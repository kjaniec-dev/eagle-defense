-- G1 test arena (original layout, not a campaign level; GAME_DESIGN §11).
-- Data only. One map character = 1/2 tile (2 x 2 destruction cells):
--   "."  empty      "X"  indestructible block (G1 only; terrain types arrive in G2)
-- Entity positions are in half-tiles (x = column, y = row of the top-left
-- half-tile); a tank covers 2 x 2 half-tiles. Players come first (P1, P2),
-- then dummies in creation order.
--
-- Layout: an open top area with two pillars and a target; a wall band
-- crossed by two 1-tile lanes (columns 6 and 10); a corridor; a row of
-- blocks with 1-tile gaps; the open bottom area with both player spawns.
-- The turret at the top of column 10 fires down that lane.
return {
  name = "g1_arena",
  map = {
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "......XXXX......XXXX......",
    "......XXXX......XXXX......",
    "......XXXX......XXXX......",
    "......XXXX......XXXX......",
    "XXXXXXXXXXXX..XXXXXX..XXXX",
    "XXXXXXXXXXXX..XXXXXX..XXXX",
    "XXXXXXXXXXXX..XXXXXX..XXXX",
    "XXXXXXXXXXXX..XXXXXX..XXXX",
    "..........................",
    "..........................",
    "..XXXX..XXXX..XXXX..XXXX..",
    "..XXXX..XXXX..XXXX..XXXX..",
    "..XXXX..XXXX..XXXX..XXXX..",
    "..XXXX..XXXX..XXXX..XXXX..",
    "..........................",
    "..........................",
    "......XX..........XX......",
    "......XX..........XX......",
    "......XX..........XX......",
    "......XX..........XX......",
    "..........................",
    "..........................",
  },
  entities = {
    { kind = "player", slot = 1, x = 8, y = 24, facing = "up" },
    { kind = "player", slot = 2, x = 16, y = 24, facing = "up" },
    { kind = "target", x = 2, y = 2, facing = "down" },
    { kind = "target", x = 22, y = 20, facing = "left" },
    { kind = "turret", x = 20, y = 0, facing = "down" },
  },
}
