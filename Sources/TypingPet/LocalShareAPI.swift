import Foundation
import CryptoKit
import AppKit

struct LocalShareManifest: Codable {
    let format: String
    let formatVersion: Int
    let name: String
    let configuration: PetPackConfiguration
    let images: [String: String]
    var creatorMessage: String? = nil
}

struct LocalSharePreview: Codable, Identifiable {
    var id: String { code }
    let code: String
    let status: String
    let latestVersion: Int
    let manifest: LocalShareManifest
    let packageSize: Int
    let sha256: String
    let publishedAt: Int
    var isPublic: Bool? = nil
}

struct CommunityPackSummary: Decodable, Identifiable {
    var id: String { code }
    let code: String
    let version: Int
    let name: String
    let creatorMessage: String
    let presetCount: Int
    let mappingCount: Int
    let packageSize: Int
    let publishedAt: Int
}
struct CommunityPackPage: Decodable {
    let packs: [CommunityPackSummary]
    let nextPage: Int?
}
private struct CommunityVisibility: Decodable { let isPublic: Bool }

struct ShareVersionSummary: Codable, Identifiable {
    var id: Int { version }
    let version: Int
    let name: String
    let creatorMessage: String
    let packageSize: Int
    let publishedAt: Int

    init(preview: LocalSharePreview) {
        version = preview.latestVersion; name = preview.manifest.name
        creatorMessage = preview.manifest.creatorMessage ?? ""
        packageSize = preview.packageSize; publishedAt = preview.publishedAt
    }
}

private struct ShareVersionHistory: Decodable {
    let versions: [ShareVersionSummary]
}

struct LocalShareCreated: Decodable {
    let managementPassword: String?
    let code: String
    let status: String
    let latestVersion: Int
}

private struct LocalShareStopped: Decodable {
    let code: String
    let status: String
    let latestVersion: Int
}

enum LocalShareError: LocalizedError {
    case unavailable, invalidPackage, invalidResponse, server(String), archiveFailed
    var errorDescription: String? {
        switch self {
        case .unavailable: L("Could not connect to the share service. Check your network and try again.")
        case .invalidPackage: L("This share package is invalid or incomplete.")
        case .invalidResponse: L("The local share server returned an invalid response.")
        case .server(let code):
            switch code {
            case "share_unavailable": L("This share code is unavailable or has been stopped.")
            case "password_length": L("Enter a management password.")
            case "invalid_password": L("The management password is incorrect.")
            case "version_conflict": L("This share changed. Check the latest version before publishing again.")
            case "rate_limited": L("Too many requests. Try again in a minute.")
            case "package_invalid": L("The share package is invalid.")
            case "package_size": L("The share package is too large.")
            default: L("Share request failed: %1$@", code)
            }
        case .archiveFailed: L("Could not prepare the set package.")
        }
    }
}

@MainActor
enum LocalShareAPI {
    static let serviceURL = URL(string: "https://pet.miel.ing/share-api")!

