import AppKit
import XCTest
@testable import DriftApp

@MainActor
final class PopoverApplicationEventObserverTests: XCTestCase {
    func testNotificationsAreForwardedOnceAcrossRepeatedStart() {
        let center = NotificationCenter()
        let observer = PopoverApplicationEventObserver(notificationCenter: center)
        var deactivationCount = 0
        var displayChangeCount = 0

        observer.start(
            onDeactivate: { deactivationCount += 1 },
            onDisplayConfigurationChange: { displayChangeCount += 1 }
        )
        observer.start(
            onDeactivate: { deactivationCount += 1 },
            onDisplayConfigurationChange: { displayChangeCount += 1 }
        )
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        XCTAssertEqual(deactivationCount, 1)
        XCTAssertEqual(displayChangeCount, 1)
    }

    func testStopRemovesObserversAndIsIdempotent() {
        let center = NotificationCenter()
        let observer = PopoverApplicationEventObserver(notificationCenter: center)
        var callbackCount = 0
        observer.start(
            onDeactivate: { callbackCount += 1 },
            onDisplayConfigurationChange: { callbackCount += 1 }
        )

        observer.stop()
        observer.stop()
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        XCTAssertEqual(callbackCount, 0)
    }
}
