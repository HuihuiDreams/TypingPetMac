import AppKit
import XCTest
@testable import TypingPet

final class SettingsAppearanceTests: XCTestCase {
    func testSettingsWidthMatchesReferenceAndGrowsWithText() {
        XCTAssertEqual(SettingsWindowSizing.contentSize(fontSize: 13).width, 1100)
        XCTAssertEqual(SettingsWindowSizing.contentSize(fontSize: 26).width, 2200)
    }

    @MainActor
    func testBubbleAppearanceUpdatesAndSystemClearsOverride() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BubbleAppearance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TodoStore(url: root.appendingPathComponent("todos.json"))
        let controller = TodoBubbleWindowController(store: store, pet: NSWindow())
        controller.setAppearanceMode(.dark)
        XCTAssertEqual(controller.panel.appearance?.name, .darkAqua)
        XCTAssertEqual(controller.entry.appearance?.name, .darkAqua)
        controller.setAppearanceMode(.light)
        XCTAssertEqual(controller.panel.appearance?.name, .aqua)
        XCTAssertEqual(controller.entry.appearance?.name, .aqua)
        controller.setAppearanceMode(.system)
        XCTAssertNil(controller.panel.appearance)
        XCTAssertNil(controller.entry.appearance)
    }
    func testStoredAppearanceAndInvalidValue() throws {
        let suite = "TypingPetAppearanceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(SettingsAppearanceMode.load(from: defaults), .system)
        defaults.set("dark", forKey: SettingsAppearanceMode.defaultsKey)
        XCTAssertEqual(SettingsAppearanceMode.load(from: defaults), .dark)
        defaults.set("unknown", forKey: SettingsAppearanceMode.defaultsKey)
        XCTAssertEqual(SettingsAppearanceMode.load(from: defaults), .system)
    }

    @MainActor
    func testPermissionGrantAndEventTapConnectionAreReportedSeparately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PermissionStatus-\(UUID())")
        let suite = "TypingPetPermissionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
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
            applyAppearance: { _ in },
            reloadPet: {}, openInputMonitoringSettings: {},
            monitoringIsRunning: { connected }, retryMonitoring: { retryCount += 1; connected = true },
            inputMonitoringAuthorized: { granted }, defaults: defaults)
        model.refreshPermissions(retryConnection: true)
        XCTAssertFalse(model.inputMonitoringGranted)
        XCTAssertFalse(model.inputMonitoringConnected)
        XCTAssertEqual(retryCount, 0, "Checking status must not prompt for or bypass permission")
        granted = true
        model.refreshPermissions()
        XCTAssertTrue(model.inputMonitoringGranted)
        XCTAssertFalse(model.inputMonitoringConnected)
        model.refreshPermissions(retryConnection: true)
        XCTAssertEqual(retryCount, 1)
        XCTAssertTrue(model.inputMonitoringConnected)
        granted = false
        model.refreshPermissions()
        XCTAssertFalse(model.inputMonitoringConnected, "Revoking permission disconnects the reported state")
    }

    @MainActor
    func testChangingModeUpdatesSettingsBubbleAndCollapsedEntryWithoutRestarting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TypingPetAppearance-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "TypingPetAppearanceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TodoStore(url: root.appendingPathComponent("todos.json"), defaults: defaults)
        let bubble = TodoBubbleWindowController(store: store, pet: NSWindow(), defaults: defaults)
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
            applyAppearance: { bubble.setAppearanceMode($0) },
            reloadPet: {},
            openInputMonitoringSettings: {},
            defaults: defaults
        )
        let settings = SettingsWindowController(
            model: model,
            todoStore: store,
            updater: UpdateController(defaults: defaults)
        )

        XCTAssertTrue(settings.window?.contentViewController is NSSplitViewController)
        XCTAssertTrue(try XCTUnwrap(settings.window).styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(try XCTUnwrap(settings.window).titlebarAppearsTransparent, "The sticky toolbar must obscure scrolling text")
        let split = try XCTUnwrap(settings.window?.contentViewController as? NSSplitViewController)
        XCTAssertFalse(split.splitViewItems[0].canCollapse)
        XCTAssertFalse(split.splitViewItems[0].canCollapseFromWindowResize)
        XCTAssertTrue(split.splitViewItems[0].allowsFullHeightLayout)
        split.toggleSidebar(nil)
        XCTAssertFalse(split.splitViewItems[0].isCollapsed, "Sidebar toggle actions must keep navigation visible")
        XCTAssertTrue(try XCTUnwrap(settings.window?.toolbar).items.contains { $0 is NSTrackingSeparatorToolbarItem })
        XCTAssertEqual(settings.window?.titlebarSeparatorStyle, NSTitlebarSeparatorStyle.none)
        split.view.layoutSubtreeIfNeeded()
        split.splitView.setPosition(270, ofDividerAt: 0)
        split.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(split.splitViewItems[0].viewController.view.frame.width, 270, accuracy: 2)
        let divider = NSRect(x: split.splitViewItems[0].viewController.view.frame.maxX, y: 0,
                             width: split.splitView.dividerThickness, height: split.splitView.bounds.height)
        let hitArea = split.splitView(split.splitView, effectiveRect: divider, forDrawnRect: divider, ofDividerAt: 0)
        XCTAssertFalse(hitArea.isEmpty, "The visible divider must accept mouse dragging")
        XCTAssertTrue(hitArea.contains(NSPoint(x: divider.midX, y: divider.midY)))

        settings.window?.setContentSize(SettingsWindowSizing.minimumSize())
        split.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(split.splitViewItems[0].isCollapsed)
        XCTAssertGreaterThanOrEqual(split.splitViewItems[0].viewController.view.frame.width, 240)
        XCTAssertGreaterThanOrEqual(split.splitViewItems[1].viewController.view.frame.width, 530)

        model.setAppearanceMode(.dark)
        XCTAssertEqual(defaults.string(forKey: SettingsAppearanceMode.defaultsKey), "dark")
        XCTAssertEqual(bubble.panel.appearance?.name, .darkAqua)
        XCTAssertEqual(bubble.entry.appearance?.name, .darkAqua)
        XCTAssertEqual(bubble.panel.contentView?.effectiveAppearance.name, .darkAqua)
        XCTAssertEqual(bubble.entry.contentView?.effectiveAppearance.name, .darkAqua)
        XCTAssertEqual(settings.window?.appearance?.name, .darkAqua)
        XCTAssertEqual(SettingsAppearanceMode.load(from: defaults), .dark)

        let reopened = TodoBubbleWindowController(store: store, pet: NSWindow(), defaults: defaults)
        XCTAssertEqual(reopened.panel.appearance?.name, .darkAqua)
        XCTAssertEqual(reopened.entry.appearance?.name, .darkAqua)

        model.setAppearanceMode(.light)
        XCTAssertEqual(bubble.panel.appearance?.name, .aqua)
        XCTAssertEqual(bubble.entry.appearance?.name, .aqua)
        XCTAssertEqual(bubble.panel.contentView?.effectiveAppearance.name, .aqua)
        XCTAssertEqual(bubble.entry.contentView?.effectiveAppearance.name, .aqua)
        XCTAssertEqual(settings.window?.appearance?.name, .aqua)

        model.setAppearanceMode(.system)
        XCTAssertNil(bubble.panel.appearance)
        XCTAssertNil(bubble.entry.appearance)
        XCTAssertNil(settings.window?.appearance)

    }
}
