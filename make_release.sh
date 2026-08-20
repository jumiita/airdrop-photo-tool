#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="AirDrop HEIC Converter Status.app"
ARCHIVE_NAME="AirDrop-Photo-Tool-$VERSION-macOS.zip"
DIST_DIR="dist"

./build_app.sh

mkdir -p "$DIST_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_NAME" "$DIST_DIR/$ARCHIVE_NAME"

echo "Release creada: $DIST_DIR/$ARCHIVE_NAME"
