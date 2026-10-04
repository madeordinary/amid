import XCTest
@testable import AmidCore

final class AlertTests: XCTestCase, @unchecked Sendable {
    func snapshot(_ seconds: Double, pressure: Pressure = .normal, cpu: Double? = 200, memory: UInt64? = 4 * 1073741824, swap: UInt64? = 0, capacity: UInt64? = 100 * 1073741824, method: MemoryMethod = .footprint, availability: Availability = .available, server: Bool = false) -> Snapshot {
        var system = SystemSnapshot(); system.logicalCPUCount = 8; system.memory.pressure = pressure; system.memory.swapUsed = swap
        system.volumes = [.init(id:"startup",name:"Startup",capacity:200 * 1073741824,available:capacity,isStartup:true,definition:"OS available capacity")]
        let process = ProcessSample(identity:.init(bootID:"boot",pid:11,uid:501,startSeconds:1,startMicroseconds:0),executable:"/node",name:"Test",runtime:"Node",cpuPercent:cpu,memoryBytes:memory,memoryMethod:method,projectPath:server ? "/project" : nil,applicationID:"app",applicationName:"Test",groupingReason:"fixture",endpoints:server ? [.init(address:"127.0.0.1",port:1234,family:"IPv4",scope:"Loopback")] : [],portAvailability:.available)
        return Snapshot(timestamp:Date(timeIntervalSince1970:seconds),system:system,processes:[process],cadence:5,availability:availability)
    }
    func testPressureSustainNormalRecoveryCooldownAndMissing() async {
        let engine = AlertEngine(settings:.init(enabledRules:[.memoryPressure]))
        var result: [AlertEvent] = []
        for t in stride(from:0.0,through:60,by:5) { result = await engine.evaluate(snapshot(t,pressure:.warning)) }
        XCTAssertEqual(result.count,1); XCTAssertTrue(result[0].notificationEligible)
        _ = await engine.evaluate(snapshot(65,pressure:.normal))
        for t in stride(from:70.0,through:365,by:5) { result = await engine.evaluate(snapshot(t)) }
        XCTAssertNotNil(result.first?.recoveredAt)
        for t in stride(from:370.0,through:430,by:5) { result = await engine.evaluate(snapshot(t,pressure:.critical)) }
        XCTAssertEqual(result.count,1); XCTAssertFalse(result[0].notificationEligible)
        let missing = AlertEngine(settings:.init(enabledRules:[.memoryPressure]))
        for t in stride(from:0.0,through:55,by:5) { _ = await missing.evaluate(snapshot(t,pressure:.warning)) }
        _ = await missing.evaluate(snapshot(60,pressure:.unknown)); result = await missing.evaluate(snapshot(65,pressure:.warning)); XCTAssertTrue(result.isEmpty)
    }
    func testCPUTriggerRecoveryMissingDisableAndExclusion() async {
        let engine = AlertEngine(settings:.init(enabledRules:[.appCPU])); var result: [AlertEvent] = []
        for t in stride(from:0.0,through:300,by:5) { result = await engine.evaluate(snapshot(t)) }
        XCTAssertEqual(result.first?.category,.appCPU); XCTAssertTrue(result[0].detail.contains("25.0%"))
        for t in stride(from:305.0,through:610,by:5) { result = await engine.evaluate(snapshot(t,cpu:0)) }
        let events = await engine.events(); XCTAssertNotNil(events.first?.recoveredAt)
        await engine.updateSettings(.init(enabledRules:[],excludedApplications:["app"]))
        for t in stride(from:615.0,through:930,by:5) { result = await engine.evaluate(snapshot(t)) }; XCTAssertTrue(result.isEmpty)
        let missing = AlertEngine(settings:.init(enabledRules:[.appCPU]))
        for t in stride(from:0.0,through:295,by:5) { _ = await missing.evaluate(snapshot(t)) }
        _ = await missing.evaluate(snapshot(300,cpu:nil)); result = await missing.evaluate(snapshot(305)); XCTAssertTrue(result.isEmpty)
    }
    func testMemoryGrowthRequiresDurationPercentAndConsistentMethod() async {
        let engine = AlertEngine(settings:.init(enabledRules:[.appMemoryGrowth])); var result: [AlertEvent] = []
        for t in stride(from:0.0,through:1800,by:5) { result = await engine.evaluate(snapshot(t,memory:UInt64(4 * 1073741824 + t / 1800 * 1073741824))) }
        XCTAssertEqual(result.first?.category,.appMemoryGrowth)
        let changed = AlertEngine(settings:.init(enabledRules:[.appMemoryGrowth]))
        for t in stride(from:0.0,through:1800,by:5) { result = await changed.evaluate(snapshot(t,memory:UInt64(4 * 1073741824 + t / 1800 * 1073741824),method:t < 900 ? .footprint : .rss)) }
        XCTAssertTrue(result.isEmpty)
    }
    func testSwapRequiresPressureAndDiskSustainMissingRecovery() async {
        let engine = AlertEngine(settings:.init(enabledRules:[.swapGrowth,.diskCapacity])); var result: [AlertEvent] = []
        for t in stride(from:0.0,through:900,by:5) { result = await engine.evaluate(snapshot(t,pressure:.warning,swap:UInt64(t / 900 * 1073741824),capacity:1)) }
        XCTAssertTrue(result.contains { $0.category == .swapGrowth }); let events = await engine.events(); XCTAssertTrue(events.contains { $0.category == .diskCapacity })
        result = await engine.evaluate(snapshot(905,capacity:100 * 1073741824)); XCTAssertTrue(result.contains { $0.category == .diskCapacity && $0.recoveredAt != nil })
        let normal = AlertEngine(settings:.init(enabledRules:[.swapGrowth]))
        for t in stride(from:0.0,through:900,by:5) { result = await normal.evaluate(snapshot(t,swap:UInt64(t / 900 * 1073741824))) }; XCTAssertTrue(result.isEmpty)
        let missing = AlertEngine(settings:.init(enabledRules:[.diskCapacity]))
        for t in stride(from:0.0,through:295,by:5) { _ = await missing.evaluate(snapshot(t,capacity:1)) }
        _ = await missing.evaluate(snapshot(300,capacity:nil)); result = await missing.evaluate(snapshot(305,capacity:1)); XCTAssertTrue(result.isEmpty)
    }
    func testLowObservedCPURequiresTwoHoursAndIsNeverNotification() async {
        let engine = AlertEngine(settings:.init(enabledRules:[.lowActivityServer])); var result: [AlertEvent] = []
        for t in stride(from:0.0,through:7200,by:5) { result = await engine.evaluate(snapshot(t,cpu:0.1,server:true)); if t < 7200 { XCTAssertTrue(result.isEmpty) } }
        XCTAssertEqual(result.first?.category,.lowActivityServer); XCTAssertFalse(result[0].notificationEligible)
        _ = await engine.evaluate(snapshot(7205,cpu:nil,server:true)); result = await engine.evaluate(snapshot(7210,cpu:0.1,server:true)); XCTAssertTrue(result.isEmpty)
    }
}

