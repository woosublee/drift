import AppKit
import XCTest
@testable import DriftApp

@MainActor
final class PopoverOutsideClickCoordinatorTests: XCTestCase {
    func testPopoverShowArmsOutsideClickShield() {
        let shield = OutsideClickShieldFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {}
        )

        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        XCTAssertEqual(shield.showCount, 1)
    }

    func testPopoverShowPlacesShieldAtPopoverLevelDirectlyBelowItsWindow() {
        let shield = OutsideClickShieldFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {}
        )

        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        XCTAssertEqual(shield.windowNumbers, [42])
        XCTAssertEqual(shield.windowLevels, [.statusBar])
    }

    func testOutsideClickClosesPopoverAndKeepsShieldUntilMouseUp() {
        let shield = OutsideClickShieldFake()
        var closeCount = 0
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: { closeCount += 1 }
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        shield.sendMouseDown()
        coordinator.popoverDidClose()

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(shield.hideCount, 0)

        shield.sendMouseUp()

        XCTAssertEqual(shield.hideCount, 1)
    }

    func testLostMouseUpDisarmsWhenPointerStateShowsReleased() {
        let shield = OutsideClickShieldFake()
        let pointerState = OutsideClickPointerStateFake(isPressed: false)
        let recovery = OutsideClickRecoverySchedulerFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {},
            pointerButtonState: pointerState,
            scheduleRecovery: recovery.schedule
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        shield.sendMouseDown()
        recovery.runNext()

        XCTAssertEqual(shield.hideCount, 1)
    }

    func testRecoveryWaitsWhileButtonRemainsPressed() {
        let shield = OutsideClickShieldFake()
        let pointerState = OutsideClickPointerStateFake(isPressed: true)
        let recovery = OutsideClickRecoverySchedulerFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {},
            pointerButtonState: pointerState,
            scheduleRecovery: recovery.schedule
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        shield.sendMouseDown()
        recovery.runNext()

        XCTAssertEqual(shield.hideCount, 0)
        XCTAssertEqual(recovery.pendingCount, 1)

        pointerState.isPressed = false
        recovery.runNext()

        XCTAssertEqual(shield.hideCount, 1)
    }

    func testRecoveryUsesHardTerminalBoundary() {
        let shield = OutsideClickShieldFake()
        let pointerState = OutsideClickPointerStateFake(isPressed: true)
        let recovery = OutsideClickRecoverySchedulerFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {},
            pointerButtonState: pointerState,
            scheduleRecovery: recovery.schedule,
            maximumRecoveryChecks: 2
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        shield.sendMouseDown()
        recovery.runNext()
        recovery.runNext()

        XCTAssertEqual(shield.hideCount, 1)
        XCTAssertEqual(recovery.pendingCount, 0)
    }

    func testNormalMouseUpInvalidatesPendingRecovery() {
        let shield = OutsideClickShieldFake()
        let recovery = OutsideClickRecoverySchedulerFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {},
            pointerButtonState: OutsideClickPointerStateFake(isPressed: false),
            scheduleRecovery: recovery.schedule
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        shield.sendMouseDown()
        shield.sendMouseUp()
        recovery.runNext()

        XCTAssertEqual(shield.hideCount, 1)
    }

    func testResetWhileConsumingImmediatelyHidesShield() {
        let shield = OutsideClickShieldFake()
        let recovery = OutsideClickRecoverySchedulerFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {},
            pointerButtonState: OutsideClickPointerStateFake(isPressed: true),
            scheduleRecovery: recovery.schedule
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )
        shield.sendMouseDown()

        coordinator.reset()
        recovery.runNext()

        XCTAssertEqual(shield.hideCount, 1)
    }

    func testNewPopoverShowClearsStaleConsumptionBeforeRearming() {
        let shield = OutsideClickShieldFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {},
            pointerButtonState: OutsideClickPointerStateFake(isPressed: true),
            scheduleRecovery: OutsideClickRecoverySchedulerFake().schedule
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )
        shield.sendMouseDown()

        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 99,
            popoverWindowLevel: .popUpMenu
        )

        XCTAssertEqual(shield.hideCount, 1)
        XCTAssertEqual(shield.showCount, 2)
        XCTAssertEqual(shield.windowNumbers, [42, 99])
    }

    func testOrdinaryPopoverCloseRemovesShieldImmediately() {
        let shield = OutsideClickShieldFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {}
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        coordinator.popoverDidClose()

        XCTAssertEqual(shield.hideCount, 1)
    }

    func testDisplayConfigurationChangeReconcilesShieldWhileConsumingClick() {
        let shield = OutsideClickShieldFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {}
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )
        shield.sendMouseDown()

        coordinator.displayConfigurationDidChange()

        XCTAssertEqual(shield.reconcileCount, 1)
        XCTAssertEqual(shield.hideCount, 0)
    }

    func testPositionSelectionDisarmsAndRearmsShieldWhilePopoverStaysOpen() {
        let shield = OutsideClickShieldFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {}
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: false,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        coordinator.selectionDidChange(true, isPopoverShown: true)
        coordinator.selectionDidChange(false, isPopoverShown: true)

        XCTAssertEqual(shield.hideCount, 1)
        XCTAssertEqual(shield.showCount, 2)
    }

    func testSelectionCompletionDoesNotRearmShieldAfterPopoverCloses() {
        let shield = OutsideClickShieldFake()
        let coordinator = PopoverOutsideClickCoordinator(
            shield: shield,
            closePopover: {}
        )
        coordinator.popoverDidShow(
            isSelectionInProgress: true,
            popoverWindowNumber: 42,
            popoverWindowLevel: .statusBar
        )

        coordinator.selectionDidChange(false, isPopoverShown: false)

        XCTAssertEqual(shield.showCount, 0)
    }
}

