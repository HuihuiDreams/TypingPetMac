import SwiftUI
import AppKit

struct TemplateImportPanel: View {
    @ObservedObject var templates: ShareTemplateStore
    var onReceived: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = TemplateVersionPreview()
    @State private var code = ""
    @State private var status = ""
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Import template")).font(.title2.weight(.semibold)).frame(maxWidth: .infinity)
            Text(L("Enter a six-character code to receive a read-only template.")).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            HStack { Spacer(minLength: 0); ShareCodeInput(code: $code).frame(width: 388, height: 70); Spacer(minLength: 0) }
                .disabled(importing || browser.busy)
                .onChange(of: code) { _ in browser.close(); status = "" }
            Button(L("Preview share")) { browser.open(code: code) }
                .disabled(importing || browser.busy || code.count != 6)
            if !browser.versions.isEmpty { TemplateVersionPicker(browser: browser).disabled(importing) }
            if let preview = browser.preview, let root = browser.root {
                ScrollView { TemplateVersionContent(preview: preview, root: root).padding(2) }.frame(height: 340)
                Button(L("Import version %1$@", String(preview.latestVersion))) {
                    guard let data = browser.data else { return }
                    importing = true; status = ""
                    Task { @MainActor in
                        defer { importing = false }
                        do {
                            try templates.install(data, preview: preview, latestKnownVersion: browser.latestVersion)
                            onReceived(preview.code); dismiss()
                        } catch { status = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(importing || browser.busy)
            }
            if browser.busy { ProgressView().controlSize(.small) }
            if !browser.error.isEmpty { Text(browser.error).font(.callout).foregroundStyle(.red) }
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(importing)
            }
        }.padding(22).frame(width: 480).interactiveDismissDisabled(importing)
            .onDisappear { browser.close() }
    }
}

struct TemplateVersionPicker: View {
    @ObservedObject var browser: TemplateVersionPreview
    var body: some View {
        Picker(L("Version"), selection: Binding(get: { browser.selectedVersion }, set: { browser.select($0) })) {
            ForEach(browser.versions) { version in
                Text("v\(version.version)" + (version.version == browser.latestVersion ? " · " + L("Latest version") : "")
                     + " · " + Date(timeIntervalSince1970: TimeInterval(version.publishedAt)).formatted(date: .abbreviated, time: .shortened))
                    .tag(version.version)
            }
        }.pickerStyle(.menu)
    }
}

struct TemplateVersionContent: View {
    let preview: LocalSharePreview
    let root: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TemplateSummary(preview: preview)
            TemplateArtworkPreview(manifest: preview.manifest, root: root)
            DisclosureGroup(L("Keyboard Mapping")) {
                TemplateKeyboardPreview(manifest: preview.manifest, root: root).padding(.top, 10)
            }
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
                            Text(preset.name).font(.caption).lineLimit(2).frame(height: 30)
                            Text(manifest.configuration.idle.presetIDs.contains(preset.id) ? L("When Resting") : " ")
                                .font(.caption2).foregroundStyle(.secondary).frame(height: 14)
                        }.padding(8).frame(maxWidth: .infinity).frame(height: 152)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(2)
            }.frame(height: min(230, CGFloat((manifest.configuration.presets.count + 2) / 3) * 162))
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
    var onReceived: ((String) -> Void)? = nil
    @StateObject private var browser = TemplateVersionPreview()
    @State private var status = ""
    @State private var busy = false
    private var template: ShareTemplate? { templates.templates.first { $0.id == code } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L("Template details")).font(.title2.weight(.semibold))
                    Spacer()
                    Button(L("Manage")) { templates.managementCode = code }.disabled(busy)
                }
                if !browser.versions.isEmpty { TemplateVersionPicker(browser: browser).disabled(busy) }
                if let preview = browser.preview, let root = browser.root {
                    TemplateVersionContent(preview: preview, root: root)
                    HStack {
                        Button(L("Copy version %1$@", String(preview.latestVersion))) {
                            run {
                                let set: PetImageSet
                                if let data = browser.data {
                                    set = try LocalShareAPI.unpack(data, into: editor.store, revision: preview.latestVersion)
                                } else {
                                    set = try await templates.copyVersion(code: code, revision: preview.latestVersion, into: editor.store)
                                }
                                editor.refresh(); editor.selectSet(set)
                            }
                        }.buttonStyle(.borderedProminent)
                        if template == nil, let data = browser.data {
                            Button(L("Import version %1$@", String(preview.latestVersion))) {
                                run {
                                    try templates.install(data, preview: preview, latestKnownVersion: browser.latestVersion)
                                    onReceived?(code)
                                }
                            }
                        }
                        Button(L("Check updates")) { reload() }
                        if let template, browser.latestVersion > template.preview.latestVersion {
                            Button(L("Update template")) {
                                run { try await templates.update(template); reload() }
                            }
                        }
                    }.disabled(busy || browser.busy)
                    if let template {
                        Text(L("Saved version: v%1$@", String(template.preview.latestVersion)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L("Updates refresh templates. Your edited local copies are always preserved."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if busy || browser.busy { ProgressView().controlSize(.small) }
                if !browser.error.isEmpty { Text(browser.error).font(.callout).foregroundStyle(.secondary) }
                if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.red) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.onAppear { reload() }
            .onDisappear { browser.close() }
            .onChange(of: templates.managementCode) { value in if value == nil { reload() } }
    }
    private func reload() {
        browser.open(code: code, local: template, directory: templates.directory)
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
                Toggle(L("Community public pack"), isOn: Binding(get: { current?.isPublic ?? false }, set: { enabled in
                    run {
                        _ = try await LocalShareAPI.setPublic(code: code, password: password, enabled: enabled)
                        current = try await LocalShareAPI.preview(code: code)
                        status = L(enabled ? "This pack is now visible in the community gallery." : "This pack is no longer listed in the community gallery.")
                    }
                })).disabled(busy)
                Text(L("Public packs can be found and imported by anyone in the community gallery."))
                    .font(.caption).foregroundStyle(.secondary)
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
