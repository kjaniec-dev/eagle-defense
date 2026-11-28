# G2 — battlefield, terrain and destruction: evidence summary

Branch `g2/battlefield`, from `main` `6e03a2f` (G1 merged), delivered as Draft PR #4. Plan: `docs/plans/G2_PLAN.md` v1.1, approved by the owner on 2026-11-28 with decisions G2-D1 … G2-D7 and clarifications C1–C6 (§19). Earlier summaries: `docs/evidence/G0.md`, `docs/evidence/PR2.md`, `docs/evidence/G1.md`.

| Item | Evidence class | Status |
|---|---|---|
| Terrain, destruction, ice, level loader and validator, replay identity, scenario tests, goldens | sandbox (Linux arm64, LuaJIT) | **PASS** (see below) |
| G1 goldens: checkpoints byte-identical to `c82ff86`; G1 smoke `581f15d4` | sandbox | **PASS** |
| Real app, both arenas, pixel-perfect smoke at 4 sizes, same sim hash as the pure simulation | sandbox (Xvfb, Mesa llvmpipe) | **PASS** 8/8 |
| HiDPI harness + mutation proof | SIMULATED HiDPI | **PASS** 8/8, 4/4 detected |
| Owner brick tuning 4 × 2 with the fixed 2-cell steel strip (`eeac1f5`) | sandbox | **PASS** (see below) |
| G2 mutation check | sandbox | **PASS** 40/40 detected at `eeac1f5` (`docs/evidence/G2-mutations.md`) |
| Brick feel | **native** (owner playtest) | **SIGNED OFF** by the owner: 4 × 2, `TUNED (owner, 2026-11-28)` |
| Native `make check`, smoke at 800x600 / 1024x640 / 1280x720, manual checklist (incl. ice tuning) on the committed build | **native** (owner) | **NOT RUN** (checklist: `docs/acceptance/G2-macos.md`) |
| Internal pre-review (independent Opus reviewer, read-only) | review | **PASS**, no blockers; 2 should-fix + 1 nit fixed (see below) |
| Independent review of `fc0fedf` | independent review | Architecture, batching, ice, replay identity and G1 compatibility **accepted**; two P2 findings **fixed** in `b30e173` (see below). Final review **PENDING** |

## Contract amendments (recorded before any code, `5b85b8d`)
- TECHNICAL_DESIGN §5: destruction in the spawn phase and in step (d), each resolved as a batch against the batch-start terrain; ice in the movement phase; the hash extension rule; the world `player_level`.
- TECHNICAL_DESIGN §6: the terrain property table, the strip, depth and steel rules, the ice rule, forest. §7: `arena_id`, `player_level`. §9: the level format, profiles and injected reader. §10: the G2 test layers.
- GAME_DESIGN §4.1 (ice, UNV), §4.3 (brick, steel, water, forest, the `X` block), §8 (events), §10 (invariant 3 refined, new invariant 9), §11 (F7) and the new §12 terrain arena.
- G2_PLAN §19 records clarifications C1–C6.

## Simulation (`src/sim/`)
- **Terrain** (`terrain.lua`, G2-D1): codes 0 empty, 1 block (`X`, the G1 code), 2 brick, 3 steel, 4 water, 5 forest, 6 ice. The sim reads only the properties. Tank collision (movement, the collision-checked snap, invariants, spawn validation) tests `blocks_tanks`, and bullets test `blocks_bullets`.
- **Destruction** (`destruction.lua`, G2-D2, G2-D3):
  - the impact line is the one nearest the shooter;
  - the brick strip is `brick_strip_cells` × `brick_strip_depth` = **4 × 2** (owner tuning, 2026-11-28), centered on the nearest cell boundary, with ties going to the lower coordinate;
  - depth stops at the first bullet-blocking cell the impact does not remove: block, and steel that is not being removed;
  - power bullets (level ≥ `steel_break_level`) remove the aligned 2 × 2 steel blocks touched by a fixed **2-cell steel strip**, independent of the brick strip;
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
- **Second regeneration (called out), owner brick tuning:** tuning id `1008b573` → `949c2b01`. Again only the `tuning_id` line changed in each G1 golden; frames and every checkpoint are unchanged (checked against the previous files and the frozen `c82ff86` values).
- Approved movement and bullet tuning is unchanged: 7 / 17 / 34, tagged `TUNED (owner, 2026-11-27)`.
- **Scope of the claim:** it covers the approved goldens, the G1 smoke, and any state without the new fields. It does not cover every G1-reachable state. A player at level ≥ 3 now fires power bullets, which are hashed.

