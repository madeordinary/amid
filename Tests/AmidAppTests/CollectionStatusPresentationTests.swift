import XCTest
@testable import AmidApp
import AmidCore

final class CollectionStatusPresentationTests: XCTestCase {
    func testEmptyUnknownPartialAndPresentationClear() {
        XCTAssertNotEqual(collectionStatusMessage(nil, empty: true, volumes: false), collectionStatusMessage(.complete, empty: true, volumes: false))
        XCTAssertNotNil(collectionStatusMessage(.partial, empty: false, volumes: true))
        XCTAssertNil(collectionStatusMessage(.complete, empty: false, volumes: true))
        var snapshot = Snapshot(); snapshot.system.volumeCollectionStatus = .partial; snapshot.system.interfaceCollectionStatus = .unavailable
        var display = OverviewPresentation(snapshot: snapshot, applications: [], projects: [])
        XCTAssertEqual(display.system.volumeCollectionStatus, .partial)
        XCTAssertEqual(display.system.interfaceCollectionStatus, .unavailable)
        display = OverviewPresentation()
        XCTAssertNil(display.system.volumeCollectionStatus); XCTAssertNil(display.system.interfaceCollectionStatus)
    }
}
