import AppKit
import Foundation
import DriftCore

public enum DriftPopoverSection: CaseIterable, Equatable {
    case status
    case smartMotion
    case silentMode
    case movement
    case clicking
    case stopConditions
    case behavior
    case accessibility
    case application
}

public enum DriftPopoverStatusTone: Equatable {
    case active
    case inactive
    case warning
}

public struct DriftPopoverStatusPresentation: Equatable {
    public let label: String
    public let tone: DriftPopoverStatusTone

    public init(label: String, tone: DriftPopoverStatusTone) {
        self.label = label
        self.tone = tone
    }
}

enum DriftPopoverAppearance {
    static let material = NSVisualEffectView.Material.popover
    static let blendingMode = NSVisualEffectView.BlendingMode.behindWindow
    static let cardBackgroundOpacity = 0.36
    static let cardBorderOpacity = 0.22
    static let statusTintOpacity = 0.10
    static let statusBorderOpacity = 0.32

    static func makeMaterialView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
}

public enum DriftPopoverMetrics {
    public static let contentWidth: CGFloat = 410
    public static let contentHorizontalPadding: CGFloat = 10
    public static let contentVerticalPadding: CGFloat = 8
    public static let cardCornerRadius: CGFloat = 12
    public static let cardSpacing: CGFloat = 8
    public static let cardHorizontalInset: CGFloat = 12
    public static let cardVerticalInset: CGFloat = 10
    public static let statusCardVerticalInset: CGFloat = 10
    public static let cardBodyWidth = contentWidth
        - 2 * contentHorizontalPadding
        - 2 * cardHorizontalInset
    public static let settingLabelWidth: CGFloat = 146
    public static let settingColumnGap: CGFloat = 10
    public static let settingControlWidth = cardBodyWidth
        - settingLabelWidth
        - settingColumnGap
    public static let standardRowMinHeight: CGFloat = 30
    public static let fullWidthBlockSpacing: CGFloat = 6
    public static let menuControlWidth: CGFloat = 112
}

public enum DriftPopoverPresentation {
    public static func status(
        isActiveIntent: Bool,
        phase: DriftPhase
    ) -> DriftPopoverStatusPresentation {
        if phase == .permissionBlocked {
            return DriftPopoverStatusPresentation(
                label: "Accessibility Required",
                tone: .warning
            )
        }
        if isActiveIntent {
            return DriftPopoverStatusPresentation(label: "Active", tone: .active)
        }
        return DriftPopoverStatusPresentation(label: "Inactive", tone: .inactive)
    }

    public static func clickPositionLabel(
        position: ClickPosition?,
        isValid: Bool
    ) -> String {
        guard let position else { return "Not Set" }
        guard isValid else { return "Invalid" }
        return "(\(Int(position.x.rounded())), \(Int(position.y.rounded())))"
    }

    public static func clickPositionControlsEnabled(for mode: ClickMode) -> Bool {
        mode != .none
    }

    public static func showsDailyStopDetails(
        for settings: DailyStopSettings
    ) -> Bool {
        settings.isEnabled
    }

    public static func showsBatteryStopDetails(
        for settings: BatteryStopSettings
    ) -> Bool {
        settings.isEnabled
    }

    public static func shortcutLabel(_ shortcut: GlobalShortcut?) -> String {
        guard let shortcut else { return "Not Set" }
        let modifiers = [
            shortcut.modifiers.contains(.command) ? "⌘" : "",
            shortcut.modifiers.contains(.control) ? "⌃" : "",
            shortcut.modifiers.contains(.option) ? "⌥" : "",
            shortcut.modifiers.contains(.shift) ? "⇧" : ""
        ].joined()
        let key = shortcut.keyCode == 2 ? "D" : "Key \(shortcut.keyCode)"
        return modifiers + key
    }

    public static func versionText(
        displayName: String,
        infoDictionary: [String: Any]
    ) -> String {
        let version = (infoDictionary["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version, !version.isEmpty else { return displayName }
        return "\(displayName) \(version)"
    }

    public static func errorSection(for message: String?) -> DriftPopoverSection? {
        guard let message else { return nil }
        if message == "Invalid click position" {
            return .clicking
        }
        if message.hasPrefix("Launch at Login") || message.hasPrefix("Shortcut") {
            return .behavior
        }
        return .application
    }

    public static let startMovingAfterAccessibilityLabel = "Start Moving After"
    public static let moveEveryAccessibilityLabel = "Move Every"
    public static let smartMotionAccessibilityLabel = "Smart Motion"
    public static let silentModeAccessibilityLabel = "Silent Mode"
    public static let smartMotionHelpText =
        "Uses natural curved paths and varied timing for visible idle movement and travel to and away from clicks. It works independently of Silent Mode."
    public static let silentModeHelpText =
        "When Click Mode is None, Drift sends a tiny 0.01-point out-and-back pointer movement instead of moving across the screen. Click modes still move to the saved position, click, and move away."
    public static let clickModeAccessibilityLabel = "Click Mode"
    public static let deactivateAtTimeAccessibilityLabel = "Deactivate At Time"

    public static func weekdayLabel(_ weekday: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][weekday - 1]
    }

    public static func weekdayAccessibilityLabel(_ weekday: Int) -> String {
        [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ][weekday - 1]
    }

    public static func weekdayAccessibilityValue(isSelected: Bool) -> String {
        isSelected ? "Selected" : "Not selected"
    }

    public static func behaviorErrorMessage(
        genericError: String?,
        shortcutError: GlobalShortcutError?
    ) -> String? {
        if let shortcutError {
            return shortcutErrorMessage(shortcutError)
        }
        return genericError
    }

    private static func shortcutErrorMessage(_ error: GlobalShortcutError) -> String {
        switch error {
        case .registrationFailed:
            "This shortcut is unavailable. Record a different combination."
        }
    }
}

public enum UpdateStatusTone: Equatable {
    case informational
    case error
}

public enum UpdatePresentation {
    public static func checkButtonEnabled(isConfigured: Bool, canCheck: Bool) -> Bool {
        isConfigured && canCheck
    }

    public static func statusMessage(
        isConfigured: Bool,
        canCheck: Bool,
        serviceMessage: String?
    ) -> String? {
        guard isConfigured else { return "Updates aren’t configured for this build." }
        if let serviceMessage { return serviceMessage }
        return canCheck ? nil : "Updates are temporarily unavailable."
    }

    public static func statusTone(
        isConfigured: Bool,
        serviceMessage: String?
    ) -> UpdateStatusTone {
        isConfigured && serviceMessage != nil ? .error : .informational
    }
}

extension StartDelay {
    var popoverLabel: String {
        switch self {
        case .oneMinute: "1 min"
        case .threeMinutes: "3 min"
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        }
    }
}

extension RepeatInterval {
    var popoverLabel: String {
        switch self {
        case .continuous: "Continuous"
        case .fiveSeconds: "5 sec"
        case .tenSeconds: "10 sec"
        case .thirtySeconds: "30 sec"
        case .oneMinute: "1 min"
        case .ninetySeconds: "1.5 min"
        case .twoMinutes: "2 min"
        case .threeMinutes: "3 min"
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        }
    }
}

extension ClickMode {
    var popoverLabel: String { rawValue.capitalized }
}
