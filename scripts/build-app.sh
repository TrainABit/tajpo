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
#   INSTALL_ROOT    Destination directory for --install (default /Applications).
#                   Useful for a disposable verification directory.
#   EXPECTED_TEAM_ID  Require this signing team before --install replaces an app.
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
  # Keep the checksum portable: release consumers run `shasum -c` from the
  # directory containing the DMG, not from the GitHub runner's filesystem.
  (cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
  hdiutil verify "$DMG"
fi

INSTALL_STAGE=""
INSTALL_BACKUP=""
INSTALL_DESTINATION=""
INSTALL_COMMITTED=0
INSTALL_KEEP_STAGE=0

cleanup_install_stage() {
  if [[ -z "$INSTALL_STAGE" || ! -e "$INSTALL_STAGE" ]]; then
    return
  fi
  if [[ "$INSTALL_COMMITTED" != "1" && -n "$INSTALL_BACKUP" && -e "$INSTALL_BACKUP" ]]; then
    if ! restore_previous_install; then
      INSTALL_KEEP_STAGE=1
      echo "Could not restore the previous app; rollback data is in $INSTALL_STAGE" >&2
      return
    fi
  fi
  if [[ "$INSTALL_KEEP_STAGE" == "1" ]]; then
    echo "Installation rollback data kept at $INSTALL_STAGE" >&2
  else
    rm -rf "$INSTALL_STAGE" || true
  fi
}
trap 'status=$?; rm -rf "$TMPROOT" || true; cleanup_install_stage; exit "$status"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

install_die() {
  echo "ERROR: $*" >&2
  exit 1
}

signature_field() {
  local details="$1"
  local key="$2"
  printf '%s\n' "$details" | awk -v key="$key" '
    index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
  '
}

normalize_team() {
  local team="${1:-}"
  if [[ "$team" == "not set" ]]; then
    printf '%s' ""
  else
    printf '%s' "$team"
  fi
}

read_signature() {
  local app="$1"
  local details
  SIGNATURE_IDENTIFIER=""
  SIGNATURE_TEAM=""
  SIGNATURE_AUTHORITY=""
  SIGNATURE_KIND=""

  if ! details="$(codesign --display --verbose=4 "$app" 2>&1)"; then
    echo "Could not read the code signature for $app" >&2
    return 1
  fi
  SIGNATURE_IDENTIFIER="$(signature_field "$details" Identifier)"
  SIGNATURE_TEAM="$(normalize_team "$(signature_field "$details" TeamIdentifier)")"
  SIGNATURE_AUTHORITY="$(signature_field "$details" Authority)"
  SIGNATURE_KIND="$(signature_field "$details" Signature)"
  # Older codesign output has no `Signature=` line for CMS signatures; the
  # authority is the positive signal in that format. Ad-hoc signatures use
  # `Signature=adhoc` (or the CodeDirectory flag).
  if [[ -z "$SIGNATURE_KIND" && -n "$SIGNATURE_AUTHORITY" ]]; then
    SIGNATURE_KIND="signed"
  fi
  if [[ -z "$SIGNATURE_IDENTIFIER" || -z "$SIGNATURE_KIND" ]]; then
    echo "The code signature for $app is missing identifying information" >&2
    return 1
  fi
  if [[ -n "$SIGNATURE_TEAM" && -z "$SIGNATURE_AUTHORITY" ]]; then
    echo "The code signature for $app has a team but no authority" >&2
    return 1
  fi
  return 0
}

verify_app() {
  local app="$1"
  local label="$2"
  local bundle_id signature_id

  if [[ ! -d "$app" || -L "$app" ]]; then
    echo "$label is not a real app directory: $app" >&2
    return 1
  fi
  if [[ ! -f "$app/Contents/Info.plist" || ! -x "$app/Contents/MacOS/Tajpo" ]]; then
    echo "$label is missing its app bundle contents: $app" >&2
    return 1
  fi
  if ! bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)"; then
    echo "$label has no readable CFBundleIdentifier" >&2
    return 1
  fi
  if [[ "$bundle_id" != "$BUNDLE_ID" ]]; then
    echo "$label has bundle identifier '$bundle_id', expected '$BUNDLE_ID'" >&2
    return 1
  fi
  if ! codesign --verify --deep --strict "$app" >/dev/null; then
    echo "$label failed code-signature verification" >&2
    return 1
  fi
  if ! read_signature "$app"; then
    return 1
  fi
  signature_id="$SIGNATURE_IDENTIFIER"
  if [[ "$signature_id" != "$BUNDLE_ID" ]]; then
    echo "$label signature identifies '$signature_id', expected '$BUNDLE_ID'" >&2
    return 1
  fi
  return 0
}

