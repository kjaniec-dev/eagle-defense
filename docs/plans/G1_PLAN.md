# G1 — Core combat: implementation plan (v2, APPROVED)

Status: **APPROVED by the owner on 2026-11-26** at commit `c772770` (plan v2, after an independent technical review PASS). Implementation started on 2026-11-26 after PR #2 was merged (`d3ccccf`), on explicit owner authorization. The approved decisions and clarifications are recorded in §13.

Preconditions for starting implementation:
1. G0 is natively accepted and merged into `main`, with explicit owner authorization.
2. The owner approves this plan, including decisions §11.

Branch: `g1/combat` from the merged `main`, delivered as one Draft PR. Model: Opus. No CI, no BMAD.

v2 incorporates the G1 plan review clarifications: integer units and rounding, snap safety and tie-breaks, contract reconciliation, the respawn rule, tuning identity in replays, and a high-priority polished visual spike.

## 1. Scope

**In scope:**
- 4-way player tank movement with half-tile turn snapping
- shooting, projectile limits and collision order
- tank and projectile collisions
- an original test arena with target dummies
- deterministic golden replays
- calibration and feel tuning
- **two polished static gameplay concepts (24 px vs 32 px tiles)**

**Out of scope:**
- G2: terrain types and destruction
- G3: final assets, animation and shaders
- G4: enemy AI, spawning, HQ logic
- G5: lives, score, power-ups
- audio

## 2. Simulation units, conversion and rounding (contract amendment, decision G1-D1)

| Quantity | Units (u), all integers |
|---|---|
| tile | **256 u** |
| destruction cell (¼ tile) | 64 u |
| turn-snap grid (½ tile) | 128 u |
| playfield (13 tiles) | 3328 u |
| tank / bullet box | 256 × 256 u / 32 × 32 u (bullet size is UNV, tunable) |

**Speeds:**
- Speeds are stored as **integer u per tick** in `config/tuning.lua`. That integer is authoritative; the simulation never uses floats.
- Human-readable tiles/s is derived for docs only: `tiles_s = u_per_tick × 60 / 256`. The resolution is 1 u/tick ≈ 0.234 tiles/s.
- Converting a design value happens once, offline: `u_per_tick = floor(tiles_s × 256 / 60 + 0.5)`, i.e. round half up. The resulting integer is committed. Runtime code never converts.

**Rendering:**
- `px = floor(u × TILE_PX / 256)`, applied to the entity's top-left in `src/render` only. `TILE_PX` lives in `config/presentation.lua`, which `src/sim` cannot require (enforced by the boundary checker).
- One sim tick is one 1/60 s step, as defined in G0.

**Golden independence:** a test runs the same replay with presentation set to 24 px and to 32 px and requires identical sim hashes at every checkpoint.

## 3. Contract reconciliation with TECHNICAL_DESIGN (part of G1-D1)

The G1 PR amends TECHNICAL_DESIGN §5–§6 before any code:

| Topic | Current text | Amended contract |
|---|---|---|
| Tick order (§5) | input → AI → tank movement → bullet movement and collisions → bullet vs bullet → … | input → AI (none in G1) → tank movement → bullet spawn → **bullet phase** → removals → respawns → events. The **bullet phase** runs sub-steps of ≤ 64 u. Each sub-step does: (a) all bullets advance; (b) bullet vs bullet; (c) bullet vs tank; (d) bullet vs solid/bounds. Bullet-vs-bullet moves *into* the per-sub-step loop instead of being a separate later pass. |
| Blocked movement (§6) | "A blocked move is rejected per axis" | A move is **clamped to contact**: the largest displacement ≤ speed that causes no overlap with solids, bounds or tanks, computed in integer u. A full rejection would leave visible gaps at walls, because speeds are not divisors of the tile. |
| Ties (§6) | resolved by entity order | Unchanged: P1, P2, dummies in creation order, bullets in spawn order. |

## 4. Movement rules

- **Instant start and stop** (decision Q3). Movement is along one axis per tick. Direction comes from the InputFrame (last pressed wins, as in G0).
- **Perpendicular turn:** the target is the nearest multiple of 128 u on the perpendicular axis.
  - The snap distance is ≤ 64 u.
  - **Tie-break** when the position is exactly between two grid lines (offset 64): snap toward the lower coordinate (up / left). This is a deterministic assumption, tagged UNV.
  - The **snap is a collision-checked move**. If the snapped box would overlap a solid, bound or tank, the tank does *not* snap and does *not* move this tick, but its facing changes. Snapping therefore never moves a tank through or into geometry.
  - Then the forward move is clamped to contact.
