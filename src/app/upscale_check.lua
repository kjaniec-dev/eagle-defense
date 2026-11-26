-- Pure verification that a window image is an exact nearest-neighbour
-- integer upscale of the canvas (used by smoke runs as pixel-perfect
-- evidence).
--
-- canvas_px(x, y) and window_px(x, y) return r, g, b (0..1).
-- vp is the viewport from render/viewport.compute (integer mode).
-- Pixels outside the scaled canvas must be black (letterbox).

local M = {}

local TOL = 1.5 / 255

local function differs(r1, g1, b1, r2, g2, b2)
  return math.abs(r1 - r2) > TOL or math.abs(g1 - g2) > TOL or math.abs(b1 - b2) > TOL
end

-- Returns { checked = n, mismatches = n, letterbox_bad = n, first = {x, y} | nil }.
function M.verify(canvas_px, canvas_w, canvas_h, window_px, win_w, win_h, vp)
  assert(vp.scale == math.floor(vp.scale), "verify requires integer scaling")
  local res = { checked = 0, mismatches = 0, letterbox_bad = 0, first = nil }
  for wy = 0, win_h - 1 do
    local cy = math.floor((wy - vp.y) / vp.scale)
    for wx = 0, win_w - 1 do
      local cx = math.floor((wx - vp.x) / vp.scale)
      local r, g, b = window_px(wx, wy)
      if cx >= 0 and cy >= 0 and cx < canvas_w and cy < canvas_h then
        res.checked = res.checked + 1
        local cr, cg, cb = canvas_px(cx, cy)
        if differs(r, g, b, cr, cg, cb) then
          res.mismatches = res.mismatches + 1
          res.first = res.first or { wx, wy }
        end
      elseif differs(r, g, b, 0, 0, 0) then
        res.letterbox_bad = res.letterbox_bad + 1
        res.first = res.first or { wx, wy }
      end
    end
  end
  return res
end

return M
