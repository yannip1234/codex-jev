import AppKit
import SwiftUI

struct SavedTask: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let cwd: String
}

struct ChatItem: Identifiable, Equatable {
    let id: String
    let role: String
    var text: String
    var status: String = ""

    static func parse(_ item: [String: Any]) -> ChatItem? {
        guard let id = item["id"] as? String, let type = item["type"] as? String else { return nil }
        let text: String
        let role: String
        switch type {
        case "userMessage":
            role = "You"
            text = (item["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        case "agentMessage", "plan": role = "Codex"; text = item["text"] as? String ?? ""
        case "commandExecution":
            role = "Command"
            text = [item["command"] as? String, item["aggregatedOutput"] as? String].compactMap { $0 }.joined(separator: "\n\n")
        case "fileChange":
            role = "File changes"
            text = (item["changes"] as? [[String: Any]] ?? []).map {
                [($0["path"] as? String ?? ""), ($0["diff"] as? String ?? "")].joined(separator: "\n")
            }.joined(separator: "\n\n")
        case "mcpToolCall", "dynamicToolCall": role = "Tool"; text = item["tool"] as? String ?? type
        case "reasoning", "contextCompaction": return nil
        default: role = "Activity"; text = type
        }
        return ChatItem(id: id, role: role, text: text, status: item["status"] as? String ?? "")
    }
}

struct Approval: Identifiable {
    let id = UUID()
    let requestID: Any
    let title: String
    let detail: String
    var rejectionDecision = "decline"
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var tasks: [SavedTask] = []
    @Published var selectedID: String?
    @Published var items: [ChatItem] = []
    @Published var draft = ""
    @Published var attachments: [ChatAttachment] = []
    @Published var approvalMode: ApprovalMode = .ask
    @Published var planMode = false
    @Published var goal: GoalState?
    @Published var userQuestions: [UserQuestionRequest] = []
    @Published var activity = ActivityState()
    @Published var contextStatus = ContextStatus()
    @Published var cwd = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JevCodex/Workspace").path
    @Published var busy = false
    @Published var running = false
    @Published var connected = false
    @Published var status = "Connecting…"
    @Published var error: String?
    @Published var approvals: [Approval] = []
    @Published private(set) var pinnedIDs: Set<String> = []
    @Published private(set) var accountLabel = "Local workspace"
    let server = AppServer()
    let modelSelection: ModelSelection
    private var turnID: String?
    var goalRevision = 0
    var loadedID: String?
    let indexURL: URL
    private var pinsURL: URL { indexURL.deletingLastPathComponent().appendingPathComponent("pinned-tasks.json") }
    var taskTitle: String { tasks.first(where: { $0.id == selectedID })?.title ?? "New chat" }

    init(indexURL: URL? = nil) {
        self.indexURL = indexURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JevCodex/tasks.json")
        modelSelection = ModelSelection(url: self.indexURL.deletingLastPathComponent().appendingPathComponent("model-preferences.json"))
        if let data = try? Data(contentsOf: self.indexURL) {
            do { tasks = try JSONDecoder().decode([SavedTask].self, from: data) }
            catch { self.error = "Could not read saved tasks: \(error.localizedDescription)" }
        }
        if let data = try? Data(contentsOf: pinsURL), let ids = try? JSONDecoder().decode([String].self, from: data) {
            pinnedIDs = Set(ids)
        }
        server.onMessage = { [weak self] in self?.receive($0) }
        server.onDisconnect = { [weak self] message in
            self?.connected = false; self?.running = false; self?.turnID = nil
            self?.loadedID = nil; self?.approvals = []; self?.userQuestions = []; self?.status = message
            self?.activity.stop(error: message)
            if self?.contextStatus.isCompacting == true { self?.contextStatus.failed(message) }
        }
    }

    func connect(executable: URL? = nil) async {
        guard !busy, !connected else { return }
        busy = true
        defer { busy = false }
        do {
            try await server.start(executable: executable)
            connected = true
            let account = try await server.request("account/read")
            if let details = account["account"] as? [String: Any] {
                accountLabel = details["email"] as? String
                    ?? (details["type"] as? String == "apiKey" ? "API key account" : "Codex account")
            }
            try await modelSelection.load(from: server)
            status = "Ready"
            if account["requiresOpenaiAuth"] as? Bool == true, !(account["account"] is [String: Any]) {
                error = "Sign in with the Codex CLI (codex login), then reconnect. Your Jev key is configured separately in Settings."
            }
        } catch { self.error = error.localizedDescription; status = "Connection failed" }
    }

    func reconnect() async {
        guard !busy, !running, !contextStatus.isCompacting else { return }
        server.stop()
        await connect()
        if let selectedID { await select(selectedID) }
    }

    func newTask() {
        guard !busy, !running, !contextStatus.isCompacting else { return }
        selectedID = nil; loadedID = nil; items = []; draft = ""; error = nil
        attachments = []; goal = nil; activity.reset(); contextStatus = ContextStatus(); approvalMode = .ask; planMode = false
    }

    func togglePin(_ id: String) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        var updated = pinnedIDs
        if !updated.insert(id).inserted { updated.remove(id) }
        do {
            try privateAtomicWrite(JSONEncoder().encode(updated.sorted()), to: pinsURL)
            pinnedIDs = updated
        } catch { self.error = "Could not save pinned tasks: \(error.localizedDescription)" }
    }

    func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map { "\($0.role)\n\($0.text)" }.joined(separator: "\n\n"), forType: .string)
    }

    func chooseFolder() {
        guard selectedID == nil, !busy, !running, !contextStatus.isCompacting else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Project"
        if panel.runModal() == .OK, let folder = panel.url { cwd = folder.path }
    }

    func select(_ id: String) async {
        guard !busy, !running, !contextStatus.isCompacting, let task = tasks.first(where: { $0.id == id }) else { return }
        guard loadedID != id else { return }
        selectedID = id; cwd = task.cwd; draft = ""; error = nil
        attachments = []; goal = nil; activity.reset(); contextStatus = ContextStatus(); approvalMode = .ask; planMode = false
        busy = true
        defer { busy = false }
        items = []
        do { try await resume(id) }
        catch { self.error = error.localizedDescription }
    }

    func resume(_ id: String) async throws {
        let result = try await server.request("thread/resume", ["threadId": id,
            "approvalPolicy": "on-request", "approvalsReviewer": "user", "sandbox": "workspace-write", "excludeTurns": true])
        guard let thread = result["thread"] as? [String: Any] else {
            throw HarnessError(message: "The harness did not return the saved task.")
        }
        var cursor: String?
        repeat {
            var params: [String: Any] = ["threadId": id, "limit": 100, "sortDirection": "asc"]
            if let cursor { params["cursor"] = cursor }
            let page = try await server.request("thread/items/list", params)
            for entry in page["data"] as? [[String: Any]] ?? [] {
                if let item = entry["item"] as? [String: Any] { contextStatus.consume(method: "item/completed", params: ["item": item]) }
                if let item = entry["item"] as? [String: Any], let parsed = ChatItem.parse(item) { upsert(parsed) }
            }
            cursor = page["nextCursor"] as? String
        } while cursor != nil
        cwd = thread["cwd"] as? String ?? cwd
        loadedID = id
        let revision = goalRevision
        let response = try await server.request("thread/goal/get", ["threadId": id])
        if goalRevision == revision { goal = decodeGoal(response["goal"]) }
    }

    func send() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard connected, !busy, !running, !contextStatus.isCompacting, (!prompt.isEmpty || !attachments.isEmpty) else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            if let selectedID, loadedID != selectedID { try await resume(selectedID) }
            try await ensureThread(title: prompt.isEmpty ? "Attached files" : prompt)
            guard let selectedID else { return }
            running = true; status = "Working…"; turnID = nil
            activity.begin(threadID: selectedID)
            var params = modelSelection.turnParameters(threadID: selectedID, prompt: prompt)
            params.merge(requestOptions(selection: modelSelection, mode: approvalMode, plan: planMode)) { _, new in new }
            var input = (params["input"] as? [[String: Any]]) ?? []
            input += attachments.map(\.input)
            params["input"] = input
            let result = try await server.request("turn/start", params)
            draft = ""; attachments = []
            if running { turnID = (result["turn"] as? [String: Any])?["id"] as? String }
        } catch { running = false; self.error = error.localizedDescription; status = "Ready"; activity.stop(error: error.localizedDescription) }
    }

    func cancel() async {
        guard let selectedID, let turnID else { return }
        do {
            _ = try await server.request("turn/interrupt", ["threadId": selectedID, "turnId": turnID])
            status = "Stopping…"
        } catch { self.error = error.localizedDescription }
    }

    func compact() async {
        guard let selectedID, connected, !busy, !running, !contextStatus.isCompacting else { return }
        busy = true
        defer { busy = false }
        do {
            contextStatus.requested()
            _ = try await server.request("thread/compact/start", ["threadId": selectedID])
        } catch { self.error = error.localizedDescription; contextStatus.failed(error.localizedDescription) }
    }

    func decide(_ approval: Approval, accept: Bool) {
        do {
            try server.respond(id: approval.requestID, decision: accept ? "accept" : approval.rejectionDecision)
            approvals.removeAll { $0.id == approval.id }
        } catch { self.error = error.localizedDescription }
    }

    private func upsert(_ item: ChatItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
    }

    private func receive(_ message: [String: Any]) {
        guard let method = message["method"] as? String else { return }
        let params = message["params"] as? [String: Any] ?? [:]
        if let id = message["id"] {
            guard params["threadId"] as? String == selectedID else {
                try? server.rejectUnsupported(id: id, method: method)
                return
            }
            if method == "item/tool/requestUserInput" {
                do {
                    let data = try JSONSerialization.data(withJSONObject: params["questions"] ?? [])
                    let questions = try JSONDecoder().decode([UserQuestionRequest.Question].self, from: data)
                    guard !questions.isEmpty else { throw HarnessError(message: "The harness sent an empty question.") }
                    userQuestions.append(UserQuestionRequest(requestID: id, questions: questions))
                } catch {
                    try? server.rejectUnsupported(id: id, method: method)
                    self.error = error.localizedDescription
                }
                return
            }
            if method == "item/commandExecution/requestApproval" || method == "item/fileChange/requestApproval" {
                let item = items.first { $0.id == params["itemId"] as? String }
                let context = (try? JSONSerialization.data(withJSONObject: params, options: [.prettyPrinted, .sortedKeys]))
                    .flatMap { String(data: $0, encoding: .utf8) }
                let details = [context, item?.text]
                    .compactMap { $0 }.joined(separator: "\n\n")
                approvals.append(Approval(requestID: id, title: method.contains("commandExecution") ? "Allow command?" : "Allow file changes?", detail: details, rejectionDecision: (params["availableDecisions"] as? [String])?.contains("decline") == false ? "cancel" : "decline"))
            } else {
                do { try server.rejectUnsupported(id: id, method: method) }
                catch { self.error = error.localizedDescription }
                self.error = "The harness requested an unsupported interaction: \(method). It was declined."
            }
            return
        }
        if method == "serverRequest/resolved" {
            let id = String(describing: params["requestId"] ?? "")
            approvals.removeAll { String(describing: $0.requestID) == id }
            userQuestions.removeAll { String(describing: $0.requestID) == id }
            return
        }
        guard params["threadId"] as? String == selectedID else { return }
        activity.consume(method: method, params: params)
        contextStatus.consume(method: method, params: params)
        switch method {
        case "thread/goal/updated": goalRevision += 1; goal = decodeGoal(params["goal"])
        case "thread/goal/cleared": goalRevision += 1; goal = nil
        case "turn/started":
            turnID = (params["turn"] as? [String: Any])?["id"] as? String
            running = true; status = "Working…"
        case "item/started", "item/completed":
            if let item = params["item"] as? [String: Any], let parsed = ChatItem.parse(item) { upsert(parsed) }
        case "item/agentMessage/delta":
            guard let id = params["itemId"] as? String, let delta = params["delta"] as? String else { return }
            var item = items.first { $0.id == id } ?? ChatItem(id: id, role: "Codex", text: "")
            item.text += delta; upsert(item)
        case "turn/completed":
            running = false; turnID = nil; approvals = []; userQuestions = []; status = "Ready"
            if let turn = params["turn"] as? [String: Any], let failure = turn["error"] as? [String: Any] {
                error = failure["message"] as? String ?? "The turn failed."
            }
        case "error":
            error = (params["error"] as? [String: Any])?["message"] as? String ?? "The harness reported an error."
        default: break
        }
    }
}
