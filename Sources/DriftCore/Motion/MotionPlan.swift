import CoreGraphics

public struct MotionSample: Equatable, Sendable {
    public let point: CGPoint
    public let delayAfterMicroseconds: UInt32

    public init(point: CGPoint, delayAfterMicroseconds: UInt32) {
        self.point = point
        self.delayAfterMicroseconds = delayAfterMicroseconds
    }
}

public struct MotionPlan: Equatable, Sendable {
    public let samples: [MotionSample]

    public init(samples: [MotionSample]) {
        self.samples = samples
    }
}
