import Foundation
import Testing
@testable import JevCodex

@Test func contextStatusWaitsForCompletionAndHandlesFailure() {
    var state = ContextStatus()
    state.requested()
    #expect(state.isCompacting && state.completedCount == 0)
    state.consume(method: "item/completed", params: ["item": ["type": "commandExecution", "id": "c"]])
    #expect(state.isCompacting)
    state.consume(method: "item/completed", params: ["item": ["type": "contextCompaction", "id": "compact-1"]])
    state.consume(method: "item/completed", params: ["item": ["type": "contextCompaction", "id": "compact-1"]])
    #expect(!state.isCompacting && state.completedCount == 1)
    #expect(state.message?.contains("transcript stays visible") == true)
    state.consume(method: "thread/tokenUsage/updated", params: ["tokenUsage": ["last": ["inputTokens": 240]]])
    #expect(state.lastInputTokens == 240)
    state.requested()
    state.consume(method: "error", params: ["willRetry": true, "error": ["message": "retry"]])
    #expect(state.isCompacting)
    state.consume(method: "error", params: ["willRetry": false, "error": ["message": "offline"]])
    #expect(!state.isCompacting && state.message == "Compaction failed: offline")
}

@Test @MainActor func controlsReachHarnessAndPlanModeCanBeDisabled() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fake-controls-server")
    let source = #"""
    #!/usr/bin/python3
    import json, pathlib, sys
    def send(value): print(json.dumps(value), flush=True)
    log = pathlib.Path(__file__).with_name('requests.jsonl')
    for line in sys.stdin:
        request = json.loads(line)
        with log.open('a') as f: f.write(json.dumps(request)+'\n')
        method, p = request.get('method'), request.get('params', {})
        if method is None or method == 'initialized': continue
        result = {}
        if method == 'account/read': result = {'requiresOpenaiAuth': False}
        if method == 'model/list': result = {'data': [{'id':'test','model':'test','displayName':'Test','description':'','hidden':False,'isDefault':True,'defaultReasoningEffort':'high','supportedReasoningEfforts':[{'reasoningEffort':'high','description':''}]}], 'nextCursor':None}
        if method == 'thread/start': result = {'thread': {'id': 'controls-thread'}}
        if method == 'turn/start': result = {'turn': {'id': 'turn-1'}}
        if method == 'thread/goal/set': result = {'goal': {'objective':p.get('objective','Continue task'),'status':p['status'],'tokensUsed':0,'tokenBudget':p.get('tokenBudget')}}
        if method == 'thread/goal/set' and p['status'] == 'complete':
            response = {'id': request['id'], 'result': result}
            cleared = {'method':'thread/goal/cleared','params':{'threadId':'controls-thread'}}
            print(json.dumps(response)+'\n'+json.dumps(cleared), flush=True)
        else: send({'id':request['id'],'result':result})
    """#
    try source.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let model = ChatModel(indexURL: directory.appendingPathComponent("tasks.json"))
    defer { model.server.stop() }
    await model.connect(executable: executable)
    model.cwd = directory.path
    let file = directory.appendingPathComponent("quoted \" file.txt")
    try "Attachment content must not be pasted into the prompt".write(to: file, atomically: true, encoding: .utf8)
    model.addAttachments([file, file, directory])
    #expect(model.attachments.count == 2)
    model.planMode = true; model.approvalMode = .automatic; model.draft = "Plan only"
    await model.send()
    #expect(model.error == nil && model.attachments.isEmpty)
    func complete() {
        model.server.onMessage?(["method":"turn/completed", "params":["threadId":"controls-thread", "turn":["id":"turn-1", "status":"completed"]]])
    }
    complete()
    model.planMode = false; model.approvalMode = .ask; model.draft = "Implement"
    await model.send()
    complete()
    model.approvalMode = .full; model.draft = "Next"
    await model.send()
    complete()
    model.approvalMode = .ask
    await model.saveGoal(objective: "Continue task", tokenBudget: 2000)
    #expect(model.goal?.status == "active" && model.goal?.tokenBudget == 2000)
    await model.updateGoal(status: "paused")
    #expect(model.goal?.status == "paused")
    await model.updateGoal(status: "active")
    await model.updateGoal(status: "complete")
    #expect(model.goal == nil) // A newer clear notification wins over the RPC response.
    model.server.onMessage?(["id": "approval-1", "method": "item/commandExecution/requestApproval", "params": ["threadId": "controls-thread", "availableDecisions": ["accept", "cancel"]]])
    let approval = try #require(model.approvals.first)
    model.decide(approval, accept: false)
    model.server.onMessage?(["id": "question-1", "method": "item/tool/requestUserInput", "params": ["threadId":"controls-thread", "questions":[["id":"q", "header":"Choice", "question":"Which option?", "options":[["label":"A", "description":"Option A"]]]]]])
    let question = try #require(model.userQuestions.first)
    model.answerQuestions(question, answers: ["q":"A"])
    // A following RPC acts as a barrier: the fake server has recorded the response.
    _ = try await model.server.request("barrier")
    let requests = try String(contentsOf: directory.appendingPathComponent("requests.jsonl"), encoding: .utf8).split(separator: "\n").map {
        try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
    }
    let turns = requests.filter { $0["method"] as? String == "turn/start" }.map { $0["params"] as! [String: Any] }
    #expect(turns.count == 3)
    #expect((turns[0]["collaborationMode"] as? [String: Any])?["mode"] as? String == "plan")
    #expect(turns[0]["approvalsReviewer"] as? String == "auto_review")
    let inputs = try #require(turns[0]["input"] as? [[String: Any]])
    #expect(inputs.count == 3 && inputs[1]["text"] as? String != "Attachment content must not be pasted into the prompt")
    #expect((inputs[1]["text"] as? String)?.contains("quoted \\\" file.txt") == true)
    #expect((turns[1]["collaborationMode"] as? [String: Any])?["mode"] as? String == "default")
    #expect(turns[1]["approvalPolicy"] as? String == "on-request")
    #expect((turns[1]["sandboxPolicy"] as? [String: Any])?["type"] as? String == "workspaceWrite")
    #expect(turns[2]["approvalPolicy"] as? String == "never")
    #expect((turns[2]["sandboxPolicy"] as? [String: Any])?["type"] as? String == "dangerFullAccess")
    let methods = requests.compactMap { $0["method"] as? String }
    let goalIndex = try #require(methods.firstIndex(of: "thread/goal/set"))
    #expect(methods[goalIndex - 1] == "thread/settings/update")
    let rejected = try #require(requests.first { $0["id"] as? String == "approval-1" })
    #expect((rejected["result"] as? [String: Any])?["decision"] as? String == "cancel")
    let answer = try #require(requests.first { $0["id"] as? String == "question-1" })
    let answers = (answer["result"] as? [String: Any])?["answers"] as? [String: [String: [String]]]
    #expect(answers?["q"]?["answers"] == ["A"])
}
