# PR #2 — native macOS Retina smoke re-acceptance

Fill this in on a real Mac with a Retina (HiDPI) display. Sandbox evidence (Linux, Xvfb, software GL) and the SIMULATED HiDPI harness do **not** count here.
Root cause and history: `docs/evidence/PR2-native-macos.md`.

**Status: PASS — final native acceptance of `2e4469a6b4cdeabd146920a1be198bf54c7d49f4` (owner, 2026-11-26).**

| Item | Status |
|---|---|
| Owner's run of `2009213`: Retina rendering at 800x600 | **PASS**; shell wrapper **FAIL** (BSD `od`), fixed in `2e4469a` |
| Owner's run of `2e4469a`: fmt-check, lint, shellcheck, 196 tests, validate | **PASS** |
| Native smoke 800x600 / 1024x640 / 1280x720 + wrapper | **PASS** 3/3, every value exact |
| HiDPI harness on the Mac (SIMULATED defaults, integer window 1280x720) | **PASS** 8/8 |
| BSD `grep: empty (sub)expression` during the harness | non-blocking, G1 follow-up |

Details, artifact hashes and the follow-up: `docs/evidence/PR2-native-macos.md` §5. Artifacts: `native-evidence/pr2-final-native-acceptance-2e4469a-2026-11-26/`.

## Environment

| Field | Value |
|---|---|
| Date | 2026-11-26 |
| Mac model / chip | Apple M3 Pro |
| macOS version | not reported (`os=OS X`) |
| Display / "looks like" resolution / DPI scale | DPI scale 2.00 (from the smoke lines) |
| LÖVE version (`love --version`) | not reported (project pins 11.5); renderer `OpenGL / 4.1 Metal - 91.7` |
| Commit SHA (`git rev-parse HEAD`) | `2e4469a6b4cdeabd146920a1be198bf54c7d49f4` (owner-reported) |

## Run (from a logged-in GUI session, in the repo root)

```sh
git fetch origin
git checkout tooling/platform-isolation
git pull --ff-only
git rev-parse HEAD                       # record it above
make toolchain                           # platform=darwin-arm64
make check 2>&1 | tee build/native-check.log
grep -E '^SMOKE (OK|FAIL)' build/smoke*.log
grep -E '^(CASE|hidpi-sim:)' build/native-check.log
bash --version | head -1                 # /bin/bash: 3.2.57 expected
od -An -tu1 -N24 build/smoke.png | cmp - tests/fixtures/od/bsd-macos-canvas-640x360.txt && echo "od fixture: match"
```

The last command confirms natively that the BSD `od` fixture used by `tests/tools/portable_sh_spec.lua` (captured in the sandbox from Apple's `od` source) matches the real macOS `od`.

`make check` runs fmt-check, lint, test, validate, the native smoke at the three default logical sizes `800x600 1024x640 1280x720`, and the SIMULATED HiDPI harness. The sizes must fit on the display. If one does not, record that and rerun only the sizes that fit, with `SMOKE_SIZES="…" make smoke`. Never mark a size that did not run as passed.

If the harness's 1366x768 window does not fit, use `HIDPI_SIM_INTEGER_SIZE=1280x720 make hidpi-sim`. On a Mac, harness results are still labelled SIMULATED (simulated resource defaults on a real HiDPI window); they are not the native acceptance below.

Afterwards, check that the sandbox toolchain is intact: `ls .rocks .tools`, which should list both `darwin-arm64` and `linux-arm64`.

## Expected integer-mode smoke values at Retina DPI 2.00

Every line must read `SMOKE OK` and contain all of the following:

| Logical | physical / screenshot | canvas | canvas_dpi | scale | offset | pixels_checked = expected_checked | letterbox_checked = expected_letterbox | mismatches | letterbox_bad |
|---|---|---|---|---|---|---|---|---|---|
| 800x600 | 1600x1200 | 640x360 | 1.00 | 2 | 160,240 | 921600 | 998400 | 0 | 0 |
| 1024x640 | 2048x1280 | 640x360 | 1.00 | 3 | 64,100 | 2073600 | 547840 | 0 | 0 |
| 1280x720 | 2560x1440 | 640x360 | 1.00 | 4 | 0,0 | 3686400 | 0 | 0 | 0 |

Each line must also contain `ticks=120`, `state=sandbox`, `p1=5600,4992 p2=4256,3552`, `mode=integer` and `problems=none`. `tools/smoke.sh` additionally requires the canvas PNG header to be 640x360.

(Values computed from `src/render/viewport.lua` at DPI 2.00. A display with another DPI scale gives other physical sizes, scales and counts. In that case record the line as printed; the rules canvas = 640x360, canvas_dpi = 1.00, `pixels_checked == expected_checked`, `letterbox_checked == expected_letterbox`, 0 mismatches and 0 letterbox errors still apply.)

## Checklist

| # | Check | Expected | Pass/Fail | Notes |
|---|---|---|---|---|
| 1 | Toolchain | `make toolchain` → `darwin-arm64`; fmt-check, lint, test and validate pass | PASS | `.tools/darwin-arm64`, lint 0/0 in 51 files, 196/0/0/0 |
| 2 | Smoke 800x600 | Row above, `SMOKE OK`; no `unexpected canvas size` | PASS | exact |
| 3 | Smoke 1024x640 | Row above, `SMOKE OK` | PASS | exact |
| 4 | Smoke 1280x720 | Row above, `SMOKE OK` | PASS | exact |
| 5 | HiDPI harness (SIMULATED, on a real HiDPI window) | `hidpi-sim: OK`, 8 × `CASE … PASS` | PASS | integer window 1280x720; BSD grep warning, G1 follow-up |
| 6 | Visual (optional) | `love .`: test-pattern text is as blocky as the 1× grid (no finer 2× glyph detail); F3 overlay text is crisp | not reported | |
| 7a | Wrapper | `smoke: OK (800x600 1024x640 1280x720) on Darwin`; `make check` exits 0 | PASS | wrapper line present; numeric exit status not in the log (`tee`), log complete with no `make: ***` |
| 7b | `od` fixture | `od fixture: match` | not reported | the wrapper passed on real BSD `od` |
| 7 | Isolation | `.rocks/linux-arm64` and `.tools/linux-arm64` still present after the Mac run | PASS | checked from the sandbox on the shared checkout; both StyLua hashes unchanged |

Attach `build/native-check.log` and `build/smoke*.png` / `build/smoke*.log`. Move them out of `build/` (e.g. to a new `native-evidence/<set>/` with a `SHA256SUMS`) if they need to survive `make clean`.
