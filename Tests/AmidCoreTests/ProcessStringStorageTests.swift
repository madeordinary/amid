import XCTest
@testable import AmidCore

final class ProcessStringStorageTests: XCTestCase, @unchecked Sendable {
    private func process() -> ProcessSample {
        ProcessSample(identity: .init(bootID: "fixture", pid: 100, uid: 501, startSeconds: 1, startMicroseconds: 0),
            executable: "/fixture/long-current-executable", name: "Long current fixture name", runtime: "Fixture runtime",
            cpuPercent: 1, memoryBytes: 100, memoryMethod: .footprint,
            workingDirectory: "/fixture/current-working-directory", projectPath: "/fixture/current-project",
            applicationID: "fixture.current.application", applicationName: "Current fixture application", groupingReason: "Current derived reason",
            endpoints: [.init(address: "fd00:0000:0000:0000:0000:0000:0000:0001", port: 4000, family: "IPv6", scope: "Interface")],
            portAvailability: .available, observedSince: Date(timeIntervalSince1970: 1))
    }
    private func encoded(_ samples: [ProcessSample]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(samples)
    }
    func testFreshChangesAndUnknownValuesRemainByteForByteCurrent() throws {
        var storage = ProcessStringStorage()
        var first = [process()]; storage.reuseStorage(in: &first)
        var changed = process()
        changed.executable = "/fixture/different-executable"; changed.name = "Different name"
        changed.runtime = nil; changed.workingDirectory = nil; changed.projectPath = nil
        changed.applicationID = "different-app"; changed.applicationName = "Different app"; changed.groupingReason = "Different evidence"
        changed.endpoints = [.init(address: "fd00::2", port: 5000, family: "IPv6", scope: "All interfaces")]
        changed.cpuPercent = nil; changed.memoryBytes = nil; changed.memoryMethod = .unavailable; changed.portAvailability = .denied
        var fresh = [changed]; let expected = try encoded(fresh)
        storage.reuseStorage(in: &fresh)
        XCTAssertEqual(try encoded(fresh), expected)
        var restored = [process()]; let restoredExpected = try encoded(restored)
        storage.reuseStorage(in: &restored)
        XCTAssertEqual(try encoded(restored), restoredExpected)
    }
    func testCanonicalUnicodeEqualityDoesNotReplaceFreshUTF8() throws {
        var storage = ProcessStringStorage()
        var first = process(); first.executable = "/fixture/caf\u{00e9}"; first.workingDirectory = "/fixture/caf\u{00e9}"
        var previous = [first]; storage.reuseStorage(in: &previous)
        var changed = first; changed.executable = "/fixture/cafe\u{0301}"; changed.workingDirectory = "/fixture/cafe\u{0301}"
        XCTAssertEqual(first.executable, changed.executable) // Swift canonical equality; bytes differ.
        var fresh = [changed]; let expected = try encoded(fresh)
        storage.reuseStorage(in: &fresh)
        XCTAssertEqual(try encoded(fresh), expected)
        XCTAssertEqual(Array(fresh[0].executable.utf8), Array(changed.executable.utf8))
    }
    func testFullIdentityDepartureEmptyAndResetBoundReferences() throws {
        var storage = ProcessStringStorage()
        var a = process(), b = process(), c = process()
        b.identity.uid += 1; c.identity.startMicroseconds += 1
        var samples = [a, b, c]; storage.reuseStorage(in: &samples)
        XCTAssertEqual(storage.retainedIdentityCount, 3)
        a.endpoints = []
        var onlyCurrent = [a]; let expected = try encoded(onlyCurrent)
        storage.reuseStorage(in: &onlyCurrent)
        XCTAssertEqual(storage.retainedIdentityCount, 1)
        XCTAssertEqual(try encoded(onlyCurrent), expected)
        var empty: [ProcessSample] = []; storage.reuseStorage(in: &empty)
        XCTAssertEqual(storage.retainedIdentityCount, 0)
        storage.reuseStorage(in: &samples); storage.reset()
        XCTAssertEqual(storage.retainedIdentityCount, 0)
    }
    func testSamplerConstructionAndResetRetainNoStringMetadata() async throws {
        let sampler = Sampler()
        let initial = await sampler.retainedStringIdentityCount
        XCTAssertEqual(initial, 0)
        let sample = await sampler.sample()
        guard sample.availability == .available, !sample.processes.isEmpty else {
            throw XCTSkip("Native collection unavailable or empty; cannot prove nonempty string-reference reset.")
        }
        let populated = await sampler.retainedStringIdentityCount
        XCTAssertGreaterThan(populated, 0)
        XCTAssertEqual(populated, Set(sample.processes.map(\.identity)).count)
        await sampler.resetBaselines()
        let reset = await sampler.retainedStringIdentityCount
        XCTAssertEqual(reset, 0)
    }
}
