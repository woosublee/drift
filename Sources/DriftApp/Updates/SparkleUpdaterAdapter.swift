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

enum SparkleUpdateAbortClassifier {
    static func shouldReport(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain != SUSparkleErrorDomain
            || error.code != Int(SUError.noUpdateError.rawValue)
    }
}

@MainActor
final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let onError: (Error) -> Void

    init(onError: @escaping (Error) -> Void) {
        self.onError = onError
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        handleAbort(error)
    }

    func handleAbort(_ error: Error) {
        guard SparkleUpdateAbortClassifier.shouldReport(error) else { return }
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
