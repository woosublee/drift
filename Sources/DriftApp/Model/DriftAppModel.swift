import Combine
import CoreGraphics
import Foundation
import DriftCore

@MainActor
public final class DriftAppModel: ObservableObject {
    @Published public private(set) var settings: DriftSettings
    @Published public private(set) var phase: DriftPhase
    @Published public private(set) var isActiveIntent: Bool
    @Published public private(set) var lastError: String?
    @Published public private(set) var isSelectingClickPosition: Bool
    @Published public private(set) var isClickPositionValid: Bool
    @Published public private(set) var lastDailyStopTrigger: DailyStopTrigger?
    @Published public private(set) var loginItemStatus: LoginItemStatus
    @Published public private(set) var shortcutRegistrationError: GlobalShortcutError?
    @Published public private(set) var isAccessibilityTrusted: Bool

    private let settingsStore: SettingsStoring
    private let runtimeStateStore: RuntimeStateStoring
    private let accessibility: AccessibilityProviding
    private let cursorLocation: CursorLocationProviding
    private let displayGeometry: DisplayGeometryProviding
    private let motionExecutor: MotionExecuting
    private let inputMonitor: InputActivityMonitoring
    private let systemActivityObserver: SystemActivityObserving
    private let scheduler: TickScheduling
    private let random: DriftRandomSource
    private let pointerButtonState: PointerButtonStateProviding
    private let clickPositionSelector: ClickPositionSelecting
    private let clickPositionValidator: ClickPositionValidating
    private let powerSource: PowerSourceProviding
    private let hudPresenter: HUDPresenting
    private let loginItem: LoginItemManaging
    private let globalShortcut: GlobalShortcutManaging
    private let calendar: Calendar
    private let now: () -> Date
    private let timingPolicy = MotionTimingPolicy()
    private let destinationPicker = DestinationPicker()
    private let pathGenerator = MotionPathGenerator()
    private let clickPlanner = ClickSequencePlanner()
    private let dailyStopPolicy = DailyStopPolicy()
    private let batteryStopPolicy = BatteryStopPolicy()
    private var machine = DriftStateMachine()
    private var hasStarted = false
    private var pendingClickMode: ClickMode?
    private var lastPowerCheckAt: Date?

