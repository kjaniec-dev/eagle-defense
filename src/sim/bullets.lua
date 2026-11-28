-- Shooting and the bullet phase (TECHNICAL_DESIGN §5, §6). Bullet vs
-- terrain and destruction live in src/sim/destruction.lua.

local units = require("src.sim.units")
local geom = require("src.sim.geom")
local destruction = require("src.sim.destruction")
local world_mod = require("src.sim.world")

local M = {}

local T, MAX_SUBSTEP = units.TANK, units.MAX_SUBSTEP
local emit = world_mod.emit

local function center(b)
  local half = math.floor(b.size / 2)
  return b.x + half, b.y + half
end

local function active_count(w, tank_id)
  local n = 0
  for _, b in ipairs(w.bullets) do
    if b.owner == tank_id and b.alive then
      n = n + 1
    end
  end
  return n
end
M.active_count = active_count

-- Bullet speed for a tank's shot.
function M.shot_speed(w, t)
  local tu = w.tuning
  if t.kind == "turret" then
    return tu.turret_bullet_speed
  end
  if t.kind == "player" and t.level >= tu.fast_bullet_level then
    return tu.bullet_speed_fast
  end
  return tu.bullet_speed_normal
end

-- Power bullets break steel (G2-D3): a player shot at upgrade level >=
-- steel_break_level.
function M.shot_power(w, t)
  return t.kind == "player" and t.level >= w.tuning.steel_break_level
end

-- Spawn box: centered on the tank's front edge, with the muzzle as the
-- bullet's rear edge.
function M.spawn_position(t, size)
  local off = math.floor((T - size) / 2)
  local f = t.facing
  if f == "up" then
    return t.x + off, t.y - size
  elseif f == "down" then
    return t.x + off, t.y + T
  elseif f == "left" then
    return t.x - size, t.y + off
  end
  return t.x + T, t.y + off
end

-- Applies a bullet hit on tank t. A bullet from the tank's own faction is
-- consumed with a friendly hit and no other effect (stun arrives in G6). An
-- opposing hit counts; a hit player leaves the field (hit_pending, then the
-- removal phase schedules its respawn).
local function hit_tank(w, t, b)
  local friendly = b.faction == t.faction
  if not friendly then
    t.hits = t.hits + 1
    if t.kind == "player" then
      t.hit_pending = true
    end
  end
  local cx, cy = center(b)
  emit(w, {
    type = "tank_hit",
    tank = t.id,
    bullet = b.id,
    by = b.owner,
    friendly = friendly,
    x = cx,
    y = cy,
  })
end

-- First present tank (entity order) overlapping bullet b, excluding its
-- owner and tanks already hit this tick.
local function tank_at(w, b)
  for _, t in ipairs(w.tanks) do
    if
      t.present
      and not t.hit_pending
      and t.id ~= b.owner
      and geom.overlaps(b.x, b.y, b.size, b.size, t.x, t.y, T, T)
    then
      return t
    end
  end
end

local function cancel(w, a, b)
  a.alive, b.alive = false, false
  local ax, ay = center(a)
  local bx, by = center(b)
  emit(w, {
    type = "bullet_cancel",
    a = a.id,
    b = b.id,
    x = math.floor((ax + bx) / 2),
    y = math.floor((ay + by) / 2),
  })
end

