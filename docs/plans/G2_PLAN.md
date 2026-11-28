# G2 — Battlefield, terrain and destruction: implementation plan (v1.1, APPROVED)

Status: **APPROVED** by the owner on 2026-11-28 after an independent review of v1.1 at `fa93ba4` (PASS with bounded clarifications). Decisions G2-D1 … G2-D7 are approved as recommended in §13. The six implementation clarifications in §19 are approved and take precedence over the sections they refine. Implementation runs on `g2/battlefield`. G3 is not started.

v1.1 incorporates an internal pre-review by an independent Opus reviewer. That review confirmed the G1 hash-preservation argument. The changes:
- the slide-restart blocker is fixed (§7);
- muzzle impacts are now order-independent (§6.4);
- the muzzle impact row, depth versus steel, mixed-terrain events, loader shape and marker parsing, and replay plumbing are made precise;
- the G1 smoke keeps its arena explicitly;
- tests are added for each of these.

Preconditions:
1. G1 is accepted and merged into `main` (done 2026-11-27, merge commit `6e03a2f`).
2. The owner approves this plan, including the decisions in §13.

Implementation branch after approval: `g2/battlefield` from `main`, delivered as one Draft PR. Model: Opus (Fable 5.2 only if a shader is ever needed; none is planned). Fast Track workflow: plan, approval, autonomous implementation, `make check`, Draft PR, evidence package, independent review, fixes, native acceptance, merge **only on explicit owner authorization**. No CI, no BMAD, no unrelated infrastructure work.

Sources: GAME_DESIGN §4.1 (ice), §4.3 (terrain), §5 (level validation), §10 (invariants); TECHNICAL_DESIGN §5 (tick order), §6 (collision), §9 (level format), §10 (testing); ROADMAP G2; ART_DIRECTION §2 and §3 (concept A, 24 px tiles, 6 px cells).

## 1. Scope

**In scope:**
- a data-driven battlefield: the existing 52 × 52 cell grid gains terrain codes with a property table;
- destructible brick at cell resolution;
- steel, and steel breaking by upgraded (level 3) projectiles;
- water: blocks tanks, bullets pass;
- forest: passable, drawn above tanks and bullets (concealment), with explicit render layers;
- ice: a deterministic slide rule;
- deterministic collision and destruction ordering;
- the level file format with a non-executing loader and a validator (`tools/validate_levels.lua` in `make validate`);
- an original terrain test arena;
- scenario and regression tests, golden replays, smoke, and native acceptance criteria;
- PLACEHOLDER rendering of every terrain type at cell resolution.

**Out of scope (milestone boundaries):**

| Item | Milestone |
|---|---|
| HQ entity, HQ destruction, game over (the format parses and validates `H` only) | G4 |
| Enemy tanks, AI, enemy spawning (the format parses and validates `E` only) | G4 |
| Power-ups, including the shovel (steel walls, brick restoration) and star pickups | G5; upgrade level stays a test setting |
| Lives and score | G5 |
| Friendly-fire stun | G6 |
| Campaign levels (G2 ships no campaign level) | G7 |
| Final terrain art, water and ice animation, the forest edge hint, destruction VFX | G3, at the approved 24 px |
| Audio | not in G2 |
| Ship power-up (Q1: no), forest clearing (Q5: no) | never in v1 |

## 2. Preserved G1 guarantees

These are acceptance criteria, each checked by a test or by the evidence:

1. **G1 behavior is unchanged.**
   - The four G1 golden replays keep **byte-identical checkpoint hashes**. Only their `tuning_id` changes, because G2 adds tuning entries (§9).
   - The G1 smoke expectation stays `p1=1408,2688 p2=1664,2652 hash=581f15d4`.
2. **Approved tuning is unchanged:** `player_speed` 7, `bullet_speed_normal` 17, `bullet_speed_fast` 34 (`TUNED (owner, 2026-11-27)`). G2 only adds entries.
3. **Tick order, clamp to contact, alignment snapping, the exact bullet-vs-bullet test, the effective-hit rule (clarification 4) and arena respawn** are unchanged. G2 adds terrain effects inside the existing phases (§5) and adds no new phase.
4. **Determinism and units.**
   - Integer u, the project RNG, and ordered iteration only.
   - `src/sim` stays pure, enforced by the boundary checker.
   - Presentation never mutates the sim, and 24 px and 32 px presentation give identical hashes.
5. **Units contract is unchanged:** 1 tile = 256 u, cell = 64 u, snap = 128 u. With concept A, a cell is exactly 6 px (24 px / 4).

## 3. Battlefield representation (data-driven)

`world.cells` stays a flat row-major array of 52 × 52 integer terrain codes. The codes and their properties live in one table, `src/sim/terrain.lua`. These are contract constants, like `units.lua`; a change needs owner approval.

