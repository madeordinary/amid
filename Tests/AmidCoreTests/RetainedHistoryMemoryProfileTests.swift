import XCTest
import CryptoKit
import Darwin
@testable import AmidCore

/// A successful Mach reply can be an older revision; missing fields remain unknown.
func fixtureMachReplyCoversField(count: mach_msg_type_number_t, capacity: Int, offset: Int?, size: Int) -> Bool {
    guard let offset, offset >= 0, size > 0, offset <= Int.max - size, Int(count) <= capacity else { return false }
    let requiredCount = (offset + size - 1) / MemoryLayout<integer_t>.size + 1
    return Int(count) >= requiredCount
}

/// Opt-in fixture-only generator/loader. Run each role in a fresh release test process.
final class RetainedHistoryMemoryProfileTests: XCTestCase, @unchecked Sendable {
    private struct Manifest: Encodable {
        var version = 3
        var settings: HistorySettings
        var aggregates: [HistoryAggregate] = []
        var alerts: [AlertEvent] = []
        var actions: [ActionRecord] = []
        var shortenedByCap = false
        var segmentFiles: [String]
    }
    private struct Fixture: Codable {
        var days: Int; var entities: Int; var minuteBuckets: Int; var hourlyBuckets: Int
        var records: Int; var ciphertextBytes: Int; var anchor: Date
    }
    private struct Checkpoint: Encodable {
        var phase: String; var residentBytes: UInt64?; var measuredMemoryBytes: UInt64?
        var measuredMemoryMethod: String; var lifetimePeakResidentBytes: Int64?
    }
    private struct StagePoint: Encodable {
        var stage: String; var aggregateCount: Int; var encodedSegmentCount: Int; var memory: Checkpoint
    }
    private final class StageRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var points: [StagePoint] = []
        func append(_ point: StagePoint) { lock.lock(); defer { lock.unlock() }; points.append(point) }
        func values() -> [StagePoint] { lock.lock(); defer { lock.unlock() }; return points }
    }
    private func checkpoint(_ phase: String) -> Checkpoint {
        var basic = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &basic) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        var vm = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let vmCapacity = Int(vmCount)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: vmCapacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        let basicKnown = result == KERN_SUCCESS && fixtureMachReplyCoversField(count: count, capacity: capacity,
            offset: MemoryLayout<mach_task_basic_info>.offset(of: \.resident_size), size: MemoryLayout.size(ofValue: basic.resident_size))
        let vmKnown = vmResult == KERN_SUCCESS && fixtureMachReplyCoversField(count: vmCount, capacity: vmCapacity,
            offset: MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint), size: MemoryLayout.size(ofValue: vm.phys_footprint))
        var usage = rusage()
        let usageAvailable = getrusage(RUSAGE_SELF, &usage) == 0
        return Checkpoint(phase: phase, residentBytes: basicKnown ? basic.resident_size : nil,
            measuredMemoryBytes: vmKnown ? vm.phys_footprint : nil,
            measuredMemoryMethod: vmKnown ? "Mach physical footprint" : "unavailable",
            lifetimePeakResidentBytes: usageAvailable ? Int64(usage.ru_maxrss) : nil)
    }
    private var fixtureKey: SymmetricKey { SymmetricKey(data: Data(repeating: 0x5a, count: 32)) }
    private func encrypted<T: Encodable>(_ value: T) throws -> Data {
        Data("AMID".utf8) + (try AES.GCM.seal(JSONEncoder().encode(value), using: fixtureKey,
            authenticating: Data("AMID".utf8)).combined!)
    }
    private func entity(_ index: Int, count: Int) -> (String, String) {
        let applicationCount = count == 21 ? 20 : count - 11
        if index == 0 { return ("system", "System") }
        if index <= applicationCount { return ("app:owned.synthetic.application.\(index)", "Owned Synthetic Application \(index)") }
        return ("project:/private/tmp/owned-synthetic-retained-history/workspace-\(index-applicationCount)", "Owned Synthetic Workspace \(index-applicationCount)")
    }
    func testMachReplyFieldCoverageRejectsShortAndImpossibleCounts() throws {
        let fields: [(Int, Int)] = [
            (try XCTUnwrap(MemoryLayout<mach_task_basic_info>.offset(of: \.resident_size)), MemoryLayout<UInt64>.size),
            (try XCTUnwrap(MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint)), MemoryLayout<UInt64>.size)
        ]
        for (offset, size) in fields {
            let required = (offset + size + MemoryLayout<integer_t>.size - 1) / MemoryLayout<integer_t>.size
            XCTAssertFalse(fixtureMachReplyCoversField(count: 0, capacity: required, offset: offset, size: size))
            XCTAssertFalse(fixtureMachReplyCoversField(count: mach_msg_type_number_t(required - 1), capacity: required, offset: offset, size: size))
            XCTAssertTrue(fixtureMachReplyCoversField(count: mach_msg_type_number_t(required), capacity: required, offset: offset, size: size))
            XCTAssertFalse(fixtureMachReplyCoversField(count: mach_msg_type_number_t(required + 1), capacity: required, offset: offset, size: size))
        }
        XCTAssertFalse(fixtureMachReplyCoversField(count: 100, capacity: 100, offset: nil, size: 8))
        XCTAssertFalse(fixtureMachReplyCoversField(count: 100, capacity: 100, offset: Int.max, size: 8))
    }
    func testOptInRetainedHistoryMemory() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let role = env["AMID_RETAINED_PROFILE"], ["generate", "load"].contains(role) else {
            throw XCTSkip("Opt-in retained-history fixture: separate generate/load release test processes.")
        }
        let path = try XCTUnwrap(env["AMID_RETAINED_DIRECTORY"])
        guard path.hasPrefix("/private/tmp/amid-owned-retained-profile-"), !path.contains(".."), !path.dropFirst("/private/tmp/".count).contains("/") else {
            XCTFail("Use one app-owned synthetic fixture directory directly under /private/tmp"); return
        }
        let directory = URL(fileURLWithPath: path)
        let descriptor = directory.appendingPathComponent("profile-fixture.json")
        let output = URL(fileURLWithPath: path + "-" + role + ".json")
        var loadReferenceDate: Date?
        if let value = env["AMID_RETAINED_REFERENCE_DATE"] {
            guard let seconds = Double(value), seconds.isFinite, abs(seconds - Date().timeIntervalSince1970) < 3600 else {
                XCTFail("Fixed fixture load reference must be a finite timestamp within one hour of current time"); return
            }
            loadReferenceDate = Date(timeIntervalSince1970: seconds)
        }
        let measurement = PerformanceMeasurement()
        var checkpoints = [checkpoint("before")]
        let recorder = StageRecorder()
        var actualMinuteRecords = 0, actualHourRecords = 0, actualBytes = 0
        var firstQuerySeconds: Double?, warmQuerySeconds: Double?
        var queryPointCount: Int?
        let fixture: Fixture
        if role == "generate" {
            let days = Int(env["AMID_RETAINED_DAYS"] ?? "7") ?? 0
            let entities = Int(env["AMID_RETAINED_ENTITIES"] ?? "21") ?? 0
            guard [7, 30].contains(days), [21, 76, 350].contains(entities) else { XCTFail("Bounded fixture choices only"); return }
            let hours = (days - 1) * 24
            let records = (1440 + hours) * entities
            XCTAssertLessThanOrEqual(records, 750_000)
            guard !FileManager.default.fileExists(atPath: path) else { XCTFail("Generator requires a new owned directory"); return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let anchor = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
            let hourlyEnd = floor(anchor.addingTimeInterval(-86400).timeIntervalSince1970 / 3600) * 3600
            var files: [String] = []; var bytes = 0
            for index in 0..<(hours + 1440) {
                let hourly = index < hours
                let resolution: Double = hourly ? 3600 : 60
                let start = hourly ? Date(timeIntervalSince1970: hourlyEnd - Double(hours-index) * 3600) : anchor.addingTimeInterval(Double(index-hours-1440) * 60)
                var values: [HistoryAggregate] = []
                for e in 0..<entities {
                    let (id, name) = entity(e, count: entities)
                    var value = HistoryAggregate(entityID: id, name: name, start: start, resolution: resolution)
                    value.samples = Int(resolution / 5); value.observedSeconds = resolution
                    value.cpuObservedSeconds = resolution; value.memoryObservedSeconds = resolution
                    value.cpu.add(Double(e % 10)); value.memory.add(Double((e + 1) * 1_048_576))
                    value.memoryMethods = [.footprint]; value.cadences = [5]
                    if e == 0 { value.load1.add(1); value.load5.add(2); value.load15.add(3); value.swap.add(0); value.pressureStates = [.normal] }
                    values.append(value)
                }
                let data = try encrypted(values)
                guard bytes + data.count <= 512 * 1024 * 1024 else { XCTFail("Fixture ciphertext bound exceeded"); return }
                let file = "bucket-\(Int64(start.timeIntervalSince1970))-\(Int(resolution)).aesgcm"
                try data.write(to: directory.appendingPathComponent(file), options: .atomic)
                files.append(file); bytes += data.count
            }
            let manifest = try encrypted(Manifest(settings: .init(retention: days == 7 ? .week : .month), segmentFiles: files))
            XCTAssertLessThanOrEqual(bytes + manifest.count, 512 * 1024 * 1024)
            try manifest.write(to: directory.appendingPathComponent("history.aesgcm"), options: .atomic)
            fixture = Fixture(days: days, entities: entities, minuteBuckets: 1440, hourlyBuckets: hours,
                records: records, ciphertextBytes: bytes + manifest.count, anchor: anchor)
            try JSONEncoder().encode(fixture).write(to: descriptor, options: .atomic)
            actualMinuteRecords = 1440 * entities; actualHourRecords = hours * entities; actualBytes = fixture.ciphertextBytes
            checkpoints.append(checkpoint("generated"))
        } else {
            fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: descriptor))
            guard [7, 30].contains(fixture.days), [21, 76, 350].contains(fixture.entities), fixture.records <= 750_000, fixture.ciphertextBytes <= 512 * 1024 * 1024 else { XCTFail("Fixture bounds invalid"); return }
            let store = HistoryStore(directory: directory, keyProvider: EphemeralHistoryKeyProvider(key: fixtureKey),
                commitObserver: { _ in }, memoryObserver: { stage, count, encoded in
                    recorder.append(StagePoint(stage: stage.rawValue, aggregateCount: count, encodedSegmentCount: encoded,
                        memory: self.checkpoint(stage.rawValue)))
                }, loadReferenceDate: loadReferenceDate)
            await store.load()
            checkpoints.append(checkpoint("loaded"))
            let metadata = await store.metadata()
            XCTAssertNil(metadata.error)
            XCTAssertGreaterThan(metadata.aggregateCount, 0)
            checkpoints.append(checkpoint("metadata"))
            await store.flush()
            checkpoints.append(checkpoint("flushed"))
            let until = loadReferenceDate ?? Date()
            let since = until.addingTimeInterval(-Double(fixture.days) * 86400)
            do {
                let started = ProcessInfo.processInfo.systemUptime
                let selected = await store.history(entityID: "system", since: since, until: until)
                firstQuerySeconds = ProcessInfo.processInfo.systemUptime - started
                XCTAssertNil(selected.error)
                XCTAssertFalse(selected.points.isEmpty)
                XCTAssertTrue(selected.points.allSatisfy { $0.entityID == "system" && $0.start >= since && $0.start <= until })
                queryPointCount = selected.points.count
                checkpoints.append(checkpoint("selected-query"))
                let warmStarted = ProcessInfo.processInfo.systemUptime
                let repeated = await store.history(entityID: "system", since: since, until: until)
                warmQuerySeconds = ProcessInfo.processInfo.systemUptime - warmStarted
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                XCTAssertEqual(try encoder.encode(repeated.points), try encoder.encode(selected.points))
                XCTAssertEqual(repeated.revision, selected.revision)
                checkpoints.append(checkpoint("warm-query"))
            }
            await store.clearQueryCache()
            checkpoints.append(checkpoint("query-cache-cleared"))
            // Validate after memory checkpoints; Set/ID construction can retain Foundation temporaries.
            do {
                let state = await store.state()
                checkpoints.append(checkpoint("diagnostic-state-materialized"))
                XCTAssertNil(state.error)
                if fixture.entities != 350 { XCTAssertFalse(state.shortenedByCap) }
                XCTAssertEqual(Set(state.aggregates.map(\.entityID)).count, fixture.entities)
                XCTAssertTrue(state.recentSnapshots.isEmpty)
                XCTAssertTrue(state.aggregates.allSatisfy { [60.0, 3600.0].contains($0.resolution) })
                XCTAssertTrue(state.aggregates.allSatisfy { $0.start.addingTimeInterval($0.resolution) > (loadReferenceDate ?? Date()).addingTimeInterval(-Double(fixture.days) * 86400) })
                actualMinuteRecords = state.aggregates.filter { $0.resolution == 60 }.count
                actualHourRecords = state.aggregates.filter { $0.resolution == 3600 }.count
                XCTAssertGreaterThan(actualMinuteRecords, 0)
                if fixture.entities != 350 || !state.shortenedByCap { XCTAssertGreaterThan(actualHourRecords, 0) }
                if fixture.ciphertextBytes > 250 * 1024 * 1024 {
                    XCTAssertTrue(state.shortenedByCap)
                    XCTAssertLessThan(state.aggregates.count, fixture.records)
                }
                XCTAssertLessThanOrEqual(state.aggregates.count, fixture.records)
                XCTAssertEqual(state.aggregates.count, metadata.aggregateCount)
                XCTAssertEqual(state.aggregates.filter { $0.entityID == "system" && $0.start >= since && $0.start <= until }.count, queryPointCount)
                actualBytes = state.storageBytes
                XCTAssertLessThanOrEqual(actualBytes, 250 * 1024 * 1024)
                let stages = recorder.values()
                XCTAssertEqual(stages.map(\.stage), ["decoded", "validated", "assigned", "decodeReturned", "enforced", "enforceReturned", "grouped", "encoded", "written", "indexReady", "loadReturned", "grouped", "encoded", "written", "indexReady"])
                XCTAssertTrue(stages.allSatisfy { $0.aggregateCount > 0 && $0.aggregateCount <= fixture.records })
                XCTAssertGreaterThan(stages.first { $0.stage == "encoded" }?.encodedSegmentCount ?? 0, 0)
                XCTAssertEqual(stages.last { $0.stage == "encoded" }?.encodedSegmentCount, 0)
            }
        }
        struct Evidence: Encodable {
            var role: String; var fixture: Fixture; var loadReferenceDate: Date?; var actualMinuteRecords: Int; var actualHourRecords: Int
            var firstQuerySeconds: Double?; var warmQuerySeconds: Double?; var queryPointCount: Int?
            var actualCiphertextBytes: Int; var checkpoints: [Checkpoint]; var stages: [StagePoint]; var process: PerformanceMeasurement.Report
            var invocation: String; var notes: [String]
        }
        let evidence = Evidence(role: role, fixture: fixture, loadReferenceDate: loadReferenceDate, actualMinuteRecords: actualMinuteRecords,
            actualHourRecords: actualHourRecords, firstQuerySeconds: firstQuerySeconds, warmQuerySeconds: warmQuerySeconds, queryPointCount: queryPointCount, actualCiphertextBytes: actualBytes, checkpoints: checkpoints, stages: recorder.values(),
            process: measurement.report(notes: ["Synthetic retained-history fixture only; not a GUI performance gate."]),
            invocation: (loadReferenceDate.map { "AMID_RETAINED_REFERENCE_DATE=\($0.timeIntervalSince1970) " } ?? "") + "AMID_RETAINED_PROFILE=\(role) AMID_RETAINED_DIRECTORY=\(path) AMID_RETAINED_DAYS=\(fixture.days) AMID_RETAINED_ENTITIES=\(fixture.entities) DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xctest -XCTest AmidCoreTests.RetainedHistoryMemoryProfileTests/testOptInRetainedHistoryMemory " + Bundle(for: Self.self).bundleURL.path,
            notes: ["Generator and loader must be separate fresh release test processes. Fixed public synthetic test key; no Keychain, host metadata, UI, heap or stack dump.",
                "Internal default-nil numeric stage callback enabled for this loader only. Whole-load/persist boundaries, no per-record callbacks. This source uses separate completed decode/enforce/persist scopes; decodeReturned/enforceReturned mark drainage before the next phase. indexReady means the index is valid; it may reuse the existing index instead of rebuilding when membership/order is unchanged. Checkpoints read only self Mach memory/getrusage; small recorder/counter overhead included. Numeric Mach replies require returned size to cover each requested field; older captured trials lacked this guard. Diagnostic GUI package frozen before this instrumentation excludes the callback.",
                "Internal test-only loadReferenceDate pins the exact epoch for paired comparisons; public production initializer uses the actual clock. Timestamp must be within one hour of current test time.",
                "1440 minute buckets plus older hourly buckets generated directly as encrypted version3 fixtures. Production load performs real retention/rollup/persist; wall-clock boundary advancement may reduce or merge oldest buckets. No five-second ingestion or raw ring is simulated.",
                "21entities means20apps+system;76 means65apps+10projects+system;350 means339apps+10projects+system. Names are bounded synthetic strings; entity churn and real metadata lengths are not represented.",
                "750000record/512MiB ciphertext fixture bound and unchanged250MiB production disk cap are not RSS bounds. The350entity case may invoke real oldest-bucket cap eviction. Lifetime peak includes test startup, but generator allocations are excluded from a fresh loader process.",
                "Checkpoint RSS is public self Mach task_info; measured memory uses self public TASK_VM_INFO physical footprint (numeric-only helper revision). Metadata/load/flush and selected-query checkpoints precede expensive diagnostic state materialization. The diagnostic-state checkpoint and whole-process peak include the full returned archive and validation; they are not production working-set measurements. Releasing values need not immediately release allocator pages. Process CPU interval includes validation. Actual runner exit must be recorded separately."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: output, options: .atomic)
    }
}
