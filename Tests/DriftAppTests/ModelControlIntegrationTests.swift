import Combine
import CoreGraphics
import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class ModelControlIntegrationTests: XCTestCase {
    func testSuccessfulRegistrationUpdatesAndPersistsToggle() {
        let login = ControlLoginFake(status: .disabled)
        let fixture = makeFixture(login: login)
        fixture.model.start()

        fixture.model.setLaunchAtLogin(true)

        XCTAssertTrue(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.store.saved?.launchAtLogin, true)
    }

    func testFailedRegistrationLeavesToggleDisabledAndShowsError() {
        let login = ControlLoginFake(status: .disabled, result: .failure(.operationFailed))
        let fixture = makeFixture(login: login)
        fixture.model.start()

        fixture.model.setLaunchAtLogin(true)

        XCTAssertFalse(fixture.model.settings.launchAtLogin)
        XCTAssertNotNil(fixture.model.lastError)
    }

    func testRequiresApprovalDoesNotReportEnabled() {
        let login = ControlLoginFake(status: .requiresApproval, result: .failure(.requiresApproval))
        let fixture = makeFixture(login: login)
        fixture.model.start()

        fixture.model.setLaunchAtLogin(true)

        XCTAssertFalse(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.model.loginItemStatus, .requiresApproval)
    }

    func testPassiveUnavailableStatusDoesNotCreateError() {
        let login = ControlLoginFake(status: .unavailable)
        let fixture = makeFixture(login: login)

        fixture.model.start()

        XCTAssertFalse(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.model.loginItemStatus, .unavailable)
        XCTAssertNil(fixture.model.lastError)
    }

    func testUnavailableMismatchUsesGenericChangeFailure() {
        let login = ControlLoginFake(status: .disabled, result: .success(.unavailable))
        let fixture = makeFixture(login: login)
        fixture.model.start()

        fixture.model.setLaunchAtLogin(true)

        XCTAssertFalse(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.model.loginItemStatus, .unavailable)
        XCTAssertEqual(fixture.model.lastError, "Launch at Login could not be changed")
    }

    func testRefreshAdoptsExternalApprovalAndClearsResolvedFeedback() {
        let login = ControlLoginFake(
            status: .requiresApproval,
            result: .failure(.requiresApproval)
        )
        let fixture = makeFixture(login: login)
        fixture.model.start()
        fixture.model.setLaunchAtLogin(true)
        XCTAssertEqual(
            fixture.model.lastError,
            "Launch at Login requires approval in System Settings"
        )

        login.observed = .enabled
        fixture.model.refreshLoginItemStatus()

        XCTAssertTrue(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.model.loginItemStatus, .enabled)
        XCTAssertEqual(fixture.store.saved?.launchAtLogin, true)
        XCTAssertNil(fixture.model.lastError)
    }

    func testRefreshAdoptsExternalDisable() {
        let login = ControlLoginFake(status: .enabled)
        let fixture = makeFixture(login: login)
        fixture.model.start()

        login.observed = .disabled
        fixture.model.refreshLoginItemStatus()

        XCTAssertFalse(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.model.loginItemStatus, .disabled)
        XCTAssertEqual(fixture.store.saved?.launchAtLogin, false)
    }

    func testRefreshWithUnchangedObservedStatePublishesNothing() {
        let login = ControlLoginFake(status: .disabled)
        let fixture = makeFixture(login: login)
        fixture.model.start()
        var settingsEmissionCount = 0
        var statusEmissionCount = 0
        var cancellables: Set<AnyCancellable> = []
        fixture.model.$settings.dropFirst().sink { _ in
            settingsEmissionCount += 1
        }.store(in: &cancellables)
        fixture.model.$loginItemStatus.dropFirst().sink { _ in
            statusEmissionCount += 1
        }.store(in: &cancellables)

        fixture.model.refreshLoginItemStatus()

        XCTAssertEqual(settingsEmissionCount, 0)
        XCTAssertEqual(statusEmissionCount, 0)
        XCTAssertEqual(fixture.store.saveCount, 0)
    }

    func testRefreshStatusOnlyChangeDoesNotRepublishEquivalentSettings() {
        let login = ControlLoginFake(status: .disabled)
        let fixture = makeFixture(login: login)
        fixture.model.start()
        var settingsEmissionCount = 0
        var statusEmissionCount = 0
        var cancellables: Set<AnyCancellable> = []
        fixture.model.$settings.dropFirst().sink { _ in
            settingsEmissionCount += 1
        }.store(in: &cancellables)
        fixture.model.$loginItemStatus.dropFirst().sink { _ in
            statusEmissionCount += 1
        }.store(in: &cancellables)
        login.observed = .unavailable

        fixture.model.refreshLoginItemStatus()

        XCTAssertEqual(settingsEmissionCount, 0)
        XCTAssertEqual(statusEmissionCount, 1)
        XCTAssertEqual(fixture.store.saveCount, 0)
    }

    func testRefreshExternalEnablePublishesAndPersistsEachChangedValueOnce() {
        let login = ControlLoginFake(status: .disabled)
        let fixture = makeFixture(login: login)
        fixture.model.start()
        var settingsEmissionCount = 0
        var statusEmissionCount = 0
        var cancellables: Set<AnyCancellable> = []
        fixture.model.$settings.dropFirst().sink { _ in
            settingsEmissionCount += 1
        }.store(in: &cancellables)
        fixture.model.$loginItemStatus.dropFirst().sink { _ in
            statusEmissionCount += 1
        }.store(in: &cancellables)
        login.observed = .enabled

        fixture.model.refreshLoginItemStatus()

        XCTAssertEqual(settingsEmissionCount, 1)
        XCTAssertEqual(statusEmissionCount, 1)
        XCTAssertEqual(fixture.store.saveCount, 1)
    }

    func testFailedDisableKeepsEnabledLaunchAtLoginSettingInSyncWithObservedStatus() {
        let login = ControlLoginFake(status: .enabled, result: .failure(.operationFailed))
        let fixture = makeFixture(login: login)
        fixture.model.start()

        fixture.model.setLaunchAtLogin(false)

        XCTAssertTrue(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.store.saved?.launchAtLogin, true)
        XCTAssertEqual(fixture.model.loginItemStatus, .enabled)
        XCTAssertEqual(fixture.model.lastError, "Launch at Login could not be changed")
    }

    func testDisableSuccessMismatchKeepsEnabledLaunchAtLoginSettingInSyncWithStatus() {
        let login = ControlLoginFake(status: .enabled, result: .success(.enabled))
        let fixture = makeFixture(login: login)
        fixture.model.start()

        fixture.model.setLaunchAtLogin(false)

        XCTAssertTrue(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.store.saved?.launchAtLogin, true)
        XCTAssertEqual(fixture.model.loginItemStatus, .enabled)
        XCTAssertEqual(fixture.model.lastError, "Launch at Login could not be changed")
    }

    func testClearClickPositionPreservesUnrelatedLaunchAtLoginError() {
        let login = ControlLoginFake(status: .disabled, result: .failure(.operationFailed))
        let fixture = makeFixture(login: login)
        fixture.model.start()
        fixture.model.setLaunchAtLogin(true)

        fixture.model.clearClickPosition()

        XCTAssertEqual(fixture.model.lastError, "Launch at Login could not be changed")
    }

    func testShortcutCallbackUsesTogglePathAndShowsHUD() {
        let shortcut = ControlShortcutFake()
        let hud = ControlHUDFake()
        let fixture = makeFixture(globalShortcut: shortcut, hud: hud)
        fixture.model.start()

        shortcut.fire()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertTrue(fixture.model.isActiveIntent)
        XCTAssertEqual(hud.messages, [HUDMessage(title: "Drift Active", subtitle: nil)])
    }

    func testShortcutRegistrationFailureKeepsMenuBarToggleWorking() {
        let shortcut = ControlShortcutFake(result: .failure(.registrationFailed(-1)))
        let fixture = makeFixture(globalShortcut: shortcut)
        fixture.model.start()

        XCTAssertNotNil(fixture.model.shortcutRegistrationError)
        fixture.model.toggleActive()

        XCTAssertTrue(fixture.model.isActiveIntent)
    }

    func testBlockedHotkeyShowsPermissionHUDInsteadOfActiveHUD() {
        let shortcut = ControlShortcutFake()
        let hud = ControlHUDFake()
        let fixture = makeFixture(
            globalShortcut: shortcut,
            hud: hud,
            accessibility: ControlAccessibility(trusted: false)
        )
        fixture.model.start()

        shortcut.fire()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(fixture.model.phase, .permissionBlocked)
        XCTAssertEqual(hud.messages, [HUDMessage(
            title: "Accessibility Required",
            subtitle: "Open System Settings to activate Drift"
        )])
    }

    func testManualDeactivationImmediatelyCancelsRunningSequence() {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.model.toggleActive()
        fixture.model.handleTick(at: Date(timeIntervalSince1970: 1_060))
        XCTAssertEqual(fixture.model.phase, .performingMotion)

        fixture.model.toggleActive()

        XCTAssertEqual(fixture.executor.cancelCount, 1)
        XCTAssertEqual(fixture.model.phase, .inactive)
    }

    func testSuccessfulShortcutRegistrationClearsOnlyItsPreviousBehaviorError() {
        let shortcut = ControlShortcutFake(result: .failure(.registrationFailed(-1)))
        let fixture = makeFixture(globalShortcut: shortcut)
        fixture.model.start()

        XCTAssertEqual(fixture.model.lastError, "Shortcut registration failed")
        XCTAssertEqual(fixture.model.shortcutRegistrationError, .registrationFailed(-1))

        shortcut.result = .success(())
        fixture.model.setToggleShortcut(
            GlobalShortcut(keyCode: 12, modifiers: [.command])
        )

        XCTAssertNil(fixture.model.shortcutRegistrationError)
        XCTAssertNil(fixture.model.lastError)
    }

    func testSuccessfulLaunchAtLoginClearsOnlyItsPreviousBehaviorError() {
        let login = ControlLoginFake(
            status: .requiresApproval,
            result: .failure(.requiresApproval)
        )
        let fixture = makeFixture(login: login)
        fixture.model.start()

        fixture.model.setLaunchAtLogin(true)
        XCTAssertEqual(
            fixture.model.lastError,
            "Launch at Login requires approval in System Settings"
        )

        login.result = .success(.enabled)
        fixture.model.setLaunchAtLogin(true)

        XCTAssertTrue(fixture.model.settings.launchAtLogin)
        XCTAssertEqual(fixture.model.loginItemStatus, .enabled)
        XCTAssertNil(fixture.model.lastError)
    }

    private func makeFixture(
        login: ControlLoginFake = ControlLoginFake(status: .disabled),
        globalShortcut: ControlShortcutFake = ControlShortcutFake(),
        hud: ControlHUDFake? = nil,
        accessibility: ControlAccessibility = ControlAccessibility()
    ) -> ControlFixture {
        let hud = hud ?? ControlHUDFake()
        let store = ControlSettingsStore()
        let executor = ControlExecutor()
        let model = DriftAppModel(
            settingsStore: store,
            runtimeStateStore: ControlRuntimeStore(),
            accessibility: accessibility,
            cursorLocation: ControlCursor(),
            displayGeometry: ControlDisplay(),
            motionExecutor: executor,
            inputMonitor: ControlInput(),
            systemActivityObserver: ControlSystemActivity(),
            scheduler: ControlScheduler(),
            random: ControlRandom(),
            pointerButtonState: ControlPointerButtonState(),
            hudPresenter: hud,
            loginItem: login,
            globalShortcut: globalShortcut,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        return ControlFixture(model: model, store: store, executor: executor)
    }
}

@MainActor private struct ControlFixture { let model: DriftAppModel; let store: ControlSettingsStore; let executor: ControlExecutor }
private final class ControlSettingsStore: SettingsStoring { var settings = DriftSettings.default; var saved: DriftSettings?; private(set) var saveCount = 0; func loadSettings() -> DriftSettings { settings }; func saveSettings(_ settings: DriftSettings) throws { self.settings = settings; saved = settings; saveCount += 1 } }
private final class ControlRuntimeStore: RuntimeStateStoring { var active: Bool? = false; func loadActiveIntent() -> Bool? { active }; func saveActiveIntent(_ activeIntent: Bool) { active = activeIntent }; func loadNextAlternatingButton() -> MouseButton { .left }; func saveNextAlternatingButton(_ button: MouseButton) {} }
private final class ControlAccessibility: AccessibilityProviding { let trusted: Bool; init(trusted: Bool = true) { self.trusted = trusted }; func isTrusted() -> Bool { trusted }; func openSystemSettings() {} }
private final class ControlCursor: CursorLocationProviding { func currentLocation() -> CGPoint { .zero } }
private final class ControlDisplay: DisplayGeometryProviding { func visibleFrame(containing point: CGPoint) -> CGRect? { CGRect(x: 0, y: 0, width: 10, height: 10) }; func screenFrames() -> [CGRect] { [CGRect(x: 0, y: 0, width: 10, height: 10)] } }
private final class ControlPointerButtonState: PointerButtonStateProviding { func isAnyButtonPressed() -> Bool { false } }
private final class ControlExecutor: MotionExecuting { private(set) var cancelCount = 0; func execute(_ plan: MotionPlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void) {}; func execute(_ sequence: ClickSequencePlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void) {}; func cancel() { cancelCount += 1 } }
private final class ControlInput: InputActivityMonitoring { func start(onActivity: @escaping () -> Void) {}; func stop() {} }
private final class ControlSystemActivity: SystemActivityObserving { func start(onSuspend: @escaping () -> Void, onResume: @escaping () -> Void) {}; func stop() {} }
private final class ControlScheduler: TickScheduling { func start(_ onTick: @escaping (Date) -> Void) {}; func stop() {} }
private final class ControlRandom: DriftRandomSource { func double(in range: ClosedRange<Double>) -> Double { range.lowerBound }; func int(in range: ClosedRange<Int>) -> Int { range.lowerBound } }
@MainActor private final class ControlHUDFake: HUDPresenting { private(set) var messages: [HUDMessage] = []; func show(_ message: HUDMessage) { messages.append(message) }; func dismiss() {} }
private final class ControlLoginFake: LoginItemManaging { var observed: LoginItemStatus; var result: Result<LoginItemStatus, LoginItemError>; init(status: LoginItemStatus, result: Result<LoginItemStatus, LoginItemError>? = nil) { observed = status; self.result = result ?? .success(.enabled) }; func status() -> LoginItemStatus { observed }; func setEnabled(_ enabled: Bool) -> Result<LoginItemStatus, LoginItemError> { if case .success(let status) = result { observed = status }; return result } }
private final class ControlShortcutFake: GlobalShortcutManaging { var result: Result<Void, GlobalShortcutError>; private var handler: (() -> Void)?; init(result: Result<Void, GlobalShortcutError> = .success(())) { self.result = result }; func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) -> Result<Void, GlobalShortcutError> { if case .success = result { self.handler = handler }; return result }; func unregister() { handler = nil }; func fire() { handler?() } }
