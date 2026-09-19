import AppKit

/// Accessory apps still need a main Edit menu for AppKit's standard key equivalents.
@MainActor enum SettingsEditingMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let application = NSMenuItem(); application.submenu = NSMenu(title: "Codex Jev")
        main.addItem(application)
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = .command
            edit.addItem(item)
        }
        let entry = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        entry.submenu = edit; main.addItem(entry)
        return main
    }
}
