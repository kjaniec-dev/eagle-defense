-- Pure view model: maps simulation state (units) to canvas pixels for a
-- given tile size. It only reads the world; it never mutates it, so the same
-- replay produces identical sim hashes at any presentation scale (24 px and
-- 32 px tiles are both tested).
--
-- Render layers (G2 plan §8, G2-D5), drawn in this order by
-- src/render/arena_view.lua: the ground terrain, tanks, bullets, the forest
-- layer (above tanks and bullets: it hides both), effects, then the HUD.

-- Terrain codes, names and the forest layer (read-only sim data).
local terrain = require("src.sim.terrain")

local M = {}

local TILE_U = 256 -- src/sim/units.TILE (render may read sim state, not mutate it)
local CELL_U = 64
local CELLS = 3328 / CELL_U

M.LAYERS = { "ground", "tanks", "bullets", "forest", "effects", "hud" }

-- Canvas pixel of a simulation coordinate: px = floor(u * tile_px / 256).
function M.px(u, tile_px)
  return math.floor(u * tile_px / TILE_U)
end

-- Returns { cells = {...}, forest = {...}, tanks = {...}, bullets = {...} }
-- with integer pixel rectangles relative to the field origin (ox, oy).
-- `cells` holds the non-empty ground-layer cells; `forest` the forest-layer
-- cells. Each cell has x, y, w, h, code, kind (terrain name), col, row.
function M.build(world, tile_px, ox, oy)
  ox, oy = ox or 0, oy or 0
  local px = M.px
  local out = { cells = {}, forest = {}, tanks = {}, bullets = {} }
  for r = 0, CELLS - 1 do
    for c = 0, CELLS - 1 do
      local code = world.cells[r * CELLS + c + 1]
      if code ~= terrain.EMPTY then
        local x0, y0 = px(c * CELL_U, tile_px), px(r * CELL_U, tile_px)
        local x1, y1 = px((c + 1) * CELL_U, tile_px), px((r + 1) * CELL_U, tile_px)
        local list = terrain.OVER[code + 1] and out.forest or out.cells
        list[#list + 1] = {
          x = ox + x0,
          y = oy + y0,
          w = x1 - x0,
          h = y1 - y0,
          code = code,
          kind = terrain.NAME[code + 1],
          col = c,
          row = r,
        }
      end
    end
  end
  for _, t in ipairs(world.tanks) do
    if t.present then
      out.tanks[#out.tanks + 1] = {
        id = t.id,
        kind = t.kind,
        slot = t.slot,
        facing = t.facing,
        x = ox + px(t.x, tile_px),
        y = oy + px(t.y, tile_px),
        size = px(TILE_U, tile_px),
        hits = t.hits,
      }
    end
  end
  for _, b in ipairs(world.bullets) do
    out.bullets[#out.bullets + 1] = {
      id = b.id,
      faction = b.faction,
      dir = b.dir,
      x = ox + px(b.x, tile_px),
      y = oy + px(b.y, tile_px),
      size = math.max(1, px(b.size, tile_px)),
    }
  end
  return out
end

return M
