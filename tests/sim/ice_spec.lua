-- Ice (G2 plan §7, G2-D4, clarification C6): the slide trigger, distance and
-- end conditions, facing during a slide, no re-trigger, snap-only moves, and
-- clearing by a hit. Every tick asserts the invariants.

local H = require("tests.sim.helpers")
local move = require("src.sim.move")

local SPEED = H.tuning().player_speed -- 7, approved
local DIST = H.tuning().ice_slide_distance -- 192, UNV

-- P1 at x = 1536, y = 2560 on a large ice field (cells 10..41 x 10..51).
local function ice_world(opts)
  opts = opts or {}
  local w = H.world({
    arena = H.arena_data({}, H.entities({ 12, 20 }, opts.p2 or { 0, 0 }, opts.dummies)),
    tuning = opts.tuning,
  })
  H.fill(w, 10, opts.ice_top or 10, 41, 51, "ice")
  return w, w.tanks[1]
end

-- Runs `n` ticks with P1 input `p1` (direction or frame spec); returns the
-- per-tick P1 y (or x) displacement list.
local function track(w, n, p1, axis, p2)
  local t = w.tanks[1]
  local moves = {}
  for _ = 1, n do
    local before = t[axis or "y"]
    H.run(w, 1, H.frame(p1, p2))
    moves[#moves + 1] = t[axis or "y"] - before
  end
  return moves
end

local function sum(list)
  local s = 0
  for _, v in ipairs(list) do
    s = s + v
  end
  return s
end

describe("ice slide", function()
  it("slides ice_slide_distance after input stops, moving on the trigger tick", function()
    local w, p1 = ice_world()
    H.run(w, 30, H.frame("up"))
    assert.are.equal(2560 - 30 * SPEED, p1.y)
    assert.are.equal("up", p1.ice_dir)
    local moves = track(w, 40, nil)
    assert.are.equal(-SPEED, moves[1]) -- the slide moves on the trigger tick
    assert.are.equal(-DIST, sum(moves))
    -- 192 = 27 x 7 + 3: tick 28 moves the last 3 u, then nothing
    local n = math.ceil(DIST / SPEED)
    assert.are.equal(-(DIST - (n - 1) * SPEED), moves[n])
    for i = n + 1, 40 do
      assert.are.equal(0, moves[i], "tick " .. i) -- regression: no re-trigger, no glide
    end
    assert.is_nil(p1.slide_dir)
    assert.is_nil(p1.ice_dir)
    assert.are.equal(0, p1.slide_rem)
  end)

  it("ends at contact with steel, using that tick (slide to contact)", function()
    local w, p1 = ice_world()
    H.fill(w, 10, 35, 41, 35, "steel") -- bottom edge at y = 2304
    H.run(w, 30, H.frame("up")) -- y = 2350
    local moves = track(w, 12, nil)
    assert.are.equal(2304, p1.y) -- clamped to contact, 46 u < 192
    assert.are.equal(-46, sum(moves))
    assert.is_nil(p1.slide_dir) -- ended by the 0 u step
    -- after contact, a perpendicular input moves normally
    local m = track(w, 1, "left", "x")
    assert.are.equal(-SPEED, m[1])
  end)

  it("ends at contact with water", function()
    local w, p1 = ice_world()
    H.fill(w, 34, 10, 34, 51, "water") -- column [2176, 2240): contact at x = 1920
    H.run(w, 40, H.frame("right")) -- x = 1536 + 280 = 1816
    track(w, 30, nil, "x")
    assert.are.equal(1920, p1.x)
    assert.is_nil(p1.slide_dir)
  end)

  it("ends when the tank is off ice at the start of a tick; input then runs at once", function()
    local w, p1 = ice_world({ ice_top = 36 }) -- ice only below y = 2304
    H.run(w, 66, H.frame("up")) -- y = 2560 - 462 = 2098, still on ice (box to 2354)
    assert.are.equal(2098, p1.y)
    local moves = track(w, 7, nil) -- y 2049: still overlapping the ice row
    assert.are.equal(-49, sum(moves))
    track(w, 1, nil) -- y 2042: off ice now
    assert.are.equal(2042, p1.y)
    assert.is_truthy(p1.slide_dir) -- ends at the start of the next tick
    local m = track(w, 1, "left", "x")
    assert.are.equal(-SPEED, m[1]) -- the slide ended and "left" moved normally
    assert.are.equal(move.snap_target(2042), p1.y) -- including its snap
    assert.is_nil(p1.slide_dir)
  end)

  it("is cancelled by the same direction, which moves normally on that tick", function()
    local w, p1 = ice_world()
    H.run(w, 30, H.frame("up"))
    local y0 = p1.y
    track(w, 5, nil) -- slide 35 u
    assert.are.equal("up", p1.slide_dir)
    local moves = track(w, 40, "up")
    assert.is_nil(p1.slide_dir)
    for i = 1, 40 do
      assert.are.equal(-SPEED, moves[i]) -- full speed: normal movement every tick
    end
    assert.are.equal(y0 - 35 - 40 * SPEED, p1.y)
    -- the next release slides the full distance again
    moves = track(w, 40, nil)
    assert.are.equal(-DIST, sum(moves))
  end)

  for _, case in ipairs({ { "perpendicular", "right" }, { "reverse", "down" } }) do
    it("a " .. case[1] .. " input triggers the slide; the facing follows the input", function()
      local w, p1 = ice_world()
      H.run(w, 30, H.frame("up"))
      local x0, y0 = p1.x, p1.y
      local n = math.ceil(DIST / SPEED)
      for i = 1, n do
        H.run(w, 1, H.frame(case[2]))
        assert.are.equal(case[2], p1.facing, "tick " .. i)
        assert.are.equal(x0, p1.x) -- the slide keeps its axis
      end
      assert.are.equal(y0 - DIST, p1.y)
      assert.is_nil(p1.slide_dir)
      -- the slide ended by distance during a tick: the input moves normally
      -- from the next tick
      H.run(w, 1, H.frame(case[2]))
      if case[2] == "right" then
        assert.are.same({ x0 + SPEED, move.snap_target(y0 - DIST) }, { p1.x, p1.y })
      else
        assert.are.same({ x0, y0 - DIST + SPEED }, { p1.x, p1.y })
      end
    end)
  end

  it("a shot during the slide leaves in the new facing", function()
    local w, p1 = ice_world()
    H.run(w, 30, H.frame("up"))
    H.run(w, 3, H.frame("left"))
    assert.is_truthy(p1.slide_dir)
    local events = H.run(w, 1, H.frame({ dir = "left", press = true }))
    local shots = H.of_type(events, "shot")
    assert.are.equal("left", shots[1].dir)
    assert.are.equal("left", w.bullets[1].dir)
  end)

  it("a hit or a respawn clears all ice state", function()
    local w, p1 = ice_world({ dummies = { { "target", 2, 2 } } })
    H.run(w, 30, H.frame("up"))
    H.run(w, 2, nil)
    assert.are.equal("up", p1.slide_dir)
    -- an enemy-faction bullet right above P1
    H.add_bullet(w, 3, p1.x + 112, p1.y - 40, "down", 17)
    H.run(w, 1, nil)
    assert.is_false(p1.present)
    assert.are.same({ nil, nil, 0 }, { p1.ice_dir, p1.slide_dir, p1.slide_rem })
    H.run(w, 1, nil) -- respawn on the next tick, on ice, with no slide
    assert.is_true(p1.present)
    assert.are.same({ 1536, 2560 }, { p1.x, p1.y })
    local moves = track(w, 10, nil)
    assert.are.equal(0, sum(moves))
  end)

  it("ice_slide_distance = 0 disables sliding", function()
    local w, p1 = ice_world({ tuning = { ice_slide_distance = 0 } })
    H.run(w, 30, H.frame("up"))
    local moves = track(w, 10, nil)
    assert.are.equal(0, sum(moves))
    assert.is_nil(p1.slide_dir)
  end)

  it("any ice cell under the box counts as on ice", function()
    local w = H.world({ arena = H.arena_data({}, H.entities({ 12, 20 }, { 0, 0 })) })
    local p1 = w.tanks[1]
    H.set(w, 27, 38, "ice") -- one cell, inside the box after moving up 64 u
    H.run(w, 10, H.frame("up")) -- y = 2490: box [2490, 2746) reaches row 38 (2432..2495)
    assert.are.equal("up", p1.ice_dir)
    -- on ice while the box overlaps row 38, i.e. 2176 < y < 2496: the whole
    -- slide (to y = 2298) stays on that one cell
    assert.are.equal(-DIST, sum(track(w, 30, nil)))
  end)

  it("plain ground never arms ice_dir", function()
    local w = H.world({ arena = H.arena_data({}, H.entities({ 12, 20 }, { 0, 0 })) })
    local p1 = w.tanks[1]
    H.run(w, 10, H.frame("up"))
    assert.is_nil(p1.ice_dir)
    assert.are.equal(0, sum(track(w, 10, nil)))
  end)
end)

describe("ice_dir arming (clarification C6)", function()
  it("a snap-only move (forward 0) does not arm ice_dir", function()
    -- P2 sits right above P1's snapped position: P1's snap to x = 1536
    -- succeeds, but its forward move up is 0. P2 then drives away, so a
    -- wrongly armed ice_dir would make P1 slide up on the next tick.
    local w, p1 = ice_world({ p2 = { 12, 18 } })
    local p2 = w.tanks[2]
    p1.x = 1568 -- 32 u right of the grid: the snap goes left
    assert.are.same({ 1536, 2304 }, { p2.x, p2.y }) -- P2 box ends at y = 2560
    H.run(w, 1, H.frame("up", "up"))
    assert.are.same({ 1536, 2560 }, { p1.x, p1.y }) -- snapped, no forward move
    assert.is_nil(p1.ice_dir)
    local moves = track(w, 10, nil, "y", "up")
    assert.are.equal(0, sum(moves)) -- no slide although the way is now free
  end)

  it("a stopped move (contact) clears ice_dir", function()
    local w, p1 = ice_world()
    H.fill(w, 10, 35, 41, 35, "steel") -- bottom at y = 2304
    H.run(w, 5, H.frame("up"))
    assert.are.equal("up", p1.ice_dir)
    H.run(w, 40, H.frame("up")) -- reaches contact, then "stopped"
    assert.are.equal(2304, p1.y)
    assert.is_nil(p1.ice_dir)
    assert.are.equal(0, sum(track(w, 5, nil)))
  end)
end)
