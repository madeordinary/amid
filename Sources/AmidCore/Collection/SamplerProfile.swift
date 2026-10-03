import Foundation

/// Explicit numeric-only attribution. Coarse CPU and fine wall stages are separate views.
public final class SamplerProfile {
    public enum Coarse: String, Codable { case enumeration, processLoop, stringReuse, systemCounters, volumes, interfaces, power }
    public enum Fine: String, Codable { case processOS, attribution, portsValidation, construction }
    public struct CPUStage: Codable, Sendable {
        public var calls = 0
        public var cpuSeconds: Double? = 0
        public var wallSeconds: Double? = 0
        public var unknownCPUIntervals = 0
        public var unknownWallIntervals = 0
    }
    public struct WallStage: Codable, Sendable {
        public var calls = 0
        public var wallSeconds: Double? = 0
        public var unknownWallIntervals = 0
    }
    public struct Report: Codable, Sendable {
        public var coarse: [String: CPUStage]
        public var fineWall: [String: WallStage]
        public var incompleteCoarse: String?
        public var incompleteIteration: Bool
        public var notes: [String]
    }
    struct Reading { var wall: Double; var cpu: Double? }
    private let readCPU: () -> Reading
    private let readWall: () -> Double
    private var active: (Coarse, Reading)?
    private var boundary: Reading?
    private var finalReport: Report?
    private var fineStart: Double?
    private var coarse: [String: CPUStage] = [:]
    private var fine: [String: WallStage] = [:]
    private var finalized = false
    public convenience init(measurement: OwnCurrentThreadMeasurement) {
        let origin = ContinuousClock.now
        self.init(readCPU: {
            let value = measurement.report()
            return Reading(wall: value.wallSeconds, cpu: value.cpuSeconds)
        }, readWall: {
            let duration = origin.duration(to: .now).components
            return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        })
    }
    init(readCPU: @escaping () -> Reading, readWall: @escaping () -> Double) {
        self.readCPU = readCPU; self.readWall = readWall
    }
    public func begin(_ stage: Coarse) {
        guard !finalized, active == nil else { return }
        active = (stage, boundary ?? readCPU())
    }
    public func end(_ stage: Coarse) {
        guard !finalized, let (current, start) = active, current == stage else { return }
        active = nil
        let end = readCPU(); boundary = end
        var value = coarse[stage.rawValue] ?? CPUStage()
        value.calls += 1
        if let delta = Self.delta(start.wall, end.wall) {
            if let previous = value.wallSeconds { value.wallSeconds = previous + delta }
        } else { value.wallSeconds = nil; value.unknownWallIntervals += 1 }
        if let delta = Self.delta(start.cpu, end.cpu) {
            if let previous = value.cpuSeconds { value.cpuSeconds = previous + delta }
        } else { value.cpuSeconds = nil; value.unknownCPUIntervals += 1 }
        coarse[stage.rawValue] = value
    }
    public func beginIteration() {
        guard !finalized, fineStart == nil else { return }
        fineStart = readWall()
    }
    /// One boundary read closes a phase and becomes the next phase's starting point.
    public func endFine(_ stage: Fine) {
        guard !finalized, let start = fineStart else { return }
        let end = readWall(); fineStart = end
        var value = fine[stage.rawValue] ?? WallStage()
        value.calls += 1
        if let delta = Self.delta(start, end) {
            if let previous = value.wallSeconds { value.wallSeconds = previous + delta }
        } else { value.wallSeconds = nil; value.unknownWallIntervals += 1 }
        fine[stage.rawValue] = value
    }
    public func endIteration() { guard !finalized else { return }; fineStart = nil }
    public func finish() -> Report {
        if let finalReport { return finalReport }
        let incomplete = active?.0.rawValue
        if let incomplete {
            var value = coarse[incomplete] ?? CPUStage()
            value.cpuSeconds = nil; value.wallSeconds = nil
            value.unknownCPUIntervals += 1; value.unknownWallIntervals += 1
            coarse[incomplete] = value
        }
        let report = Report(coarse: coarse, fineWall: fine, incompleteCoarse: incomplete,
            incompleteIteration: fineStart != nil,
            notes: ["Verification-only numeric sampler attribution; no process metadata.",
                    "Coarse stages use cumulative own-current-thread CPU differences from one owned Mach port. They exclude other threads and dispatched work; timer quantization applies. Reused boundaries include intervening recorder, bookkeeping and setup work.",
                    "Fine attribution includes marker-existence filesystem queries and is not pure Swift CPU work.",
                    "Fine stages contain aggregate monotonic WALL time and counts only, not CPU. They are inside processLoop; never add them to coarse CPU or whole-process sums.",
                    "Boundary reads and accumulator work are included in measurement cost; no overhead subtraction or whole-app budget claim.",
                    "Missing, nonfinite and regressed readings remain unknown. Incomplete stages are explicit; no fabricated zero completion."])
        finalized = true; finalReport = report
        return report
    }
    private static func delta(_ before: Double?, _ after: Double?) -> Double? {
        guard let before, let after, before.isFinite, after.isFinite, before >= 0, after >= before else { return nil }
        return after - before
    }
}
