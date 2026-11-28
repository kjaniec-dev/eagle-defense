-- G2 terrain data: codes and properties, map characters, the tuning
-- additions, the hash extension rule and terrain invariant 9 (G2 plan §3,
-- §9, §10).

local terrain = require("src.sim.terrain")
local tuning = require("src.sim.tuning")
local world = require("src.sim.world")
local sim = require("src.sim.sim")
local H = require("tests.sim.helpers")

describe("terrain table", function()
  it("has the G2-D1 codes, names and map characters", function()
    local expect = {
      { 0, "empty", "." },
      { 1, "block", "X" },
      { 2, "brick", "B" },
      { 3, "steel", "S" },
      { 4, "water", "W" },
      { 5, "forest", "F" },
      { 6, "ice", "I" },
    }
    assert.are.equal(#expect, terrain.COUNT)
    for _, e in ipairs(expect) do
      local code, name, char = e[1], e[2], e[3]
      assert.are.equal(name, terrain.TYPES[code].name)
      assert.are.equal(code, terrain.CODE[name])
      assert.are.equal(code, terrain.CHAR[char])
      assert.are.equal(name, terrain.NAME[code + 1])
    end
    assert.are.equal(0, terrain.EMPTY)
  end)

  it("has the property table of G2 plan §3", function()
    -- name -> { blocks_tanks, blocks_bullets, destroy, slippery, layer }
    local expect = {
      empty = { false, false, false, false, "ground" },
      block = { true, true, false, false, "ground" },
      brick = { true, true, "brick", false, "ground" },
      steel = { true, true, "steel", false, "ground" },
      water = { true, false, false, false, "ground" },
      forest = { false, false, false, false, "over" },
      ice = { false, false, false, true, "ground" },
    }
    for name, p in pairs(expect) do
      local c = terrain.CODE[name] + 1
      assert.are.same(p, {
        terrain.BLOCKS_TANKS[c],
        terrain.BLOCKS_BULLETS[c],
        terrain.DESTROY[c],
        terrain.SLIPPERY[c],
        terrain.TYPES[c - 1].layer,
      }, name)
      assert.are.equal(p[5] == "over", terrain.OVER[c], name)
    end
  end)

  it("box_hits tests the given property and returns the lowest cell index", function()
    local w = H.world({ arena = H.arena_data({}, H.entities({ 0, 24 }, { 24, 24 })) })
    H.set(w, 11, 10, "water")
    H.set(w, 10, 11, "brick")
    local box = { 640, 640, 128, 128 } -- cells 10..11 x 10..11
    local hit, i = terrain.box_hits(w.cells, box[1], box[2], box[3], box[4], terrain.BLOCKS_TANKS)
    assert.is_true(hit)
    assert.are.equal(H.idx(11, 10), i) -- water, row 10 comes first
    hit, i = terrain.box_hits(w.cells, box[1], box[2], box[3], box[4], terrain.BLOCKS_BULLETS)
    assert.is_true(hit)
    assert.are.equal(H.idx(10, 11), i) -- water does not block bullets
    H.set(w, 11, 10, "forest")
    H.set(w, 10, 11, "ice")
    assert.is_false(
      (terrain.box_hits(w.cells, box[1], box[2], box[3], box[4], terrain.BLOCKS_TANKS))
    )
    -- half-open: a box touching the cell does not overlap it
    H.set(w, 12, 10, "steel")
    assert.is_false((terrain.box_hits(w.cells, 640, 640, 128, 64, terrain.BLOCKS_TANKS)))
  end)
end)

describe("G2 tuning additions", function()
  local cfg = require("config.tuning")

  it("commits the G2 defaults with their provenance tags (brick: owner tuning)", function()
    local expect = {
      brick_strip_cells = { 4, "TUNED (owner, 2026-11-28)" },
      brick_strip_depth = { 2, "TUNED (owner, 2026-11-28)" },
      steel_break_level = { 3, "DOC" },
      ice_slide_distance = { 192, "UNV" },
    }
    for key, e in pairs(expect) do
      assert.are.same(e, { cfg.entries[key][1], cfg.entries[key][2] }, key)
    end
  end)

  it("validates the enumerated and ranged keys", function()
    local v = tuning.load().values
    local function bad(key, value)
      local c = tuning.copy(v)
      c[key] = value
      return tuning.check_values(c) == nil
    end
    assert.is_true(bad("brick_strip_cells", 3))
    assert.is_true(bad("brick_strip_cells", 1))
    assert.is_false(bad("brick_strip_cells", 4))
    assert.is_true(bad("brick_strip_depth", 3))
    assert.is_false(bad("brick_strip_depth", 2))
    assert.is_true(bad("steel_break_level", 0))
    assert.is_true(bad("steel_break_level", 4))
    assert.is_false(bad("steel_break_level", 1))
    assert.is_true(bad("ice_slide_distance", -1))
    assert.is_true(bad("ice_slide_distance", 513))
    assert.is_false(bad("ice_slide_distance", 0))
    assert.is_true(bad("ice_slide_distance", 1.5))
  end)

  it("keeps the approved G1 tuning 7/17/34 untouched", function()
    local v = tuning.load().values
    assert.are.same({ 7, 17, 34 }, { v.player_speed, v.bullet_speed_normal, v.bullet_speed_fast })
  end)
end)

describe("hash extension rule (G2 plan §10)", function()
  local function base()
    local w = H.world({ arena = H.arena_data({}, H.entities({ 0, 24 }, { 24, 24 })) })
    H.add_bullet(w, 1, 100, 100, "up", 17)
    return w
  end

  for _, case in ipairs({
    {
      "ice_dir",
      function(w)
        w.tanks[1].ice_dir = "up"
      end,
    },
    {
      "slide_dir + slide_rem",
      function(w)
        w.tanks[1].slide_dir, w.tanks[1].slide_rem = "left", 50
      end,
    },
    {
      "slide_rem",
      function(w)
        w.tanks[1].slide_dir, w.tanks[1].slide_rem = "left", 51
      end,
    },
    {
      "bullet power",
      function(w)
        w.bullets[1].power = true
      end,
    },
  }) do
    it(case[1] .. " changes the hash when set and not when at its default", function()
      local w = base()
      local h0 = sim.hash(w)
      local w2 = base()
      w2.tanks[1].slide_dir, w2.tanks[1].slide_rem = "left", 50
      local slide50 = sim.hash(w2)
      case[2](w)
      local h1 = sim.hash(w)
      assert.are_not.equal(h0, h1)
      if case[1] == "slide_rem" then
        assert.are_not.equal(slide50, h1) -- the remaining distance is hashed too
      end
      -- back to the defaults: the G1 hash again
      local t, b = w.tanks[1], w.bullets[1]
      t.ice_dir, t.slide_dir, t.slide_rem, b.power = nil, nil, 0, nil
      assert.are.equal(h0, sim.hash(w))
    end)
  end

  it("does not hash player_level itself, only the resulting tank level", function()
    local data = H.arena_data({}, H.entities({ 0, 24 }, { 24, 24 }))
    local a = H.world({ arena = data, player_level = 0 })
    local b = H.world({ arena = data, player_level = 0 })
    b.player_level = 3 -- an initial condition, like the tuning
    assert.are.equal(sim.hash(a), sim.hash(b))
    local c = H.world({ arena = data, player_level = 3 })
    assert.are.same({ 3, 3 }, { c.tanks[1].level, c.tanks[2].level })
    assert.are_not.equal(sim.hash(a), sim.hash(c))
  end)
end)

describe("terrain invariant 9", function()
  it("allows brick or steel to become empty, and nothing else", function()
    local w = H.world({ arena = H.arena_data({}, H.entities({ 0, 24 }, { 24, 24 })) })
    H.set(w, 5, 5, "brick")
    H.set(w, 6, 5, "steel")
    H.set(w, 7, 5, "water")
    local prev = world.copy_cells(w.cells)
    H.set(w, 5, 5, "empty")
    H.set(w, 6, 5, "empty")
    assert.are.same({}, world.terrain_violations(prev, w.cells))
    -- the invariant-9 mutation: an empty cell going back to brick
    prev = world.copy_cells(w.cells)
    H.set(w, 5, 5, "brick")
    local v = world.terrain_violations(prev, w.cells)
    assert.are.equal(1, #v)
    assert.matches("cell " .. H.idx(5, 5) .. " changed from empty to brick", v[1], 1, true)
    -- water never changes, brick never becomes steel
    prev = world.copy_cells(w.cells)
    H.set(w, 7, 5, "empty")
    H.set(w, 5, 5, "steel")
    assert.are.equal(2, #world.terrain_violations(prev, w.cells))
  end)

  it("is reported by the scenario runner", function()
    local w = H.world({ arena = H.arena_data({}, H.entities({ 0, 24 }, { 24, 24 })) })
    local real = sim.step
    local ok, err = pcall(function()
      sim.step = function(world_, frame)
        real(world_, frame)
        H.set(world_, 30, 30, "brick") -- restoration is not allowed in G2
      end
      H.run(w, 1, nil)
    end)
    sim.step = real
    assert.is_false(ok)
    assert.matches("changed from empty to brick", err)
  end)
end)