restore_previous_install() {
  local failed="$INSTALL_STAGE/failed.app"
  if [[ -n "$INSTALL_BACKUP" && -e "$INSTALL_BACKUP" ]]; then
    if [[ -e "$INSTALL_DESTINATION" || -L "$INSTALL_DESTINATION" ]]; then
      if ! mv "$INSTALL_DESTINATION" "$failed"; then
        return 1
      fi
    fi
    if ! mv "$INSTALL_BACKUP" "$INSTALL_DESTINATION"; then
      return 1
    fi
    INSTALL_BACKUP=""
    return 0
  fi

  # There was no previous install. Do not leave a failed replacement at the
  # destination; leave it in the staging directory for diagnosis instead.
  if [[ -e "$INSTALL_DESTINATION" || -L "$INSTALL_DESTINATION" ]]; then
    if ! mv "$INSTALL_DESTINATION" "$failed"; then
      return 1
    fi
    # With no known previous app, preserve anything that was at the
    # destination rather than deleting it as part of failure cleanup.
    INSTALL_KEEP_STAGE=1
  fi
  return 0
}

install_app() {
  local source="$1"
  local root="${INSTALL_ROOT:-/Applications}"
  local destination staged_app
  local source_team expected_team existing_team

  if [[ "$root" != /* ]]; then
    install_die "INSTALL_ROOT must be an absolute path"
  fi
  if [[ ! -d "$root" ]]; then
    install_die "Install root does not exist: $root"
  fi
  if ! root="$(cd -P "$root" && pwd -P)"; then
    install_die "Could not resolve install root: $root"
  fi
  destination="$root/Tajpo.app"
  INSTALL_DESTINATION="$destination"
  expected_team="${EXPECTED_TEAM_ID:-}"

  # Validate the newly built bundle before touching the destination.
  verify_app "$source" "source app" || install_die "Refusing to install an unverified app"
  source_team="$SIGNATURE_TEAM"
  if [[ -n "$expected_team" && "$source_team" != "$expected_team" ]]; then
    install_die "Source signature team '${source_team:-ad hoc}' does not match EXPECTED_TEAM_ID '$expected_team'"
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ ! -d "$destination" || -L "$destination" ]]; then
      install_die "Refusing to replace non-directory destination: $destination"
    fi
    verify_app "$destination" "existing app" || install_die "Refusing to replace an unverified existing app"
    existing_team="$SIGNATURE_TEAM"
    if [[ "$source_team" != "$existing_team" ]]; then
      install_die "Refusing to replace an app signed by '${existing_team:-ad hoc}' with '${source_team:-ad hoc}'"
    fi
  fi

  # Stage on the destination volume so both moves are renames, not copies.
  # This also means a failed verification never damages the existing app.
  INSTALL_STAGE="$(mktemp -d "$root/.tajpo-install.XXXXXX")"
  staged_app="$INSTALL_STAGE/Tajpo.app"
  ditto --rsrc --extattr "$source" "$staged_app"
  verify_app "$staged_app" "staged app" || install_die "Staged app failed verification"

  if [[ -e "$destination" || -L "$destination" ]]; then
    INSTALL_BACKUP="$INSTALL_STAGE/previous.app"
    mv "$destination" "$INSTALL_BACKUP" || install_die "Could not move the existing app aside"
  fi

  if ! mv "$staged_app" "$destination"; then
    if ! restore_previous_install; then
      INSTALL_KEEP_STAGE=1
      install_die "Could not install the app or restore the previous copy; rollback data is in $INSTALL_STAGE"
    fi
    install_die "Could not move the verified app into $destination"
  fi

  if ! verify_app "$destination" "installed app"; then
    if ! restore_previous_install; then
      INSTALL_KEEP_STAGE=1
      install_die "Installed app failed verification and rollback failed; rollback data is in $INSTALL_STAGE"
    fi
    install_die "Installed app failed verification; the previous copy was restored"
  fi
  INSTALL_COMMITTED=1

  echo "==> Installed verified $destination"
  echo "Quit any running Tajpo instance, then open the installed app from $destination."
}

if [[ "$INSTALL" == "1" ]]; then
  install_app "$APP"
fi

echo "==> Done: $APP"