| Code | Name | Map char | Tanks | Bullets | Destruction | Layer |
|---|---|---|---|---|---|---|
| 0 | empty | `.` | pass | pass | — | ground |
| 1 | block | `X` | block | consumed | never | ground |
| 2 | brick | `B` | block | consumed | brick strip (§6.2) | ground |
| 3 | steel | `S` | block | consumed | 2 × 2 steel blocks, only by power bullets (§6.3) | ground |
| 4 | water | `W` | block | pass | — | ground |
| 5 | forest | `F` | pass | pass | — (Q5) | over |
| 6 | ice | `I` | pass, slippery (§7) | pass | — | ground |

- **Code 1 (`block`) keeps its G1 meaning:** an indestructible test block. It is allowed only in arena files (G1 and the test arena), never in campaign levels. Keeping the code at 1 is what keeps the G1 hashes identical: `sim.hash` folds every non-zero cell code.
- The sim reads only the properties (`blocks_tanks`, `blocks_bullets`, `destroy`, `slippery`), never a hard-coded code. The movement and collision helpers (`box_hits_cells`, `cell_limit`) take the property they test: tank-blocking for movement, bullet-blocking for bullets.
- A cell changes only by destruction, from brick or steel to empty. No other change exists in G2. This is invariant 9 (§10).

## 4. Movement over terrain

- Tanks are blocked by block, brick, steel and water. Forest and ice do not block them.
- Clamp to contact, alignment snapping (including the collision-checked snap) and reversing are unchanged. They test the tank-blocking property instead of "any non-zero cell". For G1 cells (codes 0 and 1) this is the same set, so G1 behavior is unchanged.
- **Water** is the only new tank-blocking type that bullets pass over (§6.1). A snap that would overlap water is blocked and turns the tank in place, like any other blocked snap.
- Destruction takes effect for movement on the next tick, because movement runs before the bullet phase.

## 5. Tick order (unchanged phases, terrain effects added)

input → AI (none) → **tank movement** (ice slides here, §7) → **bullet spawn** (muzzle impacts may destroy terrain, §6.4) → **bullet phase**, n sub-steps of (a) advance, (b) bullet vs bullet, (c) bullet vs tank, (d) bullet vs terrain and bounds (**destruction here**, §6.5) → removals → respawns → events.

Each consequence follows from the order:
- A bullet cancelled in (b), or consumed by a tank in (c), never touches terrain in that sub-step.
- A bullet that overlaps both a tank and brick in one sub-step hits the tank and destroys nothing.

## 6. Bullets and destruction

### 6.1 Pass-through

Bullets pass over empty, water, forest and ice with no event. Bounds behave as in G1: leaving the field consumes the bullet with `bullet_hit_solid{kind="bound"}`.

### 6.2 Brick strip (GAME_DESIGN §4.3; dimensions UNV, tunable)

When a bullet box overlaps at least one bullet-blocking cell after an advance (or at spawn), the bullet is consumed. The cells it removes are defined in travel-axis terms:

1. **Impact row.** The bullet (32 u deep) overlaps at most two cell rows along its travel axis. The impact row is the one **nearest the shooter** (the trailing row) that contains a bullet-blocking cell under the bullet's footprint.
   - In flight only one row can qualify. A sub-step advances ≤ 64 u, the trailing row was already checked on the previous sub-step, and cells never become blocking.
   - The rule matters only for a spawn box that spans two rows. Example: a tank at y = 980 facing up has the spawn box [948, 980), which spans rows 14 and 15; the impact row is 15.
2. **Strip columns.** Let `c` be the bullet's center on the perpendicular axis. Let `b` be the cell boundary (a multiple of 64 u) nearest to `c`; an exact tie at `c ≡ 32 (mod 64)` goes to the lower coordinate, consistent with the snap tie (UNV). The strip is the `brick_strip_cells` cells centered on `b`: cells `b/64 − w/2 … b/64 + w/2 − 1`, clipped to the field.
3. **Depth.** `brick_strip_depth` rows, starting at the impact row and going in the travel direction. Within each strip column, removal stops at the first bullet-blocking cell that the bullet cannot destroy: block always, steel unless the bullet has power. So a normal bullet never removes brick that lies behind steel.
4. **Effect.**
   - Every **brick** cell in the strip × depth area becomes empty.
   - Steel and block cells there are untouched, unless the bullet has power (§6.3).
   - The bullet is consumed even when the strip contains no brick (for example a steel or block hit).

The defaults are `brick_strip_cells = 2` and `brick_strip_depth = 1`: a ½-tile-wide, ¼-tile-deep strip, as in GAME_DESIGN §4.3. The bullet footprint (32 u) always lies inside the strip, because `|c − b| ≤ 32`.

A fired bullet's center is `t.x + 128` (or `t.y + 128`). An aligned tank (on the 128 u grid) therefore always shoots exactly on a cell boundary. Only a tank whose snap was blocked shoots off the boundary, and the tie rule covers that case.

### 6.3 Steel and power bullets

