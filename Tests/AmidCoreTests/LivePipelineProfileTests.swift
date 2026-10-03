import XCTest
@testable import AmidCore

/// Opt-in diagnostic only: no process metadata is written to the report.
final class LivePipelineProfileTests: XCTestCase, @unchecked Sendable {
    struct Phase: Encodable {
        var calls = 0
        var wallSeconds = 0.0
        var cpuSeconds: Double? = 0
        mutating func add(_ report: PerformanceMeasurement.Report) {
            calls += 1; wallSeconds += report.elapsedSeconds
            cpuSeconds = cpuSeconds.flatMap { total in report.cpuSeconds.map { total + $0 } }
        }
    }
    struct Evidence: Encodable {
        var valid: Bool
        var invalidReasons: [String]
        var invocation: String
        var buildConfiguration: String
        var warmupSamples: Int
        var samples: Int
        var minimumEnumerated: Int
        var maximumEnumerated: Int
        var minimumObserved: Int
        var maximumObserved: Int
        var minimumInaccessible: Int
        var maximumInaccessible: Int
        var maximumGapSeconds: Double
        var groupedViewsAtCompletion: Int
        var process: PerformanceMeasurement.Report
        var phases: [String: Phase]
        var notes: [String]
    }
    func testOptInRealPipelineSixtySeconds() async throws {
        guard ProcessInfo.processInfo.environment["AMID_LIVE_PIPELINE_PROFILE"] == "1" else {
            throw XCTSkip("Opt-in own-process pipeline profiling; set AMID_LIVE_PIPELINE_PROFILE=1.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-live-pipeline-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        await store.updateSettings(.init(retention: .week))
        let sampler = Sampler(), alerts = AlertEngine()
        var invalid: [String] = []
        var warmups = 0
        for index in 0..<2 {
            let sample = await sampler.sample(cadence: 5)
            if sample.availability == .available { warmups += 1 }
            else { invalid.append("Warmup collection unavailable") }
            if index == 0 { try await Task.sleep(for: .seconds(5)) }
        }
        let overall = PerformanceMeasurement()
        let start = ContinuousClock.now
        func elapsed() -> Double {
            let d = start.duration(to: .now).components
            return Double(d.seconds) + Double(d.attoseconds) / 1e18
        }
        var phases: [String: Phase] = [:]
        func record(_ name: String, _ measurement: PerformanceMeasurement) {
            phases[name, default: Phase()].add(measurement.report(notes: []))
        }
        var samples = 0, groupedViews = 0
        var minEnumerated = Int.max, maxEnumerated = 0, minObserved = Int.max, maxObserved = 0
        var minInaccessible = Int.max, maxInaccessible = 0
        var previous = 0.0, maximumGap = 0.0
        while elapsed() < 60 {
            var phase = PerformanceMeasurement()
            let snapshot = await sampler.sample(cadence: 5)
            record("sampler", phase)
            let gap = elapsed() - previous
            maximumGap = max(maximumGap, gap); previous = elapsed()
            if gap > 15 { invalid.append("Collection gap exceeded fifteen seconds") }
            if snapshot.availability != .available { invalid.append("Collection unavailable") }
            minEnumerated = min(minEnumerated, snapshot.enumeratedCount); maxEnumerated = max(maxEnumerated, snapshot.enumeratedCount)
            minObserved = min(minObserved, snapshot.processes.count); maxObserved = max(maxObserved, snapshot.processes.count)
            minInaccessible = min(minInaccessible, snapshot.inaccessibleCount); maxInaccessible = max(maxInaccessible, snapshot.inaccessibleCount)
            phase = PerformanceMeasurement()
            let applications = ResourceGroup.applications(snapshot)
            let projects = ResourceGroup.projects(snapshot)
            groupedViews = applications.count + projects.count
            record("grouping", phase)
            phase = PerformanceMeasurement()
            await store.ingest(snapshot)
            record("historyIngest", phase)
            phase = PerformanceMeasurement()
            let events = await alerts.evaluate(snapshot)
            record("alertEvaluate", phase)
            phase = PerformanceMeasurement()
            await store.recordAlerts(events)
            record("recordAlerts", phase)
            phase = PerformanceMeasurement()
            let state = await store.state()
            if state.error != nil { invalid.append("Encrypted history unavailable") }
            record("historyState", phase)
            samples += 1
            try await Task.sleep(for: .seconds(5))
        }
        maximumGap = max(maximumGap, elapsed() - previous)
        if maximumGap > 15 { invalid.append("Collection gap exceeded fifteen seconds") }
        let process = overall.report(notes: ["Whole XCTest process, not the shipped GUI. Temporary encrypted week history."])
        if process.cpuSeconds == nil { invalid.append("Own-process CPU unavailable") }
        if minObserved == 0 || samples < 2 { invalid.append("Insufficient collection coverage") }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let invocation = "AMID_LIVE_PIPELINE_PROFILE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xctest -XCTest AmidCoreTests.LivePipelineProfileTests/testOptInRealPipelineSixtySeconds " + Bundle(for: Self.self).bundleURL.path
        let evidence = Evidence(valid: invalid.isEmpty, invalidReasons: Array(Set(invalid)).sorted(),
            invocation: invocation,
            buildConfiguration: configuration, warmupSamples: warmups, samples: samples,
            minimumEnumerated: minEnumerated, maximumEnumerated: maxEnumerated,
            minimumObserved: minObserved, maximumObserved: maxObserved,
            minimumInaccessible: minInaccessible, maximumInaccessible: maxInaccessible,
            maximumGapSeconds: maximumGap, groupedViewsAtCompletion: groupedViews,
            process: process, phases: phases, notes: [
                "Two collector warmup samples five seconds apart; no thirty-second GUI warmup. Twelve expected samples over approximately sixty seconds, sleeping five seconds after each pipeline.",
                "Phase CPU is whole-process getrusage delta over each async span; unrelated XCTest work can contribute. Phase spans do not overlap. Phase timing/report overhead and sleep are outside named spans.",
                "Default sorted application/project grouping mimics hidden AppModel refresh. Prior whole HistoryState is not retained. This approximates the core pipeline; no SwiftUI rendering, menu updates, notifications, or allocations measurement.",
                "Coverage counts report permission-limited process enumeration; inaccessible processes are not inferred. No identities, executable paths, project paths, listener metadata, arguments, environment, source contents or payloads are written to this evidence.",
                "A short phase profile is not a sustained observer-budget, matched baseline, reference-M1 or full-GUI pass. Runner exit must be checked and recorded separately."
            ])
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("docs/evidence/live-pipeline-profile.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: output, options: .atomic)
        XCTAssertTrue(evidence.valid, evidence.invalidReasons.joined(separator: "; "))
    }
}
