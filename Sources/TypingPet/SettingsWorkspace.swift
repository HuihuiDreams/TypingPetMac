import AppKit
import Combine
import Darwin
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
    var tint: NSColor {
        switch self {
        case .sets: .systemTeal
        case .appearance: .systemBlue
        case .todos: .systemPurple
        case .general: .secondaryLabelColor
        }
    }
}

private final class SettingsToolbarTitleCell: NSTextFieldCell {
    override var cellSize: NSSize {
        let size = super.cellSize
        return NSSize(width: size.width + 24, height: size.height)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect).insetBy(dx: 12, dy: 0)
    }
}

@MainActor
private final class WorkspaceNavigation: ObservableObject {
    @Published private(set) var history: SettingsNavigationHistory
    init(initialSetID: UUID) { history = SettingsNavigationHistory(initial: .imageSet(initialSetID)) }
    var page: WorkspacePage {
        switch history.current {
        case .imageSet: .sets
        case .appearance: .appearance
        case .todos: .todos
        case .general: .general
        }
    }
    func visit(_ destination: SettingsDestination) {
        guard destination != history.current else { return }
        history.visit(destination)
    }
    func visit(_ page: WorkspacePage) {
        switch page {
        case .sets: break
        case .appearance: visit(SettingsDestination.appearance)
        case .todos: visit(SettingsDestination.todos)
        case .general: visit(SettingsDestination.general)
        }
    }
    func goBack() { history.goBack() }
    func goForward() { history.goForward() }
    func removeDeletedSets(validIDs: Set<UUID>, fallbackID: UUID) {
        history.removeDeletedSets(validIDs: validIDs, fallbackID: fallbackID)
    }
}

/// AppKit owns the actual window, toolbar, split divider, and sidebar selection.
/// The integrated preset gallery and keyboard editor are native SwiftUI views.
@MainActor
final class SettingsWorkspaceController: NSSplitViewController, NSToolbarDelegate, NSSplitViewDelegate {
    private let editor: PackEditorModel
    private let navigation: WorkspaceNavigation
    private let historyID = NSToolbarItem.Identifier("TypingPetSettingsHistory")
    private let historyControl = NSSegmentedControl()
    private let pageTitleID = NSToolbarItem.Identifier("TypingPetSettingsPageTitle")
    private let pageTitle = NSTextField(labelWithString: "")
    private var subscriptions = Set<AnyCancellable>()
    private var restoringHistory = false

    init(model: TypingPetSettingsModel, todoStore: TodoStore, updater: UpdateController) {
        editor = PackEditorModel(store: model.packStore, onChange: { reload in model.packDidChange(reload: reload) })
        navigation = WorkspaceNavigation(initialSetID: editor.selectedSetID)
        super.init(nibName: nil, bundle: nil)
        let sidebar = NSSplitViewItem(sidebarWithViewController: WorkspaceSidebarController(editor: editor, navigation: navigation))
        sidebar.minimumThickness = 240
        sidebar.maximumThickness = 320
        sidebar.canCollapse = false
        sidebar.canCollapseFromWindowResize = false
        sidebar.allowsFullHeightLayout = true
        sidebar.preferredThicknessFraction = 0.23
        let content = NSSplitViewItem(viewController: WorkspaceContentController(
            model: model, todoStore: todoStore, updater: updater, editor: editor, navigation: navigation))
        content.minimumThickness = 530
        addSplitViewItem(sidebar)
        addSplitViewItem(content)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.autosaveName = NSSplitView.AutosaveName("TypingPetSettingsSidebar")
        navigation.$history.sink { [weak self] history in
            guard let self else { return }
            if case .imageSet(let id) = history.current, let set = self.editor.sets.first(where: { $0.id == id }) {
                self.restoringHistory = true
                self.editor.selectSet(set)
                self.restoringHistory = false
            }
            self.updateToolbar(history: history)
        }.store(in: &subscriptions)
        editor.onSelectionChanged = { [weak self] id in
            guard let self, !self.restoringHistory else { return }
            self.navigation.visit(.imageSet(id))
        }
        editor.$sets.receive(on: DispatchQueue.main).sink { [weak self] sets in
            guard let self else { return }
            self.navigation.removeDeletedSets(validIDs: Set(sets.map(\.id)), fallbackID: self.editor.selectedSetID)
        }.store(in: &subscriptions)
        editor.objectWillChange.debounce(for: .milliseconds(16), scheduler: DispatchQueue.main).sink { [weak self] in
            guard let self else { return }
            self.updateToolbar(history: self.navigation.history)
        }.store(in: &subscriptions)
        AppLocalization.shared.$language.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            self.updateToolbar(history: self.navigation.history)
        }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func splitView(_ splitView: NSSplitView, drawDividerIn rect: NSRect) {}

