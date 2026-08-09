import CoreGraphics
import XCTest
@testable import DriftCore

final class ClickSequencePlannerTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    private let start = CGPoint(x: 100, y: 100)
    private let click = CGPoint(x: 700, y: 500)

    func testNoneDoesNotCreateClickSequence() {
        let result = ClickSequencePlanner().makePlan(
            motionMode: .silent,
            clickMode: .none,
            nextAlternatingButton: .left,
            start: start,
            clickPosition: click,
            bounds: bounds,
            random: ClickSequenceStubRandomSource()
        )

        XCTAssertNil(result)
    }

    func testSilentClickUsesStandardOutboundAndReturnsToOriginalPosition() throws {
        let plan = try XCTUnwrap(ClickSequencePlanner().makePlan(
            motionMode: .silent,
            clickMode: .left,
            nextAlternatingButton: .left,
            start: start,
            clickPosition: click,
            bounds: bounds,
            random: ClickSequenceStubRandomSource()
        ))

        XCTAssertEqual(plan.button, .left)
        XCTAssertEqual(plan.outbound.samples.last?.point, click)
        XCTAssertEqual(plan.returnPlan.samples.last?.point, start)
        XCTAssertEqual(plan.holdMicroseconds, 0)
    }

    func testNaturalClickUsesRandomHold() throws {
        let plan = try XCTUnwrap(ClickSequencePlanner().makePlan(
            motionMode: .natural,
            clickMode: .right,
            nextAlternatingButton: .left,
            start: start,
            clickPosition: click,
            bounds: bounds,
            random: ClickSequenceStubRandomSource(integers: [100_000])
        ))

        XCTAssertEqual(plan.button, .right)
        XCTAssertEqual(plan.holdMicroseconds, 100_000)
    }

    func testAlternatingUsesProvidedNextButton() throws {
        let plan = try XCTUnwrap(ClickSequencePlanner().makePlan(
            motionMode: .standard,
            clickMode: .alternating,
            nextAlternatingButton: .right,
            start: start,
            clickPosition: click,
            bounds: bounds,
            random: ClickSequenceStubRandomSource()
        ))

        XCTAssertEqual(plan.button, .right)
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
