import CoreGraphics

public struct HUDMessage: Equatable, Sendable {
    public let title: String
    public let subtitle: String?

    public init(title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }
}

public enum HUDPresentation {
    public static func message(isActive: Bool) -> HUDMessage {
        HUDMessage(title: isActive ? "Drift Active" : "Drift Inactive", subtitle: nil)
    }

    public static func screen(containing point: CGPoint, in screens: [CGRect]) -> CGRect? {
        screens.first(where: { $0.contains(point) }) ?? screens.first
    }
}

@MainActor
public protocol HUDPresenting: AnyObject {
    func show(_ message: HUDMessage)
    func dismiss()
}

@MainActor
public final class NullHUDPresenter: HUDPresenting {
    public init() {}
    public func show(_ message: HUDMessage) {}
    public func dismiss() {}
}
