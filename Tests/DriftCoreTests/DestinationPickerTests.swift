import CoreGraphics
import XCTest
@testable import DriftCore

final class DestinationPickerTests: XCTestCase {
    func testPickerClampsInjectedValuesToRequestedBounds() {
        let bounds = CGRect(x: 20, y: 30, width: 80, height: 170)
        let point = DestinationPicker().pick(in: bounds, random: StubRandomSource(doubles: [700, -50]))

        XCTAssertEqual(point, CGPoint(x: 100, y: 30))
    }
}
