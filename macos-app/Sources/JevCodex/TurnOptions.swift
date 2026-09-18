import Foundation

enum ApprovalMode: String, CaseIterable, Identifiable {
    case ask, automatic, full
    var id: String { rawValue }
    var title: String {
        switch self { case .ask: "Ask for approval"; case .automatic: "Approve for me"; case .full: "Full access" }
    }
    var detail: String {
        switch self {
        case .ask: "Work in the project; ask before actions that require approval."
        case .automatic: "Work in the project; let the harness review approval requests."
        case .full: "Unrestricted file and network access, without approval prompts."
        }
    }
    var parameters: [String: Any] {
        let sandbox: [String: Any] = self == .full ? ["type": "dangerFullAccess"] :
            ["type": "workspaceWrite", "writableRoots": [String](), "networkAccess": false,
             "excludeTmpdirEnvVar": false, "excludeSlashTmp": false]
        return ["approvalPolicy": self == .full ? "never" : "on-request",
         "approvalsReviewer": self == .automatic ? "auto_review" : "user",
         "sandboxPolicy": sandbox]
    }
}

struct ChatAttachment: Identifiable, Equatable {
    let url: URL
    let isDirectory: Bool
    let isImage: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }

    init(url: URL) throws {
        let url = url.standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        guard values.isDirectory == true || values.isRegularFile == true else {
            throw HarnessError(message: "Choose a regular file or folder.")
        }
        self.url = url
        isDirectory = values.isDirectory == true
        isImage = !isDirectory && ["png", "jpg", "jpeg", "webp", "gif"].contains(url.pathExtension.lowercased())
        if isImage && (values.fileSize ?? 0) > 10 * 1024 * 1024 {
            throw HarnessError(message: "Images must be 10 MB or smaller.")
        }
    }

    var input: [String: Any] {
        if isImage { return ["type": "localImage", "path": url.path] }
        // Pass a reference rather than silently reading arbitrary files into the prompt.
        let reference = String(data: try! JSONEncoder().encode(url.path), encoding: .utf8)!
        return ["type": "text", "text": "User-attached \(isDirectory ? "folder" : "file") path: \(reference). Inspect it as needed for the request.", "text_elements": []]
    }
}

struct GoalState: Decodable, Equatable {
    let objective: String
    let status: String
    let tokenBudget: Int?
    let tokensUsed: Int
}

struct UserQuestionRequest: Identifiable {
    let id = UUID()
    let requestID: Any
    let questions: [Question]
    struct Question: Decodable, Identifiable {
        let id: String
        let header: String
        let question: String
        let isSecret: Bool?
        let options: [Option]?
        struct Option: Decodable { let label: String; let description: String }
    }
}

@MainActor
func requestOptions(selection: ModelSelection, mode: ApprovalMode, plan: Bool) -> [String: Any] {
    var params = mode.parameters
    params["summary"] = "auto"
    if let selected = selection.selectedModel {
        params["model"] = selected.model
        if let effort = selection.effort { params["effort"] = effort }
        // Always send the mode, including default, to turn off a previously sticky plan mode.
        params["collaborationMode"] = ["mode": plan ? "plan" : "default", "settings": [
            "model": selected.model, "reasoning_effort": selection.effort as Any? ?? NSNull(),
            "developer_instructions": NSNull()
        ]]
    }
    return params
}
