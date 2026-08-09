import CoreGraphics
import Foundation
import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class StopConditionIntegrationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testScheduleStopCancelsMotionSavesInactiveAndShowsReason() {
        let date = scheduledDate
        let settings = settingsWithDailyStop
        let fixture = makeFixture(settings: settings, activeIntent: true, snapshot: PowerSnapshot(source: .unavailable, percent: nil, isCharging: false), now: date)
        fixture.model.start()

        fixture.model.handleTick(at: date)

        XCTAssertEqual(fixture.executor.cancelCount, 1)
        XCTAssertEqual(fixture.runtimeStore.activeIntent, false)
        XCTAssertEqual(fixture.hud.messages, [HUDMessage(title: "Drift Inactive", subtitle: "Stopped by schedule")])
    }

    func testBatteryStopCancelsMotionSavesInactiveAndShowsThreshold() {
        let date = scheduledDate.addingTimeInterval(-60)
        var settings = DriftSettings.default
        settings.batteryStop = BatteryStopSettings(isEnabled: true, thresholdPercent: 20)
        let fixture = makeFixture(settings: settings, activeIntent: true, snapshot: PowerSnapshot(source: .battery, percent: 20, isCharging: false), now: date)
        fixture.model.start()

        fixture.model.handleTick(at: date.addingTimeInterval(60))

        XCTAssertEqual(fixture.executor.cancelCount, 1)
        XCTAssertEqual(fixture.runtimeStore.activeIntent, false)
        XCTAssertEqual(fixture.hud.messages, [HUDMessage(title: "Drift Inactive", subtitle: "Stopped at 20% battery")])
    }

    func testStopConditionDoesNothingWhileAlreadyInactive() {
        let fixture = makeFixture(settings: settingsWithDailyStop, activeIntent: false, snapshot: PowerSnapshot(source: .battery, percent: 1, isCharging: false), now: scheduledDate)
        fixture.model.start()

        fixture.model.handleTick(at: scheduledDate)

        XCTAssertEqual(fixture.executor.cancelCount, 0)
        XCTAssertTrue(fixture.hud.messages.isEmpty)
    }

    func testScheduleCheckRunsBeforeStartingDueMotion() {
        let fixture = makeFixture(settings: settingsWithDailyStop, activeIntent: true, snapshot: PowerSnapshot(source: .unavailable, percent: nil, isCharging: false), now: scheduledDate.addingTimeInterval(-60))
        fixture.model.start()

        fixture.model.handleTick(at: scheduledDate)

        XCTAssertTrue(fixture.executor.motionPlans.isEmpty)
        XCTAssertFalse(fixture.model.isActiveIntent)
    }

    func testPersistedScheduleTriggerPreventsSecondStopAfterRestartInSameMinute() {
        let runtimeStore = StopRuntimeStore(activeIntent: true)
        let snapshot = PowerSnapshot(source: .unavailable, percent: nil, isCharging: false)
        let first = makeFixture(
            settings: settingsWithDailyStop,
            activeIntent: true,
            snapshot: snapshot,
            now: scheduledDate,
            runtimeStore: runtimeStore
        )
        first.model.start()
        first.model.handleTick(at: scheduledDate)
        runtimeStore.activeIntent = true

        let relaunched = makeFixture(
            settings: settingsWithDailyStop,
            activeIntent: true,
            snapshot: snapshot,
            now: scheduledDate,
            runtimeStore: runtimeStore
        )
        relaunched.model.start()
        relaunched.model.handleTick(at: scheduledDate)

        XCTAssertTrue(relaunched.model.isActiveIntent)
        XCTAssertTrue(relaunched.hud.messages.isEmpty)
    }

    func testBatterySettingsStayWithinFiveToFiftyPercent() {
        let fixture = makeFixture(settings: .default, activeIntent: false, snapshot: PowerSnapshot(source: .unavailable, percent: nil, isCharging: false), now: scheduledDate)
        fixture.model.start()

        fixture.model.setBatteryStop(BatteryStopSettings(isEnabled: true, thresholdPercent: 99))

        XCTAssertEqual(fixture.model.settings.batteryStop.thresholdPercent, 50)
    }

    func testBatteryCheckRunsAtMostOncePerSixtySeconds() {
        let date = scheduledDate.addingTimeInterval(-120)
        var settings = DriftSettings.default
        settings.batteryStop = BatteryStopSettings(isEnabled: true, thresholdPercent: 20)
        let power = StopPowerFake(snapshot: PowerSnapshot(source: .battery, percent: 80, isCharging: false))
        let fixture = makeFixture(settings: settings, activeIntent: true, snapshot: power.snapshotValue, now: date, power: power)
        fixture.model.start()

        fixture.model.handleTick(at: date.addingTimeInterval(60))
        fixture.model.handleTick(at: date.addingTimeInterval(61))

        XCTAssertEqual(power.snapshotCallCount, 1)
    }

    private var scheduledDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 18, minute: 0))!
    }

    private var settingsWithDailyStop: DriftSettings {
        var settings = DriftSettings.default
        settings.dailyStop = DailyStopSettings(isEnabled: true, hour: 18, minute: 0, weekdays: [7])
        return settings
    }

    private func makeFixture(
        settings: DriftSettings,
        activeIntent: Bool,
        snapshot: PowerSnapshot,
        now: Date,
        power: StopPowerFake? = nil,
        runtimeStore: StopRuntimeStore? = nil
    ) -> StopModelFixture {
        let settingsStore = StopSettingsStore(settings: settings)
        let runtimeStore = runtimeStore ?? StopRuntimeStore(activeIntent: activeIntent)
        let executor = StopExecutorFake()
        let hud = StopHUDFake()
        let model = DriftAppModel(
            settingsStore: settingsStore,
            runtimeStateStore: runtimeStore,
            accessibility: StopAccessibilityFake(),
            cursorLocation: StopCursorFake(),
            displayGeometry: StopDisplayFake(),
            motionExecutor: executor,
            inputMonitor: StopInputFake(),
            systemActivityObserver: StopSystemActivityFake(),
            scheduler: StopSchedulerFake(),
            random: StopRandomFake(),
            powerSource: power ?? StopPowerFake(snapshot: snapshot),
            hudPresenter: hud,
            calendar: calendar,
            now: { now }
        )
        return StopModelFixture(model: model, runtimeStore: runtimeStore, executor: executor, hud: hud)
    }
}

