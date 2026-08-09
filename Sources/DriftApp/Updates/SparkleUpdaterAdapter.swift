import Foundation
import Sparkle

@MainActor
public final class SparkleUpdaterControllerFactory: UpdaterControllerMaking {
    public init() {}

    public func make(
        onCanCheckChange: @escaping (Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> UpdaterControlling {
        SparkleUpdaterControllerAdapter(
            onCanCheckChange: onCanCheckChange,
            onError: onError
        )
    }
}

@MainActor
private final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let onError: (Error) -> Void

    init(onError: @escaping (Error) -> Void) {
        self.onError = onError
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        onError(error)
    }
}

@MainActor
private final class SparkleUpdaterControllerAdapter: UpdaterControlling {
    private let delegate: SparkleUpdaterDelegate
    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    init(
        onCanCheckChange: @escaping (Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        let delegate = SparkleUpdaterDelegate(onError: onError)
        self.delegate = delegate
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { updater, _ in
            onCanCheckChange(updater.canCheckForUpdates)
        }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func start() {
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func stop() {
        canCheckObservation?.invalidate()
        canCheckObservation = nil
    }
}
