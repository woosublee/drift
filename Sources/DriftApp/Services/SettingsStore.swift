import Foundation
import DriftCore

public protocol SettingsStoring: AnyObject {
    func loadSettings() -> DriftSettings
    func saveSettings(_ settings: DriftSettings) throws
}

public protocol RuntimeStateStoring: AnyObject {
    func loadActiveIntent() -> Bool?
    func saveActiveIntent(_ activeIntent: Bool)
    func loadNextAlternatingButton() -> MouseButton
    func saveNextAlternatingButton(_ button: MouseButton)
    func loadLastDailyStopTrigger() -> DailyStopTrigger?
    func saveLastDailyStopTrigger(_ trigger: DailyStopTrigger)
}

public extension RuntimeStateStoring {
    func loadLastDailyStopTrigger() -> DailyStopTrigger? { nil }
    func saveLastDailyStopTrigger(_ trigger: DailyStopTrigger) {}
}

public final class UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    private let key = "settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSettings() -> DriftSettings {
        guard let data = defaults.data(forKey: key) else { return .default }
        return DriftSettings.decodeSafely(from: data)
    }

    public func saveSettings(_ settings: DriftSettings) throws {
        defaults.set(try settings.encode(), forKey: key)
    }
}

public final class UserDefaultsRuntimeStateStore: RuntimeStateStoring {
    private let defaults: UserDefaults
    private let activeKey = "runtime.active"
    private let hasLaunchedKey = "runtime.hasLaunched"
    private let nextAlternatingButtonKey = "runtime.nextAlternatingButton"
    private let lastDailyStopTriggerKey = "runtime.lastDailyStopTrigger"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadActiveIntent() -> Bool? {
        guard defaults.bool(forKey: hasLaunchedKey) else { return nil }
        return defaults.bool(forKey: activeKey)
    }

    public func saveActiveIntent(_ activeIntent: Bool) {
        defaults.set(true, forKey: hasLaunchedKey)
        defaults.set(activeIntent, forKey: activeKey)
    }

    public func loadNextAlternatingButton() -> MouseButton {
        guard let rawValue = defaults.string(forKey: nextAlternatingButtonKey),
              let button = MouseButton(rawValue: rawValue) else {
            return .left
        }
        return button
    }

    public func saveNextAlternatingButton(_ button: MouseButton) {
        defaults.set(button.rawValue, forKey: nextAlternatingButtonKey)
    }

    public func loadLastDailyStopTrigger() -> DailyStopTrigger? {
        guard let data = defaults.data(forKey: lastDailyStopTriggerKey) else { return nil }
        return try? JSONDecoder().decode(DailyStopTrigger.self, from: data)
    }

    public func saveLastDailyStopTrigger(_ trigger: DailyStopTrigger) {
        guard let data = try? JSONEncoder().encode(trigger) else { return }
        defaults.set(data, forKey: lastDailyStopTriggerKey)
    }
}
