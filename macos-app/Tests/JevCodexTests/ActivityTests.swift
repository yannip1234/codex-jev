import Testing
@testable import JevCodex

private func activityEvent(_ state: inout ActivityState, _ method: String, _ values: [String: Any] = [:], turn: String = "turn-1") {
    var params: [String: Any] = ["threadId": "thread-1", "turnId": turn]
    params.merge(values) { _, new in new }
    state.consume(method: method, params: params)
}

private func startActivity(_ state: inout ActivityState, turn: String = "turn-1") {
    activityEvent(&state, "turn/started", ["turn": ["id": turn, "status": "inProgress", "items": []]], turn: turn)
}

@Test func activityTracksSummaryPlanAndToolLifecycle() {
    var state = ActivityState()
    state.begin(threadID: "thread-1")
    #expect(state.currentStep == "Thinking…")
    startActivity(&state)
    activityEvent(&state, "item/started", ["item": ["type": "reasoning", "id": "r1", "summary": [], "content": []]])
    activityEvent(&state, "item/reasoning/summaryPartAdded", ["itemId": "r1", "summaryIndex": 0])
    activityEvent(&state, "item/reasoning/summaryTextDelta", ["itemId": "r1", "summaryIndex": 0, "delta": "**Inspecting files**\nChecking the project."])
    #expect(state.currentStep == "Inspecting files")
    activityEvent(&state, "turn/plan/updated", ["plan": [["step": "Inspect the app", "status": "inProgress"], ["step": "Verify", "status": "pending"]]])
    #expect(state.currentStep == "Inspect the app")
    let command: [String: Any] = ["type": "commandExecution", "id": "cmd-1", "command": "swift test", "cwd": "/tmp/project", "status": "inProgress"]
    activityEvent(&state, "item/started", ["item": command])
    #expect(state.currentStep == "swift test")
    activityEvent(&state, "item/commandExecution/outputDelta", ["itemId": "cmd-1", "delta": "Building\n"])
    activityEvent(&state, "item/commandExecution/outputDelta", ["itemId": "cmd-1", "delta": "Passed\n"])
    #expect(state.tools.first?.output == "Building\nPassed\n")
    var completed = command
    completed["status"] = "completed"
    completed["aggregatedOutput"] = "Final authoritative output\n"
    completed["exitCode"] = 0
    activityEvent(&state, "item/completed", ["item": completed])
    #expect(state.tools.count == 1)
    #expect(state.tools.first?.id == "cmd-1")
    #expect(state.tools.first?.output == "Final authoritative output\n")
    #expect(state.tools.first?.exitCode == 0)
    #expect(state.currentStep == "Inspect the app")
    activityEvent(&state, "turn/completed", ["turn": ["id": "turn-1", "status": "completed", "items": [completed]]])
    #expect(!state.isRunning)
    #expect(state.currentStep == "Activity")
    #expect(state.tools.count == 1)
    let final = state
    activityEvent(&state, "item/commandExecution/outputDelta", ["itemId": "cmd-1", "delta": "Late output"])
    #expect(state == final)
}

@Test func activityPartitionsSummaryByItemAndIndexAndIgnoresRawReasoning() {
    var state = ActivityState()
    startActivity(&state)
    activityEvent(&state, "item/reasoning/summaryTextDelta", ["itemId": "r1", "summaryIndex": 1, "delta": "Second"])
    activityEvent(&state, "item/reasoning/summaryTextDelta", ["itemId": "r1", "summaryIndex": 0, "delta": "First"])
    activityEvent(&state, "item/reasoning/summaryPartAdded", ["itemId": "r1", "summaryIndex": 0])
    activityEvent(&state, "item/reasoning/summaryTextDelta", ["itemId": "r1", "summaryIndex": 1, "delta": " part"])
    #expect(state.currentStep == "Second part")
    activityEvent(&state, "item/reasoning/summaryTextDelta", ["itemId": "r2", "summaryIndex": 0, "delta": "Another item"])
    #expect(state.summaryText == "First\n\nSecond part\n\nAnother item")
    #expect(state.currentStep == "Another item")
    let before = state
    activityEvent(&state, "item/reasoning/textDelta", ["itemId": "r1", "contentIndex": 0, "delta": "PRIVATE"])
    #expect(state == before)
    activityEvent(&state, "item/completed", ["item": ["type": "reasoning", "id": "r2", "summary": ["Final summary"], "content": ["PRIVATE"]]])
    #expect(state.summaryText == "First\n\nSecond part\n\nFinal summary")
    #expect(!state.summaryText.contains("PRIVATE"))
    #expect(state.summaries.count == 2)
}

