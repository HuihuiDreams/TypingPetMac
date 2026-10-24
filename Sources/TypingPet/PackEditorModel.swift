import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum PackEditorTarget: Hashable {
    case key(KeyStroke), unassigned, idle
    var title: String {
        switch self {
        case .key(let stroke): stroke.displayName
        case .unassigned: L("Unassigned")
        case .idle: "IDLE"
        }
    }
}

@MainActor
final class PackEditorModel: ObservableObject {
    let store: PetPackStore
    @Published private(set) var sets: [PetImageSet]
    @Published private(set) var selectedSetID: UUID
    @Published var draft: PetPackConfiguration
    @Published var selectedPresetID: String
    @Published var modifiers: KeyModifiers = []
    @Published var expandedTarget: PackEditorTarget?
    @Published var errorMessage: String?
    @Published var statusMessage = ""
    @Published private(set) var isPreviewing = false
    @Published private(set) var previewPresetID: String?
    @Published private(set) var previewStroke: KeyStroke?
    @Published private(set) var previewSource = "IDLE"
    @Published private(set) var lastPreviewKey = ""
    private var saved: PetPackConfiguration
    private var drafts: [UUID: (PetPackConfiguration, PetPackConfiguration)] = [:]
    private var imageCache: [URL: NSImage] = [:]
    private var cursor = PresetPlaybackCursor()
    private var idleWork: DispatchWorkItem?
    private var generation = 0
    private var editingModifiers: KeyModifiers = []

    init(store: PetPackStore) {
        self.store = store
        sets = store.library.imageSets
        selectedSetID = store.library.activeSetID
        let pack = store.activeConfiguration
        draft = pack
        saved = pack
        selectedPresetID = pack.presets.first?.id ?? ""
        errorMessage = store.loadError?.localizedDescription
    }

    var selectedSet: PetImageSet { sets.first { $0.id == selectedSetID } ?? store.library.activeSet }
    var isDirty: Bool { draft != saved }
    var isActive: Bool { selectedSetID == store.library.activeSetID }
    var canSave: Bool { store.loadError == nil }

    func refreshIfClean() {
        sets = store.library.imageSets
        guard !isDirty else { return }
        if !sets.contains(where: { $0.id == selectedSetID }) { selectedSetID = store.library.activeSetID }
        draft = store.configuration(for: selectedSet)
        saved = draft
        if !draft.presets.contains(where: { $0.id == selectedPresetID }) { selectedPresetID = draft.presets.first?.id ?? "" }
    }

    func selectSet(_ set: PetImageSet) {
        guard selectedSetID != set.id else { return }
        stopPreview()
        drafts[selectedSetID] = (draft, saved)
        selectedSetID = set.id
        let remembered = drafts[set.id]
        draft = remembered?.0 ?? store.configuration(for: set)
        saved = remembered?.1 ?? draft
        selectedPresetID = draft.presets.first?.id ?? ""
        expandedTarget = nil
        statusMessage = ""
    }

    func image(for preset: PetImagePreset, in set: PetImageSet? = nil) -> NSImage? {
        guard let url = store.imageURL(for: preset, in: set ?? selectedSet) else { return nil }
        if let cached = imageCache[url] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[url] = image
        return image
    }
    func image(id: String?) -> NSImage? {
        id.flatMap { value in draft.presets.first { $0.id == value } }.flatMap { image(for: $0) }
    }
    func name(id: String?) -> String { draft.presets.first { $0.id == id }?.name ?? "" }

    func selection(for target: PackEditorTarget) -> PresetSelection {
        switch target {
        case .unassigned: draft.unassigned
        case .idle: draft.idle
        case .key(let stroke): draft.mappings.first { $0.stroke == stroke }?.selection ?? PresetSelection(presetIDs: [])
        }
    }

    private func update(_ selection: PresetSelection, for target: PackEditorTarget) {
        switch target {
        case .unassigned: draft.unassigned = selection
        case .idle: draft.idle = selection
        case .key(let stroke):
            if let index = draft.mappings.firstIndex(where: { $0.stroke == stroke }) {
                if selection.presetIDs.isEmpty { draft.mappings.remove(at: index) }
                else { draft.mappings[index].selection = selection }
            } else if !selection.presetIDs.isEmpty {
                draft.mappings.append(PresetKeyMapping(stroke: stroke, selection: selection))
            }
        }
        statusMessage = ""
    }

