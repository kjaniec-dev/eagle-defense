-- Simulation unit contract (docs/TECHNICAL_DESIGN.md §2, decision G1-D1).
-- These are contract constants, not tuning: changing one is a contract
-- change that needs owner approval.

local M = {}

M.TILE = 256 -- 1 tile
M.CELL = 64 -- destruction cell, 1/4 tile
M.SNAP = 128 -- turn-snap grid, 1/2 tile
M.FIELD_TILES = 13
M.FIELD = M.TILE * M.FIELD_TILES -- 3328
M.CELLS = M.FIELD / M.CELL -- 52 cells per side
M.TANK = 256 -- tank box size
M.MAX_SUBSTEP = 64 -- longest bullet advance per bullet-phase sub-step
M.TICKS_PER_SECOND = 60

-- Directions: unit vectors and stable integer codes (used in hashes).
M.DIRS = {
  up = { dx = 0, dy = -1, code = 1 },
  right = { dx = 1, dy = 0, code = 2 },
  down = { dx = 0, dy = 1, code = 3 },
  left = { dx = -1, dy = 0, code = 4 },
}

-- Human-readable speed for docs and overlays only; the sim never uses it.
function M.tiles_per_second(u_per_tick)
  return u_per_tick * M.TICKS_PER_SECOND / M.TILE
end

return M
