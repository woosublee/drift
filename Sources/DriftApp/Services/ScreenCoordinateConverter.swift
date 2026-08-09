import CoreGraphics

public struct ScreenCoordinateConverter: Sendable {
    public let primaryScreenMaxY: CGFloat

    public init(primaryScreenMaxY: CGFloat) {
        self.primaryScreenMaxY = primaryScreenMaxY
    }

    public static func primaryScreenMaxY(fromAppKitScreenFrames frames: [CGRect]) -> CGFloat {
        frames.first?.maxY ?? 0
    }

    public func coreGraphicsPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    public func coreGraphicsRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
