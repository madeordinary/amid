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
    func testChildProcessStateIsReportedWithoutClaimingZero() {
        let child = ProcessIdentity(bootID: "boot", pid: 304, uid: 501, startSeconds: 4, startMicroseconds: 2)
        var running = StopResult(targetID: "server", validation: .unchanged, message: "Server exited.", signalsSent: 1, remainingObservationAvailable: true)
        running.remainingDescendants = [child]
        XCTAssertTrue(stopResultDetail(running).contains("Child processes still running, not signalled: 1."))
        var unknown = running; unknown.remainingDescendants = []; unknown.descendantsUnknown = true
        XCTAssertTrue(stopResultDetail(unknown).contains("Child process state is unavailable."))
        var mixed = running; mixed.descendantsUnknown = true
        let mixedDetail = stopResultDetail(mixed)
        XCTAssertTrue(mixedDetail.contains("Child processes still running, not signalled: 1.") && mixedDetail.contains("Child process state is unavailable."))
        let none = StopResult(targetID: "server", validation: .unchanged, message: "Server exited.", signalsSent: 1, remainingObservationAvailable: true)
        XCTAssertFalse(stopResultDetail(none).contains("Child process"))
    }
    func testObservedEmptyResultCanDisplayZeroCounts() {
        let result = StopResult(targetID: "fixture", validation: .unchanged, message: "Exited.", signalsSent: 1, remainingObservationAvailable: true)
        let detail = stopResultDetail(result)
        XCTAssertTrue(detail.contains("identities: 0; endpoints: 0"))
        XCTAssertFalse(detail.contains("state is unavailable"))
    }
}
