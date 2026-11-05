import SwiftUI
import AppKit

struct TemplateImportPanel: View {
    @ObservedObject var templates: ShareTemplateStore
    var onReceived: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var preview: LocalSharePreview?
    @State private var previewData: Data?
    @State private var artworkRoot: URL?
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Import template")).font(.title2.weight(.semibold)).frame(maxWidth: .infinity)
            Text(L("Enter a six-character code to receive a read-only template.")).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            HStack { Spacer(minLength: 0); ShareCodeInput(code: $code).frame(width: 388, height: 70); Spacer(minLength: 0) }.disabled(busy)
                .onChange(of: code) { _ in if preview?.code != code { clearPreview() } }
            Button(L("Preview share")) {
                run {
                    clearPreview()
                    let value = try await LocalShareAPI.preview(code: code)
                    let data = try await LocalShareAPI.download(value)
                    let (root, _) = try LocalShareAPI.extract(data)
                    artworkRoot = root; previewData = data; preview = value
                }
            }.disabled(busy || code.count != 6)
            if let preview {
                TemplateSummary(preview: preview)
                if let artworkRoot { TemplateArtworkPreview(manifest: preview.manifest, root: artworkRoot) }
                Button(L("Receive template")) {
                    run {
                        guard let data = previewData else { throw LocalShareError.invalidPackage }
                        try templates.install(data, preview: preview)
                        onReceived(preview.code)
                        dismiss()
                    }
                }.buttonStyle(.borderedProminent).disabled(busy)
            }
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.red) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
        }.padding(22).frame(width: 480).interactiveDismissDisabled(busy)
            .onDisappear { clearPreview() }
    }
    private func clearPreview() {
        preview = nil; previewData = nil
        if let root = artworkRoot { try? FileManager.default.removeItem(at: root) }
        artworkRoot = nil
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; status = ""
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { status = error.localizedDescription }
        }
    }
}

