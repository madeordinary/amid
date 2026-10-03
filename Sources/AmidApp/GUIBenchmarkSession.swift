import Foundation
import AmidCore

/// Verification-only evidence. Contains counts and timing, never process metadata.
struct GUIBenchmarkEvidence: Encodable {
    enum PresentationMode: String, Codable {
        case normal, hiddenOverviewSuppressed
        func suppressesOverview(windowVisible: Bool, isOverview: Bool) -> Bool {
            self == .hiddenOverviewSuppressed && !windowVisible && isOverview
        }
    }
    static func presentationMode(arguments: [String]) -> PresentationMode {
        arguments.contains("--performance-verification") && arguments.contains("--profile-suppress-hidden-overview") ? .hiddenOverviewSuppressed : .normal
    }
    struct HistorySeed: Encodable {
        let provenance: VerificationHistorySeed.Summary
        let actualLoadedAggregates: Int
        let measurementNote = "Synthetic import/startup allocations are included in process-lifetime peak RSS. Import precedes warmup and the measured CPU interval; this is loaded synthetic history, not a normal-store load benchmark."
    }
    var historySeed: HistorySeed?
    var presentationMode: PresentationMode = .normal
    enum Phase: String, Codable { case warmingUp, measuring, completed, invalid }
    let runID = UUID()
    let requestedSeconds: Double
    var retention = "unspecified"
    let createdAt = Date()
    var phase: Phase = .warmingUp
    var measurementStartedAt: Date?
    var warmupSamples = 0
    var acceptedSamples = 0
    var unavailableSamples = 0
    var observedProcessesAtCompletion = 0
    var maximumGapSeconds = 0.0
    var minimumRequestedCadence: Double?
    var maximumRequestedCadence: Double?
    var invalidReasons: [String] = []
    var statusUpdatedAt = Date()
    var elapsedSeconds = 0.0
    private var lastSampleElapsed = 0.0
    private var lastRequestedCadence = 5.0

    mutating func invalidate(_ reason: String) {
        guard phase != .completed else { return }
        if !invalidReasons.contains(reason) { invalidReasons.append(reason) }
        phase = .invalid
    }
    mutating func begin(active: Bool) {
        guard phase == .warmingUp else { return }
        guard active, warmupSamples >= 2 else {
            invalidate("Monitoring did not produce two available warmup samples."); return
        }
        phase = .measuring; measurementStartedAt = Date()
    }
    mutating func observe(available: Bool, elapsed: Double, cadence: Double, processCount: Int) {
        guard phase == .warmingUp || phase == .measuring else { return }
        guard available else {
            unavailableSamples += 1; invalidate("Collection or encrypted history became unavailable."); return
        }
        if phase == .warmingUp { warmupSamples += 1; lastRequestedCadence = cadence; return }
        checkGap(elapsed: elapsed, cadence: lastRequestedCadence)
        acceptedSamples += 1
        observedProcessesAtCompletion = processCount
        minimumRequestedCadence = min(minimumRequestedCadence ?? cadence, cadence)
        maximumRequestedCadence = max(maximumRequestedCadence ?? cadence, cadence)
        lastSampleElapsed = elapsed
        lastRequestedCadence = cadence
    }
    mutating func finish(elapsed: Double, active: Bool) {
        guard phase == .measuring else { return }
        checkGap(elapsed: elapsed, cadence: lastRequestedCadence)
        if !active { invalidate("Monitoring was suspended at completion.") }
        if acceptedSamples < 2 { invalidate("Too few accepted measurement samples.") }
        if elapsed < requestedSeconds || elapsed > requestedSeconds + 15 {
            invalidate("Measurement duration did not match the requested continuous interval.")
        }
        if phase == .measuring { phase = .completed }
    }
    private mutating func checkGap(elapsed: Double, cadence: Double) {
        let gap = elapsed - lastSampleElapsed
        maximumGapSeconds = max(maximumGapSeconds, gap)
        if gap < 0 || gap > max(15, cadence * 3) {
            invalidate("A collection gap exceeded three requested intervals (minimum 15 seconds).")
        }
    }
}

@MainActor
final class GUIBenchmarkSession {
    private(set) var evidence: GUIBenchmarkEvidence
    private let output: URL
    private var measurement: PerformanceMeasurement?
    private var started: ContinuousClock.Instant?
    private var lastStatusElapsed = 0.0
    private(set) var writeFailed = false
    private var finalized = false

    init(seconds: Double, output: URL, retention: String, presentationMode: GUIBenchmarkEvidence.PresentationMode = .normal, historySeed: GUIBenchmarkEvidence.HistorySeed? = nil) {
        evidence = GUIBenchmarkEvidence(requestedSeconds: seconds)
        evidence.retention = retention
        evidence.presentationMode = presentationMode
        evidence.historySeed = historySeed
        self.output = output
        writeStatus()
    }
    func begin(active: Bool) {
        evidence.begin(active: active)
        if evidence.phase == .measuring {
            started = .now; measurement = PerformanceMeasurement()
        }
        writeStatus()
    }
    func observe(available: Bool, cadence: Double, processCount: Int) {
        let before = evidence.phase
        evidence.observe(available: available, elapsed: elapsed, cadence: cadence, processCount: processCount)
        // A bounded heartbeat proves accepted sampling without per-sample disk writes.
        if evidence.phase != before || elapsed - lastStatusElapsed >= 60 {
            lastStatusElapsed = elapsed; writeStatus()
        }
    }
    func invalidate(_ reason: String) {
        guard !finalized else { return }
        evidence.invalidate(reason); writeStatus()
    }
    func finish(active: Bool) {
        guard !finalized else { return }
        struct Artifact: Encodable {
            var monitoring: GUIBenchmarkEvidence
            var measurement: PerformanceMeasurement.Report?
            var notes: [String]
        }
        let report = measurement?.report(notes: ["Full GUI with accessible process metadata; 30-second warmup. Temporary encrypted storage obeys monitoring.retention."])
        if report?.meanCPUPercentOneCore == nil { evidence.invalidate("Own-process CPU counters were unavailable.") }
        evidence.finish(elapsed: report?.elapsedSeconds ?? elapsed, active: active)
        writeStatus()
        let artifact = Artifact(monitoring: evidence, measurement: report, notes: [
            "Only monitoring.phase=completed describes a continuous sampling run; this is not a reference-hardware or baseline pass.",
            "Peak RSS includes startup and warmup. Wakeup counters are separate public own-process counters.",
            "Status heartbeat writes occur at most once per minute and are included in measured cost."
        ] + (evidence.presentationMode == .hiddenOverviewSuppressed ? ["Hidden Overview suppression is a causal diagnostic experiment, never normal-app acceptance performance evidence."] : []))
        write(artifact, to: output)
        if writeFailed { writeStatus() }
        finalized = true
    }
    private var elapsed: Double {
        guard let started else { return 0 }
        let duration = started.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
    private func writeStatus() {
        guard !finalized else { return }
        evidence.statusUpdatedAt = Date(); evidence.elapsedSeconds = elapsed
        write(evidence, to: output.appendingPathExtension("status.json"))
    }
    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            writeFailed = true; evidence.phase = .invalid
            evidence.invalidate("The benchmark evidence could not be written.")
        }
    }
}
