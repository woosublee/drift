import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class MenuBarSymbolUpdateCoordinatorTests: XCTestCase {
    func testPhaseChangeWhilePopoverIsShownWaitsUntilPopoverCloses() {
        var appliedPhases: [DriftPhase] = []
        let coordinator = MenuBarSymbolUpdateCoordinator { phase in
            appliedPhases.append(phase)
        }

        coordinator.phaseDidChange(.inactive, isPopoverShown: false)
        coordinator.phaseDidChange(.waitingForIdle, isPopoverShown: true)

        XCTAssertEqual(appliedPhases, [.inactive])

        coordinator.popoverDidClose(currentPhase: .waitingForIdle)

        XCTAssertEqual(appliedPhases, [.inactive, .waitingForIdle])
    }

    func testRepeatedPhaseAppliesOnlyOnce() {
        var appliedPhases: [DriftPhase] = []
        let coordinator = MenuBarSymbolUpdateCoordinator { phase in
            appliedPhases.append(phase)
        }

        coordinator.phaseDidChange(.inactive, isPopoverShown: false)
        coordinator.phaseDidChange(.inactive, isPopoverShown: false)

        XCTAssertEqual(appliedPhases, [.inactive])
    }

    func testPopoverCloseDoesNotReapplyAlreadyAppliedPhase() {
        var appliedPhases: [DriftPhase] = []
        let coordinator = MenuBarSymbolUpdateCoordinator { phase in
            appliedPhases.append(phase)
        }

        coordinator.phaseDidChange(.inactive, isPopoverShown: false)
        coordinator.popoverDidClose(currentPhase: .inactive)

        XCTAssertEqual(appliedPhases, [.inactive])
    }

    func testDistinctActivePhasesSharingGlyphApplyOnlyOnce() {
        var appliedPhases: [DriftPhase] = []
        let coordinator = MenuBarSymbolUpdateCoordinator { phase in
            appliedPhases.append(phase)
        }

        coordinator.phaseDidChange(.waitingForIdle, isPopoverShown: false)
        coordinator.phaseDidChange(.performingMotion, isPopoverShown: false)
        coordinator.phaseDidChange(.waitingForRepeat, isPopoverShown: false)

        XCTAssertEqual(appliedPhases, [.waitingForIdle])
    }
}
