import Foundation
import Darwin
import IOKit.ps
import CAmid

private func cString<T>(_ value: T) -> String {
    var copy = value
    return withUnsafePointer(to: &copy) { $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) } }
}

public enum ProjectAttribution {
    public static let markers = [".git", "Package.swift", "package.json", "pyproject.toml", "Cargo.toml", "go.mod"]
    /// Explicit containing roots win; otherwise checks marker existence within twelve ancestors.
    public static func root(for workingDirectory: String, boundaries: [String] = []) -> String? {
        var markerCache: [String: Bool] = [:]
        return root(for: workingDirectory, boundaries: boundaries, markerCache: &markerCache)
    }
    static func root(for workingDirectory: String, boundaries: [String], markerCache: inout [String: Bool], profile: SamplerProfile? = nil) -> String? {
        guard workingDirectory.hasPrefix("/") else { return nil }
        var current = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        let limits = Set(boundaries.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        if let explicit = limits.filter({ current == $0 || current.hasPrefix($0 == "/" ? "/" : $0 + "/") }).max(by: { $0.count < $1.count }) { return explicit }
        for _ in 0..<12 {
            let hasMarker: Bool
            if let cached = markerCache[current] { profile?.count(.markerCacheHit); hasMarker = cached }
            else { profile?.count(.markerCacheMiss); hasMarker = markers.contains(where: { profile?.count(.markerAccess); return ((current == "/" ? "/" : current + "/") + $0).withCString { Darwin.access($0, F_OK) == 0 } }); markerCache[current] = hasMarker }
            if hasMarker { return current }
            if limits.contains(current) || current == "/" { break }
            guard let separator = current.lastIndex(of: "/") else { break }
            current = separator == current.startIndex ? "/" : String(current[..<separator])
        }
        return nil
    }
}

/// Dispatch reports changes; there is no assumed normal state before the first event.
private final class MemoryPressureObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Pressure = .unknown
    private let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: DispatchQueue(label: "Amid.memory-pressure"))
    init() {
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source.data
            self.lock.lock()
            self.value = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : event.contains(.normal) ? .normal : .unknown
            self.lock.unlock()
        }
        source.resume()
    }
    deinit { source.cancel() }
    func current() -> Pressure { lock.lock(); defer { lock.unlock() }; return value }
}

