import AppKit
import XCTest
@testable import DriftApp

final class SystemActivityObserverTests: XCTestCase {
    func testDisplayReconfigurationNotificationIsForwardedAndRemovedOnStop() {
        let center = NotificationCenter()
        let observer = SystemActivityObserver(applicationNotificationCenter: center)
        var displayChangeCount = 0

        observer.start(
            onSuspend: {},
            onResume: {},
            onDisplayReconfiguration: { displayChangeCount += 1 }
        )
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(displayChangeCount, 1)

        observer.stop()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(displayChangeCount, 1)
    }

    func testWorkspaceNotificationsAreForwardedOnceAndStopRemovesObservers() {
        let center = NotificationCenter()
        let observer = SystemActivityObserver(workspaceNotificationCenter: center)
        var suspensionCount = 0
        var resumeCount = 0

        observer.start(
            onSuspend: { suspensionCount += 1 },
            onResume: { resumeCount += 1 }
        )
        observer.start(
            onSuspend: { suspensionCount += 1 },
            onResume: { resumeCount += 1 }
        )
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

        XCTAssertEqual(suspensionCount, 1)
        XCTAssertEqual(resumeCount, 1)

        observer.stop()
        observer.stop()
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

        XCTAssertEqual(suspensionCount, 1)
        XCTAssertEqual(resumeCount, 1)
    }
}
