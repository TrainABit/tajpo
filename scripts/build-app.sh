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
RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 4 -name 'Tajpo_TajpoCore.bundle' -print -quit 2>/dev/null || true)"
if [[ ! -d "$RESOURCE_BUNDLE/Contents" ]]; then
  # Some Swift toolchains place the bundle in a sibling build directory.
  RESOURCE_BUNDLE="$(find "$ROOT/.build" -type d -name 'Tajpo_TajpoCore.bundle' -print -quit 2>/dev/null || true)"
fi
if [[ -n "$RESOURCE_BUNDLE" && -d "$RESOURCE_BUNDLE/Contents" ]]; then
  RESOURCE_DEST="$APP/Contents/Resources/Tajpo_TajpoCore.bundle"
  rm -rf "$RESOURCE_DEST"
  mkdir -p "$RESOURCE_DEST"
  # Preserve the macOS bundle layout explicitly; do not let a flat copy reach
  # Bundle.module, which is fatal when Contents/Info.plist is missing.
  ditto "$RESOURCE_BUNDLE/Contents" "$RESOURCE_DEST/Contents"
  test -f "$RESOURCE_DEST/Contents/Info.plist"
  test -f "$RESOURCE_DEST/Contents/Resources/demo-lexicon.json"
fi
# Keep a direct copy for ad-hoc preview bundles; the loader supports both layouts.
cp "$ROOT/Sources/TajpoCore/Resources/demo-lexicon.json" "$APP/Contents/Resources/demo-lexicon.json"
test -f "$APP/Contents/Resources/demo-lexicon.json"
cp "$ROOT/Sources/TajpoCore/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
chmod +x "$APP/Contents/MacOS/Tajpo"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
