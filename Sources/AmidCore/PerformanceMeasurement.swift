import Foundation
import Darwin
import CAmid

/// Measures only this process. CPU uses getrusage timeval seconds; RSS is lifetime bytes.
public struct PerformanceMeasurement: Sendable {
    private let started: ContinuousClock.Instant
    private let baseline: Counters
    public init() {
        started = ContinuousClock.now
        baseline = Self.usage()
    }
    struct Counters: Sendable {
        var cpu: Double?
        var peakRSS: Int64?
        var voluntary: Int64?
        var involuntary: Int64?
        var interrupts: UInt64?
        var packageIdle: UInt64?
    }
    public struct Report: Codable, Sendable {
        public var elapsedSeconds: Double
        public var cpuSeconds: Double?
        public var meanCPUPercentOneCore: Double?
        public var peakResidentBytes: Int64?
        public var voluntaryContextSwitches: Int64?
        public var involuntaryContextSwitches: Int64?
        public var interruptWakeups: UInt64?
        public var packageIdleWakeups: UInt64?
        public var interruptWakeupsPerSecond: Double?
        public var packageIdleWakeupsPerSecond: Double?
        public var notes: [String]
    }
    public func report(notes: [String]) -> Report {
        let current = Self.usage()
        let duration = started.duration(to: ContinuousClock.now).components
        let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        return Self.makeReport(elapsed: elapsed, baseline: baseline, current: current, notes: notes)
    }
    static func makeReport(elapsed: Double, baseline: Counters, current: Counters, notes: [String]) -> Report {
        func difference<T: Numeric & Comparable>(_ before: T?, _ after: T?) -> T? {
            guard let before, let after, before >= 0, after >= before else { return nil }
            return after - before
        }
        let cpu = difference(baseline.cpu, current.cpu).flatMap { $0.isFinite ? $0 : nil }
        let interrupts = difference(baseline.interrupts, current.interrupts)
        let packageIdle = difference(baseline.packageIdle, current.packageIdle)
        let validDuration = elapsed.isFinite && elapsed > 0
        return Report(elapsedSeconds: elapsed, cpuSeconds: cpu,
                      meanCPUPercentOneCore: validDuration ? cpu.map { $0 / elapsed * 100 } : nil,
                      peakResidentBytes: current.peakRSS.flatMap { $0 >= 0 ? $0 : nil },
                      voluntaryContextSwitches: difference(baseline.voluntary, current.voluntary),
                      involuntaryContextSwitches: difference(baseline.involuntary, current.involuntary),
                      interruptWakeups: interrupts, packageIdleWakeups: packageIdle,
                      interruptWakeupsPerSecond: validDuration ? interrupts.map { Double($0) / elapsed } : nil,
                      packageIdleWakeupsPerSecond: validDuration ? packageIdle.map { Double($0) / elapsed } : nil,
                      notes: notes + ["Elapsed time uses ContinuousClock. CPU and context switches are interval getrusage(RUSAGE_SELF) deltas. Peak RSS is a process-lifetime maximum, including startup and warmup. Wakeups are separate own-process libproc interrupt and package-idle counter deltas; neither is a total of all wakeups. Unavailable or regressed counters are unknown."])
    }
    private static func usage() -> Counters {
        var value = rusage()
        let available = getrusage(RUSAGE_SELF, &value) == 0
        let seconds = Double(value.ru_utime.tv_sec) + Double(value.ru_stime.tv_sec)
        let fraction = (Double(value.ru_utime.tv_usec) + Double(value.ru_stime.tv_usec)) / 1_000_000
        var interrupts: UInt64 = 0, packageIdle: UInt64 = 0
        let wakeupsAvailable = amid_own_wakeups(&interrupts, &packageIdle) != 0
        return Counters(cpu: available ? seconds + fraction : nil,
                        peakRSS: available ? Int64(value.ru_maxrss) : nil,
                        voluntary: available ? Int64(value.ru_nvcsw) : nil,
                        involuntary: available ? Int64(value.ru_nivcsw) : nil,
                        interrupts: wakeupsAvailable ? interrupts : nil,
                        packageIdle: wakeupsAvailable ? packageIdle : nil)
    }
}
