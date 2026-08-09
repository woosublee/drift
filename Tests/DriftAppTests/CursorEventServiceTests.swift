import CoreGraphics
import XCTest
import DriftCore
@testable import DriftApp

final class CursorEventServiceTests: XCTestCase {
    func testPostsMotionSamplesInOrder() {
        let sink = RecordingCursorEventSink()
        let service = CursorEventService(sink: sink, sleeper: ImmediateSleeper())
        let completion = expectation(description: "completion")
        let plan = MotionPlan(samples: [
            MotionSample(point: CGPoint(x: 1, y: 2), delayAfterMicroseconds: 10),
            MotionSample(point: CGPoint(x: 3, y: 4), delayAfterMicroseconds: 0)
        ])

        service.execute(plan) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(sink.events, [.move(to: CGPoint(x: 1, y: 2)), .move(to: CGPoint(x: 3, y: 4))])
    }

    func testSecondSequenceIsRejectedWhileFirstIsRunning() {
        let sink = RecordingCursorEventSink()
        let sleeper = BlockingSleeper()
        let service = CursorEventService(sink: sink, sleeper: sleeper)
        service.execute(MotionPlan(samples: [MotionSample(point: .zero, delayAfterMicroseconds: 10)])) { _ in }

        let completion = expectation(description: "rejected")
        service.execute(MotionPlan(samples: [])) { result in
            guard case .failure(let error) = result else {
                XCTFail("Expected overlap rejection")
                return
            }
            XCTAssertEqual(error, .sequenceAlreadyRunning)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
        service.cancel()
        sleeper.release()
    }

    func testCancellationStopsSequenceAfterCurrentSleep() {
        let firstPost = expectation(description: "first post")
        let completion = expectation(description: "cancelled")
        let sink = RecordingCursorEventSink(onPost: { _ in firstPost.fulfill() })
        let sleeper = BlockingSleeper()
        let service = CursorEventService(sink: sink, sleeper: sleeper)
        let plan = MotionPlan(samples: [
            MotionSample(point: CGPoint(x: 1, y: 1), delayAfterMicroseconds: 10),
            MotionSample(point: CGPoint(x: 2, y: 2), delayAfterMicroseconds: 0)
        ])

        service.execute(plan) { result in
            guard case .failure(let error) = result else {
                XCTFail("Expected cancellation")
                return
            }
            XCTAssertEqual(error, .cancelled)
            completion.fulfill()
        }
        wait(for: [firstPost], timeout: 1)
        service.cancel()
        sleeper.release()

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(sink.events, [.move(to: CGPoint(x: 1, y: 1))])
    }

    func testSinkFailureEndsSequenceWithPostFailure() {
        let sink = RecordingCursorEventSink(results: [false])
        let service = CursorEventService(sink: sink, sleeper: ImmediateSleeper())
        let completion = expectation(description: "post failure")

        service.execute(MotionPlan(samples: [MotionSample(point: .zero, delayAfterMicroseconds: 0)])) { result in
            guard case .failure(let error) = result else {
                XCTFail("Expected post failure")
                return
            }
            XCTAssertEqual(error, .eventPostFailed)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
    }
}

private final class RecordingCursorEventSink: CursorEventSink {
    private(set) var events: [CursorEvent] = []
    private var results: [Bool]
    private let onPost: ((CursorEvent) -> Void)?

    init(results: [Bool] = [], onPost: ((CursorEvent) -> Void)? = nil) {
        self.results = results
        self.onPost = onPost
    }

    func post(_ event: CursorEvent) -> Bool {
        events.append(event)
        onPost?(event)
        return results.isEmpty ? true : results.removeFirst()
    }
}

private final class ImmediateSleeper: MicrosecondSleeping {
    func sleep(microseconds: UInt32) {}
}

private final class BlockingSleeper: MicrosecondSleeping {
    private let semaphore = DispatchSemaphore(value: 0)

    func sleep(microseconds: UInt32) {
        semaphore.wait()
    }

    func release() {
        semaphore.signal()
    }
}
