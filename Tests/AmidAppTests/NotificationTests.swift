import XCTest
import AmidCore
@testable import AmidApp

final class NotificationTests: XCTestCase {
    @MainActor
    func testDisablingDeliveryDuringAwaitStopsRemainingBatch() async throws {
        let model = AppModel()
        model.settings.notificationsEnabled = true
        let event = try JSONDecoder().decode(AlertEvent.self, from: Data("""
        {"id":"00000000-0000-0000-0000-000000000001","category":"memoryPressure","entityID":"system","title":"Fixture","detail":"Synthetic fixture","startedAt":0,"updatedAt":60,"notificationEligible":true,"observationSuspended":false}
        """.utf8))
        var deliveries = 0
        await model.deliverNotifications([event, event], generation: 0) { _ in
            deliveries += 1
            await Task.yield()
            model.settings.notificationsEnabled = false
        }
        XCTAssertEqual(deliveries, 1)
    }

    @MainActor
    func testStaleGenerationCannotDeliver() async throws {
        let model = AppModel()
        model.settings.notificationsEnabled = true
        let event = try JSONDecoder().decode(AlertEvent.self, from: Data("""
        {"id":"00000000-0000-0000-0000-000000000002","category":"memoryPressure","entityID":"system","title":"Fixture","detail":"Synthetic fixture","startedAt":0,"updatedAt":60,"notificationEligible":true,"observationSuspended":false}
        """.utf8))
        var deliveries = 0
        await model.deliverNotifications([event], generation: -1) { _ in deliveries += 1 }
        XCTAssertEqual(deliveries, 0)
        XCTAssertNil(model.snapshot.system.memory.physical)
        XCTAssertEqual(model.statusTitle, "Awaiting your choice")
    }
}

extension NotificationTests {
    @MainActor
    func testRapidSettingsEditsPersistLatestDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-settings-race-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        let model = AppModel(store: store)
        model.settings.retention = .week
        var saves: [Task<Void, Never>] = []
        for value in 0..<20 {
            model.settings.aliases["fixture"] = "Alias \(value)"
            model.settings.excludedApplications = ["fixture-\(value)"]
            saves.append(Task { await model.saveSettings() })
            await Task.yield()
        }
        model.settings.aliases["fixture"] = "Final alias"
        model.settings.excludedApplications = ["final-exclusion"]
        await model.saveSettings()
        for save in saves { await save.value }
        let state = await store.state()
        XCTAssertEqual(model.settings.aliases["fixture"], "Final alias")
        XCTAssertEqual(state.settings.aliases["fixture"], "Final alias")
        XCTAssertEqual(state.settings.excludedApplications, ["final-exclusion"])
    }

    @MainActor
    func testClearHistoryDismissesCapturedProcessMetadata() async {
        let model = AppModel()
        model.selectedProcess = ProcessSample(identity: .init(bootID: "fixture", pid: 999, uid: 501, startSeconds: 1, startMicroseconds: 0), parentPID: 1, executable: "/fixture/process", name: "Fixture", applicationID: "fixture", applicationName: "Fixture", groupingReason: "Fixture")
        model.selectedGroupID = "fixture"
        model.historyEntity = "project:/fixture/private"
        await model.clearHistory()
        XCTAssertNil(model.selectedProcess)
        XCTAssertNil(model.selectedGroupID)
        XCTAssertEqual(model.historyEntity, "system")
        XCTAssertTrue(model.snapshot.processes.isEmpty)
        XCTAssertTrue(model.applications.isEmpty)
        XCTAssertTrue(model.projects.isEmpty)
    }
}

extension NotificationTests {
    @MainActor
    func testPausedMemoryHistoryExpiresWithoutNewSamples() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-paused-expiry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        let start = Date()
        await store.updateSettings(.init(retention: .off), now: start)
        let sample = Snapshot(timestamp: start, availability: .available)
        await store.ingest(sample)
        let model = AppModel(store: store)
        model.settings.retention = .off; model.settings.paused = true
        model.fullWindowVisible = true; model.destination = .history
        model.snapshot = sample
        await model.refreshHistoryPresentation()
        XCTAssertEqual(model.recentHistoryPoints.count, 1)
        await model.expireMemoryHistory(now: start.addingTimeInterval(901))
        XCTAssertTrue(model.recentHistoryPoints.isEmpty)
        XCTAssertEqual(model.snapshot.availability, .stale)
        XCTAssertEqual(model.memoryHistoryRevision, 1)
        XCTAssertTrue(model.paused)
    }
}

extension NotificationTests {
    private func eligibleEvent(_ category: AlertCategory, entity: String) throws -> AlertEvent {
        let data = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "category": category.rawValue,
            "entityID": entity, "title": "Synthetic", "detail": "Synthetic", "startedAt": 0, "updatedAt": 60,
            "notificationEligible": true, "observationSuspended": false])
        return try JSONDecoder().decode(AlertEvent.self, from: data)
    }
    @MainActor
    func testRuleDisabledDuringAwaitSkipsOnlyThatCategory() async throws {
        let model = AppModel(); model.settings.notificationsEnabled = true
        let first = try eligibleEvent(.memoryPressure, entity: "system")
        let disabled = try eligibleEvent(.appCPU, entity: "fixture.app")
        let allowed = try eligibleEvent(.diskCapacity, entity: "startup")
        var delivered: [UUID] = []
        await model.deliverNotifications([first, disabled, allowed], generation: 0) { event in
            delivered.append(event.id)
            if event.id == first.id {
                await Task.yield()
                model.settings.alertEnabledRules.removeAll { $0 == AlertCategory.appCPU.rawValue }
            }
        }
        XCTAssertEqual(delivered, [first.id, allowed.id])
    }
    @MainActor
    func testApplicationExcludedDuringAwaitSkipsItsPendingAlertsOnly() async throws {
        let model = AppModel(); model.settings.notificationsEnabled = true
        let first = try eligibleEvent(.memoryPressure, entity: "system")
        let cpu = try eligibleEvent(.appCPU, entity: "fixture.app")
        let memory = try eligibleEvent(.appMemoryGrowth, entity: "fixture.app")
        let allowed = try eligibleEvent(.appCPU, entity: "other.app")
        var delivered: [UUID] = []
        await model.deliverNotifications([first, cpu, memory, allowed], generation: 0) { event in
            delivered.append(event.id)
            if event.id == first.id {
                await Task.yield()
                model.settings.excludedApplications.insert("fixture.app")
            }
        }
        XCTAssertEqual(delivered, [first.id, allowed.id])
    }
}
