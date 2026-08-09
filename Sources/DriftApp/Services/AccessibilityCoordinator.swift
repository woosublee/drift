import AppKit
import ApplicationServices

public protocol AccessibilityProviding: AnyObject {
    func isTrusted() -> Bool
    func requestAccess()
    func openSystemSettings()
}

public extension AccessibilityProviding {
    func requestAccess() {}
}

public final class AccessibilityCoordinator: AccessibilityProviding {
    public init() {}

    public func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
