import AppKit

// The app has no menu bar, so the standard editing shortcuts have no Edit menu to go through.
enum TextEditingShortcuts {
    // Key positions on an ANSI keyboard, used when a non-Latin input source reports another character.
    private static let ansiLetters: [UInt16: String] = [0: "a", 6: "z", 7: "x", 8: "c", 9: "v"]

    static func action(modifiers: NSEvent.ModifierFlags, characters: String?, keyCode: UInt16) -> Selector? {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        let typed = characters?.lowercased()
        let letter = typed.flatMap { $0.unicodeScalars.allSatisfy(\.isASCII) && !$0.isEmpty ? $0 : nil } ?? ansiLetters[keyCode]
        switch (flags, letter) {
        case ([.command], "a"): return #selector(NSText.selectAll(_:))
        case ([.command], "c"): return #selector(NSText.copy(_:))
        case ([.command], "v"): return #selector(NSText.paste(_:))
        case ([.command], "x"): return #selector(NSText.cut(_:))
        case ([.command], "z"): return Selector(("undo:"))
        case ([.command, .shift], "z"): return Selector(("redo:"))
        default: return nil
        }
    }

    // A hidden main menu also serves popovers and the settings window. It has no Quit shortcut,
    // so Command-Q typed into the bubble cannot quit the app by surprise.
    @MainActor static func installEditMenu(appName: String) {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: L("Quit %1$@", appName), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("Edit"))
        edit.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
