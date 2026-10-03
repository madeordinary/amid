import XCTest
import AmidCore
@testable import AmidApp

final class VerificationHistorySeedRequestTests: XCTestCase {
    private let source = "/private/tmp/amid-owned-retained-profile-test"
    private let manifestHash = String(repeating: "a", count: 64)
    func testExplicitModeAndCompletePairRequired() {
        XCTAssertEqual(VerificationHistorySeedRequest.parse(arguments: ["app"]), .disabled)
        let pair = ["--verification-history-seed", source, "--verification-history-sha256", manifestHash]
        XCTAssertEqual(VerificationHistorySeedRequest.parse(arguments: ["app"] + pair), .invalid)
        for mode in ["--verification", "--performance-verification"] {
            XCTAssertEqual(VerificationHistorySeedRequest.parse(arguments: [mode] + pair), .configured(source: URL(fileURLWithPath: source), manifestSHA256: manifestHash))
        }
        for args in [["--verification", "--verification-history-seed", source],
                     ["--verification", "--verification-history-sha256", manifestHash],
                     ["--verification"] + pair + ["--verification-history-seed", source],
                     ["--verification", "--verification-history-seed", "/tmp/other", "--verification-history-sha256", manifestHash],
                     ["--verification", "--verification-history-seed", source, "--verification-history-sha256", "wrong"]] {
            XCTAssertEqual(VerificationHistorySeedRequest.parse(arguments: args), .invalid)
        }
    }
    @MainActor
    func testMalformedAndUnavailableRequestsStopStartupAndRefresh() async {
        let source = "/private/tmp/amid-owned-retained-profile-missing-\(UUID().uuidString)"
        for args in [["app", "--verification-history-seed", source],
                     ["app", "--verification", "--verification-history-seed", source, "--verification-history-sha256", manifestHash]] {
            let model = AppModel(arguments: args)
            await model.start()
            XCTAssertNotNil(model.error)
            XCTAssertFalse(model.showOnboarding)
            model.settings.retention = .off
            await model.refresh()
            XCTAssertEqual(model.snapshot.availability, Snapshot.empty.availability)
            XCTAssertTrue(model.aggregates.isEmpty)
        }
    }
    @MainActor
    func testExplicitRepeatedGroupNavigationPublishesIntent() {
        let model = AppModel()
        model.openGroup("app:test", projects: false)
        XCTAssertEqual(model.destination, .applications)
        XCTAssertEqual(model.selectedGroupID, "app:test")
        XCTAssertEqual(model.groupNavigationRevision, 1)
        model.openGroup("app:test", projects: false)
        XCTAssertEqual(model.groupNavigationRevision, 2)
        model.openGroup("project:test", projects: true)
        XCTAssertEqual(model.destination, .projects)
        XCTAssertEqual(model.selectedGroupID, "project:test")
    }
}
