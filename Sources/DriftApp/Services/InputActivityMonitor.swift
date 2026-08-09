import AppKit
import CoreGraphics

public protocol InputActivityMonitoring: AnyObject {
    func start(onActivity: @escaping () -> Void)
    func stop()
}

public protocol PointerButtonStateProviding: AnyObject {
    func isAnyButtonPressed() -> Bool
}

public final class CoreGraphicsPointerButtonStateProvider: PointerButtonStateProviding {
    public init() {}

    public func isAnyButtonPressed() -> Bool {
        (0..<32).contains { button in
            guard let mouseButton = CGMouseButton(rawValue: UInt32(button)) else { return false }
            return CGEventSource.buttonState(.combinedSessionState, button: mouseButton)
        }
    }
}

public final class InputActivityMonitor: InputActivityMonitoring {
    public static let monitoredEventMask: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel,
        .keyDown,
        .gesture,
        .magnify,
        .swipe,
        .pressure
    ]
    private let eventMask = monitoredEventMask
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onActivity: (() -> Void)?

    public init() {}

    public func start(onActivity: @escaping () -> Void) {
        stop()
        self.onActivity = onActivity
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    public func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        onActivity = nil
    }

    public static func shouldTreatAsPhysical(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) != DriftSyntheticEventTag.value
    }

    private func handle(_ event: NSEvent) {
        guard event.cgEvent.map(Self.shouldTreatAsPhysical) ?? true else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onActivity?()
        }
    }
}
