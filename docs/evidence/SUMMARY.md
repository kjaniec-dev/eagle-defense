# G2 — battlefield, terrain and destruction: evidence summary

Branch `g2/battlefield`, from `main` `6e03a2f` (G1 merged), delivered as Draft PR #4. Plan: `docs/plans/G2_PLAN.md` v1.1, approved by the owner on 2026-11-28 with decisions G2-D1 … G2-D7 and clarifications C1–C6 (§19). Earlier summaries: `docs/evidence/G0.md`, `docs/evidence/PR2.md`, `docs/evidence/G1.md`.

| Item | Evidence class | Status |
|---|---|---|
| Terrain, destruction, ice, level loader and validator, replay identity, scenario tests, goldens | sandbox (Linux arm64, LuaJIT) | **PASS** (see below) |
| G1 goldens: checkpoints byte-identical to `c82ff86`; G1 smoke `581f15d4` | sandbox | **PASS** |
| Real app, both arenas, pixel-perfect smoke at 4 sizes, same sim hash as the pure simulation | sandbox (Xvfb, Mesa llvmpipe) | **PASS** 8/8 |
| HiDPI harness + mutation proof | SIMULATED HiDPI | **PASS** 8/8, 4/4 detected |
| G2 mutation check | sandbox | **PASS** 29/29 detected (`docs/evidence/G2-mutations.md`) |
| Native `make check`, smoke at 800x600 / 1024x640 / 1280x720, manual feel (brick, ice tuning) | **native** (owner) | **NOT RUN** (checklist: `docs/acceptance/G2-macos.md`) |
| Independent review | independent review | **PENDING** |

## Contract amendments (recorded before any code, `5b85b8d`)
- TECHNICAL_DESIGN §5: destruction in the spawn phase and in step (d), each resolved as a batch against the batch-start terrain; ice in the movement phase; the hash extension rule; the world `player_level`.
- TECHNICAL_DESIGN §6: the terrain property table, the strip, depth and steel rules, the ice rule, forest. §7: `arena_id`, `player_level`. §9: the level format, profiles and injected reader. §10: the G2 test layers.
- GAME_DESIGN §4.1 (ice, UNV), §4.3 (brick, steel, water, forest, the `X` block), §8 (events), §10 (invariant 3 refined, new invariant 9), §11 (F7) and the new §12 terrain arena.
- G2_PLAN §19 records clarifications C1–C6.

## Simulation (`src/sim/`)
- **Terrain** (`terrain.lua`, G2-D1): codes 0 empty, 1 block (`X`, the G1 code), 2 brick, 3 steel, 4 water, 5 forest, 6 ice. The sim reads only the properties. Tank collision (movement, the collision-checked snap, invariants, spawn validation) tests `blocks_tanks`, and bullets test `blocks_bullets`.
- **Destruction** (`destruction.lua`, G2-D2, G2-D3):
  - the impact line is the one nearest the shooter;
  - the strip is 2 cells centered on the nearest cell boundary, with ties going to the lower coordinate;
  - depth stops at block, and at steel for non-power bullets;
  - power bullets (level ≥ `steel_break_level`) remove aligned 2 × 2 steel blocks;
  - block is never destroyed; a bound hit destroys nothing.
- **Batches (C1).** The spawn phase and every (d) step are each one batch, resolved against the batch-start terrain. The union of the removals is applied. Each destroyed cell is reported once, for the first impact (tank order, or bullet order). Events: `bullet_hit_solid` gains `terrain`, plus a new `terrain_destroyed`.
- **Ice** (in `move.lua`, G2-D4, C6): the slide rule as specified. `ice_dir` is armed only by an input move with forward displacement > 0 that ends on ice. A 0 u slide step (contact) ends the slide and uses that tick. A hit or respawn clears all ice state.
- **World and hash:**
  - `player_level` is the initial and respawn level. It is not hashed itself (C2).
  - The new tank and bullet fields are hashed only when they are not at their defaults.
  - `terrain_violations` implements invariant 9.
- **Levels** (`level.lua`, G2-D6):
  - a non-executing loader with a 32 KiB limit;
  - the campaign and arena profiles;
  - row-major 2 × 2 marker blocks;
  - 4-neighbour reachability;
  - `load_arena`: config arenas use the G1 loader; the others go through an injected reader.
  - `tools/validate_levels.lua` is part of `make validate`.