@MainActor
final class PopoverOutsideClickShieldControllerTests: XCTestCase {
    func testHideAndShowReuseWindowsForUnchangedScreens() {
        let fixture = makeShieldController(
            screens: [PopoverShieldScreenSnapshot(id: 1, frame: NSRect(x: 0, y: 0, width: 800, height: 600))]
        )

        fixture.controller.show(
            belowWindowNumber: 42,
            windowLevel: .statusBar,
            onMouseDown: {},
            onMouseUp: {}
        )
        fixture.controller.hide()
        fixture.controller.show(
            belowWindowNumber: 42,
            windowLevel: .statusBar,
            onMouseDown: {},
            onMouseUp: {}
        )

        XCTAssertEqual(fixture.windows.count, 1)
        XCTAssertEqual(fixture.windows[0].configureCount, 2)
        XCTAssertEqual(fixture.windows[0].orderedBelow, [42, 42])
        XCTAssertEqual(fixture.windows[0].orderOutCount, 1)
    }

    func testReconcileAddsNewScreenWithoutRecreatingExistingWindow() {
        let fixture = makeShieldController(
            screens: [PopoverShieldScreenSnapshot(id: 1, frame: NSRect(x: 0, y: 0, width: 800, height: 600))]
        )
        fixture.controller.show(
            belowWindowNumber: 42,
            windowLevel: .statusBar,
            onMouseDown: {},
            onMouseUp: {}
        )

        fixture.screens.value.append(
            PopoverShieldScreenSnapshot(id: 2, frame: NSRect(x: 800, y: 0, width: 800, height: 600))
        )
        fixture.controller.reconcile()

        XCTAssertEqual(fixture.windows.count, 2)
        XCTAssertEqual(fixture.windows[0].configureCount, 2)
        XCTAssertEqual(fixture.windows[1].configureCount, 1)
    }

    func testReconcileUpdatesExistingScreenFrame() {
        let initialFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let updatedFrame = NSRect(x: 0, y: 0, width: 1_024, height: 768)
        let fixture = makeShieldController(
            screens: [PopoverShieldScreenSnapshot(id: 1, frame: initialFrame)]
        )
        fixture.controller.show(
            belowWindowNumber: 42,
            windowLevel: .statusBar,
            onMouseDown: {},
            onMouseUp: {}
        )

        fixture.screens.value = [PopoverShieldScreenSnapshot(id: 1, frame: updatedFrame)]
        fixture.controller.reconcile()

        XCTAssertEqual(fixture.windows.count, 1)
        XCTAssertEqual(fixture.windows[0].frames, [initialFrame, updatedFrame])
    }

    func testReconcileOrdersOutAndDiscardsRemovedScreen() {
        let snapshot = PopoverShieldScreenSnapshot(
            id: 1,
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let fixture = makeShieldController(screens: [snapshot])
        fixture.controller.show(
            belowWindowNumber: 42,
            windowLevel: .statusBar,
            onMouseDown: {},
            onMouseUp: {}
        )
        let removedWindow = fixture.windows[0]

        fixture.screens.value = []
        fixture.controller.reconcile()
        fixture.screens.value = [snapshot]
        fixture.controller.reconcile()

        XCTAssertEqual(removedWindow.orderOutCount, 1)
        XCTAssertEqual(fixture.windows.count, 2)
    }

    func testReusedWindowsUseLatestPopoverOrderingContext() {
        let fixture = makeShieldController(
            screens: [PopoverShieldScreenSnapshot(id: 1, frame: NSRect(x: 0, y: 0, width: 800, height: 600))]
        )
        fixture.controller.show(
            belowWindowNumber: 42,
            windowLevel: .statusBar,
            onMouseDown: {},
            onMouseUp: {}
        )
        fixture.controller.hide()

        fixture.controller.show(
            belowWindowNumber: 99,
            windowLevel: .popUpMenu,
            onMouseDown: {},
            onMouseUp: {}
        )

        XCTAssertEqual(fixture.windows.count, 1)
        XCTAssertEqual(fixture.windows[0].orderedBelow, [42, 99])
        XCTAssertEqual(fixture.windows[0].levels, [.statusBar, .popUpMenu])
    }

    private func makeShieldController(
        screens: [PopoverShieldScreenSnapshot]
    ) -> ShieldControllerFixture {
        let screenBox = ShieldScreenBox(value: screens)
        let windowBox = ShieldWindowBox()
        let controller = PopoverOutsideClickShieldController(
            screenSnapshots: { screenBox.value },
            makeWindow: { snapshot in
                let window = OutsideClickShieldWindowFake(id: snapshot.id)
                windowBox.value.append(window)
                return window
            }
        )
        return ShieldControllerFixture(
            controller: controller,
            screens: screenBox,
            windowBox: windowBox
        )
    }
}

@MainActor
final class PopoverOutsideClickShieldWindowTests: XCTestCase {
    func testShieldWindowCoversVisibleFrameWithoutActivatingTheApp() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No screen is available")
        }
        let window = PopoverOutsideClickShieldWindow(
            frame: screen.frame,
            onMouseDown: {},
            onMouseUp: {}
        )

