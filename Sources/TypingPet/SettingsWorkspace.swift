import AppKit
import Combine
import SwiftUI

private enum WorkspacePage: String, CaseIterable {
    case sets, appearance, todos, general
    var title: String {
        switch self {
        case .sets: L("Set Management")
        case .appearance: L("Appearance and Behavior")
        case .todos: L("Todos and Focus")
        case .general: L("General")
        }
    }
    var symbol: String {
        switch self {
        case .sets: "shippingbox"
        case .appearance: "slider.horizontal.3"
        case .todos: "checklist"
        case .general: "gearshape"
        }
    }
}

@MainActor
private final class WorkspaceNavigation: ObservableObject {
    @Published var page: WorkspacePage = .sets
}

/// AppKit owns the actual window, toolbar, split divider, and sidebar selection.
/// The integrated preset gallery and keyboard editor are native SwiftUI views.
@MainActor
final class SettingsWorkspaceController: NSSplitViewController, NSToolbarDelegate {
    private let editor: PackEditorModel
    private let navigation = WorkspaceNavigation()
    private let sidebarToggleID = NSToolbarItem.Identifier("TypingPetSidebarToggle")

    init(model: TypingPetSettingsModel, todoStore: TodoStore, updater: UpdateController) {
        editor = PackEditorModel(store: model.packStore, onChange: { reload in model.packDidChange(reload: reload) })
        super.init(nibName: nil, bundle: nil)
        let sidebar = NSSplitViewItem(sidebarWithViewController: WorkspaceSidebarController(editor: editor, navigation: navigation))
        sidebar.minimumThickness = 190
        sidebar.maximumThickness = 340
        sidebar.canCollapse = true
        sidebar.preferredThicknessFraction = 0.23
        let content = NSSplitViewItem(viewController: WorkspaceContentController(
            model: model, todoStore: todoStore, updater: updater, editor: editor, navigation: navigation))
        content.minimumThickness = 530
        addSplitViewItem(sidebar)
        addSplitViewItem(content)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = NSSplitView.AutosaveName("TypingPetSettingsSidebar")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        let native = super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        return native.isEmpty ? native : native.insetBy(dx: -3, dy: 0)
    }

    func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "TypingPetSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [sidebarToggleID, .flexibleSpace] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == sidebarToggleID else { return nil }
        let item = NSToolbarItem(itemIdentifier: sidebarToggleID)
        item.label = L("Toggle Sidebar")
        item.toolTip = L("Toggle Sidebar")
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: L("Toggle Sidebar"))
        item.target = self
        item.action = #selector(toggleSidebar(_:))
        return item
    }
}

@MainActor
private final class SidebarBrandView: NSStackView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
}

