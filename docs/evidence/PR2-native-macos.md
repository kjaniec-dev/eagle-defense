# PR #2 — native macOS verification and Retina smoke root cause

Date: 2026-11-26. Native host: Apple M3 Pro, macOS, LÖVE 11.5, renderer `OpenGL / 4.1 Metal - 91.7 / Apple / Apple M3 Pro`.
The results below are recorded separately on purpose. The toolchain isolation result does not depend on the rendering result, and simulated evidence is never native evidence.

| Item | Evidence class | Status |
|---|---|---|
| Native macOS toolchain isolation | native (owner) | **PASS** (§1) |
| Original native Retina smoke (before the fix) | native (owner) | **FAIL**, root cause in §2 |
| Linux sandbox reproduction of the native failure | sandbox, simulated DPI defaults | **PASS**: byte-identical reproduction (§2) |
| Fix + strengthened checks + HiDPI harness, Linux `make check` | sandbox / SIMULATED HiDPI | **PASS** (§3) |
| Corrected native Retina rendering at 800x600 (in-app smoke) | native (owner) | **PASS** (§4) |
| Native shell smoke wrapper (`tools/smoke.sh`) | native (owner) | **FAIL**: BSD `od` portability defect after SMOKE OK; fixed in §4, native re-run pending |
| Native smoke 1024x640 | native | **NOT RUN** (wrapper aborted after 800x600) |
| Native smoke 1280x720 | native | **NOT RUN** |
| Native HiDPI harness (SIMULATED defaults on a real HiDPI window) | native host | **NOT RUN** |
| Full native `make check` | native (owner) | **FAIL**, only because of the wrapper; fmt-check, lint, shellcheck, 186 tests and validate PASS |
| Portability fix: Linux `make check` + macOS-userland emulation | sandbox | **PASS** (§4) |

## 1. Native toolchain isolation — PASS (native evidence, reported by the owner)
| Check | Result |
|---|---|
| `make bootstrap` on macOS arm64 | PASS |
| Per-platform isolation: `.rocks/darwin-arm64` + `.rocks/linux-arm64`, `.tools/darwin-arm64` + `.tools/linux-arm64` coexist | PASS |
| `.tools/darwin-arm64/stylua` | Mach-O 64-bit arm64 |
| `.tools/linux-arm64/stylua` | ELF 64-bit AArch64 |
| fmt-check + luacheck | 0 warnings / 0 errors in 43 files |
| shellcheck | OK |
| busted | 156 successes / 0 failures / 0 errors / 0 pending |
| Architecture boundaries | OK |
| Asset validation | OK |

### Sandbox cross-check after the native bootstrap (sandbox evidence: Linux arm64, Xvfb, Mesa llvmpipe)
- No file under `.rocks/linux-arm64/` or `.tools/linux-arm64/` is newer than the native run; the directories date from the sandbox bootstrap (15:05), the darwin ones from the native run (18:30).
- `.tools/linux-arm64/stylua` SHA-256 `f3102639cf8d52a105f503030d97c12ccc4b901a193f849095db282fb18c2993` (ELF AArch64), unchanged by `make check`. `.tools/darwin-arm64/stylua` SHA-256 `c36d9bd2299c990d4fe9420a372a76b761f4b8db054dda248f778f59ddef4149` (Mach-O arm64).
- Native rocks (`lfs.so`, `system/core.so`, `term/core.so`) are ELF AArch64 under `linux-arm64` and Mach-O arm64 under `darwin-arm64`.
- `make check` in the sandbox: exit 0. 0 warnings / 0 errors in 43 files, shellcheck OK, busted 156/0/0/0, boundaries OK, assets OK, smoke OK at 1280x720, 1920x1080, 1366x768 and 800x600 (all `mismatches=0 letterbox_bad=0`).
- The legacy flat layout (`.rocks/bin`, `.rocks/lib`, `.rocks/share`, `.tools/stylua`) from before PR #2 is still on disk. The Makefile does not use it; it was not deleted.

