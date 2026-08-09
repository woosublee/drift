import CoreGraphics
import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class DriftAppModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testRestoredActiveIntentChecksPermissionBeforeStarting() {
        let accessibility = FakeAccessibility(trusted: true)
        let fixture = makeFixture(activeIntent: true, accessibility: accessibility)

        fixture.model.start()

        XCTAssertEqual(accessibility.isTrustedCallCount, 1)
        XCTAssertEqual(fixture.model.phase, .waitingForIdle)
        XCTAssertTrue(fixture.model.isActiveIntent)
    }

    func testPermissionDeniedRestoresBlockedStateWithoutClearingIntent() {
        let fixture = makeFixture(activeIntent: true, accessibility: FakeAccessibility(trusted: false))

        fixture.model.start()

        XCTAssertEqual(fixture.model.phase, .permissionBlocked)
        XCTAssertTrue(fixture.model.isActiveIntent)
    }

    func testStartRequestsAccessibilityAccessWhenUntrusted() {
        let accessibility = FakeAccessibility(trusted: false)
        let fixture = makeFixture(activeIntent: false, accessibility: accessibility)

        fixture.model.start()

        XCTAssertEqual(accessibility.requestAccessCallCount, 1)
    }

    func testInactiveFirstLaunchPublishesActualUntrustedAccessibilityState() {
        let fixture = makeFixture(activeIntent: false, accessibility: FakeAccessibility(trusted: false))

        fixture.model.start()

        XCTAssertEqual(fixture.model.phase, .inactive)
        XCTAssertFalse(fixture.model.isAccessibilityTrusted)
    }

    func testTickStartsExactlyOneMotionSequence() {
        let fixture = makeFixture(activeIntent: true)
        fixture.model.start()

        fixture.model.handleTick(at: now.addingTimeInterval(60))
        fixture.model.handleTick(at: now.addingTimeInterval(61))

        XCTAssertEqual(fixture.motionExecutor.plans.count, 1)
        XCTAssertEqual(fixture.model.phase, .performingMotion)
    }

    func testPressedPhysicalButtonAtDeadlineResetsIdleWithoutExecutingMotion() {
        let pointerButtons = FakePointerButtonState(isAnyButtonPressed: true)
        let fixture = makeFixture(activeIntent: true, pointerButtonState: pointerButtons)
        fixture.model.start()

        fixture.model.handleTick(at: now.addingTimeInterval(60))

        XCTAssertTrue(fixture.motionExecutor.plans.isEmpty)
        XCTAssertEqual(fixture.model.phase, .waitingForIdle)
    }

    func testPhysicalInputCancelsRunningSequenceAndResetsInitialDelay() {
        let fixture = makeFixture(activeIntent: true)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))

        fixture.model.handlePhysicalInput(at: now.addingTimeInterval(61))

        XCTAssertEqual(fixture.motionExecutor.cancelCallCount, 1)
        XCTAssertEqual(fixture.model.phase, .waitingForIdle)
    }

    func testMotionCompletionSchedulesRepeatDelay() async {
        let fixture = makeFixture(activeIntent: true)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))

        fixture.motionExecutor.complete(with: .success(()))
        await Task.yield()

        XCTAssertEqual(fixture.model.phase, .waitingForRepeat)
    }

    func testSystemResumeUsesInitialDelay() {
        let fixture = makeFixture(activeIntent: true)
        fixture.model.start()
        fixture.model.handleSystemSuspend()

        fixture.model.handleSystemResume(at: now.addingTimeInterval(300))

        XCTAssertEqual(fixture.model.phase, .waitingForIdle)
    }

    func testSystemResumeWithoutPermissionBecomesBlocked() {
        let accessibility = FakeAccessibility(trusted: true)
        let fixture = makeFixture(activeIntent: true, accessibility: accessibility)
        fixture.model.start()
        fixture.model.handleSystemSuspend()
        accessibility.isTrustedValue = false

        fixture.model.handleSystemResume(at: now.addingTimeInterval(300))

        XCTAssertEqual(fixture.model.phase, .permissionBlocked)
        XCTAssertTrue(fixture.model.isActiveIntent)
    }

    func testDisplayReconfigurationCancelsMotionAndRestartsInitialIdleWait() {
        let fixture = makeFixture(activeIntent: true)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))
        XCTAssertEqual(fixture.model.phase, .performingMotion)

        fixture.systemActivityObserver.fireDisplayReconfiguration()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(fixture.motionExecutor.cancelCallCount, 1)
        XCTAssertEqual(fixture.model.phase, .waitingForIdle)
    }

    func testChangingMotionModePersistsSettings() {
        let fixture = makeFixture(activeIntent: false)
        fixture.model.start()

        fixture.model.setMotionMode(.natural)

        XCTAssertEqual(fixture.settingsStore.savedSettings?.motionMode, .natural)
        XCTAssertEqual(fixture.model.settings.motionMode, .natural)
    }

    func testOpeningAccessibilitySettingsRequestsAccessBeforeOpeningSettings() {
        let accessibility = FakeAccessibility(trusted: false)
        let fixture = makeFixture(activeIntent: false, accessibility: accessibility)

        fixture.model.openAccessibilitySettings()

        XCTAssertEqual(accessibility.requestAccessCallCount, 1)
        XCTAssertEqual(accessibility.openSettingsCallCount, 1)
    }

    private func makeFixture(
        activeIntent: Bool?,
        accessibility: FakeAccessibility = FakeAccessibility(trusted: true),
        pointerButtonState: FakePointerButtonState = FakePointerButtonState(isAnyButtonPressed: false)
    ) -> ModelFixture {
        let settingsStore = FakeSettingsStore()
        let runtimeStore = FakeRuntimeStateStore(activeIntent: activeIntent)
        let motionExecutor = FakeMotionExecutor()
        let systemActivityObserver = FakeSystemActivityObserver()
        let model = DriftAppModel(
            settingsStore: settingsStore,
            runtimeStateStore: runtimeStore,
            accessibility: accessibility,
            cursorLocation: FakeCursorLocation(),
            displayGeometry: FakeDisplayGeometry(),
            motionExecutor: motionExecutor,
            inputMonitor: FakeInputMonitor(),
            systemActivityObserver: systemActivityObserver,
            scheduler: FakeTickScheduler(),
            random: FixedRandomSource(),
            pointerButtonState: pointerButtonState,
            now: { self.now }
        )
        return ModelFixture(
            model: model,
            settingsStore: settingsStore,
            motionExecutor: motionExecutor,
            systemActivityObserver: systemActivityObserver
        )
    }
}

