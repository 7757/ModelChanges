#!/bin/sh
set -eu

APP_NAME="ModelChanges"
OWNER="7757"
REPO="ModelChanges"
ZIP_URL="https://github.com/$OWNER/$REPO/releases/latest/download/$APP_NAME-macOS.zip"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

echo "Downloading $APP_NAME..."
curl -fL "$ZIP_URL" -o "$TMP_DIR/$APP_NAME-macOS.zip"

echo "Installing to /Applications..."
pkill -x "$APP_NAME" 2>/dev/null || true
ditto -x -k "$TMP_DIR/$APP_NAME-macOS.zip" "$TMP_DIR"
rm -rf "/Applications/$APP_NAME.app"
ditto "$TMP_DIR/$APP_NAME.app" "/Applications/$APP_NAME.app"
xattr -cr "/Applications/$APP_NAME.app" 2>/dev/null || true

echo "Opening $APP_NAME..."
open "/Applications/$APP_NAME.app"
echo "Done."
