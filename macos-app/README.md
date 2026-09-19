# Legacy Jev Codex chat client

The current product is the self-contained menu bar app and Dock wrapper. See the [main README](../README.md). This older chat-client source is retained for reference and regression tests; it is no longer required or built by the launcher instructions.

# Jev Codex for macOS

An experimental [official desktop bridge](bridge/README.md) can also launch the installed Codex app against this engine and check outgoing messages with Jev.

Native SwiftUI client for the custom `codex-jev app-server` harness. Requires macOS 14+ and a Swift 6 toolchain to build. It reuses the active Codex home's authentication and stores its task index in `~/Library/Application Support/JevCodex/tasks.json`.

```sh
python3 build-backend.py
swift test
./build-app.sh /absolute/path/to/codex-jev /absolute/path/to/JevCodex.app /absolute/path/to/codex-code-mode-host
open /absolute/path/to/JevCodex.app
```

For development, set `JEV_CODEX_BINARY=/absolute/path/to/codex-jev` before running `swift run`. Sign in with `codex login` if there is no existing Codex authentication. Open Settings with Command-comma to save the Jev key and configure compression. The valid key saved in app Settings takes precedence; `TYPESAFE_API_KEY` is used only if the saved key is missing or invalid. Settings apply to the next compression or compaction. The key is stored at `$CODEX_HOME/jev-api-key` (default `~/.codex/jev-api-key`) with mode 0600; preferences use `jev-settings.json` in the same directory.

Choose a project from the composer's plus menu. Return sends, Shift-Return or Option-Return inserts a newline, and Command-Return also sends. Files/folders are attached as explicit paths; images use the harness's local-image input (up to five images, 10 MB each). The Add menu also provides Plan mode and a persistent goal with an optional token budget. Starting/resuming a goal can launch work immediately; Pause stops future continuation, while Stop interrupts the current turn.

The approval picker applies to the next turn or resumed goal: Ask for approval uses workspace-write and on-request approvals; Approve for me uses the harness approval reviewer; Full access requires an explicit local selection and confirmation. New or reopened tasks default to Ask. Command and file-change approval requests have explicit Allow Once/Decline responses. Plan questions have a native answer sheet. Unsupported server interactions are declined.

Public reasoning summaries, current plan steps, running commands, file edits, and tool results appear in expandable activity. Raw reasoning is not displayed. The header actions include manual context compaction, reconnect, and Settings. Compaction completion is reported separately from the visible transcript, which remains intact. Settings distinguishes Jev configuration from saved recovery records and explains fallback to standard compaction. Recovery counts are not token savings or proof of API connectivity.

The bundle is locally ad-hoc signed. Native sign-in and custom MCP widgets are not implemented. Both the executable and the required code-mode helper must come from the matching custom harness build. With the standalone macOS 27 command-line toolchain, run tests with `swift test -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib` if automatic Swift Testing macro discovery fails.

Click the model and effort control beside the composer to choose a model or adjust the stepped reasoning-effort control. Choices come from the harness's model catalog; the reset arrow restores its default model and effort. Selection is locked while a turn runs and applies to the next message. Preferences are saved separately from credentials in `~/Library/Application Support/JevCodex/model-preferences.json`. If a saved model or effort is no longer supported, the picker falls back to an available default when it reconnects.

The sidebar groups saved tasks by their actual project folder. Use the search icon to filter task titles or project paths. Pin a task with its context menu or the header's pin button; pins persist in `~/Library/Application Support/JevCodex/pinned-tasks.json`. Tool activity expands inline, and the header's copy button copies the current transcript. Settings and the connected account appear at the bottom of the sidebar.

Outgoing text messages now pass through Jev in the native app before `turn/start`. This is enabled by default and controlled by **Compact my messages with Jev before sending** in Settings. The native app sends the message (up to 40 KB) to the TypeSafe API, asks which source passages are redundant, then checks the combined candidate. It accepts semantic deletion only after both preservation checks score at least 0.99. Otherwise it can remove Jev-selected exact duplicates while retaining every distinct passage. Protected text (including code, numeric values, quoted strings and negations) is kept. At least 10% and 16 estimated tokens must be saved. These thresholds are conservative heuristics, not a guarantee of semantic equivalence or lower total cost.

The composer shows a reduction or a fallback reason after the harness accepts the turn. Original and prepared text are privately archived under `$CODEX_HOME/jev-message-originals` before a reduction is submitted; an archive alone does not prove the turn was sent. The original is not appended to Codex input. Attachment references and images bypass this pass. Missing credentials, disabled settings, oversize text, API errors (15-second limit per request), failed checks or insufficient savings keep the original. Jev uses up to two requests per message and incurs separate usage. Short messages can be checked without being shortened. This feature is in the native client's Send path; terminal clients and goal/question RPCs are unchanged. Preferences are saved separately as `jev-message-settings.json`.
