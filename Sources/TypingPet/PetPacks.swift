import AppKit
import Foundation

enum PresetPlaybackMode: String, Codable, CaseIterable {
    case random, cycle
    var title: String { self == .random ? L("Random") : L("Sequential") }
}

enum PresetImageSource: String, Codable { case imageSet, keyReaction }

struct PetImagePreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var fileName: String
    var source: PresetImageSource = .imageSet
}

struct PresetSelection: Codable, Equatable {
    var presetIDs: [String]
    var mode: PresetPlaybackMode = .random
}

struct PresetKeyMapping: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var stroke: KeyStroke
    var selection: PresetSelection
}

struct PetPackConfiguration: Codable, Equatable {
    var name: String
    var presets: [PetImagePreset]
    var unassigned: PresetSelection
    var idle: PresetSelection
    var mappings: [PresetKeyMapping] = []

    func selection(for stroke: KeyStroke?) -> PresetSelection {
        stroke.flatMap { key in mappings.first { $0.stroke == key }?.selection } ?? unassigned
    }
}

enum PetPackError: LocalizedError {
    case invalidSelection, invalidPreset, invalidName, unreadableConfiguration
    var errorDescription: String? {
        switch self {
        case .invalidSelection: L("Choose at least one preset for Unassigned and IDLE.")
        case .invalidPreset: L("A preset image is missing or cannot be read.")
        case .invalidName: L("Enter a name for the pack and each preset.")
        case .unreadableConfiguration: L("Could not read saved packs. The original file has been preserved.")
        }
    }
}

/// Both the desktop pet and the settings preview use this same selection engine.
struct PresetPlaybackCursor {
    private struct Position {
        var selection: PresetSelection
        var index = -1
        var previous: String?
    }
    private var positions: [String: Position] = [:]

    mutating func next(in selection: PresetSelection, channel: String, randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String? {
        guard !selection.presetIDs.isEmpty else { return nil }
        var position = positions[channel] ?? Position(selection: selection)
        if position.selection != selection { position = Position(selection: selection) }
        let chosen: String?
        switch selection.mode {
        case .cycle:
            position.index = (position.index + 1) % selection.presetIDs.count
            chosen = selection.presetIDs[position.index]
        case .random:
            chosen = ImagePicker(names: selection.presetIDs).next(excluding: position.previous, randomIndex: randomIndex)
        }
        position.previous = chosen
        positions[channel] = position
        return chosen
    }

    mutating func reaction(for stroke: KeyStroke?, in pack: PetPackConfiguration) -> String? {
        if let stroke, let rule = pack.mappings.first(where: { $0.stroke == stroke }) {
            return next(in: rule.selection, channel: "key:\(stroke.keyCode):\(stroke.modifiers.rawValue)")
        }
        return next(in: pack.unassigned, channel: "unassigned")
    }

    mutating func idle(in pack: PetPackConfiguration) -> String? { next(in: pack.idle, channel: "idle") }
}

@MainActor
final class PetPackStore {
    private struct Document: Codable {
        var version = 1
        var packs: [String: PetPackConfiguration]
    }
    let library: PetImageLibrary
    private let legacyKeys: KeyReactionStore
    private let fileManager: FileManager
    private var configurations: [String: PetPackConfiguration] = [:]
    private(set) var loadError: Error?

    init(library: PetImageLibrary, keyStore: KeyReactionStore, fileManager: FileManager = .default) {
        self.library = library
        legacyKeys = keyStore
        self.fileManager = fileManager
        let url = library.packConfigurationsURL
        if fileManager.fileExists(atPath: url.path) {
            do {
                let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
                guard document.version == 1 else { throw PetPackError.unreadableConfiguration }
                configurations = document.packs
            } catch { loadError = PetPackError.unreadableConfiguration }
        } else {
            // Preserve the old global key rules in every existing pack. New packs start clean.
            for set in library.imageSets { configurations[set.id.uuidString] = makeConfiguration(for: set, includeLegacyKeys: true) }
            do { try persist(configurations) } catch { loadError = error }
        }
    }

    func configuration(for set: PetImageSet) -> PetPackConfiguration {
        configurations[set.id.uuidString] ?? makeConfiguration(for: set, includeLegacyKeys: loadError != nil)
    }
    var activeConfiguration: PetPackConfiguration { configuration(for: library.activeSet) }

    func imageURL(for preset: PetImagePreset, in set: PetImageSet) -> URL? {
        switch preset.source {
        case .imageSet: library.presetImageURL(fileName: preset.fileName, in: set)
        case .keyReaction: legacyKeys.imageURL(fileName: preset.fileName)
        }
    }
    func imageURL(id: String, in pack: PetPackConfiguration, set: PetImageSet) -> URL? {
        pack.presets.first { $0.id == id }.flatMap { imageURL(for: $0, in: set) }
    }
    var idleURL: URL? {
        let pack = activeConfiguration
        return pack.idle.presetIDs.first.flatMap { imageURL(id: $0, in: pack, set: library.activeSet) }
    }

