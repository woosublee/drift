import AppKit

public protocol SystemActivityObserving: AnyObject {
    func start(onSuspend: @escaping () -> Void, onResume: @escaping () -> Void)
    func start(
        onSuspend: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onDisplayReconfiguration: @escaping () -> Void
    )
    func stop()
}

public extension SystemActivityObserving {
    func start(
        onSuspend: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onDisplayReconfiguration: @escaping () -> Void
    ) {
        start(onSuspend: onSuspend, onResume: onResume)
    }
}

public final class SystemActivityObserver: SystemActivityObserving {
    private let workspaceNotificationCenter: NotificationCenter
    private let distributedNotificationCenter: DistributedNotificationCenter
    private let applicationNotificationCenter: NotificationCenter
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var applicationTokens: [NSObjectProtocol] = []

    public init(
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedNotificationCenter: DistributedNotificationCenter = .default(),
        applicationNotificationCenter: NotificationCenter = .default
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.distributedNotificationCenter = distributedNotificationCenter
        self.applicationNotificationCenter = applicationNotificationCenter
    }

    deinit {
        stop()
    }

    public func start(onSuspend: @escaping () -> Void, onResume: @escaping () -> Void) {
        start(onSuspend: onSuspend, onResume: onResume, onDisplayReconfiguration: {})
    }

    public func start(
        onSuspend: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onDisplayReconfiguration: @escaping () -> Void
    ) {
        guard workspaceTokens.isEmpty, distributedTokens.isEmpty, applicationTokens.isEmpty else { return }

        workspaceTokens = [
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { _ in onSuspend() },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { _ in onResume() }
        ]
        distributedTokens = [
            distributedNotificationCenter.addObserver(
                forName: Notification.Name("com.apple.screensaver.didstart"),
                object: nil,
                queue: .main
            ) { _ in onSuspend() },
            distributedNotificationCenter.addObserver(
                forName: Notification.Name("com.apple.screensaver.didstop"),
                object: nil,
                queue: .main
            ) { _ in onResume() }
        ]
        applicationTokens = [
            applicationNotificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in onDisplayReconfiguration() }
        ]
    }

    public func stop() {
        workspaceTokens.forEach(workspaceNotificationCenter.removeObserver)
        distributedTokens.forEach(distributedNotificationCenter.removeObserver)
        applicationTokens.forEach(applicationNotificationCenter.removeObserver)
        workspaceTokens.removeAll()
        distributedTokens.removeAll()
        applicationTokens.removeAll()
    }
}
