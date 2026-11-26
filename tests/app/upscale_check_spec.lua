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
end)
