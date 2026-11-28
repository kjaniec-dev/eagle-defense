-- Combat and terrain tuning (G1, G2). Every value is an integer in simulation units
-- (1 tile = 256 u, see docs/TECHNICAL_DESIGN.md §2) or ticks (60 per second).
--
-- Each entry is { value, provenance, note }. Provenance tags:
--   UNV       a placeholder assumption, not a reference fact
--   DOC       documented in a public secondary source (GAME_DESIGN §3)
--   TUNED     subjective owner feel sign-off: "TUNED (owner, YYYY-MM-DD)"
--   MEASURED  observed reference value: "MEASURED (method, source, date)";
--             never used for subjective tuning
--
-- tiles/s = u_per_tick * 60 / 256. Design values are converted once, offline,
-- with u_per_tick = floor(tiles_s * 256 / 60 + 0.5); the integer is committed.
--
-- The tuning id (src/sim/tuning.lua) is a hash of the canonical form of the
-- values and the version. Every golden replay records it, and the replay
-- runner refuses replays recorded with a different tuning. Changing a value
-- therefore requires regenerating the goldens with tools/update_goldens.lua,
-- called out in the PR.

return {
  version = 1,
  entries = {
    player_speed = {
      7,
      "TUNED (owner, 2026-11-27)",
      "owner playtest sign-off: 7 u/tick = 1.64 tiles/s (was the UNV placeholder 6 = 1.41 tiles/s)",
    },
    bullet_speed_normal = {
      17,
      "TUNED (owner, 2026-11-27)",
      "owner playtest sign-off: 17 u/tick = 3.98 tiles/s",
    },
    bullet_speed_fast = {
      34,
      "TUNED (owner, 2026-11-27)",
      "owner playtest sign-off: 34 u/tick = 7.97 tiles/s",
    },
    bullet_size = {
      32,
      "UNV",
      "32 x 32 u = 1/8 tile; supported 8..64 u, so it always lies inside its brick strip",
    },
    bullet_limit = {
      { 1, 1, 2, 2 },
      "DOC",
      "active bullets per tank at upgrade level 0..3 (star 2)",
    },
    fast_bullet_level = {
      1,
      "DOC",
      "upgrade level from which shots use bullet_speed_fast (star 1)",
    },
    arena_player_level = { 0, "UNV", "G1 arena only: upgrade level of both players" },
    turret_first_shot = { 60, "UNV", "G1 arena only: tick of the turret's first shot" },
    turret_period = { 120, "UNV", "G1 arena only: ticks between turret shots (limit 1)" },
    turret_bullet_speed = { 17, "UNV", "G1 arena only: turret bullet speed, normal" },
    -- G2 terrain (docs/plans/G2_PLAN.md §9; GAME_DESIGN §4.1, §4.3)
    brick_strip_cells = {
      4,
      "TUNED (owner, 2026-11-28)",
      "brick strip width in cells (4 = 1 tile) on the nearest cell boundary; steel stays 2 wide",
    },
    brick_strip_depth = {
      2,
      "TUNED (owner, 2026-11-28)",
      "brick strip depth in cells along the travel direction (2 = 1/2 tile)",
    },
    steel_break_level = {
      3,
      "DOC",
      "upgrade level from which shots break steel in aligned 2 x 2 blocks (star 3)",
    },
    ice_slide_distance = {
      192,
      "UNV",
      "ice slide distance in u (3/4 tile; 28 ticks at speed 7); 0 disables sliding",
    },
  },
}
