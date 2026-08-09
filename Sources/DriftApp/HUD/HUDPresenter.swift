import AppKit
import SwiftUI

@MainActor
public final class HUDPresenter: HUDPresenting {
    private let cursorLocation: CursorLocationProviding
    private let displayGeometry: DisplayGeometryProviding
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    public init(cursorLocation: CursorLocationProviding, displayGeometry: DisplayGeometryProviding) {
        self.cursorLocation = cursorLocation
        self.displayGeometry = displayGeometry
    }

    deinit {
        dismissWorkItem?.cancel()
    }

    public func show(_ message: HUDMessage) {
        dismiss()
        let controller = NSHostingController(rootView: HUDView(message: message))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 90),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = controller
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let location = cursorLocation.currentLocation()
        let screens = NSScreen.screens
        let converter = ScreenCoordinateConverter(primaryScreenMaxY: ScreenCoordinateConverter.primaryScreenMaxY(
            fromAppKitScreenFrames: screens.map(\.frame)
        ))
        let selectedScreen = screens.first {
            converter.coreGraphicsRect(fromAppKit: $0.frame).contains(location)
        } ?? NSScreen.main
        if let selectedScreen {
            let frame = selectedScreen.frame
            panel.setFrameOrigin(CGPoint(x: frame.midX - 130, y: frame.midY - 45))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reducedMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.contentView?.wantsLayer = true
            panel.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.96, y: 0.96))
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
                panel.contentView?.layer?.setAffineTransform(.identity)
            }
        }
        let workItem = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    public func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
