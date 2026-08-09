import Combine
import DriftCore

public struct ShortcutRecorderKeyEvent: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: ShortcutModifiers

    public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum ShortcutRecorderValidationError: Equatable {
    case modifierRequired
}

@MainActor
public final class ShortcutRecorderModel: ObservableObject {
    @Published public private(set) var shortcut: GlobalShortcut?
    @Published public private(set) var isRecording = false
    @Published public private(set) var validationError: ShortcutRecorderValidationError?
    private let onChange: (GlobalShortcut?) -> Void

    public init(shortcut: GlobalShortcut?, onChange: @escaping (GlobalShortcut?) -> Void) {
        self.shortcut = shortcut
        self.onChange = onChange
    }

    public func begin() {
        isRecording = true
        validationError = nil
    }

    public func handle(event: ShortcutRecorderKeyEvent) {
        guard isRecording else { return }
        switch event.keyCode {
        case 53:
            cancel()
        case 51, 117:
            clear()
        case 54, 55, 56, 57, 58, 60, 61, 62, 63:
            break
        default:
            guard !event.modifiers.isEmpty else {
                validationError = .modifierRequired
                return
            }
            let shortcut = GlobalShortcut(keyCode: event.keyCode, modifiers: event.modifiers)
            self.shortcut = shortcut
            validationError = nil
            isRecording = false
            onChange(shortcut)
        }
    }

    public func cancel() {
        isRecording = false
        validationError = nil
    }

    public func clear() {
        shortcut = nil
        validationError = nil
        isRecording = false
        onChange(nil)
    }
}
