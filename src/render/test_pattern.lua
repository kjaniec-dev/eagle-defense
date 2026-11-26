-- PLACEHOLDER — G0 scaling/pixel-perfect test pattern. This is not final art.
-- It verifies integer scaling, letterboxing and the 640x360 canvas layout.

local geo = require("config.geometry")

local M = {}

local font

local function px(x, y)
  love.graphics.rectangle("fill", x, y, 1, 1)
end

function M.draw(markers)
  local lg = love.graphics
  if not font then
    font = lg.newFont(10, "mono")
    font:setFilter("nearest", "nearest")
  end

  lg.clear(0.08, 0.09, 0.11, 1)

  -- Battlefield area with the tile grid.
  local fx, fy, fs, t = geo.FIELD_X, geo.FIELD_Y, geo.FIELD_PX, geo.TILE
  lg.setColor(0.13, 0.14, 0.17, 1)
  lg.rectangle("fill", fx, fy, fs, fs)
  lg.setColor(0.22, 0.24, 0.29, 1)
  for i = 0, geo.FIELD_TILES do
    lg.rectangle("fill", fx + i * t, fy, 1, fs)
    lg.rectangle("fill", fx, fy + i * t, fs, 1)
  end
  -- The destruction-cell grid, inside the top-left tile only.
  lg.setColor(0.30, 0.32, 0.38, 1)
  for i = 1, 3 do
    for j = 0, t - 1, 2 do
      px(fx + i * geo.CELL, fy + j)
      px(fx + j, fy + i * geo.CELL)
    end
  end

  -- A 1 px checkerboard swatch. Any non-integer scaling shows as moire.
  lg.setColor(0.9, 0.9, 0.9, 1)
  for y = 0, 31 do
    for x = 0, 31 do
      if (x + y) % 2 == 0 then
        px(16 + x, 300 + y)
      end
    end
  end

  -- Single-pixel markers in the canvas corners.
  lg.setColor(1, 0.2, 0.2, 1)
  px(0, 0)
  px(geo.CANVAS_W - 1, 0)
  px(0, geo.CANVAS_H - 1)
  px(geo.CANVAS_W - 1, geo.CANVAS_H - 1)

  -- Debug markers driven by input. These are not gameplay.
  for i, m in ipairs(markers or {}) do
    local x, y = math.floor(m.x / geo.SUB), math.floor(m.y / geo.SUB)
    if i == 1 then
      lg.setColor(0.95, 0.75, 0.2, 1)
    else
      lg.setColor(0.2, 0.8, 0.7, 1)
    end
    lg.rectangle("fill", x, y, t, t)
    lg.setColor(0, 0, 0, 1)
    local c = t / 2
    local notch = {
      up = { c - 2, 0 },
      down = { c - 2, t - 4 },
      left = { 0, c - 2 },
      right = { t - 4, c - 2 },
    }
    local n = notch[m.facing] or notch.up
    lg.rectangle("fill", x + n[1], y + n[2], 4, 4)
  end

  lg.setFont(font)
  lg.setColor(1, 0.35, 0.35, 1)
  lg.print("PLACEHOLDER - G0 TEST PATTERN", 8, 6)
  lg.setColor(0.7, 0.72, 0.78, 1)
  lg.print("P1: WASD + Space", 8, 24)
  lg.print("P2: Arrows + RCtrl", 8, 36)
  lg.print("F3 overlay  F4 scale", 8, 54)
  lg.print("F11 / Alt+Enter fullscr", 8, 66)
  lg.print("Esc quit", 8, 78)
  lg.setColor(1, 1, 1, 1)
end

return M
