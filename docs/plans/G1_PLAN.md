# G1 — Core combat: implementation plan (PROPOSAL)

Status: **awaiting owner approval.** Planning only. No G1 code exists until the owner approves.
Base: G0 (`g0/foundation`). Branch: `g1/combat`, one Draft PR.

## 1. Scope

**In scope:**
- 4-way player tank movement with half-tile turn snapping
- shooting, projectile limits and the collision resolution order
- tank and projectile collisions
- an original test arena with target dummies
- deterministic golden replays
- a calibration pass
- static 24 px vs 32 px art mockups

**Out of scope (later milestones):**
- G2: brick, steel, water, forest, ice and destruction
- G4: enemy AI, spawning, HQ
- G5: lives, score, power-ups
- audio and final art

## 2. Contract change: simulation units independent of art resolution

This change needs owner approval, because it amends TECHNICAL_DESIGN §2.

Today the simulation units are art pixels × 16, which couples the gameplay goldens to the 24 px tile decision. G1 switches to abstract units:

| Quantity | Simulation units (u) |
|---|---|
| tile | **256 u** (= 16 classic px × 16 sub-units) |
| destruction cell (¼ tile) | 64 u |
| turn-snap grid (½ tile) | 128 u |
| playfield (13 tiles) | 3328 u |

- Positions, speeds (u/tick), timers (ticks) and the state hash are integers in **u only**.
- Rendering maps `px = floor(u × TILE_PX / 256)`: at 24 px that is ×3/32, at 32 px it is ÷8. That mapping lives only in `src/render` and `config/presentation.lua`.
- **Changing the art resolution never changes a golden.** A test proves it by running the same replay with presentation set to 24 px and to 32 px and requiring identical sim hashes.

## 3. Reference calibration

- All G1 constants move to `config/tuning.lua`. Each is tagged `UNV` (placeholder), `MEASURED` (with method) or `TUNED` (owner feel sign-off):
  - player speed
  - normal and fast bullet speed
  - bullet limit per upgrade level
  - snap grid
  - initial values: the placeholders from GAME_DESIGN §4, converted to u/tick
- **Measurement method**, by observation only and never from ROM data or disassembly:
  - Frame-step gameplay footage and count the frames a tank or bullet needs to cross N tiles.
  - Record each measurement in `docs/calibration/G1.md`: source description, frames, tiles and result.
  - The owner supplies the footage or measurements. I cannot watch video.
- **Feel tuning:** a debug overlay (F5) adjusts tuning values live and prints them. The owner plays and signs off. Final values are committed with the tag `TUNED (owner, date)`.
- GAME_DESIGN §4 is updated wherever a value moves from UNV.

## 4. Simulation (pure Lua, `src/sim/`)

**`world`:**
- arena solids at cell resolution (a generic indestructible block in G1)
- field bounds
- tanks: player P1, plus a P2 slot used only by tests
- target dummies
- bullets
- RNG
- events
- tick counter

**Movement:**
- Instant start and stop (decision Q3).
- One axis per tick.
- Perpendicular turn: snap the other axis to the nearest 128 u, then move. If the snapped position is blocked, the tank turns in place and does not move.
- Reversing never snaps.
- Movement is clamped to contact with solids, bounds and other tanks. Tanks never overlap.

**Shooting:**
- On `fire_pressed`, spawn a bullet at the muzzle (center of the front edge) if the tank's active bullets are below its limit: 1 at upgrade levels 0–1, 2 from level 2.
- A bullet spawned inside a solid hits it immediately.

**Tick order** (documented as an invariant and tested):
1. input → tank movement (entity order: P1, P2, dummies)
2. spawn new bullets
3. advance bullets in sub-steps of ≤ 64 u. Each sub-step resolves:
   1. bullet vs bullet: opposing factions cancel, using swept overlap so head-on bullets cannot pass through each other; same-faction bullets pass through
   2. bullet vs tank
   3. bullet vs solid and bounds
4. remove dead entities
5. emit events (`shot`, `bullet_hit_solid`, `bullet_cancel`, `tank_hit`)

Ties are broken by entity order.

**In the G1 arena only:** a hit dummy is destroyed. A hit player respawns at its spawn point. Lives come in G5.

## 5. Test arena (original)

