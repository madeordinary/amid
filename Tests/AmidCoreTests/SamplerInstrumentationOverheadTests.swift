import XCTest
import Foundation
@testable import AmidCore

// Actor-isolated synchronous wrappers: no await within either measured span.
private extension Sampler {
    func overheadReading(profiled: Bool) -> (Snapshot, OwnCurrentThreadMeasurement.Report) {
        let measurement = OwnCurrentThreadMeasurement()
        let snapshot: Snapshot
        if profiled { snapshot = profiledSample(cadence: 5).snapshot }
        else { snapshot = sample(cadence: 5) }
        return (snapshot, measurement.report())
    }
    func emptyWrapperCalibration() -> [OwnCurrentThreadMeasurement.Report] {
        (0..<64).map { _ in
            let measurement = OwnCurrentThreadMeasurement()
            return measurement.report()
        }
    }
}

final class SamplerInstrumentationOverheadTests: XCTestCase, @unchecked Sendable {
    private struct Reading: Encodable {
        var path: String
        var elapsed: Double
        var enumerated: Int
        var observed: Int
        var inaccessible: Int
        var available: Bool
        var collectorWall: Double
        var outerOwnThread: OwnCurrentThreadMeasurement.Report
    }
    private struct Evidence: Encodable {
        var warmupsAvailable: Int
        var requestedCadence: Double
        var valid: Bool
        var invalidReasons: [String]
        var calibration: [OwnCurrentThreadMeasurement.Report]
        var readings: [Reading]
        var process: PerformanceMeasurement.Report
        var notes: [String]
    }
    func testOptInSamplerInstrumentationABBA() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AMID_SAMPLER_OVERHEAD"] == "1" else {
            throw XCTSkip("Opt-in numeric sampler instrumentation diagnostic")
        }
        guard let output = environment["AMID_SAMPLER_OVERHEAD_OUTPUT"],
              output.hasPrefix("/private/tmp/amid-"), output.hasSuffix(".json"),
              !output.dropFirst("/private/tmp/".count).contains("/"),
              !output.split(separator: "/").contains(".."),
              !FileManager.default.fileExists(atPath: output) else {
            XCTFail("Require a fresh owned /private/tmp/amid-*.json output"); return
        }
        let process = PerformanceMeasurement()
        let sampler = Sampler()
        var warmups = 0, invalid: [String] = []
        for index in 0..<2 {
            let snapshot = await sampler.sample(cadence: 5)
            if snapshot.availability == .available && !snapshot.processes.isEmpty { warmups += 1 }
            if index == 0 { try await Task.sleep(for: .seconds(5)) }
        }
        if warmups != 2 { invalid.append("Two available nonempty warmups required") }
        let calibration = await sampler.emptyWrapperCalibration()
        func known(_ report: OwnCurrentThreadMeasurement.Report) -> Bool {
            guard let cpu = report.cpuSeconds else { return false }
            return cpu.isFinite && cpu >= 0 && report.wallSeconds.isFinite && report.wallSeconds > 0
        }
        if !calibration.allSatisfy(known) { invalid.append("Calibration own-thread counters unavailable") }
        let clock = ContinuousClock(), origin = ContinuousClock.now
        let order = Array(repeating: [false, true, true, false], count: 3).flatMap { $0 }
        var readings: [Reading] = [], previous: Double?
        for (index, profiled) in order.enumerated() {
            let duration = origin.duration(to: clock.now).components
            let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            if let previous, elapsed <= previous || elapsed - previous > 7.5 {
                invalid.append("Invalid or excessive anchored sample gap")
            }
            previous = elapsed
            let (snapshot, report) = await sampler.overheadReading(profiled: profiled)
            let available = snapshot.availability == .available
            if !available || snapshot.processes.isEmpty { invalid.append("Collection unavailable or empty") }
            if !known(report) { invalid.append("Sample own-thread counters unavailable") }
            readings.append(.init(path: profiled ? "profiled" : "normal", elapsed: elapsed,
                enumerated: snapshot.enumeratedCount, observed: snapshot.processes.count,
                inaccessible: snapshot.inaccessibleCount, available: available,
                collectorWall: snapshot.duration, outerOwnThread: report))
            try await clock.sleep(until: origin.advanced(by: .seconds(5 * (index + 1))))
        }
        let processReport = process.report(notes: ["Whole test-process interval includes warmups, calibration and anchored sampling; measured before JSON encoding."])
        if processReport.cpuSeconds == nil || !processReport.elapsedSeconds.isFinite || processReport.elapsedSeconds <= 0 {
            invalid.append("Whole-process measurement unavailable")
        }
        let evidence = Evidence(warmupsAvailable: warmups, requestedCadence: 5, valid: invalid.isEmpty,
            invalidReasons: invalid, calibration: calibration, readings: readings, process: processReport,
            notes: ["A=normal, B=profiled; ABBA repeated three times, six samples per path, one retained Sampler and fresh OS reads.",
                    "Outer synchronous actor wrapper starts before profiledSample initialization and uniformly measures both paths. No await inside measured span.",
                    "Two available warmups five seconds apart, then twelve anchored five-second samples over about sixty seconds. Whole-test interval also includes warmups/calibration.",
                    "Calibration reports 64 empty wrappers; no overhead subtraction or budget acceptance.",
                    "Only counts, availability and numeric own-thread/process measurements are serialized; no monitored identities, paths, strings, arguments, environment or payloads.",
                    "Counts describe changing coverage. This short mixed-order diagnostic cannot establish paired causal savings, sustained GUI budget, reference hardware or all-host visibility."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
        XCTAssertEqual(readings.filter { $0.path == "normal" }.count, 6)
        XCTAssertEqual(readings.filter { $0.path == "profiled" }.count, 6)
        XCTAssertTrue(invalid.isEmpty, invalid.joined(separator: "; "))
    }
}
