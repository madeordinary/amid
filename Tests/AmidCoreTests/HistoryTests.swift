import XCTest
import CryptoKit
import Security
import LocalAuthentication
@testable import AmidCore

final class HistoryTests: XCTestCase, @unchecked Sendable {
    func location() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("amid-history-test-" + UUID().uuidString) }
    func sample(_ time: Date, cpu: Double? = 1, cadence: Double = 5, availability: Availability = .available) -> Snapshot {
        let p = ProcessSample(identity:.init(bootID:"test",pid:1,uid:1,startSeconds:1,startMicroseconds:0),executable:"/Secret/App",name:"Secret",cpuPercent:cpu,memoryBytes:1024,memoryMethod:.footprint,projectPath:"/Secret/Project",applicationID:"secret.app",applicationName:"Secret",groupingReason:"test")
        return Snapshot(timestamp:time,processes:[p],cadence:cadence,availability:availability)
    }
    func testOffPersistsOnlyEncryptedChoiceAndAliases() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let provider = EphemeralHistoryKeyProvider(); let store = HistoryStore(directory:dir,keyProvider:provider)
        await store.ingest(sample(Date()))
        XCTAssertFalse(FileManager.default.fileExists(atPath:dir.path))
        await store.updateSettings(.init(retention:.off,aliases:["private":"Secret Alias"]))
        await store.ingest(sample(Date().addingTimeInterval(5)))
        await store.recordAction(.init(operation:"stop",result:"done",targetID:"private"))
        let ciphertext = try Data(contentsOf:dir.appendingPathComponent("history.aesgcm"))
        XCTAssertNil(String(data:ciphertext,encoding:.utf8)); XCTAssertFalse(ciphertext.contains(Data("Secret".utf8)))
        let restored = HistoryStore(directory:dir,keyProvider:provider); await restored.load(); let state = await restored.state()
        XCTAssertEqual(state.settings.retention,.off); XCTAssertEqual(state.settings.aliases["private"],"Secret Alias"); XCTAssertTrue(state.actions.isEmpty); XCTAssertTrue(state.aggregates.isEmpty)
        let attrs = try FileManager.default.attributesOfItem(atPath:dir.appendingPathComponent("history.aesgcm").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue,0o600)
    }
    func testSpikeGapsExclusionsAndClear() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider()); let now = Date()
        await store.updateSettings(.init(retention:.week),now:now)
        await store.ingest(sample(now,cpu:1)); await store.ingest(sample(now.addingTimeInterval(5),cpu:999)); await store.ingest(sample(now.addingTimeInterval(65),cpu:nil,availability:.sleeping))
        var state = await store.state(); let app = state.aggregates.filter { $0.entityID == "app:secret.app" }
        XCTAssertEqual(app.compactMap { $0.cpu.maximum }.max(),999); XCTAssertTrue(app.contains { $0.gapSeconds > 0 }); XCTAssertTrue(app.contains { $0.cpu.count == 0 })
        await store.updateSettings(.init(retention:.week,excludedApplications:["secret.app"]),now:now.addingTimeInterval(65))
        state = await store.state(); XCTAssertFalse(state.aggregates.contains { $0.entityID == "app:secret.app" })
        await store.clear(); state = await store.state(); XCTAssertTrue(state.aggregates.isEmpty); XCTAssertTrue(state.recentSnapshots.isEmpty)
    }
    struct FailingKey: HistoryKeyProvider { func key() throws -> SymmetricKey { throw HistoryStorageError.invalidKey } }
    func testFailureTamperAndWrongKeyFailClosed() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let failed = HistoryStore(directory:dir,keyProvider:FailingKey()); await failed.updateSettings(.init(retention:.week)); let failedState = await failed.state(); XCTAssertNotNil(failedState.error); XCTAssertFalse(FileManager.default.fileExists(atPath:dir.path))
        let good = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider()); await good.updateSettings(.init(retention:.week))
        let before = try Data(contentsOf:dir.appendingPathComponent("history.aesgcm"))
        let wrong = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider()); await wrong.load(); await wrong.updateSettings(.init(retention:.off)); let state = await wrong.state(); XCTAssertNotNil(state.error)
        XCTAssertEqual(before,try Data(contentsOf:dir.appendingPathComponent("history.aesgcm")))
    }
    func testThirtyDaySyntheticHourlySoakRollupRetentionAndCap() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider(),maxBytes:150_000)
        let end = Date(); let start = end.addingTimeInterval(-31 * 86400)
        await store.updateSettings(.init(retention:.month),now:start)
        for hour in 0...744 { await store.ingest(sample(start.addingTimeInterval(Double(hour) * 3600),cpu:Double(hour % 100),cadence:3600)) }
        await store.flush(); var state = await store.state()
        XCTAssertLessThanOrEqual(state.storageBytes,150_000); XCTAssertTrue(state.shortenedByCap); XCTAssertTrue(state.aggregates.contains { $0.resolution == 3600 }); XCTAssertTrue(state.aggregates.allSatisfy { $0.start.addingTimeInterval($0.resolution) > end.addingTimeInterval(-30 * 86400) })
        await store.updateSettings(.init(retention:.day),now:end); state = await store.state(); XCTAssertTrue(state.aggregates.allSatisfy { $0.start.addingTimeInterval($0.resolution) > end.addingTimeInterval(-86400) })
        await store.clearMemory(); state = await store.state(); XCTAssertTrue(state.recentSnapshots.isEmpty)
    }
    func testVersionOneSettingsMigrationAndUnknownVersionPreservation() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let provider = EphemeralHistoryKeyProvider()
        func fixture(_ version: Int) throws {
            let json = Data("{\"version\":\(version),\"settings\":{\"retention\":\"week\"},\"aggregates\":[],\"alerts\":[],\"actions\":[],\"shortenedByCap\":false}".utf8)
            let sealed = try AES.GCM.seal(json,using:provider.key(),authenticating:Data("AMID".utf8)).combined!
            try (Data("AMID".utf8) + sealed).write(to:dir.appendingPathComponent("history.aesgcm"))
        }
        try fixture(1); let store = HistoryStore(directory:dir,keyProvider:provider); await store.load(); let migrated = await store.state(); XCTAssertNil(migrated.error); XCTAssertEqual(migrated.settings.numericMenuMetric,"none")
        try fixture(999); let before = try Data(contentsOf:dir.appendingPathComponent("history.aesgcm")); let unsupported = HistoryStore(directory:dir,keyProvider:provider); await unsupported.load(); let state = await unsupported.state(); XCTAssertNotNil(state.error); XCTAssertEqual(before,try Data(contentsOf:dir.appendingPathComponent("history.aesgcm")))
    }
}

