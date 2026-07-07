#!/bin/bash
# Populate vendor/ollama-runtime with a trimmed (arm64-only) Ollama runtime that
# gets bundled inside ModelChanges.app so users never install Ollama separately.
#
# Source: a local /Applications/Ollama.app if present, else the official DMG.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/ollama-runtime"

SRC=""
DETACH=""
if [ -d "/Applications/Ollama.app/Contents/Resources" ]; then
    SRC="/Applications/Ollama.app/Contents/Resources"
    echo "▸ Using local Ollama.app as runtime source"
else
    echo "▸ Downloading official Ollama runtime…"
    TMP="$(mktemp -d)"; DMG="$TMP/Ollama.dmg"
    curl -fsSL "https://ollama.com/download/Ollama.dmg" -o "$DMG"
    MNT="$TMP/mnt"; mkdir -p "$MNT"
    hdiutil attach "$DMG" -nobrowse -mountpoint "$MNT" >/dev/null
    SRC="$MNT/Ollama.app/Contents/Resources"; DETACH="$MNT"
fi

echo "▸ Copying runtime → $DEST"
rm -rf "$DEST"; mkdir -p "$DEST"
cp -R "$SRC"/. "$DEST"/
[ -n "$DETACH" ] && hdiutil detach "$DETACH" -quiet || true

echo "▸ Trimming to arm64-only…"
rm -f "$DEST"/*.png "$DEST"/*.icns "$DEST"/libggml-cpu-*.so "$DEST"/libggml-blas.so
for f in "$DEST"/*; do
    if [ -f "$f" ] && file "$f" 2>/dev/null | grep -q "Mach-O universal"; then
        lipo "$f" -thin arm64 -output "$f.a" 2>/dev/null && mv "$f.a" "$f" || true
    fi
done
chmod +x "$DEST/ollama" 2>/dev/null || true

echo "✓ Runtime ready: $(du -sh "$DEST" | cut -f1)"
