import XCTest
import DriftCore
@testable import DriftApp

final class SettingsStoreTests: XCTestCase {
    func testMissingSettingsReturnsDefaults() {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        XCTAssertEqual(UserDefaultsSettingsStore(defaults: defaults).loadSettings(), .default)
    }

    func testSettingsV2RoundTrips() throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        var settings = DriftSettings.default
        settings.isSilentModeEnabled = false
        settings.isSmartMotionEnabled = true
        let store = UserDefaultsSettingsStore(defaults: defaults)

        try store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings(), settings)
    }

    func testMalformedLegacyMotionModeUsesNewDefaults() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        defaults.set(#"{"motionMode":"future"}"#.data(using: .utf8), forKey: "settings.v1")

        let settings = UserDefaultsSettingsStore(defaults: defaults).loadSettings()
        XCTAssertTrue(settings.isSilentModeEnabled)
        XCTAssertFalse(settings.isSmartMotionEnabled)
    }

    func testMissingRuntimeLaunchMarkerReturnsNilIntent() {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        XCTAssertNil(UserDefaultsRuntimeStateStore(defaults: defaults).loadActiveIntent())
    }

    func testLastDailyStopTriggerPersistsAcrossRuntimeStoreInstances() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let trigger = DailyStopTrigger(year: 2026, month: 8, day: 8)

        UserDefaultsRuntimeStateStore(defaults: defaults).saveLastDailyStopTrigger(trigger)

        XCTAssertEqual(
            UserDefaultsRuntimeStateStore(defaults: defaults).loadLastDailyStopTrigger(),
            trigger
        )
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "DriftTests.\(UUID().uuidString)")!
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first(where: { $0.hasPrefix("DriftTests.") }) ?? "")
    }
}
