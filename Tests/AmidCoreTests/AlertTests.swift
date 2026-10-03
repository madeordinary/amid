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
