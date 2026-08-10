import AppKit
import SwiftUI
import DriftCore

struct MotionToggleSettingsCard: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        DriftSettingsCard {
            DriftToggleSettingRow(title, isOn: $isOn)
        }
    }
}

struct MovementSettingsCard: View {
    @Binding var startDelay: StartDelay
    @Binding var repeatInterval: RepeatInterval

    var body: some View {
        DriftSettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                DriftSettingRow("Start Moving After") {
                    DriftMenuPicker(
                        selection: $startDelay,
                        options: StartDelay.allCases,
                        label: { $0.popoverLabel },
                        accessibilityLabel:
                            DriftPopoverPresentation.startMovingAfterAccessibilityLabel
                    )
                    .driftMenuControlWidth()
                }
                Divider()
                DriftSettingRow("Move Every") {
                    DriftMenuPicker(
                        selection: $repeatInterval,
                        options: RepeatInterval.allCases,
                        label: { $0.popoverLabel },
                        accessibilityLabel:
                            DriftPopoverPresentation.moveEveryAccessibilityLabel
                    )
                    .driftMenuControlWidth()
                }
            }
        }
    }
}

struct ClickingSettingsCard: View {
    @Binding var clickMode: ClickMode
    let positionLabel: String
    let positionIsInvalid: Bool
    let isSelecting: Bool
    let hasPosition: Bool
    let errorMessage: String?
    let selectPosition: () -> Void
    let clearPosition: () -> Void

