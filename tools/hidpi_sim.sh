#!/usr/bin/env bash
# HiDPI regression harness. Its results are SIMULATED HiDPI evidence: they
# are not native macOS/Windows evidence.
#
# It runs the real app in smoke mode through tools/hidpi_sim/, which makes
# LÖVE's implicit resource-DPI defaults (newCanvas, newFont) equal to each
# scale in HIDPI_SIM_SCALES, in both presentation modes. Every case must:
#   * end with SMOKE OK from the in-app checks: game canvas 640x360 texels at
#     DPI 1, fit-mode prescale canvas (640k)x(360k) at DPI 1, exact pixel and
#     letterbox counts, and linear filtering in fit mode;
#   * show that the simulation was in effect (HIDPI_SIM probe line);
#   * apply the requested window size and reach the expected arena outcome;
#   * produce canvas and window PNGs byte-identical to the scale-1 reference
#     of the same mode. This catches any implicit-DPI resource drawn into the
#     canvas (e.g. a font), even when the in-app checks pass.
#
# Usage:
#   tools/hidpi_sim.sh [OUT_DIR]              run the matrix on this checkout
#   tools/hidpi_sim.sh --mutations [OUT_DIR]  prove that removing each
#                                             explicit DPI setting is detected
# Environment:
#   HIDPI_SIM_SCALES        default "1 1.25 1.5 2" (1 is the reference, first)
#   HIDPI_SIM_INTEGER_SIZE  logical window for integer mode, default 1366x768
#   HIDPI_SIM_FIT_SIZE      logical window for fit mode, default 900x600
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/lib/portable.sh
. "$ROOT/tools/lib/portable.sh"
# shellcheck source=tools/lib/hidpi_labels.sh
. "$ROOT/tools/lib/hidpi_labels.sh"
# shellcheck source=tools/lib/smoke_expect.sh
. "$ROOT/tools/lib/smoke_expect.sh"
OS="$(uname -s)"
MUTATIONS=0
if [[ "${1:-}" == "--mutations" ]]; then
  MUTATIONS=1
  shift
fi
OUT="${1:-$ROOT/build/hidpi-sim}"
SCALES="${HIDPI_SIM_SCALES:-1 1.25 1.5 2}"
INTEGER_SIZE="${HIDPI_SIM_INTEGER_SIZE:-1366x768}"
FIT_SIZE="${HIDPI_SIM_FIT_SIZE:-900x600}"
TICKS=120
TIMEOUT_SECS="${SMOKE_TIMEOUT:-120}"

LOVE="${LOVE:-love}"
if ! command -v "$LOVE" >/dev/null 2>&1 && [[ "$OS" == "Darwin" ]] \
  && [[ -x /Applications/love.app/Contents/MacOS/love ]]; then
  LOVE=/Applications/love.app/Contents/MacOS/love
fi
command -v "$LOVE" >/dev/null 2>&1 || { echo "hidpi-sim: '$LOVE' not found; install LÖVE 11.5" >&2; exit 1; }
[[ "${SCALES%% *}" == "1" ]] || { echo "hidpi-sim: HIDPI_SIM_SCALES must start with the reference scale 1" >&2; exit 1; }

export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"
export ALSOFT_DRIVERS="${ALSOFT_DRIVERS:-null}"

run_with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!"' "$secs" "$@"
  fi
}