## 2. Native Retina pixel-perfect smoke — FAIL (native evidence)
```text
SMOKE FAIL ticks=120 state=sandbox p1=5600,4992 p2=4256,3552 logical=800x600 physical=1600x1200
dpi=2.00 screenshot=1600x1200 scale=2 offset=160,240 pixels_checked=1382400 mismatches=949084
letterbox_bad=0 renderer=OpenGL / 4.1 Metal - 91.7 / Apple / Apple M3 Pro os=OS X
```
The run stopped at the first size, so the macOS sizes 1024x640 and 1280x720 were **not** exercised.

Preserved native artifacts: `native-evidence/pr2-retina-original-fail-2026-11-26/` (with `SHA256SUMS` and a README). The directory is gitignored and not removed by `make clean`. `make evidence` copies it into the package as `native/` after verifying that the checksums match and that every hash below is recorded here.

| File | Size | SHA-256 |
|---|---|---|
| `smoke.png` (canvas readback) | **1280x720**, 4-bit palette | `b2a8717e70f60ba2992a69641f5b68dcb0821758bf84722256a68d8ba7cc4679` |
| `smoke-window.png` (backbuffer) | 1600x1200, 4-bit palette | `556fe81fab397ee7dc6e7dc13708a8041519b7878784e0c9681e61226c72d4de` |
| `smoke.log` | | `ad4ce101b2ebbfc19d1e905a2d7f0cc35e7e625f1a942af1d2419895a9e7a4c3` |

### Root cause
On a HiDPI display, LÖVE 11 creates canvases and fonts at `love.graphics.getDPIScale()` unless `dpiscale` is passed explicitly. `src/render/screen.lua` calls `love.graphics.newCanvas(640, 360)` without it, so on Retina the game canvas is **1280x720 physical texels** (640x360 logical units). `src/render/test_pattern.lua` calls `newFont(10, "mono")`, so glyphs are also rasterized at 2x.

This has two consequences.

1. **Smoke-test assumption (false failure).** `smoke_report` passes `canvas_image:getWidth()/getHeight()` (1280x720 texels) to `upscale_check.verify`, but `vp` was computed for a 640x360 canvas (`scale=2`). The check therefore maps every window pixel to the wrong texel (an effective 4x expectation) and compares a 2560x1440 region clipped to the window. That gives `pixels_checked = 1440 x 960 = 1382400` instead of `640·360·2² = 921600`. It also treats the right-hand letterbox as in-canvas, which is why `letterbox_bad=0`.
2. **Real rendering defect (Retina only).** The internal resolution is not 640x360 on Retina, which contradicts ART_DIRECTION ("Internal resolution 640×360, integer-scaled") and TECHNICAL_DESIGN §"Internal canvas is 640×360". Anything not aligned to the 2x2 texel grid is rendered at double density. In the G0 pattern only text is affected, but future sub-pixel motion, rotation, lines or scaled sprites would be too. On fractional DPI (e.g. Windows 150%) the canvas would be 960x540.

The presented geometry is correct. Window = canvas at 1:1 texels, at the right offset.

### Pixel evidence (computed from the preserved native PNGs)
| Hypothesis | Result |
|---|---|
| H0: replay the smoke check on the native PNGs | checked=1382400, **mismatches=949084**, letterbox_bad=0, first=(162,240). Reproduces the native log exactly. |
| H1: window(x,y) == canvas(x−160, y−240) at 1:1 texels; the rest black | checked=921600, **mismatches=0, letterbox_bad=0** |
| H2: is the 1280x720 canvas a nearest 2x of a 640x360 image? | No: 1599 of 230400 2x2 blocks are non-uniform, all in text rows (logical y 8–15, 26–35, 38–45, 56–65, 68–76, 80–89) |
| H3: native canvas vs the Linux 640x360 canvas (same tick, same positions) upscaled 2x | 7520 of 921600 texels differ, all in the same text rows; all other content is identical |

Representative H0 mismatches (window xy → canvas texel the check used: expected → actual):
- (162,240) → (1,0): (255,51,51) → (20,23,28)
- (194,362) → (17,61): (178,183,198) → (20,23,28)
- (774,447) → (307,103): (20,23,28) → (33,35,43)
- (544,624) → (192,192): (20,23,28) → (56,61,73)
- (1068,979) → (454,369): (33,35,43) → (0,0,0), which is the real letterbox compared against canvas content

