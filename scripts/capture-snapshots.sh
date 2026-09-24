#!/usr/bin/env bash
# Captures each demo scene of build/Tajpo.app in light and dark mode.
# Used by .github/workflows/ui-snapshots.yml and safe to run locally.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Tajpo.app/Contents/MacOS/Tajpo"
OUT="$ROOT/snapshots"
BUNDLE_ID="${TAJPO_SNAPSHOT_BUNDLE_ID:-com.trainabit.tajpo.snapshot}"
mkdir -p "$OUT"

cleanup() {
  pkill -f "$BIN" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [[ ! -x "$BIN" ]]; then
  echo "Missing $BIN; build the app first" >&2
  exit 1
fi

SCENES=(
  onboarding-welcome onboarding-connect onboarding-tryit onboarding-everywhere onboarding-done onboarding-ready
  settings-general settings-ai settings-presets settings-privacy
  panel-ready panel-running panel-finished panel-copyonly panel-error panel-long
)

capture() {
  local mode="$1" scene="$2"
  local file="$OUT/$mode-$scene.png"
  local extra=()
  [[ "$scene" == onboarding-everywhere ]] && extra=(-TajpoDemoNoAccess YES)
  rm -f "$file"
  "$BIN" -TajpoDemo "$scene" -TajpoDemoAppearance "$mode" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1 &
  local pid=$!
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Tajpo exited while showing $mode-$scene" >&2
    return 1
  fi
  if [[ "$scene" != panel-* ]]; then
    open "$ROOT/build/Tajpo.app" >/dev/null 2>&1 || true
  fi
  sleep 2
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Tajpo exited before capture $mode-$scene" >&2
    return 1
  fi
  screencapture -x "$file"
  [[ -s "$file" ]] || { echo "Missing snapshot $file" >&2; return 1; }
  sips -Z 1600 "$file" >/dev/null 2>&1
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pkill -f "$BIN" 2>/dev/null || true
  sleep 0.5
}

# The test bundle gets an isolated defaults/Keychain domain.
defaults write "$BUNDLE_ID" completedOnboarding -bool true

for scene in "${SCENES[@]}"; do capture light "$scene"; done
for scene in onboarding-welcome onboarding-connect onboarding-tryit settings-ai panel-finished panel-error; do capture dark "$scene"; done

echo "Captured $(find "$OUT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ') snapshots in $OUT"
