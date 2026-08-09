import XCTest
import DriftCore
@testable import DriftApp

final class PowerSourceServiceTests: XCTestCase {
    func testInternalBatteryUsesRoundedCapacityAndChargingFlag() {
        let snapshot = PowerSourceService.snapshot(from: [[
            "Type": "InternalBattery",
            "Transport Type": "Internal",
            "Current Capacity": 49,
            "Max Capacity": 100,
            "Power Source State": "Battery Power",
            "Is Charging": false
        ]])

        XCTAssertEqual(snapshot, PowerSnapshot(source: .battery, percent: 49, isCharging: false))
    }

    func testTransportTypeInternalAlsoIdentifiesInternalBattery() {
        let snapshot = PowerSourceService.snapshot(from: [[
            "Transport Type": "Internal",
            "Current Capacity": 75,
            "Max Capacity": 100,
            "Power Source State": "Battery Power",
            "Is Charging": false
        ]])

        XCTAssertEqual(snapshot, PowerSnapshot(source: .battery, percent: 75, isCharging: false))
    }

    func testExternalPowerIsNotTreatedAsBattery() {
        let snapshot = PowerSourceService.snapshot(from: [[
            "Type": "InternalBattery",
            "Transport Type": "Internal",
            "Current Capacity": 20,
            "Max Capacity": 100,
            "Power Source State": "AC Power",
            "Is Charging": true
        ]])

        XCTAssertEqual(snapshot, PowerSnapshot(source: .external, percent: 20, isCharging: true))
    }

    func testMissingInternalBatteryIsUnavailable() {
        XCTAssertEqual(PowerSourceService.snapshot(from: [["Transport Type": "UPS"]]), PowerSnapshot(source: .unavailable, percent: nil, isCharging: false))
    }
}