H0 difference distribution (window − canvas, per channel), top entries: (−33,−35,−43)×257568, (−13,−12,−15)×199548, (+13,+12,+15)×192208, (−20,−23,−28)×172864, (−56,−61,−73)×23584, (+36,+38,+45)×17776. Every difference is between two entries of the same 11-colour palette. There are no small (±1…±11) deltas of the kind that gamma, sRGB conversion or filtering would produce.

### Hypotheses ruled out
1. **Colour space / gamma:** the canvas, window and Linux images use the identical 11-colour set, bit-exact; H1 has 0 mismatches.
2. **Pixel formats:** both readbacks are 8-bit per channel with identical values. No format conversion is observable.
3. **DPI handling:** root cause (above).
4. **Texture filtering:** the window has no colours outside the canvas palette; H1 is exact.
5. **Spatial alignment:** offset 160,240 and scale are exact. Black pixels = 1600·1200 − 921600 + 128 in-canvas black texels = 998528, which matches the counts.
6. **Screenshot readback on macOS GL:** `captureScreenshot` returns 1600x1200 physical, top-left origin, no flip, values exact.

### Reproduction in the sandbox (sandbox evidence)
A scratch harness (not in the repo) ran the real app under Xvfb at window 1600x1200, DPI 1, and supplied LÖVE's Retina defaults explicitly: `dpiscale=2` for `newCanvas`/`newFont` when the caller passes none.
- Output: `mismatches=949084`, and `smoke.png` and `smoke-window.png` are **byte-identical (same SHA-256) to the native M3 Pro artifacts**.
- Ablation, canvas 2 / font 1: FAIL (canvas size alone triggers the check failure).
- Ablation, canvas 1 / font 2: smoke **passes**, but 1782 texels in the text rows differ from the Linux canvas. The smoke check cannot see this, because it compares the window with the canvas, not with a reference.
- Canvas 1 / font 1: OK, checked=921600, and the canvas is byte-identical to the Linux 800x600 canvas.

## 3. Fix (owner-approved 2026-11-26, implemented in PR #2)
Exact HEAD, test counts and evidence package SHA-256: see the PR #2 description. A committed file cannot name its own commit.

### Rendering (narrowly scoped exception to the tooling-only scope)
- `src/render/screen.lua`: `newCanvas(self.w, self.h, { dpiscale = 1 })` for the game canvas and `newCanvas(self.w * k, self.h * k, { dpiscale = 1 })` for the fit-mode prescale canvas.
- `src/render/test_pattern.lua`: `newFont(10, "mono", 1)`.
- Audit of every graphics resource constructor in `src/`: the four listed here were the only `newCanvas`/`newFont` calls. The F3 overlay font (`src/render/debug_overlay.lua`) is drawn in window space after presentation, so it now passes `love.graphics.getDPIScale()` **explicitly**, with a `-- dpi: native` marker. Window HiDPI stays enabled. No `newImage`, `newImageFont` or `SpriteBatch` exists yet; images do not default to the display DPI in LÖVE 11.
- Invariant documented in TECHNICAL_DESIGN §2 "Pixel density", and enforced statically by `tools/check_dpi.lua` (`make validate`).

### Smoke verification (`src/app/upscale_check.lua`, new `src/app/fit_check.lua`)
The tolerance is unchanged (`TOL = 1.5/255`, locked by a test). Before any pixel comparison the smoke now requires:
- canvas readback = configured 640×360 texels, and canvas DPI = 1;
- screenshot = physical framebuffer;
- integer scale, with `vp.w == canvas_w·scale`, `vp.h == canvas_h·scale` (also asserted inside `verify`) and the viewport inside the window.

A failed setup is reported as `problems=canvas_pixels:1280x720!=640x360;canvas_dpi:2!=1;…` instead of a pixel count. After the pixel pass, `pixels_checked == expected_checked` and `letterbox_checked == expected_letterbox` must hold exactly.

