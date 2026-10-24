import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum WorkspacePage: String, CaseIterable {
    case packs, presets, mapping, appearance, todos, general
    var title: String {
        switch self {
        case .packs: L("My Packs")
        case .presets: L("Image Presets")
        case .mapping: L("Keyboard Mapping")
        case .appearance: L("Appearance and Behavior")
        case .todos: L("Todos and Focus")
        case .general: L("General")
        }
    }
    var symbol: String {
        switch self {
        case .packs: "shippingbox"
        case .presets: "photo.on.rectangle.angled"
        case .mapping: "keyboard"
        case .appearance: "slider.horizontal.3"
        case .todos: "checklist"
        case .general: "gearshape"
        }
    }
}

struct SettingsWorkspaceView: View {
    @ObservedObject var model: TypingPetSettingsModel
    @ObservedObject var todoStore: TodoStore
    let updater: UpdateController
    @StateObject private var editor: PackEditorModel
    @AppStorage("SettingsWorkspacePage", store: AppEnvironment.defaults) private var pageRaw = WorkspacePage.mapping.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: TypingPetSettingsModel, todoStore: TodoStore, updater: UpdateController) {
        self.model = model
        self.todoStore = todoStore
        self.updater = updater
        _editor = StateObject(wrappedValue: PackEditorModel(store: model.packStore))
    }
    private var page: WorkspacePage { WorkspacePage(rawValue: pageRaw) ?? .mapping }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            sidebar
                .frame(width: 200)
            VStack(alignment: .leading, spacing: 14) {
                header
                if [.packs, .presets, .mapping].contains(page) { packBar }
                Group {
                    switch page {
                    case .mapping: mapping
                    case .presets: presetGallery
                    case .packs: packs
                    case .appearance: GeneralSettingsView(model: model, updater: updater, scope: .pet)
                    case .todos: TodoSettingsView(store: todoStore)
                    case .general: GeneralSettingsView(model: model, updater: updater, scope: .system)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if !editor.statusMessage.isEmpty {
                    Text(editor.statusMessage).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .tint(.teal)
        .onChange(of: pageRaw) { _ in editor.stopPreview() }
        .onReceive(model.$imageSets) { _ in editor.refreshIfClean() }
        .onDisappear { editor.stopPreview() }
        .alert(L("Error"), isPresented: Binding(get: { editor.errorMessage != nil }, set: { if !$0 { editor.errorMessage = nil } })) {
            Button(L("OK")) { editor.errorMessage = nil }
        } message: { Text(editor.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                PresetArtwork(image: editor.image(id: editor.draft.idle.presetIDs.first))
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppEnvironment.displayName).font(.system(size: 15, weight: .medium))
                    Text(L("Your Little Companion")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            navGroup(L("Library"), pages: [.packs, .presets, .mapping])
            Divider().padding(.horizontal, 6)
            navGroup(L("Settings"), pages: [.appearance, .todos, .general])
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 46)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity)
        .modifier(WorkspaceSurface(radius: 24))
    }

    private func navGroup(_ title: String, pages: [WorkspacePage]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 2)
            ForEach(pages, id: \.self) { item in
                Button { pageRaw = item.rawValue } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 13, weight: page == item ? .medium : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .foregroundStyle(page == item ? Color.teal : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 12).fill(page == item ? Color.teal.opacity(0.13) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == item ? .isSelected : [])
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(page.title).font(.system(size: 19, weight: .medium))
            Spacer(minLength: 8)
            if page == .mapping {
                Button {
                    if editor.isPreviewing { editor.stopPreview() } else { editor.startPreview() }
                } label: {
                    Label(editor.isPreviewing ? L("Back to Editing") : L("Preview Mode"), systemImage: editor.isPreviewing ? "pencil" : "play")
                }
                .accessibilityIdentifier("preview-mode")
            }
            if [.packs, .presets, .mapping].contains(page), !editor.isPreviewing {
                Menu {
                    Button(L("Pack from Images…")) { importPack(folder: false) }
                    Button(L("Pack from Folder…")) { importPack(folder: true) }
                } label: { Label(L("Import"), systemImage: "folder") }
                .fixedSize()
                Button(L("Save Pack")) { editor.saveAndApply { model.packDidChange() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!editor.canSave)
            }
        }
        .controlSize(.regular)
        .padding(14)
        .modifier(WorkspaceSurface(radius: 20))
    }

    private var packBar: some View {
        HStack(spacing: 10) {
            Text(L("Editing Pack")).foregroundStyle(.secondary)
            TextField(L("Pack Name"), text: $editor.draft.name)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                .disabled(editor.isPreviewing)
            Text(editor.isDirty ? L("Unsaved Changes") : editor.isActive ? L("In Use") : L("Saved Pack"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
    }

    private var mapping: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if editor.isPreviewing { preview }
                HStack(spacing: 10) {
                    behaviorButton(.unassigned)
                    behaviorButton(.idle)
                }
                if !editor.isPreviewing, let target = editor.expandedTarget, target == .idle || target == .unassigned {
                    accordion(target).transition(.opacity.combined(with: .move(edge: .top)))
                }
                HStack(spacing: 5) {
                    Text(L("Modifier Combination")).font(.callout).foregroundStyle(.secondary).padding(.trailing, 4)
                    modifierButton(.control, symbol: "⌃")
                    modifierButton(.option, symbol: "⌥")
                    modifierButton(.shift, symbol: "⇧")
                    modifierButton(.command, symbol: "⌘")
                    Spacer()
                }
                keyboard
                HStack {
                    Text(L("Mac · ANSI Layout"))
                    Spacer()
                    Text(L("Thumbnail: Assigned Preset · Dot: Unassigned"))
                }
                .font(.caption).foregroundStyle(.secondary)
                if !editor.isPreviewing, editor.expandedTarget == nil {
                    Text(L("Select a key or an item above to edit its presets."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(3)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: editor.expandedTarget)
        }
    }

    private func behaviorButton(_ target: PackEditorTarget) -> some View {
        let selection = editor.selection(for: target)
        let expanded = !editor.isPreviewing && editor.expandedTarget == target
        return Button {
            if editor.isPreviewing {
                if target == .idle { editor.showPreviewIdle() } else { editor.previewUnassigned() }
            } else { editor.toggle(target) }
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: -9) {
                    ForEach(Array(selection.presetIDs.prefix(3)), id: \.self) { id in
                        PresetArtwork(image: editor.image(id: id)).frame(width: 31, height: 33)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title).font(.system(size: 13, weight: .medium))
                    Text(L("%1$@ presets · %2$@", selection.presetIDs.count, selection.mode.title))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(expanded ? Color.teal.opacity(0.10) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(expanded ? Color.teal.opacity(0.7) : Color.primary.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target.title)
        .accessibilityValue(expanded ? L("Expanded") : L("Collapsed"))
    }

    private func modifierButton(_ modifier: KeyModifiers, symbol: String) -> some View {
        Button { editor.toggleModifier(modifier) } label: {
            Text(symbol).frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(editor.modifiers.contains(modifier) ? Color.teal.opacity(0.18) : Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(editor.modifiers.contains(modifier) ? Color.teal : Color.primary.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(editor.modifiers.contains(modifier) ? .isSelected : [])
    }

    private var keyboard: some View {
        VStack(spacing: 5) {
            ForEach(KeyboardLayoutKey.rows.indices, id: \.self) { index in
                keyboardRow(KeyboardLayoutKey.rows[index], function: index == 0)
                if !editor.isPreviewing, case .key(let stroke) = editor.expandedTarget,
                   KeyboardLayoutKey.rows[index].contains(where: { $0.code == stroke.keyCode }) {
                    accordion(.key(stroke)).padding(.vertical, 4).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.09)))
    }

    private func keyboardRow(_ row: [KeyboardLayoutKey], function: Bool) -> some View {
        GeometryReader { geometry in
            let unit = max(0, geometry.size.width - CGFloat(row.count - 1) * 4) / row.reduce(0) { $0 + $1.width }
            HStack(spacing: 4) {
                ForEach(row) { key in
                    keyboardKey(key, function: function).frame(width: unit * key.width)
                }
            }
        }
        .frame(height: function ? 44 : 54)
    }

    private func keyboardKey(_ key: KeyboardLayoutKey, function: Bool) -> some View {
        let stroke = key.code.map { KeyStroke(keyCode: $0, modifiers: editor.modifiers) }
        let selection = stroke.map { editor.selection(for: .key($0)) }
        let selected = editor.isPreviewing ? stroke == editor.previewStroke && stroke != nil : stroke.map { editor.expandedTarget == .key($0) } ?? false
        return Button {
            guard let stroke else { return }
            if editor.isPreviewing { editor.previewKey(stroke) } else { editor.toggle(.key(stroke)) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(key.label.replacingOccurrences(of: "L", with: key.code == nil ? "" : "L").replacingOccurrences(of: "R", with: key.code == nil ? "" : "R"))
                    .font(.system(size: 10)).foregroundStyle(key.code == nil ? .tertiary : .secondary)
                    .lineLimit(1)
                if !function || selection?.presetIDs.isEmpty == false {
                    Spacer(minLength: 0)
                    if let id = selection?.presetIDs.first {
                        PresetArtwork(image: editor.image(id: id)).frame(maxWidth: .infinity).frame(height: function ? 20 : 29)
                    } else if key.code != nil {
                        Text("·").foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.teal.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(key.code == nil ? 0.4 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.teal : Color.primary.opacity(0.10), lineWidth: selected ? 1.5 : 0.6))
        }
        .buttonStyle(.plain).disabled(key.code == nil)
        .accessibilityLabel(stroke?.displayName ?? key.label)
        .accessibilityValue(selection?.presetIDs.map { editor.name(id: $0) }.joined(separator: ", ") ?? "")
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            guard !editor.isPreviewing, let stroke, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { value, _ in
                guard let value else { return }
                DispatchQueue.main.async { editor.assignPreset(value, to: stroke) }
            }
            return true
        }
    }

    private func accordion(_ target: PackEditorTarget) -> some View {
        let selection = editor.selection(for: target)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(target.title).font(.headline)
                Spacer()
                if case .key = target {
                    Button(L("Unassign")) { editor.unassign(target) }.disabled(selection.presetIDs.isEmpty)
                }
                Button { editor.expandedTarget = nil } label: { Label(L("Collapse"), systemImage: "chevron.up") }
            }
            .controlSize(.small)
            Text(target == .idle ? L("Choose presets shown when you stop typing.") : target == .unassigned ? L("Choose presets shown for keys without a mapping.") : L("Choose presets and a display mode for this key combination."))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker(L("Display Mode"), selection: Binding(get: { selection.mode }, set: { editor.setMode($0, for: target) })) {
                    ForEach(PresetPlaybackMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                }
                .frame(maxWidth: 210).disabled(selection.presetIDs.isEmpty)
                Text(selection.presetIDs.isEmpty ? L("Uses Unassigned settings") : L("%1$@ selected", selection.presetIDs.count))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Text(L("Image Presets · Select Multiple")).font(.callout)
                Spacer()
                Button(L("Manage Presets")) { pageRaw = WorkspacePage.presets.rawValue }.buttonStyle(.link)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78, maximum: 104))], alignment: .leading, spacing: 8) {
                ForEach(editor.draft.presets) { preset in
                    presetTile(preset, selected: selection.presetIDs.contains(preset.id), height: 49) {
                        editor.togglePreset(preset.id, for: target)
                    }
                }
            }
            if selection.mode == .cycle, selection.presetIDs.count > 1 {
                Text(L("Cycle Order")).font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], alignment: .leading, spacing: 6) {
                    ForEach(Array(selection.presetIDs.enumerated()), id: \.element) { index, id in
                        HStack(spacing: 5) {
                            Text("\(index + 1). \(editor.name(id: id))").lineLimit(1).help(editor.name(id: id))
                            Spacer(minLength: 0)
                            Button { editor.movePreset(id, by: -1, for: target) } label: { Image(systemName: "arrow.left") }
                                .disabled(index == 0).accessibilityLabel(L("Move Earlier"))
                            Button { editor.movePreset(id, by: 1, for: target) } label: { Image(systemName: "arrow.right") }
                                .disabled(index == selection.presetIDs.count - 1).accessibilityLabel(L("Move Later"))
                        }
                        .font(.caption).controlSize(.mini)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Preset Editor"))
    }

    private func presetTile(_ preset: PetImagePreset, selected: Bool, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                PresetArtwork(image: editor.image(for: preset)).frame(height: height)
                Text(preset.name).font(.caption).lineLimit(2).frame(maxWidth: .infinity)
            }
            .padding(7).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 11).fill(selected ? Color.teal.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Color.teal : Color.primary.opacity(0.10)))
            .overlay(alignment: .topTrailing) {
                if selected { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.teal).padding(5) }
            }
        }
        .buttonStyle(.plain).help(preset.name)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onDrag { NSItemProvider(object: preset.id as NSString) }
    }

    private var presetGallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("Give presets any name and reuse them across keys and reactions.")).foregroundStyle(.secondary)
                    Spacer()
                    Button { editor.addPresets() } label: { Label(L("Add Images…"), systemImage: "plus") }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180))], alignment: .leading, spacing: 12) {
                    ForEach(editor.draft.presets) { preset in
                        presetTile(preset, selected: preset.id == editor.selectedPresetID, height: 90) { editor.selectedPresetID = preset.id }
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    TextField(L("Preset Name"), text: Binding(
                        get: { editor.name(id: editor.selectedPresetID) },
                        set: { value in
                            if let index = editor.draft.presets.firstIndex(where: { $0.id == editor.selectedPresetID }) { editor.draft.presets[index].name = value }
                        }
                    ))
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 230)
                    Button(L("Replace Image…")) { editor.replacePresetImage() }
                }
            }
            .padding(3)
        }
    }

    private var packs: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220))], alignment: .leading, spacing: 14) {
                ForEach(editor.sets) { set in
                    let config = set.id == editor.selectedSetID ? editor.draft : editor.store.configuration(for: set)
                    Button {
                        editor.selectSet(set)
                        pageRaw = WorkspacePage.mapping.rawValue
                    } label: {
                        VStack(spacing: 8) {
                            PresetArtwork(image: config.idle.presetIDs.first.flatMap { id in config.presets.first { $0.id == id } }.flatMap { editor.image(for: $0, in: set) })
                                .frame(height: 110)
                            Text(config.name).font(.headline).lineLimit(2)
                            Text(set.id == editor.store.library.activeSetID ? L("In Use") : L("Edit Pack"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16).frame(maxWidth: .infinity)
                        .modifier(WorkspaceSurface(radius: 16))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !set.isBuiltIn {
                            Button(L("Remove")) { editor.removePack(set) { model.packDidChange() } }
                        }
                    }
                }
            }
            .padding(3)
        }
    }

    private var preview: some View {
        HStack(spacing: 18) {
            AnimatedPresetArtwork(image: editor.image(id: editor.previewPresetID))
                .frame(width: 145, height: 145).clipped()
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Preview Mode")).font(.headline)
                Text(editor.previewSource).font(.callout).foregroundStyle(.teal)
                Text(editor.name(id: editor.previewPresetID)).font(.title2)
                Text(L("Click the keyboard or type here. When typing stops, IDLE resumes."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    PreviewKeyInput(onStroke: { editor.previewKey($0) }).frame(width: 190, height: 30)
                    Button(L("Next IDLE Image")) { editor.showPreviewIdle() }
                }
                if !editor.lastPreviewKey.isEmpty {
                    Text(L("Last Input · %1$@", editor.lastPreviewKey)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.teal.opacity(0.7)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Preview Mode"))
    }

    private func importPack(folder: Bool) {
        editor.importPack(folder: folder) {
            model.packDidChange()
            pageRaw = WorkspacePage.mapping.rawValue
        }
    }
}

private struct WorkspaceSurface: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.primary.opacity(0.09)))
            .shadow(color: .black.opacity(0.025), radius: 4, y: 2)
    }
}

