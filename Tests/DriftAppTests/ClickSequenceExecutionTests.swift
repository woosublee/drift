import CoreGraphics
import XCTest
import DriftCore
@testable import DriftApp

final class ClickSequenceExecutionTests: XCTestCase {
    func testClickSequencePostsOutboundDownUpAndReturnInOrder() {
        let sink = ClickRecordingSink()
        let service = CursorEventService(sink: sink, sleeper: ClickImmediateSleeper())
        let completion = expectation(description: "completed")

        service.execute(makeSequence()) { result in
            guard case .success = result else {
                XCTFail("Expected successful click sequence, got \(result)")
                return
            }
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(sink.events, [
            .move(to: CGPoint(x: 5, y: 5)),
            .mouseDown(button: .left, at: CGPoint(x: 5, y: 5)),
            .mouseUp(button: .left, at: CGPoint(x: 5, y: 5)),
            .move(to: CGPoint(x: 1, y: 1))
        ])
    }

    func testCancellationAfterMouseDownPostsSafetyMouseUpButSkipsReturnPath() {
        let sink = ClickRecordingSink(cancelAfterCount: 2)
        let service = CursorEventService(sink: sink, sleeper: ClickImmediateSleeper())
        sink.onThreshold = { service.cancel() }
        let completion = expectation(description: "cancelled")

        service.execute(makeSequence()) { result in
            if case .failure(.cancelled) = result {
                completion.fulfill()
            }
        }

        wait(for: [completion], timeout: 1)
        XCTAssertTrue(sink.events.contains(.mouseUp(button: .left, at: CGPoint(x: 5, y: 5))))
        XCTAssertFalse(sink.events.contains(.move(to: CGPoint(x: 1, y: 1))))
    }

    func testNaturalHoldIsSplitIntoAtMostFiveMillisecondChunks() {
        let sleeper = ClickRecordingSleeper()
        let service = CursorEventService(sink: ClickRecordingSink(), sleeper: sleeper)
        let completion = expectation(description: "completed")

        service.execute(makeSequence(holdMicroseconds: 12_001)) { _ in
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(sleeper.delays.reduce(0, +), 12_001)
        XCTAssertTrue(sleeper.delays.allSatisfy { $0 <= 5_000 })
        XCTAssertGreaterThan(sleeper.delays.count, 1)
    }

    func testCancelAndWaitFromCursorQueueDoesNotDeadlockAndPostsSafetyMouseUp() {
        let sink = ClickRecordingSink(cancelAfterCount: 2)
        let service = CursorEventService(sink: sink, sleeper: ClickImmediateSleeper())
        sink.onThreshold = { service.cancelAndWait() }
        let completion = expectation(description: "cancelled")

        service.execute(makeSequence()) { result in
            guard case .failure(.cancelled) = result else {
                XCTFail("Expected cancellation, got \(result)")
                return
            }
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
        XCTAssertTrue(sink.events.contains(.mouseUp(button: .left, at: CGPoint(x: 5, y: 5))))
    }

    private func makeSequence(holdMicroseconds: UInt32 = 100_000) -> ClickSequencePlan {
        ClickSequencePlan(
            outbound: MotionPlan(samples: [MotionSample(point: CGPoint(x: 5, y: 5), delayAfterMicroseconds: 0)]),
            button: .left,
            position: CGPoint(x: 5, y: 5),
            holdMicroseconds: holdMicroseconds,
            returnPlan: MotionPlan(samples: [MotionSample(point: CGPoint(x: 1, y: 1), delayAfterMicroseconds: 0)])
        )
    }
}

private final class ClickRecordingSink: CursorEventSink {
    private(set) var events: [CursorEvent] = []
    let cancelAfterCount: Int?
    var onThreshold: (() -> Void)?

    init(cancelAfterCount: Int? = nil) {
        self.cancelAfterCount = cancelAfterCount
    }

    func post(_ event: CursorEvent) -> Bool {
        events.append(event)
        if events.count == cancelAfterCount {
            onThreshold?()
        }
        return true
    }
}

private final class ClickImmediateSleeper: MicrosecondSleeping {
    func sleep(microseconds: UInt32) {}
}

private final class ClickRecordingSleeper: MicrosecondSleeping {
    private(set) var delays: [UInt32] = []

    func sleep(microseconds: UInt32) {
        delays.append(microseconds)
    }
}
