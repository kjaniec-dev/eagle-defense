# src/sim

Authoritative gameplay simulation. Pure Lua: no `love`, no presentation or input requires, and no `config/presentation` (art resolution is presentation-only). `tools/check_boundaries.lua` enforces this. See `docs/TECHNICAL_DESIGN.md` §2, §4–§6.

| Module | Role |
|---|---|
| `units.lua` | Unit contract: 1 tile = 256 u, cell 64 u, snap 128 u, field 3328 u |
| `tuning.lua` | `config/tuning.lua` validation, plain values, tuning id |
| `arena.lua` | Arena data validation (half-tile map, entities) and the cell grid |
| `world.lua` | World construction, state hash, invariant checks |
| `geom.lua` | Integer AABBs and the exact continuous bullet-vs-bullet test |
| `move.lua` | Tank movement: alignment-based snap, clamp to contact |
| `bullets.lua` | Firing, muzzle obstruction, the sub-stepped bullet phase |
| `sim.lua` | `sim.new`, `sim.step` (the only mutator, fixed tick order), `sim.hash` |
| `replay.lua` | InputFrame codes, run-length frames, replay runner, recordings |
