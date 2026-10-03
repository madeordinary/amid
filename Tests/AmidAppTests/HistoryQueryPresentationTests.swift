import XCTest
import Foundation
@testable import AmidCore
@testable import AmidApp

final class HistoryQueryPresentationTests: XCTestCase {
    @MainActor
    private func model() -> AppModel {
        let model = AppModel()
        model.settings.retention = .day
        model.destination = .history
        model.fullWindowVisible = true
        return model
    }

    @MainActor
    func testMatchingReplyPublishesSelectedPoints() async {
        let model = model()
        await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
            HistoryQuery(entityID: entity, since: since, until: until, points: [HistoryAggregate(entityID: entity, name: "System", start: since, resolution: 60)], revision: 4, error: nil)
        }
        XCTAssertNil(model.historyQueryError)
        XCTAssertEqual(model.aggregates.count, 1)
        XCTAssertEqual(model.aggregates.first?.entityID, "system")
    }

    @MainActor
    func testSelectionChangedDuringReplyDoesNotPublishFailureOrData() async {
        let model = model()
        await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
            model.historyEntity = "app:other"
            return HistoryQuery(entityID: entity, since: since, until: until, points: [HistoryAggregate(entityID: entity, name: "Old", start: since, resolution: 60)], revision: 3, error: "old failure")
        }
        XCTAssertNil(model.historyQueryError)
        XCTAssertTrue(model.aggregates.isEmpty)
    }

    @MainActor
    func testHideAndShowDuringReplyInvalidatesSameSelection() async {
        let model = model()
        await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
            model.fullWindowVisible = false
            model.fullWindowVisible = true
            return HistoryQuery(entityID: entity, since: since, until: until, points: [HistoryAggregate(entityID: entity, name: "Old", start: since, resolution: 60)], revision: 3, error: "old failure")
        }
        XCTAssertNil(model.historyQueryError)
        XCTAssertEqual(model.retainedHistoryNames, ["system": "System"])
    }

    @MainActor
    func testRangeAndSettingsChangesInvalidateReply() async {
        for change in 0..<2 {
            let model = model()
            await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
                if change == 0 { model.historyHours = 1 }
                else { model.settings.excludedApplications.insert("excluded") }
                return HistoryQuery(entityID: entity, since: since, until: until, points: [HistoryAggregate(entityID: entity, name: "Old", start: since, resolution: 60)], revision: 3, error: "old failure")
            }
            XCTAssertNil(model.historyQueryError)
        }
    }

    @MainActor
    func testCurrentQueryFailureIsExplicitAndEmpty() async {
        let model = model()
        await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
            HistoryQuery(entityID: entity, since: since, until: until, points: [], revision: 4, error: "unavailable")
        }
        XCTAssertNotNil(model.historyQueryError)
        XCTAssertTrue(model.aggregates.isEmpty)
    }

    @MainActor
    func testClearAndSuspensionRejectOutstandingReply() async {
        for clear in [true, false] {
            let model = model()
            await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
                if clear { await model.clearHistory() }
                else { await model.setSuspension("screen", enabled: true) }
                return HistoryQuery(entityID: entity, since: since, until: until, points: [HistoryAggregate(entityID: entity, name: "Old", start: since, resolution: 60)], revision: 3, error: "old failure")
            }
            XCTAssertNil(model.historyQueryError)
            XCTAssertTrue(model.aggregates.isEmpty)
            XCTAssertTrue(model.inspectorHistoryPoints.isEmpty)
        }
    }
    @MainActor
    func testInspectorSelectionChangeRejectsOutstandingReply() async {
        let model = model()
        model.destination = .applications
        model.selectedGroupID = "first"
        await model.receiveHistoryQuery(entityID: "app:first", inspector: true, revision: 4) { entity, since, until in
            model.selectedGroupID = "second"
            return HistoryQuery(entityID: entity, since: since, until: until,
                                points: [HistoryAggregate(entityID: entity, name: "First", start: since, resolution: 60)], revision: 4, error: nil)
        }
        XCTAssertNil(model.inspectorHistoryEntity)
        XCTAssertTrue(model.inspectorHistoryPoints.isEmpty)
        XCTAssertNil(model.inspectorHistoryError)
    }

    @MainActor
    func testQuitRejectsOutstandingSuccessfulReply() async {
        let model = model()
        await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
            await model.prepareToQuit()
            return HistoryQuery(entityID: entity, since: since, until: until,
                                points: [HistoryAggregate(entityID: entity, name: "System", start: since, resolution: 60)], revision: 4, error: nil)
        }
        XCTAssertTrue(model.aggregates.isEmpty)
        XCTAssertTrue(model.inspectorHistoryPoints.isEmpty)
        XCTAssertNil(model.historyQueryError)
    }

    @MainActor
    func testHistoryNamesUseCurrentQualifiedThenRawAlias() {
        let model = model()
        for entity in ["app:example", "project:example"] {
            model.settings.aliases["example"] = "Raw alias"
            XCTAssertEqual(model.historyDisplayName(entityID: entity, fallback: "Stored name"), "Raw alias")
            model.settings.aliases[entity] = "Qualified alias"
            XCTAssertEqual(model.historyDisplayName(entityID: entity, fallback: "Stored name"), "Qualified alias")
            model.settings.aliases[entity] = "New current alias"
            XCTAssertEqual(model.historyDisplayName(entityID: entity, fallback: "Stored name"), "New current alias")
            model.settings.aliases.removeValue(forKey: entity)
            model.settings.aliases.removeValue(forKey: "example")
            XCTAssertEqual(model.historyDisplayName(entityID: entity, fallback: "Stored name"), "Stored name")
        }
    }

    @MainActor
    func testRealStorePublishesOnlySelectionAndKeepsExitedEntityNamesUntilHide() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-history-query-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        let settings = HistorySettings(retention: .week)
        let now = Date().addingTimeInterval(-120)
        await store.updateSettings(settings, now: now)
        let processes = ["first", "second"].enumerated().map { index, id in
            ProcessSample(identity: .init(bootID: "synthetic", pid: Int32(index + 1), uid: 501, startSeconds: 1, startMicroseconds: 0),
                          executable: "/synthetic/" + id, name: id, cpuPercent: Double(index + 1), memoryBytes: 1024,
                          applicationID: id, applicationName: id.capitalized, groupingReason: "Synthetic test")
        }
        await store.ingest(Snapshot(timestamp: now, processes: processes, availability: .available))
        // Both applications have exited from subsequent observations, but their retained names remain selectable.
        await store.ingest(Snapshot(timestamp: now.addingTimeInterval(65), availability: .available))
        let direct = await store.history(entityID: "app:first", since: now.addingTimeInterval(-3600), until: Date())
        XCTAssertNil(direct.error)
        XCTAssertFalse(direct.points.isEmpty)
        let model = AppModel(store: store)
        model.settings = settings
        model.destination = .history
        model.historyEntity = "app:first"
        model.fullWindowVisible = true
        await model.refreshHistoryPresentation()
        let firstDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.aggregates.isEmpty && ContinuousClock.now < firstDeadline { await Task.yield() }
        XCTAssertFalse(model.aggregates.isEmpty)
        XCTAssertTrue(model.aggregates.allSatisfy { $0.entityID == "app:first" })
        XCTAssertEqual(model.retainedHistoryNames["app:first"], "First")
        XCTAssertEqual(model.retainedHistoryNames["app:second"], "Second")
        XCTAssertNotNil(model.retainedHistoryNames["system"])
        XCTAssertNil(model.historyQueryError)
        model.historyEntity = "app:second"
        await model.refreshHistoryPresentation()
        let secondDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.aggregates.isEmpty && ContinuousClock.now < secondDeadline { await Task.yield() }
        XCTAssertFalse(model.aggregates.isEmpty)
        XCTAssertTrue(model.aggregates.allSatisfy { $0.entityID == "app:second" })
        model.fullWindowVisible = false
        XCTAssertTrue(model.aggregates.isEmpty)
        XCTAssertTrue(model.inspectorHistoryPoints.isEmpty)
        XCTAssertEqual(model.retainedHistoryNames, ["system": "System"])
    }

    @MainActor
    func testOrdinaryHistorySelectionPreservesNamesButPrivacyTransitionsClearThem() {
        let model = model()
        let names = ["system": "System", "app:exited": "Exited fixture"]
        model.retainedHistoryNames = names
        model.historyEntity = "app:exited"
        XCTAssertEqual(model.retainedHistoryNames, names)
        model.historyHours = 1
        XCTAssertEqual(model.retainedHistoryNames, names)
        model.destination = .settings
        model.destination = .history
        XCTAssertEqual(model.retainedHistoryNames, names)
        model.fullWindowVisible = false
        XCTAssertEqual(model.retainedHistoryNames, ["system": "System"])
        XCTAssertFalse(model.historyQueryPending)
        model.fullWindowVisible = true
        model.retainedHistoryNames = names
        model.settings.excludedApplications.insert("exited")
        XCTAssertEqual(model.retainedHistoryNames, ["system": "System"])
        XCTAssertFalse(model.inspectorHistoryPending)
    }

    @MainActor
    func testDelayedHistoryReplyIsPendingUntilCompletedEmptyOrError() async {
        for fails in [false, true] {
            let model = model()
            await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
                XCTAssertTrue(model.historyQueryPending)
                XCTAssertTrue(model.aggregates.isEmpty)
                XCTAssertNil(model.historyQueryError)
                await Task.yield()
                XCTAssertTrue(model.historyQueryPending)
                return HistoryQuery(entityID: entity, since: since, until: until, points: [], revision: 4, error: fails ? "unavailable" : nil)
            }
            XCTAssertFalse(model.historyQueryPending)
            XCTAssertTrue(model.aggregates.isEmpty)
            XCTAssertEqual(model.historyQueryError != nil, fails)
        }
    }

    @MainActor
    func testStaleReplyCannotCompleteNewerPendingRequest() async {
        let model = model()
        var oldReply: CheckedContinuation<HistoryQuery?, Never>?
        var newReply: CheckedContinuation<HistoryQuery?, Never>?
        var oldQuery: HistoryQuery?
        var newQuery: HistoryQuery?
        let oldTask = Task {
            await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
                oldQuery = HistoryQuery(entityID: entity, since: since, until: until, points: [], revision: 4, error: "old error")
                return await withCheckedContinuation { oldReply = $0 }
            }
        }
        let firstDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while oldReply == nil && ContinuousClock.now < firstDeadline { await Task.yield() }
        XCTAssertNotNil(oldReply)
        let newTask = Task {
            await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
                newQuery = HistoryQuery(entityID: entity, since: since, until: until, points: [], revision: 4, error: nil)
                return await withCheckedContinuation { newReply = $0 }
            }
        }
        let secondDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while newReply == nil && ContinuousClock.now < secondDeadline { await Task.yield() }
        XCTAssertNotNil(newReply)
        oldReply?.resume(returning: oldQuery)
        await oldTask.value
        XCTAssertTrue(model.historyQueryPending)
        XCTAssertNil(model.historyQueryError)
        newReply?.resume(returning: newQuery)
        await newTask.value
        XCTAssertFalse(model.historyQueryPending)
        XCTAssertNil(model.historyQueryError)
    }

    @MainActor
    func testHideAndSettingsClearPendingRepliesAndNamesImmediately() async {
        for hide in [true, false] {
            let model = model()
            model.retainedHistoryNames["app:private"] = "Private fixture"
            await model.receiveHistoryQuery(entityID: "system", inspector: false, revision: 4) { entity, since, until in
                XCTAssertTrue(model.historyQueryPending)
                if hide { model.fullWindowVisible = false }
                else { model.settings.excludedApplications.insert("private") }
                XCTAssertFalse(model.historyQueryPending)
                XCTAssertEqual(model.retainedHistoryNames, ["system": "System"])
                return HistoryQuery(entityID: entity, since: since, until: until, points: [], revision: 4, error: "stale")
            }
            XCTAssertFalse(model.historyQueryPending)
            XCTAssertNil(model.historyQueryError)
        }
    }

    @MainActor
    func testOffRecentHistoryCompletesLoadingAfterShow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-history-off-loading-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        await store.updateSettings(.init(retention: .off))
        let model = AppModel(store: store)
        model.settings.retention = .off
        model.destination = .history
        model.fullWindowVisible = true
        await model.refreshHistoryPresentation()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.historyQueryPending && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(model.historyQueryPending)
        XCTAssertTrue(model.recentHistoryPoints.isEmpty)
        XCTAssertNil(model.historyQueryError)
        model.destination = .applications
        model.selectedGroupID = "missing"
        await model.refreshHistoryPresentation()
        let inspectorDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.inspectorHistoryPending && ContinuousClock.now < inspectorDeadline { await Task.yield() }
        XCTAssertFalse(model.inspectorHistoryPending)
        XCTAssertTrue(model.inspectorHistoryPoints.isEmpty)
    }

}
