import AppKit
import SwiftUI

// Row titles are one AppKit field that both shows and edits the title.
// It shows two lines with a trailing ellipsis, and a click puts the caret where it lands.
// Nothing is swapped in, AppKit never selects the whole title on a click, and the field reports
// the start and end of an edit itself instead of relying on SwiftUI focus state.
struct InlineTitleField: NSViewRepresentable {
    let title: String
    let font: NSFont
    let color: NSColor
    var displayLines = 2
    var editingLines = 4
    // A new nonzero value starts editing from a menu, with the caret at the end.
    var focusToken = 0
    var tooltip: String?
    let onBegin: () -> Void
    let onDraft: (String) -> Void
    // nil means the edit was cancelled.
    let onEnd: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TitleTextField {
        let field = TitleTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.truncatesLastVisibleLine = true
        field.lineBreakMode = .byWordWrapping
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.onFocus = { [weak coordinator = context.coordinator] in coordinator?.didFocus() }
        field.onEndEditing = { [weak coordinator = context.coordinator] in coordinator?.didEndEditing() }
        context.coordinator.field = field
        context.coordinator.observeResignKey()
        return field
    }

    func updateNSView(_ field: TitleTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if field.font != font { field.font = font }
        if field.textColor != color { field.textColor = color }
        field.maximumNumberOfLines = coordinator.isEditing ? editingLines : displayLines
        if !coordinator.isEditing, field.stringValue != title { field.stringValue = title }
        field.toolTip = tooltip
        if focusToken != coordinator.focusToken {
            coordinator.focusToken = focusToken
            if focusToken != 0 { DispatchQueue.main.async { coordinator.focusAtEnd() } }
        }
    }

    // Same line height as SwiftUI text at this font, capped at the line limit for the current mode.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: TitleTextField, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 240)
        let editing = context.coordinator.isEditing
        let text = editing ? (field.currentEditor()?.string ?? field.stringValue) : title
        let cell = NSTextFieldCell(textCell: text.isEmpty ? " " : text)
        cell.font = font
        cell.wraps = true
        cell.isBordered = false
        cell.isBezeled = false
        let full = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font))
        return CGSize(width: width, height: min(ceil(full), line * CGFloat(editing ? editingLines : displayLines)))
    }

    final class TitleTextField: NSTextField {
        var onFocus: (() -> Void)?
        var onEndEditing: (() -> Void)?
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocus?() }
            return accepted
        }
        // AppKit sends cursor updates to the view under the pointer, which is this field.
        override func cursorUpdate(with event: NSEvent) { NSCursor.iBeam.set() }
        // Also called when the field loses focus without any typing.
        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            onEndEditing?()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTitleField?
        weak var field: TitleTextField?
        var isEditing = false
        var focusToken = 0
        private var original = ""
        private var cancelled = false
        private var resignToken: NSObjectProtocol?

        deinit { if let resignToken { NotificationCenter.default.removeObserver(resignToken) } }

        // Clicking another app ends the edit and saves, instead of leaving an editor behind.
        func observeResignKey() {
            resignToken = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, self.isEditing, let window = self.field?.window, (note.object as? NSWindow) === window else { return }
                    window.makeFirstResponder(nil)
                }
            }
        }

        @MainActor func focusAtEnd() {
            guard let field, let window = field.window else { return }
            window.makeKey()
            guard window.makeFirstResponder(field), let editor = field.currentEditor() else { return }
            // Programmatic focus selects everything; move the caret in the same turn so no highlight flashes.
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }

        func didFocus() {
            guard let field, !isEditing else { return }
            isEditing = true
            cancelled = false
            original = field.stringValue
            field.maximumNumberOfLines = parent?.editingLines ?? 4
            parent?.onBegin()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let editor = field?.currentEditor() else { return }
            let limited = TodoTitlePolicy.limitedDraft(editor.string)
            if limited != editor.string {
                editor.string = limited
                editor.selectedRange = NSRange(location: (limited as NSString).length, length: 0)
            }
            parent?.onDraft(limited)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                cancelled = true
                textView.string = original
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) { didEndEditing() }

        func didEndEditing() {
            guard let field, isEditing else { return }
            isEditing = false
            field.maximumNumberOfLines = parent?.displayLines ?? 2
            if cancelled {
                field.stringValue = original
                parent?.onEnd(nil)
            } else {
                parent?.onEnd(field.stringValue)
            }
        }
    }
}
