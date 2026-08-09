import CoreGraphics
import XCTest
@testable import DriftApp

final class HUDPresentationTests: XCTestCase {
    func testActiveAndInactiveMessagesAreStable() {
        XCTAssertEqual(HUDPresentation.message(isActive: true), HUDMessage(title: "Drift Active", subtitle: nil))
        XCTAssertEqual(HUDPresentation.message(isActive: false), HUDMessage(title: "Drift Inactive", subtitle: nil))
    }

    func testSelectsContainingScreenOrFirstScreen() {
        let first = CGRect(x: 0, y: 0, width: 100, height: 100)
        let second = CGRect(x: 100, y: 0, width: 100, height: 100)

        XCTAssertEqual(HUDPresentation.screen(containing: CGPoint(x: 150, y: 20), in: [first, second]), second)
        XCTAssertEqual(HUDPresentation.screen(containing: CGPoint(x: 300, y: 20), in: [first, second]), first)
    }
}
