import AppKit
import Combine
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
    private weak var coordinateView: NSView?
    private var anchors: [String: CGRect] = [:]
    private var anchorID: String?
    private var content: NSHostingController<PackPopoverContent>?
    private var subscription: AnyCancellable?

    init(editor: PackEditorModel) {
        self.editor = editor
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        subscription = editor.objectWillChange.debounce(for: .milliseconds(20), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.resizeContent() }
    }
    func registerCoordinateView(_ view: NSView) { coordinateView = view }
    func register(_ rect: CGRect, id: String) {
        anchors[id] = rect
        if popover.isShown, anchorID == id {
            popover.positioningRect = rect
        }
    }
    func toggle(_ next: Target, anchor: String) {
        if target == next, popover.isShown { close(); return }
        guard let view = coordinateView, view.window != nil, let rect = anchors[anchor], !rect.isEmpty else { return }
        popover.close()
        target = next
        anchorID = anchor
        let host = NSHostingController(rootView: PackPopoverContent(editor: editor, controller: self))
        host.sizingOptions = []
        let size = host.sizeThatFits(in: CGSize(width: 420, height: 900))
        host.view.setFrameSize(size)
        content = host
        popover.contentViewController = host
        popover.contentSize = size
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }
    func updateModifiers() {
        if case .mapping(.key(let old)) = target {
            target = .mapping(.key(KeyStroke(keyCode: old.keyCode, modifiers: editor.modifiers)))
            DispatchQueue.main.async { [weak self] in self?.resizeContent() }
        }
    }
    private func resizeContent() {
        guard popover.isShown, let content, let view = coordinateView, let anchorID, let rect = anchors[anchorID] else { return }
        let size = content.sizeThatFits(in: CGSize(width: 420, height: 900))
        if popover.contentSize != size {
            content.view.setFrameSize(size)
            popover.contentSize = size
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        }
    }
    func close() { popover.close(); popover.contentViewController = nil; content = nil; target = nil; anchorID = nil }
    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil; content = nil; target = nil; anchorID = nil }
}

private struct PopoverAnchor: View {
    let id: String
    let controller: PackPopoverController
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { controller.register(geometry.frame(in: .named("set-workspace")), id: id) }
                .onChange(of: geometry.frame(in: .named("set-workspace"))) { rect in controller.register(rect, id: id) }
        }.allowsHitTesting(false)
    }
}