@MainActor
private struct StopModelFixture {
    let model: DriftAppModel
    let runtimeStore: StopRuntimeStore
    let executor: StopExecutorFake
    let hud: StopHUDFake
}

private final class StopSettingsStore: SettingsStoring { var settings: DriftSettings; init(settings: DriftSettings) { self.settings = settings }; func loadSettings() -> DriftSettings { settings }; func saveSettings(_ settings: DriftSettings) throws { self.settings = settings } }
private final class StopRuntimeStore: RuntimeStateStoring { var activeIntent: Bool?; var nextButton = MouseButton.left; var lastDailyStopTrigger: DailyStopTrigger?; init(activeIntent: Bool?) { self.activeIntent = activeIntent }; func loadActiveIntent() -> Bool? { activeIntent }; func saveActiveIntent(_ activeIntent: Bool) { self.activeIntent = activeIntent }; func loadNextAlternatingButton() -> MouseButton { nextButton }; func saveNextAlternatingButton(_ button: MouseButton) { nextButton = button }; func loadLastDailyStopTrigger() -> DailyStopTrigger? { lastDailyStopTrigger }; func saveLastDailyStopTrigger(_ trigger: DailyStopTrigger) { lastDailyStopTrigger = trigger } }
private final class StopAccessibilityFake: AccessibilityProviding { func isTrusted() -> Bool { true }; func openSystemSettings() {} }
private final class StopCursorFake: CursorLocationProviding { func currentLocation() -> CGPoint { CGPoint(x: 100, y: 100) } }
private final class StopDisplayFake: DisplayGeometryProviding { func visibleFrame(containing point: CGPoint) -> CGRect? { CGRect(x: 0, y: 0, width: 800, height: 600) }; func screenFrames() -> [CGRect] { [CGRect(x: 0, y: 0, width: 800, height: 600)] } }
private final class StopInputFake: InputActivityMonitoring { func start(onActivity: @escaping () -> Void) {}; func stop() {} }
private final class StopSystemActivityFake: SystemActivityObserving { func start(onSuspend: @escaping () -> Void, onResume: @escaping () -> Void) {}; func stop() {} }
private final class StopSchedulerFake: TickScheduling { func start(_ onTick: @escaping (Date) -> Void) {}; func stop() {} }
private final class StopRandomFake: DriftRandomSource { func double(in range: ClosedRange<Double>) -> Double { range.lowerBound }; func int(in range: ClosedRange<Int>) -> Int { range.lowerBound } }
private final class StopPowerFake: PowerSourceProviding { let snapshotValue: PowerSnapshot; private(set) var snapshotCallCount = 0; init(snapshot: PowerSnapshot) { snapshotValue = snapshot }; func snapshot() -> PowerSnapshot { snapshotCallCount += 1; return snapshotValue } }
@MainActor private final class StopHUDFake: HUDPresenting { private(set) var messages: [HUDMessage] = []; func show(_ message: HUDMessage) { messages.append(message) }; func dismiss() {} }
private final class StopExecutorFake: MotionExecuting { private(set) var cancelCount = 0; private(set) var motionPlans: [MotionPlan] = []; func execute(_ plan: MotionPlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void) { motionPlans.append(plan) }; func execute(_ sequence: ClickSequencePlan, completion: @escaping (Result<Void, CursorEventServiceError>) -> Void) {}; func cancel() { cancelCount += 1 } }
