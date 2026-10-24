import AppKit
import XCTest
@testable import TypingPet

final class SettingsAppearanceTests: XCTestCase {
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

        model.setAppearanceMode(.dark)
        XCTAssertEqual(defaults.string(forKey: SettingsAppearanceMode.defaultsKey), "dark")
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        XCTAssertEqual(SettingsAppearanceMode.load(from: defaults), .dark)

        model.setAppearanceMode(.light)
        XCTAssertEqual(window.appearance?.name, .aqua)

        model.setAppearanceMode(.system)
        XCTAssertNil(window.appearance)

    }
}
