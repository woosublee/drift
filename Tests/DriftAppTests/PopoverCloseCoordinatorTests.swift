import XCTest
@testable import DriftApp

@MainActor
final class PopoverCloseCoordinatorTests: XCTestCase {
    func testAutomaticCloseIsAllowedOutsidePositionSelection() {
        let coordinator = PopoverCloseCoordinator(
            isSelectionInProgress: { false },
            forceClose: {}
        )

        XCTAssertTrue(coordinator.shouldAllowAutomaticClose())
    }

    func testAutomaticCloseIsVetoedDuringPositionSelection() {
        let coordinator = PopoverCloseCoordinator(
            isSelectionInProgress: { true },
            forceClose: {}
        )

        XCTAssertFalse(coordinator.shouldAllowAutomaticClose())
    }

    func testExplicitCloseResetsOutsideClickStateBeforeClosingPopover() {
        var events: [String] = []
        let coordinator = PopoverCloseCoordinator(
            isSelectionInProgress: { false },
            prepareForExplicitClose: { events.append("reset") },
            forceClose: { events.append("close") }
        )

        coordinator.closeExplicitly()

        XCTAssertEqual(events, ["reset", "close"])
    }

    func testExplicitCloseForcesClosureDuringPositionSelection() {
        var closeCount = 0
        let coordinator = PopoverCloseCoordinator(
            isSelectionInProgress: { true },
            forceClose: { closeCount += 1 }
        )

        coordinator.closeExplicitly()

        XCTAssertEqual(closeCount, 1)
    }

    func testExclusivePresentationCancelsSelectionBeforeResetAndClose() {
        var events: [String] = []
        let coordinator = PopoverCloseCoordinator(
            isSelectionInProgress: { true },
            prepareForExplicitClose: { events.append("reset") },
            forceClose: { events.append("close") }
        )

        coordinator.closeForExclusivePresentation {
            events.append("cancel")
        }

        XCTAssertEqual(events, ["cancel", "reset", "close"])
    }

    func testExclusivePresentationClosesWithoutCancellationOutsideSelection() {
        var events: [String] = []
        let coordinator = PopoverCloseCoordinator(
            isSelectionInProgress: { false },
            prepareForExplicitClose: { events.append("reset") },
            forceClose: { events.append("close") }
        )

        coordinator.closeForExclusivePresentation {
            events.append("cancel")
        }

        XCTAssertEqual(events, ["reset", "close"])
    }
}

@MainActor
final class UpdateCheckCoordinatorTests: XCTestCase {
    func testUpdateCheckPreparesExclusivePresentationBeforeChecking() {
        var events: [String] = []
        let coordinator = UpdateCheckCoordinator(
            prepareForUpdateUI: { events.append("prepare") },
            checkForUpdates: { events.append("check") }
        )

        coordinator.checkForUpdates()

        XCTAssertEqual(events, ["prepare", "check"])
    }
}
