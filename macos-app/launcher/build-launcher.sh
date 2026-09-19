#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:?Usage: build-launcher.sh /absolute/output/directory}"
APP="$OUTPUT/Codex Jev Launcher.app"
REPO="$(cd "$SOURCE/../.." && pwd)"
BACKEND="${2:-$REPO/codex-rs/target/dev-small/codex}"
HOST="${3:-$(dirname "$BACKEND")/codex-code-mode-host}"
test -x "$BACKEND"
test -x "$HOST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
STAGING="$(mktemp "$APP/Contents/MacOS/Launcher.XXXXXX")"
trap 'rm -f "$STAGING"' EXIT
swiftc -O -target "$(uname -m)-apple-macos14.0" -parse-as-library \
  "$SOURCE/LauncherConfiguration.swift" "$SOURCE/LauncherApp.swift" "$SOURCE/LauncherSettings.swift" \
  "$SOURCE/../Sources/JevCodex/SettingsStore.swift" \
  "$SOURCE/../Sources/JevCodex/SettingsEditingMenu.swift" \
  "$SOURCE/../Sources/JevCodex/MessageCompressor.swift" \
  "$SOURCE/../Sources/JevCodex/MessageWordSpans.swift" \
  "$SOURCE/../Sources/JevCodex/CompressionUsage.swift" \
  "$SOURCE/../Sources/JevCodex/CompressionStatus.swift" -o "$STAGING"
chmod 755 "$STAGING"
mv -f "$STAGING" "$APP/Contents/MacOS/Launcher"
"$SOURCE/../bridge/build-bridge.sh" "$APP/Contents/Resources"
for SOURCE_BINARY in "$BACKEND" "$HOST"; do
  NAME="codex-jev"
  if [ "$SOURCE_BINARY" = "$HOST" ]; then NAME="codex-code-mode-host"; fi
  STAGING="$(mktemp "$APP/Contents/Resources/$NAME.XXXXXX")"
  cp "$SOURCE_BINARY" "$STAGING"
  chmod 755 "$STAGING"
  mv -f "$STAGING" "$APP/Contents/Resources/$NAME"
done
cp "$REPO/LICENSE" "$REPO/NOTICE" "$REPO/JEV.md" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codexjev.launcher</string>
<key>CFBundleName</key><string>Codex Jev Launcher</string>
<key>CFBundleExecutable</key><string>Launcher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>Codex Jev Launcher</string>
<key>CFBundleURLSchemes</key><array><string>codex-jev</string></array>
</dict></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
