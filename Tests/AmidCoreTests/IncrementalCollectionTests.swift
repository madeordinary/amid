import XCTest
import Foundation
@testable import AmidCore

/// Owned short-lived Python children only; no signals are sent and each child exits on its own.
final class IncrementalCollectionTests: XCTestCase {
    private static let child = """
    import json, os, socket, sys, threading, time
    threading.Timer(30, lambda: os._exit(0)).start()
    server = None
    def report(**values):
        values["port"] = server.getsockname()[1] if server else 0
        print(json.dumps(values), flush=True)
    report(ready=1)
    if len(sys.argv) > 1 and sys.argv[1] == "late-listen":
        time.sleep(1.0)
        server = socket.socket(); server.bind(("127.0.0.1", 0)); server.listen()
        report(listening=1)
    for line in sys.stdin:
        command = line.split()
        if not command:
            continue
        if command[0] == "chdir":
            os.chdir(command[1])
        elif command[0] == "listen":
            server = socket.socket(); server.bind(("127.0.0.1", 0)); server.listen()
        elif command[0] == "exec":
            os.execv("/bin/sleep", ["sleep", "3"])
        report(done=command[0])
    os._exit(0)
    """

    private final class Child {
        let process = Process(); let input = Pipe(); let output = Pipe(); private var buffer = Data()
        func line() throws -> [String: Any] {
            while true {
                if let end = buffer.firstIndex(of: 10) {
                    let line = buffer[..<end]; buffer.removeSubrange(...end)
                    return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
                }
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { throw CocoaError(.fileReadUnknown) }
                buffer.append(chunk)
            }
        }
        func send(_ command: String) { input.fileHandleForWriting.write(Data((command + "\n").utf8)) }
    }

    private func directory(marker: Bool) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("amid-incremental-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if marker { try "{}".write(to: url.appendingPathComponent("package.json"), atomically: true, encoding: .utf8) }
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.resolvingSymlinksInPath()
    }
    private func launch(in directory: URL, arguments: [String] = []) throws -> Child {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { throw XCTSkip("Python is unavailable") }
        let child = Child()
        child.process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.process.arguments = ["-c", Self.child] + arguments
        child.process.currentDirectoryURL = directory
        child.process.standardInput = child.input; child.process.standardOutput = child.output
        try child.process.run()
        XCTAssertEqual(try child.line()["ready"] as? Int, 1)
        return child
    }
    private func observed(_ child: Child, by sampler: Sampler) async throws -> ProcessSample {
        let snapshot = await sampler.sample(cadence: 5)
        return try XCTUnwrap(snapshot.processes.first { $0.identity.pid == child.process.processIdentifier })
    }
    private func canonical(_ path: String?) -> String? { path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } }

    func testCachedMetadataStaysWithinItsWindowWhileFullReadsSeeChangesImmediately() async throws {
        let start = try directory(marker: false), moved = try directory(marker: true)
        let child = try launch(in: start)
        let incremental = Sampler(mode: .incremental(metadataRefresh: 3600, youngProcessAge: 0, markerRefresh: 3600)), full = Sampler()
        let first = try await observed(child, by: incremental)
        XCTAssertEqual(canonical(first.workingDirectory), start.path)
        child.send("chdir \(moved.path)"); _ = try child.line()
        child.send("listen"); let port = try XCTUnwrap(try child.line()["port"] as? Int)
        let cached = try await observed(child, by: incremental)
        XCTAssertEqual(canonical(cached.workingDirectory), start.path, "Inside its refresh window the cached directory is kept")
        XCTAssertTrue(cached.endpoints.isEmpty)
        let fresh = try await observed(child, by: full)
        XCTAssertEqual(canonical(fresh.workingDirectory), moved.path)
        XCTAssertEqual(canonical(fresh.projectPath), moved.path)
        XCTAssertTrue(fresh.endpoints.contains { Int($0.port) == port })
        // A changed process name signals exec and forces an immediate full read.
        child.send("exec")
        var switched: ProcessSample?
        for _ in 0..<20 {
            switched = try await observed(child, by: incremental)
            if switched?.executable == "/bin/sleep" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(switched?.executable, "/bin/sleep")
    }

    func testMetadataRefreshesAfterItsWindow() async throws {
        let start = try directory(marker: false), moved = try directory(marker: true)
        let child = try launch(in: start)
        let incremental = Sampler(mode: .incremental(metadataRefresh: 1, youngProcessAge: 0, markerRefresh: 1))
        _ = try await observed(child, by: incremental)
        child.send("chdir \(moved.path)"); _ = try child.line()
        child.send("listen"); let port = try XCTUnwrap(try child.line()["port"] as? Int)
        var latest: ProcessSample?
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < deadline {
            latest = try await observed(child, by: incremental)
            if canonical(latest?.workingDirectory) == moved.path, latest?.endpoints.contains(where: { Int($0.port) == port }) == true { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertEqual(canonical(latest?.workingDirectory), moved.path)
        XCTAssertEqual(canonical(latest?.projectPath), moved.path)
        XCTAssertTrue(latest?.endpoints.contains { Int($0.port) == port } == true)
        child.send("quit")
    }

    func testYoungProcessListenerAppearsOnTheNextSampleWithDefaultPolicy() async throws {
        let child = try launch(in: try directory(marker: true), arguments: ["late-listen"])
        let incremental = Sampler(mode: .incremental())
        let before = try await observed(child, by: incremental)
        XCTAssertTrue(before.endpoints.isEmpty)
        let port = try XCTUnwrap(try child.line()["port"] as? Int)
        let after = try await observed(child, by: incremental)
        XCTAssertTrue(after.endpoints.contains { Int($0.port) == port }, "A process younger than a minute is read fully every sample")
        child.send("quit")
    }

    func testRefreshStaggerStaysBelowOneInterval() {
        for pid: Int32 in [1, 996, 997, 1993, 65535, Int32.max] {
            let offset = Sampler.refreshStagger(pid: pid, interval: 30)
            XCTAssertGreaterThanOrEqual(offset, 0)
            XCTAssertLessThan(offset, 30)
        }
    }
}
