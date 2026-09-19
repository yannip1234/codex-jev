#!/bin/bash
set -euo pipefail
APP_SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:?Usage: build-bridge.sh /absolute/output/directory}"
mkdir -p "$OUTPUT"
STAGING="$(mktemp "$OUTPUT/jev-message-filter.XXXXXX")"
trap 'rm -f "$STAGING"' EXIT
swiftc -O -target "$(uname -m)-apple-macos14.0" -parse-as-library \
  "$APP_SOURCE/Sources/JevCodex/MessageCompressor.swift" \
  "$APP_SOURCE/Sources/JevCodex/MessageWordSpans.swift" \
  "$APP_SOURCE/Sources/JevCodex/SettingsStore.swift" \
  "$APP_SOURCE/Sources/JevCodex/CompressionStatus.swift" \
  "$APP_SOURCE/bridge/MessageFilter.swift" -o "$STAGING"
chmod 755 "$STAGING"
codesign --force --sign - "$STAGING"
mv -f "$STAGING" "$OUTPUT/jev-message-filter"
cp "$APP_SOURCE/bridge/codex-jev-bridge.py" "$OUTPUT/codex-jev-bridge"
cp "$APP_SOURCE/bridge/Try-Official-Codex-with-Jev.command" "$OUTPUT/"
chmod 755 "$OUTPUT/codex-jev-bridge" "$OUTPUT/jev-message-filter"
chmod 755 "$OUTPUT/Try-Official-Codex-with-Jev.command"
