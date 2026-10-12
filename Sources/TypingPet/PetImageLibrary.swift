import AppKit
import Foundation

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

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let name): "不支持的图像格式: \(name)"
        case .unreadableImage(let name): "无法读取图像: \(name)"
        case .noImagesInFolder: "所选文件夹中未找到支持的图像。"
        case .noReactionImages: "请选择至少一张按键反应图像。"
        case .imageSetNotFound: "未找到图像集。"
        case .cannotDeleteBuiltInSet: "无法删除默认图像集。"
        }
    }
}

@MainActor
final class PetImageLibrary {
    static let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
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

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard, imagesDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.defaults = defaults
        if let imagesDirectory {
            self.imagesDirectory = imagesDirectory
        } else {
            let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.imagesDirectory = baseDirectory
                .appendingPathComponent("TypingPet", isDirectory: true)
                .appendingPathComponent("Images", isDirectory: true)
        }
        setsDirectory = self.imagesDirectory.appendingPathComponent("Sets", isDirectory: true)
        if let data = defaults.data(forKey: AppPreferencesKey.gallery),
           let decoded = try? JSONDecoder().decode([PetImageSet].self, from: data) {
            customSets = decoded.filter { !$0.isBuiltIn }
        } else {
            customSets = []
        }
        migrateLegacySelectionIfNeeded()
        repairActiveSelection()
    }

    var imageSets: [PetImageSet] { [Self.builtInSet] + customSets }

    var activeSetID: UUID {
        get { UUID(uuidString: defaults.string(forKey: AppPreferencesKey.activeSetID) ?? "") ?? Self.builtInID }
        set { defaults.set(newValue.uuidString, forKey: AppPreferencesKey.activeSetID) }
    }

    var activeSet: PetImageSet { imageSets.first { $0.id == activeSetID } ?? Self.builtInSet }
    var idleURL: URL? { idleURL(for: activeSet) }
    var reactionURLs: [URL] { reactionURLs(for: activeSet) }
    var usesCustomImages: Bool { activeSetID != Self.builtInID }

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
        guard imageSets.contains(where: { $0.id == id }) else { throw PetImageLibraryError.imageSetNotFound }
        activeSetID = id
    }

    @discardableResult
    func addSet(from folderURL: URL, name: String? = nil) throws -> PetImageSet {
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let selection = FolderImageSelection.make(from: contents)
        let allImages = ([selection.idleURL].compactMap { $0 } + selection.reactionURLs)
        guard !allImages.isEmpty else { throw PetImageLibraryError.noImagesInFolder }

        let idleSource = selection.idleURL ?? allImages[0]
        var reactionSources = selection.reactionURLs.filter { $0 != idleSource }
        if reactionSources.isEmpty { reactionSources = [idleSource] }

        let id = UUID()
        let folderName = id.uuidString
        let destination = setsDirectory.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let idleName = try copyImage(from: idleSource, to: destination)
        let reactionNames = try reactionSources.map { try copyImage(from: $0, to: destination) }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? folderURL.lastPathComponent
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
        let setToDelete = customSets.remove(at: index)

        // Cache Invalidation (F4.2): Must resolve URLs before physical file deletion
        if let idle = idleURL(for: setToDelete) {
            invalidateCache(for: idle)
        }
        for reaction in reactionURLs(for: setToDelete) {
            invalidateCache(for: reaction)
        }

        // F2.1: Physically delete custom set storage directory on disk
        if let folder = setToDelete.storageFolder?.trimmingCharacters(in: .whitespacesAndNewlines),
           !folder.isEmpty,
           folder != ".",
           folder != "..",
           !folder.contains("/") {
            let directory = setsDirectory.appendingPathComponent(folder, isDirectory: true)
            if fileManager.fileExists(atPath: directory.path) {
                try? fileManager.removeItem(at: directory)
            }
        }

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
        var set = try editableActiveSet(named: "自定义图像")
        let oldIdleURL = idleURL(for: set)
        if set.storageFolder == nil { set.storageFolder = set.id.uuidString }
        let directory = try storageDirectory(for: set)
        set.idleFileName = try copyImage(from: sourceURL, to: directory)
        if let oldIdleURL {
            invalidateCache(for: oldIdleURL)
        }
        update(set)
    }

    func replaceReactions(with sourceURLs: [URL]) throws {
        guard !sourceURLs.isEmpty else { throw PetImageLibraryError.noReactionImages }
        var set = try editableActiveSet(named: "自定义图像")
        let oldReactionURLs = reactionURLs(for: set)
        if set.storageFolder == nil { set.storageFolder = set.id.uuidString }
        let directory = try storageDirectory(for: set)
        set.reactionFileNames = try sourceURLs.map { try copyImage(from: $0, to: directory) }
        for oldURL in oldReactionURLs {
            invalidateCache(for: oldURL)
        }
        update(set)
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
            name: "默认图集",
            storageFolder: nil,
            idleFileName: defaultIdleName,
            reactionFileNames: defaultReactionNames,
            isBuiltIn: true
        )
    }

    private func resolvedURL(fileName: String, set: PetImageSet) -> URL? {
        if set.isBuiltIn {
            let name = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            if let bundled = Bundle.main.url(forResource: name, withExtension: "png") { return bundled }
            return debugFallbackURL(for: fileName)
        }
        let base = set.storageFolder.map { setsDirectory.appendingPathComponent($0, isDirectory: true) } ?? imagesDirectory
        let url = base.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) { return url }
        if Self.defaultReactionNames.contains(fileName) || fileName == Self.defaultIdleName {
            let name = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            if let bundled = Bundle.main.url(forResource: name, withExtension: "png") { return bundled }
            return debugFallbackURL(for: fileName)
        }
        return nil
    }

    private func debugFallbackURL(for fileName: String) -> URL? {
        #if DEBUG
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: source.path) ? source : nil
        #else
        return nil
        #endif
    }

    private func editableActiveSet(named defaultName: String) throws -> PetImageSet {
        if !activeSet.isBuiltIn { return activeSet }
        let id = UUID()
        let folder = id.uuidString
        let directory = setsDirectory.appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let idleName = try idleURL.map { try copyImage(from: $0, to: directory) } ?? Self.defaultIdleName
        let reactions = try reactionURLs.map { try copyImage(from: $0, to: directory) }
        let set = PetImageSet(id: id, name: defaultName, storageFolder: folder, idleFileName: idleName, reactionFileNames: reactions, isBuiltIn: false)
        customSets.append(set)
        persistGallery()
        activeSetID = id
        return set
    }

    private func update(_ set: PetImageSet) {
        guard let index = customSets.firstIndex(where: { $0.id == set.id }) else { return }
        customSets[index] = set
        persistGallery()
        activeSetID = set.id
    }

    private func storageDirectory(for set: PetImageSet) throws -> URL {
        let folder = set.storageFolder ?? set.id.uuidString
        let url = setsDirectory.appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func copyImage(from sourceURL: URL, to destinationDirectory: URL) throws -> String {
        let ext = sourceURL.pathExtension.lowercased()
        guard FolderImageSelection.supportedExtensions.contains(ext) else {
            throw PetImageLibraryError.unsupportedFormat(sourceURL.lastPathComponent)
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
        if let data = try? JSONEncoder().encode(customSets) { defaults.set(data, forKey: AppPreferencesKey.gallery) }
    }

    private func repairActiveSelection() {
        if !imageSets.contains(where: { $0.id == activeSetID }) { activeSetID = Self.builtInID }
    }

    private func migrateLegacySelectionIfNeeded() {
        guard customSets.isEmpty else { return }
        let idle = defaults.string(forKey: AppPreferencesKey.legacyIdleFile)
        let reactions = defaults.stringArray(forKey: AppPreferencesKey.legacyReactionFiles) ?? []
        guard idle != nil || !reactions.isEmpty else { return }
        let set = PetImageSet(
            id: UUID(), name: "现有用户图集", storageFolder: nil,
            idleFileName: idle ?? Self.defaultIdleName,
            reactionFileNames: reactions.isEmpty ? Self.defaultReactionNames : reactions,
            isBuiltIn: false
        )
        customSets = [set]
        persistGallery()
        activeSetID = set.id
        defaults.removeObject(forKey: AppPreferencesKey.legacyIdleFile)
        defaults.removeObject(forKey: AppPreferencesKey.legacyReactionFiles)
    }
}