@MainActor
private struct ModelFixture {
    let model: DriftAppModel
    let settingsStore: FakeSettingsStore
    let motionExecutor: FakeMotionExecutor
    let systemActivityObserver: FakeSystemActivityObserver
}

private final class FakeSettingsStore: SettingsStoring {
    var settings = DriftSettings.default
    var savedSettings: DriftSettings?

    func loadSettings() -> DriftSettings { settings }
    func saveSettings(_ settings: DriftSettings) throws {
        savedSettings = settings
        self.settings = settings
    }
}

private final class FakeRuntimeStateStore: RuntimeStateStoring {
    var activeIntent: Bool?

    init(activeIntent: Bool?) {
        self.activeIntent = activeIntent
    }

    func loadActiveIntent() -> Bool? { activeIntent }
    func saveActiveIntent(_ activeIntent: Bool) { self.activeIntent = activeIntent }
    func loadNextAlternatingButton() -> MouseButton { .left }
    func saveNextAlternatingButton(_ button: MouseButton) {}
}

private final class FakeAccessibility: AccessibilityProviding {
    var isTrustedValue: Bool
    private(set) var isTrustedCallCount = 0
    private(set) var requestAccessCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(trusted: Bool) {
        isTrustedValue = trusted
    }

    func isTrusted() -> Bool {
        isTrustedCallCount += 1
        return isTrustedValue
    }

    func requestAccess() {
        requestAccessCallCount += 1
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}

private final class FakeCursorLocation: CursorLocationProviding {
    func currentLocation() -> CGPoint { CGPoint(x: 100, y: 100) }
}

private final class FakePointerButtonState: PointerButtonStateProviding {
    var isAnyButtonPressedValue: Bool

    init(isAnyButtonPressed: Bool) {
        isAnyButtonPressedValue = isAnyButtonPressed
    }

    func isAnyButtonPressed() -> Bool { isAnyButtonPressedValue }
}

private final class FakeDisplayGeometry: DisplayGeometryProviding {
    func visibleFrame(containing point: CGPoint) -> CGRect? {
        CGRect(x: 24, y: 24, width: 752, height: 552)
    }

    func screenFrames() -> [CGRect] {
        [CGRect(x: 0, y: 0, width: 800, height: 600)]
    }
}

private final class FakeMotionExecutor: MotionExecuting {
    private(set) var plans: [MotionPlan] = []
    private(set) var cancelCallCount = 0
    private var completion: ((Result<Void, CursorEventServiceError>) -> Void)?

    func execute(_ plan: MotionPlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void) {
        plans.append(plan)
        self.completion = completion
    }

    func execute(_ sequence: ClickSequencePlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void) {
        self.completion = completion
    }

    func cancel() {
        cancelCallCount += 1
    }

    func complete(with result: Result<Void, CursorEventServiceError>) {
        completion?(result)
    }
}

private final class FakeInputMonitor: InputActivityMonitoring {
    func start(onActivity: @escaping () -> Void) {}
    func stop() {}
}

private final class FakeSystemActivityObserver: SystemActivityObserving {
    private var onDisplayReconfiguration: (() -> Void)?

    func start(onSuspend: @escaping () -> Void, onResume: @escaping () -> Void) {}

    func start(
        onSuspend: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onDisplayReconfiguration: @escaping () -> Void
    ) {
        self.onDisplayReconfiguration = onDisplayReconfiguration
    }

    func stop() {}
    func fireDisplayReconfiguration() { onDisplayReconfiguration?() }
}

private final class FakeTickScheduler: TickScheduling {
    func start(_ onTick: @escaping (Date) -> Void) {}
    func stop() {}
}

private final class FixedRandomSource: DriftRandomSource {
    func double(in range: ClosedRange<Double>) -> Double { (range.lowerBound + range.upperBound) / 2 }
    func int(in range: ClosedRange<Int>) -> Int { (range.lowerBound + range.upperBound) / 2 }
}
