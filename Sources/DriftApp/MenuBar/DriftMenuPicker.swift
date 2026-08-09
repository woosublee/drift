import AppKit
import SwiftUI

@MainActor
struct DriftMenuPicker<Option: Hashable>: NSViewRepresentable {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, options: options)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionDidChange(_:))
        button.setAccessibilityLabel(accessibilityLabel)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let titles = options.map(label)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }

        context.coordinator.selection = $selection
        context.coordinator.options = options
        button.setAccessibilityLabel(accessibilityLabel)

        if let selectedIndex = options.firstIndex(of: selection) {
            button.selectItem(at: selectedIndex)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Option>
        var options: [Option]

        init(selection: Binding<Option>, options: [Option]) {
            self.selection = selection
            self.options = options
        }

        @objc func selectionDidChange(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard options.indices.contains(index) else { return }
            selection.wrappedValue = options[index]
        }
    }
}
