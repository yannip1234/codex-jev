import Foundation

struct TokenTotals: Equatable {
    var original: Int64 = 0
    var compacted: Int64 = 0
    var samples = 0
    var saved: Int64 { original - compacted }
    mutating func add(before: Int64, after: Int64) {
        original += before; compacted += after; samples += 1
    }
    var display: String { "\(original.formatted()) → \(compacted.formatted()) · saved \(saved.formatted())" }
}

/// Totals over completed preprocessing records, not API billing or unique conversation tokens.
struct CompressionUsage {
    var outgoing = TokenTotals()
    var tools = TokenTotals()
    var history = TokenTotals()
    var incomplete = false
    var total: TokenTotals {
        TokenTotals(original: outgoing.original + tools.original + history.original,
            compacted: outgoing.compacted + tools.compacted + history.compacted,
            samples: outgoing.samples + tools.samples + history.samples)
    }

    static func read(home: URL) -> CompressionUsage {
        var result = CompressionUsage()
        let directory = home.appendingPathComponent("jev-bridge")
        for name in ["activity.jsonl", "engine-activity.jsonl"] {
            let file = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                for line in text.split(separator: "\n") {
                    guard let data = line.data(using: .utf8),
                          let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { result.incomplete = true; continue }
                    guard let before = entry["originalTokens"] as? NSNumber,
                          let after = entry["compactedTokens"] as? NSNumber else { continue }
                    let b = before.int64Value, a = after.int64Value
                    // Bounded individual records avoid overflow from malformed local log entries.
                    guard b >= 0, a >= 0, b <= 1_000_000_000, a <= 1_000_000_000,
                          before.doubleValue == Double(b), after.doubleValue == Double(a) else {
                        result.incomplete = true; continue
                    }
                    if name == "activity.jsonl", ["turn/start", "turn/steer"].contains(entry["method"] as? String ?? "") {
                        result.outgoing.add(before: b, after: a)
                    } else if ["compacted", "kept", "fallback"].contains(entry["event"] as? String ?? "") {
                        switch entry["component"] as? String {
                        case "tool_output": result.tools.add(before: b, after: a)
                        case "history": result.history.add(before: b, after: a)
                        default: break
                        }
                    }
                }
            } catch { result.incomplete = true }
        }
        return result
    }
}
