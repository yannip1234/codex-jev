import Foundation
import Testing
@testable import JevCodex

@Test func fragmentedUTF8Protocol() throws {
    var decoder = JSONLines()
    let bytes = Data("{\"delta\":\"hello 🌲\"}\n{\"id\":7}\n".utf8)
    var received: [[String: Any]] = []
    for byte in bytes { received += try decoder.append(Data([byte])) }
    #expect(received.count == 2)
    #expect(received[0]["delta"] as? String == "hello 🌲")
    #expect(received[1]["id"] as? Int == 7)
}

@Test @MainActor func privateKeyReplacementAndValidation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SettingsStore(home: directory)
    #expect(store.saveKey("test-first"))
    #expect(!store.saveKey("bad\nkey"))
    let keyURL = directory.appendingPathComponent("jev-api-key")
    #expect(try String(contentsOf: keyURL, encoding: .utf8) == "test-first")
    #expect(store.saveKey("test-replacement"))
    #expect(try String(contentsOf: keyURL, encoding: .utf8) == "test-replacement")
    let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    store.removeKey()
    #expect(!store.keyPresent)
    #expect(!FileManager.default.fileExists(atPath: keyURL.path))
}

@Test func historyItemsRetainCommandsAndDiffs() {
    #expect(ChatItem.parse(["id": "c", "type": "commandExecution", "command": "pwd",
        "aggregatedOutput": "/tmp/project", "status": "completed"]) ==
        ChatItem(id: "c", role: "Command", text: "pwd\n\n/tmp/project", status: "completed"))
    #expect(ChatItem.parse(["id": "f", "type": "fileChange", "changes": [["path": "a.swift", "diff": "+hello"]]]) ==
        ChatItem(id: "f", role: "File changes", text: "a.swift\n+hello"))
}

@Test @MainActor func compactionLifecycleAndStreamingState() {
    let model = ChatModel(indexURL: URL(fileURLWithPath: "/nonexistent/jev-test-index"))
    model.selectedID = "thread-1"
    model.server.onMessage?(["method": "turn/started", "params": ["threadId": "thread-1", "turn": ["id": "turn-1"]]])
    #expect(model.running)
    model.server.onMessage?(["method": "item/agentMessage/delta", "params": ["threadId": "thread-1", "itemId": "a", "delta": "hello"]])
    model.server.onMessage?(["method": "item/completed", "params": ["threadId": "thread-1", "item": ["id": "a", "type": "agentMessage", "text": "hello world"]]])
    #expect(model.items == [ChatItem(id: "a", role: "Codex", text: "hello world")])
    model.server.onMessage?(["method": "turn/completed", "params": ["threadId": "thread-1", "turn": ["id": "turn-1", "status": "completed"]]])
    #expect(!model.running)
}

@Test @MainActor func mockServerHandshakeStreamAndApproval() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fake-server")
    let source = #"""
    #!/usr/bin/python3
    import json, sys
    def send(value):
        print(json.dumps(value), flush=True)
    first = json.loads(sys.stdin.readline())
    assert first['method'] == 'initialize'
    send({'id': first['id'], 'result': {}})
    assert json.loads(sys.stdin.readline())['method'] == 'initialized'
    request = json.loads(sys.stdin.readline())
    send({'method': 'item/agentMessage/delta', 'params': {'delta': 'hello'}})
    send({'id': 17, 'method': 'item/commandExecution/requestApproval', 'params': {'command': 'pwd'}})
    approval = json.loads(sys.stdin.readline())
    assert approval == {'id': 17, 'result': {'decision': 'decline'}}
    send({'id': 'unknown-18', 'method': 'unsupported/action', 'params': {}})
    unsupported = json.loads(sys.stdin.readline())
    assert unsupported['id'] == 'unknown-18' and unsupported['error']['code'] == -32601
    send({'id': request['id'], 'result': {'approvalVerified': True}})
    sys.stdin.read()
    """#
    try source.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let server = AppServer()
    defer { server.stop() }
    var deltas = ""
    server.onMessage = { message in
        let method = message["method"] as? String ?? ""
        if method == "item/agentMessage/delta" {
            deltas += (message["params"] as? [String: Any])?["delta"] as? String ?? ""
        } else if let id = message["id"] {
            if method == "item/commandExecution/requestApproval" { try? server.respond(id: id, decision: "decline") }
            else { try? server.rejectUnsupported(id: id, method: method) }
        }
    }
    try await server.start(executable: executable)
    let result = try await server.request("exercise")
    #expect(result["approvalVerified"] as? Bool == true)
    #expect(deltas == "hello")
}

@Test @MainActor func realHarnessSmokeWhenConfigured() async throws {
    guard let path = ProcessInfo.processInfo.environment["JEV_TEST_BACKEND"] else { return }
    let server = AppServer()
    defer { server.stop() }
    try await server.start(executable: URL(fileURLWithPath: path))
    let catalog = try await server.request("model/list", ["limit": 100, "includeHidden": false])
    let page = try JSONDecoder().decode(ModelPage.self, from: JSONSerialization.data(withJSONObject: catalog))
    #expect(!page.data.isEmpty)
    let result = try await server.request("thread/start", ["cwd": FileManager.default.temporaryDirectory.path,
        "approvalPolicy": "on-request", "sandbox": "workspace-write", "ephemeral": true])
    #expect((result["thread"] as? [String: Any])?["id"] is String)
}
