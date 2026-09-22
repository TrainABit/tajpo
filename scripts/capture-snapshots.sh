#!/usr/bin/env bash
# Captures each demo scene of build/Tajpo.app in light and dark mode.
# Used by .github/workflows/ui-snapshots.yml; also works locally.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Tajpo.app/Contents/MacOS/Tajpo"
OUT="$ROOT/snapshots"
mkdir -p "$OUT"

SCENES=(
  onboarding-welcome onboarding-connect onboarding-tryit onboarding-everywhere onboarding-done
  settings-general settings-ai settings-presets settings-privacy
  panel-ready panel-running panel-finished panel-copyonly panel-error panel-long
)

capture() {
  local mode="$1" scene="$2"
  local extra=()
  [[ "$scene" == onboarding-everywhere ]] && extra=(-TajpoDemoNoAccess YES)
  "$BIN" -TajpoDemo "$scene" -TajpoDemoAppearance "$mode" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1 &
  local pid=$!
  sleep 4
  # Bring regular windows to the front so they render as active. The
  # floating panel is left alone; it takes keyboard focus by itself.
  if [[ "$scene" != panel-* ]]; then
    open "$ROOT/build/Tajpo.app" >/dev/null 2>&1 || true
  fi
  sleep 2
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "::error::Tajpo exited while showing $scene"
    return
  fi
  screencapture -x "$OUT/$mode-$scene.png"
  sips -Z 1600 "$OUT/$mode-$scene.png" >/dev/null 2>&1 || true
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  # In case `open` started a second copy instead of activating this one.
  pkill -f "$BIN" 2>/dev/null || true
  sleep 1
}

defaults write com.trainabit.tajpo completedOnboarding -bool true

for scene in "${SCENES[@]}"; do capture light "$scene"; done

for scene in onboarding-welcome onboarding-connect onboarding-tryit settings-ai panel-finished panel-error; do capture dark "$scene"; done
