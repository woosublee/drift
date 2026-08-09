import Foundation

public protocol DriftRandomSource: AnyObject {
    func double(in range: ClosedRange<Double>) -> Double
    func int(in range: ClosedRange<Int>) -> Int
}

public final class SystemDriftRandomSource: DriftRandomSource {
    public init() {}

    public func double(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range)
    }

    public func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range)
    }
}
