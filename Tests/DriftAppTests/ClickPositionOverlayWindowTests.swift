import AppKit
import XCTest
@testable import DriftApp

@MainActor
final class ClickPositionOverlayWindowTests: XCTestCase {
    func testOverlayWindowKeepsCloseLifetimeUnderARC() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No screen is available")
        }
        let converter = ScreenCoordinateConverter(
            primaryScreenMaxY: ScreenCoordinateConverter.primaryScreenMaxY(
                fromAppKitScreenFrames: NSScreen.screens.map(\.frame)
            )
        )

        let window = ClickPositionOverlayWindow(
            screen: screen,
            converter: converter,
            onSelect: { _ in }
        )

        XCTAssertFalse(window.isReleasedWhenClosed)
    }
}