private final class PopoverCoordinateView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct PopoverCoordinateRoot: NSViewRepresentable {
    let controller: PackPopoverController
    func makeNSView(context: Context) -> NSView {
        let view = PopoverCoordinateView()
        controller.registerCoordinateView(view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { controller.registerCoordinateView(nsView) }
}

private struct CursorRegion: NSViewRepresentable {
    let cursor: NSCursor
    func makeNSView(context: Context) -> CursorRegionView { CursorRegionView(cursor: cursor) }
    func updateNSView(_ view: CursorRegionView, context: Context) {
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }
}

@MainActor
private final class CursorRegionView: NSView {
    var cursor: NSCursor
    init(cursor: NSCursor) { self.cursor = cursor; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct NativeSetWorkspace: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var editor: PackEditorModel
    @StateObject private var popovers: PackPopoverController
    @State private var isGalleryDropTargeted = false
    @State private var hoveredPresetID: String?
    @State private var targetedKeyCodes = Set<UInt16>()
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
        .background(PopoverCoordinateRoot(controller: popovers))
        .coordinateSpace(name: "set-workspace")
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
                    Button {
                        popovers.close()
                        do { try editor.duplicatePack() } catch { editor.errorMessage = error.localizedDescription }
                    } label: { Label(L("Duplicate"), systemImage: "plus.square.on.square") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!editor.canEdit)
                    if !editor.selectedSet.isBuiltIn {
                        Menu {
                            Button(L("Rename")) { popovers.close(); editor.renamePack(editor.selectedSet) }
                            Button(L("Delete")) { popovers.close(); editor.removePack(editor.selectedSet) }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderedButton).fixedSize().accessibilityLabel(L("Set Options"))
                    }
                }
                Text(L("Changes saved automatically."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !editor.isActive {
                Button(L("Use This Set")) { editor.activate(editor.selectedSet) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!editor.canEdit || !editor.draft.isUsable)
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
            if editor.canEditPresets {
                Text(L("Drop image files here or choose Add Images."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                            if editor.selectedSet.isBuiltIn {
                                galleryTile(preset, hovered: hoveredPresetID == preset.id)
                                    .onHover { hovering in updatePresetHover(preset.id, hovering: hovering) }
                                    .onDrag { Self.presetProvider(preset.id) }
                            }
                            else {
                                Button { popovers.toggle(.preset(preset.id), anchor: "preset:" + preset.id) } label: { galleryTile(preset, hovered: hoveredPresetID == preset.id) }
                                    .buttonStyle(.plain).disabled(!editor.canEdit)
                                    .background(PopoverAnchor(id: "preset:" + preset.id, controller: popovers))
                                    .accessibilityLabel(L("Edit %1$@", preset.name))
                                    .onHover { hovering in updatePresetHover(preset.id, hovering: hovering) }
                                    .onDrag { Self.presetProvider(preset.id) }
                            }
                        }
                    }
                    if editor.canEditPresets {
                        Button { popovers.close(); editor.addPresets() } label: {
                            VStack(spacing: 9) {
                                Image(systemName: "plus").font(.system(size: 25, weight: .medium))
                                Text(L("Add Images…")).font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 122)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.025)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Add Images…"))
                    }
                }
                .padding(13).modifier(SetSurface(radius: 14))
            }
            if editor.selectedSet.isBuiltIn {
                Text(L("Built-in presets are fixed. Duplicate to edit them."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .overlay {
            if isGalleryDropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.teal, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isGalleryDropTargeted, perform: importDroppedImages)
    }

    private func importDroppedImages(_ providers: [NSItemProvider]) -> Bool {
        guard editor.canEditPresets else { return false }
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls = Array<URL?>(repeating: nil, count: fileProviders.count)
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let url = Self.fileURL(from: item),
                      FolderImageSelection.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
                lock.lock()
                urls[index] = url
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            lock.lock()
            let images = urls.compactMap { $0 }
            lock.unlock()
            guard !images.isEmpty else {
                editor.errorMessage = L("No supported image files were dropped.")
                return
            }
            let scoped = images.map { ($0, $0.startAccessingSecurityScopedResource()) }
            editor.addPresets(from: images)
            scoped.forEach { url, started in if started { url.stopAccessingSecurityScopedResource() } }
            popovers.close()
        }
        return true
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }
    private func galleryTile(_ preset: PetImagePreset, hovered: Bool) -> some View {
        VStack(spacing: 7) {
            SetArtwork(image: editor.image(for: preset)).frame(height: 64)
            Text(preset.name).font(.caption).lineLimit(2).frame(height: 30)
        }
        .padding(10).frame(maxWidth: .infinity).frame(height: 122).contentShape(RoundedRectangle(cornerRadius: 10))
        .background(CursorRegion(cursor: .pointingHand))
        .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? Color.accentColor.opacity(0.09) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(hovered ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
    private func dropTargetBinding(for key: KeyboardLayoutKey) -> Binding<Bool> {
        guard let code = key.code else { return .constant(false) }
        return Binding(
            get: { targetedKeyCodes.contains(code) },
            set: { targeted in
                if targeted { targetedKeyCodes.insert(code) }
                else { targetedKeyCodes.remove(code) }
            }
        )
    }
    private func updatePresetHover(_ id: String, hovering: Bool) {
        if hovering {
            hoveredPresetID = id
        } else {
            if hoveredPresetID == id { hoveredPresetID = nil }
        }
    }
    private static func presetProvider(_ id: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(id.data(using: .utf8), nil)
            return nil
        }
        return provider
    }
    private var mapping: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Keyboard Mapping")).font(.headline)
            HStack(spacing: 10) { behavior(.unassigned); behavior(.idle) }
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
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    keyboard
                        .frame(minWidth: geometry.size.width, alignment: .center)
                        .padding(.bottom, 16)
                }
                .accessibilityLabel(L("Keyboard Mapping"))
            }
            .frame(height: KeyboardMetrics.height + 16)
        }
    }
    private func modifier(_ key: KeyModifiers, symbol: String, name: String) -> some View {
        Toggle(isOn: Binding(get: { editor.modifiers.contains(key) }, set: { _ in editor.toggleModifier(key) })) {
            Text(symbol + " " + name).font(.callout)
        }.toggleStyle(.checkbox).fixedSize().accessibilityLabel(name)
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
        VStack(spacing: KeyboardMetrics.rowSpacing) {
            ForEach(KeyboardLayoutKey.rows.indices, id: \.self) { index in
                if index == KeyboardLayoutKey.rows.count - 1 { keyboardBottomRow }
                else { keyboardRow(KeyboardLayoutKey.rows[index], function: index == 0) }
            }
        }
        .padding(KeyboardMetrics.padding).frame(width: KeyboardMetrics.width)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.055)))
    }
    private func keyboardRow(_ row: [KeyboardLayoutKey], function: Bool) -> some View {
        let flexibleID = row.last(where: { $0.width > 1 })?.id
        let extra = KeyboardMetrics.innerWidth - CGFloat(row.count - 1) * KeyboardMetrics.gap - row.reduce(0) { $0 + $1.width } * KeyboardMetrics.keySize
        let hardwareKey = function ? row.first(where: \.isHardwareKey) : nil
        let standardFunctionCount = row.count - (hardwareKey == nil ? 0 : 1)
        let functionWidth = (KeyboardMetrics.innerWidth - CGFloat(row.count - 1) * KeyboardMetrics.gap - (hardwareKey == nil ? 0 : KeyboardMetrics.functionHeight)) / CGFloat(max(standardFunctionCount, 1))
        return HStack(spacing: KeyboardMetrics.gap) {
            ForEach(row) { key in
                framedKey(key,
                          width: function ? (key.isHardwareKey ? KeyboardMetrics.functionHeight : functionWidth) : KeyboardMetrics.keySize * key.width + (key.id == flexibleID ? extra : 0),
                          height: function ? KeyboardMetrics.functionHeight : KeyboardMetrics.keySize,
                          function: function)
            }
        }
    }
    private var keyboardBottomRow: some View {
        let row = KeyboardLayoutKey.rows.last ?? []
        let regular = row.filter { ![123, 124, 125, 126].contains($0.code) }
        let arrows = row.filter { [123, 124, 125, 126].contains($0.code) }
        let unit = KeyboardMetrics.keySize
        let extra = KeyboardMetrics.innerWidth - CGFloat(regular.count + 2) * KeyboardMetrics.gap - (regular.reduce(0) { $0 + $1.width } + 3) * unit
        let halfHeight = (unit - KeyboardMetrics.gap) / 2
        return HStack(alignment: .bottom, spacing: KeyboardMetrics.gap) {
            ForEach(regular) { key in framedKey(key, width: unit * key.width + (key.code == 49 ? extra : 0), height: unit) }
            if let left = arrows.first(where: { $0.code == 123 }), let up = arrows.first(where: { $0.code == 126 }),
               let down = arrows.first(where: { $0.code == 125 }), let right = arrows.first(where: { $0.code == 124 }) {
                framedKey(left, width: unit, height: halfHeight, compact: true)
                VStack(spacing: KeyboardMetrics.gap) {
                    framedKey(up, width: unit, height: halfHeight, compact: true)
                    framedKey(down, width: unit, height: halfHeight, compact: true)
                }
                framedKey(right, width: unit, height: halfHeight, compact: true)
            }
        }
    }
    private func framedKey(_ key: KeyboardLayoutKey, width: CGFloat, height: CGFloat, function: Bool = false, compact: Bool = false) -> some View {
        keyboardKey(key, function: function, compact: compact)
            .frame(width: width, height: height)
            .background(PopoverAnchor(id: "key:" + (key.code.map(String.init) ?? key.label), controller: popovers))
    }
    private func keyboardKey(_ key: KeyboardLayoutKey, function: Bool, compact: Bool) -> some View {
        let target = key.code.map { PackEditorTarget.key(KeyStroke(keyCode: $0, modifiers: editor.modifiers)) }
        let value = target.map(editor.selection)
        let selected = target != nil && popovers.target == target.map(PackPopoverController.Target.mapping)
        let dropTargeted = key.code.map { targetedKeyCodes.contains($0) } ?? false
        let anchor = "key:" + (key.code.map(String.init) ?? key.label)
        return Button { if let target { popovers.toggle(.mapping(target), anchor: anchor) } } label: {
            Group {
                if key.isHardwareKey {
                    Image(systemName: "touchid")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if compact {
                    HStack(spacing: 2) {
                        Text(key.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if let id = value?.presetIDs.first { SetArtwork(image: editor.image(id: id)).frame(width: 14, height: 14) }
                        else { Text("·").font(.system(size: 11)).foregroundStyle(.tertiary) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(key.code == nil ? key.label.replacingOccurrences(of: "L", with: "").replacingOccurrences(of: "R", with: "") : key.label)
                            .font(.system(size: 11)).foregroundStyle(key.code == nil ? .tertiary : .secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if let id = value?.presetIDs.first { SetArtwork(image: editor.image(id: id)).frame(maxWidth: .infinity).frame(height: function ? 14 : 24) }
                        else if key.code != nil { Text("·").foregroundStyle(.tertiary).frame(maxWidth: .infinity) }
                    }
                }
            }
            .padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeycapButtonStyle(selected: selected, dropTargeted: dropTargeted)).disabled(target == nil || !editor.canEdit || editor.draft.presets.isEmpty)
        .accessibilityLabel(target?.title ?? (key.isHardwareKey ? L("Touch ID / Power Button") : key.label))
        .accessibilityValue(value?.presetIDs.map(editor.name).joined(separator: ", ") ?? "")
        .onDrop(of: [UTType.plainText], isTargeted: dropTargetBinding(for: key)) { providers in
            guard let code = key.code, let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                guard let data, let value = String(data: data, encoding: .utf8) else { return }
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

private enum KeyboardMetrics {
    static let width: CGFloat = 760
    static let padding: CGFloat = 8
    static let keySize: CGFloat = 48
    static let functionHeight: CGFloat = 36
    static let gap: CGFloat = 4
    static let rowSpacing: CGFloat = 5
    static var innerWidth: CGFloat { width - padding * 2 }
    static var height: CGFloat {
        functionHeight + CGFloat(KeyboardLayoutKey.rows.count - 1) * (keySize + rowSpacing) + padding * 2
    }
}

private struct KeycapButtonStyle: ButtonStyle {
    let selected: Bool
    let dropTargeted: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = isEnabled && (hovering || configuration.isPressed || selected || dropTargeted)
        return configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(
                dropTargeted ? Color.teal.opacity(0.36) : highlighted ? Color.teal.opacity(configuration.isPressed ? 0.22 : selected ? 0.14 : 0.09) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                dropTargeted ? Color.teal : highlighted ? Color.teal.opacity(selected ? 1 : 0.65) : Color.primary.opacity(0.10), lineWidth: dropTargeted ? 2 : highlighted ? 1.5 : 0.6))
            .shadow(color: dropTargeted ? Color.teal.opacity(0.85) : .clear, radius: dropTargeted ? 10 : 0)
            .scaleEffect(dropTargeted ? 1.04 : 1)
            .animation(.easeInOut(duration: 0.12), value: dropTargeted)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
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
