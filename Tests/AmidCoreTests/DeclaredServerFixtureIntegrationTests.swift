import XCTest
import Darwin
@testable import AmidCore

/// Opt-in owned integrations for user-declared development servers: scripts/test-fixtures.sh.
/// Every server is started here with a finite lifetime; cleanup never signals. No downloads.
final class DeclaredServerFixtureIntegrationTests: XCTestCase {
    private static let nodeServer = """
    const http = require('http');
    const mode = process.argv[2] || 'plain';
    const server = http.createServer((request, response) => response.end('ok'));
    server.listen(0, '127.0.0.1', () => {
      const child = mode === 'child' ? require('child_process').spawn('/bin/sleep', ['20'], { stdio: 'ignore' }) : null;
      process.stdout.write(JSON.stringify({ port: server.address().port, child: child ? child.pid : null }) + '\\n');
    });
    if (mode === 'ignore') process.on('SIGTERM', () => {});
    else process.on('SIGTERM', () => server.close(() => process.exit(0)));
    setTimeout(() => process.exit(0), Number(process.argv[3] || 18000));
    """
    private static let restartingParent = """
    const { spawn } = require('child_process');
    let port = 0, starts = 0;
    function start() {
      starts += 1;
      const child = spawn(process.execPath, ['child.js', String(port)], { stdio: ['ignore', 'pipe', 'inherit'] });
      child.stdout.once('data', (data) => {
        port = Number(String(data).trim());
        if (starts === 1) process.stdout.write(JSON.stringify({ child: child.pid, port }) + '\\n');
      });
      child.on('exit', () => { if (starts < 2) setTimeout(start, 2000); });
    }
    start();
    setTimeout(() => process.exit(0), 20000);
    """
    private static let restartingChild = """
    const http = require('http');
    const server = http.createServer((request, response) => response.end('ok'));
    server.listen(Number(process.argv[2]), '127.0.0.1', () => process.stdout.write(String(server.address().port) + '\\n'));
    process.on('SIGTERM', () => server.close(() => process.exit(0)));
    setTimeout(() => process.exit(0), 14000);
    """
    private static let execingPython = """
    import http.server, json, os, socketserver, sys, threading
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200); self.end_headers()
        def log_message(self, *args):
            pass
    server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    threading.Timer(20, lambda: os._exit(0)).start()
    print(json.dumps({"port": server.server_address[1]}), flush=True)
    command = sys.stdin.readline().rstrip("\\n").split("\\t")
    if command[0] == "exec":
        os.execv("/bin/sleep", ["sleep", "4"])
    if command[0] == "same":
        os.execv(command[1], [command[1], "-c", "open(%r, 'w').close()\\nimport time\\ntime.sleep(4)" % command[2]])
    os._exit(0)
    """