@Test func activityFileAndMCPToolsReplaceSnapshotsAndClearRunningStatus() {
    var state = ActivityState()
    startActivity(&state)
    let changes: [[String: Any]] = [["path": "/tmp/App.swift", "kind": ["type": "update"], "diff": "+ fixed"]]
    activityEvent(&state, "item/started", ["item": ["id": "file-1", "type": "fileChange", "changes": changes, "status": "inProgress"]])
    #expect(state.tools.first?.title == "Edit App.swift")
    #expect(state.tools.first?.detail.contains("+ fixed") == true)
    activityEvent(&state, "item/completed", ["item": ["id": "file-1", "type": "fileChange", "changes": changes, "status": "completed"]])
    activityEvent(&state, "item/started", ["item": ["id": "mcp-1", "type": "mcpToolCall", "server": "docs", "tool": "search", "arguments": ["query": "SwiftUI"], "status": "inProgress"]])
    #expect(state.currentStep == "docs · search")
    activityEvent(&state, "item/completed", ["item": ["id": "mcp-1", "type": "mcpToolCall", "server": "docs", "tool": "search", "status": "failed", "error": ["message": "Connection closed"]]])
    #expect(state.tools.count == 2)
    #expect(state.tools.last?.output == "Connection closed")
    #expect(state.currentStep == "Thinking…")
    activityEvent(&state, "item/started", ["item": ["id": "cmd-2", "type": "commandExecution", "command": "sleep 10", "status": "inProgress"]])
    activityEvent(&state, "turn/completed", ["turn": ["id": "turn-1", "status": "interrupted", "items": [["id": "cmd-2", "type": "commandExecution", "command": "sleep 10", "status": "inProgress"]]]])
    #expect(!state.isRunning)
    #expect(!state.tools.contains(where: { $0.isActive }))
    #expect(state.tools.last?.status == "interrupted")
    #expect(state.tools.first?.status == "completed")
    #expect(state.currentStep == "Stopped")
}

@Test func activityResetsRejectsForeignEventsAndReplacesProposedPlan() {
    var state = ActivityState()
    startActivity(&state)
    activityEvent(&state, "item/plan/delta", ["itemId": "p1", "delta": "Draft "])
    activityEvent(&state, "item/plan/delta", ["itemId": "p1", "delta": "plan"])
    #expect(state.proposedPlan == "Draft plan")
    activityEvent(&state, "item/completed", ["item": ["id": "p1", "type": "plan", "text": "Final plan"]])
    #expect(state.proposedPlan == "Final plan")
    let before = state
    activityEvent(&state, "turn/completed", ["turn": ["id": "old-turn", "status": "completed"]], turn: "old-turn")
    state.consume(method: "turn/started", params: ["threadId": "other-thread", "turn": ["id": "foreign-turn"]])
    #expect(state == before)
    startActivity(&state, turn: "turn-2")
    #expect(!state.hasContent)
    #expect(state.turnID == "turn-2")
    #expect(state.currentStep == "Thinking…")
    state.reset()
    #expect(state == ActivityState())
    state.begin(threadID: "new-thread")
    #expect(state.threadID == "new-thread")
    #expect(state.isRunning)
}

@Test func activityErrorsDistinguishRetryFromTerminalFailure() {
    var state = ActivityState()
    startActivity(&state)
    activityEvent(&state, "error", ["error": ["message": "Retrying connection"], "willRetry": true])
    #expect(state.isRunning)
    #expect(state.error == "Retrying connection")
    activityEvent(&state, "error", ["error": ["message": "Disconnected"], "willRetry": false])
    #expect(!state.isRunning)
    #expect(state.currentStep == "Activity failed")
    state.begin()
    state.stop(error: "Cannot start turn")
    #expect(state.error == "Cannot start turn")
    #expect(!state.isRunning)
}
