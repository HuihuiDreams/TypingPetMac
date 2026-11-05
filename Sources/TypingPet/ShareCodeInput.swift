import AppKit
import SwiftUI

/// Six visible cells with native text editing, paste and keyboard navigation.
struct ShareCodeInput: NSViewRepresentable {
    @Binding var code: String

    func makeCoordinator() -> Coordinator { Coordinator(code: $code) }
    func makeNSView(context: Context) -> NSView {
        let stack = CodeStack()
        for index in 0..<6 {
            let field = NSTextField(string: "")
            field.cell = CodeCell(textCell: "")
            field.tag = index; field.delegate = context.coordinator
            field.isEditable = true; field.isSelectable = true
            field.font = .monospacedSystemFont(ofSize: 30, weight: .medium)
            field.alignment = .center; field.isBordered = false; field.drawsBackground = true
            field.backgroundColor = .controlBackgroundColor; field.focusRingType = .none
            field.maximumNumberOfLines = 1; field.cell?.usesSingleLineMode = true
            field.wantsLayer = true; field.layer?.cornerRadius = 13
            field.layer?.borderWidth = 1.5; field.layer?.borderColor = NSColor.gray.withAlphaComponent(0.35).cgColor
            field.setAccessibilityLabel(L("Share code character %1$@", String(index + 1)))
            field.setAccessibilityIdentifier("share-code-\(index + 1)")
            field.frame = NSRect(x: index * 66, y: 0, width: 58, height: 70)
            stack.addSubview(field); context.coordinator.fields.append(field)
        }
        stack.onAttach = { [weak coordinator = context.coordinator] in coordinator?.focus(0) }
        context.coordinator.render()
        return stack
    }
    func updateNSView(_ view: NSView, context: Context) {
        for field in context.coordinator.fields { field.isEnabled = context.environment.isEnabled }
        context.coordinator.code = $code
        context.coordinator.render()
    }

    final class CodeCell: NSTextFieldCell {
        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            var result = super.drawingRect(forBounds: rect)
            let inset = max(0, (result.height - cellSize.height) / 2)
            result.origin.y += inset; result.size.height -= inset * 2
            return result
        }
    }

    final class CodeStack: NSView {
        override var intrinsicContentSize: NSSize { NSSize(width: 388, height: 70) }
        override func layout() {
            super.layout()
            for (index, view) in subviews.enumerated() { view.frame = NSRect(x: index * 66, y: 0, width: 58, height: 70) }
        }
        var onAttach: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { DispatchQueue.main.async { [weak self] in self?.onAttach?() } }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var code: Binding<String>
        var fields: [NSTextField] = []
        init(code: Binding<String>) { self.code = code }
        func render() {
            let characters = Array(code.wrappedValue)
            for (index, field) in fields.enumerated() {
                let value = index < characters.count ? String(characters[index]) : ""
                if field.stringValue != value { field.stringValue = value }
            }
        }
        func focus(_ requested: Int) {
            let index = min(max(requested, 0), min(code.wrappedValue.count, 5))
            guard fields.indices.contains(index), fields[index].window != nil else { return }
            fields[index].window?.makeFirstResponder(fields[index])
            fields[index].selectText(nil)
            highlight(index)
        }
        private func highlight(_ index: Int?) {
            for (position, field) in fields.enumerated() {
                field.layer?.borderColor = (position == index ? NSColor.controlAccentColor : NSColor.gray.withAlphaComponent(0.35)).cgColor
                field.layer?.borderWidth = position == index ? 2 : 1.5
            }
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            highlight(field.tag)
            if field.tag > code.wrappedValue.count { focus(code.wrappedValue.count) }
            else if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: 0, length: editor.string.count) }
        }
        func controlTextDidEndEditing(_ notification: Notification) { highlight(nil) }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let input = LocalShareAPI.normalizedCode(field.stringValue)
            var characters = Array(code.wrappedValue)
            let start = input.count == 6 ? 0 : min(field.tag, characters.count)
            if input.isEmpty {
                if start < characters.count { characters.remove(at: start) }
            } else {
                for (offset, character) in input.enumerated() where start + offset < 6 {
                    if start + offset < characters.count { characters[start + offset] = character }
                    else { characters.append(character) }
                }
            }
            code.wrappedValue = String(characters.prefix(6)); render()
            focus(min(start + input.count, 5))
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }
            if command == #selector(NSResponder.deleteBackward(_:)) {
                var characters = Array(code.wrappedValue)
                let index = field.stringValue.isEmpty ? max(0, field.tag - 1) : field.tag
                if index < characters.count { characters.remove(at: index) }
                code.wrappedValue = String(characters); render(); focus(index)
                return true
            }
            if command == #selector(NSResponder.moveLeft(_:)) { focus(field.tag - 1); return true }
            if command == #selector(NSResponder.moveRight(_:)) { focus(field.tag + 1); return true }
            return false
        }
    }
}