    override func viewWillAppear() {
        super.viewWillAppear()
        // Restore any saved width, but never restore a previously hidden sidebar.
        splitViewItems.first?.isCollapsed = false
    }

    override func toggleSidebar(_ sender: Any?) {
        splitViewItems.first?.isCollapsed = false
    }

    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        let native = super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        return native.isEmpty ? native : native.insetBy(dx: -3, dy: 0)
    }

    func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "TypingPetSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.sidebarTrackingSeparator, historyID, pageTitleID, .flexibleSpace] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .sidebarTrackingSeparator {
            return NSTrackingSeparatorToolbarItem(identifier: itemIdentifier, splitView: splitView, dividerIndex: 0)
        }
        if itemIdentifier == historyID {
            historyControl.segmentCount = 2
            historyControl.trackingMode = .momentary
            historyControl.segmentStyle = .automatic
            historyControl.setWidth(30, forSegment: 0)
            historyControl.setWidth(30, forSegment: 1)
            historyControl.target = self
            historyControl.action = #selector(navigateHistory(_:))
            updateToolbar(history: navigation.history)
            let item = NSToolbarItem(itemIdentifier: historyID)
            item.label = L("Navigate Settings")
            item.view = historyControl
            return item
        }
        guard itemIdentifier == pageTitleID else { return nil }
        updateToolbar(history: navigation.history)
        pageTitle.cell = SettingsToolbarTitleCell(textCell: pageTitle.stringValue)
        pageTitle.isEnabled = true
        pageTitle.isEditable = false
        pageTitle.isSelectable = false
        pageTitle.isBordered = false
        pageTitle.drawsBackground = false
        pageTitle.textColor = .labelColor
        pageTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        pageTitle.lineBreakMode = .byTruncatingTail
        pageTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let item = NSToolbarItem(itemIdentifier: pageTitleID)
        item.label = L("Settings")
        item.view = pageTitle
        return item
    }

    private func updateToolbar(history: SettingsNavigationHistory) {
        let page: WorkspacePage
        switch history.current {
        case .imageSet: page = .sets
        case .appearance: page = .appearance
        case .todos: page = .todos
        case .general: page = .general
        }
        if case .imageSet(let id) = history.current, let set = editor.sets.first(where: { $0.id == id }) {
            pageTitle.stringValue = editor.configuration(for: set).name
        } else {
            pageTitle.stringValue = page.title
        }
        pageTitle.setAccessibilityLabel(pageTitle.stringValue)
        guard historyControl.segmentCount == 2 else { return }
        historyControl.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: L("Back")), forSegment: 0)
        historyControl.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: L("Forward")), forSegment: 1)
        historyControl.setEnabled(history.canGoBack, forSegment: 0)
        historyControl.setEnabled(history.canGoForward, forSegment: 1)
        historyControl.setToolTip(L("Back"), forSegment: 0)
        historyControl.setToolTip(L("Forward"), forSegment: 1)
        historyControl.setAccessibilityLabel(L("Navigate Settings"))
        view.window?.toolbar?.items.first(where: { $0.itemIdentifier == historyID })?.label = L("Navigate Settings")
        view.window?.toolbar?.items.first(where: { $0.itemIdentifier == pageTitleID })?.label = pageTitle.stringValue
    }

    @objc private func navigateHistory(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { navigation.goBack() }
        else if sender.selectedSegment == 1 { navigation.goForward() }
    }
}

