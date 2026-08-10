import Foundation

public enum ClickMode: String, Codable, CaseIterable, Sendable {
    case none
    case left
    case right
    case alternating
}

public enum StartDelay: String, Codable, CaseIterable, Sendable {
    case oneMinute
    case threeMinutes
    case fiveMinutes
    case tenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .threeMinutes: 180
        case .fiveMinutes: 300
        case .tenMinutes: 600
        }
    }
}

public enum RepeatInterval: String, Codable, CaseIterable, Sendable {
    case continuous
    case fiveSeconds
    case tenSeconds
    case thirtySeconds
    case oneMinute
    case ninetySeconds
    case twoMinutes
    case threeMinutes
    case fiveMinutes
    case tenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .continuous: 0.1
        case .fiveSeconds: 5
        case .tenSeconds: 10
        case .thirtySeconds: 30
        case .oneMinute: 60
        case .ninetySeconds: 90
        case .twoMinutes: 120
        case .threeMinutes: 180
        case .fiveMinutes: 300
        case .tenMinutes: 600
        }
    }
}

public struct ClickPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct DailyStopSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var hour: Int
    public var minute: Int
    public var weekdays: Set<Int>

    public init(isEnabled: Bool, hour: Int, minute: Int, weekdays: Set<Int>) {
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
    }

    public static let `default` = DailyStopSettings(
        isEnabled: false,
        hour: 18,
        minute: 0,
        weekdays: Set(1...7)
    )
}

public struct BatteryStopSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var thresholdPercent: Int

    public init(isEnabled: Bool, thresholdPercent: Int) {
        self.isEnabled = isEnabled
        self.thresholdPercent = thresholdPercent
    }

    public static let `default` = BatteryStopSettings(isEnabled: false, thresholdPercent: 20)
}

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let control = ShortcutModifiers(rawValue: 1 << 1)
    public static let option = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)
}

public struct GlobalShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: ShortcutModifiers

    public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum DriftSettingsError: Error, Equatable {
    case clickPositionRequired
}

public struct DriftSettings: Equatable, Sendable {
    public var schemaVersion: Int
    public var startDelay: StartDelay
    public var repeatInterval: RepeatInterval
    public var isSilentModeEnabled: Bool
    public var isSmartMotionEnabled: Bool
    public private(set) var clickMode: ClickMode
    public var clickPosition: ClickPosition?
    public var dailyStop: DailyStopSettings
    public var batteryStop: BatteryStopSettings
    public var launchAtLogin: Bool
    public var toggleShortcut: GlobalShortcut?

    public init(
        schemaVersion: Int,
        startDelay: StartDelay,
        repeatInterval: RepeatInterval,
        isSilentModeEnabled: Bool,
        isSmartMotionEnabled: Bool,
        clickMode: ClickMode,
        clickPosition: ClickPosition?,
        dailyStop: DailyStopSettings,
        batteryStop: BatteryStopSettings,
        launchAtLogin: Bool,
        toggleShortcut: GlobalShortcut?
    ) {
        self.schemaVersion = schemaVersion
        self.startDelay = startDelay
        self.repeatInterval = repeatInterval
        self.isSilentModeEnabled = isSilentModeEnabled
        self.isSmartMotionEnabled = isSmartMotionEnabled
        self.clickMode = clickMode
        self.clickPosition = clickPosition
        self.dailyStop = dailyStop
        self.batteryStop = batteryStop
        self.launchAtLogin = launchAtLogin
        self.toggleShortcut = toggleShortcut
    }

    public static let `default` = DriftSettings(
        schemaVersion: 2,
        startDelay: .oneMinute,
        repeatInterval: .tenSeconds,
        isSilentModeEnabled: true,
        isSmartMotionEnabled: false,
        clickMode: .none,
        clickPosition: nil,
        dailyStop: .default,
        batteryStop: .default,
        launchAtLogin: false,
        toggleShortcut: GlobalShortcut(keyCode: 2, modifiers: [.command, .control])
    )

    public mutating func setClickMode(_ mode: ClickMode) throws {
        if mode != .none, clickPosition == nil {
            throw DriftSettingsError.clickPositionRequired
        }
        clickMode = mode
    }
}
