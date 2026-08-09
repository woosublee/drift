import CoreGraphics
import XCTest
import DriftCore
@testable import DriftApp

final class ClickPositionValidatorTests: XCTestCase {
    func testPositionInsideAnyConnectedScreenIsValid() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1_440, height: 900),
            CGRect(x: 1_440, y: -200, width: 1_920, height: 1_080)
        ]

        XCTAssertTrue(ClickPositionValidator().isValid(ClickPosition(x: 1_600, y: 100), in: frames))
    }

    func testDisconnectedScreenPositionIsInvalid() {
        let frames = [CGRect(x: 0, y: 0, width: 1_440, height: 900)]

        XCTAssertFalse(ClickPositionValidator().isValid(ClickPosition(x: 2_000, y: 100), in: frames))
    }
}
