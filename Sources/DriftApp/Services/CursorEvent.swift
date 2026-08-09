import CoreGraphics
import DriftCore

public enum DriftSyntheticEventTag {
    public static let value: Int64 = 0x4452494654
}

public enum CursorEvent: Equatable {
    case move(to: CGPoint)
    case mouseDown(button: MouseButton, at: CGPoint)
    case mouseUp(button: MouseButton, at: CGPoint)
}

public enum CursorEventServiceError: Error, Equatable {
    case sequenceAlreadyRunning
    case eventCreationFailed
    case eventPostFailed
    case cancelled
}

public protocol CursorEventSink: AnyObject {
    func post(_ event: CursorEvent) -> Bool
}

public protocol MicrosecondSleeping: AnyObject {
    func sleep(microseconds: UInt32)
}

public protocol MotionExecuting: AnyObject {
    func execute(_ plan: MotionPlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void)
    func execute(_ sequence: ClickSequencePlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void)
    func cancel()
}
