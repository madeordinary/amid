import XCTest
import Foundation
import CryptoKit
import AmidCore
@testable import AmidApp

/// Holds the first existing-key read, which happens inside HistoryStore.load(), until the test opens it.
private final class LoadBarrierKeyProvider: HistoryKeyProvider, @unchecked Sendable {
    private let base: EphemeralHistoryKeyProvider
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var armed = true
    private var reached = false
    init(key: SymmetricKey) { base = EphemeralHistoryKeyProvider(key: key) }
    func key() throws -> SymmetricKey { try base.key() }
    func existingKey() throws -> SymmetricKey {
        let hold = lock.withLock { () -> Bool in
            guard armed else { return false }
            armed = false; reached = true; return true
        }
        if hold { gate.wait() }
        return try base.existingKey()
    }
    var loadReached: Bool { lock.withLock { reached } }
    func open() { gate.signal() }
}

@MainActor private final class Flag { var value = false }

final class SettingsLoadTests: XCTestCase {
    private static let saved = HistorySettings(retention: .week, aliases: ["app:first": "Renamed"])

    /// A previous session's store: saved preferences plus persisted aggregate buckets.
    private static func seedStore(_ directory: URL, key: SymmetricKey) async throws {
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider(key: key))
        let now = Date().addingTimeInterval(-120)
        await store.updateSettings(saved, now: now)
        let process = ProcessSample(identity: .init(bootID: "synthetic", pid: 1, uid: 501, startSeconds: 1, startMicroseconds: 0),
                                    executable: "/synthetic/first", name: "first", cpuPercent: 1, memoryBytes: 1024,
                                    applicationID: "first", applicationName: "First", groupingReason: "Synthetic test")
        await store.ingest(Snapshot(timestamp: now, processes: [process], availability: .available))
        await store.ingest(Snapshot(timestamp: now.addingTimeInterval(65), availability: .available))
        await store.flush()
        let state = await store.metadata()
        XCTAssertNil(state.error)
        XCTAssertGreaterThan(state.aggregateCount, 0)
    }

    private static func reopened(_ directory: URL, key: SymmetricKey) async -> HistoryMetadata {
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider(key: key))
        await store.load()
        return await store.metadata()
    }

    @MainActor
    private func waitUntilLoadIsHeld(_ barrier: LoadBarrierKeyProvider) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !barrier.loadReached && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(barrier.loadReached)
    }

    @MainActor
    func testPauseDuringLoadCannotReplaceSavedSettingsOrDeleteHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-settings-load-pause-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        try await Self.seedStore(directory, key: key)
        let barrier = LoadBarrierKeyProvider(key: key)
        let store = HistoryStore(directory: directory, keyProvider: barrier)
        let model = AppModel(store: store)
        let loading = Task { await model.retryStore() }
        await waitUntilLoadIsHeld(barrier)
        XCTAssertTrue(model.settingsLoading)
        // The main-window Pause control is reachable while saved settings are still loading.
        model.togglePause()
        barrier.open()
        await loading.value
        XCTAssertEqual(model.settings.retention, .week)
        XCTAssertEqual(model.settings.aliases["app:first"], "Renamed")
        XCTAssertFalse(model.paused)
        // The next retention choice (onboarding or Settings) must not commit an emptied catalog.
        model.settings.retention = .week
        await model.saveSettings()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            let current = await store.metadata().settings
            if current.retention == .week && current.paused == model.paused { break }
            await Task.yield()
        }
        let state = await Self.reopened(directory, key: key)
        XCTAssertNil(state.error)
        XCTAssertEqual(state.settings.retention, .week)
        XCTAssertEqual(state.settings.aliases["app:first"], "Renamed")
        XCTAssertGreaterThan(state.aggregateCount, 0)
    }

    @MainActor
    func testSettingsDraftSavedDuringLoadIsNotPersistedOverSavedSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-settings-load-draft-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        try await Self.seedStore(directory, key: key)
        let barrier = LoadBarrierKeyProvider(key: key)
        let store = HistoryStore(directory: directory, keyProvider: barrier)
        let model = AppModel(store: store)
        let loading = Task { await model.retryStore() }
        await waitUntilLoadIsHeld(barrier)
        XCTAssertTrue(model.settingsLoading)
        // Settings form bindings mutate the draft directly, then save.
        model.settings.retention = .day
        model.settings.aliases["app:first"] = "Draft"
        let saveReturned = Flag()
        let save = Task { await model.saveSettings(); saveReturned.value = true }
        // The save must return while the load is still held; one that reached the store would wait behind it.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !saveReturned.value && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(saveReturned.value)
        barrier.open()
        await loading.value
        await save.value
        XCTAssertEqual(model.settings.retention, .week)
        XCTAssertEqual(model.settings.aliases["app:first"], "Renamed")
        let current = await store.metadata().settings
        XCTAssertEqual(current.retention, .week)
        XCTAssertEqual(current.aliases["app:first"], "Renamed")
        let state = await Self.reopened(directory, key: key)
        XCTAssertNil(state.error)
        XCTAssertEqual(state.settings.retention, .week)
        XCTAssertEqual(state.settings.aliases["app:first"], "Renamed")
        XCTAssertGreaterThan(state.aggregateCount, 0)
    }
}
