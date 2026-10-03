import XCTest
import Foundation
@testable import AmidCore

/// Opt-in numeric diagnostic; snapshots are discarded rather than serialized.
final class LiveSamplerProfileTests: XCTestCase, @unchecked Sendable {
    private struct Reading: Encodable {
        var enumerated: Int
        var observed: Int
        var inaccessible: Int
        var available: Bool
        var elapsed: Double
        var collectorWall: Double
        var ownThread: OwnCurrentThreadMeasurement.Report
        var stages: SamplerProfile.Report
    }
    private struct Evidence: Encodable {
        var warmupsAvailable: Int
        var requestedCadence: Double
        var valid: Bool
        var invalidReasons: [String]
        var readings: [Reading]
        var process: PerformanceMeasurement.Report
        var notes: [String]
    }
    func testOptInLiveSamplerSixtySeconds() async throws {
        guard ProcessInfo.processInfo.environment["AMID_LIVE_SAMPLER_PROFILE"] == "1" else {
            throw XCTSkip("Opt-in numeric real sampler profile; no metadata output.")
        }
        guard let output = ProcessInfo.processInfo.environment["AMID_LIVE_SAMPLER_PROFILE_OUTPUT"], output.hasPrefix("/private/tmp/amid-") else {
            XCTFail("Provide a new owned /private/tmp/amid- output path"); return
        }
        guard !FileManager.default.fileExists(atPath: output) else { XCTFail("Refusing to replace existing evidence"); return }
        let sampler = Sampler()
        var warmups = 0
        for index in 0..<2 {
            let snapshot = await sampler.sample(cadence: 5)
            if snapshot.availability == .available && !snapshot.processes.isEmpty { warmups += 1 }
            if index == 0 { try await Task.sleep(for: .seconds(5)) }
        }
        let clock = ContinuousClock(), origin = ContinuousClock.now
        let process = PerformanceMeasurement()
        var readings: [Reading] = [], invalid: [String] = []
        if warmups != 2 { invalid.append("Not all warmups available") }
        var previous: Double?
        for index in 0..<12 {
            let components = origin.duration(to: clock.now).components
            let elapsed = Double(components.seconds) + Double(components.attoseconds) / 1e18
            if let previous, elapsed - previous > 7.5 { invalid.append("Excessive sample gap") }
            previous = elapsed
            let result = await sampler.profiledSample(cadence: 5)
            let snapshot = result.snapshot
            let available = snapshot.availability == .available
            if !available || snapshot.processes.isEmpty { invalid.append("Collection unavailable or empty") }
            readings.append(.init(enumerated: snapshot.enumeratedCount, observed: snapshot.processes.count,
                inaccessible: snapshot.inaccessibleCount, available: available, elapsed: elapsed,
                collectorWall: snapshot.duration, ownThread: result.measurement, stages: result.breakdown))
            // Anchored deadlines preserve requested cadence; no reduced coverage or result cache.
            try await clock.sleep(until: origin.advanced(by: .seconds(5 * (index + 1))))
        }
        let evidence = Evidence(warmupsAvailable: warmups, requestedCadence: 5, valid: invalid.isEmpty,
            invalidReasons: invalid, readings: readings,
            process: process.report(notes: ["Own test-process interval, includes timer and numeric report overhead."]),
            notes: ["Two available warmups five seconds apart, then twelve anchored five-second samples over about sixty seconds. No thirty-second GUI warmup.",
                    "Only aggregate counts and numeric own-process/current-thread timing are persisted. Snapshots and monitored metadata are not serialized.",
                    "Coarse current-thread CPU excludes other threads; fine stages are wall-only and nested inside processLoop. Do not add fine wall to coarse CPU.",
                    "Partial OS visibility is reported by enumerated/observed/inaccessible counts; available does not imply every process was readable. Sandbox-limited runs must not be treated as full-host coverage.",
                    "Single short collector diagnostic, not GUI, sustained budget, matched baseline or reference hardware evidence. No overhead subtraction."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: URL(fileURLWithPath: output), options: .atomic)
        XCTAssertTrue(invalid.isEmpty, invalid.joined(separator: "; "))
    }
}
