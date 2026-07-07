#!/bin/bash
# Build a release .app, install it to /Applications, and produce a drag-to-install DMG.
#
# Usage: Scripts/package.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="ModelChanges"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

echo "▸ Quitting any running instance…"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1

echo "▸ Building release .app…"
"$ROOT/Scripts/build_app.sh" release >/dev/null
echo "  built $APP"

echo "▸ Installing to /Applications…"
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP" "/Applications/$APP_NAME.app"
# Locally built → not quarantined, but strip just in case so Gatekeeper stays quiet.
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true
echo "  installed /Applications/$APP_NAME.app"

echo "▸ Building DMG…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "  created $DMG ($(du -h "$DMG" | cut -f1))"

echo "✓ Done. Installed to /Applications and packaged $DMG"
