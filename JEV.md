# Jev Codex — custom harness

This fork adds extractive Jev compression to OpenAI Codex. It includes a native SwiftUI macOS app and the terminal UI. It does not modify the installed OpenAI desktop app.

## Use

Launch **Jev Codex.app** and open **Settings** to save a Jev/TypeSafe API key and enable or disable tool-output compression and history compaction. The terminal equivalent is `/jev`. The native composer also includes a model/effort popover populated from the harness model catalog; selections are validated, saved locally and applied to the next turn.

The valid key saved in Settings at `$CODEX_HOME/jev-api-key` (default `~/.codex/jev-api-key`) takes priority. The harness uses a valid `TYPESAFE_API_KEY` environment variable only when the saved key is missing or invalid. The saved key is a private local file, not part of config.toml or a conversation. Preferences are in `jev-settings.json` in the same directory. Removing the saved key does not unset an inherited environment variable. No Jev calls are made without a configured key.

OpenAI authentication remains separate; this app uses the Codex home and login already configured locally. The native app connects to its bundled custom `codex-jev app-server` process. Project permissions and approval requests remain enforced by Codex.

## Tool output

The final history-recording boundary compresses eligible text returned by tools, including the final output printed by code-mode scripts. It does not alter the objects returned to running JavaScript or the tools' actual execution.

Jev judges numbered source blocks, then checks the proposed omissions together. Kept passages remain verbatim and carry line references. Short results, failed outputs, arbitrary structured JSON, code fences and multimodal output are preserved. Recognized shell-result JSON wrappers retain status, session IDs and timing fields. Each accepted result must save at least 25% by Codex's approximate token estimator, including its recovery reference. This is an estimate, not tokenizer-exact billing.

Inputs are bounded: eligible text is 8–64 KB, user requirements at most 16 KB, at most 48 block questions, each Jev HTTP request at most 120 KB/15 seconds, and a whole history append has a 35-second compression deadline. Any unsupported case, API failure, malformed response, uncertain judgment or insufficient saving preserves the original behavior.

## Compaction

Manual compaction and eligible automatic context-limit compaction first attempt Jev selection. All conversation text/instructions, recent context and the current user turn remain. Only complete, unambiguous older tool call/result groups are candidates, with their IDs and retained metadata preserved. Selection and combined verification run in bounded sequential batches, so later decisions see earlier omissions. If the final result cannot save at least 25%, native Codex compaction runs normally. Token-budget mode and model-compatibility transitions retain native behavior.

Original outputs and pre-compaction histories are saved under `$CODEX_HOME/jev-originals` with private permissions. They remain there for recovery; delete old files only when you no longer need the references in saved conversations. Failed judgments do not prove that deletion is safe, and successful judgments do not guarantee semantic equivalence. This build is experimental; compare task accuracy as well as total Jev plus Codex cost.

## Build

Baseline: `openai/codex` commit `7498521d288b9b3b96ffba4eedf089d8d6e06a84`.

With Rust 1.95.0, Python 3.10+ and Swift 6, from the repository root:

```sh
python3 macos-app/build-backend.py
macos-app/build-app.sh "$PWD/codex-rs/target/dev-small/codex" "$PWD/JevCodex.app"
cd codex-rs
CARGO_PROFILE_DEV_SMALL_STRIP=none just test --cargo-profile dev-small -p codex-config -p codex-core -p codex-tui --lib -E 'test(jev) or test(compact) or test(record_conversation) or test(world_state)'
```

The backend script downloads and verifies upstream's pinned Codex V8 artifacts for the matching code-mode helper. Disabling stripping avoids a macOS dynamic-loader error observed with stripped proc-macro libraries on this machine. Native app packaging instructions are in `macos-app/README.md`. The local artifact is an Apple Silicon development build, ad-hoc signed for local use, not notarized for distribution.

No API key is included in the source, app bundle, patches or test fixtures.
