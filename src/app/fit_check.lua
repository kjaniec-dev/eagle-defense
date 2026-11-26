-- Pure verification of the "fit" presentation mode ("sharp bilinear"):
--   1. the game canvas is upscaled by the integer prescale k with NEAREST
--      filtering into an intermediate canvas of (w*k) x (h*k) texels;
--   2. that canvas is drawn once with LINEAR filtering at vp.scale / k.
--
-- Step 1 is checked for exact equality (it is a nearest integer upscale).
-- Step 2 is checked against what bilinear filtering can produce, not
-- against nearest-neighbour equality: every window pixel inside the
-- viewport must lie within the per-channel range of the prescaled texels
-- around its sample point (bilinear output is a convex combination of
-- them), and at a non-integer ratio some pixels must actually be
-- interpolated (linear, not nearest). Pixels whose centre is outside the
-- viewport must be black.
--
-- All window coordinates are physical pixels; vp comes from
-- render/viewport.compute(..., "fit").

local upscale_check = require("src.app.upscale_check")

local M = {}

-- Sampling-position slack in prescaled texels. GPUs compute the bilinear
-- weights at limited sub-texel precision (at least 4 bits in practice), so
-- near a texel centre either neighbour pair may be used. This widens the
-- set of candidate texels; it does not widen the colour tolerance, which
-- stays upscale_check.TOL.
M.SAMPLE_SLACK = 1 / 16

-- Pixel centres closer than this to a viewport edge (in physical pixels)
-- may be rasterised either way and are skipped (counted as "ambiguous").
M.EDGE = 1 / 16

local differs = upscale_check.differs
local TOL = upscale_check.TOL

