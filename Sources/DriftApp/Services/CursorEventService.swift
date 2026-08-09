import Foundation
import DriftCore

public final class CursorEventService: MotionExecuting {
    private let sink: CursorEventSink
    private let sleeper: MicrosecondSleeping
    private let queue = DispatchQueue(label: "com.woosublee.Drift.cursor-events")
    private let queueSpecificKey = DispatchSpecificKey<Void>()
    private let lock = NSLock()
    private var isRunning = false
    private var isCancelled = false

    public init(sink: CursorEventSink, sleeper: MicrosecondSleeping) {
        self.sink = sink
        self.sleeper = sleeper
        queue.setSpecific(key: queueSpecificKey, value: ())
    }

    public func execute(
        _ plan: MotionPlan,
        completion: @escaping (Result<Void, CursorEventServiceError>) -> Void
    ) {
        begin(completion: completion) { [self] in
            for sample in plan.samples {
                try checkCancellation()
                try post(.move(to: sample.point))
                if sample.delayAfterMicroseconds > 0 {
                    try cancellableSleep(microseconds: sample.delayAfterMicroseconds)
                }
            }
        }
    }

    public func execute(
        _ sequence: ClickSequencePlan,
        completion: @escaping (Result<Void, CursorEventServiceError>) -> Void
    ) {
        begin(completion: completion) { [self] in
            var buttonIsDown = false
            defer {
                if buttonIsDown {
                    _ = sink.post(.mouseUp(button: sequence.button, at: sequence.position))
                }
            }

            for sample in sequence.outbound.samples {
                try checkCancellation()
                try post(.move(to: sample.point))
                if sample.delayAfterMicroseconds > 0 {
                    try cancellableSleep(microseconds: sample.delayAfterMicroseconds)
                }
            }
            try checkCancellation()
            try post(.mouseDown(button: sequence.button, at: sequence.position))
            buttonIsDown = true

            if sequence.holdMicroseconds > 0 {
                try cancellableSleep(microseconds: sequence.holdMicroseconds)
            }
            try checkCancellation()
            try post(.mouseUp(button: sequence.button, at: sequence.position))
            buttonIsDown = false

            try checkCancellation()
            for sample in sequence.returnPlan.samples {
                try checkCancellation()
                try post(.move(to: sample.point))
                if sample.delayAfterMicroseconds > 0 {
                    try cancellableSleep(microseconds: sample.delayAfterMicroseconds)
                }
            }
        }
    }

    public func cancel() {
        lock.lock()
        if isRunning {
            isCancelled = true
        }
        lock.unlock()
    }

    public func cancelAndWait() {
        cancel()
        guard DispatchQueue.getSpecific(key: queueSpecificKey) == nil else { return }
        queue.sync {}
    }

    public var isExecuting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    private func begin(
        completion: @escaping (Result<Void, CursorEventServiceError>) -> Void,
        operation: @escaping () throws -> Void
    ) {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            DispatchQueue.main.async {
                completion(.failure(.sequenceAlreadyRunning))
            }
            return
        }
        isRunning = true
        isCancelled = false
        lock.unlock()

        queue.async { [self] in
            let result: Result<Void, CursorEventServiceError>
            do {
                try operation()
                result = .success(())
            } catch let error as CursorEventServiceError {
                result = .failure(error)
            } catch {
                result = .failure(.eventPostFailed)
            }
            lock.lock()
            isRunning = false
            lock.unlock()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func post(_ event: CursorEvent) throws {
        guard sink.post(event) else {
            throw CursorEventServiceError.eventPostFailed
        }
    }

    private func cancellableSleep(microseconds: UInt32) throws {
        var remaining = microseconds
        while remaining > 0 {
            try checkCancellation()
            let chunk = min(remaining, 5_000)
            sleeper.sleep(microseconds: chunk)
            remaining -= chunk
        }
        try checkCancellation()
    }

    private func checkCancellation() throws {
        if cancelled {
            throw CursorEventServiceError.cancelled
        }
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }
}
