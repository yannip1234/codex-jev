import AppKit

@MainActor
extension ChatModel {
    func ensureThread(title: String) async throws {
        if let selectedID {
            if loadedID != selectedID { try await resume(selectedID) }
            return
        }
        try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        let result = try await server.request("thread/start", ["cwd": cwd,
            "approvalPolicy": "on-request", "sandbox": "workspace-write"])
        guard let thread = result["thread"] as? [String: Any], let id = thread["id"] as? String else {
            throw HarnessError(message: "The harness did not return a task ID.")
        }
        selectedID = id; loadedID = id
        tasks.insert(SavedTask(id: id, title: String(title.prefix(72)), cwd: cwd), at: 0)
        try privateAtomicWrite(JSONEncoder().encode(tasks), to: indexURL)
    }

    func attachFiles() {
        guard !busy, !running, !contextStatus.isCompacting else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true; panel.prompt = "Attach"
        if panel.runModal() == .OK { addAttachments(panel.urls) }
    }

    func addAttachments(_ urls: [URL]) {
        do {
            var updated = attachments
            for url in urls {
                let file = try ChatAttachment(url: url)
                if !updated.contains(where: { $0.id == file.id }) { updated.append(file) }
            }
            guard updated.count <= 20, updated.filter(\.isImage).count <= 5 else {
                throw HarnessError(message: "Attach up to 20 files or folders, including at most 5 images.")
            }
            attachments = updated
        } catch { self.error = error.localizedDescription }
    }

    func decodeGoal(_ value: Any?) -> GoalState? {
        guard let value, !(value is NSNull),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(GoalState.self, from: data)
    }

    func saveGoal(objective: String, tokenBudget: Int?) async {
        let objective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard connected, !busy, !running, !contextStatus.isCompacting, !objective.isEmpty else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await ensureThread(title: objective)
            guard let selectedID else { return }
            var options = requestOptions(selection: modelSelection, mode: approvalMode, plan: planMode)
            options["threadId"] = selectedID
            _ = try await server.request("thread/settings/update", options)
            var params: [String: Any] = ["threadId": selectedID, "objective": objective, "status": "active"]
            params["tokenBudget"] = tokenBudget as Any? ?? NSNull()
            let revision = goalRevision
            let response = try await server.request("thread/goal/set", params)
            if goalRevision == revision { goal = decodeGoal(response["goal"]) }
        } catch { self.error = error.localizedDescription }
    }

    func updateGoal(status: String) async {
        guard let selectedID, connected, !busy else { return }
        // Pausing remains available during an active goal turn.
        guard status == "paused" || !running else { return }
        busy = true
        defer { busy = false }
        do {
            if status == "active" {
                var options = requestOptions(selection: modelSelection, mode: approvalMode, plan: planMode)
                options["threadId"] = selectedID
                _ = try await server.request("thread/settings/update", options)
            }
            let revision = goalRevision
            let response = try await server.request("thread/goal/set", ["threadId": selectedID, "status": status])
            if goalRevision == revision { goal = decodeGoal(response["goal"]) }
        } catch { self.error = error.localizedDescription }
    }

    func answerQuestions(_ request: UserQuestionRequest, answers: [String: String]) {
        do {
            let values = answers.mapValues { ["answers": [$0]] }
            try server.respond(id: request.requestID, result: ["answers": values])
            userQuestions.removeAll { $0.id == request.id }
        } catch { self.error = error.localizedDescription }
    }
}
