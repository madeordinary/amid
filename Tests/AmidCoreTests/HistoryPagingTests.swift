import XCTest
import CryptoKit
@testable import AmidCore

final class HistoryPagingTests: XCTestCase, @unchecked Sendable {
    private struct Archive: Encodable {
        var version = 3
        var settings = HistorySettings(retention: .week)
        var aggregates: [HistoryAggregate] = []
        var alerts: [AlertEvent] = []
        var actions: [ActionRecord] = []
        var shortenedByCap = false
        var segmentFiles: [String]
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("amid-owned-paging-" + UUID().uuidString) }
    private func seal<T: Encodable>(_ value: T, key: SymmetricKey) throws -> Data {
        Data("AMID".utf8) + (try AES.GCM.seal(JSONEncoder().encode(value),using:key,authenticating:Data("AMID".utf8)).combined!)
    }
    private func fixture(_ directory: URL, key: SymmetricKey, base: Date, buckets: Int, entities: Int = 4) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var paths: [String] = []
        for index in 0..<buckets {
            let start = base.addingTimeInterval(Double(index) * 60)
            let path = "bucket-\(Int64(start.timeIntervalSince1970))-60-paging.aesgcm"
            var rows: [HistoryAggregate] = []
            for entity in 0..<entities {
                var row = HistoryAggregate(entityID:entity == 0 ? "system" : "app:synthetic.\(entity)",name:"Synthetic \(entity)",start:start,resolution:60)
                row.samples = 2; row.observedSeconds = 10; row.cpuObservedSeconds = 10; row.cpu.add(Double(index)); row.cadences = [5]
                rows.append(row)
            }
            try seal(rows,key:key).write(to:directory.appendingPathComponent(path)); paths.append(path)
        }
        try seal(Archive(segmentFiles:paths),key:key).write(to:directory.appendingPathComponent("history.aesgcm"))
    }
    private func sample(_ date: Date) -> Snapshot {
        var result = Snapshot.empty; result.timestamp = date; result.availability = .available; result.cadence = 5; result.expectedCadence = 5
        return result
    }
    func testLoadedCatalogHasNoResidentArchiveAndDiagnosticRowsRemainComplete() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let provider = EphemeralHistoryKeyProvider(); let now = Date(); let base = Date(timeIntervalSince1970:floor(now.timeIntervalSince1970 / 60) * 60 - 200 * 60)
        try fixture(dir,key:provider.key(),base:base,buckets:200)
        let store = HistoryStore(directory:dir,keyProvider:provider); await store.load()
        let metadata = await store.metadata(); let diagnostics = await store.pagingDiagnostics()
        XCTAssertNil(metadata.error); XCTAssertEqual(metadata.aggregateCount,800)
        XCTAssertEqual(diagnostics.residentRows,0); XCTAssertEqual(diagnostics.buckets,200)
        let names = await store.entities(); XCTAssertEqual(names.count,4); XCTAssertEqual(names.first?.id,"system")
        let state = await store.state(); XCTAssertEqual(state.aggregates.count,800)
        let after = await store.pagingDiagnostics(); XCTAssertEqual(after.residentRows,0)
        XCTAssertTrue(state.aggregates.allSatisfy { $0.memory.count == 0 && $0.memory.average == nil })
    }
    func testMovingBoundsAndCurrentMinuteReuseImmutableQueryGenerations() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let provider = EphemeralHistoryKeyProvider(); let now = Date(); let base = Date(timeIntervalSince1970:floor(now.timeIntervalSince1970 / 60) * 60 - 120 * 60)
        try fixture(dir,key:provider.key(),base:base,buckets:120)
        let store = HistoryStore(directory:dir,keyProvider:provider); await store.load()
        let first = await store.history(entityID:"system",since:base.addingTimeInterval(-1),until:now)
        XCTAssertNil(first.error); XCTAssertEqual(first.points.count,120)
        let reads = await store.pagingDiagnostics().bucketReads
        let moving = await store.history(entityID:"system",since:base.addingTimeInterval(1),until:now.addingTimeInterval(2))
        XCTAssertEqual(moving.points.count,119)
        let afterMoving = await store.pagingDiagnostics(); XCTAssertEqual(afterMoving.bucketReads,reads)
        await store.ingest(sample(now.addingTimeInterval(5)))
        let beforeRefresh = await store.pagingDiagnostics().bucketReads
        let changed = await store.history(entityID:"system",since:base.addingTimeInterval(3),until:now.addingTimeInterval(7))
        XCTAssertNil(changed.error); XCTAssertEqual(changed.points.count,120)
        let afterRefresh = await store.pagingDiagnostics(); XCTAssertEqual(afterRefresh.bucketReads,beforeRefresh)
        XCTAssertEqual(first.points.count,120,"Previously published query remains immutable.")
        await store.clearQueryCache(); let cleared = await store.pagingDiagnostics(); XCTAssertEqual(cleared.cachedPoints,0)
    }
    func testInclusiveEndpointsNoPointTruncationAndInvalidRangeDoesNotPoisonStore() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let provider = EphemeralHistoryKeyProvider(); let base = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 60) * 60)
        try fixture(dir,key:provider.key(),base:base,buckets:2140,entities:1)
        let store = HistoryStore(directory:dir,keyProvider:provider); await store.load()
        let all = await store.history(entityID:"system",since:base,until:base.addingTimeInterval(2139 * 60))
        XCTAssertNil(all.error); XCTAssertEqual(all.points.count,2140)
        let one = await store.history(entityID:"system",since:base,until:base)
        XCTAssertEqual(one.points.count,1)
        let invalid = await store.history(entityID:"system",since:base.addingTimeInterval(1),until:base)
        XCTAssertNotNil(invalid.error); XCTAssertTrue(invalid.points.isEmpty)
        let metadata = await store.metadata(); XCTAssertNil(metadata.error); XCTAssertEqual(metadata.aggregateCount,2140)
    }
    func testMixedFractionalResolutionOldBucketNormalizesEveryRow() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let provider = EphemeralHistoryKeyProvider(); let key = try provider.key()
        let hour = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 3600) * 3600 - 30 * 3600)
        let path = "bucket-\(Int64(hour.timeIntervalSince1970))-3600-fractional.aesgcm"
        var a = HistoryAggregate(entityID:"app:a",name:"First",start:hour,resolution:3600)
        a.samples = 1; a.cpu.add(4); a.cadences = [5]
        var b = HistoryAggregate(entityID:"app:b",name:"Second",start:hour.addingTimeInterval(0.5),resolution:3600.5)
        b.samples = 1; b.memory.add(123); b.memoryMethods = [.footprint]; b.cadences = [10]
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try seal([a,b],key:key).write(to:dir.appendingPathComponent(path))
        try seal(Archive(segmentFiles:[path]),key:key).write(to:dir.appendingPathComponent("history.aesgcm"))
        let store = HistoryStore(directory:dir,keyProvider:provider); await store.load()
        let state = await store.state(); XCTAssertNil(state.error)
        XCTAssertEqual(state.aggregates.count,2)
        XCTAssertTrue(state.aggregates.allSatisfy { $0.start == hour && $0.resolution == 3600 })
        XCTAssertEqual(state.aggregates.first { $0.entityID == "app:a" }?.cpu.sum,4)
        XCTAssertEqual(state.aggregates.first { $0.entityID == "app:b" }?.memory.sum,123)
        XCTAssertEqual(state.aggregates.first { $0.entityID == "app:b" }?.memoryMethods,[.footprint])
    }
    func testEntityDirectoryKeepsLaterStoredNameAfterOlderObservation() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider())
        let base = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 60) * 60)
        await store.updateSettings(.init(retention:.week),now:base)
        func observed(_ time: Date, name: String) -> Snapshot {
            let process = ProcessSample(identity:.init(bootID:"owned",pid:1,uid:1,startSeconds:1,startMicroseconds:0),executable:"/owned/application",name:name,applicationID:"owned.app",applicationName:name,groupingReason:"fixture")
            return Snapshot(timestamp:time,processes:[process],cadence:5,expectedCadence:5,availability:.available)
        }
        await store.ingest(observed(base.addingTimeInterval(3601),name:"Later name"))
        await store.clearMemory()
        await store.ingest(observed(base.addingTimeInterval(1),name:"Earlier name"))
        let names = await store.entities()
        XCTAssertEqual(names.first { $0.id == "app:owned.app" }?.name,"Later name")
    }
    private final class CommitFailure: @unchecked Sendable {
        private let lock = NSLock()
        private var armed = false
        func arm() { lock.withLock { armed = true } }
        func observe(_ stage: HistoryCommitStage) throws {
            if stage == .generationsDurable && lock.withLock({ armed }) { throw HistoryStorageError.invalidEnvelope }
        }
    }
    func testOffFailedSaveReleasesCommittedIdentityCacheBeforeFailure() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let failure = CommitFailure()
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider(),commitObserver: { try failure.observe($0) })
        let now = Date()
        await store.updateSettings(.init(retention:.week),now:now)
        let process = ProcessSample(identity:.init(bootID:"owned",pid:1,uid:1,startSeconds:1,startMicroseconds:0),executable:"/owned/application",name:"Owned",projectPath:"/owned/project",applicationID:"owned.app",applicationName:"Owned",groupingReason:"fixture")
        await store.ingest(Snapshot(timestamp:now,processes:[process],cadence:5,expectedCadence:5,availability:.available))
        let before = await store.pagingDiagnostics()
        XCTAssertGreaterThan(before.committedIDs,0); XCTAssertGreaterThan(before.entityDirectoryCount,0)
        let committed = try Data(contentsOf:dir.appendingPathComponent("history.aesgcm"))
        failure.arm()
        await store.updateSettings(.init(retention:.off),now:now.addingTimeInterval(1))
        let metadata = await store.metadata(); XCTAssertNotNil(metadata.error)
        let after = await store.pagingDiagnostics()
        XCTAssertEqual(after.committedIDs,0); XCTAssertEqual(after.residentRows,0); XCTAssertEqual(after.cachedPoints,0); XCTAssertEqual(after.entityDirectoryCount,0)
        XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("history.aesgcm")),committed,"Failed commit leaves the prior encrypted archive recoverable.")
        await store.clearMemory(); let locked = await store.pagingDiagnostics(); XCTAssertEqual(locked.committedIDs,0)
    }
    func testQueryMissingGenerationFailsClosedAndClearDropsCatalogAndCaches() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let provider = EphemeralHistoryKeyProvider(); let base = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 60) * 60 - 600)
        try fixture(dir,key:provider.key(),base:base,buckets:5)
        let store = HistoryStore(directory:dir,keyProvider:provider); await store.load()
        let files = try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("bucket-") }
        try FileManager.default.removeItem(at:try XCTUnwrap(files.last))
        let query = await store.history(entityID:"system",since:base,until:Date())
        XCTAssertNotNil(query.error); XCTAssertTrue(query.points.isEmpty)
        let failed = await store.metadata(); XCTAssertNotNil(failed.error)
        await store.clear()
        let cleared = await store.metadata(); XCTAssertNil(cleared.error); XCTAssertEqual(cleared.aggregateCount,0)
        let diagnostics = await store.pagingDiagnostics(); XCTAssertEqual(diagnostics.buckets,0); XCTAssertEqual(diagnostics.cachedPoints,0)
    }
}
