import Foundation

struct LauncherConfiguration {
    let output: URL
    let home: URL
    let officialApp: URL

    var profile: URL { home.appendingPathComponent("Library/Application Support/Codex-Jev-Bridge") }
    var resources: URL { output.appendingPathComponent("Codex Jev Launcher.app/Contents/Resources") }
    var requiredFiles: [URL] {
        ["codex-jev-bridge", "jev-message-filter", "codex-jev", "codex-code-mode-host"].map { resources.appendingPathComponent($0) }
    }

    func isTrialCommand(_ command: String, executable: URL) -> Bool {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
            == executable.path + " --user-data-dir=" + profile.path
    }

    func environment(jev: Bool, inherited: [String: String]) -> [String: String] {
        var environment = inherited
        for key in ["CODEX_CLI_PATH", "CODEX_APP_SERVER_FORCE_CLI", "CODEX_ELECTRON_USER_DATA_PATH",
                    "CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED"] { environment.removeValue(forKey: key) }
        if jev {
            environment["CODEX_CLI_PATH"] = resources.appendingPathComponent("codex-jev-bridge").path
            environment["CODEX_APP_SERVER_FORCE_CLI"] = "1"
            environment["CODEX_ELECTRON_USER_DATA_PATH"] = profile.path
            environment["CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED"] = "1"
        }
        return environment
    }

    func logURL(environment: [String: String]) -> URL {
        let codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        return codexHome.appendingPathComponent("jev-bridge/activity.jsonl")
    }

    func legacyAppInUse(commands: String) -> Bool {
        let prefix = output.appendingPathComponent("JevCodex.app/Contents/").path + "/"
        return commands.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }
    }

    /// A local opt-in marker authorizes retiring the old bundle after its processes exit.
    func retireLegacyAppIfRequested() {
        let marker = output.appendingPathComponent(".retire-legacy-jev-app")
        let oldApp = output.appendingPathComponent("JevCodex.app")
        let files = FileManager.default
        guard files.fileExists(atPath: marker.path),
              Bundle(url: oldApp)?.bundleIdentifier == "local.jevcodex.native" else { return }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-axo", "command="]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0,
                  !legacyAppInUse(commands: String(decoding: data, as: UTF8.self)) else { return }
            try files.trashItem(at: oldApp, resultingItemURL: nil)
            try files.removeItem(at: marker)
        } catch { return }
    }
}
