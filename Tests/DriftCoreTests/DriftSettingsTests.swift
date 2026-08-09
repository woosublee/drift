import XCTest
@testable import DriftCore

final class DriftSettingsTests: XCTestCase {
    func testDefaultSettingsMatchProductDecisions() {
        let settings = DriftSettings.default

        XCTAssertEqual(settings.startDelay, .oneMinute)
        XCTAssertEqual(settings.repeatInterval, .tenSeconds)
        XCTAssertEqual(settings.motionMode, .silent)
        XCTAssertEqual(settings.clickMode, .none)
        XCTAssertNil(settings.clickPosition)
        XCTAssertFalse(settings.dailyStop.isEnabled)
        XCTAssertFalse(settings.batteryStop.isEnabled)
        XCTAssertEqual(settings.batteryStop.thresholdPercent, 20)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.toggleShortcut, GlobalShortcut(keyCode: 2, modifiers: [.command, .control]))
    }

    func testSettingsRoundTrip() throws {
        var settings = DriftSettings.default
        settings.motionMode = .natural
        settings.repeatInterval = .thirtySeconds

        let restored = DriftSettings.decodeSafely(from: try settings.encode())

        XCTAssertEqual(restored, settings)
    }

    func testClearedShortcutRoundTripsAsExplicitNil() throws {
        var settings = DriftSettings.default
        settings.toggleShortcut = nil

        let restored = DriftSettings.decodeSafely(from: try settings.encode())

        XCTAssertNil(restored.toggleShortcut)
    }

    func testMissingShortcutKeyKeepsDefaultForLegacyPayload() {
        let json = #"{"schemaVersion":1}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertEqual(restored.toggleShortcut, DriftSettings.default.toggleShortcut)
    }

    func testEmptyWeekdaySelectionRoundTripsWithoutBecomingAllDays() throws {
        var settings = DriftSettings.default
        settings.dailyStop = DailyStopSettings(isEnabled: true, hour: 18, minute: 0, weekdays: [])

        let restored = DriftSettings.decodeSafely(from: try settings.encode())

        XCTAssertTrue(restored.dailyStop.isEnabled)
        XCTAssertEqual(restored.dailyStop.weekdays, [])
    }

    func testCorruptDailyStopFieldFallsBackWithoutDiscardingValidSiblings() {
        let json = #"{"dailyStop":{"isEnabled":true,"hour":"bad","minute":30,"weekdays":[2]}}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertTrue(restored.dailyStop.isEnabled)
        XCTAssertEqual(restored.dailyStop.hour, DailyStopSettings.default.hour)
        XCTAssertEqual(restored.dailyStop.minute, 30)
        XCTAssertEqual(restored.dailyStop.weekdays, [2])
    }

    func testCorruptBatteryStopFieldFallsBackWithoutDiscardingValidSibling() {
        let json = #"{"batteryStop":{"isEnabled":true,"thresholdPercent":"bad"}}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertTrue(restored.batteryStop.isEnabled)
        XCTAssertEqual(restored.batteryStop.thresholdPercent, BatteryStopSettings.default.thresholdPercent)
    }

    func testCorruptShortcutFieldFallsBackWithoutDiscardingValidSibling() {
        let json = #"{"toggleShortcut":{"keyCode":42,"modifiers":"bad"}}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertEqual(restored.toggleShortcut?.keyCode, 42)
        XCTAssertEqual(restored.toggleShortcut?.modifiers, DriftSettings.default.toggleShortcut?.modifiers)
    }

    func testUnknownEnumFallsBackWithoutDiscardingOtherFields() {
        let json = #"{"schemaVersion":1,"startDelay":"threeMinutes","repeatInterval":"tenSeconds","motionMode":"futureMode","launchAtLogin":true}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertEqual(restored.startDelay, .threeMinutes)
        XCTAssertEqual(restored.motionMode, .silent)
        XCTAssertTrue(restored.launchAtLogin)
    }

    func testClickModeRequiresPosition() {
        var settings = DriftSettings.default

        XCTAssertThrowsError(try settings.setClickMode(.left))
        settings.clickPosition = ClickPosition(x: 400, y: 300)
        XCTAssertNoThrow(try settings.setClickMode(.left))
        XCTAssertEqual(settings.clickMode, .left)
    }

    func testUnsafePersistedLimitsAreClamped() {
        let json = #"{"dailyStop":{"isEnabled":true,"hour":28,"minute":-1,"weekdays":[0,8]},"batteryStop":{"isEnabled":true,"thresholdPercent":99}}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertEqual(restored.dailyStop.hour, 23)
        XCTAssertEqual(restored.dailyStop.minute, 0)
        XCTAssertEqual(restored.dailyStop.weekdays, Set(1...7))
        XCTAssertEqual(restored.batteryStop.thresholdPercent, 50)
    }
}