extension HistoryTests {
    func testThirtyDayThousandProcessTwentyAppSyntheticSoak() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider())
        let end = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 60) * 60)
        let start = end.addingTimeInterval(-30 * 86400)
        let processes = (0..<1000).map { i in ProcessSample(identity:.init(bootID:"soak",pid:Int32(i + 100),uid:501,startSeconds:1,startMicroseconds:0),executable:"/fixture",name:"Fixture",cpuPercent:0.1,memoryBytes:1024 * 1024,memoryMethod:.footprint,applicationID:"fixture.\(i % 20)",applicationName:"Fixture \(i % 20)",groupingReason:"synthetic grouping") }
        await store.updateSettings(.init(retention:.month),now:start)
        // Older portion uses hourly fixtures; newest 24h exercises actual persisted minute buckets.
        for hour in 0..<696 { await store.ingest(Snapshot(timestamp:start.addingTimeInterval(Double(hour) * 3600),processes:processes,cadence:3600,availability:.available)) }
        for minute in 0...1440 { await store.ingest(Snapshot(timestamp:end.addingTimeInterval(Double(minute-1440) * 60),processes:processes,cadence:60,availability:.available)) }
        await store.flush(); let state = await store.state()
        XCTAssertLessThanOrEqual(state.storageBytes,250 * 1024 * 1024); XCTAssertFalse(state.shortenedByCap)
        XCTAssertTrue(state.aggregates.contains { $0.resolution == 60 }); XCTAssertTrue(state.aggregates.contains { $0.resolution == 3600 })
        XCTAssertEqual(Set(state.aggregates.map(\.entityID)).count,21)
    }
    func testPauseAndProjectExclusionDoesNotPersistIdentifyingRecords() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let key = EphemeralHistoryKeyProvider(); let store = HistoryStore(directory:dir,keyProvider:key); let now = Date()
        await store.updateSettings(.init(retention:.week,aliases:["secret.app":"Friendly"],excludedProjects:["/Secret/Project"]),now:now)
        await store.ingest(sample(now)); await store.flush(); var state = await store.state(); XCTAssertTrue(state.aggregates.allSatisfy { $0.entityID == "system" })
        await store.updateSettings(.init(retention:.week,paused:true),now:now); await store.ingest(sample(now.addingTimeInterval(5))); state = await store.state(); XCTAssertTrue(state.aggregates.allSatisfy { $0.entityID == "system" })
        await store.updateSettings(.init(retention:.week,aliases:["secret.app":"Friendly"]),now:now); await store.ingest(sample(now.addingTimeInterval(10))); state = await store.state(); XCTAssertEqual(state.aggregates.first { $0.entityID == "app:secret.app" }?.name,"Friendly")
    }
}

