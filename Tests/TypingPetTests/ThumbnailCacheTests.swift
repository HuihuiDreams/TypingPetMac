import AppKit
import Foundation
import Testing
@testable import TypingPet

@Suite(.serialized)
@MainActor
struct ThumbnailCacheTests {
    @Test func thumbnailCacheProvidesImageAndInvalidatesOnDeletion() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("TypingPetCacheTest-\(UUID().uuidString)", isDirectory: true)
        let inputDir = tempRoot.appendingPathComponent("CatSet", isDirectory: true)
        let storedDir = tempRoot.appendingPathComponent("Stored", isDirectory: true)
        try fileManager.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resource = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        try fileManager.copyItem(at: resource, to: inputDir.appendingPathComponent("idle.png"))

        let suite = "TypingPetCacheTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: storedDir)
        let set = try library.addSet(from: inputDir, name: "Cache Test Set")

        // First read populates cache
        let image1 = library.thumbnail(for: set)
        #expect(image1 != nil)

        // Subsequent read hits memory cache
        let image2 = library.thumbnail(for: set)
        #expect(image2 != nil)
        #expect(image1 === image2)

        // Deleting set invalidates cache
        try library.deleteSet(id: set.id)
        #expect(library.thumbnail(for: set) == nil)
    }

    @Test func clearCacheRemovesAllCachedImages() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("TypingPetClearCacheTest-\(UUID().uuidString)", isDirectory: true)
        let inputDir = tempRoot.appendingPathComponent("CatSet", isDirectory: true)
        let storedDir = tempRoot.appendingPathComponent("Stored", isDirectory: true)
        try fileManager.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resource = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        try fileManager.copyItem(at: resource, to: inputDir.appendingPathComponent("idle.png"))

        let suite = "TypingPetClearCacheTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: storedDir)
        let set = try library.addSet(from: inputDir, name: "Clear Cache Test Set")

        // First read caches image
        let image1 = library.thumbnail(for: set)
        #expect(image1 != nil)

        // Clear cache
        library.clearCache()

        // Next read must instantiate a new object instance
        let image2 = library.thumbnail(for: set)
        #expect(image2 != nil)
        #expect(image1 !== image2)
    }

    @Test func activateSetInvalidatesPreviousSetReactionCache() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("TypingPetActivateCacheTest-\(UUID().uuidString)", isDirectory: true)
        let inputDir1 = tempRoot.appendingPathComponent("CatSet1", isDirectory: true)
        let inputDir2 = tempRoot.appendingPathComponent("CatSet2", isDirectory: true)
        let storedDir = tempRoot.appendingPathComponent("Stored", isDirectory: true)
        try fileManager.createDirectory(at: inputDir1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: inputDir2, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let basic = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        let left = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/left.png")
        try fileManager.copyItem(at: basic, to: inputDir1.appendingPathComponent("idle.png"))
        try fileManager.copyItem(at: left, to: inputDir1.appendingPathComponent("reaction.png"))
        try fileManager.copyItem(at: basic, to: inputDir2.appendingPathComponent("idle.png"))

        let suite = "TypingPetActivateCacheTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: storedDir)
        let set1 = try library.addSet(from: inputDir1, name: "Set 1")
        let set2 = try library.addSet(from: inputDir2, name: "Set 2")

        try library.activateSet(id: set1.id)
        let reactionURL = try #require(library.reactionURLs.first)
        let cachedImg1 = library.image(for: reactionURL)
        #expect(cachedImg1 != nil)

        // Switching sets invalidates reaction cache of set1
        try library.activateSet(id: set2.id)
        let cachedImg2 = library.image(for: reactionURL)
        #expect(cachedImg2 != nil)
        #expect(cachedImg1 !== cachedImg2)
    }

    @Test func packEditorModelSharesLibraryImageCache() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("TypingPetEditorCacheTest-\(UUID().uuidString)", isDirectory: true)
        let storedDir = tempRoot.appendingPathComponent("Stored", isDirectory: true)
        let keysDir = tempRoot.appendingPathComponent("Keys", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let suite = "TypingPetEditorCacheTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: storedDir)
        let keyStore = KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: keysDir)
        let store = PetPackStore(library: library, keyStore: keyStore)
        let editor = PackEditorModel(store: store)
        let preset = try #require(editor.draft.presets.first)
        let url = try #require(store.imageURL(for: preset, in: editor.selectedSet))

        let editorImage = try #require(editor.image(for: preset))
        let libraryImage = try #require(library.image(for: url))
        #expect(editorImage === libraryImage)

        library.clearCache()
        let reloadedImage = try #require(editor.image(for: preset))
        #expect(reloadedImage !== editorImage)
    }
}