- A bullet has `power = true` when its shooter's upgrade level is ≥ `steel_break_level` (3; DOC: "a star 3 shot removes steel").
- A non-power bullet that hits steel is consumed, and the steel is unchanged.
- A power bullet removes every **steel** cell of each aligned 2 × 2 steel block (cells at even cell coordinates, which is ½ tile, the map-char granularity) that contains a steel cell of its strip in the impact row.
  - A centered shot from an aligned tank straddles two blocks, so it removes 1 tile wide × ½ tile deep of steel (UNV, a direct consequence of "½-tile steel block" plus a centered strip).
  - The same power bullet also removes brick in its strip as in §6.2. Brick behavior does not depend on the upgrade level.
- **Block (`X`) is never destroyed**, not even by power bullets.

### 6.4 Muzzle impacts

The G1 rule for a spawn box that overlaps a bullet-blocking cell is "hit solid without travel". It now applies the same destruction as §6.2 and §6.3, so a tank touching a brick wall can shoot it. This matters because a tank stopped at contact has its spawn box exactly in the first brick row.

**Order independence.** Bullet spawns are still processed in tank order (P1, P2, then dummies) for bullet-vs-bullet and bullet-vs-tank, as in G1. **Terrain impacts in the spawn phase use the cell state at the start of the spawn phase**, and their removals are applied as a union at the end of the spawn phase, in tank order.

Example: P1 and P2 fire point-blank, from opposite sides, at the same 1-cell-thick wall in the same column. Both bullets are consumed, and neither passes through the hole the other makes. This matches §6.5.

### 6.5 Simultaneous impacts within a sub-step (order-independent)

Step (d) first determines every impact against the cell state at the start of (d), in bullet order. Only then does it apply all removals: the union of the cells, in bullet order.

As a result, two bullets that hit the same or adjacent brick in one sub-step are both consumed. Neither can slip through a hole that the other makes in that same sub-step. The outcome does not depend on bullet order; only the event order does. The next sub-step sees the updated cells.

### 6.6 Events (data only; presentation and audio consume them)

- `bullet_hit_solid` keeps its G1 fields (`kind` = `"solid" | "bound"`; `cell` = the lowest cell index among the blocking cells under the footprint in the impact row). It gains `terrain`, the highest-precedence type under the footprint there: steel > brick > block.
- New event `terrain_destroyed{bullet, terrain = "brick" | "steel", cells = { index, … }}`. It is emitted per impact and per terrain type that lost at least one cell, brick before steel. The cells are listed in ascending order.
- These map to GAME_DESIGN §8 `hit_brick` / `hit_steel` for presentation. The names follow the G1 style; §13 G2-D6 records the mapping.

## 7. Ice (GAME_DESIGN §4.1; slide rule and distance UNV, owner feel sign-off)

**On ice.** A tank is on ice when its box overlaps at least one ice cell. This is evaluated at the start of the tank's movement in that tick.

**New per-tank state:**
- `ice_dir`: set only by an **input-driven move with a displacement > 0 that ends on ice**, to the direction of that move. It is cleared by every other movement outcome: a slide move, a blocked snap, a 0-distance move, no movement, or a move ending off ice. A slide therefore can never re-trigger itself.
- `slide_dir` and `slide_rem` (u): an active slide.

**Starting a slide.** A slide starts when the tank is on ice, `ice_dir` is set, and this tick's input is one of:
- no direction;
- a perpendicular direction;
- the reverse direction.

The slide is set to `slide_dir = ice_dir` and `slide_rem = ice_slide_distance`, and **the tank slides on that same tick**.

**While sliding.** Each tick the tank moves along `slide_dir` by `min(speed, slide_rem)`, clamped to contact.
- No snap is needed, because the tank is already aligned for that axis.
- The **facing follows the input** (if any), so a shot leaves in the new facing.

**Ending a slide.** The slide ends at the first of:
- `slide_rem` reaching 0;
- a clamp to 0 (contact with a wall, water, bound or tank);
- the tank no longer being on ice at the start of a tick;
- an input equal to `slide_dir`, which cancels the slide and starts normal movement in that direction on the same tick.

- When the slide ends because the tank is off ice (checked at the start of the tick), normal input movement runs on that same tick.
- When the slide ends by distance or contact during a tick, any input (perpendicular or reverse) moves normally from the next tick.
- Ice state is processed per tank in tank order within the movement phase, as for all G1 movement.

Worked example (speed 7, distance 192, input "up" held on a large ice field, then released at tick N):
1. Tick N: no input, and `ice_dir = up`. The slide starts and moves 7 u (`slide_rem` 185); `ice_dir` is cleared.
2. Ticks N+1 … N+27: the slide continues; tick N+27 moves the last 3 u.
3. Tick N+28: no slide and `ice_dir` is none, so the tank stays put. It does not glide on.

