import XCTest
@testable import DriftCore

final class DriftStateMachineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testRestoreActiveWithoutPermissionIsBlockedButKeepsIntent() {
        var machine = DriftStateMachine()

        machine.restore(activeIntent: true, permissionGranted: false, now: now, initialDelay: 60)

        XCTAssertEqual(machine.phase, .permissionBlocked)
        XCTAssertTrue(machine.activeIntent)
    }

    func testInitialDeadlineStartsMotionOnce() {
        var machine = DriftStateMachine()
        machine.restore(activeIntent: true, permissionGranted: true, now: now, initialDelay: 60)

        XCTAssertEqual(machine.evaluate(at: now.addingTimeInterval(59)), .none)
        XCTAssertEqual(machine.evaluate(at: now.addingTimeInterval(60)), .beginMotion)
        XCTAssertEqual(machine.phase, .performingMotion)
        XCTAssertEqual(machine.evaluate(at: now.addingTimeInterval(61)), .none)
    }

    func testPhysicalInputDuringMotionCancelsToInitialWait() {
        var machine = DriftStateMachine()
        machine.restore(activeIntent: true, permissionGranted: true, now: now, initialDelay: 60)
        _ = machine.evaluate(at: now.addingTimeInterval(60))

        machine.recordPhysicalActivity(at: now.addingTimeInterval(61), initialDelay: 60)

        XCTAssertEqual(machine.phase, .waitingForIdle)
        XCTAssertEqual(machine.deadline, now.addingTimeInterval(121))
    }

    func testMotionCompletionUsesRepeatDelay() {
        var machine = DriftStateMachine()
        machine.restore(activeIntent: true, permissionGranted: true, now: now, initialDelay: 60)
        _ = machine.evaluate(at: now.addingTimeInterval(60))

        machine.motionFinished(at: now.addingTimeInterval(61), repeatDelay: 10)

        XCTAssertEqual(machine.phase, .waitingForRepeat)
        XCTAssertEqual(machine.deadline, now.addingTimeInterval(71))
    }

    func testResumeWaitsInitialDelayAgain() {
        var machine = DriftStateMachine()
        machine.restore(activeIntent: true, permissionGranted: true, now: now, initialDelay: 60)
        machine.suspend()
        machine.resume(permissionGranted: true, at: now.addingTimeInterval(300), initialDelay: 60)

        XCTAssertEqual(machine.phase, .waitingForIdle)
        XCTAssertEqual(machine.deadline, now.addingTimeInterval(360))
    }

    func testResumeRechecksAccessibilityPermission() {
        var machine = DriftStateMachine()
        machine.restore(activeIntent: true, permissionGranted: true, now: now, initialDelay: 60)
        machine.suspend()

        machine.resume(permissionGranted: false, at: now.addingTimeInterval(300), initialDelay: 60)

        XCTAssertEqual(machine.phase, .permissionBlocked)
        XCTAssertNil(machine.deadline)
        XCTAssertTrue(machine.activeIntent)
    }
}
