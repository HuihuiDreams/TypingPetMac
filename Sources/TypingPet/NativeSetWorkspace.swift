import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One AppKit popover owns its hosting controller independently of changing key thumbnails.
/// Saving a selection updates the content without dismissing or recreating the popover.
@MainActor
final class PackPopoverController: NSObject, ObservableObject, NSPopoverDelegate {
    enum Target: Equatable { case mapping(PackEditorTarget), preset(String) }
    @Published private(set) var target: Target?
    private let editor: PackEditorModel
    private let popover = NSPopover()
    private let anchors = NSMapTable<NSString, NSView>.strongToWeakObjects()

    init(editor: PackEditorModel) {
        self.editor = editor
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }
    func register(_ view: NSView, id: String) { anchors.setObject(view, forKey: id as NSString) }
    func toggle(_ next: Target, anchor: String) {
        if target == next, popover.isShown { close(); return }
        guard let view = anchors.object(forKey: anchor as NSString), view.window != nil else { return }
        popover.close()
        target = next
        popover.contentViewController = NSHostingController(rootView: PackPopoverContent(editor: editor, controller: self))
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }
    func updateModifiers() {
        if case .mapping(.key(let old)) = target {
            target = .mapping(.key(KeyStroke(keyCode: old.keyCode, modifiers: editor.modifiers)))
        }
    }
    func close() { popover.close(); popover.contentViewController = nil; target = nil }
    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil; target = nil }
}

private struct PopoverAnchor: NSViewRepresentable {
    let id: String
    let controller: PackPopoverController
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        controller.register(view, id: id)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { controller.register(nsView, id: id) }
}

