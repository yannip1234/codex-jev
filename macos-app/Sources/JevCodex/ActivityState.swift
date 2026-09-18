import Foundation

/// Public app-server progress for the current turn. Never stores raw reasoning content.
struct ActivityState: Equatable {
    struct Summary: Identifiable, Equatable {
        let id: String
        var parts: [Int: String] = [:]
        var text: String { parts.keys.sorted().compactMap { parts[$0] }.filter { !$0.isEmpty }.joined(separator: "\n\n") }
    }
    struct PlanStep: Identifiable, Equatable {
        let id: Int
        let text: String
        let status: String
    }
    struct Tool: Identifiable, Equatable {
        let id: String
        var kind: String
        var title: String
        var status: String
        var detail: String = ""
        var output: String = ""
        var exitCode: Int?
        var isActive: Bool { status == "inProgress" }
        var icon: String {
            switch kind {
            case "commandExecution": "terminal"
            case "fileChange": "doc.text"
            default: "circle.grid.2x2"
            }
        }
    }
    private(set) var threadID: String?
    private(set) var turnID: String?
    private(set) var isRunning = false
    private(set) var status = ""
    private(set) var error: String?
    private(set) var summaries: [Summary] = []
    private(set) var plan: [PlanStep] = []
    private(set) var planExplanation: String?
    private(set) var tools: [Tool] = []
    private var planItemIDs: [String] = []
    private var planItems: [String: String] = [:]

    var summaryText: String { summaries.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n") }
    var proposedPlan: String { planItemIDs.compactMap { planItems[$0] }.filter { !$0.isEmpty }.joined(separator: "\n\n") }
    var hasContent: Bool { !summaryText.isEmpty || !plan.isEmpty || !proposedPlan.isEmpty || !tools.isEmpty || error != nil }
    var currentStep: String {
        guard isRunning else {
            switch status {
            case "failed": return "Activity failed"
            case "interrupted": return "Stopped"
            default: return "Activity"
            }
        }
        if let tool = tools.last(where: \.isActive) { return tool.title }
        if let step = plan.first(where: { $0.status == "inProgress" }) { return step.text }
        if let text = summaries.reversed().lazy.flatMap({ summary in
            summary.parts.keys.sorted(by: >).compactMap { summary.parts[$0] }
        }).first(where: { !$0.isEmpty }),
           let title = text.split(separator: "\n").first {
            return String(title).trimmingCharacters(in: CharacterSet(charactersIn: "*# ")).prefix(140).description
        }
        return "Thinking…"
    }

    mutating func reset() { self = ActivityState() }

    mutating func begin(threadID: String? = nil) {
        reset()
        self.threadID = threadID
        isRunning = true
        status = "inProgress"
    }

    mutating func stop(error: String? = nil) {
        self.error = error
        finish(status: error == nil ? "interrupted" : "failed")
    }

    mutating func consume(method: String, params: [String: Any]) {
        if let incoming = params["threadId"] as? String, let threadID, incoming != threadID { return }
        if method == "turn/started" {
            guard let turn = params["turn"] as? [String: Any], let id = turn["id"] as? String else { return }
            if turnID != id {
                begin(threadID: params["threadId"] as? String ?? threadID)
                turnID = id
            }
            return
        }
        let incomingTurn = params["turnId"] as? String ?? (params["turn"] as? [String: Any])?["id"] as? String
        if let turnID, let incomingTurn, turnID != incomingTurn { return }
        // Once a turn terminates, delayed deltas must not restart its indicators.
        guard isRunning else { return }
        switch method {
        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any] else { return }
            for item in turn["items"] as? [[String: Any]] ?? [] { consumeItem(item, completed: true) }
            error = (turn["error"] as? [String: Any])?["message"] as? String
            finish(status: turn["status"] as? String ?? "completed")
        case "error":
            error = (params["error"] as? [String: Any])?["message"] as? String
            if params["willRetry"] as? Bool != true { finish(status: "failed") }
        case "turn/plan/updated":
            planExplanation = params["explanation"] as? String
            plan = (params["plan"] as? [[String: Any]] ?? []).enumerated().compactMap { index, item in
                guard let text = item["step"] as? String else { return nil }
                return PlanStep(id: index, text: text, status: item["status"] as? String ?? "pending")
            }
        case "item/reasoning/summaryPartAdded", "item/reasoning/summaryTextDelta":
            guard let id = params["itemId"] as? String, let part = params["summaryIndex"] as? Int, part >= 0 else { return }
            let index = summaryIndex(id)
            summaries[index].parts[part, default: ""] += params["delta"] as? String ?? ""
        case "item/plan/delta":
            guard let id = params["itemId"] as? String else { return }
            rememberPlan(id)
            planItems[id, default: ""] += params["delta"] as? String ?? ""
        case "item/started", "item/completed":
            guard let item = params["item"] as? [String: Any] else { return }
            consumeItem(item, completed: method == "item/completed")
        case "item/commandExecution/outputDelta", "item/fileChange/outputDelta":
            guard let id = params["itemId"] as? String, let index = tools.firstIndex(where: { $0.id == id }) else { return }
            tools[index].output += params["delta"] as? String ?? ""
        case "item/fileChange/patchUpdated":
            guard let id = params["itemId"] as? String, let index = tools.firstIndex(where: { $0.id == id }) else { return }
            let changes = params["changes"] as? [[String: Any]] ?? []
            tools[index].detail = fileDetails(changes)
            tools[index].title = fileTitle(changes)
        default: break // Deliberately ignores item/reasoning/textDelta and raw response items.
        }
    }

