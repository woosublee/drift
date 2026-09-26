import AppKit
import ApplicationServices
import PermissionFlow

public protocol AccessibilityProviding: AnyObject {
    func isTrusted() -> Bool
    func requestAccess()
    @MainActor func openSystemSettings()
}

public extension AccessibilityProviding {
    func requestAccess() {}
}

public final class AccessibilityCoordinator: AccessibilityProviding {
    @MainActor private lazy var permissionFlow = PermissionFlow.makeController()

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

    @MainActor
    public func openSystemSettings() {
        let mouse = NSEvent.mouseLocation
        permissionFlow.authorize(
            pane: .accessibility,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
        )
    }
}
