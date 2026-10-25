import AppKit
import Testing
@testable import TypingPet

@Suite struct PetPackTests {
    @MainActor private struct Fixture {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let library: PetImageLibrary
        let keys: KeyReactionStore
        var image: URL {
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/TypingPet/Resources/left.png")
        }
        var sampleImages: [URL] {
            ["basic.png", "left.png", "right.png"].map { image.deletingLastPathComponent().appendingPathComponent($0) }
        }
        init() throws {
            suite = "TypingPetPacks.\(UUID())"
            defaults = try #require(UserDefaults(suiteName: suite))
            root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            library = PetImageLibrary(defaults: defaults, imagesDirectory: root.appendingPathComponent("Images"))
            keys = KeyReactionStore(defaults: defaults, directory: root.appendingPathComponent("Keys"))
        }
        func store() -> PetPackStore { PetPackStore(library: library, keyStore: keys) }
        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test @MainActor func migratesExistingGlobalRulesWithoutMovingImagesAndNewPacksStartClean() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let imported = try f.library.addSet(from: [f.image], name: "Existing")
        let stroke = KeyStroke(keyCode: 0, modifiers: [.command, .shift])
        try f.keys.setRule(for: stroke, image: f.image)
        let oldURL = try #require(f.keys.imageURL(matching: stroke))
        let store = f.store()
        #expect(store.loadError == nil)
        for set in f.library.imageSets {
            let pack = store.configuration(for: set)
            #expect(pack.mappings.map(\.stroke) == [stroke])
            let id = try #require(pack.mappings.first?.selection.presetIDs.first)
            #expect(store.imageURL(id: id, in: pack, set: set) == oldURL)
        }
        #expect(store.configuration(for: imported).idle.presetIDs.count == 1)
        let new = try f.library.addSet(from: [f.image], name: "New")
        #expect(store.configuration(for: new).mappings.isEmpty)
        #expect(store.configuration(for: new).presets.count == 1)
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
        try store.resetToDefaults()
        #expect(store.activeConfiguration.presets.count == 3)
        #expect(store.activeConfiguration.mappings.isEmpty)
    }

