import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalSharePanel: View {
    @ObservedObject var editor: PackEditorModel
    @StateObject private var templates = ShareTemplateStore()
    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0
    @State private var managementCode = ""
    @State private var password = ""
    @State private var issuedPassword = ""
    @State private var issuedCode = ""
    @State private var message = ""
    @State private var importCode = ""
    @State private var preview: LocalSharePreview?
    @State private var managementPreview: LocalSharePreview?
    @State private var status = ""
    @State private var isError = false
    @State private var busy = false
    @State private var confirmDeletion = false
    @State private var pendingArchive: Data?
    @State private var requestID = UUID().uuidString
    @State private var requestSecret = UUID().uuidString + UUID().uuidString

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("Pack exchange")).font(.title2.weight(.semibold))
                Spacer()
                if AppEnvironment.isDevelopment {
                    Text(L("Development")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker(L("Share actions"), selection: $selection) {
                Text(L("Share pack")).tag(0)
                Text(L("Import by code")).tag(1)
                Text(L("Received templates")).tag(2)
                Text(L("Manage share")).tag(3)
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selection {
                    case 0: createPane
                    case 1: importPane
                    case 2: templatePane
                    default: managePane
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if !status.isEmpty {
                Text(status).font(.callout).foregroundStyle(isError ? Color.red : Color.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("Close")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
        }
        .padding(22).frame(width: 620, height: 620)
        .interactiveDismissDisabled(busy)
        .onAppear { managementCode = LocalShareAPI.code(for: editor.selectedSet) ?? "" }
        .alert(L("Delete shared pack?"), isPresented: $confirmDeletion) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete share"), role: .destructive) {
                run {
                    try await LocalShareAPI.stop(code: managementCode, password: password)
                    managementPreview = nil; password = ""
                    status = L("Share deleted. Received templates and local copies are preserved.")
                }
            }
        } message: {
            Text(L("New downloads and updates will stop. Existing local copies will remain available."))
        }
    }

    private var createPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Create a distribution for “%1$@”", editor.draft.name)).font(.headline)
            Text(L("Sharing publishes a snapshot. Later local edits are published only when you choose to update."))
                .font(.callout).foregroundStyle(.secondary)
            messageField
            Button(L(pendingArchive == nil ? "Create share copy" : "Retry share creation")) {
                run {
                    if pendingArchive == nil {
                        pendingArchive = try LocalShareAPI.package(configuration: editor.draft, set: editor.selectedSet,
                                                                  store: editor.store, message: message)
                    }
                    guard let archive = pendingArchive else { return }
                    let result = try await LocalShareAPI.create(archive: archive, set: editor.selectedSet,
                                                               requestID: requestID, secret: requestSecret)
                    guard let generated = result.managementPassword else { throw LocalShareError.invalidResponse }
                    LocalShareAPI.remember(result.code, for: editor.selectedSet)
                    issuedCode = result.code; issuedPassword = generated
                    managementCode = result.code; password = generated
                    pendingArchive = nil; requestID = UUID().uuidString
                    requestSecret = UUID().uuidString + UUID().uuidString
                    status = L("Shared snapshot published as version 1.")
                }
            }.buttonStyle(.borderedProminent).disabled(busy || !editor.draft.isUsable || !issuedCode.isEmpty)
            if !issuedCode.isEmpty {
                GroupBox(L("Save your management password")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(issuedCode).font(.system(.title, design: .monospaced)).textSelection(.enabled)
                        Button(L("Copy code")) { copy(issuedCode) }
                        Text(issuedPassword).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Button(L("Copy management password")) { copy(issuedPassword) }
                        Text(L("Keep the password separately. Anyone with it can edit or delete this share. Lost passwords cannot be recovered."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
            }
            Divider()
            fileButtons
        }.disabled(busy)
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("A word from the creator (optional)")).font(.callout.weight(.medium))
            TextEditor(text: $message).font(.body).frame(height: 72)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                .onChange(of: message) { value in if value.count > 500 { message = String(value.prefix(500)) } }
            Text("\(message.count)/500").font(.caption2).foregroundStyle(.secondary)
        }.disabled(busy || pendingArchive != nil)
    }

    private var managePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Publish the selected local pack to an existing share.")).font(.callout)
            codeField(L("Current share code"), value: $managementCode)
                .onChange(of: managementCode) { _ in managementPreview = nil }
            Button(L("Check current version")) {
                run {
                    managementPreview = try await LocalShareAPI.preview(code: managementCode)
                    message = managementPreview?.manifest.creatorMessage ?? ""
                    status = ""
                }
            }.disabled(managementCode.count != 6)
            if let managementPreview {
                previewCard(managementPreview)
                Text(L("Publish from “%1$@”", editor.draft.name)).font(.callout.weight(.medium))
                messageField
            }
            SecureField(L("Management password"), text: $password).textFieldStyle(.roundedBorder)
            HStack {
                Button(L("Publish new version")) {
                    guard let current = managementPreview else { return }
                    run {
                        let version = try await LocalShareAPI.update(code: managementCode, configuration: editor.draft,
                            set: editor.selectedSet, store: editor.store, password: password, message: message,
                            baseVersion: current.latestVersion)
                        managementPreview = try await LocalShareAPI.preview(code: managementCode)
                        status = L("Published version %1$@", String(version))
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(managementPreview == nil || password.isEmpty || !editor.draft.isUsable)
                Button(L("Delete share"), role: .destructive) { confirmDeletion = true }
                    .disabled(managementCode.count != 6 || password.isEmpty)
            }
            Text(L("Anyone with the code can receive this pack. The management password is separate."))
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(busy)
    }

    private var importPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Enter a six-character code to receive a read-only template.")).font(.callout)
            codeField("AB12CD", value: $importCode).onChange(of: importCode) { _ in preview = nil }
            Button(L("Preview share")) {
                run { preview = try await LocalShareAPI.preview(code: importCode) }
            }.disabled(importCode.count != 6)
            if let preview {
                previewCard(preview)
                Button(L("Receive template")) {
                    run {
                        try await templates.receive(preview)
                        selection = 2; status = L("Template received. Make a local copy to use it.")
                    }
                }.buttonStyle(.borderedProminent)
            }
        }.disabled(busy)
    }

    private var templatePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Updates refresh templates. Your edited local copies are always preserved."))
                .font(.callout).foregroundStyle(.secondary)
            if let error = templates.loadError { Text(error).foregroundStyle(.red) }
            if templates.templates.isEmpty { Text(L("No received templates yet.")).foregroundStyle(.secondary) }
            if !templates.templates.isEmpty {
                Button(L("Check all updates")) {
                    run {
                        var failures = 0
                        for template in templates.templates {
                            do { try await templates.check(template) } catch { failures += 1 }
                        }
                        status = failures == 0 ? L("Update checks completed.") : L("Some update checks failed. See each template for details.")
                        isError = failures > 0
                    }
                }
            }
            ForEach(templates.templates) { template in
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        previewCard(template.preview)
                        if let check = template.checkStatus { Text(L(check)).font(.caption).foregroundStyle(.secondary) }
                        if let latest = template.latestVersion {
                            Text(latest > template.preview.latestVersion
                                 ? L("Update available: v%1$@", String(latest)) : L("Latest version"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button(L("Make local copy")) {
                                run {
                                    let set = try templates.copy(template, into: editor.store)
                                    editor.refresh(); editor.selectSet(set)
                                    status = L("Imported “%1$@” as an independent copy.", set.name)
                                }
                            }.buttonStyle(.borderedProminent)
                            Button(L("Check updates")) { run { try await templates.check(template) } }
                            Button(L("Update template")) {
                                run {
                                    try await templates.update(template)
                                    status = L("Template updated. Existing local copies are unchanged.")
                                }
                            }.disabled((template.latestVersion ?? 0) <= template.preview.latestVersion)
                            Button(role: .destructive) { run { try templates.remove(template) } } label: {
                                Image(systemName: "trash")
                            }.help(L("Remove received template"))
                        }
                    }.padding(4)
                }
            }
        }.disabled(busy)
    }

    private func previewCard(_ preview: LocalSharePreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(preview.manifest.name).font(.headline)
            Text("\(preview.code) · v\(preview.latestVersion) · \(ByteCountFormatter.string(fromByteCount: Int64(preview.packageSize), countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary)
            if let message = preview.manifest.creatorMessage, !message.isEmpty {
                Text(verbatim: message).font(.callout).textSelection(.enabled)
            }
            Text(L("Version %1$@ · %2$@ images · includes key settings", String(preview.latestVersion), String(preview.manifest.configuration.presets.count)))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func codeField(_ title: String, value: Binding<String>) -> some View {
        TextField(title, text: value).textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .onChange(of: value.wrappedValue) { text in value.wrappedValue = LocalShareAPI.normalizedCode(text) }
    }

    private var fileButtons: some View {
        HStack {
            Button(L("Export set file…")) {
                run {
                    let data = try LocalShareAPI.package(configuration: editor.draft, set: editor.selectedSet, store: editor.store, message: message)
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "pack.typingpet.zip"; panel.allowedContentTypes = [.zip]
                    if panel.runModal() == .OK, let url = panel.url {
                        try data.write(to: url, options: .atomic); status = L("Exported set file.")
                    }
                }
            }
            Button(L("Import set file…")) {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]; panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                run {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? Int.max) <= 50 * 1024 * 1024 else { throw LocalShareError.invalidPackage }
                    let set = try LocalShareAPI.unpack(Data(contentsOf: url), into: editor.store)
                    editor.refresh(); editor.selectSet(set)
                    status = L("Imported “%1$@” as an independent copy.", set.name)
                }
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; status = ""; isError = false
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() }
            catch { status = error.localizedDescription; isError = true }
        }
    }
}
