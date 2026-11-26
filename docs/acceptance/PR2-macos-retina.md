# PR #2 — native macOS Retina smoke re-acceptance

Fill this in on a real Mac with a Retina (HiDPI) display. Sandbox evidence (Linux, Xvfb, software GL) and the SIMULATED HiDPI harness do **not** count here.
Root cause and history: `docs/evidence/PR2-native-macos.md`.

**Status: PARTIAL — re-run required.**

| Item (owner's run of `2009213`, 2026-11-26) | Status |
|---|---|
| Retina rendering at 800x600 (in-app smoke, all values as in the table below) | **PASS** |
| Shell smoke wrapper | **FAIL**: BSD `od` portability defect after SMOKE OK (fixed after `2009213`) |
| 1024x640 | **NOT RUN** |
| 1280x720 | **NOT RUN** |
| HiDPI harness on the Mac | **NOT RUN** |
| Full `make check` | **FAIL** (wrapper only) |

Details: `docs/evidence/PR2-native-macos.md` §4. Re-run everything below on the new PR head, including 800x600.

## Environment

| Field | Value |
|---|---|
| Date | |
| Mac model / chip | |
| macOS version | |
| Display / "looks like" resolution / DPI scale | |
| LÖVE version (`love --version`) | (project pins 11.5) |
| Commit SHA (`git rev-parse HEAD`) | must equal the PR #2 HEAD under review |

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
| 1 | Toolchain | `make toolchain` → `darwin-arm64`; fmt-check, lint, test and validate pass | | |
| 2 | Smoke 800x600 | Row above, `SMOKE OK`; no `unexpected canvas size` | | |
| 3 | Smoke 1024x640 | Row above, `SMOKE OK` | | |
| 4 | Smoke 1280x720 | Row above, `SMOKE OK` | | |
| 5 | HiDPI harness (SIMULATED, on a real HiDPI window) | `hidpi-sim: OK`, 8 × `CASE … PASS` | | |
| 6 | Visual (optional) | `love .`: test-pattern text is as blocky as the 1× grid (no finer 2× glyph detail); F3 overlay text is crisp | | |
| 7a | Wrapper | `smoke: OK (800x600 1024x640 1280x720) on Darwin`; `make check` exits 0 | | |
| 7b | `od` fixture | `od fixture: match` | | |
| 7 | Isolation | `.rocks/linux-arm64` and `.tools/linux-arm64` still present after the Mac run | | |

Attach `build/native-check.log` and `build/smoke*.png` / `build/smoke*.log`. Move them out of `build/` (e.g. to a new `native-evidence/<set>/` with a `SHA256SUMS`) if they need to survive `make clean`.
