-- Tank movement scenarios (TECHNICAL_DESIGN §6, G1 plan §4). Each scenario
-- drives sim.step with InputFrames and asserts positions, facings and the
-- no-overlap invariant on every tick (helpers.run).

local H = require("tests.sim.helpers")
local sim = require("src.sim.sim")
local rng = require("src.core.rng")
local mapper = require("src.input.mapper")
local bindings = require("config.bindings")

local F = H.frame

local function empty_arena(p1, p2, dummies)
  return H.arena_data({}, H.entities(p1, p2, dummies))
end

describe("sim movement", function()
  it("starts and stops instantly, one speed step per tick", function()
    local w = H.world({ arena = empty_arena({ 12, 12 }, { 0, 0 }) })
    local p1 = w.tanks[1]
    H.run(w, 1, F("up"))
    assert.are.same({ 1536, 1530, "up" }, { p1.x, p1.y, p1.facing })
    H.run(w, 5, F(nil))
    assert.are.same({ 1536, 1530 }, { p1.x, p1.y })
    H.run(w, 3, F("left"))
    -- the turn snapped y back to the 128 grid before moving
    assert.are.same({ 1536 - 18, 1536, "left" }, { p1.x, p1.y, p1.facing })
  end)

  it("stops exactly at contact with a wall (clamp to contact)", function()
    local rows = {}
    rows[6] = "XXXXXXXXXXXXX" -- tile row 5: y 1280..1536
    local w = H.world({ arena = H.arena_data(rows, H.entities({ 0, 14 }, { 24, 24 })) })
    local p1 = w.tanks[1]
    H.run(w, 42, F("up"))
    assert.are.equal(1792 - 42 * 6, p1.y) -- 1540: 4 u from the wall
    H.run(w, 1, F("up"))
    assert.are.equal(1536, p1.y) -- moved only the 4 u to contact
    H.run(w, 50, F("up"))
    assert.are.equal(1536, p1.y)
  end)

  it("stops at the field bounds", function()
    local w = H.world({ arena = empty_arena({ 0, 2 }, { 24, 24 }) })
    local p1 = w.tanks[1]
    H.run(w, 100, F("up"))
    assert.are.equal(0, p1.y)
    H.run(w, 10, F("left"))
    assert.are.same({ 0, 0 }, { p1.x, p1.y })
    H.run(w, 1000, F("right"))
    assert.are.equal(3328 - 256, p1.x)
  end)

  it("stops at contact with another tank; earlier tanks move first", function()
    local w = H.world({ arena = empty_arena({ 0, 20 }, { 0, 10 }) })
    local p1, p2 = w.tanks[1], w.tanks[2]
    -- gap 1024 u, closing at 12 u/tick: P1 takes the last 4 u, P2 is blocked
    H.run(w, 200, F("up", "down"))
    assert.are.equal(2560 - 85 * 6 - 4, p1.y)
    assert.are.equal(1280 + 85 * 6, p2.y)
    assert.are.equal(p1.y, p2.y + 256)
  end)

  it("enters a 1-tile lane on the first try from anywhere within half a snap", function()
    local rows = {}
    rows[5] = "XXXXXX.XXXXXX" -- lane at tile column 6: x 1536..1792
    rows[6] = "XXXXXX.XXXXXX"
    for x = 1473, 1600 do
      local w = H.world({ arena = H.arena_data(rows, H.entities({ 0, 12 }, { 24, 24 })) })
      local p1 = w.tanks[1]
      p1.x = x -- in the corridor below the wall band, moving along it
      H.run(w, 1, F("up"))
      assert.are.same({ 1536, 1536 - 6 }, { p1.x, p1.y }, "x = " .. x)
      H.run(w, 60, F("up"))
      assert.are.same({ 1536, 1536 - 61 * 6 }, { p1.x, p1.y }, "x = " .. x)
    end
  end)

  it("breaks an exact snap tie toward the lower coordinate (up / left)", function()
    local w = H.world({ arena = empty_arena({ 4, 4 }, { 24, 24 }) })
    local p1 = w.tanks[1]
    p1.x, p1.y = 600, 1600 -- 1600 = 12 * 128 + 64, 600 = 4 * 128 + 88
    H.run(w, 1, F("right"))
    assert.are.same({ 606, 1536 }, { p1.x, p1.y })
    p1.x = 576 -- 4 * 128 + 64: tie
    H.run(w, 1, F("down"))
    assert.are.same({ 512, 1542 }, { p1.x, p1.y })
  end)

  it("a blocked snap turns in place, and the snap is still required on later ticks", function()
    -- Regression (G1 plan review): once the facing has changed, the tank
    -- must not skip the snap and move unaligned.
    local w = H.world({ arena = empty_arena({ 2, 12, "right" }, { 0, 12, "right" }) })
    local p1, p2 = w.tanks[1], w.tanks[2]
    H.run(w, 10, F("right"))
    H.run(w, 10, F(nil, "right"))
    assert.are.same({ 316, 60 }, { p1.x, p2.x }) -- touching, P1 unaligned
    -- P1 turns up: the snap target x = 256 would overlap P2 -> no snap, no move
    H.run(w, 1, F("up"))
    assert.are.same({ 316, 1536, "up" }, { p1.x, p1.y, p1.facing })
    -- P2 backs off 6 u per tick; P1 keeps holding up (same as its facing)
    local moved_at
    for tick = 1, 12 do
      H.run(w, 1, F("up", "left"))
      if p1.y ~= 1536 then
        assert.are.equal(0, p1.x % 128, "moved vertically while unaligned")
        moved_at = moved_at or tick
      else
        assert.are.equal(316, p1.x)
      end
    end
    -- P2 clears the snap target box once it is back at x = 0, after 10 ticks:
    -- P1 (which moves first) snaps and moves on tick 11.
    assert.are.equal(11, moved_at)
    assert.are.equal(256, p1.x)
    assert.are.equal(1536 - 2 * 6, p1.y)
  end)

  it("reversing never snaps", function()
    local w = H.world({ arena = empty_arena({ 2, 12, "right" }, { 24, 24 }) })
    local p1 = w.tanks[1]
    H.run(w, 10, F("right"))
    assert.are.equal(316, p1.x)
    H.run(w, 1, F("left"))
    assert.are.same({ 310, 1536 }, { p1.x, p1.y })
    H.run(w, 1, F("up")) -- turn: snaps x to 256
    assert.are.same({ 256, 1530 }, { p1.x, p1.y })
    H.run(w, 1, F("down")) -- reverse along y: no snap of y, x stays
    assert.are.same({ 256, 1536 }, { p1.x, p1.y })
    H.run(w, 1, F("down"))
    assert.are.same({ 256, 1542 }, { p1.x, p1.y })
  end)

  it("follows last-pressed direction through a full turn sequence (mapper -> sim)", function()
    local w = H.world({ arena = empty_arena({ 12, 12 }, { 24, 24 }) })
    local p1 = w.tanks[1]
    local m = mapper.new(bindings)
    local keys = {}
    local function tick(events)
      for _, e in ipairs(events) do
        keys[e.name] = e.kind == "press" or nil
      end
      local frame = m:update({ keys = keys, events = events })
      H.run(w, 1, frame)
      return frame[1].dir
    end
    local function press(k)
      return { kind = "press", device = "key", name = k }
    end
    local function release(k)
      return { kind = "release", device = "key", name = k }
    end
    local trace = {
      tick({ press("w") }),
      tick({}),
      tick({ press("d") }), -- W still held: D is newer
      tick({ release("d") }), -- back to W
      tick({ press("a") }),
      tick({ release("w") }), -- A still held
      tick({ release("a") }),
    }
    assert.are.same({ "up", "up", "right", "up", "left", "left" }, { unpack(trace, 1, 6) })
    assert.is_nil(trace[7])
    -- up x2 (y 1524); right: snap y up to 1536 (offset 116 > 64), x 1542;
    -- up: snap x to 1536, y 1530; left: snap y to 1536, x 1530; left: x 1524
    assert.are.same({ 1524, 1536, "left" }, { p1.x, p1.y, p1.facing })
  end)

  it("random driving never overlaps geometry and only moves along aligned axes", function()
    local w = H.world({ seed = 7 })
    local r = rng.new(12345)
    local dirs = { "up", "down", "left", "right", false }
    local hold = { 0, 0 }
    local current = { false, false }
    for _ = 1, 3000 do
      for p = 1, 2 do
        if hold[p] == 0 then
          current[p] = dirs[r:range(1, 5)]
          hold[p] = r:range(1, 40)
        end
        hold[p] = hold[p] - 1
      end
      local before = {}
      for i, t in ipairs(w.tanks) do
        before[i] = { t.x, t.y }
      end
      sim.step(w, F(current[1] or nil, current[2] or nil))
      H.assert_invariants(w)
      for i, t in ipairs(w.tanks) do
        local dx, dy = t.x - before[i][1], t.y - before[i][2]
        assert.is_true(math.abs(dx) <= 64 + 6 and math.abs(dy) <= 64 + 6)
        if dx ~= 0 and dy == 0 then
          assert.are.equal(0, t.y % 128)
        elseif dy ~= 0 and dx == 0 then
          assert.are.equal(0, t.x % 128)
        elseif dx ~= 0 and dy ~= 0 then
          -- a snap on one axis plus a move on the other
          assert.is_true(t.x % 128 == 0 or t.y % 128 == 0)
        end
      end
      w.events:drain()
    end
  end)
end)
