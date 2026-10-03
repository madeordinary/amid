import Foundation
import Darwin
import AmidCore

/// Explicit verification only. Own-process intervals include concurrent work during awaits.
@MainActor final class AppPipelineProfile {
    enum Phase: String, Codable, CaseIterable { case expiry, collection, grouping, publication, historyIngest, alerts, alertRecord, storeSync, notifications }
    enum OutputChoice { case disabled, configured(URL), invalid }
    static func outputChoice(arguments: [String], benchmarkOutput: URL) -> OutputChoice {
        guard let index = arguments.firstIndex(of: "--profile-pipeline-output") else { return .disabled }
        guard arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/") else { return .invalid }
        let output = URL(fileURLWithPath:arguments[index + 1])
        func canonical(_ url: URL) -> String {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            // Output files may not exist yet; resolve the existing parent independently.
            return resolved.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(resolved.lastPathComponent).path
        }
        let reserved = [benchmarkOutput, benchmarkOutput.appendingPathExtension("status.json")].map(canonical)
        guard !reserved.contains(where: { $0.caseInsensitiveCompare(canonical(output)) == .orderedSame }) else { return .invalid }
        return .configured(output)
    }
    struct Reading { var wall: Double; var cpu: Double? }
    struct Token { fileprivate var id: UUID; fileprivate var phase: Phase; fileprivate var start: Reading }
    struct PhaseReport: Codable {
        var calls = 0
        var wallSeconds: Double? = 0
        var unknownWallIntervals = 0
        var cpuSeconds: Double? = 0
        var unknownCPUIntervals = 0
    }
    struct Report: Codable {
        var elapsedSeconds: Double?
        var ownCPUSeconds: Double?
        var measuredPhaseCPUSeconds: Double?
        var residualCPUSeconds: Double?
        var phases: [String: PhaseReport]
        var ingestionThread: PhaseReport
        var collectionThread: PhaseReport
        var samplerBreakdown: [SamplerProfile.Report]
        var benchmarkPhase: String
        var notes: [String]
    }
    private let output: URL?
    private let read: () -> Reading
    private var ingestionThread = PhaseReport()
    private var collectionThread = PhaseReport()
    private var samplerBreakdown: [SamplerProfile.Report] = []
    private var baseline: Reading?
    private var active: Token?
    private var phases: [Phase:PhaseReport] = [:]
    private(set) var finalized = false
    private(set) var writeFailed = false
    init(output: URL? = nil, read: (() -> Reading)? = nil) {
        self.output = output
        let origin = ContinuousClock.now
        self.read = read ?? {
            let duration = origin.duration(to: .now).components
            var usage = rusage()
            let available = getrusage(RUSAGE_SELF, &usage) == 0
            let cpu = Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec) + (Double(usage.ru_utime.tv_usec) + Double(usage.ru_stime.tv_usec)) / 1_000_000
            return Reading(wall: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
                           cpu: available && cpu.isFinite && cpu >= 0 ? cpu : nil)
        }
    }
    var isMeasuring: Bool { baseline != nil && !finalized }
    func recordIngestionThread(_ report: OwnCurrentThreadMeasurement.Report) { recordThread(report, into: &ingestionThread) }
    func recordSamplerBreakdown(_ report: SamplerProfile.Report) {
        guard isMeasuring else { return }; samplerBreakdown.append(report)
    }
    func recordCollectionThread(_ report: OwnCurrentThreadMeasurement.Report) { recordThread(report, into: &collectionThread) }
    private func recordThread(_ report: OwnCurrentThreadMeasurement.Report, into value: inout PhaseReport) {
        guard isMeasuring else { return }
        value.calls += 1
        if report.wallSeconds.isFinite, report.wallSeconds >= 0 {
            if let previous = value.wallSeconds { value.wallSeconds = previous + report.wallSeconds }
        } else { value.wallSeconds = nil; value.unknownWallIntervals += 1 }
        if let cpu = report.cpuSeconds, cpu.isFinite, cpu >= 0 {
            if let previous = value.cpuSeconds { value.cpuSeconds = previous + cpu }
        } else { value.cpuSeconds = nil; value.unknownCPUIntervals += 1 }
    }
    func start() { guard baseline == nil, !finalized else { return }; baseline = read() }
    func begin(_ phase: Phase) -> Token? {
        guard baseline != nil, !finalized, active == nil else { return nil }
        let token = Token(id:UUID(),phase:phase,start:read()); active = token; return token
    }
    func end(_ token: Token?) {
        guard let token, !finalized, active?.id == token.id else { return }
        active = nil
        let now = read()
        var value = phases[token.phase] ?? PhaseReport()
        value.calls += 1
        if let wall = Self.delta(token.start.wall, now.wall) {
            if let previous = value.wallSeconds { value.wallSeconds = previous + wall }
        } else { value.wallSeconds = nil; value.unknownWallIntervals += 1 }
        if let before = token.start.cpu, let after = now.cpu, let cpu = Self.delta(before,after) {
            if let previous = value.cpuSeconds { value.cpuSeconds = previous + cpu }
        } else { value.cpuSeconds = nil; value.unknownCPUIntervals += 1 }
        phases[token.phase] = value
    }
    @discardableResult func finish(benchmarkPhase: String) -> Report? {
        guard let baseline, !finalized else { return nil }
        let now = read(); finalized = true
        let elapsed = Self.delta(baseline.wall,now.wall)
        let cpu = baseline.cpu.flatMap { before in now.cpu.flatMap { Self.delta(before,$0) } }
        let allKnown = phases.values.allSatisfy { $0.cpuSeconds != nil } && active == nil
        let measured = allKnown ? phases.values.reduce(0) { $0 + ($1.cpuSeconds ?? 0) } : nil
        let residual = cpu.flatMap { total in measured.flatMap { total >= $0 ? total - $0 : nil } }
        let report = Report(elapsedSeconds:elapsed,ownCPUSeconds:cpu,measuredPhaseCPUSeconds:measured,residualCPUSeconds:residual,
            phases:Dictionary(uniqueKeysWithValues:phases.map { ($0.key.rawValue,$0.value) }),ingestionThread:ingestionThread,collectionThread:collectionThread,samplerBreakdown:samplerBreakdown,benchmarkPhase:benchmarkPhase,
            notes:["Verification-only own getrusage(RUSAGE_SELF) CPU seconds and ContinuousClock wall intervals. No process metadata or payloads.",
                   "The profile starts after benchmark begin/status serialization and finishes after final benchmark serialization. The intervals are close but not identical; benchmark evidence remains separate.",
                   "Supplemental ingestionThread and collectionThread CPU uses the current actor thread only, excludes dispatched worker/other-thread CPU, and can reflect timer quantization. It is not added to process phase sums or residual subtraction.",
                   "Phases never overlap. Each phase's own-process CPU includes concurrent work during awaited operations; these are coarse intervals, not causal stack attribution.",
                   "Residual is whole interval CPU minus completed phase intervals; it includes SwiftUI, timers, other tasks, uninstrumented work and instrumentation overhead. It is not exclusively rendering.",
                   "Unavailable, nonfinite or regressed counters remain unknown. An unfinished phase makes summed and residual CPU unknown. Benchmark phase is recorded separately; this profile is not a release budget pass."])
        if let output {
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; try encoder.encode(report).write(to:output,options:.atomic) }
            catch { writeFailed = true }
        }
        return report
    }
    private static func delta(_ before: Double,_ after: Double) -> Double? {
        guard before.isFinite, after.isFinite, before >= 0, after >= before else { return nil }; return after-before
    }
}
