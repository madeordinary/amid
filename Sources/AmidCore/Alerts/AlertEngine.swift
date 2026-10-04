import Foundation

public enum AlertCategory: String, Codable, Sendable, CaseIterable {
    case memoryPressure, appCPU, appMemoryGrowth, swapGrowth, diskCapacity, lowActivityServer
    public var title: String { switch self { case .memoryPressure: localized("Memory pressure"); case .appCPU: localized("Sustained CPU"); case .appMemoryGrowth: localized("Memory increased"); case .swapGrowth: localized("Swap increased"); case .diskCapacity: localized("Startup capacity"); case .lowActivityServer: localized("Low observed CPU") } }
}
public struct AlertSettings: Sendable, Equatable {
    public var enabledRules: Set<AlertCategory>
    public var excludedApplications: Set<String>
    public var diskThresholdBytes: UInt64
    public init(enabledRules: Set<AlertCategory> = Set(AlertCategory.allCases), excludedApplications: Set<String> = [], diskThresholdBytes: UInt64 = 10 * 1024 * 1024 * 1024) { self.enabledRules = enabledRules; self.excludedApplications = excludedApplications; self.diskThresholdBytes = diskThresholdBytes }
}
public struct AlertEvent: Codable, Sendable, Identifiable {
    public var id: UUID
    public var category: AlertCategory
    public var entityID: String
    public var title: String
    public var detail: String
    public var startedAt: Date
    public var updatedAt: Date
    public var recoveredAt: Date?
    public var observationSuspended: Bool = false
    public var lastNotificationAt: Date? = nil
    public var dismissedAt: Date? = nil
    public var notificationEligible: Bool
}
public actor AlertEngine {
    private struct Point: Sendable { var time: Date; var value: Double; var method: MemoryMethod = .unavailable }
    private var settings: AlertSettings
    private var windows: [String:[Point]] = [:]
    private var retained: [AlertEvent] = []
    private var lastNotification: [String:Date] = [:]
    private var lastSample: Date?
    private var normalSince: Date?
    private func suspend(_ category: AlertCategory? = nil, entity: String? = nil) { for i in retained.indices where retained[i].recoveredAt == nil && (category == nil || retained[i].category == category) && (entity == nil || retained[i].entityID == entity) { retained[i].observationSuspended = true; retained[i].notificationEligible = false } }
    private var listenerSince: [String:Date] = [:]
    public init(settings: AlertSettings = .init()) { self.settings = settings }
    public func updateSettings(_ value: AlertSettings) { guard settings != value else { return }; settings = value; suspendObservation() }
    public func events() -> [AlertEvent] { retained }
    public func dismiss(_ id: UUID, at date: Date = Date()) -> AlertEvent? {
        guard let i = retained.firstIndex(where: { $0.id == id }) else { return nil }
        retained[i].dismissedAt = date; retained[i].updatedAt = date; retained[i].notificationEligible = false
        return retained[i]
    }
    public func suspendObservation() { suspend(); windows.removeAll(); listenerSince.removeAll(); normalSince = nil; lastSample = nil }
    public func restore(events: [AlertEvent]) {
        retained = events
        for event in events {
            let key = event.category.rawValue + ":" + event.entityID
            if let time = event.lastNotificationAt, time > (lastNotification[key] ?? .distantPast) { lastNotification[key] = time }
        }
        suspendObservation()
    }
    public func reset() { windows.removeAll(); listenerSince.removeAll(); retained.removeAll(); lastNotification.removeAll(); lastSample = nil; normalSince = nil }
    public func evaluate(_ snapshot: Snapshot) -> [AlertEvent] {
        let now = snapshot.timestamp
        if let lastSample, now <= lastSample { return [] }
        let discontinuity = lastSample.map { now.timeIntervalSince($0) > max(30,(snapshot.expectedCadence ?? snapshot.cadence) * 2.5) } ?? false
        self.lastSample = now
        guard snapshot.availability == .available else { suspend(); windows.removeAll(); listenerSince.removeAll(); normalSince = nil; return [] }
        if discontinuity { suspend(); windows.removeAll(); listenerSince.removeAll(); normalSince = nil }
        var updates: [AlertEvent] = []
        var seen = Set<String>()
        func observe(_ category: AlertCategory, _ entity: String, _ value: Double?, _ duration: Double, _ method: MemoryMethod = .unavailable, condition: ([Point]) -> Bool, recoveryCondition: (([Point]) -> Bool)? = nil, detail: @autoclosure () -> String) {
            let key = category.rawValue + ":" + entity; seen.insert(key)
            guard settings.enabledRules.contains(category), let value, value.isFinite else { windows.removeValue(forKey:key); suspend(category,entity:entity); return }
            var points = windows[key] ?? []
            if let first = points.first, method != .unavailable && first.method != method { points = []; suspend(category,entity:entity) }
            points.append(Point(time:now,value:value,method:method))
            while points.count > 1 && now.timeIntervalSince(points[1].time) >= duration { points.removeFirst() }
            windows[key] = points
            let satisfied = now.timeIntervalSince(points[0].time) >= duration && condition(points)
            if satisfied {
                if let index = retained.lastIndex(where: { $0.category == category && $0.entityID == entity && $0.recoveredAt == nil }) { retained[index].updatedAt = now; retained[index].detail = detail(); retained[index].observationSuspended = false; retained[index].notificationEligible = false; if retained[index].dismissedAt == nil { updates.append(retained[index]) } }
                else {
                    let eligible = category != .lowActivityServer && (lastNotification[key].map { now.timeIntervalSince($0) >= 3600 } ?? true)
                    if eligible { lastNotification[key] = now }
                    var event = AlertEvent(id:UUID(),category:category,entityID:entity,title:category.title,detail:detail(),startedAt:points[0].time,updatedAt:now,recoveredAt:nil,notificationEligible:eligible)
                    event.lastNotificationAt = eligible ? now : lastNotification[key]
                    retained.append(event); updates.append(event)
                }
            } else if category != .memoryPressure, (category == .diskCapacity || now.timeIntervalSince(points[0].time) >= duration), let index = retained.lastIndex(where: { $0.category == category && $0.entityID == entity && $0.recoveredAt == nil }), (recoveryCondition?(points) ?? !condition(category == .diskCapacity ? [Point(time:now,value:value,method:method)] : points)) { retained[index].observationSuspended = false; retained[index].recoveredAt = now; retained[index].updatedAt = now; retained[index].notificationEligible = false; updates.append(retained[index]) }
        }
        let pressure = snapshot.system.memory.pressure
        observe(.memoryPressure,"system", pressure == .unknown ? nil : (pressure == .normal ? 0 : 1),60,condition: { $0.allSatisfy { $0.value == 1 } },detail:localized("Warning or critical memory pressure sustained for 60 seconds."))
        if pressure == .normal { if normalSince == nil { normalSince = now }; if now.timeIntervalSince(normalSince!) >= 300, let i = retained.lastIndex(where: { $0.category == .memoryPressure && $0.recoveredAt == nil }) { retained[i].recoveredAt = now; retained[i].updatedAt = now; retained[i].notificationEligible = false; updates.append(retained[i]) } } else { normalSince = nil }
        observe(.swapGrowth,"system", pressure == .warning || pressure == .critical ? snapshot.system.memory.swapUsed.map { Double($0) } : nil,900,condition: { ($0.last!.value - $0.first!.value) >= 1073741824 },detail:localized("Swap increased at least 1 GiB over 15 minutes with warning or critical pressure."))
        if pressure == .normal, snapshot.system.memory.swapUsed != nil, let i = retained.lastIndex(where: { $0.category == .swapGrowth && $0.recoveredAt == nil }) {
            retained[i].observationSuspended = false; retained[i].recoveredAt = now; retained[i].updatedAt = now; retained[i].notificationEligible = false; updates.append(retained[i])
        }
        for group in ResourceGroup.applications(snapshot, sortedByMemory: false) where !settings.excludedApplications.contains(group.id) {
            let memoryMethod = group.memoryMethod
            let cpu = group.processes.contains { $0.cpuPercent == nil } ? nil : group.cpuPercent
            observe(.appCPU,group.id,cpu,300,condition: { points in
                guard points.count > 1 else { return points[0].value >= Double(snapshot.system.logicalCPUCount) * 25 }
                var weighted = 0.0; var elapsed = 0.0
                for index in 1..<points.count { let dt = points[index].time.timeIntervalSince(points[index-1].time); weighted += points[index-1].value * dt; elapsed += dt }
                return elapsed > 0 && weighted / elapsed >= Double(snapshot.system.logicalCPUCount) * 25
            },detail:localizedFormat("%@: raw CPU %@%% of one core; threshold 25%% of %ld logical cores averaged over five minutes.",group.name,String(cpu ?? 0),snapshot.system.logicalCPUCount))
            observe(.appMemoryGrowth,group.id,group.processes.contains { $0.memoryBytes == nil } || (memoryMethod == .mixed || memoryMethod == .unavailable) ? nil : group.memoryBytes.map { Double($0) },1800,memoryMethod,condition: { $0.count > 1 && $0.last!.value - $0.first!.value >= 1073741824 && $0.last!.value >= $0.first!.value * 1.25 },detail:localizedFormat("%@ memory increased at least 1 GiB and 25%% over 30 continuously observed minutes (%@).",group.name,localized(memoryMethod.rawValue)))
        }
        for volume in snapshot.system.volumes where volume.isStartup {
            observe(.diskCapacity,volume.id,volume.available.map { Double($0) },300,condition: { $0.allSatisfy { $0.value < Double(settings.diskThresholdBytes) } },detail:localizedFormat("Available capacity below %llu bytes for five minutes. %@",settings.diskThresholdBytes,volume.definition))
        }
        var listeners = Set<String>()
        for process in snapshot.processes where process.projectPath != nil && !process.endpoints.isEmpty && process.portAvailability == .available && !settings.excludedApplications.contains(process.applicationID) && ["node", "node.js", "python", "swift"].contains(process.runtime?.lowercased() ?? "") {
            guard let cpu = process.cpuPercent else { continue }
            let identity = process.id + ":" + process.endpoints.map(\.id).sorted().joined(separator:",")
            listeners.insert(identity)
            if listenerSince[identity] == nil { listenerSince[identity] = now }
            func average(_ points: [Point]) -> Double? {
                var sum = 0.0; var duration = 0.0
                for i in 1..<points.count { let dt = points[i].time.timeIntervalSince(points[i-1].time); sum += points[i-1].value * dt; duration += dt }
                return duration > 0 ? sum / duration : nil
            }
            observe(.lowActivityServer,identity,cpu,1800,condition: { points in
                guard now.timeIntervalSince(listenerSince[identity] ?? now) >= 7200, let value = average(points) else { return false }
                return value < 1
            },recoveryCondition: { points in
                guard let value = average(points) else { return false }
                return value >= 1
            },detail:localizedFormat("%@: continuously observed native development listener for at least 2 hours; average CPU below 1%% of one core in the last 30 minutes. No client or traffic measurement is implied.",process.name))
        }
        for identity in Array(listenerSince.keys) where !listeners.contains(identity) { listenerSince.removeValue(forKey:identity) }
        for key in Array(windows.keys) where !seen.contains(key) { windows.removeValue(forKey:key); for i in retained.indices where retained[i].category.rawValue + ":" + retained[i].entityID == key && retained[i].recoveredAt == nil { retained[i].observationSuspended = true; retained[i].notificationEligible = false } }
        for i in updates.indices where updates[i].category == .appCPU {
            let points = windows[AlertCategory.appCPU.rawValue + ":" + updates[i].entityID] ?? []
            var sum = 0.0; var elapsed = 0.0
            for j in 1..<points.count { let dt = points[j].time.timeIntervalSince(points[j-1].time); sum += points[j-1].value * dt; elapsed += dt }
            let raw = elapsed > 0 ? sum / elapsed : 0
            updates[i].detail = localizedFormat("Five-minute average %.1f%% of one core; %.1f%% of total %ld logical-core capacity.",raw,raw / Double(max(1,snapshot.system.logicalCPUCount)),snapshot.system.logicalCPUCount)
            if let index = retained.firstIndex(where: { $0.id == updates[i].id }) { retained[index].detail = updates[i].detail }
        }
        retained.removeAll { now.timeIntervalSince($0.updatedAt) > 2592000 }
        return updates
    }
}


extension AlertEvent {
    private enum CodingKeys: String, CodingKey { case id, category, entityID, title, detail, startedAt, updatedAt, recoveredAt, notificationEligible, observationSuspended, lastNotificationAt, dismissedAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(UUID.self,forKey:.id); category = try c.decode(AlertCategory.self,forKey:.category)
        entityID = try c.decode(String.self,forKey:.entityID); title = try c.decode(String.self,forKey:.title); detail = try c.decode(String.self,forKey:.detail)
        startedAt = try c.decode(Date.self,forKey:.startedAt); updatedAt = try c.decode(Date.self,forKey:.updatedAt)
        recoveredAt = try c.decodeIfPresent(Date.self,forKey:.recoveredAt)
        notificationEligible = try c.decodeIfPresent(Bool.self,forKey:.notificationEligible) ?? false
        observationSuspended = try c.decodeIfPresent(Bool.self,forKey:.observationSuspended) ?? true
        lastNotificationAt = try c.decodeIfPresent(Date.self,forKey:.lastNotificationAt)
        dismissedAt = try c.decodeIfPresent(Date.self,forKey:.dismissedAt)
    }
}