struct NativeSetWorkspace: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var editor: PackEditorModel
    @StateObject private var popovers: PackPopoverController
    init(editor: PackEditorModel) {
        self.editor = editor
        _popovers = StateObject(wrappedValue: PackPopoverController(editor: editor))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                gallery
                mapping
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.teal)
        .environment(\.locale, localization.locale)
        .onChange(of: editor.selectedSetID) { _ in popovers.close() }
        .onChange(of: editor.modifiers) { _ in popovers.updateModifiers() }
        .onChange(of: editor.draft.presets) { presets in
            if case .preset(let id) = popovers.target, !presets.contains(where: { $0.id == id }) { popovers.close() }
        }
        .onDisappear { popovers.close() }
        .alert(L("Error"), isPresented: Binding(get: { editor.errorMessage != nil }, set: { if !$0 { editor.errorMessage = nil } })) {
            Button(L("OK")) { editor.errorMessage = nil }
        } message: { Text(editor.errorMessage ?? "") }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(editor.draft.name).font(.system(size: 22, weight: .semibold)).lineLimit(2)
                    if editor.isActive { Label(L("In Use"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.teal).fixedSize() }
                }
                Text(editor.isActive ? L("Changes apply immediately.") : L("Changes saved automatically."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !editor.isActive {
                Button(L("Use Set")) { editor.activate(editor.selectedSet) }.disabled(!editor.canEdit || !editor.draft.isUsable)
            }
            Button {
                popovers.close()
                do { try editor.duplicatePack() } catch { editor.errorMessage = error.localizedDescription }
            } label: { Label(L("Duplicate"), systemImage: "plus.square.on.square") }
            .disabled(!editor.canEdit)
            if !editor.selectedSet.isBuiltIn {
                Menu {
                    Button(L("Rename")) { popovers.close(); editor.renamePack(editor.selectedSet) }
                    Button(L("Delete")) { popovers.close(); editor.removePack(editor.selectedSet) }.disabled(editor.isActive)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(L("Set Options"))
            }
        }
    }
    private var gallery: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Image Presets")).font(.headline)
                Text("\(editor.draft.presets.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if editor.canEditPresets { Button { popovers.close(); editor.addPresets() } label: { Label(L("Add Images…"), systemImage: "plus") } }
            }
            if editor.draft.presets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text(L("No images yet")).font(.headline)
                    Text(L("The first image is used while typing and while resting.")).font(.callout).foregroundStyle(.secondary)
                    if editor.canEditPresets { Button(L("Add Images…")) { editor.addPresets() } }
                }
                .frame(maxWidth: .infinity).padding(30).modifier(SetSurface(radius: 14))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 180))], spacing: 10) {
                    ForEach(editor.draft.presets) { preset in
                        Group {
                            if editor.selectedSet.isBuiltIn { galleryTile(preset) }
                            else {
                                Button { popovers.toggle(.preset(preset.id), anchor: "preset:" + preset.id) } label: { galleryTile(preset) }
                                    .buttonStyle(.plain).disabled(!editor.canEdit)
                                    .background(PopoverAnchor(id: "preset:" + preset.id, controller: popovers))
                                    .accessibilityLabel(L("Edit %1$@", preset.name))
                            }
                        }
                        .onDrag { NSItemProvider(object: preset.id as NSString) }
                    }
                }
                .padding(13).modifier(SetSurface(radius: 14))
            }
            if editor.selectedSet.isBuiltIn {
                Text(L("Built-in presets are fixed. Duplicate to edit them."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func galleryTile(_ preset: PetImagePreset) -> some View {
        VStack(spacing: 7) {
            SetArtwork(image: editor.image(for: preset)).frame(height: 64)
            Text(preset.name).font(.caption).lineLimit(2)
        }
        .padding(10).frame(maxWidth: .infinity).contentShape(Rectangle())
    }
    private var mapping: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Keyboard Mapping")).font(.headline)
            HStack(spacing: 10) { behavior(.unassigned); behavior(.idle) }
            SetToolsLayout {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Text(L("Modifier Combination"))
                        Text(L("Multiple selections allowed")).font(.caption)
                    }.font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        modifier(.control, symbol: "⌃", name: "Control")
                        modifier(.option, symbol: "⌥", name: "Option")
                        modifier(.shift, symbol: "⇧", name: "Shift")
                        modifier(.command, symbol: "⌘", name: "Command")
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("Common Keys")).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 7) { quickKey(49, name: L("Space"), symbol: "space"); quickKey(36, name: L("Enter"), symbol: "return") }
                }
            }
            ScrollView(.horizontal) { keyboard.padding(.bottom, 5) }
                .accessibilityLabel(L("Keyboard Mapping"))
            HStack {
                Text(L("Mac · ANSI Layout"))
                Spacer()
                Text(L("Click a key to edit its presets."))
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private func modifier(_ key: KeyModifiers, symbol: String, name: String) -> some View {
        Toggle(isOn: Binding(get: { editor.modifiers.contains(key) }, set: { _ in editor.toggleModifier(key) })) {
            Text(symbol + " " + name).font(.callout)
        }.toggleStyle(.checkbox).fixedSize().accessibilityLabel(name)
    }
    private func quickKey(_ code: UInt16, name: String, symbol: String) -> some View {
        let target = PackEditorTarget.key(KeyStroke(keyCode: code, modifiers: editor.modifiers))
        let anchor = "quick:\(code)"
        return Button { popovers.toggle(.mapping(target), anchor: anchor) } label: {
            HStack(spacing: 6) {
                if let id = editor.selection(for: target).presetIDs.first { SetArtwork(image: editor.image(id: id)).frame(width: 20, height: 20) }
                else { Image(systemName: symbol) }
                Text(name)
            }
        }
        .disabled(!editor.canEdit || editor.draft.presets.isEmpty)
        .background(PopoverAnchor(id: anchor, controller: popovers))
        .accessibilityLabel(L("Quick setup for %1$@", editor.modifiers.displayPrefix + name))
    }
    private func behavior(_ target: PackEditorTarget) -> some View {
        let value = editor.selection(for: target)
        let anchor = target == .idle ? "idle" : "unassigned"
        return Button { popovers.toggle(.mapping(target), anchor: anchor) } label: {
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    ForEach(Array(value.presetIDs.prefix(3)), id: \.self) { id in SetArtwork(image: editor.image(id: id)).frame(width: 30, height: 36) }
                    if value.presetIDs.isEmpty { Image(systemName: "photo").foregroundStyle(.tertiary) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.title).font(.headline)
                    Text(L("%1$@ presets · %2$@", value.presetIDs.count, value.mode.title)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 68).modifier(SetSurface(radius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(popovers.target == .mapping(target) ? Color.teal : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!editor.canEdit || editor.draft.presets.isEmpty)
        .background(PopoverAnchor(id: anchor, controller: popovers))
    }
    private var keyboard: some View {
        VStack(spacing: 5) {
            ForEach(KeyboardLayoutKey.rows.indices, id: \.self) { index in keyboardRow(KeyboardLayoutKey.rows[index], function: index == 0) }
        }
        .padding(8).frame(width: 760)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.055)))
    }
    private func keyboardRow(_ row: [KeyboardLayoutKey], function: Bool) -> some View {
        let unit = (744 - CGFloat(row.count - 1) * 4) / row.reduce(0) { $0 + $1.width }
        return HStack(spacing: 4) {
            ForEach(row) { key in keyboardKey(key, function: function).frame(width: unit * key.width, height: function ? 42 : 52) }
        }
    }
    private func keyboardKey(_ key: KeyboardLayoutKey, function: Bool) -> some View {
        let target = key.code.map { PackEditorTarget.key(KeyStroke(keyCode: $0, modifiers: editor.modifiers)) }
        let value = target.map(editor.selection)
        let selected = target != nil && popovers.target == target.map(PackPopoverController.Target.mapping)
        let anchor = "key:" + (key.code.map(String.init) ?? key.label)
        return Button { if let target { popovers.toggle(.mapping(target), anchor: anchor) } } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(key.code == nil ? key.label.replacingOccurrences(of: "L", with: "").replacingOccurrences(of: "R", with: "") : key.label)
                    .font(.system(size: 11)).foregroundStyle(key.code == nil ? .tertiary : .secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let id = value?.presetIDs.first { SetArtwork(image: editor.image(id: id)).frame(maxWidth: .infinity).frame(height: function ? 19 : 27) }
                else if key.code != nil { Text("·").foregroundStyle(.tertiary).frame(maxWidth: .infinity) }
            }
            .padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.teal.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(key.code == nil ? 0.4 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.teal : Color.primary.opacity(0.10), lineWidth: selected ? 1.5 : 0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(target == nil || !editor.canEdit || editor.draft.presets.isEmpty)
        .background(PopoverAnchor(id: anchor, controller: popovers))
        .accessibilityLabel(target?.title ?? key.label)
        .accessibilityValue(value?.presetIDs.map(editor.name).joined(separator: ", ") ?? "")
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            guard let code = key.code, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { value, _ in
                guard let value else { return }
                DispatchQueue.main.async {
                    let stroke = KeyStroke(keyCode: code, modifiers: editor.modifiers)
                    editor.assignPreset(value, to: stroke)
                    popovers.toggle(.mapping(.key(stroke)), anchor: anchor)
                }
            }
            return true
        }
    }
}

