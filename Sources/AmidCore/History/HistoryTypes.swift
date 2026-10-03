import Foundation
import CryptoKit

public enum HistoryRetention: String, Codable, Sendable, CaseIterable {
    case off, day, week, month
    public var seconds: TimeInterval { switch self { case .off: 0; case .day: 86400; case .week: 604800; case .month: 2592000 } }
    public var title: String { switch self { case .off: localized("Off"); case .day: localized("24 hours"); case .week: localized("7 days"); case .month: localized("30 days") } }
}
public struct HistorySettings: Codable, Sendable {
    public var alertEnabledRules: [String] = AlertCategory.allCases.map(\.rawValue)
    public var diskThresholdBytes: UInt64 = 10 * 1024 * 1024 * 1024
    public var numericMenuMetric: String = "none"
    public var notificationsEnabled: Bool = false
    public var launchAtLogin: Bool = false
    public var updateChecks: Bool = false
    public var projectBoundaries: [String] = []
    public var retention: HistoryRetention?
    public var paused: Bool
    public var aliases: [String: String]
    public var excludedApplications: Set<String>
    public var excludedProjects: Set<String>
    public init(retention: HistoryRetention? = nil, paused: Bool = false, aliases: [String:String] = [:], excludedApplications: Set<String> = [], excludedProjects: Set<String> = []) {
        self.retention = retention; self.paused = paused; self.aliases = aliases; self.excludedApplications = excludedApplications; self.excludedProjects = excludedProjects
    }
}
public struct MetricAggregate: Codable, Sendable {
    public var count: Int = 0
    public var minimum: Double? = nil
    public var maximum: Double? = nil
    public var sum: Double = 0
    public var average: Double? { count > 0 ? sum / Double(count) : nil }
    public init() {}
    mutating func add(_ value: Double?) { guard let value, value.isFinite else { return }; count += 1; sum += value; minimum = min(minimum ?? value, value); maximum = max(maximum ?? value, value) }
    mutating func merge(_ other: Self) { count += other.count; sum += other.sum; if let v = other.minimum { minimum = min(minimum ?? v,v) }; if let v = other.maximum { maximum = max(maximum ?? v,v) } }
}
public struct HistoryAggregate: Codable, Sendable, Identifiable {
    public var id: String { "\(entityID):\(start.timeIntervalSince1970):\(resolution)" }
    public var entityID: String
    public var name: String
    public var start: Date
    public var resolution: TimeInterval
    public var cpu: MetricAggregate = .init()
    public var memory: MetricAggregate = .init()
    public var memoryMethods: Set<MemoryMethod> = []
    public var cpuObservedSeconds: Double = 0
    public var memoryObservedSeconds: Double = 0
    public var metricCoverageEstimated: Bool = false
    var requiresPersistenceMigration: Bool = false
    public var load1: MetricAggregate = .init()
    public var load5: MetricAggregate = .init()
    public var load15: MetricAggregate = .init()
    public var swap: MetricAggregate = .init()
    public var pressureStates: Set<Pressure> = []
    public var samples: Int = 0
    public var observedSeconds: Double = 0
    public var gapSeconds: Double = 0
    public var cadences: Set<Double> = []
    public var partial: Bool = false
    public var coverage: Double { min(1, observedSeconds / resolution) }
    public var cpuCoverage: Double { min(1, max(0, cpuObservedSeconds / resolution)) }
    public var memoryCoverage: Double { min(1, max(0, memoryObservedSeconds / resolution)) }
}
public struct ActionRecord: Codable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var operation: String
    public var result: String
    public var targetID: String
    public init(timestamp: Date = Date(), operation: String, result: String, targetID: String) { id = UUID(); self.timestamp = timestamp; self.operation = operation; self.result = result; self.targetID = targetID }
}
public struct HistoryState: Sendable {
    public var settings: HistorySettings
    public var aggregates: [HistoryAggregate]
    public var alerts: [AlertEvent]
    public var actions: [ActionRecord]
    public var recentSnapshots: [Snapshot]
    public var storageBytes: Int
    public var shortenedByCap: Bool
    public var error: String?
}
public protocol HistoryKeyProvider: Sendable { func key() throws -> SymmetricKey; func existingKey() throws -> SymmetricKey }
public struct EphemeralHistoryKeyProvider: HistoryKeyProvider {
    private let value: SymmetricKey
    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) { value = key }
    public func key() throws -> SymmetricKey { value }
}

