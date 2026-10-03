import XCTest
@testable import AmidApp

final class HiddenOverviewProfileTests: XCTestCase {
    func testFlagRequiresPerformanceVerification() {
        XCTAssertEqual(GUIBenchmarkEvidence.presentationMode(arguments: []), .normal)
        XCTAssertEqual(GUIBenchmarkEvidence.presentationMode(arguments: ["--profile-suppress-hidden-overview"]), .normal)
        XCTAssertEqual(GUIBenchmarkEvidence.presentationMode(arguments: ["--verification", "--profile-suppress-hidden-overview"]), .normal)
        XCTAssertEqual(GUIBenchmarkEvidence.presentationMode(arguments: ["--performance-verification"]), .normal)
        XCTAssertEqual(GUIBenchmarkEvidence.presentationMode(arguments: ["--performance-verification", "--profile-suppress-hidden-overview"]), .hiddenOverviewSuppressed)
    }
    func testVisibilityAndDestinationRestorePresentation() {
        let mode = GUIBenchmarkEvidence.PresentationMode.hiddenOverviewSuppressed
        XCTAssertTrue(mode.suppressesOverview(windowVisible: false, isOverview: true))
        XCTAssertFalse(mode.suppressesOverview(windowVisible: true, isOverview: true))
        XCTAssertFalse(mode.suppressesOverview(windowVisible: false, isOverview: false))
        XCTAssertTrue(mode.suppressesOverview(windowVisible: false, isOverview: true))
        XCTAssertFalse(GUIBenchmarkEvidence.PresentationMode.normal.suppressesOverview(windowVisible: false, isOverview: true))
    }
    @MainActor
    func testDefaultAndDiagnosticStatusReportPresentationMode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-presentation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for mode in [GUIBenchmarkEvidence.PresentationMode.normal, .hiddenOverviewSuppressed] {
            let output = directory.appendingPathComponent(mode.rawValue + ".json")
            let session = GUIBenchmarkSession(seconds: 30, output: output, retention: "off", presentationMode: mode)
            XCTAssertEqual(session.evidence.presentationMode, mode)
            let data = try Data(contentsOf: output.appendingPathExtension("status.json"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["presentationMode"] as? String, mode.rawValue)
            session.invalidate("test interruption")
            session.finish(active: false)
            let final = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
            let monitoring = try XCTUnwrap(final["monitoring"] as? [String: Any])
            XCTAssertEqual(monitoring["presentationMode"] as? String, mode.rawValue)
        }
        XCTAssertEqual(GUIBenchmarkEvidence(requestedSeconds: 30).presentationMode, .normal)
    }
}
