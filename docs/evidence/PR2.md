# PR #2 (merged as `d3ccccf`): per-platform toolchain isolation — evidence summary (archived)

Standalone tooling PR between G0 (merged as `550a9f1`) and G1. It contains no gameplay, simulation or asset changes. The owner explicitly authorised one narrowly scoped rendering correction as an exception: the Retina pixel-density fix, see "Retina pixel-density fix" below and `docs/evidence/PR2-native-macos.md`. The G0 evidence summary is archived in `docs/evidence/G0.md`.

| Item | Evidence class | Status |
|---|---|---|
| Native macOS toolchain isolation | native (owner, Apple M3 Pro) | **PASS** |
| Original native Retina smoke | native (owner) | **FAIL**: canvas created at display DPI (1280×720 texels), root-caused |
| Linux sandbox reproduction of that failure | sandbox, simulated DPI defaults | **PASS**: byte-identical to the native PNGs |
| Fix, strengthened smoke and HiDPI harness: Linux `make check` | sandbox + SIMULATED HiDPI | **PASS** |
| Corrected native Retina rendering at 800x600 (run of `2009213`) | native (owner) | **PASS**: in-app SMOKE OK, all values exact; canvas and window PNGs byte-identical to the sandbox renders |
| Native shell smoke wrapper (run of `2009213`) | native (owner) | **FAIL**: BSD `od` extra empty line parsed as `0x0`; fixed in `2e4469a` |
| Portability fix: Linux `make check` + emulated macOS userland | sandbox | **PASS** |
| **Final native acceptance of `2e4469a`** | native (owner, Apple M3 Pro) | **PASS**: fmt-check, lint 0/0 (51 files), shellcheck, 196 tests, validate; smoke 800x600 / 1024x640 / 1280x720 exact; HiDPI harness (SIMULATED defaults) 8/8 |
| BSD `grep: empty (sub)expression` in the harness | native (owner) | non-blocking (diagnostic label only); G1 follow-up |

## Problem
G0 installed native tools into one flat location (`.rocks/bin`, `.rocks/lib`, `.tools/stylua`). The macOS host and the Docker sandbox mount the same checkout, so whichever ran `make bootstrap` last overwrote the other's binaries. For example, the sandbox left Linux arm64 ELF files (`stylua`, `lfs.so`, `system/core.so`, `term/core.so`) where macOS expected Mach-O.

## Change
- `tools/platform.sh` (new) is the single source of the platform key `<os>-<arch>`: lowercase `uname -s`, with the architecture normalized to `x86_64`/`arm64`. It rejects keys that are not safe directory names.
- `tools/bootstrap.sh` installs into `.rocks/<platform>/` and `.tools/<platform>/`. The StyLua asset is selected by platform key, with the same four SHA-256 pins. `--print-plan` prints the resolved plan without installing anything. A legacy flat layout is reported, never deleted.
- `Makefile` derives `ROCKS`, `TOOLS`, `LUA_PATH` and `LUA_CPATH` from the platform key. New targets:
  - `make toolchain` prints the resolved key, directories and Lua search paths.
  - `require-toolchain` stops with a `make bootstrap` hint when this platform is not installed, instead of running another platform's binaries.
  - `luacheck-version` and `stylua-version`.
- `tools/evidence.sh` records the platform in `MANIFEST.txt` and reads tool versions through the Makefile (no hard-coded `.rocks/bin` / `.tools/stylua` paths).
- Docs: README, AGENTS.md, TECHNICAL_DESIGN §11, and CI.md (new "Toolchain layout" section with migration steps).
- `docs/acceptance/G0-macos.md`: only the reference to the archived G0 summary changed.

## Preserved
- Versions: busted 2.3.0-1, luacheck 1.2.0-1, StyLua 2.6.0.
- StyLua SHA-256 pins for linux-x86_64, linux-arm64, darwin-arm64 and darwin-x86_64 (byte-identical values).
- Quality gate: `make check` = fmt-check + lint + test + validate + smoke. Fail-closed `make evidence` is unchanged apart from the manifest lines.
- On this sandbox (linux-arm64), the freshly bootstrapped `.rocks/linux-arm64/` has exactly the same set of rock names and versions as the old flat tree, and `.tools/linux-arm64/stylua` is byte-identical to the old `.tools/stylua`.

## Tests
`tests/tools/toolchain_spec.lua` (13 tests; total suite 156, 0 failures):
- Platform-key normalization (Darwin/Linux × arm64/aarch64/x86_64/amd64), rejection of unsafe keys, and distinct keys for an Apple-silicon Mac and its Linux container.
- The Makefile and bootstrap resolve the same directories on this machine.
- With a fake `uname` reporting Darwin arm64:
  - every fmt-check, lint and test command goes to `.rocks/darwin-arm64/` and `.tools/darwin-arm64/`;
  - `LUA_PATH` and `LUA_CPATH` point at the darwin tree;
  - nothing references the legacy flat paths or this machine's tree.
