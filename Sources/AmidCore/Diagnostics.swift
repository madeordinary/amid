import Foundation

/// Explicit allowlist: never serializes process records, paths or identities.
public enum Diagnostics {
    public static func preview(snapshot: Snapshot, settings: HistorySettings, storageBytes: Int, alerts: [AlertEvent], operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString) -> String {
        let payload: [String: Any] = [
            "application": "Amid", "version": "0.1.0", "operatingSystem": operatingSystem,
            "observedProcessCount": snapshot.processes.count, "inaccessibleProcessCount": snapshot.inaccessibleCount,
            "logicalCPUCount": snapshot.system.logicalCPUCount,
            "systemCPUPercentRounded": snapshot.system.cpuPercent.map { Int($0.rounded()) } as Any? ?? "Unavailable",
            "memoryPressure": snapshot.system.memory.pressure.rawValue,
            "retention": settings.retention?.title ?? "Not chosen", "historyStorageMiB": storageBytes / 1048576,
            "aliases": Array(settings.aliases.values).sorted(),
            "activeAlertCategories": Array(Set(alerts.filter { $0.recoveredAt == nil }.map { $0.category.rawValue })).sorted(),
            "coverage": snapshot.availability.rawValue,
            "omitted": ["arguments", "environment", "usernames", "project paths", "process identities", "remote endpoints", "payloads"]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "Preview unavailable" }
        return text
    }
}

public enum SamplingPolicy {
    public static func cadence(detailVisible: Bool, onBattery: Bool, thermal: String) -> Double {
        if onBattery || ["fair", "serious", "critical"].contains(thermal.lowercased()) { return 10 }
        return detailVisible ? 2 : 5
    }
}
