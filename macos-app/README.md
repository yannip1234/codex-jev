# Jev Codex for macOS

Native SwiftUI client for the custom `codex-jev app-server` harness. Requires macOS 14+ and a Swift 6 toolchain to build. It reuses the active Codex home's authentication and stores its task index in `~/Library/Application Support/JevCodex/tasks.json`.

```sh
python3 build-backend.py
swift test
./build-app.sh /absolute/path/to/codex-jev /absolute/path/to/JevCodex.app /absolute/path/to/codex-code-mode-host
open /absolute/path/to/JevCodex.app
```

For development, set `JEV_CODEX_BINARY=/absolute/path/to/codex-jev` before running `swift run`. Sign in with `codex login` if there is no existing Codex authentication. Open Settings with Command-comma to save the Jev key and configure compression. `TYPESAFE_API_KEY` takes precedence over the saved key. Settings apply to the next compression or compaction. The key is stored at `$CODEX_HOME/jev-api-key` (default `~/.codex/jev-api-key`) with mode 0600; preferences use `jev-settings.json` in the same directory.

Choose a project from the composer's plus menu and send with Command-Return. The client uses workspace-write sandboxing and on-request approvals; the Workspace access badge describes this policy. Command and file-change approvals require an explicit Allow Once or Decline response. Other server-initiated interactions return an unsupported-method error. The header's actions menu includes manual context compaction, reconnect, and Settings. Conversation text and tool details come from app-server history; the local index only stores task IDs, titles, and folders.

The bundle is locally ad-hoc signed. The MVP supports text chat and tool activity, without attachments, native sign-in, or custom MCP widgets. Both the executable and the required code-mode helper must come from the matching custom harness build.

Click the model and effort control beside the composer to choose a model or adjust the stepped reasoning-effort control. Choices come from the harness's model catalog; the reset arrow restores its default model and effort. Selection is locked while a turn runs and applies to the next message. Preferences are saved separately from credentials in `~/Library/Application Support/JevCodex/model-preferences.json`. If a saved model or effort is no longer supported, the picker falls back to an available default when it reconnects.

The sidebar groups saved tasks by their actual project folder. Use the search icon to filter task titles or project paths. Pin a task with its context menu or the header's pin button; pins persist in `~/Library/Application Support/JevCodex/pinned-tasks.json`. Tool activity expands inline, and the header's copy button copies the current transcript. Settings and the connected account appear at the bottom of the sidebar.
