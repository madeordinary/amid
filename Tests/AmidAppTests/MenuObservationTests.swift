import XCTest
import Observation
import Foundation
import AmidCore
@testable import AmidApp

private final class ChangeCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func changed() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

final class MenuObservationTests: XCTestCase {
    @MainActor
    func testDefaultMenuAttentionDoesNotObserveUnchangedSnapshots() {
        let model = AppModel()
        var sample = Snapshot.empty
        sample.availability = .available
        sample.system.memory.pressure = .normal
        model.snapshot = sample
        let changes = ChangeCount()
        withObservationTracking { _ = model.pressureAttention } onChange: { changes.changed() }
        sample.system.cpuPercent = 73
        sample.enumeratedCount = 100
        model.snapshot = sample
        XCTAssertFalse(model.pressureAttention)
        XCTAssertEqual(changes.count, 0, "Unchanged menu attention must not invalidate the scene for new process metrics.")
    }

    @MainActor
    func testAttentionTracksOnlyPredicateTransitionsIncludingNestedWrites() {
        let model = AppModel()
        model.snapshot.availability = .available
        let warning = ChangeCount()
        withObservationTracking { _ = model.pressureAttention } onChange: { warning.changed() }
        model.snapshot.system.memory.pressure = .warning
        XCTAssertTrue(model.pressureAttention)
        XCTAssertEqual(warning.count, 1)
        let stillAttention = ChangeCount()
        withObservationTracking { _ = model.pressureAttention } onChange: { stillAttention.changed() }
        model.snapshot.system.memory.pressure = .critical
        XCTAssertTrue(model.pressureAttention)
        XCTAssertEqual(stillAttention.count, 0)
        let unavailable = ChangeCount()
        withObservationTracking { _ = model.pressureAttention } onChange: { unavailable.changed() }
        model.snapshot.availability = .unavailable
        XCTAssertFalse(model.pressureAttention)
        XCTAssertEqual(unavailable.count, 1)
        model.snapshot = .empty
        XCTAssertFalse(model.pressureAttention)
    }

    @MainActor
    func testNumericMenuStillUpdatesFromNewMeasurements() {
        let model = AppModel()
        model.settings.numericMenuMetric = "cpu"
        model.snapshot.system.cpuPercent = 10
        let oldTitle = model.menuTitle
        let changes = ChangeCount()
        withObservationTracking { _ = model.menuTitle } onChange: { changes.changed() }
        model.snapshot.system.cpuPercent = 80
        XCTAssertNotEqual(model.menuTitle, oldTitle)
        XCTAssertEqual(changes.count, 1)
        model.settings.numericMenuMetric = "memory"
        model.snapshot.system.memory.pressure = .warning
        XCTAssertEqual(model.menuTitle, "Warning")
    }

    @MainActor
    func testClearHistoryResetsAttention() async {
        let model = AppModel()
        model.snapshot.availability = .available
        model.snapshot.system.memory.pressure = .critical
        XCTAssertTrue(model.pressureAttention)
        await model.clearHistory()
        XCTAssertFalse(model.pressureAttention)
    }
}