`--scale-mode=fit` checks the sharp-bilinear path against its intended filtering, not nearest equality:
- prescale canvas = (640k)×(360k) texels at DPI 1, and an exact nearest k-upscale of the canvas;
- every presented pixel lies within the colour range of the bilinear neighbourhood (sampling slack 1/16 texel, same colour TOL);
- interpolated pixels exist at a non-integer ratio;
- letterbox is black, with exact counts. Pixel centres exactly on an edge are counted separately, and that count is also predicted exactly.

Regression tests: `tests/app/upscale_check_spec.lua` (+13) and `tests/app/fit_check_spec.lua` (+10) cover invalid viewport/canvas combinations: Retina 1280×720 at DPI 2, Windows 150 % 960×540, screenshot ≠ framebuffer, non-integer scale, viewport ≠ canvas×scale, viewport outside the window, incomplete counts, nearest instead of linear, prescale at display DPI. Also `tests/app/args_spec.lua` (+1, `--scale-mode`), `tests/tools/dpi_audit_spec.lua` (+5) and `tests/tools/evidence_spec.lua` (+1).

### HiDPI regression harness — SIMULATED HiDPI evidence, not native
`tools/hidpi_sim.sh` (in `make check` and `make evidence`) runs the real app through `tools/hidpi_sim/`. That entry point forces LÖVE's implicit `newCanvas`/`newFont` DPI default to 1, 1.25, 1.5 and 2, in integer mode (1366x768) and fit mode (900x600). Every case must give SMOKE OK, show a probe line proving the simulation was applied, reach the expected window, tick and markers, and produce canvas and window PNGs byte-identical to the DPI-1 reference. Not simulated: the real window's DPI transform, which only native acceptance covers.

Linux sandbox results (Xvfb, Mesa llvmpipe):
- matrix: 8/8 `CASE … PASS`;
- the exact native failure geometry (1600x1200, implicit DPI 2) now gives `SMOKE OK … canvas=640x360 canvas_dpi=1.00 scale=2 offset=160,240 pixels_checked=921600 expected_checked=921600 letterbox_checked=998400 expected_letterbox=998400 problems=none`, with canvas and window byte-identical to the DPI-1 run.

Mutation proof (`tools/hidpi_sim.sh --mutations`). Each mutation is applied to a copy of the app; the label is the check that caught it:

| Mutation | Integer mode | Fit mode | Detected by |
|---|---|---|---|
| game canvas `{ dpiscale = 1 }` removed | FAIL at 1.25/1.5/2 (`canvas_pixels`, `canvas_dpi`) | FAIL at 1.25/1.5/2 | `game-canvas-dpi` |
| prescale canvas `{ dpiscale = 1 }` removed | PASS (not used) | FAIL at 1.25/1.5/2 (`prescale_pixels`, `prescale_dpi`); game canvas still OK | `prescale-canvas-dpi` |
| test-pattern font DPI `1` removed | in-app SMOKE OK, but FAIL vs reference at 1.25/1.5/2 | same | `content-vs-reference` |
| fit prescale filter linear → nearest | PASS (not used) | FAIL at every scale (`blended:0:expected_linear_filtering`) | `fit-filtering` |

DPI 1 passes in every mutation, as expected: Xvfb's real default is 1. This is exactly why the original defect was invisible in the sandbox.

### Native re-acceptance
Commands, expected values per logical size (800x600, 1024x640, 1280x720) and the checklist are in `docs/acceptance/PR2-macos-retina.md`. **Native PASS must not be reported until the owner runs it.**

## 4. Native re-run of the corrected version (2026-11-26) and the shell wrapper portability fix

### Native result — rendering PASS at 800x600, wrapper FAIL (native evidence, owner's run)
The owner ran `make check 2>&1 | tee build/native-check.log` on the Apple M3 Pro. The log does not record the commit; its 186 tests and its `check_dpi` step match `2009213`. fmt-check, luacheck (0/0 in 50 files), shellcheck, busted (186 / 0 / 0 / 0), boundaries, assets and DPI validation all passed. The first smoke size then reported:

