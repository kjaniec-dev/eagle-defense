# Eagle Defense — Game Design v1.0

Status: **APPROVED v1.0** (owner, 2026-11-26), amended by G2-D1 … G2-D7 (owner-approved 2026-11-28: §4.1 ice, §4.3 terrain, §8 events, §10 invariants, §12 terrain arena). Changes to rules or invariants require owner approval.

## 1. Pillars

1. **Faithful classic play.** The rules, pacing and feel of the 1985 top-down tank arcade formula. When in doubt, prefer the classic behavior over a "better" idea.
2. **Readable at a glance.** Every tank, shot, wall and power-up can be identified instantly, even during effects.
3. **Modern craft, original identity.** High-quality original pixel art, audio and levels. Nothing is copied from the reference games: no code, ROM data, sprites, maps, audio, logos or eagle artwork.

Out of scope: see the master prompt, §10. Any new mechanic requires owner approval.

## 2. Reference variant

| Option | Description | Recommendation |
|---|---|---|
| **A. Battle City (Namco, NES, 1985)** | The canonical ruleset. It has 6 power-ups and 4 enemy archetypes, and enemies cannot pick up power-ups. | **Recommended baseline** |
| B. "Tank 1990" (unlicensed Famicom hack) | Battle City rules with extras: Gun (instant max firepower) and Ship (cross water). Enemies can collect power-ups. It has more stages. | Optional extras, each needs owner approval |

Proposal: baseline = **A**. Tank 1990 extras are **owner decisions Q1–Q2** (§9). Both are cheap to add later as data-driven power-ups.

## 3. Confidence legend for the behavior matrix

- **DOC**: documented in a public secondary source. Sources: StrategyWiki *Battle City/Gameplay*, Wikipedia *Battle City* and *Tank 1990*, a Kotaku article on Tank 1990.
- **CC**: community consensus or widely recalled, but no source was retrieved in this session.
- **UNV**: unverified. The value in the "Eagle Defense proposal" column is **our assumption**. It must be calibrated, not cited as reference fact.

Calibration method (G1/G5): we measure behavior by frame-stepping gameplay footage or play sessions, i.e. by observing behavior. We never read ROM data or disassemblies. Each calibrated value is recorded here with its method and date.

## 4. Reference behavior matrix

Units: **tiles** = playfield tiles (the playfield is 13×13 tiles). **cells** = quarter-tiles (destruction granularity, 52×52 per field). Durations are in seconds at the 60 Hz simulation rate.

### 4.1 Field and movement

| Behavior | Reference | Conf. | Eagle Defense proposal |
|---|---|---|---|
| Playfield | 13×13 tiles; tanks are 1×1 tile | CC | Same: 13×13 tiles, 24 px art per tile (see TECHNICAL_DESIGN) |
| Movement | 4 directions, continuous, no turret | DOC | Same |
| Acceleration | Classic tanks start and stop instantly. Ice is the exception. | CC | **Instant start/stop.** The master prompt says "classic acceleration". We read that as "none". Question Q3. |
| Turning | On a perpendicular turn, the tank snaps to the nearest half-tile | CC | Snap to the half-tile grid. The snap distance is ≤ ¼ tile, so it is unnoticeable. An exact tie snaps up/left (**UNV**). A snap that would collide is not performed: the tank turns in place and retries the snap on later ticks (G1, TECHNICAL_DESIGN §6). |
| Reversing | Reversing is instant, with no snap | CC | Same |
| Simultaneous directions | Unknown | UNV | **Last-pressed direction wins**, so a released key restores the remaining held key. This is deterministic and testable. |
| Speeds | Player ≈ basic enemy; fast enemy ≈ 2× basic | Player: TUNED (owner, 2026-11-27); enemies: UNV | Data-driven values, stored as integer u/tick in `config/tuning.lua` (1 tile = 256 u). Player **7 u/tick = 1.64 tiles/s**, signed off by the owner after G1 playtesting (the placeholder was 6 u/tick = 1.41 tiles/s); this is subjective feel tuning, not a reference measurement. Enemy placeholders (tiles/s): basic 0.70, fast 1.40, power 1.05, armor 0.70, tuned in G4. |
| Ice | The tank slides a short distance after input stops or turns | CC (duration UNV) | G2-D4: on ice (any ice cell under the tank), after an input move that went forward, an input that stops, turns or reverses starts a slide in the last move direction. The slide moves at the tank's speed for `ice_slide_distance` = **192 u (¾ tile, 28 ticks ≈ 0.47 s at speed 7), UNV** until the owner signs it off natively. The facing follows the input during the slide. It ends at the distance, at contact, off ice, or on an input equal to the slide direction, and never retriggers itself. A snap-only move does not arm it. The rule and the distance are **UNV** (assumptions, not reference facts); exact rule: TECHNICAL_DESIGN §6. |
| Tank vs tank | Tanks block each other. Overlap is resolved by refusing the move. | CC | Same, as clamp-to-contact: a move stops exactly at the blocking tank, wall or bound (G1-D1). Tanks spawning inside other tanks may move out (§4.5). |