@MainActor
private final class WorkspaceSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row: Equatable { case set(UUID), settings, page(WorkspacePage) }
    private let editor: PackEditorModel
    private let navigation: WorkspaceNavigation
    private let table = NSTableView()
    private let addButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let brandLabel = NSTextField(labelWithString: AppEnvironment.displayName)
    private let subtitle = NSTextField(labelWithString: "")
    private var rows: [Row] = []
    private var subscriptions = Set<AnyCancellable>()
    private var createPopover: NSPopover?
    private var updating = false

    init(editor: PackEditorModel, navigation: WorkspaceNavigation) {
        self.editor = editor
        self.navigation = navigation
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        view = background
        let artwork = NSImageView(image: editor.cover(for: editor.store.library.activeSet) ?? NSImage())
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.setAccessibilityHidden(true)
        artwork.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([artwork.widthAnchor.constraint(equalToConstant: 35), artwork.heightAnchor.constraint(equalToConstant: 35)])
        brandLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [brandLabel, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let brand = SidebarBrandView(views: [artwork, labels])
        brand.spacing = 10
        brand.alignment = .centerY
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.target = self
        addButton.action = #selector(createSet)
        let heading = NSStackView(views: [titleLabel, NSView(), addButton])
        heading.alignment = .centerY
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("navigation"))
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.style = .sourceList
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(L("Set Management"))
        table.registerForDraggedTypes([.string])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        for child in [brand, heading, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            brand.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            brand.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            brand.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            heading.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 24),
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
        editor.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in self?.reload() }.store(in: &subscriptions)
        navigation.$page.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        AppLocalization.shared.$language.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        reload()
    }

    private func reload() {
        guard isViewLoaded else { return }
        updating = true
        defer { updating = false }
        titleLabel.stringValue = L("Set Management")
        subtitle.stringValue = L("Your Little Companion")
        addButton.setAccessibilityLabel(L("New Set"))
        addButton.toolTip = L("New Set")
        addButton.isEnabled = editor.canEdit
        rows = editor.sets.map { .set($0.id) } + [.settings] + [WorkspacePage.appearance, .todos, .general].map(Row.page)
        table.reloadData()
        let desired: Row = navigation.page == .sets ? .set(editor.selectedSetID) : .page(navigation.page)
        if let row = rows.firstIndex(of: desired) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rows[row] == .settings ? 46 : 40 }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows[row] == .settings }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row] != .settings }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let name: String
        let symbol: String
        var active = false
        switch rows[row] {
        case .set(let id):
            guard let set = editor.sets.first(where: { $0.id == id }) else { return cell }
            name = editor.configuration(for: set).name
            symbol = "shippingbox"
            active = id == editor.activeSetID
        case .settings: name = L("Settings"); symbol = ""
        case .page(let page): name = page.title; symbol = page.symbol
        }
        let label = NSTextField(labelWithString: name)
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: rows[row] == .settings ? 11 : 13)
        label.textColor = rows[row] == .settings ? .secondaryLabelColor : .labelColor
        cell.textField = label
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .secondaryLabelColor
        cell.imageView = image
        let check = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: L("In Use")) ?? NSImage())
        check.contentTintColor = .systemTeal
        check.isHidden = !active
        check.setAccessibilityLabel(L("In Use"))
        for child in [image, label, check] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: rows[row] == .settings ? 0 : 18), image.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            check.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10), check.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: active ? 14 : 0), check.heightAnchor.constraint(equalToConstant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -6)
        ])
        cell.toolTip = name
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updating, rows.indices.contains(table.selectedRow) else { return }
        switch rows[table.selectedRow] {
        case .set(let id):
            guard let set = editor.sets.first(where: { $0.id == id }) else { return }
            editor.selectSet(set)
            navigation.page = .sets
        case .page(let page): navigation.page = page
        case .settings: break
        }
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard case .set(let id) = rows[row] else { return nil }
        return id.uuidString as NSString
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard operation == .above, row >= 0, row < editor.sets.count,
              let text = info.draggingPasteboard.string(forType: .string), let id = UUID(uuidString: text),
              editor.sets.contains(where: { $0.id == id }) else { return [] }
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard row >= 0, row < editor.sets.count, let text = info.draggingPasteboard.string(forType: .string), let id = UUID(uuidString: text) else { return false }
        editor.moveSet(id: id, before: editor.sets[row].id)
        return true
    }
    @objc private func createSet() {
        if createPopover?.isShown == true { createPopover?.close(); return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: CreateSetPopover(editor: editor) { [weak self, weak popover] in
            self?.navigation.page = .sets
            popover?.close()
        } onCancel: { [weak popover] in popover?.close() })
        createPopover = popover
        popover.show(relativeTo: addButton.bounds, of: addButton, preferredEdge: .maxX)
    }
}

@MainActor
private final class WorkspaceContentController: NSHostingController<WorkspaceContentView> {
    init(model: TypingPetSettingsModel, todoStore: TodoStore, updater: UpdateController, editor: PackEditorModel, navigation: WorkspaceNavigation) {
        super.init(rootView: WorkspaceContentView(model: model, todoStore: todoStore, updater: updater, editor: editor, navigation: navigation))
        sizingOptions = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct WorkspaceContentView: View {
    @ObservedObject var model: TypingPetSettingsModel
    @ObservedObject var todoStore: TodoStore
    let updater: UpdateController
    @ObservedObject var editor: PackEditorModel
    @ObservedObject var navigation: WorkspaceNavigation
    var body: some View {
        Group {
            if navigation.page == .sets { NativeSetWorkspace(editor: editor) }
            else { NativeSettingsPages(model: model, todoStore: todoStore, updater: updater, navigation: navigation) }
        }
        .onReceive(model.$imageSets) { _ in editor.refresh() }
    }
}

private struct NativeSettingsPages: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var model: TypingPetSettingsModel
    @ObservedObject var todoStore: TodoStore
    let updater: UpdateController
    @ObservedObject var navigation: WorkspaceNavigation
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(navigation.page.title).font(.system(size: 22, weight: .semibold))
            Group {
                switch navigation.page {
                case .sets: EmptyView()
                case .appearance: GeneralSettingsView(model: model, updater: updater, scope: .pet)
                case .todos: TodoSettingsView(store: todoStore)
                case .general: GeneralSettingsView(model: model, updater: updater, scope: .system)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(22).background(Color(nsColor: .windowBackgroundColor)).tint(.teal)
        .environment(\.locale, localization.locale)
        .alert(L("Error"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L("OK")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct CreateSetPopover: View {
    @ObservedObject var editor: PackEditorModel
    let onCreated: () -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("New Set")).font(.headline)
            TextField(L("Pack Name"), text: $name).textFieldStyle(.roundedBorder).focused($focused).onSubmit(create)
            Text(L("Create an empty pack, then add your images.")).font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Create"), action: create).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 290).onAppear { focused = true }
    }
    private func create() {
        do { try editor.createPack(name: name); onCreated() }
        catch { self.error = error.localizedDescription }
    }
}
