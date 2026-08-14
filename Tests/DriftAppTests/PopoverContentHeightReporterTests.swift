import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DriftApp

@MainActor
final class PopoverContentHeightReporterTests: XCTestCase {
    func testScrollableContentReportsExpansionBeyondCurrentViewport() {
        let model = ExpandablePopoverModel()
        var reportedHeights: [CGFloat] = []
        let controller = NSHostingController(
            rootView: ExpandableScrollablePopoverContent(
                model: model,
                onContentHeightChange: { reportedHeights.append($0) }
            )
        )
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 240, height: 80))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        controller.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let collapsedHeight = try? XCTUnwrap(reportedHeights.last)

        model.isExpanded = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        controller.view.layoutSubtreeIfNeeded()

        let expandedHeight = try? XCTUnwrap(reportedHeights.last)
        XCTAssertNotNil(collapsedHeight)
        XCTAssertNotNil(expandedHeight)
        XCTAssertGreaterThan(expandedHeight ?? 0, collapsedHeight ?? 0)
        XCTAssertGreaterThan(expandedHeight ?? 0, controller.view.frame.height)
    }
}

@MainActor
private final class ExpandablePopoverModel: ObservableObject {
    @Published var isExpanded = false
}

private struct ExpandablePopoverContent: View {
    @ObservedObject var model: ExpandablePopoverModel

    var body: some View {
        VStack {
            Text("Header")
            if model.isExpanded {
                ForEach(0..<8, id: \.self) { index in
                    Text("Expanded row \(index)")
                }
            }
        }
        .frame(width: 240)
    }
}

private struct ExpandableScrollablePopoverContent: View {
    @ObservedObject var model: ExpandablePopoverModel
    let onContentHeightChange: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            ExpandablePopoverContent(model: model)
                .reportPopoverContentHeight(onContentHeightChange)
        }
        .frame(width: 240, height: 80)
    }
}
