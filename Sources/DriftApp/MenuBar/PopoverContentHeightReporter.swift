import AppKit
import SwiftUI

extension View {
    func reportPopoverContentHeight(
        _ onChange: @escaping (CGFloat) -> Void
    ) -> some View {
        background(PopoverContentHeightReportingView(onChange: onChange))
    }
}

private struct PopoverContentHeightReportingView: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> PopoverContentHeightReportingNSView {
        PopoverContentHeightReportingNSView(onChange: onChange)
    }

    func updateNSView(
        _ nsView: PopoverContentHeightReportingNSView,
        context: Context
    ) {
        nsView.onChange = onChange
    }
}

private final class PopoverContentHeightReportingNSView: NSView {
    var onChange: (CGFloat) -> Void

    init(onChange: @escaping (CGFloat) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        onChange(bounds.height)
    }
}
