import XCTest
import Foundation
@testable import AmidCore

// Actor-isolated synchronous wrapper: no await inside the measured span.
private extension Sampler {
    func measuredSample() -> (Snapshot, OwnCurrentThreadMeasurement.Report) {
        let measurement = OwnCurrentThreadMeasurement()
        let snapshot = sample(cadence: 5)
        return (snapshot, measurement.report())
    }
}

/// Opt-in A/B experiment: full versus incremental collection on the live host, interleaved ABBA at five-second cadence.
/// Numeric output only; no paths, names or identities are serialized.
final class IncrementalCollectionExperimentTests: XCTestCase, @unchecked Sendable {
    private struct Reading: Encodable {
        var mode: String; var round: Int; var cpuMilliseconds: Double?; var wallMilliseconds: Double?
        var enumerated: Int; var observed: Int; var inaccessible: Int
    }
    private struct Audit: Encodable {
        var round: Int; var shared: Int; var onlyFull: Int; var onlyIncremental: Int
        var executable: Int; var workingDirectory: Int; var project: Int; var application: Int; var endpoints: Int; var portAvailability: Int
    }
    private struct Evidence: Encodable {
        var rounds: Int; var cadence: Double; var readings: [Reading]; var audits: [Audit]
        var meanCPUMilliseconds: [String: Double]; var notes: [String]
    }

    func testOptInFullVersusIncrementalCollection() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AMID_INCREMENTAL_EXPERIMENT"] == "1" else { throw XCTSkip("Opt-in incremental collection experiment") }
        guard let output = environment["AMID_INCREMENTAL_EXPERIMENT_OUTPUT"], output.hasPrefix("/private/tmp/amid-"), output.hasSuffix(".json"),
              !output.dropFirst("/private/tmp/".count).contains("/"), !FileManager.default.fileExists(atPath: output) else {
            XCTFail("Require a fresh owned /private/tmp/amid-*.json output"); return
        }
        let rounds = Int(environment["AMID_INCREMENTAL_EXPERIMENT_ROUNDS"] ?? "") ?? 24
        let full = Sampler(), incremental = Sampler(mode: .incremental())
        for _ in 0..<2 {
            _ = await full.sample(cadence: 5); _ = await incremental.sample(cadence: 5)
            try await Task.sleep(for: .seconds(5))
        }
        var readings: [Reading] = [], audits: [Audit] = []
        for round in 0..<rounds {
            let order: [(String, Sampler)] = round % 2 == 0 ? [("full", full), ("incremental", incremental)] : [("incremental", incremental), ("full", full)]
            var snapshots: [String: Snapshot] = [:]
            for (name, sampler) in order {
                let (snapshot, measured) = await sampler.measuredSample()
                snapshots[name] = snapshot
                readings.append(Reading(mode: name, round: round, cpuMilliseconds: measured.cpuSeconds.map { $0 * 1000 },
                                        wallMilliseconds: measured.wallSeconds * 1000, enumerated: snapshot.enumeratedCount,
                                        observed: snapshot.processes.count, inaccessible: snapshot.inaccessibleCount))
            }
            let a = Dictionary(snapshots["full"]!.processes.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
            let b = Dictionary(snapshots["incremental"]!.processes.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
            let shared = Set(a.keys).intersection(b.keys)
            var audit = Audit(round: round, shared: shared.count, onlyFull: a.count - shared.count, onlyIncremental: b.count - shared.count,
                              executable: 0, workingDirectory: 0, project: 0, application: 0, endpoints: 0, portAvailability: 0)
            for identity in shared {
                let x = a[identity]!, y = b[identity]!
                if x.executable != y.executable { audit.executable += 1 }
                if x.workingDirectory != y.workingDirectory { audit.workingDirectory += 1 }
                if x.projectPath != y.projectPath { audit.project += 1 }
                if x.applicationID != y.applicationID { audit.application += 1 }
                if x.endpoints != y.endpoints { audit.endpoints += 1 }
                if x.portAvailability != y.portAvailability { audit.portAvailability += 1 }
            }
            audits.append(audit)
            try await Task.sleep(for: .seconds(5))
        }
        var means: [String: Double] = [:]
        for mode in ["full", "incremental"] {
            let values = readings.filter { $0.mode == mode }.compactMap(\.cpuMilliseconds)
            if !values.isEmpty { means[mode] = values.reduce(0, +) / Double(values.count) }
        }
        let evidence = Evidence(rounds: rounds, cadence: 5, readings: readings, audits: audits, meanCPUMilliseconds: means, notes: [
            "Own sampler-thread CPU per sample; each mode keeps its own baselines and caches.",
            "ABBA order alternates each round; host workload varies, so this is descriptive, not causal.",
            "Audit compares the two modes' adjacent snapshots for shared identities; differences include real changes between the two reads."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(evidence).write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
        print("INCREMENTAL_EXPERIMENT mean CPU ms/sample: \(means)")
    }
}
