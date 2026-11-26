# Eagle Defense — Technical Design v1.0

Status: **APPROVED v1.0** (owner, 2026-11-26). Contract changes require owner approval.

## 1. Platform and pinned versions

| Component | Version | Notes |
|---|---|---|
| LÖVE | **11.5** (2023-12-03) | This is the latest stable release. No 11.6 release or tag exists (checked against the GitHub API on 2026-11-26), and 12.0 is still unreleased development. The official macOS build is a universal binary (x86_64 + arm64), which was verified. |
| Lua runtime | LuaJIT 2.1 (bundled with LÖVE) | Code must stay compatible with Lua 5.1 + LuaJIT: no `goto`, no 5.2+ APIs. `bit` is allowed. |
| Test runner | busted 2.3.0, run with `--lua=luajit` | Installed into a project-local `.rocks/` tree (gitignored) |
| Linter | luacheck 1.2.0 | `std = luajit + love` |
| Formatter | StyLua 2.6.0 | Release binary, pinned by SHA-256 |
| Shell lint | shellcheck (system package) | Run as part of `make lint` when installed |

12.0 migration policy: avoid APIs that are deprecated in 12. Any migration requires an approved technical decision.

## 2. Resolution, units and scaling

**Hypothesis, to be confirmed by the G3 visual prototype:**

- Internal canvas is **640×360** (16:9). It scales by an exact integer to 1280×720 (2×), 1920×1080 (3×), 2560×1440 (4×) and 3840×2160 (6×). Steam Deck (1280×800) gets 2× with bars.
- **Tile = 24 art px.** The playfield is 13×13 tiles = **312×312 px**. The remaining ~328 px of width hold side panels for the HUD: P1 left, P2 right, enemy reserve and stage info.
- Destruction **cell = ¼ tile = 6 px**, so the field is 52×52 cells. Turn snapping uses the half-tile grid (12 px).
- **Simulation units:** integer *subpixels*, with 1 art px = 16 subpixels. All positions and velocities are integers (exact in doubles), and speeds are given as subpixels/tick. This gives determinism without fixed-point libraries.
- Scaling modes:
  - **Integer** (default): the largest integer scale that fits, letterboxed.
  - **Fit** (optional): integer pre-scale followed by a single linear upscale ("sharp bilinear").
- The alternative candidate is 32 px tiles on a 768×432 canvas, which has more sprite detail but non-integer scaling at 1080p. Both will be compared in the G3 prototype.

## 3. Main loop

There is a custom `love.run`:

- Fixed step `DT = 1/60`. An accumulator collects frame time.
- The frame delta is clamped to 0.25 s, with at most 5 sim ticks per rendered frame. This prevents a spiral of death.
- Input is sampled **once per tick** into an immutable `InputFrame`.
- The renderer draws the latest sim state **without interpolation**, which is the arcade-authentic choice. Interpolation can be revisited in G3 for 120/144 Hz displays as a presentation-only option.
- VSync is on by default. A debug overlay (F3) shows FPS, tick count, frame time, sim time and draw calls.

## 4. Module layout and dependency rules

```text
main.lua, conf.lua          bootstrap only
src/core/                   loop, rng, events, state machine, util, serialize. Pure Lua.
src/sim/                    authoritative gameplay: world, tiles, tanks, bullets, AI, rules. Pure Lua.
src/input/                  devices → actions → InputFrame (uses love.keyboard / love.joystick)
src/render/                 canvases, sprites, tilemap drawing, VFX particles, shaders, scaling
src/audio/                  event → sound mapping, source pooling, music
src/ui/                     menus, HUD, fonts
src/app/                    game states (boot, title, play, pause, ...) and wiring
config/                     data tables: tank stats, power-ups, timings, bindings
levels/                     declarative level files
tools/                      validators, packaging, asset generators
tests/                      busted specs, fixtures, replays
```

The master prompt suggests `gameplay/`, `entities/` and `world/`. We merge them into **`sim/`**, because a three-way split adds indirection without benefit at this size. Its boundary is the important part:

| Module | May require | Must not require |
|---|---|---|
| `core`, `sim` | `core`, `sim`, `config` | `love.*`, `render`, `audio`, `input`, `ui`, `app` |
| `input` | `core`, `love` | `sim` internals |
| `render`, `audio` | `core`, read-only `sim` state, `love` | sim mutators |
| `app` | everything | — |

This boundary is **enforced by a test** that statically scans `src/core` and `src/sim` for `love` references and forbidden `require` calls.

## 5. Simulation model

