import XCTest
import Foundation
@testable import AmidCore

/// Opt-in numeric profile of history ingestion against an imported synthetic seven-day store.
/// One live sample supplies realistic processes; ingestion then advances simulated five-second time.
final class IngestCostProfileTests: XCTestCase {
    private struct Call: Encodable { var index: Int; var minuteBoundary: Bool; var cpuMilliseconds: Double?; var wallMilliseconds: Double }
    private struct Evidence: Encodable {
        var processes: Int; var loadedAggregates: Int; var calls: [Call]
        var meanOrdinaryMilliseconds: Double?; var meanBoundaryMilliseconds: Double?
        var amortizedPerSampleAtFiveSeconds: Double?; var notes: [String]
    }

    func testOptInIngestCostAgainstSeededStore() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AMID_INGEST_PROFILE"] == "1" else { throw XCTSkip("Opt-in ingestion cost profile") }
        let seed = try XCTUnwrap(environment["AMID_INGEST_SEED"]), hash = try XCTUnwrap(environment["AMID_INGEST_SEED_SHA256"])
        let output = try XCTUnwrap(environment["AMID_INGEST_OUTPUT"])
        guard output.hasPrefix("/private/tmp/amid-"), output.hasSuffix(".json"), !FileManager.default.fileExists(atPath: output) else {
            XCTFail("Require a fresh owned /private/tmp/amid-*.json output"); return
        }
        let destination = URL(fileURLWithPath: "/private/tmp/amid-ui-verification-seeded-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: destination) }
        let imported = try VerificationHistorySeed.importStore(from: URL(fileURLWithPath: seed), to: destination,
                                                               expectedManifestSHA256: hash, verificationMode: true)
        let store = imported.store
        await store.load()
        let loaded = await store.metadata()
        XCTAssertNil(loaded.error)
        let live = await Sampler(mode: .incremental()).sample(cadence: 5)
        var calls: [Call] = []
        let start = Date()
        var previousMinute: Double?
        for index in 0..<60 {
            var snapshot = live
            snapshot.timestamp = start.addingTimeInterval(Double(index) * 5)
            snapshot.cadence = 5; snapshot.expectedCadence = 5
            let minute = floor(snapshot.timestamp.timeIntervalSince1970 / 60)
            let boundary = previousMinute.map { $0 != minute } ?? true
            previousMinute = minute
            let report = await store.profiledIngest(snapshot)
            calls.append(Call(index: index, minuteBoundary: boundary, cpuMilliseconds: report.cpuSeconds.map { $0 * 1000 }, wallMilliseconds: report.wallSeconds * 1000))
        }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let measured = calls.dropFirst()
        let ordinary = mean(measured.filter { !$0.minuteBoundary }.compactMap(\.cpuMilliseconds))
        let boundary = mean(measured.filter(\.minuteBoundary).compactMap(\.cpuMilliseconds))
        let amortized = mean(measured.compactMap(\.cpuMilliseconds))
        let evidence = Evidence(processes: live.processes.count, loadedAggregates: loaded.aggregateCount, calls: calls,
                                meanOrdinaryMilliseconds: ordinary, meanBoundaryMilliseconds: boundary, amortizedPerSampleAtFiveSeconds: amortized,
                                notes: ["Own ingestion-thread CPU per call; the first call is excluded from means.",
                                        "Simulated five-second timestamps; minute-boundary calls enforce retention and persist encrypted state."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(evidence).write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
        print("INGEST_PROFILE ordinary=\(ordinary ?? -1)ms boundary=\(boundary ?? -1)ms amortized=\(amortized ?? -1)ms processes=\(live.processes.count) aggregates=\(loaded.aggregateCount)")
    }
}
