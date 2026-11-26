# Eagle Defense — Roadmap v1.0

Each milestone goes through the same steps:
1. plan
2. owner approval
3. autonomous implementation
4. `make check` green
5. Draft PR
6. evidence package
7. independent review
8. fixes
9. native acceptance (if needed)
10. merge, **only on explicit owner authorization**

The next milestone never starts automatically.

| ID | Milestone | Key exit criteria | Native macOS acceptance |
|---|---|---|---|
| G0 | Project foundation (merged) | The skeleton runs; fixed-step loop and scaling work; input abstraction; the test, lint and format toolchain; CI deferred (target: company GitLab), with `make check` run locally as the gate; documentation. | Yes (launch, scaling, input smoke) |
| G1 | Core combat | Player movement, turn snapping, shooting, bullets, tank/bullet collisions, test arena, golden replays, plus the static art-direction spike (24 px vs 32 px). Plan: `docs/plans/G1_PLAN.md` (approved 2026-11-26). | Yes (feel) |
| G2 | Battlefield and destruction | Cell grid, partial brick, steel, water, forest, ice, level format + loader + validator | Optional |
| G3 | Visual vertical slice | Final-quality Classic environment, tanks, HQ, effects, lighting and bloom prototype, pixel-perfect pipeline. **Owner art approval gate.** | Yes (visuals on a real display) |
| G4 | Enemies and HQ defense | 4 archetypes, spawn rotation, AI, waves, HQ destruction, stage clear, game over | Optional |
| G5 | Progression and power-ups | Stars, the 6 power-ups, lives, respawn, scoring, difficulty curve | Optional |
| G6 | Local co-op | P2, independent bindings, friendly-fire stun, co-op lives and scoring, gamepads | **Yes (2 gamepads)** |
| G7 | Campaign and AV completion | 50 levels, 5 environments, final sprites and tilesets, SFX and music, balancing | Yes |
| G8 | Product experience | Menus, player select, settings, pause, high scores, persistence, transitions, VFX accessibility, controller navigation | Yes |
| G9 | Release preparation | Native acceptance on all 3 OSes, profiling, packaging, signing and notarization, optional Steamworks, license audit, trademark check, Steam AI disclosure, release checklist | Yes (all platforms) |

## G0 — exact implementation plan

**Branch:** `g0/foundation`, delivered as one Draft PR.

1. **Repository hygiene**
   - `.gitignore`: `.rocks/`, `build/`, `dist/`, `.serena/cache`, `*.love`, OS junk.
   - `.editorconfig`, `stylua.toml`, `.luacheckrc`.
   - `LICENSE` (PolyForm Noncommercial 1.0.0, code) and `NOTICE.md` (proprietary content, third-party notices) (Q-G0-3).
   - `assets/PROVENANCE.md` and `assets/manifest.lua` (initially empty).
2. **Bootstrap**
   - `conf.lua`: identity `eagle-defense`, version 11.5, a resizable 1280×720 window, highdpi, vsync, and the unused `physics` module disabled.
   - `main.lua` only `require`s `src/app`.
3. **Core** (pure Lua, unit-tested)
   - `core/loop`: fixed-step accumulator. It is driven by an injectable clock so it can be tested without LÖVE.
   - `core/rng`: xorshift32 with seed, serialize and restore.
   - `core/events`: an event queue.
   - `core/statemachine`: explicit `enter`/`exit`/`update`/`draw` and transition validation.
   - `core/serialize`: canonical Lua-literal writer plus a non-executing parser.
4. **Rendering foundation**
   - `render/viewport`: a 640×360 canvas with integer scale and letterbox computation (pure function, unit-tested), plus window resize and fullscreen toggle (Alt+Enter / F11).
   - `render/debug_overlay` (F3).
   - **No final art.** A clearly labelled `PLACEHOLDER` test pattern (grid + 13×13 field outline) is used to verify pixel-perfect scaling.
5. **Input abstraction**
   - `input/bindings`: data tables for P1 and P2 keyboard plus gamepad defaults.
   - `input/mapper`: raw device state → per-player actions → `InputFrame`, with last-pressed-wins direction resolution and stick-to-4-way conversion. Pure functions, unit-tested.
   - `input/devices`: the thin LÖVE adapter, including hot-plug.
6. **App states**
   - `boot` → `sandbox`. The sandbox is a debug scene: a placeholder square moved by P1/P2 input. It proves the input → fixed-tick → render path. **It is not gameplay.**
   - `--smoke=N` CLI flag: run N ticks, write a canvas PNG to the save directory, then quit with exit code 0.
7. **Tooling**
   - `Makefile` targets: `bootstrap`, `fmt`, `fmt-check`, `lint`, `test`, `smoke`, `love`, `check`, `evidence`.
   - `tools/bootstrap.sh`: luarocks into `.rocks/`, and StyLua with SHA-256 pinning.
   - `tools/check_boundaries.lua`: the sim/core purity scan.
   - `tools/check_assets.lua`: manifest coverage (it trivially passes at first).
   - `tools/build_love.sh`: the `.love` artifact plus SHA-256.
   - `tools/evidence.sh`: builds a tar.gz containing the SHA, diff, test/lint output, smoke screenshot, summary template and `SHA256SUMS`.
8. **Tests:** busted specs for loop (frame-rate independence: the same tick count for 30/60/144 Hz frame sequences), rng (known sequence plus round-trip), statemachine, serialize (including malicious input rejection), viewport math, input mapper and the boundary scan.
9. **CI:** deferred by the owner on 2026-11-26. The target is the company GitLab with self-hosted runners. `docs/CI.md` holds the pipeline contract (`make bootstrap && make check`). A GitHub Actions workflow was drafted and then removed.
10. **Docs:** README (run, test, controls), AGENTS.md, CLAUDE.md, this roadmap, `docs/CI.md`, `docs/acceptance/G0-macos.md`.

**G0 acceptance criteria**
- `make check` passes in the sandbox.
- ~~CI passes on the self-hosted runner~~. **CI is deferred** (owner, 2026-11-26). `make check` passing locally is the gate, and its output goes into the evidence package. The CI pipeline will be added on the company GitLab.
- `love .` opens a window showing the scaled test pattern; P1 (WASD/Space) and P2 (arrows) move the debug markers; Alt+Enter toggles fullscreen; F3 shows the overlay.
- The macOS checklist is executed by the owner.

**G0 decisions** (owner accepted the defaults on 2026-11-26)

| # | Topic | Decision |
|---|---|---|
| Q-G0-1 | Runner hosting: where, which labels, and should the macOS runner be the owner's Mac? | **CI deferred** (owner, 2026-11-26). For now we test locally with `make check`. CI will run on the company GitLab with self-hosted runners. |
| Q-G0-2 | Public repo + self-hosted runner: make it private, or restrict triggers? | No GitHub runner will be used, so the runner risk is gone. The repo **stays public** (owner, 2026-11-26) under the Q-G0-3 license. |
| Q-G0-3 | Source license | **PolyForm Noncommercial 1.0.0** for source code. Game content (`assets/`, `levels/`, name and logo) is proprietary, all rights reserved. The repo stays **public** (owner, 2026-11-26). See `NOTICE.md`. |
| Q-G0-4 | Move the static art spike into G1? | Yes |
