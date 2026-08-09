import CoreGraphics

public struct DestinationPicker {
    public init() {}

    public func pick(in bounds: CGRect, random: DriftRandomSource) -> CGPoint {
        let point = CGPoint(
            x: random.double(in: bounds.minX...bounds.maxX),
            y: random.double(in: bounds.minY...bounds.maxY)
        )
        return CGPoint(
            x: min(bounds.maxX, max(bounds.minX, point.x)),
            y: min(bounds.maxY, max(bounds.minY, point.y))
        )
    }
}