@MainActor
private final class SidebarBrandView: NSStackView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
}

@MainActor
private final class SidebarSetCellView: NSTableCellView {
    let menuButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    var isRowSelected = false { didSet { updateMenuVisibility() } }
    var supportsSetMenu = false { didSet { updateMenuVisibility() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; updateMenuVisibility() }
    override func mouseExited(with event: NSEvent) { isHovered = false; updateMenuVisibility() }
    private func updateMenuVisibility() { menuButton.isHidden = !(supportsSetMenu && (isHovered || isRowSelected)) }
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
    private let brandArtwork = NSImageView()
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
        brandArtwork.image = editor.cover(for: editor.store.library.activeSet) ?? NSImage()
        brandArtwork.imageScaling = .scaleProportionallyUpOrDown
        brandArtwork.setAccessibilityHidden(true)
        brandArtwork.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([brandArtwork.widthAnchor.constraint(equalToConstant: 32), brandArtwork.heightAnchor.constraint(equalToConstant: 32)])
        brandLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let brand = SidebarBrandView(views: [brandArtwork, brandLabel])
        brand.spacing = 8
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
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSetFromDoubleClick(_:))
        table.setAccessibilityLabel(L("Set Management"))
        table.registerForDraggedTypes([.string])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        for child in [brand, heading, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            brand.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            brand.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            brand.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            heading.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
        editor.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in self?.reload() }.store(in: &subscriptions)
        navigation.$history.map(\.current).removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        AppLocalization.shared.$language.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        reload()
    }

    private func reload() {
        guard isViewLoaded else { return }
        updating = true
        defer { updating = false }
        brandArtwork.image = editor.cover(for: editor.store.library.activeSet) ?? NSImage()
        titleLabel.stringValue = L("Set Management")
        addButton.setAccessibilityLabel(L("New Set"))
        addButton.toolTip = L("New Set")
        addButton.isEnabled = editor.canEdit
        rows = editor.sets.map { .set($0.id) } + [.settings] + [WorkspacePage.appearance, .todos, .general].map(Row.page)
        table.reloadData()
        let desired: Row = navigation.page == .sets ? .set(editor.selectedSetID) : .page(navigation.page)
        if let row = rows.firstIndex(of: desired) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rows[row] == .settings ? 36 : 38 }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows[row] == .settings }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row] != .settings }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if rows[row] == .settings {
            let group = NSView()
            let label = NSTextField(labelWithString: L("Settings"))
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            group.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 16),
                label.centerYAnchor.constraint(equalTo: group.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: group.trailingAnchor, constant: -16)
            ])
            return group
        }
        let isSetRow: Bool
        if case .set = rows[row] { isSetRow = true } else { isSetRow = false }
        let cell: NSTableCellView = isSetRow ? SidebarSetCellView() : NSTableCellView()
        let name: String
        let symbol: String
        var presetArtwork: NSImage?
        var iconTint = NSColor.secondaryLabelColor
        var active = false
        switch rows[row] {
        case .set(let id):
            guard let set = editor.sets.first(where: { $0.id == id }) else { return cell }
            name = editor.configuration(for: set).name
            symbol = "shippingbox"
            presetArtwork = editor.cover(for: set)
            active = id == editor.activeSetID
        case .settings: name = L("Settings"); symbol = ""; presetArtwork = nil
        case .page(let page): name = page.title; symbol = page.symbol; presetArtwork = nil; iconTint = page.tint
        }
        let label = NSTextField(labelWithString: name)
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: rows[row] == .settings ? 11 : 13)
        label.textColor = rows[row] == .settings ? .secondaryLabelColor : .labelColor
        cell.textField = label
        let image = NSImageView(image: presetArtwork ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.imageScaling = .scaleProportionallyUpOrDown
        if presetArtwork != nil {
            image.wantsLayer = true
            image.layer?.cornerRadius = 4
            image.layer?.masksToBounds = true
        } else {
            image.contentTintColor = iconTint
            image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        }
        cell.imageView = image
        let check = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: L("In Use")) ?? NSImage())
        check.contentTintColor = .controlAccentColor
        check.isHidden = !active
        check.setAccessibilityLabel(L("In Use"))
        for child in [image, label, check] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
        let iconDimension: CGFloat = presetArtwork == nil ? 20 : 24
        var constraints = [
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: iconDimension), image.heightAnchor.constraint(equalToConstant: iconDimension),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: rows[row] == .settings ? 0 : 8), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            check.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: active ? 14 : 0), check.heightAnchor.constraint(equalToConstant: 14)
        ]
        if let setCell = cell as? SidebarSetCellView, case .set(let id) = rows[row], let set = editor.sets.first(where: { $0.id == id }) {
            setCell.isRowSelected = table.selectedRow == row
            setCell.supportsSetMenu = !set.isBuiltIn
            if !set.isBuiltIn {
                setCell.menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("Set Options"))
                setCell.menuButton.bezelStyle = .inline
                setCell.menuButton.isBordered = false
                setCell.menuButton.contentTintColor = .secondaryLabelColor
                setCell.menuButton.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
                setCell.menuButton.target = self
                setCell.menuButton.action = #selector(showSetMenu(_:))
                setCell.menuButton.setAccessibilityLabel(L("Set Options"))
                setCell.menuButton.toolTip = L("Set Options")
                setCell.menuButton.translatesAutoresizingMaskIntoConstraints = false
                setCell.addSubview(setCell.menuButton)
                constraints += [
                    setCell.menuButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    setCell.menuButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    setCell.menuButton.widthAnchor.constraint(equalToConstant: 22),
                    setCell.menuButton.heightAnchor.constraint(equalToConstant: 22),
                    check.trailingAnchor.constraint(equalTo: setCell.menuButton.leadingAnchor, constant: -3),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -5)
                ]
            } else {
                constraints += [
                    check.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -6)
                ]
            }
        } else {
            constraints += [
                check.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -6)
            ]
        }
        NSLayoutConstraint.activate(constraints)
        cell.toolTip = name
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        for row in 0..<table.numberOfRows {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarSetCellView)?.isRowSelected = row == table.selectedRow
        }
        guard !updating, rows.indices.contains(table.selectedRow) else { return }
        switch rows[table.selectedRow] {
        case .set(let id):
            guard let set = editor.sets.first(where: { $0.id == id }) else { return }
            editor.selectSet(set)
            navigation.visit(.imageSet(id))
        case .page(let page):
            navigation.visit(page)
        case .settings: break
        }
    }
    @objc private func showSetMenu(_ sender: NSButton) {
        guard let rawID = sender.identifier?.rawValue, let id = UUID(uuidString: rawID),
              let set = editor.sets.first(where: { $0.id == id }), !set.isBuiltIn else { return }
        let menu = NSMenu()
        let use = NSMenuItem(title: L("Use This Set"), action: #selector(useSetFromMenu(_:)), keyEquivalent: "")
        use.attributedTitle = NSAttributedString(string: use.title, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        use.target = self
        use.representedObject = id
        use.isEnabled = id != editor.activeSetID
        menu.addItem(use)
        menu.addItem(.separator())
        let rename = NSMenuItem(title: L("Rename"), action: #selector(renameSetFromMenu(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = id
        menu.addItem(rename)
        let delete = NSMenuItem(title: L("Delete"), action: #selector(deleteSetFromMenu(_:)), keyEquivalent: "")
        delete.target = self
        delete.representedObject = id
        menu.addItem(delete)
        if let event = NSApp.currentEvent { NSMenu.popUpContextMenu(menu, with: event, for: sender) }
    }
    @objc private func openSetFromDoubleClick(_ sender: NSTableView) {
        guard rows.indices.contains(sender.clickedRow), case .set(let id) = rows[sender.clickedRow],
              let set = editor.sets.first(where: { $0.id == id }) else { return }
        useSet(set)
    }
    @objc private func useSetFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let set = editor.sets.first(where: { $0.id == id }) else { return }
        useSet(set)
    }
    private func useSet(_ set: PetImageSet) {
        editor.selectSet(set)
        navigation.visit(.imageSet(set.id))
        editor.activate(set)
    }
    @objc private func renameSetFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let set = editor.sets.first(where: { $0.id == id }) else { return }
        editor.renamePack(set)
    }
    @objc private func deleteSetFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let set = editor.sets.first(where: { $0.id == id }) else { return }
        editor.removePack(set)
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
        let host = NSHostingController(rootView: CreateSetPopover(editor: editor) { [weak self, weak popover] in
            if let self { self.navigation.visit(.imageSet(self.editor.selectedSetID)) }
            popover?.close()
        } onCancel: { [weak popover] in popover?.close() })
        // Size before showing so the arrow stays centered on the add button.
        host.sizingOptions = []
        let size = host.sizeThatFits(in: CGSize(width: 360, height: 600))
        host.view.setFrameSize(size)
        popover.contentViewController = host
        popover.contentSize = size
        host.rootView.onContentSizeChange = { [weak self, weak host, weak popover] in
            DispatchQueue.main.async {
                guard let self, let host, let popover, popover.isShown else { return }
                let size = host.sizeThatFits(in: CGSize(width: 360, height: 600))
                guard size != popover.contentSize else { return }
                host.view.setFrameSize(size)
                popover.contentSize = size
                popover.show(relativeTo: self.addButton.bounds, of: self.addButton, preferredEdge: .maxX)
            }
        }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsLinksFooter()
        }
        .onReceive(model.$imageSets) { _ in editor.refresh() }
    }
}

