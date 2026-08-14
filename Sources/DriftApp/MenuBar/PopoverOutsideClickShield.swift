import AppKit

@MainActor
protocol PopoverOutsideClickShielding: AnyObject {
    func show(
        belowWindowNumber windowNumber: Int,
        windowLevel: NSWindow.Level,
        onMouseDown: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    )
    func reconcile()
    func hide()
}

@MainActor
final class PopoverOutsideClickCoordinator {
    typealias ScheduledRecovery = @MainActor @Sendable () -> Void
    typealias RecoveryScheduler = (@escaping ScheduledRecovery) -> Void

    private enum State {
        case idle
        case armed
        case consuming
    }

    private let shield: PopoverOutsideClickShielding
    private let closePopover: () -> Void
    private let pointerButtonState: PointerButtonStateProviding
    private let scheduleRecovery: RecoveryScheduler
    private let maximumRecoveryChecks: Int
    private var popoverWindowNumber: Int?
    private var popoverWindowLevel: NSWindow.Level?
    private var state = State.idle
    private var recoveryGeneration = 0
    private var recoveryCheckCount = 0

    init(
        shield: PopoverOutsideClickShielding,
        closePopover: @escaping () -> Void,
        pointerButtonState: PointerButtonStateProviding = CoreGraphicsPointerButtonStateProvider(),
        scheduleRecovery: @escaping RecoveryScheduler = { recovery in
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.1,
                execute: recovery
            )
        },
        maximumRecoveryChecks: Int = 20
    ) {
        self.shield = shield
        self.closePopover = closePopover
        self.pointerButtonState = pointerButtonState
        self.scheduleRecovery = scheduleRecovery
        self.maximumRecoveryChecks = max(1, maximumRecoveryChecks)
    }

    func popoverDidShow(
        isSelectionInProgress: Bool,
        popoverWindowNumber: Int,
        popoverWindowLevel: NSWindow.Level
    ) {
        if state != .idle {
            reset()
        }
        self.popoverWindowNumber = popoverWindowNumber
        self.popoverWindowLevel = popoverWindowLevel
        guard !isSelectionInProgress else { return }
        arm()
    }

    func selectionDidChange(_ isSelecting: Bool, isPopoverShown: Bool) {
        if isSelecting {
            disarm()
        } else if isPopoverShown {
            arm()
        }
    }

    func displayConfigurationDidChange() {
        guard state != .idle else { return }
        shield.reconcile()
    }

    func popoverDidClose() {
        popoverWindowNumber = nil
        popoverWindowLevel = nil
        guard state != .consuming else { return }
        disarm()
    }

    func reset() {
        popoverWindowNumber = nil
        popoverWindowLevel = nil
        invalidateRecovery()
        guard state != .idle else { return }
        state = .idle
        shield.hide()
    }

    func stop() {
        reset()
    }

    private func arm() {
        guard state == .idle,
              let popoverWindowNumber,
              let popoverWindowLevel else {
            return
        }
        state = .armed
        shield.show(
            belowWindowNumber: popoverWindowNumber,
            windowLevel: popoverWindowLevel,
            onMouseDown: { [weak self] in
                self?.outsideMouseDown()
            },
            onMouseUp: { [weak self] in
                self?.outsideMouseUp()
            }
        )
    }

    private func disarm() {
        invalidateRecovery()
        guard state != .idle else { return }
        state = .idle
        shield.hide()
    }

    private func outsideMouseDown() {
        guard state == .armed else { return }
        state = .consuming
        startRecovery()
        closePopover()
    }

    private func outsideMouseUp() {
        guard state == .consuming else { return }
        disarm()
    }

    private func startRecovery() {
        recoveryGeneration += 1
        recoveryCheckCount = 0
        scheduleRecoveryCheck(generation: recoveryGeneration)
    }

    private func scheduleRecoveryCheck(generation: Int) {
        scheduleRecovery { [weak self] in
            guard let self,
                  self.recoveryGeneration == generation,
                  self.state == .consuming else {
                return
            }
            self.recoveryCheckCount += 1
            if !self.pointerButtonState.isAnyButtonPressed()
                || self.recoveryCheckCount >= self.maximumRecoveryChecks {
                self.disarm()
            } else {
                self.scheduleRecoveryCheck(generation: generation)
            }
        }
    }

    private func invalidateRecovery() {
        recoveryGeneration += 1
        recoveryCheckCount = 0
    }
}

struct PopoverShieldScreenSnapshot: Equatable {
    let id: Int
    let frame: NSRect
}

@MainActor
protocol PopoverOutsideClickShieldWindowing: AnyObject {
    func configure(
        frame: NSRect,
        level: NSWindow.Level,
        onMouseDown: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    )
    func orderBelow(windowNumber: Int)
    func orderOut()
}

