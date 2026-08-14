import CoreGraphics
import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class ClickIntegrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testClickModeWithoutPositionIsRejectedAndStartsSelection() {
        let fixture = makeFixture(settings: .default)
        fixture.model.start()

        XCTAssertThrowsError(try fixture.model.setClickMode(.left))
        XCTAssertTrue(fixture.model.isSelectingClickPosition)
        XCTAssertEqual(fixture.model.settings.clickMode, .none)
        XCTAssertEqual(fixture.selector.selectCallCount, 1)
    }

    func testSettingClickModeToNonePreservesStoredPosition() throws {
        var settings = DriftSettings.default
        let position = ClickPosition(x: 500, y: 400)
        settings.clickPosition = position
        try settings.setClickMode(.left)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()

        try fixture.model.setClickMode(.none)

        XCTAssertEqual(fixture.model.settings.clickMode, .none)
        XCTAssertEqual(fixture.model.settings.clickPosition, position)
        XCTAssertEqual(fixture.settingsStore.savedSettings?.clickPosition, position)
    }

    func testReenablingClickModeReusesStoredPositionWithoutSelection() throws {
        var settings = DriftSettings.default
        let position = ClickPosition(x: 500, y: 400)
        settings.clickPosition = position
        let fixture = makeFixture(settings: settings)
        fixture.model.start()

        try fixture.model.setClickMode(.right)

        XCTAssertEqual(fixture.model.settings.clickMode, .right)
        XCTAssertEqual(fixture.model.settings.clickPosition, position)
        XCTAssertEqual(fixture.selector.selectCallCount, 0)
    }

    func testSelectedPositionIsPersistedAndEnablesRequestedClickMode() async throws {
        let fixture = makeFixture(settings: .default)
        fixture.model.start()
        XCTAssertThrowsError(try fixture.model.setClickMode(.right))

        fixture.selector.complete(with: .success(ClickPosition(x: 500, y: 400)))
        await Task.yield()

        XCTAssertEqual(fixture.model.settings.clickMode, .right)
        XCTAssertEqual(fixture.settingsStore.savedSettings?.clickPosition, ClickPosition(x: 500, y: 400))
        XCTAssertTrue(fixture.model.isClickPositionValid)
    }

    func testCancellingPositionSelectionPreservesStoredPositionAndMode() async throws {
        var settings = DriftSettings.default
        let position = ClickPosition(x: 500, y: 400)
        settings.clickPosition = position
        try settings.setClickMode(.left)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()
        fixture.model.selectClickPosition()

        fixture.model.cancelClickPositionSelection()
        await Task.yield()

        XCTAssertEqual(fixture.selector.cancelCallCount, 1)
        XCTAssertFalse(fixture.model.isSelectingClickPosition)
        XCTAssertEqual(fixture.model.settings.clickPosition, position)
        XCTAssertEqual(fixture.model.settings.clickMode, .left)
    }

    func testInvalidStoredPositionPreventsAnyEventSequence() {
        var settings = DriftSettings.default
        settings.clickPosition = ClickPosition(x: 900, y: 400)
        try? settings.setClickMode(.left)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()

        fixture.model.handleTick(at: now.addingTimeInterval(60))

        XCTAssertTrue(fixture.executor.motionPlans.isEmpty)
        XCTAssertTrue(fixture.executor.clickPlans.isEmpty)
        XCTAssertEqual(fixture.model.lastError, "Invalid click position")
    }

    func testClearingInvalidStoredPositionClearsResolvedInvalidPositionError() {
        var settings = DriftSettings.default
        settings.clickPosition = ClickPosition(x: 900, y: 400)
        try? settings.setClickMode(.left)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))

        fixture.model.clearClickPosition()

        XCTAssertNil(fixture.model.lastError)
        XCTAssertNil(fixture.model.settings.clickPosition)
        XCTAssertFalse(fixture.model.isClickPositionValid)
        XCTAssertNil(fixture.settingsStore.savedSettings?.clickPosition)
    }

    func testValidReplacementSelectionClearsResolvedInvalidPositionError() async {
        var settings = DriftSettings.default
        settings.clickPosition = ClickPosition(x: 900, y: 400)
        try? settings.setClickMode(.left)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))

        fixture.model.selectClickPosition()
        fixture.selector.complete(with: .success(ClickPosition(x: 500, y: 400)))
        await Task.yield()

        XCTAssertNil(fixture.model.lastError)
        XCTAssertEqual(fixture.model.settings.clickPosition, ClickPosition(x: 500, y: 400))
        XCTAssertTrue(fixture.model.isClickPositionValid)
        XCTAssertEqual(
            fixture.settingsStore.savedSettings?.clickPosition,
            ClickPosition(x: 500, y: 400)
        )
    }

    func testSuccessfulAlternatingClickFlipsNextButton() throws {
        var settings = DriftSettings.default
        settings.clickPosition = ClickPosition(x: 500, y: 400)
        try settings.setClickMode(.alternating)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))

        XCTAssertEqual(fixture.executor.clickPlans.first?.button, .left)
        fixture.executor.completeClick(with: .success(()))
        awaitMainActorTurn()

        XCTAssertEqual(fixture.runtimeStore.nextButton, .right)
    }

    func testCancelledAlternatingClickKeepsNextButton() throws {
        var settings = DriftSettings.default
        settings.clickPosition = ClickPosition(x: 500, y: 400)
        try settings.setClickMode(.alternating)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))
        fixture.executor.completeClick(with: .failure(.cancelled))
        awaitMainActorTurn()

        XCTAssertEqual(fixture.runtimeStore.nextButton, .left)
    }

    func testSuccessfulAlternatingClickAdvancesAfterPhysicalInputChangesPhase() throws {
        var settings = DriftSettings.default
        settings.clickPosition = ClickPosition(x: 500, y: 400)
        try settings.setClickMode(.alternating)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))

        fixture.model.handlePhysicalInput(at: now.addingTimeInterval(61))
        fixture.executor.completeClick(with: .success(()))
        awaitMainActorTurn()

        XCTAssertEqual(fixture.model.phase, .waitingForIdle)
        XCTAssertEqual(fixture.runtimeStore.nextButton, .right)
    }

    func testSuccessfulCompletionAfterDeactivationDoesNotAdvanceAlternatingButton() throws {
        var settings = DriftSettings.default
        settings.clickPosition = ClickPosition(x: 500, y: 400)
        try settings.setClickMode(.alternating)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()
        fixture.model.handleTick(at: now.addingTimeInterval(60))

        fixture.model.toggleActive()
        fixture.executor.completeClick(with: .success(()))
        awaitMainActorTurn()

        XCTAssertEqual(fixture.model.phase, .inactive)
        XCTAssertEqual(fixture.runtimeStore.nextButton, .left)
    }

    func testClickSequenceMovesToSafeRandomPositionOnClickDisplay() throws {
        var settings = DriftSettings.default
        settings.clickPosition = ClickPosition(x: 500, y: 400)
        try settings.setClickMode(.left)
        let fixture = makeFixture(settings: settings)
        fixture.model.start()

        fixture.model.handleTick(at: now.addingTimeInterval(60))

        XCTAssertEqual(
            fixture.executor.clickPlans.first?.returnPlan.samples.last?.point,
            CGPoint(x: 0, y: 0)
        )
        XCTAssertNotEqual(
            fixture.executor.clickPlans.first?.returnPlan.samples.last?.point,
            CGPoint(x: 100, y: 100)
        )
    }

    private func awaitMainActorTurn() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    private func makeFixture(settings: DriftSettings) -> ClickModelFixture {
        let settingsStore = ClickSettingsStore(settings: settings)
        let runtimeStore = ClickRuntimeStore(activeIntent: true)
        let selector = ClickSelectorFake()
        let executor = ClickExecutorFake()
        let model = DriftAppModel(
            settingsStore: settingsStore,
            runtimeStateStore: runtimeStore,
            accessibility: ClickAccessibilityFake(),
            cursorLocation: ClickCursorFake(),
            displayGeometry: ClickDisplayFake(),
            motionExecutor: executor,
            inputMonitor: ClickInputFake(),
            systemActivityObserver: ClickSystemActivityFake(),
            scheduler: ClickSchedulerFake(),
            random: ClickRandomFake(),
            clickPositionSelector: selector,
            now: { self.now }
        )
        return ClickModelFixture(model: model, settingsStore: settingsStore, runtimeStore: runtimeStore, selector: selector, executor: executor)
    }
}

