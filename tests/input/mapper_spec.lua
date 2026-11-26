local mapper = require("src.input.mapper")
local bindings = require("config.bindings")

-- Snapshot helpers ---------------------------------------------------------

local function set(list)
  local s = {}
  for _, k in ipairs(list or {}) do
    s[k] = true
  end
  return s
end

-- held: list of held keys. events: list of "+key" / "-key" (press/release).
local function kb(held, events)
  local evs = {}
  for _, e in ipairs(events or {}) do
    evs[#evs + 1] = {
      kind = e:sub(1, 1) == "+" and "press" or "release",
      device = "key",
      name = e:sub(2),
    }
  end
  return { keys = set(held), events = evs }
end

local function pad_ev(kind, player, name)
  return { kind = kind, device = "pad", player = player, name = name }
end

describe("input.mapper", function()
  local m
  before_each(function()
    m = mapper.new(bindings)
  end)

  it("maps the P1 and P2 keyboard layouts independently", function()
    local f = m:update(kb({ "w", "space", "left" }, { "+w", "+space", "+left" }))
    assert.are.equal("up", f[1].dir)
    assert.is_true(f[1].fire)
    assert.are.equal("left", f[2].dir)
    assert.is_false(f[2].fire)
  end)

  it("gives no direction when nothing is held", function()
    local f = m:update(kb({}))
    assert.is_nil(f[1].dir)
    assert.is_nil(f[2].dir)
  end)

  describe("last pressed wins with chronological events (review P2-1)", function()
    it("D then W between two ticks -> up", function()
      assert.are.equal("up", m:update(kb({ "d", "w" }, { "+d", "+w" }))[1].dir)
    end)

    it("W then D between two ticks -> right", function()
      assert.are.equal("right", m:update(kb({ "d", "w" }, { "+w", "+d" }))[1].dir)
    end)

    it("A then S then D in one interval -> right, and releasing restores S, then A", function()
      assert.are.equal("right", m:update(kb({ "a", "s", "d" }, { "+a", "+s", "+d" }))[1].dir)
      assert.are.equal("down", m:update(kb({ "a", "s" }, { "-d" }))[1].dir)
      assert.are.equal("left", m:update(kb({ "a" }, { "-s" }))[1].dir)
      assert.is_nil(m:update(kb({}, { "-a" }))[1].dir)
    end)

    it("releasing the latest direction restores the previously held one", function()
      assert.are.equal("up", m:update(kb({ "w" }, { "+w" }))[1].dir)
      assert.are.equal("right", m:update(kb({ "w", "d" }, { "+d" }))[1].dir)
      assert.are.equal("right", m:update(kb({ "w", "d" }))[1].dir)
      assert.are.equal("up", m:update(kb({ "w" }, { "-d" }))[1].dir)
    end)

    it("re-pressing an older held direction promotes it again", function()
      m:update(kb({ "w" }, { "+w" }))
      m:update(kb({ "w", "d" }, { "+d" }))
      -- W released and pressed again within one interval while D is held.
      assert.are.equal("up", m:update(kb({ "w", "d" }, { "-w", "+w" }))[1].dir)
    end)

    it("uses the fixed tie-break order for polled-only simultaneous input", function()
      -- No events (e.g. a direction already held when the app starts): up < down < left < right.
      local a = mapper.new(bindings):update(kb({ "a", "w" }))[1].dir
      local b = mapper.new(bindings):update(kb({ "w", "a" }))[1].dir
      assert.are.equal("left", a)
      assert.are.equal(a, b)
    end)
  end)

  describe("latching and repeats (review P2-1)", function()
    it("a tap (press + release within one interval) registers for exactly one tick", function()
      m:update(kb({ "w" }, { "+w" }))
      assert.are.equal("right", m:update(kb({ "w" }, { "+d", "-d" }))[1].dir)
      assert.are.equal("up", m:update(kb({ "w" }))[1].dir)
    end)

    it("a fire tap within one interval yields fire and fire_pressed once", function()
      local f = m:update(kb({}, { "+space", "-space" }))
      assert.is_true(f[1].fire)
      assert.is_true(f[1].fire_pressed)
      f = m:update(kb({}))
      assert.is_false(f[1].fire)
      assert.is_false(f[1].fire_pressed)
    end)

    it(
      "reports fire_pressed only on new presses, including release+press within one interval",
      function()
        assert.is_true(m:update(kb({ "space" }, { "+space" }))[1].fire_pressed)
        local held = m:update(kb({ "space" }))[1]
        assert.is_true(held.fire)
        assert.is_false(held.fire_pressed)
        assert.is_true(m:update(kb({ "space" }, { "-space", "+space" }))[1].fire_pressed)
      end
    )

    it("duplicate press events do not duplicate stack entries", function()
      m:update(kb({ "w", "d" }, { "+w", "+d", "+d" }))
      assert.are.equal("up", m:update(kb({ "w" }, { "-d" }))[1].dir)
      assert.is_nil(m:update(kb({}, { "-w" }))[1].dir)
    end)

    it("reports pause_pressed on the press edge", function()
      assert.is_true(m:update(kb({ "escape" }, { "+escape" }))[1].pause_pressed)
      assert.is_false(m:update(kb({ "escape" }))[1].pause_pressed)
    end)

    it("ignores unbound keys", function()
      local f = m:update(kb({ "x" }, { "+x" }))
      assert.is_nil(f[1].dir)
      assert.is_false(f[1].fire)
    end)
  end)

  describe("keyboard and gamepad together (review P2-1)", function()
    it("a later pad press overrides a held key, and releasing it restores the key", function()
      m:update(kb({ "w" }, { "+w" }))
      local f = m:update({
        keys = set({ "w" }),
        pads = { [1] = { buttons = set({ "dpright" }) } },
        events = { pad_ev("press", 1, "dpright") },
      })
      assert.are.equal("right", f[1].dir)
      f = m:update({
        keys = set({ "w" }),
        pads = { [1] = { buttons = {} } },
        events = { pad_ev("release", 1, "dpright") },
      })
      assert.are.equal("up", f[1].dir)
    end)

    it("a later key press overrides a held pad direction", function()
      m:update({
        pads = { [1] = { buttons = set({ "dpdown" }) } },
        events = { pad_ev("press", 1, "dpdown") },
      })
      local f = m:update({
        keys = set({ "a" }),
        pads = { [1] = { buttons = set({ "dpdown" }) } },
        events = { { kind = "press", device = "key", name = "a" } },
      })
      assert.are.equal("left", f[1].dir)
    end)

    it("orders mixed key and pad events within one interval", function()
      local f = m:update({
        keys = set({ "w" }),
        pads = { [1] = { buttons = set({ "dpleft" }) } },
        events = { pad_ev("press", 1, "dpleft"), { kind = "press", device = "key", name = "w" } },
      })
      assert.are.equal("up", f[1].dir)
    end)

    it("pad events for player 2 only affect player 2", function()
      local f = m:update({
        pads = { [2] = { buttons = set({ "dpdown", "a" }) } },
        events = { pad_ev("press", 2, "dpdown"), pad_ev("press", 2, "a") },
      })
      assert.is_nil(f[1].dir)
      assert.is_false(f[1].fire)
      assert.are.equal("down", f[2].dir)
      assert.is_true(f[2].fire_pressed)
    end)

    it("a stick change in the same interval counts after the digital events", function()
      m:update(kb({}))
      local f = m:update({
        keys = set({ "w" }),
        pads = { [1] = { buttons = {}, leftx = 0.9, lefty = 0 } },
        events = { { kind = "press", device = "key", name = "w" } },
      })
      assert.are.equal("right", f[1].dir)
      f = m:update({ keys = set({ "w" }), pads = { [1] = { buttons = {}, leftx = 0, lefty = 0 } } })
      assert.are.equal("up", f[1].dir)
    end)
  end)

  describe("replay-friendly InputFrame", function()
    it("contains only plain fields and is a fresh table every tick", function()
      local a = m:update(kb({ "w" }, { "+w" }))
      local b = m:update(kb({ "w" }))
      assert.are_not.equal(a, b)
      assert.are_not.equal(a[1], b[1])
      for _, pf in ipairs(a) do
        for k, v in pairs(pf) do
          assert.is_truthy(
            ({ dir = true, fire = true, fire_pressed = true, pause_pressed = true })[k]
          )
          assert.is_truthy(type(v) == "string" or type(v) == "boolean")
        end
      end
    end)

    it("produces identical frames for identical snapshot sequences", function()
      local seq = {
        kb({ "w" }, { "+w" }),
        kb({ "w", "d" }, { "+d" }),
        kb({ "d" }, { "-w", "+space", "-space" }),
        kb({}, { "-d" }),
      }
      local m1, m2 = mapper.new(bindings), mapper.new(bindings)
      for _, raw in ipairs(seq) do
        assert.are.same(m1:update(raw), m2:update(raw))
      end
    end)
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
