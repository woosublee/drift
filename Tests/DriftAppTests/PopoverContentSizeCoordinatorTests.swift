import AppKit
import XCTest
@testable import DriftApp

@MainActor
final class PopoverContentSizeCoordinatorTests: XCTestCase {
    func testReportedContentHeightUpdatesPopoverSize() {
        var currentSize = NSSize(width: 410, height: 500)
        var pendingUpdate: (() -> Void)?
        var appliedSizes: [NSSize] = []
        let coordinator = PopoverContentSizeCoordinator(
            currentSize: { currentSize },
            availableHeight: { 1_000 },
            schedule: { pendingUpdate = $0 },
            applySize: {
                currentSize = $0
                appliedSizes.append($0)
            }
        )

        coordinator.contentHeightDidChange(640)
        pendingUpdate?()

        XCTAssertEqual(appliedSizes, [NSSize(width: 410, height: 640)])
    }

    func testMultipleReportsBeforeScheduledUpdateUseLatestHeight() {
        var currentSize = NSSize(width: 410, height: 500)
        var scheduleCount = 0
        var pendingUpdate: (() -> Void)?
        var appliedSizes: [NSSize] = []
        let coordinator = PopoverContentSizeCoordinator(
            currentSize: { currentSize },
            availableHeight: { 1_000 },
            schedule: {
                scheduleCount += 1
                pendingUpdate = $0
            },
            applySize: {
                currentSize = $0
                appliedSizes.append($0)
            }
        )

        coordinator.contentHeightDidChange(600)
        coordinator.contentHeightDidChange(700)
        pendingUpdate?()

        XCTAssertEqual(scheduleCount, 1)
        XCTAssertEqual(appliedSizes, [NSSize(width: 410, height: 700)])
    }

    func testEquivalentHeightAfterFlushDoesNotScheduleAgain() {
        var currentSize = NSSize(width: 410, height: 500)
        var scheduleCount = 0
        var pendingUpdate: (() -> Void)?
        let coordinator = PopoverContentSizeCoordinator(
            currentSize: { currentSize },
            availableHeight: { 1_000 },
            schedule: {
                scheduleCount += 1
                pendingUpdate = $0
            },
            applySize: { currentSize = $0 }
        )
        coordinator.contentHeightDidChange(600)
        pendingUpdate?()

        coordinator.contentHeightDidChange(600.2)

        XCTAssertEqual(scheduleCount, 1)
    }

    func testRepeatedEquivalentSizeDoesNotReapply() {
        let currentSize = NSSize(width: 410, height: 600)
        var pendingUpdate: (() -> Void)?
        var appliedSizes: [NSSize] = []
        let coordinator = PopoverContentSizeCoordinator(
            currentSize: { currentSize },
            availableHeight: { 1_000 },
            schedule: { pendingUpdate = $0 },
            applySize: { appliedSizes.append($0) }
        )

        coordinator.contentHeightDidChange(600)
        pendingUpdate?()

        XCTAssertTrue(appliedSizes.isEmpty)
    }

    func testContentHeightIsCappedToAvailableScreenHeight() {
        var pendingUpdate: (() -> Void)?
        var appliedSize: NSSize?
        let coordinator = PopoverContentSizeCoordinator(
            currentSize: { NSSize(width: 410, height: 500) },
            availableHeight: { 700 },
            schedule: { pendingUpdate = $0 },
            applySize: { appliedSize = $0 }
        )

        coordinator.contentHeightDidChange(900)
        pendingUpdate?()

        XCTAssertEqual(appliedSize, NSSize(width: 410, height: 668))
    }

    func testInvalidContentHeightsAreIgnored() {
        var scheduleCount = 0
        let coordinator = PopoverContentSizeCoordinator(
            currentSize: { NSSize(width: 410, height: 500) },
            availableHeight: { 1_000 },
            schedule: { _ in scheduleCount += 1 },
            applySize: { _ in XCTFail("Invalid heights must not be applied") }
        )

        for height in [CGFloat.zero, -1, .nan, .infinity] {
            coordinator.contentHeightDidChange(height)
        }

        XCTAssertEqual(scheduleCount, 0)
    }

    func testPrepareForPresentationAppliesCurrentScreenCapSynchronously() {
        var currentSize = NSSize(width: 410, height: 500)
        var appliedSizes: [NSSize] = []
        let coordinator = PopoverContentSizeCoordinator(
            currentSize: { currentSize },
            availableHeight: { 700 },
            schedule: { _ in XCTFail("Synchronous preparation must not schedule") },
            applySize: {
                currentSize = $0
                appliedSizes.append($0)
            }
        )

        coordinator.prepareForPresentation(contentHeight: 900)

        XCTAssertEqual(appliedSizes, [NSSize(width: 410, height: 668)])
    }

    func testRefreshImmediatelyRestoresRawHeightAfterScreenGrows() {
        var availableHeight: CGFloat = 700
        var currentSize = NSSize(width: 410, height: 500)
        var appliedSizes: [NSSize] = []
        let coordinator = PopoverContentSizeCoordinator(
            currentSize: { currentSize },
            availableHeight: { availableHeight },
            schedule: { _ in },
            applySize: {
                currentSize = $0
                appliedSizes.append($0)
            }
        )
        coordinator.prepareForPresentation(contentHeight: 900)

        availableHeight = 1_000
        coordinator.refreshImmediately()

        XCTAssertEqual(
            appliedSizes,
            [NSSize(width: 410, height: 668), NSSize(width: 410, height: 900)]
        )
    }

}
