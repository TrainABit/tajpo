#!/usr/bin/env bash
# End-to-end test on your Mac:
# TextEdit document with a typo → ⌃⌥T → ⌘1 (Correct) → ⌘↩ (Replace) →
# check the document, against a local fake OpenAI server (no API key or cost).
#
# Before running: build with scripts/build-app.sh, then allow both Tajpo and
# your terminal app in System Settings ▸ Privacy & Security ▸ Accessibility.
# It resets Tajpo's preferences, so don't run it on a Mac where you use Tajpo daily.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Tajpo.app"
OUT="$ROOT/snapshots"
WORK="$(mktemp -d)"
mkdir -p "$OUT"
PORT=8765
EXPECTED="I think the plan is good, and the team agrees."

fail() { echo "::error::E2E: $*"; screencapture -x "$OUT/e2e-failure.png" 2>/dev/null; cleanup; exit 1; }
cleanup() {
  pkill -x Tajpo 2>/dev/null
  osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
  kill "${SERVER_PID:-}" 2>/dev/null
}

echo "==> Fake OpenAI server"
python3 "$ROOT/Tests/E2E/fake_openai.py" "$PORT" "$WORK/requests.log" &
SERVER_PID=$!
sleep 1

echo "==> Tajpo settings"
defaults delete com.trainabit.tajpo 2>/dev/null || true
defaults write com.trainabit.tajpo completedOnboarding -bool true
defaults write com.trainabit.tajpo baseURL "http://127.0.0.1:$PORT/v1"

echo "==> TextEdit with a typo"
printf "I think teh plan is good, and teh team agrees." > "$WORK/e2e.txt"
open -a TextEdit "$WORK/e2e.txt"
sleep 4
osascript -e 'tell application "TextEdit" to activate' -e 'delay 1' \
  -e 'tell application "System Events" to keystroke "a" using command down' || fail "could not select text (osascript needs Accessibility)"
sleep 1

echo "==> Launch Tajpo"
open "$APP"
sleep 6
pgrep -x Tajpo >/dev/null || fail "Tajpo is not running"
osascript -e 'tell application "TextEdit" to activate'
sleep 1
screencapture -x "$OUT/e2e-1-selected.png"

echo "==> ⌃⌥T"
osascript -e 'tell application "System Events" to key code 17 using {control down, option down}'
sleep 3
screencapture -x "$OUT/e2e-2-panel.png"

echo "==> ⌘1 (Correct)"
osascript -e 'tell application "System Events" to keystroke "1" using command down'
sleep 4
screencapture -x "$OUT/e2e-3-result.png"
[[ -s "$WORK/requests.log" ]] || fail "Tajpo sent no request to the AI server"
grep -q '<text>' "$WORK/requests.log" || fail "request did not wrap the selection in <text> tags"

echo "==> ⌘↩ (Replace)"
osascript -e 'tell application "System Events" to key code 36 using command down'
sleep 3
screencapture -x "$OUT/e2e-4-replaced.png"

ACTUAL="$(osascript -e 'tell application "TextEdit" to get text of document 1')"
echo "Document now: $ACTUAL"
[[ "$ACTUAL" == "$EXPECTED" ]] || fail "expected '$EXPECTED' but found '$ACTUAL'"

echo "==> E2E passed"
cleanup
