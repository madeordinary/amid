import XCTest
import CryptoKit
@testable import AmidCore

final class HistoryPersistenceIndexTests: XCTestCase, @unchecked Sendable {
    private func location() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("amid-owned-index-" + UUID().uuidString) }
    private func snapshot(_ time: Date, apps: [String]) -> Snapshot {
        let processes = apps.enumerated().map { index, app in
            ProcessSample(identity: .init(bootID: "owned-index", pid: Int32(100 + index), uid: 501, startSeconds: 1, startMicroseconds: 0),
                executable: "/owned/" + app, name: app, cpuPercent: 1, memoryBytes: 1024, memoryMethod: .footprint,
                projectPath: "/private/tmp/owned-index-" + app, applicationID: app, applicationName: app, groupingReason: "fixture")
        }
        return Snapshot(timestamp: time, processes: processes, cadence: 5, expectedCadence: 5, availability: .available)
    }
    private func values(_ state: HistoryState) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Dictionary(uniqueKeysWithValues: state.aggregates.map { ($0.id, $0) }))
    }
    private func chronological(_ state: HistoryState) -> Bool {
        !state.aggregates.indices.dropFirst().contains { state.aggregates[$0-1].start > state.aggregates[$0].start }
    }
    func testUnchangedFlushPreservesOrderValuesAndSubsequentIndexes() async throws {
        let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
        let key = EphemeralHistoryKeyProvider(); let store = HistoryStore(directory: directory, keyProvider: key)
        let base = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        await store.updateSettings(.init(retention: .week), now: base)
        await store.ingest(snapshot(base.addingTimeInterval(1), apps: ["a", "b", "c"]))
        await store.ingest(snapshot(base.addingTimeInterval(61), apps: ["a", "b", "c"]))
        let before = await store.state(); let ids = before.aggregates.map(\.id); let expected = try values(before)
        for _ in 0..<8 {
            await store.flush(); let state = await store.state()
            XCTAssertNil(state.error); XCTAssertEqual(state.aggregates.map(\.id), ids)
            XCTAssertEqual(try values(state), expected)
        }
        await store.ingest(snapshot(base.addingTimeInterval(66), apps: ["a"]))
        await store.ingest(snapshot(base.addingTimeInterval(71), apps: ["d"]))
        await store.flush(); let updated = await store.state()
        XCTAssertEqual(updated.aggregates.first { $0.entityID == "app:a" && $0.start == base.addingTimeInterval(60) }?.samples, 2)
        XCTAssertEqual(updated.aggregates.filter { $0.entityID == "app:d" }.count, 1)
        XCTAssertTrue(chronological(updated))
        let loaded = HistoryStore(directory: directory, keyProvider: key); await loaded.load()
        let reloaded = await loaded.state(); XCTAssertNil(reloaded.error)
        XCTAssertEqual(try values(reloaded), try values(updated))
    }
    func testCapPruningRebuildsIndexAndReloadsSurvivingValues() async throws {
        let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
        let key = EphemeralHistoryKeyProvider(); let store = HistoryStore(directory: directory, keyProvider: key, maxBytes: 5000)
        let base = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        await store.updateSettings(.init(retention: .week), now: base)
        for minute in 0..<12 { await store.ingest(snapshot(base.addingTimeInterval(Double(minute) * 60 + 1), apps: ["a", "b"])) }
        let pruned = await store.state()
        XCTAssertNil(pruned.error); XCTAssertTrue(pruned.shortenedByCap); XCTAssertLessThanOrEqual(pruned.storageBytes, 5000)
        XCTAssertFalse(pruned.aggregates.contains { $0.start == base })
        let latest = base.addingTimeInterval(11 * 60)
        let before = try XCTUnwrap(pruned.aggregates.first { $0.entityID == "app:a" && $0.start == latest })
        await store.ingest(snapshot(latest.addingTimeInterval(6), apps: ["a"]))
        let updated = await store.state()
        let after = try XCTUnwrap(updated.aggregates.first { $0.id == before.id })
        XCTAssertEqual(after.samples, before.samples + 1); XCTAssertEqual(after.cpu.count, before.cpu.count + 1)
        XCTAssertEqual(after.cpu.sum, before.cpu.sum + 1)
        await store.flush(); let persisted = await store.state()
        let loaded = HistoryStore(directory: directory, keyProvider: key, maxBytes: 5000); await loaded.load()
        let reloaded = await loaded.state(); XCTAssertNil(reloaded.error)
        XCTAssertEqual(try values(reloaded), try values(persisted))
    }
    func testExclusionsOffAndClearKeepIndexesConsistent() async throws {
        let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        let base = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        await store.updateSettings(.init(retention: .week), now: base)
        await store.ingest(snapshot(base.addingTimeInterval(1), apps: ["a", "b"]))
        await store.updateSettings(.init(retention: .week, excludedApplications: ["a"]), now: base.addingTimeInterval(2))
        await store.ingest(snapshot(base.addingTimeInterval(6), apps: ["a", "b"]))
        var state = await store.state()
        XCTAssertFalse(state.aggregates.contains { $0.entityID == "app:a" })
        XCTAssertEqual(state.aggregates.first { $0.entityID == "app:b" }?.samples, 2)
        await store.updateSettings(.init(retention: .off), now: base.addingTimeInterval(7)); await store.flush()
        state = await store.state(); XCTAssertTrue(state.aggregates.isEmpty)
        await store.clear(); await store.updateSettings(.init(retention: .week), now: base.addingTimeInterval(8))
        await store.ingest(snapshot(base.addingTimeInterval(11), apps: ["a"]))
        await store.ingest(snapshot(base.addingTimeInterval(16), apps: ["a"]))
        await store.flush(); state = await store.state(); XCTAssertNil(state.error)
        XCTAssertEqual(state.aggregates.first { $0.entityID == "app:a" }?.samples, 2)
        XCTAssertFalse(state.aggregates.contains { $0.entityID == "app:b" })
    }
    func testOlderMinuteNewEntityAfterClearMemorySortsAndUpdatesCorrectBucket() async throws {
        let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        let base = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        await store.updateSettings(.init(retention: .week), now: base)
        await store.ingest(snapshot(base.addingTimeInterval(3601), apps: ["a"]))
        await store.clearMemory()
        await store.ingest(snapshot(base.addingTimeInterval(1), apps: ["a"]))
        await store.ingest(snapshot(base.addingTimeInterval(6), apps: ["b"]))
        let unordered = await store.state(); XCTAssertFalse(chronological(unordered))
        await store.flush(); let sorted = await store.state(); XCTAssertTrue(chronological(sorted))
        let target = try XCTUnwrap(sorted.aggregates.first { $0.entityID == "app:b" && $0.start == base })
        await store.ingest(snapshot(base.addingTimeInterval(11), apps: ["b"]))
        let updated = await store.state()
        XCTAssertEqual(updated.aggregates.first { $0.id == target.id }?.samples, target.samples + 1)
        XCTAssertEqual(updated.aggregates.filter { $0.entityID == "app:b" }.count, 1)
        XCTAssertEqual(updated.aggregates.first { $0.entityID == "app:a" && $0.start == base.addingTimeInterval(3600) }?.samples, 1)
    }
}

