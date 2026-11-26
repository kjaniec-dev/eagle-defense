local viewport = require("src.render.viewport")

describe("render.viewport", function()
  local cases = {
    -- window w, h, expected integer scale, x, y
    { 1280, 720, 2, 0, 0 },
    { 1920, 1080, 3, 0, 0 },
    { 2560, 1440, 4, 0, 0 },
    { 3840, 2160, 6, 0, 0 },
    { 1280, 800, 2, 0, 40 }, -- Steam Deck
    { 3024, 1964, 4, 232, 262 }, -- 14" MacBook Pro Retina (physical pixels)
    { 1440, 900, 2, 80, 90 },
    { 640, 360, 1, 0, 0 },
    { 500, 300, 1, -70, -30 }, -- smaller than the canvas: clamped to 1x
  }
  for _, c in ipairs(cases) do
    it(("integer mode %dx%d -> %dx"):format(c[1], c[2], c[3]), function()
      local vp = viewport.compute(c[1], c[2], 640, 360, "integer")
      assert.are.equal(c[3], vp.scale)
      assert.are.equal(c[4], vp.x)
      assert.are.equal(c[5], vp.y)
      assert.are.equal(640 * c[3], vp.w)
      assert.are.equal(360 * c[3], vp.h)
    end)
  end

  it("integer mode always yields whole-pixel offsets and scale", function()
    for w = 640, 4000, 37 do
      for h = 360, 2400, 41 do
        local vp = viewport.compute(w, h, 640, 360, "integer")
        assert.are.equal(math.floor(vp.scale), vp.scale)
        assert.are.equal(math.floor(vp.x), vp.x)
        assert.are.equal(math.floor(vp.y), vp.y)
        assert.is_true(vp.w <= w and vp.h <= h)
      end
    end
  end)

  it("fit mode fills one dimension and uses an integer prescale", function()
    local vp = viewport.compute(1366, 768, 640, 360, "fit")
    assert.is_true(math.abs(vp.scale - 2.1333333) < 1e-6)
    assert.are.equal(3, vp.prescale)
    assert.is_true(math.abs(vp.h - 768) < 1e-6)
  end)

  it("maps window pixels to canvas pixels", function()
    local vp = viewport.compute(1280, 800, 640, 360, "integer")
    assert.are.same({ 0, 0 }, { viewport.to_canvas(vp, 0, 40) })
    assert.are.same({ 639, 359 }, { viewport.to_canvas(vp, 1279, 759) })
    assert.is_nil(viewport.to_canvas(vp, 10, 10))
  end)

  it("cycles scale modes", function()
    assert.are.equal("fit", viewport.next_mode("integer"))
    assert.are.equal("integer", viewport.next_mode("fit"))
  end)

  it("rejects unknown modes", function()
    assert.has_error(function()
      viewport.compute(800, 600, 640, 360, "stretch")
    end)
  end)
end)
