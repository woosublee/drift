import Foundation

public protocol TickScheduling: AnyObject {
    func start(_ onTick: @escaping (Date) -> Void)
    func stop()
}

public final class TickScheduler: TickScheduling {
    private var timer: Timer?

    public init() {}

    public func start(_ onTick: @escaping (Date) -> Void) {
        stop()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            onTick(Date())
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
