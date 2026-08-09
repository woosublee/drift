import AppKit
import DriftCore

@MainActor
final class DriftApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: DriftAppModel?
    private var menuBarController: MenuBarController?
    private var cursorEventService: CursorEventService?
    private var clickPositionSelector: ClickPositionSelector?
    private var hudPresenter: HUDPresenter?
    private var globalShortcutService: GlobalShortcutService?
    private var updateService: UpdateService?
    private var shutdownCoordinator: ApplicationShutdownCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let displayGeometry = DisplayGeometryService()
        let cursorEventService = CursorEventService(
            sink: CoreGraphicsCursorEventSink(),
            sleeper: SystemMicrosecondSleeper()
        )
        let selector = ClickPositionSelector(
            screenFrames: { displayGeometry.screenFrames() },
            overlayProvider: SystemOverlayWindowProvider()
        )
        let hudPresenter = HUDPresenter(cursorLocation: displayGeometry, displayGeometry: displayGeometry)
        let globalShortcutService = GlobalShortcutService()
        let updateService = UpdateService(
            configuration: UpdateConfiguration.load(from: Bundle.main.infoDictionary ?? [:]),
            factory: SparkleUpdaterControllerFactory()
        )
        let appModel = DriftAppModel(
            settingsStore: UserDefaultsSettingsStore(),
            runtimeStateStore: UserDefaultsRuntimeStateStore(),
            accessibility: AccessibilityCoordinator(),
            cursorLocation: displayGeometry,
            displayGeometry: displayGeometry,
            motionExecutor: cursorEventService,
            inputMonitor: InputActivityMonitor(),
            systemActivityObserver: SystemActivityObserver(),
            scheduler: TickScheduler(),
            random: SystemDriftRandomSource(),
            clickPositionSelector: selector,
            powerSource: PowerSourceService(),
            hudPresenter: hudPresenter,
            loginItem: LoginItemService(),
            globalShortcut: globalShortcutService
        )
        self.cursorEventService = cursorEventService
        self.clickPositionSelector = selector
        self.hudPresenter = hudPresenter
        self.globalShortcutService = globalShortcutService
        self.updateService = updateService
        appModel.start()
        model = appModel

        let menuBarController = MenuBarController(model: appModel, updateService: updateService)
        self.menuBarController = menuBarController
        shutdownCoordinator = ApplicationShutdownCoordinator(hooks: ShutdownHooks(
            closeOverlays: { [weak selector] in selector?.cancel() },
            unregisterShortcut: { [weak globalShortcutService] in globalShortcutService?.unregister() },
            shutdownModel: { [weak appModel] in appModel?.shutdown() },
            cancelCursor: { [weak cursorEventService] in cursorEventService?.cancelAndWait() },
            dismissHUD: { [weak hudPresenter] in hudPresenter?.dismiss() },
            stopUpdater: { [weak updateService] in updateService?.stop() },
            removeStatusItem: { [weak menuBarController] in menuBarController?.stop() }
        ))
        updateService.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdownCoordinator?.shutdown()
    }
}
