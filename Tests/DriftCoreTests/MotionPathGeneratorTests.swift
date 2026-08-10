import CoreGraphics
import XCTest
@testable import DriftCore

final class MotionPathGeneratorTests: XCTestCase {
    private let start = CGPoint(x: 100, y: 200)
    private let destination = CGPoint(x: 500, y: 500)
    private let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    func testSilentModeReturnsToOriginalPoint() {
        let plan = makePlan(isSilentModeEnabled: true, isSmartMotionEnabled: false)

        XCTAssertEqual(plan.samples.count, 2)
        XCTAssertEqual(plan.samples.first?.point, CGPoint(x: 100.01, y: 200))
        XCTAssertEqual(plan.samples.last?.point, start)
    }

    func testSilentModeTakesPrecedenceOverSmartMotionPath() {
        let plan = makePlan(isSilentModeEnabled: true, isSmartMotionEnabled: true)

        XCTAssertEqual(plan.samples.map(\.point), [
            CGPoint(x: 100.01, y: 200),
            start
        ])
    }

    func testFixedMotionUsesSixSamplesAndStaysInsideBounds() {
        let plan = makePlan(isSilentModeEnabled: false, isSmartMotionEnabled: false)

        XCTAssertEqual(plan.samples.count, 6)
        XCTAssertEqual(plan.samples.last?.point, destination)
        XCTAssertTrue(plan.samples.allSatisfy { bounds.contains($0.point) })
    }

    func testSmartMotionClampsSamplesAndEndsAtDestination() {
        let plan = MotionPathGenerator().makePlan(
            isSilentModeEnabled: false,
            isSmartMotionEnabled: true,
            start: start,
            destination: destination,
            bounds: bounds,
            random: StubRandomSource(doubles: [0.7], integers: [3])
        )

        XCTAssertEqual(plan.samples.count, 42)
        XCTAssertEqual(plan.samples.last?.point, destination)
        XCTAssertTrue(plan.samples.allSatisfy { bounds.contains($0.point) })
    }

    func testSilentPlanPreservesExactExcursionWhenCurrentPointIsOutsideInsetBounds() {
        let offBoundsStart = CGPoint(x: 10, y: 10)
        let plan = MotionPathGenerator().makePlan(
            isSilentModeEnabled: true,
            isSmartMotionEnabled: false,
            start: offBoundsStart,
            destination: destination,
            bounds: CGRect(x: 24, y: 24, width: 752, height: 552),
            random: StubRandomSource(doubles: [])
        )

        XCTAssertEqual(plan.samples.map(\.point), [
            CGPoint(x: 10.01, y: 10),
            offBoundsStart
        ])
    }

    private func makePlan(
        isSilentModeEnabled: Bool,
        isSmartMotionEnabled: Bool
    ) -> MotionPlan {
        MotionPathGenerator().makePlan(
            isSilentModeEnabled: isSilentModeEnabled,
            isSmartMotionEnabled: isSmartMotionEnabled,
            start: start,
            destination: destination,
            bounds: bounds,
            random: StubRandomSource(doubles: [])
        )
    }
}
