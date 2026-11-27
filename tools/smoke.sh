#!/usr/bin/env bash
# Headless/real-window smoke test. It runs the real LÖVE app for N fixed
# ticks with scripted input, captures the canvas and the window
# backbuffer, verifies pixel-perfect integer scaling in PHYSICAL pixels,
# and checks the expected arena outcome (positions and sim hash).
#
# Usage: tools/smoke.sh [TICKS] [OUT_PNG] [WINDOW_SIZES]
#   WINDOW_SIZES: space-separated *logical* WxH list (window points).
#     Defaults: Linux  "1280x720 1920x1080 1366x768 800x600" (Xvfb, DPI 1)
#               macOS  "800x600 1024x640 1280x720" (these must fit on the
#                       display; HiDPI makes physical = logical x DPI scale)
#     Can also be set via the SMOKE_SIZES environment variable.
#
# Linux runs under Xvfb with software GL (sandbox evidence only).
# macOS opens a real window and needs a logged-in GUI session. Its
# results are native automated evidence, which still does not replace the
# owner's manual acceptance.
# Requires bash (3.2+, macOS /bin/bash works), od, awk, grep, and one of:
# timeout, gtimeout or perl (macOS ships perl).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/lib/portable.sh
. "$ROOT/tools/lib/portable.sh"
# shellcheck source=tools/lib/smoke_expect.sh
. "$ROOT/tools/lib/smoke_expect.sh"
OS="$(uname -s)"
TICKS="${1:-120}"
OUT="${2:-$ROOT/build/smoke.png}"
if [[ "$OS" == "Darwin" ]]; then
  DEFAULT_SIZES="800x600 1024x640 1280x720"
else
  DEFAULT_SIZES="1280x720 1920x1080 1366x768 800x600"
fi
SIZES="${3:-${SMOKE_SIZES:-$DEFAULT_SIZES}}"
TIMEOUT_SECS="${SMOKE_TIMEOUT:-60}"

LOVE="${LOVE:-love}"
if ! command -v "$LOVE" >/dev/null 2>&1 && [[ "$OS" == "Darwin" ]] \
  && [[ -x /Applications/love.app/Contents/MacOS/love ]]; then
  LOVE=/Applications/love.app/Contents/MacOS/love
fi
command -v "$LOVE" >/dev/null 2>&1 || { echo "smoke: '$LOVE' not found; install LÖVE 11.5" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"
export ALSOFT_DRIVERS="${ALSOFT_DRIVERS:-null}"

# Portable timeout: GNU timeout, Homebrew gtimeout, or perl's alarm (macOS).
run_with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!"' "$secs" "$@"
  else
    echo "smoke: need timeout, gtimeout or perl" >&2
    return 127
  fi
}

smoke_one() {
  local size="$1" out="$2"
  local window_out="${out%.png}-window.png"
  local log="${out%.png}.log"
  local run=("$LOVE" "$ROOT" "--smoke=$TICKS" "--window=$size" "--smoke-out=$out"
    "--smoke-window-out=$window_out")
  local code
  rm -f "$out" "$window_out" "$log"
  set +e
  if [[ "$OS" == "Linux" && -z "${SMOKE_NO_XVFB:-}" ]]; then
    command -v xvfb-run >/dev/null 2>&1 || { echo "smoke: xvfb-run not found" >&2; exit 1; }
    run_with_timeout "$TIMEOUT_SECS" xvfb-run -a -s "-screen 0 1920x1080x24" "${run[@]}" >"$log" 2>&1
  else
    run_with_timeout "$TIMEOUT_SECS" "${run[@]}" >"$log" 2>&1
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
  # The requested size is logical; the window must actually have it, so a
  # display that is too small fails loudly instead of testing another size.
  grep -q " logical=$size " "$log" || {
    echo "smoke[$size]: window logical size not applied (display too small? set SMOKE_SIZES)" >&2
    exit 1
  }

  # The expected outcome of the 120-tick script (positions and sim hash) is
  # pinned in tools/lib/smoke_expect.sh and checked against the pure
  # simulation by tests/app/arena_spec.lua. Here the real app must agree.
  if [[ "$TICKS" == "120" ]]; then
    grep -q " $SMOKE_EXPECT_120 " "$log" || {
      echo "smoke[$size]: arena outcome differs (expected $SMOKE_EXPECT_120)" >&2
      exit 1
    }
  fi

  # The canvas PNG IHDR must be 640x360. png_dims (tools/lib/portable.sh)
  # validates the PNG header and works with GNU and BSD/macOS od.
  local dims
  dims="$(png_dims "$out")" || dims="unreadable"
  [[ "$dims" == "640x360" ]] || { echo "smoke[$size]: unexpected canvas size '$dims' (expected 640x360): $out" >&2; exit 1; }
  [[ -s "$window_out" ]] || { echo "smoke[$size]: missing window capture" >&2; exit 1; }
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
echo "smoke: OK ($SIZES) on $OS -> $(dirname "$OUT")"
