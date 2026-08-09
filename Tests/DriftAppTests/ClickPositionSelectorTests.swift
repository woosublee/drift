import CoreGraphics
import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class ClickPositionSelectorTests: XCTestCase {
    func testSelectionOpensOneOverlayPerScreen() {
        let provider = FakeOverlayWindowProvider()
        let selector = makeSelector(provider: provider)

        selector.select { _ in }

        XCTAssertEqual(provider.overlays.count, 2)
        XCTAssertTrue(provider.overlays.allSatisfy(\.isShown))
    }

    func testFirstClickCompletesOnceAndClosesAllOverlays() {
        let provider = FakeOverlayWindowProvider()
        let selector = makeSelector(provider: provider)
        var results: [Result<ClickPosition, ClickPositionSelectionError>] = []
        selector.select { results.append($0) }

        provider.overlays[0].select(ClickPosition(x: 10, y: 20))

        XCTAssertEqual(results, [.success(ClickPosition(x: 10, y: 20))])
        XCTAssertTrue(provider.overlays.allSatisfy(\.isClosed))
    }

    func testEscapeCancelsAndClosesAllOverlays() {
        let provider = FakeOverlayWindowProvider()
        let selector = makeSelector(provider: provider)
        var results: [Result<ClickPosition, ClickPositionSelectionError>] = []
        selector.select { results.append($0) }

        provider.overlays[0].cancel()

        XCTAssertEqual(results, [.failure(.cancelled)])
        XCTAssertTrue(provider.overlays.allSatisfy(\.isClosed))
    }

    func testSecondClickAfterCompletionIsIgnored() {
        let provider = FakeOverlayWindowProvider()
        let selector = makeSelector(provider: provider)
        var results: [Result<ClickPosition, ClickPositionSelectionError>] = []
        selector.select { results.append($0) }

        provider.overlays[0].select(ClickPosition(x: 10, y: 20))
        provider.overlays[1].select(ClickPosition(x: 30, y: 40))

        XCTAssertEqual(results, [.success(ClickPosition(x: 10, y: 20))])
    }

    private func makeSelector(provider: FakeOverlayWindowProvider) -> ClickPositionSelector {
        ClickPositionSelector(
            screenFrames: {
                [
                    CGRect(x: 0, y: 0, width: 100, height: 100),
                    CGRect(x: 100, y: 0, width: 100, height: 100)
                ]
            },
            overlayProvider: provider
        )
    }
}

@MainActor
private final class FakeOverlayWindowProvider: OverlayWindowProviding {
    private(set) var overlays: [FakeOverlay] = []

    func makeOverlay(
        screenFrame: CGRect,
        converter: ScreenCoordinateConverter,
        onSelect: @escaping (ClickPosition) -> Void,
        onCancel: @escaping () -> Void
    ) -> ClickPositionOverlayClosing {
        let overlay = FakeOverlay(onSelect: onSelect, onCancel: onCancel)
        overlays.append(overlay)
        return overlay
    }
}

@MainActor
private final class FakeOverlay: ClickPositionOverlayClosing {
    private let onSelect: (ClickPosition) -> Void
    private let onCancel: () -> Void
    private(set) var isShown = false
    private(set) var isClosed = false

    init(onSelect: @escaping (ClickPosition) -> Void, onCancel: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    func show() { isShown = true }
    func close() { isClosed = true }
    func select(_ position: ClickPosition) { onSelect(position) }
    func cancel() { onCancel() }
}
