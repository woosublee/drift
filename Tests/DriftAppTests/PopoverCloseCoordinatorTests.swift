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
}
