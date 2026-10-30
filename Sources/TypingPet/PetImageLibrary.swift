import AppKit
import Foundation

/// 应用存储中的文件或目录名只允许单级名称，防止读取或删除时越出存储目录。
enum StoredFileName {
    static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}

struct FolderImageSelection {
    let idleURL: URL?
    let reactionURLs: [URL]

    static let supportedExtensions: Set<String> = [
        "png", "apng", "jpg", "jpeg", "gif",
        "tif", "tiff", "heic", "heif", "webp"
    ]

    static func make(from urls: [URL]) -> FolderImageSelection {
        let images = urls
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let idleURL = images.first {
            let name = $0.deletingPathExtension().lastPathComponent.lowercased()
            return name == "idle" || name == "pet-idle" || name == "basic"
        }
        return FolderImageSelection(idleURL: idleURL, reactionURLs: images.filter { $0 != idleURL })
    }
}

struct PetImageSet: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var storageFolder: String?
    var idleFileName: String
    var reactionFileNames: [String]
    var isBuiltIn: Bool
}

struct FolderImportResult {
    let imageSet: PetImageSet
    let changedIdle: Bool
    let reactionCount: Int?
}

enum PetImageLibraryError: LocalizedError {
    case unsupportedFormat(String)
    case unreadableImage(String)
    case noImagesInFolder
    case noReactionImages
    case imageSetNotFound
    case cannotDeleteBuiltInSet
    case invalidStoragePath

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let name): L("Unsupported image format: %1$@", name)
        case .unreadableImage(let name): L("Cannot read image: %1$@", name)
        case .noImagesInFolder: L("No supported images were found in the selected folder.")
        case .noReactionImages: L("Select at least one reaction image.")
        case .imageSetNotFound: L("Image set not found.")
        case .cannotDeleteBuiltInSet: L("The built-in image set cannot be removed.")
        case .invalidStoragePath: L("Cannot read image: %1$@", "invalid path")
        }
    }
}

@MainActor
final class PetImageLibrary {
    private enum Keys {
        static let gallery = AppPreferencesKey.gallery
        static let activeSetID = AppPreferencesKey.activeSetID
        static let order = AppPreferencesKey.imagePackOrder
        static let legacyIdleFile = AppPreferencesKey.legacyIdleFile
        static let legacyReactionFiles = AppPreferencesKey.legacyReactionFiles
    }

    static let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let defaultIdleName = "basic.png"
    private static let defaultReactionNames = [
        "left.png", "right.png"
    ]

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let imagesDirectory: URL
    private let setsDirectory: URL
    private var customSets: [PetImageSet]
    private let imageCache = NSCache<NSURL, NSImage>()

    init(fileManager: FileManager = .default, defaults: UserDefaults = AppEnvironment.defaults, imagesDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.defaults = defaults
        imageCache.countLimit = 64
        if let imagesDirectory {
            self.imagesDirectory = imagesDirectory
        } else {
            self.imagesDirectory = AppEnvironment.supportDirectory
                .appendingPathComponent("Images", isDirectory: true)
        }
        setsDirectory = self.imagesDirectory.appendingPathComponent("Sets", isDirectory: true)
        if let data = defaults.data(forKey: Keys.gallery),
           let decoded = try? JSONDecoder().decode([PetImageSet].self, from: data) {
            customSets = decoded.filter { !$0.isBuiltIn }
        } else {
            customSets = []
        }
        migrateLegacySelectionIfNeeded()
        repairActiveSelection()
    }

    var imageSets: [PetImageSet] {
        let sets = [Self.builtInSet] + customSets
        let order = defaults.stringArray(forKey: Keys.order) ?? []
        let ranks = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return sets.enumerated().sorted {
            (ranks[$0.element.id.uuidString] ?? (order.count + $0.offset))
                < (ranks[$1.element.id.uuidString] ?? (order.count + $1.offset))
        }.map(\.element)
    }

    func moveSet(id: UUID, before target: UUID) {
        guard id != target, let set = imageSets.first(where: { $0.id == id }) else { return }
        var reordered = imageSets.filter { $0.id != id }
        guard let index = reordered.firstIndex(where: { $0.id == target }) else { return }
        reordered.insert(set, at: index)
        defaults.set(reordered.map { $0.id.uuidString }, forKey: Keys.order)
    }