    static var baseURL: URL {
        // Only development tests may override the built-in service endpoint.
        if AppEnvironment.isDevelopment,
           let configured = ProcessInfo.processInfo.environment["TYPINGPET_SHARE_API_URL"],
           let url = URL(string: configured), url.user == nil, url.password == nil,
           url.query == nil, url.fragment == nil,
           url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost"].contains(url.host ?? "")) {
            return url
        }
        return serviceURL
    }

    private static func endpoint(_ path: String) throws -> URL {
        baseURL.appendingPathComponent(path)
    }

    static func normalizedCode(_ text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(6))
    }
    private static let codesKey = "localShareCodes-v1"

    static func code(for set: PetImageSet) -> String? {
        (AppEnvironment.defaults.dictionary(forKey: codesKey) as? [String: String])?[set.id.uuidString]
    }

    static func remember(_ code: String, for set: PetImageSet) {
        var codes = AppEnvironment.defaults.dictionary(forKey: codesKey) as? [String: String] ?? [:]
        codes[set.id.uuidString] = code
        AppEnvironment.defaults.set(codes, forKey: codesKey)
    }

    static func create(archive: Data, set: PetImageSet, requestID: String, secret: String, password: String? = nil) async throws -> LocalShareCreated {
        let result: LocalShareCreated = try await request("/v1/shares", method: "POST", body: archive, password: password,
            headers: ["X-Request-ID": requestID, "X-Request-Secret": secret])
        return result
    }

    static func update(code: String, configuration: PetPackConfiguration, set: PetImageSet, store: PetPackStore,
                       password: String, message: String, baseVersion: Int) async throws -> Int {
        let archive = try package(configuration: configuration, set: set, store: store, message: message)
        let result: LocalShareCreated = try await request("/v1/shares/\(code)/versions", method: "POST", body: archive,
            password: password, headers: ["X-Base-Version": String(baseVersion)])
        return result.latestVersion
    }

    static func stop(code: String, password: String) async throws {
        let _: LocalShareStopped = try await request("/v1/shares/\(code)", method: "DELETE", password: password)
    }

    static func preview(code: String) async throws -> LocalSharePreview {
        guard normalizedCode(code) == code, code.count == 6 else { throw LocalShareError.invalidResponse }
        return try await request("/v1/shares/\(code)")
    }

    static func authorize(code: String, password: String) async throws {
        let _: LocalShareCreated = try await request("/v1/shares/\(code)/authorize", method: "POST", password: password)
    }

    static func versions(code: String) async throws -> [ShareVersionSummary] {
        let history: ShareVersionHistory = try await request("/v1/shares/\(code)/versions")
        return history.versions
    }

    static func version(code: String, revision: Int) async throws -> LocalSharePreview {
        guard revision > 0 else { throw LocalShareError.invalidResponse }
        return try await request("/v1/shares/\(code)/versions/\(revision)/metadata")
    }

    static func community(page: Int = 1) async throws -> CommunityPackPage {
        try await request("/v1/community", query: [URLQueryItem(name: "page", value: String(page))])
    }
    static func communityCover(code: String, revision: Int) -> URL {
        var parts = URLComponents(url: baseURL.appendingPathComponent("v1/community/\(code)/cover"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "version", value: String(revision))]
        return parts.url!
    }
    static func setPublic(code: String, password: String, enabled: Bool) async throws -> Bool {
        let data = try JSONEncoder().encode(["isPublic": enabled])
        let result: CommunityVisibility = try await request("/v1/shares/\(code)/visibility", method: "POST", body: data,
            password: password, contentType: "application/json")
        return result.isPublic
    }

    static func download(_ preview: LocalSharePreview) async throws -> Data {
        let request = URLRequest(url: try endpoint("v1/shares/\(preview.code)/versions/\(preview.latestVersion)"))
        // Download to disk so an oversized response never accumulates in memory.
        let (file, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let response = response as? HTTPURLResponse else { throw LocalShareError.invalidResponse }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 50 * 1024 * 1024 else { throw LocalShareError.invalidPackage }
        let data = try Data(contentsOf: file)
        guard response.statusCode == 200 else { throw LocalShareError.server(errorCode(data)) }
        guard size == preview.packageSize,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == preview.sha256 else {
            throw LocalShareError.invalidPackage
        }
        return data
    }

    private static func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil,
            password: String? = nil, headers: [String: String] = [:], contentType: String = "application/zip",
            query: [URLQueryItem] = []) async throws -> T {
        var parts = URLComponents(url: try endpoint(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var request = URLRequest(url: parts.url!)
        request.timeoutInterval = 30
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let password { request.setValue(Data(password.utf8).base64EncodedString(), forHTTPHeaderField: "X-Share-Password-Base64") }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw LocalShareError.unavailable }
        guard let response = response as? HTTPURLResponse else { throw LocalShareError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw LocalShareError.server(errorCode(data)) }
        guard data.count <= 2 * 1024 * 1024,
              let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw LocalShareError.invalidResponse }
        return decoded
    }

    private static func errorCode(_ data: Data) -> String {
        (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "invalid_response"
    }

    static func package(configuration: PetPackConfiguration, set: PetImageSet, store: PetPackStore, message: String = "") throws -> Data {
        guard configuration.isUsable, message.count <= 500 else { throw LocalShareError.invalidPackage }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TypingPetShare-\(UUID().uuidString)", isDirectory: true)
        let images = root.appendingPathComponent("images", isDirectory: true)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("TypingPetShare-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: archive) }
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        var paths: [String: String] = [:]
        for preset in configuration.presets {
            guard StoredFileName.isSafe(preset.id) else { throw LocalShareError.invalidPackage }
            guard let source = store.imageURL(for: preset, in: set) else { throw LocalShareError.invalidPackage }
            let name = "\(preset.id).\(source.pathExtension.lowercased())"
            try FileManager.default.copyItem(at: source, to: images.appendingPathComponent(name))
            paths[preset.id] = "images/\(name)"
        }
        let manifest = LocalShareManifest(format: "typing-pet-pack", formatVersion: 1, name: configuration.name, configuration: configuration, images: paths, creatorMessage: message)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archive.path, "manifest.json", "images"]
        process.currentDirectoryURL = root
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: archive) else { throw LocalShareError.archiveFailed }
        return data
    }

    static func unpack(_ data: Data, into store: PetPackStore, revision: Int? = nil) throws -> PetImageSet {
        let (root, manifest) = try extract(data)
        defer { try? FileManager.default.removeItem(at: root) }
        return try copy(manifest, root: root, into: store, revision: revision)
    }

    static func extract(_ data: Data) throws -> (URL, LocalShareManifest) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TypingPetImport-\(UUID().uuidString)", isDirectory: true)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: root) } }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // Extract only validated regular files ourselves; no archive metadata or links are restored.
        try ShareArchiveValidator.validate(data, extractingTo: root)
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        guard manifestData.count <= 1024 * 1024,
              let manifest = try? JSONDecoder().decode(LocalShareManifest.self, from: manifestData) else {
            throw LocalShareError.invalidPackage
        }

        try validateManifest(manifest, root: root)
        succeeded = true
        return (root, manifest)
    }

    static func validateManifest(_ manifest: LocalShareManifest, root: URL) throws {
        let pack = manifest.configuration
        let ids = Set(pack.presets.map(\.id))
        guard manifest.format == "typing-pet-pack", manifest.formatVersion == 1,
              !(manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              manifest.name == pack.name, pack.isUsable,
              (manifest.creatorMessage?.count ?? 0) <= 500,
              pack.presets.count <= 100, ids.count == pack.presets.count,
              Set(manifest.images.keys) == ids,
              Set(pack.mappings.map(\.stroke)).count == pack.mappings.count else { throw LocalShareError.invalidPackage }
        for selection in [pack.idle, pack.unassigned] + pack.mappings.map(\.selection) {
            guard !selection.presetIDs.isEmpty,
                  Set(selection.presetIDs).count == selection.presetIDs.count,
                  Set(selection.presetIDs).isSubset(of: ids) else { throw LocalShareError.invalidPackage }
        }
        for preset in pack.presets {
            guard StoredFileName.isSafe(preset.id), !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let path = manifest.images[preset.id], path.hasPrefix("images/"),
                  path.split(separator: "/").count == 2,
                  StoredFileName.isSafe(String(path.dropFirst(7))) else { throw LocalShareError.invalidPackage }
            let url = root.appendingPathComponent(path)
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  (attributes.fileSize ?? Int.max) <= 50 * 1024 * 1024,
                  FolderImageSelection.supportedExtensions.contains(url.pathExtension.lowercased()),
                  NSImage(contentsOf: url) != nil else { throw LocalShareError.invalidPackage }
        }
    }

    static func copy(_ manifest: LocalShareManifest, root: URL, into store: PetPackStore, revision: Int? = nil) throws -> PetImageSet {
        try validateManifest(manifest, root: root)
        guard manifest.images.count == manifest.configuration.presets.count else { throw LocalShareError.invalidPackage }
        let originalName = manifest.configuration.name + (revision.map { " v\($0)" } ?? "")
        var name = "\(originalName) (\(L("Copy")))"
        var suffix = 2
        while store.library.imageSets.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            name = "\(originalName) (\(L("Copy")) \(suffix))"; suffix += 1
        }
        let set = try store.createPack(name: name)
        do {
            var configuration = manifest.configuration
            configuration.name = name
            for index in configuration.presets.indices {
                let id = configuration.presets[index].id
                guard let relative = manifest.images[id], !relative.hasPrefix("/"),
                      !relative.split(separator: "/").contains(".."), relative.hasPrefix("images/") else { throw LocalShareError.invalidPackage }
                let imageURL = root.appendingPathComponent(relative)
                let values = try imageURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw LocalShareError.invalidPackage }
                configuration.presets[index].fileName = try store.library.importPresetImage(from: imageURL, into: set)
                configuration.presets[index].source = .imageSet
            }
            try store.save(configuration, for: set)
            return set
        } catch {
            try? store.library.deleteSet(id: set.id)
            throw error
        }
    }
}
