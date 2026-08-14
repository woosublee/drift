import AppKit
import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class DriftPopoverPresentationTests: XCTestCase {
    func testSectionOrderPlacesIndependentMotionCardsBeforeMovementSettings() {
        XCTAssertEqual(
            DriftPopoverSection.allCases,
            [.status, .smartMotion, .silentMode, .movement, .clicking, .stopConditions,
             .behavior, .accessibility, .application]
        )
    }

    func testStatusPresentationDistinguishesInactiveActiveAndBlocked() {
        XCTAssertEqual(
            DriftPopoverPresentation.status(isActiveIntent: false, phase: .inactive),
            DriftPopoverStatusPresentation(label: "Inactive", tone: .inactive)
        )
        XCTAssertEqual(
            DriftPopoverPresentation.status(isActiveIntent: true, phase: .waitingForIdle),
            DriftPopoverStatusPresentation(label: "Active", tone: .active)
        )
        XCTAssertEqual(
            DriftPopoverPresentation.status(isActiveIntent: true, phase: .permissionBlocked),
            DriftPopoverStatusPresentation(label: "Accessibility Required", tone: .warning)
        )
    }

    func testShortcutLabelMatchesRecorderAndStatusCardCopy() {
        XCTAssertEqual(DriftPopoverPresentation.shortcutLabel(nil), "Not Set")
        XCTAssertEqual(
            DriftPopoverPresentation.shortcutLabel(
                GlobalShortcut(keyCode: 2, modifiers: [.command, .control])
            ),
            "⌘⌃D"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.shortcutLabel(
                GlobalShortcut(keyCode: 12, modifiers: [.option, .shift])
            ),
            "⌥⇧Key 12"
        )
    }

    func testVersionTextUsesRuntimeIdentityWithoutHardCodingVariant() {
        XCTAssertEqual(
            DriftPopoverPresentation.versionText(
                displayName: "Drift Dev",
                infoDictionary: ["CFBundleShortVersionString": "0.1.0"]
            ),
            "Drift Dev 0.1.0"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.versionText(displayName: "Drift", infoDictionary: [:]),
            "Drift"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.versionText(
                displayName: "Drift",
                infoDictionary: ["CFBundleShortVersionString": "   "]
            ),
            "Drift"
        )
    }

    func testConditionalStopControlsAppearOnlyWhenEnabled() {
        XCTAssertFalse(
            DriftPopoverPresentation.showsDailyStopDetails(for: .default)
        )
        XCTAssertTrue(
            DriftPopoverPresentation.showsDailyStopDetails(
                for: DailyStopSettings(isEnabled: true, hour: 18, minute: 0, weekdays: [1])
            )
        )
        XCTAssertFalse(
            DriftPopoverPresentation.showsBatteryStopDetails(for: .default)
        )
        XCTAssertTrue(
            DriftPopoverPresentation.showsBatteryStopDetails(
                for: BatteryStopSettings(isEnabled: true, thresholdPercent: 20)
            )
        )
    }

    func testClickPositionLabelShowsNotSetInvalidAndRoundedCoordinates() {
        XCTAssertEqual(
            DriftPopoverPresentation.clickPositionLabel(position: nil, isValid: false),
            "Not Set"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.clickPositionLabel(
                position: ClickPosition(x: 1, y: 2),
                isValid: false
            ),
            "Invalid"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.clickPositionLabel(
                position: ClickPosition(x: 123.4, y: 456.6),
                isValid: true
            ),
            "(123, 457)"
        )
    }

    func testClickPositionControlsAreEnabledOnlyWhenClickModeIsActive() {
        XCTAssertFalse(DriftPopoverPresentation.clickPositionControlsEnabled(for: .none))
        XCTAssertTrue(DriftPopoverPresentation.clickPositionControlsEnabled(for: .left))
        XCTAssertTrue(DriftPopoverPresentation.clickPositionControlsEnabled(for: .right))
        XCTAssertTrue(DriftPopoverPresentation.clickPositionControlsEnabled(for: .alternating))
    }

    func testGenericErrorsAreRoutedToTheirResponsibleCard() {
        XCTAssertEqual(
            DriftPopoverPresentation.errorSection(for: "Invalid click position"),
            .clicking
        )
        XCTAssertEqual(
            DriftPopoverPresentation.errorSection(
                for: "Launch at Login requires approval in System Settings"
            ),
            .behavior
        )
        XCTAssertEqual(
            DriftPopoverPresentation.errorSection(for: "Shortcut registration failed"),
            .behavior
        )
        XCTAssertEqual(
            DriftPopoverPresentation.errorSection(for: "Settings could not be saved"),
            .application
        )
        XCTAssertNil(DriftPopoverPresentation.errorSection(for: nil))
    }

    func testPopoverUsesNativeMaterialWithSubtleCardSurfaces() {
        XCTAssertEqual(DriftPopoverAppearance.material, .popover)
        XCTAssertEqual(DriftPopoverAppearance.blendingMode, .behindWindow)
        XCTAssertEqual(DriftPopoverAppearance.cardBackgroundOpacity, 0.36)
        XCTAssertEqual(DriftPopoverAppearance.cardBorderOpacity, 0.22)
        XCTAssertEqual(DriftPopoverAppearance.statusTintOpacity, 0.10)
        XCTAssertEqual(DriftPopoverAppearance.statusBorderOpacity, 0.32)
    }

    func testMaterialViewUsesApprovedNativeAppearance() {
        let materialView = DriftPopoverAppearance.makeMaterialView()

        XCTAssertEqual(materialView.material, .popover)
        XCTAssertEqual(materialView.blendingMode, .behindWindow)
        XCTAssertEqual(materialView.state, .active)
    }

    func testApprovedCompactPopoverMetricsAreExact() {
        XCTAssertEqual(DriftPopoverMetrics.contentWidth, 410)
        XCTAssertEqual(DriftPopoverMetrics.contentHorizontalPadding, 10)
        XCTAssertEqual(DriftPopoverMetrics.contentVerticalPadding, 8)
        XCTAssertEqual(DriftPopoverMetrics.cardCornerRadius, 12)
        XCTAssertEqual(DriftPopoverMetrics.cardSpacing, 8)
        XCTAssertEqual(DriftPopoverMetrics.cardHorizontalInset, 12)
        XCTAssertEqual(DriftPopoverMetrics.cardVerticalInset, 10)
        XCTAssertEqual(DriftPopoverMetrics.statusCardVerticalInset, 10)
        XCTAssertEqual(DriftPopoverMetrics.cardBodyWidth, 366)
        XCTAssertEqual(DriftPopoverMetrics.settingLabelWidth, 146)
        XCTAssertEqual(DriftPopoverMetrics.settingColumnGap, 10)
        XCTAssertEqual(DriftPopoverMetrics.settingControlWidth, 210)
        XCTAssertEqual(DriftPopoverMetrics.standardRowMinHeight, 30)
        XCTAssertEqual(DriftPopoverMetrics.fullWidthBlockSpacing, 6)
        XCTAssertEqual(DriftPopoverMetrics.menuControlWidth, 112)
        XCTAssertEqual(
            DriftPopoverMetrics.settingLabelWidth
                + DriftPopoverMetrics.settingColumnGap
                + DriftPopoverMetrics.settingControlWidth,
            DriftPopoverMetrics.cardBodyWidth
        )
    }

    func testHiddenControlsExposeExactAccessibilityLabels() {
        XCTAssertEqual(
            DriftPopoverPresentation.startMovingAfterAccessibilityLabel,
            "Start Moving After"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.moveEveryAccessibilityLabel,
            "Move Every"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.smartMotionAccessibilityLabel,
            "Smart Motion"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.silentModeAccessibilityLabel,
            "Silent Mode"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.clickModeAccessibilityLabel,
            "Click Mode"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.deactivateAtTimeAccessibilityLabel,
            "Deactivate At Time"
        )
    }

    func testMotionHelpTextExplainsIndependentRuntimeBehavior() {
        XCTAssertEqual(
            DriftPopoverPresentation.smartMotionHelpText,
            "Uses natural curved paths and varied timing for visible idle movement and travel to and away from clicks. It works independently of Silent Mode."
        )
        XCTAssertEqual(
            DriftPopoverPresentation.silentModeHelpText,
            "When Click Mode is None, Drift sends a tiny 0.01-point out-and-back pointer movement instead of moving across the screen. Click modes still move to the saved position, click, and move away."
        )
    }

    func testWeekdayAccessibilityNamesAndSelectionValuesAreUnambiguous() {
        let names = [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ]

        for (index, name) in names.enumerated() {
            XCTAssertEqual(
                DriftPopoverPresentation.weekdayAccessibilityLabel(index + 1),
                name
            )
        }
        XCTAssertEqual(
            DriftPopoverPresentation.weekdayAccessibilityValue(isSelected: true),
            "Selected"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.weekdayAccessibilityValue(isSelected: false),
            "Not selected"
        )
    }

    func testBehaviorErrorPresentationUsesOnlyAttemptDerivedMessages() {
        XCTAssertEqual(
            DriftPopoverPresentation.behaviorErrorMessage(
                genericError: "Shortcut registration failed",
                shortcutError: .registrationFailed(-1)
            ),
            "This shortcut is unavailable. Record a different combination."
        )
        XCTAssertEqual(
            DriftPopoverPresentation.behaviorErrorMessage(
                genericError: "Launch at Login requires approval in System Settings",
                shortcutError: nil
            ),
            "Launch at Login requires approval in System Settings"
        )
        XCTAssertEqual(
            DriftPopoverPresentation.behaviorErrorMessage(
                genericError: "Shortcut registration failed",
                shortcutError: nil
            ),
            "Shortcut registration failed"
        )
        XCTAssertNil(
            DriftPopoverPresentation.behaviorErrorMessage(
                genericError: nil,
                shortcutError: nil
            )
        )
    }
}
