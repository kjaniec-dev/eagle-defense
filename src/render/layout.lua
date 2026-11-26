-- Pure view model: maps simulation state (units) to canvas pixels for a
-- given tile size. It only reads the world; it never mutates it, so the same
-- replay produces identical sim hashes at any presentation scale (24 px and
-- 32 px tiles are both tested).

local M = {}

local TILE_U = 256 -- src/sim/units.TILE (render may read sim state, not mutate it)
local CELL_U = 64

-- Canvas pixel of a simulation coordinate: px = floor(u * tile_px / 256).
function M.px(u, tile_px)
  return math.floor(u * tile_px / TILE_U)
end

-- Returns { cells = {...}, tanks = {...}, bullets = {...} } with integer
-- pixel rectangles relative to the field origin (ox, oy).
function M.build(world, tile_px, ox, oy)
  ox, oy = ox or 0, oy or 0
  local px = M.px
  local out = { cells = {}, tanks = {}, bullets = {} }
  local n = 3328 / CELL_U
  for r = 0, n - 1 do
    for c = 0, n - 1 do
      local code = world.cells[r * n + c + 1]
      if code ~= 0 then
        local x0, y0 = px(c * CELL_U, tile_px), px(r * CELL_U, tile_px)
        local x1, y1 = px((c + 1) * CELL_U, tile_px), px((r + 1) * CELL_U, tile_px)
        out.cells[#out.cells + 1] = {
          x = ox + x0,
          y = oy + y0,
          w = x1 - x0,
          h = y1 - y0,
          code = code,
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
