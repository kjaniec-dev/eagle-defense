-- The G0 debug sandbox is not gameplay, but its pure stepping proves the
-- input -> fixed tick -> state path. It also fixes the smoke-test
-- expectations used by tools/smoke.sh.
local sandbox = require("src.app.states.sandbox")
local args = require("src.app.args")
local geo = require("config.geometry")

describe("app.states.sandbox (debug scene)", function()
  it("moves markers by SPEED per tick in the input direction", function()
    local m = sandbox.initial_markers()
    local x0, y0 = m[1].x, m[1].y
    sandbox.step_markers(m, { { dir = "right" }, { dir = nil } })
    assert.are.equal(x0 + sandbox.SPEED, m[1].x)
    assert.are.equal(y0, m[1].y)
    assert.are.equal("right", m[1].facing)
  end)

  it("keeps markers inside the battlefield", function()
    local m = sandbox.initial_markers()
    for _ = 1, 1000 do
      sandbox.step_markers(m, { { dir = "left" }, { dir = "down" } })
    end
    assert.are.equal(geo.FIELD_X * geo.SUB, m[1].x)
    assert.are.equal((geo.FIELD_Y + geo.FIELD_PX - geo.TILE) * geo.SUB, m[2].y)
  end)

  it("ends the 120-tick scripted smoke run at known positions", function()
    local m = sandbox.initial_markers()
    for tick = 1, 120 do
      sandbox.step_markers(m, args.smoke_frame(tick))
    end
    assert.are.same({ 5600, 4992 }, { m[1].x, m[1].y })
    assert.are.same({ 4256, 3552 }, { m[2].x, m[2].y })
  end)

  it("uses only integer subpixel positions", function()
    local m = sandbox.initial_markers()
    for tick = 1, 200 do
      sandbox.step_markers(m, args.smoke_frame(tick))
      for _, mk in ipairs(m) do
        assert.are.equal(math.floor(mk.x), mk.x)
        assert.are.equal(math.floor(mk.y), mk.y)
      end
    end
  end)
end)
