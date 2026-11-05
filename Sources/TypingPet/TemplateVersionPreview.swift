import Foundation
import Combine

/// Keeps a viewed version separate from the template saved on this Mac.
@MainActor
final class TemplateVersionPreview: ObservableObject {
    @Published private(set) var versions: [ShareVersionSummary] = []
    @Published private(set) var selectedVersion = 0
    @Published private(set) var preview: LocalSharePreview?
    @Published private(set) var root: URL?
    @Published private(set) var data: Data?
    @Published private(set) var busy = false
    @Published private(set) var error = ""
    private var code = ""
    private var local: ShareTemplate?
    private var directory: URL?
    private var ownsRoot = false
    private var generation = UUID()
    private var task: Task<Void, Never>?

    var latestVersion: Int { versions.map(\.version).max() ?? selectedVersion }

    func open(code: String, local: ShareTemplate? = nil, directory: URL? = nil) {
        self.code = code; self.local = local; self.directory = directory
        start(reload: true, revision: nil)
    }
    func select(_ revision: Int) {
        guard revision != selectedVersion || preview == nil else { return }
        start(reload: false, revision: revision)
    }
    func close() {
        generation = UUID(); task?.cancel(); task = nil
        clearPrepared(); versions = []; selectedVersion = 0; error = ""; busy = false
    }
    private func clearPrepared() {
        if ownsRoot, let root { try? FileManager.default.removeItem(at: root) }
        preview = nil; root = nil; data = nil; ownsRoot = false
    }
    private func start(reload: Bool, revision: Int?) {
        task?.cancel(); let ticket = UUID(); generation = ticket
        clearPrepared(); busy = true; error = ""
        if let revision { selectedVersion = revision }
        if reload { versions = []; selectedVersion = 0 }
        let requestedCode = code
        task = Task { @MainActor in
            defer { if self.generation == ticket { self.busy = false } }
            do {
                if reload {
                    let history = try await LocalShareAPI.versions(code: requestedCode)
                    try Task.checkCancellation()
                    guard self.generation == ticket, !history.isEmpty else { return }
                    self.versions = history.sorted { $0.version > $1.version }
                    self.selectedVersion = self.versions[0].version
                }
                let selected = self.selectedVersion
                if let local = self.local, local.preview.latestVersion == selected, let directory = self.directory {
                    self.preview = local.preview
                    self.root = directory.appendingPathComponent(local.folder)
                } else {
                    let metadata = try await LocalShareAPI.version(code: requestedCode, revision: selected)
                    let bytes = try await LocalShareAPI.download(metadata)
                    try Task.checkCancellation()
                    guard self.generation == ticket else { return }
                    let (root, _) = try LocalShareAPI.extract(bytes)
                    self.preview = metadata; self.data = bytes; self.root = root; self.ownsRoot = true
                }
            } catch {
                guard self.generation == ticket else { return }
                self.error = error.localizedDescription
                if reload, let local = self.local, let directory = self.directory {
                    if !self.versions.contains(where: { $0.version == local.preview.latestVersion }) {
                        self.versions.append(ShareVersionSummary(preview: local.preview))
                        self.versions.sort { $0.version > $1.version }
                    }
                    self.selectedVersion = local.preview.latestVersion
                    self.preview = local.preview; self.root = directory.appendingPathComponent(local.folder)
                }
            }
        }
    }
}