    @Test @MainActor func roundTripKeepsPerPackSelectionsModesNamesAndModifierCombinations() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let set = try f.library.addSet(from: f.sampleImages, name: "Editable")
        var pack = store.configuration(for: set)
        let ids = Array(pack.presets.prefix(3).map(\.id))
        pack.name = "自定义动作包"
        pack.presets[0].name = "自定义表情"
        pack.idle = PresetSelection(presetIDs: Array(ids.reversed()), mode: .cycle)
        pack.unassigned = PresetSelection(presetIDs: ids, mode: .random)
        pack.mappings = [PresetKeyMapping(stroke: KeyStroke(keyCode: 40, modifiers: [.control, .option, .shift, .command]), selection: PresetSelection(presetIDs: ids, mode: .cycle))]
        try store.save(pack, for: set)
        let second = try f.library.addSet(from: [f.image], name: "Separate")
        let restored = f.store()
        #expect(restored.configuration(for: set) == pack)
        #expect(restored.configuration(for: second).mappings.isEmpty)
        #expect(restored.configuration(for: second).name != pack.name)
    }

    @Test @MainActor func invalidSelectionsCannotOverwriteSavedPack() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let set = f.library.activeSet
        let original = store.activeConfiguration
        let bytes = try Data(contentsOf: f.library.packConfigurationsURL)
        var invalid = original
        invalid.idle.presetIDs = []
        #expect(throws: (any Error).self) { try store.save(invalid, for: set) }
        invalid = original
        invalid.unassigned.presetIDs = ["missing"]
        #expect(throws: (any Error).self) { try store.save(invalid, for: set) }
        invalid = original
        let mapping = PresetKeyMapping(stroke: KeyStroke(keyCode: 0, modifiers: []), selection: original.idle)
        invalid.mappings = [mapping, mapping]
        #expect(throws: (any Error).self) { try store.save(invalid, for: set) }
        #expect(try Data(contentsOf: f.library.packConfigurationsURL) == bytes)
        #expect(store.activeConfiguration == original)
    }

    @Test @MainActor func unreadableAndFutureDocumentsArePreserved() throws {
        let f = try Fixture(); defer { f.cleanup() }
        _ = f.store()
        for text in ["broken document", "{\"version\":99,\"packs\":{}}"] {
            let bytes = Data(text.utf8)
            try bytes.write(to: f.library.packConfigurationsURL)
            let store = f.store()
            #expect(store.loadError != nil)
            #expect(throws: (any Error).self) { try store.save(store.activeConfiguration, for: f.library.activeSet) }
            #expect(try Data(contentsOf: f.library.packConfigurationsURL) == bytes)
        }
    }

    @Test @MainActor func importedPresetIsIndependentOfOriginalAndCanBeSavedInCustomPack() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        _ = try f.library.addSet(from: [f.image], name: "Editable")
        let source = f.root.appendingPathComponent("my-expression.png")
        try FileManager.default.copyItem(at: f.image, to: source)
        let preset = try #require(store.importPresets([source], into: f.library.activeSet).first)
        let copy = try #require(store.imageURL(for: preset, in: f.library.activeSet))
        #expect(source != copy)
        try FileManager.default.removeItem(at: source)
        #expect(NSImage(contentsOf: copy) != nil)
        var pack = store.activeConfiguration
        pack.presets.append(preset)
        pack.idle.presetIDs = [preset.id]
        try store.save(pack, for: f.library.activeSet)
        #expect(f.store().idleURL == copy)
    }

    @Test func playbackUsesExactModifiersAndIndependentKeyFallbackAndIdleCycles() {
        var pack = samplePack()
        let plain = KeyStroke(keyCode: 0, modifiers: [])
        let combo = KeyStroke(keyCode: 0, modifiers: [.command, .shift])
        pack.mappings = [PresetKeyMapping(stroke: combo, selection: PresetSelection(presetIDs: ["c", "d"], mode: .cycle))]
        var cursor = PresetPlaybackCursor()
        #expect(cursor.reaction(for: combo, in: pack) == "c")
        #expect(cursor.reaction(for: plain, in: pack) == "a")
        #expect(cursor.idle(in: pack) == "e")
        #expect(cursor.reaction(for: combo, in: pack) == "d")
        #expect(cursor.reaction(for: KeyStroke(keyCode: 1, modifiers: []), in: pack) == "b")
        #expect(cursor.idle(in: pack) == "f")
        #expect(cursor.reaction(for: combo, in: pack) == "c")
        pack.idle.presetIDs.reverse()
        #expect(cursor.idle(in: pack) == "f")
    }

    @Test func randomPlaybackAvoidsImmediateRepeats() {
        var cursor = PresetPlaybackCursor()
        let selection = PresetSelection(presetIDs: ["a", "b", "c"])
        var previous: String?
        for _ in 0..<20 {
            let next = cursor.next(in: selection, channel: "random", randomIndex: { _ in 0 })
            #expect(next != nil)
            #expect(previous != next)
            previous = next
        }
    }

    @Test @MainActor func editorAutosavesExactModifierMappingAndOpensOnlyOneTarget() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var reloads: [Bool] = []
        let editor = PackEditorModel(store: f.store(), onChange: { reloads.append($0) })
        let stroke = KeyStroke(keyCode: 0, modifiers: [.command, .option])
        editor.toggle(.unassigned)
        editor.toggle(.idle)
        #expect(editor.expandedTarget == .idle)
        editor.toggle(.idle)
        #expect(editor.expandedTarget == nil)
        let ids = editor.draft.presets.map(\.id)
        editor.assignPreset(ids[1], to: stroke)
        editor.togglePreset(ids[2], for: .key(stroke))
        editor.setMode(.cycle, for: .key(stroke))
        let saved = try #require(f.store().activeConfiguration.mappings.first)
        #expect(saved.stroke == stroke)
        #expect(saved.selection == PresetSelection(presetIDs: [ids[1], ids[2]], mode: .cycle))
        #expect(reloads == [true, true, true])
        editor.unassign(.key(stroke))
        #expect(f.store().activeConfiguration.mappings.isEmpty)
    }

    @Test @MainActor func emptyPackCreationAndInactiveEditsNeverSwitchActivePet() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let original = store.activeConfiguration
        let originalID = f.library.activeSetID
        var reloads: [Bool] = []
        let editor = PackEditorModel(store: store, onChange: { reloads.append($0) })
        try editor.createPack(name: "My empty pack")
        let set = editor.selectedSet
        #expect(editor.draft.presets.isEmpty)
        #expect(!editor.draft.isUsable)
        #expect(f.library.activeSetID == originalID)
        #expect(throws: (any Error).self) { try store.activate(set) }
        #expect(throws: (any Error).self) { try store.createPack(name: "  my EMPTY pack  ") }
        editor.addPresets(from: [f.image])
        #expect(editor.draft.presets.count == 1)
        #expect(editor.draft.idle.presetIDs == editor.draft.unassigned.presetIDs)
        #expect(editor.draft.isUsable)
        #expect(store.activeConfiguration == original)
        #expect(reloads == [false, false])
        editor.activate(set)
        #expect(f.library.activeSetID == set.id)
        #expect(reloads.last == true)
        let restoredLibrary = PetImageLibrary(defaults: f.defaults, imagesDirectory: f.root.appendingPathComponent("Images"))
        let restored = PetPackStore(library: restoredLibrary, keyStore: f.keys)
        #expect(restoredLibrary.activeSetID == set.id)
        #expect(restored.activeConfiguration == editor.draft)
    }

    @Test @MainActor func deletingPresetRequiresFallbackReplacementAndRemovesEmptyKeyMapping() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let set = try f.library.addSet(from: f.sampleImages, name: "Editable")
        var pack = store.configuration(for: set)
        let removed = pack.idle.presetIDs[0]
        let replacement = try #require(pack.presets.first { $0.id != removed }?.id)
        pack.unassigned.presetIDs = [removed]
        pack.mappings = [PresetKeyMapping(stroke: KeyStroke(keyCode: 0, modifiers: []), selection: PresetSelection(presetIDs: [removed]))]
        try store.save(pack, for: set)
        #expect(throws: (any Error).self) { try store.removingPreset(id: removed, from: pack, in: set, replacementID: nil) }
        let result = try store.removingPreset(id: removed, from: pack, in: set, replacementID: replacement)
        try store.save(result, for: set)
        #expect(result.idle.presetIDs == [replacement])
        #expect(result.unassigned.presetIDs == [replacement])
        #expect(result.mappings.isEmpty)
        #expect(!result.presets.contains { $0.id == removed })
        #expect(store.imageURL(id: removed, in: pack, set: set) != nil)
        #expect(f.store().activeConfiguration == result)
    }

    @Test @MainActor func builtInPresetsRejectChangesButAllowMappingAndPlaybackEdits() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let set = f.library.activeSet
        let original = store.activeConfiguration
        let bytes = try Data(contentsOf: f.library.packConfigurationsURL)
        var renamed = original
        renamed.presets[0].name = "Changed"
        var replaced = original
        replaced.presets[0].fileName = original.presets[1].fileName
        var removed = original
        removed.presets.removeLast()
        var added = original
        var extra = original.presets[0]
        extra.id = UUID().uuidString
        added.presets.append(extra)
        for edited in [renamed, replaced, removed, added] {
            #expect(throws: PetPackError.self) {
                try store.save(edited, for: set)
            }
        }
        #expect(throws: (any Error).self) { try store.importPresets([f.image], into: set) }
        #expect(throws: (any Error).self) { try store.removingPreset(id: original.presets[0].id, from: original, in: set, replacementID: nil) }
        #expect(throws: (any Error).self) { try store.replaceIdle(with: f.image) }
        #expect(throws: (any Error).self) { try store.replaceUnassigned(with: [f.image]) }
        #expect(try Data(contentsOf: f.library.packConfigurationsURL) == bytes)

        let editor = PackEditorModel(store: store)
        #expect(!editor.canEditPresets)
        editor.renamePreset("Changed")
        editor.addPresets(from: [f.image])
        editor.replacePresetImage()
        editor.removeSelectedPreset()
        #expect(editor.draft == original)
        let stroke = KeyStroke(keyCode: 0, modifiers: [.command, .shift])
        editor.assignPreset(original.presets[1].id, to: stroke)
        editor.setMode(.cycle, for: .unassigned)
        editor.togglePreset(original.presets[1].id, for: .idle)
        let restored = f.store().activeConfiguration
        #expect(restored.presets == original.presets)
        #expect(restored.mappings.first?.stroke == stroke)
        #expect(restored.unassigned.mode == .cycle)
        #expect(restored.idle.presetIDs.count == 2)
        try editor.createPack(name: "My editable pack")
        #expect(editor.canEditPresets)
        editor.addPresets(from: [f.image])
        editor.renamePreset("My image")
        #expect(editor.draft.presets.first?.name == "My image")
    }

    @Test @MainActor func lastImageCanOnlyBeRemovedFromInactivePackAndOrderPersists() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let editor = PackEditorModel(store: store)
        try editor.createPack(name: "One image")
        editor.addPresets(from: [f.image])
        let set = editor.selectedSet
        let pack = editor.draft
        let id = try #require(pack.presets.first?.id)
        let empty = try store.removingPreset(id: id, from: pack, in: set, replacementID: nil)
        #expect(empty.presets.isEmpty)
        editor.activate(set)
        #expect(throws: (any Error).self) { try store.removingPreset(id: id, from: pack, in: set, replacementID: nil) }
        editor.moveSet(id: set.id, before: PetImageLibrary.builtInID)
        let library = PetImageLibrary(defaults: f.defaults, imagesDirectory: f.root.appendingPathComponent("Images"))
        #expect(library.imageSets.first?.id == set.id)
        try store.activate(try #require(library.imageSets.first { $0.isBuiltIn }))
        try store.save(empty, for: set)
        #expect(f.store().configuration(for: set).presets.isEmpty)
    }

    @Test @MainActor func duplicateCopiesImagesAndMappingsWithoutActivatingOrSharingEdits() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let basic = f.library.activeSet
        var original = store.configuration(for: basic)
        original.idle.mode = .cycle
        original.mappings = [PresetKeyMapping(stroke: KeyStroke(keyCode: 49, modifiers: [.command, .shift]), selection: original.unassigned)]
        try store.save(original, for: basic)
        let copy = try store.duplicatePack(basic)
        var copied = store.configuration(for: copy)
        #expect(!copy.isBuiltIn)
        #expect(f.library.activeSetID == basic.id)
        #expect(copied.idle == original.idle)
        #expect(copied.unassigned == original.unassigned)
        #expect(copied.mappings.first?.stroke == original.mappings.first?.stroke)
        #expect(copied.mappings.first?.id != original.mappings.first?.id)
        for (source, destination) in zip(original.presets, copied.presets) {
            let sourceURL = try #require(store.imageURL(for: source, in: basic))
            let copiedURL = try #require(store.imageURL(for: destination, in: copy))
            #expect(sourceURL != copiedURL)
            #expect(try Data(contentsOf: sourceURL) == (try Data(contentsOf: copiedURL)))
            #expect(source.id == destination.id)
        }
        copied.presets[0].name = "Only in the copy"
        try store.save(copied, for: copy)
        #expect(store.configuration(for: basic) == original)
        #expect(f.store().configuration(for: copy) == copied)
        let second = try store.duplicatePack(basic)
        #expect(store.configuration(for: second).name != copied.name)
        #expect(f.library.activeSetID == basic.id)
    }

    @Test @MainActor func duplicatePreservesMigratedKeyImagesAndSupportsEmptySets() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.keys.setRule(for: KeyStroke(keyCode: 36, modifiers: [.option]), image: f.image)
        let store = f.store()
        let source = store.activeConfiguration
        let copy = try store.duplicatePack(f.library.activeSet)
        let pack = store.configuration(for: copy)
        #expect(pack.presets.allSatisfy { $0.source == .imageSet })
        #expect(pack.mappings.map(\.selection) == source.mappings.map(\.selection))
        for p in pack.presets { #expect(store.imageURL(for: p, in: copy) != nil) }
        let empty = try store.createPack(name: "Empty")
        let emptyCopy = try store.duplicatePack(empty)
        #expect(store.configuration(for: emptyCopy).presets.isEmpty)
        #expect(!store.configuration(for: emptyCopy).isUsable)
    }

    private func samplePack() -> PetPackConfiguration {
        PetPackConfiguration(name: "Test", presets: [],
            unassigned: PresetSelection(presetIDs: ["a", "b"], mode: .cycle),
            idle: PresetSelection(presetIDs: ["e", "f"], mode: .cycle))
    }
}
