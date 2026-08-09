import CoreGraphics
import XCTest
@testable import DriftApp

final class ScreenCoordinateConverterTests: XCTestCase {
    func testProductionFlipReferenceUsesFirstMenuBarScreenInsteadOfKeyWindowScreen() {
        let menuBarScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let keyWindowScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(
            ScreenCoordinateConverter.primaryScreenMaxY(fromAppKitScreenFrames: [menuBarScreen, keyWindowScreen]),
            900
        )
    }

    func testConvertsAppKitFramesIntoCoreGraphicsGlobalCoordinates() {
        let converter = ScreenCoordinateConverter(primaryScreenMaxY: 900)

        XCTAssertEqual(
            converter.coreGraphicsRect(fromAppKit: CGRect(x: 1440, y: -180, width: 1920, height: 1080)),
            CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        )
    }

    func testConvertsAppKitPointsIntoCoreGraphicsGlobalCoordinates() {
        let converter = ScreenCoordinateConverter(primaryScreenMaxY: 900)

        XCTAssertEqual(
            converter.coreGraphicsPoint(fromAppKit: CGPoint(x: 100, y: 200)),
            CGPoint(x: 100, y: 700)
        )
    }
}
