import Foundation
import AmidCore
import Darwin

@main
struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        let sampler = Sampler()
        if let index = args.firstIndex(of: "--benchmark") {
            guard args.indices.contains(index + 1), let seconds = Double(args[index + 1]), seconds.isFinite, seconds > 0 else {
                FileHandle.standardError.write(Data("--benchmark requires a finite positive duration in seconds.\n".utf8))
                exit(EXIT_FAILURE)
            }
            _ = await sampler.sample(cadence: 5)
            try await Task.sleep(for: .seconds(5))
            let measurement = PerformanceMeasurement()
            let begin = ContinuousClock.now
            func elapsedSeconds() -> Double {
                let duration = begin.duration(to: .now).components
                return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            }
            let pid = getpid()
            var iterations = 0
            var durations: [Double] = []
            var selfCPU: [Double] = []
            var rss: [UInt64] = []
            while elapsedSeconds() < seconds {
                let snap = await sampler.sample(cadence: 5)
                if iterations > 0 {
                    durations.append(snap.duration)
                    if let own = snap.processes.first(where: { $0.identity.pid == pid }) {
                        if let cpu = own.cpuPercent { selfCPU.append(cpu) }
                        if let mem = own.memoryBytes { rss.append(mem) }
                    }
                }
                iterations += 1
                try await Task.sleep(for: .seconds(5))
            }
            struct Report: Encodable {
                var process: PerformanceMeasurement.Report
                var durationSeconds: Double; var samples: Int; var meanCPUPercentOneCore: Double?
                var maxObservedMemoryBytes: UInt64?; var meanCollectionSeconds: Double?; var notes: [String]
            }
            let process = measurement.report(notes: ["Collector-only probe, after one warmup sample. No matched workload baseline. Optional interrupt and package-idle wakeup deltas cover this process only."])
            let report = Report(process: process, durationSeconds: process.elapsedSeconds, samples: iterations,
                                meanCPUPercentOneCore: selfCPU.isEmpty ? nil : selfCPU.reduce(0,+)/Double(selfCPU.count),
                                maxObservedMemoryBytes: rss.max(),
                                meanCollectionSeconds: durations.isEmpty ? nil : durations.reduce(0,+)/Double(durations.count),
                                notes: ["Collector-only probe. Memory method follows collector; not a full GUI RSS measurement.", "No matched no-monitor baseline; separate own-process wakeup counters do not measure system-wide wakeups. PRD overhead gate is not established by this report."])
            try printJSON(report)
            return
        }
        _ = await sampler.sample(cadence: 2)
        try await Task.sleep(for: .seconds(2))
        var snap = await sampler.sample(cadence: 2)
        if let index = args.firstIndex(of: "--fixture-pids"), args.indices.contains(index + 1) {
            let ids = Set(args[index + 1].split(separator: ",").compactMap { Int32($0) })
            snap.processes = snap.processes.filter { ids.contains($0.identity.pid) }
            try printJSON(snap)
        } else if args.contains("--snapshot-json") {
            try printJSON(snap)
        } else {
            struct Summary: Encodable {
                var availability: String; var observed: Int; var inaccessible: Int; var applications: Int; var projects: Int
                var listeningEndpoints: Int; var systemCPU: Double?; var pressure: String; var selfObserved: Bool; var duration: Double
                var notes: [String]
            }
            let report = Summary(availability: snap.availability.rawValue, observed: snap.processes.count,
                                 inaccessible: snap.inaccessibleCount, applications: ResourceGroup.applications(snap).count,
                                 projects: ResourceGroup.projects(snap).count, listeningEndpoints: snap.processes.reduce(0) { $0 + $1.endpoints.count },
                                 systemCPU: snap.system.cpuPercent, pressure: snap.system.memory.pressure.rawValue,
                                 selfObserved: snap.processes.contains { $0.identity.pid == getpid() }, duration: snap.duration, notes: snap.notes)
            try printJSON(report)
        }
    }
    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}