-- Fires from tank t if it is below its bullet limit. The new bullet is
-- resolved at once against opposing bullets, then tanks, then solids and
-- bounds (muzzle obstruction); only an unobstructed bullet joins the list.
-- A muzzle impact destroys terrain like an in-flight impact (G2 plan §6.4).
-- `batch` is the spawn phase's destruction batch (src/sim/destruction): its
-- removals are applied when the spawn phase ends, so every muzzle impact of
-- the phase sees the phase-start terrain (clarification C1). Without a
-- batch, the removals are applied at once.
-- Returns the bullet, or nil when the tank is at its limit.
function M.try_fire(w, t, batch)
  if active_count(w, t.id) >= world_mod.bullet_limit(w, t) then
    return nil
  end
  local size = w.tuning.bullet_size
  local x, y = M.spawn_position(t, size)
  local b = {
    id = w.next_bullet_id,
    owner = t.id,
    faction = t.faction,
    x = x,
    y = y,
    size = size,
    dir = t.facing,
    speed = M.shot_speed(w, t),
    power = M.shot_power(w, t) or nil, -- nil (not false): only set when true
    alive = true,
  }
  w.next_bullet_id = w.next_bullet_id + 1
  local cx, cy = center(b)
  emit(w, { type = "shot", tank = t.id, bullet = b.id, dir = b.dir, x = cx, y = cy })

  for _, o in ipairs(w.bullets) do
    if
      o.alive
      and o.faction ~= b.faction
      and geom.overlaps(b.x, b.y, size, size, o.x, o.y, o.size, o.size)
    then
      cancel(w, b, o)
      return b
    end
  end
  local target = tank_at(w, b)
  if target then
    b.alive = false
    hit_tank(w, target, b)
    if target.hit_pending then
      target.present = false
    end
    return b
  end
  local own = batch == nil
  batch = batch or destruction.new_batch()
  local consumed = destruction.resolve(w, b, batch, true, emit)
  if own then
    destruction.apply(w, batch)
  end
  if consumed then
    return b
  end
  w.bullets[#w.bullets + 1] = b
  return b
end

-- Number of sub-steps for this tick: ceil(max active speed / 64), >= 1.
function M.substeps(w)
  local max = 0
  for _, b in ipairs(w.bullets) do
    if b.alive and b.speed > max then
      max = b.speed
    end
  end
  local n = math.ceil(max / MAX_SUBSTEP)
  return n < 1 and 1 or n
end

-- Part of `speed` moved in sub-step k of n: equal integer parts, with the
-- remainder going to the first sub-steps.
function M.part(speed, k, n)
  local base = math.floor(speed / n)
  if k <= speed % n then
    return base + 1
  end
  return base
end

-- The bullet phase: n sub-steps of (a) advance, (b) bullet vs bullet,
-- (c) bullet vs tank, (d) bullet vs solids and bounds with destruction. In
-- (d) every impact is calculated against the cells at the start of (d), and
-- the union of the removals is applied after the last bullet (G2 plan §6.5,
-- clarification C1); the next sub-step sees the updated cells.
function M.phase(w)
  local list = w.bullets
  local n = M.substeps(w)
  for k = 1, n do
    -- (a) advance
    for _, b in ipairs(list) do
      if b.alive then
        local d = units.DIRS[b.dir]
        local s = M.part(b.speed, k, n)
        b.px, b.py = b.x, b.y
        b.x, b.y = b.x + d.dx * s, b.y + d.dy * s
      end
    end
    -- (b) opposing bullets cancel (exact continuous test, bullet order)
    for i = 1, #list do
      local a = list[i]
      if a.alive then
        for j = i + 1, #list do
          local b = list[j]
          if
            b.alive
            and a.faction ~= b.faction
            and geom.sweep_overlap(
              a.px,
              a.py,
              a.size,
              a.size,
              a.x - a.px,
              a.y - a.py,
              b.px,
              b.py,
              b.size,
              b.size,
              b.x - b.px,
              b.y - b.py
            )
          then
            cancel(w, a, b)
            break
          end
        end
      end
    end
    -- (c) tanks: every overlapping bullet is consumed, each tank hit once.
    -- The effective hit is the first hostile bullet in bullet order, else
    -- the first friendly one, so a friendly hit never suppresses a hostile
    -- one (G1 review clarification 4).
    local hit_by = {}
    for _, b in ipairs(list) do
      if b.alive then
        local t = tank_at(w, b)
        if t then
          b.alive = false
          local cur = hit_by[t.id]
          if not cur or (cur.faction == t.faction and b.faction ~= t.faction) then
            hit_by[t.id] = b
          end
        end
      end
    end
    for _, t in ipairs(w.tanks) do
      local b = hit_by[t.id]
      if b then
        hit_tank(w, t, b)
      end
    end
    -- A hit player stops being a collision target after this sub-step.
    for _, t in ipairs(w.tanks) do
      if t.hit_pending then
        t.present = false
      end
    end
    -- (d) solids and bounds, simultaneous destruction
    local batch = destruction.new_batch()
    for _, b in ipairs(list) do
      if b.alive then
        destruction.resolve(w, b, batch, false, emit)
      end
    end
    destruction.apply(w, batch)
  end
  for _, b in ipairs(list) do
    b.px, b.py = nil, nil
  end
end

-- Removes consumed bullets, keeping spawn order.
function M.remove_dead(w)
  local kept = {}
  for _, b in ipairs(w.bullets) do
    if b.alive then
      kept[#kept + 1] = b
    end
  end
  w.bullets = kept
end

return M
