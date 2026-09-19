import Foundation

@main struct LauncherTests {
    static func main() throws {
        let app = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let home = URL(fileURLWithPath: "/Users/test user")
        let output = URL(fileURLWithPath: "/tmp/build output")
        let config = LauncherConfiguration(output: output, home: home, officialApp: app)
        let command = app.path + "/Contents/MacOS/ChatGPT --user-data-dir=" + config.profile.path
        precondition(config.isTrialCommand(command, executable: app.appendingPathComponent("Contents/MacOS/ChatGPT")))
        precondition(!config.isTrialCommand(app.path + "/Contents/MacOS/ChatGPT", executable: app.appendingPathComponent("Contents/MacOS/ChatGPT")))
        precondition(!config.isTrialCommand(command + "-other", executable: app.appendingPathComponent("Contents/MacOS/ChatGPT")))
        precondition(!config.isTrialCommand("/tmp/fake --user-data-dir=" + config.profile.path, executable: app.appendingPathComponent("Contents/MacOS/ChatGPT")))
        let inherited = ["PATH": "/usr/bin", "CODEX_HOME": "/tmp/custom home", "CODEX_CLI_PATH": "old", "OTHER": "keep"]
        let standard = config.environment(jev: false, inherited: inherited)
        precondition(standard["CODEX_CLI_PATH"] == nil && standard["OTHER"] == "keep")
        precondition(standard["CODEX_HOME"] == "/tmp/custom home")
        let enabled = config.environment(jev: true, inherited: inherited)
        precondition(enabled["CODEX_CLI_PATH"] == output.appendingPathComponent("Codex Jev Launcher.app/Contents/Resources/codex-jev-bridge").path)
        precondition(config.requiredFiles.allSatisfy { $0.path.hasPrefix(config.resources.path + "/") })
        precondition(enabled["CODEX_APP_SERVER_FORCE_CLI"] == "1")
        precondition(enabled["CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED"] == "1")
        precondition(enabled["CODEX_ELECTRON_USER_DATA_PATH"] == config.profile.path)
        precondition(config.logURL(environment: inherited).path == "/tmp/custom home/jev-bridge/activity.jsonl")
        precondition(config.legacyAppInUse(commands: output.path + "/JevCodex.app/Contents/Resources/codex-jev app-server"))
        precondition(config.legacyAppInUse(commands: output.path + "/JevCodex.app/Contents/MacOS/JevCodex"))
        precondition(!config.legacyAppInUse(commands: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"))
        precondition(!config.legacyAppInUse(commands: config.resources.path + "/codex-jev app-server"))
        print("Launcher checks passed: trial identity, regular-instance exclusion, environment isolation, and custom Codex home.")
    }
}
