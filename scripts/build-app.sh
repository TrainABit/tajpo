#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product Tajpo
BIN_DIR="$(swift build -c release --product Tajpo --show-bin-path)"
APP="$ROOT/build/Tajpo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tajpo" "$APP/Contents/MacOS/Tajpo"
cp "$ROOT/Sources/Tajpo/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.trainabit.tajpo' "$APP/Contents/Info.plist"
RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 2 -name 'Tajpo_TajpoCore.bundle' -print -quit 2>/dev/null || true)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/Tajpo_TajpoCore.bundle"
fi
# Keep a direct copy for ad-hoc preview bundles; the loader supports both layouts.
cp "$ROOT/Sources/TajpoCore/Resources/demo-lexicon.json" "$APP/Contents/Resources/demo-lexicon.json"
test -f "$APP/Contents/Resources/demo-lexicon.json"
cp "$ROOT/Sources/TajpoCore/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
chmod +x "$APP/Contents/MacOS/Tajpo"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
