import CoreGraphics

public struct ClickSequencePlanner {
    private let pathGenerator: MotionPathGenerator

    public init(pathGenerator: MotionPathGenerator = MotionPathGenerator()) {
        self.pathGenerator = pathGenerator
    }

    public func makePlan(
        motionMode: MotionMode,
        clickMode: ClickMode,
        nextAlternatingButton: MouseButton,
        start: CGPoint,
        clickPosition: CGPoint,
        bounds: CGRect,
        random: DriftRandomSource
    ) -> ClickSequencePlan? {
        let button: MouseButton
        switch clickMode {
        case .none:
            return nil
        case .left:
            button = .left
        case .right:
            button = .right
        case .alternating:
            button = nextAlternatingButton
        }

        let pathMode: MotionMode = motionMode == .silent ? .standard : motionMode
        let holdMicroseconds: UInt32 = motionMode == .natural
            ? UInt32(random.int(in: 50_000...200_000))
            : 0
        let outbound = pathGenerator.makePlan(
            mode: pathMode,
            start: start,
            destination: clickPosition,
            bounds: bounds,
            random: random
        )
        let returnPlan = pathGenerator.makePlan(
            mode: pathMode,
            start: clickPosition,
            destination: start,
            bounds: bounds,
            random: random
        )
        return ClickSequencePlan(
            outbound: outbound,
            button: button,
            position: clickPosition,
            holdMicroseconds: holdMicroseconds,
            returnPlan: returnPlan
        )
    }
}
