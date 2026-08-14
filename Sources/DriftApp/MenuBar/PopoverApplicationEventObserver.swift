import AppKit

@MainActor
final class PopoverApplicationEventObserver {
    private let notificationCenter: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func start(
        onDeactivate: @escaping () -> Void,
        onDisplayConfigurationChange: @escaping () -> Void
    ) {
        guard tokens.isEmpty else { return }
        tokens = [
            notificationCenter.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in onDeactivate() },
            notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in onDisplayConfigurationChange() }
        ]
    }

    func stop() {
        tokens.forEach(notificationCenter.removeObserver)
        tokens.removeAll()
    }
}
