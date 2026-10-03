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
    private var aggregateIndex: [String:Int] = [:]
    private var dirtySegments = Set<String>()
    private var segmentSizes: [String:Int] = [:]
    private var segmentPaths: [String:String] = [:]
    private var excludedAlertIDs = Set<String>()
    private var lastAlertWrite: Date?
    public init(directory: URL, keyProvider: any HistoryKeyProvider = KeychainHistoryKeyProvider(), maxBytes: Int = 250 * 1024 * 1024) { self.directory = directory; self.keyProvider = keyProvider; self.maxBytes = max(1024,maxBytes); self.commitObserver = { _ in }; self.memoryObserver = nil; self.loadReferenceDate = nil }
    init(directory: URL, keyProvider: any HistoryKeyProvider, maxBytes: Int = 250 * 1024 * 1024, commitObserver: @escaping @Sendable (HistoryCommitStage) throws -> Void, memoryObserver: (@Sendable (HistoryMemoryStage, Int, Int) -> Void)? = nil, loadReferenceDate: Date? = nil) { self.directory = directory; self.keyProvider = keyProvider; self.maxBytes = max(1024,maxBytes); self.commitObserver = commitObserver; self.memoryObserver = memoryObserver; self.loadReferenceDate = loadReferenceDate }
    private var file: URL { directory.appendingPathComponent("history.aesgcm") }
    public func load() {
        autoreleasepool { loadWithinPool() }
        memoryObserver?(.loadReturned, aggregates.count, 0)
    }
    private func loadWithinPool() {
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        do {
            let loadKey = try autoreleasepool { try decodeAndAssignArchive() }
            memoryObserver?(.decodeReturned, aggregates.count, 0)
            autoreleasepool {
                enforce(now:loadReferenceDate ?? Date())
                memoryObserver?(.enforced, aggregates.count, 0)
            }
            memoryObserver?(.enforceReturned, aggregates.count, 0)
            try autoreleasepool { try persist(using: loadKey) }
        } catch { failure = "Encrypted history unavailable. Unlock Keychain or clear the app-owned store to recover. No plaintext fallback." }
    }
    private func decodeAndAssignArchive() throws -> SymmetricKey {
        try validateDirectory()
        let encrypted = try Data(contentsOf:file)
        guard encrypted.prefix(4) == Data("AMID".utf8) else { throw HistoryStorageError.invalidEnvelope }
        let loadKey = try keyProvider.existingKey()
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined:encrypted.dropFirst(4)),using:loadKey,authenticating:Data("AMID".utf8))
        let archive = try JSONDecoder().decode(Archive.self,from:clear)
        guard (1...3).contains(archive.version) else { throw HistoryStorageError.unsupportedVersion(archive.version) }
        var loaded = archive.aggregates
        var loadedSizes: [String:Int] = [:]
        var loadedPaths: [String:String] = [:]
        if archive.version == 3 {
            guard let files = archive.segmentFiles else { throw HistoryStorageError.invalidEnvelope }
            for name in files {
                guard name.hasPrefix("bucket-"), name.hasSuffix(".aesgcm"), !name.contains("/"), !name.contains("..") else { throw HistoryStorageError.invalidEnvelope }
                let url = directory.appendingPathComponent(name)
                try validateRegular(url)
                let data = try Data(contentsOf:url)
                let decoded = try decrypt(data,using:loadKey)
                let bucket = try JSONDecoder().decode([HistoryAggregate].self,from:decoded)
                guard let first = bucket.first, bucket.allSatisfy({ segmentName($0) == segmentName(first) }), loadedPaths[segmentName(first)] == nil else { throw HistoryStorageError.invalidEnvelope }
                loaded += bucket
                loadedSizes[segmentName(first)] = data.count; loadedPaths[segmentName(first)] = name
            }
        }
        memoryObserver?(.decoded, loaded.count, 0)
        guard Set(loaded.map(\.id)).count == loaded.count else { throw HistoryStorageError.invalidEnvelope }
        memoryObserver?(.validated, loaded.count, 0)
        settings = archive.settings; aggregates = loaded; segmentSizes = loadedSizes; segmentPaths = loadedPaths
        memoryObserver?(.assigned, aggregates.count, 0)
        dirtySegments = archive.version < 3 ? Set(aggregates.map(segmentName)) : Set(archive.aggregates.map(segmentName))
        for value in aggregates where value.requiresPersistenceMigration || excluded(value.entityID) { dirtySegments.insert(segmentName(value)) }
        aggregates.removeAll { excluded($0.entityID) }
        alerts = archive.alerts; actions = archive.actions; shortened = archive.shortenedByCap; bytes = encrypted.count; failure = nil
        return loadKey
    }
    public func state() -> HistoryState { HistoryState(settings:settings,aggregates:aggregates,alerts:alerts,actions:actions,recentSnapshots:recent,storageBytes:bytes,shortenedByCap:shortened,error:failure) }
    public func updateSettings(_ value: HistorySettings, now: Date = Date()) {
        let changedApps = settings.excludedApplications != value.excludedApplications
        let changedProjects = settings.excludedProjects != value.excludedProjects
        dirtySegments.formUnion(aggregates.map(segmentName))
        settings = value
        recentHistoryCache = nil; recentEntitiesCache = nil
        if let latest = recent.last { excludedAlertIDs = excludedEntities(in:latest) }
        if changedApps { aggregates.removeAll { $0.entityID.hasPrefix("project:") } }
        if changedProjects { aggregates.removeAll { $0.entityID.hasPrefix("app:") } }
        aggregates.removeAll { excluded($0.entityID) }
        alerts.removeAll {
            settings.excludedApplications.contains($0.entityID) || isExcludedEntity($0.entityID) ||
            (changedProjects && [.appCPU, .appMemoryGrowth, .lowActivityServer].contains($0.category))
        }
        actions.removeAll { isExcludedEntity($0.targetID) || (changedProjects && !settings.excludedProjects.isEmpty) }
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
    public func suspendObservation() { observationInterrupted = true }
    public func clearMemory() { recent.removeAll(); recentIntervals.removeAll(); recentHistoryCache = nil; recentEntitiesCache = nil; excludedAlertIDs.removeAll(); observationInterrupted = true; if settings.retention == .off || settings.retention == nil { alerts.removeAll(); actions.removeAll() } }
    public func clear() { aggregates.removeAll(); alerts.removeAll(); actions.removeAll(); recent.removeAll(); recentIntervals.removeAll(); recentHistoryCache = nil; recentEntitiesCache = nil; excludedAlertIDs.removeAll(); previous = nil; observationInterrupted = false; shortened = false; failure = nil; do { try validateDirectory(); if FileManager.default.fileExists(atPath:directory.path) { for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where url.lastPathComponent == "history.aesgcm" || url.lastPathComponent.hasPrefix("bucket-") || url.lastPathComponent.hasPrefix(".cipher-") { try FileManager.default.removeItem(at:url) } }; segmentSizes.removeAll(); segmentPaths.removeAll(); aggregateIndex.removeAll(); dirtySegments.removeAll(); bytes = 0; if settings.retention != nil { try persist() } } catch { failure = "Could not clear the encrypted history store." } }
    public func flush() { guard settings.retention != nil else { return }; save() }
    private func enforce(now: Date) {
        guard let retention = settings.retention, retention != .off else { aggregates.removeAll(); aggregateIndex.removeAll(); alerts.removeAll { now.timeIntervalSince($0.updatedAt) > 900 }; actions.removeAll { now.timeIntervalSince($0.timestamp) > 900 }; return }
        let cutoff = now.addingTimeInterval(-retention.seconds)
        aggregates.removeAll { $0.start.addingTimeInterval($0.resolution) <= cutoff }
        alerts.removeAll { $0.updatedAt < cutoff }; actions.removeAll { $0.timestamp < cutoff }
        var hourly: [String:HistoryAggregate] = [:]; var minute: [HistoryAggregate] = []
        for value in aggregates {
            guard value.start < now.addingTimeInterval(-86400) else { minute.append(value); continue }
            let hour = Date(timeIntervalSince1970:floor(value.start.timeIntervalSince1970 / 3600) * 3600)
            if value.resolution != 3600 || value.start != hour || hasSignedZero(value) { dirtySegments.insert("bucket-\(Int64(hour.timeIntervalSince1970))-3600.aesgcm") }
            let key = value.entityID + ":" + String(hour.timeIntervalSince1970)
            var result = hourly[key] ?? HistoryAggregate(entityID:value.entityID,name:value.name,start:hour,resolution:3600)
            result.cpu.merge(value.cpu); result.memory.merge(value.memory); result.memoryMethods.formUnion(value.memoryMethods); result.cpuObservedSeconds += value.cpuObservedSeconds; result.memoryObservedSeconds += value.memoryObservedSeconds; result.metricCoverageEstimated = result.metricCoverageEstimated || value.metricCoverageEstimated; result.load1.merge(value.load1); result.load5.merge(value.load5); result.load15.merge(value.load15); result.swap.merge(value.swap); result.pressureStates.formUnion(value.pressureStates); result.samples += value.samples; result.observedSeconds += value.observedSeconds; result.gapSeconds += value.gapSeconds; result.cadences.formUnion(value.cadences); result.partial = result.partial || value.partial
            hourly[key] = result
        }
        let changed = hourly.values
        aggregates = (minute + changed).sorted { $0.start < $1.start }
        aggregateIndex = Dictionary(uniqueKeysWithValues:aggregates.enumerated().map { ($0.element.id,$0.offset) })
    }
    private func save() { guard failure == nil, settings.retention != nil else { return }; do { try persist(); failure = nil } catch { failure = "Encrypted history could not be saved. No plaintext fallback." } }
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
        var groups = Dictionary(grouping:aggregates,by:segmentName)
        memoryObserver?(.grouped, aggregates.count, 0)
        for name in groups.keys where segmentPaths[name] == nil { dirtySegments.insert(name) }
        var encodedSegments: [String:Data] = [:]
        for name in dirtySegments where groups[name] != nil { encodedSegments[name] = try encrypt(groups[name]!,using:key) }
        memoryObserver?(.encoded, aggregates.count, encodedSegments.count)
        let enabled = settings.retention != .off && settings.retention != nil
        var aggregateMembershipChanged = false
        if !enabled { groups.removeAll(); encodedSegments.removeAll(); aggregateMembershipChanged = true }
        var paths = segmentPaths
        for name in encodedSegments.keys { paths[name] = String(name.dropLast(7)) + "-" + UUID().uuidString + ".aesgcm" }
        var archive = Archive(settings:settings,aggregates:[],alerts:enabled ? alerts : [],actions:enabled ? actions : [],shortenedByCap:shortened,segmentFiles:groups.keys.compactMap { paths[$0] }.sorted())
        var manifest = try encrypt(archive,using:key)
        var sizes = groups.mapValues { values in encodedSegments[segmentName(values[0])]?.count ?? segmentSizes[segmentName(values[0])] ?? 0 }
        while manifest.count + sizes.values.reduce(0,+) > maxBytes {
            shortened = true
            if let oldest = groups.keys.min(by: { groups[$0]![0].start < groups[$1]![0].start }) { groups.removeValue(forKey:oldest); sizes.removeValue(forKey:oldest); encodedSegments.removeValue(forKey:oldest); aggregateMembershipChanged = true }
            else if !alerts.isEmpty { alerts.removeFirst() }
            else if !actions.isEmpty { actions.removeFirst() }
            else { throw HistoryStorageError.invalidEnvelope }
            archive = Archive(settings:settings,aggregates:[],alerts:enabled ? alerts : [],actions:enabled ? actions : [],shortenedByCap:shortened,segmentFiles:groups.keys.compactMap { paths[$0] }.sorted())
            manifest = try encrypt(archive,using:key)
        }
        for (name,data) in encodedSegments where groups[name] != nil { try writeCiphertext(data,to:directory.appendingPathComponent(paths[name]!)) }
        // New generation directory entries must be durable before a manifest can name them.
        try synchronizeDirectory()
        try commitObserver(.generationsDurable)
        try writeCiphertext(manifest,to:file)
        // Never remove an old generation until the replacement manifest is durable.
        try synchronizeDirectory()
        try commitObserver(.manifestDurable)
        let activePaths = Set(groups.keys.compactMap { paths[$0] })
        for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where (url.lastPathComponent.hasPrefix("bucket-") && !activePaths.contains(url.lastPathComponent)) || url.lastPathComponent.hasPrefix(".cipher-") { try FileManager.default.removeItem(at:url) }
        try synchronizeDirectory()
        memoryObserver?(.written, aggregates.count, encodedSegments.count)
        // Existing mutations maintain the index; preserve it when persistence changes no rows or order.
        if aggregateMembershipChanged || aggregates.indices.dropFirst().contains(where: { aggregates[$0-1].start > aggregates[$0].start }) {
            aggregates = groups.values.flatMap { $0 }.sorted { $0.start < $1.start }
            aggregateIndex = Dictionary(uniqueKeysWithValues:aggregates.enumerated().map { ($0.element.id,$0.offset) })
        }
        segmentSizes = sizes; segmentPaths = paths.filter { groups[$0.key] != nil }; dirtySegments.removeAll(); bytes = manifest.count + sizes.values.reduce(0,+)
        memoryObserver?(.indexReady, aggregates.count, encodedSegments.count)
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
