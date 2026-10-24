import AppKit
import XCTest
@testable import TypingPet

final class SettingsAppearanceTests: XCTestCase {
    func testSettingsWidthMatchesReferenceAndGrowsWithText() {
        XCTAssertEqual(SettingsWindowSizing.contentSize(fontSize: 13).width, 490)
        XCTAssertEqual(SettingsWindowSizing.contentSize(fontSize: 26).width, 980)
    }

    @MainActor
    func testBubbleAppearanceUpdatesAndSystemClearsOverride() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BubbleAppearance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TodoStore(url: root.appendingPathComponent("todos.json"))
        let controller = TodoBubbleWindowController(store: store, pet: NSWindow())
        controller.setAppearanceMode(.dark)
        XCTAssertEqual(controller.panel.appearance?.name, .darkAqua)
        controller.setAppearanceMode(.light)
        XCTAssertEqual(controller.panel.appearance?.name, .aqua)
        controller.setAppearanceMode(.system)
        XCTAssertNil(controller.panel.appearance)
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
    func testChangingModePersistsAndUpdatesWindowAppearance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TypingPetAppearance-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "TypingPetAppearanceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
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

        model.setAppearanceMode(.dark)
        XCTAssertEqual(defaults.string(forKey: SettingsAppearanceMode.defaultsKey), "dark")
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        XCTAssertEqual(settings.window?.appearance?.name, .darkAqua)
        XCTAssertEqual(SettingsAppearanceMode.load(from: defaults), .dark)

        model.setAppearanceMode(.light)
        XCTAssertEqual(window.appearance?.name, .aqua)
        XCTAssertEqual(settings.window?.appearance?.name, .aqua)

        model.setAppearanceMode(.system)
        XCTAssertNil(window.appearance)
        XCTAssertNil(settings.window?.appearance)

    }
}
