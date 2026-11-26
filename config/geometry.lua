-- Battlefield geometry in canvas pixels (see docs/TECHNICAL_DESIGN.md §2).
-- Simulation code works in integer subpixels: 1 px = SUB subpixels.

local TILE = 24
local FIELD_TILES = 13
local FIELD_PX = TILE * FIELD_TILES -- 312

return {
  CANVAS_W = 640,
  CANVAS_H = 360,
  TILE = TILE,
  CELL = TILE / 4, -- destruction granularity, 6 px
  HALF_TILE = TILE / 2, -- turn-snapping grid, 12 px
  FIELD_TILES = FIELD_TILES,
  FIELD_PX = FIELD_PX,
  FIELD_X = (640 - FIELD_PX) / 2, -- 164
  FIELD_Y = (360 - FIELD_PX) / 2, -- 24
  SUB = 16,
}
