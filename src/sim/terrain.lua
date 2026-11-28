-- Terrain codes and their properties (G2 plan §3, decision G2-D1).
--
-- world.cells holds one of these integer codes per 64 u destruction cell.
-- They are contract constants, like src/sim/units.lua: changing a code or a
-- property is a contract change that needs owner approval. The simulation
-- reads only the properties (blocks_tanks, blocks_bullets, destroy,
-- slippery), never a hard-coded code; the lookup arrays below are indexed
-- by code + 1 for speed.

local units = require("src.sim.units")

local M = {}

M.EMPTY = 0

-- code -> properties. `char` is the level-map character (G2 plan §11);
-- `layer` is the presentation layer ("over" is drawn above tanks and
-- bullets, G2-D5).
M.TYPES = {
  [0] = {
    name = "empty",
    char = ".",
    blocks_tanks = false,
    blocks_bullets = false,
    layer = "ground",
  },
  [1] = {
    name = "block", -- the G1 indestructible test block (X), arena files only
    char = "X",
    blocks_tanks = true,
    blocks_bullets = true,
    layer = "ground",
  },
  [2] = {
    name = "brick",
    char = "B",
    blocks_tanks = true,
    blocks_bullets = true,
    destroy = "brick",
    layer = "ground",
  },
  [3] = {
    name = "steel",
    char = "S",
    blocks_tanks = true,
    blocks_bullets = true,
    destroy = "steel",
    layer = "ground",
  },
  [4] = {
    name = "water",
    char = "W",
    blocks_tanks = true,
    blocks_bullets = false,
    layer = "ground",
  },
  [5] = {
    name = "forest",
    char = "F",
    blocks_tanks = false,
    blocks_bullets = false,
    layer = "over",
  },
  [6] = {
    name = "ice",
    char = "I",
    blocks_tanks = false,
    blocks_bullets = false,
    slippery = true,
    layer = "ground",
  },
}

M.COUNT = 7 -- codes 0 .. COUNT - 1

M.CODE = {} -- name -> code
M.CHAR = {} -- map character -> code
M.NAME = {} -- code + 1 -> name

-- Property lookups by code + 1: true/false (or the destroy kind).
M.BLOCKS_TANKS = {}
M.BLOCKS_BULLETS = {}
M.SLIPPERY = {}
M.DESTROY = {}
M.OVER = {}

-- Destruction kinds in event order and the precedence of the `terrain`
-- field of bullet_hit_solid (steel > brick > block), G2 plan §6.6.
M.PRECEDENCE = { steel = 3, brick = 2, block = 1 }

for code = 0, M.COUNT - 1 do
  local t = M.TYPES[code]
  M.CODE[t.name] = code
  M.CHAR[t.char] = code
  M.NAME[code + 1] = t.name
  M.BLOCKS_TANKS[code + 1] = t.blocks_tanks
  M.BLOCKS_BULLETS[code + 1] = t.blocks_bullets
  M.SLIPPERY[code + 1] = t.slippery == true
  M.DESTROY[code + 1] = t.destroy or false
  M.OVER[code + 1] = t.layer == "over"
end

-- True when the box [x, x+w) x [y, y+h) (in u) overlaps a cell whose
-- property is true in `prop` (one of the lookup arrays above). Also returns
-- the lowest such cell index (row-major, 1-based).
function M.box_hits(cells, x, y, w, h, prop)
  local n, cs = units.CELLS, units.CELL
  local c0, c1 = math.floor(x / cs), math.floor((x + w - 1) / cs)
  local r0, r1 = math.floor(y / cs), math.floor((y + h - 1) / cs)
  if c0 < 0 then
    c0 = 0
  end
  if r0 < 0 then
    r0 = 0
  end
  if c1 > n - 1 then
    c1 = n - 1
  end
  if r1 > n - 1 then
    r1 = n - 1
  end
  for r = r0, r1 do
    for c = c0, c1 do
      local i = r * n + c + 1
      if prop[cells[i] + 1] then
        return true, i
      end
    end
  end
  return false
end

return M