extension AlertTests {
    func testSuspendRestorePreservesCooldown() async {
        let first = AlertEngine(settings:.init(enabledRules:[.appCPU])); var updates: [AlertEvent] = []
        for t in stride(from:0.0,through:300,by:5) { updates = await first.evaluate(snapshot(t)) }
        XCTAssertTrue(updates[0].notificationEligible); XCTAssertEqual(updates[0].lastNotificationAt,Date(timeIntervalSince1970:300))
        await first.suspendObservation(); let suspended = await first.events(); XCTAssertTrue(suspended[0].observationSuspended)
        let resumed = AlertEngine(settings:.init(enabledRules:[.appCPU])); await resumed.restore(events:suspended)
        for t in stride(from:305.0,through:605,by:5) { updates = await resumed.evaluate(snapshot(t)) }
        XCTAssertFalse(updates[0].notificationEligible); XCTAssertFalse(updates[0].observationSuspended)
        let events = await resumed.events(); XCTAssertEqual(events.count,1)
    }
    func testMissingAndSleepResetGrowthWindow() async {
        for category in [AlertCategory.appMemoryGrowth,.swapGrowth] {
            let engine = AlertEngine(settings:.init(enabledRules:[category])); var result: [AlertEvent] = []
            for t in stride(from:0.0,through:1795,by:5) {
                result = await engine.evaluate(snapshot(t,pressure:.warning,memory:t == 890 ? nil : UInt64(4 * 1073741824 + t / 1800 * 1073741824),swap:t == 890 ? nil : UInt64(t / 900 * 1073741824),availability:t == 895 ? .sleeping : .available))
            }
            XCTAssertTrue(result.isEmpty)
        }
    }
}

