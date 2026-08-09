import Carbon
import XCTest
import DriftCore
@testable import DriftApp

final class GlobalShortcutServiceTests: XCTestCase {
    func testCommandControlMapsToCarbonFlags() {
        XCTAssertEqual(
            CarbonShortcutMapping.modifiers(for: [.command, .control]),
            UInt32(cmdKey | controlKey)
        )
    }

    func testChangingShortcutUnregistersPreviousBeforeRegisteringNew() {
        let system = FakeGlobalShortcutSystem()
        let service = GlobalShortcutService(system: system)

        guard case .success = service.register(GlobalShortcut(keyCode: 2, modifiers: [.command]), handler: {}) else {
            return XCTFail("Expected first registration to succeed")
        }
        guard case .success = service.register(GlobalShortcut(keyCode: 3, modifiers: [.command]), handler: {}) else {
            return XCTFail("Expected replacement registration to succeed")
        }

        XCTAssertEqual(system.operations, [.register(2), .unregister, .register(3)])
    }

    func testRegistrationFailureKeepsMenuBarToggleWorking() {
        let system = FakeGlobalShortcutSystem(result: .failure(.registrationFailed(-9876)))
        let service = GlobalShortcutService(system: system)
        var toggled = false

        let result = service.register(GlobalShortcut(keyCode: 2, modifiers: [.command])) { toggled = true }
        guard case .failure(.registrationFailed(-9876)) = result else {
            return XCTFail("Expected Carbon registration error")
        }
        system.fireHandler()

        XCTAssertFalse(toggled)
        XCTAssertEqual(system.operations, [.register(2)])
    }

    func testNilShortcutUnregistersWithoutRegisteringReplacement() {
        let system = FakeGlobalShortcutSystem()
        let service = GlobalShortcutService(system: system)
        _ = service.register(GlobalShortcut(keyCode: 2, modifiers: [.command])) { }

        service.unregister()

        XCTAssertEqual(system.operations, [.register(2), .unregister])
    }
}

private final class FakeGlobalShortcutSystem: GlobalShortcutSystemControlling {
    enum Operation: Equatable {
        case register(UInt32)
        case unregister
    }

    let result: Result<Void, GlobalShortcutError>
    private(set) var operations: [Operation] = []
    private var handler: (() -> Void)?

    init(result: Result<Void, GlobalShortcutError> = .success(())) {
        self.result = result
    }

    func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) -> Result<Void, GlobalShortcutError> {
        operations.append(.register(shortcut.keyCode))
        if case .success = result {
            self.handler = handler
        }
        return result
    }

    func unregister() {
        operations.append(.unregister)
        handler = nil
    }

    func fireHandler() {
        handler?()
    }
}
