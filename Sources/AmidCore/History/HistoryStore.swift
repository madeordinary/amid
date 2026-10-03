import Foundation
import CryptoKit
import Darwin

enum HistoryCommitStage: Sendable { case generationsDurable, manifestDurable }
enum HistoryMemoryStage: String, Sendable { case decoded, validated, assigned, decodeReturned, enforced, enforceReturned, grouped, encoded, written, indexReady, loadReturned }

public actor HistoryStore {
    private struct Archive: Codable { var version: Int = 3; var settings: HistorySettings; var aggregates: [HistoryAggregate]; var alerts: [AlertEvent]; var actions: [ActionRecord]; var shortenedByCap: Bool; var segmentFiles: [String]? = nil }
    private let directory: URL
    private let keyProvider: any HistoryKeyProvider
    private let maxBytes: Int
    private let commitObserver: @Sendable (HistoryCommitStage) throws -> Void
    private let memoryObserver: (@Sendable (HistoryMemoryStage, Int, Int) -> Void)?
    private let loadReferenceDate: Date?
    private var settings = HistorySettings()
    private var aggregates: [HistoryAggregate] = []
    private var alerts: [AlertEvent] = []
    private var actions: [ActionRecord] = []
    private var recent: [Snapshot] = []
    private var recentIntervals: [Date: (seconds: Double, continuous: Bool)] = [:]
    private var recentHistoryCache: (entityID: String, values: [HistoryAggregate])?
    private var recentEntitiesCache: [String:String]?
    private var bytes = 0
    private var shortened = false
    private var failure: String?
    private var previous: Date?
    private var observationInterrupted = false
    // aggregates/index hold one mutable minute only; immutable archive values stay on disk.
    private var aggregateIndex: [String:Int] = [:]
    private struct Bucket {
        var path: String; var bytes: Int; var count: Int
        var first: Date; var last: Date; var end: Date; var resolution: Double
        var members: [Int]; var migration: Bool; var noncanonical: Bool
    }
    private struct EntityRecord { var id: String; var name: String; var latest: Date }
    private var catalog: [String:Bucket] = [:]
    private var tokens: [String:Int] = [:]
    private var entityRecords: [Int:EntityRecord] = [:]
    private var nextToken = 0
    private var workingCommittedIDs = Set<String>()
    private var workingName: String?
    private var revision: UInt64 = 0
    private var entityListCache: [HistoryEntity]?
    private struct CachedBucket { var generation: String; var points: [HistoryAggregate] }
    private struct QueryCache { var entity: String; var buckets: [String:CachedBucket] }
    private var queryCaches: [QueryCache] = []
    private var bucketReads = 0
    private var stagedWrites = 0
    private var dirtySegments = Set<String>()
    private var excludedAlertIDs = Set<String>()
    private var lastAlertWrite: Date?
    public init(directory: URL, keyProvider: any HistoryKeyProvider = KeychainHistoryKeyProvider(), maxBytes: Int = 250 * 1024 * 1024) { self.directory = directory; self.keyProvider = keyProvider; self.maxBytes = max(1024,maxBytes); self.commitObserver = { _ in }; self.memoryObserver = nil; self.loadReferenceDate = nil }
    init(directory: URL, keyProvider: any HistoryKeyProvider, maxBytes: Int = 250 * 1024 * 1024, commitObserver: @escaping @Sendable (HistoryCommitStage) throws -> Void, memoryObserver: (@Sendable (HistoryMemoryStage, Int, Int) -> Void)? = nil, loadReferenceDate: Date? = nil) { self.directory = directory; self.keyProvider = keyProvider; self.maxBytes = max(1024,maxBytes); self.commitObserver = commitObserver; self.memoryObserver = memoryObserver; self.loadReferenceDate = loadReferenceDate }
    private var file: URL { directory.appendingPathComponent("history.aesgcm") }
    public func load() {
        autoreleasepool { loadWithinPool() }
        memoryObserver?(.loadReturned, aggregateCount, 0)
    }
    private var aggregateCount: Int {
        catalog.reduce(0) { $0 + ($1.key == workingName ? 0 : $1.value.count) } + aggregates.count
    }
    private func loadWithinPool() {
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        do {
            let loadKey = try autoreleasepool { try decodeAndAssignArchive() }
            memoryObserver?(.decodeReturned, aggregateCount, 0)
            autoreleasepool { enforce(now:loadReferenceDate ?? Date(), using:loadKey) }
            guard failure == nil else { return }
            memoryObserver?(.enforced, aggregateCount, 0)
            memoryObserver?(.enforceReturned, aggregateCount, 0)
            try autoreleasepool { try persist(using:loadKey) }
        } catch { unavailable() }
    }
    private func unavailable() {
        failure = "Encrypted history unavailable. Unlock Keychain or clear the app-owned store to recover. No plaintext fallback."
        clearQueryCache()
    }
    private func readBucket(_ bucket: Bucket, using key: SymmetricKey) throws -> [HistoryAggregate] {
        let url = directory.appendingPathComponent(bucket.path)
        try validateRegular(url)
        bucketReads += 1
        return try JSONDecoder().decode([HistoryAggregate].self,from:decrypt(Data(contentsOf:url),using:key))
    }
    private func describe(_ rows: [HistoryAggregate], path: String, bytes: Int) throws -> Bucket {
        guard let first = rows.first, rows.allSatisfy({ segmentName($0) == segmentName(first) }), Set(rows.map(\.id)).count == rows.count else { throw HistoryStorageError.invalidEnvelope }
        var members = Set<Int>()
        for row in rows {
            let token: Int
            if let existing = tokens[row.entityID] { token = existing }
            else { token = nextToken; nextToken += 1; tokens[row.entityID] = token }
            members.insert(token)
            if entityRecords[token].map({ $0.latest <= row.start }) ?? true { entityRecords[token] = EntityRecord(id:row.entityID,name:row.name,latest:row.start) }
        }
        return Bucket(path:path,bytes:bytes,count:rows.count,first:rows.map(\.start).min()!,last:rows.map(\.start).max()!,end:rows.map { $0.start.addingTimeInterval($0.resolution) }.max()!,resolution:first.resolution,members:members.sorted(),migration:rows.contains { $0.requiresPersistenceMigration },noncanonical:rows.contains { hasSignedZero($0) || $0.resolution != 3600 || $0.start.timeIntervalSince1970 != floor($0.start.timeIntervalSince1970 / 3600) * 3600 })
    }
    private func decodeAndAssignArchive() throws -> SymmetricKey {
        try validateDirectory()
        let encrypted = try Data(contentsOf:file)
        guard encrypted.prefix(4) == Data("AMID".utf8) else { throw HistoryStorageError.invalidEnvelope }
        let loadKey = try keyProvider.existingKey()
        let archive = try JSONDecoder().decode(Archive.self,from:decrypt(encrypted,using:loadKey))
        guard (1...3).contains(archive.version) else { throw HistoryStorageError.unsupportedVersion(archive.version) }
        // No key or decoded row array is retained by the actor after this synchronous operation.
        catalog.removeAll(); tokens.removeAll(); entityRecords.removeAll(); nextToken = 0
        aggregates.removeAll(); aggregateIndex.removeAll(); workingName = nil; workingCommittedIDs.removeAll(); dirtySegments.removeAll(); stagedWrites = 0
        clearQueryCache()
        var candidate: [String:Bucket] = [:]
        if archive.version == 3 {
            guard let files = archive.segmentFiles else { throw HistoryStorageError.invalidEnvelope }
            for name in files {
                guard name.hasPrefix("bucket-"), name.hasSuffix(".aesgcm"), !name.contains("/"), !name.contains("..") else { throw HistoryStorageError.invalidEnvelope }
                try autoreleasepool {
                    let url = directory.appendingPathComponent(name); try validateRegular(url)
                    let data = try Data(contentsOf:url)
                    let rows = try JSONDecoder().decode([HistoryAggregate].self,from:decrypt(data,using:loadKey))
                    let entry = try describe(rows,path:name,bytes:data.count)
                    let logical = segmentName(rows[0])
                    guard candidate[logical] == nil else { throw HistoryStorageError.invalidEnvelope }
                    candidate[logical] = entry
                }
            }
        }
        // Inline old archives are the explicit one-time migration exception.
        guard Set(archive.aggregates.map(\.id)).count == archive.aggregates.count else { throw HistoryStorageError.invalidEnvelope }
        let inlineGroups = Dictionary(grouping:archive.aggregates,by:segmentName)
        for (logical,rows) in inlineGroups {
            if let entry = candidate[logical] {
                let persisted = try readBucket(entry,using:loadKey)
                guard Set((persisted + rows).map(\.id)).count == persisted.count + rows.count else { throw HistoryStorageError.invalidEnvelope }
            }
        }
        memoryObserver?(.decoded, candidate.values.reduce(0) { $0 + $1.count } + archive.aggregates.count, 0)
        memoryObserver?(.validated, candidate.values.reduce(0) { $0 + $1.count } + archive.aggregates.count, 0)
        settings = archive.settings; catalog = candidate; alerts = archive.alerts; actions = archive.actions
        shortened = archive.shortenedByCap; bytes = encrypted.count + candidate.values.reduce(0) { $0 + $1.bytes }; failure = nil
        for (logical,rows) in inlineGroups {
            let existing = try catalog[logical].map { try readBucket($0,using:loadKey) } ?? []
            try stage(existing + rows, logical:logical, using:loadKey)
        }
        // Apply configured exclusions and schema defaults before publishing usable history.
        for logical in catalog.keys.sorted() {
            let entry = catalog[logical]!
            if entry.migration || !settings.excludedApplications.isEmpty || !settings.excludedProjects.isEmpty {
                let rows = try readBucket(entry,using:loadKey).filter { !excluded($0.entityID) }
                if entry.migration || rows.count != entry.count { try stage(rows,logical:logical,using:loadKey) }
            }
        }
        revision &+= 1; entityListCache = nil
        memoryObserver?(.assigned, aggregateCount, 0)
        return loadKey
    }
    public func metadata() -> HistoryMetadata {
        HistoryMetadata(settings:settings,alerts:alerts,actions:actions,aggregateCount:failure == nil ? aggregateCount : 0,storageBytes:bytes,shortenedByCap:shortened,error:failure,revision:revision)
    }
    public func entities() -> [HistoryEntity] {
        guard failure == nil else { return [] }
        if let entityListCache { return entityListCache }
        let active = Set(catalog.values.flatMap(\.members)).union(aggregates.compactMap { tokens[$0.entityID] })
        do {
            var key: SymmetricKey?
            for token in active {
                guard let record = entityRecords[token] else { continue }
                let entries = catalog.values.filter { $0.members.contains(token) }
                let latestStored = max(entries.map(\.last).max() ?? .distantPast, aggregates.filter { $0.entityID == record.id }.map(\.start).max() ?? .distantPast)
                if record.latest > latestStored {
                    let rows: [HistoryAggregate]
                    if let entry = entries.max(by:{ $0.last < $1.last }) {
                        if key == nil { key = try keyProvider.existingKey() }
                        rows = try readBucket(entry,using:key!).filter { $0.entityID == record.id }
                    } else { rows = aggregates.filter { $0.entityID == record.id } }
                    if let latest = rows.max(by:{ $0.start < $1.start }) { entityRecords[token] = EntityRecord(id:record.id,name:latest.name,latest:latest.start) }
                }
            }
        } catch { unavailable(); return [] }
        let result = active.compactMap { entityRecords[$0] }.map { HistoryEntity(id:$0.id,name:$0.name) }.sorted { lhs,rhs in lhs.id == "system" ? rhs.id != "system" : rhs.id == "system" ? false : lhs.id < rhs.id }
        entityListCache = result; return result
    }
    public func clearQueryCache() { queryCaches.removeAll() }
    public func history(entityID: String, since: Date, until: Date) -> HistoryQuery {
        func reply(_ points: [HistoryAggregate], _ error: String?) -> HistoryQuery { HistoryQuery(entityID:entityID,since:since,until:until,points:points,revision:revision,error:error) }
        guard since.timeIntervalSince1970.isFinite, until.timeIntervalSince1970.isFinite, since <= until, until.timeIntervalSince(since).isFinite, until.timeIntervalSince(since) <= 30 * 86400 else { return reply([],"Invalid history range.") }
        guard failure == nil else { return reply([],failure) }
        guard let token = tokens[entityID] else { return reply([],nil) }
        let matching = catalog.filter { $0.value.last >= since && $0.value.first <= until && $0.key != workingName && $0.value.members.contains(token) }
        var cache = queryCaches.first { $0.entity == entityID } ?? QueryCache(entity:entityID,buckets:[:])
        cache.buckets = cache.buckets.filter { matching[$0.key] != nil }
        var key: SymmetricKey?
        do {
            for (logical,entry) in matching where cache.buckets[logical]?.generation != entry.path {
                if key == nil { key = try keyProvider.existingKey() }
                let points = try autoreleasepool { try readBucket(entry,using:key!).filter { $0.entityID == entityID } }
                cache.buckets[logical] = CachedBucket(generation:entry.path,points:points)
            }
            var points = cache.buckets.values.flatMap(\.points) + aggregates.filter { $0.entityID == entityID }
            points.removeAll { $0.start < since || $0.start > until }
            points.sort { $0.start == $1.start ? $0.resolution < $1.resolution : $0.start < $1.start }
            queryCaches.removeAll { $0.entity == entityID }; queryCaches.append(cache)
            if queryCaches.count > 2 { queryCaches.removeFirst() }
            return reply(points,nil)
        } catch { unavailable(); return reply([],failure) }
    }
    /// Expensive diagnostics only: decoded archive rows are returned, never installed as resident state.
    public func state() -> HistoryState {
        var values: [HistoryAggregate] = []
        if failure == nil {
            do {
                var key: SymmetricKey?
                for (logical,entry) in catalog where logical != workingName {
                    if key == nil { key = try keyProvider.existingKey() }
                    values += try autoreleasepool { try readBucket(entry,using:key!) }
                }
                let pending = workingName.map { dirtySegments.contains($0) } ?? false
                if pending {
                    values += aggregates.filter { workingCommittedIDs.contains($0.id) }
                    values.sort { $0.start < $1.start }
                    // Preserve the old diagnostic append order until the next durable flush.
                    values += aggregates.filter { !workingCommittedIDs.contains($0.id) }
                } else { values += aggregates; values.sort { $0.start < $1.start } }
            } catch { unavailable(); values.removeAll() }
        }
        return HistoryState(settings:settings,aggregates:values,alerts:alerts,actions:actions,recentSnapshots:recent,storageBytes:bytes,shortenedByCap:shortened,error:failure)
    }
    func pagingDiagnostics() -> (residentRows: Int, bucketReads: Int, cachedPoints: Int, buckets: Int, committedIDs: Int, entityDirectoryCount: Int) { (aggregates.count,bucketReads,queryCaches.reduce(0) { $0 + $1.buckets.values.reduce(0) { $0 + $1.points.count } },catalog.count,workingCommittedIDs.count,entityRecords.count) }
    public func updateSettings(_ value: HistorySettings, now: Date = Date()) {
        let changedApps = settings.excludedApplications != value.excludedApplications
        let changedProjects = settings.excludedProjects != value.excludedProjects
        settings = value; recentHistoryCache = nil; recentEntitiesCache = nil; clearQueryCache()
        if let latest = recent.last { excludedAlertIDs = excludedEntities(in:latest) }
        if failure == nil && (changedApps || changedProjects) {
            do {
                var key: SymmetricKey?
                for logical in catalog.keys.sorted() {
                    if key == nil { key = try keyProvider.existingKey() }
                    let rows = try readRows(logical,using:key!).filter { !excluded($0.entityID) && !(changedApps && $0.entityID.hasPrefix("project:")) && !(changedProjects && $0.entityID.hasPrefix("app:")) }
                    try stage(rows,logical:logical,using:key!)
                }
                aggregates.removeAll { excluded($0.entityID) || (changedApps && $0.entityID.hasPrefix("project:")) || (changedProjects && $0.entityID.hasPrefix("app:")) }; rebuildAggregateIndex()
            } catch { unavailable() }
        }
        alerts.removeAll { settings.excludedApplications.contains($0.entityID) || isExcludedEntity($0.entityID) || (changedProjects && [.appCPU,.appMemoryGrowth,.lowActivityServer].contains($0.category)) }
        actions.removeAll { isExcludedEntity($0.targetID) || (changedProjects && !settings.excludedProjects.isEmpty) }
        revision &+= 1; entityListCache = nil
        enforce(now:now); save()
    }
    private func excluded(_ id: String) -> Bool { (id.hasPrefix("app:") && settings.excludedApplications.contains(String(id.dropFirst(4)))) || (id.hasPrefix("project:") && settings.excludedProjects.contains(String(id.dropFirst(8)))) }
    private func excludedEntities(in snapshot: Snapshot) -> Set<String> {
        Set(snapshot.processes.filter { settings.excludedApplications.contains($0.applicationID) || ($0.projectPath.map { settings.excludedProjects.contains($0) } ?? false) }.flatMap { [$0.applicationID,$0.id] })
    }
    private func isExcludedEntity(_ id: String) -> Bool { excludedAlertIDs.contains(id) || excludedAlertIDs.contains { id.hasPrefix($0 + ":") } }
    /// Opt-in own-current-thread timing around the unchanged synchronous ingestion path.
    public func profiledIngest(_ snapshot: Snapshot) -> OwnCurrentThreadMeasurement.Report {
        let measurement = OwnCurrentThreadMeasurement()
        ingest(snapshot)
        return measurement.report()
    }
    public func ingest(_ snapshot: Snapshot) {
        guard settings.retention != nil else { return }
        guard recent.last.map({snapshot.timestamp > $0.timestamp}) ?? true else { return }
        excludedAlertIDs = excludedEntities(in:snapshot)
        let interval = previous.map { snapshot.timestamp.timeIntervalSince($0) } ?? (snapshot.expectedCadence ?? snapshot.cadence)
        let continuous = !observationInterrupted && !settings.paused && interval <= max(30,(snapshot.expectedCadence ?? snapshot.cadence) * 2.5) && snapshot.availability == .available
        observationInterrupted = false
        recentIntervals[snapshot.timestamp] = (interval, continuous)
        recent.append(snapshot); recent.removeAll { snapshot.timestamp.timeIntervalSince($0.timestamp) > 900 }
        recentIntervals = recentIntervals.filter { snapshot.timestamp.timeIntervalSince($0.key) <= 900 }
        recentHistoryCache = nil; recentEntitiesCache = nil
        defer { previous = snapshot.timestamp }
        guard !settings.paused, let retention = settings.retention, retention != .off, failure == nil else { return }
        let start = Date(timeIntervalSince1970:floor(snapshot.timestamp.timeIntervalSince1970 / 60) * 60)
        let logical = "bucket-\(Int64(start.timeIntervalSince1970))-60.aesgcm"
        if workingName != logical {
            do {
                if let old = workingName, dirtySegments.contains(old) { try stage(aggregates,logical:old,using:keyProvider.existingKey()); dirtySegments.remove(old) }
                aggregates = try catalog[logical].map { try readBucket($0,using:keyProvider.existingKey()) } ?? []
                workingName = logical; workingCommittedIDs = Set(aggregates.map(\.id)); rebuildAggregateIndex()
            } catch { unavailable(); return }
        }
        var groups: [(String,String,Double?,Double?,Bool,Set<MemoryMethod>)] = [("system","System",snapshot.system.cpuPercent,snapshot.system.memory.active.map { Double($0) },snapshot.availability != .available,[])]
        let permitted = snapshot.processes.filter { !settings.excludedApplications.contains($0.applicationID) && !($0.projectPath.map { settings.excludedProjects.contains($0) } ?? false) }
        var filtered = snapshot; filtered.processes = permitted
        for group in ResourceGroup.applications(filtered, sortedByMemory: false) { groups.append(("app:" + group.id,group.name,group.cpuPercent,group.memoryBytes.map { Double($0) },group.partial,Set(group.processes.filter { $0.memoryBytes != nil }.map(\.memoryMethod)))) }
        for group in ResourceGroup.projects(filtered, sortedByMemory: false) { groups.append(("project:" + group.id,group.name,group.cpuPercent,group.memoryBytes.map { Double($0) },group.partial,Set(group.processes.filter { $0.memoryBytes != nil }.map(\.memoryMethod)))) }
        for (id,name,cpu,memory,partial,methods) in groups {
            let index: Int
            let aggregateID = "\(id):\(start.timeIntervalSince1970):60.0"
            if let existing = aggregateIndex[aggregateID] { index = existing }
            else { aggregates.append(HistoryAggregate(entityID:id,name:settings.aliases[id] ?? settings.aliases[String(id.dropFirst(id.hasPrefix("app:") ? 4 : 8))] ?? name,start:start,resolution:60)); index = aggregates.count - 1; aggregateIndex[aggregates[index].id] = index }
            dirtySegments.insert(segmentName(aggregates[index]))
            if id == "system", continuous {
                if snapshot.system.loadAverage.count >= 3 { aggregates[index].load1.add(snapshot.system.loadAverage[0]); aggregates[index].load5.add(snapshot.system.loadAverage[1]); aggregates[index].load15.add(snapshot.system.loadAverage[2]) }
                aggregates[index].swap.add(snapshot.system.memory.swapUsed.map { Double($0) }); aggregates[index].pressureStates.insert(snapshot.system.memory.pressure)
            }
            aggregates[index].samples += 1; aggregates[index].cadences.insert(snapshot.cadence); aggregates[index].partial = aggregates[index].partial || partial
            if continuous {
                let duration = max(0, min(interval,60))
                aggregates[index].observedSeconds += duration
                if let cpu, cpu.isFinite { aggregates[index].cpuObservedSeconds += duration }
                if let memory, memory.isFinite { aggregates[index].memoryObservedSeconds += duration; aggregates[index].memoryMethods.formUnion(methods) }
                aggregates[index].cpu.add(cpu); aggregates[index].memory.add(memory)
            }
            else { aggregates[index].gapSeconds += interval }
        }
        revision &+= 1; entityListCache = nil
        for row in aggregates { if tokens[row.entityID] == nil { let token = nextToken; nextToken += 1; tokens[row.entityID] = token }; let token = tokens[row.entityID]!; if entityRecords[token].map({ $0.latest <= row.start }) ?? true { entityRecords[token] = EntityRecord(id:row.entityID,name:row.name,latest:row.start) } }
        if previous == nil || floor(previous!.timeIntervalSince1970 / 60) != floor(snapshot.timestamp.timeIntervalSince1970 / 60) { enforce(now:snapshot.timestamp) }
        // Persist at minute boundaries: every raw sample remains in RAM only.
        if previous == nil || floor(previous!.timeIntervalSince1970 / 60) != floor(snapshot.timestamp.timeIntervalSince1970 / 60) { save() }
    }
    /// Selected-entity raw observations from the RAM ring only; never serialized.
    public func recentHistory(entityID: String) -> [HistoryAggregate] {
        if let cache = recentHistoryCache, cache.entityID == entityID { return cache.values }
        let values = recent.compactMap { snapshot -> HistoryAggregate? in
            let interval = recentIntervals[snapshot.timestamp] ?? (0, false)
            let resolution = max(0.001, snapshot.expectedCadence ?? snapshot.cadence)
            var name = "System"
            var cpu = snapshot.system.cpuPercent
            var memory = snapshot.system.memory.active.map { Double($0) }
            var methods = Set<MemoryMethod>()
            var partial = snapshot.availability != .available
            if entityID != "system" {
                let isApp = entityID.hasPrefix("app:")
                guard isApp || entityID.hasPrefix("project:") else { return nil }
                let rawID = String(entityID.dropFirst(isApp ? 4 : 8))
                var seen = Set<String>()
                let processes = snapshot.processes.filter {
                    (isApp ? $0.applicationID == rawID : $0.projectPath == rawID) && seen.insert($0.id).inserted
                }
                guard !processes.isEmpty else { return nil }
                let group = ResourceGroup(id:rawID,name:isApp ? processes[0].applicationName : URL(fileURLWithPath:rawID).lastPathComponent,processes:processes)
                name = settings.aliases[entityID] ?? settings.aliases[rawID] ?? group.name
                cpu = group.cpuPercent; memory = group.memoryBytes.map { Double($0) }; partial = partial || group.partial
                methods = Set(processes.filter { $0.memoryBytes != nil }.map(\.memoryMethod))
            }
            var value = HistoryAggregate(entityID:entityID,name:name,start:snapshot.timestamp,resolution:resolution)
            value.samples = 1; value.cadences = [snapshot.cadence]; value.partial = partial
            if interval.continuous {
                let duration = max(0,min(interval.seconds,resolution))
                value.observedSeconds = duration
                if let cpu, cpu.isFinite { value.cpuObservedSeconds = duration; value.cpu.add(cpu) }
                if let memory, memory.isFinite { value.memoryObservedSeconds = duration; value.memory.add(memory); value.memoryMethods = methods }
                if entityID == "system" {
                    if snapshot.system.loadAverage.count >= 3 { value.load1.add(snapshot.system.loadAverage[0]); value.load5.add(snapshot.system.loadAverage[1]); value.load15.add(snapshot.system.loadAverage[2]) }
                    value.swap.add(snapshot.system.memory.swapUsed.map { Double($0) }); value.pressureStates.insert(snapshot.system.memory.pressure)
                }
            } else { value.gapSeconds = max(0,interval.seconds) }
            return value
        }
        recentHistoryCache = (entityID,values)
        return values
    }
    /// Includes entities that exited during the bounded recent observation window.
    public func recentHistoryEntities() -> [String:String] {
        if let cache = recentEntitiesCache { return cache }
        var result = ["system":"System"]
        for snapshot in recent {
            for process in snapshot.processes {
                let appID = "app:" + process.applicationID
                result[appID] = settings.aliases[appID] ?? settings.aliases[process.applicationID] ?? process.applicationName
                if let path = process.projectPath {
                    let projectID = "project:" + path
                    result[projectID] = settings.aliases[projectID] ?? settings.aliases[path] ?? URL(fileURLWithPath:path).lastPathComponent
                }
            }
        }
        recentEntitiesCache = result
        return result
    }
    public func recordAction(_ record: ActionRecord) { guard !settings.paused, !excludedAlertIDs.contains(record.targetID), !settings.excludedApplications.contains(record.targetID), !settings.excludedProjects.contains(record.targetID) else { return }; actions.append(record); enforce(now:record.timestamp); if settings.retention != .off && settings.retention != nil && !settings.paused { save() } }
    public func recordAlerts(_ values: [AlertEvent]) { guard !settings.paused, !values.isEmpty else { return }; let isImportant = values.contains { $0.notificationEligible || $0.recoveredAt != nil }; for value in values where !settings.excludedApplications.contains(value.entityID) && !excludedAlertIDs.contains(value.entityID) && !excludedAlertIDs.contains(where: { value.entityID.hasPrefix($0 + ":") }) { if let i = alerts.firstIndex(where: { $0.id == value.id }) { alerts[i] = value } else { alerts.append(value) } }; if let now = values.map(\.updatedAt).max() { enforce(now:now); if settings.retention != .off && settings.retention != nil && (isImportant || lastAlertWrite.map { now.timeIntervalSince($0) >= 60 } ?? true) { save(); lastAlertWrite = now } } }
    /// Expires the RAM window even while collection is paused.
    @discardableResult public func expireRecent(now: Date = Date()) -> Bool {
        let oldCount = recent.count
        recent.removeAll { now.timeIntervalSince($0.timestamp) > 900 }
        guard oldCount != recent.count else { return false }
        let timestamps = Set(recent.map(\.timestamp))
        recentIntervals = recentIntervals.filter { timestamps.contains($0.key) }
        recentHistoryCache = nil; recentEntitiesCache = nil
        if recent.isEmpty { excludedAlertIDs.removeAll() }
        return true
    }
    public func suspendObservation() { observationInterrupted = true; clearQueryCache() }
    public func clearMemory() { clearQueryCache(); recent.removeAll(); recentIntervals.removeAll(); recentHistoryCache = nil; recentEntitiesCache = nil; excludedAlertIDs.removeAll(); observationInterrupted = true; if settings.retention == .off || settings.retention == nil { alerts.removeAll(); actions.removeAll() } }
    public func clear() {
        aggregates.removeAll(); catalog.removeAll(); tokens.removeAll(); entityRecords.removeAll(); workingName = nil; workingCommittedIDs.removeAll(); entityListCache = nil; clearQueryCache(); revision &+= 1
        alerts.removeAll(); actions.removeAll(); recent.removeAll(); recentIntervals.removeAll(); recentHistoryCache = nil; recentEntitiesCache = nil; excludedAlertIDs.removeAll(); previous = nil; observationInterrupted = false; shortened = false; failure = nil
        do { try validateDirectory(); if FileManager.default.fileExists(atPath:directory.path) { for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where url.lastPathComponent == "history.aesgcm" || url.lastPathComponent.hasPrefix("bucket-") || url.lastPathComponent.hasPrefix(".cipher-") { try FileManager.default.removeItem(at:url) } }; aggregateIndex.removeAll(); dirtySegments.removeAll(); stagedWrites = 0; bytes = 0; if settings.retention != nil { try persist() } } catch { failure = "Could not clear the encrypted history store." }
    }
    public func flush() { guard settings.retention != nil else { return }; save() }
    private func readRows(_ logical: String, using key: SymmetricKey) throws -> [HistoryAggregate] {
        if logical == workingName { return aggregates }
        return try catalog[logical].map { try readBucket($0,using:key) } ?? []
    }
    private func stage(_ rows: [HistoryAggregate], logical: String, using key: SymmetricKey) throws {
        if rows.isEmpty { catalog.removeValue(forKey:logical); if logical == workingName { aggregates.removeAll(); workingCommittedIDs.removeAll(); rebuildAggregateIndex() }; revision &+= 1; entityListCache = nil; clearQueryCache(); return }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let path = String(logical.dropLast(7)) + "-" + UUID().uuidString + ".aesgcm"
        let data = try encrypt(rows,using:key)
        try writeCiphertext(data,to:directory.appendingPathComponent(path))
        var entry = try describe(rows,path:path,bytes:data.count)
        entry.migration = false
        catalog[logical] = entry
        if logical == workingName { aggregates = rows; rebuildAggregateIndex(); dirtySegments.remove(logical) }
        stagedWrites += 1; revision &+= 1; entityListCache = nil
    }
    private func merge(_ value: HistoryAggregate, into result: inout HistoryAggregate) {
        result.cpu.merge(value.cpu); result.memory.merge(value.memory); result.memoryMethods.formUnion(value.memoryMethods); result.cpuObservedSeconds += value.cpuObservedSeconds; result.memoryObservedSeconds += value.memoryObservedSeconds; result.metricCoverageEstimated = result.metricCoverageEstimated || value.metricCoverageEstimated; result.load1.merge(value.load1); result.load5.merge(value.load5); result.load15.merge(value.load15); result.swap.merge(value.swap); result.pressureStates.formUnion(value.pressureStates); result.samples += value.samples; result.observedSeconds += value.observedSeconds; result.gapSeconds += value.gapSeconds; result.cadences.formUnion(value.cadences); result.partial = result.partial || value.partial
    }
    private func enforce(now: Date, using loadKey: SymmetricKey? = nil) {
        guard failure == nil else { return }
        guard let retention = settings.retention, retention != .off else { catalog.removeAll(); aggregates.removeAll(); aggregateIndex.removeAll(); workingName = nil; workingCommittedIDs.removeAll(); tokens.removeAll(); entityRecords.removeAll(); nextToken = 0; clearQueryCache(); entityListCache = nil; alerts.removeAll { now.timeIntervalSince($0.updatedAt) > 900 }; actions.removeAll { now.timeIntervalSince($0.timestamp) > 900 }; return }
        let cutoff = now.addingTimeInterval(-retention.seconds)
        alerts.removeAll { $0.updatedAt < cutoff }; actions.removeAll { $0.timestamp < cutoff }
        do {
            var key = loadKey
            func getKey() throws -> SymmetricKey { if let key { return key }; let fetched = try keyProvider.existingKey(); key = fetched; return fetched }
            if let name = workingName, dirtySegments.contains(name) {
                aggregates.removeAll { $0.start.addingTimeInterval($0.resolution) <= cutoff }
                workingCommittedIDs.formIntersection(aggregates.map(\.id))
                if !aggregates.isEmpty { _ = try describe(aggregates,path:catalog[name]?.path ?? "",bytes:catalog[name]?.bytes ?? 0) }
            }
            for name in catalog.keys.sorted() {
                let entry = catalog[name]!
                if entry.end <= cutoff { catalog.removeValue(forKey:name); if name == workingName { aggregates.removeAll(); workingName = nil; workingCommittedIDs.removeAll(); rebuildAggregateIndex() }; revision &+= 1; entityListCache = nil }
                else if entry.first < cutoff {
                    let rows = try readRows(name,using:getKey()).filter { $0.start.addingTimeInterval($0.resolution) > cutoff }
                    if rows.count != entry.count { try stage(rows,logical:name,using:getKey()) }
                }
            }
            let boundary = now.addingTimeInterval(-86400)
            var hours: [Int64:[String]] = [:]
            for (name,entry) in catalog where entry.first < boundary {
                let hour = Int64(floor(entry.first.timeIntervalSince1970 / 3600))
                hours[hour,default:[]].append(name)
            }
            for hour in hours.keys.sorted() {
                let names = hours[hour]!
                if names.count == 1, let entry = catalog[names[0]], entry.resolution == 3600, !entry.noncanonical, !entry.migration { continue }
                var merged: [String:HistoryAggregate] = [:]
                var kept: [String:[HistoryAggregate]] = [:]
                for name in names.sorted(by: { catalog[$0]!.first == catalog[$1]!.first ? $0 < $1 : catalog[$0]!.first < catalog[$1]!.first }) {
                    for value in try readRows(name,using:getKey()) {
                        guard value.start < boundary else { kept[name,default:[]].append(value); continue }
                        let start = Date(timeIntervalSince1970:floor(value.start.timeIntervalSince1970 / 3600) * 3600)
                        let resultKey = value.entityID + ":" + String(start.timeIntervalSince1970)
                        var result = merged[resultKey] ?? HistoryAggregate(entityID:value.entityID,name:value.name,start:start,resolution:3600)
                        merge(value,into:&result); merged[resultKey] = result
                    }
                }
                for name in names { catalog.removeValue(forKey:name); if name == workingName { aggregates = kept[name] ?? []; workingCommittedIDs.formIntersection(aggregates.map(\.id)); rebuildAggregateIndex() } }
                for (name,rows) in kept { try stage(rows,logical:name,using:getKey()) }
                let output = Dictionary(grouping:merged.values,by:segmentName)
                for (name,rows) in output { try stage(rows,logical:name,using:getKey()) }
                revision &+= 1; entityListCache = nil
            }
        } catch { unavailable() }
    }
    private func rebuildAggregateIndex() {
        aggregateIndex.removeAll(keepingCapacity: true)
        aggregateIndex.reserveCapacity(aggregates.count)
        for index in aggregates.indices {
            let replaced = aggregateIndex.updateValue(index, forKey: aggregates[index].id)
            precondition(replaced == nil)
        }
    }
    private func save() { guard failure == nil, settings.retention != nil else { return }; do { try persist(); failure = nil } catch { clearQueryCache(); failure = "Encrypted history could not be saved. No plaintext fallback." } }
    private func validateDirectory() throws {
        var info = stat()
        if lstat(directory.path,&info) == 0 { guard info.st_mode & S_IFMT == S_IFDIR else { throw HistoryStorageError.unsafePath } }
        if lstat(file.path,&info) == 0 { guard info.st_mode & S_IFMT == S_IFREG else { throw HistoryStorageError.unsafePath } }
    }
    private func validateRegular(_ url: URL) throws {
        var info = stat(); guard lstat(url.path,&info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw HistoryStorageError.unsafePath }
    }
    private func segmentName(_ value: HistoryAggregate) -> String { "bucket-\(Int64(value.start.timeIntervalSince1970))-\(Int(value.resolution)).aesgcm" }
    private func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        guard data.prefix(4) == Data("AMID".utf8) else { throw HistoryStorageError.invalidEnvelope }
        return try AES.GCM.open(AES.GCM.SealedBox(combined:data.dropFirst(4)),using:key,authenticating:Data("AMID".utf8))
    }
    private func encrypt<T:Encodable>(_ value: T, using key: SymmetricKey) throws -> Data {
        let plain = try JSONEncoder().encode(value)
        return Data("AMID".utf8) + (try AES.GCM.seal(plain,using:key,authenticating:Data("AMID".utf8)).combined!)
    }
    private func hasSignedZero(_ value: HistoryAggregate) -> Bool {
        func negativeZero(_ value: Double) -> Bool { value == 0 && value.sign == .minus }
        return negativeZero(value.cpu.sum) || negativeZero(value.memory.sum) || negativeZero(value.load1.sum) || negativeZero(value.load5.sum) || negativeZero(value.load15.sum) || negativeZero(value.swap.sum) || negativeZero(value.observedSeconds) || negativeZero(value.gapSeconds) || negativeZero(value.cpuObservedSeconds) || negativeZero(value.memoryObservedSeconds)
    }
    private func persist(using loadKey: SymmetricKey? = nil) throws {
        try validateDirectory()
        let key: SymmetricKey
        if let loadKey { key = loadKey } else { key = try keyProvider.key() }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        if let name = workingName, dirtySegments.contains(name) { try stage(aggregates,logical:name,using:key) }
        var next = catalog
        let enabled = settings.retention != .off && settings.retention != nil
        if !enabled { next.removeAll() }
        memoryObserver?(.grouped, aggregateCount, 0)
        memoryObserver?(.encoded, aggregateCount, stagedWrites)
        func encodedManifest() throws -> Data {
            try encrypt(Archive(settings:settings,aggregates:[],alerts:enabled ? alerts : [],actions:enabled ? actions : [],shortenedByCap:shortened,segmentFiles:next.values.map(\.path).sorted()),using:key)
        }
        var manifest = try encodedManifest()
        var size = next.values.reduce(0) { $0 + $1.bytes }
        let oldest = next.keys.sorted { next[$0]!.first < next[$1]!.first }
        var oldestIndex = 0
        while manifest.count + size > maxBytes {
            shortened = true
            if oldestIndex < oldest.count { let removed = next.removeValue(forKey:oldest[oldestIndex])!; size -= removed.bytes; oldestIndex += 1 }
            else if !alerts.isEmpty { alerts.removeFirst() }
            else if !actions.isEmpty { actions.removeFirst() }
            else { throw HistoryStorageError.invalidEnvelope }
            manifest = try encodedManifest()
        }
        // All provisional files are ciphertext; no full encoded archive is held in memory.
        try synchronizeDirectory()
        try commitObserver(.generationsDurable)
        try writeCiphertext(manifest,to:file)
        try synchronizeDirectory()
        try commitObserver(.manifestDurable)
        let activePaths = Set(next.values.map(\.path))
        for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where (url.lastPathComponent.hasPrefix("bucket-") && !activePaths.contains(url.lastPathComponent)) || url.lastPathComponent.hasPrefix(".cipher-") { try FileManager.default.removeItem(at:url) }
        try synchronizeDirectory()
        memoryObserver?(.written, aggregateCount, stagedWrites)
        if catalog.keys.contains(where:{next[$0] == nil}) { revision &+= 1; entityListCache = nil }
        catalog = next
        if let name = workingName, catalog[name] == nil { aggregates.removeAll(); workingName = nil; workingCommittedIDs.removeAll(); rebuildAggregateIndex() }
        workingCommittedIDs = Set(aggregates.map(\.id))
        dirtySegments.removeAll(); stagedWrites = 0; bytes = manifest.count + size
        let active = Set(catalog.values.flatMap(\.members)).union(aggregates.compactMap { tokens[$0.entityID] })
        entityRecords = entityRecords.filter { active.contains($0.key) }; tokens = tokens.filter { active.contains($0.value) }
        memoryObserver?(.indexReady, aggregateCount, 0)
    }
    private func synchronizeDirectory() throws {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
    private func writeCiphertext(_ encoded: Data, to destination: URL) throws {
        let staging = directory.appendingPathComponent(".cipher-" + UUID().uuidString)
        let descriptor = open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor); try? FileManager.default.removeItem(at:staging) }
        try encoded.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor,buffer.baseAddress!.advanced(by:offset),buffer.count-offset)
                guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(staging.path,destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