extension HistoryTests {
    func testUncommittedEncryptedBucketCannotResurrectExcludedHistory() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let key = EphemeralHistoryKeyProvider(); let store = HistoryStore(directory:dir,keyProvider:key); let now = Date()
        await store.updateSettings(.init(retention:.week),now:now); await store.ingest(sample(now)); await store.flush()
        let bucket = try XCTUnwrap(FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).first { $0.lastPathComponent.hasPrefix("bucket-") })
        let oldCipher = try Data(contentsOf:bucket)
        await store.updateSettings(.init(retention:.week,excludedApplications:["secret.app"]),now:now)
        // Simulate a ciphertext generation left by an interrupted pre-manifest write.
        let orphan = dir.appendingPathComponent("bucket-orphan.aesgcm"); try oldCipher.write(to:orphan)
        let restored = HistoryStore(directory:dir,keyProvider:key); await restored.load(); let state = await restored.state()
        XCTAssertNil(state.error); XCTAssertFalse(state.aggregates.contains { $0.entityID == "app:secret.app" || $0.entityID.hasPrefix("project:") })
        XCTAssertFalse(FileManager.default.fileExists(atPath:orphan.path))
    }
    func testSymlinkStoreDirectoryFailsClosed() async throws {
        let target = location(); let link = location(); defer { try? FileManager.default.removeItem(at:link); try? FileManager.default.removeItem(at:target) }
        try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        let store = HistoryStore(directory:link,keyProvider:EphemeralHistoryKeyProvider()); await store.updateSettings(.init(retention:.week)); let state = await store.state()
        XCTAssertNotNil(state.error); XCTAssertTrue(try FileManager.default.contentsOfDirectory(at:target,includingPropertiesForKeys:nil).isEmpty)
    }
}


extension HistoryTests {
    func testOptionalOwnedKeychainRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["AMID_KEYCHAIN_TEST"] == "1" else { throw XCTSkip("Opt-in owned Keychain integration test; set AMID_KEYCHAIN_TEST=1.") }
        let namespace = UUID()
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.madeordinary.amid.history.test." + namespace.uuidString,kSecAttrAccount as String:"encryption-key-v1",kSecUseAuthenticationContext as String:context]
        var readQuery = query; readQuery[kSecReturnData as String] = true; readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var existing: CFTypeRef?
        let before = SecItemCopyMatching(readQuery as CFDictionary,&existing)
        guard before == errSecItemNotFound else { throw XCTSkip("Unique owned namespace not available without interaction: status \(before).") }
        let provider = KeychainHistoryKeyProvider(testNamespace:namespace)
        let created: SymmetricKey
        do { created = try provider.key() }
        catch HistoryStorageError.keychain(let status) { throw XCTSkip("Owned Keychain creation unavailable: OS status \(status); no consent interaction attempted.") }
        defer { let status = SecItemDelete(query as CFDictionary); XCTAssertEqual(status,errSecSuccess) }
        let read = try provider.existingKey()
        XCTAssertEqual(created.withUnsafeBytes { Data($0) },read.withUnsafeBytes { Data($0) })
    }
}