    private struct Launched { let process: Process; let input: Pipe; let record: [String: Any] }

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["AMID_RUN_FIXTURES"] == "1" else {
            throw XCTSkip("Opt-in owned declared-server fixtures: scripts/test-fixtures.sh")
        }
    }
    private func node() throws -> String { try XCTUnwrap(ProcessInfo.processInfo.environment["AMID_FIXTURE_NODE"]) }
    private func project(marker: String, files: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-declared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{}".write(to: directory.appendingPathComponent(marker), atomically: true, encoding: .utf8)
        for (name, body) in files { try body.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    private func launch(_ executable: String, _ arguments: [String], in directory: URL) throws -> Launched {
        let process = Process(); let output = Pipe(); let input = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output; process.standardInput = input
        try process.run()
        let record = try XCTUnwrap(try JSONSerialization.jsonObject(with: output.fileHandleForReading.availableData) as? [String: Any])
        return Launched(process: process, input: input, record: record)
    }
    private func observe(_ pid: Int32, sampler: Sampler) async throws -> (ProcessSample, Snapshot) {
        _ = await sampler.sample()
        let snapshot = await sampler.sample()
        return (try XCTUnwrap(snapshot.processes.first { $0.identity.pid == pid }, "PID \(pid) was not observed"), snapshot)
    }
    /// A blocking waitUntilExit() in an async test can starve the main queue that delivers the exit.
    private func waitForExit(_ process: Process, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while process.isRunning && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(process.isRunning, "Owned fixture outlived its own lifetime", file: file, line: line)
    }
    private static func executablePath(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        return size > 0 ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
    }

    func testDeclarationIsRequiredAndOneSigtermStopsAPlainNodeServer() async throws {
        let launched = try launch(try node(), ["server.js"], in: try project(marker: "package.json", files: ["server.js": Self.nodeServer]))
        let sampler = Sampler(); let controller = ActionController(sampler: sampler)
        let (target, state) = try await observe(launched.process.processIdentifier, sampler: sampler)
        let first = await controller.preview(process: target, snapshot: state)
        XCTAssertTrue(first.canStop, first.disabledReason)
        XCTAssertTrue(first.requiresDevelopmentConfirmation)
        XCTAssertTrue(first.declaration.contains("node"), first.declaration)
        XCTAssertFalse(first.exposedToNetwork)
        let undeclared = await controller.confirm(preview: first, confirmed: true, developmentConfirmed: false)
        XCTAssertEqual(undeclared.signalsSent, 0)
        let consumed = await controller.confirm(preview: first, confirmed: true, developmentConfirmed: true)
        XCTAssertEqual(consumed.signalsSent, 0)
        let (fresh, freshState) = try await observe(launched.process.processIdentifier, sampler: sampler)
        let second = await controller.preview(process: fresh, snapshot: freshState)
        XCTAssertTrue(second.canStop, second.disabledReason)
        let stopped = await controller.confirm(preview: second, confirmed: true, developmentConfirmed: true)
        XCTAssertEqual(stopped.signalsSent, 1)
        XCTAssertEqual(stopped.validation, .unchanged)
        XCTAssertTrue(stopped.message.contains("Server exited"), stopped.message)
        await waitForExit(launched.process)
        XCTAssertEqual(launched.process.terminationStatus, 0)
        print("FIXTURE_EVIDENCE declared node stop: \(stopped.message) executable=\(target.executable)")
    }

    func testServerIgnoringSigtermIsReportedStillRunningWithoutForce() async throws {
        let launched = try launch(try node(), ["server.js", "ignore"], in: try project(marker: "package.json", files: ["server.js": Self.nodeServer]))
        let sampler = Sampler(); let controller = ActionController(sampler: sampler)
        let (target, state) = try await observe(launched.process.processIdentifier, sampler: sampler)
        let preview = await controller.preview(process: target, snapshot: state)
        XCTAssertTrue(preview.canStop, preview.disabledReason)
        let result = await controller.confirm(preview: preview, confirmed: true, developmentConfirmed: true)
        XCTAssertEqual(result.signalsSent, 1)
        XCTAssertTrue(result.message.contains("Still running"), result.message)
        XCTAssertEqual(result.remainingIdentities, [target.identity])
        await waitForExit(launched.process)
        XCTAssertEqual(launched.process.terminationStatus, 0, "The server outlived SIGTERM and exited on its own timer")
    }

    func testChildIsListedNeverSignalledAndReportedByIdentity() async throws {
        let launched = try launch(try node(), ["server.js", "child"], in: try project(marker: "package.json", files: ["server.js": Self.nodeServer]))
        let childPID = try XCTUnwrap(launched.record["child"] as? Int32)
        let sampler = Sampler(); let controller = ActionController(sampler: sampler)
        let (target, state) = try await observe(launched.process.processIdentifier, sampler: sampler)
        let child = try XCTUnwrap(state.processes.first { $0.identity.pid == childPID })
        let preview = await controller.preview(process: target, snapshot: state)
        XCTAssertTrue(preview.canStop, preview.disabledReason)
        XCTAssertEqual(preview.descendants, [child.identity])
        let result = await controller.confirm(preview: preview, confirmed: true, developmentConfirmed: true)
        XCTAssertEqual(result.signalsSent, 1)
        XCTAssertTrue(result.message.contains("Server exited"), result.message)
        XCTAssertEqual(result.remainingDescendants, [child.identity], "The reparented child keeps running and was never signalled")
        XCTAssertFalse(result.descendantsUnknown)

        await waitForExit(launched.process)
    }

    func testRestartedListenerIsReportedAsAnotherOwnerWithoutRetry() async throws {
        let directory = try project(marker: "package.json", files: ["parent.js": Self.restartingParent, "child.js": Self.restartingChild])
        let launched = try launch(try node(), ["parent.js"], in: directory)
        let childPID = try XCTUnwrap(launched.record["child"] as? Int32)
        let port = try XCTUnwrap(launched.record["port"] as? Int)
        let sampler = Sampler(); let controller = ActionController(sampler: sampler)
        let (target, state) = try await observe(childPID, sampler: sampler)
        let preview = await controller.preview(process: target, snapshot: state)
        XCTAssertTrue(preview.canStop, preview.disabledReason)
        XCTAssertEqual(preview.ancestors.last, "node")
        let result = await controller.confirm(preview: preview, confirmed: true, developmentConfirmed: true)
        XCTAssertEqual(result.signalsSent, 1)
        XCTAssertTrue(result.message.contains("Another process now owns port \(port)"), result.message)
        XCTAssertTrue(result.remainingIdentities.isEmpty)

        await waitForExit(launched.process)
    }

    func testSamePathReExecBeforeDispatchIsRefusedWithoutSignal() async throws {
        let directory = try project(marker: "pyproject.toml", files: ["server.py": Self.execingPython])
        let launched = try launch("/usr/bin/python3", ["server.py"], in: directory)
        let sampler = Sampler(); let controller = ActionController(sampler: sampler)
        let (target, state) = try await observe(launched.process.processIdentifier, sampler: sampler)
        let preview = await controller.preview(process: target, snapshot: state)
        XCTAssertTrue(preview.canStop, preview.disabledReason)
        let input = launched.input.fileHandleForWriting
        let marker = directory.appendingPathComponent("re-executed").path
        let executable = target.executable
        await controller.setBeforeDispatchForTesting {
            input.write(Data("same\t\(executable)\t\(marker)\n".utf8))
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while ContinuousClock.now < deadline, !FileManager.default.fileExists(atPath: marker) {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        let result = await controller.confirm(preview: preview, confirmed: true, developmentConfirmed: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker), "The same binary re-executed before dispatch")
        XCTAssertEqual(Self.executablePath(launched.process.processIdentifier), executable)
        XCTAssertEqual(result.signalsSent, 0, result.message)
        XCTAssertEqual(result.validation, .programChanged, result.message)
        await waitForExit(launched.process)
        XCTAssertEqual(launched.process.terminationStatus, 0)
        print("FIXTURE_EVIDENCE same-path re-exec before dispatch: \(result.message)")
    }

    func testReplacedExecutablePathBeforePreviewLeavesStopUnavailable() async throws {
        let directory = try project(marker: "package.json", files: ["server.js": Self.nodeServer])
        let copied = directory.appendingPathComponent("node")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: try node()).resolvingSymlinksInPath(), to: copied)
        let launched = try launch(copied.path, ["server.js", "plain", "6000"], in: directory)
        // Keep the running inode; replace only its pathname with different code.
        try FileManager.default.removeItem(at: copied)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: copied)
        let sampler = Sampler(); let controller = ActionController(sampler: sampler)
        let (target, state) = try await observe(launched.process.processIdentifier, sampler: sampler)
        let preview = await controller.preview(process: target, snapshot: state)
        XCTAssertFalse(preview.canStop, "Different bytes at the path must not yield a running-code identity")
        print("FIXTURE_EVIDENCE replaced executable path refused: \(preview.disabledReason) executable=\(target.executable)")
        let refused = await controller.confirm(preview: preview, confirmed: true, developmentConfirmed: true)
        XCTAssertEqual(refused.signalsSent, 0)
        await waitForExit(launched.process)
        XCTAssertEqual(launched.process.terminationStatus, 0)
    }

    func testExecBeforeDispatchIsRefusedWithoutSignal() async throws {
        let directory = try project(marker: "pyproject.toml", files: ["server.py": Self.execingPython])
        let launched = try launch("/usr/bin/python3", ["server.py"], in: directory)
        let pid = launched.process.processIdentifier
        let sampler = Sampler(); let controller = ActionController(sampler: sampler)
        let (target, state) = try await observe(pid, sampler: sampler)
        let preview = await controller.preview(process: target, snapshot: state)
        XCTAssertTrue(preview.canStop, preview.disabledReason + " executable=\(target.executable)")
        let input = launched.input.fileHandleForWriting
        await controller.setBeforeDispatchForTesting {
            input.write(Data("exec\n".utf8))
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while ContinuousClock.now < deadline, !Self.executablePath(pid).hasSuffix("/sleep") {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        let result = await controller.confirm(preview: preview, confirmed: true, developmentConfirmed: true)
        XCTAssertEqual(result.signalsSent, 0, result.message)
        XCTAssertEqual(result.validation, .programChanged, result.message)
        await waitForExit(launched.process)
        XCTAssertEqual(launched.process.terminationStatus, 0, "The re-executed program finished on its own")
        print("FIXTURE_EVIDENCE exec before dispatch: \(result.message) python=\(target.executable)")
    }
}
