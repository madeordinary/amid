import XCTest
import Foundation
@testable import AmidCore

/// Opt-in synthetic timings; never a whole-app performance-budget result.
final class HistoryAlertProfileTests: XCTestCase, @unchecked Sendable {
    func testSyntheticHistoryAlertGrowthProfile() async throws {
        guard ProcessInfo.processInfo.environment["AMID_PROFILE_SYNTHETIC"] == "1" else { throw XCTSkip("Opt-in synthetic profiling only.") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("amid-profile-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider())
        let engine = AlertEngine()
        let start = Date(timeIntervalSince1970:1_800_000_000)
        let processes = (0..<650).map { i in
            ProcessSample(identity:.init(bootID:"synthetic",pid:Int32(i+100),uid:501,startSeconds:1,startMicroseconds:0),executable:"/fixture",name:"Fixture",cpuPercent:0.1,memoryBytes:1_048_576,memoryMethod:.footprint,applicationID:"fixture.\(i % 65)",applicationName:"Fixture",groupingReason:"synthetic")
        }
        await store.updateSettings(.init(retention:.month),now:start)
        let clock = ContinuousClock()
        var totals = [Double](repeating:0,count:3)
        var count = 0
        for step in 0...360 {
            var snapshot = Snapshot(timestamp:start.addingTimeInterval(Double(step)*5),processes:processes,cadence:5,availability:.available)
            snapshot.system.memory.pressure = .warning // Sustained updates exercise recordAlerts after60s.
            let a = clock.now; await store.ingest(snapshot); let b = clock.now
            let events = await engine.evaluate(snapshot); let c = clock.now
            await store.recordAlerts(events); let d = clock.now
            func ms(_ duration: Duration) -> Double { Double(duration.components.seconds)*1000 + Double(duration.components.attoseconds)/1e15 }
            totals[0] += ms(a.duration(to:b)); totals[1] += ms(b.duration(to:c)); totals[2] += ms(c.duration(to:d)); count += 1
            if [12,180,360].contains(step) {
                let state = await store.state()
                print("SYNTHETIC elapsed_min=\(step/12) processes=650 apps=65 segment_samples=\(count) mean_ingest_ms=\(totals[0]/Double(count)) mean_evaluate_ms=\(totals[1]/Double(count)) mean_record_ms=\(totals[2]/Double(count)) raw_ring=\(state.recentSnapshots.count) aggregates=\(state.aggregates.count) alerts=\(state.alerts.count)")
                totals = [0,0,0]; count = 0
            }
        }
        let state = await store.state()
        XCTAssertEqual(state.recentSnapshots.count,181)
        XCTAssertEqual(state.alerts.count,1)
        // Isolate the ownership pattern only; no claim that this models full engine allocation.
        for extracting in [false,true] {
            var windows = Dictionary(uniqueKeysWithValues:(0..<65).map { ($0,Array(repeating:1.0,count:361)) })
            let a = clock.now
            for _ in 0..<2000 {
                for key in 0..<65 {
                    var points = extracting ? windows.removeValue(forKey:key)! : windows[key]!
                    points.append(2); points.removeFirst(); windows[key] = points
                }
            }
            let duration = a.duration(to:clock.now)
            let milliseconds = Double(duration.components.seconds)*1000 + Double(duration.components.attoseconds)/1e15
            print("SYNTHETIC ownership_extract=\(extracting) operations=130000 elapsed_ms=\(milliseconds) checksum=\(windows.values.reduce(0) { $0+$1.count })")
        }
    }
}
