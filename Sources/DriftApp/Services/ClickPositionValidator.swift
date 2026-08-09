import CoreGraphics
import DriftCore

public protocol ClickPositionValidating {
    func isValid(_ position: ClickPosition, in screenFrames: [CGRect]) -> Bool
}

public struct ClickPositionValidator: ClickPositionValidating {
    public init() {}

    public func isValid(_ position: ClickPosition, in screenFrames: [CGRect]) -> Bool {
        let point = CGPoint(x: position.x, y: position.y)
        return screenFrames.contains { $0.contains(point) }
    }
}
