import Foundation
import Testing
@testable import JevCodex

@Test func usageTotalsSurviveReloadAndSeparateStagesWithoutCountingAPILifecycleTwice() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let logs = home.appendingPathComponent("jev-bridge")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try Data("""
    {"method":"turn/start","originalTokens":100,"compactedTokens":60}
    {"method":"turn/steer","originalTokens":30,"compactedTokens":30}
    {"method":"turn/start","savedEstimate":42}
    """.utf8).write(to: logs.appendingPathComponent("activity.jsonl"))
    try Data("""
    {"component":"tool_output","event":"api_started"}
    {"component":"tool_output","event":"api_completed"}
    {"component":"tool_output","event":"compacted","originalTokens":200,"compactedTokens":50}
    {"component":"history","event":"fallback","originalTokens":500,"compactedTokens":500}
    {"component":"history","event":"compacted","originalTokens":500,"compactedTokens":200}
    malformed partial record
    {"component":"history","event":"compacted","originalTokens":-1,"compactedTokens":0}
    """.utf8).write(to: logs.appendingPathComponent("engine-activity.jsonl"))
    for _ in 0..<2 {
        let usage = CompressionUsage.read(home: home)
        #expect(usage.outgoing == TokenTotals(original: 130, compacted: 90, samples: 2))
        #expect(usage.tools == TokenTotals(original: 200, compacted: 50, samples: 1))
        #expect(usage.history == TokenTotals(original: 1000, compacted: 700, samples: 2))
        #expect(usage.total.saved == 490)
        #expect(usage.incomplete)
    }
}
