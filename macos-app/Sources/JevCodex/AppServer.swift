import Foundation

struct HarnessError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Frames bytes before decoding, so split UTF-8 characters remain intact.
struct JSONLines {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [[String: Any]] {
        buffer.append(data)
        guard buffer.count <= 64 * 1024 * 1024 else {
            throw HarnessError(message: "The harness protocol message exceeded 64 MB.")
        }
        var messages: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw HarnessError(message: "The harness returned an invalid protocol message.")
            }
            messages.append(object)
        }
        return messages
    }
}

@MainActor
final class AppServer {
    var onMessage: (([String: Any]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var lines = JSONLines()
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var nextID = 0
    private var generation = UUID()
    private(set) var ready = false

    static func backendURL() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["JEV_CODEX_BINARY"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("codex-jev"),
           FileManager.default.isExecutableFile(atPath: url.path) { return url }
        throw HarnessError(message: "The bundled codex-jev harness is missing. Build the app with build-app.sh, or set JEV_CODEX_BINARY to its absolute path.")
    }

    func start(executable: URL? = nil) async throws {
        guard !ready else { return }
        let child = Process()
        let generation = UUID()
        self.generation = generation
        child.executableURL = try executable ?? Self.backendURL()
        child.arguments = ["--enable", "goals", "app-server"]
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        errors = stderr.fileHandleForReading
        lines = JSONLines()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in
                guard self?.generation == generation else { return }
                self?.receive(data)
            }
        }
        // Drain diagnostics without logging potentially sensitive tool output.
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor in
                guard self?.generation == generation else { return }
                self?.disconnected("The harness stopped (exit \(status)). Reconnect to continue.")
            }
        }
        process = child
        do {
            try child.run()
            _ = try await request("initialize", ["clientInfo": [
                "name": "jev-codex-native", "title": "Jev Codex", "version": "0.2.0"
            ], "capabilities": ["experimentalApi": true]])
            try send(["method": "initialized"])
            ready = true
        } catch {
            stop()
            throw error
        }
    }

    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        guard process?.isRunning == true else { throw HarnessError(message: "The harness is not connected.") }
        nextID += 1
        let id = "native-\(nextID)"
        let result: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(60))
                self?.pending.removeValue(forKey: id)?.resume(throwing:
                    HarnessError(message: "The harness timed out while handling \(method). Reconnect and try again."))
            }
            do { try send(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
        }
        return try JSONSerialization.jsonObject(with: result) as? [String: Any] ?? [:]
    }

    func respond(id: Any, result: [String: Any]) throws {
        try send(["id": id, "result": result])
    }

    func respond(id: Any, decision: String) throws {
        try send(["id": id, "result": ["decision": decision]])
    }

    func rejectUnsupported(id: Any, method: String) throws {
        try send(["id": id, "error": ["code": -32601,
            "message": "Jev Codex does not support the client request: \(method)"]])
    }

    private func send(_ message: [String: Any]) throws {
        guard let input else { throw HarnessError(message: "The harness is not connected.") }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        do {
            for message in try lines.append(data) {
                if message["method"] == nil, let id = message["id"] as? String,
                   let continuation = pending.removeValue(forKey: id) {
                    if let error = message["error"] as? [String: Any] {
                        continuation.resume(throwing: HarnessError(message: error["message"] as? String ?? "Harness request failed."))
                    } else {
                        do { continuation.resume(returning: try JSONSerialization.data(withJSONObject: message["result"] as? [String: Any] ?? [:])) }
                        catch { continuation.resume(throwing: error) }
                    }
                } else { onMessage?(message) }
            }
        } catch { stop(); onDisconnect?(error.localizedDescription) }
    }

    private func disconnected(_ message: String) {
        ready = false
        let requests = pending.values
        pending.removeAll()
        for request in requests { request.resume(throwing: HarnessError(message: message)) }
        onDisconnect?(message)
    }

    func stop() {
        generation = UUID()
        process?.terminationHandler = nil
        output?.readabilityHandler = nil
        errors?.readabilityHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil
        input = nil
        output = nil
        errors = nil
        disconnected("The harness was disconnected.")
    }
}
