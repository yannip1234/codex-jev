import AppKit

@main @MainActor final class DockApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared, delegate = DockApp()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), appMenu = NSMenu(), root = NSMenuItem()
        root.submenu = appMenu; menu.addItem(root); NSApp.mainMenu = menu
        for (title, action, shortcut) in [
            ("Open Codex with Jev", #selector(openCodex), "o"),
            ("Settings…", #selector(settings), ","),
            ("Quit Dock Launcher", #selector(quit), "q")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
            item.target = self; appMenu.addItem(item)
        }
        openCodex()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openCodex(); return false
    }

    @objc private func openCodex() { send("open") }
    @objc private func settings() { send("settings") }
    @objc private func quit() { NSApp.terminate(nil) }

    private func send(_ action: String) {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Codex Jev Launcher.app")
        let options = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([URL(string: "codex-jev://" + action)!], withApplicationAt: app, configuration: options) { _, error in
            if let error {
                Task { @MainActor in
                    let alert = NSAlert(); alert.messageText = "Cannot open Codex–Jev"
                    alert.informativeText = "Keep Codex Jev.app beside Codex Jev Launcher.app.\n\n" + error.localizedDescription
                    NSApp.activate(ignoringOtherApps: true); alert.runModal()
                }
            }
        }
    }
}
