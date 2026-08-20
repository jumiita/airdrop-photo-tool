#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AirDrop HEIC Converter Status.app"
EXECUTABLE="AirDropPhotoTool"
CONTENTS="$APP_NAME/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [[ -d "$APP_NAME" ]]; then
  /usr/bin/find "$APP_NAME" -depth -mindepth 1 -delete
fi
mkdir -p "$MACOS" "$RESOURCES"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>es</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>com.juma.airdrop-photo-tool</string>
  <key>CFBundleName</key>
  <string>AirDrop HEIC Converter Status</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

swiftc -parse-as-library PhotoToolApp.swift -o "$MACOS/$EXECUTABLE"
cp heic_airdrop_watcher.py install.sh uninstall.sh "$RESOURCES/"
chmod +x "$RESOURCES/heic_airdrop_watcher.py" "$RESOURCES/install.sh" "$RESOURCES/uninstall.sh"
codesign --force --deep --sign - "$APP_NAME" >/dev/null 2>&1 || true

mkdir -p "$HOME/Applications"
if [[ -d "$HOME/Applications/$APP_NAME" ]]; then
  /usr/bin/find "$HOME/Applications/$APP_NAME" -depth -mindepth 1 -delete
fi
/usr/bin/ditto "$APP_NAME" "$HOME/Applications/$APP_NAME"

echo "App creada: $HOME/Applications/$APP_NAME"
