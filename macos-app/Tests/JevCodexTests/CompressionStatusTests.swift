import Foundation
import Testing
@testable import JevCodex

@Test func compressionStatusCountsOnlyPrivateRecoveryRecordNames() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let archives = home.appendingPathComponent("jev-originals")
    try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
    for name in ["tool-\(UUID().uuidString).txt", "tool-\(UUID().uuidString).txt",
                 "history-\(UUID().uuidString).txt", "unrelated.txt", "tool-invalid.txt"] {
        try Data("private source".utf8).write(to: archives.appendingPathComponent(name))
    }
    try FileManager.default.createDirectory(at: archives.appendingPathComponent("tool-\(UUID().uuidString).txt"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: archives.appendingPathComponent("history-\(UUID().uuidString).txt"),
                                             withDestinationURL: archives.appendingPathComponent("unrelated.txt"))
    let status = CompressionStatus.read(home: home)
    #expect(status.toolRecords == 2)
    #expect(status.historyRecords == 1)
    #expect(!status.unavailable)
}

@Test func compressionStatusDistinguishesNoRecordsFromUnreadableArchiveLocation() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let empty = CompressionStatus.read(home: home)
    #expect(empty.toolRecords == 0 && empty.historyRecords == 0 && !empty.unavailable)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try Data().write(to: home.appendingPathComponent("jev-originals"))
    #expect(CompressionStatus.read(home: home).unavailable)
}

@Test @MainActor func compressionConfigurationDoesNotTreatEmptyKeyFileAsConfigured() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let keyURL = home.appendingPathComponent("jev-api-key")
    try Data().write(to: keyURL)
    let settings = SettingsStore(home: home)
    #expect(settings.keyPresent && !settings.savedKeyValid)
    try Data("test-key".utf8).write(to: keyURL)
    settings.refreshCompressionStatus()
    #expect(settings.savedKeyValid)
    #expect(settings.compressionConfiguration == "Enabled · key configured")
    settings.preferences.tool_compression = false
    settings.preferences.compaction = false
    settings.messageCompressionEnabled = false
    #expect(settings.compressionConfiguration == "Disabled")
    #expect(settings.compressionStatus.toolRecords == 0 && settings.compressionStatus.historyRecords == 0)
}
