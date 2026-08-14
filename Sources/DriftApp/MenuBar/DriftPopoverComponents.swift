import SwiftUI

struct DriftSettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DriftPopoverMetrics.cardHorizontalInset)
            .padding(.vertical, DriftPopoverMetrics.cardVerticalInset)
            .background(
                RoundedRectangle(
                    cornerRadius: DriftPopoverMetrics.cardCornerRadius,
                    style: .continuous
                )
                .fill(
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(DriftPopoverAppearance.cardBackgroundOpacity)
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: DriftPopoverMetrics.cardCornerRadius,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: .separatorColor)
                        .opacity(DriftPopoverAppearance.cardBorderOpacity),
                    lineWidth: 1
                )
            )
    }
}

private struct DriftMenuControlWidthModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(
            width: DriftPopoverMetrics.menuControlWidth,
            alignment: .trailing
        )
    }
}

extension View {
    func driftMenuControlWidth() -> some View {
        modifier(DriftMenuControlWidthModifier())
    }
}

struct DriftSettingRow<Trailing: View>: View {
    let label: String
    let helpText: String?
    let labelAccessibilityHidden: Bool
    private let trailing: Trailing

    init(
        _ label: String,
        helpText: String? = nil,
        labelAccessibilityHidden: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.label = label
        self.helpText = helpText
        self.labelAccessibilityHidden = labelAccessibilityHidden
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DriftPopoverMetrics.settingColumnGap) {
            HStack(spacing: 4) {
                Text(label)
                    .accessibilityHidden(labelAccessibilityHidden)
                if let helpText {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(helpText)
                        .accessibilityLabel("\(label) Help")
                        .accessibilityHint(helpText)
                }
                Spacer(minLength: 0)
            }
            .frame(
                width: DriftPopoverMetrics.settingLabelWidth,
                alignment: .leading
            )
            .fixedSize(horizontal: false, vertical: true)
            trailing
                .frame(
                    width: DriftPopoverMetrics.settingControlWidth,
                    alignment: .trailing
                )
        }
        .frame(minHeight: DriftPopoverMetrics.standardRowMinHeight)
    }
}

struct DriftToggleSettingRow: View {
    let label: String
    let helpText: String?
    let isOn: Binding<Bool>

    init(_ label: String, helpText: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.helpText = helpText
        self.isOn = isOn
    }

    var body: some View {
        DriftSettingRow(
            label,
            helpText: helpText,
            labelAccessibilityHidden: true
        ) {
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(label)
                .accessibilityHint(helpText ?? "")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct DriftInlineMessage: View {
    let text: String
    let tone: UpdateStatusTone

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tone == .error ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DriftStatusCard: View {
    let displayName: String
    let status: DriftPopoverStatusPresentation
    let shortcutLabel: String
    @Binding var isActive: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.headline)
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(status.label)
                        .font(.subheadline.weight(.semibold))
                    Text(shortcutLabel)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Toggle("Active", isOn: $isActive)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Active")
        }
        .padding(.horizontal, DriftPopoverMetrics.cardHorizontalInset)
        .padding(.vertical, DriftPopoverMetrics.statusCardVerticalInset)
        .background(
            RoundedRectangle(
                cornerRadius: DriftPopoverMetrics.cardCornerRadius,
                style: .continuous
            )
            .fill(statusBackground)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: DriftPopoverMetrics.cardCornerRadius,
                style: .continuous
            )
            .stroke(statusBorder, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch status.tone {
        case .active: .green
        case .inactive: .secondary
        case .warning: .orange
        }
    }

    private var statusBackground: Color {
        switch status.tone {
        case .active:
            Color.accentColor.opacity(DriftPopoverAppearance.statusTintOpacity)
        case .inactive:
            Color(nsColor: .controlBackgroundColor)
                .opacity(DriftPopoverAppearance.cardBackgroundOpacity)
        case .warning:
            Color.orange.opacity(DriftPopoverAppearance.statusTintOpacity)
        }
    }

    private var statusBorder: Color {
        switch status.tone {
        case .active:
            Color.accentColor.opacity(DriftPopoverAppearance.statusBorderOpacity)
        case .inactive:
            Color(nsColor: .separatorColor)
                .opacity(DriftPopoverAppearance.cardBorderOpacity)
        case .warning:
            Color.orange.opacity(DriftPopoverAppearance.statusBorderOpacity)
        }
    }
}
