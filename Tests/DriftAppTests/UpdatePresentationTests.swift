import XCTest
@testable import DriftApp

final class UpdatePresentationTests: XCTestCase {
    func testUnconfiguredBuildDisablesCheckButtonAndShowsExplanation() {
        XCTAssertFalse(UpdatePresentation.checkButtonEnabled(isConfigured: false, canCheck: false))
        XCTAssertEqual(
            UpdatePresentation.statusMessage(isConfigured: false, canCheck: false, serviceMessage: nil),
            "Updates aren’t configured for this build."
        )
    }

    func testUnconfiguredExplanationUsesInformationalToneRatherThanErrorTone() {
        XCTAssertEqual(
            UpdatePresentation.statusTone(
                isConfigured: false,
                serviceMessage: "Updates aren’t configured for this build."
            ),
            .informational
        )
    }

    func testConfiguredReadyBuildEnablesCheckButton() {
        XCTAssertTrue(UpdatePresentation.checkButtonEnabled(isConfigured: true, canCheck: true))
    }

    func testConfiguredUnavailableBuildExplainsDisabledCheckButton() {
        XCTAssertFalse(UpdatePresentation.checkButtonEnabled(isConfigured: true, canCheck: false))
        XCTAssertEqual(
            UpdatePresentation.statusMessage(isConfigured: true, canCheck: false, serviceMessage: nil),
            "Updates are temporarily unavailable."
        )
    }

    func testConfiguredFailureUsesIndependentServiceMessage() {
        XCTAssertEqual(
            UpdatePresentation.statusMessage(
                isConfigured: true,
                canCheck: false,
                serviceMessage: "The update check failed."
            ),
            "The update check failed."
        )
    }
}
