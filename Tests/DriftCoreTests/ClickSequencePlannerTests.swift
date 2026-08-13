import CoreGraphics
import XCTest
@testable import DriftCore

final class ClickSequencePlannerTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    private let start = CGPoint(x: 100, y: 100)
    private let click = CGPoint(x: 700, y: 500)

    func testNoneDoesNotCreateClickSequence() {
        let result = ClickSequencePlanner().makePlan(
            isSmartMotionEnabled: false,
            clickMode: .none,
            nextAlternatingButton: .left,
            start: start,
            clickPosition: click,
            departurePosition: CGPoint(x: 300, y: 700),
            bounds: bounds,
            random: ClickSequenceStubRandomSource()
        )

        XCTAssertNil(result)
    }

    func testFixedClickUsesDistanceBasedPathsAndMovesToDeparturePosition() throws {
        let departure = CGPoint(x: 300, y: 700)
        let plan = try makePlan(
            isSmartMotionEnabled: false,
            clickMode: .left,
            departurePosition: departure
        )

        XCTAssertEqual(plan.button, .left)
        XCTAssertEqual(plan.outbound.samples.last?.point, click)
        XCTAssertEqual(plan.returnPlan.samples.last?.point, departure)
        XCTAssertNotEqual(plan.returnPlan.samples.last?.point, start)
        XCTAssertEqual(plan.holdMicroseconds, 0)
    }

    func testSmartMotionClickUsesNaturalPathAndRandomHold() throws {
        let plan = try makePlan(
            isSmartMotionEnabled: true,
            clickMode: .right,
            integers: [100_000]
        )

        XCTAssertEqual(plan.button, .right)
        XCTAssertEqual(plan.outbound.samples.count, 42)
        XCTAssertEqual(plan.returnPlan.samples.count, 42)
        XCTAssertEqual(plan.holdMicroseconds, 100_000)
    }

    func testAlternatingUsesProvidedNextButton() throws {
        let plan = try makePlan(
            isSmartMotionEnabled: false,
            clickMode: .alternating,
            nextAlternatingButton: .right
        )

        XCTAssertEqual(plan.button, .right)
    }

    private func makePlan(
        isSmartMotionEnabled: Bool,
        clickMode: ClickMode,
        nextAlternatingButton: MouseButton = .left,
        departurePosition: CGPoint = CGPoint(x: 300, y: 700),
        integers: [Int] = []
    ) throws -> ClickSequencePlan {
        try XCTUnwrap(ClickSequencePlanner().makePlan(
            isSmartMotionEnabled: isSmartMotionEnabled,
            clickMode: clickMode,
            nextAlternatingButton: nextAlternatingButton,
            start: start,
            clickPosition: click,
            departurePosition: departurePosition,
            bounds: bounds,
            random: ClickSequenceStubRandomSource(integers: integers)
        ))
    }
}

private final class ClickSequenceStubRandomSource: DriftRandomSource {
    private var integers: [Int]

    init(integers: [Int] = []) {
        self.integers = integers
    }

    func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound
    }

    func int(in range: ClosedRange<Int>) -> Int {
        if !integers.isEmpty {
            return integers.removeFirst()
        }
        return range.lowerBound
    }
}
