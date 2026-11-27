-- Shooting scenarios (G1 plan §5): one shot per press, bullet limits per
-- upgrade level, spawn position, muzzle obstruction, hits on walls, bounds
-- and dummies, same-faction pass-through.

local H = require("tests.sim.helpers")

local F = H.frame
local PRESS = { press = true }
local HOLD = { fire = true }

local function count(events, kind)
  return #H.of_type(events, kind)
end

describe("sim shooting", function()
  it("fires exactly one shot per press; holding fire does not repeat", function()
    local w = H.world({ arena = H.arena_data({}, H.entities({ 12, 12 }, { 24, 24 })) })
    assert.are.equal(1, count(H.run(w, 1, F(PRESS)), "shot"))
    assert.are.equal(0, count(H.run(w, 200, F(HOLD)), "shot"))
    local again = H.run(w, 1, F(PRESS))
    assert.are.equal(1, count(again, "shot"))
  end)

  for _, case in ipairs({
    { level = 0, limit = 1, speed = 17 },
    { level = 1, limit = 1, speed = 34 },
    { level = 2, limit = 2, speed = 34 },
    { level = 3, limit = 2, speed = 34 },
  }) do
    it(
      ("level %d: %d active bullet(s) at %d u/tick"):format(case.level, case.limit, case.speed),
      function()
        local w = H.world({
          arena = H.arena_data({}, H.entities({ 12, 22 }, { 24, 24 })),
          tuning = { arena_player_level = case.level },
        })
        local shots = 0
        for _ = 1, 4 do
          shots = shots + count(H.run(w, 1, F(PRESS)), "shot")
          H.run(w, 1, F(nil)) -- release between presses
        end
        assert.are.equal(case.limit, shots)
        assert.are.equal(case.limit, #w.bullets)
        for _, b in ipairs(w.bullets) do
          assert.are.equal(case.speed, b.speed)
        end
      end
    )
  end

  it("spawns the bullet centered on the front edge for every facing", function()
    local expected = {
      up = { 1536 + 112, 1536 - 32 },
      down = { 1536 + 112, 1536 + 256 },
      left = { 1536 - 32, 1536 + 112 },
      right = { 1536 + 256, 1536 + 112 },
    }
    for dir, pos in pairs(expected) do
      local w = H.world({ arena = H.arena_data({}, H.entities({ 12, 12, dir }, { 24, 24 })) })
      local shot = H.of_type(H.run(w, 1, F(PRESS)), "shot")[1]
      assert.are.same({ pos[1] + 16, pos[2] + 16, dir }, { shot.x, shot.y, shot.dir }, dir)
      -- the bullet already moved once in the spawn tick's bullet phase
      local b = w.bullets[1]
      local dx = ({ left = -17, right = 17 })[dir] or 0
      local dy = ({ up = -17, down = 17 })[dir] or 0
      assert.are.same({ pos[1] + dx, pos[2] + dy }, { b.x, b.y }, dir)
    end
  end)

  describe("muzzle obstruction", function()
    it("a wall touching the muzzle is hit on spawn, without travel", function()
      local rows = {}
      rows[6] = "XXXXXXXXXXXXX" -- bottom edge at y = 1536
      local w = H.world({ arena = H.arena_data(rows, H.entities({ 12, 12 }, { 24, 24 })) })
      local ev = H.run(w, 1, F(PRESS))
      local hit = H.of_type(ev, "bullet_hit_solid")[1]
      assert.are.same({ "solid", true }, { hit.kind, hit.at_spawn })
      assert.are.equal(1, count(ev, "shot"))
      assert.are.equal(0, #w.bullets)
      -- the slot is free again: the next press fires (and hits) again
      assert.are.equal(1, count(H.run(w, 1, F(PRESS)), "bullet_hit_solid"))
    end)

    it("the field bound is hit on spawn", function()
      local w = H.world({ arena = H.arena_data({}, H.entities({ 12, 0 }, { 24, 24 })) })
      local hit = H.of_type(H.run(w, 1, F(PRESS)), "bullet_hit_solid")[1]
      assert.are.same({ "bound", true }, { hit.kind, hit.at_spawn })
      assert.are.equal(0, #w.bullets)
    end)

    it("an opposing bullet in the muzzle box cancels with the new bullet", function()
      local w = H.world({
        arena = H.arena_data({}, H.entities({ 12, 12 }, { 24, 24 }, { { "target", 0, 0 } })),
      })
      local enemy = H.add_bullet(w, 3, 1536 + 112, 1536 - 40, "up", 17) -- overlaps the muzzle
      local ev = H.run(w, 1, F(PRESS))
      local c = H.of_type(ev, "bullet_cancel")[1]
      assert.is_truthy(c)
      assert.are.same({ 2, enemy.id }, { c.a, c.b }) -- new bullet first
      assert.are.equal(0, #w.bullets)
    end)

    it("an adjacent tank is hit on spawn", function()
      local w = H.world({
        arena = H.arena_data({}, H.entities({ 12, 12 }, { 24, 24 }, { { "target", 12, 10 } })),
      })
      local ev = H.run(w, 1, F(PRESS))
      local hit = H.of_type(ev, "tank_hit")[1]
      assert.are.same({ 3, 1, false }, { hit.tank, hit.by, hit.friendly })
      assert.are.equal(1, w.tanks[3].hits)
      assert.is_true(w.tanks[3].present) -- dummies are never destroyed
      assert.are.equal(0, #w.bullets)
    end)
  end)

  it("bullets hit walls after travel, reporting the solid cell", function()
    local rows = {}
    rows[2] = "XXXXXXXXXXXXX" -- tile row 1: y 256..512
    local w = H.world({ arena = H.arena_data(rows, H.entities({ 12, 12 }, { 24, 24 })) })
    local ev = H.run(w, 70, function(tick)
      return F(tick == 1 and PRESS or nil)
    end)
    local hit = H.of_type(ev, "bullet_hit_solid")[1]
    assert.are.same({ "solid", false }, { hit.kind, hit.at_spawn })
    -- 1504 -> first overlap with y < 512 after 59 ticks of 17 u
    assert.are.equal(59, hit.tick)
    assert.are.equal(7 * 52 + 25 + 1, hit.cell) -- cell row 7, column 25 (x 1600..1664)
    assert.are.equal(0, #w.bullets)
  end)

  it("bullets hit the field bound", function()
    local w = H.world({ arena = H.arena_data({}, H.entities({ 0, 12, "left" }, { 24, 24 })) })
    local ev = H.run(w, 5, F(PRESS))
    local hit = H.of_type(ev, "bullet_hit_solid")[1]
    assert.are.same({ "bound", true }, { hit.kind, hit.at_spawn })
    w = H.world({ arena = H.arena_data({}, H.entities({ 2, 12, "left" }, { 24, 24 })) })
    ev = H.run(w, 30, function(tick)
      return F(tick == 1 and PRESS or nil)
    end)
    hit = H.of_type(ev, "bullet_hit_solid")[1]
    assert.are.same({ "bound", false, 14 }, { hit.kind, hit.at_spawn, hit.tick })
  end)

  it("bullets hit dummies, which count hits and stay", function()
    local w = H.world({
      arena = H.arena_data({}, H.entities({ 12, 20 }, { 24, 24 }, { { "target", 12, 2 } })),
    })
    -- each bullet needs 119 ticks to reach the dummy (limit 1 at level 0)
    local ev = H.run(w, 400, function(tick)
      return F(tick % 130 == 1 and PRESS or nil)
    end)
    local hits = H.of_type(ev, "tank_hit")
    assert.are.equal(3, #hits)
    for _, h in ipairs(hits) do
      assert.are.same({ 3, 1, false }, { h.tank, h.by, h.friendly })
    end
    assert.are.equal(3, w.tanks[3].hits)
    assert.is_true(w.tanks[3].present)
  end)

  it("same-faction bullets pass through each other; a friendly hit has no effect", function()
    local w = H.world({
      arena = H.arena_data({}, H.entities({ 2, 12, "right" }, { 20, 12, "left" })),
    })
    local ev = H.run(w, 150, function(tick)
      return F(tick == 1 and PRESS or nil, tick == 1 and PRESS or nil)
    end)
    assert.are.equal(0, count(ev, "bullet_cancel"))
    local hits = H.of_type(ev, "tank_hit")
    assert.are.equal(2, #hits)
    for _, h in ipairs(hits) do
      assert.is_true(h.friendly)
    end
    assert.is_true(w.tanks[1].present and w.tanks[2].present)
    assert.are.same({ 0, 0 }, { w.tanks[1].hits, w.tanks[2].hits })
  end)
end)
