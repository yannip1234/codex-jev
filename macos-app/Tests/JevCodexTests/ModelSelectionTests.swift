import Foundation
import Testing
@testable import JevCodex

private func catalogModel(_ id: String, defaultModel: Bool = false, defaultEffort: String = "high",
                          efforts: [String] = ["low", "high", "ultra"], hidden: Bool = false) throws -> HarnessModel {
    let data = try JSONSerialization.data(withJSONObject: ["id": id, "model": "wire-\(id)",
        "displayName": "Model \(id)", "description": "Test model", "hidden": hidden, "isDefault": defaultModel,
        "defaultReasoningEffort": defaultEffort,
        "supportedReasoningEfforts": efforts.map { ["reasoningEffort": $0, "description": "Effort \($0)"] }])
    return try JSONDecoder().decode(HarnessModel.self, from: data)
}

@Test @MainActor func modelPreferencesFollowCatalogAndRecoverStaleChoices() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("model-preferences.json")
    let first = try catalogModel("first", defaultModel: true)
    let second = try catalogModel("second", defaultEffort: "medium", efforts: ["medium", "max"])
    let store = ModelSelection(url: url)
    store.updateCatalog([try catalogModel("hidden", hidden: true), first, second])
    #expect(store.models == [first, second])
    #expect(store.modelID == "first" && store.effort == "high")
    store.selectEffort("ultra")
    store.selectEffort("unsupported")
    #expect(store.effort == "ultra")
    let restored = ModelSelection(url: url)
    restored.updateCatalog([first, second])
    #expect(restored.modelID == "first" && restored.effort == "ultra")
    restored.selectModel("second")
    #expect(restored.effort == "medium")
    restored.reset()
    #expect(restored.modelID == "first" && restored.effort == "high")
    restored.updateCatalog([second])
    #expect(restored.modelID == "second" && restored.effort == "medium")
    let changed = try catalogModel("second", defaultModel: true, defaultEffort: "missing", efforts: ["future-effort"])
    restored.updateCatalog([changed])
    #expect(restored.effort == "future-effort")
    restored.updateCatalog([try catalogModel("second", efforts: [])])
    #expect(restored.effort == nil)
    #expect(restored.turnParameters(threadID: "t", prompt: "hello")["effort"] == nil)
    restored.updateCatalog([])
    #expect(restored.selectedModel == nil)
    #expect(restored.turnParameters(threadID: "t", prompt: "hello")["model"] == nil)
}

@Test @MainActor func selectedModelAndEffortReachTurnStart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fake-model-server")
    let receipt = directory.appendingPathComponent("received.json")
    let source = #"""
    #!/usr/bin/python3
    import json, pathlib, sys
    def send(value): print(json.dumps(value), flush=True)
    def model(identifier, default):
        return {'id': identifier, 'model': 'wire-' + identifier, 'displayName': identifier,
                'description': '', 'hidden': False, 'isDefault': default, 'defaultReasoningEffort': 'low',
                'supportedReasoningEfforts': [{'reasoningEffort': x, 'description': x} for x in ['low', 'high']]}
    for line in sys.stdin:
        request = json.loads(line)
        method, params = request.get('method'), request.get('params', {})
        if method == 'initialized': continue
        result = {}
        if method == 'account/read': result = {'requiresOpenaiAuth': False}
        if method == 'model/list':
            result = {'data': [model('second' if params.get('cursor') else 'first', not params.get('cursor'))],
                      'nextCursor': None if params.get('cursor') else 'page-2'}
        if method == 'thread/start': result = {'thread': {'id': 'test-thread'}}
        if method == 'turn/start':
            pathlib.Path(__file__).with_name('received.json').write_text(json.dumps(params))
            result = {'turn': {'id': 'test-turn'}}
        send({'id': request['id'], 'result': result})
    """#
    try source.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    var duringCompression: (() -> Void)?
    let compressor = MessageCompressor(home: directory, key: { "test-key" }, judge: { _, questions in
        duringCompression?()
        return Dictionary(uniqueKeysWithValues: questions.keys.map { ($0, $0 == "drop_1" || $0.hasPrefix("verify_") ? 1.0 : 0.0) })
    })
    let model = ChatModel(indexURL: directory.appendingPathComponent("tasks.json"), messageCompressor: compressor)
    defer { model.server.stop() }
    await model.connect(executable: executable)
    #expect(model.error == nil)
    #expect(model.modelSelection.models.count == 2)
    model.modelSelection.selectModel("second")
    model.modelSelection.selectEffort("high")
    model.cwd = directory.path
    model.draft = "Say hello\n" + String(repeating: "Thank you very much for helping with this request; ", count: 12)
    duringCompression = { model.draft = "My next message" }
    await model.send()
    #expect(model.draft == "My next message")
    #expect(model.messageCompression?.savedEstimate ?? 0 > 0)
    let received = try JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [String: Any]
    #expect(received?["model"] as? String == "wire-second")
    #expect(received?["effort"] as? String == "high")
    #expect(received?["threadId"] as? String == "test-thread")
    #expect((received?["input"] as? [[String: Any]])?.first?["text"] as? String == "Say hello")
}
