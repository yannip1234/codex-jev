import Foundation

/// Reports harness events, without inferring Jev savings from billing counters.
struct ContextStatus: Equatable {
    var isCompacting = false
    var message: String?
    var lastInputTokens: Int?
    private var completedIDs: Set<String> = []
    var completedCount: Int { completedIDs.count }

    mutating func requested() { isCompacting = true; message = "Compacting context…" }
    mutating func failed(_ reason: String) { isCompacting = false; message = "Compaction failed: \(reason)" }
    mutating func consume(method: String, params: [String: Any]) {
        if method == "thread/tokenUsage/updated",
           let usage = params["tokenUsage"] as? [String: Any], let last = usage["last"] as? [String: Any] {
            lastInputTokens = last["inputTokens"] as? Int
        }
        if ["item/started", "item/completed"].contains(method),
           let item = params["item"] as? [String: Any], item["type"] as? String == "contextCompaction" {
            if method == "item/started" { requested() }
            else {
                if let id = item["id"] as? String { completedIDs.insert(id) }
                isCompacting = false
                message = "Context compacted. The transcript stays visible; the model uses the compacted history."
            }
        }
        if isCompacting && method == "error" && params["willRetry"] as? Bool != true {
            failed((params["error"] as? [String: Any])?["message"] as? String ?? "The harness reported an error.")
        }
        if isCompacting && method == "turn/completed" {
            let turn = params["turn"] as? [String: Any] ?? [:]
            if turn["status"] as? String == "failed" || turn["status"] as? String == "interrupted" {
                failed((turn["error"] as? [String: Any])?["message"] as? String ?? "The turn stopped before compaction completed.")
            }
        }
    }
}
