#!/usr/bin/env bash
# Headless smoke test: runs the real LÖVE app for N fixed ticks with scripted
# input, captures the canvas and window, verifies pixel-perfect integer
# scaling and checks the expected debug-marker positions.
#
# Usage: tools/smoke.sh [TICKS] [OUT_PNG] [WINDOW_SIZES]
#   WINDOW_SIZES: space-separated WxH list (default "1280x720 1920x1080 1366x768 800x600")
# Linux uses Xvfb with software GL. macOS runs against the real display.
# Results are sandbox/CI evidence only, never native acceptance.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TICKS="${1:-120}"
OUT="${2:-$ROOT/build/smoke.png}"
SIZES="${3:-1280x720 1920x1080 1366x768 800x600}"
LOVE="${LOVE:-love}"
mkdir -p "$(dirname "$OUT")"

if ! command -v "$LOVE" >/dev/null 2>&1; then
  echo "smoke: '$LOVE' not found; install LÖVE 11.5" >&2
  exit 1
fi

export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"
export ALSOFT_DRIVERS="${ALSOFT_DRIVERS:-null}"

smoke_one() {
  local size="$1" out="$2"
  local window_out="${out%.png}-window.png"
  local log="${out%.png}.log"
  local run=("$LOVE" "$ROOT" "--smoke=$TICKS" "--window=$size" "--smoke-out=$out"
    "--smoke-window-out=$window_out")
  local code
  set +e
  if [[ "$(uname -s)" == "Linux" && -z "${SMOKE_NO_XVFB:-}" ]]; then
    command -v xvfb-run >/dev/null 2>&1 || { echo "smoke: xvfb-run not found" >&2; exit 1; }
    timeout 60 xvfb-run -a -s "-screen 0 1920x1080x24" "${run[@]}" >"$log" 2>&1
  else
    timeout 60 "${run[@]}" >"$log" 2>&1
  fi
  code=$?
  set -e

  grep -E '^SMOKE (OK|FAIL)' "$log" || true
  if [[ $code -ne 0 ]]; then
    echo "smoke[$size]: FAILED (exit $code), log: $log" >&2
    grep -v -E '^(ALSA|\[ALSOFT\]|\[[WE]\]\[)' "$log" | tail -20 >&2
    exit 1
  fi
  grep -q '^SMOKE OK' "$log" || { echo "smoke[$size]: no SMOKE OK line" >&2; exit 1; }
  grep -q "window=$size " "$log" || { echo "smoke[$size]: window size not applied" >&2; exit 1; }

  # Expected positions for the 120-tick script are asserted in
  # tests/app/sandbox_spec.lua. Here we check that the real app agrees.
  if [[ "$TICKS" == "120" ]]; then
    grep -q 'p1=5600,4992 p2=4256,3552' "$log" || { echo "smoke[$size]: marker positions differ" >&2; exit 1; }
  fi

  # The PNG IHDR must be 640x360.
  local dims
  dims="$(od -An -tu1 -j16 -N8 "$out" | awk '{print ($1*16777216+$2*65536+$3*256+$4) "x" ($5*16777216+$6*65536+$7*256+$8)}')"
  [[ "$dims" == "640x360" ]] || { echo "smoke[$size]: unexpected canvas size $dims" >&2; exit 1; }
}

first=1
for size in $SIZES; do
  if [[ $first -eq 1 ]]; then
    smoke_one "$size" "$OUT"
    first=0
  else
    smoke_one "$size" "${OUT%.png}-$size.png"
  fi
done
echo "smoke: OK ($SIZES) -> $(dirname "$OUT")"