        XCTAssertEqual(window.frame, screen.frame)
        XCTAssertEqual(window.contentView?.frame.size, screen.frame.size)
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(window.level, .statusBar)
        XCTAssertFalse(window.isReleasedWhenClosed)
    }

    func testShieldViewConsumesMouseDownAndMouseUpPair() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No screen is available")
        }
        var downCount = 0
        var upCount = 0
        let window = PopoverOutsideClickShieldWindow(
            frame: screen.frame,
            onMouseDown: { downCount += 1 },
            onMouseUp: { upCount += 1 }
        )
        let view = try XCTUnwrap(window.contentView)
        let down = try XCTUnwrap(mouseEvent(type: .leftMouseDown, window: window))
        let up = try XCTUnwrap(mouseEvent(type: .leftMouseUp, window: window))

        XCTAssertTrue(view.acceptsFirstMouse(for: down))
        view.mouseDown(with: down)
        view.mouseUp(with: up)

        XCTAssertEqual(downCount, 1)
        XCTAssertEqual(upCount, 1)
    }

    private func mouseEvent(type: NSEvent.EventType, window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    }
}

private final class OutsideClickPointerStateFake: PointerButtonStateProviding {
    var isPressed: Bool

    init(isPressed: Bool) {
        self.isPressed = isPressed
    }

    func isAnyButtonPressed() -> Bool {
        isPressed
    }
}

@MainActor
private final class OutsideClickRecoverySchedulerFake {
    private var pending: [PopoverOutsideClickCoordinator.ScheduledRecovery] = []

    var pendingCount: Int {
        pending.count
    }

    func schedule(
        _ recovery: @escaping PopoverOutsideClickCoordinator.ScheduledRecovery
    ) {
        pending.append(recovery)
    }

    func runNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()()
    }
}

@MainActor
private final class ShieldScreenBox {
    var value: [PopoverShieldScreenSnapshot]

    init(value: [PopoverShieldScreenSnapshot]) {
        self.value = value
    }
}

@MainActor
private final class ShieldWindowBox {
    var value: [OutsideClickShieldWindowFake] = []
}

@MainActor
private struct ShieldControllerFixture {
    let controller: PopoverOutsideClickShieldController
    let screens: ShieldScreenBox
    let windowBox: ShieldWindowBox

    var windows: [OutsideClickShieldWindowFake] {
        windowBox.value
    }
}

@MainActor
private final class OutsideClickShieldWindowFake: PopoverOutsideClickShieldWindowing {
    let id: Int
    private(set) var configureCount = 0
    private(set) var frames: [NSRect] = []
    private(set) var levels: [NSWindow.Level] = []
    private(set) var orderedBelow: [Int] = []
    private(set) var orderOutCount = 0

    init(id: Int) {
        self.id = id
    }

    func configure(
        frame: NSRect,
        level: NSWindow.Level,
        onMouseDown: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    ) {
        configureCount += 1
        frames.append(frame)
        levels.append(level)
    }

    func orderBelow(windowNumber: Int) {
        orderedBelow.append(windowNumber)
    }

    func orderOut() {
        orderOutCount += 1
    }
}

@MainActor
private final class OutsideClickShieldFake: PopoverOutsideClickShielding {
    private var onMouseDown: (() -> Void)?
    private var onMouseUp: (() -> Void)?
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var windowNumbers: [Int] = []
    private(set) var windowLevels: [NSWindow.Level] = []
    private(set) var reconcileCount = 0

    func show(
        belowWindowNumber windowNumber: Int,
        windowLevel: NSWindow.Level,
        onMouseDown: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    ) {
        showCount += 1
        windowNumbers.append(windowNumber)
        windowLevels.append(windowLevel)
        self.onMouseDown = onMouseDown
        self.onMouseUp = onMouseUp
    }

    func reconcile() {
        reconcileCount += 1
    }

    func hide() {
        hideCount += 1
        onMouseDown = nil
        onMouseUp = nil
    }

    func sendMouseDown() {
        onMouseDown?()
    }

    func sendMouseUp() {
        onMouseUp?()
    }
}
