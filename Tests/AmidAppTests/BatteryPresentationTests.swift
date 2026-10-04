import XCTest
import AmidCore
@testable import AmidApp

final class BatteryPresentationTests: XCTestCase {
    func testUnknownPowerDoesNotImplyExternalPowerOrDiscardKnownCharging() {
        let chargingStates: [Bool?] = [nil, false]
        for charging in chargingStates {
            XCTAssertEqual(batteryPowerDescription(BatterySnapshot(percent: 75, isCharging: charging, onBattery: nil, condition: "Fixture")), "Power source unavailable")
        }
        XCTAssertEqual(batteryPowerDescription(BatterySnapshot(percent: 75, isCharging: true, onBattery: nil, condition: "Fixture")), "Charging")
        XCTAssertEqual(batteryPowerDescription(BatterySnapshot(percent: nil, isCharging: nil, onBattery: true, condition: "Fixture")), "On battery")
        XCTAssertEqual(batteryPowerDescription(BatterySnapshot(percent: nil, isCharging: nil, onBattery: false, condition: "Fixture")), "External power")
    }
    @MainActor
    func testPowerObservationKeepsExistingSamplingPolicy() {
        let model = AppModel()
        model.snapshot.system.thermalState = "Nominal"
        let cases: [(Bool?, Double)] = [(true, 10), (false, 5), (nil, 5)]
        for (onBattery, backgroundCadence) in cases {
            model.fullWindowVisible = false
            model.snapshot.system.battery = BatterySnapshot(percent: 75, isCharging: nil, onBattery: onBattery, condition: "Fixture")
            XCTAssertEqual(model.cadence, backgroundCadence)
            model.fullWindowVisible = true; model.destination = .applications
            XCTAssertEqual(model.cadence, onBattery == true ? 10 : 2)
        }
        model.snapshot.system.thermalState = "Serious"
        XCTAssertEqual(model.cadence, 10)
    }
}
