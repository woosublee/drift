import CoreGraphics

public struct ClickSequencePlan: Equatable, Sendable {
    public let outbound: MotionPlan
    public let button: MouseButton
    public let position: CGPoint
    public let holdMicroseconds: UInt32
    public let returnPlan: MotionPlan

    public init(
        outbound: MotionPlan,
        button: MouseButton,
        position: CGPoint,
        holdMicroseconds: UInt32,
        returnPlan: MotionPlan
    ) {
        self.outbound = outbound
        self.button = button
        self.position = position
        self.holdMicroseconds = holdMicroseconds
        self.returnPlan = returnPlan
    }
}
