import AppKit
import DriftCore

@MainActor
final class ClickPositionOverlayView: NSView {
    private let converter: ScreenCoordinateConverter
    private let onSelect: (ClickPosition) -> Void

    init(converter: ScreenCoordinateConverter, onSelect: @escaping (ClickPosition) -> Void) {
        self.converter = converter
        self.onSelect = onSelect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor

        let instruction = NSTextField(labelWithString: "Click anywhere to save the position")
        instruction.font = .systemFont(ofSize: 18, weight: .semibold)
        instruction.textColor = .white
        instruction.alignment = .center
        instruction.translatesAutoresizingMaskIntoConstraints = false
        addSubview(instruction)
        NSLayoutConstraint.activate([
            instruction.centerXAnchor.constraint(equalTo: centerXAnchor),
            instruction.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let appKitGlobalPoint = window.convertPoint(toScreen: event.locationInWindow)
        let coreGraphicsPoint = converter.coreGraphicsPoint(fromAppKit: appKitGlobalPoint)
        onSelect(ClickPosition(x: coreGraphicsPoint.x, y: coreGraphicsPoint.y))
    }
}
