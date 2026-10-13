import Foundation
import Testing
@testable import TypingPet

private final class RemovalFailingFileManager: FileManager, @unchecked Sendable {
    var blockedURL: URL?
    var blockedCopySource: URL?

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL == blockedCopySource {
            try Data("partial copy".utf8).write(to: dstURL)
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at URL: URL) throws {
        if URL == blockedURL { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: URL)
    }
}

@MainActor
private final class ImageStorageFixture {
    let root: URL
    let input: URL
    let stored: URL
    let defaults: UserDefaults
    let suite = "ImageStorageTests.\(UUID())"
    let fileManager = RemovalFailingFileManager()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ImageStorageTests-\(UUID())")
        input = root.appendingPathComponent("Input")
        stored = root.appendingPathComponent("Stored")
        defaults = try #require(UserDefaults(suiteName: suite))
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stored, withIntermediateDirectories: true)
        let resource = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        try fileManager.copyItem(at: resource, to: input.appendingPathComponent("idle.png"))
        try fileManager.copyItem(at: resource, to: input.appendingPathComponent("reaction.png"))
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func library() -> PetImageLibrary {
        PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: stored)
    }

    func rules() -> KeyReactionStore {
        KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: stored)
    }

    func settingsModel(currentPositionLock: @escaping () -> Bool = { false }) -> TypingPetSettingsModel {
        TypingPetSettingsModel(
            library: library(), keyStore: rules(),
            scale: AppPreferencesDefault.petScale,
            restingOpacity: AppPreferencesDefault.restingOpacity,
            hoverOpacity: AppPreferencesDefault.hoverOpacity,
            shakeLevel: AppPreferencesDefault.shakeLevel,
            alwaysOnTop: AppPreferencesDefault.alwaysOnTop,
            positionLocked: AppPreferencesDefault.positionLocked,
            avoidsPointerWhenLocked: AppPreferencesDefault.avoidsPointerWhenLocked,
            applyScale: { _ in }, applyRestingOpacity: { _ in }, applyHoverOpacity: { _ in },
            applyShake: { _ in }, applyAlwaysOnTop: { _ in }, applyPositionLock: { _ in },
            currentPositionLock: currentPositionLock, applyPointerAvoidance: { _ in },
            reloadPet: {}, openInputMonitoringSettings: {}
        )
    }

    func corruptImage() throws -> URL {
        let url = input.appendingPathComponent("z-broken.png")
        try Data("invalid image".utf8).write(to: url)
        return url
    }

    func allStoredFiles() throws -> [String] {
        let enumerator = try #require(fileManager.enumerator(atPath: stored.path))
        return try #require(enumerator.allObjects as? [String]).sorted()
    }

    func legacyLibrary() throws -> PetImageLibrary {
        for name in ["idle.png", "reaction.png"] {
            try fileManager.copyItem(at: input.appendingPathComponent(name), to: stored.appendingPathComponent(name))
        }
        defaults.set("idle.png", forKey: AppPreferencesKey.legacyIdleFile)
        defaults.set(["reaction.png"], forKey: AppPreferencesKey.legacyReactionFiles)
        return library()
    }
}

