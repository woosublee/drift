import AppKit
import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class MenuBarPresentationTests: XCTestCase {
    func testInactiveUsesInactiveSVGAsset() {
        XCTAssertEqual(
            MenuBarPresentation.glyph(for: .inactive),
            .asset(name: "MenuBarIcon-Inactive")
        )
    }

    func testActivePhasesUseActiveSVGAsset() {
        for phase in [
            DriftPhase.waitingForIdle,
            .performingMotion,
            .waitingForRepeat,
            .suspendedBySystem
        ] {
            XCTAssertEqual(
                MenuBarPresentation.glyph(for: phase),
                .asset(name: "MenuBarIcon-Active")
            )
        }
    }

    func testBlockedUsesWarningSymbol() {
        XCTAssertEqual(
            MenuBarPresentation.glyph(for: .permissionBlocked),
            .systemSymbol(name: "exclamationmark.triangle")
        )
    }

    // Break caught: the provided SVGs are not loaded from the built app resource directory.
    func testSVGAssetsRenderAsDistinctTemplateImages() throws {
        let resourceDirectory = sourceRoot().appendingPathComponent("Resources")
        let inactive = try XCTUnwrap(
            MenuBarIconRenderer.image(
                for: .asset(name: "MenuBarIcon-Inactive"),
                accessibilityDescription: "Drift",
                resourceDirectory: resourceDirectory
            )
        )
        let active = try XCTUnwrap(
            MenuBarIconRenderer.image(
                for: .asset(name: "MenuBarIcon-Active"),
                accessibilityDescription: "Drift",
                resourceDirectory: resourceDirectory
            )
        )
        let inactiveAlpha = try alphaPixelCount(inactive)
        let activeAlpha = try alphaPixelCount(active)

        XCTAssertEqual(inactive.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(active.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(inactive.isTemplate)
        XCTAssertTrue(active.isTemplate)
        XCTAssertGreaterThan(inactiveAlpha, 0)
        XCTAssertGreaterThan(activeAlpha, 0)
        XCTAssertNotEqual(activeAlpha, inactiveAlpha)
    }

    func testBlockedRendererUsesTemplateSystemSymbol() throws {
        let image = try XCTUnwrap(
            MenuBarIconRenderer.image(
                for: .systemSymbol(name: "exclamationmark.triangle"),
                accessibilityDescription: "Drift"
            )
        )

        XCTAssertTrue(image.isTemplate)
    }

    func testPopoverUsesCompactReferenceWidth() {
        XCTAssertEqual(MenuBarPresentation.popoverContentWidth, 410)
    }

    func testPopoverContentSizeUsesFittingHeightWhenItFits() {
        XCTAssertEqual(
            MenuBarPresentation.popoverContentSize(
                fittingSize: NSSize(width: 360, height: 520),
                availableHeight: 1_000
            ),
            NSSize(width: 360, height: 520)
        )
    }

    func testPopoverContentSizeCapsHeightBeforePresentation() {
        XCTAssertEqual(
            MenuBarPresentation.popoverContentSize(
                fittingSize: NSSize(width: 360, height: 1_200),
                availableHeight: 970
            ),
            NSSize(width: 360, height: 938)
        )
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func alphaPixelCount(_ image: NSImage) throws -> Int {
        let width = 36
        let height = 36
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = NSSize(width: 18, height: 18)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()

        var count = 0
        for y in 0..<height {
            for x in 0..<width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                count += 1
            }
        }
        return count
    }
}
