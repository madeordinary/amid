import XCTest
import Foundation
import CAmid
@testable import AmidCore

final class CollectionStatusTests: XCTestCase, @unchecked Sendable {
    func testInterfaceFailureEmptyOverflowAndRecoveryResetDeltas() async {
        let sampler = Sampler()
        func rows(_ value: UInt64) -> @Sendable (inout [AmidInterface]) -> Int32 {
            { output in
                var row = AmidInterface()
                withUnsafeMutableBytes(of: &row.name) { bytes in
                    for (index, byte) in Array("en-fixture".utf8).enumerated() { bytes[index] = byte }
                    bytes[10] = 0
                }
                row.received = value; row.sent = value; output[0] = row; return 1
            }
        }
        let first = await sampler.collectInterfaces(time: 1, read: rows(10))
        XCTAssertEqual(first.1, .complete); XCTAssertEqual(first.0.first?.id, "en-fixture"); XCTAssertNil(first.0.first?.receivedBytesPerSecond); XCTAssertNil(first.0.first?.sentBytesPerSecond)
        let second = await sampler.collectInterfaces(time: 2, read: rows(20))
        XCTAssertEqual(second.0.first?.receivedBytesPerSecond, 10); XCTAssertEqual(second.0.first?.sentBytesPerSecond, 10)
        let denied = await sampler.collectInterfaces(time: 3) { _ in -1 }
        XCTAssertEqual(denied.1, .unavailable); XCTAssertTrue(denied.0.isEmpty)
        let recovered = await sampler.collectInterfaces(time: 4, read: rows(30))
        XCTAssertNil(recovered.0.first?.receivedBytesPerSecond); XCTAssertNil(recovered.0.first?.sentBytesPerSecond)
        let oversized = await sampler.collectInterfaces(time: 5) { _ in 257 }
        XCTAssertEqual(oversized.1, .unavailable); XCTAssertTrue(oversized.0.isEmpty)
        let afterOverflow = await sampler.collectInterfaces(time: 6, read: rows(40))
        XCTAssertEqual(afterOverflow.1, .complete)
        XCTAssertNil(afterOverflow.0.first?.receivedBytesPerSecond); XCTAssertNil(afterOverflow.0.first?.sentBytesPerSecond)
        let deltaBeforeEmpty = await sampler.collectInterfaces(time: 7, read: rows(50))
        XCTAssertEqual(deltaBeforeEmpty.0.first?.receivedBytesPerSecond, 10); XCTAssertEqual(deltaBeforeEmpty.0.first?.sentBytesPerSecond, 10)
        let empty = await sampler.collectInterfaces(time: 8) { _ in 0 }
        XCTAssertEqual(empty.1, .complete); XCTAssertTrue(empty.0.isEmpty)
        let fresh = await sampler.collectInterfaces(time: 9, read: rows(60))
        XCTAssertNil(fresh.0.first?.receivedBytesPerSecond); XCTAssertNil(fresh.0.first?.sentBytesPerSecond)
    }
    func testVolumeEnumerationFailureEmptyAndPartialPreserveGoodRows() {
        XCTAssertEqual(Sampler.volumeCollection(urls: nil) { _ in .notLocal }.1, .unavailable)
        XCTAssertEqual(Sampler.volumeCollection(urls: []) { _ in .unavailable }.1, .complete)
        let a = URL(fileURLWithPath: "/fixture-a"), b = URL(fileURLWithPath: "/fixture-b")
        let row = VolumeSnapshot(id: "fixture", name: "Fixture", capacity: 20, available: 10, isStartup: false, definition: "Fixture")
        let mixed = Sampler.volumeCollection(urls: [a,b]) { $0 == a ? .volume(row) : .unavailable }
        var missing = row; missing.available = nil
        let incomplete = Sampler.volumeCollection(urls: [a]) { _ in .volume(missing) }
        XCTAssertEqual(incomplete.1, .partial); XCTAssertEqual(incomplete.0.count, 1); XCTAssertNil(incomplete.0[0].available)
        XCTAssertEqual(mixed.1, .partial); XCTAssertEqual(mixed.0.count, 1); XCTAssertEqual(mixed.0[0].available, 10)
        XCTAssertEqual(Sampler.volumeCollection(urls: [a]) { _ in .unavailable }.1, .unavailable)
        XCTAssertEqual(Sampler.volumeCollection(urls: [a]) { _ in .notLocal }.1, .complete)
    }
    func testLegacyOptionalFieldsAndStatusRoundTrip() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var snapshot = SystemSnapshot(); snapshot.volumeCollectionStatus = .partial; snapshot.interfaceCollectionStatus = .complete
        let encoded = try encoder.encode(snapshot)
        let copy = try decoder.decode(SystemSnapshot.self, from: encoded)
        XCTAssertEqual(copy.volumeCollectionStatus, .partial); XCTAssertEqual(copy.interfaceCollectionStatus, .complete)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String:Any])
        object.removeValue(forKey: "volumeCollectionStatus"); object.removeValue(forKey: "interfaceCollectionStatus")
        let old = try decoder.decode(SystemSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.volumeCollectionStatus); XCTAssertNil(old.interfaceCollectionStatus)
    }
}
