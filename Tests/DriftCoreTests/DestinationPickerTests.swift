import CoreGraphics
import XCTest
@testable import DriftCore

final class DestinationPickerTests: XCTestCase {
    func testPickerClampsInjectedValuesToRequestedBounds() {
        let bounds = CGRect(x: 20, y: 30, width: 80, height: 170)
        let point = DestinationPicker().pick(in: bounds, random: StubRandomSource(doubles: [700, -50]))

        XCTAssertEqual(point, CGPoint(x: 100, y: 30))
    }

    func testPickerChoosesPointAtLeastMinimumDistanceFromAvoidedPoint() {
        let bounds = CGRect(x: 24, y: 24, width: 752, height: 552)
        let avoided = CGPoint(x: 400, y: 300)
        let point = DestinationPicker().pick(
            in: bounds,
            avoiding: avoided,
            minimumDistance: 96,
            random: StubRandomSource(doubles: [410, 310, 600, 500])
        )

        XCTAssertEqual(point, CGPoint(x: 600, y: 500))
        XCTAssertGreaterThanOrEqual(hypot(point.x - avoided.x, point.y - avoided.y), 96)
    }

    func testPickerFallsBackToFarthestCornerWhenRandomPointsAreTooClose() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let point = DestinationPicker().pick(
            in: bounds,
            avoiding: CGPoint(x: 100, y: 100),
            minimumDistance: 1_000,
            random: StubRandomSource(doubles: Array(repeating: 100, count: 16))
        )

        XCTAssertEqual(point, CGPoint(x: 800, y: 600))
    }
}
