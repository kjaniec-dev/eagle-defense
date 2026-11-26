-- Tests the LÖVE input adapter against a minimal fake `love` table.
local bindings = require("config.bindings")

local function fake_pad(id, held)
  return {
    held = held or {},
    axes = { leftx = 0, lefty = 0 },
    isGamepad = function()
      return true
    end,
    isConnected = function()
      return true
    end,
    getID = function()
      return id
    end,
    isGamepadDown = function(self, b)
      return self.held[b] == true
    end,
    getGamepadAxis = function(self, a)
      return self.axes[a]
    end,
  }
end

describe("input.devices (LÖVE adapter, fake love)", function()
  local saved_love, held_keys, joysticks, devices_mod

  before_each(function()
    saved_love = _G.love
    held_keys, joysticks = {}, {}
    _G.love = {
      keyboard = {
        isDown = function(k)
          return held_keys[k] == true
        end,
      },
      joystick = {
        getJoysticks = function()
          return joysticks
        end,
      },
    }
    package.loaded["src.input.devices"] = nil
    devices_mod = require("src.input.devices")
  end)

  after_each(function()
    _G.love = saved_love
  end)

  it("records bound key events in chronological order and clears them per sample", function()
    local d = devices_mod.new(bindings)
    d:keypressed("d", "d", false)
    d:keypressed("w", "w", false)
    d:keyreleased("d")
    held_keys.w = true
    local raw = d:sample()
    assert.are.same({
      { kind = "press", device = "key", name = "d" },
      { kind = "press", device = "key", name = "w" },
      { kind = "release", device = "key", name = "d" },
    }, raw.events)
    assert.are.same({ w = true }, raw.keys)
    assert.are.same({}, d:sample().events)
  end)

  it("ignores keyboard auto-repeat and unbound keys", function()
    local d = devices_mod.new(bindings)
    d:keypressed("w", "w", false)
    d:keypressed("w", "w", true)
    d:keypressed("w", "w", true)
    d:keypressed("x", "x", false)
    assert.are.equal(1, #d:sample().events)
  end)

  it("assigns pads to players in connection order and tags their events", function()
    local p1, p2, p3 = fake_pad(10), fake_pad(20), fake_pad(30)
    joysticks = { p1 }
    local d = devices_mod.new(bindings)
    d:joystick_added(p1) -- duplicate add is ignored
    d:joystick_added(p2)
    d:joystick_added(p3) -- a third pad is not assigned to a player
    d:gamepadpressed(p2, "dpup")
    d:gamepadpressed(p3, "dpup")
    d:gamepadreleased(p2, "dpup")
    local raw = d:sample()
    assert.are.same({
      { kind = "press", device = "pad", player = 2, name = "dpup" },
      { kind = "release", device = "pad", player = 2, name = "dpup" },
    }, raw.events)
  end)

  it("polls held pad buttons and stick axes", function()
    local p1 = fake_pad(1, { a = true, dpleft = true })
    p1.axes.leftx = 0.8
    joysticks = { p1 }
    local d = devices_mod.new(bindings)
    local raw = d:sample()
    assert.is_true(raw.pads[1].buttons.a)
    assert.is_true(raw.pads[1].buttons.dpleft)
    assert.are.equal(0.8, raw.pads[1].leftx)
  end)

  it("reassigns players after a pad is removed", function()
    local p1, p2 = fake_pad(1), fake_pad(2)
    joysticks = { p1, p2 }
    local d = devices_mod.new(bindings)
    d:joystick_removed(p1)
    d:gamepadpressed(p2, "a")
    assert.are.equal(1, d:sample().events[1].player)
  end)

  it("end-to-end with the mapper: D then W between ticks yields up", function()
    local mapper = require("src.input.mapper")
    local d = devices_mod.new(bindings)
    local m = mapper.new(bindings)
    d:keypressed("d", "d", false)
    d:keypressed("w", "w", false)
    held_keys.d, held_keys.w = true, true
    assert.are.equal("up", m:update(d:sample())[1].dir)
    d:keyreleased("w")
    held_keys.w = nil
    assert.are.equal("right", m:update(d:sample())[1].dir)
  end)
end)
