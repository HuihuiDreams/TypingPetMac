import Foundation
import Testing
@testable import TypingPet

@Suite struct FolderImageSelectionTests {
    @Test func recognizesPetIdleAndSortsReactionImages() {
        let urls = [
            URL(fileURLWithPath: "/set/z-last.webp"),
            URL(fileURLWithPath: "/set/pet-idle.png"),
            URL(fileURLWithPath: "/set/a-first.gif"),
            URL(fileURLWithPath: "/set/readme.txt")
        ]

        let selection = FolderImageSelection.make(from: urls)

        #expect(selection.idleURL?.lastPathComponent == "pet-idle.png")
        #expect(
            selection.reactionURLs.map(\.lastPathComponent) ==
            ["a-first.gif", "z-last.webp"]
        )
    }

    @Test func keepsAllImagesAsReactionsWhenIdleIsMissing() {
        let urls = [
            URL(fileURLWithPath: "/set/left.png"),
            URL(fileURLWithPath: "/set/right.jpg")
        ]

        let selection = FolderImageSelection.make(from: urls)

        #expect(selection.idleURL == nil)
        #expect(selection.reactionURLs.count == 2)
    }

    @Test func idleNameIsCaseInsensitive() {
        let selection = FolderImageSelection.make(from: [
            URL(fileURLWithPath: "/set/IDLE.HEIC")
        ])

        #expect(selection.idleURL?.lastPathComponent == "IDLE.HEIC")
        #expect(selection.reactionURLs.isEmpty)
    }

    @Test @MainActor
    func libraryCopiesSelectedImagesAndPersistsTheSelection() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("TypingPetTests-\(UUID().uuidString)", isDirectory: true)
        let inputDirectory = temporaryRoot.appendingPathComponent("Input", isDirectory: true)
        let storedDirectory = temporaryRoot.appendingPathComponent("Stored", isDirectory: true)
        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceImage = packageRoot
            .appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        let selectedImage = inputDirectory.appendingPathComponent("my-idle.png")
        try fileManager.copyItem(at: sourceImage, to: selectedImage)

        let suiteName = "TypingPetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let library = PetImageLibrary(
            fileManager: fileManager,
            defaults: defaults,
            imagesDirectory: storedDirectory
        )
        try library.replaceIdle(with: selectedImage)

        let copiedURL = try #require(library.idleURL)
        #expect(copiedURL.path.hasPrefix(storedDirectory.appendingPathComponent("Sets").path))
        #expect(fileManager.fileExists(atPath: copiedURL.path))
        #expect(library.usesCustomImages)

        let restored = PetImageLibrary(
            fileManager: fileManager,
            defaults: defaults,
            imagesDirectory: storedDirectory
        )
        #expect(restored.activeSetID == library.activeSetID)
        #expect(restored.imageSets.count == 2)
        #expect(restored.idleURL?.path == copiedURL.path)
    }

    @Test @MainActor
    func folderImportCreatesSelectableGallerySet() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("TypingPetGallery-\(UUID())", isDirectory: true)
        let input = root.appendingPathComponent("Happy Cat", isDirectory: true)
        let stored = root.appendingPathComponent("Stored", isDirectory: true)
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = packageRoot.appendingPathComponent("Sources/TypingPet/Resources", isDirectory: true)
        try fileManager.copyItem(at: resources.appendingPathComponent("basic.png"), to: input.appendingPathComponent("idle.png"))
        try fileManager.copyItem(at: resources.appendingPathComponent("left.png"), to: input.appendingPathComponent("wave.png"))

        let suite = "TypingPetGalleryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: stored)
        let imported = try library.addSet(from: input)

        #expect(imported.name == "Happy Cat")
        #expect(library.imageSets.count == 2)
        #expect(library.activeSetID == imported.id)
        #expect(library.reactionURLs.count == 1)
        try library.activateSet(id: PetImageLibrary.builtInID)
        #expect(library.activeSetID == PetImageLibrary.builtInID)
    }

    @Test @MainActor
    func migratesLegacyImageSelectionIntoGallery() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("TypingPetMigration-\(UUID())", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resource = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        let legacyImage = root.appendingPathComponent("legacy.png")
        try fileManager.copyItem(at: resource, to: legacyImage)

        let suite = "TypingPetMigrationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("legacy.png", forKey: AppPreferencesKey.legacyIdleFile)
        defaults.set(["legacy.png"], forKey: AppPreferencesKey.legacyReactionFiles)

        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: root)
        #expect(library.imageSets.count == 2)
        #expect(library.activeSet.name == "现有用户图集")
        #expect(library.idleURL?.path == legacyImage.path)

        try library.replaceIdle(with: resource)
        #expect(library.idleURL?.path.contains("/Sets/") == true)
    }
}
