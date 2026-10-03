import XCTest
import Foundation
import Darwin
@testable import AmidCore

final class ExecutableDerivationProfileTests: XCTestCase {
    private struct Input {
        var executable: String
        var identity: ProcessIdentity
        var name: String
    }
    private struct Derived {
        var id: String
        var name: String
        var reason: String
        var runtime: String?
    }
    private func derive(_ input: Input) -> Derived {
        let app = Sampler.application(executable: input.executable, identity: input.identity, name: input.name)
        return Derived(id: app.0, name: app.1, reason: app.2, runtime: Sampler.runtime(input.executable))
    }
    private func memoized(_ input: Input, memo: inout [Data: Derived]) -> Derived {
        // String equality is canonically equivalent; exact executable bytes must stay distinct.
        guard !input.executable.isEmpty else { return derive(input) }
        let key = Data(input.executable.utf8)
        if let cached = memo[key] { return cached }
        let value = derive(input)
        memo[key] = value
        return value
    }
    private func input(_ executable: String, index: Int) -> Input {
        Input(executable: executable, identity: ProcessIdentity(bootID: "synthetic", pid: Int32(index + 1), uid: 501, startSeconds: 1, startMicroseconds: UInt64(index)), name: "synthetic-\(index)")
    }
    private func assertBytesEqual(_ a: Derived, _ b: Derived, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Data(a.id.utf8), Data(b.id.utf8), file: file, line: line)
        XCTAssertEqual(Data(a.name.utf8), Data(b.name.utf8), file: file, line: line)
        XCTAssertEqual(Data(a.reason.utf8), Data(b.reason.utf8), file: file, line: line)
        XCTAssertEqual(a.runtime.map { Data($0.utf8) }, b.runtime.map { Data($0.utf8) }, file: file, line: line)
    }
    func testExactByteMemoPreservesDerivationAndEmptyFallback() {
        let paths = ["/Applications/Outer.app/Contents/Nested.app/Contents/MacOS/node", "/usr/bin/python3.12", "/usr/bin/swift-frontend", "/bin/plain", "/BIN/Node", "///odd//node", "/tmp/Caf\u{00e9}.app/node", "/tmp/Cafe\u{0301}.app/node", "", ""]
        var memo: [Data: Derived] = [:]
        for (index, path) in paths.enumerated() {
            let value = input(path, index: index)
            assertBytesEqual(derive(value), memoized(value, memo: &memo))
        }
        XCTAssertEqual(memo.count, paths.count - 2)
        let first = memoized(input("", index: 50), memo: &memo)
        let second = memoized(input("", index: 51), memo: &memo)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.name, second.name)
        XCTAssertEqual(memo.count, paths.count - 2)
        // Every sample starts fresh; no identity or metadata survives this candidate memo.
        memo.removeAll()
        XCTAssertTrue(memo.isEmpty)
        let changed = input("/bin/plain", index: 100)
        assertBytesEqual(derive(changed), memoized(changed, memo: &memo))
    }
    func testSparseAndRepeatedWorkloadsMatchExactly() {
        for distinct in [650, 65, 21] {
            var memo: [Data: Derived] = [:]
            for index in 0..<650 {
                let value = input("/Synthetic/App\(index % distinct).app/Contents/MacOS/node", index: index)
                assertBytesEqual(derive(value), memoized(value, memo: &memo))
            }
            XCTAssertEqual(memo.count, distinct)
        }
    }
    func testOptInExecutableDerivationCPUProfile() throws {
        guard ProcessInfo.processInfo.environment["AMID_EXECUTABLE_DERIVATION_PROFILE"] == "1" else {
            throw XCTSkip("Opt-in synthetic executable derivation comparison; no application performance claim.")
        }
        struct Measurement: Codable { var calls: Int; var ownCPUSeconds: Double?; var wallSeconds: Double; var checksum: Int }
        struct Workload: Codable { var processes: Int; var distinctPaths: Int; var current: Measurement; var transientMemo: Measurement }
        struct Report: Codable { var scope: String; var workloads: [Workload] }
        func cpu() -> Double? {
            var usage = rusage()
            guard getrusage(RUSAGE_SELF, &usage) == 0,
                  usage.ru_utime.tv_sec >= 0, usage.ru_utime.tv_usec >= 0,
                  usage.ru_stime.tv_sec >= 0, usage.ru_stime.tv_usec >= 0 else { return nil }
            let value = Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec)
                + (Double(usage.ru_utime.tv_usec) + Double(usage.ru_stime.tv_usec)) / 1e6
            return value.isFinite ? value : nil
        }
        func measure(_ inputs: [Input], useMemo: Bool) -> Measurement {
            let before = cpu(); let start = ContinuousClock.now
            var checksum = 0
            for _ in 0..<10 {
                for _ in 0..<36 {
                    var memo: [Data: Derived] = [:]
                    for input in inputs {
                        let result = useMemo ? memoized(input, memo: &memo) : derive(input)
                        checksum += result.id.utf8.count + result.name.utf8.count + result.reason.utf8.count + (result.runtime?.utf8.count ?? 0)
                    }
                }
            }
            let after = cpu(); let duration = start.duration(to: .now).components
            let delta = before.flatMap { first in after.flatMap { last in last >= first ? last - first : nil } }
            return Measurement(calls: inputs.count * 360, ownCPUSeconds: delta,
                wallSeconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18, checksum: checksum)
        }
        var workloads: [Workload] = []
        for distinct in [650, 65, 21] {
            let inputs = (0..<650).map { input("/Synthetic/App\($0 % distinct).app/Contents/MacOS/node", index: $0) }
            let current = measure(inputs, useMemo: false)
            let memo = measure(inputs, useMemo: true)
            XCTAssertEqual(current.checksum, memo.checksum)
            workloads.append(Workload(processes: 650, distinctPaths: distinct, current: current, transientMemo: memo))
        }
        let report = Report(scope: "Synthetic pure executable derivation only; 10 batches × 36 samples × 650 processes per variant per shape. Exact UTF8 Data keys, fresh memo per sample; current-then-memo order. Own process CPU includes harness work. No OS metadata or whole-app performance claim.", workloads: workloads)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        print("AMID_EXECUTABLE_DERIVATION_PROFILE " + String(decoding: data, as: UTF8.self))
        if let path = ProcessInfo.processInfo.environment["AMID_EXECUTABLE_DERIVATION_PROFILE_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
