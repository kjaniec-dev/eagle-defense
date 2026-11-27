-- Arena respawn (decision G1-D2) and the reconciled tick order
-- (TECHNICAL_DESIGN §5), plus the turret dummy in the G1 arena.

local H = require("tests.sim.helpers")
local sim = require("src.sim.sim")

local F = H.frame
local S = H.tuning().player_speed -- committed player speed

local function by_tick(events, kind)
  local out = {}
  for _, e in ipairs(H.of_type(events, kind)) do
    out[#out + 1] = e.tick
  end
  return out
end

-- Enemy bullet (owned by the target dummy, id 3) that hits a tank whose box
-- starts at x0 in its first sub-step.
local function shoot_from_left(w, x0, y)
  return H.add_bullet(w, 3, x0 - 32 - 5, y, "right", 17)
end

local function world()
  return H.world({
    arena = H.arena_data({}, H.entities({ 4, 4 }, { 8, 4 }, { { "target", 24, 24 } })),
  })
end

describe("sim respawn (arena only)", function()
  it("a hit player leaves the field and respawns at its spawn on the next tick", function()
    local w = world()
    local p1 = w.tanks[1]
    H.run(w, 50, F("down"))
    assert.are.same({ 512, 512 + 50 * S }, { p1.x, p1.y })
    shoot_from_left(w, 512, p1.y + 88)
    local ev = H.run(w, 1, F(nil))
    assert.are.same({ 51 }, by_tick(ev, "tank_hit"))
    assert.is_false(p1.present)
    assert.are.equal(52, p1.respawn_tick)
    ev = H.run(w, 1, F("right")) -- input for an absent tank is ignored
    assert.are.same({ 52 }, by_tick(ev, "tank_respawn"))
    assert.are.same({ 512, 512, "up", true }, { p1.x, p1.y, p1.facing, p1.present })
    assert.are.equal(1, p1.hits)
  end)

  it("is deferred while a tank occupies the spawn box, reported once, never overlapping", function()
    local w = world()
    local p1, p2 = w.tanks[1], w.tanks[2]
    H.run(w, 100, F("down"))
    -- P2 drives left until it covers part of P1's spawn box (x 512..768)
    local n = math.floor((1024 - 700) / S)
    H.run(w, n, F(nil, "left"))
    assert.are.equal(1024 - n * S, p2.x)
    assert.is_true(p2.x > 512 and p2.x < 768)
    shoot_from_left(w, 512, p1.y + 100)
    local ev = H.run(w, 1, F(nil))
    assert.are.equal(1, #H.of_type(ev, "tank_hit"))
    local hit_tick = 100 + n + 1
    ev = H.run(w, 30, F(nil))
    assert.are.same({ hit_tick + 1 }, by_tick(ev, "respawn_blocked"))
    assert.are.equal(0, #H.of_type(ev, "tank_respawn"))
    assert.is_false(p1.present)
    -- P2 backs off until x >= 768; P1 is placed in that same tick (after
    -- the movement phase)
    local back = math.ceil((768 - p2.x) / S)
    ev = H.run(w, back + 5, F(nil, "right"))
    assert.are.same({ hit_tick + 30 + back }, by_tick(ev, "tank_respawn"))
    assert.are.equal(0, #H.of_type(ev, "respawn_blocked"))
    assert.is_true(p1.present)
    assert.is_true(p2.x >= 768)
  end)

  it("a bullet inside the spawn box resolves in the first bullet phase after placement", function()
    -- Regression (G1 plan review): respawn timing reconciled with the tick
    -- order; respawns run after the bullet phase, and bullets never block.
    local w = world()
    local p1 = w.tanks[1]
    shoot_from_left(w, 512, 600)
    local ev = H.run(w, 1, F(nil)) -- tick 1: hit at the spawn point
    assert.are.same({ 1 }, by_tick(ev, "tank_hit"))
    H.add_bullet(w, 3, 600, 600, "right", 2) -- slow bullet inside the spawn box
    ev = H.run(w, 1, F(nil)) -- tick 2: bullet phase (no tank), then respawn
    assert.are.same({}, by_tick(ev, "tank_hit"))
    assert.are.same({ 2 }, by_tick(ev, "tank_respawn"))
    assert.is_true(p1.present)
    ev = H.run(w, 1, F(nil)) -- tick 3: the bullet now hits the placed tank
    assert.are.same({ 3 }, by_tick(ev, "tank_hit"))
    assert.is_false(p1.present)
    assert.are.same({ 4 }, by_tick(H.run(w, 1, F(nil)), "tank_respawn"))
  end)

  describe("G1 arena turret", function()
    local function lane_world()
      local w = H.world()
      local p1 = w.tanks[1]
      p1.x, p1.y = 2560, 1536 -- column 10, in the corridor under the turret's lane
      return w, p1
    end

    it("fires on its schedule down the lane and hits a player standing in it", function()
      local w, p1 = lane_world()
      local ev = H.run(w, 140, F(nil))
      assert.are.same({ 60 }, by_tick(ev, "shot"))
      local hit = H.of_type(ev, "tank_hit")[1]
      assert.are.same({ 1, 5, 133 }, { hit.tank, hit.by, hit.tick })
      assert.are.same({ 134 }, by_tick(ev, "tank_respawn"))
      assert.are.same({ 1024, 3072 }, { p1.x, p1.y })
    end)

    it("its bullet can be cancelled by the player's shot", function()
      local w, p1 = lane_world()
      local ev = H.run(w, 170, function(tick)
        return F(tick == 100 and { press = true } or nil)
      end)
      assert.are.equal(1, #H.of_type(ev, "bullet_cancel"))
      assert.are.equal(0, #H.of_type(ev, "tank_hit"))
      assert.is_true(p1.present)
      assert.are.equal(0, sim.violations(w)[1] and 1 or 0)
    end)
  end)
end)
