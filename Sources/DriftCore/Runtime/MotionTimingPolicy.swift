import Foundation

public struct MotionTimingPolicy {
    public init() {}

    public func initialDelay(settings: DriftSettings, random: DriftRandomSource) -> TimeInterval {
        let base = settings.startDelay.seconds
        guard settings.motionMode == .natural else { return base }
        return random.double(in: max(1, base - 5)...(base + 5))
    }

    public func repeatDelay(settings: DriftSettings, random: DriftRandomSource) -> TimeInterval {
        let base = settings.repeatInterval.seconds
        guard settings.motionMode == .natural, settings.repeatInterval != .continuous else { return base }
        switch settings.repeatInterval {
        case .fiveSeconds:
            return random.double(in: 4...5)
        case .tenSeconds:
            return random.double(in: 7...13)
        case .thirtySeconds:
            return random.double(in: 27...33)
        default:
            return random.double(in: max(1, base - 5)...(base + 5))
        }
    }
}
