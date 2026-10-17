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

    @Test func formatsControlAndOptionModifiersAndFunctionKeys() {
        let allModifiers = KeyModifiers(eventFlags: [.maskControl, .maskAlternate, .maskShift, .maskCommand])
        #expect(allModifiers == [.control, .option, .shift, .command])
        #expect(allModifiers.displayPrefix == "⌃⌥⇧⌘")

        let f1 = KeyStroke(keyCode: 122, modifiers: [.control])
        #expect(f1.displayName == "⌃F1")

        let f2 = KeyStroke(keyCode: 120, modifiers: [.option])
        #expect(f2.displayName == "⌥F2")

        let f4 = KeyStroke(keyCode: 118, modifiers: [])
        #expect(f4.displayName == "F4")
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

    @Test @MainActor
    func rejectsSymlinkedRuleImage() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("TypingPetKeySymlink-\(UUID())", isDirectory: true)
        let stored = root.appendingPathComponent("Rules", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let realImage = packageRoot.appendingPathComponent("Sources/TypingPet/Resources/left.png")
        let symlinkImage = root.appendingPathComponent("symlink.png")
        try fileManager.createSymbolicLink(at: symlinkImage, withDestinationURL: realImage)

        let suite = "TypingPetKeySymlinkTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = KeyReactionStore(fileManager: fileManager, defaults: defaults, directory: stored)
        let stroke = KeyStroke(keyCode: 40, modifiers: [.command])
        #expect(throws: KeyReactionError.self) {
            try store.setRule(for: stroke, image: symlinkImage)
        }
        #expect(store.rules.isEmpty)
    }
}
