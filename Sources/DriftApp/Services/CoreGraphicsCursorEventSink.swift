import CoreGraphics
import DriftCore

public final class CoreGraphicsCursorEventSink: CursorEventSink {
    public init() {}

    public func post(_ event: CursorEvent) -> Bool {
        let type: CGEventType
        let point: CGPoint
        let button: CGMouseButton
        switch event {
        case .move(let value):
            type = .mouseMoved
            point = value
            button = .left
        case .mouseDown(let mouseButton, let value):
            type = eventType(button: mouseButton, isDown: true)
            point = value
            button = cgButton(for: mouseButton)
        case .mouseUp(let mouseButton, let value):
            type = eventType(button: mouseButton, isDown: false)
            point = value
            button = cgButton(for: mouseButton)
        }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            return false
        }
        event.setIntegerValueField(.eventSourceUserData, value: DriftSyntheticEventTag.value)
        event.post(tap: .cghidEventTap)
        return true
    }

    private func eventType(button: MouseButton, isDown: Bool) -> CGEventType {
        switch (button, isDown) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        }
    }

    private func cgButton(for button: MouseButton) -> CGMouseButton {
        button == .left ? .left : .right
    }
}

public final class SystemMicrosecondSleeper: MicrosecondSleeping {
    public init() {}

    public func sleep(microseconds: UInt32) {
        usleep(microseconds)
    }
}
