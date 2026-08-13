import CoreGraphics

public struct ClickSequencePlanner {
    private let pathGenerator: MotionPathGenerator

    public init(pathGenerator: MotionPathGenerator = MotionPathGenerator()) {
        self.pathGenerator = pathGenerator
    }

    public func makePlan(
        isSmartMotionEnabled: Bool,
        clickMode: ClickMode,
        nextAlternatingButton: MouseButton,
        start: CGPoint,
        clickPosition: CGPoint,
        departurePosition: CGPoint,
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

        let holdMicroseconds: UInt32 = isSmartMotionEnabled
            ? UInt32(random.int(in: 50_000...200_000))
            : 0
        let outbound = pathGenerator.makePlan(
            isSilentModeEnabled: false,
            isSmartMotionEnabled: isSmartMotionEnabled,
            start: start,
            destination: clickPosition,
            bounds: bounds,
            random: random
        )
        let returnPlan = pathGenerator.makePlan(
            isSilentModeEnabled: false,
            isSmartMotionEnabled: isSmartMotionEnabled,
            start: clickPosition,
            destination: departurePosition,
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