- **Replays** (G2-D7, C3):
  - optional `arena_id` and `player_level` header fields;
  - the runner refuses a mismatching `arena_id` in either format, and a level-format replay without one;
  - legacy G1 headers stay valid;
  - invariant 9 is asserted on every tick;
  - `tools/update_goldens.lua` never writes `arena_id`.
- **Terrain arena** (`levels/arenas/g2_terrain.lua`): original, arena profile, the zones of GAME_DESIGN §12. During authoring the `X` block was moved to rows 6–7, columns 18–19, so it is out of the line of fire at the ½-tile wall.

## G1 guarantees (C5)
- **Golden regeneration (called out):** the four G1 goldens were regenerated with `tools/update_goldens.lua` for the tuning-id change only (`348b3a6c` → `1008b573`, from the four new tuning keys).
  - The fixture diff is exactly one `tuning_id` line per file.
  - Every checkpoint is byte-identical. `tests/sim/replay_spec.lua` compares the stored and the recomputed checkpoints with the `c82ff86` values frozen in `tests/sim/g1_frozen_checkpoints.lua`.
  - The G1 headers keep no `arena_id` and no `player_level`.
- The G1 smoke expectation is unchanged: `p1=1408,2688 p2=1664,2652 hash=581f15d4`, run with `--arena=g1_arena` explicitly.
- Approved tuning is unchanged: 7 / 17 / 34, tagged `TUNED (owner, 2026-11-27)`.
- **Scope of the claim:** it covers the approved goldens, the G1 smoke, and any state without the new fields. It does not cover every G1-reachable state. A player at level ≥ 3 now fires power bullets, which are hashed.

## New goldens (inputs from `tools/gen_g2_replay_inputs.lua`, checkpoints from `tools/update_goldens.lua`)
The generator is goal-driven, the G2 form of G1's distance-based authoring. It drives a live simulation to asserted waypoints at the committed tuning. Every fixture records the terrain arena's `arena_id` (`8b30c45c`).

| Golden | Ticks | Observed | Named-behavior check (`tests/sim/terrain_replay_spec.lua`) |
|---|---|---|---|
| `terrain_tour` | 1375 | slides ending by distance, at steel and water contact, and at the ice edge; no player shots; the turret digs 8 brick cells | ≥ 2 slides ending at contact, ≥ 1 at the ice edge, ≥ 2 by distance; forest crossed; contact with water, brick and steel; no tank hit |
| `brick_demolition` (level 0) | 2277 | 43 shots, 62 brick cells in 32 `terrain_destroyed`, 7 muzzle impacts, target hit | ≥ 20 events; a same-tick P1 + P2 point-blank pair at one 1-cell wall; a tank inside cells that were brick; every brick event ≤ 2 cells |
| `steel_and_power` (level 3) | 953 | 32 steel and 32 brick cells; the X block is shot 3 times | ≥ 16 steel cells; block count constant (16) on every tick; every brick event ≤ 2 cells |
| `terrain_stress` (level 3, turret) | 3600 | 357 shots, 110 brick + 56 steel cells, 23 hostile + 19 friendly hits | ≥ 200 shots, ≥ 50 cells; invariants on every tick |

All 8 goldens are also replayed in a second LuaJIT process and with 24 px and 32 px presentation, and they are refused under a different tuning or arena id.

## Tests (`make test`: 409 successes, 0 failures)
- `terrain_spec`: the code and property table, `box_hits`, the tuning additions (tags, `one_of`, ranges), the hash extension rule per field, invariant 9 and its runner.
- `destruction_spec`:
  - the exact removed cells in 4 directions;
  - the tie case, and the nearest boundary versus the bullet's cell, using real blocked-snap shots;
  - depth 2, width 4, clipping, a 2-cell hole;
  - muzzle impacts, including a spawn box spanning two lines;
  - simultaneous impacts in (d), from opposite sides and perpendicular, in both orders, with overlapping strips and the attribution;
  - point-blank shots from both sides in the spawn phase; the next sub-step seeing the updated cells;
  - tank + brick in one sub-step, cancellation over brick, destruction affecting movement from the next tick;
  - steel at levels 0–2 and 3, one block or two, `steel_break_level`, block with power, brick behind steel at depth 2, mixed steel + brick precedence;
  - no tunnelling through 1-cell brick and steel at 13 speeds (17 … 512 u/tick) × 64 offsets × 4 directions.
