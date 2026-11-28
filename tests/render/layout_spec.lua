-- Render layers and terrain cells (G2 plan §8, G2-D5): the forest layer is
-- drawn after tanks and bullets, cells are exactly 6 px at 24 px tiles and
-- 8 px at 32 px, and presentation never mutates the world.

local layout = require("src.render.layout")
local sim = require("src.sim.sim")
local H = require("tests.sim.helpers")

local function terrain_world()
  local w = H.world({ arena = H.arena_data({}, H.entities({ 12, 20 }, { 0, 0 })) })
  local kinds = { "block", "brick", "steel", "water", "forest", "ice" }
  for i, k in ipairs(kinds) do
    H.fill(w, i * 4, 10, i * 4 + 1, 11, k)
  end
  H.fill(w, 24, 40, 27, 43, "forest") -- over P1 (x 1536..1792, y 2560..2816)
  H.add_bullet(w, 1, 1600, 2600, "up", 17)
  return w
end

describe("render.layout layers", function()
  it("draws ground, tanks, bullets, forest, effects, HUD in that order", function()
    assert.are.same({ "ground", "tanks", "bullets", "forest", "effects", "hud" }, layout.LAYERS)
    local pos = {}
    for i, name in ipairs(layout.LAYERS) do
      pos[name] = i
    end
    assert.is_true(pos.forest > pos.tanks and pos.forest > pos.bullets)
    assert.is_true(pos.ground < pos.tanks)
  end)

  it("puts forest cells on their own layer and every other type on the ground layer", function()
    local view = layout.build(terrain_world(), 24, 0, 0)
    local ground, forest = {}, 0
    for _, c in ipairs(view.cells) do
      ground[c.kind] = (ground[c.kind] or 0) + 1
    end
    for _, c in ipairs(view.forest) do
      assert.are.equal("forest", c.kind)
      forest = forest + 1
    end
    assert.are.same({ block = 4, brick = 4, steel = 4, water = 4, ice = 4 }, ground)
    assert.are.equal(4 + 16, forest)
    -- the forest over P1 covers its tank and its bullet
    assert.are.equal(2, #view.tanks) -- P1 and P2 present
    assert.are.equal(1, #view.bullets)
  end)

  for _, case in ipairs({ { 24, 6 }, { 32, 8 } }) do
    it(("draws every cell as exactly %d px at %d px tiles"):format(case[2], case[1]), function()
      local w = H.world({ arena = H.arena_data({}, H.entities({ 12, 20 }, { 0, 0 })) })
      for i = 1, #w.cells do
        w.cells[i] = 2 -- brick everywhere (layout does not check overlaps)
      end
      local view = layout.build(w, case[1], 164, 24)
      assert.are.equal(52 * 52, #view.cells)
      for _, c in ipairs(view.cells) do
        assert(c.w == case[2] and c.h == case[2], "cell size")
        assert(c.x == 164 + c.col * case[2] and c.y == 24 + c.row * case[2], "cell position")
      end
    end)
  end

  it("never mutates the world, at either tile size", function()
    local w = terrain_world()
    local before = sim.hash(w)
    for _, px in ipairs({ 24, 32 }) do
      layout.build(w, px, 0, 0)
    end
    assert.are.equal(before, sim.hash(w))
  end)
end)

describe("render.arena_view painters", function()
  -- A minimal love.graphics stub that records rectangles and their colors.
  local function stub_love()
    local log = { rects = {} }
    local current = { 1, 1, 1, 1 }
    local font = {
      setFilter = function() end,
    }
    _G.love = {
      graphics = {
        newFont = function()
          return font
        end,
        setFont = function() end,
        print = function() end,
        clear = function() end,
        setColor = function(r, g, b, a)
          current = { r, g, b, a or 1 }
        end,
        rectangle = function(_, x, y, w, h)
          log.rects[#log.rects + 1] = { x = x, y = y, w = w, h = h, color = current }
        end,
      },
    }
    return log
  end

  it("paints the layers in layout.LAYERS order, forest after tanks and bullets", function()
    local saved_love = _G.love
    stub_love()
    package.loaded["src.render.arena_view"] = nil
    local view = require("src.render.arena_view")
    local order = {}
    local real = {}
    for name, fn in pairs(view.PAINTERS) do
      real[name] = fn
      view.PAINTERS[name] = function(d)
        order[#order + 1] = name
        return fn(d)
      end
    end
    local w = terrain_world()
    local before = sim.hash(w)
    local edit = require("src.app.tuning_edit").new(require("src.sim.tuning").load())
    local ok, err = pcall(view.draw, {
      world = w,
      fx = {},
      counts = { shots = 0, cancels = 0, destroyed = 0 },
      edit = edit,
      modified = false,
      title = "TEST",
    })
    for name, fn in pairs(real) do
      view.PAINTERS[name] = fn
    end
    _G.love = saved_love
    package.loaded["src.render.arena_view"] = nil
    assert(ok, err)
    assert.are.same(layout.LAYERS, order)
    assert.are.equal(before, sim.hash(w)) -- drawing never mutates the sim
  end)

  it("draws the forest cell over a tank in that cell", function()
    local saved_love = _G.love
    local log = stub_love()
    package.loaded["src.render.arena_view"] = nil
    local view = require("src.render.arena_view")
    local w = terrain_world()
    local edit = require("src.app.tuning_edit").new(require("src.sim.tuning").load())
    view.draw({
      world = w,
      fx = {},
      counts = { shots = 0, cancels = 0, destroyed = 0 },
      edit = edit,
      modified = false,
    })
    _G.love = saved_love
    package.loaded["src.render.arena_view"] = nil
    -- P1's tank body (24 px at 164 + 144, 24 + 240) and the forest cell at
    -- column 24, row 40 (164 + 144, 24 + 240, 6 px): the last rectangle
    -- covering that pixel must be a forest one
    local px, py = 164 + 144 + 2, 24 + 240 + 2
    local last
    for i, r in ipairs(log.rects) do
      if px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h then
        last = i
      end
    end
    local tank_seen = false
    for i = 1, last do
      local r = log.rects[i]
      if r.w == 24 and r.h == 24 then
        tank_seen = true
      end
    end
    assert.is_true(tank_seen)
    -- the covering rectangle is a forest-layer one (6 px or smaller)
    assert.is_true(log.rects[last].w <= 6 and log.rects[last].h <= 6)
  end)
end)
