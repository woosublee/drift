import Foundation

public struct ShutdownHooks {
    public let closeOverlays: () -> Void
    public let unregisterShortcut: () -> Void
    public let shutdownModel: () -> Void
    public let cancelCursor: () -> Void
    public let dismissHUD: () -> Void
    public let stopUpdater: () -> Void
    public let removeStatusItem: () -> Void

    public init(
        closeOverlays: @escaping () -> Void,
        unregisterShortcut: @escaping () -> Void,
        shutdownModel: @escaping () -> Void,
        cancelCursor: @escaping () -> Void,
        dismissHUD: @escaping () -> Void,
        stopUpdater: @escaping () -> Void,
        removeStatusItem: @escaping () -> Void
    ) {
        self.closeOverlays = closeOverlays
        self.unregisterShortcut = unregisterShortcut
        self.shutdownModel = shutdownModel
        self.cancelCursor = cancelCursor
        self.dismissHUD = dismissHUD
        self.stopUpdater = stopUpdater
        self.removeStatusItem = removeStatusItem
    }

    public static func all(_ action: @escaping () -> Void) -> ShutdownHooks {
        ShutdownHooks(
            closeOverlays: action,
            unregisterShortcut: action,
            shutdownModel: action,
            cancelCursor: action,
            dismissHUD: action,
            stopUpdater: action,
            removeStatusItem: action
        )
    }
}

@MainActor
public final class ApplicationShutdownCoordinator {
    private let hooks: ShutdownHooks
    private var didShutdown = false

    public init(hooks: ShutdownHooks) {
        self.hooks = hooks
    }

    public func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        hooks.closeOverlays()
        hooks.unregisterShortcut()
        hooks.shutdownModel()
        hooks.cancelCursor()
        hooks.dismissHUD()
        hooks.stopUpdater()
        hooks.removeStatusItem()
    }
}
