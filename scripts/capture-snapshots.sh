#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/snapshots"
mkdir -p "$OUT"
defaults delete com.trainabit.tajpo 2>/dev/null || true
open "$ROOT/build/Tajpo.app"
sleep 8
screencapture -x "$OUT/onboarding-redesign.png"
pkill -x Tajpo || true