extension HistoryTests {
    func testMetricCoverageUsesObservedDurationsAndMemoryMethodsRollUp() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider())
        let start = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 3600) * 3600)
        await store.updateSettings(.init(retention:.week),now:start)
        await store.ingest(sample(start,cpu:1,cadence:2))
        var missing = sample(start.addingTimeInterval(10),cpu:nil,cadence:10)
        missing.processes[0].memoryMethod = .rss
        await store.ingest(missing)
        var cpuOnly = sample(start.addingTimeInterval(20),cpu:2,cadence:10)
        cpuOnly.processes[0].memoryBytes = nil; cpuOnly.processes[0].memoryMethod = .unavailable
        await store.ingest(cpuOnly)
        let minuteState = await store.state(); let minute = try XCTUnwrap(minuteState.aggregates.first { $0.entityID == "app:secret.app" })
        XCTAssertEqual(minute.cpuObservedSeconds,12); XCTAssertEqual(minute.memoryObservedSeconds,12)
        XCTAssertEqual(minute.cpuCoverage,0.2,accuracy:0.0001); XCTAssertEqual(minute.memoryCoverage,0.2,accuracy:0.0001)
        XCTAssertEqual(minute.memoryMethods,[.footprint,.rss]); XCTAssertFalse(minute.metricCoverageEstimated)
        XCTAssertEqual(minute.cpu.count,2); XCTAssertEqual(minute.memory.count,2)
        await store.updateSettings(.init(retention:.week),now:start.addingTimeInterval(25 * 3600))
        let hourlyState = await store.state(); let hour = try XCTUnwrap(hourlyState.aggregates.first { $0.entityID == "app:secret.app" })
        XCTAssertEqual(hour.resolution,3600); XCTAssertEqual(hour.memoryMethods,[.footprint,.rss]); XCTAssertEqual(hour.cpuObservedSeconds,12); XCTAssertEqual(hour.memoryObservedSeconds,12)
    }
    func testLegacyMetricCoverageIsMarkedEstimatedAndMethodsUnknown() throws {
        var original = HistoryAggregate(entityID:"app:fixture",name:"Fixture",start:Date(),resolution:60)
        original.samples = 3; original.observedSeconds = 22; original.cpu.add(5); original.memory.add(nil)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        for field in ["memoryMethods","cpuObservedSeconds","memoryObservedSeconds","metricCoverageEstimated"] { json.removeValue(forKey:field) }
        let restored = try JSONDecoder().decode(HistoryAggregate.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertTrue(restored.metricCoverageEstimated); XCTAssertTrue(restored.memoryMethods.isEmpty)
        XCTAssertEqual(restored.cpuCoverage,22 / 3 / 60,accuracy:0.0001); XCTAssertEqual(restored.memoryCoverage,0); XCTAssertNil(restored.memory.average)
    }
}

extension HistoryTests {
    private final class CommitInterruption: @unchecked Sendable {
        private let lock = NSLock()
        private var armed = false
        let stage: HistoryCommitStage
        init(stage: HistoryCommitStage) { self.stage = stage }
        func arm() { lock.lock(); armed = true; lock.unlock() }
        func observe(_ value: HistoryCommitStage) throws {
            lock.lock(); let shouldFail = armed && value == stage; lock.unlock()
            if shouldFail { throw CocoaError(.fileWriteUnknown) }
        }
    }
    func testInterruptedCommitBeforeManifestPreservesPreviousGeneration() async throws {
        try await checkInterruptedCommit(stage:.generationsDurable, expectsExcluded:false)
    }
    func testInterruptedCommitAfterManifestUsesNewMembershipBeforeCleanup() async throws {
        try await checkInterruptedCommit(stage:.manifestDurable, expectsExcluded:true)
    }
    private func checkInterruptedCommit(stage: HistoryCommitStage, expectsExcluded: Bool) async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let key = EphemeralHistoryKeyProvider(); let initial = HistoryStore(directory:dir,keyProvider:key); let now = Date()
        await initial.updateSettings(.init(retention:.week),now:now); await initial.ingest(sample(now)); await initial.flush()
        let interruption = CommitInterruption(stage:stage)
        let interrupted = HistoryStore(directory:dir,keyProvider:key,commitObserver:interruption.observe)
        await interrupted.load(); let before = await interrupted.state(); XCTAssertNil(before.error)
        let previousFiles = Set(try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("bucket-") })
        interruption.arm()
        await interrupted.updateSettings(.init(retention:.week,excludedApplications:["secret.app"]),now:now)
        let failed = await interrupted.state(); XCTAssertNotNil(failed.error)
        // Both interruption boundaries precede garbage collection: no old generation was removed.
        for file in previousFiles { XCTAssertTrue(FileManager.default.fileExists(atPath:file.path)) }
        let restored = HistoryStore(directory:dir,keyProvider:key); await restored.load(); let state = await restored.state()
        XCTAssertNil(state.error)
        XCTAssertEqual(state.settings.excludedApplications.contains("secret.app"),expectsExcluded)
        XCTAssertEqual(state.aggregates.contains { $0.entityID == "app:secret.app" },!expectsExcluded)
    }
}

