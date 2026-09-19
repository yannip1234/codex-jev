import AppKit
import SwiftUI

@MainActor final class LauncherSettings: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private var store = SettingsStore()
    private let key = NSSecureTextField()
    private let keyStatus = NSTextField(wrappingLabelWithString: "")
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: "Save Key", target: nil, action: #selector(saveKey))
    private let remove = NSButton(title: "Remove Saved Key", target: nil, action: #selector(removeKey))
    private let messages = NSButton(checkboxWithTitle: "Compact outgoing messages", target: nil, action: #selector(saveMessages))
    private let usage = NSTextField(wrappingLabelWithString: "")
    private var usageTimer: Timer?
    private let mode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tools = NSButton(checkboxWithTitle: "Compress eligible tool output", target: nil, action: #selector(saveContext))
    private let history = NSButton(checkboxWithTitle: "Compact older tool exchanges", target: nil, action: #selector(saveContext))

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 780),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Codex–Jev Settings"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self; window.center()
        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Jev settings")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let label = NSTextField(labelWithString: "TypeSafe API key")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        key.placeholderString = "Paste a new or replacement API key"
        key.setAccessibilityLabel("TypeSafe API key"); key.delegate = self
        key.target = self; key.action = #selector(saveKey)
        key.translatesAutoresizingMaskIntoConstraints = false
        save.target = self; remove.target = self
        let buttons = NSStackView(views: [save, remove]); buttons.spacing = 10
        let heading = NSTextField(labelWithString: "Compression")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        for control in [messages, tools, history] { control.target = self }
        mode.addItems(withTitles: ["Balanced", "Strict (caveman)"])
        mode.setAccessibilityLabel("Outgoing message compaction mode")
        mode.target = self; mode.action = #selector(saveMode)
        let modeRow = NSStackView(views: [NSTextField(labelWithString: "Outgoing mode"), mode]); modeRow.spacing = 12
        let modeDetail = NSTextField(wrappingLabelWithString: "Jev decides which words are needed and which text must stay verbatim. Strict aims for terse messages; both modes check the combined result. History compaction has its own setting below.")
        modeDetail.font = .systemFont(ofSize: 12); modeDetail.textColor = .secondaryLabelColor
        let detail = NSTextField(wrappingLabelWithString:
            "Enabled compression sends eligible content to TypeSafe and incurs Jev usage. Your saved key takes priority over TYPESAFE_API_KEY. Changes apply to the next request; no Codex restart is needed.")
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        keyStatus.font = .systemFont(ofSize: 12); keyStatus.textColor = .secondaryLabelColor
        notice.font = .systemFont(ofSize: 12)
        usage.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        usage.setAccessibilityLabel("Token estimates before and after compaction")
        for view in [title, label, key, buttons, keyStatus, heading, messages, modeRow, modeDetail, tools, history, detail, usage, notice] {
            content.addArrangedSubview(view)
        }
        window.contentView?.addSubview(content)
        if let parent = window.contentView {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 24),
                content.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -24),
                content.topAnchor.constraint(equalTo: parent.topAnchor, constant: 24),
                content.bottomAnchor.constraint(lessThanOrEqualTo: parent.bottomAnchor, constant: -24),
                key.widthAnchor.constraint(equalTo: content.widthAnchor),
                modeDetail.widthAnchor.constraint(equalTo: content.widthAnchor),
                detail.widthAnchor.constraint(equalTo: content.widthAnchor),
                keyStatus.widthAnchor.constraint(equalTo: content.widthAnchor),
                usage.widthAnchor.constraint(equalTo: content.widthAnchor),
                notice.widthAnchor.constraint(equalTo: content.widthAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present() {
        if window?.isVisible != true {
            store = SettingsStore(); key.stringValue = ""; notice.stringValue = ""
            messages.state = store.messageCompressionEnabled ? .on : .off
            mode.selectItem(at: store.messageCompressionMode == .strict ? 1 : 0)
            tools.state = store.preferences.tool_compression ? .on : .off
            history.state = store.preferences.compaction ? .on : .off
        }
        refresh()
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage() }
        }
        showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { key.stringValue = ""; usageTimer?.invalidate() }
    func controlTextDidChange(_ notification: Notification) { refresh() }

    private func refresh() {
        store.refreshKeyStatus()
        refreshUsage()
        keyStatus.stringValue = store.savedKeyValid ? "Saved API key configured. The key is stored locally with private permissions." :
            store.environmentKeyPresent ? "Using TYPESAFE_API_KEY as a fallback. Save a key here to override it." :
            store.keyPresent ? "The saved key is invalid. Paste a replacement above." : "No API key configured."
        mode.isEnabled = store.messageCompressionEnabled
        save.isEnabled = !key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        remove.isEnabled = store.keyPresent
    }

    private func refreshUsage() {
        let counts = CompressionUsage.read(home: store.home)
        usage.stringValue = "Token estimates · Original → After · Saved\n"
            + "Outgoing: " + counts.outgoing.display + "\n"
            + "Tool output: " + counts.tools.display + "\n"
            + "History: " + counts.history.display + "\n"
            + "Total: " + counts.total.display + "\n\n"
            + "Cumulative processing estimates since tracking began; not billing totals. History can count retained text again. Earlier records without counts are excluded."
            + (counts.incomplete ? " Some log records could not be read." : "")
    }

    @objc private func saveKey() {
        if store.saveKey(key.stringValue) { key.stringValue = "" }
        notice.stringValue = store.notice ?? ""; refresh()
    }

    @objc private func removeKey() {
        store.removeKey(); key.stringValue = ""
        notice.stringValue = store.notice ?? ""; refresh()
    }

    @objc private func saveMessages() {
        store.messageCompressionEnabled = messages.state == .on; store.saveMessagePreference()
        notice.stringValue = store.notice ?? ""; refresh()
    }

    @objc private func saveMode() {
        store.messageCompressionMode = mode.indexOfSelectedItem == 1 ? .strict : .balanced
        store.saveMessagePreference(); notice.stringValue = store.notice ?? ""
    }

    @objc private func saveContext() {
        store.preferences.tool_compression = tools.state == .on
        store.preferences.compaction = history.state == .on
        store.savePreferences(); notice.stringValue = store.notice ?? ""
    }
}
