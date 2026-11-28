-- G2 terrain goldens (G2 plan §14): each golden exercises the behavior it
-- is named for, and arena identity is enforced (clarification C3): legacy
-- G1 headers stay valid, G2 replays need a matching arena_id, and golden
-- regeneration never bypasses a mismatch.

local fs = require("tools.lib.fs")
local serialize = require("src.core.serialize")
local replay = require("src.sim.replay")
local tuning = require("src.sim.tuning")
local terrain = require("src.sim.terrain")
local move = require("src.sim.move")
local arena = require("src.sim.arena")
local level = require("src.sim.level")
local levels = require("tools.lib.levels")
local world = require("src.sim.world")
local update_goldens = require("tools.update_goldens")

local DIR = "tests/fixtures/replays/"
local ACTIVE = tuning.load()
local OPTS = { resolve_arena = levels.read_arena }
local T = 256

local function load(name)
  return assert(serialize.decode(assert(fs.read(DIR .. name .. ".lua"))))
end

-- True when the 1 u-expanded box of tank t touches a cell of `kind` (a tank
-- never overlaps tank-blocking cells, so any overlap is contact).
local function touching(w, t, kind)
  local code = terrain.CODE[kind]
  local prop = {}
  for c = 0, terrain.COUNT - 1 do
    prop[c + 1] = c == code
  end
  return (terrain.box_hits(w.cells, t.x - 1, t.y - 1, T + 2, T + 2, prop))
end

