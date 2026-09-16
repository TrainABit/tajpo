#!/bin/bash
set -euo pipefail

# Build a notarizable Tajpo.app from the Swift package.
# Required for signing/notarization:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID="you@example.com"
#   TEAM_ID="TEAMID"
#   APP_PASSWORD="app-specific-password"
#
# Developer ID distribution is the intended path. App Store / App Sandbox is
# not supported: Accessibility, the global hotkey, and clipboard fallback fail
# in the sandbox.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Tajpo.app"
ICON_SOURCE="$ROOT/Sources/TajpoCore/Resources/AppIcon.png"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Building Tajpo..."
swift build -c release --package-path "$ROOT"
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/Tajpo"
cp "$BIN" "$APP/Contents/MacOS/Tajpo"
cp "$ROOT/Sources/Tajpo/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ICON_SOURCE" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
  ICONSET="$DIST/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    if [[ "$double" -le 1024 ]]; then
      sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    fi
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  cp "$ICON_SOURCE" "$APP/Contents/Resources/AppIcon.png"
fi

chmod +x "$APP/Contents/MacOS/Tajpo"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Signing..."
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Sources/Tajpo/Tajpo.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"
fi

if [[ -n "${APPLE_ID:-}" && -n "${TEAM_ID:-}" && -n "${APP_PASSWORD:-}" ]]; then
  echo "Notarizing..."
  ditto -c -k --keepParent "$APP" "$DIST/Tajpo.zip"
  xcrun notarytool submit "$DIST/Tajpo.zip" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP"
fi

echo "App: $APP"
echo "Upload the notarized app to GitHub Releases so Tajpo's in-app updater can find it."
