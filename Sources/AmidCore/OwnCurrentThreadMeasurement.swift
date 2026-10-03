import Foundation
import Darwin

/// Numeric counters for this caller's thread only. Keep usage synchronous, without await.
public final class OwnCurrentThreadMeasurement {
    public struct Report: Codable, Sendable {
        public var wallSeconds: Double
        public var cpuSeconds: Double?
    }
    private let started = ContinuousClock.now
    private let thread: mach_port_t
    private let baseline: Double?
    private let readCPU: (mach_port_t) -> Double?
    private let release: (mach_port_t) -> Void
    public convenience init() {
        self.init(thread:mach_thread_self(),readCPU:Self.cpu,release:{ mach_port_deallocate(mach_task_self_,$0) })
    }
    init(thread: mach_port_t, readCPU: @escaping (mach_port_t) -> Double?, release: @escaping (mach_port_t) -> Void) {
        self.thread = thread; self.readCPU = readCPU; self.release = release
        baseline = thread == MACH_PORT_NULL ? nil : readCPU(thread)
    }
    deinit { if thread != MACH_PORT_NULL { release(thread) } }
    public func report() -> Report {
        let duration = started.duration(to:.now).components
        let wall = Double(duration.seconds) + Double(duration.attoseconds)/1e18
        // Refuse a moved caller: never turn this into an arbitrary-thread counter API.
        let current = thread != MACH_PORT_NULL && pthread_mach_thread_np(pthread_self()) == thread ? readCPU(thread) : nil
        return Report(wallSeconds:wall,cpuSeconds:Self.delta(baseline,current))
    }
    static func delta(_ before: Double?,_ after: Double?) -> Double? {
        guard let before, let after, before.isFinite, after.isFinite, before >= 0, after >= before else { return nil }; return after-before
    }
    private static func cpu(_ thread: mach_port_t) -> Double? {
        var info = thread_basic_info_data_t()
        let expected = MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        var count = mach_msg_type_number_t(expected)
        let status = withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:expected) { thread_info(thread,thread_flavor_t(THREAD_BASIC_INFO),$0,&count) }
        }
        guard status == KERN_SUCCESS, Int(count) == expected,
              info.user_time.seconds >= 0, info.user_time.microseconds >= 0,
              info.system_time.seconds >= 0, info.system_time.microseconds >= 0 else { return nil }
        return Double(info.user_time.seconds) + Double(info.system_time.seconds) + (Double(info.user_time.microseconds) + Double(info.system_time.microseconds))/1_000_000
    }
}