extension AlertTests {
    func testDismissedSuggestionStaysDismissedDuringSameEpisode() async throws {
        let engine = AlertEngine(settings:.init(enabledRules:[.lowActivityServer])); var updates: [AlertEvent] = []
        for t in stride(from:0.0,through:7200,by:5) { updates = await engine.evaluate(snapshot(t,cpu:0.1,server:true)) }
        let id = try XCTUnwrap(updates.first?.id)
        let dismissed = await engine.dismiss(id,at:Date(timeIntervalSince1970:7201)); XCTAssertNotNil(dismissed?.dismissedAt)
        updates = await engine.evaluate(snapshot(7205,cpu:0.1,server:true)); XCTAssertTrue(updates.isEmpty)
    }
}


extension AlertTests {
    func testIdenticalSettingsUpdatePreservesContinuousPressureQualification() async {
        let settings = AlertSettings(enabledRules:[.memoryPressure])
        let engine = AlertEngine(settings:settings)
        for t in stride(from:0.0,through:30,by:5) { _ = await engine.evaluate(snapshot(t,pressure:.warning)) }
        await engine.updateSettings(settings)
        var updates: [AlertEvent] = []
        for t in stride(from:35.0,through:60,by:5) { updates = await engine.evaluate(snapshot(t,pressure:.warning)) }
        XCTAssertEqual(updates.count,1); XCTAssertEqual(updates.first?.category,.memoryPressure)
        XCTAssertEqual(updates.first?.startedAt,Date(timeIntervalSince1970:0)); XCTAssertTrue(updates.first?.notificationEligible ?? false)
    }
}

extension AlertTests {
    func testActualStallWithFiveSecondExpectedCadenceResetsPressureWindow() async {
        let engine = AlertEngine(settings:.init(enabledRules:[.memoryPressure]))
        for t in stride(from:0.0,through:55,by:5) { _ = await engine.evaluate(snapshot(t,pressure:.warning)) }
        var stalled = snapshot(175,pressure:.warning); stalled.cadence = 120; stalled.expectedCadence = 5
        let result = await engine.evaluate(stalled); XCTAssertTrue(result.isEmpty)
        var final: [AlertEvent] = []
        for t in stride(from:180.0,through:235,by:5) { final = await engine.evaluate(snapshot(t,pressure:.warning)) }
        XCTAssertEqual(final.count,1); XCTAssertEqual(final.first?.startedAt,Date(timeIntervalSince1970:175))
    }
    func testMemoryEventDetailUsesCurrentLiteralNameOnCreationAndUpdate() async {
        let engine = AlertEngine(settings:.init(enabledRules:[.appMemoryGrowth]))
        var result: [AlertEvent] = []
        for t in stride(from:0.0,through:1800,by:5) {
            var value = snapshot(t,memory:UInt64(4 * 1073741824 + t / 1800 * 1073741824))
            value.processes[0].applicationName = "Literal %@ 100%"
            result = await engine.evaluate(value)
        }
        XCTAssertEqual(result.count,1)
        XCTAssertTrue(result[0].detail.contains("Literal %@ 100%"))
        XCTAssertTrue(result[0].detail.contains("footprint"))
        let id = result[0].id
        var updated = snapshot(1805,memory:6 * 1073741824)
        updated.processes[0].applicationName = "Updated %@"
        result = await engine.evaluate(updated)
        XCTAssertEqual(result.first?.id,id)
        XCTAssertTrue(result.first?.detail.contains("Updated %@") == true)
        XCTAssertFalse(result.first?.notificationEligible ?? true)
    }

}


extension AlertTests {
    func testMemoryGrowthIndependentThresholdsRecoveryAndHourlyCooldown() async throws {
        let gib: UInt64 = 1_073_741_824
        // Each threshold independently fails: 1 GiB is only 12.5% of 8 GiB;
        // 1 GiB minus one byte is below the absolute threshold despite >25% growth.
        for (initial, growth) in [(8 * gib, gib), (2 * gib, gib - 1)] {
            let engine = AlertEngine(settings: .init(enabledRules: [.appMemoryGrowth]))
            for t in stride(from: 0.0, through: 1800, by: 5) {
                let updates = await engine.evaluate(snapshot(t, memory: initial + UInt64(Double(growth) * t / 1800)))
                XCTAssertTrue(updates.isEmpty)
            }
        }
        let engine = AlertEngine(settings: .init(enabledRules: [.appMemoryGrowth]))
        var updates: [AlertEvent] = []
        for t in stride(from: 0.0, through: 1800, by: 5) {
            updates = await engine.evaluate(snapshot(t, memory: 4 * gib + UInt64(Double(gib) * t / 1800)))
            if t < 1800 { XCTAssertTrue(updates.isEmpty) }
        }
        let first = try XCTUnwrap(updates.first)
        XCTAssertEqual(first.updatedAt, Date(timeIntervalSince1970: 1800)); XCTAssertTrue(first.notificationEligible)
        updates = await engine.evaluate(snapshot(1805, memory: 4 * gib))
        XCTAssertEqual(updates.first?.recoveredAt, Date(timeIntervalSince1970: 1805))
        for t in stride(from: 1810.0, through: 3610, by: 5) {
            updates = await engine.evaluate(snapshot(t, memory: 4 * gib + UInt64(Double(gib) * (t - 1810) / 1800)))
        }
        let second = try XCTUnwrap(updates.first)
        XCTAssertNotEqual(second.id, first.id); XCTAssertFalse(second.notificationEligible)
        _ = await engine.evaluate(snapshot(3615, memory: 4 * gib))
        for t in stride(from: 3620.0, through: 5420, by: 5) {
            updates = await engine.evaluate(snapshot(t, memory: 4 * gib + UInt64(Double(gib) * (t - 3620) / 1800)))
        }
        XCTAssertTrue(try XCTUnwrap(updates.first).notificationEligible)
    }

