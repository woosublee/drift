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
}
