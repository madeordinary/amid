import XCTest
@testable import AmidCore
@testable import AmidApp

final class StopLifecycleTests: XCTestCase {
    @MainActor
    func testClearDuringConfirmationCannotRepopulateActionHistory() async throws {
        for retention in [HistoryRetention.off, .week] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-stop-clear-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
            await store.updateSettings(.init(retention: retention))
            let model = AppModel(store: store)
            model.settings.retention = retention
            let process = ProcessSample(identity: .init(bootID: "test", pid: 123, uid: 501, startSeconds: 1, startMicroseconds: 0), executable: "/synthetic", name: "Synthetic", applicationID: "synthetic", applicationName: "Synthetic", groupingReason: "Test")
            let preview = StopPreview.unavailable(process: process, reason: "Synthetic confirmation")
            let result = await model.finishStop(preview, confirmed: true) {
                await model.clearHistory()
                return StopResult(targetID: process.id, validation: .stale, message: "Observation ended.", signalsSent: 0)
            }
            XCTAssertEqual(result.signalsSent, 0)
            let state = await store.state()
            XCTAssertTrue(state.actions.isEmpty)
            XCTAssertTrue(state.recentSnapshots.isEmpty)
            XCTAssertTrue(model.snapshot.processes.isEmpty)
        }
    }
    @MainActor
    func testSuspensionDuringConfirmationDoesNotRetainTargetRecord() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-stop-suspend-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        await store.updateSettings(.init(retention: .off))
        let model = AppModel(store: store)
        model.settings.retention = .off
        let process = ProcessSample(identity: .init(bootID: "test", pid: 123, uid: 501, startSeconds: 1, startMicroseconds: 0), executable: "/synthetic", name: "Synthetic", applicationID: "synthetic", applicationName: "Synthetic", groupingReason: "Test")
        let preview = StopPreview.unavailable(process: process, reason: "Synthetic confirmation")
        let result = await model.finishStop(preview, confirmed: true) {
            model.sleeping = true
            await store.clearMemory()
            return StopResult(targetID: process.id, validation: .stale, message: "Observation ended after signal.", signalsSent: 1)
        }
        XCTAssertEqual(result.signalsSent, 1)
        let state = await store.state()
        XCTAssertTrue(state.actions.isEmpty)
    }
}
