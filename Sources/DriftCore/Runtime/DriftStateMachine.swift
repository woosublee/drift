import Foundation

public enum DriftPhase: Equatable, Sendable {
    case inactive
    case permissionBlocked
    case waitingForIdle
    case performingMotion
    case waitingForRepeat
    case suspendedBySystem
}

public enum DriftDirective: Equatable, Sendable {
    case none
    case beginMotion
}

public struct DriftStateMachine: Sendable {
    public private(set) var phase: DriftPhase = .inactive
    public private(set) var activeIntent = false
    public private(set) var deadline: Date?

    public init() {}

    public mutating func restore(
        activeIntent: Bool,
        permissionGranted: Bool,
        now: Date,
        initialDelay: TimeInterval
    ) {
        setActive(activeIntent, permissionGranted: permissionGranted, now: now, initialDelay: initialDelay)
    }

    public mutating func setActive(
        _ active: Bool,
        permissionGranted: Bool,
        now: Date,
        initialDelay: TimeInterval
    ) {
        activeIntent = active
        guard active else {
            phase = .inactive
            deadline = nil
            return
        }
        guard permissionGranted else {
            phase = .permissionBlocked
            deadline = nil
            return
        }
        phase = .waitingForIdle
        deadline = now.addingTimeInterval(initialDelay)
    }

    public mutating func permissionChanged(
        isGranted: Bool,
        now: Date,
        initialDelay: TimeInterval
    ) {
        guard activeIntent else { return }
        if isGranted {
            phase = .waitingForIdle
            deadline = now.addingTimeInterval(initialDelay)
        } else {
            phase = .permissionBlocked
            deadline = nil
        }
    }

    public mutating func recordPhysicalActivity(at now: Date, initialDelay: TimeInterval) {
        guard activeIntent, phase != .permissionBlocked, phase != .suspendedBySystem else { return }
        phase = .waitingForIdle
        deadline = now.addingTimeInterval(initialDelay)
    }

    public mutating func evaluate(at now: Date) -> DriftDirective {
        guard (phase == .waitingForIdle || phase == .waitingForRepeat),
              let deadline,
              now >= deadline else {
            return .none
        }
        phase = .performingMotion
        self.deadline = nil
        return .beginMotion
    }

    public mutating func motionFinished(at now: Date, repeatDelay: TimeInterval) {
        guard activeIntent, phase == .performingMotion else { return }
        phase = .waitingForRepeat
        deadline = now.addingTimeInterval(repeatDelay)
    }

    public mutating func motionCancelled(at now: Date, initialDelay: TimeInterval) {
        guard activeIntent else { return }
        phase = .waitingForIdle
        deadline = now.addingTimeInterval(initialDelay)
    }

    public mutating func suspend() {
        guard activeIntent else { return }
        phase = .suspendedBySystem
        deadline = nil
    }

    public mutating func resume(
        permissionGranted: Bool,
        at now: Date,
        initialDelay: TimeInterval
    ) {
        guard activeIntent else { return }
        guard permissionGranted else {
            phase = .permissionBlocked
            deadline = nil
            return
        }
        phase = .waitingForIdle
        deadline = now.addingTimeInterval(initialDelay)
    }
}