/// Wrap the two control groups without creating duplicate popover anchors.
private struct SetToolsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let horizontal = sizes.reduce(0) { $0 + $1.width } + 24 <= (proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? sizes.reduce(0) { $0 + $1.width } + 24,
                      height: horizontal ? sizes.map(\.height).max() ?? 0 : sizes.reduce(0) { $0 + $1.height } + 14)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let horizontal = sizes.reduce(0) { $0 + $1.width } + 24 <= bounds.width
        var point = bounds.origin
        for (index, view) in subviews.enumerated() {
            view.place(at: point, anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
            if horizontal { point.x += sizes[index].width + 24 } else { point.y += sizes[index].height + 14 }
        }
    }
}

private struct PackPopoverContent: View {
    @ObservedObject var editor: PackEditorModel
    @ObservedObject var controller: PackPopoverController
    @ObservedObject private var localization = AppLocalization.shared
    var body: some View {
        Group {
            switch controller.target {
            case .mapping(let target): MappingPresetPopover(editor: editor, controller: controller, target: target)
            case .preset(let id): GalleryPresetPopover(editor: editor, controller: controller, presetID: id).id(id)
            case nil: EmptyView()
            }
        }.tint(.teal).environment(\.locale, localization.locale)
    }
}

private struct MappingPresetPopover: View {
    @ObservedObject var editor: PackEditorModel
    let controller: PackPopoverController
    let target: PackEditorTarget
    var body: some View {
        let value = editor.selection(for: target)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(target.title).font(.headline)
                Spacer()
                if case .key = target { Button(L("Unassign")) { editor.unassign(target) }.disabled(value.presetIDs.isEmpty) }
                Button { controller.close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(L("Close"))
            }
            Text(target == .idle ? L("Choose presets shown when you stop typing.") : target == .unassigned ? L("Choose presets shown for keys without a mapping.") : L("Choose presets and a display mode for this key combination."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker(L("Display Mode"), selection: Binding(get: { value.mode }, set: { editor.setMode($0, for: target) })) {
                ForEach(PresetPlaybackMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
            }.disabled(value.presetIDs.isEmpty)
            Text(value.presetIDs.isEmpty ? L("Uses Unassigned settings") : L("%1$@ selected", value.presetIDs.count)).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(editor.draft.presets) { preset in
                        Button { editor.togglePreset(preset.id, for: target) } label: {
                            VStack(spacing: 5) {
                                SetArtwork(image: editor.image(for: preset)).frame(height: 44)
                                Text(preset.name).font(.caption).lineLimit(2)
                            }
                            .padding(8).frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 9).fill(value.presetIDs.contains(preset.id) ? Color.teal.opacity(0.13) : Color(nsColor: .controlBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(value.presetIDs.contains(preset.id) ? Color.teal : Color.primary.opacity(0.10)))
                            .overlay(alignment: .topTrailing) {
                                if value.presetIDs.contains(preset.id) { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.teal).padding(4) }
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel(preset.name).accessibilityAddTraits(value.presetIDs.contains(preset.id) ? .isSelected : [])
                    }
                }.padding(2)
            }.frame(height: min(240, max(86, CGFloat((editor.draft.presets.count + 3) / 4) * 90)))
            if value.mode == .cycle && value.presetIDs.count > 1 {
                Text(L("Cycle Order")).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(Array(value.presetIDs.enumerated()), id: \.element) { index, id in
                            HStack {
                                Text("\(index + 1). \(editor.name(id: id))").lineLimit(1)
                                Spacer()
                                Button { editor.movePreset(id, by: -1, for: target) } label: { Image(systemName: "arrow.up") }
                                    .disabled(index == 0).accessibilityLabel(L("Move Earlier"))
                                Button { editor.movePreset(id, by: 1, for: target) } label: { Image(systemName: "arrow.down") }
                                    .disabled(index == value.presetIDs.count - 1).accessibilityLabel(L("Move Later"))
                            }
                        }
                    }
                }.font(.caption).controlSize(.small).frame(height: min(105, CGFloat(value.presetIDs.count) * 28))
            }
        }
        .padding(20).frame(width: 380)
        .accessibilityElement(children: .contain).accessibilityLabel(L("Preset Editor"))
    }
}

private struct GalleryPresetPopover: View {
    @ObservedObject var editor: PackEditorModel
    let controller: PackPopoverController
    let presetID: String
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editor.name(id: presetID)).font(.headline)
                Spacer()
                Button { controller.close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(L("Close"))
            }
            TextField(L("Preset Name"), text: $name).textFieldStyle(.roundedBorder).onSubmit(apply)
            HStack {
                Button(L("Replace Image…")) { editor.selectedPresetID = presetID; controller.close(); editor.replacePresetImage() }
                Button(L("Delete Image")) { editor.selectedPresetID = presetID; controller.close(); editor.removeSelectedPreset() }
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { controller.close() }.keyboardShortcut(.cancelAction)
                Button(L("Apply"), action: apply).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 310).onAppear { name = editor.name(id: presetID) }
    }
    private func apply() { editor.selectedPresetID = presetID; editor.renamePreset(name.trimmingCharacters(in: .whitespacesAndNewlines)); controller.close() }
}

private struct SetSurface: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.primary.opacity(0.08)))
    }
}
private struct SetArtwork: View {
    let image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.tertiary) }
        }.accessibilityHidden(true)
    }
}
