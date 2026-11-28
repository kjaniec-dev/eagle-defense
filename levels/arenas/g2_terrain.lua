-- G2 terrain test arena (original layout drawn from scratch, not a campaign
-- level and not traced from any reference map; GAME_DESIGN §12, G2 plan
-- §12). Data only: read with the non-executing loader (src/sim/level.lua,
-- arena profile), never `require`d.
--
-- One character = 1/2 tile (2 x 2 cells):
--   .  empty   B brick   S steel   W water   F forest   I ice   X test block
--   1 / 2      player spawns (2 x 2 blocks, facing up)
-- Dummies are in half-tiles (x = column, y = row of the top-left).
--
-- Zones (rows, columns are half-tiles):
--   * top left: a 1/2-tile brick wall (row 4) with a partial row below it
--     and the target dummy behind it; a 1-tile wall (cols 7-10) and a
--     2-tile wall (cols 13-16);
--   * top right: a steel band (rows 4-5) with brick behind it (rows 2-3):
--     power bullets (F7 level 3) open it, normal bullets do not; an X block
--     (row 7) never breaks;
--   * the turret lane (rows 8-9): the turret at the right edge fires left
--     across water (cols 18-21) and through forest (cols 12-15) into brick
--     (cols 6-7), enemy-faction destruction;
--   * a water channel (rows 12-13) with a 1-tile gap (cols 10-11); bullets
--     cross it anywhere;
--   * a forest patch (rows 16-19, cols 12-15) over the lane crossing;
--   * bottom left: an ice field (rows 16-23, cols 0-5) ending at steel (row
--     15, slide to contact), at water (col 6, slide stop at contact) and at
--     plain ground (rows 22-25 to the right and the spawn rows below);
--   * P1 spawns below the ice; P2 spawns touching a brick wall (rows 22-23)
--     that it can shoot point-blank.
return {
  name = "g2_terrain",
  map = {
    "..........................",
    "..........................",
    ".............BBBB...BBBBBB",
    ".............BBBB...BBBBBB",
    ".BBBB..BBBB..BBBB...SSSSSS",
    "B.B.B..BBBB..BBBB...SSSSSS",
    "..........................",
    "...XX.....................",
    "......BB....FFFF..WWWW....",
    "......BB....FFFF..WWWW....",
    "..........................",
    "..........................",
    "WWWWWWWWWW..WWWWWWWWWWWWWW",
    "WWWWWWWWWW..WWWWWWWWWWWWWW",
    "..........................",
    "SSSSSS....................",
    "IIIIIIW.....FFFF..........",
    "IIIIIIW.....FFFF..........",
    "IIIIIIW.....FFFF..........",
    "IIIIIIW.....FFFF..........",
    "IIIIIIW...................",
    "IIIIIIW...................",
    "IIIIII..........BBBBBB....",
    "IIIIII..........BBBBBB....",
    "..11..............22......",
    "..11..............22......",
  },
  dummies = {
    { kind = "target", x = 2, y = 1, facing = "down" },
    { kind = "turret", x = 24, y = 8, facing = "left" },
  },
}
