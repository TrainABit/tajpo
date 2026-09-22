#!/usr/bin/env bash
# Builds build/Tajpo.app from the Swift package, signs it, and optionally
# notarizes it and wraps it in a DMG.
#
#   scripts/build-app.sh [--dmg] [--install]
#
# Environment:
#   SIGN_IDENTITY   Code signing identity. Default "-" (ad hoc). Use a stable
#                   identity (Developer ID, or a self-signed "Tajpo Dev"
#                   certificate, see README) so macOS keeps the Accessibility
#                   permission across rebuilds.
#   BUNDLE_ID       Default com.trainabit.tajpo
#   VERSION         Default: latest git tag without "v", else 0.2.0
#   NOTARY_PROFILE  notarytool keychain profile; if set, the app is notarized.
#   UNIVERSAL       1 (default) builds arm64 + x86_64; 0 builds this Mac's arch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAKE_DMG=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --dmg) MAKE_DMG=1 ;;
    --install) INSTALL=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="${BUNDLE_ID:-com.trainabit.tajpo}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-1}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building Tajpo $VERSION ($BUILD_NUMBER)"
swift build -c release --product Tajpo ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --product Tajpo ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$ROOT/build/Tajpo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tajpo" "$APP/Contents/MacOS/Tajpo"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
  Support/Info.plist > "$APP/Contents/Info.plist"

echo "==> Making the icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing with identity: $SIGN_IDENTITY"
SIGN_ARGS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_ARGS+=(--timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing"
  ZIP="$ROOT/build/Tajpo-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

if [[ "$MAKE_DMG" == "1" ]]; then
  echo "==> Making the DMG"
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Tajpo" -srcfolder "$STAGE" -ov -format UDZO "$ROOT/build/Tajpo-$VERSION.dmg" >/dev/null
  if [[ "$SIGN_IDENTITY" != "-" ]]; then codesign --sign "$SIGN_IDENTITY" --timestamp "$ROOT/build/Tajpo-$VERSION.dmg"; fi
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ROOT/build/Tajpo-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$ROOT/build/Tajpo-$VERSION.dmg"
  fi
  echo "    build/Tajpo-$VERSION.dmg"
fi

if [[ "$INSTALL" == "1" ]]; then
  echo "==> Installing to /Applications"
  pkill -x Tajpo 2>/dev/null || true
  rm -rf /Applications/Tajpo.app
  cp -R "$APP" /Applications/
  open /Applications/Tajpo.app
fi

echo "==> Done: $APP"
