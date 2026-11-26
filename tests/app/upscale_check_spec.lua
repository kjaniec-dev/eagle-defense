local check = require("src.app.upscale_check")
local viewport = require("src.render.viewport")

-- A tiny 4x3 canvas with distinct colors per pixel.
local CW, CH = 4, 3
local function canvas(x, y)
  return x / CW, y / CH, 0.5
end

local function window_from(vp, f)
  return function(wx, wy)
    local cx = math.floor((wx - vp.x) / vp.scale)
    local cy = math.floor((wy - vp.y) / vp.scale)
    if cx >= 0 and cy >= 0 and cx < CW and cy < CH then
      return f(cx, cy, wx, wy)
    end
    return 0, 0, 0
  end
end

describe("app.upscale_check", function()
  local vp = viewport.compute(13, 9, CW, CH, "integer") -- scale 3, offset (0, 0)

  it("accepts an exact nearest-neighbour upscale with letterbox", function()
    local vp2 = viewport.compute(14, 11, CW, CH, "integer")
    local r = check.verify(canvas, CW, CH, window_from(vp2, canvas), 14, 11, vp2)
    assert.are.equal(CW * CH * vp2.scale * vp2.scale, r.checked)
    assert.are.equal(0, r.mismatches)
    assert.are.equal(0, r.letterbox_bad)
  end)

  it("detects a single wrong pixel (e.g. filtering or a half-pixel offset)", function()
    local win = window_from(vp, function(cx, cy, wx, wy)
      if wx == 4 and wy == 4 then
        return 1, 1, 1
      end
      return canvas(cx, cy)
    end)
    local r = check.verify(canvas, CW, CH, win, 13, 9, vp)
    assert.are.equal(1, r.mismatches)
    assert.are.same({ 4, 4 }, r.first)
  end)

  it("detects content bleeding into the letterbox", function()
    local win = function(wx, wy)
      if wx == 12 then
        return 1, 0, 0
      end
      return window_from(vp, canvas)(wx, wy)
    end
    local r = check.verify(canvas, CW, CH, win, 13, 9, vp)
    assert.are.equal(9, r.letterbox_bad)
  end)

  it("counts every letterbox pixel it checks", function()
    local vp2 = viewport.compute(14, 11, CW, CH, "integer")
    local r = check.verify(canvas, CW, CH, window_from(vp2, canvas), 14, 11, vp2)
    local e = check.expected_counts(CW, CH, 14, 11, vp2.scale)
    assert.are.equal(e.content, r.checked)
    assert.are.equal(e.letterbox, r.letterbox_checked)
    assert.are.equal(14 * 11, r.checked + r.letterbox_checked)
  end)

  it("refuses a viewport that is not canvas x scale", function()
    local bad = { scale = 3, x = 0, y = 0, w = CW * 3 + 1, h = CH * 3 }
    assert.has_error(function()
      check.verify(canvas, CW, CH, window_from(vp, canvas), 13, 9, bad)
    end)
    -- The PR #2 Retina defect: a 2x-density canvas readback (8x6 texels)
    -- verified against a viewport computed for the 4x3 canvas.
    local retina = viewport.compute(13, 9, CW, CH, "integer")
    assert.has_error(function()
      check.verify(canvas, CW * 2, CH * 2, window_from(retina, canvas), 13, 9, retina)
    end)
  end)
end)

-- Setup for the 640x360 canvas, as smoke_report builds it.
local function setup(over)
  local s = {
    canvas_w = 640,
    canvas_h = 360,
    canvas_dpi = 1,
    expected_w = 640,
    expected_h = 360,
    shot_w = 1600,
    shot_h = 1200,
    phys_w = 1600,
    phys_h = 1200,
  }
  s.vp = viewport.compute(s.shot_w, s.shot_h, 640, 360, "integer")
  for k, v in pairs(over or {}) do
    s[k] = v
  end
  return s
end

local function has(problems, prefix)
  for _, p in ipairs(problems) do
    if p:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

