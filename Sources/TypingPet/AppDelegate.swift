import AppKit
import CoreGraphics
import ServiceManagement

// MARK: - AppDelegate

@MainActor
internal final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let imageLibrary = PetImageLibrary()
    private let keyReactionStore = KeyReactionStore()
    private lazy var packStore = PetPackStore(library: imageLibrary, keyStore: keyReactionStore)
    private let todoStore: TodoStore = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["TYPINGPET_TODO_TEST_PATH"] {
            return TodoStore(url: URL(fileURLWithPath: path))
        }
        #endif
        return TodoStore()
    }()
    private var todoBubble: TodoBubbleWindowController?
    private var statusItem: NSStatusItem!
    private var petController: PetController!
    private var keyMonitor: GlobalKeyMonitor!
    private var menu: NSMenu!
    private var petVisibilityItem: NSMenuItem!
    private var positionLockedItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var monitoringStatusItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private let updater = UpdateController()
    private var permissionRetryTimer: Timer?
    private static let inputMonitoringWelcomeShownKey = AppPreferencesKey.inputMonitoringWelcomeShown
    private static let inputMonitoringSetupPendingKey = AppPreferencesKey.inputMonitoringSetupPending
    private var settingsWindowController: SettingsWindowController?
    private var settingsModel: TypingPetSettingsModel?
    private var inputMonitoringGuideController: InputMonitoringGuideController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TextEditingShortcuts.installEditMenu(appName: AppEnvironment.displayName)
        BackgroundCursor.enable()
        petController = PetController(
            library: imageLibrary,
            packStore: packStore,
            onScaleChanged: { [weak self] scale in self?.settingsModel?.syncScale(scale) },
            onOpenSettings: { [weak self] in self?.showSettings() }
        )
        todoBubble = TodoBubbleWindowController(store: todoStore, pet: petController.todoAnchorWindow)
        petController.shouldHoldPosition = { [weak self] in self?.todoBubble?.isInteracting == true }
        petController.onPresentationChanged = { [weak self] in self?.todoBubble?.synchronize() }
        configureStatusItem()

        updater.isTimerRunning = { [weak self] in self?.todoStore.engine.activeSession?.status == .running }
        updater.onChange = { [weak self] in self?.updateUpdateItem() }
        updater.start()

        keyMonitor = GlobalKeyMonitor { [weak self] stroke in
            DispatchQueue.main.async {
                self?.petController.handleKeystroke(stroke)
                self?.inputMonitoringGuideController?.receivedGlobalKeystroke()
            }
        }

        let shouldShowWelcome = !AppEnvironment.isDevelopment
            && !(AppEnvironment.defaults.object(forKey: Self.inputMonitoringWelcomeShownKey) as? Bool ?? AppPreferencesDefault.inputMonitoringWelcomeShown)
        let shouldResumeSetup = !AppEnvironment.isDevelopment
            && (AppEnvironment.defaults.object(forKey: Self.inputMonitoringSetupPendingKey) as? Bool ?? AppPreferencesDefault.inputMonitoringSetupPending)

        #if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("--todo-preview"),
           !ProcessInfo.processInfo.arguments.contains("--input-guide-preview") {
            startMonitoring(showGuideIfNeeded: shouldShowWelcome)
            if shouldResumeSetup { showInputMonitoringGuide() }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-todos") { showTodos() }
        if ProcessInfo.processInfo.arguments.contains("--install-update-now") { updater.installNowForChecks() }
        if ProcessInfo.processInfo.arguments.contains("--show-input-guide") { showInputMonitoringGuide() }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--input-guide-preview"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let phase = InputMonitoringGuideModel.Phase(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            inputMonitoringGuideController = .preview(
                phase: phase, idleURL: packStore.idleURL, reactionURLs: imageLibrary.reactionURLs
            )
            inputMonitoringGuideController?.show()
        }
        #else
        startMonitoring(showGuideIfNeeded: shouldShowWelcome)
        if shouldResumeSetup { showInputMonitoringGuide() }
        #endif

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(retryMonitoringIfAuthorized),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        todoStore.pauseForSleepOrTermination()
        guard let error = todoStore.errorMessage, !todoStore.loadBlocked else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("Could not save Todo records")
        alert.informativeText = error
        alert.addButton(withTitle: L("Save Again"))
        alert.addButton(withTitle: L("Cancel"))
        alert.addButton(withTitle: L("Quit Without Saving"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            todoStore.persist()
            return todoStore.errorMessage == nil ? .terminateNow : .terminateCancel
        case .alertThirdButtonReturn: return .terminateNow
        default: return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        permissionRetryTimer?.invalidate()
        keyMonitor.stop()
        updater.applicationWillTerminate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        retryMonitoringIfAuthorized()
        settingsModel?.refresh()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !petController.isPetVisible {
            petController.showPet()
        }
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        petVisibilityItem.title = petController.isPetVisible ? L("Hide Pet") : L("Show Pet Again")
        positionLockedItem.state = petController.isPositionLocked ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateMonitoringStatusItem()
        updateUpdateItem()
    }

    @objc private func togglePetVisibility() {
        petController.togglePetVisibility()
    }

    @objc private func togglePositionLock() {
        petController.isPositionLocked.toggle()
        settingsModel?.refresh()
    }

    @objc private func resetPosition() {
        petController.resetPosition()
    }

    @objc private func handleScreenParametersChanged() {
        petController.clampToVisibleScreen()
    }

    @objc private func showTodos() {
        petController.showPet()
        todoBubble?.show()
    }

    @objc private func showSettings() {
        if settingsModel == nil {
            settingsModel = TypingPetSettingsModel(
                library: imageLibrary,
                keyStore: keyReactionStore,
                packStore: packStore,
                scale: petController.scale,
                restingOpacity: petController.restingOpacity,
                hoverOpacity: petController.hoverOpacity,
                shakeLevel: petController.shakeLevel,
                alwaysOnTop: petController.isAlwaysOnTop,
                positionLocked: petController.isPositionLocked,
                avoidsPointerWhenLocked: petController.avoidsPointerWhenLocked,
                applyScale: { [weak self] in self?.petController.scale = $0 },
                applyRestingOpacity: { [weak self] in self?.petController.restingOpacity = $0 },
                applyHoverOpacity: { [weak self] in self?.petController.hoverOpacity = $0 },
                applyShake: { [weak self] in self?.petController.shakeLevel = $0 },
                applyAlwaysOnTop: { [weak self] in self?.petController.isAlwaysOnTop = $0 },
                applyPositionLock: { [weak self] in self?.petController.isPositionLocked = $0 },
                currentPositionLock: { [weak self] in self?.petController.isPositionLocked == true },
                applyPointerAvoidance: { [weak self] in self?.petController.avoidsPointerWhenLocked = $0 },
                reloadPet: { [weak self] in self?.petController.reloadImages() },
                openInputMonitoringSettings: { [weak self] in self?.openInputMonitoringSettings() },
                monitoringIsRunning: { [weak self] in self?.keyMonitor?.isRunning == true },
                retryMonitoring: { [weak self] in _ = self?.connectMonitoring(restart: true) }
            )
        }
        settingsModel?.refresh()
        if settingsWindowController == nil, let settingsModel {
            settingsWindowController = SettingsWindowController(model: settingsModel, todoStore: todoStore, updater: updater)
        }
        settingsWindowController?.show()
    }

    @objc private func openInputMonitoringSettings() {
        if CGPreflightListenEventAccess(), keyMonitor.isRunning {
            InputMonitoringSettings.open()
        } else {
            showInputMonitoringGuide()
        }
    }

    private func showInputMonitoringGuide() {
        AppEnvironment.defaults.set(true, forKey: Self.inputMonitoringWelcomeShownKey)
        if inputMonitoringGuideController == nil {
            inputMonitoringGuideController = InputMonitoringGuideController(
                idleURL: packStore.idleURL,
                reactionURLs: imageLibrary.reactionURLs,
                resumeSetup: AppEnvironment.defaults.object(forKey: Self.inputMonitoringSetupPendingKey) as? Bool ?? AppPreferencesDefault.inputMonitoringSetupPending,
                onSetupStarted: {
                    AppEnvironment.defaults.set(true, forKey: Self.inputMonitoringSetupPendingKey)
                },
                onDismiss: {
                    AppEnvironment.defaults.set(false, forKey: Self.inputMonitoringSetupPendingKey)
                }
            ) { [weak self] restart in
                let connected = self?.connectMonitoring(restart: restart) ?? false
                self?.settingsModel?.refresh()
                return connected
            }
        }
        inputMonitoringGuideController?.show()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(
                title: L("Could not change launch at login"),
                message: error.localizedDescription,
                primaryButton: L("OK")
            )
        }
    }

    @objc private func performUpdateAction() {
        updater.performPrimaryAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: AppEnvironment.isDevelopment ? NSStatusItem.variableLength : NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: AppEnvironment.isDevelopment ? "flask.fill" : "pawprint.fill", accessibilityDescription: AppEnvironment.displayName)
            image?.isTemplate = true
            button.image = image
            button.toolTip = AppEnvironment.displayName
            if AppEnvironment.isDevelopment {
                button.title = " DEV"
                button.imagePosition = .imageLeading
            }
        }

        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(makeMenuItem(L("Show Todos"), action: #selector(showTodos)))
        menu.addItem(makeMenuItem(L("Settings"), action: #selector(showSettings), keyEquivalent: ","))
        petVisibilityItem = makeMenuItem(L("Hide Pet"), action: #selector(togglePetVisibility))
        menu.addItem(petVisibilityItem)
        menu.addItem(.separator())

        positionLockedItem = makeMenuItem(L("Lock position (click through)"), action: #selector(togglePositionLock))
        menu.addItem(positionLockedItem)
        menu.addItem(makeMenuItem(L("Reset Position"), action: #selector(resetPosition)))
        menu.addItem(.separator())
        monitoringStatusItem = NSMenuItem(title: L("Key detection (checking)"), action: nil, keyEquivalent: "")
        monitoringStatusItem.isEnabled = true
        menu.addItem(monitoringStatusItem)
        updateMonitoringStatusItem()
        menu.addItem(makeMenuItem(L("Input Monitoring Settings"), action: #selector(openInputMonitoringSettings)))
        menu.addItem(.separator())

        loginItem = makeMenuItem(L("Launch at login"), action: #selector(toggleLaunchAtLogin))
        menu.addItem(loginItem)
        updateItem = makeMenuItem(L("Check for Updates…"), action: #selector(performUpdateAction))
        menu.addItem(updateItem)
        updateUpdateItem()
        menu.addItem(makeMenuItem(L("Quit %1$@", AppEnvironment.displayName), action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func updateMonitoringStatusItem() {
        let isAvailable = keyMonitor?.isRunning == true
        let title = isAvailable ? L("Key detection (available)") : L("Key detection (unavailable)")
        monitoringStatusItem.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: isAvailable ? NSColor.systemGreen : NSColor.systemRed
            ]
        )
    }

    private func updateUpdateItem() {
        guard let updateItem else { return }
        updateItem.title = updater.menuTitle
        updateItem.isEnabled = !updater.isBusy
    }

    private func makeMenuItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func startMonitoring(showGuideIfNeeded: Bool) {
        if connectMonitoring() { return }
        schedulePermissionRetry()
        if showGuideIfNeeded { showInputMonitoringGuide() }
    }

    @discardableResult
    private func connectMonitoring(restart: Bool = false) -> Bool {
        guard CGPreflightListenEventAccess() else { return false }
        if restart { keyMonitor.stop() }
        let connected = keyMonitor.isRunning || keyMonitor.start()
        if connected {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
        } else {
            schedulePermissionRetry()
        }
        updateMonitoringStatusItem()
        return connected
    }

    private func schedulePermissionRetry() {
        guard permissionRetryTimer == nil else { return }
        permissionRetryTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(retryMonitoringIfAuthorized),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func retryMonitoringIfAuthorized() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--todo-preview")
            || ProcessInfo.processInfo.arguments.contains("--input-guide-preview") { return }
        #endif
        connectMonitoring()
    }

    private func showAlert(
        title: String,
        message: String,
        primaryButton: String,
        secondaryButton: String? = nil,
        completion: ((NSApplication.ModalResponse) -> Void)? = nil
    ) {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        let response = alert.runModal()
        completion?(response)
    }
}
