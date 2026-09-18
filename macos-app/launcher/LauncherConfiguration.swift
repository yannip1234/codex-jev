import Foundation

struct LauncherConfiguration {
    let output: URL
    let home: URL
    let officialApp: URL

    var profile: URL { home.appendingPathComponent("Library/Application Support/Codex-Jev-Bridge") }
    var nativeApp: URL { output.appendingPathComponent("JevCodex.app") }
    var requiredFiles: [URL] {
        [output.appendingPathComponent("codex-jev-bridge"), output.appendingPathComponent("jev-message-filter"),
         nativeApp.appendingPathComponent("Contents/Resources/codex-jev"),
         nativeApp.appendingPathComponent("Contents/Resources/codex-code-mode-host")]
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
            environment["CODEX_CLI_PATH"] = output.appendingPathComponent("codex-jev-bridge").path
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
}
