-- Bullet collision scenarios (TECHNICAL_DESIGN §6): no tunnelling at any
-- speed or phase, no false cancellation of perpendicular bullets, and the
-- simultaneous-hit rules.

local H = require("tests.sim.helpers")
local sim = require("src.sim.sim")
local geom = require("src.sim.geom")
local bullets = require("src.sim.bullets")
local rng = require("src.core.rng")

local F = H.frame

-- Players at the bottom and two targets (ids 3 and 4) as owners of
-- enemy bullets, all out of the way of the test bullets.
local BUILT, TUNING
local function world()
  if not BUILT then
    BUILT = require("src.sim.arena").build(
      H.arena_data(
        {},
        H.entities({ 0, 24 }, { 4, 24 }, { { "target", 24, 24 }, { "target", 20, 24 } })
      )
    )
    TUNING = H.tuning()
  end
  return sim.new({ arena = BUILT, tuning = TUNING })
end

-- Brute-force reference for geom.sweep_overlap: samples t = k / D with a
-- denominator that hits a point strictly inside every non-empty overlap
-- interval (interval ends are multiples of 1 / |v| per axis).
local function brute(ax, ay, aw, ah, adx, ady, bx, by, bw, bh, bdx, bdy)
  local vx, vy = math.abs(adx - bdx), math.abs(ady - bdy)
  local d = 2 * math.max(vx, 1) * math.max(vy, 1)
  for k = 0, d do
    -- positions scaled by d stay integers
    local x1, y1 = ax * d + adx * k, ay * d + ady * k
    local x2, y2 = bx * d + bdx * k, by * d + bdy * k
    if geom.overlaps(x1, y1, aw * d, ah * d, x2, y2, bw * d, bh * d) then
      return true
    end
  end
  return false
end

