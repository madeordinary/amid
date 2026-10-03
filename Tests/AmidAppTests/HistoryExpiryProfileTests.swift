import XCTest
import AmidCore
@testable import AmidApp

final class HistoryExpiryProfileTests: XCTestCase {
    struct Result: Encodable {
        var retention: String
        var visibleHistory: Bool
        var duplicatePresentationSync: Bool
        var iterations: Int
        var process: PerformanceMeasurement.Report
        var expiryWallSeconds: Double
        var ingestWallSeconds: Double
        var finalSyncWallSeconds: Double
        var finalRawSamples: Int
    }
    @MainActor
    func testOptInFilledRingExpiryCost() async throws {
        guard ProcessInfo.processInfo.environment["AMID_EXPIRY_PROFILE"] == "1" else {
            throw XCTSkip("Opt-in synthetic filled-ring expiry profile; set AMID_EXPIRY_PROFILE=1.")
        }
        let processes = (0..<650).map { i in
            ProcessSample(identity: .init(bootID: "synthetic", pid: Int32(i + 100), uid: 501, startSeconds: 1, startMicroseconds: 0), executable: "/fixture", name: "Fixture", cpuPercent: 0.1, memoryBytes: 1_048_576, memoryMethod: .footprint, applicationID: "fixture.\(i % 65)", applicationName: "Fixture", groupingReason: "Synthetic owned fixture")
        }
        let base = Date()
        func snapshot(_ time: Date) -> Snapshot {
            Snapshot(timestamp: time, processes: processes, cadence: 5, expectedCadence: 5, availability: .available)
        }
        func elapsed(_ begin: ContinuousClock.Instant) -> Double {
            let d = begin.duration(to: .now).components
            return Double(d.seconds) + Double(d.attoseconds) / 1e18
        }
        var results: [Result] = []
        for (retention, visible) in [(HistoryRetention.week, false), (.week, true), (.off, true)] {
            for duplicateSync in [true, false] {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-expiry-profile-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
                await store.updateSettings(.init(retention: retention), now: base.addingTimeInterval(-900))
                for index in 0...180 { await store.ingest(snapshot(base.addingTimeInterval(Double(index - 180) * 5))) }
                let model = AppModel(store: store)
                model.settings.retention = retention
                model.fullWindowVisible = visible; model.destination = .history
                model.snapshot = snapshot(base)
                await model.refreshHistoryPresentation()
                let measurement = PerformanceMeasurement()
                var expiry = 0.0, ingest = 0.0, sync = 0.0
                for index in 1...30 {
                    let time = base.addingTimeInterval(Double(index) * 5)
                    var begin = ContinuousClock.now
                    if duplicateSync { await model.expireMemoryHistory(now: time) }
                    else {
                        // Isolate the extra presentation sync only; preserve raw expiry before ingest.
                        let expired = await store.expireRecent(now: time)
                        XCTAssertTrue(expired)
                    }
                    expiry += elapsed(begin)
                    begin = .now
                    await store.ingest(snapshot(time))
                    model.snapshot = snapshot(time)
                    ingest += elapsed(begin)
                    begin = .now
                    await model.refreshHistoryPresentation()
                    sync += elapsed(begin)
                    let state = await store.state()
                    XCTAssertNil(state.error)
                    XCTAssertEqual(state.recentSnapshots.count, 181)
                    XCTAssertTrue(state.recentSnapshots.allSatisfy { time.timeIntervalSince($0.timestamp) <= 900 })
                }
                let report = measurement.report(notes: ["Synthetic fixture pipeline; no collection, UI rendering or live process metadata."])
                let state = await store.state()
                results.append(Result(retention: retention.rawValue, visibleHistory: visible,
                    duplicatePresentationSync: duplicateSync, iterations: 30, process: report,
                    expiryWallSeconds: expiry, ingestWallSeconds: ingest, finalSyncWallSeconds: sync,
                    finalRawSamples: state.recentSnapshots.count))
            }
        }
        struct Evidence: Encodable { var results: [Result]; var notes: [String] }
        let evidence = Evidence(results: results, notes: [
            "Release opt-in XCTest with650syntheticprocesses/65apps and181samples spanning15minutes;30five-second logical ticks per case. No actual150-second wait or process sampling.",
            "Candidate preserves raw expiry but directly invokes store.expireRecent to isolate omission of the pre-ingest presentation sync. This is a cost experiment, not a shipping lifecycle patch; it does not simulate revision changes, suspension or interrupted refresh behavior.",
            "Shared immutable synthetic process arrays avoid real per-sample string allocation; timings do not establish the GUI budget or allocation behavior. CPU is whole XCTest process over each case.",
            "Actual runner exit must be recorded separately. Output contains fixture counts/timings only."
        ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: URL(fileURLWithPath: "/private/tmp/amid-expiry-profile.json"), options: .atomic)
    }
}
