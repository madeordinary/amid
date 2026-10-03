import XCTest
import Darwin
@testable import AmidCore

final class CollectionTests: XCTestCase {
    func testConstructionDoesNotStartMetadataCollection() async {
        let sampler = Sampler()
        let before = await sampler.initializedCollectionResources
        XCTAssertFalse(before)
        await sampler.resetBaselines()
        let afterReset = await sampler.initializedCollectionResources
        XCTAssertFalse(afterReset)
        _ = await sampler.sample()
        let afterSample = await sampler.initializedCollectionResources
        XCTAssertTrue(afterSample)
    }
    func testIdentitySeparatesPIDReuseAndBoot() {
        let a = ProcessIdentity(bootID: "a", pid: 22, uid: 501, startSeconds: 10, startMicroseconds: 1)
        let b = ProcessIdentity(bootID: "a", pid: 22, uid: 501, startSeconds: 10, startMicroseconds: 2)
        let c = ProcessIdentity(bootID: "b", pid: 22, uid: 501, startSeconds: 10, startMicroseconds: 1)
        XCTAssertNotEqual(a, b); XCTAssertNotEqual(a, c)
    }
    func testProjectMarkerNearestRootAndBoundary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("amid-collection-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("workspace/nested/src")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("sensitive marker contents must not be read".utf8).write(to: root.appendingPathComponent("package.json"))
        XCTAssertEqual(ProjectAttribution.root(for: nested.path), root.path)
        XCTAssertEqual(ProjectAttribution.root(for: nested.path, boundaries: [root.appendingPathComponent("workspace").path]), root.appendingPathComponent("workspace").path)
        try Data().write(to: root.appendingPathComponent("workspace/nested/Package.swift"))
        XCTAssertEqual(ProjectAttribution.root(for: nested.path), root.appendingPathComponent("workspace/nested").path)
        XCTAssertEqual(ProjectAttribution.root(for: nested.path, boundaries: [root.path]), root.path)
        XCTAssertNil(ProjectAttribution.root(for: "relative/path"))
    }
    func testSharedAncestorMarkerCacheKeepsTraversalBoundAndFreshPublicLookups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("amid-marker-cache-\(UUID().uuidString)")
        var deep = root
        for _ in 0..<13 { deep.appendPathComponent("nested") }
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("Package.swift")
        try Data().write(to: marker)
        var cache: [String: Bool] = [:]
        XCTAssertEqual(ProjectAttribution.root(for: root.path, boundaries: [], markerCache: &cache), root.path)
        XCTAssertNil(ProjectAttribution.root(for: deep.path, boundaries: [], markerCache: &cache))
        try FileManager.default.removeItem(at: marker)
        XCTAssertNil(ProjectAttribution.root(for: root.path))
    }
    func testGroupingDoesNotMergeUnavailableExecutables() {
        let a = ProcessIdentity(bootID: "a", pid: 1, uid: 501, startSeconds: 1, startMicroseconds: 0)
        let b = ProcessIdentity(bootID: "a", pid: 2, uid: 501, startSeconds: 1, startMicroseconds: 0)
        XCTAssertNotEqual(Sampler.application(executable: "", identity: a, name: "same").0, Sampler.application(executable: "", identity: b, name: "same").0)
        XCTAssertEqual(Sampler.application(executable: "/Applications/A.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", identity: a, name: "Helper").1, "A")
        XCTAssertNil(Sampler.runtime("/bin/not-python"))
    }
    func testRealCurrentProcessAndReset() async throws {
        let sampler = Sampler()
        let first = await sampler.sample()
        let own = try XCTUnwrap(first.processes.first { $0.identity.pid == getpid() })
        XCTAssertEqual(own.identity.uid, getuid())
        XCTAssertGreaterThan(own.identity.startSeconds, 0)
        XCTAssertNil(own.cpuPercent)
        XCTAssertNotNil(own.memoryBytes)
        XCTAssertFalse(own.executable.isEmpty)
        try await Task.sleep(for: .milliseconds(30))
        let second = await sampler.sample()
        XCTAssertNotNil(second.processes.first { $0.identity == own.identity }?.cpuPercent)
        await sampler.resetBaselines()
        let reset = await sampler.sample()
        XCTAssertNil(reset.processes.first { $0.identity == own.identity }?.cpuPercent)
        XCTAssertGreaterThan(try XCTUnwrap(reset.processes.first { $0.identity == own.identity }?.observedSince), own.observedSince)
        XCTAssertNil(reset.system.cpuPercent)
        XCTAssertTrue(reset.system.interfaces.allSatisfy { $0.receivedBytesPerSecond == nil && $0.sentBytesPerSecond == nil })
    }
    func testCPUUnitsMatchOwnProcessReferenceWorkload() async throws {
        func cpuSeconds() -> Double {
            var usage = rusage()
            XCTAssertEqual(getrusage(RUSAGE_SELF, &usage), 0)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
                Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let sampler = Sampler()
        let first = await sampler.sample()
        let before = cpuSeconds()
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        var value: UInt64 = 1
        // Consume at least one second of our own CPU, not a guessed wall-clock duration.
        while cpuSeconds() - before < 1.1 && ProcessInfo.processInfo.systemUptime < deadline {
            for _ in 0..<100_000 { value = (value &* 1_664_525) &+ 1_013_904_223 }
        }
        XCTAssertNotEqual(value, 0)
        let second = await sampler.sample()
        let referenceCPU = cpuSeconds() - before
        XCTAssertGreaterThan(referenceCPU, 1)
        let own = try XCTUnwrap(second.processes.first { $0.identity.pid == getpid() })
        let actual = try XCTUnwrap(own.cpuPercent)
        let elapsed = second.timestamp.timeIntervalSince(first.timestamp)
        let expected = referenceCPU / elapsed * 100
        // Sampling before/after the reference calls contributes a small boundary difference.
        // The former ticks-as-nanoseconds bug produces about 2.4%, and fails this tolerance.
        XCTAssertEqual(actual, expected, accuracy: max(5, expected * 0.15))
        print("CPU_UNIT_EVIDENCE referenceSeconds=\(referenceCPU) elapsedSeconds=\(elapsed) measuredPercent=\(actual) expectedPercent=\(expected)")
    }
    func testOwnListenerMetadataWithoutConnection() async throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0 else { throw XCTSkip("Sandbox denied owned loopback fixture bind (errno \(errno))") }
        XCTAssertEqual(listen(fd, 1), 0)
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        XCTAssertEqual(withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) } }, 0)
        let snapshot = await Sampler().sample()
        let own = try XCTUnwrap(snapshot.processes.first { $0.identity.pid == getpid() })
        XCTAssertEqual(own.portAvailability, .available)
        XCTAssertTrue(own.endpoints.contains { $0.port == UInt16(bigEndian: address.sin_port) && $0.address == "127.0.0.1" })
    }
}
