import XCTest
@testable import DriftCore

final class StubRandomSource: DriftRandomSource {
    private var doubles: [Double]
    private var integers: [Int]

    init(doubles: [Double], integers: [Int] = []) {
        self.doubles = doubles
        self.integers = integers
    }

    func double(in range: ClosedRange<Double>) -> Double {
        let fallback = (range.lowerBound + range.upperBound) / 2
        let value = doubles.isEmpty ? fallback : doubles.removeFirst()
        return min(range.upperBound, max(range.lowerBound, value))
    }

    func int(in range: ClosedRange<Int>) -> Int {
        let fallback = (range.lowerBound + range.upperBound) / 2
        let value = integers.isEmpty ? fallback : integers.removeFirst()
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

final class MotionTimingPolicyTests: XCTestCase {
    func testNaturalTimingUsesConfiguredVariation() {
        let random = StubRandomSource(doubles: [58, 12])
        let policy = MotionTimingPolicy()
        var settings = DriftSettings.default
        settings.motionMode = .natural

        XCTAssertEqual(policy.initialDelay(settings: settings, random: random), 58)
        XCTAssertEqual(policy.repeatDelay(settings: settings, random: random), 12)
    }

    func testContinuousRepeatDelayIsNotRandomized() {
        let random = StubRandomSource(doubles: [99])
        var settings = DriftSettings.default
        settings.motionMode = .natural
        settings.repeatInterval = .continuous

        XCTAssertEqual(MotionTimingPolicy().repeatDelay(settings: settings, random: random), 0.1)
    }
}