- `terrain_movement_spec`: every tank-blocking type stops a tank at contact; forest and ice do not block; a snap into water turns the tank in place; bullets pass water, forest and ice; forest neutrality (identical positions and events with forest replaced by empty).
- `ice_spec`:
  - the distance, and movement on the trigger tick; no re-trigger;
  - the contact (steel, water), off-ice and same-direction end conditions;
  - perpendicular and reverse triggers with facing, then normal movement on the next tick;
  - a shot during a slide; hit and respawn; distance 0; a single ice cell; the C6 snap-only regression.
- `level_spec`: 4 valid fixtures and 30 invalid ones (one per rule); non-execution and size limits; character mapping; marker parsing; the battlefield shape; reachability; arena resolution; the validator tree check and the file-name checks.
- `terrain_replay_spec`: the named behaviors above; arena identity (legacy accepted, mismatch and missing refused, a changed arena file refused, regeneration refuses both).
- `arena_spec`, `args_spec`: both smoke pins against the pure sim; the default arena; F6, F7, F2 and F5 interplay (C2); the respawn level; F8 at level 3 in the terrain arena (two saves plus a file round trip); G1-arena recordings with `arena_id`.
- `layout_spec`: the layer order, the forest split, exact 6 px and 8 px cells, the painter order through a stubbed `love.graphics`, forest drawn over a tank.

## App
- `love .` opens the terrain arena. `--arena=g1_arena|g2_terrain` selects one, and F6 switches.
- F7 cycles the players' level 0–3 and restarts. It is recorded as `player_level` and is never debug tuning.
- F5 no longer offers `arena_player_level`. It gains `ice_slide_distance` (step 8) and `brick_strip_cells` / `brick_strip_depth` (allowed values).
- F2 keeps the arena, the level and the F5 copy. F8 recordings carry `arena`, `arena_id` and `player_level`.
- PLACEHOLDER terrain rendering at cell resolution, with the forest layer above tanks and bullets. No new assets.
- The SMOKE line gains `arena=<name>`. `tools/smoke.sh` runs both arenas at every size, each with its expectation (C4); `tools/hidpi_sim.sh` passes `--arena=g1_arena`.

## Sandbox runs (`make check` at the final HEAD; see the evidence package)
- Formatting and lint: PASS, 0 warnings / 0 errors. Shellcheck: OK.
- Validate: boundaries, assets, DPI and levels: OK.
- Smoke (Linux, Xvfb, llvmpipe): 8 × `SMOKE OK … problems=none`, both arenas at 1280x720, 1920x1080, 1366x768 and 800x600. The terrain smoke gives `p1=512,2688 p2=2304,3072 hash=4b7aaef1`: P1 slides on ice into the water column, and P2 digs its wall point-blank.
- hidpi-sim (SIMULATED): 8/8 PASS, and `--mutations`: 4/4 detected.
- Shell portability (sandbox emulation, **not native**): `tools/smoke.sh` and `tools/hidpi_sim.sh` also pass under an emulated macOS userland, as in PR #2: bash 3.2.57, Apple `od`, and `LANG=LC_ALL=pl_PL.UTF-8`. Smoke ran both arenas at the three macOS sizes (6 × `SMOKE OK`, the same hashes), and hidpi-sim was 8/8.

## Not verified here
- Nothing native has been run. Native rendering, smoke at the macOS sizes, feel (brick strip, ice distance), smoothness while destroying terrain, and F8 saves on the Mac are all for the owner (`docs/acceptance/G2-macos.md`).
- `brick_strip_cells`, `brick_strip_depth` and `ice_slide_distance` stay **UNV** until the owner signs them off natively.
- The "impact line nearest the shooter" rule only matters for a box spanning two lines with blocking cells in both. That can happen neither in flight nor at the muzzle: the muzzle's trailing line is inside the shooter's own cells, which never block tanks. It is therefore tested on the pure function, and through the muzzle case where only the far line holds brick.