```text
SMOKE OK ticks=120 state=sandbox p1=5600,4992 p2=4256,3552 logical=800x600 physical=1600x1200 dpi=2.00 screenshot=1600x1200 mode=integer canvas=640x360 canvas_dpi=1.00 scale=2 offset=160,240 pixels_checked=921600 expected_checked=921600 mismatches=0 letterbox_checked=998400 expected_letterbox=998400 letterbox_bad=0 problems=none renderer=OpenGL / 4.1 Metal - 91.7 / Apple / Apple M3 Pro os=OS X
smoke[800x600]: unexpected canvas size 640x360
0x0
make: *** [smoke] Error 1
```

Every value matches the 800x600 row of `docs/acceptance/PR2-macos-retina.md`. The wrapper aborted before 1024x640, 1280x720 and `hidpi-sim`, so those were **not run**.

The artifacts were copied unchanged from the owner's `build/` to `native-evidence/pr2-retina-fixed-800x600-2026-11-26/` before any sandbox command touched `build/`. That directory is outside Git and survives `make clean`.

| File | Size | SHA-256 |
|---|---|---|
| `smoke.png` (canvas readback) | 640x360, 4-bit palette | `0bb5bb198021179823c555e5754fb2a64cf53b32d0e597daef17d73fcce47cde` |
| `smoke-window.png` (backbuffer) | 1600x1200, 4-bit palette | `d7a904a9028d9dc1d289d72f44b3a48180dbba66bdeba95956010e9d8c40cf16` |
| `smoke.log` | | `eba55d84e44fe6b94a8f74d67d6c236438708a7dcc5679e4a577fa538e4a1c17` |
| `native-check.log` | | `11ed12ac073b1b7bb859e4bec1c7ca251a71410bddf8154bd5d36d4f3bcd8180` |

Independent pixel cross-check (a comparison in the sandbox, not native evidence): the native canvas PNG is **byte-identical** to the Linux sandbox 640x360 canvas. The native 1600x1200 window PNG is **byte-identical** to a Linux sandbox run at 1600x1200 (DPI 1, scale 2, offset 160,240). The 7520 differing text texels of §2 are gone.

### Root cause of the wrapper failure (confirmed from the actual output)
- The native log holds `640x360`, a newline, then `0x0`. The per-line parser in `tools/smoke.sh` (and the copy in `tools/hidpi_sim.sh`) printed one result per input line of `od -An -tu1 -j16 -N8`. So `od` produced one complete line and one line with no fields. GNU `od` prints exactly one line, which is why Linux passed.
- Apple's `od` is `hexdump` invoked as `od` (`apple-oss-distributions/shell_cmds`, `hexdump/`). Its `parse.c` forces an extra blank line for `-A n` (comment: "Force -A n to dump extra blank line like default od behavior"), and pads the last data line with spaces.
- Reproduced in the sandbox with that `od` built from source (tag `shell_cmds-329`, `-D__APPLE__`) on the native canvas PNG. Its output is the data line plus trailing spaces, `\n`, then an empty `\n`. The old parser on it prints exactly `640x360\n0x0\n`. Running the pre-fix `tools/smoke.sh` with that `od` (and bash 3.2) reproduces the native message verbatim; with GNU `od` it passes.
- This is a test-harness defect, not a rendering defect. No rendering code changed.

### Further macOS issues found in the harness review (`tools/hidpi_sim.sh`)
Checked under bash 3.2.57 built from Apple's source (`apple-oss-distributions/bash`, tag `bash-144`; macOS ships 3.2.57):
1. **Same `od` defect, worse symptom.** The pre-fix harness with Apple `od` marked every case FAIL with the false label `game-canvas-dpi`, a wrong rendering diagnosis (reproduced: 4/4 cases with `HIDPI_SIM_SCALES="1 2"`).
2. **Locale-dependent `printf %.2f`.** The expected probe string was formatted by bash's `printf`, which parses and prints floats per `LC_NUMERIC`. Under a decimal-comma locale such as `pl_PL.UTF-8`, `printf %.2f 1.25` fails with "invalid number" and prints `0,00`, while LÖVE prints `1.25`. Reproduced with bash 3.2 and glibc `pl_PL.UTF-8`: every case failed with `simulation-not-applied`. On a Mac this happens when Terminal sets `LANG` to a decimal-comma locale.
   - The obvious fix `LC_ALL=C printf …` works in bash 5 but **not** in bash 3.2, which ignores temporary assignments for builtins. Only an assignment inside a subshell works in both (verified).