extension HistoryTests {
    func testActualStallComparedAgainstExpectedCadenceRecordsGap() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider()); let now = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 60) * 60)
        await store.updateSettings(.init(retention:.week),now:now)
        var first = sample(now); first.expectedCadence = 5; await store.ingest(first)
        var stalled = sample(now.addingTimeInterval(120),cpu:999,cadence:120); stalled.expectedCadence = 5
        await store.ingest(stalled)
        let state = await store.state(); let arrival = try XCTUnwrap(state.aggregates.first { $0.entityID == "app:secret.app" && $0.start == stalled.timestamp })
        XCTAssertEqual(arrival.gapSeconds,120); XCTAssertEqual(arrival.observedSeconds,0); XCTAssertEqual(arrival.cpuCoverage,0); XCTAssertEqual(arrival.memoryCoverage,0); XCTAssertNil(arrival.cpu.average); XCTAssertNil(arrival.memory.average)
    }
    func testProjectExclusionImmediatelyPurgesOverlappingAppAlertAndAction() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let key = EphemeralHistoryKeyProvider(); let store = HistoryStore(directory:dir,keyProvider:key); let now = Date()
        await store.updateSettings(.init(retention:.week),now:now); await store.ingest(sample(now))
        let alert = AlertEvent(id:UUID(),category:.appCPU,entityID:"secret.app",title:"CPU",detail:"Sensitive app title",startedAt:now,updatedAt:now,recoveredAt:nil,notificationEligible:false)
        await store.recordAlerts([alert]); await store.recordAction(.init(timestamp:now,operation:"stop",result:"done",targetID:sample(now).processes[0].id))
        let before = await store.state(); XCTAssertEqual(before.alerts.count,1); XCTAssertEqual(before.actions.count,1)
        await store.updateSettings(.init(retention:.week,excludedProjects:["/Secret/Project"]),now:now)
        let after = await store.state(); XCTAssertTrue(after.alerts.isEmpty); XCTAssertTrue(after.actions.isEmpty)
        await store.recordAlerts([alert]); await store.flush()
        let restored = HistoryStore(directory:dir,keyProvider:key); await restored.load(); let saved = await restored.state(); XCTAssertTrue(saved.alerts.isEmpty); XCTAssertTrue(saved.actions.isEmpty)
    }
    func testSnapshotWithoutExpectedCadenceDecodesBackwardCompatibly() throws {
        let original = sample(Date()); var json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any]); json.removeValue(forKey:"expectedCadence")
        let restored = try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:json)); XCTAssertNil(restored.expectedCadence); XCTAssertEqual(restored.cadence,5)
    }
}

