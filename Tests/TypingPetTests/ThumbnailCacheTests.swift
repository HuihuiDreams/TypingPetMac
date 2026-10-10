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
}
