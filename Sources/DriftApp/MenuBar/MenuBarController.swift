import AppKit
import Combine
import SwiftUI
import DriftCore

public enum MenuBarPresentation {
    public static let popoverContentWidth: CGFloat = DriftPopoverMetrics.contentWidth

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
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let model: DriftAppModel
    private let updateService: UpdateService
    private let identity: AppIdentity
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private lazy var symbolUpdateCoordinator = MenuBarSymbolUpdateCoordinator {
        [weak self] phase in
        self?.updateSymbol(for: phase)
    }
    private var phaseSubscription: AnyCancellable?
    private var isStopped = false

    init(model: DriftAppModel, updateService: UpdateService) {
        self.model = model
        self.updateService = updateService
        let identity = AppIdentity.current
        self.identity = identity
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.delegate = self
        let hostingController = NSHostingController(
            rootView: DriftPopoverView(
                model: model,
                updateService: updateService,
                identity: identity
            )
        )
        hostingController.view.layoutSubtreeIfNeeded()
        let availableHeight = NSScreen.screens.first?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? hostingController.view.fittingSize.height
        popover.contentViewController = hostingController
        popover.contentSize = MenuBarPresentation.popoverContentSize(
            fittingSize: hostingController.view.fittingSize,
            availableHeight: availableHeight
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
    }

    func popoverDidClose(_ notification: Notification) {
        symbolUpdateCoordinator.popoverDidClose(currentPhase: model.phase)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        popover.performClose(nil)
        phaseSubscription = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateSymbol(for phase: DriftPhase) {
        statusItem.button?.image = MenuBarIconRenderer.image(
            for: MenuBarPresentation.glyph(for: phase),
            accessibilityDescription: identity.displayName
        )
    }
}
