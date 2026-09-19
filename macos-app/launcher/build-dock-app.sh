#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:?Usage: build-dock-app.sh /absolute/output/directory}"
APP="$OUTPUT/Codex Jev.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
STAGING="$(mktemp "$APP/Contents/MacOS/DockLauncher.XXXXXX")"
ICONSET="$(mktemp -d)/AppIcon.iconset"
trap 'rm -f "$STAGING"; rm -rf "$(dirname "$ICONSET")"' EXIT
swiftc -O -target "$(uname -m)-apple-macos14.0" -parse-as-library "$SOURCE/DockApp.swift" -o "$STAGING"
chmod 755 "$STAGING"; mv -f "$STAGING" "$APP/Contents/MacOS/DockLauncher"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$SOURCE/PinkIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$SOURCE/PinkIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codexjev.dock</string>
<key>CFBundleName</key><string>Codex Jev</string>
<key>CFBundleExecutable</key><string>DockLauncher</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
