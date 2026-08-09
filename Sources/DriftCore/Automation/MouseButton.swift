public enum MouseButton: String, Codable, Equatable, Sendable {
    case left
    case right

    public var opposite: MouseButton {
        self == .left ? .right : .left
    }
}
