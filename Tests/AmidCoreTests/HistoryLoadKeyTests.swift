import XCTest
import CryptoKit
@testable import AmidCore

private final class CountingLoadKey: HistoryKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var existingCount = 0
    private var creatingCount = 0
    let value: SymmetricKey
    var missing = false
    init(_ value: SymmetricKey) { self.value = value }
    func key() throws -> SymmetricKey { lock.withLock { creatingCount += 1 }; return value }
    func existingKey() throws -> SymmetricKey {
        lock.withLock { existingCount += 1 }
        if missing { throw HistoryStorageError.invalidKey }
        return value
    }
    var counts: (Int, Int) { lock.withLock { (existingCount, creatingCount) } }
}
final class HistoryLoadKeyTests: XCTestCase, @unchecked Sendable {
    private func fixture(_ directory: URL, key: SymmetricKey) async throws {
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider(key: key))
        let now = Date()
        await store.updateSettings(.init(retention: .week), now: now)
        for index in 0..<4 {
            let sample = Snapshot(timestamp: now.addingTimeInterval(Double(index) * 65), availability: .available)
            await store.ingest(sample)
        }
        await store.flush()
    }
    func testExistingKeyFetchedOncePerLoadAndNeverCreatedDuringLoad() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-load-key-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        try await fixture(directory, key: key)
        let provider = CountingLoadKey(key)
        let store = HistoryStore(directory: directory, keyProvider: provider)
        await store.load()
        let metadata = await store.metadata()
        XCTAssertNil(metadata.error); XCTAssertGreaterThan(metadata.aggregateCount, 1)
        XCTAssertEqual(provider.counts.0, 1); XCTAssertEqual(provider.counts.1, 0)
        await store.load()
        XCTAssertEqual(provider.counts.0, 2); XCTAssertEqual(provider.counts.1, 0)
        // Diagnostic materialization decrypts again without retaining the load key.
        let state = await store.state()
        XCTAssertNil(state.error); XCTAssertGreaterThan(state.aggregates.count, 1)
        XCTAssertEqual(provider.counts.0, 3); XCTAssertEqual(provider.counts.1, 0)
    }
    func testInvalidEnvelopeDoesNotRequestAnyKey() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-load-key-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("history.aesgcm"))
        let provider = CountingLoadKey(SymmetricKey(size: .bits256))
        let store = HistoryStore(directory: directory, keyProvider: provider)
        await store.load()
        XCTAssertEqual(provider.counts.0, 0); XCTAssertEqual(provider.counts.1, 0)
        let state = await store.state(); XCTAssertNotNil(state.error)
    }
    func testMissingOrWrongKeyAndLaterSegmentTamperingFailWithoutCreationOrManifestReplacement() async throws {
        for failure in ["missing", "wrong", "segment"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-load-key-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let key = SymmetricKey(size: .bits256)
            try await fixture(directory, key: key)
            let manifest = try Data(contentsOf: directory.appendingPathComponent("history.aesgcm"))
            let provider = CountingLoadKey(failure == "wrong" ? SymmetricKey(size: .bits256) : key)
            provider.missing = failure == "missing"
            if failure == "segment" {
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("bucket-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                let last = try XCTUnwrap(files.last)
                var data = try Data(contentsOf: last); data[data.count - 1] ^= 1
                try data.write(to: last)
            }
            let store = HistoryStore(directory: directory, keyProvider: provider)
            await store.load(); let state = await store.state()
            XCTAssertNotNil(state.error); XCTAssertTrue(state.aggregates.isEmpty)
            XCTAssertEqual(provider.counts.0, 1); XCTAssertEqual(provider.counts.1, 0)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.aesgcm")), manifest)
        }
    }
}
