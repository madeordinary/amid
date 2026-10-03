import XCTest
@testable import AmidCore
@testable import AmidApp

final class ActionPresentationTests: XCTestCase {
    func testMissingObservationIsNotDisplayedAsZeroRemaining() {
        for signals in [0, 1] {
            let result = StopResult(targetID: "fixture", validation: .stale, message: "Observation unavailable.", signalsSent: signals)
            let detail = stopResultDetail(result)
            XCTAssertTrue(detail.contains("Remaining process and endpoint state is unavailable."))
            XCTAssertFalse(detail.contains("identities: 0"))
            XCTAssertFalse(detail.contains("endpoints: 0"))
        }
    }
    func testObservedEmptyResultCanDisplayZeroCounts() {
        let result = StopResult(targetID: "fixture", validation: .unchanged, message: "Exited.", signalsSent: 1, remainingObservationAvailable: true)
        let detail = stopResultDetail(result)
        XCTAssertTrue(detail.contains("identities: 0; endpoints: 0"))
        XCTAssertFalse(detail.contains("state is unavailable"))
    }
}