private struct SettingsLinksFooter: View {
    private let supportEmail = "support@miel.ing"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L("Unknown")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            links(showsLabels: true).fixedSize()
            links(showsLabels: false).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func links(showsLabels: Bool) -> some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            iconLink("Website", url: URL(string: "https://typing-pet.miel.ing"), symbol: "globe", showsLabel: showsLabels)
            iconLink("GitHub", url: URL(string: "https://github.com/ynifamily3"), symbol: "chevron.left.forwardslash.chevron.right", showsLabel: showsLabels)
            iconLink("Repository", url: URL(string: "https://github.com/ynifamily3/TypingPetMac"), symbol: "shippingbox", showsLabel: showsLabels)
            iconLink("X", url: URL(string: "https://x.com/miel_ggyu"), symbol: nil, showsLabel: showsLabels)
            iconLink("Write an email", url: feedbackMailURL, symbol: "envelope", showsLabel: showsLabels)
            HStack(spacing: 6) {
                Text("v\(appVersion)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(L(AppEnvironment.isDevelopment ? "Development" : "Production"))
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppEnvironment.isDevelopment ? Color.orange.opacity(0.16) : Color.accentColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(AppEnvironment.isDevelopment ? Color.orange : Color.accentColor)
            }
            .padding(.leading, 4)
            .help(L("Current version %1$@", appVersion))
        }
    }

    private func iconLink(_ title: String, url: URL?, symbol: String?, showsLabel: Bool) -> some View {
        Group {
            if let url {
                Link(destination: url) {
                    Group {
                        if let symbol {
                            if showsLabel { Label(L(title), systemImage: symbol) }
                            else { Image(systemName: symbol) }
                        } else {
                            HStack(spacing: 6) {
                                XBrandMark().fill(.foreground).frame(width: 15, height: 15)
                                if showsLabel { Text(L(title)) }
                            }
                        }
                    }.fixedSize()
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.secondary)
        .help(L(title))
        .accessibilityLabel("\(L("Creator: Miel")) · \(L(title))")
    }

    private var feedbackMailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: L("Typing Pet feedback")),
            URLQueryItem(name: "body", value: feedbackMailBody)
        ]
        return components.url
    }

    private var feedbackMailBody: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? L("Unknown")
        let build = info["CFBundleVersion"] as? String ?? L("Unknown")
        var modelSize = 0
        sysctlbyname("hw.model", nil, &modelSize, nil, 0)
        var modelBuffer = [CChar](repeating: 0, count: max(modelSize, 1))
        if modelSize > 0 { _ = sysctlbyname("hw.model", &modelBuffer, &modelSize, nil, 0) }
        let deviceModel = modelSize > 0 ? String(cString: modelBuffer) : L("Unknown")
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = L("Unknown")
        #endif
        return "\(L("Describe the bug or question here."))\n\n---\n\(L("App")): Typing Pet \(version) (\(build))\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n\(L("Device model")): \(deviceModel)\n\(L("Architecture")): \(architecture)"
    }
}