extension HistorySettings {
    private enum CodingKeys: String, CodingKey { case retention, paused, aliases, excludedApplications, excludedProjects, numericMenuMetric, notificationsEnabled, launchAtLogin, updateChecks, projectBoundaries, alertEnabledRules, diskThresholdBytes }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        retention = try c.decodeIfPresent(HistoryRetention.self,forKey:.retention)
        paused = try c.decodeIfPresent(Bool.self,forKey:.paused) ?? false
        aliases = try c.decodeIfPresent([String:String].self,forKey:.aliases) ?? [:]
        excludedApplications = try c.decodeIfPresent(Set<String>.self,forKey:.excludedApplications) ?? []
        excludedProjects = try c.decodeIfPresent(Set<String>.self,forKey:.excludedProjects) ?? []
        numericMenuMetric = try c.decodeIfPresent(String.self,forKey:.numericMenuMetric) ?? "none"
        notificationsEnabled = try c.decodeIfPresent(Bool.self,forKey:.notificationsEnabled) ?? false
        launchAtLogin = try c.decodeIfPresent(Bool.self,forKey:.launchAtLogin) ?? false
        updateChecks = try c.decodeIfPresent(Bool.self,forKey:.updateChecks) ?? false
        projectBoundaries = try c.decodeIfPresent([String].self,forKey:.projectBoundaries) ?? []
        alertEnabledRules = try c.decodeIfPresent([String].self,forKey:.alertEnabledRules) ?? AlertCategory.allCases.map(\.rawValue)
        diskThresholdBytes = try c.decodeIfPresent(UInt64.self,forKey:.diskThresholdBytes) ?? 10 * 1024 * 1024 * 1024
    }
}

extension HistoryKeyProvider { public func existingKey() throws -> SymmetricKey { try key() } }


extension HistoryAggregate {
    private enum CodingKeys: String, CodingKey { case entityID, name, start, resolution, cpu, memory, memoryMethods, cpuObservedSeconds, memoryObservedSeconds, metricCoverageEstimated, load1, load5, load15, swap, pressureStates, samples, observedSeconds, gapSeconds, cadences, partial }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        entityID = try c.decode(String.self,forKey:.entityID); name = try c.decode(String.self,forKey:.name)
        start = try c.decode(Date.self,forKey:.start); resolution = try c.decode(Double.self,forKey:.resolution)
        cpu = try c.decode(MetricAggregate.self,forKey:.cpu); memory = try c.decode(MetricAggregate.self,forKey:.memory)
        load1 = try c.decodeIfPresent(MetricAggregate.self,forKey:.load1) ?? .init(); load5 = try c.decodeIfPresent(MetricAggregate.self,forKey:.load5) ?? .init(); load15 = try c.decodeIfPresent(MetricAggregate.self,forKey:.load15) ?? .init(); swap = try c.decodeIfPresent(MetricAggregate.self,forKey:.swap) ?? .init()
        pressureStates = try c.decodeIfPresent(Set<Pressure>.self,forKey:.pressureStates) ?? []
        samples = try c.decode(Int.self,forKey:.samples); observedSeconds = try c.decode(Double.self,forKey:.observedSeconds); gapSeconds = try c.decode(Double.self,forKey:.gapSeconds)
        cadences = try c.decode(Set<Double>.self,forKey:.cadences); partial = try c.decode(Bool.self,forKey:.partial)
        memoryMethods = try c.decodeIfPresent(Set<MemoryMethod>.self,forKey:.memoryMethods) ?? []
        let cpuDuration = try c.decodeIfPresent(Double.self,forKey:.cpuObservedSeconds)
        let memoryDuration = try c.decodeIfPresent(Double.self,forKey:.memoryObservedSeconds)
        // Older buckets did not retain per-metric durations. Preserve their estimate explicitly.
        cpuObservedSeconds = cpuDuration ?? (samples > 0 ? observedSeconds * Double(cpu.count) / Double(samples) : 0)
        memoryObservedSeconds = memoryDuration ?? (samples > 0 ? observedSeconds * Double(memory.count) / Double(samples) : 0)
        metricCoverageEstimated = try c.decodeIfPresent(Bool.self,forKey:.metricCoverageEstimated) ?? (cpuDuration == nil || memoryDuration == nil)
        let defaultedFields: [CodingKeys] = [.load1, .load5, .load15, .swap, .pressureStates, .memoryMethods, .cpuObservedSeconds, .memoryObservedSeconds, .metricCoverageEstimated]
        requiresPersistenceMigration = try defaultedFields.contains { key in
            guard c.contains(key) else { return true }
            return try c.decodeNil(forKey:key)
        }
    }
}

/// Lightweight production state. Full archive materialization belongs to diagnostic state().
public struct HistoryMetadata: Sendable {
    public var settings: HistorySettings
    public var alerts: [AlertEvent]
    public var actions: [ActionRecord]
    public var aggregateCount: Int
    public var storageBytes: Int
    public var shortenedByCap: Bool
    public var error: String?
    public var revision: UInt64
}
public struct HistoryEntity: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
}
public struct HistoryQuery: Sendable {
    public var entityID: String
    public var since: Date
    public var until: Date
    public var points: [HistoryAggregate]
    public var revision: UInt64
    public var error: String?
}