    func save(_ pack: PetPackConfiguration, for set: PetImageSet) throws {
        guard loadError == nil else { throw PetPackError.unreadableConfiguration }
        try validate(pack, in: set)
        var updated = configurations
        updated[set.id.uuidString] = pack
        try persist(updated)
        configurations = updated
    }

    func importPresets(_ urls: [URL], into set: PetImageSet) throws -> [PetImagePreset] {
        try urls.map { url in
            let fileName = try library.importPresetImage(from: url, into: set)
            return PetImagePreset(id: UUID().uuidString, name: url.deletingPathExtension().lastPathComponent, fileName: fileName)
        }
    }

    func replaceIdle(with url: URL) throws {
        let set = library.activeSet
        var pack = configuration(for: set)
        let imported = try importPresets([url], into: set)
        pack.presets.append(contentsOf: imported)
        pack.idle = PresetSelection(presetIDs: imported.map(\.id))
        try save(pack, for: set)
    }

    func replaceUnassigned(with urls: [URL]) throws {
        guard !urls.isEmpty else { throw PetPackError.invalidSelection }
        let set = library.activeSet
        var pack = configuration(for: set)
        let imported = try importPresets(urls, into: set)
        pack.presets.append(contentsOf: imported)
        pack.unassigned = PresetSelection(presetIDs: imported.map(\.id))
        try save(pack, for: set)
    }

    func resetToDefaults() throws {
        guard let builtIn = library.imageSets.first(where: { $0.id == PetImageLibrary.builtInID }) else { return }
        try save(makeConfiguration(for: builtIn, includeLegacyKeys: false), for: builtIn)
        library.resetToDefaults()
    }

    private func validate(_ pack: PetPackConfiguration, in set: PetImageSet) throws {
        guard !pack.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pack.presets.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw PetPackError.invalidName }
        let ids = Set(pack.presets.map(\.id))
        let selections = [pack.idle, pack.unassigned] + pack.mappings.map(\.selection)
        guard ids.count == pack.presets.count, !ids.isEmpty,
              selections.allSatisfy({ !$0.presetIDs.isEmpty && Set($0.presetIDs).count == $0.presetIDs.count && Set($0.presetIDs).isSubset(of: ids) }),
              Set(pack.mappings.map(\.stroke)).count == pack.mappings.count else { throw PetPackError.invalidSelection }
        for preset in pack.presets {
            guard let url = imageURL(for: preset, in: set), NSImage(contentsOf: url) != nil else { throw PetPackError.invalidPreset }
        }
    }

    private func persist(_ packs: [String: PetPackConfiguration]) throws {
        let url = library.packConfigurationsURL
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Document(packs: packs)).write(to: url, options: .atomic)
    }

    private func makeConfiguration(for set: PetImageSet, includeLegacyKeys: Bool) -> PetPackConfiguration {
        let fileNames = [set.idleFileName] + set.reactionFileNames
        var seen = Set<String>()
        let presets = fileNames.filter { seen.insert($0).inserted }.map { fileName in
            PetImagePreset(id: fileName, name: Self.presetName(fileName), fileName: fileName)
        }
        var reactionNames = Set<String>()
        let reactions = set.reactionFileNames.filter { reactionNames.insert($0).inserted }
        var pack = PetPackConfiguration(name: set.name, presets: presets,
            unassigned: PresetSelection(presetIDs: reactions.isEmpty ? [set.idleFileName] : reactions),
            idle: PresetSelection(presetIDs: [set.idleFileName]))
        if includeLegacyKeys {
            for rule in legacyKeys.rules where legacyKeys.imageURL(for: rule) != nil {
                let id = "key-" + rule.id.uuidString
                pack.presets.append(PetImagePreset(id: id, name: rule.stroke.displayName, fileName: rule.imageFileName, source: .keyReaction))
                pack.mappings.append(PresetKeyMapping(stroke: rule.stroke, selection: PresetSelection(presetIDs: [id])))
            }
        }
        return pack
    }

    private static func presetName(_ fileName: String) -> String {
        switch fileName {
        case "pet-idle.png": return L("Basic Expression")
        case "pet-left.png": return L("Left Hand")
        case "pet-right.png": return L("Right Hand")
        case "pet-question.png": return L("Curious")
        case "pet-exclamation.png": return L("Surprised")
        default:
            let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            return base.count > 37 && UUID(uuidString: String(base.prefix(36))) != nil ? String(base.dropFirst(37)) : base
        }
    }
}
