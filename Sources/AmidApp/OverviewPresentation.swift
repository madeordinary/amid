import Foundation
import AmidCore

/// Lightweight display values only; never retains raw processes or resource groups.
struct OverviewPresentation {
    struct ApplicationRow: Identifiable {
        var id: String
        var name: String
        var processCount: Int
        var memoryMethod: MemoryMethod
        var memoryBytes: UInt64?
        var cpuPercent: Double?
    }
    struct ProjectRow: Identifiable {
        var id: String
        var name: String
        var memoryBytes: UInt64?
        var ports: String
    }
    var system = SystemSnapshot()
    var availability: Availability = .unavailable
    var timestamp: Date?
    var applications: [ApplicationRow] = []
    var projects: [ProjectRow] = []

    init() {}
    init(snapshot: Snapshot, applications: [ResourceGroup], projects: [ResourceGroup]) {
        system = snapshot.system; availability = snapshot.availability; timestamp = snapshot.timestamp
        self.applications = applications.prefix(6).map {
            ApplicationRow(id: $0.id, name: $0.name, processCount: $0.processes.count,
                memoryMethod: $0.memoryMethod, memoryBytes: $0.memoryBytes, cpuPercent: $0.cpuPercent)
        }
        self.projects = projects.prefix(4).map {
            ProjectRow(id: $0.id, name: $0.name, memoryBytes: $0.memoryBytes,
                ports: $0.processes.flatMap(\.endpoints).map { String($0.port) }.sorted().joined(separator: ", "))
        }
    }
}
