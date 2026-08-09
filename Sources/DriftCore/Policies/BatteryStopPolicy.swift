public enum PowerSourceKind: Equatable, Sendable {
    case battery
    case external
    case unavailable
}

public struct PowerSnapshot: Equatable, Sendable {
    public let source: PowerSourceKind
    public let percent: Int?
    public let isCharging: Bool

    public init(source: PowerSourceKind, percent: Int?, isCharging: Bool) {
        self.source = source
        self.percent = percent
        self.isCharging = isCharging
    }
}

public struct BatteryStopPolicy {
    public init() {}

    public func shouldDeactivate(snapshot: PowerSnapshot, settings: BatteryStopSettings) -> Bool {
        guard settings.isEnabled,
              snapshot.source == .battery,
              !snapshot.isCharging,
              let percent = snapshot.percent else {
            return false
        }
        return percent <= settings.thresholdPercent
    }
}