@Suite(.serialized)
@MainActor
struct ImageStorageFailureTests {
    @Test func settingsRefreshTracksPositionLockChangedOutsideSettings() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        var locked = false
        let model = fixture.settingsModel(currentPositionLock: { locked })
        locked = true
        model.refresh()
        #expect(model.positionLocked)
        locked = false
        model.refresh()
        #expect(!model.positionLocked)
    }

    @Test func settingsReportsRuleDeletionFailureAndKeepsRule() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let rule = try fixture.rules().setRule(for: KeyStroke(keyCode: 40, modifiers: []),
                                               image: fixture.input.appendingPathComponent("idle.png"))
        let model = fixture.settingsModel()
        fixture.fileManager.blockedURL = fixture.stored.appendingPathComponent(rule.imageFileName)
        model.removeRule(rule)
        #expect(model.errorMessage != nil)
        #expect(model.rules == [rule])
        #expect(fixture.rules().rules == [rule])
    }

    @Test func replacingLegacyIdlePreservesReactionImages() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = try fixture.legacyLibrary()
        let oldReaction = try #require(library.reactionURLs.first)
        let bytes = try Data(contentsOf: oldReaction)
        try library.replaceIdle(with: fixture.input.appendingPathComponent("idle.png"))
        let restored = fixture.library()
        let reaction = try #require(restored.reactionURLs.first)
        #expect(try Data(contentsOf: reaction) == bytes)
        #expect(reaction.path.contains("/Sets/"))
    }

    @Test func replacingLegacyReactionsPreservesIdleImage() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = try fixture.legacyLibrary()
        let bytes = try Data(contentsOf: #require(library.idleURL))
        try library.replaceReactions(with: [fixture.input.appendingPathComponent("reaction.png")])
        let idle = try #require(fixture.library().idleURL)
        #expect(try Data(contentsOf: idle) == bytes)
        #expect(idle.path.contains("/Sets/"))
    }

    @Test func replacementsRemoveOldFilesWithoutTouchingSourceImages() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library()
        try library.addSet(from: fixture.input)
        let oldIdle = try #require(library.idleURL)
        #expect(library.image(for: oldIdle) != nil)
        try library.replaceIdle(with: fixture.input.appendingPathComponent("idle.png"))
        #expect(!fixture.fileManager.fileExists(atPath: oldIdle.path))
        #expect(library.image(for: oldIdle) == nil)
        let oldReactions = library.reactionURLs
        #expect(oldReactions.allSatisfy { library.image(for: $0) != nil })
        try library.replaceReactions(with: [fixture.input.appendingPathComponent("reaction.png")])
        #expect(oldReactions.allSatisfy { !fixture.fileManager.fileExists(atPath: $0.path) })
        #expect(oldReactions.allSatisfy { library.image(for: $0) == nil })
        #expect(library.idleURL != nil)
        #expect(library.reactionURLs.count == 1)
        #expect(fixture.fileManager.fileExists(atPath: fixture.input.appendingPathComponent("idle.png").path))
        #expect(fixture.fileManager.fileExists(atPath: fixture.input.appendingPathComponent("reaction.png").path))
    }

    @Test func failedFolderImportLeavesNoFilesOrGalleryEntry() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library()
        _ = try fixture.corruptImage()
        #expect(throws: (any Error).self) { try library.addSet(from: fixture.input) }
        #expect(library.imageSets.count == 1)
        #expect(library.activeSetID == PetImageLibrary.builtInID)
        #expect(try fixture.allStoredFiles().filter { $0 != "Sets" }.isEmpty)
    }

    @Test func failedReplacementPreservesFilesAndSelection() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library()
        let set = try library.addSet(from: fixture.input)
        let files = try fixture.allStoredFiles()
        let corrupt = try fixture.corruptImage()
        #expect(throws: (any Error).self) {
            try library.replaceReactions(with: [fixture.input.appendingPathComponent("reaction.png"), corrupt])
        }
        #expect(library.activeSet == set)
        #expect(fixture.library().activeSet == set)
        #expect(try fixture.allStoredFiles() == files)
    }

    @Test func interruptedCopyRemovesPartialReplacementFiles() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library()
        let set = try library.addSet(from: fixture.input)
        let files = try fixture.allStoredFiles()
        let source = fixture.input.appendingPathComponent("reaction.png")
        fixture.fileManager.blockedCopySource = source
        #expect(throws: (any Error).self) { try library.replaceReactions(with: [source]) }
        #expect(fixture.library().activeSet == set)
        #expect(try fixture.allStoredFiles() == files)
    }

    @Test func interruptedRuleCopyRemovesPartialFileAndKeepsOldRule() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let store = fixture.rules()
        let stroke = KeyStroke(keyCode: 40, modifiers: [])
        let rule = try store.setRule(for: stroke, image: fixture.input.appendingPathComponent("idle.png"))
        let files = try fixture.allStoredFiles()
        let source = fixture.input.appendingPathComponent("reaction.png")
        fixture.fileManager.blockedCopySource = source
        #expect(throws: (any Error).self) { try store.setRule(for: stroke, image: source) }
        #expect(fixture.rules().rules == [rule])
        #expect(try fixture.allStoredFiles() == files)
    }

    @Test func deletingLegacySetCleansOwnedFilesAndKeepsSourceImages() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = try fixture.legacyLibrary()
        try library.deleteSet(id: library.activeSetID)
        #expect(try fixture.allStoredFiles().isEmpty)
        #expect(fixture.fileManager.fileExists(atPath: fixture.input.appendingPathComponent("idle.png").path))
        #expect(fixture.fileManager.fileExists(atPath: fixture.input.appendingPathComponent("reaction.png").path))
    }

    @Test func failedBuiltInReplacementDoesNotCreateCustomSet() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library()
        let corrupt = try fixture.corruptImage()
        #expect(throws: (any Error).self) { try library.replaceIdle(with: corrupt) }
        #expect(library.imageSets.count == 1)
        #expect(fixture.library().activeSetID == PetImageLibrary.builtInID)
        #expect(try fixture.allStoredFiles().filter { $0 != "Sets" }.isEmpty)
    }

    @Test func failedSetDeletionKeepsSelectionAndCanBeRetried() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library()
        let set = try library.addSet(from: fixture.input)
        fixture.fileManager.blockedURL = fixture.stored.appendingPathComponent("Sets")
            .appendingPathComponent(try #require(set.storageFolder), isDirectory: true)
        #expect(throws: (any Error).self) { try library.deleteSet(id: set.id) }
        #expect(library.activeSet == set)
        #expect(fixture.library().activeSet == set)
        #expect(library.idleURL != nil)
        fixture.fileManager.blockedURL = nil
        try library.deleteSet(id: set.id)
        #expect(library.imageSets.count == 1)
    }

    @Test func failedOldSetCleanupRollsBackReplacement() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library()
        let set = try library.addSet(from: fixture.input)
        let files = try fixture.allStoredFiles()
        fixture.fileManager.blockedURL = fixture.stored.appendingPathComponent("Sets")
            .appendingPathComponent(try #require(set.storageFolder), isDirectory: true)
        #expect(throws: (any Error).self) {
            try library.replaceIdle(with: fixture.input.appendingPathComponent("idle.png"))
        }
        #expect(fixture.library().activeSet == set)
        #expect(try fixture.allStoredFiles() == files)
    }

    @Test func failedRuleDeletionKeepsRuleAndCanBeRetried() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let store = fixture.rules()
        let stroke = KeyStroke(keyCode: 40, modifiers: [])
        let rule = try store.setRule(for: stroke, image: fixture.input.appendingPathComponent("idle.png"))
        fixture.fileManager.blockedURL = fixture.stored.appendingPathComponent(rule.imageFileName)
        #expect(throws: (any Error).self) { try store.removeRule(id: rule.id) }
        #expect(store.rules == [rule])
        #expect(fixture.rules().rules == [rule])
        fixture.fileManager.blockedURL = nil
        try store.removeRule(id: rule.id)
        #expect(store.rules.isEmpty)
    }

    @Test func failedRuleOverwriteKeepsOldImageAndRemovesNewCopy() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let store = fixture.rules()
        let stroke = KeyStroke(keyCode: 40, modifiers: [])
        let rule = try store.setRule(for: stroke, image: fixture.input.appendingPathComponent("idle.png"))
        let files = try fixture.allStoredFiles()
        fixture.fileManager.blockedURL = fixture.stored.appendingPathComponent(rule.imageFileName)
        #expect(throws: (any Error).self) {
            try store.setRule(for: stroke, image: fixture.input.appendingPathComponent("reaction.png"))
        }
        #expect(fixture.rules().rules == [rule])
        #expect(try fixture.allStoredFiles() == files)
    }

    @Test func storedFileNameRejectsPathTraversal() {
        for name in ["", ".", "..", "../outside.png", "a/b.png", "/etc/hosts"] {
            #expect(!StoredFileName.isSafe(name))
        }
        #expect(StoredFileName.isSafe("8F2C-idle.png"))
    }

    @Test func unsafeGalleryFileNamesDoNotResolveOutsideStorage() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let sets = fixture.stored.appendingPathComponent("Sets")
        try fixture.fileManager.createDirectory(at: sets.appendingPathComponent("Safe"), withIntermediateDirectories: true)
        try fixture.fileManager.copyItem(at: fixture.input.appendingPathComponent("idle.png"),
                                         to: fixture.stored.appendingPathComponent("escape.png"))
        let escapingNames = PetImageSet(id: UUID(), name: "names", storageFolder: "Safe",
                                        idleFileName: "../../../Input/idle.png",
                                        reactionFileNames: ["../../../Input/reaction.png"], isBuiltIn: false)
        let escapingFolder = PetImageSet(id: UUID(), name: "folder", storageFolder: "..",
                                         idleFileName: "escape.png", reactionFileNames: ["escape.png"], isBuiltIn: false)
        fixture.defaults.set(try JSONEncoder().encode([escapingNames, escapingFolder]), forKey: AppPreferencesKey.gallery)
        let library = fixture.library()
        for set in [escapingNames, escapingFolder] {
            #expect(library.idleURL(for: set) == nil)
            #expect(library.reactionURLs(for: set).isEmpty)
        }
    }

    @Test func unsafeRuleFileNameDoesNotResolveOutsideStorage() throws {
        let fixture = try ImageStorageFixture()
        defer { fixture.cleanUp() }
        let stroke = KeyStroke(keyCode: 40, modifiers: [])
        let rule = KeyReactionRule(id: UUID(), stroke: stroke, imageFileName: "../Input/idle.png")
        fixture.defaults.set(try JSONEncoder().encode([rule]), forKey: AppPreferencesKey.keyReactionRules)
        let store = fixture.rules()
        #expect(store.imageURL(matching: stroke) == nil)
        #expect(store.imageURL(for: rule) == nil)
    }
}