    public init(
        settingsStore: SettingsStoring,
        runtimeStateStore: RuntimeStateStoring,
        accessibility: AccessibilityProviding,
        cursorLocation: CursorLocationProviding,
        displayGeometry: DisplayGeometryProviding,
        motionExecutor: MotionExecuting,
        inputMonitor: InputActivityMonitoring,
        systemActivityObserver: SystemActivityObserving,
        scheduler: TickScheduling,
        random: DriftRandomSource,
        pointerButtonState: PointerButtonStateProviding = CoreGraphicsPointerButtonStateProvider(),
        clickPositionSelector: ClickPositionSelecting? = nil,
        clickPositionValidator: ClickPositionValidating = ClickPositionValidator(),
        powerSource: PowerSourceProviding = NullPowerSourceService(),
        hudPresenter: HUDPresenting? = nil,
        loginItem: LoginItemManaging = NullLoginItemService(),
        globalShortcut: GlobalShortcutManaging = NullGlobalShortcutService(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.runtimeStateStore = runtimeStateStore
        self.accessibility = accessibility
        self.cursorLocation = cursorLocation
        self.displayGeometry = displayGeometry
        self.motionExecutor = motionExecutor
        self.inputMonitor = inputMonitor
        self.systemActivityObserver = systemActivityObserver
        self.scheduler = scheduler
        self.random = random
        self.pointerButtonState = pointerButtonState
        self.clickPositionSelector = clickPositionSelector ?? NullClickPositionSelector()
        self.clickPositionValidator = clickPositionValidator
        self.powerSource = powerSource
        self.hudPresenter = hudPresenter ?? NullHUDPresenter()
        self.loginItem = loginItem
        self.globalShortcut = globalShortcut
        self.calendar = calendar
        self.now = now
        settings = .default
        phase = .inactive
        isActiveIntent = false
        lastError = nil
        isSelectingClickPosition = false
        isClickPositionValid = false
        lastDailyStopTrigger = nil
        loginItemStatus = .disabled
        shortcutRegistrationError = nil
        isAccessibilityTrusted = false
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        settings = settingsStore.loadSettings()
        lastDailyStopTrigger = runtimeStateStore.loadLastDailyStopTrigger()
        refreshClickPositionValidity()
        loginItemStatus = loginItem.status()
        settings.launchAtLogin = loginItemStatus == .enabled
        let permissionGranted = accessibility.isTrusted()
        isAccessibilityTrusted = permissionGranted
        if !permissionGranted {
            accessibility.requestAccess()
        }
        machine.restore(
            activeIntent: runtimeStateStore.loadActiveIntent() ?? false,
            permissionGranted: permissionGranted,
            now: now(),
            initialDelay: initialDelay()
        )
        publishMachineState()
        registerStoredShortcut()

        inputMonitor.start { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePhysicalInput(at: self.now())
            }
        }
        systemActivityObserver.start(
            onSuspend: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleSystemSuspend()
                }
            },
            onResume: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handleSystemResume(at: self.now())
                }
            },
            onDisplayReconfiguration: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handleDisplayReconfiguration(at: self.now())
                }
            }
        )
        scheduler.start { [weak self] tickDate in
            Task { @MainActor [weak self] in
                self?.handleTick(at: tickDate)
            }
        }
    }

    public func shutdown() {
        inputMonitor.stop()
        systemActivityObserver.stop()
        scheduler.stop()
        hasStarted = false
    }

    public func toggleActive() {
        toggleActive(showHUD: false)
    }

    public func setSilentModeEnabled(_ enabled: Bool) {
        settings.isSilentModeEnabled = enabled
        persistSettings()
    }

    public func setSmartMotionEnabled(_ enabled: Bool) {
        settings.isSmartMotionEnabled = enabled
        persistSettings()
    }

    public func setClickMode(_ mode: ClickMode) throws {
        guard mode != .none else {
            try settings.setClickMode(.none)
            persistSettings()
            return
        }
        guard settings.clickPosition != nil, isClickPositionValid else {
            pendingClickMode = mode
            selectClickPosition()
            throw DriftSettingsError.clickPositionRequired
        }
        try settings.setClickMode(mode)
        persistSettings()
    }

    public func selectClickPosition() {
        guard !isSelectingClickPosition else { return }
        isSelectingClickPosition = true
        clickPositionSelector.select { [weak self] result in
            Task { @MainActor [weak self] in
                self?.finishClickPositionSelection(result)
            }
        }
    }

    public func cancelClickPositionSelection() {
        guard isSelectingClickPosition else { return }
        clickPositionSelector.cancel()
    }

    public func clearClickPosition() {
        clickPositionSelector.cancel()
        pendingClickMode = nil
        settings.clickPosition = nil
        try? settings.setClickMode(.none)
        isSelectingClickPosition = false
        refreshClickPositionValidity()
        persistSettings()
    }

    public func setDailyStop(_ dailyStop: DailyStopSettings) {
        settings.dailyStop = dailyStop
        persistSettings()
    }

    public func setBatteryStop(_ batteryStop: BatteryStopSettings) {
        var normalized = batteryStop
        normalized.thresholdPercent = min(50, max(5, normalized.thresholdPercent))
        settings.batteryStop = normalized
        persistSettings()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        let result = loginItem.setEnabled(enabled)
        switch result {
        case .success(let status) where (enabled && status == .enabled) || (!enabled && status == .disabled):
            loginItemStatus = status
            settings.launchAtLogin = enabled
            clearLastError(withPrefix: "Launch at Login")
            persistSettings()
        case .success(let status):
            loginItemStatus = status
            settings.launchAtLogin = status == .enabled
            lastError = loginErrorMessage(for: status)
            persistSettings()
        case .failure(let error):
            let observedStatus = loginItem.status()
            loginItemStatus = observedStatus
            settings.launchAtLogin = observedStatus == .enabled
            lastError = loginErrorMessage(for: error)
            persistSettings()
        }
    }

    public func refreshLoginItemStatus() {
        let observedStatus = loginItem.status()
        let launchAtLogin = observedStatus == .enabled
        let statusChanged = loginItemStatus != observedStatus
        let launchSettingChanged = settings.launchAtLogin != launchAtLogin

        if statusChanged {
            loginItemStatus = observedStatus
            clearLastError(withPrefix: "Launch at Login")
        }
        if launchSettingChanged {
            settings.launchAtLogin = launchAtLogin
            persistSettings()
        }
    }

    public func setToggleShortcut(_ shortcut: GlobalShortcut?) {
        settings.toggleShortcut = shortcut
        shortcutRegistrationError = nil
        guard let shortcut else {
            globalShortcut.unregister()
            clearLastError(equalTo: "Shortcut registration failed")
            persistSettings()
            return
        }
        switch registerShortcut(shortcut) {
        case .success:
            clearLastError(equalTo: "Shortcut registration failed")
            persistSettings()
        case .failure(let error):
            shortcutRegistrationError = error
            lastError = "Shortcut registration failed"
            persistSettings()
        }
    }

    public func openAccessibilitySettings() {
        accessibility.requestAccess()
        accessibility.openSystemSettings()
    }

    public func setStartDelay(_ delay: StartDelay) {
        settings.startDelay = delay
        persistSettings()
    }

    public func setRepeatInterval(_ interval: RepeatInterval) {
        settings.repeatInterval = interval
        persistSettings()
    }

    public func handleTick(at date: Date) {
        refreshAccessibilityTrust(at: date)
        guard machine.activeIntent else { return }
        refreshClickPositionValidity()
        if let trigger = dailyStopPolicy.trigger(
            now: date,
            settings: settings.dailyStop,
            lastTrigger: lastDailyStopTrigger,
            calendar: calendar
        ) {
            lastDailyStopTrigger = trigger
            runtimeStateStore.saveLastDailyStopTrigger(trigger)
            deactivate(reason: HUDMessage(title: "Drift Inactive", subtitle: "Stopped by schedule"), at: date)
            return
        }
        if lastPowerCheckAt.map({ date.timeIntervalSince($0) >= 60 }) ?? true {
            lastPowerCheckAt = date
            let snapshot = powerSource.snapshot()
            if batteryStopPolicy.shouldDeactivate(snapshot: snapshot, settings: settings.batteryStop) {
                let subtitle = "Stopped at \(settings.batteryStop.thresholdPercent)% battery"
                deactivate(reason: HUDMessage(title: "Drift Inactive", subtitle: subtitle), at: date)
                return
            }
        }
        guard machine.evaluate(at: date) == .beginMotion else { return }
        if pointerButtonState.isAnyButtonPressed() {
            machine.recordPhysicalActivity(at: date, initialDelay: initialDelay())
            publishMachineState()
            return
        }
        publishMachineState()

        let start = cursorLocation.currentLocation()
        if settings.clickMode != .none {
            executeClickSequence(start: start, at: date)
            return
        }
        guard let bounds = displayGeometry.visibleFrame(containing: start) else {
            machine.motionCancelled(at: date, initialDelay: initialDelay())
            publishMachineState()
            return
        }
        let destination = destinationPicker.pick(in: bounds, random: random)
        let plan = pathGenerator.makePlan(
            isSilentModeEnabled: settings.isSilentModeEnabled,
            isSmartMotionEnabled: settings.isSmartMotionEnabled,
            start: start,
            destination: destination,
            bounds: bounds,
            random: random
        )
        motionExecutor.execute(plan) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleMotionCompletion(result, at: self.now())
            }
        }
    }

    public func handlePhysicalInput(at date: Date) {
        motionExecutor.cancel()
        machine.recordPhysicalActivity(at: date, initialDelay: initialDelay())
        publishMachineState()
    }

    public func handleSystemSuspend() {
        motionExecutor.cancel()
        machine.suspend()
        publishMachineState()
    }

    public func handleSystemResume(at date: Date) {
        let permissionGranted = accessibility.isTrusted()
        isAccessibilityTrusted = permissionGranted
        machine.resume(
            permissionGranted: permissionGranted,
            at: date,
            initialDelay: initialDelay()
        )
        publishMachineState()
    }

    public func handleDisplayReconfiguration(at date: Date) {
        clickPositionSelector.cancel()
        motionExecutor.cancel()
        refreshClickPositionValidity()
        machine.recordPhysicalActivity(at: date, initialDelay: initialDelay())
        publishMachineState()
    }

    private func executeClickSequence(start: CGPoint, at date: Date) {
        guard let position = settings.clickPosition, isClickPositionValid else {
            lastError = "Invalid click position"
            machine.motionCancelled(at: date, initialDelay: initialDelay())
            publishMachineState()
            return
        }
        let clickPoint = CGPoint(x: position.x, y: position.y)
        guard let bounds = displayGeometry.visibleFrame(containing: clickPoint) else {
            lastError = "Invalid click position"
            machine.motionCancelled(at: date, initialDelay: initialDelay())
            publishMachineState()
            return
        }
        let departurePosition = destinationPicker.pick(
            in: bounds,
            avoiding: clickPoint,
            minimumDistance: 96,
            random: random
        )
        guard let sequence = clickPlanner.makePlan(
            isSmartMotionEnabled: settings.isSmartMotionEnabled,
            clickMode: settings.clickMode,
            nextAlternatingButton: runtimeStateStore.loadNextAlternatingButton(),
            start: start,
            clickPosition: clickPoint,
            departurePosition: departurePosition,
            bounds: bounds,
            random: random
        ) else {
            machine.motionCancelled(at: date, initialDelay: initialDelay())
            publishMachineState()
            return
        }
        motionExecutor.execute(sequence) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleClickCompletion(result, at: self.now())
            }
        }
    }

    private func handleMotionCompletion(
        _ result: Result<Void, CursorEventServiceError>,
        at date: Date
    ) {
        completeMotion(result, at: date, completedClick: false)
    }

    private func handleClickCompletion(
        _ result: Result<Void, CursorEventServiceError>,
        at date: Date
    ) {
        completeMotion(result, at: date, completedClick: true)
    }

    private func completeMotion(
        _ result: Result<Void, CursorEventServiceError>,
        at date: Date,
        completedClick: Bool
    ) {
        if case .success = result,
           completedClick,
           settings.clickMode == .alternating,
           machine.activeIntent {
            let nextButton = runtimeStateStore.loadNextAlternatingButton().opposite
            runtimeStateStore.saveNextAlternatingButton(nextButton)
        }
        guard machine.phase == .performingMotion else { return }
        switch result {
        case .success:
            machine.motionFinished(at: date, repeatDelay: repeatDelay())
        case .failure(.cancelled):
            machine.motionCancelled(at: date, initialDelay: initialDelay())
        case .failure(let error):
            lastError = String(describing: error)
            machine.motionFinished(at: date, repeatDelay: repeatDelay())
        }
        publishMachineState()
    }

    private func deactivate(reason: HUDMessage, at date: Date) {
        motionExecutor.cancel()
        machine.setActive(false, permissionGranted: true, now: date, initialDelay: 0)
        runtimeStateStore.saveActiveIntent(false)
        publishMachineState()
        hudPresenter.show(reason)
    }

    private func finishClickPositionSelection(_ result: Result<ClickPosition, ClickPositionSelectionError>) {
        isSelectingClickPosition = false
        defer { pendingClickMode = nil }
        guard case .success(let position) = result else { return }
        settings.clickPosition = position
        refreshClickPositionValidity()
        guard isClickPositionValid else {
            lastError = "Invalid click position"
            persistSettings()
            return
        }
        if let pendingClickMode {
            try? settings.setClickMode(pendingClickMode)
        }
        persistSettings()
    }

    private func refreshClickPositionValidity() {
        guard let position = settings.clickPosition else {
            isClickPositionValid = false
            clearLastError(equalTo: "Invalid click position")
            return
        }
        isClickPositionValid = clickPositionValidator.isValid(position, in: displayGeometry.screenFrames())
        if isClickPositionValid {
            clearLastError(equalTo: "Invalid click position")
        }
    }

    private func toggleActive(showHUD: Bool) {
        let active = !machine.activeIntent
        if !active {
            motionExecutor.cancel()
        }
        let permissionGranted = accessibility.isTrusted()
        isAccessibilityTrusted = permissionGranted
        machine.setActive(
            active,
            permissionGranted: permissionGranted,
            now: now(),
            initialDelay: active ? initialDelay() : 0
        )
        runtimeStateStore.saveActiveIntent(active)
        publishMachineState()
        if showHUD {
            if active, !permissionGranted {
                hudPresenter.show(HUDMessage(
                    title: "Accessibility Required",
                    subtitle: "Open System Settings to activate Drift"
                ))
            } else {
                hudPresenter.show(HUDPresentation.message(isActive: active))
            }
        }
    }

    private func registerStoredShortcut() {
        guard let shortcut = settings.toggleShortcut else { return }
        switch registerShortcut(shortcut) {
        case .success:
            shortcutRegistrationError = nil
        case .failure(let error):
            shortcutRegistrationError = error
            lastError = "Shortcut registration failed"
        }
    }

    private func registerShortcut(_ shortcut: GlobalShortcut) -> Result<Void, GlobalShortcutError> {
        globalShortcut.register(shortcut) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleActive(showHUD: true)
            }
        }
    }

    private func loginErrorMessage(for status: LoginItemStatus) -> String {
        switch status {
        case .requiresApproval:
            "Launch at Login requires approval in System Settings"
        case .enabled, .disabled, .unavailable:
            "Launch at Login could not be changed"
        }
    }

    private func loginErrorMessage(for error: LoginItemError) -> String {
        switch error {
        case .requiresApproval:
            "Launch at Login requires approval in System Settings"
        case .operationFailed:
            "Launch at Login could not be changed"
        case .statusMismatch(let status):
            loginErrorMessage(for: status)
        }
    }

    private func initialDelay() -> TimeInterval {
        timingPolicy.initialDelay(settings: settings, random: random)
    }

    private func repeatDelay() -> TimeInterval {
        timingPolicy.repeatDelay(settings: settings, random: random)
    }

    private func refreshAccessibilityTrust(at date: Date) {
        let permissionGranted = accessibility.isTrusted()
        guard permissionGranted != isAccessibilityTrusted else { return }
        isAccessibilityTrusted = permissionGranted
        guard machine.activeIntent else { return }
        if !permissionGranted {
            motionExecutor.cancel()
        }
        machine.permissionChanged(
            isGranted: permissionGranted,
            now: date,
            initialDelay: initialDelay()
        )
        publishMachineState()
    }

    private func clearLastError(equalTo message: String) {
        if lastError == message {
            lastError = nil
        }
    }

    private func clearLastError(withPrefix prefix: String) {
        if lastError?.hasPrefix(prefix) == true {
            lastError = nil
        }
    }

    private func persistSettings() {
        do {
            try settingsStore.saveSettings(settings)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func publishMachineState() {
        phase = machine.phase
        isActiveIntent = machine.activeIntent
    }
}
