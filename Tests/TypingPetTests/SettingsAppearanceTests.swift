import AppKit
import Testing
@testable import TypingPet

@Suite struct SettingsAppearanceTests {
    @Test func settingsWidthMatchesReferenceAndGrowsWithText() {
        #expect(SettingsWindowSizing.contentSize(fontSize: 13).width == 1100)
        #expect(SettingsWindowSizing.contentSize(fontSize: 26).width == 2200)
    }

    @Test @MainActor
    func bubbleAppearanceUpdatesAndSystemClearsOverride() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BubbleAppearance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TodoStore(url: root.appendingPathComponent("todos.json"))
        let controller = TodoBubbleWindowController(store: store, pet: NSWindow())
        controller.setAppearanceMode(.dark)
        #expect(controller.panel.appearance?.name == .darkAqua)
        controller.setAppearanceMode(.light)
        #expect(controller.panel.appearance?.name == .aqua)
        controller.setAppearanceMode(.system)
        #expect(controller.panel.appearance == nil)
    }

    @Test func storedAppearanceAndInvalidValue() throws {
        let suite = "TypingPetAppearanceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(SettingsAppearanceMode.load(from: defaults) == .system)
        defaults.set("dark", forKey: SettingsAppearanceMode.defaultsKey)
        #expect(SettingsAppearanceMode.load(from: defaults) == .dark)
        defaults.set("unknown", forKey: SettingsAppearanceMode.defaultsKey)
        #expect(SettingsAppearanceMode.load(from: defaults) == .system)
    }

    @Test @MainActor
    func permissionGrantAndEventTapConnectionAreReportedSeparately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PermissionStatus-\(UUID())")
        let suite = "TypingPetPermissionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        var granted = false
        var connected = false
        var retryCount = 0
        let model = TypingPetSettingsModel(
            library: PetImageLibrary(defaults: defaults, imagesDirectory: root.appendingPathComponent("Images")),
            keyStore: KeyReactionStore(defaults: defaults, directory: root.appendingPathComponent("Keys")),
            scale: 1, restingOpacity: 1, hoverOpacity: 1, shakeLevel: 0,
            alwaysOnTop: false, positionLocked: false, avoidsPointerWhenLocked: false,
            applyScale: { _ in }, applyRestingOpacity: { _ in }, applyHoverOpacity: { _ in }, applyShake: { _ in },
            applyAlwaysOnTop: { _ in }, applyPositionLock: { _ in }, applyPointerAvoidance: { _ in },
            reloadPet: {}, openInputMonitoringSettings: {},
            monitoringIsRunning: { connected }, retryMonitoring: { retryCount += 1; connected = true },
            inputMonitoringAuthorized: { granted }, defaults: defaults)
        model.refreshPermissions(retryConnection: true)
        #expect(!model.inputMonitoringGranted)
        #expect(!model.inputMonitoringConnected)
        #expect(retryCount == 0)
        granted = true
        model.refreshPermissions()
        #expect(model.inputMonitoringGranted)
        #expect(!model.inputMonitoringConnected)
        model.refreshPermissions(retryConnection: true)
        #expect(retryCount == 1)
        #expect(model.inputMonitoringConnected)
        granted = false
        model.refreshPermissions()
        #expect(!model.inputMonitoringConnected)
    }

    @Test @MainActor
    func changingModePersistsAndUpdatesWindowAppearance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TypingPetAppearance-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "TypingPetAppearanceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TypingPetSettingsModel(
            library: PetImageLibrary(defaults: defaults, imagesDirectory: root.appendingPathComponent("Images")),
            keyStore: KeyReactionStore(defaults: defaults, directory: root.appendingPathComponent("Keys")),
            scale: 1,
            restingOpacity: 1,
            hoverOpacity: 1,
            shakeLevel: 0,
            alwaysOnTop: false,
            positionLocked: false,
            avoidsPointerWhenLocked: false,
            applyScale: { _ in },
            applyRestingOpacity: { _ in },
            applyHoverOpacity: { _ in },
            applyShake: { _ in },
            applyAlwaysOnTop: { _ in },
            applyPositionLock: { _ in },
            applyPointerAvoidance: { _ in },
            reloadPet: {},
            openInputMonitoringSettings: {},
            defaults: defaults
        )
        let window = NSWindow()
        model.onAppearanceChanged = { window.appearance = $0.windowAppearance }
        let settings = SettingsWindowController(
            model: model,
            todoStore: TodoStore(url: root.appendingPathComponent("todos.json"), defaults: defaults),
            updater: UpdateController(defaults: defaults)
        )

        #expect(settings.window?.contentViewController is NSSplitViewController)
        #expect(try !#require(settings.window).styleMask.contains(.fullSizeContentView))
        let split = try #require(settings.window?.contentViewController as? NSSplitViewController)
        split.view.layoutSubtreeIfNeeded()
        split.splitView.setPosition(270, ofDividerAt: 0)
        split.view.layoutSubtreeIfNeeded()
        #expect(abs(split.splitViewItems[0].viewController.view.frame.width - 270) <= 2)
        let divider = NSRect(x: split.splitViewItems[0].viewController.view.frame.maxX, y: 0,
                             width: split.splitView.dividerThickness, height: split.splitView.bounds.height)
        let hitArea = split.splitView(split.splitView, effectiveRect: divider, forDrawnRect: divider, ofDividerAt: 0)
        #expect(!hitArea.isEmpty)
        #expect(hitArea.contains(NSPoint(x: divider.midX, y: divider.midY)))

        model.setAppearanceMode(.dark)
        #expect(defaults.string(forKey: SettingsAppearanceMode.defaultsKey) == "dark")
        #expect(window.appearance?.name == .darkAqua)
        #expect(settings.window?.appearance?.name == .darkAqua)
        #expect(SettingsAppearanceMode.load(from: defaults) == .dark)

        model.setAppearanceMode(.light)
        #expect(window.appearance?.name == .aqua)
        #expect(settings.window?.appearance?.name == .aqua)

        model.setAppearanceMode(.system)
        #expect(window.appearance == nil)
        #expect(settings.window?.appearance == nil)
    }
}
