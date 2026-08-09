import CoreGraphics
import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class ApplicationShutdownCoordinatorTests: XCTestCase {
    func testShutdownRunsEveryCleanupInSafetyOrder() {
        var calls: [String] = []
        let coordinator = ApplicationShutdownCoordinator(hooks: ShutdownHooks(
            closeOverlays: { calls.append("overlays") },
            unregisterShortcut: { calls.append("shortcut") },
            shutdownModel: { calls.append("model") },
            cancelCursor: { calls.append("cursor") },
            dismissHUD: { calls.append("hud") },
            stopUpdater: { calls.append("updater") },
            removeStatusItem: { calls.append("statusItem") }
        ))

        coordinator.shutdown()

        XCTAssertEqual(calls, [
            "overlays", "shortcut", "model", "cursor", "hud", "updater", "statusItem"
        ])
    }

    func testShutdownIsIdempotent() {
        var count = 0
        let coordinator = ApplicationShutdownCoordinator(hooks: .all { count += 1 })

        coordinator.shutdown()
        coordinator.shutdown()

        XCTAssertEqual(count, 7)
    }

    func testShutdownWaitsForSafetyMouseUpAndCursorQueueDrain() {
        let sink = ShutdownRecordingSink()
        let sleeper = ShutdownDelaySleeper()
        let service = CursorEventService(sink: sink, sleeper: sleeper)
        let position = CGPoint(x: 10, y: 20)
        let sequence = ClickSequencePlan(
            outbound: MotionPlan(samples: []),
            button: .left,
            position: position,
            holdMicroseconds: 200_000,
            returnPlan: MotionPlan(samples: [])
        )
        service.execute(sequence) { _ in }
        XCTAssertEqual(sleeper.waitUntilSleeping(), .success)
        let coordinator = ApplicationShutdownCoordinator(hooks: ShutdownHooks(
            closeOverlays: {},
            unregisterShortcut: {},
            shutdownModel: {},
            cancelCursor: { service.cancelAndWait() },
            dismissHUD: {},
            stopUpdater: {},
            removeStatusItem: {}
        ))

        coordinator.shutdown()

        XCTAssertEqual(sink.events, [
            .mouseDown(button: .left, at: position),
            .mouseUp(button: .left, at: position)
        ])
        XCTAssertFalse(service.isExecuting)
    }
}

private final class ShutdownRecordingSink: CursorEventSink {
    private let lock = NSLock()
    private var recordedEvents: [CursorEvent] = []

    var events: [CursorEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func post(_ event: CursorEvent) -> Bool {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
        return true
    }
}

private final class ShutdownDelaySleeper: MicrosecondSleeping {
    private let didEnterSleep = DispatchSemaphore(value: 0)
    private var hasSignalled = false
    private let lock = NSLock()

    func sleep(microseconds: UInt32) {
        lock.lock()
        if !hasSignalled {
            hasSignalled = true
            didEnterSleep.signal()
        }
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.02)
    }

    func waitUntilSleeping() -> DispatchTimeoutResult {
        didEnterSleep.wait(timeout: .now() + 1)
    }
}