- An uninstalled platform fails with the bootstrap hint.
- Pinned versions, and the StyLua asset and SHA-256 for all four platforms, match G0. A platform without a pin is refused.
- A legacy flat layout is reported but not deleted, and no warning is shown when only per-platform directories exist.
- `tests/tools/evidence_spec.lua`: per-platform ignored directories keep the tree clean for final evidence.
- Mutation check: reverting the Makefile to the flat `.rocks`/`.tools` paths makes 4 toolchain tests fail.

## Retina pixel-density fix (owner-approved exception)
- Root cause: LÖVE 11 creates `newCanvas`/`newFont` at the display DPI unless told otherwise. On Retina the 640×360 game canvas was 1280×720 texels and text was rasterised at 2×. The old smoke check then compared against the wrong texels (949084 false mismatches), and the real defect (2× text detail) sat behind that. Pixel evidence, reproduction and ablation: `docs/evidence/PR2-native-macos.md`.
- Fix: explicit `dpiscale = 1` for the game canvas and the fit prescale canvas, and DPI scale 1 for the test-pattern font. The F3 overlay font is explicitly native-DPI (screen-space). Invariant: TECHNICAL_DESIGN §2 "Pixel density".
- Smoke checks before any pixel comparison: canvas = 640×360 texels at DPI 1; screenshot = physical framebuffer; viewport = canvas × scale, inside the window. After the pass, content and letterbox counts must match exactly. Tolerance is unchanged. `--scale-mode=fit` verifies sharp bilinear: exact nearest prescale, then bilinear bounds plus interpolation present.
- `tools/check_dpi.lua` (validate) statically requires an explicit density on every canvas and font in `src/`.
- `tools/hidpi_sim.sh` (check, evidence) is SIMULATED HiDPI: implicit DPI defaults forced to 1/1.25/1.5/2, integer + fit, byte-compared with the DPI-1 reference. `--mutations` proves that removing each explicit setting (game canvas, prescale canvas, font), or switching the fit filter to nearest, is detected by its own check.
- The original native PNGs and log are kept outside Git in `native-evidence/` (survives `make clean`). Their hashes are in `docs/evidence/PR2-native-macos.md`, and `make evidence` verifies and packages them as `native/`.
- Tests: 186 (156 + 30 new); 196 after the portability fix (+10).

## Shell wrapper portability fix (after the native 800x600 re-run)
- Native: the corrected Retina rendering passed at 800x600. Then `tools/smoke.sh` failed with `unexpected canvas size 640x360\n0x0`. Cause, confirmed from the native log bytes and from Apple's `od` source: with `-An`, BSD `od` prints an extra empty line, and the per-line awk parser turned it into a second `0x0` result. `tools/hidpi_sim.sh` had the same parser, which would have produced a false `game-canvas-dpi` label. The harness also formatted its expected probe with a locale-dependent `printf %.2f`, which breaks under decimal-comma locales such as `pl_PL`.
- Fix: `tools/lib/portable.sh` is a shared reader that checks the PNG signature and IHDR, requires exactly 24 bytes including eight dimension bytes, ignores layout and whitespace, and rejects malformed input. It also adds a C-locale `printf_c`. The strict 640x360 assertion is unchanged.
- Tests: `tests/tools/portable_sh_spec.lua` (+10) uses byte-exact GNU and Apple `od` fixtures. The spec was mutation-checked; both scripts were validated end-to-end under bash 3.2.57 with Apple `od` and `pl_PL` (emulated userland, sandbox evidence). Details: `docs/evidence/PR2-native-macos.md` §4.
- New native artifacts (outside Git): `native-evidence/pr2-retina-fixed-800x600-2026-11-26/`, with hashes in the same §4.

## Evidence class (sandbox: Linux arm64, Xvfb, Mesa llvmpipe — NOT native)
- `make bootstrap` and `make check` ran in the sandbox (linux-arm64). `hidpi-sim/` results are SIMULATED HiDPI evidence.
- Native, owner-reported: `make bootstrap` / `make check` toolchain steps on macOS (darwin-arm64) PASS, with both platform trees coexisting. The original native Retina smoke FAILED (fixed here).
- Native, owner-reported (corrected version, `2009213`): Retina rendering at 800x600 PASS; wrapper FAIL (fixed here); full `make check` FAIL because of the wrapper only.
- Native, owner-reported (final, `2e4469a`): full `make check` PASS, including the three Retina smoke sizes and the HiDPI harness (SIMULATED defaults on a real DPI-2 window). The numeric exit status is not in the log; the log is complete with no `make` error. Artifacts in `native-evidence/pr2-final-native-acceptance-2e4469a-2026-11-26/`, hashes and analysis in `docs/evidence/PR2-native-macos.md` §5. Sandbox renders at the same physical sizes are byte-identical to the native integer-mode windows.
- Follow-up for G1 (not part of PR #2): `tools/hidpi_sim.sh` `labels_for_problems` uses an empty regex alternative that BSD grep rejects, so the `other-check` diagnostic label is lost on macOS. Failure detection is unaffected. Requirements are in §5.

## Not changed
No gameplay or simulation changes. CI stays disabled. No new runtime or tooling dependencies (the harness uses LÖVE, bash, perl, `cmp` and `od`, all already used by the existing tooling). No BMAD.