describe(
  "app.upscale_check setup (regressions for invalid viewport/canvas combinations)",
  function()
    it("accepts a consistent 640x360 canvas at 2x in a 1600x1200 framebuffer", function()
      assert.are.same({}, check.setup_problems(setup()))
    end)

    it("rejects the native Retina failure: a 1280x720 canvas at DPI 2", function()
      local p = check.setup_problems(setup({ canvas_w = 1280, canvas_h = 720, canvas_dpi = 2 }))
      assert.is_true(has(p, "canvas_pixels:1280x720!=640x360"))
      assert.is_true(has(p, "canvas_dpi:2!=1"))
      assert.is_true(has(p, "viewport:"))
    end)

    it("rejects fractional-DPI canvases (Windows 150 %)", function()
      local p = check.setup_problems(setup({ canvas_w = 960, canvas_h = 540, canvas_dpi = 1.5 }))
      assert.is_true(has(p, "canvas_pixels:960x540!=640x360"))
      assert.is_true(has(p, "canvas_dpi:1.5!=1"))
    end)

    it("rejects a screenshot that is not the physical framebuffer", function()
      local p = check.setup_problems(setup({ shot_w = 800, shot_h = 600 }))
      assert.is_true(has(p, "screenshot:800x600!=physical:1600x1200"))
    end)

    it("rejects a non-integer scale", function()
      local s = setup()
      s.vp = { scale = 2.5, x = 0, y = 150, w = 1600, h = 900 }
      assert.is_true(has(check.setup_problems(s), "scale:2.5:not_a_positive_integer"))
    end)

    it("rejects a viewport that does not equal canvas x scale", function()
      local s = setup()
      s.vp = { scale = 2, x = 160, y = 240, w = 1280, h = 722 }
      assert.is_true(has(check.setup_problems(s), "viewport:1280x722!=canvas_x_scale:1280x720"))
    end)

    it("rejects a viewport that leaves the window", function()
      local s = setup()
      s.vp = { scale = 2, x = 400, y = 240, w = 1280, h = 720 }
      assert.is_true(
        has(check.setup_problems(s), "viewport:400,240+1280x720:outside_window:1600x1200")
      )
      s.vp = { scale = 2, x = -1, y = 240, w = 1280, h = 720 }
      assert.is_true(has(check.setup_problems(s), "viewport:-1,240"))
    end)

    it("computes exact content and letterbox counts", function()
      local e = check.expected_counts(640, 360, 1600, 1200, 2)
      assert.are.equal(921600, e.content)
      assert.are.equal(1600 * 1200 - 921600, e.letterbox)
    end)

    it("rejects an incomplete or over-complete pixel pass", function()
      local e = { content = 100, letterbox = 20 }
      local ok = { checked = 100, letterbox_checked = 20, mismatches = 0, letterbox_bad = 0 }
      assert.are.same({}, check.result_problems(ok, e))
      local p = check.result_problems(
        { checked = 99, letterbox_checked = 20, mismatches = 0, letterbox_bad = 0 },
        e
      )
      assert.is_true(has(p, "pixels_checked:99!=100"))
      p = check.result_problems(
        { checked = 100, letterbox_checked = 21, mismatches = 0, letterbox_bad = 0 },
        e
      )
      assert.is_true(has(p, "letterbox_checked:21!=20"))
      p = check.result_problems(
        { checked = 100, letterbox_checked = 20, mismatches = 2, letterbox_bad = 1 },
        e
      )
      assert.is_true(has(p, "mismatches:2"))
      assert.is_true(has(p, "letterbox_bad:1"))
    end)

    it("run(): passes a correct upscale and skips pixels when the setup is wrong", function()
      local s = {
        canvas_w = CW,
        canvas_h = CH,
        canvas_dpi = 1,
        expected_w = CW,
        expected_h = CH,
        shot_w = 14,
        shot_h = 11,
        phys_w = 14,
        phys_h = 11,
      }
      s.vp = viewport.compute(14, 11, CW, CH, "integer")
      local problems, fields = check.run(s, canvas, window_from(s.vp, canvas))
      assert.are.same({}, problems)
      assert.is_true(#fields > 0)

      s.canvas_dpi = 2
      local calls = 0
      problems = check.run(s, canvas, function(x, y)
        calls = calls + 1
        return window_from(s.vp, canvas)(x, y)
      end)
      assert.is_true(has(problems, "canvas_dpi:2!=1"))
      assert.are.equal(0, calls)
    end)

    it("keeps the G0 comparison tolerance", function()
      assert.are.equal(1.5 / 255, check.TOL)
    end)
  end
)
