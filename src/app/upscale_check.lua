-- Pure verification that a window image is an exact nearest-neighbour
-- integer upscale of the canvas (used by smoke runs as pixel-perfect
-- evidence).
--
-- canvas_px(x, y) and window_px(x, y) return r, g, b (0..1).
-- vp is the viewport from render/viewport.compute (integer mode).
-- Pixels outside the scaled canvas must be black (letterbox).
--
-- The setup checks come first. A pixel comparison only means something when
-- the canvas really is the configured internal resolution at one texel per
-- internal pixel, the screenshot is the physical framebuffer, and the
-- viewport is exactly canvas x scale and lies inside the window. A canvas
-- created at the display DPI (e.g. 1280x720 texels on Retina) is rejected
-- here with an explicit reason instead of producing a flood of mismatches.

local M = {}

-- Per-channel comparison tolerance (8-bit readback rounding). Unchanged
-- since G0; do not raise it to make a run pass.
M.TOL = 1.5 / 255
local TOL = M.TOL

local function differs(r1, g1, b1, r2, g2, b2)
  return math.abs(r1 - r2) > TOL or math.abs(g1 - g2) > TOL or math.abs(b1 - b2) > TOL
end
M.differs = differs

local function add(list, fmt, ...)
  list[#list + 1] = fmt:format(...)
end

-- Checks that hold for every presentation mode.
--   s = { canvas_w, canvas_h, canvas_dpi, expected_w, expected_h,
--         shot_w, shot_h, phys_w, phys_h }
-- Problem strings contain no spaces, so they fit in one smoke log field.
function M.common_problems(s)
  local p = {}
  if s.canvas_w ~= s.expected_w or s.canvas_h ~= s.expected_h then
    add(p, "canvas_pixels:%dx%d!=%dx%d", s.canvas_w, s.canvas_h, s.expected_w, s.expected_h)
  end
  if s.canvas_dpi ~= 1 then
    add(p, "canvas_dpi:%s!=1", tostring(s.canvas_dpi))
  end
  if s.shot_w ~= s.phys_w or s.shot_h ~= s.phys_h then
    add(p, "screenshot:%dx%d!=physical:%dx%d", s.shot_w, s.shot_h, s.phys_w, s.phys_h)
  end
  return p
end

-- Integer-mode setup problems. s also carries vp. Returns a list (empty = ok).
function M.setup_problems(s)
  local p = M.common_problems(s)
  local vp = s.vp
  if vp.scale ~= math.floor(vp.scale) or vp.scale < 1 then
    add(p, "scale:%s:not_a_positive_integer", tostring(vp.scale))
    return p
  end
  if vp.w ~= s.canvas_w * vp.scale or vp.h ~= s.canvas_h * vp.scale then
    add(
      p,
      "viewport:%sx%s!=canvas_x_scale:%dx%d",
      vp.w,
      vp.h,
      s.canvas_w * vp.scale,
      s.canvas_h * vp.scale
    )
  end
  if vp.x < 0 or vp.y < 0 or vp.x + vp.w > s.shot_w or vp.y + vp.h > s.shot_h then
    add(p, "viewport:%d,%d+%dx%d:outside_window:%dx%d", vp.x, vp.y, vp.w, vp.h, s.shot_w, s.shot_h)
  end
  return p
end

-- Exact pixel counts a complete check must reach.
function M.expected_counts(canvas_w, canvas_h, win_w, win_h, scale)
  local content = canvas_w * canvas_h * scale * scale
  return { content = content, letterbox = win_w * win_h - content }
end

-- Returns { checked, mismatches, letterbox_checked, letterbox_bad, first }.
function M.verify(canvas_px, canvas_w, canvas_h, window_px, win_w, win_h, vp)
  assert(vp.scale == math.floor(vp.scale), "verify requires integer scaling")
  assert(
    vp.w == canvas_w * vp.scale and vp.h == canvas_h * vp.scale,
    ("viewport %sx%s does not match canvas %dx%d at scale %d"):format(
      vp.w,
      vp.h,
      canvas_w,
      canvas_h,
      vp.scale
    )
  )
  local res = { checked = 0, mismatches = 0, letterbox_checked = 0, letterbox_bad = 0, first = nil }
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
      else
        res.letterbox_checked = res.letterbox_checked + 1
        if differs(r, g, b, 0, 0, 0) then
          res.letterbox_bad = res.letterbox_bad + 1
          res.first = res.first or { wx, wy }
        end
      end
    end
  end
  return res
end

-- Problems found by a pixel pass, given the exact expected counts.
function M.result_problems(res, expected)
  local p = {}
  if res.checked ~= expected.content then
    add(p, "pixels_checked:%d!=%d", res.checked, expected.content)
  end
  if res.letterbox_checked ~= expected.letterbox then
    add(p, "letterbox_checked:%d!=%d", res.letterbox_checked, expected.letterbox)
  end
  if res.mismatches ~= 0 then
    add(p, "mismatches:%d", res.mismatches)
  end
  if res.letterbox_bad ~= 0 then
    add(p, "letterbox_bad:%d", res.letterbox_bad)
  end
  return p
end

-- Runs the whole integer-mode check. Returns problems (empty = pass) and an
-- ordered list of { key, value } fields for the smoke log.
function M.run(s, canvas_px, window_px)
  local problems = M.setup_problems(s)
  local vp = s.vp
  local res = { checked = 0, mismatches = 0, letterbox_checked = 0, letterbox_bad = 0 }
  local expected = { content = 0, letterbox = 0 }
  if #problems == 0 then
    expected = M.expected_counts(s.canvas_w, s.canvas_h, s.shot_w, s.shot_h, vp.scale)
    res = M.verify(canvas_px, s.canvas_w, s.canvas_h, window_px, s.shot_w, s.shot_h, vp)
    for _, p in ipairs(M.result_problems(res, expected)) do
      problems[#problems + 1] = p
    end
  end
  local fields = {
    { "scale", ("%d"):format(vp.scale) },
    { "offset", ("%d,%d"):format(vp.x, vp.y) },
    { "pixels_checked", res.checked },
    { "expected_checked", expected.content },
    { "mismatches", res.mismatches },
    { "letterbox_checked", res.letterbox_checked },
    { "expected_letterbox", expected.letterbox },
    { "letterbox_bad", res.letterbox_bad },
  }
  return problems, fields
end

return M