    private mutating func finish(status: String) {
        isRunning = false
        self.status = status
        for index in tools.indices where tools[index].isActive {
            // Missing completion is not evidence of success.
            tools[index].status = status == "failed" ? "failed" : "interrupted"
        }
    }

    private mutating func summaryIndex(_ id: String) -> Int {
        if let index = summaries.firstIndex(where: { $0.id == id }) { return index }
        summaries.append(Summary(id: id))
        return summaries.count - 1
    }

    private mutating func rememberPlan(_ id: String) {
        if !planItemIDs.contains(id) { planItemIDs.append(id) }
    }

    private mutating func consumeItem(_ item: [String: Any], completed: Bool) {
        guard let id = item["id"] as? String, let kind = item["type"] as? String else { return }
        if kind == "reasoning" {
            let index = summaryIndex(id)
            if let summary = item["summary"] as? [String], completed || !summary.isEmpty {
                summaries[index].parts = Dictionary(uniqueKeysWithValues: summary.enumerated().map { ($0.offset, $0.element) })
            }
            return
        }
        if kind == "plan" {
            rememberPlan(id)
            if let text = item["text"] as? String, completed || !text.isEmpty { planItems[id] = text }
            return
        }
        guard ["commandExecution", "fileChange", "mcpToolCall"].contains(kind) else { return }
        let index = tools.firstIndex(where: { $0.id == id })
        var tool = index.map { tools[$0] } ?? Tool(id: id, kind: kind, title: "Tool", status: "inProgress")
        tool.status = item["status"] as? String ?? (completed ? "completed" : "inProgress")
        switch kind {
        case "commandExecution":
            if let command = item["command"] as? String {
                tool.title = command
                tool.detail = command
                if let cwd = item["cwd"] as? String { tool.detail += "\n\nWorking directory: \(cwd)" }
            }
            // A completed snapshot replaces streaming output rather than duplicating it.
            if let output = item["aggregatedOutput"] as? String { tool.output = output }
            tool.exitCode = item["exitCode"] as? Int
        case "fileChange":
            if let changes = item["changes"] as? [[String: Any]] {
                tool.title = fileTitle(changes)
                tool.detail = fileDetails(changes)
            }
        default:
            let server = item["server"] as? String ?? "MCP"
            let name = item["tool"] as? String ?? "Tool"
            tool.title = "\(server) · \(name)"
            if let arguments = item["arguments"] { tool.detail = "Arguments\n" + jsonText(arguments) }
            if let result = item["result"], !(result is NSNull) { tool.output = jsonText(result) }
            if let failure = item["error"] as? [String: Any], let message = failure["message"] as? String {
                tool.output = message
            }
        }
        if let index { tools[index] = tool } else { tools.append(tool) }
    }

    private func fileTitle(_ changes: [[String: Any]]) -> String {
        let paths = changes.compactMap { $0["path"] as? String }
        if paths.count == 1 { return "Edit \(URL(fileURLWithPath: paths[0]).lastPathComponent)" }
        return "Edit \(paths.count) files"
    }
    private func fileDetails(_ changes: [[String: Any]]) -> String {
        changes.map { change in
            let path = change["path"] as? String ?? "File"
            let kind = (change["kind"] as? [String: Any])?["type"] as? String ?? "update"
            return "\(kind.capitalized): \(path)\n\(change["diff"] as? String ?? "")"
        }.joined(separator: "\n\n")
    }
    private func jsonText(_ value: Any) -> String {
        if let text = value as? String { return text }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}