    func addEmptySet(name: String) throws -> PetImageSet {
        let id = UUID()
        try fileManager.createDirectory(at: setsDirectory.appendingPathComponent(id.uuidString), withIntermediateDirectories: true)
        let set = PetImageSet(id: id, name: name, storageFolder: id.uuidString, idleFileName: "", reactionFileNames: [], isBuiltIn: false)
        customSets.append(set)
        persistGallery()
        return set
    }

    var activeSetID: UUID {
        get { UUID(uuidString: defaults.string(forKey: Keys.activeSetID) ?? "") ?? Self.builtInID }
        set { defaults.set(newValue.uuidString, forKey: Keys.activeSetID) }
    }

    var activeSet: PetImageSet {
        let id = activeSetID
        return id == Self.builtInID ? Self.builtInSet : (customSets.first { $0.id == id } ?? Self.builtInSet)
    }
    var idleURL: URL? { idleURL(for: activeSet) }
    var reactionURLs: [URL] { reactionURLs(for: activeSet) }
    var usesCustomImages: Bool { activeSetID != Self.builtInID }
    var packConfigurationsURL: URL { imagesDirectory.appendingPathComponent("packs-v1.json") }

    func presetImageURL(fileName: String, in set: PetImageSet) -> URL? {
        if let existing = resolvedURL(fileName: fileName, set: set) { return existing }
        let folder = set.storageFolder ?? set.id.uuidString
        guard !set.isBuiltIn, StoredFileName.isSafe(fileName), StoredFileName.isSafe(folder) else { return nil }
        let imported = setsDirectory.appendingPathComponent(folder)
            .appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: imported.path) ? imported : nil
    }

    func importPresetImage(from url: URL, into set: PetImageSet) throws -> String {
        try copyImage(from: url, to: storageDirectory(for: set))
    }

    func idleURL(for set: PetImageSet) -> URL? { resolvedURL(fileName: set.idleFileName, set: set) }

    func reactionURLs(for set: PetImageSet) -> [URL] {
        set.reactionFileNames.compactMap { resolvedURL(fileName: $0, set: set) }
    }

    func image(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    func thumbnail(for set: PetImageSet) -> NSImage? {
        guard let url = idleURL(for: set) else { return nil }
        return image(for: url)
    }

    func invalidateCache(for url: URL) {
        imageCache.removeObject(forKey: url as NSURL)
    }

    func clearCache() {
        imageCache.removeAllObjects()
    }

    func activateSet(id: UUID) throws {
        guard id == Self.builtInID || customSets.contains(where: { $0.id == id }) else { throw PetImageLibraryError.imageSetNotFound }
        let previousSet = activeSet
        activeSetID = id
        if previousSet.id != id {
            let idle = idleURL(for: previousSet)
            reactionURLs(for: previousSet).filter { $0 != idle }.forEach { invalidateCache(for: $0) }
        }
    }

    @discardableResult
    func addSet(from folderURL: URL, name: String? = nil) throws -> PetImageSet {
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            return values?.isSymbolicLink != true && values?.isRegularFile == true
        }
        return try addSet(from: contents, name: name ?? folderURL.lastPathComponent)
    }

    @discardableResult
    func addSet(from imageURLs: [URL], name: String) throws -> PetImageSet {
        let selection = FolderImageSelection.make(from: imageURLs)
        let allImages = ([selection.idleURL].compactMap { $0 } + selection.reactionURLs)
        guard !allImages.isEmpty else { throw PetImageLibraryError.noImagesInFolder }

        let idleSource = selection.idleURL ?? allImages[0]
        var reactionSources = selection.reactionURLs.filter { $0 != idleSource }
        if reactionSources.isEmpty { reactionSources = [idleSource] }

        let id = UUID()
        let folderName = id.uuidString
        let destination = setsDirectory.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let idleName: String
        let reactionNames: [String]
        do {
            idleName = try copyImage(from: idleSource, to: destination)
            if reactionSources.count == 1 && reactionSources[0] == idleSource {
                reactionNames = [idleName]
            } else {
                reactionNames = try reactionSources.map { try copyImage(from: $0, to: destination) }
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        let requestedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = requestedName.isEmpty ? L("New Pack") : requestedName
        let set = PetImageSet(
            id: id,
            name: displayName,
            storageFolder: folderName,
            idleFileName: idleName,
            reactionFileNames: reactionNames,
            isBuiltIn: false
        )
        customSets.append(set)
        persistGallery()
        activeSetID = id
        return set
    }

    func deleteSet(id: UUID) throws {
        guard id != Self.builtInID else { throw PetImageLibraryError.cannotDeleteBuiltInSet }
        guard let index = customSets.firstIndex(where: { $0.id == id }) else {
            throw PetImageLibraryError.imageSetNotFound
        }
        let setToDelete = customSets[index]
        let cachedURLs = [idleURL(for: setToDelete)].compactMap { $0 } + reactionURLs(for: setToDelete)
        try removeStoredImages(for: setToDelete)
        customSets.remove(at: index)
        cachedURLs.forEach { invalidateCache(for: $0) }
        if activeSetID == id { activeSetID = Self.builtInID }
        persistGallery()
    }

    func renameSet(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = customSets.firstIndex(where: { $0.id == id }) else {
            throw PetImageLibraryError.imageSetNotFound
        }
        customSets[index].name = trimmed
        persistGallery()
    }

    func replaceIdle(with sourceURL: URL) throws {
        try replaceImages(idleSource: sourceURL, reactionSources: nil)
    }

    func replaceReactions(with sourceURLs: [URL]) throws {
        guard !sourceURLs.isEmpty else { throw PetImageLibraryError.noReactionImages }
        try replaceImages(idleSource: nil, reactionSources: sourceURLs)
    }

    @discardableResult
    func importFolder(_ folderURL: URL) throws -> FolderImportResult {
        let set = try addSet(from: folderURL)
        return FolderImportResult(imageSet: set, changedIdle: true, reactionCount: set.reactionFileNames.count)
    }

    func resetToDefaults() { activeSetID = Self.builtInID }

    private static var builtInSet: PetImageSet {
        PetImageSet(
            id: builtInID,
            name: L("Default Set"),
            storageFolder: nil,
            idleFileName: defaultIdleName,
            reactionFileNames: defaultReactionNames,
            isBuiltIn: true
        )
    }

    private func resolvedURL(fileName: String, set: PetImageSet) -> URL? {
        // All idle, reaction, and preset lookups pass through this check before constructing a path.
        guard StoredFileName.isSafe(fileName),
              set.storageFolder.map(StoredFileName.isSafe) != false else { return nil }
        if set.isBuiltIn {
            return builtInResourceURL(fileName: fileName)
        }
        guard StoredFileName.isSafe(fileName), set.storageFolder.map(StoredFileName.isSafe) ?? true else { return nil }
        let base = set.storageFolder.map { setsDirectory.appendingPathComponent($0, isDirectory: true) } ?? imagesDirectory
        let url = base.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) { return url }
        if Self.defaultReactionNames.contains(fileName) || fileName == Self.defaultIdleName
            || fileName == "pet-idle.png" || fileName == "pet-left.png" || fileName == "pet-right.png" {
            return builtInResourceURL(fileName: fileName)
        }
        return nil
    }

    private func builtInResourceURL(fileName: String) -> URL? {
        let name = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if let bundled = Bundle.main.url(forResource: name, withExtension: "png") { return bundled }
        #if DEBUG
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: source.path) ? source : nil
        #else
        return nil
        #endif
    }

    private func replaceImages(idleSource: URL?, reactionSources: [URL]?) throws {
        let original = activeSet
        let oldURLs = [idleURL(for: original)].compactMap { $0 } + reactionURLs(for: original)
        let folder = UUID().uuidString
        let directory = setsDirectory.appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var replacement = original
        replacement.storageFolder = folder
        if original.isBuiltIn {
            replacement = PetImageSet(id: UUID(), name: L("Custom Images"), storageFolder: folder,
                                      idleFileName: original.idleFileName,
                                      reactionFileNames: original.reactionFileNames, isBuiltIn: false)
        }
        do {
            replacement.idleFileName = try (idleSource ?? idleURL(for: original))
                .map { try copyImage(from: $0, to: directory) } ?? original.idleFileName
            if let reactionSources {
                replacement.reactionFileNames = try reactionSources.map { try copyImage(from: $0, to: directory) }
            } else {
                replacement.reactionFileNames = try original.reactionFileNames.map { name in
                    try resolvedURL(fileName: name, set: original)
                        .map { try copyImage(from: $0, to: directory) } ?? name
                }
            }
            if !original.isBuiltIn { try removeStoredImages(for: original) }
        } catch {
            try fileManager.removeItem(at: directory)
            throw error
        }
        if let index = customSets.firstIndex(where: { $0.id == replacement.id }) {
            customSets[index] = replacement
        } else {
            customSets.append(replacement)
        }
        oldURLs.forEach { invalidateCache(for: $0) }
        persistGallery()
        activeSetID = replacement.id
    }

    private func storageDirectory(for set: PetImageSet) throws -> URL {
        let folder = set.storageFolder ?? set.id.uuidString
        guard StoredFileName.isSafe(folder) else {
            throw PetImageLibraryError.invalidStoragePath
        }
        let url = setsDirectory.appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeStoredImages(for set: PetImageSet) throws {
        let otherSets = customSets.filter { $0.id != set.id }
        if let folder = set.storageFolder {
            guard StoredFileName.isSafe(folder) else {
                throw PetImageLibraryError.invalidStoragePath
            }
            guard !otherSets.contains(where: { $0.storageFolder == folder }) else { return }
            let directory = setsDirectory.appendingPathComponent(folder, isDirectory: true)
            if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
        } else {
            let retained = Set(otherSets.filter { $0.storageFolder == nil }
                .flatMap { [$0.idleFileName] + $0.reactionFileNames })
            for name in Set([set.idleFileName] + set.reactionFileNames).subtracting(retained) {
                guard StoredFileName.isSafe(name) else {
                    throw PetImageLibraryError.invalidStoragePath
                }
                let url = imagesDirectory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            }
        }
    }

    private func copyImage(from sourceURL: URL, to destinationDirectory: URL) throws -> String {
        let ext = sourceURL.pathExtension.lowercased()
        guard FolderImageSelection.supportedExtensions.contains(ext) else {
            throw PetImageLibraryError.unsupportedFormat(sourceURL.lastPathComponent)
        }
        let values = try? sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values?.isSymbolicLink == false, values?.isRegularFile == true else {
            throw PetImageLibraryError.unreadableImage(sourceURL.lastPathComponent)
        }
        guard NSImage(contentsOf: sourceURL) != nil else {
            throw PetImageLibraryError.unreadableImage(sourceURL.lastPathComponent)
        }
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let safe = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = "\(UUID().uuidString)-\(safe).\(ext)"
        try fileManager.copyItem(at: sourceURL, to: destinationDirectory.appendingPathComponent(name))
        return name
    }

    private func persistGallery() {
        if let data = try? JSONEncoder().encode(customSets) { defaults.set(data, forKey: Keys.gallery) }
    }

    private func repairActiveSelection() {
        let id = activeSetID
        if id != Self.builtInID, !customSets.contains(where: { $0.id == id }) || (!activeSet.idleFileName.isEmpty && idleURL(for: activeSet) == nil) {
            activeSetID = Self.builtInID
        }
    }

    private func migrateLegacySelectionIfNeeded() {
        guard customSets.isEmpty else { return }
        let idle = defaults.string(forKey: Keys.legacyIdleFile)
        let reactions = defaults.stringArray(forKey: Keys.legacyReactionFiles) ?? []
        guard idle != nil || !reactions.isEmpty else { return }
        let set = PetImageSet(
            id: UUID(), name: L("Existing Custom Set"), storageFolder: nil,
            idleFileName: idle ?? Self.defaultIdleName,
            reactionFileNames: reactions.isEmpty ? Self.defaultReactionNames : reactions,
            isBuiltIn: false
        )
        customSets = [set]
        persistGallery()
        activeSetID = set.id
        defaults.removeObject(forKey: Keys.legacyIdleFile)
        defaults.removeObject(forKey: Keys.legacyReactionFiles)
    }
}
