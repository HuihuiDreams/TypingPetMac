import AppKit
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - AppDelegate

@MainActor
internal final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let imageLibrary = PetImageLibrary()
    private let keyReactionStore = KeyReactionStore()
    private var statusItem: NSStatusItem!
    private var petController: PetController!
    private var keyMonitor: GlobalKeyMonitor!
    private var menu: NSMenu!
    private var petVisibilityItem: NSMenuItem!
    private var positionLockedItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var monitoringStatusItem: NSMenuItem!
    private var permissionRetryTimer: Timer?
    private var didShowPermissionAlert = false
    private var settingsWindowController: SettingsWindowController?
    private var settingsModel: TypingPetSettingsModel?
    private var inputMonitoringGuideController: InputMonitoringGuideController?

    override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        petController = PetController(
            library: imageLibrary,
            keyStore: keyReactionStore,
            onScaleChanged: { [weak self] scale in self?.settingsModel?.syncScale(scale) }
        )
        configureStatusItem()

        // 事件源挂在主 RunLoop 上（见 GlobalKeyMonitor.start），回调已在主线程执行。
        keyMonitor = GlobalKeyMonitor { [weak self] stroke in
            MainActor.assumeIsolated {
                self?.petController.handleKeystroke(stroke)
            }
        }

        startMonitoringOrRequestPermission(shouldShowAlert: true)

        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRetryTimer?.invalidate()
        keyMonitor.stop()
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
        petVisibilityItem.title = petController.isPetVisible ? "隐藏宠物" : "重新显示宠物"
        positionLockedItem.state = petController.isPositionLocked ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateMonitoringStatusItem()
    }

    @objc private func toggleAlwaysOnTop() {
        petController.isAlwaysOnTop.toggle()
    }

    @objc private func togglePetVisibility() {
        petController.togglePetVisibility()
    }

    @objc private func togglePositionLock() {
        petController.isPositionLocked.toggle()
    }

    @objc private func resetPosition() {
        petController.resetPosition()
    }

    @objc private func setSmallSize() {
        petController.scale = AppPreferencesDefault.smallScale
    }

    @objc private func setMediumSize() {
        petController.scale = AppPreferencesDefault.mediumScale
    }

    @objc private func setLargeSize() {
        petController.scale = AppPreferencesDefault.largeScale
    }

    @objc private func setExtraLargeSize() {
        petController.scale = AppPreferencesDefault.extraLargeScale
    }

    @objc private func changeIdleImage() {
        guard let url = chooseImageFiles(
            title: "选择待机图像",
            message: "请选择无按键输入时显示的图像。",
            allowsMultipleSelection: false
        )?.first else { return }

        do {
            try imageLibrary.replaceIdle(with: url)
            petController.reloadImages()
        } catch {
            showImageError(error)
        }
    }

    @objc private func replaceReactionImages() {
        guard let urls = chooseImageFiles(
            title: "选择反应图像",
            message: "请选择按下按键时随机显示的一张或多张图像。",
            allowsMultipleSelection: true
        ), !urls.isEmpty else { return }

        do {
            try imageLibrary.replaceReactions(with: urls)
            petController.reloadImages()
        } catch {
            showImageError(error)
        }
    }

    @objc private func importImageFolder() {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        let panel = NSOpenPanel()
        panel.title = "导入图像文件夹"
        panel.message = "idle.* 或 pet-idle.* 作为待机图像，其余作为按键输入反应图像导入。"
        panel.prompt = "导入"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        do {
            let result = try imageLibrary.importFolder(folderURL)
            petController.reloadImages()

            var parts: [String] = []
            if result.changedIdle {
                parts.append("待机图像 1 张")
            }
            if let reactionCount = result.reactionCount {
                parts.append("反应图像 \(reactionCount) 张")
            }
            showAlert(
                title: "图像导入成功",
                message: "已应用 " + parts.joined(separator: ", ") + "。",
                primaryButton: "好"
            )
        } catch {
            showImageError(error)
        }
    }

    @objc private func showImageFolderRules() {
        showAlert(
            title: "图像集文件夹规则",
            message: "文件名无限制。若包含 idle.* 或 pet-idle.* 文件，将作为待机图像，其余作为按键输入反应图像。若无待机图像，则按文件名排序的第一张作为待机图像。若仅有 1 张图像，则同时用于待机和反应。支持 PNG、APNG、JPG、GIF、TIFF、HEIC、WebP 格式。",
            primaryButton: "好"
        )
    }

    @objc private func resetImages() {
        showAlert(
            title: "确定恢复为默认图像吗？",
            message: "将当前选中的待机图像和反应图像设置恢复为默认值。不会修改原始图像文件。",
            primaryButton: "恢复",
            secondaryButton: "取消"
        ) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.imageLibrary.resetToDefaults()
            self?.petController.reloadImages()
        }
    }

    @objc private func restartMonitoring() {
        startMonitoringOrRequestPermission(shouldShowAlert: true)
    }

    @objc private func previewReaction() {
        petController.handleKeystroke(nil)
    }

    @objc private func showSettings() {
        if settingsModel == nil {
            settingsModel = TypingPetSettingsModel(
                library: imageLibrary,
                keyStore: keyReactionStore,
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
                currentPositionLock: { [weak self] in self?.petController.isPositionLocked ?? AppPreferencesDefault.positionLocked },
                applyPointerAvoidance: { [weak self] in self?.petController.avoidsPointerWhenLocked = $0 },
                reloadPet: { [weak self] in self?.petController.reloadImages() },
                openInputMonitoringSettings: { [weak self] in self?.openInputMonitoringSettings() }
            )
        }
        settingsModel?.refresh()
        if settingsWindowController == nil, let settingsModel {
            settingsWindowController = SettingsWindowController(model: settingsModel)
        }
        settingsWindowController?.show()
    }

    @objc private func openInputMonitoringSettings() {
        InputMonitoringSettings.open()
        guard !CGPreflightListenEventAccess() else { return }

        if inputMonitoringGuideController == nil {
            inputMonitoringGuideController = InputMonitoringGuideController { [weak self] in
                self?.retryMonitoringIfAuthorized()
                self?.settingsModel?.refresh()
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
                title: "设置自动启动失败",
                message: error.localizedDescription,
                primaryButton: "好"
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Typing Pet")
            image?.isTemplate = true
            button.image = image
        }

        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(makeMenuItem("设置", action: #selector(showSettings), keyEquivalent: ","))
        petVisibilityItem = makeMenuItem("隐藏宠物", action: #selector(togglePetVisibility))
        menu.addItem(petVisibilityItem)
        menu.addItem(.separator())

        positionLockedItem = makeMenuItem("锁定位置 (点击穿透)", action: #selector(togglePositionLock))
        menu.addItem(positionLockedItem)
        menu.addItem(makeMenuItem("重置位置", action: #selector(resetPosition)))
        menu.addItem(.separator())
        monitoringStatusItem = NSMenuItem(title: "按键监听 (检测中)", action: nil, keyEquivalent: "")
        monitoringStatusItem.isEnabled = true
        menu.addItem(monitoringStatusItem)
        updateMonitoringStatusItem()
        menu.addItem(makeMenuItem("输入监控设置", action: #selector(openInputMonitoringSettings)))
        menu.addItem(.separator())

        loginItem = makeMenuItem("登录时自动启动", action: #selector(toggleLaunchAtLogin))
        menu.addItem(loginItem)
        menu.addItem(makeMenuItem("退出 Typing Pet", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func updateMonitoringStatusItem() {
        let isAvailable = keyMonitor?.isRunning == true
        let title = isAvailable ? "按键监听 (正常)" : "按键监听 (未授权/异常)"
        monitoringStatusItem.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: isAvailable ? NSColor.systemGreen : NSColor.systemRed
            ]
        )
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

    private func chooseImageFiles(
        title: String,
        message: String,
        allowsMultipleSelection: Bool
    ) -> [URL]? {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls : nil
    }

    private func showImageError(_ error: Error) {
        showAlert(
            title: "无法应用图像",
            message: error.localizedDescription,
            primaryButton: "好"
        )
    }

    private func startMonitoringOrRequestPermission(shouldShowAlert: Bool) {
        if CGPreflightListenEventAccess(), keyMonitor.start() {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
            return
        }

        schedulePermissionRetry()
        guard shouldShowAlert, !didShowPermissionAlert else { return }
        didShowPermissionAlert = true
        _ = CGRequestListenEventAccess()
        showAlert(
            title: "需要输入监控权限",
            message: "Typing Pet 不会读取或保存您的输入内容，仅检测是否有按键按下。在系统设置中允许 Typing Pet 的输入监控权限后，应用将自动恢复连接。",
            primaryButton: "打开系统设置",
            secondaryButton: "稍后"
        ) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.openInputMonitoringSettings()
            }
        }
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
        guard !keyMonitor.isRunning, CGPreflightListenEventAccess() else { return }
        if keyMonitor.start() {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
        }
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