/// Official X logo geometry from X Corp.'s brand artwork, sourced via Wikimedia Commons.
private struct XBrandMark: Shape {
    private let contours: [[CGPoint]] = [
        [
            CGPoint(x: 21.742, y: 21.75), CGPoint(x: 14.179, y: 10.571),
            CGPoint(x: 21.235, y: 2.25), CGPoint(x: 18.779, y: 2.25),
            CGPoint(x: 13.088, y: 8.964), CGPoint(x: 8.548, y: 2.25),
            CGPoint(x: 2.359, y: 2.25), CGPoint(x: 9.649, y: 13.026),
            CGPoint(x: 2.25, y: 21.75), CGPoint(x: 4.706, y: 21.75),
            CGPoint(x: 10.741, y: 14.632), CGPoint(x: 15.559, y: 21.75),
            CGPoint(x: 21.75, y: 21.75)
        ],
        [
            CGPoint(x: 7.739, y: 3.818), CGPoint(x: 18.81, y: 20.182),
            CGPoint(x: 16.363, y: 20.182), CGPoint(x: 5.29, y: 3.818),
            CGPoint(x: 7.737, y: 3.818)
        ]
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for contour in contours {
            guard let first = contour.first else { continue }
            path.move(to: CGPoint(x: rect.minX + first.x * rect.width / 24,
                                  y: rect.minY + first.y * rect.height / 24))
            for point in contour.dropFirst() {
                path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width / 24,
                                         y: rect.minY + point.y * rect.height / 24))
            }
            path.closeSubpath()
        }
        return path
    }
}

private struct NativeSettingsPages: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var model: TypingPetSettingsModel
    @ObservedObject var todoStore: TodoStore
    let updater: UpdateController
    @ObservedObject var navigation: WorkspaceNavigation
    var body: some View {
        Group {
                switch navigation.page {
                case .sets: EmptyView()
                case .appearance: GeneralSettingsView(model: model, updater: updater, scope: .pet)
                case .todos: TodoSettingsView(store: todoStore)
                case .general: GeneralSettingsView(model: model, updater: updater, scope: .system)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
    var onContentSizeChange: () -> Void = {}
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("New Set")).font(.headline)
            TextField(L("Pack Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: name) { value in
                    let limited = TodoTitlePolicy.limitedDraft(value)
                    if limited != value { name = limited }
                }
                .onSubmit(create)
            Text(L("Create an empty pack, then add your images.")).font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Create"), action: create).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 290).onAppear { focused = true }
            .onChange(of: error) { _ in onContentSizeChange() }
    }
    private func create() {
        do { try editor.createPack(name: name); onCreated() }
        catch { self.error = error.localizedDescription }
    }
}
