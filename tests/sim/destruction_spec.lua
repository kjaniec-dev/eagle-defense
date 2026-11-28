-- Brick and steel destruction (G2 plan §6, G2-D2, G2-D3, clarification C1):
-- the exact removed cells, the strip and its tie, depth, clipping, muzzle
-- impacts, simultaneous impacts in a sub-step and in the spawn phase, event
-- attribution, steel and power bullets, and phase-order interactions. Every
-- scenario asserts the tick invariants, including terrain invariant 9.

local sim = require("src.sim.sim")
local destruction = require("src.sim.destruction")
local world = require("src.sim.world")
local H = require("tests.sim.helpers")

local idx = H.idx

-- An empty arena with the players in the bottom corners (away from the
-- action) and optional dummies.
local function new_world(opts)
  opts = opts or {}
  return H.world({
    arena = H.arena_data({}, H.entities({ 0, 24 }, { 24, 24 }, opts.dummies)),
    tuning = opts.tuning,
    player_level = opts.player_level,
  })
end

-- Runs until no bullet is left (at most n ticks); returns the events and the
-- changed cells ("c,r").
local function settle(w, n)
  local before = world.copy_cells(w.cells)
  local events = {}
  for _ = 1, n or 300 do
    for _, e in ipairs(H.run(w, 1, nil)) do
      events[#events + 1] = e
    end
    if #w.bullets == 0 then
      break
    end
  end
  return events, H.changed(before, w.cells)
end

local function destroyed(events)
  local out = {}
  for _, e in ipairs(H.of_type(events, "terrain_destroyed")) do
    out[#out + 1] = { e.bullet, e.terrain, e.cells }
  end
  return out
end

describe("brick strip", function()
  -- One bullet per direction against a 2-cell-thick wall, centered on the
  -- boundary x (or y) = 1280, i.e. between cells 19 and 20.
  local cases = {
    {
      dir = "up",
      wall = { 10, 20, 30, 21 },
      bullet = { 1264, 1500 },
      removed = { "19,21", "20,21" },
    },
    {
      dir = "down",
      wall = { 10, 20, 30, 21 },
      bullet = { 1264, 1100 },
      removed = { "19,20", "20,20" },
    },
    {
      dir = "left",
      wall = { 20, 10, 21, 30 },
      bullet = { 1500, 1264 },
      removed = { "21,19", "21,20" },
    },
    {
      dir = "right",
      wall = { 20, 10, 21, 30 },
      bullet = { 1100, 1264 },
      removed = { "20,19", "20,20" },
    },
  }
  for _, c in ipairs(cases) do
    it("removes exactly 2 x 1 cells going " .. c.dir, function()
      local w = new_world()
      H.fill(w, c.wall[1], c.wall[2], c.wall[3], c.wall[4], "brick")
      local b = H.add_bullet(w, 1, c.bullet[1], c.bullet[2], c.dir, 17)
      local events, changed = settle(w)
      assert.are.same(c.removed, changed)
      local hits = H.of_type(events, "bullet_hit_solid")
      assert.are.equal(1, #hits)
      assert.are.same(
        { "solid", "brick", false },
        { hits[1].kind, hits[1].terrain, hits[1].at_spawn }
      )
      local cells = {}
      for _, key in ipairs(c.removed) do
        local col, row = key:match("(%d+),(%d+)")
        cells[#cells + 1] = idx(tonumber(col), tonumber(row))
      end
      table.sort(cells)
      assert.are.same({ { b.id, "brick", cells } }, destroyed(events))
      assert.are.equal(cells[1], hits[1].cell) -- lowest index in the impact line
    end)
  end

  -- A tank shoots off the 128 u grid only when its snap is blocked, and only
  -- another tank can block a snap at a distance other than 64 u.
  local function unaligned_shot(px)
    local w = new_world()
    H.fill(w, 10, 10, 30, 11, "brick")
    local p1, p2 = w.tanks[1], w.tanks[2]
    p1.x, p1.y = px, 1536
    p2.x, p2.y = px - 256, 1536 -- touching P1 on the left: blocks the snap left
    H.run(w, 1, H.frame("up")) -- blocked snap: turns up in place
    assert.are.same({ px, 1536, "up" }, { p1.x, p1.y, p1.facing })
    H.run(w, 1, H.frame({ press = true }))
    local _, changed = settle(w)
    return changed
  end

  it("ties (center = 32 mod 64) go to the lower boundary", function()
    -- center 1184 + 128 = 1312 = 1280 + 32: tie -> boundary 1280 -> cells 19, 20
    assert.are.same({ "19,11", "20,11" }, unaligned_shot(1184))
  end)

  it("centers on the nearest cell boundary, not on the bullet's cell", function()
    -- center 1202 + 128 = 1330: nearest boundary 1344 -> cells 20, 21, although
    -- the whole bullet ([1314, 1346)) is mostly in cell 20
    assert.are.same({ "20,11", "21,11" }, unaligned_shot(1202))
    -- center 1170 + 128 = 1298: nearest boundary 1280 -> cells 19, 20
    assert.are.same({ "19,11", "20,11" }, unaligned_shot(1170))
  end)

  it("an aligned tank always shoots on a cell boundary", function()
    local w = new_world()
    H.fill(w, 0, 10, 51, 11, "brick")
    local p1 = w.tanks[1]
    p1.x, p1.y = 1152, 1536
    H.run(w, 1, H.frame({ dir = "up", press = true }))
    local _, changed = settle(w)
    assert.are.same({ "19,11", "20,11" }, changed)
  end)

  it("depth 2 removes two lines; width 4 removes four columns", function()
    local w = new_world({ tuning = { brick_strip_depth = 2 } })
    H.fill(w, 10, 20, 30, 23, "brick")
    H.add_bullet(w, 1, 1264, 1600, "up", 17)
    local _, changed = settle(w)
    assert.are.same({ "19,22", "19,23", "20,22", "20,23" }, changed)

    w = new_world({ tuning = { brick_strip_cells = 4 } })
    H.fill(w, 10, 20, 30, 23, "brick")
    H.add_bullet(w, 1, 1264, 1600, "up", 17)
    _, changed = settle(w)
    assert.are.same({ "18,23", "19,23", "20,23", "21,23" }, changed)
  end)

  it("clips the strip and the depth at the field edge", function()
    local w = new_world()
    H.fill(w, 0, 20, 5, 21, "brick")
    H.add_bullet(w, 1, 0, 1500, "up", 17) -- center 16 -> boundary 0 -> cells -1, 0
    local _, changed = settle(w)
    assert.are.same({ "0,21" }, changed)

    w = new_world({ tuning = { brick_strip_cells = 4, brick_strip_depth = 2 } })
    H.fill(w, 0, 0, 5, 0, "brick") -- one line at the top edge
    H.add_bullet(w, 1, 48, 200, "up", 17) -- center 64 -> cells -1 .. 2
    _, changed = settle(w)
    assert.are.same({ "0,0", "1,0", "2,0" }, changed)
  end)

  it("a bullet passes through a 2-cell hole without touching it", function()
    local w = new_world()
    H.fill(w, 10, 20, 30, 21, "brick")
    H.fill(w, 19, 20, 20, 21, "empty")
    H.add_bullet(w, 1, 1264, 1500, "up", 17)
    local events, changed = settle(w)
    assert.are.same({}, changed)
    local hits = H.of_type(events, "bullet_hit_solid")
    assert.are.same({ "bound" }, { hits[1].kind })
  end)
end)

describe("muzzle impacts (G2 plan §6.4)", function()
  it("a tank touching a brick wall destroys it with a point-blank shot", function()
    local w = new_world()
    H.fill(w, 10, 22, 30, 23, "brick") -- wall bottom at y = 1536
    local p1 = w.tanks[1]
    p1.x, p1.y = 1152, 1536 -- touching the wall
    local events = H.run(w, 1, H.frame({ dir = "up", press = true }))
    assert.are.same({ 1152, 1536 }, { p1.x, p1.y }) -- contact: no movement
    local hits = H.of_type(events, "bullet_hit_solid")
    assert.are.same({ "solid", "brick", true }, { hits[1].kind, hits[1].terrain, hits[1].at_spawn })
    assert.are.same(
      { { hits[1].bullet, "brick", { idx(19, 23), idx(20, 23) } } },
      destroyed(events)
    )
    assert.are.equal(0, #w.bullets)
    -- the next shot flies one line deeper
    H.run(w, 1, H.frame({ press = true }))
    local _, changed = settle(w)
    assert.are.same({ "19,22", "20,22" }, changed)
  end)

  it("a spawn box spanning two lines removes only the line it hits", function()
    local w = new_world()
    H.fill(w, 10, 13, 30, 14, "brick")
    local p1 = w.tanks[1]
    p1.x, p1.y = 1152, 980 -- spawn box [948, 980): rows 14 and 15
    local events = H.run(w, 1, H.frame({ press = true }))
    local d = destroyed(events)
    assert.are.equal(1, #d)
    assert.are.same({ idx(19, 14), idx(20, 14) }, d[1][3]) -- row 15 holds no brick
  end)

  it("the impact line is the one nearest the shooter (pure rule)", function()
    local tu = H.tuning()
    local cells = world.copy_cells(new_world().cells)
    -- both rows under a spanning up-bullet are brick
    for _, c in ipairs({ 19, 20 }) do
      cells[idx(c, 14)] = 2
      cells[idx(c, 15)] = 2
    end
    local hit = destruction.impact(cells, { x = 1264, y = 948, size = 32, dir = "up" }, tu)
    assert.are.equal(15, hit.line) -- trailing row (nearest the shooter)
    assert.are.same({ idx(19, 15), idx(20, 15) }, hit.brick)
    assert.are.equal(idx(19, 15), hit.cell)
    hit = destruction.impact(cells, { x = 1264, y = 948, size = 32, dir = "down" }, tu)
    assert.are.equal(14, hit.line)
  end)
end)

describe("simultaneous impacts (G2 plan §6.5, clarification C1)", function()
  -- A 1-cell wall (row 20); P1's bullet comes from below and P2's from above
  -- (same faction: they pass through each other). Both reach row 20 in the
  -- same sub-step.
  local function opposite(order, x_up, x_down)
    local w = new_world()
    H.fill(w, 10, 20, 30, 20, "brick")
    local ids = {}
    local function up()
      ids.up = H.add_bullet(w, 1, x_up, 1349, "up", 17).id
    end
    local function down()
      ids.down = H.add_bullet(w, 2, x_down, 1243, "down", 17).id
    end
    if order == "up first" then
      up()
      down()
    else
      down()
      up()
    end
    local before = world.copy_cells(w.cells)
    local events = H.run(w, 1, nil)
    return w, events, H.changed(before, w.cells), ids
  end

  for _, order in ipairs({ "up first", "down first" }) do
    it("both bullets are consumed and the union is removed (" .. order .. ")", function()
      local w, events, changed = opposite(order, 1264, 1264)
      assert.are.equal(0, #w.bullets) -- neither slips through the other's hole
      assert.are.equal(2, #H.of_type(events, "bullet_hit_solid"))
      assert.are.same({ "19,20", "20,20" }, changed)
      -- each destroyed cell is reported once, for the first impact
      local d = destroyed(events)
      assert.are.equal(1, #d)
      assert.are.same({ idx(19, 20), idx(20, 20) }, d[1][3])
    end)

    it(
      "overlapping strips: same final terrain, cells attributed in order (" .. order .. ")",
      function()
        local w, events, changed, ids = opposite(order, 1264, 1328) -- strips {19,20} and {20,21}
        assert.are.equal(0, #w.bullets)
        assert.are.same({ "19,20", "20,20", "21,20" }, changed)
        local d = destroyed(events)
        if order == "up first" then
          assert.are.same({
            { ids.up, "brick", { idx(19, 20), idx(20, 20) } },
            { ids.down, "brick", { idx(21, 20) } },
          }, d)
        else
          assert.are.same({
            { ids.down, "brick", { idx(20, 20), idx(21, 20) } },
            { ids.up, "brick", { idx(19, 20) } },
          }, d)
        end
      end
    )
  end

  it("perpendicular bullets in one sub-step see the same start terrain", function()
    for _, order in ipairs({ 1, 2 }) do
      local w = new_world()
      H.fill(w, 20, 20, 21, 21, "brick") -- a 2 x 2 block
      local function up()
        H.add_bullet(w, 1, 1328, 1420, "up", 17) -- strip cols 20, 21; impact row 21
      end
      local function left()
        H.add_bullet(w, 2, 1420, 1360, "left", 17) -- footprint row 21 only; tie -> rows 20, 21
      end
      if order == 1 then
        up()
        left()
      else
        left()
        up()
      end
      local before = world.copy_cells(w.cells)
      H.run(w, 1, nil)
      assert.are.equal(0, #w.bullets, "order " .. order)
      assert.are.same({ "20,21", "21,20", "21,21" }, H.changed(before, w.cells), "order " .. order)
    end
  end)

  it("the spawn phase resolves point-blank shots from both sides together", function()
    local w = new_world()
    H.fill(w, 10, 20, 30, 20, "brick") -- 1-cell wall, rows [1280, 1344)
    local p1, p2 = w.tanks[1], w.tanks[2]
    p1.x, p1.y, p1.facing = 1152, 1344, "up" -- touching from below
    p2.x, p2.y, p2.facing = 1152, 1024, "down" -- touching from above
    local events = H.run(w, 1, H.frame({ press = true }, { press = true }))
    assert.are.equal(0, #w.bullets) -- no bullet passes through the other's hole
    local hits = H.of_type(events, "bullet_hit_solid")
    assert.are.same({ true, true }, { hits[1].at_spawn, hits[2].at_spawn })
    assert.are.equal(21 - 2, H.count(w, "brick")) -- the wall minus one strip
    assert.are.same(
      { { hits[1].bullet, "brick", { idx(19, 20), idx(20, 20) } } },
      destroyed(events)
    )
    -- nothing else happens on the following ticks (no friendly hit)
    events = H.run(w, 30, nil)
    assert.are.same({}, H.of_type(events, "tank_hit"))
  end)

  it("the next sub-step sees the updated cells", function()
    -- Speed 128 = 2 sub-steps of 64. The first bullet removes the row-21
    -- strip in sub-step 1; the second bullet, one cell behind, reaches row
    -- 21 only in sub-step 2, after the removal, so it flies on to row 20.
    local w = new_world()
    H.fill(w, 10, 20, 30, 21, "brick")
    H.add_bullet(w, 1, 1264, 1420, "up", 128) -- reaches row 21 in sub-step 1
    H.add_bullet(w, 2, 1264, 1484, "up", 128) -- reaches row 21 only in sub-step 2
    local events = H.run(w, 1, nil)
    local d = destroyed(events)
    assert.are.equal(1, #d)
    assert.are.same({ idx(19, 21), idx(20, 21) }, d[1][3])
    assert.are.equal(1, #w.bullets) -- the second bullet passed into the hole
    local _, changed = settle(w)
    assert.are.same({ "19,20", "20,20" }, changed)
  end)
end)

describe("phase order with terrain (G2 plan §5)", function()
  it("a bullet overlapping a tank and brick in one sub-step hits the tank only", function()
    local w = new_world({ dummies = { { "target", 10, 9 } } }) -- box [1280, 1536) x [1152, 1408)
    H.fill(w, 19, 21, 19, 21, "brick") -- cell (19, 21): [1216, 1280) x [1344, 1408)
    H.add_bullet(w, 1, 1264, 1420, "up", 17) -- overlaps both after the first advance
    local before = world.copy_cells(w.cells)
    local events = H.run(w, 1, nil)
    assert.are.equal(1, #H.of_type(events, "tank_hit"))
    assert.are.same({}, H.of_type(events, "bullet_hit_solid"))
    assert.are.same({}, H.changed(before, w.cells))
  end)

  it("opposing bullets that cancel over brick destroy nothing", function()
    local w = new_world({ dummies = { { "turret", 20, 0 } } })
    H.fill(w, 10, 20, 30, 20, "brick") -- row 20: [1280, 1344)
    H.add_bullet(w, 1, 1264, 1344, "up", 64) -- ends at [1280, 1312)
    H.add_bullet(w, 3, 1264, 1200, "down", 64) -- ends at [1264, 1296)
    local before = world.copy_cells(w.cells)
    local events = H.run(w, 1, nil)
    assert.are.equal(1, #H.of_type(events, "bullet_cancel"))
    assert.are.same({}, H.of_type(events, "bullet_hit_solid"))
    assert.are.same({}, H.changed(before, w.cells))
  end)

  it("destruction takes effect for movement on the next tick", function()
    local w = new_world()
    H.fill(w, 0, 22, 51, 23, "brick") -- 2 cells thick, bottom at 1536
    local p1 = w.tanks[1]
    p1.x, p1.y = 1152, 1536
    -- a 2-cell hole is too narrow for a tank
    for _ = 1, 2 do
      H.run(w, 1, H.frame({ dir = "up", press = true }))
      settle(w)
    end
    assert.are.equal(0, H.cell(w, 19, 22))
    H.run(w, 20, H.frame("up"))
    assert.are.equal(1536, p1.y)
    -- widen the opening from the neighbouring grid positions: strips 17-18
    -- (from x = 1024) and 21-22 (from x = 1280) give cells 17..22 open
    for _, x in ipairs({ 1024, 1280 }) do
      p1.x = x
      for _ = 1, 2 do
        H.run(w, 1, H.frame({ dir = "up", press = true }))
        settle(w)
      end
    end
    p1.x = 1152
    H.run(w, 30, H.frame("up"))
    assert.is_true(p1.y < 1536 - 128) -- passed through the dug opening
  end)
end)

describe("steel and power bullets (G2-D3)", function()
  local function steel_world(level, extra)
    local w = new_world({ player_level = level, tuning = extra })
    H.fill(w, 10, 20, 30, 21, "steel") -- aligned 2 x 2 blocks: rows 20-21
    local p1 = w.tanks[1]
    p1.x, p1.y = 1152, 1408 -- touching the steel (bottom at 1408)
    return w, p1
  end

  for level = 0, 2 do
    it("absorbs bullets at level " .. level, function()
      local w = steel_world(level)
      local n = H.count(w, "steel")
      local events = H.run(w, 1, H.frame({ dir = "up", press = true }))
      local hits = H.of_type(events, "bullet_hit_solid")
      assert.are.same({ "solid", "steel" }, { hits[1].kind, hits[1].terrain })
      assert.are.equal(n, H.count(w, "steel"))
      assert.are.same({}, H.of_type(events, "terrain_destroyed"))
    end)
  end

  it("a level-3 shot removes the two aligned 2 x 2 blocks it straddles", function()
    local w = steel_world(3)
    local before = world.copy_cells(w.cells)
    local events = H.run(w, 1, H.frame({ press = true }))
    local changed = H.changed(before, w.cells)
    -- 1 tile wide x 1/2 tile deep: cells 18..21 x rows 20..21
    assert.are.same(
      { "18,20", "18,21", "19,20", "19,21", "20,20", "20,21", "21,20", "21,21" },
      changed
    )
    local d = destroyed(events)
    assert.are.equal(1, #d)
    assert.are.equal("steel", d[1][2])
  end)

  it("a level-3 strip inside one block removes that block only", function()
    local w = new_world({ player_level = 3 })
    H.fill(w, 10, 20, 30, 21, "steel")
    H.add_bullet(w, 1, 1200, 1500, "up", 34, true) -- center 1216 -> cells 18, 19
    local _, changed = settle(w)
    assert.are.same({ "18,20", "18,21", "19,20", "19,21" }, changed)
  end)

  it("respects steel_break_level", function()
    local w = steel_world(2, { steel_break_level = 2 })
    local n = H.count(w, "steel")
    H.run(w, 1, H.frame({ press = true }))
    assert.are.equal(n - 8, H.count(w, "steel"))
  end)

  it("never destroys block, not even with power", function()
    local w = new_world({ player_level = 3 })
    H.fill(w, 10, 20, 30, 21, "block")
    local p1 = w.tanks[1]
    p1.x, p1.y = 1152, 1408
    local events = H.run(w, 1, H.frame({ press = true }))
    local hits = H.of_type(events, "bullet_hit_solid")
    assert.are.same({ "solid", "block" }, { hits[1].kind, hits[1].terrain })
    assert.are.equal(42, H.count(w, "block"))
    assert.are.same({}, H.of_type(events, "terrain_destroyed"))
  end)

  it("brick behind steel survives a normal depth-2 shot and falls to power", function()
    for _, power in ipairs({ false, true }) do
      local w = new_world({ tuning = { brick_strip_depth = 2 } })
      H.fill(w, 10, 21, 30, 21, "steel") -- steel line nearest the shooter
      H.fill(w, 10, 20, 30, 20, "brick") -- brick behind it
      H.add_bullet(w, 1, 1264, 1500, "up", 17, power)
      local events, changed = settle(w)
      if power then
        assert.are.same({ "18,21", "19,20", "19,21", "20,20", "20,21", "21,21" }, changed)
        local d = destroyed(events)
        assert.are.same({ "brick", "steel" }, { d[1][2], d[2][2] }) -- brick first
      else
        assert.are.same({}, changed)
      end
    end
  end)

  it("mixed steel and brick under one footprint: precedence and two events", function()
    for _, power in ipairs({ false, true }) do
      local w = new_world()
      H.fill(w, 10, 20, 30, 21, "brick")
      H.fill(w, 18, 20, 19, 21, "steel") -- block left of the boundary 1280
      local b = H.add_bullet(w, 1, 1264, 1500, "up", 17, power)
      local events, changed = settle(w)
      local hits = H.of_type(events, "bullet_hit_solid")
      assert.are.equal("steel", hits[1].terrain)
      assert.are.equal(idx(19, 21), hits[1].cell)
      if power then
        assert.are.same({ "18,20", "18,21", "19,20", "19,21", "20,21" }, changed)
        assert.are.same({
          { b.id, "brick", { idx(20, 21) } },
          { b.id, "steel", { idx(18, 20), idx(19, 20), idx(18, 21), idx(19, 21) } },
        }, destroyed(events))
      else
        assert.are.same({ "20,21" }, changed)
        assert.are.same({ { b.id, "brick", { idx(20, 21) } } }, destroyed(events))
      end
    end
  end)

  it("a power bullet's brick strip is the same as at level 0", function()
    local results = {}
    for _, power in ipairs({ false, true }) do
      local w = new_world()
      H.fill(w, 10, 20, 30, 21, "brick")
      H.add_bullet(w, 1, 1264, 1500, "up", 17, power)
      local _, changed = settle(w)
      results[#results + 1] = changed
    end
    assert.are.same(results[1], results[2])
  end)

  it("marks player shots from steel_break_level as power, never dummy shots", function()
    local w = new_world({ player_level = 3, dummies = { { "turret", 20, 0 } } })
    H.run(w, 1, H.frame({ press = true }))
    assert.is_true(w.bullets[1].power)
    w = new_world({ player_level = 2 })
    H.run(w, 1, H.frame({ press = true }))
    assert.is_nil(w.bullets[1].power)
    -- the turret fires at turret_first_shot
    w = new_world({ player_level = 3, dummies = { { "turret", 20, 0 } } })
    H.run(w, w.tuning.turret_first_shot, nil)
    assert.is_nil(w.bullets[1].power)
  end)
end)

describe("bullet footprint versus the destruction strip (review P2-2)", function()
  -- Blocking cells under the footprint in the impact line, for a bullet
  -- over solid brick.
  local function touched(hit, b)
    local d = require("src.sim.units").DIRS[b.dir]
    local vertical = d.dx == 0
    local px = vertical and b.x or b.y
    local out = {}
    for p = math.floor(px / 64), math.floor((px + b.size - 1) / 64) do
      out[#out + 1] = vertical and idx(p, hit.line) or idx(hit.line, p)
    end
    return out
  end

  local function solid_brick()
    local cells = {}
    for i = 1, 52 * 52 do
      cells[i] = H.CODE.brick
    end
    return cells
  end

  it(
    "every supported bullet size, at every alignment, destroys all the brick it touches",
    function()
      local tu = H.tuning()
      local cells = solid_brick()
      local misses = {}
      for size = 8, 64 do
        for off = 0, 63 do
          for _, dir in ipairs({ "up", "down", "left", "right" }) do
            local b = { size = size, dir = dir }
            if dir == "up" or dir == "down" then
              b.x, b.y = 1216 + off, 1500
            else
              b.x, b.y = 1500, 1216 + off
            end
            local hit = destruction.impact(cells, b, tu)
            local removed = {}
            for _, i in ipairs(hit.brick) do
              removed[i] = true
            end
            for _, i in ipairs(touched(hit, b)) do
              if not removed[i] then
                misses[#misses + 1] = ("size %d offset %d %s"):format(size, off, dir)
              end
            end
          end
        end
      end
      assert.are.same({}, misses)
    end
  )

  it("rejects the previously accepted oversized bullets (65..128 u)", function()
    local tuning = require("src.sim.tuning")
    local v = tuning.load().values
    for _, size in ipairs({ 65, 96, 128 }) do
      local c = tuning.copy(v)
      c.bullet_size = size
      assert.is_nil((tuning.check_values(c)), size)
    end
    for _, size in ipairs({ 8, 32, 64 }) do
      local c = tuning.copy(v)
      c.bullet_size = size
      assert.is_true(tuning.check_values(c), size)
    end
    assert.are.equal(32, v.bullet_size) -- the committed default is unchanged
    -- why: at 128 u an off-boundary bullet touches brick outside its strip
    local b = { x = 1200, y = 1500, size = 128, dir = "up" } -- center 1264 -> strip 19, 20
    local hit = destruction.impact(solid_brick(), b, H.tuning())
    assert.are.same({ idx(19, hit.line), idx(20, hit.line) }, hit.brick)
    assert.are.same({ idx(18, hit.line), idx(19, hit.line), idx(20, hit.line) }, touched(hit, b))
  end)
end)

describe("no tunnelling through cell remnants", function()
  -- A 1-cell-thick line of brick or steel; bullets at speeds up to 512 u/tick
  -- and 64 phase offsets, in all four directions, must hit it.
  local SPEEDS = { 17, 34, 63, 64, 65, 127, 128, 200, 255, 256, 384, 511, 512 }
  local DIRS = {
    up = { wall = { 0, 25, 51, 25 }, x = 1264, y0 = 1700, axis = "y", sign = 1 },
    down = { wall = { 0, 25, 51, 25 }, x = 1264, y0 = 1300, axis = "y", sign = -1 },
    left = { wall = { 25, 0, 25, 51 }, y = 1264, x0 = 1700, axis = "x", sign = 1 },
    right = { wall = { 25, 0, 25, 51 }, y = 1264, x0 = 1300, axis = "x", sign = -1 },
  }
  for _, kind in ipairs({ "brick", "steel" }) do
    it("holds for 1-cell " .. kind .. " at 13 speeds x 64 offsets x 4 directions", function()
      local built =
        require("src.sim.arena").build(H.arena_data({}, H.entities({ 0, 24 }, { 24, 24 })))
      local tu = H.tuning()
      local code = H.CODE[kind]
      local fails = {}
      for _, dir in ipairs({ "up", "down", "left", "right" }) do
        local d = DIRS[dir]
        for _, speed in ipairs(SPEEDS) do
          for off = 0, 63 do
            local w = sim.new({ arena = built, tuning = tu })
            for r = d.wall[2], d.wall[4] do
              for c = d.wall[1], d.wall[3] do
                w.cells[idx(c, r)] = code
              end
            end
            if d.axis == "y" then
              H.add_bullet(w, 1, d.x, d.y0 + d.sign * off, dir, speed)
            else
              H.add_bullet(w, 1, d.x0 + d.sign * off, d.y, dir, speed)
            end
            local hit
            for _ = 1, 40 do
              sim.step(w, nil)
              for _, e in ipairs(w.events:drain()) do
                if e.type == "bullet_hit_solid" then
                  hit = e
                end
              end
              if hit then
                break
              end
            end
            if not hit or hit.kind ~= "solid" or hit.terrain ~= kind then
              fails[#fails + 1] = ("%s speed %d offset %d"):format(dir, speed, off)
            end
          end
        end
      end
      assert.are.same({}, fails)
    end)
  end
end)
