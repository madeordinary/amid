import XCTest
import Observation
import Foundation
@testable import AmidCore
@testable import AmidApp

private final class OverviewChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var countStorage = 0
    func changed() { lock.withLock { countStorage += 1 } }
    var count: Int { lock.withLock { countStorage } }
}

final class OverviewPresentationTests: XCTestCase {
    @MainActor
    func testHiddenPublicationDoesNotInvalidatePresentationAndShowResyncs() {
        let model = AppModel()
        model.settings.retention = .off
        model.snapshot = Snapshot(timestamp: Date(), availability: .available)
        model.snapshot.system.cpuPercent = 10
        model.fullWindowVisible = true
        XCTAssertEqual(model.overviewPresentation.system.cpuPercent, 10)
        model.fullWindowVisible = false
        let changes = OverviewChanges()
        withObservationTracking { _ = model.overviewPresentation.system.cpuPercent; _ = model.overviewStatusTitle } onChange: { changes.changed() }
        model.snapshot.system.cpuPercent = 80
        model.updateOverviewPresentation()
        XCTAssertEqual(changes.count, 0)
        XCTAssertEqual(model.overviewPresentation.system.cpuPercent, 10)
        model.fullWindowVisible = true
        XCTAssertEqual(model.overviewPresentation.system.cpuPercent, 80)
        model.snapshot.system.cpuPercent = 90
        model.updateOverviewPresentation()
        XCTAssertEqual(model.overviewPresentation.system.cpuPercent, 90)
    }
    @MainActor
    func testAcceptedRefreshPublishesVisiblePresentationAtomically() async {
        let model = AppModel()
        model.settings.retention = .off
        model.fullWindowVisible = true
        await model.refresh()
        XCTAssertTrue(model.overviewPresentation.timestamp == model.snapshot.timestamp)
        XCTAssertEqual(model.overviewPresentation.availability, model.snapshot.availability)
        XCTAssertTrue(model.overviewPresentation.applications.map(\.id) == Array(model.applications.prefix(6)).map(\.id))
        XCTAssertTrue(model.overviewPresentation.projects.map(\.id) == Array(model.projects.prefix(4)).map(\.id))
    }
    @MainActor
    func testExpiryWithoutStoreUnderEveryRetentionAndShowDoesNotResurrect() async {
        for retention in [HistoryRetention.off, .day, .week, .month] {
            let model = AppModel()
            model.settings.retention = retention
            let timestamp = Date().addingTimeInterval(-899)
            model.snapshot = Snapshot(timestamp: timestamp, availability: .available)
            model.snapshot.system.cpuPercent = 42
            model.fullWindowVisible = true
            XCTAssertEqual(model.overviewPresentation.system.cpuPercent, 42)
            model.fullWindowVisible = false
            await model.expireMemoryHistory(now: timestamp.addingTimeInterval(901))
            XCTAssertNil(model.overviewPresentation.timestamp)
            XCTAssertNil(model.overviewPresentation.system.cpuPercent)
            model.snapshot.timestamp = Date().addingTimeInterval(-901)
            model.fullWindowVisible = true
            XCTAssertNil(model.overviewPresentation.timestamp)
        }
    }
    @MainActor
    func testClearAndQuitErasePresentation() async {
        let model = AppModel()
        model.snapshot = Snapshot(timestamp: Date(), availability: .available)
        model.snapshot.system.cpuPercent = 12
        model.fullWindowVisible = true
        await model.clearHistory()
        XCTAssertNil(model.overviewPresentation.timestamp)
        XCTAssertTrue(model.overviewPresentation.applications.isEmpty)
        model.fullWindowVisible = false
        model.fullWindowVisible = true
        XCTAssertNil(model.overviewPresentation.timestamp)
        let quitting = AppModel()
        quitting.snapshot = Snapshot(timestamp: Date(), availability: .available)
        quitting.fullWindowVisible = true
        XCTAssertNotNil(quitting.overviewPresentation.timestamp)
        await quitting.prepareToQuit()
        XCTAssertNil(quitting.overviewPresentation.timestamp)
        quitting.fullWindowVisible = false
        quitting.fullWindowVisible = true
        XCTAssertNil(quitting.overviewPresentation.timestamp)
    }
    @MainActor
    func testLockAndSleepClearBeforeShowingAgain() async {
        for reason in ["screen", "sleep"] {
            let model = AppModel()
            model.settings.retention = .week
            model.snapshot = Snapshot(timestamp: Date(), availability: .available)
            model.snapshot.system.cpuPercent = 99
            model.fullWindowVisible = true
            await model.setSuspension(reason, enabled: true)
            XCTAssertNil(model.overviewPresentation.timestamp)
            model.fullWindowVisible = false
            model.fullWindowVisible = true
            XCTAssertNil(model.overviewPresentation.timestamp)
        }
    }
    func testRowsAreBoundedDisplayValuesWithExactIdentityAndUnknowns() {
        let identity = ProcessIdentity(bootID: "synthetic", pid: 1, uid: 501, startSeconds: 1, startMicroseconds: 0)
        var process = ProcessSample(identity: identity, parentPID: 0, executable: "/synthetic/node", name: "node", cpuPercent: nil, memoryBytes: 123, memoryMethod: .rss, applicationID: "app", applicationName: "App", groupingReason: "test")
        process.endpoints = [Endpoint(address: "127.0.0.1", port: 9000, family: "IPv4", scope: "loopback"), Endpoint(address: "127.0.0.1", port: 1000, family: "IPv4", scope: "loopback")]
        let groups = (0..<9).map { ResourceGroup(id: "id-\($0)", name: "Name-\($0)", processes: [process]) }
        var snapshot = Snapshot(timestamp: Date(), availability: .available)
        snapshot.system.memory.active = nil
        let value = OverviewPresentation(snapshot: snapshot, applications: groups, projects: groups)
        XCTAssertEqual(value.applications.count, 6)
        XCTAssertEqual(value.projects.count, 4)
        XCTAssertEqual(value.applications.first?.id, "id-0")
        XCTAssertEqual(value.applications.first?.processCount, 1)
        XCTAssertEqual(value.applications.first?.memoryBytes, 123)
        XCTAssertEqual(value.applications.first?.memoryMethod, .rss)
        XCTAssertNil(value.applications.first?.cpuPercent)
        XCTAssertEqual(value.projects.first?.ports, "1000, 9000")
        XCTAssertNil(value.system.memory.active)
    }
}
