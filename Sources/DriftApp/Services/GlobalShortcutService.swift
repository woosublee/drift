import Carbon
import DriftCore

public enum GlobalShortcutError: Error, Equatable {
    case registrationFailed(Int32)
}

public protocol GlobalShortcutManaging: AnyObject {
    func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) -> Result<Void, GlobalShortcutError>
    func unregister()
}

public protocol GlobalShortcutSystemControlling: AnyObject {
    func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) -> Result<Void, GlobalShortcutError>
    func unregister()
}

public enum CarbonShortcutMapping {
    public static func modifiers(for modifiers: ShortcutModifiers) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

public final class NullGlobalShortcutService: GlobalShortcutManaging {
    public init() {}
    public func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) -> Result<Void, GlobalShortcutError> { .success(()) }
    public func unregister() {}
}

public final class GlobalShortcutService: GlobalShortcutManaging {
    private let system: GlobalShortcutSystemControlling
    private var hasRegisteredShortcut = false

    public init(system: GlobalShortcutSystemControlling = CarbonHotKeySystem()) {
        self.system = system
    }

    deinit {
        unregister()
    }

    public func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) -> Result<Void, GlobalShortcutError> {
        if hasRegisteredShortcut {
            system.unregister()
            hasRegisteredShortcut = false
        }
        let result = system.register(shortcut, handler: handler)
        if case .success = result {
            hasRegisteredShortcut = true
        }
        return result
    }

    public func unregister() {
        guard hasRegisteredShortcut else { return }
        system.unregister()
        hasRegisteredShortcut = false
    }
}

private func fourCharCode(_ value: StaticString) -> OSType {
    precondition(value.utf8CodeUnitCount == 4)
    return value.withUTF8Buffer { buffer in
        buffer.reduce(0) { ($0 << 8) | OSType($1) }
    }
}

public final class CarbonHotKeySystem: GlobalShortcutSystemControlling {
    private let hotKeyID = EventHotKeyID(signature: fourCharCode("DRFT"), id: 1)
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    public init() {}

    deinit {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    public func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) -> Result<Void, GlobalShortcutError> {
        unregister()
        self.handler = handler
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                Self.receiveHotKey,
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
            guard status == noErr else {
                self.handler = nil
                return .failure(.registrationFailed(status))
            }
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            CarbonShortcutMapping.modifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            self.handler = nil
            return .failure(.registrationFailed(status))
        }
        hotKeyRef = reference
        return .success(())
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        handler = nil
    }

    private static let receiveHotKey: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        let system = Unmanaged<CarbonHotKeySystem>.fromOpaque(userData).takeUnretainedValue()
        var receivedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedID
        )
        guard status == noErr,
              receivedID.signature == system.hotKeyID.signature,
              receivedID.id == system.hotKeyID.id else {
            return OSStatus(eventNotHandledErr)
        }
        Task { @MainActor [weak system] in
            system?.handler?()
        }
        return noErr
    }
}
