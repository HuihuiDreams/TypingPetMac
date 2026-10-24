import AppKit
import XCTest
@testable import TypingPet

final class PetPackTests: XCTestCase {
    @MainActor private struct Fixture {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let library: PetImageLibrary
        let keys: KeyReactionStore
        var image: URL {
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/TypingPet/Resources/pet-left.png")
        }
        init() throws {
            suite = "TypingPetPacks.\(UUID())"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
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

    @MainActor func testMigratesExistingGlobalRulesWithoutMovingImagesAndNewPacksStartClean() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let imported = try f.library.addSet(from: [f.image], name: "Existing")
        let stroke = KeyStroke(keyCode: 0, modifiers: [.command, .shift])
        try f.keys.setRule(for: stroke, image: f.image)
        let oldURL = try XCTUnwrap(f.keys.imageURL(matching: stroke))
        let store = f.store()
        XCTAssertNil(store.loadError)
        for set in f.library.imageSets {
            let pack = store.configuration(for: set)
            XCTAssertEqual(pack.mappings.map(\.stroke), [stroke])
            let id = try XCTUnwrap(pack.mappings.first?.selection.presetIDs.first)
            XCTAssertEqual(store.imageURL(id: id, in: pack, set: set), oldURL)
        }
        XCTAssertEqual(store.configuration(for: imported).idle.presetIDs.count, 1)
        let new = try f.library.addSet(from: [f.image], name: "New")
        XCTAssertTrue(store.configuration(for: new).mappings.isEmpty)
        XCTAssertEqual(store.configuration(for: new).presets.count, 1, "A single imported image is shared by IDLE and Unassigned")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
    }

    @MainActor func testRoundTripKeepsPerPackSelectionsModesNamesAndModifierCombinations() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let builtIn = f.library.activeSet
        var pack = store.configuration(for: builtIn)
        let ids = Array(pack.presets.prefix(3).map(\.id))
        pack.name = "자유로운 팩 이름"
        pack.presets[0].name = "자유로운 표정"
        pack.idle = PresetSelection(presetIDs: Array(ids.reversed()), mode: .cycle)
        pack.unassigned = PresetSelection(presetIDs: ids, mode: .random)
        pack.mappings = [PresetKeyMapping(stroke: KeyStroke(keyCode: 40, modifiers: [.control, .option, .shift, .command]), selection: PresetSelection(presetIDs: ids, mode: .cycle))]
        try store.save(pack, for: builtIn)
        let second = try f.library.addSet(from: [f.image], name: "Separate")
        let restored = f.store()
        XCTAssertEqual(restored.configuration(for: builtIn), pack)
        XCTAssertTrue(restored.configuration(for: second).mappings.isEmpty)
        XCTAssertNotEqual(restored.configuration(for: second).name, pack.name)
    }