## New goldens (inputs from `tools/gen_g2_replay_inputs.lua`, checkpoints from `tools/update_goldens.lua`)
The generator is goal-driven, the G2 form of G1's distance-based authoring. It drives a live simulation to asserted waypoints at the committed tuning. Every fixture records the terrain arena's `arena_id` (`8b30c45c`).

| Golden | Ticks | Observed | Named-behavior check (`tests/sim/terrain_replay_spec.lua`) |
|---|---|---|---|
| `terrain_tour` | 1375 | slides ending by distance, at steel and water contact, and at the ice edge; no player shots; the turret digs 16 brick cells | ≥ 2 slides ending at contact, ≥ 1 at the ice edge, ≥ 2 by distance; forest crossed; contact with water, brick and steel; no tank hit |
| `brick_demolition` (level 0) | 3090 | 50 shots, 140 brick cells in 24 `terrain_destroyed`, 7 muzzle impacts, the target hit | ≥ 20 events; a same-tick P1 + P2 point-blank pair at one 2-cell wall; a tank inside cells that were brick; every brick event ≤ 8 cells, the first > 2 |
| `steel_and_power` (level 3) | 1111 | 32 steel and 64 brick cells; the X block is hit 5 times | ≥ 16 steel cells; every steel event 4 or 8 cells and at most 1 tile wide; block count constant (16) on every tick; every brick event ≤ 8 cells |
| `terrain_stress` (level 3, turret) | 3600 | 349 shots, 168 brick + 56 steel cells, 24 hostile + 23 friendly hits | ≥ 200 shots, ≥ 50 cells; invariants on every tick |

All 8 goldens are also replayed in a second LuaJIT process and with 24 px and 32 px presentation, and they are refused under a different tuning or arena id.

## Tests (`make test`: 430 successes, 0 failures)
- `terrain_spec`: the code and property table, `box_hits`, the tuning additions (tags, `one_of`, ranges), the hash extension rule per field, invariant 9 and its runner.
- `destruction_spec`:
  - the rule tests pin the minimal 2 × 1 strip (still an F5 value) so that every cell is visible; the approved 4 × 2 default has its own scenarios (below);
  - the exact removed cells in 4 directions;
  - the tie case, and the nearest boundary versus the bullet's cell, using real blocked-snap shots;
  - depth 2, width 4, clipping, a 2-cell hole;
  - muzzle impacts, including a spawn box spanning two lines;
  - simultaneous impacts in (d), from opposite sides and perpendicular, in both orders, with overlapping strips and the attribution;
  - point-blank shots from both sides in the spawn phase; the next sub-step seeing the updated cells;
  - tank + brick in one sub-step, cancellation over brick, destruction affecting movement from the next tick;
  - steel at levels 0–2 and 3, one block or two, `steel_break_level`, block with power, brick behind steel at depth 2, mixed steel + brick precedence;
  - no tunnelling through 1-cell brick and steel at 13 speeds (17 … 512 u/tick) × 64 offsets × 4 directions;
  - the approved 4 × 2 strip: exact cells in 4 directions, one point-blank shot through a ½-tile wall, two through a 1-tile wall, the same level-3 steel cells as 2 × 1, one steel block off a boundary, steel cells independent of the brick strip at 64 offsets × 4 directions × every allowed width and depth, brick behind steel that stays never removed (with and without power), a C1 union at the default strip;
  - the P2-2 footprint coverage at brick widths 2 and 4.
