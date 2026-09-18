import SwiftUI
import AppKit

// Select the property wrapper explicitly; newer SDKs also declare a State macro
// whose plugin is not shipped with the standalone command-line toolchain.
private typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct JevCodexApp: App {
    @StateObject private var model = ChatModel()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        Window("Jev Codex", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                .task { await model.connect() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.server.stop() }
        }
        .defaultSize(width: 1320, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { model.newTask() }
                    .keyboardShortcut("n").disabled(model.busy || model.running)
            }
        }
        Settings { JevSettingsView(settings: settings) }
    }
}

struct JevSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ViewState private var key = ""

    var body: some View {
        Form {
            Section("Jev API key") {
                Text(settings.savedKeyValid ? "A saved Jev API key is configured." :
                     settings.keyPresent ? "The saved API key is empty or invalid. Replace it to enable Jev." : "No Jev API key is saved.")
                SecureField(settings.keyPresent ? "Replacement API key" : "API key", text: $key)
                HStack {
                    Button("Save Key") { if settings.saveKey(key) { key = "" } }.disabled(key.isEmpty)
                    Button("Remove Saved Key", role: .destructive) { settings.removeKey() }.disabled(!settings.keyPresent)
                }
                if settings.environmentKeyPresent {
                    Text("TYPESAFE_API_KEY is set in this app’s environment and takes precedence over the saved key.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("The key is stored in a private file in your Codex home and is never added to chat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Context compression") {
                Toggle("Compress tool output with Jev", isOn: $settings.preferences.tool_compression)
                Toggle("Compact conversations with Jev", isOn: $settings.preferences.compaction)
                LabeledContent("Configuration", value: settings.compressionConfiguration)
                Text("Jev compresses eligible plain-text tool output (8–64 KB), not ordinary chat replies. Conversation compaction can remove older tool exchanges; standard compaction runs when Jev cannot safely reduce them.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Changes apply to the next compression or compaction.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Jev activity") {
                if settings.compressionStatus.unavailable {
                    Text("Recovery records could not be read.")
                } else {
                    LabeledContent("Saved tool reductions", value: "\(settings.compressionStatus.toolRecords)")
                    LabeledContent("Saved history candidates", value: "\(settings.compressionStatus.historyRecords)")
                    if settings.compressionStatus.toolRecords == 0 && settings.compressionStatus.historyRecords == 0 {
                        Text("No Jev reductions recorded yet. Enabled settings do not mean every response is compressed.")
                            .font(.callout)
                    }
                }
                Text("Counts cover this Codex home. Recovery records do not measure token savings; a history candidate may be saved before it is applied. A configured key does not confirm service connectivity.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh status") { settings.refreshCompressionStatus() }
            }
            if let notice = settings.notice { Text(notice).font(.callout).textSelection(.enabled) }
        }
        .formStyle(.grouped).frame(width: 580, height: 700)
        .onAppear { settings.refreshCompressionStatus() }
        .onChange(of: settings.preferences.tool_compression) { _, _ in settings.savePreferences() }
        .onChange(of: settings.preferences.compaction) { _, _ in settings.savePreferences() }
        .onDisappear { key = "" }
    }
}
