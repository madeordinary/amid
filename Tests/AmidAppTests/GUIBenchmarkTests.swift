import XCTest
@testable import AmidApp

final class GUIBenchmarkTests: XCTestCase {
    private func warmedRun(seconds: Double = 30) -> GUIBenchmarkEvidence {
        var run = GUIBenchmarkEvidence(requestedSeconds: seconds)
        for _ in 0..<2 { run.observe(available: true, elapsed: 0, cadence: 5, processCount: 10) }
        run.begin(active: true)
        return run
    }
    func testSilentLaunchAndSuspendedWarmupCannotPass() {
        var run = GUIBenchmarkEvidence(requestedSeconds: 30)
        run.begin(active: true)
        XCTAssertEqual(run.phase, .invalid)
        var suspended = warmedRun()
        suspended.invalidate("screen lock")
        suspended.observe(available: true, elapsed: 5, cadence: 5, processCount: 10)
        suspended.finish(elapsed: 30, active: true)
        XCTAssertEqual(suspended.phase, .invalid)
        XCTAssertEqual(suspended.acceptedSamples, 0)
    }
    func testContinuousSamplingAndTailGap() {
        var run = warmedRun()
        for time in stride(from: 5.0, through: 30, by: 5) {
            run.observe(available: true, elapsed: time, cadence: 5, processCount: 10)
        }
        run.finish(elapsed: 30, active: true)
        XCTAssertEqual(run.phase, .completed)
        XCTAssertEqual(run.acceptedSamples, 6)
        XCTAssertEqual(run.maximumGapSeconds, 5)
        var gap = warmedRun()
        gap.observe(available: true, elapsed: 5, cadence: 5, processCount: 10)
        gap.observe(available: true, elapsed: 10, cadence: 5, processCount: 10)
        gap.finish(elapsed: 30, active: true)
        XCTAssertEqual(gap.phase, .invalid)
    }
    func testUnavailableSampleAndLongSuspensionStayInvalid() {
        var run = warmedRun()
        run.observe(available: false, elapsed: 5, cadence: 5, processCount: 0)
        XCTAssertEqual(run.unavailableSamples, 1)
        run.finish(elapsed: 30, active: true)
        XCTAssertEqual(run.phase, .invalid)
        var gap = warmedRun()
        gap.observe(available: true, elapsed: 90, cadence: 5, processCount: 10)
        gap.finish(elapsed: 90, active: true)
        XCTAssertEqual(gap.phase, .invalid)
    }
    func testTailGapUsesLatestCadenceAfterPolicyChanges() {
        var run = warmedRun(seconds: 50)
        run.observe(available: true, elapsed: 5, cadence: 10, processCount: 10)
        run.observe(available: true, elapsed: 15, cadence: 5, processCount: 10)
        run.observe(available: true, elapsed: 30, cadence: 5, processCount: 10)
        run.finish(elapsed: 50, active: true)
        XCTAssertEqual(run.phase, .invalid)
    }
    @MainActor
    func testCompletedArtifactIsFrozenAcrossQuitAndRepeatedFinish() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-benchmark-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("result.json")
        let run = GUIBenchmarkSession(seconds: 0, output: output, retention: "week")
        for _ in 0..<2 { run.observe(available: true, cadence: 5, processCount: 10) }
        run.begin(active: true)
        for _ in 0..<2 { run.observe(available: true, cadence: 5, processCount: 10) }
        run.finish(active: true)
        XCTAssertEqual(run.evidence.phase, .completed)
        let original = try Data(contentsOf: output)
        let status = try Data(contentsOf: output.appendingPathExtension("status.json"))
        run.invalidate("quit"); run.finish(active: false)
        run.invalidate("cancelled"); run.finish(active: false)
        XCTAssertEqual(try Data(contentsOf: output), original)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathExtension("status.json")), status)
        XCTAssertEqual(run.evidence.phase, .completed)
    }
}
