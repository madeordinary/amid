import XCTest
@testable import AmidCore

final class PrivacyAndAggregationTests: XCTestCase {
    private func process() -> ProcessSample {
        ProcessSample(identity: .init(bootID: "secret-boot", pid: 98765, uid: 555, startSeconds: 1234, startMicroseconds: 5), executable: "/Users/private-person/private-repo/node", name: "secret-process-name", cpuPercent: 250, memoryBytes: 4096, memoryMethod: .footprint, workingDirectory: "/Users/private-person/private-repo", projectPath: "/Users/private-person/private-repo", applicationID: "private-app-id", applicationName: "private-app-name", groupingReason: "private-reason", endpoints: [.init(address: "10.11.12.13", port: 8765, family: "IPv4", scope: "Interface")])
    }
    func testDiagnosticsAllowlistDoesNotLeakProcessOrPathData() throws {
        let snapshot = Snapshot(processes: [process()], availability: .available)
        let text = Diagnostics.preview(snapshot: snapshot, settings: HistorySettings(retention: .off, aliases: ["/private/path": "Chosen alias"]), storageBytes: 123, alerts: [], operatingSystem: "Test OS")
        for secret in ["private-person", "private-repo", "secret-process-name", "private-app-id", "private-app-name", "private-reason", "secret-boot", "10.11.12.13", "98765", "/private/path"] { XCTAssertFalse(text.contains(secret), secret) }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String:Any])
        XCTAssertEqual(object["aliases"] as? [String], ["Chosen alias"])
        XCTAssertEqual(object["observedProcessCount"] as? Int, 1)
    }
    func testDistinctAlternateViewsDeduplicateAndDiscloseMixedMemory() {
        let a = process(); var b = process(); b.identity.pid += 1; b.memoryMethod = .rss
        let snapshot = Snapshot(processes: [a,a,b])
        let apps = ResourceGroup.applications(snapshot), projects = ResourceGroup.projects(snapshot)
        XCTAssertEqual(apps.count,1); XCTAssertEqual(projects.count,1)
        XCTAssertEqual(apps[0].processes.count,2)
        XCTAssertEqual(apps[0].memoryBytes,8192)
        XCTAssertEqual(apps[0].cpuPercent,500)
        XCTAssertEqual(apps[0].memoryMethod,.mixed)
        XCTAssertEqual(apps[0].memoryBytes,projects[0].memoryBytes)
    }
    func testMissingMetricsRemainUnknownAndPartial() {
        var p = process(); p.cpuPercent = nil; p.memoryBytes = nil; p.memoryMethod = .unavailable
        let group = ResourceGroup.applications(Snapshot(processes:[p]))[0]
        XCTAssertNil(group.cpuPercent); XCTAssertNil(group.memoryBytes); XCTAssertTrue(group.partial)
    }
    func testDedupePreservesDistinctUIDAndStartForSamePIDAndExecutable() {
        let original = process()
        var changedUID = original; changedUID.identity.uid += 1
        var changedStart = original; changedStart.identity.startMicroseconds += 1
        let snapshot = Snapshot(processes: [original, original, changedUID, changedStart])
        for groups in [ResourceGroup.applications(snapshot), ResourceGroup.projects(snapshot)] {
            XCTAssertEqual(groups.count, 1)
            XCTAssertEqual(groups[0].processes.map(\.identity), [original.identity, changedUID.identity, changedStart.identity])
            XCTAssertEqual(groups[0].memoryBytes, 3 * original.memoryBytes!)
        }
    }
    func testDefaultOrderingAndUnsortedMembershipMatch() {
        var low = process(); low.applicationID = "low"; low.projectPath = "/fixture/low"; low.memoryBytes = 10
        var high = process(); high.identity.pid += 1; high.applicationID = "high"; high.projectPath = "/fixture/high"; high.memoryBytes = 100
        var unknown = process(); unknown.identity.pid += 2; unknown.applicationID = "unknown"; unknown.projectPath = "/fixture/unknown"; unknown.memoryBytes = nil
        let snapshot = Snapshot(processes: [low, unknown, high, high])
        let views = [(ResourceGroup.applications(snapshot), ResourceGroup.applications(snapshot, sortedByMemory: false)),
                     (ResourceGroup.projects(snapshot), ResourceGroup.projects(snapshot, sortedByMemory: false))]
        for (ordered, unsorted) in views {
            XCTAssertEqual(ordered.map { $0.memoryBytes }, [100, 10, nil])
            let members = { (groups: [ResourceGroup]) in Dictionary(uniqueKeysWithValues: groups.map { ($0.id, Set($0.processes.map(\.identity))) }) }
            XCTAssertEqual(members(ordered), members(unsorted))
            XCTAssertEqual(unsorted.reduce(0) { $0 + $1.processes.count }, 3)
        }
    }
    func testCadenceHonorsBatteryAndEveryElevatedThermalState() {
        XCTAssertEqual(SamplingPolicy.cadence(detailVisible:false,onBattery:false,thermal:"Nominal"),5)
        XCTAssertEqual(SamplingPolicy.cadence(detailVisible:true,onBattery:false,thermal:"Nominal"),2)
        for state in ["Fair","Serious","Critical"] { XCTAssertEqual(SamplingPolicy.cadence(detailVisible:true,onBattery:false,thermal:state),10) }
        XCTAssertEqual(SamplingPolicy.cadence(detailVisible:true,onBattery:true,thermal:"Nominal"),10)
    }
}
