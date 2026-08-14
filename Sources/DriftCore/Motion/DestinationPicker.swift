import CoreGraphics

public struct DestinationPicker {
    public init() {}

    public func pick(in bounds: CGRect, random: DriftRandomSource) -> CGPoint {
        randomPoint(in: bounds, random: random)
    }

    public func pick(
        in bounds: CGRect,
        avoiding point: CGPoint,
        minimumDistance: CGFloat,
        random: DriftRandomSource
    ) -> CGPoint {
        for _ in 0..<8 {
            let candidate = randomPoint(in: bounds, random: random)
            if hypot(candidate.x - point.x, candidate.y - point.y) >= minimumDistance {
                return candidate
            }
        }
        return [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        ].max { lhs, rhs in
            hypot(lhs.x - point.x, lhs.y - point.y)
                < hypot(rhs.x - point.x, rhs.y - point.y)
        } ?? point
    }

    private func randomPoint(in bounds: CGRect, random: DriftRandomSource) -> CGPoint {
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
