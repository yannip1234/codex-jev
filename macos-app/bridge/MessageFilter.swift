import Foundation
import SwiftUI

/// One request per process. Stdout is reserved for the bridge's JSON envelope.
@main
struct MessageFilter {
    @MainActor static func main() async {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= 1_000_000,
                  var request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var params = request["params"] as? [String: Any],
                  var input = params["input"] as? [[String: Any]] else { exit(2) }
            let textIndices = input.indices.filter { input[$0]["type"] as? String == "text" }
            var stats: [String: Any] = ["apiCalls": 0, "savedEstimate": 0, "status": "Structured input kept unchanged."]
            // Preserve offsets, attached context, and boundaries of multipart text messages.
            if textIndices.count == 1, let index = textIndices.first,
               (input[index]["text_elements"] as? [Any] ?? []).isEmpty,
               let text = input[index]["text"] as? String {
                let home = MessageCompressor.defaultHome
                let key = MessageCompressor.resolvedKey(home: home,
                    environmentKey: ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"])
                // Use the system curl transport: Foundation networking can stall in a CLI helper.
                let compressor = MessageCompressor(home: home, key: { key }, judge: { state, questions in
                    try judge(state: state, questions: questions, key: key ?? "")
                })
                let result = await compressor.compress(text)
                input[index]["text"] = result.text
                stats = ["apiCalls": result.apiCalls, "savedEstimate": result.savedEstimate, "status": result.status]
            }
            params["input"] = input; request["params"] = params
            let output = try JSONSerialization.data(withJSONObject: ["request": request, "stats": stats])
            FileHandle.standardOutput.write(output)
        } catch { exit(2) }
    }

    static func judge(state: [String: Any], questions: [String: String], key: String) throws -> [String: Double] {
        let body = try JSONSerialization.data(withJSONObject: ["model": "jev-latest", "state": state,
            "questions": questions.mapValues { ["type": "noul", "instructions": $0] }])
        guard body.count <= 120_000 else { throw URLError(.dataLengthExceedsMaximum) }
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r") + "\""
        }
        // Pipe the credential and body to curl; neither appears in argv or a temporary file.
        let config = "header = \(quoted("Authorization: Bearer " + key))\n"
            + "header = \(quoted("Content-Type: application/json"))\n"
            + "data = \(quoted(String(decoding: body, as: UTF8.self)))\n"
        let child = Process(), input = Pipe(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        child.arguments = ["--disable", "--silent", "--fail", "--proto", "=https", "--max-time", "15",
            "--max-filesize", "65536", "--config", "-", "https://api.typesafe.ai/v1/systemone"]
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        try input.fileHandleForWriting.write(contentsOf: Data(config.utf8))
        try input.fileHandleForWriting.close()
        var response = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
            response.append(chunk)
            guard response.count <= 65_536 else { throw URLError(.dataLengthExceedsMaximum) }
        }
        child.waitUntilExit()
        guard child.terminationStatus == 0 else { throw URLError(.badServerResponse) }
        struct Answer: Decodable { let type: String; let noul: Double }
        struct Response: Decodable { let answers: [String: Answer] }
        let answers = try JSONDecoder().decode(Response.self, from: response).answers
        guard questions.keys.allSatisfy({ answers[$0]?.type == "noul" }) else { throw URLError(.cannotParseResponse) }
        return answers.mapValues(\.noul)
    }
}
