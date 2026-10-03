import XCTest
import Darwin
@testable import AmidCore

final class RawRingMemoryProfileTests: XCTestCase, @unchecked Sendable {
    struct Checkpoint: Encodable {
        var samples: Int
        var currentResidentBytes: UInt64?
        var currentFootprintBytes: UInt64?
        var lifetimePeakResidentBytes: Int64?
    }
    private func ownMemory(samples: Int) -> Checkpoint {
        var basic = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let basicCapacity = Int(basicCount)
        let basicResult = withUnsafeMutablePointer(to: &basic) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: basicCapacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }
        var vm = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let vmCapacity = Int(vmCount)
        let vmResult = withUnsafeMutablePointer(to: &vm) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: vmCapacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        let basicKnown = basicResult == KERN_SUCCESS && fixtureMachReplyCoversField(count: basicCount, capacity: basicCapacity,
            offset: MemoryLayout<mach_task_basic_info>.offset(of: \.resident_size), size: MemoryLayout.size(ofValue: basic.resident_size))
        let vmKnown = vmResult == KERN_SUCCESS && fixtureMachReplyCoversField(count: vmCount, capacity: vmCapacity,
            offset: MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint), size: MemoryLayout.size(ofValue: vm.phys_footprint))
        var usage = rusage()
        let usageAvailable = getrusage(RUSAGE_SELF, &usage) == 0
        return Checkpoint(samples: samples,
            currentResidentBytes: basicKnown ? basic.resident_size : nil,
            currentFootprintBytes: vmKnown ? vm.phys_footprint : nil,
            lifetimePeakResidentBytes: usageAvailable ? Int64(usage.ru_maxrss) : nil)
    }
    private func fresh(_ value: String) -> String { String(decoding: Array(value.utf8), as: UTF8.self) }
    func testOptInFreshStringRingMemory() async throws {
        guard let mode = ProcessInfo.processInfo.environment["AMID_RAW_MEMORY_PROFILE"], ["baseline", "sharing"].contains(mode) else {
            throw XCTSkip("Opt-in synthetic raw-ring memory profile; use baseline or sharing in separate test processes.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-owned-memory-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider())
        let base = Date()
        await store.updateSettings(.init(retention: .off), now: base)
        var checkpoints = [ownMemory(samples: 0)]
        var storage = ProcessStringStorage()
        let measurement = PerformanceMeasurement()
        for sampleIndex in 0...180 {
            var processes: [ProcessSample] = []
            for index in 0..<600 {
                let suffix = index == 0 ? sampleIndex / 45 : index % 50
                let executable = fresh("/Applications/Owned Synthetic Application \(suffix).app/Contents/MacOS/Owned Synthetic Runtime")
                let identity = ProcessIdentity(bootID: "synthetic-memory-fixture", pid: Int32(index + 100), uid: 501, startSeconds: 1, startMicroseconds: 0)
                let app = Sampler.application(executable: executable, identity: identity, name: "Unused fallback")
                let cwd: String? = index == 1 && sampleIndex % 30 == 0 ? nil : fresh("/private/tmp/amid-owned-synthetic-memory/project-\(index % 3)/workspace-\(index == 1 ? sampleIndex / 60 : 0)")
                let endpoints: [Endpoint] = index % 10 == 0 ? [.init(address: fresh("fd00:0000:0000:0000:0000:0000:0000:0001"), port: UInt16(4000 + index), family: "IPv6", scope: "Interface")] : []
                let current = ProcessSample(identity: identity, executable: executable,
                    name: fresh("Owned Synthetic Process \(index)"), runtime: "Swift",
                    cpuPercent: Double(sampleIndex % 10), memoryBytes: UInt64(1_048_576 + sampleIndex), memoryMethod: .footprint,
                    workingDirectory: cwd, projectPath: fresh("/private/tmp/amid-owned-synthetic-memory/project-\(index % 3)"),
                    applicationID: app.0, applicationName: app.1, groupingReason: app.2,
                    endpoints: endpoints, portAvailability: .available, observedSince: base)
                let value = current
                // Field equality is tested on changed executable/CWD and missing CWD, not only stable values.
                XCTAssertEqual(value.executable, current.executable); XCTAssertEqual(value.workingDirectory, current.workingDirectory)
                XCTAssertEqual(value.applicationID, current.applicationID); XCTAssertEqual(value.endpoints, current.endpoints)
                XCTAssertEqual(value.cpuPercent, current.cpuPercent); XCTAssertEqual(value.memoryBytes, current.memoryBytes)
                processes.append(value)
            }
            if mode == "sharing" { storage.reuseStorage(in: &processes) }
            XCTAssertEqual(processes.count, 600)
            XCTAssertEqual(processes[0].executable, "/Applications/Owned Synthetic Application \(sampleIndex / 45).app/Contents/MacOS/Owned Synthetic Runtime")
            if sampleIndex % 30 == 0 { XCTAssertNil(processes[1].workingDirectory) }
            await store.ingest(Snapshot(timestamp: base.addingTimeInterval(Double(sampleIndex) * 5), processes: processes,
                cadence: 5, expectedCadence: 5, availability: .available))
            if [44, 89, 134, 180].contains(sampleIndex) { checkpoints.append(ownMemory(samples: sampleIndex + 1)) }
        }
        let retainedCount = await store.state().recentSnapshots.count
        XCTAssertEqual(retainedCount, 181)
        let report = measurement.report(notes: ["Synthetic fixture memory experiment, not a GUI performance budget measurement."])
        storage.reset()
        XCTAssertEqual(storage.retainedIdentityCount, 0)
        await store.clearMemory()
        let clearedCount = await store.state().recentSnapshots.count
        XCTAssertEqual(clearedCount, 0)
        let afterClear = ownMemory(samples: 0)
        struct Evidence: Encodable {
            var mode: String; var processCount: Int; var retainedSamples: Int; var checkpoints: [Checkpoint]
            var afterClear: Checkpoint; var process: PerformanceMeasurement.Report; var invocation: String; var notes: [String]
        }
        let evidence = Evidence(mode: mode, processCount: 600, retainedSamples: retainedCount, checkpoints: checkpoints,
            afterClear: afterClear, process: report,
            invocation: "AMID_RAW_MEMORY_PROFILE=\(mode) DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xctest -XCTest AmidCoreTests.RawRingMemoryProfileTests/testOptInFreshStringRingMemory " + Bundle(for: Self.self).bundleURL.path,
            notes: [
                "Release test; each mode must run in a fresh subprocess. 181 logical five-second samples preserve a full15-minute ring. No actual15-minute wait, host process sampling, UI, network, stack or heap dump.",
                "600fixtures with long UTF8 strings rebuilt every sample;10%haveoneIPv6endpoint. Boot/runtime/reason constants share as production literals. Off retention isolates raw memory; only choice is encrypted with ephemeral key.",
                "Sharing mode uses the production ProcessStringStorage helper: exact UTF8-equal reuse of prior string storage for the same full process identity. Every current value is independently recreated and compared; executable/CWD changes and missing CWD remain fresh. Endpoint arrays are not shared.",
                "Current RSS/footprint use public Mach task_info on self with returned-field-size checks (older captured profiles lacked these checks); lifetime peak RSS uses getrusage. Memory after clear need not return to baseline because allocator/framework caches can retain freed pages. This fixture cannot prove the size of real process metadata or GUI savings.",
                "Actual runner exit must be recorded separately. This profile measures the helper with synthetic metadata, not live sampler or GUI savings."
            ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: URL(fileURLWithPath: "/private/tmp/amid-raw-ring-\(mode).json"), options: .atomic)
    }
}
