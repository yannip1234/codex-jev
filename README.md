# Codex–Jev

Experimental Jev compression for Codex: a custom engine, a bridge for the official desktop app, a native macOS chat client, and a menu bar launcher.

This is an independent project, not an official OpenAI or TypeSafe release. The desktop integration uses undocumented launch hooks that may change with app updates. It does not modify the installed official app bundle.

## Components

| Component | Purpose |
| --- | --- |
| Menu bar launcher | Toggle the Jev trial instance on/off, open Codex, and find settings and logs. |
| [Desktop bridge](macos-app/bridge/README.md) | Check eligible outgoing messages with Jev before forwarding them to the custom engine. |
| [Custom engine](JEV.md) | Reduce eligible tool output and older tool exchanges using bounded, extractive compression. |
| [Native macOS app](macos-app/README.md) | SwiftUI chat client with Jev settings, model/effort selection, activity, attachments, goals, and plan mode. |

## Build on macOS

Requires macOS 14+, Xcode Command Line Tools with Swift 6, Rust 1.95.0 via rustup, and Python 3.11+. Tested on Apple Silicon; Intel builds are unverified. Live use requires a Codex login and a TypeSafe API key. This is a source release with local ad-hoc signing, not a notarized installer.

```sh
git clone https://github.com/yannip1234/codex-jev.git
cd codex-jev
python3 macos-app/build-backend.py
mkdir -p dist
macos-app/build-app.sh \
  "$PWD/codex-rs/target/dev-small/codex" \
  "$PWD/dist/JevCodex.app" \
  "$PWD/codex-rs/target/dev-small/codex-code-mode-host"
macos-app/bridge/build-bridge.sh "$PWD/dist"
macos-app/launcher/build-launcher.sh "$PWD/dist"
open "dist/Codex Jev Launcher.app"
```

The backend build downloads and verifies pinned upstream V8 artifacts. It can take substantial time and disk space. Keep the whole `dist` folder together: the launcher, bridge, helper, and native app bundle are dependencies of one another.

## Use the menu bar toggle

Click **Jev** in the macOS menu bar, then **Use Codex–Jev**. On starts a separate official-app profile using the Jev bridge. Off asks before closing that trial instance, then opens standard Codex. It never force-quits the trial or closes regular Codex instances. Switching cannot hot-swap the engine inside an active turn; finish work before switching off.

The indicator reflects whether the Jev trial application is running, not API health or guaranteed compression. Quitting the launcher leaves Codex running. Use **Choose Codex App…** if your installation is not at the detected `/Applications/ChatGPT.app` or `/Applications/Codex.app` path. Choose an app while the toggle is off.

**Open Jev Codex (settings)** opens the native client. Press Command-comma there to save your TypeSafe key and configure compression. A valid saved key takes priority over `TYPESAFE_API_KEY`. Outgoing-message compression has a separate toggle; tool-output compression and history compaction are configured independently. The official app itself does not gain Jev Settings controls.

OpenAI authentication remains separate and uses your existing Codex home. If needed:

```sh
./dist/JevCodex.app/Contents/Resources/codex-jev login
```

You can also use `./dist/Try-Official-Codex-with-Jev.command`. Set `JEV_OFFICIAL_APP` for a non-default app path with that script. The isolated desktop profile shares your existing Codex authentication, task storage, and settings. Remote control is disabled for the trial process to avoid competing with the regular app's enrolled server.

## Logs and data

```sh
tail -f "${CODEX_HOME:-$HOME/.codex}/jev-bridge/activity.jsonl"
```

The log contains timestamps, API attempt counts, statuses, and estimated savings. It contains no message bodies or keys. An entry describes preprocessing, not billing or proof of turn completion.

Eligible messages are sent to the TypeSafe API. Enabled tool/history compression can send eligible tool contents and relevant context there too. Jev incurs separate usage. Message compression accepts one plain text item, up to 40 KB, with no text-element offsets. Attachments and multipart text bypass that pass; a file read can qualify separately as tool output. Compression does not rewrite files on disk.

Kept passages are copied from the source. Semantic deletion requires verification; exact duplicate removal retains a copy of every distinct passage. API failures, timeouts, uncertainty, and insufficient savings preserve the original. Older tool exchanges can be removed during Jev history compaction; standard Codex compaction remains the fallback. The visible chat transcript is not cleared.

Private local original/prepared message archives are stored in `$CODEX_HOME/jev-message-originals`; tool/history originals are in `jev-originals` (default Codex home: `~/.codex`). These archives can contain sensitive content and must not be committed. Compression adds latency and can change meaning despite checks. Savings are estimated, not tokenizer-exact billing. Equal task accuracy and lower total cost have not been established by a benchmark.

## Verification

```sh
# Bridge protocol checks; no API requests.
python3 -m unittest discover -s macos-app/bridge -p 'test_*.py' -v
# Launcher instance selection and environment isolation checks.
swiftc -parse-as-library macos-app/launcher/LauncherConfiguration.swift \
  macos-app/launcher/LauncherTests.swift -o /tmp/jev-launcher-tests
/tmp/jev-launcher-tests
# Optional live helper test; uses the saved key and makes Jev API requests.
JEV_TEST_FILTER="$PWD/dist/jev-message-filter" \
  python3 -m unittest discover -s macos-app/bridge -p 'test_*.py' -v
```

Native tests: `swift test --package-path macos-app`; see the [native README](macos-app/README.md) for the standalone toolchain workaround. Engine test instructions are in [JEV.md](JEV.md).

Prior local checks included five bridge protocol tests, a live helper/key-priority test, 35 native tests, and scoped Rust checks. A manually sent official-app message was reduced from approximately 185 to 44 estimated input tokens and received `COMPACTION_OK`. The menu launcher builds and its instance-selection/environment checks pass; automated menu inspection timed out, so the toggle's full interactive flow remains unverified. This demonstrates the integration, not complete desktop compatibility. Upstream GitHub Actions are disabled pending a project-specific CI setup.

## Upstream and license

Based on [OpenAI Codex](https://github.com/openai/codex), source commit `7498521d288b9b3b96ffba4eedf089d8d6e06a84`. Imported source and local changes remain in Git history. See [LICENSE](LICENSE), [NOTICE](NOTICE), and the preserved [upstream README](README.upstream.md).