### 4.2 Shooting

| Behavior | Reference | Conf. | Eagle Defense proposal |
|---|---|---|---|
| Shot limit | 1 active player bullet at star 0–1, and 2 at star 2+ | DOC (star 2) | Same |
| Firing | Fires as soon as a slot is free; there is no cooldown beyond that | CC | Same. A held fire button does **not** auto-repeat; this is an assumption, see Q4. |
| Bullet speed | Normal and fast (star 1+ and the Power enemy) | DOC (qualitative); values TUNED (owner, 2026-11-27) | Normal **17 u/tick = 3.98 tiles/s**, fast **34 u/tick = 7.97 tiles/s**, signed off by the owner after G1 playtesting (subjective feel tuning, not a reference measurement). The G1 turret's bullet speed (17) stays UNV. Bullet size 32 × 32 u (⅛ tile) is **UNV**; it is tunable within 8–64 u, so that a bullet always fits inside its brick strip (G2 review P2-2). |
| Bullet vs bullet | Opposing bullets cancel each other | CC | Player and enemy bullets cancel. Bullets from the same faction pass through each other (UNV). |
| Point-blank shot | Unknown | UNV | A bullet whose spawn box (on the tank's front edge) already overlaps something resolves at once: opposing bullet → cancel, tank → hit, wall or bound → `bullet_hit_solid` without travel (G1). |
| Friendly bullet (G1) | A hit stuns the partner (see §4.6) | CC | Until the stun arrives in G6, a player bullet that reaches the other player is consumed and reported as a friendly `tank_hit` with no other effect. If a hostile bullet hits the same player in the same sub-step, the hostile hit is the one that counts. |
| Bullet vs water and forest | Passes over them | CC | Same |
| Bullet vs edge of the field | Bullet is destroyed | CC | Same, with a "spark" event |

### 4.3 Terrain

| Terrain | Tanks | Bullets | Conf. | Proposal |
|---|---|---|---|---|
| Brick | Block | A hit removes a half-tile-wide, ¼-tile-deep strip in the direction of travel | CC (granularity UNV) | Same, using cell resolution. A tile is a 4×4 cell grid. G2-D2: a shot removes `brick_strip_cells` × `brick_strip_depth` cells: **4 cells (1 tile) wide × 2 cells (½ tile) deep, TUNED (owner, 2026-11-28)** after native playtesting (the G2-D2 proposal was 2 × 1, a reading of the classic ½ × ¼ tile; 2 and 1 remain F5 values), centered on the cell boundary nearest the bullet's center (ties up/left, **UNV**), starting at the brick line nearest the shooter. Depth removal stops at steel (unless the bullet has power) or block. Muzzle impacts (a tank touching the wall) destroy brick too. Simultaneous impacts are resolved together, so no bullet passes through a hole another bullet makes in the same step. |
| Steel | Block | Steel absorbs the bullet. A star 3 shot removes a ½-tile steel block. | DOC (star 3) | Same. Steel granularity is 2×2 cells. G2-D3: below `steel_break_level` = 3 (DOC) steel absorbs the bullet unchanged; a level-3 bullet removes every aligned 2 × 2 steel block touched by its **steel strip** in the impact line, typically 1 tile × ½ tile (a consequence of the centered strip, **UNV**). The steel strip is a fixed 2 cells (½ tile), independent of `brick_strip_cells`, so the wider brick strip never widens steel destruction. Brick behavior does not depend on the level. |
| Water | Block | Pass over | CC | Same. A snap that would overlap water is blocked and turns the tank in place. |
| Forest | Pass; hides tanks | Pass | CC | Same. Forest is drawn above tanks **and bullets** and has no simulation effect (G2-D5). Not destructible: Q5 (some variants clear it at star 3). The G2 placeholder is fully opaque; the edge hint is G3 art. |
| Ice | Pass, slippery | Pass | CC | Same (slide rule in §4.1) |
| Headquarters | Blocks | Any hit destroys it, which means game over | CC | Same (G4; G2 parses and validates the `H` marker only) |
| Test block `X` | Block | Consumed | — | G1 indestructible test block, kept as terrain code 1 (G2-D1). Never destroyed, not even by power bullets. Allowed in test arenas only, never in campaign levels. |

### 4.4 Enemies

| Behavior | Reference | Conf. | Proposal |
|---|---|---|---|
| Archetypes | Basic, Fast (movement), Power (fast bullets), Armor (4 hits) | DOC (types), CC (4 hits) | Same, data-driven |
| Enemies per stage | 20 | CC | 20, with the per-level roster defined in the level file |
| Max on field | 4 in 1P. The 2P value is uncertain (6 is often cited). | UNV | 4 in 1P and 6 in 2P, as a data value. Q6. |
| Spawn points | 3 along the top edge, in rotation | CC (order UNV) | 3 points, cycled center → right → left. The order is an assumption. |
| Spawn timing | The interval shortens with stage and player count | UNV | `interval = max(min, base − k·stage)` with placeholder values, tuned in G4 |
| Spawn animation | A flashing spawn marker appears for ≈1 s before the tank | CC | Same idea with original art. The marker blocks nothing. A spawn is delayed while the point is occupied. |
| Armor feedback | The tank changes color per remaining hit | CC | Same, with an original palette ramp |
| Power-up carriers | The 4th, 11th and 18th spawned tanks flash. Hitting one drops a power-up. | DOC | Same |
| AI | Simple: random direction changes, a bias toward the HQ, random firing | CC (details UNV) | Seeded random walk. On a timer or when blocked, the tank picks a direction weighted toward the HQ (or toward the player as the stage progresses). Fire probability is set per tick per archetype. No pathfinding. |

### 4.5 Power-ups

| Power-up | Reference effect | Conf. | Proposal (durations are placeholders, UNV) |
|---|---|---|---|
| Star | Upgrades the tank: 1 = fast shot, 2 = 2 bullets, 3 = breaks steel | DOC | Same. Level resets to 0 on death. |
| Grenade | Destroys all enemies on the field | DOC | Same. **No score** for grenade kills (CC/UNV, Q7). |
| Helmet | Temporary invulnerability | DOC | 10 s |
| Clock | Freezes all enemies | DOC | 10 s. Frozen enemies neither move nor fire. Spawns continue. |
| Shovel | Turns the HQ walls to steel temporarily | DOC | 20 s, with a flashing warning for the last 3 s. When it ends, the walls are restored as **fresh brick**, including bricks destroyed before the shovel. |
| Tank | +1 life | CC | Same |
| Gun *(T1990)* | Instant max firepower | DOC (variant) | **Q1**: off by default |
| Ship *(T1990)* | Lets the tank cross water | DOC (variant) | **Q1**: off by default |
| Placement | One power-up at a time. A new carrier spawning removes the uncollected one. | DOC | Same. The position is chosen at random from tiles reachable by players (seeded RNG). |
| Enemy pickup | No (BC). Yes (T1990). | DOC | No (Q2) |
| Pickup score | 500 | DOC | 500 |

### 4.6 Players, lives and scoring

| Behavior | Reference | Conf. | Proposal |
|---|---|---|---|
| Starting lives | 3 | CC | 3 (the life in play counts as one) |
| Spawn shield | Short invulnerability on spawn | CC (duration UNV) | 3 s |
| Respawn | Respawn at the player spawn point immediately after the explosion, if lives remain | CC | Same, at a fixed P1 or P2 point beside the HQ |
| Extra life | Awarded at a score threshold | UNV (20 000 often cited) | Every 20 000? Q8 |
| Kill score | 100 / 200 / 300 / 400 for Basic / Fast / Power / Armor | CC | Same |
| Stage tally | Per-type kill counts × points | CC | Same structure, original presentation |
| Friendly fire (2P) | A hit stuns your partner briefly. It does not kill. | CC (duration UNV) | Stun of 3 s. The stunned tank can neither move nor fire, and is shown with a flashing overlay. |
| Stage clear | All 20 enemies destroyed, followed by a short delay | CC | Clear after a 3 s delay. Upgrades and lives carry over. |
| Game over | HQ destroyed, or all players out of lives | CC | Same. In 2P, the game continues while either player has lives. |
| After the last stage | Classic: loops with faster spawns | DOC | 50 stages, then a campaign-complete screen. Loop/"hard mode" is Q9. |

## 5. Campaign

- **50 original levels.** Each is a 13×13-tile declarative file at cell resolution, holding the layout, the enemy roster and an environment tag (see TECHNICAL_DESIGN §9).
- Five environments, which are visual only: Classic Brick, Countryside, Industrial, Winter, Stronghold. Ten levels each, in campaign order.
- Difficulty levers, in order of preference: enemy roster mix → terrain layout → spawn interval → AI aggression. Rule constants do not change between environments.
- Level-design principles: HQ at bottom center, enclosed by brick. Three enemy spawns along the top edge. Player spawns flank the HQ. Lanes, choke points, forest ambush zones, steel cover and water barriers. Layouts are original and are not traced from any reference map.
- Automated validation: dimensions, legal tiles, clear spawns, an intact HQ enclosure, and reachability. A path must exist from every enemy spawn to the HQ when brick is treated as passable and steel and water as blocking.

## 6. Modes and persistence

- 1P and 2P local co-op, with shared stage progress and separate lives and scores.
- High scores: top 10 per mode. Campaign progress: the highest stage reached. A "continue from stage" option is Q10.
- Saves are local only. There are no accounts or backend.

## 7. Controls (default proposal)

| Action | P1 keyboard | P2 keyboard | Gamepad |
|---|---|---|---|
| Move | WASD | Arrow keys | D-pad / left stick (4-way, dead-zone) |
| Fire | Space | Right Ctrl or Enter (numpad) | A / Cross (also B / Circle) |
| Pause | Esc / P | — | Start |

All bindings will be rebindable in G8.

## 8. Audio and feedback events (gameplay-facing)

The simulation emits **events**: shot, hit_brick, hit_steel, tank_destroyed, hq_destroyed, powerup_spawned, powerup_taken, spawn, stage_clear, game_over, player_stunned. Audio and VFX react only to these events and never change gameplay state.

G2-D6 event names: `hit_brick` / `hit_steel` are `bullet_hit_solid` (with `terrain` = `steel` > `brick` > `block`, the highest-precedence type under the bullet in its impact line) and `terrain_destroyed { bullet, terrain = "brick" | "steel", cells }`. `terrain_destroyed` is emitted per impact and per terrain type that lost at least one cell, brick before steel, with the cells in ascending order; a cell destroyed by several simultaneous impacts is reported once, for the first impact in tank order (spawn phase) or bullet order (in flight) (G2 clarification C1).

## 9. Fidelity decisions

On 2026-11-26 the owner accepted the defaults below. Each one can be reopened by the owner.

| # | Question | Decision |
|---|---|---|
| Q1 | Include the Tank 1990 Gun and Ship power-ups? | No |
| Q2 | Can enemies pick up power-ups (the T1990 rule)? | No |
| Q3 | Should "classic acceleration" mean instant start/stop, as in the reference? | Yes, instant |
| Q4 | Does holding fire auto-repeat? | No; each press fires one shot |
| Q5 | Can star 3 shots clear forest? | No |
| Q6 | Max enemies on the field in 2P: 4 or 6? | 6 |
| Q7 | Do grenade kills score points? | No |
| Q8 | Extra-life rule: once at 20k, or every 20k? | Every 20 000 |
| Q9 | Hard/loop mode after stage 50? | Not in v1 |
| Q10 | Stage select / continue for completed stages? | Continue from the highest reached stage |
| Q11 | 1P difficulty: should the spawn interval also depend on player count? | Yes, a shorter interval in 2P |

## 10. Gameplay invariants

1. The simulation advances only in fixed 1/60 s ticks. Rendering never changes simulation state.
2. Identical seed plus input sequence produces an identical state hash on every tick, on every platform.
3. A tank never overlaps a tank-blocking cell (block, brick, steel, water), a bound or another tank after a tick has resolved, apart from the documented spawn-overlap exception.
4. Each tank has at most N active bullets, where N comes from its upgrade level.
5. At most one power-up exists on the field at a time.
6. There are exactly 20 enemies per stage (from the level roster). Each is spawned once and removed once.
7. HQ destruction ends the stage as a loss within the same tick.
8. Destruction state is stored at cell resolution only. There is no floating-point geometry.
9. Terrain changes only by destruction: a cell goes from brick or steel to empty and never back (G2). Asserted every tick in scenarios and replays. The G5 shovel will amend this invariant.

## 11. G1 test arena (not a campaign level)

The G1 arena (`config/arenas/g1_arena.lua`) exists only to tune and verify combat feel. It is original, uses indestructible blocks only (terrain types arrive in G2), and has no HQ, enemies, lives or score.
- **Target dummies** are static tank-sized targets in the enemy faction. A hit consumes the bullet and is counted; dummies are never destroyed.
- **Turret dummy:** a static enemy-faction target that fires one bullet (limit 1) on a fixed tick schedule down a lane, so cancellation can be practised. No AI.
- **Arena respawn** (G1-D2): a hit player respawns at its spawn point on the next tick; it is deferred while any tank occupies the spawn box. Lives arrive in G5.
- Player upgrade level for testing bullet limits and speeds: in G1 the tuning value `arena_player_level`, changed through F5. From G2 it is selected with **F7** (0–3, recorded in replays as `player_level`), and F5 no longer offers it (G2 clarification C2).

## 12. G2 terrain test arena (not a campaign level)

The terrain arena (`levels/arenas/g2_terrain.lua`, arena profile) exists only to verify and tune terrain behavior. It is original and drawn from scratch; no reference map was traced. It has brick walls ½, 1 and 2 tiles thick with partial-brick shapes and a target dummy behind them; a steel band with brick behind it (power bullets open it, normal bullets do not); an `X` block; a turret firing across water and through forest into brick (enemy-faction destruction); a water channel with a 1-tile gap; a forest patch over a lane crossing; an ice field ending at steel (slide to contact), at water (slide stop at contact) and at plain ground (slide ends off ice); P1 spawns below the ice and P2 below a brick wall it can shoot point-blank. `love .` opens it by default; `--arena=` and **F6** switch between it and the G1 arena; **F7** selects the players' upgrade level. Like the G1 arena, it has no HQ, enemies, lives or score.
