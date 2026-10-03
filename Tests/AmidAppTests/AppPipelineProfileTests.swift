import XCTest
@testable import AmidApp
@testable import AmidCore

final class AppPipelineProfileTests: XCTestCase {
    @MainActor
    func testSamplerBreakdownIsSupplementalAndBoundedByMeasurementLifetime() throws {
        var readings = [AppPipelineProfile.Reading(wall: 0, cpu: 10), .init(wall: 1, cpu: 12)]
        let profile = AppPipelineProfile(read: { readings.removeFirst() })
        let sampler = SamplerProfile.Report(coarse: [:], fineWall: [:], incompleteCoarse: nil, incompleteIteration: false, notes: [])
        profile.recordSamplerBreakdown(sampler)
        profile.start(); profile.recordSamplerBreakdown(sampler)
        let report = try XCTUnwrap(profile.finish(benchmarkPhase: "completed"))
        XCTAssertEqual(report.samplerBreakdown.count, 1)
        XCTAssertEqual(report.measuredPhaseCPUSeconds, 0)
        XCTAssertEqual(report.residualCPUSeconds, 2)
        profile.recordSamplerBreakdown(sampler)
        XCTAssertNil(profile.finish(benchmarkPhase: "completed"))
    }
    @MainActor
    func testCollectionThreadIsSupplementalAndRespectsMeasurementLifetime() throws {
        var readings = [AppPipelineProfile.Reading(wall: 0, cpu: 10), .init(wall: 1, cpu: 12)]
        let profile = AppPipelineProfile(read: { readings.removeFirst() })
        let thread = OwnCurrentThreadMeasurement.Report(wallSeconds: 0.2, cpuSeconds: 0.1)
        profile.recordCollectionThread(thread)
        profile.start()
        profile.recordCollectionThread(thread)
        let report = try XCTUnwrap(profile.finish(benchmarkPhase: "completed"))
        XCTAssertEqual(report.collectionThread.calls, 1)
        XCTAssertEqual(report.collectionThread.cpuSeconds, 0.1)
        XCTAssertEqual(report.ingestionThread.calls, 0)
        XCTAssertEqual(report.measuredPhaseCPUSeconds, 0)
        XCTAssertEqual(report.residualCPUSeconds, 2)
        profile.recordCollectionThread(thread)
        XCTAssertNil(profile.finish(benchmarkPhase: "completed"))
    }
    @MainActor
    func testPhasesDoNotOverlapAndResidualIsExplicit() throws {
        var readings = [AppPipelineProfile.Reading(wall:0,cpu:10), .init(wall:1,cpu:11), .init(wall:3,cpu:13), .init(wall:5,cpu:15)]
        let profile = AppPipelineProfile(read:{ readings.removeFirst() })
        XCTAssertNil(profile.begin(.collection))
        profile.start()
        let token = profile.begin(.collection)
        XCTAssertNil(profile.begin(.grouping))
        profile.end(token); profile.end(token)
        let report = try XCTUnwrap(profile.finish(benchmarkPhase:"completed"))
        XCTAssertEqual(report.elapsedSeconds,5)
        XCTAssertEqual(report.ownCPUSeconds,5)
        XCTAssertEqual(report.measuredPhaseCPUSeconds,2)
        XCTAssertEqual(report.residualCPUSeconds,3)
        XCTAssertEqual(report.phases["collection"]?.calls,1)
        XCTAssertEqual(report.phases["collection"]?.wallSeconds,2)
        XCTAssertNil(profile.begin(.alerts))
        XCTAssertNil(profile.finish(benchmarkPhase:"invalid"))
        XCTAssertTrue(readings.isEmpty)
    }
    @MainActor
    func testUnknownAndRegressedCountersDoNotBecomeZero() throws {
        for endCPU: Double? in [nil,9,.infinity] {
            var readings = [AppPipelineProfile.Reading(wall:0,cpu:10), .init(wall:1,cpu:10), .init(wall:2,cpu:endCPU), .init(wall:3,cpu:12)]
            let profile = AppPipelineProfile(read:{ readings.removeFirst() })
            profile.start(); profile.end(profile.begin(.alerts))
            let report = try XCTUnwrap(profile.finish(benchmarkPhase:"invalid"))
            XCTAssertNil(report.phases["alerts"]?.cpuSeconds)
            XCTAssertEqual(report.phases["alerts"]?.unknownCPUIntervals,1)
            XCTAssertNil(report.measuredPhaseCPUSeconds); XCTAssertNil(report.residualCPUSeconds)
            XCTAssertEqual(report.ownCPUSeconds,2)
        }
    }
    @MainActor
    func testUnfinishedPhaseAndLateFinishStayUnknownAndArtifactFrozen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-pipeline-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let output = directory.appendingPathComponent("profile.json")
        var readings = [AppPipelineProfile.Reading(wall:0,cpu:10), .init(wall:1,cpu:11), .init(wall:2,cpu:12)]
        let profile = AppPipelineProfile(output:output,read:{ readings.removeFirst() })
        profile.start(); let token = profile.begin(.storeSync)
        let report = try XCTUnwrap(profile.finish(benchmarkPhase:"invalid"))
        XCTAssertNil(report.measuredPhaseCPUSeconds); XCTAssertNil(report.residualCPUSeconds)
        let saved = try Data(contentsOf:output)
        profile.end(token); profile.start(); _ = profile.finish(benchmarkPhase:"completed")
        XCTAssertEqual(try Data(contentsOf:output),saved)
        XCTAssertFalse(profile.writeFailed)
        XCTAssertTrue(readings.isEmpty)
    }
    @MainActor
    func testFailedOutputIsVisibleAndNotRetried() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-pipeline-missing-\(UUID())")
        let profile = AppPipelineProfile(output:directory.appendingPathComponent("profile.json"))
        profile.start(); _ = profile.finish(benchmarkPhase:"invalid")
        XCTAssertTrue(profile.writeFailed)
        XCTAssertNil(profile.finish(benchmarkPhase:"completed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
    }
    @MainActor
    func testRegressedWallAndWholeCPUCountersStayUnknown() throws {
        var readings = [AppPipelineProfile.Reading(wall:2,cpu:10), .init(wall:3,cpu:11), .init(wall:1,cpu:12), .init(wall:1,cpu:9)]
        let profile = AppPipelineProfile(read:{ readings.removeFirst() })
        profile.start(); profile.end(profile.begin(.publication))
        let report = try XCTUnwrap(profile.finish(benchmarkPhase:"invalid"))
        XCTAssertNil(report.elapsedSeconds); XCTAssertNil(report.ownCPUSeconds); XCTAssertNil(report.residualCPUSeconds)
        XCTAssertNil(report.phases["publication"]?.wallSeconds)
        XCTAssertEqual(report.phases["publication"]?.unknownWallIntervals,1)
    }

    @MainActor
    func testValidIntervalAfterUnknownDoesNotInflateUnknownCount() throws {
        var readings = [AppPipelineProfile.Reading(wall:0,cpu:10), .init(wall:2,cpu:11), .init(wall:1,cpu:nil), .init(wall:3,cpu:12), .init(wall:4,cpu:13), .init(wall:5,cpu:14)]
        let profile = AppPipelineProfile(read:{ readings.removeFirst() })
        profile.start()
        profile.end(profile.begin(.alerts))
        profile.end(profile.begin(.alerts))
        let report = try XCTUnwrap(profile.finish(benchmarkPhase:"completed"))
        XCTAssertEqual(report.phases["alerts"]?.calls,2)
        XCTAssertEqual(report.phases["alerts"]?.unknownCPUIntervals,1)
        XCTAssertEqual(report.phases["alerts"]?.unknownWallIntervals,1)
        XCTAssertNil(report.phases["alerts"]?.cpuSeconds)
        XCTAssertNil(report.phases["alerts"]?.wallSeconds)
        XCTAssertNil(report.measuredPhaseCPUSeconds); XCTAssertNil(report.residualCPUSeconds)
    }

    @MainActor
    func testOutputParserRejectsPrimaryStatusAndCanonicalAliases() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-profile-output-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:directory)
        let primary = directory.appendingPathComponent("benchmark.json")
        for (index,path) in [primary.path, primary.appendingPathExtension("status.json").path,
                     alias.appendingPathComponent("benchmark.json").path,
                     alias.appendingPathComponent("benchmark.json.status.json").path,
                     directory.appendingPathComponent("BeNcHmArK.JsOn").path,
                     directory.appendingPathComponent("BeNcHmArK.JsOn.StAtUs.JsOn").path,
                     directory.appendingPathComponent("nested/../benchmark.json").path].enumerated() {
            guard case .invalid = AppPipelineProfile.outputChoice(arguments:["--profile-pipeline-output",path],benchmarkOutput:primary) else { return XCTFail("Reserved output case \(index) accepted") }
        }
        let privateTemporary = URL(fileURLWithPath:"/private/tmp/amid-profile-output-\(UUID()).json")
        let temporaryAlias = privateTemporary.path.replacingOccurrences(of:"/private/tmp/",with:"/tmp/")
        guard case .invalid = AppPipelineProfile.outputChoice(arguments:["--profile-pipeline-output",temporaryAlias],benchmarkOutput:privateTemporary) else { return XCTFail("Temporary alias accepted") }
        guard case .configured(let output) = AppPipelineProfile.outputChoice(arguments:["--profile-pipeline-output",directory.appendingPathComponent("profile.json").path],benchmarkOutput:primary) else { return XCTFail("Distinct output rejected") }
        XCTAssertEqual(output.lastPathComponent,"profile.json")
        guard case .disabled = AppPipelineProfile.outputChoice(arguments:[],benchmarkOutput:primary) else { return XCTFail("Absent flag enabled profiling") }
        for arguments in [["--profile-pipeline-output"],["--profile-pipeline-output","relative.json"]] {
            guard case .invalid = AppPipelineProfile.outputChoice(arguments:arguments,benchmarkOutput:primary) else { return XCTFail("Malformed profile output accepted") }
        }
    }

    @MainActor
    func testSupplementalThreadCPUIsNeverAddedTwice() throws {
        var readings = [AppPipelineProfile.Reading(wall:0,cpu:10), .init(wall:1,cpu:11), .init(wall:3,cpu:13), .init(wall:5,cpu:15)]
        let profile = AppPipelineProfile(read:{ readings.removeFirst() })
        profile.recordIngestionThread(.init(wallSeconds:1,cpuSeconds:100))
        profile.start(); let token = profile.begin(.historyIngest)
        profile.recordIngestionThread(.init(wallSeconds:1,cpuSeconds:1.5))
        profile.end(token)
        let report = try XCTUnwrap(profile.finish(benchmarkPhase:"completed"))
        XCTAssertEqual(report.ingestionThread.calls,1)
        XCTAssertEqual(report.ingestionThread.cpuSeconds,1.5)
        XCTAssertEqual(report.measuredPhaseCPUSeconds,2)
        XCTAssertEqual(report.residualCPUSeconds,3)
        profile.recordIngestionThread(.init(wallSeconds:1,cpuSeconds:100))
        XCTAssertNil(profile.finish(benchmarkPhase:"completed"))
    }

}
