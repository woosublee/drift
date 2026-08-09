import CoreGraphics
import XCTest
@testable import DriftCore

final class MotionPathGeneratorTests: XCTestCase {
    func testSilentPlanReturnsToOriginalPoint() {
        let plan = MotionPathGenerator().makePlan(
            mode: .silent,
            start: CGPoint(x: 100, y: 200),
            destination: CGPoint(x: 500, y: 500),
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 800),
            random: StubRandomSource(doubles: [])
        )

        XCTAssertEqual(plan.samples.count, 2)
        XCTAssertEqual(plan.samples.first?.point, CGPoint(x: 100.01, y: 200))
        XCTAssertEqual(plan.samples.last?.point, CGPoint(x: 100, y: 200))
    }

    func testSilentPlanPreservesExactExcursionWhenCurrentPointIsOutsideInsetBounds() {
        let start = CGPoint(x: 10, y: 10)
        let plan = MotionPathGenerator().makePlan(
            mode: .silent,
            start: start,
            destination: CGPoint(x: 500, y: 500),
            bounds: CGRect(x: 24, y: 24, width: 752, height: 552),
            random: StubRandomSource(doubles: [])
        )

        XCTAssertEqual(plan.samples.map(\.point), [
            CGPoint(x: 10.01, y: 10),
            start
        ])
    }

    func testStandardPlanUsesSixSamplesAndStaysInsideBounds() {
        let bounds = CGRect(x: 24, y: 24, width: 752, height: 552)
        let plan = MotionPathGenerator().makePlan(
            mode: .standard,
            start: CGPoint(x: 100, y: 100),
            destination: CGPoint(x: 700, y: 500),
            bounds: bounds,
            random: StubRandomSource(doubles: [])
        )

        XCTAssertEqual(plan.samples.count, 6)
        XCTAssertEqual(plan.samples.last?.point, CGPoint(x: 700, y: 500))
        XCTAssertTrue(plan.samples.allSatisfy { bounds.contains($0.point) })
    }

    func testNaturalPlanClampsSamplesAndEndsAtDestination() {
        let bounds = CGRect(x: 24, y: 24, width: 752, height: 552)
        let destination = CGPoint(x: 700, y: 500)
        let plan = MotionPathGenerator().makePlan(
            mode: .natural,
            start: CGPoint(x: 100, y: 100),
            destination: destination,
            bounds: bounds,
            random: StubRandomSource(doubles: [0.7], integers: [3])
        )

        XCTAssertEqual(plan.samples.count, 42)
        XCTAssertEqual(plan.samples.last?.point, destination)
        XCTAssertTrue(plan.samples.allSatisfy { bounds.contains($0.point) })
    }
}
