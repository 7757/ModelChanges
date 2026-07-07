#!/bin/bash
# Build ModelChanges and wrap it into a double-clickable macOS .app bundle.
#
# Usage:
#   Scripts/build_app.sh            # debug build (fast)
#   Scripts/build_app.sh release    # optimized build
#   Scripts/build_app.sh release run # build + launch

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
APP_NAME="ModelChanges"
BUNDLE_ID="com.lifespace.modelchanges"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
    echo "✗ Build product not found at $BIN" >&2
    exit 1
fi

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Bundle the Ollama runtime so users never install Ollama separately.
if [[ ! -x "$ROOT/vendor/ollama-runtime/ollama" ]]; then
    echo "▸ Preparing bundled Ollama runtime…"
    "$ROOT/Scripts/prepare_runtime.sh"
fi
echo "▸ Bundling Ollama runtime…"
mkdir -p "$APP/Contents/Resources/ollama-runtime"
cp -R "$ROOT/vendor/ollama-runtime/." "$APP/Contents/Resources/ollama-runtime/"
chmod +x "$APP/Contents/Resources/ollama-runtime/ollama" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>ModelChanges</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing…"
# Re-sign the bundled runtime binaries (thinned to arm64, so old signatures are stale).
if [[ -d "$APP/Contents/Resources/ollama-runtime" ]]; then
    find "$APP/Contents/Resources/ollama-runtime" -type f \
        \( -name "*.dylib" -o -name "ollama" -o -name "llama-server" -o -name "llama-quantize" -o -name "mlx_metal_*" \) \
        -exec codesign --force --sign - {} \; 2>/dev/null || true
fi
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Built $APP"

if [[ "${2:-}" == "run" ]]; then
    echo "▸ Launching…"
    open "$APP"
fi
