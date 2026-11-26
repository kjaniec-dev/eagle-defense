# G0 — Project foundation: evidence summary

## Implemented
- Approved specification docs (GAME_DESIGN, TECHNICAL_DESIGN, ART_DIRECTION, ROADMAP), AGENTS.md and CLAUDE.md
- LÖVE 11.5 skeleton (`conf.lua`, `main.lua`) with a custom `love.run`
- `src/core`:
  - fixed-step loop (60 Hz, clamped and capped catch-up)
  - xorshift32 RNG
  - event queue
  - explicit state machine with deferred, whitelisted transitions
  - canonical Lua-literal serializer with a strict, non-executing parser
- `src/render`:
  - 640×360 canvas
  - integer and fit viewport math (HiDPI-aware, in physical pixels)
  - F3 debug overlay
  - PLACEHOLDER test pattern
- `src/input`:
  - P1/P2 keyboard and gamepad bindings
  - last-pressed-wins direction resolution
  - stick-to-4-way conversion with hysteresis
  - chronological input events with press latching between ticks
  - pad hot-plug
- `src/app`: boot → debug sandbox (not gameplay); `--smoke`, `--window`, `--smoke-out`, `--smoke-window-out`
- Tooling, all pinned:
  - `make bootstrap`, `make check`
  - busted, luacheck, StyLua, shellcheck
  - boundary checker (src/core and src/sim must stay pure)
  - asset manifest checker
  - reproducible `.love` built from the exact commit
  - fail-closed evidence package (`make evidence`), plus a DEV snapshot mode
- CI: deferred by the owner. The target is the company GitLab; the pipeline contract is in `docs/CI.md`.

## Independent review fixes (review of `014cc63`)

| Finding | Fix | Regression tests |
|---|---|---|
| P2-1 input ordering | `devices.lua` records press/release events in chronological order and ignores auto-repeat. `mapper.lua` applies the events in order, then the stick, then reconciles with the polled state. Ties are broken by a fixed order (up < down < left < right). Taps are latched for one tick. The InputFrame contract is unchanged. | `tests/input/mapper_spec.lua`: D→W, W→D, release restores, re-press, tie-break, taps, fire edges, key+pad in both orders, stick after events, replay determinism. `tests/input/devices_spec.lua` uses a fake `love`: event order, auto-repeat, unbound keys, pad→player, hot-plug, end-to-end D→W. On the old implementation they produce 8 failures and 4 errors. |
| P2-2 macOS smoke and HiDPI | Portable timeout (`timeout` → `gtimeout` → `perl`). Smoke reports `logical`, `physical`, `dpi` and `screenshot` sizes and fails if the screenshot size ≠ physical size or the logical size was not applied. The pixel check runs in physical pixels. There are macOS default sizes and `SMOKE_SIZES`, and the prerequisites are documented in `docs/CI.md`. | `viewport.to_logical` tests at DPI 2, 1.5 and 1.25. The perl timeout fallback was exercised manually (exit 142 after 1 s). The Linux pixel-perfect assertions are unchanged. |
| P2-3 canonical serialization | The array part is the contiguous prefix `1..n` (never `#t`). Encode and decode share the MAX_DEPTH semantics. The decoder rejects nil values in tables and duplicate keys (tracked separately from values). | Sparse tables built with different insertion histories, output across 2 independent LuaJIT processes, strict-decoding cases, exact depth boundary. On the old implementation they produce 5 failures. |
| P2-4 evidence integrity | `tools/evidence_gate.lua` (rules in `tools/lib/evidence.lua`): a clean tree is required, including untracked files and ignored files in source paths. All checks are mandatory. The `.love` is built via `git archive HEAD`, with the commit recorded in `.love.commit`. Mandatory files and smoke logs are validated. Copies are verified and checksums are checked before and after archiving. HEAD and the tree are re-checked at the end. Toolchain versions are recorded. `--dev` mode is separate and labelled. | `tests/tools/evidence_spec.lua`: rule unit tests, plus a temporary git repository proving the gate fails on untracked files and on ignored files in `src/`, and that a commit build excludes untracked files and records the exact SHA. |
| P3-1 PR metadata | The PR description now matches the final HEAD, the results and the full SHA-256. | n/a |
| P3-2 loader docs | TECHNICAL_DESIGN §9 describes the non-executing parser. No `loadstring` for level or save data. | n/a |

A test also caught a bug in the new evidence rules during development (`main.lua.orig` was matched as `main.lua`). It was fixed before commit.

Also found while fixing P2-4: the unanchored `evidence/` pattern in `.gitignore` also ignored `docs/evidence/`, so this summary was never committed. The build-output patterns are now anchored to the repo root, and the gate treats `docs/` as a source path (regression test in `tests/tools/evidence_spec.lua`).

## Automated evidence (sandbox: Linux arm64, Xvfb, Mesa llvmpipe — NOT native)
- `checks/` in the package holds the full output of fmt-check, lint, test, validate, smoke and love.
- The smoke test runs the real app for 120 ticks with scripted input at logical window sizes 1280×720, 1920×1080, 1366×768 and 800×600 (DPI 1).
  - It asserts the final marker positions, which match the pure-logic spec.
  - It asserts that every physical window pixel equals the nearest-neighbour integer upscale of the canvas, with a black letterbox.
- Mutation checks:
  - The loop epsilon mutation is caught by the 144 Hz test.
  - Last-pressed-wins is covered by the mapper tests.
  - A half-pixel draw offset is caught by the smoke pixel check.
  - The old serializer and the old input code fail the new tests.

## Known limitations
- **CI is deferred** (owner decision). The target is the company GitLab. The gate is a local `make check`.
- **Not verified natively:** macOS rendering, Retina/HiDPI scaling (DPI 2 is covered only by unit math and by the smoke design), real-GPU behavior, gamepads, frame pacing, and `bootstrap.sh` or `smoke.sh` on macOS. These are covered by `docs/acceptance/G0-macos.md` and the optional native `make smoke`.
- The sandbox debug markers are not gameplay. Their 1.5 px/tick speed is arbitrary.

## Manual acceptance
`docs/acceptance/G0-macos.md`
