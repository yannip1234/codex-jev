import Foundation
import Testing
@testable import JevCodex

@Test @MainActor func outgoingMessageRemovesOnlyVerifiedPassagesAndArchivesOriginal() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    var calls = 0
    let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { _, questions in
        calls += 1
        return Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, $0 == "drop_1" || $0.hasPrefix("verify_") ? 1.0 : 0.0) })
    })
    let original = "Build a native model picker.\n" + String(repeating: "This sentence repeats background already covered by the first instruction, and adds nothing; ", count: 8) + "\nKeep Shift-Return as a newline."
    let result = await compressor.compress(original)
    #expect(calls == 2)
    #expect(result.text == "Build a native model picker.\nKeep Shift-Return as a newline.")
    #expect(result.savedEstimate > 0 && result.apiCalls == 2)
    let archive = try #require(result.archive)
    let record = try JSONDecoder().decode(MessageCompressionRecord.self, from: Data(contentsOf: archive))
    #expect(record.original == original && record.sent == result.text)
    #expect((try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test @MainActor func outgoingMessageFallsBackOnFailedVerificationAndAPIError() async {
    let text = "Build a picker.\n" + String(repeating: "Background filler; ", count: 30) + "\nPreserve accessibility."
    let compressor = MessageCompressor(key: { "test-key" }, judge: { _, questions in
        Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, $0 == "drop_1" ? 1.0 : 0.0) })
    })
    let failed = await compressor.compress(text)
    #expect(failed.text == text && failed.archive == nil && failed.apiCalls == 2)
    let offline = MessageCompressor(key: { "test-key" }, judge: { _, _ in throw URLError(.timedOut) })
    let result = await offline.compress(text)
    #expect(result.text == text && result.apiCalls == 1 && result.status.contains("unavailable"))
}

@Test @MainActor func outgoingMessageChecksShortMessagesAndReportsMissingKey() async {
    var calls = 0
    let compressor = MessageCompressor(key: { "test-key" }, judge: { _, questions in
        calls += 1
        return Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, 0.0) })
    })
    let short = await compressor.compress("hello")
    #expect(calls == 1 && short.text == "hello" && short.status.contains("unchanged"))
    let missing = await MessageCompressor(key: { nil }).compress("hello")
    #expect(missing.text == "hello" && missing.apiCalls == 0 && missing.status.contains("API key"))
}

@Test @MainActor func outgoingMessageProtectsExactDetailsAndRejectsMalformedScores() async {
    let text = "Do not modify auth.swift.\nUse exactly 42 workers.\nCopy `foo --bar` unchanged.\nKeep https://example.com/a."
    let compressor = MessageCompressor(key: { "test-key" }, judge: { _, questions in
        Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, 1.0) })
    })
    #expect(await compressor.compress(text).text == text)
    let malformed = MessageCompressor(key: { "test-key" }, judge: { _, _ in [:] })
    #expect(await malformed.compress(text).text == text)
}

@Test @MainActor func liveOutgoingMessageCompactionWhenConfigured() async throws {
    guard ProcessInfo.processInfo.environment["JEV_TEST_MESSAGE_API"] == "1" else { return }
    let prompt = "Build a native model picker.\n" + String(repeating: "Thank you very much for your help and your time; I appreciate your assistance and I am grateful for the effort.\n", count: 6) + "Keep Shift-Return as a newline."
    let result = await MessageCompressor().compress(prompt)
    print("Live Jev message check: \(result.status); API requests: \(result.apiCalls)")
    #expect(result.apiCalls == 2 && result.savedEstimate > 0)
    #expect(result.text.contains("Build a native model picker.") && result.text.contains("Keep Shift-Return as a newline."))
}

@Test @MainActor func outgoingMessageDuplicateFallbackRetainsEveryDistinctPassage() async {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let repeated = "Thank you very much for assisting with this request; I appreciate the effort.\n"
    let source = "Build a model picker.\n" + String(repeating: repeated, count: 5) + "Preserve accessibility."
    let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { _, questions in
        Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, $0.hasPrefix("drop_") ? 0.96 : 0.2) })
    })
    // Keep a unique protected requirement so the proposed removal isn't empty.
    let result = await compressor.compress(source + "\nDo not remove keyboard support.")
    #expect(result.text == "Build a model picker.\n" + repeated + "Preserve accessibility.\nDo not remove keyboard support.")
    #expect(result.savedEstimate > 0)
}

@Test @MainActor func outgoingMessageBypassesDisabledOrOversizeMessagesWithoutAPI() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    var calls = 0
    let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { _, _ in calls += 1; return [:] })
    let settings = SettingsStore(home: home)
    settings.messageCompressionEnabled = false; settings.saveMessagePreference()
    let disabled = await compressor.compress("Test prompt")
    #expect(disabled.text == "Test prompt" && disabled.status.contains("off"))
    #expect(!SettingsStore(home: home).messageCompressionEnabled)
    settings.messageCompressionEnabled = true; settings.saveMessagePreference()
    let large = String(repeating: "a", count: 40_001)
    let oversized = await compressor.compress(large)
    #expect(oversized.text == large && oversized.status.contains("40 KB"))
    #expect(calls == 0)
    let unicode = String(repeating: "こんにちは。\n", count: 80)
    let pieces = MessageCompressor.passages(unicode)
    #expect(pieces.count <= 48 && pieces.joined() == unicode)
}