3. No other bash 3.2 problem was found:
   - Empty arrays are only expanded as `${#a[@]}` or `${a[*]:-}`; plain `"${a[@]}"` on an empty array fails under `set -u` in 3.2.
   - Also fine in 3.2: `+=` on arrays, process substitution, here-strings, `local a=()`, `[[ … == *glob* ]]`, `${var%% *}`, and BSD `mktemp -d`, `cp -R`, `sed -n 's/…/p'` and `perl`.

### Fix
- `tools/lib/portable.sh` (new, sourced by both scripts):
  - `png_dims FILE` reads the first 24 bytes with `od -An -tu1 -N24`.
  - `png_dims_from_od` parses them independently of line layout. Whitespace and blank lines are ignored.
  - The input is rejected unless it has exactly 24 decimal tokens in 0..255: the PNG signature, an IHDR chunk of length 13, and exactly eight dimension bytes with width and height in 1..2^31−1.
  - Missing, empty, truncated, non-PNG and non-regular inputs fail with no output.
  - `printf_c` is `printf` in the C locale, using the subshell form.
- `tools/smoke.sh` keeps the strict check `[[ "$dims" == "640x360" ]]`. An unreadable header reports `'unreadable'`.
- `tools/hidpi_sim.sh` uses `png_dims` (an unreadable canvas PNG gets its own label `canvas-png-unreadable`, never `game-canvas-dpi`) and `printf_c` for the probe string.
- `make lint` now also runs shellcheck on `tools/lib/*.sh`. Tolerances, acceptance criteria and rendering code are unchanged.

### Tests
- `tests/tools/portable_sh_spec.lua`: +10 tests, 196 in total.
- It runs the real helpers under the system `bash` and `od`, which on a Mac means `/bin/bash` 3.2 and BSD `od`.
- Fixtures in `tests/fixtures/od/` are byte-exact GNU and Apple `od` captures of the native canvas header; provenance is in their README.
- The regression test proves the Apple fixture makes the old parser print exactly the native `640x360\n0x0\n`, while the new reader prints one line.
- Further tests cover:
  - harmless whitespace and blank-line variants;
  - 17 malformed inputs: empty, blank-only, the bare 8-byte dump, 23 or 25 bytes, a value of 256, negative and hex tokens, an address column, CRLF, a wrong signature, a wrong IHDR type or length, zero width or height, and the high bit set;
  - real files read with the system `od`;
  - `printf_c` under `pl_PL`;
  - static pins on both callers.

Mutation check of the spec (failing tests):

| Mutation of `tools/lib/portable.sh` | GNU od, bash 5, C locale | Apple od, bash 3.2, pl_PL |
|---|---|---|
| none | 0 | 0 |
| per-line parser restored | 7 | 7 |
| byte count not checked | 1 | 1 |
| 0..255 range not checked | 1 | 1 |
| PNG signature/IHDR not checked | 2 | 2 |
| no C-locale override | 0 | 1 |
| `LC_ALL=C printf` (temporary assignment) | 0 | 1 |

The locale mutations fail only where `pl_PL` is installed, which includes macOS. Minimal Linux containers fall back to C and cannot detect them.

### Validation in the sandbox (sandbox evidence; macOS userland emulated, not native)
With bash 3.2.57, Apple `od` (built as above) and `LANG=pl_PL.UTF-8`, under Xvfb:
- fixed `tools/smoke.sh` at the macOS default sizes `800x600 1024x640 1280x720`: 3 × SMOKE OK, `smoke: OK`;
- fixed `tools/hidpi_sim.sh`: 8/8 `CASE … PASS`;
- `--mutations`: all four DETECTED by their own labels.

With a fake `love` that writes chosen canvas headers, the wrapper accepts 640x360 and rejects 1280x720 (the original Retina shape), a truncated header and a non-PNG file. The full Linux `make check` result is in `docs/evidence/SUMMARY.md`.

What this does **not** prove: Apple's shipped `od` binary and macOS libc were emulated, not run. The native re-run in `docs/acceptance/PR2-macos-retina.md` remains required for 1024x640, 1280x720, the harness and the full `make check`.