public actor Sampler {
    private struct Counter { var value: UInt64; var time: Double }
    private var processCounters: [ProcessIdentity: Counter] = [:]
    private var interfaceCounters: [String: (UInt64, UInt64, Double)] = [:]
    private var systemCounter: AmidSystem?
    private var powerSampleTime: Double?
    private var cachedBattery: BatterySnapshot?
    private var cachedThermal = "Unknown"
    private var firstSeen: [ProcessIdentity: Date] = [:]
    private var stringStorage = ProcessStringStorage()
    private var bootID: String?
    private var pressureObserver: MemoryPressureObserver?
    public init() {}
    var retainedStringIdentityCount: Int { stringStorage.retainedIdentityCount }
    var initializedCollectionResources: Bool { bootID != nil || pressureObserver != nil }
    private func initializeCollectionResources() {
        guard bootID == nil else { return }
        var buffer = [CChar](repeating: 0, count: 128)
        let result = amid_boot(&buffer, Int32(buffer.count))
        bootID = result == 0 ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : "unavailable-\(UUID().uuidString)"
        pressureObserver = MemoryPressureObserver()
    }
    public func resetBaselines() { stringStorage.reset(); processCounters.removeAll(); firstSeen.removeAll(); interfaceCounters.removeAll(); systemCounter = nil; powerSampleTime = nil }
    /// Verification-only synchronous own-current-thread attribution; sampling behavior is unchanged.
    public func profiledSample(cadence: Double = 5, projectBoundaries: [String] = []) -> (snapshot: Snapshot, measurement: OwnCurrentThreadMeasurement.Report, breakdown: SamplerProfile.Report) {
        let measurement = OwnCurrentThreadMeasurement()
        let profile = SamplerProfile(measurement: measurement)
        let snapshot = sample(cadence: cadence, projectBoundaries: projectBoundaries, profile: profile)
        return (snapshot, measurement.report(), profile.finish())
    }
    public func sample(cadence: Double = 5, projectBoundaries: [String] = []) -> Snapshot {
        sample(cadence: cadence, projectBoundaries: projectBoundaries, profile: nil)
    }
    private func sample(cadence: Double, projectBoundaries: [String], profile: SamplerProfile?) -> Snapshot {
        profile?.begin(.enumeration)
        let start = ProcessInfo.processInfo.systemUptime
        let date = Date()
        initializeCollectionResources()
        guard let bootID else { profile?.end(.enumeration); stringStorage.reset(); return Snapshot(timestamp: date, cadence: cadence, expectedCadence: cadence, availability: .unavailable) }
        var pids = [Int32](repeating: 0, count: 65536)
        let count = amid_pids(&pids, Int32(pids.count))
        profile?.end(.enumeration)
        guard count >= 0 else { stringStorage.reset(); return Snapshot(timestamp: date, cadence: cadence, expectedCadence: cadence, availability: .denied, notes: ["Process enumeration unavailable"]) }
        var processes: [ProcessSample] = []
        var inaccessible = 0
        var projectsByCWD: [String: String] = [:]
        var markerCache: [String: Bool] = [:]
        var nextCounters: [ProcessIdentity: Counter] = [:]
        var nextSeen: [ProcessIdentity: Date] = [:]
        var ports = [AmidPort](repeating: AmidPort(), count: 256)
        profile?.begin(.processLoop)
        for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 {
            profile?.beginIteration()
            defer { profile?.endIteration() }
            var raw = AmidProcess()
            let processStatus = amid_process(pid, &raw)
            profile?.endFine(.processOS)
            guard processStatus == 1 else { inaccessible += 1; continue }
            let identity = ProcessIdentity(bootID: bootID, pid: pid, uid: raw.uid, startSeconds: raw.seconds, startMicroseconds: raw.micros)
            var cpu: Double?
            if raw.cpu_known == 1 {
                if let prior = processCounters[identity], raw.cpu >= prior.value, start > prior.time { cpu = Double(raw.cpu - prior.value) / (start - prior.time) / 1_000_000_000 * 100 }
                nextCounters[identity] = Counter(value: raw.cpu, time: start)
            }
            let executable = cString(raw.executable)
            let name = cString(raw.name)
            let observedCWD = raw.cwd_status == 1 ? cString(raw.cwd) : ""
            let cwd = observedCWD.isEmpty ? nil : observedCWD
            profile?.endFine(.decoding)
            let app = Self.application(executable: executable, identity: identity, name: name)
            let runtime = profile == nil ? nil : Self.runtime(executable)
            profile?.endFine(.application)
            var project: String?
            if let cwd {
                if let cached = projectsByCWD[cwd] { profile?.count(.cwdCacheHit); project = cached.isEmpty ? nil : cached }
                else { profile?.count(.cwdCacheMiss); project = ProjectAttribution.root(for: cwd, boundaries: projectBoundaries, markerCache: &markerCache, profile: profile); projectsByCWD[cwd] = project ?? "" }
            }
            profile?.endFine(.project)
            var portStatus: Int32 = 0
            let portCount = amid_ports(pid, &ports, Int32(ports.count), &portStatus)
            // Revalidate identity after socket inspection as well.
            let identityMatches = amid_identity_matches(pid, raw.uid, raw.seconds, raw.micros)
            profile?.endFine(.portsValidation)
            guard identityMatches == 1 else { inaccessible += 1; continue }
            let endpoints = Set(ports.prefix(Int(portCount)).map { item in
                let address = cString(item.address)
                return Endpoint(address: address, port: item.port, family: item.family == AF_INET ? "IPv4" : "IPv6", scope: address.hasPrefix("127.") || address == "::1" ? "Loopback" : address == "0.0.0.0" || address == "::" ? "All interfaces" : "Interface")
            }).sorted { $0.id < $1.id }
            let seen = firstSeen[identity] ?? date
            nextSeen[identity] = seen
            processes.append(ProcessSample(identity: identity, parentPID: raw.parent, executable: executable, name: name, runtime: profile == nil ? Self.runtime(executable) : runtime, cpuPercent: cpu, memoryBytes: raw.memory_method == 0 ? nil : raw.memory, memoryMethod: raw.memory_method == 1 ? .footprint : raw.memory_method == 2 ? .rss : .unavailable, workingDirectory: cwd, projectPath: project, applicationID: app.0, applicationName: app.1, groupingReason: app.2, endpoints: endpoints, portAvailability: portStatus == 1 ? .available : portStatus == 2 ? .denied : .unavailable, observedSince: seen))
            profile?.endFine(.construction)
        }
        profile?.end(.processLoop)
        profile?.begin(.stringReuse)
        stringStorage.reuseStorage(in: &processes)
        processCounters = nextCounters; firstSeen = nextSeen
        profile?.end(.stringReuse)
        let system = collectSystem(time: start, profile: profile)
        return Snapshot(timestamp: date, system: system, processes: processes, enumeratedCount: Int(count), inaccessibleCount: inaccessible, duration: ProcessInfo.processInfo.systemUptime - start, cadence: cadence, expectedCadence: cadence, availability: .available, notes: ["CPU is percent of one logical core; first samples and reset counters are unknown.", "Project attribution uses explicit containing roots or marker existence within twelve ancestors.", "Application grouping uses outer bundle path or exact executable path; ancestry is not inferred."])
    }
    public static func application(executable: String, identity: ProcessIdentity, name: String) -> (String, String, String) {
        let components = executable.split(separator: "/")
        if let index = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            let path = "/" + components.prefix(through: index).joined(separator: "/")
            return ("bundle:\(path)", String(components[index].dropLast(4)), "Executable inside outer application bundle")
        }
        if !executable.isEmpty { return ("executable:\(executable)", String(components.last ?? ""), "Exact executable path; no parent inference") }
        return ("process:\(identity.id)", name, "Executable unavailable; individual process identity")
    }
    public static func runtime(_ executable: String) -> String? {
        let name = executable.split(separator: "/").last.map { String($0).lowercased() } ?? ""
        if name == "node" { return "Node.js" }
        if name == "codex" { return "Codex CLI" }
        if name == "claude" { return "Claude Code CLI" }
        if name == "gemini" { return "Gemini CLI" }
        if name == "ollama" { return "Ollama" }
        let pythonVersion = name.hasPrefix("python3.") && !name.dropFirst(8).isEmpty &&
            name.dropFirst(8).split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
            }
        if name == "python" || name == "python3" || pythonVersion { return "Python" }
        if name == "swift" || name == "swift-frontend" { return "Swift" }
        return nil
    }
    enum VolumeRead { case notLocal, unavailable, volume(VolumeSnapshot) }
    static func volumeCollection(urls: [URL]?, read: (URL) -> VolumeRead) -> ([VolumeSnapshot], CollectionStatus) {
        guard let urls else { return ([], .unavailable) }
        var rows: [VolumeSnapshot] = []; var failed = false
        for url in urls {
            switch read(url) {
            case .notLocal: break
            case .unavailable: failed = true
            case .volume(let row):
                rows.append(row)
                if row.capacity == nil || row.available == nil { failed = true }
            }
        }
        return (rows, failed ? (rows.isEmpty ? .unavailable : .partial) : .complete)
    }
    func collectInterfaces(time: Double, read: @Sendable (inout [AmidInterface]) -> Int32) -> ([InterfaceSnapshot], CollectionStatus) {
        var interfaces = [AmidInterface](repeating: AmidInterface(), count: 256)
        let count = read(&interfaces); var next: [String: (UInt64, UInt64, Double)] = [:]
        if count < 0 || count > Int32(interfaces.count) { interfaceCounters.removeAll(); return ([], .unavailable) }
        var output: [InterfaceSnapshot] = []
        if count > 0 { output = interfaces.prefix(Int(count)).map { item in
            let name = cString(item.name); var received: Double?; var sent: Double?
            if let prior = interfaceCounters[name], time > prior.2, item.received >= prior.0, item.sent >= prior.1 { received = Double(item.received - prior.0) / (time - prior.2); sent = Double(item.sent - prior.1) / (time - prior.2) }
            next[name] = (item.received, item.sent, time)
            return InterfaceSnapshot(id: name, receivedBytesPerSecond: received, sentBytesPerSecond: sent, isVirtual: !name.hasPrefix("en"))
        } }
        interfaceCounters = next
        return (output, .complete)
    }
    private func collectSystem(time: Double, profile: SamplerProfile?) -> SystemSnapshot {
        profile?.begin(.systemCounters)
        var result = SystemSnapshot(); var raw = AmidSystem(); amid_system(&raw)
        if raw.cpu_known == 1, let prior = systemCounter {
            let nowTotal = raw.user + raw.system + raw.idle + raw.nice
            let oldTotal = prior.user + prior.system + prior.idle + prior.nice
            if nowTotal > oldTotal, raw.idle >= prior.idle, raw.user >= prior.user, raw.system >= prior.system, raw.nice >= prior.nice { result.cpuPercent = 100 * (1 - Double(raw.idle - prior.idle) / Double(nowTotal - oldTotal)) }
        }
        systemCounter = raw.cpu_known == 1 ? raw : nil
        var load = [Double](repeating: 0, count: 3); let n = getloadavg(&load, 3); result.loadAverage = n > 0 ? Array(load.prefix(Int(n))) : []
        result.memory.physical = ProcessInfo.processInfo.physicalMemory
        if raw.memory_known == 1 { result.memory.active = raw.active; result.memory.inactive = raw.inactive; result.memory.wired = raw.wired; result.memory.compressed = raw.compressed; result.memory.free = raw.free }
        result.memory.swapUsed = raw.swap_known == 1 ? raw.swap : nil
        result.memory.pressure = pressureObserver?.current() ?? .unknown
        profile?.end(.systemCounters)
        profile?.begin(.volumes)
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let volumeResult = Self.volumeCollection(urls: FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes])) { url in
            guard let v = try? url.resourceValues(forKeys: keys), let local = v.volumeIsLocal else { return .unavailable }
            guard local else { return .notLocal }
            return .volume(VolumeSnapshot(id: url.path, name: v.volumeName ?? url.lastPathComponent, capacity: v.volumeTotalCapacity.map { UInt64(max(0, $0)) }, available: v.volumeAvailableCapacity.map { UInt64(max(0, $0)) }, isStartup: url.path == "/", definition: "Volume available capacity; shared APFS capacity can overlap"))
        }
        result.volumes = volumeResult.0; result.volumeCollectionStatus = volumeResult.1
        profile?.end(.volumes)
        profile?.begin(.interfaces)
        let interfaceResult = collectInterfaces(time: time) { amid_interfaces(&$0, 256) }
        result.interfaces = interfaceResult.0; result.interfaceCollectionStatus = interfaceResult.1
        profile?.end(.interfaces)
        profile?.begin(.power)
        defer { profile?.end(.power) }
        if let last = powerSampleTime, time - last < 10 {
            result.battery = cachedBattery; result.thermalState = cachedThermal; return result
        }
        switch ProcessInfo.processInfo.thermalState { case .nominal: result.thermalState = "Nominal"; case .fair: result.thermalState = "Fair"; case .serious: result.thermalState = "Serious"; case .critical: result.thermalState = "Critical"; @unknown default: result.thermalState = "Unknown" }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                let current = d[kIOPSCurrentCapacityKey] as? Double; let maximum = d[kIOPSMaxCapacityKey] as? Double
                result.battery = BatterySnapshot(percent: current.flatMap { c in maximum.flatMap { $0 > 0 ? c / $0 * 100 : nil } }, isCharging: d[kIOPSIsChargingKey] as? Bool ?? false, onBattery: d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue, condition: d[kIOPSBatteryHealthConditionKey] as? String ?? d[kIOPSBatteryHealthKey] as? String ?? "Condition unavailable")
                break
            }
        }
        cachedBattery = result.battery; cachedThermal = result.thermalState; powerSampleTime = time
        return result
    }
}
