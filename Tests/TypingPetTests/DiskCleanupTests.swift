import Foundation
import Testing
@testable import TypingPet

@Suite(.serialized)
@MainActor
struct DiskCleanupTests {
    @Test func deleteSetRemovesPhysicalDirectoryOnDisk() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("TypingPetDiskTest-\(UUID().uuidString)", isDirectory: true)
        let inputDir = tempRoot.appendingPathComponent("CatSet", isDirectory: true)
        let storedDir = tempRoot.appendingPathComponent("Stored", isDirectory: true)
        try fileManager.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resource = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        try fileManager.copyItem(at: resource, to: inputDir.appendingPathComponent("idle.png"))
        try fileManager.copyItem(at: resource, to: inputDir.appendingPathComponent("wave.png"))

        let suite = "TypingPetDiskTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: storedDir)
        let set = try library.addSet(from: inputDir, name: "Test Set")

        let folderName = try #require(set.storageFolder)
        let diskFolder = storedDir.appendingPathComponent("Sets").appendingPathComponent(folderName)
        #expect(fileManager.fileExists(atPath: diskFolder.path))

        try library.deleteSet(id: set.id)
        #expect(!fileManager.fileExists(atPath: diskFolder.path))
    }

    @Test func removeRuleDeletesPhysicalImageFileOnDisk() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("TypingPetKeyDiskTest-\(UUID().uuidString)", isDirectory: true)
        let rulesDir = tempRoot.appendingPathComponent("Rules", isDirectory: true)
        try fileManager.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let image = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/left.png")
        let suite = "TypingPetKeyDiskTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let stroke = KeyStroke(keyCode: 40, modifiers: [.command])
        let store = KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: rulesDir)
        let rule = try store.setRule(for: stroke, image: image)

        let diskFile = rulesDir.appendingPathComponent(rule.imageFileName)
        #expect(fileManager.fileExists(atPath: diskFile.path))

        try store.removeRule(id: rule.id)
        #expect(!fileManager.fileExists(atPath: diskFile.path))
    }

    @Test func overwritingRuleDeletesPreviousImageFileOnDisk() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("TypingPetKeyOverwriteTest-\(UUID().uuidString)", isDirectory: true)
        let rulesDir = tempRoot.appendingPathComponent("Rules", isDirectory: true)
        try fileManager.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let image1 = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/left.png")
        let image2 = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/right.png")
        let suite = "TypingPetKeyOverwriteTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let stroke = KeyStroke(keyCode: 40, modifiers: [.command])
        let store = KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: rulesDir)

        let rule1 = try store.setRule(for: stroke, image: image1)
        let file1 = rulesDir.appendingPathComponent(rule1.imageFileName)
        #expect(fileManager.fileExists(atPath: file1.path))

        let rule2 = try store.setRule(for: stroke, image: image2)
        let file2 = rulesDir.appendingPathComponent(rule2.imageFileName)
        #expect(!fileManager.fileExists(atPath: file1.path))
        #expect(fileManager.fileExists(atPath: file2.path))
    }

    @Test func removeTemplateDeletesPhysicalDirectoryOnDisk() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("TypingPetTemplateDiskTest-\(UUID().uuidString)", isDirectory: true)
        let templatesDir = tempRoot.appendingPathComponent("Templates", isDirectory: true)
        let imagesDir = tempRoot.appendingPathComponent("Images", isDirectory: true)
        let keysDir = tempRoot.appendingPathComponent("Keys", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let suite = "TypingPetTemplateDiskTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let library = PetImageLibrary(fileManager: fileManager, defaults: defaults, imagesDirectory: imagesDir)
        let keyStore = KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: keysDir)
        let store = PetPackStore(library: library, keyStore: keyStore)
        let templates = ShareTemplateStore(directory: templatesDir)

        let package = try LocalShareAPI.package(
            configuration: store.activeConfiguration,
            set: store.library.activeSet,
            store: store,
            message: "disk test"
        )
        let (root, manifest) = try LocalShareAPI.extract(package)
        defer { try? fileManager.removeItem(at: root) }

        let preview = LocalSharePreview(
            code: "AB12CD",
            status: "active",
            latestVersion: 1,
            manifest: manifest,
            packageSize: package.count,
            sha256: "test-hash",
            publishedAt: 1
        )

        try templates.install(package, preview: preview)
        let template = try #require(templates.templates.first)
        let templateFolder = templatesDir.appendingPathComponent(template.folder)
        #expect(fileManager.fileExists(atPath: templateFolder.path))

        try templates.remove(template)
        #expect(!fileManager.fileExists(atPath: templateFolder.path))
        #expect(templates.templates.isEmpty)
    }
}