@MainActor
final class PopoverOutsideClickShieldController: PopoverOutsideClickShielding {
    typealias ScreenSnapshots = @MainActor () -> [PopoverShieldScreenSnapshot]
    typealias WindowFactory = @MainActor (PopoverShieldScreenSnapshot) -> PopoverOutsideClickShieldWindowing

    private struct Presentation {
        let windowNumber: Int
        let windowLevel: NSWindow.Level
        let onMouseDown: () -> Void
        let onMouseUp: () -> Void
    }

    private let screenSnapshots: ScreenSnapshots
    private let makeWindow: WindowFactory
    private var windows: [Int: PopoverOutsideClickShieldWindowing] = [:]
    private var presentation: Presentation?

    init(
        screenSnapshots: @escaping ScreenSnapshots = PopoverOutsideClickShieldController.systemScreenSnapshots,
        makeWindow: @escaping WindowFactory = { snapshot in
            PopoverOutsideClickShieldWindow(
                frame: snapshot.frame,
                onMouseDown: {},
                onMouseUp: {}
            )
        }
    ) {
        self.screenSnapshots = screenSnapshots
        self.makeWindow = makeWindow
    }

    func show(
        belowWindowNumber windowNumber: Int,
        windowLevel: NSWindow.Level,
        onMouseDown: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    ) {
        presentation = Presentation(
            windowNumber: windowNumber,
            windowLevel: windowLevel,
            onMouseDown: onMouseDown,
            onMouseUp: onMouseUp
        )
        reconcile()
    }

    func reconcile() {
        guard let presentation else { return }
        let snapshots = screenSnapshots()
        let currentIDs = Set(snapshots.map(\.id))

        for id in windows.keys where !currentIDs.contains(id) {
            windows[id]?.orderOut()
            windows[id] = nil
        }

        for snapshot in snapshots {
            let window: PopoverOutsideClickShieldWindowing
            if let existing = windows[snapshot.id] {
                window = existing
            } else {
                let created = makeWindow(snapshot)
                windows[snapshot.id] = created
                window = created
            }
            window.configure(
                frame: snapshot.frame,
                level: presentation.windowLevel,
                onMouseDown: presentation.onMouseDown,
                onMouseUp: presentation.onMouseUp
            )
            window.orderBelow(windowNumber: presentation.windowNumber)
        }
    }

    func hide() {
        presentation = nil
        windows.values.forEach { $0.orderOut() }
    }

    private static func systemScreenSnapshots() -> [PopoverShieldScreenSnapshot] {
        NSScreen.screens.map { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            let id = (screen.deviceDescription[key] as? NSNumber)?.intValue
                ?? ObjectIdentifier(screen).hashValue
            return PopoverShieldScreenSnapshot(id: id, frame: screen.frame)
        }
    }
}

@MainActor
final class PopoverOutsideClickShieldWindow: NSPanel, PopoverOutsideClickShieldWindowing {
    private let shieldView: PopoverOutsideClickShieldView

    init(
        frame: NSRect,
        level: NSWindow.Level = .statusBar,
        onMouseDown: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    ) {
        shieldView = PopoverOutsideClickShieldView(
            frame: NSRect(origin: .zero, size: frame.size),
            onMouseDown: onMouseDown,
            onMouseUp: onMouseUp
        )
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        contentView = shieldView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configure(
        frame: NSRect,
        level: NSWindow.Level,
        onMouseDown: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    ) {
        setFrame(frame, display: false)
        self.level = level
        shieldView.frame = NSRect(origin: .zero, size: frame.size)
        shieldView.onMouseDown = onMouseDown
        shieldView.onMouseUp = onMouseUp
    }

    func orderBelow(windowNumber: Int) {
        order(.below, relativeTo: windowNumber)
    }

    func orderOut() {
        orderOut(nil)
    }
}

private final class PopoverOutsideClickShieldView: NSView {
    var onMouseDown: () -> Void
    var onMouseUp: () -> Void

    init(
        frame: NSRect,
        onMouseDown: @escaping () -> Void,
        onMouseUp: @escaping () -> Void
    ) {
        self.onMouseDown = onMouseDown
        self.onMouseUp = onMouseUp
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown()
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp()
    }

    override func rightMouseDown(with event: NSEvent) {
        onMouseDown()
    }

    override func rightMouseUp(with event: NSEvent) {
        onMouseUp()
    }

    override func otherMouseDown(with event: NSEvent) {
        onMouseDown()
    }

    override func otherMouseUp(with event: NSEvent) {
        onMouseUp()
    }
}
