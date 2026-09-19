import Foundation
import Testing
@testable import JevCodex

@Test @MainActor func outgoingWordsAllReachJevAndProtectionComesFromItsAnswers() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let settings = SettingsStore(home: home)
    settings.messageCompressionMode = .strict; settings.saveMessagePreference()
    let original = "Please really fix the picker; do not change `the API_KEY=42` or \"the exact title\".\n```sh\necho the value\n```\n    echo the other value\nKeep /tmp/the/file and https://example.com/the unchanged."
    var seen: [Int] = [], calls = 0
    let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { state, questions in
        calls += 1
        if let words = state["words"] as? [String: [String: Any]] {
            #expect(state["message"] as? String == original)
            var answers: [String: Double] = [:]
            for (id, _) in words {
                let i = Int(id.dropFirst())!
                seen.append(i)
                // Mock Jev marks the entire suffix verbatim; even low keep scores cannot remove it.
                answers["keep_\(i)"] = [2, 4].contains(i) ? 1 : 0
                answers["verbatim_\(i)"] = i >= 5 ? 1 : 0
            }
            #expect(Set(answers.keys) == Set(questions.keys))
            return answers
        }
        #expect(questions.count == 3)
        return Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, $0 == "verify_intent" ? 1.0 : 0.0) })
    })
    let result = await compressor.compress(original)
    #expect(result.text == "fix picker;" + String(original[original.range(of: " do not")!.lowerBound...]))
    #expect(seen.sorted() == Array(MessageWordSpans.index(original).indices))
    #expect(calls == 2 && result.savedEstimate > 0 && result.status.contains("Strict"))
    let archive = try #require(result.archive)
    let record = try JSONDecoder().decode(MessageCompressionRecord.self, from: Data(contentsOf: archive))
    #expect(record.original == original && record.sent == result.text)
    #expect((try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test @MainActor func allOccurrencesAcrossBatchesAreJudgedWithFullOriginal() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let original = (0..<300).map { "word\($0)" }.joined(separator: " ")
    var seen = Set<Int>(), calls = 0
    let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { state, questions in
        calls += 1
        if let words = state["words"] as? [String: [String: Any]] {
            #expect(state["message"] as? String == original && words.count <= 96)
            var answers: [String: Double] = [:]
            for id in words.keys {
                let i = Int(id.dropFirst())!
                #expect(seen.insert(i).inserted)
                answers["keep_\(i)"] = i == 299 ? 1 : 0
                answers["verbatim_\(i)"] = 0
            }
            return answers
        }
        #expect(state["candidate"] as? String == "word299")
        return Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, $0 == "verify_intent" ? 1.0 : 0.0) })
    })
    let result = await compressor.compress(original)
    #expect(seen == Set(0..<300) && calls == 5 && result.text == "word299")
}

@Test @MainActor func combinedVerificationFailureOrMalformedAnswerKeepsOriginal() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let settings = SettingsStore(home: home)
    settings.messageCompressionMode = .strict; settings.saveMessagePreference()
    let text = "Please kindly fix the picker."
    for score in [0.79, 0.99] {
        let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { state, questions in
            if state["words"] != nil {
                return questions.mapValues { instruction in
                    instruction.contains("`words.w2`") || instruction.contains("`words.w4`") ? 1 : 0
                }
            }
            return Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, $0 == "verify_intent" ? score : 0.0) })
        })
        let result = await compressor.compress(text)
        #expect(result.text == (score == 0.99 ? "fix picker." : text))
        #expect(result.apiCalls == 2)
    }
    for invalid in [Double.nan, -1, 2] {
        let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { _, q in q.mapValues { _ in invalid } })
        #expect(await compressor.compress(text).text == text)
    }
    let malformed = MessageCompressor(home: home, key: { "test-key" }, judge: { _, _ in [:] })
    #expect(await malformed.compress(text).text == text)
    let offline = MessageCompressor(home: home, key: { "test-key" }, judge: { _, _ in throw URLError(.timedOut) })
    #expect(await offline.compress(text).text == text)
}

