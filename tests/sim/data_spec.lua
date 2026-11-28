-- Units, tuning, hashing and arena data (G1 plan §2, §6, §7).

local units = require("src.sim.units")
local tuning = require("src.sim.tuning")
local hash = require("src.core.hash")
local arena = require("src.sim.arena")
local terrain = require("src.sim.terrain")
local sim = require("src.sim.sim")
local boundaries = require("tools.lib.boundaries")
local H = require("tests.sim.helpers")

describe("simulation units", function()
  it("follow the G1-D1 contract", function()
    assert.are.same({ 256, 64, 128, 3328, 52, 256, 64 }, {
      units.TILE,
      units.CELL,
      units.SNAP,
      units.FIELD,
      units.CELLS,
      units.TANK,
      units.MAX_SUBSTEP,
    })
  end)

  it("converts the committed tuning to readable tiles/s", function()
    local v = tuning.load().values
    assert.are.equal(7 * 60 / 256, units.tiles_per_second(v.player_speed)) -- 1.64 tiles/s
    -- design value -> u/tick, round half up (TECHNICAL_DESIGN §2)
    local function convert(tiles_s)
      return math.floor(tiles_s * 256 / 60 + 0.5)
    end
    assert.are.same({ 6, 17, 34 }, { convert(1.40), convert(4), convert(8) })
  end)

  it("commits the owner-approved speeds tagged TUNED (owner, 2026-11-27)", function()
    local cfg = require("config.tuning")
    local approved = { player_speed = 7, bullet_speed_normal = 17, bullet_speed_fast = 34 }
    for key, value in pairs(approved) do
      assert.are.same(
        { value, "TUNED (owner, 2026-11-27)" },
        { cfg.entries[key][1], cfg.entries[key][2] },
        key
      )
    end
    -- everything else keeps its earlier value and tag
    assert.are.same(
      { 17, "UNV" },
      { cfg.entries.turret_bullet_speed[1], cfg.entries.turret_bullet_speed[2] }
    )
    assert.are.same({ 32, "UNV" }, { cfg.entries.bullet_size[1], cfg.entries.bullet_size[2] })
  end)
end)

