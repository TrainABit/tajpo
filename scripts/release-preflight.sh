#!/usr/bin/env bash
# Fails closed before a release is signed. This intentionally does not guess
# licensing, privacy, bundle-ID, or support decisions for the maintainer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${1:?Usage: release-preflight.sh MAJOR.MINOR[.PATCH]}"
BUNDLE_ID="${BUNDLE_ID:-com.trainabit.tajpo}"

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "Invalid version: $VERSION" >&2; exit 2; }
git diff --check

grep -Eq "^## .*\\($VERSION\\)" CHANGELOG.md || {
  echo "CHANGELOG.md has no release entry for $VERSION" >&2
  exit 1
}

if grep -qi 'draft' PRIVACY.md; then
  echo "PRIVACY.md is still marked Draft; approve it before release" >&2
  exit 1
fi
if [[ ! -f LICENSE && "${ALLOW_PROPRIETARY:-0}" != "1" ]]; then
  echo "LICENSE is missing. Add one or explicitly set ALLOW_PROPRIETARY=1" >&2
  exit 1
fi
if grep -Rqs 'REPLACE_WITH_DMG_SHA256' packaging; then
  echo "Homebrew packaging still contains a placeholder checksum" >&2
  exit 1
fi

for required in \
  "scripts/build-app.sh" \
  "Sources/Tajpo/System/KeychainAPIKeyStore.swift" \
  "README.md"; do
  grep -q "$BUNDLE_ID" "$required" || {
    echo "$required does not mention expected bundle ID $BUNDLE_ID" >&2
    exit 1
  }
done
grep -q '__BUNDLE_ID__' Support/Info.plist || {
  echo "Support/Info.plist is missing the bundle ID template" >&2
  exit 1
}

[[ -x scripts/build-app.sh ]] || { echo "scripts/build-app.sh is not executable" >&2; exit 1; }
[[ -x scripts/e2e-test.sh ]] || { echo "scripts/e2e-test.sh is not executable" >&2; exit 1; }

echo "Release preflight passed for $VERSION ($BUNDLE_ID)."
