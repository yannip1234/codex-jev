#!/bin/bash
set -euo pipefail
OUTPUT="$(cd "$(dirname "$0")" && pwd)"
APP="${JEV_OFFICIAL_APP:-/Applications/ChatGPT.app}"
PROFILE="$HOME/Library/Application Support/Codex-Jev-Bridge"
RUNTIME="$OUTPUT/Codex Jev Launcher.app/Contents/Resources"
if [ -x "$OUTPUT/codex-jev" ] && [ -x "$OUTPUT/jev-message-filter" ]; then RUNTIME="$OUTPUT"; fi
test -d "$APP" || { echo "Official Codex app not found: $APP" >&2; exit 1; }
test -x "$RUNTIME/codex-jev-bridge"
test -x "$RUNTIME/jev-message-filter"
test -x "$RUNTIME/codex-jev"
mkdir -p "$PROFILE"
/usr/bin/open -n \
  --env "CODEX_CLI_PATH=$RUNTIME/codex-jev-bridge" \
  --env "CODEX_APP_SERVER_FORCE_CLI=1" \
  --env "CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED=1" \
  --env "CODEX_ELECTRON_USER_DATA_PATH=$PROFILE" \
  "$APP" --args "--user-data-dir=$PROFILE"
