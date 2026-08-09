import AppKit
import CoreGraphics

public protocol CursorLocationProviding: AnyObject {
    func currentLocation() -> CGPoint
}

public protocol DisplayGeometryProviding: AnyObject {
    func visibleFrame(containing point: CGPoint) -> CGRect?
    func screenFrames() -> [CGRect]
}

public final class DisplayGeometryService: CursorLocationProviding, DisplayGeometryProviding {
    public init() {}

    public func currentLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    public func visibleFrame(containing point: CGPoint) -> CGRect? {
        let convertedScreens = convertedScreenFrames()
        guard !convertedScreens.isEmpty else { return nil }
        let selected = convertedScreens.first(where: { $0.frame.contains(point) })
            ?? convertedScreens.first(where: { $0.isMain })
            ?? convertedScreens[0]
        return selected.visibleFrame.insetBy(dx: 24, dy: 24)
    }

    public func screenFrames() -> [CGRect] {
        convertedScreenFrames().map(\.frame)
    }

    private func convertedScreenFrames() -> [(frame: CGRect, visibleFrame: CGRect, isMain: Bool)] {
        let screens = NSScreen.screens
        let primaryMaxY = ScreenCoordinateConverter.primaryScreenMaxY(
            fromAppKitScreenFrames: screens.map(\.frame)
        )
        let converter = ScreenCoordinateConverter(primaryScreenMaxY: primaryMaxY)
        return screens.map { screen in
            (
                frame: converter.coreGraphicsRect(fromAppKit: screen.frame),
                visibleFrame: converter.coreGraphicsRect(fromAppKit: screen.visibleFrame),
                isMain: screen == NSScreen.main
            )
        }
    }
}
