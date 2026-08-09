import AppKit
import CoreGraphics
import DriftCore

@MainActor
final class ClickPositionOverlayWindow: NSWindow, ClickPositionOverlayClosing {
    init(screen: NSScreen, converter: ScreenCoordinateConverter, onSelect: @escaping (ClickPosition) -> Void) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        contentView = ClickPositionOverlayView(converter: converter, onSelect: onSelect)
    }

    func show() {
        orderFrontRegardless()
    }
}

@MainActor
public final class SystemOverlayWindowProvider: OverlayWindowProviding {
    public init() {}

    public func makeOverlay(
        screenFrame: CGRect,
        converter: ScreenCoordinateConverter,
        onSelect: @escaping (ClickPosition) -> Void,
        onCancel: @escaping () -> Void
    ) -> ClickPositionOverlayClosing {
        let screen = NSScreen.screens.first { candidate in
            converter.coreGraphicsRect(fromAppKit: candidate.frame) == screenFrame
        } ?? NSScreen.main
        guard let screen else {
            return EmptyClickPositionOverlay()
        }
        return ClickPositionOverlayWindow(screen: screen, converter: converter, onSelect: onSelect)
    }
}

@MainActor
private final class EmptyClickPositionOverlay: ClickPositionOverlayClosing {
    func show() {}
    func close() {}
}