@MainActor
private struct ClickModelFixture {
    let model: DriftAppModel
    let settingsStore: ClickSettingsStore
    let runtimeStore: ClickRuntimeStore
    let selector: ClickSelectorFake
    let executor: ClickExecutorFake
}

private final class ClickSettingsStore: SettingsStoring {
    var settings: DriftSettings
    var savedSettings: DriftSettings?
    init(settings: DriftSettings) { self.settings = settings }
    func loadSettings() -> DriftSettings { settings }
    func saveSettings(_ settings: DriftSettings) throws { self.settings = settings; savedSettings = settings }
}

private final class ClickRuntimeStore: RuntimeStateStoring {
    var activeIntent: Bool?
    var nextButton: MouseButton = .left
    init(activeIntent: Bool?) { self.activeIntent = activeIntent }
    func loadActiveIntent() -> Bool? { activeIntent }
    func saveActiveIntent(_ activeIntent: Bool) { self.activeIntent = activeIntent }
    func loadNextAlternatingButton() -> MouseButton { nextButton }
    func saveNextAlternatingButton(_ button: MouseButton) { nextButton = button }
}

private final class ClickAccessibilityFake: AccessibilityProviding { func isTrusted() -> Bool { true }; func openSystemSettings() {} }
private final class ClickCursorFake: CursorLocationProviding { func currentLocation() -> CGPoint { CGPoint(x: 100, y: 100) } }
private final class ClickDisplayFake: DisplayGeometryProviding {
    func visibleFrame(containing point: CGPoint) -> CGRect? { CGRect(x: 0, y: 0, width: 800, height: 600) }
    func screenFrames() -> [CGRect] { [CGRect(x: 0, y: 0, width: 800, height: 600)] }
}
private final class ClickInputFake: InputActivityMonitoring { func start(onActivity: @escaping () -> Void) {}; func stop() {} }
private final class ClickSystemActivityFake: SystemActivityObserving { func start(onSuspend: @escaping () -> Void, onResume: @escaping () -> Void) {}; func stop() {} }
private final class ClickSchedulerFake: TickScheduling { func start(_ onTick: @escaping (Date) -> Void) {}; func stop() {} }
private final class ClickRandomFake: DriftRandomSource { func double(in range: ClosedRange<Double>) -> Double { range.lowerBound }; func int(in range: ClosedRange<Int>) -> Int { range.lowerBound } }