struct TemplateArtworkPreview: View {
    let manifest: LocalShareManifest
    let root: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Image set preview")).font(.headline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
                    ForEach(manifest.configuration.presets) { preset in
                        VStack(spacing: 6) {
                            if let image = image(for: preset) {
                                Image(nsImage: image).resizable().scaledToFit().frame(height: 76)
                            }
                            Text(preset.name).font(.caption).lineLimit(2)
                            if manifest.configuration.idle.presetIDs.contains(preset.id) {
                                Text(L("When Resting")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(8).frame(maxWidth: .infinity)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(2)
            }.frame(height: min(230, CGFloat((manifest.configuration.presets.count + 2) / 3) * 140))
        }
    }
    private func image(for preset: PetImagePreset) -> NSImage? {
        guard let path = manifest.images[preset.id], path.hasPrefix("images/"),
              path.split(separator: "/").count == 2, StoredFileName.isSafe(String(path.dropFirst(7))) else { return nil }
        return NSImage(contentsOf: root.appendingPathComponent(path))
    }
}

struct TemplateSummary: View {
    let preview: LocalSharePreview
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.manifest.name).font(.headline)
            Text("\(preview.code) · v\(preview.latestVersion) · \(ByteCountFormatter.string(fromByteCount: Int64(preview.packageSize), countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary)
            if let message = preview.manifest.creatorMessage, !message.isEmpty {
                Text(verbatim: message).font(.callout).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TemplateLibraryView: View {
    @ObservedObject var templates: ShareTemplateStore
    var onSelect: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Templates")).font(.title2.weight(.semibold))
                Text(L("Updates refresh templates. Your edited local copies are always preserved."))
                    .font(.callout).foregroundStyle(.secondary)
                if let error = templates.loadError { Text(error).foregroundStyle(.red) }
                if templates.templates.isEmpty { Text(L("No received templates yet.")).foregroundStyle(.secondary) }
                ForEach(templates.templates) { template in
                    GroupBox {
                        HStack(alignment: .top) {
                            Button { onSelect(template.id) } label: {
                                TemplateSummary(preview: template.preview).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button(L("Manage")) { templates.managementCode = template.id }
                        }.padding(8)
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TemplateDetailView: View {
    let code: String
    @ObservedObject var editor: PackEditorModel
    @ObservedObject var templates: ShareTemplateStore
    @State private var versions: [ShareVersionSummary] = []
    @State private var status = ""
    @State private var busy = false
    private var template: ShareTemplate? { templates.templates.first { $0.id == code } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let template {
                    HStack(alignment: .top) {
                        TemplateSummary(preview: template.preview)
                        Button(L("Manage")) { templates.managementCode = code }.disabled(busy)
                    }
                    TemplateArtworkPreview(manifest: template.preview.manifest, root: templates.directory.appendingPathComponent(template.folder))
                    HStack {
                        Button(L("Make local copy")) { copy(template.preview.latestVersion) }.buttonStyle(.borderedProminent)
                        Button(L("Check updates")) { run { try await loadHistory() } }
                        if (template.latestVersion ?? 0) > template.preview.latestVersion {
                            Button(L("Update template")) {
                                run { try await templates.update(template); try await loadHistory() }
                            }
                        }
                    }.disabled(busy)
                    Text(L("Updates refresh templates. Your edited local copies are always preserved."))
                        .font(.callout).foregroundStyle(.secondary)
                    Divider()
                    Text(L("Version history")).font(.headline)
                    ForEach(versions) { version in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("v\(version.version)").font(.headline)
                                    if version.version == template.preview.latestVersion {
                                        Text(L("Saved template")).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(Date(timeIntervalSince1970: TimeInterval(version.publishedAt)), style: .date)
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(Date(timeIntervalSince1970: TimeInterval(version.publishedAt)), style: .time)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(version.name).font(.callout)
                                if !version.creatorMessage.isEmpty { Text(verbatim: version.creatorMessage).font(.callout).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button(L("Copy version %1$@", String(version.version))) { copy(version.version) }.disabled(busy)
                        }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                } else { Text(L("No received templates yet.")) }
                if busy { ProgressView().controlSize(.small) }
                if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.onAppear { run { try await loadHistory() } }
    }

    private func loadHistory() async throws {
        do {
            let history = try await LocalShareAPI.versions(code: code)
            versions = history
            if let template { try await templates.check(template) }
        } catch {
            if versions.isEmpty, let template { versions = [ShareVersionSummary(preview: template.preview)] }
            throw error
        }
    }
    private func copy(_ revision: Int) {
        run {
            let set = try await templates.copyVersion(code: code, revision: revision, into: editor.store)
            editor.refresh(); editor.selectSet(set)
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; status = ""
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { status = error.localizedDescription }
        }
    }
}

struct TemplateManagementPanel: View {
    let code: String
    @ObservedObject var editor: PackEditorModel
    @ObservedObject var templates: ShareTemplateStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var authorized = false
    @State private var current: LocalSharePreview?
    @State private var sourceID: UUID?
    @State private var message = ""
    @State private var status = ""
    @State private var busy = false
    @State private var deletion = false
    @State private var deleted = false
    private var source: PetImageSet? { editor.sets.first { $0.id == sourceID } }
    private var sources: [PetImageSet] { editor.sets.filter { editor.configuration(for: $0).isUsable } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(L("Manage template")).font(.title2.weight(.semibold)); Spacer(); Text(code).font(.system(.body, design: .monospaced)) }
            if !authorized {
                Text(L("Enter the management password to manage and publish this template.")).font(.callout).foregroundStyle(.secondary)
                TextField(L("Management password"), text: $password).textFieldStyle(.roundedBorder)
                    .onSubmit { unlock() }.disabled(busy)
                Button(L("Unlock management")) { unlock() }.buttonStyle(.borderedProminent).disabled(busy || password.isEmpty)
            } else if !deleted {
                if let current { TemplateSummary(preview: current) }
                Picker(L("Local pack to publish"), selection: $sourceID) {
                    Text(L("Choose a local pack")).tag(nil as UUID?)
                    ForEach(sources) { set in Text(editor.configuration(for: set).name).tag(Optional(set.id)) }
                }.disabled(busy)
                CreatorMessageField(message: $message).disabled(busy)
                HStack {
                    Button(L("Publish new version")) {
                        guard let source, let current else { return }
                        run {
                            let revision = try await LocalShareAPI.update(code: code, configuration: editor.configuration(for: source),
                                set: source, store: editor.store, password: password, message: message, baseVersion: current.latestVersion)
                            self.current = try await LocalShareAPI.preview(code: code)
                            if let template = templates.templates.first(where: { $0.id == code }) { try await templates.check(template) }
                            status = L("Published version %1$@", String(revision))
                        }
                    }.buttonStyle(.borderedProminent).disabled(busy || source == nil || current == nil)
                    Button(L("Check current version")) {
                        run { current = try await LocalShareAPI.preview(code: code) }
                    }.disabled(busy)
                    Button(L("Delete share"), role: .destructive) { deletion = true }.disabled(busy)
                }
                Text(L("Publishing creates a new version. Local copies are preserved."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("Close")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
        }.padding(22).frame(width: 560).interactiveDismissDisabled(busy)
            .alert(L("Delete shared pack?"), isPresented: $deletion) {
                Button(L("Cancel"), role: .cancel) {}
                Button(L("Delete share"), role: .destructive) {
                    run {
                        try await LocalShareAPI.stop(code: code, password: password)
                        deleted = true; authorized = false; password = ""
                        status = L("Share deleted. Received templates and local copies are preserved.")
                        dismiss()
                    }
                }
            } message: { Text(L("New downloads and updates will stop. Existing local copies will remain available.")) }
    }

    private func unlock() {
        guard !busy, !password.isEmpty else { return }
        run {
            try await LocalShareAPI.authorize(code: code, password: password)
            let preview = try await LocalShareAPI.preview(code: code)
            current = preview; message = preview.manifest.creatorMessage ?? ""
            // Nothing that changes the share is shown before the server accepts the password.
            authorized = true
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; status = ""
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { status = error.localizedDescription }
        }
    }
}
