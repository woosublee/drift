import AppKit
import SwiftUI
import XCTest
@testable import DriftApp

@MainActor
final class ApplicationFooterTests: XCTestCase {
    func testFooterUsesCompactHeightWhenNoStatusMessageIsVisible() throws {
        let size = try footerSize(
            versionText: "Drift 0.1.2",
            quitTitle: "Quit Drift",
            dynamicTypeSize: .medium
        )

        XCTAssertLessThan(size.height, 60)
    }

    func testFooterUsesTallerFallbackWhenCompactRowDoesNotFit() throws {
        let normalSize = try footerSize(
            versionText: "Drift 0.1.2",
            quitTitle: "Quit Drift",
            dynamicTypeSize: .medium
        )
        let constrainedSize = try footerSize(
            versionText: "Drift 0.1.2",
            quitTitle: "Quit Drift",
            dynamicTypeSize: .accessibility5,
            width: 240
        )

        XCTAssertEqual(constrainedSize.width, 240, accuracy: 0.5)
        XCTAssertGreaterThan(constrainedSize.height, normalSize.height)
    }

    func testFooterUsesFallbackForLongDevelopmentLabels() throws {
        let size = try footerSize(
            versionText: "Drift Development Preview 0.1.2-beta.123456789",
            quitTitle: "Quit Drift Development Preview",
            dynamicTypeSize: .accessibility5
        )

        XCTAssertEqual(size.width, 366, accuracy: 0.5)
        XCTAssertGreaterThan(size.height, 60)
    }

    private func footerSize(
        versionText: String,
        quitTitle: String,
        dynamicTypeSize: DynamicTypeSize,
        width: CGFloat = 366
    ) throws -> NSSize {
        let updater = FooterUpdater()
        let service = UpdateService(
            configuration: UpdateConfiguration(
                feedURL: try XCTUnwrap(URL(string: "https://example.com/appcast.xml")),
                publicEDKey: "test-key"
            ),
            factory: FooterUpdaterFactory(updater: updater)
        )
        service.start()
        let hostingController = NSHostingController(
            rootView: ApplicationFooter(
                updateService: service,
                quitTitle: quitTitle,
                versionText: versionText,
                errorMessage: nil,
                checkForUpdates: service.checkForUpdates
            )
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(
                \.sizeCategory,
                dynamicTypeSize == .medium
                    ? ContentSizeCategory.medium
                    : .accessibilityExtraExtraExtraLarge
            )
            .frame(width: width)
        )

        hostingController.view.layoutSubtreeIfNeeded()
        return hostingController.view.fittingSize
    }
}

@MainActor
private final class FooterUpdater: UpdaterControlling {
    let canCheckForUpdates = true
    func start() {}
    func checkForUpdates() {}
    func stop() {}
}

@MainActor
private final class FooterUpdaterFactory: UpdaterControllerMaking {
    private let updater: UpdaterControlling

    init(updater: UpdaterControlling) {
        self.updater = updater
    }

    func make(
        onCanCheckChange: @escaping (Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> UpdaterControlling {
        updater
    }
}
