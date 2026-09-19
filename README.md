# Codex–Jev

Experimental Jev compression for Codex: a custom engine, a bridge for the official desktop app, a menu bar launcher with Settings, and a pink Dock shortcut.

This is an independent project, not an official OpenAI or TypeSafe release. The desktop integration uses undocumented launch hooks that may change with app updates. It does not modify the installed official app bundle.

## Components

| Component | Purpose |
| --- | --- |
| Menu bar launcher | Toggle the Jev trial instance on/off, open Codex, and find settings and logs. |
| [Desktop bridge](macos-app/bridge/README.md) | Check eligible outgoing messages with Jev before forwarding them to the custom engine. |
| [Custom engine](JEV.md) | Reduce eligible tool output and older tool exchanges using bounded, extractive compression. |
| Dock wrapper | Pink Codex Jev.app shortcut that opens the official app with Jev enabled. |

## Build on macOS

Requires macOS 14+, Xcode Command Line Tools with Swift 6, Rust 1.95.0 via rustup, and Python 3.11+. Tested on Apple Silicon; Intel builds are unverified. Live use requires a Codex login and a TypeSafe API key. This is a source release with local ad-hoc signing, not a notarized installer.

```sh
git clone https://github.com/yannip1234/codex-jev.git
cd codex-jev
python3 macos-app/build-backend.py
mkdir -p dist
macos-app/launcher/build-launcher.sh "$PWD/dist"
macos-app/launcher/build-dock-app.sh "$PWD/dist"
open "dist/Codex Jev Launcher.app"
```

The backend build downloads and verifies pinned upstream V8 artifacts. It can take substantial time and disk space. The menu bar app bundles its engine, bridge, and message helper; the old JevCodex chat app is no longer required. Keep `Codex Jev.app` beside `Codex Jev Launcher.app` if using the Dock shortcut. Drag the pink `Codex Jev.app` into the Dock to keep it there. Clicking it opens or activates the official Codex app with Jev enabled. Quitting the Dock wrapper does not quit Codex.

## Use the menu bar toggle

Click **Jev** in the macOS menu bar, then **Use Codex–Jev**. On starts a separate official-app profile using the Jev bridge. Off asks before closing that trial instance, then opens standard Codex. It never force-quits the trial or closes regular Codex instances. Switching cannot hot-swap the engine inside an active turn; finish work before switching off.

The indicator reflects whether the Jev trial application is running, not API health or guaranteed compression. Quitting the launcher leaves Codex running. Use **Choose Codex App…** if your installation is not at the detected `/Applications/ChatGPT.app` or `/Applications/Codex.app` path. Choose an app while the toggle is off.

**Jev → Settings…** opens Settings directly in the menu bar app. Paste your TypeSafe key into the secure field and click **Save Key**. The existing saved key is never displayed. You can replace or remove it and change compression options here; changes apply to the next request without restarting Codex. A valid saved key takes priority over `TYPESAFE_API_KEY`. Standard Edit shortcuts (including ⌘V to paste and ⌘A to select all) work in the Settings field. Outgoing-message compression has a separate toggle; tool-output compression and history compaction are configured independently. The official app itself does not gain Jev Settings controls.

Choose **Outgoing mode → Strict (caveman)** for terse, telegraphic messages. Both modes send the entire eligible text to Jev. Every whitespace-delimited word occurrence is mechanically numbered; Jev decides whether it carries needed task information and whether it belongs to code, quotations, literal values, or other material that must stay verbatim. There are no filler dictionaries, syntax detectors, or preselected word candidates in this outgoing pass. Words are judged in batches of up to 96, each with the full original text. Code applies the judgments by deleting source spans, then Jev separately verifies meaning, constraints, and verbatim material together. Strict tries a more conservative cutoff if its first proposal fails. Balanced favors a readable request and requires a larger saving. Failed or incomplete reviews keep the original. Changing modes applies to the next message.

This is source-word deletion, not a guarantee of the shortest possible prompt. Word boundaries are whitespace, so languages without spaces receive coarser decisions. Each API request has a 15-second limit; selection stops starting new batches after 30 seconds, with up to two verification requests afterward. The bridge has an 85-second outer timeout. Large or slow reviews may therefore send the original rather than partially reviewed text.

Strict does not change automatic history compaction. Context-limit compaction tries Jev's older-tool-exchange removal first, then falls back to normal Codex compaction if it cannot safely save enough. History selection keeps images and encrypted checkpoints unchanged in Codex history and sends Jev explicit placeholders for those opaque fields. Unknown content cannot establish redundancy. Text judgment payloads remain bounded at 90 KB, and an accepted history reduction must save at least 25% of estimated tokens. Token-budget compaction and model downshifts bypass that Jev path. The official “Context automatically compacting” indicator does not identify which compactor ran.