    func testMemoryMissingRestartsFullThirtyMinuteQualification() async throws {
        let gib: UInt64 = 1_073_741_824
        let engine = AlertEngine(settings: .init(enabledRules: [.appMemoryGrowth]))
        for t in stride(from: 0.0, through: 1790, by: 5) {
            _ = await engine.evaluate(snapshot(t, memory: 4 * gib + UInt64(Double(gib) * t / 1800)))
        }
        _ = await engine.evaluate(snapshot(1795, memory: nil))
        var updates: [AlertEvent] = []
        for t in stride(from: 1800.0, through: 3600, by: 5) {
            updates = await engine.evaluate(snapshot(t, memory: 4 * gib + UInt64(Double(gib) * (t - 1800) / 1800)))
            if t < 3600 { XCTAssertTrue(updates.isEmpty) }
        }
        XCTAssertEqual(try XCTUnwrap(updates.first).startedAt, Date(timeIntervalSince1970: 1800))
        XCTAssertEqual(updates.first?.updatedAt, Date(timeIntervalSince1970: 3600))
    }

    func testSwapThresholdMissingRestartRecoveryAndHourlyCooldown() async throws {
        let gib: UInt64 = 1_073_741_824
        let below = AlertEngine(settings: .init(enabledRules: [.swapGrowth]))
        for t in stride(from: 0.0, through: 900, by: 5) {
            let updates = await below.evaluate(snapshot(t, pressure: .warning, swap: UInt64(Double(gib - 1) * t / 900)))
            XCTAssertTrue(updates.isEmpty)
        }
        let engine = AlertEngine(settings: .init(enabledRules: [.swapGrowth]))
        for t in stride(from: 0.0, through: 895, by: 5) { _ = await engine.evaluate(snapshot(t, pressure: .warning, swap: gib)) }
        _ = await engine.evaluate(snapshot(900, pressure: .warning, swap: nil))
        var updates: [AlertEvent] = []
        for t in stride(from: 905.0, through: 1805, by: 5) {
            updates = await engine.evaluate(snapshot(t, pressure: .warning, swap: UInt64(Double(gib) * (t - 905) / 900)))
            if t < 1805 { XCTAssertTrue(updates.isEmpty) }
        }
        XCTAssertEqual(updates.first?.updatedAt, Date(timeIntervalSince1970: 1805)); XCTAssertTrue(try XCTUnwrap(updates.first).notificationEligible)
        updates = await engine.evaluate(snapshot(1810, pressure: .normal, swap: gib))
        XCTAssertEqual(updates.first?.recoveredAt, Date(timeIntervalSince1970: 1810))
        for t in stride(from: 1815.0, through: 2715, by: 5) {
            updates = await engine.evaluate(snapshot(t, pressure: .critical, swap: UInt64(Double(gib) * (t - 1815) / 900)))
        }
        XCTAssertFalse(try XCTUnwrap(updates.first).notificationEligible)
        _ = await engine.evaluate(snapshot(2720, pressure: .normal, swap: gib))
        for t in stride(from: 4510.0, through: 5410, by: 5) {
            updates = await engine.evaluate(snapshot(t, pressure: .warning, swap: UInt64(Double(gib) * (t - 4510) / 900)))
        }
        XCTAssertTrue(try XCTUnwrap(updates.first).notificationEligible)
    }

