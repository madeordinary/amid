import XCTest
import IOKit.ps
@testable import AmidCore

final class BatteryCollectionTests: XCTestCase {
    func testMissingUnsupportedAndMalformedPowerStateRemainUnknown() {
        let states: [Any?] = [nil, "Off Line", "Future source", 1]
        for state in states {
            var description: [String: Any] = [kIOPSCurrentCapacityKey: NSNumber(value: 75), kIOPSMaxCapacityKey: NSNumber(value: 100)]
            description[kIOPSPowerSourceStateKey] = state
            let battery = Sampler.internalBatterySnapshot(description)
            XCTAssertNil(battery.onBattery, "Unsupported state must not become external power: \(String(describing: state))")
            XCTAssertNil(battery.isCharging)
            XCTAssertEqual(battery.percent, 75)
        }
    }
    func testMalformedChargingValueDoesNotBecomeAChargingFact() {
        let values: [Any] = ["true", NSNumber(value: 1), NSNumber(value: 0), NSNumber(value: 2)]
        for value in values {
            let battery = Sampler.internalBatterySnapshot([kIOPSIsChargingKey: value])
            XCTAssertNil(battery.isCharging, "Only an actual Boolean establishes charging state: \(value)")
        }
    }
    func testKnownBatteryAndExternalStatesPreserveOtherMeasurements() {
        for (state, onBattery) in [(kIOPSBatteryPowerValue, true), (kIOPSACPowerValue, false)] {
            for charging in [false, true] {
                let battery = Sampler.internalBatterySnapshot([
                    kIOPSPowerSourceStateKey: state, kIOPSIsChargingKey: charging,
                    kIOPSCurrentCapacityKey: NSNumber(value: 60), kIOPSMaxCapacityKey: NSNumber(value: 80),
                    kIOPSBatteryHealthConditionKey: "Fixture health"
                ])
                XCTAssertEqual(battery.onBattery, onBattery)
                XCTAssertEqual(battery.isCharging, charging)
                XCTAssertEqual(battery.percent, 75)
                XCTAssertEqual(battery.condition, "Fixture health")
            }
        }
    }
    func testRawSnapshotDecodesLegacyBooleansAndPreservesUnknownFields() throws {
        let decoder = JSONDecoder()
        let legacy = try decoder.decode(BatterySnapshot.self, from: Data(#"{"percent":75,"isCharging":false,"onBattery":true,"condition":"Fixture"}"#.utf8))
        XCTAssertEqual(legacy.isCharging, false); XCTAssertEqual(legacy.onBattery, true)
        let absent = try decoder.decode(BatterySnapshot.self, from: Data(#"{"percent":75,"condition":"Fixture"}"#.utf8))
        XCTAssertNil(absent.isCharging); XCTAssertNil(absent.onBattery); XCTAssertEqual(absent.percent, 75)
        let roundTrip = try decoder.decode(BatterySnapshot.self, from: JSONEncoder().encode(absent))
        XCTAssertNil(roundTrip.isCharging); XCTAssertNil(roundTrip.onBattery); XCTAssertEqual(roundTrip.condition, "Fixture")
    }
}