- `world` is a plain table: `tick`, `rng`, `cells` (a flat array of 52×52 terrain codes), `tanks`, `bullets`, `powerup`, `hq`, `players`, `stage`. Entity lists are **arrays iterated in order**; `pairs()` is never used in gameplay order.
- `sim.step(world, input_frame)` is the only mutator. The resolution order per tick is fixed and documented: input → AI decisions → tank movement → bullet movement and collisions → bullet vs bullet → pickups → timers → spawns → win/loss checks.
- **RNG:** a project-owned xorshift32 built on LuaJIT `bit`. It is seedable and serializable. `math.random`, `love.math.random` and `os.time` are banned in `sim`.
- **Events:** `step` appends to `world.events`, which presentation drains each frame. Events are data only, such as `{type="hit_brick", x=, y=}`.
- **State hash:** `sim.hash(world)` folds all authoritative fields into a 32-bit checksum. It is used by golden replays and desync checks.

## 6. Collision

- Terrain is an integer cell grid (6 px cells). A tank AABB is tested against the cells it would overlap after the move. A blocked move is rejected per axis (tanks only move along one axis per tick anyway).
- Bullets advance in sub-steps of ≤ 1 cell per sub-step, so they cannot tunnel.
- Tank-vs-tank and bullet-vs-tank use integer AABB tests. Ties are resolved by entity order (P1, P2, enemies in spawn order).
- Destruction removes cells according to data-defined patterns (see GAME_DESIGN §4.3).

## 7. Input

- Actions are `up`, `down`, `left`, `right`, `fire` and `pause`, per player.
- Sources: keyboard and gamepads through the `love.joystick` gamepad API, with an SDL controller DB bundled at a pinned version. Stick input is converted to 4 directions with a dead zone and hysteresis.
- Direction policy: **last pressed wins**, implemented with a per-player press-order stack.
- Rebinding is stored in the save data (G8). Hot-plugging is supported. The default assignment is first pad → P1, second → P2.
- `InputFrame`s are recorded to replay files (`seed`, `level`, `frames`) for tests and bug reports.

## 8. Rendering and shader architecture

Shader implementation work is assigned to the **Fable 5.2** model, per owner instruction.

```text
world canvas 640x360 (nearest)
  ├─ tile layer → tank / bullet / pickup layer → forest layer (above tanks) → particles
  ├─ light canvas 160x90  : additive light sprites (muzzle, explosions, HQ) → multiplied onto world
  ├─ bloom (opt.)        : threshold → 2 downsample blur passes at ¼/⅛ res → additive, capped
  └─ HUD canvas 640x360  : drawn after post-FX so effects never obscure UI
→ integer upscale to screen (nearest) → optional CRT shader at screen res (scanlines, mask, mild curvature)
```

- GLSL that is compatible with LÖVE 11.5, uses the `effect()` entry point and works on GL 2.1 and GLES. Each effect can be toggled, and the whole post stack falls back to a plain blit if shader compilation fails.
- Particles use a fixed-size, preallocated pool, so nothing is allocated per frame. Particles take their own seeded RNG and have no gameplay authority.
- Sprites are packed into a few atlases with SpriteBatch for tiles. The draw-call budget is under 100 per frame.

## 9. Data formats

**Levels:** `levels/NN.lua` contains a data-only table literal (`return { ... }`). It is read with `core/serialize.decode`, a **non-executing parser** for a strict Lua-literal subset: tables, strings, finite numbers, booleans and `--` line comments. The data is never compiled or run. There is no `loadstring`/`load`/`dofile`/`require` of level or save data. Input size and nesting depth are limited, and bytecode, block comments, expressions, function calls, duplicate keys and nil values inside tables are all rejected. Being `.lua` files is only for editor syntax highlighting.

```lua
return {
  id = 1, env = "classic", name = "Opening Gate",
  roster = { basic = 14, fast = 4, power = 2, armor = 0 },  -- sum = 20
  map = {   -- 26 rows × 26 cols: one char = ½ tile (2×2 cells)
    "..........................",
    -- B brick  S steel  W water  F forest  I ice  . empty  E enemy spawn  1/2 player spawn  H HQ
  },
}
```

The half-tile character grid is human-readable and diffable. Partial-brick authoring granularity (½ tile) matches the classic design practice.

**Config:** `config/*.lua` tables, validated at load.

**Saves:** written by `core/serialize.encode` and read by the same non-executing `decode`. Encoding is canonical (sorted keys; the array part is the contiguous prefix `1..n`, never `#t`), so equal data always yields identical bytes. Each save has a version, a schema check and a checksum. Writes go to two alternating slots (A/B) with a sequence number, because LÖVE 11 has no atomic rename. The loader picks the newest valid slot, and if both slots are corrupt it falls back to defaults and backs up the corrupt file.

## 10. Testing

