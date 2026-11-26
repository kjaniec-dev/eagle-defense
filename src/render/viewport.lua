-- Viewport math: placing the fixed-size game canvas inside a window.
--
-- This module is pure (it does not use `love`). All inputs and outputs are in
-- *physical pixels*, so integer scaling stays pixel-perfect on HiDPI
-- displays. The adapter divides by the DPI scale when it draws.

local M = {}

M.CANVAS_W = 640
M.CANVAS_H = 360

M.MODES = { "integer", "fit" }

-- Computes the placement of a canvas_w x canvas_h canvas in a win_w x win_h
-- window.
--
-- mode "integer": the largest integer scale that fits (at least 1),
--                 centered and letterboxed.
-- mode "fit":     the largest scale that fits, possibly fractional, with
--                 aspect ratio preserved. `prescale` is the integer
--                 nearest-neighbour pre-scale used before the final linear
--                 filtering step ("sharp bilinear").
--
-- Returns { scale, prescale, x, y, w, h }. x/y are integer offsets in
-- integer mode.
function M.compute(win_w, win_h, canvas_w, canvas_h, mode)
  canvas_w = canvas_w or M.CANVAS_W
  canvas_h = canvas_h or M.CANVAS_H
  mode = mode or "integer"
  assert(win_w > 0 and win_h > 0, "window size must be positive")

  local fit = math.min(win_w / canvas_w, win_h / canvas_h)
  local scale, prescale
  if mode == "integer" then
    scale = math.max(1, math.floor(fit))
    prescale = scale
  elseif mode == "fit" then
    scale = fit
    prescale = math.max(1, math.ceil(fit))
  else
    error("unknown scale mode: " .. tostring(mode))
  end

  local w, h = canvas_w * scale, canvas_h * scale
  local x = math.floor((win_w - w) / 2)
  local y = math.floor((win_h - h) / 2)
  return { scale = scale, prescale = prescale, x = x, y = y, w = w, h = h }
end

-- Maps a window pixel position to canvas coordinates. Returns nil when the
-- position lies outside the canvas.
function M.to_canvas(vp, px, py, canvas_w, canvas_h)
  canvas_w = canvas_w or M.CANVAS_W
  canvas_h = canvas_h or M.CANVAS_H
  local cx = (px - vp.x) / vp.scale
  local cy = (py - vp.y) / vp.scale
  if cx < 0 or cy < 0 or cx >= canvas_w or cy >= canvas_h then
    return nil
  end
  return math.floor(cx), math.floor(cy)
end

function M.next_mode(mode)
  for i, m in ipairs(M.MODES) do
    if m == mode then
      return M.MODES[i % #M.MODES + 1]
    end
  end
  return M.MODES[1]
end

return M
