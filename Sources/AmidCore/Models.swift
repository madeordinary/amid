import Foundation

public enum Availability: String, Codable, Sendable {
    case available, unsupported, denied, gone, sleeping, stale, unavailable
}

public enum MemoryMethod: String, Codable, Sendable {
    case footprint = "Physical footprint"
    case rss = "Resident size (RSS)"
    case mixed = "Mixed footprint / RSS"
    case unavailable = "Unavailable"
}

public enum Pressure: String, Codable, Sendable {
    case normal, warning, critical, unknown
}

public struct ProcessIdentity: Hashable, Codable, Sendable, Identifiable {
    public var bootID: String
    public var pid: Int32
    public var uid: UInt32
    public var startSeconds: UInt64
    public var startMicroseconds: UInt64
    public var id: String { "\(bootID):\(uid):\(pid):\(startSeconds):\(startMicroseconds)" }
    public init(bootID: String, pid: Int32, uid: UInt32, startSeconds: UInt64, startMicroseconds: UInt64) {
        self.bootID = bootID; self.pid = pid; self.uid = uid
        self.startSeconds = startSeconds; self.startMicroseconds = startMicroseconds
    }
}

public struct Endpoint: Hashable, Codable, Sendable, Identifiable {
    public var address: String
    public var port: UInt16
    public var family: String
    public var scope: String
    public var id: String { "TCP:\(family):\(address):\(port)" }
    public init(address: String, port: UInt16, family: String, scope: String) {
        self.address = address; self.port = port; self.family = family; self.scope = scope
    }
}

public struct ProcessSample: Codable, Sendable, Identifiable {
    public var identity: ProcessIdentity
    public var parentPID: Int32
    public var executable: String
    public var name: String
    public var runtime: String?
    public var cpuPercent: Double?
    public var memoryBytes: UInt64?
    public var memoryMethod: MemoryMethod
    public var workingDirectory: String?
    public var projectPath: String?
    public var applicationID: String
    public var applicationName: String
    public var groupingReason: String
    public var endpoints: [Endpoint]
    public var portAvailability: Availability
    public var observedSince: Date
    public var id: String { identity.id }
    public init(identity: ProcessIdentity, parentPID: Int32 = 0, executable: String, name: String,
                runtime: String? = nil, cpuPercent: Double? = nil, memoryBytes: UInt64? = nil,
                memoryMethod: MemoryMethod = .unavailable, workingDirectory: String? = nil,
                projectPath: String? = nil, applicationID: String, applicationName: String,
                groupingReason: String, endpoints: [Endpoint] = [], portAvailability: Availability = .unavailable,
                observedSince: Date = Date()) {
        self.identity = identity; self.parentPID = parentPID; self.executable = executable; self.name = name
        self.runtime = runtime; self.cpuPercent = cpuPercent; self.memoryBytes = memoryBytes
        self.memoryMethod = memoryMethod; self.workingDirectory = workingDirectory; self.projectPath = projectPath
        self.applicationID = applicationID; self.applicationName = applicationName; self.groupingReason = groupingReason
        self.endpoints = endpoints; self.portAvailability = portAvailability; self.observedSince = observedSince
    }
}

public struct MemorySnapshot: Codable, Sendable {
    public var physical: UInt64? = nil
    public var active: UInt64? = nil
    public var inactive: UInt64? = nil
    public var wired: UInt64? = nil
    public var compressed: UInt64? = nil
    public var free: UInt64? = nil
    public var swapUsed: UInt64? = nil
    public var pressure: Pressure = .unknown
    public init() {}
}

public struct VolumeSnapshot: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var capacity: UInt64?
    public var available: UInt64?
    public var isStartup: Bool
    public var definition: String
    public init(id: String, name: String, capacity: UInt64?, available: UInt64?, isStartup: Bool, definition: String) {
        self.id = id; self.name = name; self.capacity = capacity; self.available = available
        self.isStartup = isStartup; self.definition = definition
    }
}

public struct InterfaceSnapshot: Codable, Sendable, Identifiable {
    public var id: String
    public var receivedBytesPerSecond: Double?
    public var sentBytesPerSecond: Double?
    public var isVirtual: Bool
    public init(id: String, receivedBytesPerSecond: Double?, sentBytesPerSecond: Double?, isVirtual: Bool) {
        self.id = id; self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond; self.isVirtual = isVirtual
    }
}

