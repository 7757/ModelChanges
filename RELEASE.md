# Release Checklist

Use this checklist for every ModelChanges release.

## Before Release

1. Update the app version in `Scripts/build_app.sh`.
2. Add an English entry to `CHANGELOG.md`.
3. Sync the website changelog copy in `docs/i18n.js`.
4. Run `swift build`.
5. Run `./Scripts/build_app.sh release`.
6. Install locally and verify the app launches:

   ```bash
   pkill -x ModelChanges 2>/dev/null || true
   rm -rf /Applications/ModelChanges.app
   ditto dist/ModelChanges.app /Applications/ModelChanges.app
   xattr -cr /Applications/ModelChanges.app
   open /Applications/ModelChanges.app
   ```

7. Verify the website with a local static server and headless Chrome screenshots.
8. Run the installer script against the intended release asset.

## Package

```bash
./Scripts/build_app.sh release
mkdir -p dist/release
ditto -c -k --keepParent dist/ModelChanges.app dist/release/ModelChanges-macOS.zip
cp dist/release/ModelChanges-macOS.zip dist/release/ModelChanges-1.0.0-macOS.zip
shasum -a 256 dist/release/ModelChanges-1.0.0-macOS.zip
```

## Publish

```bash
gh release create v1.0.0 \
  dist/release/ModelChanges-macOS.zip \
  dist/release/ModelChanges-1.0.0-macOS.zip \
  --target main \
  --title "ModelChanges 1.0.0" \
  --notes-file CHANGELOG.md
gh release list
```

## Website

```bash
git push
gh repo edit 7757/ModelChanges \
  --homepage "https://7757.github.io/ModelChanges/" \
  --add-topic macos --add-topic ollama --add-topic local-ai --add-topic swiftui
```

Verify:

```bash
curl -I https://7757.github.io/ModelChanges/
curl -I https://github.com/7757/ModelChanges/releases/latest/download/ModelChanges-macOS.zip
```
