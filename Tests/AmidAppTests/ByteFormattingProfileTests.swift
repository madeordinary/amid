import XCTest
import Foundation
import Darwin
@testable import AmidApp
import AmidCore

final class ByteFormattingProfileTests: XCTestCase {
    @MainActor
    func testCachedFormatterPreservesByteOutput() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let values: [UInt64?] = [nil, 0, 1, 1023, 1024, 1025, 1_048_575, 1_048_576, 1_073_741_824, UInt64(Int64.max), UInt64.max]
        for value in values {
            let cached = value.map { formatter.string(fromByteCount: Int64(clamping: $0)) } ?? localized("Unavailable")
            XCTAssertEqual(bytes(value), cached)
        }
    }

    @MainActor
    func testOptInFormattingCPUProfile() throws {
        guard ProcessInfo.processInfo.environment["AMID_BYTE_FORMAT_PROFILE"] == "1" else {
            throw XCTSkip("Opt-in synthetic formatting profile; no application performance claim.")
        }
        struct Measurement: Codable {
            var calls: Int
            var ownCPUSeconds: Double?
            var wallSeconds: Double
            var outputUTF8Bytes: Int
        }
        struct Report: Codable {
            var scope: String
            var convenience: Measurement
            var cached: Measurement
        }
        func ownCPU() -> Double? {
            var usage = rusage()
            guard getrusage(RUSAGE_SELF, &usage) == 0,
                  usage.ru_utime.tv_sec >= 0, usage.ru_utime.tv_usec >= 0,
                  usage.ru_stime.tv_sec >= 0, usage.ru_stime.tv_usec >= 0 else { return nil }
            let value = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            return value.isFinite ? value : nil
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let values: [UInt64?] = [nil, 0, 1023, 1024, 1_048_576, 37_123_456, UInt64.max]
        func measure(_ format: (UInt64?) -> String) -> Measurement {
            let startCPU = ownCPU()
            let start = ContinuousClock.now
            var checksum = 0
            for _ in 0..<10 {
                for tick in 0..<36 {
                    for call in 0..<60 { checksum += format(values[(tick + call) % values.count]).utf8.count }
                }
            }
            let endCPU = ownCPU()
            let elapsed = start.duration(to: .now).components
            let delta = startCPU.flatMap { first in endCPU.flatMap { last in last >= first ? last - first : nil } }
            return Measurement(calls: 21_600, ownCPUSeconds: delta,
                wallSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                outputUTF8Bytes: checksum)
        }
        // Warm both paths equally; measured loops preserve the same nil and clamping behavior.
        for value in values {
            XCTAssertEqual(bytes(value), value.map { formatter.string(fromByteCount: Int64(clamping: $0)) } ?? localized("Unavailable"))
        }
        let convenience = measure(bytes)
        let cached = measure { value in
            value.map { formatter.string(fromByteCount: Int64(clamping: $0)) } ?? localized("Unavailable")
        }
        XCTAssertEqual(convenience.outputUTF8Bytes, cached.outputUTF8Bytes)
        let report = Report(scope: "Synthetic MainActor byte formatting only; 10 batches × 36 ticks × 60 calls per variant. Own process CPU includes concurrent test-harness work. Fixed convenience-then-cached order; no whole-app or locale-change claim.", convenience: convenience, cached: cached)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        print("AMID_BYTE_FORMAT_PROFILE " + String(decoding: data, as: UTF8.self))
        if let path = ProcessInfo.processInfo.environment["AMID_BYTE_FORMAT_PROFILE_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
