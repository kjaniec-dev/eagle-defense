local mapper = require("src.input.mapper")
local bindings = require("config.bindings")

local function keys(...)
  local set = {}
  for _, k in ipairs({ ... }) do
    set[k] = true
  end
  return { keys = set }
end

describe("input.mapper", function()
  local m
  before_each(function()
    m = mapper.new(bindings)
  end)

  it("maps the P1 and P2 keyboard layouts independently", function()
    local f = m:update(keys("w", "space", "left"))
    assert.are.equal("up", f[1].dir)
    assert.is_true(f[1].fire)
    assert.are.equal("left", f[2].dir)
    assert.is_false(f[2].fire)
  end)

  it("gives no direction when nothing is held", function()
    local f = m:update(keys())
    assert.is_nil(f[1].dir)
    assert.is_nil(f[2].dir)
  end)

  it("last pressed direction wins, and releasing it restores the older one", function()
    assert.are.equal("up", m:update(keys("w"))[1].dir)
    assert.are.equal("right", m:update(keys("w", "d"))[1].dir)
    assert.are.equal("right", m:update(keys("w", "d"))[1].dir)
    assert.are.equal("up", m:update(keys("w"))[1].dir)
  end)

  it("resolves simultaneous presses in a deterministic order", function()
    local a = mapper.new(bindings):update(keys("a", "w"))[1].dir
    local b = mapper.new(bindings):update(keys("w", "a"))[1].dir
    assert.are.equal(a, b)
  end)

  it("reports fire_pressed only on the press edge", function()
    assert.is_true(m:update(keys("space"))[1].fire_pressed)
    local held = m:update(keys("space"))[1]
    assert.is_true(held.fire)
    assert.is_false(held.fire_pressed)
    m:update(keys())
    assert.is_true(m:update(keys("space"))[1].fire_pressed)
  end)

  it("reports pause_pressed on the edge", function()
    assert.is_true(m:update(keys("escape"))[1].pause_pressed)
    assert.is_false(m:update(keys("escape"))[1].pause_pressed)
  end)

  it("merges gamepad buttons with the keyboard for the same player", function()
    local f =
      m:update({ keys = { w = true }, pads = { [1] = { buttons = { dpright = true, a = true } } } })
    assert.are.equal("right", f[1].dir) -- the pad direction was pressed after w in DIRECTIONS order
    assert.is_true(f[1].fire)
  end)

  it("drives player 2 from the second pad", function()
    local f = m:update({ pads = { [2] = { buttons = { dpdown = true } } } })
    assert.is_nil(f[1].dir)
    assert.are.equal("down", f[2].dir)
  end)

  it("treats the left stick as a held direction", function()
    local f = m:update({ pads = { [1] = { buttons = {}, leftx = 0.9, lefty = 0.1 } } })
    assert.are.equal("right", f[1].dir)
    f = m:update({ pads = { [1] = { buttons = {}, leftx = 0, lefty = 0 } } })
    assert.is_nil(f[1].dir)
  end)

  it("returns a fresh frame table every tick", function()
    local a = m:update(keys("w"))
    local b = m:update(keys("w"))
    assert.are_not.equal(a, b)
    assert.are_not.equal(a[1], b[1])
  end)

  it("lists every bound key exactly once", function()
    local list = mapper.bound_keys(bindings)
    local seen = {}
    for _, k in ipairs(list) do
      assert.is_nil(seen[k])
      seen[k] = true
    end
    assert.is_true(seen.w and seen.space and seen.up and seen.rctrl)
  end)

  describe("stick_direction", function()
    local cfg = bindings.stick
    it("ignores the dead zone", function()
      assert.is_nil(mapper.stick_direction(0.2, -0.2, nil, cfg))
    end)
    it("picks the dominant axis", function()
      assert.are.equal("up", mapper.stick_direction(0.3, -0.8, nil, cfg))
      assert.are.equal("left", mapper.stick_direction(-0.8, 0.3, nil, cfg))
    end)
    it("holds the engaged direction until it drops below release (hysteresis)", function()
      assert.are.equal("right", mapper.stick_direction(0.3, 0, "right", cfg))
      assert.is_nil(mapper.stick_direction(0.2, 0, "right", cfg))
    end)
    it("does not flicker on a near-diagonal", function()
      assert.are.equal("right", mapper.stick_direction(0.70, 0.72, "right", cfg))
      assert.are.equal("down", mapper.stick_direction(0.50, 0.75, "right", cfg))
    end)
    it("switches immediately on reversal", function()
      assert.are.equal("left", mapper.stick_direction(-0.9, 0, "right", cfg))
    end)
  end)
end)
