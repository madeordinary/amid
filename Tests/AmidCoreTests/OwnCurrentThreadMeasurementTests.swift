import XCTest
import Darwin
@testable import AmidCore

final class OwnCurrentThreadMeasurementTests: XCTestCase, @unchecked Sendable {
    func testOwnBusyThreadCPUAdvancesAndPortRightIsReleasedOnce() throws {
        let measurement = OwnCurrentThreadMeasurement()
        let before = try XCTUnwrap(measurement.report().cpuSeconds)
        let until = ContinuousClock.now.advanced(by:.milliseconds(50))
        var value = 1.0
        while ContinuousClock.now < until { value += sqrt(value) }
        XCTAssertGreaterThan(value,1)
        let after = try XCTUnwrap(measurement.report().cpuSeconds)
        XCTAssertGreaterThan(after,before)
        var releases = 0
        let port = mach_thread_self()
        var owned: OwnCurrentThreadMeasurement? = OwnCurrentThreadMeasurement(thread:port,readCPU:{ _ in 1 },release:{ ownedPort in
            XCTAssertEqual(ownedPort,port); releases += 1; mach_port_deallocate(mach_task_self_,ownedPort)
        })
        XCTAssertEqual(owned?.report().cpuSeconds,0)
        owned = nil; XCTAssertEqual(releases,1)
    }
    func testUnavailableAndRegressedNumericCountersAreUnknown() {
        XCTAssertNil(OwnCurrentThreadMeasurement.delta(nil,1))
        XCTAssertNil(OwnCurrentThreadMeasurement.delta(1,nil))
        XCTAssertNil(OwnCurrentThreadMeasurement.delta(2,1))
        XCTAssertNil(OwnCurrentThreadMeasurement.delta(1,.infinity))
        XCTAssertNil(OwnCurrentThreadMeasurement.delta(-1,1))
        var reads = 0; var releases = 0
        let failed = OwnCurrentThreadMeasurement(thread:mach_port_t(MACH_PORT_NULL),readCPU:{ _ in reads += 1; return 0 },release:{ _ in releases += 1 })
        XCTAssertNil(failed.report().cpuSeconds); XCTAssertEqual(reads,0); XCTAssertEqual(releases,0)
    }
    func testProfiledIngestHasIdenticalHistoryAndGapSemantics() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("amid-thread-parity-\(UUID())")
        defer { try? FileManager.default.removeItem(at:root) }
        for retention in [HistoryRetention.off,.week] {
            let plain = HistoryStore(directory:root.appendingPathComponent("plain-"+retention.rawValue),keyProvider:EphemeralHistoryKeyProvider())
            let profiled = HistoryStore(directory:root.appendingPathComponent("profiled-"+retention.rawValue),keyProvider:EphemeralHistoryKeyProvider())
            let start = Date(timeIntervalSince1970:1_800_000_000)
            await plain.updateSettings(.init(retention:retention),now:start)
            await profiled.updateSettings(.init(retention:retention),now:start)
            var system = SystemSnapshot(); system.cpuPercent = 10; system.memory.active = 1024
            for second in [0.0,5,125] {
                let snapshot = Snapshot(timestamp:start.addingTimeInterval(second),system:system,cadence:second == 125 ? 120 : 5,expectedCadence:5,availability:.available)
                await plain.ingest(snapshot)
                let report = await profiled.profiledIngest(snapshot)
                XCTAssertGreaterThanOrEqual(report.wallSeconds,0)
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(report.cpuSeconds),0)
            }
            let a = await plain.state(); let b = await profiled.state()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            XCTAssertEqual(try encoder.encode(a.aggregates),try encoder.encode(b.aggregates))
            let rawA = await plain.recentHistory(entityID:"system"); let rawB = await profiled.recentHistory(entityID:"system")
            XCTAssertEqual(try encoder.encode(rawA),try encoder.encode(rawB))
            XCTAssertNil(a.error); XCTAssertNil(b.error)
        }
    }
}