describe("tuning", function()
  local cfg = require("config.tuning")

  it("loads config/tuning.lua: integers, provenance tags, schema", function()
    local t = tuning.load()
    assert.are.equal(1, t.version)
    assert.matches("^%x%x%x%x%x%x%x%x$", t.id)
    for key, e in pairs(cfg.entries) do
      assert.is_truthy(tuning.SCHEMA[key], key)
      assert.is_string(e[3])
    end
  end)

  it("has an id that is stable and changes with any value or the version", function()
    local v = tuning.load().values
    local id = tuning.id(v, 1)
    assert.are.equal(id, tuning.id(tuning.copy(v), 1))
    local changed = tuning.copy(v)
    changed.bullet_limit[3] = 3
    assert.are_not.equal(id, tuning.id(changed, 1))
    assert.are_not.equal(id, tuning.id(v, 2))
  end)

  it("copies are independent of the active values", function()
    local v = tuning.load().values
    local c = tuning.copy(v)
    c.player_speed = 9
    assert.are.equal(cfg.entries.player_speed[1], tuning.load().values.player_speed)
  end)

  it("rejects bad values, unknown keys and missing provenance", function()
    local v = tuning.copy(tuning.load().values)
    v.player_speed = 1.5
    v.extra = 1
    v.bullet_limit = { 1, 1 }
    local ok, problems = tuning.check_values(v)
    assert.is_nil(ok)
    assert.are.equal(3, #problems)
    assert.has_error(function()
      tuning.from_config({ version = 1, entries = { player_speed = { 6, "GUESS", "x" } } })
    end)
    assert.has_error(function()
      tuning.from_config({ version = 1, entries = { player_speed = { 6, "MEASURED", "x" } } })
    end)
  end)

  it("accepts TUNED and MEASURED tags only in their documented forms", function()
    local entries = {}
    for k, e in pairs(cfg.entries) do
      entries[k] = { e[1], e[2], e[3] }
    end
    entries.player_speed[2] = "TUNED (owner, 2026-12-01)"
    entries.bullet_speed_fast[2] = "MEASURED (frame-stepped footage, owner recording, 2026-12-01)"
    entries.player_speed[2] = "TUNED (owner)" -- date missing
    assert.has_error(function()
      tuning.from_config({ version = 1, entries = entries })
    end)
    entries.player_speed[2] = "TUNED (owner, 2026-12-01)"
    assert.are.equal(
      cfg.entries.player_speed[1],
      tuning.from_config({ version = 1, entries = entries }).player_speed
    )
  end)
end)

describe("core.hash", function()
  it("is deterministic and sensitive to every byte", function()
    assert.are.equal(hash.string("abc"), hash.string("abc"))
    assert.are_not.equal(hash.string("abc"), hash.string("abd"))
    assert.are.equal(hash.new():int(-1):hex(), hash.new():int(4294967295):hex())
    assert.are_not.equal(hash.new():int(1):int(2):hex(), hash.new():int(2):int(1):hex())
    assert.matches("^%x+$", hash.new():hex())
  end)

  it("rejects non-integers and out-of-range values", function()
    assert.has_error(function()
      hash.new():int(1.5)
    end)
    assert.has_error(function()
      hash.new():int(2 ^ 32)
    end)
  end)
end)

describe("sim.hash", function()
  it("covers positions, facings, bullets and tick", function()
    local w = H.world()
    local h0 = sim.hash(w)
    local p1 = w.tanks[1]
    p1.x = p1.x + 1
    assert.are_not.equal(h0, sim.hash(w))
    p1.x = p1.x - 1
    assert.are.equal(h0, sim.hash(w))
    p1.facing = "left"
    assert.are_not.equal(h0, sim.hash(w))
  end)
end)

describe("arena data", function()
  it("loads the G1 arena: players first, dummies, 1-tile lanes", function()
    local a = arena.load("g1_arena")
    assert.are.same(
      { "player", "player", "target", "target", "turret" },
      (function()
        local k = {}
        for i, e in ipairs(a.entities) do
          k[i] = e.kind
        end
        return k
      end)()
    )
    assert.are.same({ 1024, 3072 }, { a.entities[1].x, a.entities[1].y })
    -- lane in tile column 6, rows 4-5: free, with solid neighbours
    local function solid_at(tx, ty)
      return (terrain.box_hits(a.cells, tx * 256, ty * 256, 256, 256, terrain.BLOCKS_TANKS))
    end
    for _, ty in ipairs({ 4, 5 }) do
      assert.is_false(solid_at(6, ty))
      assert.is_true(solid_at(5, ty) and solid_at(7, ty))
      assert.is_false(solid_at(10, ty))
      assert.is_true(solid_at(9, ty) and solid_at(11, ty))
    end
  end)

  it("lists exactly the config arenas under config/arenas/ as G1-format arenas", function()
    local fs = require("tools.lib.fs")
    local names = {}
    for _, path in ipairs(fs.list_files("config/arenas", "%.lua$")) do
      names[#names + 1] = path:match("([%w_]+)%.lua$")
    end
    local listed = {}
    for name in pairs(arena.CONFIG) do
      listed[#listed + 1] = name
    end
    table.sort(listed)
    assert.are.same(names, listed)
    assert.is_true(arena.is_config("g1_arena"))
    assert.is_false(arena.is_config("g2_terrain"))
    assert.has_error(function()
      arena.load("g2_terrain")
    end)
  end)

  it("has a stable arena id that changes with any cell or entity", function()
    local a = arena.load("g1_arena")
    local id = arena.id(a)
    assert.matches("^%x%x%x%x%x%x%x%x$", id)
    assert.are.equal(id, arena.id(arena.load("g1_arena")))
    a.cells[100] = 1 - a.cells[100]
    assert.are_not.equal(id, arena.id(a))
    a.cells[100] = 1 - a.cells[100]
    a.entities[3].x = a.entities[3].x + 128
    assert.are_not.equal(id, arena.id(a))
    a.entities[3].x = a.entities[3].x - 128
    a.entities[5].facing = "left"
    assert.are_not.equal(id, arena.id(a))
  end)

  it("rejects malformed arenas", function()
    local ok_entities = H.entities({ 0, 0 }, { 4, 0 })
    local bad = {
      { name = "x", map = { "..." }, entities = ok_entities },
      H.arena_data({ "Q" .. string.rep(".", 12) }, ok_entities),
      H.arena_data({}, { ok_entities[2], ok_entities[1] }), -- players out of order
      H.arena_data({}, H.entities({ 0, 0 }, { 1, 0 })), -- overlapping tanks
      H.arena_data({ "X" .. string.rep(".", 12) }, ok_entities), -- tank on a block
      H.arena_data({}, H.entities({ 25, 0 }, { 4, 0 })), -- outside the field
      H.arena_data({}, { ok_entities[1] }), -- one entity
    }
    for i, data in ipairs(bad) do
      assert.has_error(function()
        arena.build(data)
      end, nil, "case " .. i)
    end
  end)
end)

describe("presentation boundary", function()
  it("forbids src/sim from requiring config/presentation", function()
    local p = boundaries.check_source("x.lua", 'local p = require("config.presentation")')
    assert.are.equal(1, #p)
    assert.are.same({}, boundaries.check_source("x.lua", 'local t = require("config.tuning")'))
  end)
end)
