import AppKit
import UniformTypeIdentifiers

@main @MainActor final class LauncherApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var status: NSStatusItem!
    private var modeItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var chooseItem: NSMenuItem!
    private var timer: Timer?
    private var busy = false
    private var trialApps: [NSRunningApplication] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = LauncherApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    private var configuration: LauncherConfiguration {
        let defaults = UserDefaults.standard.string(forKey: "officialAppPath")
        let override = ProcessInfo.processInfo.environment["JEV_OFFICIAL_APP"]
        let fallback = FileManager.default.fileExists(atPath: "/Applications/ChatGPT.app")
            ? "/Applications/ChatGPT.app" : "/Applications/Codex.app"
        return LauncherConfiguration(output: Bundle.main.bundleURL.deletingLastPathComponent(),
            home: FileManager.default.homeDirectoryForCurrentUser,
            officialApp: URL(fileURLWithPath: defaults ?? override ?? fallback))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        modeItem = NSMenuItem(title: "Codex–Jev", action: nil, keyEquivalent: "")
        modeItem.isEnabled = false; menu.addItem(modeItem)
        toggleItem = item("Use Codex–Jev", action: #selector(toggle), menu: menu)
        menu.addItem(.separator())
        item("Open Codex", action: #selector(openCodex), menu: menu)
        item("Open Jev Codex (settings)", action: #selector(openNative), menu: menu)
        item("Show Bridge Log", action: #selector(showLog), menu: menu)
        chooseItem = item("Choose Codex App…", action: #selector(chooseApp), menu: menu)
        menu.addItem(.separator())
        item("Quit Launcher", action: #selector(quit), menu: menu)
        status.menu = menu
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    @discardableResult private func item(_ title: String, action: Selector, menu: NSMenu) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: "")
        result.target = self; menu.addItem(result); return result
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        guard !busy else { return }
        let config = configuration
        trialApps = []
        if let identifier = Bundle(url: config.officialApp)?.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
                guard let executable = app.executableURL else { continue }
                let child = Process(), output = Pipe()
                child.executableURL = URL(fileURLWithPath: "/bin/ps")
                child.arguments = ["-ww", "-p", String(app.processIdentifier), "-o", "command="]
                child.standardOutput = output; child.standardError = FileHandle.nullDevice
                do {
                    try child.run()
                    let bytes = output.fileHandleForReading.readDataToEndOfFile()
                    child.waitUntilExit()
                    if child.terminationStatus == 0,
                       config.isTrialCommand(String(decoding: bytes, as: UTF8.self), executable: executable) {
                        trialApps.append(app)
                    }
                } catch { continue }
            }
        }
        let enabled = !trialApps.isEmpty
        status.button?.title = enabled ? "Jev ●" : "Jev ○"
        status.button?.toolTip = enabled ? "Codex–Jev is running" : "Codex–Jev is off"
        status.button?.setAccessibilityLabel(enabled ? "Codex–Jev On" : "Codex–Jev Off")
        modeItem.title = enabled ? "Codex–Jev: On" : "Codex–Jev: Off"
        toggleItem.state = enabled ? .on : .off; toggleItem.isEnabled = true
        chooseItem.isEnabled = !enabled
    }

    private func setBusy() {
        busy = true; toggleItem.isEnabled = false; chooseItem.isEnabled = false
        modeItem.title = "Switching…"; status.button?.title = "Jev …"
    }

    @objc private func toggle() {
        guard !busy else { return }
        refresh()
        if trialApps.isEmpty { launch(jev: true); return }
        let alert = NSAlert()
        alert.messageText = "Switch to standard Codex?"
        alert.informativeText = "This closes the Codex–Jev trial window and stops any work running there. Saved conversations remain. Regular Codex windows stay open."
        alert.addButton(withTitle: "Switch to Standard"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let closing = trialApps
        setBusy()
        // Ask only the positively identified trial applications to quit. Never force termination.
        guard closing.allSatisfy({ $0.terminate() }) else {
            finish(error: "Codex did not accept the quit request. Finish its current work and close the trial window, then try again.")
            return
        }
        Task {
            for _ in 0..<80 {
                if closing.allSatisfy(\.isTerminated) { launch(jev: false); return }
                try? await Task.sleep(for: .milliseconds(250))
            }
            finish(error: "The trial window is still open. Respond to any quit prompt in Codex; the launcher will not force it closed.")
        }
    }

    @objc private func openCodex() {
        guard !busy else { return }
        refresh()
        if let app = trialApps.first { app.activate(options: [.activateAllWindows]); return }
        launch(jev: false)
    }

    private func launch(jev: Bool) {
        let config = configuration
        guard FileManager.default.fileExists(atPath: config.officialApp.path) else {
            finish(error: "Choose your installed Codex application using Choose Codex App…"); return
        }
        if jev {
            guard config.requiredFiles.allSatisfy({ FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                finish(error: "Keep Codex Jev Launcher.app beside codex-jev-bridge, jev-message-filter, and JevCodex.app in the build output folder."); return
            }
            do { try FileManager.default.createDirectory(at: config.profile, withIntermediateDirectories: true) }
            catch { finish(error: error.localizedDescription); return }
        }
        setBusy()
        let options = NSWorkspace.OpenConfiguration()
        options.createsNewApplicationInstance = jev
        options.activates = true
        options.arguments = jev ? ["--user-data-dir=" + config.profile.path] : []
        options.environment = config.environment(jev: jev, inherited: ProcessInfo.processInfo.environment)
        NSWorkspace.shared.openApplication(at: config.officialApp, configuration: options) { [weak self] _, error in
            Task { @MainActor in self?.finish(error: error?.localizedDescription) }
        }
    }

    private func finish(error: String?) {
        busy = false; refresh()
        if let error {
            let alert = NSAlert(); alert.messageText = "Codex launcher"; alert.informativeText = error
            NSApp.activate(ignoringOtherApps: true); alert.runModal()
        }
    }

    @objc private func openNative() {
        NSWorkspace.shared.openApplication(at: configuration.nativeApp,
            configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error { Task { @MainActor in self?.finish(error: error.localizedDescription) } }
            }
    }

    @objc private func showLog() {
        let url = configuration.logURL(environment: ProcessInfo.processInfo.environment)
        guard FileManager.default.fileExists(atPath: url.path) else {
            finish(error: "No bridge log yet. Enable Codex–Jev and send a message first."); return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func chooseApp() {
        guard !busy && trialApps.isEmpty else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose the installed official Codex application."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "officialAppPath"); refresh()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
