import Foundation
import SwiftUI
import DriftCore

private struct DriftPopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        DriftPopoverAppearance.makeMaterialView()
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@MainActor
struct DriftPopoverView: View {
    @ObservedObject var model: DriftAppModel
    @ObservedObject var updateService: UpdateService
    let identity: AppIdentity
    let versionText: String
    let onContentHeightChange: (CGFloat) -> Void
    @StateObject private var recorder: ShortcutRecorderModel

    init(
        model: DriftAppModel,
        updateService: UpdateService,
        identity: AppIdentity = .current,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        self.updateService = updateService
        self.identity = identity
        self.onContentHeightChange = onContentHeightChange
        versionText = DriftPopoverPresentation.versionText(
            displayName: identity.displayName,
            infoDictionary: infoDictionary
        )
        _recorder = StateObject(
            wrappedValue: ShortcutRecorderModel(
                shortcut: model.settings.toggleShortcut
            ) { shortcut in
                model.setToggleShortcut(shortcut)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DriftPopoverMetrics.cardSpacing) {
                DriftStatusCard(
                    displayName: identity.displayName,
                    status: DriftPopoverPresentation.status(
                        isActiveIntent: model.isActiveIntent,
                        phase: model.phase
                    ),
                    shortcutLabel: DriftPopoverPresentation.shortcutLabel(
                        model.settings.toggleShortcut
                    ),
                    isActive: activeBinding
                )

                MotionToggleSettingsCard(
                    title: DriftPopoverPresentation.smartMotionAccessibilityLabel,
                    helpText: DriftPopoverPresentation.smartMotionHelpText,
                    isOn: smartMotionBinding
                )

                MotionToggleSettingsCard(
                    title: DriftPopoverPresentation.silentModeAccessibilityLabel,
                    helpText: DriftPopoverPresentation.silentModeHelpText,
                    isOn: silentModeBinding
                )

                MovementSettingsCard(
                    startDelay: startDelayBinding,
                    repeatInterval: repeatIntervalBinding
                )

                ClickingSettingsCard(
                    clickMode: clickModeBinding,
                    positionLabel: DriftPopoverPresentation.clickPositionLabel(
                        position: model.settings.clickPosition,
                        isValid: model.isClickPositionValid
                    ),
                    positionIsInvalid: model.settings.clickPosition != nil && !model.isClickPositionValid,
                    isSelecting: model.isSelectingClickPosition,
                    hasPosition: model.settings.clickPosition != nil,
                    errorMessage: errorMessage(for: .clicking),
                    selectPosition: model.selectClickPosition,
                    clearPosition: model.clearClickPosition
                )

                StopConditionsSettingsCard(
                    dailyStop: model.settings.dailyStop,
                    batteryStop: model.settings.batteryStop,
                    setDailyStop: model.setDailyStop,
                    setBatteryStop: model.setBatteryStop
                )

                BehaviorSettingsCard(
                    launchAtLogin: launchAtLoginBinding,
                    recorder: recorder,
                    errorMessage: DriftPopoverPresentation.behaviorErrorMessage(
                        genericError: errorMessage(for: .behavior),
                        shortcutError: model.shortcutRegistrationError
                    )
                )

                AccessibilitySettingsCard(
                    isTrusted: model.isAccessibilityTrusted,
                    openSystemSettings: model.openAccessibilitySettings
                )

                ApplicationFooter(
                    updateService: updateService,
                    quitTitle: identity.quitTitle,
                    versionText: versionText,
                    errorMessage: errorMessage(for: .application)
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DriftPopoverMetrics.contentHorizontalPadding)
            .padding(.vertical, DriftPopoverMetrics.contentVerticalPadding)
            .reportPopoverContentHeight(onContentHeightChange)
        }
        .scrollIndicators(.automatic)
        .frame(width: DriftPopoverMetrics.contentWidth)
        .background(DriftPopoverMaterial())
    }

    private func errorMessage(for section: DriftPopoverSection) -> String? {
        guard DriftPopoverPresentation.errorSection(for: model.lastError) == section else {
            return nil
        }
        return model.lastError
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { model.isActiveIntent },
            set: { isActive in
                if isActive != model.isActiveIntent {
                    model.toggleActive()
                }
            }
        )
    }

    private var startDelayBinding: Binding<StartDelay> {
        Binding(get: { model.settings.startDelay }, set: { model.setStartDelay($0) })
    }

    private var repeatIntervalBinding: Binding<RepeatInterval> {
        Binding(get: { model.settings.repeatInterval }, set: { model.setRepeatInterval($0) })
    }

    private var smartMotionBinding: Binding<Bool> {
        Binding(
            get: { model.settings.isSmartMotionEnabled },
            set: { model.setSmartMotionEnabled($0) }
        )
    }

    private var silentModeBinding: Binding<Bool> {
        Binding(
            get: { model.settings.isSilentModeEnabled },
            set: { model.setSilentModeEnabled($0) }
        )
    }

    private var clickModeBinding: Binding<ClickMode> {
        Binding(get: { model.settings.clickMode }, set: { try? model.setClickMode($0) })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
    }
}
