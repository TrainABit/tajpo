#!/usr/bin/env bash
# End-to-end test on a Mac with Accessibility permission for the terminal
# runner and the test app. It uses a loopback fake server and a disposable
# bundle ID; it never reads or modifies the normal Tajpo preferences/Keychain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Tajpo.app"
OUT="$ROOT/snapshots"
WORK="$(mktemp -d)"
mkdir -p "$OUT"

fail() {
  echo "::error::E2E: $*" >&2
  screencapture -x "$OUT/e2e-failure.png" 2>/dev/null || true
  exit 1
}

if [[ ! -d "$APP" ]]; then
  fail "Build Tajpo.app first with: BUNDLE_ID=com.trainabit.tajpo.e2e scripts/build-app.sh"
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [[ "$BUNDLE_ID" == "com.trainabit.tajpo" ]]; then
  fail "Refusing to run E2E against the production bundle; build with BUNDLE_ID=com.trainabit.tajpo.e2e"
fi

PORT_FILE="$WORK/port"
SERVER_PID=""
TAJPO_PID=""
DOCUMENT_NAME="Tajpo-E2E-$$.txt"
ORIGINAL_DEFAULTS="$WORK/defaults.plist"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "$DOCUMENT_NAME" ]]; then
    osascript -e "tell application \"TextEdit\" to close document \"$DOCUMENT_NAME\" saving no" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TAJPO_PID" ]]; then
    kill "$TAJPO_PID" 2>/dev/null || true
  fi
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  if [[ -s "$ORIGINAL_DEFAULTS" ]]; then
    defaults import "$BUNDLE_ID" "$ORIGINAL_DEFAULTS" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT INT TERM

# Preserve any preferences belonging to this disposable test bundle.
defaults export "$BUNDLE_ID" "$ORIGINAL_DEFAULTS" >/dev/null 2>&1 || true
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

python3 "$ROOT/Tests/E2E/fake_openai.py" 0 "$WORK/requests.log" "$PORT_FILE" >"$WORK/server.out" 2>&1 &
SERVER_PID=$!
for _ in {1..100}; do
  [[ -s "$PORT_FILE" ]] && break
  kill -0 "$SERVER_PID" 2>/dev/null || fail "fake server exited: $(cat "$WORK/server.out")"
  sleep 0.05
done
[[ -s "$PORT_FILE" ]] || fail "fake server did not become ready"
PORT="$(cat "$PORT_FILE")"
/usr/bin/curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null || fail "fake server health check failed"

# Use only the disposable test bundle. Its Keychain service is also isolated
# from the production app by KeychainAPIKeyStore's bundle-derived service.
defaults write "$BUNDLE_ID" completedOnboarding -bool true
defaults write "$BUNDLE_ID" baseURL "http://127.0.0.1:$PORT/v1"

TEXT_FILE="$WORK/$DOCUMENT_NAME"
printf "I think teh plan is good, and teh team agrees." > "$TEXT_FILE"
# `open -na` can leave a new TextEdit process without opening its file on
# some macOS releases. Let the existing TextEdit instance open the uniquely
# named disposable document instead.
open -a TextEdit "$TEXT_FILE"
sleep 3
DOCUMENT_FOUND="$(osascript - "$DOCUMENT_NAME" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set targetName to item 1 of argv
  tell application "TextEdit"
    repeat with candidate in documents
      if (name of candidate as text) is targetName then return "yes"
    end repeat
  end tell
  return "no"
end run
APPLESCRIPT
)"
[[ "$DOCUMENT_FOUND" == "yes" ]] || fail "could not identify the test TextEdit document"
osascript -e 'tell application "TextEdit" to activate' -e 'delay 0.5' \
  -e 'tell application "System Events" to keystroke "a" using command down' \
  >/dev/null 2>&1 || fail "could not select text (System Events needs Accessibility)"

open -n "$APP"
for _ in {1..100}; do
  TAJPO_PID="$(pgrep -n -f "$APP/Contents/MacOS/Tajpo" || true)"
  [[ -n "$TAJPO_PID" ]] && break
  sleep 0.1
done
[[ -n "$TAJPO_PID" ]] || fail "Tajpo test process did not start"
osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1 || true
sleep 1
screencapture -x "$OUT/e2e-1-selected.png" 2>/dev/null || true

osascript -e 'tell application "System Events" to key code 17 using {control down, option down}' \
  >/dev/null 2>&1 || fail "could not trigger the global shortcut"
sleep 3
screencapture -x "$OUT/e2e-2-panel.png" 2>/dev/null || true

osascript -e 'tell application "System Events" to keystroke "1" using command down' \
  >/dev/null 2>&1 || fail "could not trigger Correct"
sleep 4
screencapture -x "$OUT/e2e-3-result.png" 2>/dev/null || true
[[ -s "$WORK/requests.log" ]] || fail "Tajpo sent no request to the fake server"
grep -q '<text' "$WORK/requests.log" || fail "request did not wrap the selection in a text tag"

osascript -e 'tell application "System Events" to key code 36 using command down' \
  >/dev/null 2>&1 || fail "could not trigger Replace"
sleep 3
screencapture -x "$OUT/e2e-4-replaced.png" 2>/dev/null || true

ACTUAL="$(osascript -e "tell application \"TextEdit\" to get text of document \"$DOCUMENT_NAME\"" 2>/dev/null || true)"
EXPECTED="I think the plan is good, and the team agrees."
[[ "$ACTUAL" == "$EXPECTED" ]] || fail "expected '$EXPECTED' but found '$ACTUAL'"

echo "==> E2E passed"
