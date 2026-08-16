import Foundation
import XCTest
@testable import DriftApp

final class UpdateConfigurationTests: XCTestCase {
    private let publicKey = Data(repeating: 7, count: 32).base64EncodedString()

    func testMissingBothValuesIsUnconfigured() {
        XCTAssertNil(UpdateConfiguration.load(from: [:]))
    }

    func testOnlyFeedURLIsUnconfigured() {
        XCTAssertNil(UpdateConfiguration.load(from: [
            "SUFeedURL": "https://updates.example.com/appcast.xml"
        ]))
    }

    func testOnlyPublicKeyIsUnconfigured() {
        XCTAssertNil(UpdateConfiguration.load(from: ["SUPublicEDKey": publicKey]))
    }

    func testNonHTTPSFeedIsRejected() {
        XCTAssertNil(UpdateConfiguration.load(from: [
            "SUFeedURL": "http://updates.example.com/appcast.xml",
            "SUPublicEDKey": publicKey
        ]))
    }

    func testPublicKeyMustDecodeToThirtyTwoBytes() {
        XCTAssertNil(UpdateConfiguration.load(from: [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": Data(repeating: 1, count: 31).base64EncodedString()
        ]))
    }

    func testCompleteConfigurationIsAccepted() throws {
        let configuration = try XCTUnwrap(UpdateConfiguration.load(from: [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": publicKey
        ]))

        XCTAssertEqual(configuration.feedURL.absoluteString, "https://updates.example.com/appcast.xml")
        XCTAssertEqual(configuration.publicEDKey, publicKey)
    }
}

@MainActor
final class UpdateServiceTests: XCTestCase {
    func testUnconfiguredServiceDoesNotCreateUpdater() {
        let factory = RecordingUpdaterFactory()
        let service = UpdateService(configuration: nil, factory: factory)

        service.start()

        XCTAssertEqual(factory.makeCount, 0)
        XCTAssertFalse(service.isConfigured)
        XCTAssertFalse(service.canCheckForUpdates)
        XCTAssertEqual(service.statusMessage, "Updates aren’t configured for this build.")
    }

    func testConfiguredServiceCreatesAndStartsUpdaterOnce() {
        let updater = RecordingUpdater()
        let factory = RecordingUpdaterFactory(updater: updater)
        let service = configuredService(factory: factory)

        service.start()
        service.start()
        factory.emitCanCheck(true)

        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertEqual(updater.startCount, 1)
        XCTAssertTrue(service.canCheckForUpdates)
    }

    func testCheckDelegatesOnlyWhenUpdaterCanCheck() {
        let updater = RecordingUpdater()
        let factory = RecordingUpdaterFactory(updater: updater)
        let service = configuredService(factory: factory)
        service.start()

        service.checkForUpdates()
        XCTAssertEqual(updater.checkCount, 0)

        factory.emitCanCheck(true)
        service.checkForUpdates()
        XCTAssertEqual(updater.checkCount, 1)
    }

    func testCheckForUpdatesClearsPreviousError() {
        let updater = RecordingUpdater()
        let factory = RecordingUpdaterFactory(updater: updater)
        let service = configuredService(factory: factory)
        service.start()
        factory.emitCanCheck(true)
        factory.emitError(NSError(domain: "SparkleTest", code: 1))

        service.checkForUpdates()

        XCTAssertNil(service.statusMessage)
        XCTAssertEqual(updater.checkCount, 1)
    }

    func testUpdaterErrorPublishesStatusWithoutDisablingDriftFeatures() {
        let factory = RecordingUpdaterFactory(updater: RecordingUpdater())
        let service = configuredService(factory: factory)
        service.start()

        factory.emitError(NSError(domain: "SparkleTest", code: 1))

        XCTAssertEqual(service.statusMessage, "The update check failed.")
    }

    func testStopStopsAndReleasesUpdaterOnlyOnce() {
        let updater = RecordingUpdater()
        let factory = RecordingUpdaterFactory(updater: updater)
        let service = configuredService(factory: factory)
        service.start()
        factory.emitCanCheck(true)

        service.stop()
        service.stop()

        XCTAssertEqual(updater.stopCount, 1)
        XCTAssertFalse(service.canCheckForUpdates)
    }

    private func configuredService(factory: RecordingUpdaterFactory) -> UpdateService {
        UpdateService(
            configuration: UpdateConfiguration(
                feedURL: URL(string: "https://updates.example.com/appcast.xml")!,
                publicEDKey: Data(repeating: 7, count: 32).base64EncodedString()
            ),
            factory: factory
        )
    }
}

private final class RecordingUpdater: UpdaterControlling {
    private(set) var startCount = 0
    private(set) var checkCount = 0
    private(set) var stopCount = 0
    var canCheckForUpdates = false

    func start() { startCount += 1 }
    func checkForUpdates() { checkCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
private final class RecordingUpdaterFactory: UpdaterControllerMaking {
    private let updater: RecordingUpdater
    private var onCanCheckChange: ((Bool) -> Void)?
    private var onError: ((Error) -> Void)?
    private(set) var makeCount = 0

    init(updater: RecordingUpdater? = nil) {
        self.updater = updater ?? RecordingUpdater()
    }

    func make(
        onCanCheckChange: @escaping (Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> UpdaterControlling {
        makeCount += 1
        self.onCanCheckChange = onCanCheckChange
        self.onError = onError
        return updater
    }

    func emitCanCheck(_ value: Bool) {
        updater.canCheckForUpdates = value
        onCanCheckChange?(value)
    }

    func emitError(_ error: Error) {
        onError?(error)
    }
}