@MainActor
private final class ClickSelectorFake: ClickPositionSelecting {
    private var completion: ((Result<ClickPosition, ClickPositionSelectionError>) -> Void)?
    private(set) var selectCallCount = 0
    private(set) var cancelCallCount = 0
    func select(completion: @escaping (Result<ClickPosition, ClickPositionSelectionError>) -> Void) {
        selectCallCount += 1
        self.completion = completion
    }
    func cancel() {
        cancelCallCount += 1
        completion?(.failure(.cancelled))
        completion = nil
    }
    func complete(with result: Result<ClickPosition, ClickPositionSelectionError>) { completion?(result); completion = nil }
}

private final class ClickExecutorFake: MotionExecuting {
    var motionPlans: [MotionPlan] = []
    var clickPlans: [ClickSequencePlan] = []
    private var motionCompletion: ((Result<Void, CursorEventServiceError>) -> Void)?
    private var clickCompletion: ((Result<Void, CursorEventServiceError>) -> Void)?
    func execute(_ plan: MotionPlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void) { motionPlans.append(plan); motionCompletion = completion }
    func execute(_ sequence: ClickSequencePlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void) { clickPlans.append(sequence); clickCompletion = completion }
    func cancel() {}
    func completeClick(with result: Result<Void, CursorEventServiceError>) { clickCompletion?(result) }
}
