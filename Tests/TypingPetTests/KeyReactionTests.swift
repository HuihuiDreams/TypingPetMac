import CoreGraphics
import Foundation
import Testing
@testable import TypingPet

@Suite struct KeyReactionTests {
    @Test func normalizesOnlySupportedModifierFlags() {
        let modifiers = KeyModifiers(eventFlags: [.maskCommand, .maskShift, .maskAlphaShift])
        #expect(modifiers == [.command, .shift])
        #expect(modifiers.displayPrefix == "⇧⌘")
    }

    @Test func sameKeyWithDifferentModifiersIsDifferentStroke() {
        let plain = KeyStroke(keyCode: 40, modifiers: [])
        let command = KeyStroke(keyCode: 40, modifiers: [.command])
        #expect(plain != command)
        #expect(command.displayName == "⌘K")
    }

    @Test @MainActor
    func rulePersistsAndMatchesExactly() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("TypingPetKeys-\(UUID())", isDirectory: true)
        let stored = root.appendingPathComponent("Rules", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let image = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/left.png")
        let suite = "TypingPetKeyTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let stroke = KeyStroke(keyCode: 40, modifiers: [.command])
        let store = KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: stored)
        try store.setRule(for: stroke, image: image)
        #expect(store.imageURL(matching: stroke) != nil)
        #expect(store.imageURL(matching: KeyStroke(keyCode: 40, modifiers: [])) == nil)

        let restored = KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: stored)
        #expect(restored.rules.count == 1)
        #expect(restored.imageURL(matching: stroke) != nil)
    }
}