- **Reversing** never snaps.
- **Invariant:** after every tick, no tank overlaps a solid, a bound or another tank. A per-tick debug assertion checks it in tests and replays.

## 5. Shooting and bullets

- `fire_pressed` spawns a bullet if the tank's active bullets are below the limit: 1 at upgrade levels 0–1, 2 at level 2+. Holding fire does not repeat (decision Q4).
- **Spawn position:** centered on the tank's front edge, so the muzzle is the bullet's rear edge.
- **Muzzle obstruction:** if the spawn box overlaps a solid or bound, the bullet hits it on spawn (`bullet_hit_solid`, no travel). If it overlaps an opposing bullet, they cancel. If it overlaps another tank, it hits that tank.
- **Sub-steps:** the whole world uses one sub-step count per tick, `n = ceil(max active bullet speed / 64)`. Each bullet splits its own speed into n integer parts, giving the remainder to the first sub-steps. A bullet therefore never moves more than 64 u per sub-step, and all bullets are checked against each other at the same sub-step boundaries.
- **Bullet vs bullet:** opposing factions cancel. Detection uses the swept AABB of each bullet over the sub-step, so head-on bullets at any speed and phase cannot tunnel. Same-faction bullets pass through each other.
- **Simultaneous hits:**
  - If a bullet would hit a bullet and a tank in the same sub-step, the bullet-vs-bullet check runs first.
  - If two bullets hit the same tank in one sub-step, both are consumed and the tank is hit once.
- **Events:** `shot`, `bullet_hit_solid`, `bullet_cancel`, `tank_hit`, `tank_respawn`, `respawn_blocked`.

## 6. Arena, dummies and respawn (decision G1-D2)

- `config/arenas/g1_arena.lua` holds an original 13×13 layout of indestructible blocks: corridors, a 1-tile lane, intersections and an open area. It is validated at load.
- Dummies: 2 static targets, and 1 turret that fires on a fixed tick schedule down a lane. No AI.
- **Arena-only respawn:** a hit player is removed and respawns at its spawn point on the next tick.
  - If the spawn box is **occupied** by any tank, the respawn is deferred tick by tick, emitting `respawn_blocked` once, until the box is free. A respawn never creates an overlap.
  - Bullets do not block a respawn. A bullet inside the spawn box on the respawn tick resolves normally in that tick's bullet phase.
  - Lives arrive in G5; this rule is arena-only.

## 7. Tuning, calibration and replay identity (decision G1-D3)

- `config/tuning.lua` holds every G1 constant with a provenance tag:
  - `UNV`: a placeholder assumption
  - `TUNED (owner, date)`: subjective feel sign-off
  - `MEASURED (method, source, date)`: an observed reference value
- **Subjective tuning is never labelled MEASURED.** Measurement comes from frame-stepping gameplay footage only, never from ROM data. It is optional in G1.
- **Tuning identity:** `tuning_id` = the hash of the canonical serialization of the tuning table (G0 serializer).
  - Every replay records the `tuning_id` and `tuning_version` it was recorded with.
  - The replay runner **refuses** to evaluate a replay whose `tuning_id` differs from the active tuning. It reports the mismatch instead of silently producing different results.
- **Live debug tuning (F5 overlay):**
  - It edits an in-memory copy only. It never writes `config/tuning.lua` or any fixture.
  - While active, the HUD shows `TUNING MODIFIED`, and recordings are tagged `debug_tuned = true`.
  - `tools/update_goldens.lua` refuses to accept debug-tuned replays.
  - Signed-off values are copied into `config/tuning.lua` by a normal commit. Goldens are then regenerated explicitly and called out in the PR.

## 8. Tests (they must prove combat works)

