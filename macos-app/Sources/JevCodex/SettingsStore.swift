import Foundation
import Darwin

struct JevPreferences: Codable {
    var tool_compression = true
    var compaction = true
}

/// Writes the replacement with private permissions before publishing its name.
func privateAtomicWrite(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".jev-\(UUID().uuidString)")
    let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { try? FileManager.default.removeItem(at: temporary) }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    try handle.write(contentsOf: data)
    try handle.synchronize()
    try handle.close()
    guard rename(temporary.path, url.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferences: JevPreferences
    @Published var keyPresent = false
    @Published private(set) var savedKeyValid = false
    @Published private(set) var compressionStatus = CompressionStatus()
    @Published var notice: String?
    let home: URL

    init(home: URL? = nil) {
        self.home = home ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let settings = self.home.appendingPathComponent("jev-settings.json")
        preferences = (try? JSONDecoder().decode(JevPreferences.self, from: Data(contentsOf: settings))) ?? JevPreferences()
        refreshKeyStatus()
        refreshCompressionStatus()
    }

    var environmentKeyPresent: Bool {
        Self.validKey(ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] ?? "")
    }

    func refreshKeyStatus() {
        let url = home.appendingPathComponent("jev-api-key")
        keyPresent = FileManager.default.fileExists(atPath: url.path)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        savedKeyValid = size > 0 && size <= 8192 && Self.validKey((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    var compressionConfiguration: String {
        guard preferences.tool_compression || preferences.compaction else { return "Disabled" }
        return environmentKeyPresent || savedKeyValid ? "Enabled · key configured" : "API key required"
    }

    func refreshCompressionStatus() {
        refreshKeyStatus()
        compressionStatus = CompressionStatus.read(home: home)
    }

    private static func validKey(_ value: String) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && key.utf8.count <= 8192
            && !key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) })
    }

    func savePreferences() {
        do {
            try privateAtomicWrite(JSONEncoder().encode(preferences), to: home.appendingPathComponent("jev-settings.json"))
            notice = "Settings saved."
        } catch { notice = error.localizedDescription }
    }

    func saveKey(_ value: String) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { notice = "Enter a Jev API key."; return false }
        guard key.utf8.count <= 8192,
              !key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            notice = "The key must be at most 8192 bytes and contain no whitespace or control characters."
            return false
        }
        do {
            try privateAtomicWrite(Data(key.utf8), to: home.appendingPathComponent("jev-api-key"))
            refreshKeyStatus()
            notice = "Jev API key saved."
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    func removeKey() {
        do {
            let url = home.appendingPathComponent("jev-api-key")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            refreshKeyStatus()
            notice = "Saved Jev API key removed."
        } catch { notice = error.localizedDescription }
    }
}