    var body: some View {
        DriftSettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                DriftSettingRow("Click Mode") {
                    DriftMenuPicker(
                        selection: $clickMode,
                        options: ClickMode.allCases,
                        label: { $0.popoverLabel },
                        accessibilityLabel:
                            DriftPopoverPresentation.clickModeAccessibilityLabel
                    )
                    .driftMenuControlWidth()
                }
                Divider()
                DriftSettingRow("Click Position") {
                    Text(positionLabel)
                        .foregroundStyle(positionIsInvalid ? Color.red : Color.secondary)
                }
                VStack(alignment: .leading, spacing: DriftPopoverMetrics.fullWidthBlockSpacing) {
                    Button(action: selectPosition) {
                        Text(isSelecting ? "Selecting…" : "Select Position…")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSelecting)
                    if hasPosition {
                        Button(action: clearPosition) {
                            Text("Clear Position")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                    }
                    if let errorMessage {
                        DriftInlineMessage(text: errorMessage, tone: .error)
                    }
                }
                .padding(.top, DriftPopoverMetrics.fullWidthBlockSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct StopConditionsSettingsCard: View {
    let dailyStop: DailyStopSettings
    let batteryStop: BatteryStopSettings
    let setDailyStop: (DailyStopSettings) -> Void
    let setBatteryStop: (BatteryStopSettings) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DriftSettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                DriftToggleSettingRow("Deactivate At", isOn: dailyStopEnabled)
                if DriftPopoverPresentation.showsDailyStopDetails(for: dailyStop) {
                    Divider()
                    DriftSettingRow("Time") {
                        DatePicker(
                            "",
                            selection: dailyStopTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .accessibilityLabel(
                            DriftPopoverPresentation.deactivateAtTimeAccessibilityLabel
                        )
                        .driftMenuControlWidth()
                    }
                    Divider()
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { weekday in
                            let isSelected = dailyStop.weekdays.contains(weekday)
                            Button(DriftPopoverPresentation.weekdayLabel(weekday)) {
                                toggleWeekday(weekday)
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelected ? .accentColor : .gray)
                            .accessibilityLabel(
                                DriftPopoverPresentation.weekdayAccessibilityLabel(weekday)
                            )
                            .accessibilityValue(
                                DriftPopoverPresentation.weekdayAccessibilityValue(
                                    isSelected: isSelected
                                )
                            )
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Divider()
                DriftToggleSettingRow("Battery Level", isOn: batteryStopEnabled)
                if DriftPopoverPresentation.showsBatteryStopDetails(for: batteryStop) {
                    Divider()
                    DriftSettingRow("Battery Threshold") {
                        HStack(spacing: DriftPopoverMetrics.fullWidthBlockSpacing) {
                            Text("\(batteryStop.thresholdPercent)%")
                                .accessibilityHidden(true)
                            Stepper(
                                "",
                                value: batteryThreshold,
                                in: 5...50,
                                step: 5
                            )
                            .labelsHidden()
                            .accessibilityLabel("Battery Level Threshold")
                            .accessibilityValue(
                                "\(batteryStop.thresholdPercent) percent"
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.16),
            value: dailyStop.isEnabled
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.16),
            value: batteryStop.isEnabled
        )
    }

    private var dailyStopEnabled: Binding<Bool> {
        Binding(
            get: { dailyStop.isEnabled },
            set: { enabled in
                var value = dailyStop
                value.isEnabled = enabled
                setDailyStop(value)
            }
        )
    }

    private var dailyStopTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.year = 2001
                components.month = 1
                components.day = 1
                components.hour = dailyStop.hour
                components.minute = dailyStop.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                var value = dailyStop
                value.hour = components.hour ?? value.hour
                value.minute = components.minute ?? value.minute
                setDailyStop(value)
            }
        )
    }

    private var batteryStopEnabled: Binding<Bool> {
        Binding(
            get: { batteryStop.isEnabled },
            set: { enabled in
                var value = batteryStop
                value.isEnabled = enabled
                setBatteryStop(value)
            }
        )
    }

    private var batteryThreshold: Binding<Int> {
        Binding(
            get: { batteryStop.thresholdPercent },
            set: { threshold in
                var value = batteryStop
                value.thresholdPercent = threshold
                setBatteryStop(value)
            }
        )
    }

    private func toggleWeekday(_ weekday: Int) {
        var value = dailyStop
        if value.weekdays.contains(weekday) {
            value.weekdays.remove(weekday)
        } else {
            value.weekdays.insert(weekday)
        }
        setDailyStop(value)
    }
}

struct BehaviorSettingsCard: View {
    @Binding var launchAtLogin: Bool
    @ObservedObject var recorder: ShortcutRecorderModel
    let errorMessage: String?

    var body: some View {
        DriftSettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                DriftToggleSettingRow("Launch at Login", isOn: $launchAtLogin)
                Divider()
                VStack(alignment: .leading, spacing: DriftPopoverMetrics.fullWidthBlockSpacing) {
                    ShortcutRecorderView(recorder: recorder)
                    if let errorMessage {
                        DriftInlineMessage(text: errorMessage, tone: .error)
                    }
                }
                .padding(.top, DriftPopoverMetrics.fullWidthBlockSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct AccessibilitySettingsCard: View {
    let isTrusted: Bool
    let openSystemSettings: () -> Void

    var body: some View {
        DriftSettingsCard {
            VStack(alignment: .leading, spacing: DriftPopoverMetrics.fullWidthBlockSpacing) {
                HStack(spacing: DriftPopoverMetrics.fullWidthBlockSpacing) {
                    Image(
                        systemName: isTrusted
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isTrusted ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                    Text(
                        isTrusted
                            ? "Accessibility Ready"
                            : "Accessibility access is required to move or click the pointer."
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !isTrusted {
                    Button(action: openSystemSettings) {
                        Text("Open System Settings")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ApplicationSettingsCard: View {
    @ObservedObject var updateService: UpdateService
    let quitTitle: String
    let versionText: String
    let errorMessage: String?

    var body: some View {
        DriftSettingsCard {
            VStack(alignment: .leading, spacing: DriftPopoverMetrics.fullWidthBlockSpacing) {
                Button {
                    updateService.checkForUpdates()
                } label: {
                    Text("Check for Updates…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!UpdatePresentation.checkButtonEnabled(
                    isConfigured: updateService.isConfigured,
                    canCheck: updateService.canCheckForUpdates
                ))

                if let status = UpdatePresentation.statusMessage(
                    isConfigured: updateService.isConfigured,
                    canCheck: updateService.canCheckForUpdates,
                    serviceMessage: updateService.statusMessage
                ) {
                    DriftInlineMessage(
                        text: status,
                        tone: UpdatePresentation.statusTone(
                            isConfigured: updateService.isConfigured,
                            serviceMessage: updateService.statusMessage
                        )
                    )
                }

                if let errorMessage {
                    DriftInlineMessage(text: errorMessage, tone: .error)
                }

                Divider()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text(quitTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
