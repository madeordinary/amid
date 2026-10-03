import XCTest
import Foundation
@testable import AmidCore

final class SamplerProfileTests: XCTestCase {
    func testCoarseCPUAndFineWallAreSeparateAndBoundaryReadsAreBounded() throws {
        var cpu = [SamplerProfile.Reading(wall: 0, cpu: 10), .init(wall: 3, cpu: 11), .init(wall: 5, cpu: 12)]
        var wall = [0.0, 0.5, 1.5, 2.0, 2.5]
        let profile = SamplerProfile(readCPU: { cpu.removeFirst() }, readWall: { wall.removeFirst() })
        profile.begin(.processLoop)
        profile.beginIteration()
        for stage in [SamplerProfile.Fine.processOS, .attribution, .portsValidation, .construction] { profile.endFine(stage) }
        profile.endIteration(); profile.end(.processLoop)
        profile.begin(.volumes); profile.end(.volumes)
        let report = profile.finish()
        XCTAssertEqual(report.coarse["processLoop"]?.cpuSeconds, 1)
        XCTAssertEqual(report.coarse["volumes"]?.cpuSeconds, 1)
        XCTAssertEqual(report.fineWall["attribution"]?.wallSeconds, 1)
        XCTAssertEqual(report.fineWall.values.reduce(0) { $0 + $1.calls }, 4)
        XCTAssertNil(report.incompleteCoarse); XCTAssertFalse(report.incompleteIteration)
        XCTAssertTrue(cpu.isEmpty); XCTAssertTrue(wall.isEmpty)
        profile.begin(.power); profile.beginIteration(); profile.endFine(.processOS)
        XCTAssertEqual(profile.finish().coarse.count, report.coarse.count)
    }
    func testEarlyIterationExitCountsOnlyObservedStages() {
        let profile = SamplerProfile(readCPU: { .init(wall: 0, cpu: 0) }, readWall: { 0 })
        profile.beginIteration(); profile.endFine(.processOS); profile.endIteration()
        let report = profile.finish()
        XCTAssertEqual(report.fineWall["processOS"]?.calls, 1)
        XCTAssertNil(report.fineWall["attribution"])
        XCTAssertNil(report.fineWall["portsValidation"])
        XCTAssertNil(report.fineWall["construction"])
        XCTAssertFalse(report.incompleteIteration)
    }
    func testUnknownRegressionAndIncompleteStagesRemainExplicit() {
        var readings = [SamplerProfile.Reading(wall: 1, cpu: 10), .init(wall: 0, cpu: nil), .init(wall: 2, cpu: 12)]
        let profile = SamplerProfile(readCPU: { readings.removeFirst() }, readWall: { .nan })
        profile.begin(.processLoop); profile.end(.processLoop)
        profile.begin(.processLoop); profile.end(.processLoop)
        profile.begin(.volumes); profile.beginIteration(); profile.endFine(.processOS)
        let report = profile.finish()
        XCTAssertNil(report.coarse["processLoop"]?.cpuSeconds)
        XCTAssertNil(report.coarse["processLoop"]?.wallSeconds)
        XCTAssertEqual(report.coarse["processLoop"]?.calls, 2)
        XCTAssertNil(report.fineWall["processOS"]?.wallSeconds)
        XCTAssertEqual(report.incompleteCoarse, "volumes")
        XCTAssertTrue(report.incompleteIteration)
        XCTAssertNil(report.coarse["volumes"]?.cpuSeconds)
        XCTAssertEqual(profile.finish().coarse["volumes"]?.unknownCPUIntervals, 1)
    }
    func testRefinedWallBoundariesAndNumericCountersAreSeparate() throws {
        var wall = [0.0, 1.0, 3.0, 6.0]
        let profile = SamplerProfile(readCPU: { .init(wall: 0, cpu: 0) }, readWall: { wall.removeFirst() })
        profile.beginIteration()
        profile.endFine(.decoding); profile.endFine(.application); profile.endFine(.project)
        profile.endIteration()
        profile.count(.cwdCacheMiss); profile.count(.cwdCacheHit)
        profile.count(.markerCacheMiss); profile.count(.markerCacheHit)
        for _ in 0..<6 { profile.count(.markerAccess) }
        let report = profile.finish()
        XCTAssertEqual(report.fineWall["decoding"]?.wallSeconds, 1)
        XCTAssertEqual(report.fineWall["application"]?.wallSeconds, 2)
        XCTAssertEqual(report.fineWall["project"]?.wallSeconds, 3)
        XCTAssertEqual(report.counters, ["cwdCacheMiss": 1, "cwdCacheHit": 1, "markerCacheMiss": 1, "markerCacheHit": 1, "markerAccess": 6])
        profile.count(.markerAccess)
        XCTAssertEqual(profile.finish().counters?["markerAccess"], 6)
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(report)) as? [String: Any])
        object.removeValue(forKey: "counters")
        let historical = try JSONDecoder().decode(SamplerProfile.Report.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(historical.counters)
    }
    func testProjectCountersReflectActualMarkerQueriesAndCacheReuse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-marker-profile-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent(".git"))
        var cache: [String: Bool] = [:]
        let profile = SamplerProfile(readCPU: { .init(wall: 0, cpu: 0) }, readWall: { 0 })
        let first = ProjectAttribution.root(for: directory.path, boundaries: [], markerCache: &cache, profile: profile)
        let second = ProjectAttribution.root(for: directory.path, boundaries: [], markerCache: &cache, profile: profile)
        XCTAssertEqual(first, second); XCTAssertNotNil(first)
        XCTAssertEqual(profile.finish().counters, ["markerCacheMiss": 1, "markerCacheHit": 1, "markerAccess": 1])
        XCTAssertEqual(ProjectAttribution.root(for: directory.path), first)
    }
    func testOptInBoundaryReadCalibration() throws {
        guard ProcessInfo.processInfo.environment["AMID_SAMPLER_BOUNDARY_PROFILE"] == "1" else {
            throw XCTSkip("Opt-in synthetic numeric sampler instrumentation calibration.")
        }
        struct Report: Codable { var samples: Int; var iterationsPerSample: Int; var fineBoundaryReads: Int; var coarseCounterReads: Int; var ownCPUSeconds: Double?; var wallSeconds: Double; var scope: String }
        let measurement = OwnCurrentThreadMeasurement()
        for _ in 0..<100 {
            let profile = SamplerProfile(measurement: measurement)
            profile.begin(.enumeration); profile.end(.enumeration)
            profile.begin(.processLoop)
            for _ in 0..<1082 {
                profile.beginIteration()
                for stage in [SamplerProfile.Fine.processOS, .decoding, .application, .project, .portsValidation, .construction] { profile.endFine(stage) }
                profile.endIteration()
            }
            profile.end(.processLoop)
            for stage in [SamplerProfile.Coarse.stringReuse, .systemCounters, .volumes, .interfaces, .power] { profile.begin(stage); profile.end(stage) }
            let result = profile.finish()
            XCTAssertEqual(result.fineWall["construction"]?.calls, 1082)
        }
        let timing = measurement.report()
        let report = Report(samples: 100, iterationsPerSample: 1082, fineBoundaryReads: 757400, coarseCounterReads: 800,
            ownCPUSeconds: timing.cpuSeconds, wallSeconds: timing.wallSeconds,
            scope: "Synthetic empty sampler instrumentation only; one owned current-thread Mach port, 100 samples × 1082 iterations. Includes dictionary accumulation and report construction; no overhead subtraction or application performance claim.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        print("AMID_SAMPLER_BOUNDARY_PROFILE " + String(decoding: data, as: UTF8.self))
        if let path = ProcessInfo.processInfo.environment["AMID_SAMPLER_BOUNDARY_PROFILE_OUTPUT"] { try data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    }
}
