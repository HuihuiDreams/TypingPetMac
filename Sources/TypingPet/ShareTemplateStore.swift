import Foundation
import Combine

struct ShareTemplate: Codable, Identifiable {
    var id: String { preview.code }
    let preview: LocalSharePreview
    let folder: String
    var lastCheckedAt: Date?
    var latestVersion: Int?
    var checkStatus: String?
}

/// A template never enters PetImageLibrary until the user explicitly makes a copy.
@MainActor
final class ShareTemplateStore: ObservableObject {
    @Published var showsImport = false
    @Published var managementCode: String?
    @Published private(set) var templates: [ShareTemplate] = []
    @Published private(set) var loadError: String?
    let directory: URL

    init(directory: URL = AppEnvironment.supportDirectory.appendingPathComponent("SharedTemplates")) {
        self.directory = directory
        let index = directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            do {
                let data = try Data(contentsOf: index)
                guard data.count <= 10 * 1024 * 1024 else { throw LocalShareError.invalidPackage }
                templates = try JSONDecoder().decode([ShareTemplate].self, from: data)
                guard Set(templates.map(\.id)).count == templates.count,
                      templates.allSatisfy({ UUID(uuidString: $0.folder) != nil && LocalShareAPI.normalizedCode($0.id) == $0.id && $0.id.count == 6 }) else {
                    throw LocalShareError.invalidPackage
                }
            } catch { templates = []; loadError = error.localizedDescription }
        }
    }

    private func save(_ next: [ShareTemplate]) throws {
        guard loadError == nil else { throw LocalShareError.invalidPackage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("index.json"), options: .atomic)
        templates = next
    }

    func receive(_ preview: LocalSharePreview) async throws {
        let data = try await LocalShareAPI.download(preview)
        try install(data, preview: preview)
    }

    func install(_ data: Data, preview: LocalSharePreview) throws {
        let (root, manifest) = try LocalShareAPI.extract(data)
        defer { try? FileManager.default.removeItem(at: root) }
        guard manifest.name == preview.manifest.name,
              manifest.configuration == preview.manifest.configuration,
              manifest.images == preview.manifest.images,
              manifest.creatorMessage == preview.manifest.creatorMessage else { throw LocalShareError.invalidPackage }
        let folder = UUID().uuidString
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(folder)
        try FileManager.default.moveItem(at: root, to: destination)
        let old = templates.first { $0.id == preview.id }
        var next = templates.filter { $0.id != preview.id }
        next.append(ShareTemplate(preview: preview, folder: folder, lastCheckedAt: Date(),
                                  latestVersion: preview.latestVersion, checkStatus: nil))
        do { try save(next) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        if let old { try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.folder)) }
    }

    func check(_ template: ShareTemplate) async throws {
        do {
            let preview = try await LocalShareAPI.preview(code: template.id)
            try recordCheck(template.id, latest: preview.latestVersion, status: nil)
        } catch {
            let unavailable: Bool
            if case LocalShareError.server("share_unavailable") = error { unavailable = true } else { unavailable = false }
            try recordCheck(template.id, latest: nil, status: unavailable ? "Share deleted" : "Update check failed")
            throw error
        }
    }

    private func recordCheck(_ code: String, latest: Int?, status: String?) throws {
        var next = templates
        guard let index = next.firstIndex(where: { $0.id == code }) else { return }
        next[index].lastCheckedAt = Date()
        next[index].latestVersion = latest
        next[index].checkStatus = status
        try save(next)
    }

    func update(_ template: ShareTemplate) async throws {
        try await receive(LocalShareAPI.preview(code: template.id))
    }

    func copy(_ template: ShareTemplate, into store: PetPackStore) throws -> PetImageSet {
        let root = directory.appendingPathComponent(template.folder)
        let manifest = try JSONDecoder().decode(LocalShareManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        return try LocalShareAPI.copy(manifest, root: root, into: store)
    }

    func copyVersion(code: String, revision: Int, into store: PetPackStore) async throws -> PetImageSet {
        if let template = templates.first(where: { $0.id == code && $0.preview.latestVersion == revision }) {
            let root = directory.appendingPathComponent(template.folder)
            let manifest = try JSONDecoder().decode(LocalShareManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
            return try LocalShareAPI.copy(manifest, root: root, into: store, revision: revision)
        }
        let preview = try await LocalShareAPI.version(code: code, revision: revision)
        let data = try await LocalShareAPI.download(preview)
        return try LocalShareAPI.unpack(data, into: store, revision: revision)
    }

    func remove(_ template: ShareTemplate) throws {
        try save(templates.filter { $0.id != template.id })
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(template.folder))
    }
}