- `terrain_movement_spec`: every tank-blocking type stops a tank at contact; forest and ice do not block; a snap into water turns the tank in place; bullets pass water, forest and ice; forest neutrality (identical positions and events with forest replaced by empty).
- `ice_spec`:
  - the distance, and movement on the trigger tick; no re-trigger;
  - the contact (steel, water), off-ice and same-direction end conditions;
  - perpendicular and reverse triggers with facing, then normal movement on the next tick;
  - a shot during a slide; hit and respawn; distance 0; a single ice cell; the C6 snap-only regression.
- `level_spec`: 4 valid fixtures and 43 invalid ones (one per rule); non-execution and size limits; character mapping; marker parsing; the battlefield shape; reachability; arena resolution; the validator tree check and the file-name checks.
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
- Smoke (Linux, Xvfb, llvmpipe): 8 × `SMOKE OK … problems=none`, both arenas at 1280x720, 1920x1080, 1366x768 and 800x600. The terrain smoke gives `p1=512,2688 p2=2304,3072 hash=ac2a42a0` (it was `4b7aaef1` before the brick tuning; positions unchanged): P1 slides on ice into the water column, and P2 digs through its wall.
- hidpi-sim (SIMULATED): 8/8 PASS, and `--mutations`: 4/4 detected.
- Shell portability (sandbox emulation, **not native**): `tools/smoke.sh` and `tools/hidpi_sim.sh` also pass under an emulated macOS userland, as in PR #2: bash 3.2.57, Apple `od`, and `LANG=LC_ALL=pl_PL.UTF-8`. Smoke ran both arenas at the three macOS sizes (6 × `SMOKE OK`, the same hashes), and hidpi-sim was 8/8. This emulation was run before the brick tuning and not repeated: since then no shell script changed, only the terrain expectation value in `tools/lib/smoke_expect.sh`.

