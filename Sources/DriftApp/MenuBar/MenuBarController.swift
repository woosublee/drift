import AppKit
import Combine
import SwiftUI
import DriftCore

public enum MenuBarPresentation {
    public static let popoverContentWidth: CGFloat = DriftPopoverMetrics.contentWidth
    public static let popoverBehavior = NSPopover.Behavior.applicationDefined

    static func availablePopoverHeight(
        statusItemScreenHeight: CGFloat?,
        mainScreenHeight: CGFloat?,
        firstScreenHeight: CGFloat?,
        fallbackHeight: CGFloat
    ) -> CGFloat {
        statusItemScreenHeight
            ?? mainScreenHeight
            ?? firstScreenHeight
            ?? fallbackHeight
    }

    static func glyph(for phase: DriftPhase) -> MenuBarGlyph {
        switch phase {
        case .inactive:
            .asset(name: "MenuBarIcon-Inactive")
        case .permissionBlocked:
            .systemSymbol(name: "exclamationmark.triangle")
        case .waitingForIdle, .performingMotion, .waitingForRepeat, .suspendedBySystem:
            .asset(name: "MenuBarIcon-Active")
        }
    }

    public static func popoverContentSize(
        fittingSize: NSSize,
        availableHeight: CGFloat
    ) -> NSSize {
        NSSize(
            width: fittingSize.width,
            height: min(fittingSize.height, max(0, availableHeight - 32))
        )
    }
}

@MainActor
final class MenuBarSymbolUpdateCoordinator {
    private let applyPhase: (DriftPhase) -> Void

    init(applyPhase: @escaping (DriftPhase) -> Void) {
        self.applyPhase = applyPhase
    }

    func phaseDidChange(
        _ phase: DriftPhase,
        isPopoverShown: Bool
    ) {
        guard !isPopoverShown else { return }
        applyPhase(phase)
    }

    func popoverDidClose(currentPhase: DriftPhase) {
        applyPhase(currentPhase)
    }
}

@MainActor
final class PopoverCloseCoordinator {
    private let isSelectionInProgress: () -> Bool
    private let prepareForExplicitClose: () -> Void
    private let forceClose: () -> Void

    init(
        isSelectionInProgress: @escaping () -> Bool,
        prepareForExplicitClose: @escaping () -> Void = {},
        forceClose: @escaping () -> Void
    ) {
        self.isSelectionInProgress = isSelectionInProgress
        self.prepareForExplicitClose = prepareForExplicitClose
        self.forceClose = forceClose
    }

    func shouldAllowAutomaticClose() -> Bool {
        !isSelectionInProgress()
    }

    func closeExplicitly() {
        prepareForExplicitClose()
        forceClose()
    }

    func closeForApplicationDeactivation(
        cancelSelection: () -> Void
    ) {
        if isSelectionInProgress() {
            cancelSelection()
        }
        closeExplicitly()
    }
}

@MainActor
final class PopoverContentSizeCoordinator {
    typealias ScheduledUpdate = @MainActor @Sendable () -> Void

    private let currentSize: () -> NSSize
    private let availableHeight: () -> CGFloat
    private let schedule: (@escaping ScheduledUpdate) -> Void
    private let applySize: (NSSize) -> Void
    private var latestContentHeight: CGFloat?
    private var isUpdateScheduled = false

    init(
        currentSize: @escaping () -> NSSize,
        availableHeight: @escaping () -> CGFloat,
        schedule: @escaping (@escaping ScheduledUpdate) -> Void,
        applySize: @escaping (NSSize) -> Void
    ) {
        self.currentSize = currentSize
        self.availableHeight = availableHeight
        self.schedule = schedule
        self.applySize = applySize
    }

    func contentHeightDidChange(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        if let latestContentHeight,
           abs(latestContentHeight - height) < 0.5 {
            return
        }
        latestContentHeight = height
        scheduleUpdate()
    }

    func prepareForPresentation(contentHeight: CGFloat) {
        guard contentHeight.isFinite, contentHeight > 0 else { return }
        latestContentHeight = contentHeight
        applyLatestSize()
    }

    func refreshImmediately() {
        guard latestContentHeight != nil else { return }
        applyLatestSize()
    }

    private func scheduleUpdate() {
        guard !isUpdateScheduled else { return }
        isUpdateScheduled = true
        schedule { [weak self] in
            self?.applyScheduledSize()
        }
    }

    private func applyScheduledSize() {
        isUpdateScheduled = false
        applyLatestSize()
    }

    private func applyLatestSize() {
        guard let latestContentHeight else { return }
        let currentSize = currentSize()
        let width = currentSize.width > 0
            ? currentSize.width
            : DriftPopoverMetrics.contentWidth
        let targetSize = MenuBarPresentation.popoverContentSize(
            fittingSize: NSSize(width: width, height: latestContentHeight),
            availableHeight: availableHeight()
        )
        guard !approximatelyEqual(currentSize, targetSize) else { return }
        applySize(targetSize)
    }