**Defaults and other tanks.**
- The slide runs at the tank's own speed. A hit or respawn clears all ice state.
- `ice_slide_distance = 192` u (¾ tile, inside GAME_DESIGN's ½–1 tile), UNV. At 7 u/tick that is 28 ticks ≈ 0.47 s. The owner tunes it with F5 and signs it off as `TUNED`.
- Enemies (G4) use the same rule at their own speed.

## 8. Forest and render layers (presentation only)

- Forest has **no simulation effect**. Tanks and bullets pass, and nothing is detected or hidden in the sim. A test proves this: positions and events are identical when forest is replaced by empty.
- **Render order:**
  1. ground layer (empty, block, brick, steel, water, ice);
  2. tanks;
  3. bullets;
  4. **forest layer**, which hides both tanks and bullets;
  5. effects;
  6. HUD.

  `src/render/layout` returns the forest cells in their own list, and the view draws it after tanks and bullets. A pure test asserts the order.
- The G2 placeholder draws forest fully opaque, which is classic concealment. The "subtle hint at the edges" (ART_DIRECTION §2.5) is G3 art.
- PLACEHOLDER rendering:
  - each terrain type gets a distinct flat or patterned look from the concept-A palette, labelled PLACEHOLDER;
  - destruction is visible per 6 px cell at 24 px (8 px at 32 px);
  - no new assets, so no manifest entry is needed.

## 9. Tuning additions (`config/tuning.lua`, provenance-tagged)

| Key | Default | Tag | Validation |
|---|---|---|---|
| `brick_strip_cells` | 2 | UNV | 2 or 4 |
| `brick_strip_depth` | 1 | UNV | 1 or 2 |
| `steel_break_level` | 3 | DOC | 1..3 |
| `ice_slide_distance` | 192 | UNV | 0..512 (0 disables sliding) |

The approved values stay untouched (§2). Supporting changes:
- The tuning schema gains a `one_of` rule type for the enumerated keys.
- The F5 editor (`src/app/tuning_edit.lua`) gains entries for `ice_slide_distance` (step 8), `brick_strip_cells` and `brick_strip_depth`, so the owner can tune them natively. As in G1, any F5 change marks recordings `debug_tuned`.

The tuning id changes. Therefore:
- The four G1 goldens are regenerated with `tools/update_goldens.lua`. The PR diff of those fixtures must show **only** the `tuning_id` line, with every checkpoint hash identical.
- The regeneration is called out in the PR.
- A test checks that the regenerated G1 checkpoints equal the `c82ff86` values, which are copied into the test as frozen data.

## 10. State hash and invariants

**Hash extension rule.** New authoritative fields are folded into `sim.hash` after the G1 fields, each with a distinct tag, and **only when they differ from their default**:
- tank `ice_dir`, `slide_dir`, `slide_rem`;
- bullet `power`.

Exact placement:
- per tank, after `hits`: tag 101 + `ice_dir` code, tag 102 + `slide_dir` code + `slide_rem`;
- per bullet, after `size`: tag 111 when `power`.

`player_level` (§14) is an initial condition like the tuning, so it is deliberately not hashed itself; the resulting tank `level` is hashed, as in G1.

Any state reachable in G1 therefore hashes exactly as before, which is what preserves guarantee 1. Every new field is still covered whenever it matters. Destroyed cells are already covered, because the cell section folds every non-zero code.

**Invariants**, asserted every tick in scenarios and replays (GAME_DESIGN §10, extended):
3. No present tank overlaps a tank-blocking cell (block, brick, steel, water), a bound or another tank.
8. Destruction state is stored at cell resolution only.
9. **(new)** Terrain changes only by destruction: a cell goes from brick or steel to empty and never back. The test helper and the replay runner compare each tick with the previous one. Restoration arrives with the shovel in G5 and will amend this invariant.

## 11. Level format, loader and validator (TECHNICAL_DESIGN §9)

**File.** A data-only table literal, read only with `core/serialize.decode` (non-executing, with size and depth limits). It is never `require`d.

**Map.** 26 rows × 26 characters, one character per ½ tile (2 × 2 cells):
- terrain: `. B S W F I`, plus `X` in arena files only;
- markers: `1`, `2`, `E`, `H`, each written as a **2 × 2 block of the same character** at any half-tile position. The tank or HQ covers that block, and the marker cells become empty ground.
- **Marker parsing** scans row-major from the top-left. Each still-unclaimed marker character starts a block at that position, and the other three cells must be the same character, else it is an error. For example, `EEEEEE` over two rows gives three side-by-side blocks. Any marker character left unclaimed is an error.
- Player spawns face up. Enemy spawns (G4) face down.

**Pure loader.** `src/sim/level.lua` has `level.parse(text, profile)`. It returns every problem found, or a battlefield with the same shape `world.new` already accepts from `arena.build`: `{ name, cells, entities }`, with the players first (slots 1 and 2), then dummies. It adds `hq` and `enemy_spawns`, which `world.new` ignores until G4.
- File access: the app reads the text with `love.filesystem.read`; tests and tools read it with `tools/lib/fs`. G2 adds **no new file access** to `src/sim`. G1 already `require`s config modules there, and that is unchanged.
- **Arena selection rule:** a name that exists under `config/arenas/` uses the G1 loader. Any other name is resolved through the caller's resolver (`levels/arenas/<name>.lua`).

**Profiles:**

| Check | `campaign` (G7 levels; G2 tests only) | `arena` (test arenas) |
|---|---|---|
| Header | `id` (1..50), `env` (`classic`, `countryside`, `industrial`, `winter`, `stronghold`), `name`, `roster` (basic, fast, power, armor ≥ 0, sum = 20) | `name`; optional `dummies` (G1 target/turret entities, in half-tiles, validated against tank-blocking terrain as `arena.build` does) |
| Markers | exactly one `1`, one `2`, one `H`; exactly three `E` blocks, all in rows 0–1 | exactly one `1` and one `2`; no `H` or `E` |
| `X` | forbidden | allowed |
| HQ | at bottom center (half-tile columns 12–13, rows 24–25); the 8 surrounding half-tiles (row 23, columns 11–14; rows 24–25, columns 11 and 14) are all `B` (an intact enclosure) | — |
| Reachability | from every `E` spawn, a 2 × 2-half-tile tank box can reach a position overlapping the HQ. The search is a 4-neighbour BFS over half-tile positions, with `B F I . 1 2 E H` passable and `S W` blocking (GAME_DESIGN §5) | — |
| Overlaps | markers do not overlap each other or the dummies | same |

**Validator.** `tools/validate_levels.lua` validates every file under `levels/` by profile (`levels/NN.lua` uses campaign, `levels/arenas/*.lua` uses arena) and is added to `make validate`. G2 ships no campaign level, so campaign validation is proven by fixtures in `tests/fixtures/levels/`: valid files, plus one invalid file per rule.

**G1 arena.** `config/arenas/g1_arena.lua` stays in its G1 format and loader, unchanged. This protects the G1 goldens; converting it would gain nothing.

## 12. Terrain test arena (original, not a campaign level)

`levels/arenas/g2_terrain.lua` is in the arena profile. It is original and drawn from scratch, with no reference map traced.

**Zones:**
- brick walls ½, 1 and 2 tiles thick, with partial-brick shapes;
- a steel band with brick behind it, so that power bullets open it and normal bullets do not;
- a water channel with a 1-tile gap, and a lane where bullets cross water;
- a forest patch over a lane crossing;
- an ice field ending at a steel wall (slide to contact) and at water (slide stop);
- a turret dummy firing across water and through forest into brick (enemy-faction destruction);
- a target dummy behind brick;
- player spawns at the bottom.

**App:**
- `love .` opens the terrain arena by default.
- `--arena=g1_arena|g2_terrain` selects an arena (new in `src/app/args.lua`), and **F6** switches between the two.
- **Smoke mode keeps the G1 arena:** `tools/smoke.sh` and `tools/hidpi_sim.sh` pass `--arena=g1_arena` explicitly for the G1 smoke. The terrain smoke passes `--arena=g2_terrain` with its own script and expectation variable. Both scripts and expectations are pinned against the pure sim in `tests/app/arena_spec.lua`.
- **F7** cycles the players' upgrade level 0–3 and restarts the arena. The level is recorded in the replay header (§14), so it is not debug tuning; F5 still marks debug tuning.
- F2 (restart) and F8 (save replay) are unchanged.

## 13. Owner decisions

| # | Decision | Recommendation |
|---|---|---|
| G2-D1 | Terrain codes: keep G1 `X` as code 1 `block` (indestructible, arena-only, forbidden in campaign levels); the new types get codes 2–6; the hash extension rule (§10) | Approve. This keeps the G1 goldens and smoke byte-identical except for `tuning_id` |
| G2-D2 | Brick strip 2 cells wide × 1 cell deep, centered on the nearest cell boundary (tie up/left), resolved simultaneously within a sub-step and within the spawn phase; depth removal stops at steel or block that the bullet cannot destroy (§6.2, §6.4, §6.5). Alternative: 4 cells wide (a tank-wide tunnel per row) | The 2 × 1 default from GAME_DESIGN, kept tunable; owner feel check natively |
| G2-D3 | Steel: absorbs below level 3; a level-3 bullet removes the aligned 2 × 2 steel blocks touched by its strip (typically 1 tile × ½ tile); brick behavior is the same at all levels | Approve |
| G2-D4 | Ice: the slide model in §7 (trigger, facing follows input, the end conditions, "on ice" = any ice cell under the box) with `ice_slide_distance = 192` u (UNV). Alternative for "on ice": the majority of the box's cells | Approve the model; the owner signs off the distance as `TUNED` after native play |
| G2-D5 | Forest: presentation only, opaque in G2, drawn above tanks **and** bullets; the edge hint is G3 | Approve |
| G2-D6 | Level format: 2 × 2 marker blocks, the `campaign` and `arena` profiles, the fixed HQ position and brick enclosure, reachability as GAME_DESIGN §5; HQ and enemy-spawn behavior deferred to G4; event names `bullet_hit_solid.terrain` and `terrain_destroyed`, mapped to GAME_DESIGN §8 `hit_brick` / `hit_steel` | Approve |
| G2-D7 | Replays: the G1 goldens regenerated for the `tuning_id` change only (checkpoints byte-identical, asserted); new terrain goldens; the optional `player_level` and `arena_id` header fields (§14); the app's F6/F7 keys; the G1 smoke pinned to `--arena=g1_arena` plus a separate terrain smoke | Approve |

**Contract amendments** (made in the first G2 commit, before any code, like G1):
- TECHNICAL_DESIGN §5: destruction in (d), simultaneous; muzzle destruction; ice in movement.
- TECHNICAL_DESIGN §6: terrain properties, the strip and steel rules.
- TECHNICAL_DESIGN §9: the marker blocks, the profiles and the injected reader.
- GAME_DESIGN §4.1 and §4.3: exact rules and UNV tags.
- GAME_DESIGN §8 and §10: the events and invariant 9.
- GAME_DESIGN: a new §12 for the terrain arena.

## 14. Replays and golden strategy

**Format.** It stays at `format = 1`, with two new **optional** header fields. Existing fixtures are unchanged apart from `tuning_id`.

| Field | Meaning |
|---|---|
| `player_level` | 0..3; overrides `arena_player_level` for the initial level and for respawns |
| `arena_id` | 8-hex hash of the built battlefield (cells, spawns, dummies) |

The runner refuses a replay whose `arena_id` differs from the loaded arena, with a clear message; this mirrors the `tuning_id` check.

Plumbing:
- `replay.check` validates both fields when present.
- `replay.new_recording` and `replay.snapshot` carry them, so F8 saves keep them.
- `replay.run` and `tools/update_goldens.lua` take `opts.resolve_arena(name) -> text` for level-format arenas (the selection rule is in §11).
- Tests: an F8 round trip at level 3 in the terrain arena, and refusal of an `arena_id` mismatch.

**New goldens** (inputs authored by `tools/gen_g2_replay_inputs.lua`, distance-based as in G1; checkpoints only from `tools/update_goldens.lua`; each also checked for the behavior it is named after):

| Golden | Proves | Named-behavior check |
|---|---|---|
| `terrain_tour` | movement over ice and forest, blocked by water, brick and steel, slides including a slide into contact | ≥ 1 slide ending at contact, ≥ 1 ending at the ice edge; forest crossed |
| `brick_demolition` | digging through ½-, 1- and 2-tile brick at level 0, muzzle impacts, P1 and P2 hitting a 1-cell wall from opposite sides in the same tick | `terrain_destroyed` ≥ 20; a tank passes through a dug opening |
| `steel_and_power` (`player_level = 3`) | steel broken by power bullets; block untouched; brick strip unchanged | ≥ 2 steel `terrain_destroyed`; block cell count constant |
| `terrain_stress` | 3600 ticks of seeded random input at level 3 with the turret | ≥ 200 shots, ≥ 50 cells destroyed, invariants every tick |

**Determinism.** Each golden is replayed in a second LuaJIT process and with 24 px and 32 px presentation, and a tuning or arena mismatch is refused, as in G1. The G1 goldens run unchanged alongside.

**Smoke.** The G1 smoke run and its expectation are unchanged. A second scripted 120-tick smoke runs on the terrain arena at 1280x720 and 800x600: P1 slides on ice, P2 shoots brick point-blank. It has its own expectation pinned in `tools/lib/smoke_expect.sh` against the pure sim. The SMOKE line gains `arena=<name>`; the existing fields are unchanged.

## 15. Tests (they must prove the battlefield works)

**Scenario specs** drive `sim.step` with InputFrames and assert the no-overlap and terrain invariants on every tick.

- **Data and loader:**
  - the code table and its properties; the char → code mapping;
  - the new tuning keys, their tags and ranges;
  - every profile rule, with one invalid fixture per rule;
  - rejection of executable or oversized level text;
  - reachability: a sealed spawn fails, and a brick-only path passes.
- **Movement:**
  - each tank-blocking type stops the tank at contact;
  - forest and ice do not block;
  - a snap blocked by water turns the tank in place;
  - after brick is dug out, the tank passes, but not through a half-width hole.
- **Brick:**
  - the exact removed cells for all 4 directions;
  - an aligned shot versus a blocked-snap (unaligned) shot, including the tie case. Terrain can only block a 64 u snap, which still leaves the shot on a boundary, so the c ≡ 32 (mod 64) tie needs another tank blocking the snap;
  - depth 1 versus `brick_strip_depth = 2`, and width 2 versus 4;
  - clipping at the field edge;
  - a muzzle impact against touching brick;
  - a bullet passing through a 2-cell hole;
  - **two bullets in one sub-step**, built from opposite sides or perpendicular, because side-by-side shots never share strip cells. Both are consumed, the union is removed, and the result is the same in both bullet orders. The sequential mutation must fail on this geometry. The same test is repeated for the spawn phase (point-blank from both sides);
  - the muzzle impact row when the spawn box spans two rows;
  - depth 2 behind steel (normal bullet: brick behind steel kept; power: removed);
  - mixed steel + brick under one footprint: `terrain` precedence and two `terrain_destroyed` events;
  - **bullet + tank + brick in one sub-step** (the tank wins, no destruction);
  - bullet vs bullet over brick (cancel, no destruction).
- **Steel:**
  - absorbed at levels 0–2;
  - level 3 removes exactly the touched 2 × 2 blocks, including a strip straddling two blocks;
  - level 3 against block: no change;
  - mixed steel and brick in one strip.
- **Water, forest, ice:**
  - bullets pass water, forest and ice;
  - forest neutrality: identical positions and events with forest replaced by empty;
  - ice slide distance and end conditions (contact, ice edge, `slide_rem` 0, the same direction cancels);
  - **regression for the slide restart**: after a slide ends with no input, the tank stays put;
  - the slide moves on its trigger tick; off-ice ends it and normal input runs on the same tick;
  - perpendicular and reverse triggers;
  - a shot during a slide uses the new facing;
  - a hit or respawn clears the slide;
  - `ice_slide_distance = 0` disables sliding.
- **High speed, no tunnelling:** 1-cell-thick brick and steel remnants at speeds up to 512 u/tick × 64 phase offsets, in all directions. This extends the G1 tunnelling matrix to destructible cells.
- **Hash and invariants:**
  - each new field (`ice_dir`, `slide_dir`, `slide_rem`, bullet `power`) changes the hash when non-default and leaves it unchanged when default;
  - an invariant-9 mutation (a cell going from empty back to brick) is reported by the checker.
- **Render:**
  - the layout returns the forest layer after tanks and bullets;
  - cell rectangles are exactly 6 px at 24 px and 8 px at 32 px;
  - presentation never mutates the world.
- **Mutation check.** Each mutation below must be caught by its dedicated test:
  - sequential instead of simultaneous impacts in (d);
  - a strip tie going down/right;
  - a strip centered on the bullet's cell instead of the nearest boundary;
  - steel broken at level 2;
  - a power bullet destroying block;
  - water letting bullets stop, or tanks pass;
  - forest drawn below tanks;
  - a slide that ignores the end of ice;
  - a slide not cancelled by the same direction;
  - muzzle impacts without destruction;
  - a hash extension that folds default values (breaks G1 checkpoints);
  - `ice_dir` set by slide moves (the slide-restart blocker);
  - sequential terrain impacts in the spawn phase;
  - brick removed behind steel by a normal bullet at depth 2.

## 16. Owner acceptance criteria

**Automated** (sandbox and native):
1. `make check` is green with everything in §15.
2. The G1 goldens have checkpoint hashes identical to `c82ff86`.
3. The G1 smoke expectation is unchanged.
4. The terrain smoke expectation matches natively.
5. Final evidence is generated from a clean HEAD.

**Native** (owner's Mac, `docs/acceptance/G2-macos.md`). The roadmap marks this optional; the checklist is provided:
1. Digging through brick feels right, and the ½-tile strip (G2-D2) is acceptable or a change is requested.
2. Steel absorbs normal shots; F7 → level 3 breaks steel; block never breaks.
3. Water blocks tanks, and bullets cross it.
4. Forest hides tanks and bullets fully, and tanks drive through it.
5. The ice slide feels right; the owner signs off `ice_slide_distance` (TUNED) or asks for a change.
6. Motion stays smooth at 60 Hz while terrain is destroyed.
7. Both smoke expectations match natively at 800x600, 1024x640 and 1280x720.
8. Repeated F8 saves in the terrain arena replay correctly.

## 17. Work order

1. Contract amendments (TECHNICAL_DESIGN, GAME_DESIGN), before any code.
2. `src/sim/terrain.lua`, the tuning keys, and the property-based collision helpers. The G1 goldens are regenerated here and their checkpoints proven identical.
3. Brick and steel destruction (spawn and sub-step) + tests.
4. Ice + tests.
5. Level loader, profiles, validator, fixtures, `make validate`.
6. Terrain arena; replay header fields and resolver; G2 goldens.
7. Render layers and PLACEHOLDER terrain; app arena switch and F7; smoke for the terrain arena.
8. Mutation check, docs, evidence, Draft PR, native checklist.

## 18. Risks

| Risk | Mitigation |
|---|---|
| The brick strip or ice feel differs from the classic (granularity UNV) | Tunable data with provenance tags; native feel check; values become `TUNED` only on owner sign-off |
| A hidden G1 behavior change through the property refactor | G1 checkpoints asserted byte-identical; G1 smoke unchanged; G1 mutation tests rerun |
| Destruction makes outcomes depend on bullet order | Simultaneous resolution in (d), tested in both orders; tank order at spawn, documented |
| Level files become an injection vector | Non-executing `serialize.decode` only, with size and depth limits; a rejection test |
| The placeholder look is mistaken for the art direction | PLACEHOLDER labels; G3 owns the art (concept A, ART_DIRECTION §3a) |

## 19. Owner approval and implementation clarifications (2026-11-28)

The owner approved G2-D1 … G2-D7 and authorized implementation with the six clarifications below. They are recorded here before any G2 code, and they refine the sections named.

### C1. Simultaneous destruction events (refines §6.4, §6.5, §6.6)
- Every impact in one resolution batch (the spawn phase, or step (d) of one sub-step) is calculated against the **same batch-start terrain state**. No cell changes until the batch ends.
- The batch removes the **union** of all impacts' cells.
- Each cell actually destroyed is reported **once** in `terrain_destroyed`. A cell claimed by several impacts is attributed to the **first impact in deterministic impact order**: tank order in the spawn phase, bullet order in (d). An impact whose cells were all claimed earlier emits no `terrain_destroyed` for that type, but its `bullet_hit_solid` is still emitted.
- The final terrain and the set of consumed bullets do not depend on the impact order. Only the event attribution does.
- Regression coverage: overlapping strips from two impacts (both orders), in (d) and in the spawn phase.

### C2. F5 / F7 interaction (refines §12, §14)
- **Effective player upgrade level.** The world has one `player_level`, used for the initial level of both players and for every respawn. It is the replay header's `player_level` when present, otherwise the tuning value `arena_player_level` (legacy G1 replays and direct simulation users).
- **F7** is the ordinary arena-level selector. It cycles 0 → 1 → 2 → 3 → 0 and restarts the current arena at that level. It is not debug tuning, so it never sets `debug_tuned`.
- **F5** no longer offers `arena_player_level`, so the two keys can never hold conflicting level settings. The committed `arena_player_level` (0) remains only the default for replays without the header field. F5 still edits every other listed key, and any change marks recordings `debug_tuned`.
- **Restart (F2)** keeps the arena, the F7 level and the F5 copy.
- **Arena switch (F6)** keeps the F7 level and the F5 copy, and restarts on the other arena.
- **Recordings** made by the app always carry `arena`, `arena_id` and `player_level`. A recording made with a modified F5 copy is `debug_tuned` whatever the F7 level is.

### C3. Replay arena identity (refines §14)
- `arena_id` is the 8-hex hash of the built battlefield (cells and entities, i.e. spawns and dummies).
- **Legacy G1 headers stay valid.** A replay of a config arena (`config/arenas/`, the G1 format) may omit `arena_id`. The four G1 goldens keep their headers, and only `tuning_id` changes.
- **G2 recordings and goldens require it.** A replay of a level-format arena (`levels/arenas/`) without `arena_id` is refused. Any replay whose `arena_id` differs from the loaded arena is refused, whatever its format, with a message that names both ids.
- Every new recording carries `arena_id`, in either arena.
- `tools/update_goldens.lua` never writes `arena_id`. It refuses a fixture whose `arena_id` is missing (G2) or does not match, so a regeneration cannot silently bypass an arena change. A changed arena needs the inputs re-authored by the generator, called out in the PR.

### C4. Smoke consistency (refines §12, §14)
- The G1 smoke passes `--arena=g1_arena` explicitly and keeps its expectation, including hash `581f15d4`.
- The terrain smoke passes `--arena=g2_terrain` and has its own expectation.
- `tools/smoke.sh` runs **both** arena scenarios at every window size it covers: the three supported native macOS sizes (800x600, 1024x640, 1280x720) natively, and the existing four sandbox sizes on Linux.
- The sandbox smoke coverage and the SIMULATED HiDPI harness are kept. The harness keeps the G1 arena, passed explicitly.

### C5. G1 hash preservation (refines §2, §10)
- The four approved G1 golden fixtures keep **byte-identical checkpoint hashes**, and only their `tuning_id` line changes. A test compares them with the `c82ff86` values frozen into the test data.
- This is **not** claimed as hash compatibility for every possible G1 state. A G1 state with upgraded players (level ≥ `steel_break_level`) now has power bullets, which are authoritative state and are hashed. The claim covers the approved goldens, the G1 smoke and any state without the new fields.

### C6. Ice movement (refines §7)
- `ice_dir` is armed only by an input-driven move whose **forward** displacement along the input direction is > 0 and that ends on ice.
- A snap-only displacement (the snap succeeds, but the forward move is 0) does not arm `ice_dir`; it clears it.
- The finite-slide and no-retrigger guarantees are unchanged, and a focused regression test covers the snap-only case.
- A slide step of 0 u (contact) ends the slide, and the slide uses that tick's movement.