extension HistoryTests {
    func testShortExplicitSuspensionRecordsGapWithoutMetricCoverage() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider()); let start = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 60) * 60 + 50)
        await store.updateSettings(.init(retention:.week),now:start); await store.ingest(sample(start))
        await store.suspendObservation()
        let suspended = await store.state(); XCTAssertEqual(suspended.recentSnapshots.count,1)
        await store.ingest(sample(start.addingTimeInterval(20)))
        let resumed = await store.state(); let bucket = try XCTUnwrap(resumed.aggregates.first { $0.entityID == "app:secret.app" && $0.start > start })
        XCTAssertEqual(bucket.gapSeconds,20); XCTAssertEqual(bucket.cpuCoverage,0); XCTAssertEqual(bucket.memoryCoverage,0); XCTAssertNil(bucket.cpu.average); XCTAssertNil(bucket.memory.average)
        await store.ingest(sample(start.addingTimeInterval(25)))
        let next = await store.state(); let known = try XCTUnwrap(next.aggregates.first { $0.id == bucket.id }); XCTAssertEqual(known.cpuObservedSeconds,5); XCTAssertEqual(known.memoryObservedSeconds,5)
    }
    func testClearMemoryMarksLockGapAndKeepsRawRingEmpty() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider()); let start = Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970 / 60) * 60 + 50)
        await store.updateSettings(.init(retention:.week),now:start); await store.ingest(sample(start)); await store.clearMemory()
        let locked = await store.state(); XCTAssertTrue(locked.recentSnapshots.isEmpty)
        await store.ingest(sample(start.addingTimeInterval(20)))
        let state = await store.state(); let bucket = try XCTUnwrap(state.aggregates.first { $0.entityID == "app:secret.app" && $0.start > start }); XCTAssertEqual(bucket.gapSeconds,20); XCTAssertEqual(bucket.cpuCoverage,0); XCTAssertEqual(bucket.memoryCoverage,0)
    }
    func testOffRecentHistoryPreservesRawSpikesUnknownsAndPauseGaps() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider())
        let now = Date(timeIntervalSince1970:1_800_000_003)
        await store.updateSettings(.init(retention:.off),now:now)
        await store.ingest(sample(now,cpu:1))
        await store.ingest(sample(now.addingTimeInterval(5),cpu:999))
        await store.ingest(sample(now.addingTimeInterval(10),cpu:nil))
        await store.suspendObservation()
        await store.ingest(sample(now.addingTimeInterval(30),cpu:888))
        let points = await store.recentHistory(entityID:"app:secret.app")
        XCTAssertEqual(points.map(\.start),[now,now.addingTimeInterval(5),now.addingTimeInterval(10),now.addingTimeInterval(30)])
        XCTAssertEqual(points[1].cpu.maximum,999)
        XCTAssertNil(points[2].cpu.average); XCTAssertEqual(points[2].cpuCoverage,0)
        XCTAssertEqual(points[2].memoryMethods,[.footprint])
        XCTAssertEqual(points[3].gapSeconds,20); XCTAssertNil(points[3].cpu.average)
        XCTAssertEqual(points[3].memoryCoverage,0)
        let state = await store.state(); XCTAssertTrue(state.aggregates.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:dir.path),["history.aesgcm"])
        let project = await store.recentHistory(entityID:"project:/Secret/Project")
        XCTAssertEqual(project.count,4); XCTAssertEqual(project[1].cpu.maximum,999)
    }
    func testOffRecentEntitiesIncludeExitedThenPruneAndClearCachedPoints() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider())
        let now = Date(timeIntervalSince1970:1_800_000_000)
        await store.updateSettings(.init(retention:.off),now:now)
        await store.ingest(sample(now))
        _ = await store.recentHistory(entityID:"app:secret.app")
        var empty = sample(now.addingTimeInterval(5)); empty.processes = []
        await store.ingest(empty)
        var entities = await store.recentHistoryEntities()
        XCTAssertEqual(entities["app:secret.app"],"Secret")
        XCTAssertEqual(entities["project:/Secret/Project"],"Project")
        empty.timestamp = now.addingTimeInterval(901); empty.cadence = 896; empty.expectedCadence = 5
        await store.ingest(empty)
        entities = await store.recentHistoryEntities(); XCTAssertNil(entities["app:secret.app"])
        let pruned = await store.recentHistory(entityID:"app:secret.app"); XCTAssertTrue(pruned.isEmpty)
        let system = await store.recentHistory(entityID:"system"); XCTAssertEqual(system.last?.gapSeconds,896)
        await store.clearMemory()
        let cleared = await store.recentHistory(entityID:"system"); XCTAssertTrue(cleared.isEmpty)
        await store.ingest(sample(now.addingTimeInterval(906)))
        let resumed = await store.recentHistory(entityID:"app:secret.app"); XCTAssertEqual(resumed.first?.gapSeconds,5)
        await store.clear()
        let reset = await store.recentHistory(entityID:"app:secret.app"); XCTAssertTrue(reset.isEmpty)
    }

    func testRecentClockExpiryWithoutIngestInvalidatesCachesAndPreservesGap() async throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = HistoryStore(directory:dir,keyProvider:EphemeralHistoryKeyProvider())
        let now = Date(timeIntervalSince1970:1_800_000_000)
        await store.updateSettings(.init(retention:.off),now:now)
        await store.ingest(sample(now))
        _ = await store.recentHistory(entityID:"app:secret.app")
        _ = await store.recentHistoryEntities()
        let unchanged = await store.expireRecent(now:now.addingTimeInterval(900)); XCTAssertFalse(unchanged)
        await store.suspendObservation()
        let expired = await store.expireRecent(now:now.addingTimeInterval(901)); XCTAssertTrue(expired)
        let state = await store.state(); XCTAssertTrue(state.recentSnapshots.isEmpty)
        let entities = await store.recentHistoryEntities(); XCTAssertNil(entities["app:secret.app"])
        let points = await store.recentHistory(entityID:"app:secret.app"); XCTAssertTrue(points.isEmpty)
        await store.ingest(sample(now.addingTimeInterval(905)))
        let resumed = await store.recentHistory(entityID:"app:secret.app")
        XCTAssertEqual(resumed.first?.gapSeconds,905); XCTAssertNil(resumed.first?.cpu.average)
    }

}
