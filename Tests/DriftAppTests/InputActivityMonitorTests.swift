import CoreGraphics
import XCTest
@testable import DriftApp

final class InputActivityMonitorTests: XCTestCase {
    func testMonitoredEventMaskIncludesAllMouseDragEvents() {
        let mask = InputActivityMonitor.monitoredEventMask

        XCTAssertTrue(mask.contains(.leftMouseDragged))
        XCTAssertTrue(mask.contains(.rightMouseDragged))
        XCTAssertTrue(mask.contains(.otherMouseDragged))
    }

    func testSyntheticTaggedEventIsIgnored() throws {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))
        event.setIntegerValueField(.eventSourceUserData, value: DriftSyntheticEventTag.value)

        XCTAssertFalse(InputActivityMonitor.shouldTreatAsPhysical(event))
    }

    func testUntaggedEventIsPhysical() throws {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))

        XCTAssertTrue(InputActivityMonitor.shouldTreatAsPhysical(event))
    }
}
