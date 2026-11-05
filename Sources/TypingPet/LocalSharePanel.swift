import AppKit
import SwiftUI

/// A pack's Share button only publishes a snapshot. Receiving and management live in Templates.
struct LocalSharePanel: View {
    @ObservedObject var editor: PackEditorModel
    @ObservedObject var templates: ShareTemplateStore
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var password = ""
    @State private var issuedCode = ""
    @State private var issuedPassword = ""
    @State private var busy = false
    @State private var status = ""
    @State private var isError = false
    @State private var pendingArchive: Data?
    @State private var requestID = UUID().uuidString
    @State private var secret = UUID().uuidString + UUID().uuidString

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Share")).font(.title2.weight(.semibold))
            Text(editor.draft.name).font(.headline)
            Text(L("Sharing publishes a snapshot. Later local edits are published only when you choose to update."))
                .font(.callout).foregroundStyle(.secondary)
            if issuedCode.isEmpty {
                CreatorMessageField(message: $message).disabled(busy || pendingArchive != nil)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Management password")).font(.callout)
                    TextField(L("Management password"), text: $password).textFieldStyle(.roundedBorder)
                }.disabled(busy || pendingArchive != nil)
                Button(L(pendingArchive == nil ? "Create share copy" : "Retry share creation")) { publish() }
                    .buttonStyle(.borderedProminent).disabled(busy || !editor.draft.isUsable || password.isEmpty)
            } else {
                GroupBox(L("Save your management password")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(issuedCode).font(.system(.title, design: .monospaced)).textSelection(.enabled)
                        Button(L("Copy code")) { copy(issuedCode) }
                        Text(issuedPassword).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Button(L("Copy management password")) { copy(issuedPassword) }
                        Text(L("Keep the password separately. Anyone with it can edit or delete this share. Lost passwords cannot be recovered."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(L(templates.templates.contains(where: { $0.id == issuedCode })
                       ? "Your shared pack is available in Templates."
                       : "Sharing succeeded. Import this code in Templates to add it to your library."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !status.isEmpty { Text(status).foregroundStyle(isError ? Color.red : Color.secondary).font(.callout) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("Close")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
        }.padding(22).frame(width: 480).interactiveDismissDisabled(busy)
    }

    private func publish() {
        busy = true; isError = false; status = ""
        Task { @MainActor in
            defer { busy = false }
            do {
                if pendingArchive == nil {
                    pendingArchive = try LocalShareAPI.package(configuration: editor.draft, set: editor.selectedSet, store: editor.store, message: message)
                }
                guard let archive = pendingArchive else { return }
                let created = try await LocalShareAPI.create(archive: archive, set: editor.selectedSet, requestID: requestID, secret: secret, password: password)
                issuedCode = created.code; issuedPassword = password
                LocalShareAPI.remember(created.code, for: editor.selectedSet)
                let preview = try await LocalShareAPI.preview(code: created.code)
                try templates.install(archive, preview: preview)
                pendingArchive = nil
                status = L("Shared snapshot published as version 1.")
            } catch { status = error.localizedDescription; isError = true }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
}

struct CreatorMessageField: View {
    @Binding var message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("A word from the creator (optional)")).font(.callout.weight(.medium))
            TextEditor(text: $message).font(.body).frame(height: 72)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                .onChange(of: message) { value in if value.count > 500 { message = String(value.prefix(500)) } }
            Text("\(message.count)/500").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
