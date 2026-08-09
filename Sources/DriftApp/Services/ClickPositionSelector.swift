import AppKit
import CoreGraphics
import DriftCore

public enum ClickPositionSelectionError: Error, Equatable {
    case cancelled
}

@MainActor
public protocol ClickPositionSelecting: AnyObject {
    func select(completion: @escaping (Result<ClickPosition, ClickPositionSelectionError>) -> Void)
    func cancel()
}

@MainActor
public protocol ClickPositionOverlayClosing: AnyObject {
    func show()
    func close()
}

@MainActor
public protocol OverlayWindowProviding: AnyObject {
    func makeOverlay(
        screenFrame: CGRect,
        converter: ScreenCoordinateConverter,
        onSelect: @escaping (ClickPosition) -> Void,
        onCancel: @escaping () -> Void
    ) -> ClickPositionOverlayClosing
}

@MainActor
public final class ClickPositionSelector: ClickPositionSelecting {
    private let screenFrames: () -> [CGRect]
    private let coordinateConverter: () -> ScreenCoordinateConverter
    private let overlayProvider: OverlayWindowProviding
    private var overlays: [ClickPositionOverlayClosing] = []
    private var completion: ((Result<ClickPosition, ClickPositionSelectionError>) -> Void)?
    private var keyMonitor: Any?
    private var screenChangeObserver: NSObjectProtocol?

    public init(
        screenFrames: @escaping () -> [CGRect],
        coordinateConverter: @escaping () -> ScreenCoordinateConverter = {
            ScreenCoordinateConverter(primaryScreenMaxY: ScreenCoordinateConverter.primaryScreenMaxY(
                fromAppKitScreenFrames: NSScreen.screens.map(\.frame)
            ))
        },
        overlayProvider: OverlayWindowProviding
    ) {
        self.screenFrames = screenFrames
        self.coordinateConverter = coordinateConverter
        self.overlayProvider = overlayProvider
    }

    deinit {
        let overlays = overlays
        let keyMonitor = keyMonitor
        let screenChangeObserver = screenChangeObserver
        Task { @MainActor in
            overlays.forEach { $0.close() }
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            if let screenChangeObserver {
                NotificationCenter.default.removeObserver(screenChangeObserver)
            }
        }
    }

    public func select(completion: @escaping (Result<ClickPosition, ClickPositionSelectionError>) -> Void) {
        cancel()
        self.completion = completion
        let converter = coordinateConverter()
        overlays = screenFrames().map { frame in
            overlayProvider.makeOverlay(
                screenFrame: frame,
                converter: converter,
                onSelect: { [weak self] position in self?.finish(.success(position)) },
                onCancel: { [weak self] in self?.finish(.failure(.cancelled)) }
            )
        }
        overlays.forEach { $0.show() }
        installCancellationMonitors()
    }

    public func cancel() {
        guard completion != nil else { return }
        finish(.failure(.cancelled))
    }

    private func finish(_ result: Result<ClickPosition, ClickPositionSelectionError>) {
        guard let completion else { return }
        self.completion = nil
        closeSelection()
        completion(result)
    }

    private func closeSelection() {
        overlays.forEach { $0.close() }
        overlays.removeAll()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
    }

    private func installCancellationMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }
}

@MainActor
public final class NullClickPositionSelector: ClickPositionSelecting {
    public init() {}
    public func select(completion: @escaping (Result<ClickPosition, ClickPositionSelectionError>) -> Void) {}
    public func cancel() {}
}