    private func approximatelyEqual(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let model: DriftAppModel
    private let updateService: UpdateService
    private let identity: AppIdentity
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let applicationEventObserver = PopoverApplicationEventObserver()
    private lazy var symbolUpdateCoordinator = MenuBarSymbolUpdateCoordinator {
        [weak self] phase in
        self?.updateSymbol(for: phase)
    }
    private lazy var closeCoordinator = PopoverCloseCoordinator(
        isSelectionInProgress: { [weak self] in
            self?.model.isSelectingClickPosition ?? false
        },
        prepareForExplicitClose: { [weak self] in
            self?.outsideClickCoordinator.reset()
        },
        forceClose: { [weak self] in
            self?.popover.close()
        }
    )
    private lazy var outsideClickCoordinator = PopoverOutsideClickCoordinator(
        shield: PopoverOutsideClickShieldController(),
        closePopover: { [weak self] in
            self?.popover.close()
        }
    )
    private lazy var contentSizeCoordinator = PopoverContentSizeCoordinator(
        currentSize: { [weak self] in
            self?.popover.contentSize ?? NSSize(
                width: DriftPopoverMetrics.contentWidth,
                height: 0
            )
        },
        availableHeight: { [weak self] in
            self?.availablePopoverHeight() ?? 0
        },
        schedule: { update in
            DispatchQueue.main.async(execute: update)
        },
        applySize: { [weak self] size in
            self?.popover.contentSize = size
        }
    )
    private var phaseSubscription: AnyCancellable?
    private var selectionSubscription: AnyCancellable?
    private var isStopped = false

    init(model: DriftAppModel, updateService: UpdateService) {
        self.model = model
        self.updateService = updateService
        let identity = AppIdentity.current
        self.identity = identity
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        popover.behavior = MenuBarPresentation.popoverBehavior
        popover.delegate = self
        let hostingController = NSHostingController(
            rootView: DriftPopoverView(
                model: model,
                updateService: updateService,
                identity: identity,
                onContentHeightChange: { [weak self] height in
                    self?.contentSizeCoordinator.contentHeightDidChange(height)
                }
            )
        )
        hostingController.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hostingController
        contentSizeCoordinator.prepareForPresentation(
            contentHeight: hostingController.view.fittingSize.height
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        updateSymbol(for: model.phase)
        phaseSubscription = model.$phase.sink { [weak self] phase in
            guard let self else { return }
            symbolUpdateCoordinator.phaseDidChange(
                phase,
                isPopoverShown: popover.isShown
            )
        }
        selectionSubscription = model.$isSelectingClickPosition
            .removeDuplicates()
            .sink { [weak self] isSelecting in
                guard let self else { return }
                outsideClickCoordinator.selectionDidChange(
                    isSelecting,
                    isPopoverShown: popover.isShown
                )
            }
        applicationEventObserver.start(
            onDeactivate: { [weak self] in
                guard let self, popover.isShown else { return }
                closeCoordinator.closeForApplicationDeactivation {
                    model.cancelClickPositionSelection()
                }
            },
            onDisplayConfigurationChange: { [weak self] in
                guard let self, popover.isShown else { return }
                contentSizeCoordinator.refreshImmediately()
                outsideClickCoordinator.displayConfigurationDidChange()
            }
        )
    }

    func popoverWillShow(_ notification: Notification) {
        model.refreshLoginItemStatus()
        contentSizeCoordinator.refreshImmediately()
    }

    func popoverDidShow(_ notification: Notification) {
        guard let popoverWindow = popover.contentViewController?.view.window else {
            return
        }
        outsideClickCoordinator.popoverDidShow(
            isSelectionInProgress: model.isSelectingClickPosition,
            popoverWindowNumber: popoverWindow.windowNumber,
            popoverWindowLevel: popoverWindow.level
        )
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        closeCoordinator.shouldAllowAutomaticClose()
    }

    func popoverDidClose(_ notification: Notification) {
        outsideClickCoordinator.popoverDidClose()
        symbolUpdateCoordinator.popoverDidClose(currentPhase: model.phase)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        applicationEventObserver.stop()
        closeCoordinator.closeExplicitly()
        phaseSubscription = nil
        selectionSubscription = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closeCoordinator.closeExplicitly()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func availablePopoverHeight() -> CGFloat {
        MenuBarPresentation.availablePopoverHeight(
            statusItemScreenHeight: statusItem.button?.window?.screen?.visibleFrame.height,
            mainScreenHeight: NSScreen.main?.visibleFrame.height,
            firstScreenHeight: NSScreen.screens.first?.visibleFrame.height,
            fallbackHeight: popover.contentSize.height + 32
        )
    }

    private func updateSymbol(for phase: DriftPhase) {
        statusItem.button?.image = MenuBarIconRenderer.image(
            for: MenuBarPresentation.glyph(for: phase),
            accessibilityDescription: identity.displayName
        )
    }
}
