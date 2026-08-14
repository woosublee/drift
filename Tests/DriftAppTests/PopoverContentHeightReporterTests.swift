import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DriftApp

@MainActor
final class PopoverContentHeightReporterTests: XCTestCase {
    func testScrollableContentReportsExpansionBeyondCurrentViewport() throws {
        let model = ExpandablePopoverModel()
        let collapsedExpectation = expectation(
            description: "Reports collapsed content height"
        )
        let expandedExpectation = expectation(
            description: "Reports expanded content height"
        )
        var reportedCollapsedHeight: CGFloat?
        var reportedExpandedHeight: CGFloat?
        let controller = NSHostingController(
            rootView: ExpandableScrollablePopoverContent(
                model: model,
                onContentHeightChange: { height in
                    if model.isExpanded {
                        guard reportedExpandedHeight == nil,
                              height > (reportedCollapsedHeight ?? 0) else {
                            return
                        }
                        reportedExpandedHeight = height
                        expandedExpectation.fulfill()
                    } else if reportedCollapsedHeight == nil {
                        reportedCollapsedHeight = height
                        collapsedExpectation.fulfill()
                    }
                }
            )
        )
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 240, height: 80))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        controller.view.layoutSubtreeIfNeeded()
        wait(for: [collapsedExpectation], timeout: 1)

        model.isExpanded = true
        controller.view.layoutSubtreeIfNeeded()
        wait(for: [expandedExpectation], timeout: 1)

        let collapsedHeight = try XCTUnwrap(reportedCollapsedHeight)
        let expandedHeight = try XCTUnwrap(reportedExpandedHeight)
        XCTAssertGreaterThan(expandedHeight, collapsedHeight)
        XCTAssertGreaterThan(expandedHeight, controller.view.frame.height)
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