-- Replays a golden and observes it: event counts, slide endings by reason,
-- forest crossings, contacts, and tanks inside originally-brick cells.
local function observe(name)
  local r = load(name)
  local built = level.load_arena(r.arena, levels.read_arena)
  local original = world.copy_cells(built.cells)
  local o = {
    counts = {},
    destroyed = { brick = 0, steel = 0 },
    brick_events = {},
    slide_end = {},
    forest = false,
    touched = {},
    through_dug = false,
    spawn_pairs = 0,
    block_cells = {},
  }
  local prev = {}
  local res = assert(replay.run(r, ACTIVE, {
    resolve_arena = levels.read_arena,
    on_tick = function(w, tick, events)
      local spawn_hits = {}
      for _, e in ipairs(events) do
        o.counts[e.type] = (o.counts[e.type] or 0) + 1
        if e.type == "terrain_destroyed" then
          o.destroyed[e.terrain] = o.destroyed[e.terrain] + #e.cells
          if e.terrain == "brick" then
            o.brick_events[#o.brick_events + 1] = #e.cells
          end
        elseif e.type == "bullet_hit_solid" and e.at_spawn and e.terrain == "brick" then
          spawn_hits[#spawn_hits + 1] = e
        end
      end
      -- two muzzle impacts of different players on the same tick
      if #spawn_hits >= 2 then
        o.spawn_pairs = o.spawn_pairs + 1
      end
      local n = 0
      for i = 1, #w.cells do
        if w.cells[i] == terrain.CODE.block then
          n = n + 1
        end
      end
      o.block_cells[#o.block_cells + 1] = n
      for i = 1, 2 do
        local t = w.tanks[i]
        local p = prev[i]
        if p and p.slide_dir and not t.slide_dir and t.present then
          local moved = math.abs(t.x - p.x) + math.abs(t.y - p.y)
          local reason
          if not move.on_ice(w, { x = p.x, y = p.y }) then
            reason = "edge"
          elseif moved == 0 then
            reason = "contact"
          elseif moved == p.slide_rem then
            reason = "distance"
          else
            reason = "cancel"
          end
          o.slide_end[reason] = (o.slide_end[reason] or 0) + 1
        end
        if t.present then
          if terrain.box_hits(w.cells, t.x, t.y, T, T, terrain.OVER) then
            o.forest = true
          end
          for _, kind in ipairs({ "water", "brick", "steel" }) do
            if touching(w, t, kind) then
              o.touched[kind] = true
            end
          end
          if terrain.box_hits(original, t.x, t.y, T, T, terrain.BLOCKS_TANKS) then
            o.through_dug = true -- inside cells that were brick at the start
          end
        end
        prev[i] = { x = t.x, y = t.y, slide_dir = t.slide_dir, slide_rem = t.slide_rem }
      end
      assert(tick == w.tick)
    end,
  }))
  return o, res
end

describe("G2 terrain goldens", function()
  it("all record the terrain arena's id, in the terrain arena", function()
    local id = arena.id(level.load_arena("g2_terrain", levels.read_arena))
    for _, name in ipairs({
      "terrain_tour",
      "brick_demolition",
      "steel_and_power",
      "terrain_stress",
    }) do
      local r = load(name)
      assert.are.same({ "g2_terrain", id }, { r.arena, r.arena_id }, name)
    end
    assert.are.equal(3, load("steel_and_power").player_level)
    assert.are.equal(3, load("terrain_stress").player_level)
  end)

  it(
    "terrain_tour: slides end by distance, at contact and at the ice edge; forest; contacts",
    function()
      local o = observe("terrain_tour")
      assert.is_nil(o.counts.tank_hit) -- players never shoot; the turret never reaches them
      assert.is_true((o.slide_end.contact or 0) >= 2, "slides ending at contact (steel, water)")
      assert.is_true((o.slide_end.edge or 0) >= 1, "slide ending at the ice edge")
      assert.is_true((o.slide_end.distance or 0) >= 2, "slides ending by distance")
      assert.is_true(o.forest, "forest crossed")
      assert.is_true(o.touched.water and o.touched.brick and o.touched.steel, "contacts")
    end
  )

  it(
    "brick_demolition: >= 20 cells, muzzle impacts, a same-tick pair, a tank through a dug opening",
    function()
      local o = observe("brick_demolition")
      assert.is_true(o.counts.terrain_destroyed >= 20)
      assert.is_true(o.destroyed.brick >= 40)
      assert.are.equal(0, o.destroyed.steel)
      assert.is_true(o.spawn_pairs >= 1, "P1 and P2 point-blank at one wall on the same tick")
      assert.is_true(o.through_dug, "a tank passes through a dug opening")
      assert.is_true((o.counts.tank_hit or 0) >= 1, "the target behind the 1/2-tile wall")
      for _, n in ipairs(o.brick_events) do
        assert.is_true(n <= 2) -- the 2 x 1 strip
      end
    end
  )

  it("steel_and_power: power breaks steel, block never breaks, brick strip unchanged", function()
    local o = observe("steel_and_power")
    assert.is_true(o.counts.terrain_destroyed >= 2)
    assert.is_true(o.destroyed.steel >= 16, "two shots' worth of 2 x 2 steel blocks")
    for _, n in ipairs(o.block_cells) do
      assert.are.equal(o.block_cells[1], n) -- constant on every tick
    end
    assert.are.equal(16, o.block_cells[1]) -- the 1-tile X block
    assert.is_true(#o.brick_events >= 4)
    for _, n in ipairs(o.brick_events) do
      assert.is_true(n <= 2, "brick strip is the same at level 3")
    end
  end)

  it("terrain_stress: >= 200 shots and >= 50 destroyed cells, invariants on every tick", function()
    local o = observe("terrain_stress")
    assert.is_true(o.counts.shot >= 200)
    assert.is_true(o.destroyed.brick + o.destroyed.steel >= 50)
  end)
end)

describe("replay arena identity (clarification C3)", function()
  it("accepts legacy G1 headers without arena_id for config arenas", function()
    local r = load("movement_tour")
    assert.is_nil(r.arena_id)
    assert.is_true(replay.verify(r, ACTIVE))
    -- with the right id it is accepted too
    r.arena_id = arena.id(arena.load("g1_arena"))
    assert.is_true(replay.verify(r, ACTIVE))
  end)

  it("refuses a mismatching arena_id in either format, naming both ids", function()
    for _, name in ipairs({ "movement_tour", "brick_demolition" }) do
      local r = load(name)
      local want = arena.id(level.load_arena(r.arena, levels.read_arena))
      r.arena_id = "deadbeef"
      local res, err = replay.run(r, ACTIVE, OPTS)
      assert.is_nil(res)
      assert.matches("arena_id mismatch", err)
      assert.matches("deadbeef", err)
      assert.matches(want, err)
    end
  end)

  it("refuses a level-format replay without arena_id", function()
    local r = load("terrain_tour")
    r.arena_id = nil
    local res, err = replay.run(r, ACTIVE, OPTS)
    assert.is_nil(res)
    assert.matches("arena_id required", err)
  end)

  it("refuses a level-format replay when the arena file changed", function()
    local r = load("terrain_tour")
    local text = assert(levels.read_arena("g2_terrain"))
    local changed = text:gsub('"%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%.%."', function(m)
      return m:sub(1, 26) .. 'B"'
    end, 1)
    assert.are_not.equal(text, changed)
    local res, err = replay.run(r, ACTIVE, {
      resolve_arena = function()
        return changed
      end,
    })
    assert.is_nil(res)
    assert.matches("arena_id mismatch", err)
  end)

  it("validates the optional header fields", function()
    local r = load("steel_and_power")
    r.player_level = 4
    assert.is_nil((replay.check(r)))
    r.player_level = 3
    r.arena_id = "xyz"
    assert.is_nil((replay.check(r)))
  end)

  it("a level-format replay needs an arena reader", function()
    local res, err = replay.run(load("terrain_tour"), ACTIVE)
    assert.is_nil(res)
    assert.matches("needs a level reader", err)
  end)

  it("golden regeneration refuses missing or mismatching arena ids", function()
    local r = load("brick_demolition")
    r.arena_id = nil
    local res, err = update_goldens.regenerate(r, ACTIVE)
    assert.is_nil(res)
    assert.matches("arena_id required", err)
    r = load("brick_demolition")
    r.arena_id = "00000000"
    res, err = update_goldens.regenerate(r, ACTIVE)
    assert.is_nil(res)
    assert.matches("arena_id mismatch", err)
    -- and it never writes an arena_id into a legacy G1 fixture
    local g1 = assert(update_goldens.regenerate(load("stress_run"), ACTIVE))
    assert.is_nil(g1.arena_id)
  end)
end)
