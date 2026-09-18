import Foundation
import Combine

struct ReasoningOption: Decodable, Equatable, Identifiable {
    let reasoningEffort: String
    let description: String
    var id: String { reasoningEffort }
    var label: String {
        switch reasoningEffort {
        case "xhigh": "Extra high"
        default: reasoningEffort.capitalized
        }
    }
}

struct HarnessModel: Decodable, Equatable, Identifiable {
    let id: String
    let model: String
    let displayName: String
    let description: String
    let hidden: Bool
    let isDefault: Bool
    let defaultReasoningEffort: String
    let supportedReasoningEfforts: [ReasoningOption]

    var defaultEffort: String? {
        efforts.first(where: { $0.id == defaultReasoningEffort })?.id ?? efforts.first?.id
    }

    var efforts: [ReasoningOption] {
        var seen = Set<String>()
        return supportedReasoningEfforts.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }
}

struct ModelPage: Decodable {
    let data: [HarnessModel]
    let nextCursor: String?
}

private struct ModelPreference: Codable {
    var model: String?
    var effort: String?
}

@MainActor
final class ModelSelection: ObservableObject {
    @Published private(set) var models: [HarnessModel] = []
    @Published private(set) var modelID: String?
    @Published private(set) var effort: String?
    @Published private(set) var notice: String?
    private var preference: ModelPreference
    private let url: URL

    init(url: URL) {
        self.url = url
        preference = (try? JSONDecoder().decode(ModelPreference.self, from: Data(contentsOf: url)))
            ?? ModelPreference()
    }

    var selectedModel: HarnessModel? { models.first { $0.id == modelID } }
    var selectedEffort: ReasoningOption? { selectedModel?.efforts.first { $0.id == effort } }

    func load(from server: AppServer) async throws {
        models = []; modelID = nil; effort = nil
        var available: [HarnessModel] = []
        var cursor: String?
        repeat {
            var params: [String: Any] = ["limit": 100, "includeHidden": false]
            if let cursor { params["cursor"] = cursor }
            let result = try await server.request("model/list", params)
            let page = try JSONDecoder().decode(ModelPage.self, from: JSONSerialization.data(withJSONObject: result))
            available += page.data
            cursor = page.nextCursor
        } while cursor != nil
        updateCatalog(available)
    }

    func updateCatalog(_ available: [HarnessModel]) {
        var seen = Set<String>()
        models = available.filter { !$0.hidden && !$0.model.isEmpty && seen.insert($0.id).inserted }
        let saved = models.first { $0.model == preference.model }
        let model = saved ?? models.first(where: \.isDefault) ?? models.first
        modelID = model?.id
        effort = saved?.efforts.first(where: { $0.id == preference.effort })?.id ?? model?.defaultEffort
        if model != nil { persist() }
    }

    func selectModel(_ id: String) {
        guard let model = models.first(where: { $0.id == id }) else { return }
        modelID = model.id
        effort = model.defaultEffort
        persist()
    }

    func selectEffort(_ id: String) {
        guard effort != id, selectedModel?.efforts.contains(where: { $0.id == id }) == true else { return }
        effort = id
        persist()
    }

    func reset() {
        guard let model = models.first(where: \.isDefault) ?? models.first else { return }
        selectModel(model.id)
    }

    func turnParameters(threadID: String, prompt: String) -> [String: Any] {
        var params: [String: Any] = ["threadId": threadID,
            "input": [["type": "text", "text": prompt, "text_elements": []]]]
        if let selectedModel {
            params["model"] = selectedModel.model
            if let selectedEffort { params["effort"] = selectedEffort.id }
        }
        return params
    }

    private func persist() {
        preference = ModelPreference(model: selectedModel?.model, effort: effort)
        do {
            try privateAtomicWrite(JSONEncoder().encode(preference), to: url)
            notice = nil
        } catch { notice = "Could not save model preference: \(error.localizedDescription)" }
    }
}
