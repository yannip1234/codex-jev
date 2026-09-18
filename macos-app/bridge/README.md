# Official Codex app bridge (experimental)

Build the native app bundle first, then run `./macos-app/bridge/build-bridge.sh /absolute/output/directory`. Keep the generated bridge, message filter, launcher, and `JevCodex.app` together. Python 3 and macOS are required.

Open `Try-Official-Codex-with-Jev.command` in that output directory. It launches `/Applications/ChatGPT.app` (override with `JEV_OFFICIAL_APP`) with `CODEX_CLI_PATH` pointing to the bridge and `CODEX_APP_SERVER_FORCE_CLI=1`. These are undocumented implementation hooks verified in the installed app, and may change with updates. No app bundle is modified. The separate Electron profile is `~/Library/Application Support/Codex-Jev-Bridge`; Codex authentication, settings, and task storage still use the existing Codex home. Remote control is disabled for this trial process to avoid competing with the regular app's enrolled remote server.

The official app sends JSON-RPC through the bridge to the bundled custom engine. Plain text in `turn/start` and `turn/steer` is checked by the same Swift compression logic as the native client. The standalone helper uses system curl because Foundation requests timed out in this command-line process. API credentials and request bodies enter curl through stdin, never command arguments or temporary files. TLS verification remains enabled, redirects are not followed, and requests have 15-second limits. Saved Settings credentials take priority over `TYPESAFE_API_KEY`.

Only a single plain text item with no text-element offsets is eligible. Multipart text, attachments, routing, models, reasoning effort, tool activity, approvals, and other RPC messages pass through. Each task keeps its request order; responses to server approval requests bypass the filter queue. API failures and a 35-second helper timeout retain the original message. Non-stdio CLI commands pass directly to the real engine.

The native app's message-compression toggle also controls the bridge (`$CODEX_HOME/jev-message-settings.json`). Use native Jev Codex Settings to edit the key and preferences; this experiment does not add Jev controls to the official app's Settings. Original/prepared text archives remain under `jev-message-originals`. A metadata-only `jev-bridge/activity.jsonl` reports API attempts and estimated savings. It records preprocessing, not provider billing or proof of turn completion. The official app may display the shortened text when it receives the engine's turn data.

Quit the trial window and open the official app normally to return to its standard engine. Existing regular instances are unaffected by the launcher. The hooks, all desktop features, and future app versions are not compatibility guarantees.

Verification:

```sh
python3 -m unittest discover -s macos-app/bridge -p 'test_*.py' -v
# Optional: makes actual Jev API requests using the existing saved key.
JEV_TEST_FILTER=/absolute/output/jev-message-filter python3 -m unittest discover -s macos-app/bridge -p 'test_*.py' -v
```

Locally verified: official desktop initialize handshake and catalog/account reads, five bridge protocol tests, saved-key precedence, and a real compressed Astra turn returning `BRIDGE_OK`. A message sent manually in the official app was also checked: approximately 185 to 44 estimated input tokens, two Jev API requests, and the expected `COMPACTION_OK` response. Automated control of the official app is unavailable; other desktop interactions have not been exhaustively tested.
