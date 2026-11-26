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

  describe("HiDPI: logical vs physical pixels (review P2-2)", function()
    it("scales in physical pixels: logical 1280x720 at DPI 2 is 4x, not 2x", function()
      local vp = viewport.compute(1280 * 2, 720 * 2, 640, 360, "integer")
      assert.are.equal(4, vp.scale)
      local lx, ly, ls = viewport.to_logical(vp, 2)
      assert.are.same({ 0, 0, 2 }, { lx, ly, ls })
    end)

    for _, case in ipairs({
      { dpi = 2, lw = 1512, lh = 982 }, -- 14" MacBook Pro default
      { dpi = 2, lw = 1440, lh = 900 },
      { dpi = 1.5, lw = 1280, lh = 720 }, -- Windows 150%
      { dpi = 1.25, lw = 1536, lh = 864 }, -- Windows 125% on 1920x1080
    }) do
      it(
        ("maps back to integer physical pixels at DPI %.2f (%dx%d logical)"):format(
          case.dpi,
          case.lw,
          case.lh
        ),
        function()
          local pw, ph = math.floor(case.lw * case.dpi), math.floor(case.lh * case.dpi)
          local vp = viewport.compute(pw, ph, 640, 360, "integer")
          local lx, ly, ls = viewport.to_logical(vp, case.dpi)
          local px, py, ps = lx * case.dpi, ly * case.dpi, ls * case.dpi
          assert.is_true(math.abs(px - math.floor(px + 0.5)) < 1e-9)
          assert.is_true(math.abs(py - math.floor(py + 0.5)) < 1e-9)
          assert.is_true(math.abs(ps - math.floor(ps + 0.5)) < 1e-9)
          assert.is_true(vp.w <= pw and vp.h <= ph)
        end
      )
    end
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