describe("sim bullet collisions", function()
  it("sweep_overlap agrees with a brute-force reference", function()
    local r = rng.new(99)
    local function v()
      return r:range(-40, 40)
    end
    for _ = 1, 3000 do
      local args = {
        r:range(0, 200),
        r:range(0, 200),
        32,
        32,
        v(),
        v(),
        r:range(0, 200),
        r:range(0, 200),
        32,
        32,
        v(),
        v(),
      }
      assert.are.equal(
        brute(unpack(args)),
        geom.sweep_overlap(unpack(args)),
        table.concat(args, ",")
      )
    end
  end)

  it("splits a bullet's speed into sub-steps of at most 64 u, remainder first", function()
    assert.are.same(
      { 44, 43, 43 },
      { bullets.part(130, 1, 3), bullets.part(130, 2, 3), bullets.part(130, 3, 3) }
    )
    assert.are.same({ 33, 32 }, { bullets.part(65, 1, 2), bullets.part(65, 2, 2) })
    for _, s in ipairs({ 1, 17, 34, 64, 65, 128, 129, 256, 500 }) do
      local n = math.max(1, math.ceil(s / 64))
      local sum = 0
      for k = 1, n do
        local p = bullets.part(s, k, n)
        assert.is_true(p <= 64)
        sum = sum + p
      end
      assert.are.equal(s, sum)
    end
  end)

  it("head-on bullets cancel at every speed pair and phase offset (no tunnelling)", function()
    local speeds = { 1, 5, 17, 34, 63, 64, 65, 127, 128, 200, 256 }
    local cases = 0
    for _, s1 in ipairs(speeds) do
      for _, s2 in ipairs(speeds) do
        for offset = 0, 63 do
          local w = world()
          local a = H.add_bullet(w, 1, 1000, 200, "right", s1) -- player faction
          local b = H.add_bullet(w, 3, 1000 + 32 + 300 + offset, 200, "left", s2) -- enemy
          local cancelled = false
          for _ = 1, 400 do
            sim.step(w, nil)
            local ev = w.events:drain()
            if #H.of_type(ev, "bullet_cancel") == 1 then
              cancelled = true
              break
            end
            assert.are.equal(0, #ev, "unexpected event")
            assert.is_true(a.x < b.x, ("passed through: %d/%d offset %d"):format(s1, s2, offset))
          end
          assert.is_true(cancelled, ("no cancel: %d/%d offset %d"):format(s1, s2, offset))
          assert.are.equal(0, #w.bullets)
          cases = cases + 1
        end
      end
    end
    assert.are.equal(11 * 11 * 64, cases)
  end)

  it("fast bullets never tunnel through a half-tile wall or a tank (sub-steps)", function()
    -- one half-tile wall column (128 u thick) at x 2048..2176, rows 0..1 (y 0..256)
    local rows = { string.rep(".", 16) .. "X" .. string.rep(".", 9) }
    rows[2] = rows[1]
    local wall = require("src.sim.arena").build(
      H.arena_data(rows, H.entities({ 0, 24 }, { 4, 24 }, { { "target", 20, 4 } }))
    )
    local tu = H.tuning()
    for _, speed in ipairs({ 64, 65, 128, 200, 256, 512 }) do
      for offset = 0, 127 do
        local w = sim.new({ arena = wall, tuning = tu })
        local b = H.add_bullet(w, 1, 1500 + offset, 100, "right", speed)
        local ev = H.run(w, 10, nil)
        local hit = H.of_type(ev, "bullet_hit_solid")[1]
        assert.is_truthy(hit, ("speed %d offset %d"):format(speed, offset))
        assert.are.equal("solid", hit.kind)
        assert.is_true(b.x < 2176, "passed the wall")
        -- a tank (the target at x 2560..2816, y 512..768) is never skipped
        w = sim.new({ arena = wall, tuning = tu })
        b = H.add_bullet(w, 1, 2200 + offset, 600, "right", speed)
        ev = H.run(w, 10, nil)
        assert.are.equal(
          1,
          #H.of_type(ev, "tank_hit"),
          ("tank: speed %d offset %d"):format(speed, offset)
        )
        assert.is_true(b.x < 2816)
      end
    end
  end)

  it("perpendicular bullets crossing the same region at different times do not cancel", function()
    -- Regression (G1 plan review): their swept boxes overlap within the
    -- sub-step, but the player bullet has left before the enemy bullet
    -- arrives.
    local w = world()
    local a = H.add_bullet(w, 1, 2020, 1000, "right", 64)
    local b = H.add_bullet(w, 3, 2000, 950, "down", 64)
    assert.is_true(geom.overlaps(2020, 1000, 96, 32, 2000, 950, 32, 96)) -- swept boxes
    sim.step(w, nil)
    assert.are.equal(0, #H.of_type(w.events:drain(), "bullet_cancel"))
    assert.are.same({ 2084, 1014 }, { a.x, b.y })
    assert.are.equal(2, #w.bullets)

    -- The same geometry 20 u earlier: they do meet, and cancel.
    w = world()
    H.add_bullet(w, 1, 2000, 1000, "right", 64)
    H.add_bullet(w, 3, 2000, 950, "down", 64)
    sim.step(w, nil)
    assert.are.equal(1, #H.of_type(w.events:drain(), "bullet_cancel"))
  end)

  it("bullet vs bullet runs before bullet vs tank in the same sub-step", function()
    local w = world()
    local target = w.tanks[3]
    target.x, target.y = 1000, 1000 -- box y 1000..1256
    -- the player bullet would end inside the target (y 1250 < 1256) ...
    H.add_bullet(w, 1, 1112, 1280, "up", 30)
    -- ... but meets an enemy bullet in the same sub-step first
    H.add_bullet(w, 4, 1112, 1256, "down", 10)
    sim.step(w, nil)
    local ev = w.events:drain()
    assert.are.equal(1, #H.of_type(ev, "bullet_cancel"))
    assert.are.equal(0, #H.of_type(ev, "tank_hit"))
    assert.are.equal(0, target.hits)
  end)

  it("two bullets hitting one tank in one sub-step are both consumed; one hit", function()
    local w = world()
    local p1 = w.tanks[1]
    p1.x, p1.y = 1536, 1536
    H.add_bullet(w, 4, 1500, 1600, "right", 10) -- overlaps after sub-step 1 (x 1505)
    H.add_bullet(w, 4, 1796, 1600, "left", 10) -- overlaps after sub-step 1 (x 1791)
    -- 128 u/tick: 2 sub-steps; it would reach the tank only in sub-step 2
    H.add_bullet(w, 3, 1600, 1404, "down", 128)
    sim.step(w, nil)
    local ev = w.events:drain()
    local hits = H.of_type(ev, "tank_hit")
    assert.are.equal(1, #hits)
    assert.are.same({ 1, 4, false }, { hits[1].tank, hits[1].by, hits[1].friendly })
    assert.is_false(p1.present) -- left the field
    assert.are.equal(1, #w.bullets) -- the fast bullet passed the removed tank
    assert.are.equal(1404 + 128, w.bullets[1].y)
  end)

  it("never hits the owner tank", function()
    local w = world()
    local p1 = w.tanks[1]
    p1.x, p1.y = 1536, 1536
    H.add_bullet(w, 1, 1600, 1600, "right", 10) -- inside its own tank
    sim.step(w, F(nil))
    assert.are.equal(0, #H.of_type(w.events:drain(), "tank_hit"))
  end)
end)