    @MainActor func testInvalidSelectionsCannotOverwriteSavedPack() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let set = f.library.activeSet
        let original = store.activeConfiguration
        let bytes = try Data(contentsOf: f.library.packConfigurationsURL)
        var invalid = original
        invalid.idle.presetIDs = []
        XCTAssertThrowsError(try store.save(invalid, for: set))
        invalid = original
        invalid.unassigned.presetIDs = ["missing"]
        XCTAssertThrowsError(try store.save(invalid, for: set))
        invalid = original
        let mapping = PresetKeyMapping(stroke: KeyStroke(keyCode: 0, modifiers: []), selection: original.idle)
        invalid.mappings = [mapping, mapping]
        XCTAssertThrowsError(try store.save(invalid, for: set))
        XCTAssertEqual(try Data(contentsOf: f.library.packConfigurationsURL), bytes)
        XCTAssertEqual(store.activeConfiguration, original)
    }

    @MainActor func testUnreadableAndFutureDocumentsArePreserved() throws {
        let f = try Fixture(); defer { f.cleanup() }
        _ = f.store()
        for text in ["broken document", "{\"version\":99,\"packs\":{}}"] {
            let bytes = Data(text.utf8)
            try bytes.write(to: f.library.packConfigurationsURL)
            let store = f.store()
            XCTAssertNotNil(store.loadError)
            XCTAssertThrowsError(try store.save(store.activeConfiguration, for: f.library.activeSet))
            XCTAssertEqual(try Data(contentsOf: f.library.packConfigurationsURL), bytes)
        }
    }

    @MainActor func testImportedPresetIsIndependentOfOriginalAndCanBeSavedInBuiltInPack() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let source = f.root.appendingPathComponent("my-expression.png")
        try FileManager.default.copyItem(at: f.image, to: source)
        let preset = try XCTUnwrap(store.importPresets([source], into: f.library.activeSet).first)
        let copy = try XCTUnwrap(store.imageURL(for: preset, in: f.library.activeSet))
        XCTAssertNotEqual(source, copy)
        try FileManager.default.removeItem(at: source)
        XCTAssertNotNil(NSImage(contentsOf: copy))
        var pack = store.activeConfiguration
        pack.presets.append(preset)
        pack.idle.presetIDs = [preset.id]
        try store.save(pack, for: f.library.activeSet)
        XCTAssertEqual(f.store().idleURL, copy)
    }

    func testPlaybackUsesExactModifiersAndIndependentKeyFallbackAndIdleCycles() {
        var pack = samplePack()
        let plain = KeyStroke(keyCode: 0, modifiers: [])
        let combo = KeyStroke(keyCode: 0, modifiers: [.command, .shift])
        pack.mappings = [PresetKeyMapping(stroke: combo, selection: PresetSelection(presetIDs: ["c", "d"], mode: .cycle))]
        var cursor = PresetPlaybackCursor()
        XCTAssertEqual(cursor.reaction(for: combo, in: pack), "c")
        XCTAssertEqual(cursor.reaction(for: plain, in: pack), "a")
        XCTAssertEqual(cursor.idle(in: pack), "e")
        XCTAssertEqual(cursor.reaction(for: combo, in: pack), "d")
        XCTAssertEqual(cursor.reaction(for: KeyStroke(keyCode: 1, modifiers: []), in: pack), "b")
        XCTAssertEqual(cursor.idle(in: pack), "f")
        XCTAssertEqual(cursor.reaction(for: combo, in: pack), "c")
        pack.idle.presetIDs.reverse()
        XCTAssertEqual(cursor.idle(in: pack), "f", "Changing a selection starts its new cycle at the first image")
    }

    func testRandomPlaybackAvoidsImmediateRepeats() {
        var cursor = PresetPlaybackCursor()
        let selection = PresetSelection(presetIDs: ["a", "b", "c"])
        var previous: String?
        for _ in 0..<20 {
            let next = cursor.next(in: selection, channel: "random", randomIndex: { _ in 0 })
            XCTAssertNotNil(next)
            XCTAssertNotEqual(previous, next)
            previous = next
        }
    }

    @MainActor func testEditorOpensOnlyOneTargetAndPreviewUsesDraftThenReturnsToIdle() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let editor = PackEditorModel(store: f.store())
        let stroke = KeyStroke(keyCode: 0, modifiers: [.command, .option])
        editor.toggle(.unassigned)
        editor.toggle(.idle)
        XCTAssertEqual(editor.expandedTarget, .idle)
        editor.toggle(.idle)
        XCTAssertNil(editor.expandedTarget)
        let ids = editor.draft.presets.map(\.id)
        editor.assignPreset(ids[1], to: stroke)
        XCTAssertTrue(editor.isDirty)
        editor.startPreview()
        editor.previewKey(stroke)
        XCTAssertEqual(editor.previewPresetID, ids[1])
        XCTAssertEqual(editor.previewStroke, stroke)
        try await Task.sleep(nanoseconds: 850_000_000)
        XCTAssertEqual(editor.previewSource, "IDLE")
        XCTAssertEqual(editor.previewPresetID, editor.draft.idle.presetIDs.first)
        editor.stopPreview()
        editor.saveAndApply(onApplied: {})
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(f.store().activeConfiguration.mappings.first?.stroke, stroke)
    }

    private func samplePack() -> PetPackConfiguration {
        PetPackConfiguration(name: "Test", presets: [],
            unassigned: PresetSelection(presetIDs: ["a", "b"], mode: .cycle),
            idle: PresetSelection(presetIDs: ["e", "f"], mode: .cycle))
    }
}
