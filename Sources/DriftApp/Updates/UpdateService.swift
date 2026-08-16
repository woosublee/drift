import Combine
import Foundation

@MainActor
public protocol UpdaterControlling: AnyObject {
    var canCheckForUpdates: Bool { get }
    func start()
    func checkForUpdates()
    func stop()
}

@MainActor
public protocol UpdaterControllerMaking: AnyObject {
    func make(
        onCanCheckChange: @escaping (Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> UpdaterControlling
}

@MainActor
public final class UpdateService: ObservableObject {
    public let isConfigured: Bool

    @Published public private(set) var canCheckForUpdates = false
    @Published public private(set) var statusMessage: String?

    private let configuration: UpdateConfiguration?
    private let factory: UpdaterControllerMaking
    private var updater: UpdaterControlling?

    public init(configuration: UpdateConfiguration?, factory: UpdaterControllerMaking) {
        self.configuration = configuration
        self.factory = factory
        isConfigured = configuration != nil
        statusMessage = configuration == nil ? "Updates aren’t configured for this build." : nil
    }

    public func start() {
        guard configuration != nil, updater == nil else { return }

        let updater = factory.make(
            onCanCheckChange: { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            },
            onError: { [weak self] _ in
                self?.statusMessage = "The update check failed."
            }
        )
        self.updater = updater
        updater.start()
        canCheckForUpdates = updater.canCheckForUpdates
    }

    public func checkForUpdates() {
        guard canCheckForUpdates else { return }
        statusMessage = nil
        updater?.checkForUpdates()
    }

    public func stop() {
        guard let updater else { return }
        updater.stop()
        self.updater = nil
        canCheckForUpdates = false
    }
}