- A data file `config/arenas/g1_arena.lua` holds a 13×13 original layout of indestructible blocks with corridors, a 1-tile lane, intersections and open space.
- Target dummies: 2 static dummies, and 1 turret that fires on a fixed tick schedule along a lane, to exercise bullet cancellation.
- It is drawn with flat-color shapes marked PLACEHOLDER.
- The app state `arena` is reached from boot. `--arena` and `--smoke` run it headless.

## 6. Tests (they must prove the combat works)

**Scenario tests** drive `sim.step` with InputFrames and assert observable outcomes:
- exact positions after N ticks
- reaching and stopping at walls and other tanks
- turn snapping at an intersection, and entering the 1-tile lane
- blocked snap
- reversing
- last-pressed direction through a full turn sequence
- one press fires one bullet; holding fire does nothing more (decision Q4)
- bullet limits per level
- muzzle spawn inside a wall
- bullet vs wall, bounds and dummy
- head-on cancellation at every relative phase, so nothing tunnels
- same-faction pass-through
- collision ordering when a bullet would hit a bullet and a tank in the same sub-step

**Golden replays:**
- Format: `tests/fixtures/replays/*.lua` in the serialize format, holding seed, arena, run-length-encoded InputFrames and `checkpoints = { [tick] = hash }`.
- 3–4 replays: a movement tour, a shooting gallery, a cancellation duel, a stress run.
- Goldens are regenerated only with `tools/update_goldens.lua`, and the PR must call it out.
- Determinism is checked across 2 independent LuaJIT processes and across the 24 px / 32 px presentation settings (§2).

**Purity and smoke:**
- The boundary checker now covers real `src/sim` code.
- Smoke runs the arena with scripted input, asserting the sim hash plus the existing pixel-perfect check.

## 7. Static art mockups: 24 px vs 32 px tiles

- One static scene, rendered twice:
  - classic environment with brick, steel, water, forest and ice
  - an original HQ emblem
  - P1 and P2
  - 3 enemy silhouettes
  - 2 bullets
  - one explosion frame
- Built with Pipeline A (ART_DIRECTION §7): palette-indexed source sprites in the repo, `tools/build_sprites.lua` → PNG, composed by LÖVE in a `--mockup` mode.
- Output at 1× and 3× into `docs/art/mockups/`. These are **concept art, not shipped**, and their provenance is recorded.
- This is an art spike only. It does not change gameplay, and the result does not affect goldens (§2).

## 8. Owner acceptance criteria

**Game feel** (native, on the owner's Mac, keyboard and pad):
1. Start and stop feel instant, with no perceived input lag.
2. Turning into a 1-tile lane at an intersection works on the first try, with no fighting the snap.
3. Movement and bullet speeds feel "classic". The owner signs off the tuned values.
4. One press = one shot. The bullet limit is noticeable. Fast bullets are clearly faster.
5. Bullet cancellation against the turret is visible and reliable.
6. Motion is smooth at 60 Hz, with no hitching. 120 Hz ProMotion is acceptable.

**Visual direction:**

7. The owner picks 24 px or 32 px tiles from the mockups and records style feedback. On approval, ART_DIRECTION §3 is updated. A "revise" outcome is allowed.

**Automated:**

8. `make check` is green, with all of §6 passing. Final evidence comes from a clean HEAD.

## 9. Work order

1. Units contract + `config/tuning.lua`
2. Movement + tests
3. Bullets and collision order + tests
4. Arena + dummies
5. Replays + goldens
6. Placeholder render + arena state + smoke
7. Tuning overlay + calibration doc
8. Mockups
9. Docs + evidence + Draft PR

Models: Opus throughout. Shaders are not needed in G1, so Fable 5.2 is not used yet.

## 10. Owner decisions needed

| # | Decision | Proposal |
|---|---|---|
| G1-D1 | Approve the simulation-units contract change (§2, tile = 256 u) | Approve |
| G1-D2 | Arena-only rule: a hit player respawns instantly | Approve (lives come in G5) |
| G1-D3 | Calibration source: will you provide frame-stepped measurements from footage, or feel tuning only? | Both if possible; feel tuning at minimum |
| G1-D4 | Mockups stored as concept art under `docs/art/mockups/`, not shipped | Approve |