    func testDiskStrictCustomThresholdMissingRestartRecoveryAndHourlyCooldown() async throws {
        let threshold: UInt64 = 20 * 1_073_741_824
        let engine = AlertEngine(settings: .init(enabledRules: [.diskCapacity], diskThresholdBytes: threshold))
        for t in stride(from: 0.0, through: 300, by: 5) {
            let updates = await engine.evaluate(snapshot(t, capacity: threshold)); XCTAssertTrue(updates.isEmpty)
        }
        for t in stride(from: 305.0, through: 600, by: 5) { _ = await engine.evaluate(snapshot(t, capacity: threshold - 1)) }
        _ = await engine.evaluate(snapshot(605, capacity: nil))
        var updates: [AlertEvent] = []
        for t in stride(from: 610.0, through: 910, by: 5) {
            updates = await engine.evaluate(snapshot(t, capacity: threshold - 1))
            if t < 910 { XCTAssertTrue(updates.isEmpty) }
        }
        XCTAssertTrue(try XCTUnwrap(updates.first).notificationEligible)
        updates = await engine.evaluate(snapshot(915, capacity: threshold))
        XCTAssertEqual(updates.first?.recoveredAt, Date(timeIntervalSince1970: 915))
        for t in stride(from: 920.0, through: 1220, by: 5) { updates = await engine.evaluate(snapshot(t, capacity: threshold - 1)) }
        XCTAssertFalse(try XCTUnwrap(updates.first).notificationEligible)
        _ = await engine.evaluate(snapshot(1225, capacity: threshold))
        for t in stride(from: 4210.0, through: 4510, by: 5) { updates = await engine.evaluate(snapshot(t, capacity: threshold - 1)) }
        XCTAssertTrue(try XCTUnwrap(updates.first).notificationEligible)
    }

    func testLowActivityStrictAverageRecoveryRecurrenceAndMissingListenerRestart() async throws {
        let engine = AlertEngine(settings: .init(enabledRules: [.lowActivityServer]))
        for t in stride(from: 0.0, through: 7200, by: 5) {
            let updates = await engine.evaluate(snapshot(t, cpu: 1, server: true)); XCTAssertTrue(updates.isEmpty)
        }
        var updates: [AlertEvent] = []
        for t in stride(from: 7205.0, through: 9005, by: 5) { updates = await engine.evaluate(snapshot(t, cpu: 0.5, server: true)) }
        let first = try XCTUnwrap(updates.first); XCTAssertFalse(first.notificationEligible)
        for t in stride(from: 9010.0, through: 10810, by: 5) { updates = await engine.evaluate(snapshot(t, cpu: 2, server: true)) }
        let events = await engine.events(); XCTAssertNotNil(events.first { $0.id == first.id }?.recoveredAt)
        for t in stride(from: 10815.0, through: 12615, by: 5) { updates = await engine.evaluate(snapshot(t, cpu: 0.5, server: true)) }
        let second = try XCTUnwrap(updates.first)
        XCTAssertNotEqual(second.id, first.id); XCTAssertFalse(second.notificationEligible)
        _ = await engine.evaluate(snapshot(12620, cpu: nil, server: true))
        for t in stride(from: 12625.0, through: 19825, by: 5) {
            updates = await engine.evaluate(snapshot(t, cpu: 0.5, server: true))
            if t < 19825 { XCTAssertTrue(updates.isEmpty) }
        }
        let resumed = try XCTUnwrap(updates.first)
        XCTAssertEqual(resumed.id, second.id)
        XCTAssertEqual(resumed.updatedAt, Date(timeIntervalSince1970: 19825))
        XCTAssertNil(resumed.recoveredAt); XCTAssertFalse(resumed.observationSuspended)
        XCTAssertFalse(resumed.notificationEligible)
    }
}


extension AlertTests {
    func testLowActivityKnownHighCPURecoversAfterMissingWithoutTwoHourRequalification() async throws {
        let engine = AlertEngine(settings: .init(enabledRules: [.lowActivityServer]))
        var updates: [AlertEvent] = []
        for t in stride(from: 0.0, through: 7200, by: 5) { updates = await engine.evaluate(snapshot(t, cpu: 0.5, server: true)) }
        let id = try XCTUnwrap(updates.first).id
        _ = await engine.evaluate(snapshot(7205, cpu: nil, server: true))
        for t in stride(from: 7210.0, through: 9010, by: 5) {
            updates = await engine.evaluate(snapshot(t, cpu: 1, server: true))
            if t < 9010 { XCTAssertTrue(updates.isEmpty) }
        }
        let recovered = try XCTUnwrap(updates.first)
        XCTAssertEqual(recovered.id, id)
        XCTAssertEqual(recovered.recoveredAt, Date(timeIntervalSince1970: 9010))
        XCTAssertFalse(recovered.observationSuspended); XCTAssertFalse(recovered.notificationEligible)
    }
}