**Scenario tests** drive `sim.step` with InputFrames and assert positions, events and invariants:
- movement and stop-at-contact for walls, bounds and tanks
- turn snap at an intersection, entering the 1-tile lane, the snap tie-break, and a blocked snap (turn without moving)
- snapping never passing through geometry
- reversing
- last-pressed through a full turn sequence
- single shot per press, and the bullet limits per level
- **muzzle obstruction** by a wall, a bound, an opposing bullet and an adjacent tank
- bullet vs wall, bounds and dummy
- **high-speed head-on cancellation** across every relative phase offset (0–63 u) and speed pair, so nothing tunnels
- same-faction pass-through
- **simultaneous collisions**: bullet + bullet + tank in one sub-step, two bullets on one tank
- **occupied respawn**: deferred until free, never overlapping
- the no-overlap invariant asserted every tick in every scenario

**Golden replays:**
- Fixtures in `tests/fixtures/replays/*.lua` hold seed, arena, `tuning_id`, run-length-encoded InputFrames and checkpoint hashes.
- Four replays: a movement tour, a shooting gallery, a cancellation duel and a stress run.
- They are regenerated only by `tools/update_goldens.lua`, and each regeneration is called out in the PR.

**Determinism:** checked across 2 LuaJIT processes, and identical for 24 px and 32 px presentation.

**Smoke:** runs the arena headless with scripted input, asserting the sim hash plus the G0 pixel-perfect check.

## 9. Visual direction spike — HIGH PRIORITY (decision G1-D4, G1-D5)

**Goal:** two genuinely polished static gameplay concepts, so the owner can pick the art direction. They must not look like placeholders.

**Same original battlefield composition in both**, including:
- detailed top-down tanks (silhouette, armor plating, tracks)
- the original gold P1 and teal P2 tanks
- 3 distinct enemy designs
- an original eagle HQ
- detailed brick and steel
- water, forest and ice
- one readable projectile with a trail
- one explosion with restrained debris
- restrained shadows and lighting
- a representative HUD (side panels)

| Concept | Tile | Internal canvas | At 1920×1080 |
|---|---|---|---|
| A | 24 px | 640×360 | 3× integer, exact fill |
| B | 32 px | 768×432 | 2× integer = 1536×864 with letterbox, **or** 2.5× "fit" (sharp-bilinear) |

**Deliverables** go in `docs/art/mockups/`, which is concept art, never shipped, with provenance recorded:
- `A-native.png` (640×360) and `B-native.png` (768×432)
- `A-1920x1080.png` (3×), `B-1920x1080-integer.png` (2× letterboxed) and `B-1920x1080-fit.png` (2.5×)
- `compare-1920x1080.png`: the same region (P1 tank, a brick and steel corner, the HQ) from A and B side by side **at the same physical size on screen**, showing the real detail gain against the scaling trade-off. The 2560×1440 case is also noted: A at 4×, B at 3×.
- a short write-up of the trade-offs and a recommendation

**Pipeline options** (decision G1-D5):
- **A. Hand-authored pixel art in the repo (default).**
  - Palette-indexed sprite sources (`assets/src/*.lua`) are rendered by `tools/build_sprites.lua`, with helpers for outlines, shading ramps, mirrored halves and 4-direction rotation.
  - The final composition is rendered by LÖVE in a `--mockup` mode.
  - No new dependencies. This is the crispest result, and its provenance is fully text-reviewable.
- **B. Blender-assisted tank bodies (proposed, not adopted).**
  - Low-poly tank models are rendered orthographically top-down, quantized to the palette, then hand-cleaned as indexed sprites.
  - Pros: consistent lighting and plating across rotations and track frames, and easier variants.
  - Cons: pre-rendered "mush" without heavy cleanup, and an extra tool dependency for asset authoring. **Blender is never a runtime dependency.**
  - It would be used through the Blender MCP only if the owner approves.
- **Honest risk:** AI-authored pixel art may fall short of the premium bar. If it does, the comparison still decides the resolution, and ART_DIRECTION Pipeline B (commission a pixel artist for hero sprites) becomes the recommendation.

**Bounded:** static frames only. No animation, no shaders and no final asset set; those are G3.

## 10. Owner acceptance criteria

