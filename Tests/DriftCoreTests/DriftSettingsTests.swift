import XCTest
@testable import DriftCore

final class DriftSettingsTests: XCTestCase {
    func testDefaultSettingsMatchProductDecisions() {
        let settings = DriftSettings.default

        XCTAssertEqual(settings.schemaVersion, 2)
        XCTAssertEqual(settings.startDelay, .oneMinute)
        XCTAssertEqual(settings.repeatInterval, .tenSeconds)
        XCTAssertTrue(settings.isSilentModeEnabled)
        XCTAssertFalse(settings.isSmartMotionEnabled)
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
        settings.isSilentModeEnabled = false
        settings.isSmartMotionEnabled = true
        settings.repeatInterval = .thirtySeconds

        let encoded = try settings.encode()
        let restored = DriftSettings.decodeSafely(from: encoded)

        XCTAssertEqual(restored, settings)
        XCTAssertFalse(try XCTUnwrap(String(data: encoded, encoding: .utf8)).contains("motionMode"))
    }

    func testV1MotionModesMigrateToIndependentSettings() {
        let cases: [(String, Bool, Bool)] = [
            ("silent", true, false),
            ("standard", false, false),
            ("natural", false, true)
        ]

        for (legacyMode, expectedSilent, expectedSmart) in cases {
            let json = #"{"schemaVersion":1,"motionMode":"\#(legacyMode)"}"#.data(using: .utf8)!
            let restored = DriftSettings.decodeSafely(from: json)

            XCTAssertEqual(restored.schemaVersion, 2)
            XCTAssertEqual(restored.isSilentModeEnabled, expectedSilent)
            XCTAssertEqual(restored.isSmartMotionEnabled, expectedSmart)
        }
    }

    func testV2MotionSettingsTakePrecedenceOverLegacyMode() {
        let json = #"{"schemaVersion":2,"isSilentModeEnabled":true,"isSmartMotionEnabled":true,"motionMode":"standard"}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertTrue(restored.isSilentModeEnabled)
        XCTAssertTrue(restored.isSmartMotionEnabled)
    }

    func testMissingV2MotionSiblingFallsBackToItsDefault() {
        let json = #"{"schemaVersion":2,"isSmartMotionEnabled":true}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertTrue(restored.isSilentModeEnabled)
        XCTAssertTrue(restored.isSmartMotionEnabled)
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

    func testUnknownLegacyMotionModeFallsBackWithoutDiscardingOtherFields() {
        let json = #"{"schemaVersion":1,"startDelay":"threeMinutes","repeatInterval":"tenSeconds","motionMode":"futureMode","launchAtLogin":true}"#.data(using: .utf8)!

        let restored = DriftSettings.decodeSafely(from: json)

        XCTAssertEqual(restored.startDelay, .threeMinutes)
        XCTAssertTrue(restored.isSilentModeEnabled)
        XCTAssertFalse(restored.isSmartMotionEnabled)
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
