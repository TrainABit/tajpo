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
cp "$ROOT/Sources/TajpoCore/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;
chmod +x "$APP/Contents/MacOS/Tajpo"
codesign --force --deep --sign - "$APP"
echo "$APP"
