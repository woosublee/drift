import Foundation

private struct SafeDailyStopPayload: Decodable {
    let isEnabled: Bool?
    let hour: Int?
    let minute: Int?
    let weekdays: Set<Int>?

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case hour
        case minute
        case weekdays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try? container.decode(Bool.self, forKey: .isEnabled)
        hour = try? container.decode(Int.self, forKey: .hour)
        minute = try? container.decode(Int.self, forKey: .minute)
        weekdays = try? container.decode(Set<Int>.self, forKey: .weekdays)
    }
}

private struct SafeBatteryStopPayload: Decodable {
    let isEnabled: Bool?
    let thresholdPercent: Int?

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case thresholdPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try? container.decode(Bool.self, forKey: .isEnabled)
        thresholdPercent = try? container.decode(Int.self, forKey: .thresholdPercent)
    }
}

private struct SafeGlobalShortcutPayload: Decodable {
    let keyCode: UInt32?
    let modifiers: ShortcutModifiers?

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try? container.decode(UInt32.self, forKey: .keyCode)
        modifiers = try? container.decode(ShortcutModifiers.self, forKey: .modifiers)
    }
}

private enum DecodedShortcut {
    case missing
    case explicitNil
    case value(SafeGlobalShortcutPayload)
    case invalid
}

private struct DriftSettingsPayload: Decodable {
    var schemaVersion: Int?
    var startDelay: StartDelay?
    var repeatInterval: RepeatInterval?
    var motionMode: MotionMode?
    var clickMode: ClickMode?
    var clickPosition: ClickPosition?
    var dailyStop: SafeDailyStopPayload?
    var batteryStop: SafeBatteryStopPayload?
    var launchAtLogin: Bool?
    var toggleShortcut: DecodedShortcut

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case startDelay
        case repeatInterval
        case motionMode
        case clickMode
        case clickPosition
        case dailyStop
        case batteryStop
        case launchAtLogin
        case toggleShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try? container.decode(Int.self, forKey: .schemaVersion)
        startDelay = try? container.decode(StartDelay.self, forKey: .startDelay)
        repeatInterval = try? container.decode(RepeatInterval.self, forKey: .repeatInterval)
        motionMode = try? container.decode(MotionMode.self, forKey: .motionMode)
        clickMode = try? container.decode(ClickMode.self, forKey: .clickMode)
        clickPosition = try? container.decode(ClickPosition.self, forKey: .clickPosition)
        dailyStop = try? container.decode(SafeDailyStopPayload.self, forKey: .dailyStop)
        batteryStop = try? container.decode(SafeBatteryStopPayload.self, forKey: .batteryStop)
        launchAtLogin = try? container.decode(Bool.self, forKey: .launchAtLogin)

        if !container.contains(.toggleShortcut) {
            toggleShortcut = .missing
        } else if (try? container.decodeNil(forKey: .toggleShortcut)) == true {
            toggleShortcut = .explicitNil
        } else if let shortcut = try? container.decode(SafeGlobalShortcutPayload.self, forKey: .toggleShortcut) {
            toggleShortcut = .value(shortcut)
        } else {
            toggleShortcut = .invalid
        }
    }
}

private struct DriftSettingsEncodingPayload: Encodable {
    let settings: DriftSettings

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case startDelay
        case repeatInterval
        case motionMode
        case clickMode
        case clickPosition
        case dailyStop
        case batteryStop
        case launchAtLogin
        case toggleShortcut
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(settings.schemaVersion, forKey: .schemaVersion)
        try container.encode(settings.startDelay, forKey: .startDelay)
        try container.encode(settings.repeatInterval, forKey: .repeatInterval)
        try container.encode(settings.motionMode, forKey: .motionMode)
        try container.encode(settings.clickMode, forKey: .clickMode)
        try container.encodeIfPresent(settings.clickPosition, forKey: .clickPosition)
        try container.encode(settings.dailyStop, forKey: .dailyStop)
        try container.encode(settings.batteryStop, forKey: .batteryStop)
        try container.encode(settings.launchAtLogin, forKey: .launchAtLogin)
        if let toggleShortcut = settings.toggleShortcut {
            try container.encode(toggleShortcut, forKey: .toggleShortcut)
        } else {
            try container.encodeNil(forKey: .toggleShortcut)
        }
    }
}

public extension DriftSettings {
    func encode() throws -> Data {
        try JSONEncoder().encode(DriftSettingsEncodingPayload(settings: self))
    }

    static func decodeSafely(from data: Data) -> DriftSettings {
        guard let payload = try? JSONDecoder().decode(DriftSettingsPayload.self, from: data) else {
            return .default
        }

        let defaults = DriftSettings.default
        var result = defaults
        result.schemaVersion = 1
        result.startDelay = payload.startDelay ?? defaults.startDelay
        result.repeatInterval = payload.repeatInterval ?? defaults.repeatInterval
        result.motionMode = payload.motionMode ?? defaults.motionMode
        result.clickPosition = payload.clickPosition

        if let dailyStop = payload.dailyStop {
            result.dailyStop.isEnabled = dailyStop.isEnabled ?? defaults.dailyStop.isEnabled
            result.dailyStop.hour = min(23, max(0, dailyStop.hour ?? defaults.dailyStop.hour))
            result.dailyStop.minute = min(59, max(0, dailyStop.minute ?? defaults.dailyStop.minute))
            if let weekdays = dailyStop.weekdays {
                if weekdays.isEmpty {
                    result.dailyStop.weekdays = []
                } else {
                    let validWeekdays = Set(weekdays.filter { (1...7).contains($0) })
                    result.dailyStop.weekdays = validWeekdays.isEmpty
                        ? defaults.dailyStop.weekdays
                        : validWeekdays
                }
            }
        }

        if let batteryStop = payload.batteryStop {
            result.batteryStop.isEnabled = batteryStop.isEnabled ?? defaults.batteryStop.isEnabled
            result.batteryStop.thresholdPercent = min(
                50,
                max(5, batteryStop.thresholdPercent ?? defaults.batteryStop.thresholdPercent)
            )
        }

        result.launchAtLogin = payload.launchAtLogin ?? defaults.launchAtLogin
        switch payload.toggleShortcut {
        case .missing, .invalid:
            result.toggleShortcut = defaults.toggleShortcut
        case .explicitNil:
            result.toggleShortcut = nil
        case .value(let shortcut):
            if let defaultShortcut = defaults.toggleShortcut {
                result.toggleShortcut = GlobalShortcut(
                    keyCode: shortcut.keyCode ?? defaultShortcut.keyCode,
                    modifiers: shortcut.modifiers ?? defaultShortcut.modifiers
                )
            } else if let keyCode = shortcut.keyCode, let modifiers = shortcut.modifiers {
                result.toggleShortcut = GlobalShortcut(keyCode: keyCode, modifiers: modifiers)
            } else {
                result.toggleShortcut = nil
            }
        }

        try? result.setClickMode(payload.clickMode ?? .none)
        return result
    }
}