Settings and the menu show **Original → After compaction → Saved** token estimates, with separate outgoing-message, tool-output and history totals. They survive app restarts by reading local metadata logs. Tracking starts with records produced by this version; earlier records without before/after counts are excluded. These are cumulative processing estimates, not billing totals: history passes may count retained text again. Native engine counts require relaunching the Jev trial after an engine update.

OpenAI authentication remains separate and uses your existing Codex home. If needed:

```sh
"./dist/Codex Jev Launcher.app/Contents/Resources/codex-jev" login
```

You can also use `"./dist/Codex Jev Launcher.app/Contents/Resources/Try-Official-Codex-with-Jev.command"`. Set `JEV_OFFICIAL_APP` for a non-default app path with that script. The isolated desktop profile shares your existing Codex authentication, task storage, and settings. Remote control is disabled for the trial process to avoid competing with the regular app's enrolled server.

## Logs and data

```sh
tail -f "${CODEX_HOME:-$HOME/.codex}/jev-bridge/activity.jsonl"
```

The bridge log contains timestamps, API attempt counts, statuses, and estimated savings. Native engine outcomes are written to `jev-bridge/engine-activity.jsonl`, including API attempts, explicit skip/fallback reasons, and before/after estimates for processed tool output or history. It contains no message bodies or keys. An entry describes preprocessing, not billing or proof of turn completion.

Eligible messages are sent to the TypeSafe API. Enabled tool/history compression can send eligible tool contents and relevant context there too. Jev incurs separate usage. Message compression accepts one plain text item, up to 40 KB, with no text-element offsets. Attachments and multipart text bypass that pass; a file read can qualify separately as tool output. Compression does not rewrite files on disk.

Retained text is copied from the source. Tool output can represent exact repeated blocks with source-line references while retaining every distinct block verbatim; Jev checks the complete proposal. Semantic deletion requires a combined preservation check. API failures, timeouts, uncertainty, and insufficient savings preserve the original. Older tool exchanges can be removed during Jev history compaction; standard Codex compaction remains the fallback. The visible chat transcript is not cleared.

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
JEV_TEST_FILTER="$PWD/dist/Codex Jev Launcher.app/Contents/Resources/jev-message-filter" \
  python3 -m unittest discover -s macos-app/bridge -p 'test_*.py' -v
```

Shared settings/compressor regression tests (in the retained legacy source package): `swift test --package-path macos-app`; see the [native README](macos-app/README.md) for the standalone toolchain workaround. Engine test instructions are in [JEV.md](JEV.md).

Local checks include 38 Swift tests (including clipboard shortcuts, word coverage, literal preservation, rejection of meaning loss, and usage totals), five bridge protocol tests, a live helper/key-priority check, and 104 scoped Rust compaction regressions. Four live Strict message examples produced reductions; one went from approximately 24 to 8 tokens and a code-containing example from 31 to 15 with its code unchanged. A separate live native tool-compressor test accepted a repetitive-log reduction. A full app-server exercise confirmed actual Jev tool/history API requests, but both proposals were rejected and native history fallback preserved the next response. Those full-engine checks do not establish accepted history savings. A long outgoing courtesy fixture also retained its original after a failed preservation check. These are examples, not an accuracy or cost benchmark.

The menu launcher builds, its instance-selection/environment checks pass, and the Settings layout and counters were checked visually. The toggle's full interactive flow is still not exhaustively tested. This demonstrates the integration, not complete desktop compatibility. Upstream GitHub Actions are disabled pending a project-specific CI setup.

## Upstream and license

Based on [OpenAI Codex](https://github.com/openai/codex), source commit `7498521d288b9b3b96ffba4eedf089d8d6e06a84`. Imported source and local changes remain in Git history. See [LICENSE](LICENSE), [NOTICE](NOTICE), and the preserved [upstream README](README.upstream.md).

## Acknowledgments

Inspired by [tamaratran/fast-jev-compaction](https://github.com/tamaratran/fast-jev-compaction), which uses Jev to decide which older tool calls and results to retain for Claude Code. That project motivated exploring a similar approach for the Codex engine and desktop workflow.

Strict outgoing mode also draws inspiration from [Caveman](https://github.com/JuliusBrussee/caveman): omit expendable prose while retaining exact technical details. The implementation here uses Jev judgments and source-span deletion, not the Caveman CLI.