    func toggle(_ target: PackEditorTarget) { expandedTarget = expandedTarget == target ? nil : target }
    func toggleModifier(_ modifier: KeyModifiers) {
        if modifiers.contains(modifier) { modifiers.remove(modifier) } else { modifiers.insert(modifier) }
        if case .key(let old) = expandedTarget { expandedTarget = .key(KeyStroke(keyCode: old.keyCode, modifiers: modifiers)) }
    }

    func togglePreset(_ id: String, for target: PackEditorTarget) {
        var value = selection(for: target)
        if value.presetIDs.contains(id) {
            if value.presetIDs.count == 1, target == .idle || target == .unassigned {
                statusMessage = L("Choose at least one preset.")
                return
            }
            value.presetIDs.removeAll { $0 == id }
        } else { value.presetIDs.append(id) }
        update(value, for: target)
    }

    func setMode(_ mode: PresetPlaybackMode, for target: PackEditorTarget) {
        var value = selection(for: target)
        value.mode = mode
        update(value, for: target)
    }

    func movePreset(_ id: String, by offset: Int, for target: PackEditorTarget) {
        var value = selection(for: target)
        guard let index = value.presetIDs.firstIndex(of: id), value.presetIDs.indices.contains(index + offset) else { return }
        value.presetIDs.swapAt(index, index + offset)
        update(value, for: target)
    }

    func unassign(_ target: PackEditorTarget) { if case .key = target { update(PresetSelection(presetIDs: []), for: target) } }

    func assignPreset(_ id: String, to stroke: KeyStroke) {
        guard draft.presets.contains(where: { $0.id == id }) else { return }
        update(PresetSelection(presetIDs: [id]), for: .key(stroke))
        expandedTarget = .key(stroke)
    }

    func saveAndApply(onApplied: () -> Void) {
        do {
            draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.save(draft, for: selectedSet)
            try store.library.activateSet(id: selectedSetID)
            saved = draft
            drafts.removeValue(forKey: selectedSetID)
            statusMessage = L("Pack saved and applied.")
            onApplied()
        } catch { errorMessage = error.localizedDescription }
    }

    func addPresets() {
        let panel = NSOpenPanel()
        panel.title = L("Add Preset Images")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            let presets = try store.importPresets(panel.urls, into: selectedSet)
            draft.presets.append(contentsOf: presets)
            selectedPresetID = presets.first?.id ?? selectedPresetID
        } catch { errorMessage = error.localizedDescription }
    }

    func replacePresetImage() {
        guard let index = draft.presets.firstIndex(where: { $0.id == selectedPresetID }) else { return }
        let panel = NSOpenPanel()
        panel.title = L("Replace Preset Image")
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let replacement = try store.importPresets([url], into: selectedSet).first else { return }
            draft.presets[index].fileName = replacement.fileName
            draft.presets[index].source = replacement.source
        } catch { errorMessage = error.localizedDescription }
    }

    func importPack(folder: Bool, onImported: () -> Void) {
        let panel = NSOpenPanel()
        panel.title = L("Import Image Pack")
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = !folder
        if !folder { panel.allowedContentTypes = [.image] }
        guard panel.runModal() == .OK else { return }
        do {
            let set: PetImageSet
            if folder, let url = panel.url { set = try store.library.addSet(from: url) }
            else { set = try store.library.addSet(from: panel.urls, name: L("New Pack")) }
            sets = store.library.imageSets
            selectSet(set)
            try store.save(draft, for: set)
            saved = draft
            onImported()
        } catch { errorMessage = error.localizedDescription }
    }

    func removePack(_ set: PetImageSet, onRemoved: () -> Void) {
        guard !set.isBuiltIn else { return }
        let alert = NSAlert()
        alert.messageText = L("Remove “%1$@” from the list?", store.configuration(for: set).name)
        alert.informativeText = L("Original images will not be changed.")
        alert.addButton(withTitle: L("Remove"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.library.deleteSet(id: set.id)
            sets = store.library.imageSets
            if selectedSetID == set.id {
                selectSet(store.library.activeSet)
            }
            drafts.removeValue(forKey: set.id)
            onRemoved()
        } catch { errorMessage = error.localizedDescription }
    }

    func startPreview() {
        editingModifiers = modifiers
        cursor = PresetPlaybackCursor()
        isPreviewing = true
        previewStroke = nil
        lastPreviewKey = ""
        showPreviewIdle()
    }
    func stopPreview() {
        generation += 1
        idleWork?.cancel()
        idleWork = nil
        guard isPreviewing else { return }
        isPreviewing = false
        modifiers = editingModifiers
        previewStroke = nil
    }
    func previewKey(_ stroke: KeyStroke) {
        guard isPreviewing else { return }
        generation += 1
        let currentGeneration = generation
        idleWork?.cancel()
        modifiers = stroke.modifiers
        previewStroke = stroke
        lastPreviewKey = stroke.displayName
        previewSource = draft.mappings.contains { $0.stroke == stroke } ? L("Key Mapping") + " · " + stroke.displayName : L("Unassigned")
        previewPresetID = cursor.reaction(for: stroke, in: draft)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == currentGeneration, self.isPreviewing else { return }
            self.showPreviewIdle()
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }
    func showPreviewIdle() {
        guard isPreviewing else { return }
        generation += 1
        idleWork?.cancel()
        idleWork = nil
        previewSource = "IDLE"
        previewStroke = nil
        previewPresetID = cursor.idle(in: draft)
    }
    func previewUnassigned() {
        previewKey(KeyStroke(keyCode: UInt16.max, modifiers: []))
        lastPreviewKey = L("Unassigned")
    }
}