local function add(list, fmt, ...)
  list[#list + 1] = fmt:format(...)
end

-- s = upscale_check.common_problems fields plus vp, pre_w, pre_h, pre_dpi.
function M.setup_problems(s)
  local p = upscale_check.common_problems(s)
  local vp = s.vp
  local k = vp.prescale
  if k ~= math.floor(k) or k < 1 then
    add(p, "prescale:%s:not_a_positive_integer", tostring(k))
    return p
  end
  if s.pre_w ~= s.expected_w * k or s.pre_h ~= s.expected_h * k then
    add(p, "prescale_pixels:%dx%d!=%dx%d", s.pre_w, s.pre_h, s.expected_w * k, s.expected_h * k)
  end
  if s.pre_dpi ~= 1 then
    add(p, "prescale_dpi:%s!=1", tostring(s.pre_dpi))
  end
  if vp.w ~= s.canvas_w * vp.scale or vp.h ~= s.canvas_h * vp.scale then
    add(
      p,
      "viewport:%sx%s!=canvas_x_scale:%sx%s",
      vp.w,
      vp.h,
      s.canvas_w * vp.scale,
      s.canvas_h * vp.scale
    )
  end
  if vp.x < 0 or vp.y < 0 or vp.x + vp.w > s.shot_w or vp.y + vp.h > s.shot_h then
    add(p, "viewport:%d,%d+%sx%s:outside_window:%dx%d", vp.x, vp.y, vp.w, vp.h, s.shot_w, s.shot_h)
  end
  return p
end

-- Classifies a pixel centre offset d (from the viewport origin) along an
-- axis of length len: "in", "out" or "edge".
local function classify(d, len)
  if d < 0 or d > len + M.EDGE then
    return "out"
  elseif d < len - M.EDGE then
    return "in"
  end
  return "edge"
end

-- 1-D counts of in / edge pixels along an axis, computed analytically
-- (independent of the per-pixel classification used by verify).
local function axis_counts(origin, len, win)
  local n_in = math.max(0, math.ceil(len - 0.5 - M.EDGE))
  n_in = math.min(n_in, win - origin)
  local t = len - 0.5
  local r = math.floor(t + 0.5)
  local n_edge = 0
  if math.abs(r - t) <= M.EDGE and r >= n_in and origin + r < win then
    n_edge = 1
  end
  return n_in, n_edge
end

-- Exact counts a complete fit check must reach.
function M.expected_counts(win_w, win_h, vp)
  local ix, ex = axis_counts(vp.x, vp.w, win_w)
  local iy, ey = axis_counts(vp.y, vp.h, win_h)
  local content = ix * iy
  local covered = (ix + ex) * (iy + ey)
  return { content = content, edge = covered - content, letterbox = win_w * win_h - covered }
end

-- Verifies the window against the prescaled canvas.
-- Returns { checked, mismatches, blended, edge, letterbox_checked,
--           letterbox_bad, first }.
function M.verify(pre_px, pre_w, pre_h, k, window_px, win_w, win_h, vp)
  local ratio = vp.scale / k -- window pixels per prescaled texel
  local slack = M.SAMPLE_SLACK
  local res = {
    checked = 0,
    mismatches = 0,
    blended = 0,
    edge = 0,
    letterbox_checked = 0,
    letterbox_bad = 0,
    first = nil,
  }
  local function texel_range(u, n)
    local a = math.max(0, math.min(n - 1, math.floor(u - 0.5 - slack)))
    local b = math.max(0, math.min(n - 1, math.floor(u - 0.5 + slack) + 1))
    return a, b
  end
  for wy = 0, win_h - 1 do
    local dy = wy + 0.5 - vp.y
    local cy = classify(dy, vp.h)
    for wx = 0, win_w - 1 do
      local dx = wx + 0.5 - vp.x
      local cx = classify(dx, vp.w)
      local r, g, b = window_px(wx, wy)
      if cx == "out" or cy == "out" then
        res.letterbox_checked = res.letterbox_checked + 1
        if differs(r, g, b, 0, 0, 0) then
          res.letterbox_bad = res.letterbox_bad + 1
          res.first = res.first or { wx, wy }
        end
      elseif cx == "edge" or cy == "edge" then
        res.edge = res.edge + 1
      else
        res.checked = res.checked + 1
        local x0, x1 = texel_range(dx / ratio, pre_w)
        local y0, y1 = texel_range(dy / ratio, pre_h)
        local lo_r, lo_g, lo_b, hi_r, hi_g, hi_b = 1, 1, 1, 0, 0, 0
        local equals_a_texel = false
        for ty = y0, y1 do
          for tx = x0, x1 do
            local tr, tg, tb = pre_px(tx, ty)
            lo_r, hi_r = math.min(lo_r, tr), math.max(hi_r, tr)
            lo_g, hi_g = math.min(lo_g, tg), math.max(hi_g, tg)
            lo_b, hi_b = math.min(lo_b, tb), math.max(hi_b, tb)
            if not differs(r, g, b, tr, tg, tb) then
              equals_a_texel = true
            end
          end
        end
        if
          r < lo_r - TOL
          or r > hi_r + TOL
          or g < lo_g - TOL
          or g > hi_g + TOL
          or b < lo_b - TOL
          or b > hi_b + TOL
        then
          res.mismatches = res.mismatches + 1
          res.first = res.first or { wx, wy }
        elseif not equals_a_texel then
          res.blended = res.blended + 1
        end
      end
    end
  end
  return res
end

-- Runs the whole fit-mode check: setup, exact nearest prescale, filtered
-- presentation and exact counts. Returns problems and log fields.
function M.run(s, canvas_px, pre_px, window_px)
  local problems = M.setup_problems(s)
  local vp = s.vp
  local pre = { checked = 0, mismatches = 0 }
  local res = {
    checked = 0,
    mismatches = 0,
    blended = 0,
    edge = 0,
    letterbox_checked = 0,
    letterbox_bad = 0,
  }
  local expected = { content = 0, edge = 0, letterbox = 0 }
  if #problems == 0 then
    local k = vp.prescale
    -- Step 1: the prescaled canvas is an exact nearest k-upscale.
    local pre_vp = { scale = k, x = 0, y = 0, w = s.canvas_w * k, h = s.canvas_h * k }
    pre = upscale_check.verify(canvas_px, s.canvas_w, s.canvas_h, pre_px, s.pre_w, s.pre_h, pre_vp)
    if pre.checked ~= s.pre_w * s.pre_h or pre.letterbox_checked ~= 0 then
      add(problems, "prescale_checked:%d!=%d", pre.checked, s.pre_w * s.pre_h)
    end
    if pre.mismatches ~= 0 or pre.letterbox_bad ~= 0 then
      add(problems, "prescale_mismatches:%d", pre.mismatches + pre.letterbox_bad)
    end
    -- Step 2: the linear-filtered presentation.
    expected = M.expected_counts(s.shot_w, s.shot_h, vp)
    res = M.verify(pre_px, s.pre_w, s.pre_h, k, window_px, s.shot_w, s.shot_h, vp)
    if res.checked ~= expected.content then
      add(problems, "pixels_checked:%d!=%d", res.checked, expected.content)
    end
    if res.edge ~= expected.edge then
      add(problems, "edge:%d!=%d", res.edge, expected.edge)
    end
    if res.letterbox_checked ~= expected.letterbox then
      add(problems, "letterbox_checked:%d!=%d", res.letterbox_checked, expected.letterbox)
    end
    if res.mismatches ~= 0 then
      add(problems, "mismatches:%d", res.mismatches)
    end
    if res.letterbox_bad ~= 0 then
      add(problems, "letterbox_bad:%d", res.letterbox_bad)
    end
    local ratio = vp.scale / k
    if ratio ~= math.floor(ratio) and res.blended == 0 then
      add(problems, "blended:0:expected_linear_filtering")
    end
  end
  local fields = {
    { "scale", ("%.5f"):format(vp.scale) },
    { "prescale", tostring(vp.prescale) },
    { "prescale_canvas", ("%sx%s"):format(tostring(s.pre_w), tostring(s.pre_h)) },
    { "prescale_dpi", ("%.2f"):format(s.pre_dpi or -1) },
    { "offset", ("%d,%d"):format(vp.x, vp.y) },
    { "prescale_checked", pre.checked },
    { "prescale_mismatches", pre.mismatches },
    { "pixels_checked", res.checked },
    { "expected_checked", expected.content },
    { "mismatches", res.mismatches },
    { "blended", res.blended },
    { "edge", res.edge },
    { "letterbox_checked", res.letterbox_checked },
    { "expected_letterbox", expected.letterbox },
    { "letterbox_bad", res.letterbox_bad },
  }
  return problems, fields
end

return M
