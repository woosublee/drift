import XCTest
@testable import DriftCore

final class BatteryStopPolicyTests: XCTestCase {
    private let enabled = BatteryStopSettings(isEnabled: true, thresholdPercent: 20)

    func testDisabledBatteryStopNeverTriggers() {
        XCTAssertFalse(BatteryStopPolicy().shouldDeactivate(
            snapshot: PowerSnapshot(source: .battery, percent: 5, isCharging: false),
            settings: .default
        ))
    }

    func testDesktopWithoutBatteryNeverTriggers() {
        XCTAssertFalse(BatteryStopPolicy().shouldDeactivate(
            snapshot: PowerSnapshot(source: .unavailable, percent: nil, isCharging: false),
            settings: enabled
        ))
    }

    func testExternalPowerNeverTriggers() {
        XCTAssertFalse(BatteryStopPolicy().shouldDeactivate(
            snapshot: PowerSnapshot(source: .external, percent: 10, isCharging: false),
            settings: enabled
        ))
    }

    func testChargingBatteryNeverTriggers() {
        XCTAssertFalse(BatteryStopPolicy().shouldDeactivate(
            snapshot: PowerSnapshot(source: .battery, percent: 10, isCharging: true),
            settings: enabled
        ))
    }

    func testBatteryAboveThresholdNeverTriggers() {
        XCTAssertFalse(BatteryStopPolicy().shouldDeactivate(
            snapshot: PowerSnapshot(source: .battery, percent: 21, isCharging: false),
            settings: enabled
        ))
    }

    func testBatteryAtThresholdTriggers() {
        XCTAssertTrue(BatteryStopPolicy().shouldDeactivate(
            snapshot: PowerSnapshot(source: .battery, percent: 20, isCharging: false),
            settings: enabled
        ))
    }

    func testBatteryBelowThresholdTriggers() {
        XCTAssertTrue(BatteryStopPolicy().shouldDeactivate(
            snapshot: PowerSnapshot(source: .battery, percent: 19, isCharging: false),
            settings: enabled
        ))
    }
}