| Layer | Tool | Runs where |
|---|---|---|
| Unit (core, sim, serialize, input mapping) | busted + LuaJIT, no LÖVE | local `make check` (+ CI when enabled) |
| Scenario / golden replays | busted: load level + replay → assert state hash at checkpoints | local `make check` (+ CI when enabled) |
| Level and save validation | `tools/validate_levels.lua`, spec tests | local `make check` (+ CI when enabled) |
| Architecture boundary | spec that scans `src/sim` and `src/core` | local `make check` (+ CI when enabled) |
| Headless smoke | `tools/smoke.sh`: `love . --smoke=N --window=WxH` under Xvfb (Linux) or in a real window (macOS). It runs N ticks of scripted input, captures the canvas and the backbuffer, verifies the integer upscale pixel by pixel in **physical** pixels, and reports logical size, physical size and DPI | sandbox (verified feasible: Mesa llvmpipe GL 4.5) + Linux CI when enabled |
| Native macOS | owner, or a macOS GitLab runner later | see §13 |

Golden fixtures are regenerated only by an explicit `tools/update_goldens.lua`, and every regeneration is called out in the PR.

## 11. Tooling and CI

- `make bootstrap` installs the rocks into `.rocks/` and downloads the pinned StyLua.
- `make check` runs `fmt-check`, `lint`, `test`, `validate` and `smoke` (smoke only when `love` and `xvfb-run` exist).
- **Current gate: `make check` run locally.** CI is deferred by owner decision (2026-11-26).
- **Target CI: the company GitLab with self-hosted runners.** The project will move from GitHub. The Makefile is the CI contract, so the pipeline only runs `make bootstrap && make check && make love` (see `docs/CI.md`).

## 12. Packaging (G0: `.love` only; full in G9)

- `.love` is a zip of `main.lua`, `conf.lua`, `src/`, `config/`, `levels/` and `assets/`.
- Windows: fused `love.exe` + `.love` from the pinned 11.5 win64 zip, with checksums verified.
- macOS: an `.app` built from the pinned 11.5 universal bundle (Info.plist identity, icon). Distribution requires **Developer ID signing + notarization** (Apple Developer Program), which is a G9 dependency.
- Linux: Steam runtime + `love` binary, x86_64 only. LÖVE has no official Linux arm64 build; arm64 is used only for development.

## 13. Native macOS acceptance

1. The owner runs `love .` with LÖVE 11.5 installed, or a `.love` from `make love`. Once GitLab CI exists, it can also build an unsigned `.app` artifact.
2. The owner follows `docs/acceptance/<milestone>-macos.md`, a checklist covering launch, window/fullscreen toggle, scaling at native Retina resolution, input feel, gamepad, audio, a 10-minute stability run and the F3 overlay FPS.
3. Evidence is recorded in that file: Mac model, chip, macOS version, LÖVE version, commit SHA, screenshots and pass/fail per item.
4. Sandbox evidence (Linux arm64, Xvfb, software GL) is always labelled **"automated sandbox evidence"** and never presented as native validation.

## 14. Technical risks

| Risk | Impact | Mitigation |
|---|---|---|
| CI deferred until the move to company GitLab | Regressions slip through if `make check` is skipped | `make check` output is mandatory in every evidence package. Set up the GitLab pipeline before G9 at the latest. |
| Public repo (owner decision) | Clones or rebuilds of the code appear | Code is PolyForm Noncommercial, so commercial use is forbidden. Assets and levels are proprietary, so a rebuild without them is not the game. Monitor for infringements before and after launch. |
| Reference behavior largely unverified | Feel deviates from the classic | Data-driven constants, calibration pass in G1/G4, values marked UNV |
| Original art quality from an AI-driven pipeline | The "commercial quality" bar may not be met | Early G3 slice and an owner decision on commissioning an artist (see ART_DIRECTION §7) |
| LÖVE 11.5 is aging (2023), and 12.0 is unreleased | Future OS/SDL issues, especially on macOS | Pin 11.5, keep API usage conservative, re-evaluate 12.0 at G9 |
| macOS signing and notarization | Gatekeeper blocks the release | Apple Developer account before G9 |
| Steamworks from Lua needs a native module | Packaging complexity | Steam integration is optional. Decide in G9; a release without Steamworks is valid. |
| Software-GL sandbox ≠ real GPU | Shader bugs missed | Native acceptance per milestone with shaders; GL 2.1-safe GLSL |
| Determinism across platforms | Replay/golden mismatches | Integer-only sim math, own RNG, ordered iteration, hash checks in `make check` |
| Trademark/name not cleared | Rebrand late | Pre-release trademark search task (G9 checklist) |
