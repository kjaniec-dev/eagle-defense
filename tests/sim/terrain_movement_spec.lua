-- Movement and bullets over terrain (G2 plan §4, §6.1, §8): every
-- tank-blocking type stops a tank at contact, forest and ice do not block,
-- a snap into water turns the tank in place, bullets pass water, forest and
-- ice, and forest has no simulation effect at all.

local H = require("tests.sim.helpers")

local function new_world(opts)
  opts = opts or {}
  return H.world({
    arena = H.arena_data({}, H.entities({ 12, 20 }, { 0, 0 }, opts.dummies)),
    tuning = opts.tuning,
  })
end

describe("tanks over terrain", function()
  for _, kind in ipairs({ "block", "brick", "steel", "water" }) do
    it(kind .. " stops a tank exactly at contact", function()
      local w = new_world()
      H.fill(w, 0, 30, 51, 31, kind) -- bottom edge at y = 2048
      local p1 = w.tanks[1] -- at y = 2560
      H.run(w, 120, H.frame("up"))
      assert.are.equal(2048, p1.y)
    end)
  end

  for _, kind in ipairs({ "forest", "ice" }) do
    it(kind .. " does not block a tank", function()
      local w = new_world({ tuning = { ice_slide_distance = 0 } })
      H.fill(w, 0, 30, 51, 31, kind)
      local p1 = w.tanks[1]
      H.run(w, 100, H.frame("up"))
      assert.are.equal(2560 - 700, p1.y)
    end)
  end

  it("a snap that would overlap water is blocked and turns the tank in place", function()
    local w = new_world()
    local p1 = w.tanks[1]
    p1.x = 1216 -- 1216 = 1152 + 64: the snap tie goes left, to 1152
    H.fill(w, 18, 0, 18, 51, "water") -- cell column [1152, 1216)
    H.run(w, 1, H.frame("up"))
    assert.are.same({ 1216, 2560, "up" }, { p1.x, p1.y, p1.facing })
    H.run(w, 5, H.frame("up")) -- retried and blocked on every tick
    assert.are.same({ 1216, 2560 }, { p1.x, p1.y })
  end)
end)

describe("bullets over terrain", function()
  for _, kind in ipairs({ "water", "forest", "ice" }) do
    it("pass over " .. kind .. " with no event", function()
      local w = new_world()
      H.fill(w, 0, 10, 51, 35, kind)
      H.run(w, 1, H.frame({ press = true }))
      local events = H.run(w, 200, nil)
      local hits = H.of_type(events, "bullet_hit_solid")
      assert.are.equal(1, #hits)
      assert.are.equal("bound", hits[1].kind)
      assert.are.same({}, H.of_type(events, "terrain_destroyed"))
    end)
  end
end)

describe("forest neutrality (G2-D5)", function()
  -- The same inputs with forest and with forest replaced by empty give
  -- identical positions and events: forest has no simulation effect.
  local function play(with_forest)
    local w = new_world({ dummies = { { "target", 12, 4 }, { "turret", 2, 10, "right" } } })
    if with_forest then
      H.fill(w, 0, 20, 51, 45, "forest") -- y 1280 .. 2943: P1 starts inside it
    end
    H.fill(w, 0, 48, 51, 49, "brick") -- below the forest, P1 shoots it facing down
    local trace = {}
    local events = H.run(w, 600, function(tick)
      local dirs = { "up", "left", "down", "right" }
      local dir = dirs[math.floor(tick / 50) % 4 + 1]
      local dir2 = tick % 100 < 50 and "right" or "down"
      return H.frame({ dir = dir, press = tick % 23 == 1 }, { dir = dir2, press = tick % 31 == 1 })
    end)
    for _, t in ipairs(w.tanks) do
      trace[#trace + 1] = ("%d:%d,%d,%s,%s,%d"):format(
        t.id,
        t.x,
        t.y,
        t.facing,
        tostring(t.present),
        t.hits
      )
    end
    for _, e in ipairs(events) do
      local parts =
        { e.type, e.tick, e.tank or "", e.bullet or "", e.kind or "", e.x or "", e.y or "" }
      for i = 1, #parts do
        parts[i] = tostring(parts[i])
      end
      trace[#trace + 1] = table.concat(parts, " ")
    end
    return trace, w
  end

  it("gives identical positions and events with forest replaced by empty", function()
    local a, wa = play(true)
    local b = play(false)
    assert.are.same(b, a)
    local census = {}
    for _, line in ipairs(a) do
      local k = line:match("^(%S+)")
      census[k] = (census[k] or 0) + 1
    end
    assert.is_true(census.shot >= 10, "shots")
    assert.is_true(census.terrain_destroyed >= 1, "brick behind the forest destroyed")
    assert.is_true(census.tank_hit >= 1, "a dummy hit through the forest")
    assert.is_true(H.count(wa, "forest") > 0)
  end)

  it("never changes forest cells, even under fire", function()
    local _, w = play(true)
    assert.are.equal(52 * 26, H.count(w, "forest"))
  end)
end)
