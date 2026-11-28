-- Level loader, profiles and validator (G2 plan §11, G2-D6): every valid
-- fixture loads, every invalid fixture fails with its rule's message, the
-- loader never executes level text, marker parsing, reachability, the
-- battlefield shape and the arena selection rule.

local fs = require("tools.lib.fs")
local levels = require("tools.lib.levels")
local validate = require("tools.validate_levels")
local level = require("src.sim.level")
local terrain = require("src.sim.terrain")
local units = require("src.sim.units")
local sim = require("src.sim.sim")
local H = require("tests.sim.helpers")

local DIR = "tests/fixtures/levels/"

local function profile_of_fixture(path)
  return path:match("/(%a+)_[%w_]+%.lua$")
end

local function map_text(rows, header)
  local out = { "return {", header or '  name = "t",', "  map = {" }
  for _, r in ipairs(rows) do
    out[#out + 1] = '    "' .. r .. '",'
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "}"
  return table.concat(out, "\n")
end

local EMPTY = string.rep(".", 26)
local function arena_rows(edits)
  local rows = {}
  for r = 1, 26 do
    rows[r] = EMPTY
  end
  rows[25] = "11" .. string.rep(".", 20) .. "22.."
  rows[26] = rows[25]
  for r, row in pairs(edits or {}) do
    rows[r] = row
  end
  return rows
end

describe("level fixtures", function()
  it("loads every valid fixture with its profile", function()
    local files = fs.list_files(DIR .. "valid", "%.lua$")
    assert.is_true(#files >= 4)
    for _, path in ipairs(files) do
      local built, problems = level.parse(fs.read(path), profile_of_fixture(path))
      assert.is_truthy(built, path .. ": " .. table.concat(problems or {}, "; "))
    end
  end)

  it("rejects every invalid fixture with the message of its rule", function()
    local files = fs.list_files(DIR .. "invalid", "%.lua$")
    assert.is_true(#files >= 30)
    for _, path in ipairs(files) do
      local text = fs.read(path)
      local expect = assert(text:match("\n%-%- expect: ([^\n]+)"), path .. ": no expect line")
      local built, problems = level.parse(text, profile_of_fixture(path))
      assert.is_nil(built, path)
      local found = false
      for _, p in ipairs(problems) do
        found = found or p:find(expect, 1, true) ~= nil
      end
      assert.is_true(
        found,
        path .. ": expected '" .. expect .. "', got: " .. table.concat(problems, "; ")
      )
    end
  end)

  it("validates the same campaign map as an arena only without campaign rules", function()
    -- the arena profile forbids H and E, and the campaign keys
    local built, problems = level.parse(fs.read(DIR .. "valid/campaign_basic.lua"), "arena")
    assert.is_nil(built)
    assert.is_true(#problems >= 3)
  end)
end)

describe("level loader", function()
  it("never executes level text", function()
    _G.__level_pwned = nil
    for _, text in ipairs({
      "return (function() __level_pwned = true; return {} end)()",
      'return { name = "x", map = loadstring("__level_pwned = true") }',
      "\27LuaJ",
      "__level_pwned = true return {}",
      "return { name = [[x]] }",
    }) do
      local built, problems = level.parse(text, "arena")
      assert.is_nil(built)
      assert.matches("^level: ", problems[1])
    end
    assert.is_nil(_G.__level_pwned)
  end)

  it("rejects oversized text before parsing", function()
    local text = map_text(arena_rows()) .. "\n-- " .. string.rep("x", level.MAX_BYTES)
    local built, problems = level.parse(text, "arena")
    assert.is_nil(built)
    assert.are.same({ "level: input too large" }, problems)
  end)

  it("maps every terrain character to its code at 2 x 2 cells", function()
    local rows = arena_rows({ [1] = ".XBSWFI" .. string.rep(".", 19) })
    local built = assert(level.parse(map_text(rows), "arena"))
    local n = units.CELLS
    for c, ch in ipairs({ ".", "X", "B", "S", "W", "F", "I" }) do
      for dy = 0, 1 do
        for dx = 0, 1 do
          local i = dy * n + (c - 1) * 2 + dx + 1
          assert.are.equal(terrain.CHAR[ch], built.cells[i], ch)
        end
      end
    end
  end)

  it("parses 2 x 2 marker blocks row-major; markers are empty ground", function()
    -- "EEEEEE" over two rows is three side-by-side blocks
    local rows =
      arena_rows({ [1] = "EEEEEE" .. string.rep(".", 20), [2] = "EEEEEE" .. string.rep(".", 20) })
    local _, problems = level.parse(map_text(rows), "arena")
    assert.matches("got 3", table.concat(problems, ";"))
    -- a 2 x 2 block offset by one row and column is still one block
    rows = arena_rows({ [4] = "..22" .. string.rep(".", 22), [5] = "..22" .. string.rep(".", 22) })
    rows[25], rows[26] = "11" .. string.rep(".", 24), "11" .. string.rep(".", 24)
    local built = assert(level.parse(map_text(rows), "arena"))
    assert.are.same(
      { 256, 384, "up" },
      { built.entities[2].x, built.entities[2].y, built.entities[2].facing }
    )
    assert.are.same({ 0, 3072 }, { built.entities[1].x, built.entities[1].y })
    assert.are.equal(terrain.EMPTY, built.cells[H.idx(4, 6)])
    -- a stray third row of the same marker is an error
    rows[6] = "..22" .. string.rep(".", 22)
    local _, p2 = level.parse(map_text(rows), "arena")
    assert.matches("not a complete 2 x 2 block", table.concat(p2, ";"))
  end)

  it("returns the battlefield shape world.new accepts, players first, then dummies", function()
    local built = assert(level.parse(fs.read(DIR .. "valid/arena_basic.lua"), "arena"))
    local kinds = {}
    for i, e in ipairs(built.entities) do
      kinds[i] = e.kind .. (e.slot and tostring(e.slot) or "")
    end
    assert.are.same({ "player1", "player2", "target", "turret" }, kinds)
    local w = sim.new({ arena = built, tuning = H.tuning() })
    assert.are.equal(4, #w.tanks)
    assert.are.same({}, sim.violations(w))
    -- campaign: hq and enemy spawns for G4, ignored by world.new
    local c = assert(level.parse(fs.read(DIR .. "valid/campaign_basic.lua"), "campaign"))
    assert.are.same({ x = 1536, y = 3072 }, c.hq)
    assert.are.same(
      { 0, 1536, 3072 },
      { c.enemy_spawns[1].x, c.enemy_spawns[2].x, c.enemy_spawns[3].x }
    )
    assert.are.equal("down", c.enemy_spawns[1].facing)
    assert.are.same({ "campaign", 7, "winter" }, { c.meta.profile, c.meta.id, c.meta.env })
    assert.are.equal(2, #sim.new({ arena = c, tuning = H.tuning() }).tanks)
  end)

  -- Review finding: the campaign name is a display name ("Opening Gate",
  -- TECHNICAL_DESIGN §9); only arena names must be identifiers.
  it("accepts a campaign display name and keeps arena names identifiers", function()
    local text = fs.read(DIR .. "valid/campaign_basic.lua")
    local spaced = text:gsub('name = "fixture_campaign"', 'name = "Opening Gate"')
    local built, problems = level.parse(spaced, "campaign")
    assert.is_truthy(built, table.concat(problems or {}, "; "))
    assert.are.equal("Opening Gate", built.name)
    local arena_text = fs.read(DIR .. "valid/arena_basic.lua")
      :gsub('"fixture_arena"', '"Opening Gate"')
    local _, p2 = level.parse(arena_text, "arena")
    assert.matches("name: identifier expected", p2[1])
  end)

  it("reachability: brick is passable, steel and water block", function()
    local grid = {}
    for r = 0, 25 do
      grid[r] = {}
      for c = 0, 25 do
        grid[r][c] = "."
      end
    end
    for c = 0, 25 do
      grid[12][c] = "S"
    end
    assert.is_false(level.reachable(grid, { 0, 0 }, { 12, 24 }))
    grid[12][5], grid[12][6] = "B", "B"
    assert.is_true(level.reachable(grid, { 0, 0 }, { 12, 24 }))
    grid[12][5] = "W" -- a 1-half-tile gap is too narrow for a tank
    assert.is_false(level.reachable(grid, { 0, 0 }, { 12, 24 }))
  end)
end)

describe("arena selection and the validator", function()
  it("resolves config arenas with the G1 loader and others through the reader", function()
    local g1 = level.load_arena("g1_arena")
    assert.are.equal("g1_arena", g1.name)
    local read = function(name)
      assert.are.equal("fixture_arena", name)
      return fs.read(DIR .. "valid/arena_basic.lua")
    end
    assert.are.equal("fixture_arena", level.load_arena("fixture_arena", read).name)
    assert.has_error(function()
      level.load_arena("fixture_arena")
    end) -- no reader
    assert.has_error(function()
      level.load_arena("other", function()
        return fs.read(DIR .. "valid/arena_basic.lua") -- declares fixture_arena
      end)
    end)
    assert.has_error(function()
      level.load_arena("missing", levels.read_arena)
    end)
  end)

  it("validates every file under levels/ by its location", function()
    local problems, n = validate.check_tree()
    assert.are.same({}, problems)
    assert.is_true(n >= 1)
    assert.are.same({ "campaign", 7 }, { levels.profile_of("levels/07.lua") })
    assert.are.same(
      { "arena", "g2_terrain" },
      { levels.profile_of("levels/arenas/g2_terrain.lua") }
    )
    assert.is_nil(levels.profile_of("levels/notes.lua"))
    assert.is_nil(levels.profile_of("levels/7.lua"))
  end)

  -- Review finding: a Finder .DS_Store under levels/ must not fail make validate
  it("ignores hidden files but still flags other files outside the level locations", function()
    assert.is_true(validate.hidden("levels/arenas/.DS_Store"))
    assert.is_true(validate.hidden("levels/.01.lua.swp"))
    assert.is_false(validate.hidden("levels/arenas/g2_terrain.lua"))
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "/arenas'")
    local function put(rel, text)
      local f = assert(io.open(dir .. "/" .. rel, "wb"))
      f:write(text)
      f:close()
    end
    put("arenas/.DS_Store", "\0\0\0\1Bud1")
    put("notes.txt", "x")
    local problems, n = validate.check_tree(dir)
    os.execute("rm -rf '" .. dir .. "'")
    assert.are.equal(1, n) -- notes.txt only; .DS_Store is skipped
    assert.are.equal(1, #problems)
    assert.matches("notes.txt: not a level file location", problems[1])
  end)

  it("checks that a campaign file's id and an arena file's name match the file name", function()
    local p = validate.check_file(DIR .. "valid/campaign_basic.lua", "campaign", 8)
    assert.matches("does not match the file name %(08%)", p[1])
    assert.are.same({}, validate.check_file(DIR .. "valid/campaign_basic.lua", "campaign", 7))
    p = validate.check_file(DIR .. "valid/arena_basic.lua", "arena", "g2_terrain")
    assert.matches("does not match the file name", p[1])
  end)
end)
