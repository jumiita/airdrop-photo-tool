#!/usr/bin/env bash
set -euo pipefail

LABEL="com.juma.airdrop-heic-converter"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

echo "Desinstalado. Los archivos ya convertidos no se han tocado."
