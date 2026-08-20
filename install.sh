#!/usr/bin/env bash
set -euo pipefail

LABEL="com.juma.airdrop-heic-converter"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
OUTPUT_FORMAT="${AIRDROP_OUTPUT_FORMAT:-jpg}"
WATCH_DIR="${AIRDROP_CONVERT_DIR:-$HOME/Downloads}"
DELETE_ORIGINAL="${AIRDROP_DELETE_ORIGINAL:-false}"
ASK_DELETE_ORIGINAL="${AIRDROP_ASK_DELETE_ORIGINAL:-true}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/airdrop-heic-converter"

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON_BIN</string>
    <string>$SCRIPT_DIR/heic_airdrop_watcher.py</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>AIRDROP_CONVERT_DIR</key>
    <string>$WATCH_DIR</string>
    <key>AIRDROP_OUTPUT_FORMAT</key>
    <string>$OUTPUT_FORMAT</string>
    <key>AIRDROP_DELETE_ORIGINAL</key>
    <string>$DELETE_ORIGINAL</string>
    <key>AIRDROP_ASK_DELETE_ORIGINAL</key>
    <string>$ASK_DELETE_ORIGINAL</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardInPath</key>
  <string>/dev/null</string>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/launchd.err.log</string>
</dict>
</plist>
PLIST

chmod +x "$SCRIPT_DIR/heic_airdrop_watcher.py"

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Instalado y arrancado."
echo "Vigilando: $WATCH_DIR"
echo "Formato de salida: .$([[ "$OUTPUT_FORMAT" == "png" ]] && echo PNG || echo JPG)"
echo "Logs: $LOG_DIR/watcher.log"
