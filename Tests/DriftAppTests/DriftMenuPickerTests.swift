import AppKit
import SwiftUI
import XCTest
@testable import DriftApp

@MainActor
final class DriftMenuPickerTests: XCTestCase {
    func testNativePopupButtonUsesExactVisibleWidthAndAccessibilityLabel() throws {
        let selection = MenuSelectionBox("Short")
        let hostingView = makeHostingView(selection: selection)

        let popUpButton = try XCTUnwrap(
            firstSubview(of: NSPopUpButton.self, in: hostingView)
        )

        XCTAssertEqual(
            popUpButton.frame.width,
            DriftPopoverMetrics.menuControlWidth,
            accuracy: 0.5
        )
        XCTAssertEqual(popUpButton.accessibilityLabel(), "Test Menu")
    }

    func testNativePopupButtonWritesSelectedOptionThroughBinding() throws {
        let selection = MenuSelectionBox("Short")
        let hostingView = makeHostingView(selection: selection)
        let popUpButton = try XCTUnwrap(
            firstSubview(of: NSPopUpButton.self, in: hostingView)
        )

        popUpButton.selectItem(at: 1)
        _ = popUpButton.sendAction(popUpButton.action, to: popUpButton.target)

        XCTAssertEqual(selection.value, "A Much Longer Value")
    }

    private func makeHostingView(
        selection: MenuSelectionBox
    ) -> NSHostingView<some View> {
        let picker = DriftMenuPicker(
            selection: Binding(
                get: { selection.value },
                set: { selection.value = $0 }
            ),
            options: ["Short", "A Much Longer Value"],
            label: { $0 },
            accessibilityLabel: "Test Menu"
        )
        .frame(width: DriftPopoverMetrics.menuControlWidth)

        let hostingView = NSHostingView(rootView: picker)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: DriftPopoverMetrics.menuControlWidth,
            height: 40
        )
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    private func firstSubview<ViewType: NSView>(
        of type: ViewType.Type,
        in root: NSView
    ) -> ViewType? {
        if let match = root as? ViewType {
            return match
        }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }
}

private final class MenuSelectionBox {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}