struct KeyboardLayoutKey: Identifiable {
    var code: UInt16?
    var label: String
    var width: CGFloat = 1
    var id: String { "\(code.map(String.init) ?? label)-\(label)" }
    static let rows: [[KeyboardLayoutKey]] = [
        [Self(code: 53, label: "esc")] + zip([122,120,99,118,96,97,98,100,101,109,103,111], 1...12).map { Self(code: UInt16($0.0), label: "F\($0.1)") },
        [Self(code:50,label:"`"),Self(code:18,label:"1"),Self(code:19,label:"2"),Self(code:20,label:"3"),Self(code:21,label:"4"),Self(code:23,label:"5"),Self(code:22,label:"6"),Self(code:26,label:"7"),Self(code:28,label:"8"),Self(code:25,label:"9"),Self(code:29,label:"0"),Self(code:27,label:"−"),Self(code:24,label:"="),Self(code:51,label:"⌫",width:1.5)],
        [Self(code:48,label:"⇥",width:1.5),Self(code:12,label:"Q"),Self(code:13,label:"W"),Self(code:14,label:"E"),Self(code:15,label:"R"),Self(code:17,label:"T"),Self(code:16,label:"Y"),Self(code:32,label:"U"),Self(code:34,label:"I"),Self(code:31,label:"O"),Self(code:35,label:"P"),Self(code:33,label:"["),Self(code:30,label:"]"),Self(code:42,label:"\\")],
        [Self(code:nil,label:"caps",width:1.8),Self(code:0,label:"A"),Self(code:1,label:"S"),Self(code:2,label:"D"),Self(code:3,label:"F"),Self(code:5,label:"G"),Self(code:4,label:"H"),Self(code:38,label:"J"),Self(code:40,label:"K"),Self(code:37,label:"L"),Self(code:41,label:";"),Self(code:39,label:"'"),Self(code:36,label:"↩",width:1.8)],
        [Self(code:nil,label:"⇧L",width:2.2),Self(code:6,label:"Z"),Self(code:7,label:"X"),Self(code:8,label:"C"),Self(code:9,label:"V"),Self(code:11,label:"B"),Self(code:45,label:"N"),Self(code:46,label:"M"),Self(code:43,label:","),Self(code:47,label:"."),Self(code:44,label:"/"),Self(code:nil,label:"⇧R",width:2.2)],
        [Self(code:nil,label:"fn"),Self(code:nil,label:"⌃"),Self(code:nil,label:"⌥L"),Self(code:nil,label:"⌘L",width:1.3),Self(code:49,label:"space",width:5),Self(code:nil,label:"⌘R",width:1.3),Self(code:nil,label:"⌥R"),Self(code:123,label:"←"),Self(code:126,label:"↑"),Self(code:125,label:"↓"),Self(code:124,label:"→")]
    ]
}
