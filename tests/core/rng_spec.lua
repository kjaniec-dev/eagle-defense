local rng_mod = require("src.core.rng")

describe("core.rng", function()
  it("matches the reference xorshift32 (13,17,5) sequence", function()
    local r = rng_mod.new(1)
    -- Reference values computed by hand from the xorshift32 definition.
    assert.are.equal(270369, r:next_u32())
    assert.are.equal(67634689, r:next_u32())
    assert.are.equal(2647435461, r:next_u32())
  end)

  it("is deterministic for equal seeds and differs for different seeds", function()
    local a, b, c = rng_mod.new(12345), rng_mod.new(12345), rng_mod.new(54321)
    local same, diff = true, false
    for _ = 1, 1000 do
      local va, vb, vc = a:next_u32(), b:next_u32(), c:next_u32()
      same = same and va == vb
      diff = diff or va ~= vc
    end
    assert.is_true(same)
    assert.is_true(diff)
  end)

  it("never gets stuck on a zero seed", function()
    local r = rng_mod.new(0)
    assert.are_not.equal(0, r:next_u32())
  end)

  it("accepts seeds at and above 2^31", function()
    local r = rng_mod.new(2 ^ 32 - 1)
    local v = r:next_u32()
    assert.is_true(v >= 0 and v < 2 ^ 32)
  end)

  it("range() stays inclusive and covers every value", function()
    local r = rng_mod.new(7)
    local seen = {}
    for _ = 1, 2000 do
      local v = r:range(-2, 3)
      assert.is_true(v >= -2 and v <= 3 and v == math.floor(v))
      seen[v] = true
    end
    for v = -2, 3 do
      assert.is_true(seen[v], "value " .. v .. " never produced")
    end
  end)

  it("range() with a single value always returns it", function()
    local r = rng_mod.new(9)
    for _ = 1, 10 do
      assert.are.equal(4, r:range(4, 4))
    end
  end)

  it("chance() respects the 0 and 1 extremes", function()
    local r = rng_mod.new(3)
    for _ = 1, 100 do
      assert.is_false(r:chance(0, 10))
      assert.is_true(r:chance(10, 10))
    end
  end)

  it("round-trips its state", function()
    local r = rng_mod.new(99)
    r:next_u32()
    local saved = r:get_state()
    local expected = { r:next_u32(), r:next_u32(), r:next_u32() }
    local restored = rng_mod.new(1)
    restored:set_state(saved)
    assert.are.same(expected, { restored:next_u32(), restored:next_u32(), restored:next_u32() })
  end)
end)
