#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND="${1:?Usage: build-app.sh /absolute/path/to/codex-jev [output.app] [code-mode-host]}"
OUTPUT="${2:-$SOURCE_DIR/../../../outputs/JevCodex.app}"
HOST="${3:-$(dirname "$BACKEND")/codex-code-mode-host}"
test -x "$BACKEND" || { echo "Backend must be executable: $BACKEND" >&2; exit 1; }
test -x "$HOST" || { echo "Matching code-mode helper must be executable: $HOST" >&2; exit 1; }
swift build --package-path "$SOURCE_DIR" -c release
BIN_DIR="$(swift build --package-path "$SOURCE_DIR" -c release --show-bin-path)"
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$BIN_DIR/JevCodex" "$OUTPUT/Contents/MacOS/JevCodex"
cp "$BACKEND" "$OUTPUT/Contents/Resources/codex-jev"
cp "$SOURCE_DIR/../LICENSE" "$SOURCE_DIR/../NOTICE" "$SOURCE_DIR/../JEV.md" "$OUTPUT/Contents/Resources/"
cp "$HOST" "$OUTPUT/Contents/Resources/codex-code-mode-host"
cat > "$OUTPUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.jevcodex.native</string>
<key>CFBundleName</key><string>Jev Codex</string>
<key>CFBundleDisplayName</key><string>Jev Codex</string>
<key>CFBundleExecutable</key><string>JevCodex</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$OUTPUT"
codesign --verify --deep --strict "$OUTPUT"
echo "Built $OUTPUT"
