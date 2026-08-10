import CoreGraphics

public struct MotionPathGenerator {
    public init() {}

    public func makePlan(
        isSilentModeEnabled: Bool,
        isSmartMotionEnabled: Bool,
        start: CGPoint,
        destination: CGPoint,
        bounds: CGRect,
        random: DriftRandomSource
    ) -> MotionPlan {
        if isSilentModeEnabled {
            return silentPlan(start: start)
        }
        if isSmartMotionEnabled {
            return naturalPlan(start: start, destination: destination, bounds: bounds, random: random)
        }
        return standardPlan(start: start, destination: destination, bounds: bounds)
    }

    private func silentPlan(start: CGPoint) -> MotionPlan {
        MotionPlan(samples: [
            MotionSample(point: CGPoint(x: start.x + 0.01, y: start.y), delayAfterMicroseconds: 16_667),
            MotionSample(point: start, delayAfterMicroseconds: 16_667)
        ])
    }

    private func standardPlan(start: CGPoint, destination: CGPoint, bounds: CGRect) -> MotionPlan {
        let samples = (1...6).map { index -> MotionSample in
            let point = clamp(interpolate(start: start, end: destination, t: CGFloat(index) / 6), to: bounds)
            return MotionSample(point: point, delayAfterMicroseconds: index == 6 ? 0 : 16_667)
        }
        return MotionPlan(samples: samples)
    }

    private func naturalPlan(
        start: CGPoint,
        destination: CGPoint,
        bounds: CGRect,
        random: DriftRandomSource
    ) -> MotionPlan {
        let duration = random.double(in: 0.7...1.7)
        let sampleCount = min(102, max(42, Int((duration * 60).rounded())))
        let waypointCount = random.int(in: 1...3)
        let segments = waypointCount + 1
        var points = [clamp(start, to: bounds)]

        for index in 1...waypointCount {
            let progress = CGFloat(index) / CGFloat(segments)
            points.append(clamp(interpolate(start: start, end: destination, t: progress), to: bounds))
        }
        points.append(clamp(destination, to: bounds))

        let controls = zip(points, points.dropFirst()).map { start, end in
            clamp(
                CGPoint(
                    x: (start.x + end.x) / 2 + CGFloat(random.double(in: -100...100)),
                    y: (start.y + end.y) / 2 + CGFloat(random.double(in: -100...100))
                ),
                to: bounds
            )
        }

        let samples = (1...sampleCount).map { index -> MotionSample in
            let progress = CGFloat(index) / CGFloat(sampleCount)
            let scaledProgress = progress * CGFloat(segments)
            let segmentIndex = min(segments - 1, Int(scaledProgress))
            let segmentProgress = segmentIndex == segments - 1 && index == sampleCount
                ? 1
                : scaledProgress - CGFloat(segmentIndex)
            let point = clamp(
                quadraticBezier(
                    start: points[segmentIndex],
                    control: controls[segmentIndex],
                    end: points[segmentIndex + 1],
                    t: segmentProgress
                ),
                to: bounds
            )
            var delay = UInt32(random.int(in: 11_667...21_667))
            if index.isMultiple(of: 18) {
                delay += UInt32(random.int(in: 10_000...50_000))
            }
            return MotionSample(point: point, delayAfterMicroseconds: delay)
        }

        return MotionPlan(samples: samples)
    }
}

private func interpolate(start: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
    CGPoint(
        x: start.x + (end.x - start.x) * t,
        y: start.y + (end.y - start.y) * t
    )
}

private func quadraticBezier(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
    let inverse = 1 - t
    return CGPoint(
        x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
        y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
    )
}

private func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
    CGPoint(
        x: min(bounds.maxX, max(bounds.minX, point.x)),
        y: min(bounds.maxY, max(bounds.minY, point.y))
    )
}
