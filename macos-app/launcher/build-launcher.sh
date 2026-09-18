#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:?Usage: build-launcher.sh /absolute/output/directory}"
APP="$OUTPUT/Codex Jev Launcher.app"
mkdir -p "$APP/Contents/MacOS"
STAGING="$(mktemp "$APP/Contents/MacOS/Launcher.XXXXXX")"
trap 'rm -f "$STAGING"' EXIT
swiftc -O -target "$(uname -m)-apple-macos14.0" -parse-as-library \
  "$SOURCE/LauncherConfiguration.swift" "$SOURCE/LauncherApp.swift" -o "$STAGING"
chmod 755 "$STAGING"
mv -f "$STAGING" "$APP/Contents/MacOS/Launcher"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codexjev.launcher</string>
<key>CFBundleName</key><string>Codex Jev Launcher</string>
<key>CFBundleExecutable</key><string>Launcher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