# run_case APP_ROOT MODE SIZE SCALE DIR -> prints "CASE ... PASS|FAIL [labels]"
run_case() {
  local app="$1" mode="$2" size="$3" scale="$4" dir="$5"
  local base="$dir/$mode-dpi$scale"
  local log="$base.log" canvas="$base.png" window="$base-window.png"
  local ref="$dir/$mode-dpi1"
  # The harness runs the G1 smoke explicitly (G2 clarification C4).
  local run=("$LOVE" "$ROOT/tools/hidpi_sim" "--smoke=$TICKS" "--arena=g1_arena" "--window=$size" "--scale-mode=$mode"
    "--smoke-out=$canvas" "--smoke-window-out=$window")
  local code labels=() line problems expected_probe dims
  rm -f "$log" "$canvas" "$window"
  set +e
  if [[ "$OS" == "Linux" && -z "${SMOKE_NO_XVFB:-}" ]]; then
    EAGLE_APP_ROOT="$app" HIDPI_SIM_SCALE="$scale" run_with_timeout "$TIMEOUT_SECS" \
      xvfb-run -a -s "-screen 0 1920x1080x24" "${run[@]}" >"$log" 2>&1
  else
    EAGLE_APP_ROOT="$app" HIDPI_SIM_SCALE="$scale" run_with_timeout "$TIMEOUT_SECS" "${run[@]}" >"$log" 2>&1
  fi
  code=$?
  set -e

  # C locale: the app prints '.', and a decimal-comma locale would break %.2f.
  expected_probe="$(printf_c 'default_dpi=%.2f probe_canvas_dpi=%.2f probe_font_dpi=%.2f' "$scale" "$scale" "$scale")"
  grep -q "^HIDPI_SIM SIMULATED $expected_probe " "$log" || labels+=("simulation-not-applied")
  line="$(grep -E '^SMOKE (OK|FAIL) ' "$log" | head -1 || true)"
  if [[ -z "$line" ]]; then
    labels+=("no-smoke-result")
  else
    problems="$(sed -n 's/.* problems=\([^ ]*\).*/\1/p' <<<"$line")"
    while IFS= read -r l; do [[ -n "$l" ]] && labels+=("$l"); done < <(labels_for_problems "$problems")
    [[ "$line" == "SMOKE OK "* ]] || [[ ${#labels[@]} -gt 0 ]] || labels+=("other-check")
    [[ "$line" == *" logical=$size "* ]] || labels+=("window-size-not-applied")
    [[ "$line" == *"ticks=$TICKS "*" $SMOKE_EXPECT_120 arena=g1_arena "* ]] || labels+=("tick-or-markers")
  fi
  [[ $code -eq 0 ]] || [[ ${#labels[@]} -gt 0 ]] || labels+=("exit-$code")
  if [[ -s "$canvas" ]]; then
    dims="$(png_dims "$canvas")" || dims="unreadable"
    if [[ "$dims" == "unreadable" ]]; then
      labels+=("canvas-png-unreadable")
    elif [[ "$dims" != "640x360" ]]; then
      [[ " ${labels[*]:-} " == *" game-canvas-dpi "* ]] || labels+=("game-canvas-dpi")
    fi
  fi
  if [[ "$scale" != "1" ]]; then
    if ! cmp -s "$canvas" "$ref.png" || ! cmp -s "$window" "$ref-window.png"; then
      labels+=("content-vs-reference")
    fi
  fi

  if [[ ${#labels[@]} -eq 0 && $code -eq 0 ]]; then
    echo "CASE mode=$mode window=$size sim_dpi=$scale PASS"
    return 0
  fi
  echo "CASE mode=$mode window=$size sim_dpi=$scale FAIL ${labels[*]} (log: $log)"
  [[ -n "$line" ]] && echo "     ${line%% out=*}"
  return 1
}

# run_matrix APP_ROOT DIR -> 0 when every case passes.
run_matrix() {
  local app="$1" dir="$2" failed=0 mode size scale
  mkdir -p "$dir"
  for mode in integer fit; do
    if [[ "$mode" == "integer" ]]; then size="$INTEGER_SIZE"; else size="$FIT_SIZE"; fi
    for scale in $SCALES; do
      run_case "$app" "$mode" "$size" "$scale" "$dir" || failed=1
    done
  done
  return $failed
}

if [[ $MUTATIONS -eq 0 ]]; then
  echo "hidpi-sim: SIMULATED HiDPI resource defaults (not native evidence); scales: $SCALES"
  if run_matrix "$ROOT" "$OUT"; then
    echo "hidpi-sim: OK (integer $INTEGER_SIZE, fit $FIT_SIZE; scales $SCALES) -> $OUT"
    exit 0
  fi
  echo "hidpi-sim: FAILED" >&2
  exit 1
fi

# --- mutation proof ------------------------------------------------------------
# Each mutation removes exactly one explicit setting from a copy of the app
# and must be detected by the expected check (and only the expected label
# must be required; independence is asserted for the DPI mutations).
replace_once() {
  OLD="$2" NEW="$3" perl -e '
    local $/; my $f = $ARGV[0];
    open(my $in, "<", $f) or die "cannot read $f\n"; my $s = <$in>; close $in;
    my $n = () = $s =~ /\Q$ENV{OLD}\E/g;
    die "mutation target found $n times in $f (expected exactly 1)\n" unless $n == 1;
    $s =~ s/\Q$ENV{OLD}\E/$ENV{NEW}/;
    open(my $out, ">", $f) or die "cannot write $f\n"; print $out $s; close $out;' "$1"
}

# name | file | old | new | required label | labels that must NOT appear
MUTATIONS_TABLE=(
  'game-canvas|src/render/screen.lua|newCanvas(self.w, self.h, { dpiscale = 1 })|newCanvas(self.w, self.h)|game-canvas-dpi|prescale-canvas-dpi'
  'prescale-canvas|src/render/screen.lua|newCanvas(self.w * k, self.h * k, { dpiscale = 1 })|newCanvas(self.w * k, self.h * k)|prescale-canvas-dpi|game-canvas-dpi'
  'font|src/render/arena_view.lua|newFont(10, "mono", 1)|newFont(10, "mono")|content-vs-reference|game-canvas-dpi prescale-canvas-dpi'
  'fit-filter|src/render/screen.lua|c:setFilter("linear", "linear")|c:setFilter("nearest", "nearest")|fit-filtering|game-canvas-dpi prescale-canvas-dpi'
)

echo "hidpi-sim: mutation proof (SIMULATED HiDPI evidence; scales: $SCALES)"
overall=0
for entry in "${MUTATIONS_TABLE[@]}"; do
  IFS='|' read -r name file old new want forbid <<<"$entry"
  work="$(mktemp -d)"
  for p in main.lua conf.lua src config levels assets; do
    if [[ -e "$ROOT/$p" ]]; then cp -R "$ROOT/$p" "$work/"; fi
  done
  replace_once "$work/$file" "$old" "$new"
  set +e
  result="$(run_matrix "$work" "$OUT/mutation-$name")"
  code=$?
  set -e
  rm -rf "$work"
  while IFS= read -r l; do echo "  [$name] $l"; done <<<"$result"
  verdict="DETECTED"
  if [[ $code -eq 0 ]]; then verdict="NOT DETECTED"; fi
  if ! grep -q -- " $want" <<<"$result"; then verdict="NOT DETECTED (missing label $want)"; fi
  for f in $forbid; do
    if grep -q -- " $f" <<<"$result"; then verdict="NOT INDEPENDENT (unexpected label $f)"; fi
  done
  echo "MUTATION $name: '$old' -> '$new' in $file -> $verdict by $want"
  [[ "$verdict" == "DETECTED" ]] || overall=1
done
if [[ $overall -ne 0 ]]; then
  echo "hidpi-sim: mutation proof FAILED" >&2
  exit 1
fi
echo "hidpi-sim: mutation proof OK (every mutation detected by its own check)"
