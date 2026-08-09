import AppKit
import SwiftUI
import DriftCore

struct ShortcutRecorderView: View {
    @ObservedObject var recorder: ShortcutRecorderModel
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: DriftPopoverMetrics.fullWidthBlockSpacing) {
            DriftSettingRow("Toggle Shortcut") {
                HStack(spacing: DriftPopoverMetrics.fullWidthBlockSpacing) {
                    Button(
                        recorder.isRecording
                            ? "Recording…"
                            : DriftPopoverPresentation.shortcutLabel(recorder.shortcut)
                    ) {
                        recorder.begin()
                    }
                    .buttonStyle(.bordered)
                    Button("Clear") {
                        recorder.clear()
                    }
                    .disabled(recorder.shortcut == nil)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if recorder.isRecording {
                Text("Press a shortcut. Escape cancels; Delete clears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if recorder.validationError == .modifierRequired {
                Text("Include Command, Control, Option, or Shift.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard recorder.isRecording else { return event }
            recorder.handle(event: ShortcutRecorderKeyEvent(
                keyCode: UInt32(event.keyCode),
                modifiers: shortcutModifiers(from: event)
            ))
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func shortcutModifiers(from event: NSEvent) -> ShortcutModifiers {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: ShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