@Test @MainActor func verificationRejectsConstraintAndLiteralLossEvenWhenTaskMatches() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let settings = SettingsStore(home: home)
    settings.messageCompressionMode = .strict; settings.saveMessagePreference()
    for failure in ["constraint_loss", "verbatim_loss"] {
        let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { state, q in
            if state["words"] != nil {
                return Dictionary(uniqueKeysWithValues: q.keys.map { ($0, $0 == "keep_2" ? 1.0 : 0.0) })
            }
            return Dictionary(uniqueKeysWithValues: q.keys.map { ($0, $0 == "verify_intent" || $0 == failure ? 1.0 : 0.0) })
        })
        let source = "Please preserve `exact_value`."
        let result = await compressor.compress(source)
        #expect(result.text == source && result.archive == nil && result.status.contains("preservation check failed"))
    }
}

@Test @MainActor func messagesBypassWhenDisabledMissingKeyOversizeOrContainingCredential() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    var calls = 0
    let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { _, _ in calls += 1; return [:] })
    let settings = SettingsStore(home: home)
    settings.messageCompressionEnabled = false; settings.saveMessagePreference()
    #expect(await compressor.compress("Test prompt").status.contains("off"))
    settings.messageCompressionEnabled = true; settings.saveMessagePreference()
    #expect(await compressor.compress(String(repeating: "a", count: 40_001)).status.contains("40 KB"))
    #expect(await compressor.compress("test-key").status.contains("credential"))
    #expect(await MessageCompressor(home: home, key: { nil }).compress("hello").status.contains("API key"))
    #expect(calls == 0)
}

@Test @MainActor func shortMessagesAreJudgedAndAmbiguousProtectionPreventsDeletion() async {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    var calls = 0
    let compressor = MessageCompressor(home: home, key: { "test-key" }, judge: { _, q in
        calls += 1
        return Dictionary(uniqueKeysWithValues: q.keys.map { ($0, $0.hasPrefix("verbatim_") ? 0.5 : 0) })
    })
    let result = await compressor.compress("hello")
    #expect(result.text == "hello" && result.status.contains("unchanged") && calls == 1)
}

@Test func wordCoordinatesPreserveUnicodeAndUntouchedWhitespace() {
    let text = "    👋 please\tfix\n    `a b` 日本語\n"
    let words = MessageWordSpans.index(text)
    #expect(words.map(\.text) == ["👋", "please", "fix", "`a", "b`", "日本語"])
    for word in words { #expect((text as NSString).substring(with: word.range) == word.text) }
    #expect(MessageWordSpans.removing([words[1].deletionRange], from: text) == "    👋 fix\n    `a b` 日本語\n")
    #expect(MessageWordSpans.removing([], from: text) == text)
}

@Test @MainActor func savedAppKeyWinsAndChangesApplyWithoutRestart() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = SettingsStore(home: home)
    #expect(MessageCompressor.resolvedKey(home: home, environmentKey: " env-secret ") == "env-secret")
    #expect(store.saveKey("saved-secret"))
    #expect(MessageCompressor.resolvedKey(home: home, environmentKey: "env-secret") == "saved-secret")
    #expect(store.saveKey("replacement-secret"))
    #expect(MessageCompressor.resolvedKey(home: home, environmentKey: "env-secret") == "replacement-secret")
    try privateAtomicWrite(Data("bad\nkey".utf8), to: home.appendingPathComponent("jev-api-key"))
    #expect(MessageCompressor.resolvedKey(home: home, environmentKey: "env-secret") == "env-secret")
    store.removeKey()
    #expect(MessageCompressor.resolvedKey(home: home, environmentKey: "env-secret") == "env-secret")
    #expect(MessageCompressor.resolvedKey(home: home, environmentKey: " ") == nil)
}

@Test @MainActor func messageModeMigrationPreservesDisabledSettingAndUnknownMode() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let file = home.appendingPathComponent("jev-message-settings.json")
    for json in [#"{"enabled":false}"#, #"{"enabled":false,"mode":"future"}"#] {
        try privateAtomicWrite(Data(json.utf8), to: file)
        let store = SettingsStore(home: home)
        #expect(!store.messageCompressionEnabled && store.messageCompressionMode == .balanced)
        store.messageCompressionMode = .strict; store.saveMessagePreference()
        let reload = SettingsStore(home: home)
        #expect(!reload.messageCompressionEnabled && reload.messageCompressionMode == .strict)
    }
}