extension HistoryPersistenceIndexTests {
    private struct FixtureArchive: Codable {
        var version: Int = 3
        var settings = HistorySettings(retention: .week)
        var aggregates: [HistoryAggregate] = []
        var alerts: [AlertEvent] = []
        var actions: [ActionRecord] = []
        var shortenedByCap = false
        var segmentFiles: [String]?
    }
    private func fixtureRow(_ entity: String, start: Date, resolution: Double = 60) -> HistoryAggregate {
        var row = HistoryAggregate(entityID: entity, name: entity, start: start, resolution: resolution)
        row.samples = 2; row.observedSeconds = 10; row.cpuObservedSeconds = 10; row.memoryObservedSeconds = 10
        row.cpu.add(4); row.memory.add(1024); row.memoryMethods = [.footprint]; row.cadences = [5]
        return row
    }
    private func sealed(_ clear: Data, key: SymmetricKey) throws -> Data {
        Data("AMID".utf8) + (try AES.GCM.seal(clear, using: key, authenticating: Data("AMID".utf8)).combined!)
    }
    private func clear(_ file: URL, key: SymmetricKey) throws -> Data {
        let data = try Data(contentsOf: file)
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(4)), using: key, authenticating: Data("AMID".utf8))
    }
    private func writeFixture(_ directory: URL, key: SymmetricKey, groups: [[HistoryAggregate]], inline: [HistoryAggregate] = [],
                              version: Int = 3, excluded: Set<String> = [], mutate: ((inout [[String: Any]]) -> Void)? = nil) throws -> [String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var files: [String] = []
        for group in groups {
            let first = try XCTUnwrap(group.first)
            let name = "bucket-\(Int64(first.start.timeIntervalSince1970))-\(Int(first.resolution))-owned-fixture.aesgcm"
            var data = try JSONEncoder().encode(group)
            if let mutate {
                var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
                mutate(&rows); data = try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys)
            }
            try sealed(data, key: key).write(to: directory.appendingPathComponent(name)); files.append(name)
        }
        let archive = FixtureArchive(version: version, settings: .init(retention: .week, excludedApplications: excluded),
            aggregates: inline, segmentFiles: version == 3 ? files : nil)
        try sealed(JSONEncoder().encode(archive), key: key).write(to: directory.appendingPathComponent("history.aesgcm"))
        return files
    }
    private func manifest(_ directory: URL, key: SymmetricKey) throws -> FixtureArchive {
        try JSONDecoder().decode(FixtureArchive.self, from: clear(directory.appendingPathComponent("history.aesgcm"), key: key))
    }
    private func fixedStore(_ directory: URL, key: EphemeralHistoryKeyProvider, now: Date) -> HistoryStore {
        HistoryStore(directory: directory, keyProvider: key, commitObserver: { _ in }, loadReferenceDate: now)
    }
    func testAuthenticatedCurrentSegmentsAreReusedOnLoadAndReload() async throws {
        let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
        let key = EphemeralHistoryKeyProvider(); let now = Date()
        let minute = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60)
        let hour = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 3600) * 3600)
        let rows = [[fixtureRow("app:a", start: minute.addingTimeInterval(-600)), fixtureRow("app:b", start: minute.addingTimeInterval(-600))],
                    [fixtureRow("app:c", start: hour.addingTimeInterval(-30 * 3600), resolution: 3600)]]
        let files = try writeFixture(directory, key: key.key(), groups: rows)
        let hashes = try Dictionary(uniqueKeysWithValues: files.map { ($0, SHA256.hash(data: try Data(contentsOf: directory.appendingPathComponent($0))).description) })
        let store = fixedStore(directory, key: key, now: now); await store.load()
        let state = await store.state(); XCTAssertNil(state.error); XCTAssertEqual(state.aggregates.count, 3)
        XCTAssertEqual(Set(try manifest(directory, key: key.key()).segmentFiles ?? []), Set(files))
        for name in files where FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: directory.appendingPathComponent(name))).description, hashes[name])
        }
        let reloaded = fixedStore(directory, key: key, now: now); await reloaded.load()
        let reloadedState = await reloaded.state()
        XCTAssertEqual(try values(reloadedState), try values(state))
        XCTAssertEqual(Set(try manifest(directory, key: key.key()).segmentFiles ?? []), Set(files))
        await reloaded.ingest(snapshot(minute.addingTimeInterval(1), apps: ["a"]))
        let updated = await reloaded.state()
        XCTAssertEqual(updated.aggregates.first { $0.entityID == "app:a" && $0.start == minute }?.samples, 1)
    }
    func testInlineSchemaThreeRowsPersistEvenWithSharedSegmentBucket() async throws {
        for sharedBucket in [false, true] {
            let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
            let key = EphemeralHistoryKeyProvider(); let now = Date()
            let minute = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60 - 600)
            let inline = fixtureRow("app:inline", start: sharedBucket ? minute : minute.addingTimeInterval(-60))
            let segmented = fixtureRow("app:segment", start: minute)
            _ = try writeFixture(directory, key: key.key(), groups: [[segmented]], inline: [inline])
            let store = fixedStore(directory, key: key, now: now); await store.load()
            let state = await store.state(); XCTAssertNil(state.error); XCTAssertEqual(state.aggregates.count, 2)
            XCTAssertTrue(try manifest(directory, key: key.key()).aggregates.isEmpty)
            let reload = fixedStore(directory, key: key, now: now); await reload.load()
            let next = await reload.state(); XCTAssertNil(next.error); XCTAssertEqual(try values(next), try values(state))
        }
    }
    func testDefaultedMissingAndNullFieldsArePersistedExplicitly() async throws {
        let fields = ["load1", "load5", "load15", "swap", "pressureStates", "memoryMethods", "cpuObservedSeconds", "memoryObservedSeconds", "metricCoverageEstimated"]
        for field in fields { for null in [false, true] {
            let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
            let key = EphemeralHistoryKeyProvider(); let now = Date()
            let row = fixtureRow("app:legacy", start: Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60 - 600))
            let files = try writeFixture(directory, key: key.key(), groups: [[row]], mutate: { rows in
                if null { rows[0][field] = NSNull() } else { rows[0].removeValue(forKey: field) }
            })
            let store = fixedStore(directory, key: key, now: now); await store.load()
            let state = await store.state(); XCTAssertNil(state.error)
            let paths = try XCTUnwrap(manifest(directory, key: key.key()).segmentFiles)
            XCTAssertNotEqual(paths, files, "Missing/null field must migrate: \(field)")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: clear(directory.appendingPathComponent(try XCTUnwrap(paths.first)), key: key.key())) as? [[String: Any]])
            XCTAssertNotNil(json.first?[field]); XCTAssertFalse(json.first?[field] is NSNull)
            XCTAssertNil(json.first?["requiresPersistenceMigration"])
            let reload = fixedStore(directory, key: key, now: now); await reload.load()
            let reloadedState = await reload.state()
            XCTAssertEqual(try values(reloadedState), try values(state))
        } }
    }
    func testExclusionsRewriteOnlyAffectedGeneration() async throws {
        let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
        let key = EphemeralHistoryKeyProvider(); let now = Date()
        let minute = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60 - 600)
        let files = try writeFixture(directory, key: key.key(), groups: [
            [fixtureRow("app:a", start: minute), fixtureRow("app:b", start: minute)],
            [fixtureRow("app:c", start: minute.addingTimeInterval(-60))],
            [fixtureRow("app:a", start: minute.addingTimeInterval(-120))]], excluded: ["a"])
        let store = fixedStore(directory, key: key, now: now); await store.load()
        let state = await store.state(); XCTAssertNil(state.error); XCTAssertEqual(Set(state.aggregates.map(\.entityID)), ["app:b", "app:c"])
        let paths = try XCTUnwrap(manifest(directory, key: key.key()).segmentFiles)
        XCTAssertTrue(paths.contains(files[1])); XCTAssertFalse(paths.contains(files[0])); XCTAssertFalse(paths.contains(files[2]))
        let reload = fixedStore(directory, key: key, now: now); await reload.load()
        let reloadedState = await reload.state()
        XCTAssertEqual(try values(reloadedState), try values(state))
    }
    func testMinuteRollupMergesExistingHourAndPersistsOnce() async throws {
        let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
        let key = EphemeralHistoryKeyProvider(); let now = Date()
        let hour = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 3600) * 3600 - 30 * 3600)
        let files = try writeFixture(directory, key: key.key(), groups: [[fixtureRow("app:a", start: hour, resolution: 3600)], [fixtureRow("app:a", start: hour.addingTimeInterval(120))]])
        let store = fixedStore(directory, key: key, now: now); await store.load()
        let state = await store.state(); XCTAssertNil(state.error)
        let merged = try XCTUnwrap(state.aggregates.first); XCTAssertEqual(state.aggregates.count, 1)
        XCTAssertEqual(merged.start, hour); XCTAssertEqual(merged.resolution, 3600)
        XCTAssertEqual(merged.samples, 4); XCTAssertEqual(merged.cpu.count, 2); XCTAssertEqual(merged.cpu.sum, 8)
        XCTAssertEqual(merged.observedSeconds, 20); XCTAssertEqual(merged.cpuObservedSeconds, 20); XCTAssertEqual(merged.memoryMethods, [.footprint])
        let paths = try XCTUnwrap(manifest(directory, key: key.key()).segmentFiles)
        XCTAssertEqual(paths.count, 1); XCTAssertFalse(paths.contains(files[0])); XCTAssertFalse(paths.contains(files[1]))
        let reload = fixedStore(directory, key: key, now: now); await reload.load()
        let reloadedState = await reload.state()
        XCTAssertEqual(try values(reloadedState), try values(state))
    }
    func testNoncanonicalOlderRowsAndSignedZerosAreRepersisted() async throws {
        let scalars: [WritableKeyPath<HistoryAggregate, Double>] = [\.cpu.sum, \.memory.sum, \.load1.sum, \.load5.sum, \.load15.sum, \.swap.sum, \.observedSeconds, \.gapSeconds, \.cpuObservedSeconds, \.memoryObservedSeconds]
        for index in 0..<(2 + scalars.count) {
            let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
            let key = EphemeralHistoryKeyProvider(); let now = Date()
            let hour = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 3600) * 3600 - 30 * 3600)
            var row = fixtureRow("app:a", start: hour, resolution: 3600)
            if index == 0 { row.start = hour.addingTimeInterval(90); row.resolution = 120 }
            else if index == 1 { row.start = hour.addingTimeInterval(30) }
            else { row[keyPath: scalars[index-2]] = -0.0 }
            let files = try writeFixture(directory, key: key.key(), groups: [[row]])
            let store = fixedStore(directory, key: key, now: now); await store.load()
            let state = await store.state(); XCTAssertNil(state.error)
            let changed = try XCTUnwrap(state.aggregates.first)
            XCTAssertEqual(changed.start, hour); XCTAssertEqual(changed.resolution, 3600)
            if index >= 2 { XCTAssertEqual(changed[keyPath: scalars[index-2]].sign, .plus) }
            XCTAssertNotEqual(try manifest(directory, key: key.key()).segmentFiles, files)
            let reload = fixedStore(directory, key: key, now: now); await reload.load()
            let reloadedState = await reload.state()
            XCTAssertEqual(try values(reloadedState), try values(state))
        }
    }
    func testLegacyArchivesStillMigrateAllInlineRows() async throws {
        for version in [1, 2] {
            let directory = location(); defer { try? FileManager.default.removeItem(at: directory) }
            let key = EphemeralHistoryKeyProvider(); let now = Date()
            let row = fixtureRow("app:a", start: Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60 - 600))
            _ = try writeFixture(directory, key: key.key(), groups: [], inline: [row], version: version)
            let store = fixedStore(directory, key: key, now: now); await store.load()
            let state = await store.state(); XCTAssertNil(state.error); XCTAssertEqual(state.aggregates.count, 1)
            let migrated = try manifest(directory, key: key.key()); XCTAssertEqual(migrated.version, 3)
            XCTAssertTrue(migrated.aggregates.isEmpty); XCTAssertEqual(migrated.segmentFiles?.count, 1)
            let reload = fixedStore(directory, key: key, now: now); await reload.load()
            let reloadedState = await reload.state()
            XCTAssertEqual(try values(reloadedState), try values(state))
        }
    }
}
