local fit = require("src.app.fit_check")
local viewport = require("src.render.viewport")

-- A tiny 4x3 canvas with hard colour edges between texels.
local CW, CH = 4, 3
local COLORS = {
  { 0.1, 0.2, 0.3 },
  { 0.9, 0.1, 0.1 },
  { 0.2, 0.8, 0.4 },
  { 1.0, 1.0, 1.0 },
}
local function canvas(x, y)
  local c = COLORS[(x + y) % #COLORS + 1]
  return c[1], c[2], c[3]
end

-- The exact nearest k-upscale (the intended prescale canvas).
local function prescaled(k)
  return function(x, y)
    return canvas(math.floor(x / k), math.floor(y / k))
  end
end

-- What a GPU produces for the linear presentation step: bilinear sampling
-- of the prescaled canvas at each pixel centre, clamped at the borders.
local function bilinear_window(pre, pre_w, pre_h, k, vp)
  local ratio = vp.scale / k
  return function(wx, wy)
    local dx, dy = wx + 0.5 - vp.x, wy + 0.5 - vp.y
    if dx < 0 or dy < 0 or dx > vp.w or dy > vp.h then
      return 0, 0, 0
    end
    local u, v = dx / ratio - 0.5, dy / ratio - 0.5
    local x0, y0 = math.floor(u), math.floor(v)
    local fx, fy = u - x0, v - y0
    local function at(x, y)
      return pre(math.max(0, math.min(pre_w - 1, x)), math.max(0, math.min(pre_h - 1, y)))
    end
    local out = {}
    local a, b, c, d =
      { at(x0, y0) }, { at(x0 + 1, y0) }, { at(x0, y0 + 1) }, { at(x0 + 1, y0 + 1) }
    for i = 1, 3 do
      local top = a[i] * (1 - fx) + b[i] * fx
      local bottom = c[i] * (1 - fx) + d[i] * fx
      -- 8-bit quantisation, as in a real framebuffer readback.
      out[i] = math.floor((top * (1 - fy) + bottom * fy) * 255 + 0.5) / 255
    end
    return out[1], out[2], out[3]
  end
end

-- Nearest presentation (the regression the fit check must reject).
local function nearest_window(pre, pre_w, pre_h, k, vp)
  local ratio = vp.scale / k
  return function(wx, wy)
    local dx, dy = wx + 0.5 - vp.x, wy + 0.5 - vp.y
    if dx < 0 or dy < 0 or dx > vp.w or dy > vp.h then
      return 0, 0, 0
    end
    local x = math.min(pre_w - 1, math.floor(dx / ratio))
    local y = math.min(pre_h - 1, math.floor(dy / ratio))
    return pre(x, y)
  end
end

local function setup(win_w, win_h)
  local vp = viewport.compute(win_w, win_h, CW, CH, "fit")
  return {
    canvas_w = CW,
    canvas_h = CH,
    canvas_dpi = 1,
    expected_w = CW,
    expected_h = CH,
    pre_w = CW * vp.prescale,
    pre_h = CH * vp.prescale,
    pre_dpi = 1,
    shot_w = win_w,
    shot_h = win_h,
    phys_w = win_w,
    phys_h = win_h,
    vp = vp,
  }
end

local function has(problems, prefix)
  for _, p in ipairs(problems) do
    if p:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

describe("app.fit_check (sharp bilinear presentation)", function()
  -- 23x13 window: fit = min(5.75, 4.33) = 4.333 (non-integer), prescale 5.
  local s = setup(23, 13)
  local k = s.vp.prescale
  local pre = prescaled(k)

  it("uses a non-integer scale in this fixture", function()
    assert.are.equal(5, k)
    assert.is_true(s.vp.scale ~= math.floor(s.vp.scale))
  end)

  it("accepts a correct sharp-bilinear presentation with exact counts", function()
    local win = bilinear_window(pre, s.pre_w, s.pre_h, k, s.vp)
    local problems, fields = fit.run(s, canvas, pre, win)
    assert.are.same({}, problems)
    local r = fit.verify(pre, s.pre_w, s.pre_h, k, win, 23, 13, s.vp)
    local e = fit.expected_counts(23, 13, s.vp)
    assert.are.equal(e.content, r.checked)
    assert.are.equal(e.letterbox, r.letterbox_checked)
    assert.are.equal(23 * 13, r.checked + r.edge + r.letterbox_checked)
    assert.is_true(r.blended > 0)
    assert.is_true(#fields > 0)
  end)

  it("rejects nearest filtering in the presentation step", function()
    local win = nearest_window(pre, s.pre_w, s.pre_h, k, s.vp)
    assert.is_true(has(fit.run(s, canvas, pre, win), "blended:0:expected_linear_filtering"))
  end)

  it("rejects a colour outside the range of the neighbouring texels", function()
    local good = bilinear_window(pre, s.pre_w, s.pre_h, k, s.vp)
    local cx, cy = s.vp.x + 5, s.vp.y + 5
    local win = function(x, y)
      if x == cx and y == cy then
        return 0.5, 0.5, 0.0
      end
      return good(x, y)
    end
    assert.is_true(has(fit.run(s, canvas, pre, win), "mismatches:1"))
  end)

  it("rejects content bleeding into the letterbox", function()
    local good = bilinear_window(pre, s.pre_w, s.pre_h, k, s.vp)
    local win = function(x, y)
      if x == 0 then -- vp.x is 2: columns 0..1 are letterbox
        return 1, 0, 0
      end
      return good(x, y)
    end
    assert.are.equal(2, s.vp.x)
    assert.is_true(has(fit.run(s, canvas, pre, win), "letterbox_bad:13"))
  end)

  it("rejects a prescale canvas that is not an exact nearest upscale", function()
    local bad_pre = function(x, y)
      if x == 1 and y == 1 then
        return 0, 0, 0
      end
      return pre(x, y)
    end
    local win = bilinear_window(bad_pre, s.pre_w, s.pre_h, k, s.vp)
    assert.is_true(has(fit.run(s, canvas, bad_pre, win), "prescale_mismatches:1"))
  end)

  it("rejects a prescale canvas created at display DPI", function()
    local bad = setup(23, 13)
    bad.pre_w, bad.pre_h, bad.pre_dpi = bad.pre_w * 2, bad.pre_h * 2, 2
    local p = fit.setup_problems(bad)
    assert.is_true(has(p, "prescale_pixels:40x30!=20x15"))
    assert.is_true(has(p, "prescale_dpi:2!=1"))
  end)

  it("rejects a game canvas created at display DPI (shared check)", function()
    local bad = setup(23, 13)
    bad.canvas_w, bad.canvas_h, bad.canvas_dpi = CW * 2, CH * 2, 2
    local p = fit.setup_problems(bad)
    assert.is_true(has(p, "canvas_pixels:8x6!=4x3"))
    assert.is_true(has(p, "canvas_dpi:2!=1"))
    assert.is_true(has(p, "viewport:"))
  end)

  it("rejects a viewport outside the window and a non-integer prescale", function()
    local bad = setup(23, 13)
    bad.vp = { scale = bad.vp.scale, prescale = 5, x = 10, y = 0, w = bad.vp.w, h = bad.vp.h }
    assert.is_true(has(fit.setup_problems(bad), "viewport:10,0"))
    bad.vp.prescale = 4.5
    assert.is_true(has(fit.setup_problems(bad), "prescale:4.5:not_a_positive_integer"))
  end)

  it("counts pixel centres exactly on a viewport edge as edge pixels", function()
    -- 900x600 vs 640x360: no centre on an edge.
    local e = fit.expected_counts(900, 600, viewport.compute(900, 600, 640, 360, "fit"))
    assert.are.same({ content = 900 * 506, edge = 0, letterbox = 900 * 600 - 900 * 506 }, e)
    -- 1000x600: height 562.5, so the centre of the last row lies on the edge.
    e = fit.expected_counts(1000, 600, viewport.compute(1000, 600, 640, 360, "fit"))
    assert.are.same({ content = 1000 * 562, edge = 1000, letterbox = 1000 * 600 - 1000 * 563 }, e)
  end)
end)
