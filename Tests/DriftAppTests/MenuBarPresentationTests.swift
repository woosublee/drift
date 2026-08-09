import AppKit
import XCTest
import DriftCore
@testable import DriftApp

final class MenuBarPresentationTests: XCTestCase {
    func testInactiveUsesWindSymbol() {
        XCTAssertEqual(MenuBarPresentation.symbolName(for: .inactive), "wind")
    }

    func testActivePhasesUseFilledWindSymbol() {
        XCTAssertEqual(MenuBarPresentation.symbolName(for: .waitingForIdle), "wind.circle.fill")
        XCTAssertEqual(MenuBarPresentation.symbolName(for: .performingMotion), "wind.circle.fill")
        XCTAssertEqual(MenuBarPresentation.symbolName(for: .waitingForRepeat), "wind.circle.fill")
    }

    func testBlockedUsesWarningSymbol() {
        XCTAssertEqual(MenuBarPresentation.symbolName(for: .permissionBlocked), "exclamationmark.triangle")
    }

    func testPopoverUsesCompactReferenceWidth() {
        XCTAssertEqual(MenuBarPresentation.popoverContentWidth, 410)
    }

    func testPopoverContentSizeUsesFittingHeightWhenItFits() {
        XCTAssertEqual(
            MenuBarPresentation.popoverContentSize(
                fittingSize: NSSize(width: 360, height: 520),
                availableHeight: 1_000
            ),
            NSSize(width: 360, height: 520)
        )
    }

    func testPopoverContentSizeCapsHeightBeforePresentation() {
        XCTAssertEqual(
            MenuBarPresentation.popoverContentSize(
                fittingSize: NSSize(width: 360, height: 1_200),
                availableHeight: 970
            ),
            NSSize(width: 360, height: 938)
        )
    }
}
