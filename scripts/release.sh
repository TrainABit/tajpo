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
BIN_DIR="$(dirname "$BIN")"
cp "$BIN" "$APP/Contents/MacOS/Tajpo"
cp "$ROOT/Sources/Tajpo/Info.plist" "$APP/Contents/Info.plist"

# Ship the SwiftPM resource bundle in both locations used by packaged apps.
# DemoLexiconLoader also has a safe fallback, but keeping the bundle intact
# makes the on-device demo deterministic and keeps release verification honest.
RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 4 -name 'Tajpo_TajpoCore.bundle' -print -quit 2>/dev/null || true)"
if [[ ! -d "$RESOURCE_BUNDLE/Contents" ]]; then
  # Some Swift toolchains place the bundle in a sibling build directory.
  RESOURCE_BUNDLE="$(find "$ROOT/.build" -type d -name 'Tajpo_TajpoCore.bundle' -print -quit 2>/dev/null || true)"
fi
if [[ -n "$RESOURCE_BUNDLE" && -d "$RESOURCE_BUNDLE/Contents" ]]; then
  copy_resource_bundle() {
    local destination="$1"
    rm -rf "$destination"
    mkdir -p "$destination"
    # Copy Contents explicitly so a malformed/flat bundle cannot pass as a
    # valid macOS resource bundle. The generated SwiftPM accessor requires
    # Contents/Info.plist and Contents/Resources/*.
    ditto "$RESOURCE_BUNDLE/Contents" "$destination/Contents"
    [[ -f "$destination/Contents/Info.plist" ]]
    [[ -f "$destination/Contents/Resources/demo-lexicon.json" ]]
  }

  copy_resource_bundle "$APP/Tajpo_TajpoCore.bundle"
  # Also keep a copy under Contents/Resources for tools that expect resources there.
  copy_resource_bundle "$APP/Contents/Resources/Tajpo_TajpoCore.bundle"
  # A direct copy is a deliberate fallback for ad-hoc/local app launches.
  cp "$ROOT/Sources/TajpoCore/Resources/demo-lexicon.json" "$APP/Contents/Resources/demo-lexicon.json"
  echo "Bundled resources: $(basename "$RESOURCE_BUNDLE") (app root + Contents/Resources)"
else
  echo "error: valid Tajpo_TajpoCore.bundle was not produced by 'swift build -c release' in $BIN_DIR." >&2
  echo "error: the packaged app would fail to load its on-device demo lexicon. Aborting." >&2
  exit 1
fi

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
  # Zip and submit a staging copy; the distributable ZIP is rebuilt after the
  # staple so it contains the final stapled bundle.
  ditto -c -k --keepParent "$APP" "$DIST/Tajpo-notarize.zip"
  xcrun notarytool submit "$DIST/Tajpo-notarize.zip" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  rm -f "$DIST/Tajpo-notarize.zip" "$DIST/Tajpo.zip"
  ditto -c -k --keepParent "$APP" "$DIST/Tajpo.zip"
  echo "Distributable ZIP rebuilt after stapling: $DIST/Tajpo.zip"
fi

echo "App: $APP"
echo "Upload the notarized app to GitHub Releases so Tajpo's in-app updater can find it."