public struct BatterySnapshot: Codable, Sendable {
    public var percent: Double?
    public var isCharging: Bool
    public var onBattery: Bool
    public var condition: String
    public init(percent: Double?, isCharging: Bool, onBattery: Bool, condition: String) {
        self.percent = percent; self.isCharging = isCharging; self.onBattery = onBattery; self.condition = condition
    }
}

public struct SystemSnapshot: Codable, Sendable {
    public var cpuPercent: Double? = nil
    public var loadAverage: [Double] = []
    public var logicalCPUCount: Int = ProcessInfo.processInfo.processorCount
    public var memory: MemorySnapshot = .init()
    public var volumes: [VolumeSnapshot] = []
    public var interfaces: [InterfaceSnapshot] = []
    public var battery: BatterySnapshot? = nil
    public var thermalState: String = "Unknown"
    public init() {}
}

public struct Snapshot: Codable, Sendable {
    public var timestamp: Date
    public var system: SystemSnapshot
    public var processes: [ProcessSample]
    public var enumeratedCount: Int
    public var inaccessibleCount: Int
    public var duration: Double
    public var cadence: Double
    public var expectedCadence: Double?
    public var availability: Availability
    public var notes: [String]
    public init(timestamp: Date = Date(), system: SystemSnapshot = .init(), processes: [ProcessSample] = [],
                enumeratedCount: Int = 0, inaccessibleCount: Int = 0, duration: Double = 0,
                cadence: Double = 5, expectedCadence: Double? = nil, availability: Availability = .unavailable, notes: [String] = []) {
        self.timestamp = timestamp; self.system = system; self.processes = processes
        self.enumeratedCount = enumeratedCount; self.inaccessibleCount = inaccessibleCount
        self.duration = duration; self.cadence = cadence; self.expectedCadence = expectedCadence; self.availability = availability; self.notes = notes
    }
    public static var empty: Snapshot { Snapshot() }
}

public struct ResourceGroup: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var processes: [ProcessSample]
    public var cpuPercent: Double? {
        let known = processes.compactMap(\.cpuPercent)
        return known.isEmpty ? nil : known.reduce(0, +)
    }
    public var memoryBytes: UInt64? {
        let known = processes.compactMap(\.memoryBytes)
        return known.isEmpty ? nil : known.reduce(0, +)
    }
    public var memoryMethod: MemoryMethod {
        let methods = Set(processes.filter { $0.memoryBytes != nil }.map(\.memoryMethod))
        return methods.count > 1 ? .mixed : methods.first ?? .unavailable
    }
    public var partial: Bool { processes.contains { $0.cpuPercent == nil || $0.memoryBytes == nil } }
    public static func applications(_ snapshot: Snapshot, sortedByMemory: Bool = true) -> [ResourceGroup] {
        let groups = Dictionary(grouping: unique(snapshot.processes), by: \.applicationID).map {
            ResourceGroup(id: $0.key, name: $0.value.first?.applicationName ?? "Unknown", processes: $0.value)
        }
        return sortedByMemory ? memorySorted(groups) : groups
    }
    public static func projects(_ snapshot: Snapshot, sortedByMemory: Bool = true) -> [ResourceGroup] {
        let groups = Dictionary(grouping: unique(snapshot.processes).filter { $0.projectPath != nil }, by: { $0.projectPath! }).map {
            ResourceGroup(id: $0.key, name: URL(fileURLWithPath: $0.key).lastPathComponent, processes: $0.value)
        }
        return sortedByMemory ? memorySorted(groups) : groups
    }
    private static func memorySorted(_ groups: [ResourceGroup]) -> [ResourceGroup] {
        groups.map { (group: $0, memory: $0.memoryBytes ?? 0) }
            .sorted { $0.memory > $1.memory }.map(\.group)
    }
    private static func unique(_ processes: [ProcessSample]) -> [ProcessSample] {
        var ids = Set<ProcessIdentity>()
        return processes.filter { ids.insert($0.identity).inserted }
    }
}
