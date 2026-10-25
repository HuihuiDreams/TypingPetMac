import AppKit
import Foundation
import Testing
@testable import TypingPet

@Suite(.serialized)
@MainActor
struct PetPreferencesContractTests {
    @Test func keyReactionStorePersistsUsingCentralizedPreferencesKey() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("PreferencesContractTest-\(UUID().uuidString)", isDirectory: true)
        let rulesDir = tempRoot.appendingPathComponent("Rules", isDirectory: true)
        try fileManager.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sampleImage = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/left.png")

        let suite = "PreferencesContractTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: rulesDir)
        let stroke = KeyStroke(keyCode: 12, modifiers: [.command])
        _ = try store.setRule(for: stroke, image: sampleImage)

        // Verify that data is persisted under AppPreferencesKey.keyReactionRules
        let rawData = defaults.data(forKey: AppPreferencesKey.keyReactionRules)
        #expect(rawData != nil)
        if let rawData {
            let rules = try JSONDecoder().decode([KeyReactionRule].self, from: rawData)
            #expect(rules.count == 1)
            #expect(rules.first?.stroke == stroke)
        }
    }

    @Test func petImageLibraryPersistsUsingCentralizedPreferencesKey() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("LibPreferencesContractTest-\(UUID().uuidString)", isDirectory: true)
        let inputDir = tempRoot.appendingPathComponent("Set1", isDirectory: true)
        let storedDir = tempRoot.appendingPathComponent("Stored", isDirectory: true)
        try fileManager.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sampleImage = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        try fileManager.copyItem(at: sampleImage, to: inputDir.appendingPathComponent("idle.png"))

        let suite = "LibPreferencesContractTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: storedDir)
        let set = try library.addSet(from: inputDir, name: "Contract Set")

        // Verify gallery persistence key
        let galleryData = defaults.data(forKey: AppPreferencesKey.gallery)
        #expect(galleryData != nil)

        // Verify activeSetID persistence key
        try library.activateSet(id: set.id)
        let activeIDString = defaults.string(forKey: AppPreferencesKey.activeSetID)
        #expect(activeIDString == set.id.uuidString)
    }

    @Test func globalKeyMonitorLifecycleAndSafeTeardown() {
        var strokeReceived: KeyStroke?
        let monitor = GlobalKeyMonitor { stroke in
            strokeReceived = stroke
        }

        #expect(!monitor.isRunning)
        monitor.stop()
        #expect(!monitor.isRunning)
        monitor.stop() // Idempotent stop
        #expect(!monitor.isRunning)
        #expect(strokeReceived == nil)
    }

    @Test func preferencesKeysAndDefaultsAreConsistent() {
        let allKeys: [String] = [
            AppPreferencesKey.alwaysOnTop,
            AppPreferencesKey.positionLocked,
            AppPreferencesKey.petScale,
            AppPreferencesKey.restingOpacity,
            AppPreferencesKey.hoverOpacity,
            AppPreferencesKey.avoidsPointerWhenLocked,
            AppPreferencesKey.shakeLevel,
            AppPreferencesKey.windowFrame,
            AppPreferencesKey.gallery,
            AppPreferencesKey.activeSetID,
            AppPreferencesKey.legacyIdleFile,
            AppPreferencesKey.legacyReactionFiles,
            AppPreferencesKey.imagePackOrder,
            AppPreferencesKey.keyReactionRules,
            AppPreferencesKey.todoBubbleZoom,
            AppPreferencesKey.todoBubbleVisibility,
            AppPreferencesKey.todoBubbleRestingOpacity,
            AppPreferencesKey.todoBubbleHoverOpacity,
            AppPreferencesKey.todoListStyle,
            AppPreferencesKey.todoIdleMinutes,
            AppPreferencesKey.settingsAppearanceMode,
            AppPreferencesKey.appLanguageMode,
            AppPreferencesKey.automaticUpdateChecks,
            AppPreferencesKey.lastUpdateCheck,
            AppPreferencesKey.notifiedUpdateBuild,
            AppPreferencesKey.pendingUpdateBuild,
            AppPreferencesKey.pendingUpdateFolder,
            AppPreferencesKey.updateFeedURL,
            AppPreferencesKey.inputMonitoringWelcomeShown,
            AppPreferencesKey.inputMonitoringSetupPending,
        ]

        #expect(allKeys.count == 30)
        let uniqueKeys = Set(allKeys)
        #expect(uniqueKeys.count == allKeys.count)
        for key in allKeys {
            #expect(!key.isEmpty)
        }

        // Scale bounds & default
        #expect(AppPreferencesDefault.minScale < AppPreferencesDefault.petScale)
        #expect(AppPreferencesDefault.petScale < AppPreferencesDefault.maxScale)
        #expect(AppPreferencesDefault.minScale > 0)

        // Shake level bounds & default
        #expect(AppPreferencesDefault.minShakeLevel <= AppPreferencesDefault.shakeLevel)
        #expect(AppPreferencesDefault.shakeLevel <= AppPreferencesDefault.maxShakeLevel)

        // Opacity bounds
        #expect((0.0...1.0).contains(AppPreferencesDefault.restingOpacity))
        #expect((0.0...1.0).contains(AppPreferencesDefault.hoverOpacity))

        // Todo bubble defaults
        #expect(AppPreferencesDefault.todoBubbleZoom > 0)
        #expect((0.0...1.0).contains(AppPreferencesDefault.todoBubbleRestingOpacity))
        #expect((0.0...1.0).contains(AppPreferencesDefault.todoBubbleHoverOpacity))
        #expect(AppPreferencesDefault.todoIdleMinutes >= 0)
    }
}
