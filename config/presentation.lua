-- Presentation geometry in canvas pixels (TECHNICAL_DESIGN §2). Render-only:
-- src/sim must not require this file (tools/check_boundaries.lua). The
-- simulation works in units (1 tile = 256 u); src/render maps
-- px = floor(u * TILE_PX / 256).

local TILE_PX = 24
local FIELD_TILES = 13
local FIELD_PX = TILE_PX * FIELD_TILES -- 312

return {
  CANVAS_W = 640,
  CANVAS_H = 360,
  TILE_PX = TILE_PX,
  FIELD_TILES = FIELD_TILES,
  FIELD_PX = FIELD_PX,
  FIELD_X = (640 - FIELD_PX) / 2, -- 164
  FIELD_Y = (360 - FIELD_PX) / 2, -- 24
}