**Feel** (native, on the owner's Mac, keyboard and pad):
1. Start and stop feel instant, with no perceived lag.
2. The 1-tile lane can be entered on the first try at an intersection.
3. Movement and bullet speeds feel classic, and the owner signs off the tuned values.
4. One press = one shot. The bullet limit is noticeable. Fast bullets are clearly faster.
5. Cancellation against the turret is visible and reliable.
6. Motion is smooth at 60 Hz, with no hitching. 120 Hz is acceptable.

**Visual:**

7. The owner picks A or B, or asks for a revision, viewing the PNGs on a real display. The decision and feedback are recorded in ART_DIRECTION §3.

**Automated:**

8. `make check` is green with all of §8. Final evidence is generated from a clean HEAD.

## 11. Owner decisions

| # | Decision | Reviewer recommendation |
|---|---|---|
| G1-D1 | Tile = 256 u, plus the §3 contract amendments (tick order, clamp-to-contact) | Approve |
| G1-D2 | Arena-only instant respawn, deferred while the spawn is occupied | Approve |
| G1-D3 | Calibration: owner feel tuning is sufficient; frame-stepped measurements are optional | Feel tuning is sufficient |
| G1-D4 | Mockups under `docs/art/mockups/`, not shipped | Approve |
| G1-D5 | Visual pipeline: A (hand-authored, default) or A plus a Blender-assisted tank experiment through the Blender MCP | A; Blender only if the owner wants the experiment |

## 12. Work order

1. TECHNICAL_DESIGN amendments
2. Units and tuning
3. Movement + tests
4. Bullets + tests
5. Arena, dummies and respawn
6. Replays and goldens
7. Placeholder render, arena state and smoke
8. Tuning overlay
9. **Visual spike** (it can start in parallel after step 1)
10. Docs, evidence and Draft PR

## 13. Owner decisions and clarifications (recorded 2026-11-26)

| # | Owner decision |
|---|---|
| G1-D1 | **Approved:** tile = 256 u, including the §3 contract amendments (tick order with the sub-stepped bullet phase, clamp-to-contact). Recorded in TECHNICAL_DESIGN §2, §5 and §6. |
| G1-D2 | **Approved:** arena-only respawn, deferred while the spawn position is occupied. |
| G1-D3 | **Approved:** owner feel tuning is sufficient; frame-stepped reference measurements are optional. |
| G1-D4 | **Approved:** static mockups in `docs/art/mockups/`, concept art only, never shipped. |
| G1-D5 | **Approved as OPTIONAL:** hand-authored pixel art first. A bounded Blender MCP experiment is allowed only if it materially improves the tank sprites; the owner is notified with setup instructions if it is needed. Blender is never a runtime dependency. |

Implementation clarifications from the plan review (no scope expansion; each has a focused regression test):
1. **Blocked turn:** a turn whose snap is blocked must not let the tank skip the snap on a later tick just because its facing already changed. Implemented as an alignment rule: a tank moves along an axis only while its perpendicular coordinate is on the 128 u grid; otherwise the move first attempts the snap, on every tick, regardless of facing (TECHNICAL_DESIGN §6).
2. **Respawn timing** is reconciled with the documented tick order (TECHNICAL_DESIGN §5): a player hit in tick T is removed in T's removal phase and placed in tick T+1's respawn phase, which runs after T+1's bullet phase. A bullet inside the spawn box therefore resolves in the first bullet phase after placement (tick T+2). Bullets never block a respawn.
3. **Swept projectile collision** must not cancel perpendicular bullets that cross the same region at different times. Bullet vs bullet uses an exact continuous test on the relative motion within the sub-step (integer arithmetic), not an overlap of the two swept boxes (TECHNICAL_DESIGN §6).

Clarification from the G1 independent review of PR #3 (2026-11-27; narrow, no G6 friendly-fire mechanics):
4. **Mixed-faction simultaneous hits:** when friendly and hostile bullets overlap the same tank in one sub-step, all of them are still consumed and the tank still takes one effective hit, but that hit is the first hostile bullet in bullet order, never a friendly one listed earlier. Other collision priorities are unchanged (TECHNICAL_DESIGN §6).

Owner tuning approval (2026-11-27, after manual playtesting, included in PR #3): `player_speed = 7` (was 6), `bullet_speed_normal = 17`, `bullet_speed_fast = 34`, tagged `TUNED (owner, 2026-11-27)` in `config/tuning.lua`; every other tuning value unchanged. The golden replays were regenerated with the approved tooling and the smoke expectation updated.

Also in G1 (owner, PR #2 acceptance): the BSD grep portability correction for `tools/hidpi_sim.sh` with a regression test, as a separate commit.

Process: Fast Track workflow without intermediate approvals unless a material blocker or contract change occurs. CI stays disabled. No BMAD. G1 is delivered as a Draft PR and is merged only on explicit owner authorization; G2 is not started automatically.
