-- The simulation entry points: sim.new, sim.step (the only mutator) and
-- sim.hash. Pure Lua (TECHNICAL_DESIGN §4, §5).
--
-- Tick order: input -> AI (none yet) -> tank movement (with ice) -> bullet
-- spawn (muzzle destruction) -> bullet phase (destruction in (d)) ->
-- removals -> respawns -> events.

local world = require("src.sim.world")
local move = require("src.sim.move")
local bullets = require("src.sim.bullets")
local destruction = require("src.sim.destruction")

local M = {}

M.new = world.new
M.hash = world.hash
M.violations = world.violations

local NO_INPUT = { dir = nil, fire = false, fire_pressed = false }

local function input_for(frame, t)
  if t.kind ~= "player" or not frame then
    return NO_INPUT
  end
  return frame[t.slot] or NO_INPUT
end

-- Turret dummies fire on a fixed schedule (GAME_DESIGN §11).
local function turret_fires(w)
  local tu = w.tuning
  local since = w.tick - tu.turret_first_shot
  return since >= 0 and since % tu.turret_period == 0
end

-- Advances the world by one fixed tick with the given InputFrame
-- ({ [1] = { dir, fire, fire_pressed }, [2] = ... }; nil means no input).
function M.step(w, frame)
  w.tick = w.tick + 1
  local tanks = w.tanks

  -- Tank movement in entity order, including ice slides (G2 plan §7).
  for _, t in ipairs(tanks) do
    if t.present then
      move.tank_tick(w, t, input_for(frame, t).dir, w.tuning.player_speed)
    end
  end

  -- Bullet spawn: one shot per fire press (no auto-repeat), turret schedule.
  -- Muzzle impacts form one destruction batch, applied after the last tank
  -- (clarification C1).
  local turret_now = turret_fires(w)
  local batch = destruction.new_batch()
  for _, t in ipairs(tanks) do
    if t.present then
      if t.kind == "player" then
        if input_for(frame, t).fire_pressed then
          bullets.try_fire(w, t, batch)
        end
      elseif t.kind == "turret" and turret_now then
        bullets.try_fire(w, t, batch)
      end
    end
  end
  destruction.apply(w, batch)

  bullets.phase(w)

  -- Removals: consumed bullets; hit players leave the field and are
  -- scheduled to respawn on the next tick.
  bullets.remove_dead(w)
  for _, t in ipairs(tanks) do
    if t.hit_pending then
      t.hit_pending = false
      t.present = false
      t.respawn_tick = w.tick + 1
      t.respawn_reported = false
      move.clear_ice(t)
    end
  end

  -- Respawns (arena-only, G1-D2): deferred while any tank occupies the
  -- spawn box; bullets never block a respawn.
  for _, t in ipairs(tanks) do
    if t.respawn_tick and t.respawn_tick <= w.tick and not t.present then
      if move.box_blocked(w, t.spawn_x, t.spawn_y, t) then
        if not t.respawn_reported then
          t.respawn_reported = true
          world.emit(w, { type = "respawn_blocked", tank = t.id })
        end
      else
        t.x, t.y, t.facing = t.spawn_x, t.spawn_y, t.spawn_facing
        t.present = true
        t.respawn_tick = nil
        t.respawn_reported = false
        t.level = w.player_level
        move.clear_ice(t)
        world.emit(w, { type = "tank_respawn", tank = t.id, x = t.x, y = t.y })
      end
    end
  end
end

return M
