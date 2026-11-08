import SwiftUI
import AppKit

struct TemplateKeyboardPreview: View {
    let manifest: LocalShareManifest
    let root: URL
    @State private var modifiers: KeyModifiers = []
    private var configuration: PetPackConfiguration { manifest.configuration }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Keyboard mappings are included with this pack.")).font(.caption).foregroundStyle(.secondary)
            Text(L("When Resting") + ": " + names(configuration.idle)).font(.caption)
            Text(L("Unassigned") + ": " + names(configuration.unassigned)).font(.caption)
            HStack(spacing: 5) {
                modifier("⌃", .control); modifier("⌥", .option); modifier("⇧", .shift); modifier("⌘", .command)
                Spacer()
            }
            GeometryReader { geometry in
                VStack(spacing: 3) {
                    ForEach(KeyboardLayoutKey.rows.indices, id: \.self) { rowIndex in
                        let row = KeyboardLayoutKey.rows[rowIndex]
                        let unit = max(1, (geometry.size.width - CGFloat(row.count - 1) * 3) / row.reduce(0) { $0 + $1.width })
                        HStack(spacing: 3) {
                            ForEach(row) { key in
                                let mapping = key.code.flatMap { code in configuration.mappings.first { $0.stroke == KeyStroke(keyCode: code, modifiers: modifiers) } }
                                VStack(spacing: 1) {
                                    Text(key.label == "space" ? "␣" : key.label).font(.system(size: 8)).lineLimit(1)
                                    if let id = mapping?.selection.presetIDs.first, let image = image(id) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(height: 19)
                                    } else { Color.clear.frame(height: 19) }
                                }.frame(width: unit * key.width, height: 34)
                                    .background(mapping == nil ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                                    .help(mapping.map { names($0.selection) } ?? L("Unassigned"))
                            }
                        }
                    }
                }
            }.frame(height: 219)
            if configuration.mappings.isEmpty {
                Text(L("No individual key assignments. Uses the normal typing selection."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(configuration.mappings) { mapping in
                    HStack(alignment: .top) {
                        Text(mapping.stroke.displayName).font(.system(.caption, design: .monospaced)).frame(minWidth: 55, alignment: .leading)
                        Text(names(mapping.selection)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private func modifier(_ name: String, _ value: KeyModifiers) -> some View {
        Toggle(name, isOn: Binding(get: { modifiers.contains(value) }, set: { selected in
            if selected { modifiers.insert(value) } else { modifiers.remove(value) }
        })).toggleStyle(.button).controlSize(.small)
    }
    private func names(_ selection: PresetSelection) -> String {
        selection.presetIDs.compactMap { id in configuration.presets.first { $0.id == id }?.name }.joined(separator: ", ") + " · " + selection.mode.title
    }
    private func image(_ id: String) -> NSImage? {
        guard let path = manifest.images[id], path.hasPrefix("images/"),
              path.split(separator: "/").count == 2, StoredFileName.isSafe(String(path.dropFirst(7))) else { return nil }
        return NSImage(contentsOf: root.appendingPathComponent(path))
    }
}