## Internal pre-review (before the independent review)
An independent Opus reviewer read the full diff against the plan and C1–C6. It found **no blockers** and confirmed the sim core, C1, ice and C6, the hash rule and C5, C3, the loader, the app (C2), the render order, the smoke and determinism, several points with scratch scripts. Fixed after the review, with tests:
1. **Campaign `name`** was restricted to an identifier, which rejected TECHNICAL_DESIGN §9's own example `"Opening Gate"`. A campaign name is now a display name of 1–40 characters (letters, digits, space, `_ ' -`). Arena names stay identifiers, because they must equal the file name. New fixtures: `campaign_name`, `campaign_name_chars`, `arena_name`.
2. **Hidden files under `levels/`** (Finder's `.DS_Store`, editor swap files) failed `make validate`, which would break the native `make check`. The validator now skips hidden files and still flags any other misplaced file (regression test with a temporary tree).
3. **Keyed entries in `dummies`** were ignored silently; they are now rejected (fixture `arena_dummies_keyed`).
4. Noted, not a defect, because the spec requires it (§6.6): for a muzzle hit whose spawn box spans two lines with blocking cells in both, `bullet_hit_solid.cell` now comes from the impact line instead of the whole footprint, as G1 did. Events are not hashed, so goldens and smoke are unaffected.

The fixes touch only the level loader and validator. The mutation check (run at `4487626`) does not mutate those files.

## Independent review corrections (review of `fc0fedf`, fixed in `b30e173`)
The reviewer also compared all four G1 golden files with merged G1 independently and confirmed that only `tuning_id` changed.
- **P2-1, strict level arrays** (`src/sim/level.lua`):
  - key types are never converted;
  - `map` and `dummies` must be exactly `t[1..n]`, so string keys such as `"1"`, holes and extra keys are rejected;
  - the header, `roster` and dummy entries accept only their string field names;
  - a present `dummies` that is not a table (`false`, a string) is an error;
  - entries are read by index, never skipped by `ipairs`, and bad keys are reported in sorted order.
  - 10 new invalid fixtures and 5 regression tests. Every valid level and the `g2_terrain` arena id `8b30c45c` are unchanged.
- **P2-2, bullet size bound:**
  - `bullet_size` is limited to 8–64 u (it was 128), matching the F5 editor, and the default stays 32.
  - The footprint then always lies inside the 2-cell strip, and this is documented in TECHNICAL_DESIGN §2 and §6, GAME_DESIGN §4.2 and G2_PLAN §6.2 and §19.
  - Tests: every size 8–64 × 64 offsets × 4 directions destroys all the brick it touches; 65, 96 and 128 u are rejected, with the 128 u geometry that motivated the bound.
- **Unchanged:** the destruction rules, the approved tuning, the tuning id (`1008b573`, since the schema is not part of it), all 8 golden checkpoints (`update_goldens --check` 8/8) and both smoke hashes.
- **Mutation proof:** 5 new mutations (rows 30–34), each detected; the full set of 34 was rerun at `b30e173`.

## Owner brick tuning (2026-11-28, `eeac1f5`)
After native manual playtesting the owner approved `brick_strip_cells = 4` and `brick_strip_depth = 2`, both `TUNED (owner, 2026-11-28)`. Ice tuning stays pending.
- **Steel destruction preserved independently.** Power bullets use a fixed 2-cell steel strip (`destruction.STEEL_STRIP_CELLS`, a contract constant, not tuning), so the wider brick strip never widens steel: 1 tile × ½ tile for an aligned shot, as before. The brick walk stops at steel the impact does not remove, so no brick behind remaining steel is removed. With 2 × 1 the rule gives the previous results: every rule test, pinned to 2 × 1, passes unchanged.
- **Goldens (called out):** tuning id `1008b573` → `949c2b01`. The G1 goldens change only in `tuning_id`. The G2 inputs were re-authored with `tools/gen_g2_replay_inputs.lua`: the `brick_demolition` route was adapted (one muzzle impact per pocket position, a same-tick pair at a 2-cell wall, two more positions on the 2-tile wall), `steel_and_power` waits follow the new bullet paths, and the `terrain_tour` and `terrain_stress` frames are unchanged. Checkpoints come from `tools/update_goldens.lua` (`--check` 8/8 up to date).
- **Smoke:** terrain hash `4b7aaef1` → `ac2a42a0`, positions unchanged; the script now produces 3 P2 shots (the wall is pierced on the second) plus the turret's first shot; the G1 smoke `581f15d4` is unchanged.
- **Named behavior:** `terrain_replay_spec` now checks brick events ≤ 8 cells (the first > 2), and steel events of 4 or 8 cells at most 1 tile wide.
- **Mutation proof:** 6 new mutations (T-1 … T-6, rows 35–40): steel strip following the brick width, the walk passing steel it does not remove, brick width or depth ignoring tuning, the approved width reverted, the steel strip widened. All detected; the full set is 40/40 at `eeac1f5`.

## Not verified here
- Nothing native has been run. Native rendering, smoke at the macOS sizes, feel (brick strip, ice distance), smoothness while destroying terrain, and F8 saves on the Mac are all for the owner (`docs/acceptance/G2-macos.md`).
- `ice_slide_distance` stays **UNV** until the owner signs it off natively. The brick strip (4 × 2) was signed off by the owner after native playtesting; the native checklist on the committed build is still to be run.
- The "impact line nearest the shooter" rule only matters for a box spanning two lines with blocking cells in both. That can happen neither in flight nor at the muzzle: the muzzle's trailing line is inside the shooter's own cells, which never block tanks. It is therefore tested on the pure function, and through the muzzle case where only the far line holds brick.
