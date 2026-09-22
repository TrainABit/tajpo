#!/usr/bin/env bash
# Builds build/Tajpo.app from the Swift package, signs it, and optionally
# notarizes it and wraps it in a DMG.
#
#   scripts/build-app.sh [--dmg] [--install]
#
# Environment:
#   SIGN_IDENTITY   Code signing identity. Default "-" (ad hoc, for local use
#                   only). Use a stable identity (Developer ID, or a
#                   self-signed "Tajpo Dev" certificate, see README) so macOS
#                   keeps the Accessibility permission across rebuilds.
#   BUNDLE_ID       Default com.trainabit.tajpo
#   VERSION         MAJOR[.MINOR[.PATCH]]. Default: latest git tag without "v", else 0.2.0
#   UNIVERSAL       1 (default) builds arm64 + x86_64; 0 builds this Mac's arch.
#
# Notarization (optional; either one):
#   NOTARY_PROFILE                          notarytool keychain profile
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   App Store Connect API key (CI)
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

if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "VERSION must look like 1.2.3 (got '$VERSION')" >&2
  exit 2
fi
if ! [[ "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "BUNDLE_ID may only contain letters, digits, '.' and '-' (got '$BUNDLE_ID')" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

NOTARY_ARGS=()
NOTARIZE=0
if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  NOTARIZE=1
  NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID is required}" --issuer "${NOTARY_ISSUER:?NOTARY_ISSUER is required}")
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARIZE=1
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
fi

notarize() {
  local file="$1"
  echo "==> Notarizing $(basename "$file")"
  local result
  result="$(xcrun notarytool submit "$file" "${NOTARY_ARGS[@]}" --wait --output-format json)"
  echo "$result"
  local status id
  status="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$result")"
  id="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' <<<"$result")"
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed ($status). Log:" >&2
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${NOTARY_ARGS[@]}" >&2 || true
    exit 1
  fi
}

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
if [[ "${UNIVERSAL:-1}" == "1" ]]; then
  lipo "$APP/Contents/MacOS/Tajpo" -verify_arch arm64 x86_64
fi
sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|" -e "s|__VERSION__|$VERSION|" -e "s|__BUILD__|$BUILD_NUMBER|" \
  Support/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Keeping debug symbols"
mkdir -p "$ROOT/build"
DSYM="$ROOT/build/Tajpo-$VERSION.dSYM"
rm -rf "$DSYM" "$DSYM.zip"
if [[ -d "$BIN_DIR/Tajpo.dSYM" ]]; then
  cp -R "$BIN_DIR/Tajpo.dSYM" "$DSYM"
else
  dsymutil "$BIN_DIR/Tajpo" -o "$DSYM"
fi
ditto -c -k --keepParent "$DSYM" "$DSYM.zip"
rm -rf "$DSYM"

echo "==> Making the icon"
ICONSET="$TMPROOT/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing with identity: $SIGN_IDENTITY"
SIGN_ARGS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  SIGN_ARGS+=(--timestamp=none)
else
  SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ "$NOTARIZE" == "1" ]]; then
  ZIP="$TMPROOT/Tajpo-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vvv -t exec "$APP"
fi

if [[ "$MAKE_DMG" == "1" ]]; then
  echo "==> Making the DMG"
  DMG="$ROOT/build/Tajpo-$VERSION.dmg"
  STAGE="$TMPROOT/dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  # hdiutil occasionally fails with "Resource busy" on CI runners.
  for attempt in 1 2 3; do
    if hdiutil create -volname "Tajpo" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null; then break; fi
    [[ $attempt == 3 ]] && { echo "hdiutil failed" >&2; exit 1; }
    sleep 5
  done
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  fi
  if [[ "$NOTARIZE" == "1" ]]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl -a -vvv -t open --context context:primary-signature "$DMG"
  fi
  shasum -a 256 "$DMG" | tee "$DMG.sha256"
fi

if [[ "$INSTALL" == "1" ]]; then
  echo "==> Installing to /Applications"
  pkill -x Tajpo 2>/dev/null || true
  rm -rf /Applications/Tajpo.app
  cp -R "$APP" /Applications/
  open /Applications/Tajpo.app
fi

echo "==> Done: $APP"