private struct PresetArtwork: View {
    var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.tertiary) }
        }
        .accessibilityHidden(true)
    }
}

private struct AnimatedPresetArtwork: NSViewRepresentable {
    var image: NSImage?
    final class FlexibleImageView: NSImageView {
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    }
    func makeNSView(context: Context) -> NSImageView {
        let view = FlexibleImageView()
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        return view
    }
    func updateNSView(_ view: NSImageView, context: Context) { if view.image !== image { view.image = image } }
}

/// This local responder exists only in Preview Mode. It never requests global input access.
private struct PreviewKeyInput: NSViewRepresentable {
    let onStroke: (KeyStroke) -> Void
    func makeNSView(context: Context) -> PreviewInputButton {
        let button = PreviewInputButton(title: L("Click Here and Type"), target: nil, action: nil)
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(PreviewInputButton.focusPreview)
        button.onStroke = onStroke
        return button
    }
    func updateNSView(_ view: PreviewInputButton, context: Context) {
        view.title = L("Click Here and Type")
        view.onStroke = onStroke
    }
    final class PreviewInputButton: NSButton {
        var onStroke: ((KeyStroke) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        @objc func focusPreview() { window?.makeFirstResponder(self) }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.focusPreview() }
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48 {
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
                else { window?.selectNextKeyView(self) }
                return
            }
            onStroke?(KeyStroke(keyCode: event.keyCode, modifiers: KeyModifiers(eventFlags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))))
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
    }
}
