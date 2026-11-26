-- World construction, state hash and invariant checks.
--
-- The world is a plain table (TECHNICAL_DESIGN §5). Entity lists are arrays
-- iterated in order: tanks are P1, P2, then dummies in creation order;
-- bullets are in spawn order.

local rng_mod = require("src.core.rng")
local events = require("src.core.events")
local hash = require("src.core.hash")
local units = require("src.sim.units")
local geom = require("src.sim.geom")
local arena_mod = require("src.sim.arena")

local M = {}

local FACTION = { player = "player", target = "enemy", turret = "enemy" }
local FACTION_CODE = { player = 1, enemy = 2 }
local KIND_CODE = { player = 1, target = 2, turret = 3 }

-- opts = {
--   arena   = built arena (src/sim/arena.build) or an arena name,
--   tuning  = plain tuning values (src/sim/tuning),
--   seed    = integer (default 1),
-- }
function M.new(opts)
  assert(type(opts) == "table" and type(opts.tuning) == "table", "world: tuning required")
  local arena = opts.arena or "g1_arena"
  if type(arena) == "string" then
    arena = arena_mod.load(arena)
  end
  local tuning = opts.tuning
  local w = {
    tick = 0,
    rng = rng_mod.new(opts.seed or 1),
    arena_name = arena.name,
    cells = {},
    tanks = {},
    bullets = {},
    next_bullet_id = 1,
    events = events.new(),
    tuning = tuning,
  }
  for i = 1, #arena.cells do
    w.cells[i] = arena.cells[i]
  end
  for i, e in ipairs(arena.entities) do
    local player = e.kind == "player"
    w.tanks[i] = {
      id = i,
      kind = e.kind,
      slot = e.slot,
      faction = FACTION[e.kind],
      x = e.x,
      y = e.y,
      facing = e.facing,
      present = true,
      level = player and tuning.arena_player_level or 0,
      spawn_x = e.x,
      spawn_y = e.y,
      spawn_facing = e.facing,
      respawn_tick = nil, -- players only: tick of the scheduled respawn
      respawn_reported = false, -- respawn_blocked already emitted
      hit_pending = false, -- hit this tick; removed in the removal phase
      hits = 0, -- times hit by an opposing bullet
    }
  end
  return w
end

-- Pushes an event stamped with the current tick.
function M.emit(w, event)
  event.tick = w.tick
  w.events:push(event)
end

-- 32-bit hash of all authoritative state, as 8 hex digits. Used by golden
-- replays and determinism checks.
function M.hash(w)
  local h = hash.new()
  h:int(w.tick):int(w.rng:get_state()):int(w.next_bullet_id)
  h:int(#w.tanks)
  for _, t in ipairs(w.tanks) do
    h:int(t.id):int(KIND_CODE[t.kind]):int(t.x):int(t.y):int(units.DIRS[t.facing].code)
    h:bool(t.present):int(t.level):int(t.respawn_tick or -1):bool(t.respawn_reported)
    h:int(t.hits)
  end
  h:int(#w.bullets)
  for _, b in ipairs(w.bullets) do
    h:int(b.id):int(b.owner):int(FACTION_CODE[b.faction]):int(b.x):int(b.y)
    h:int(units.DIRS[b.dir].code):int(b.speed):int(b.size)
  end
  local solid = 0
  for i = 1, #w.cells do
    if w.cells[i] ~= 0 then
      solid = solid + 1
      h:int(i):int(w.cells[i])
    end
  end
  h:int(solid)
  return h:hex()
end

-- Returns a list of invariant violations (empty when the state is valid):
--   * no present tank overlaps a solid cell, a bound or another tank;
--   * no tank has more active bullets than its limit;
--   * all coordinates are integers.
function M.violations(w)
  local out = {}
  local T, F = units.TANK, units.FIELD
  for i, t in ipairs(w.tanks) do
    if t.present then
      if t.x ~= math.floor(t.x) or t.y ~= math.floor(t.y) then
        out[#out + 1] = ("tank %d: non-integer position"):format(t.id)
      end
      if t.x < 0 or t.y < 0 or t.x + T > F or t.y + T > F then
        out[#out + 1] = ("tank %d: outside the field at %d,%d"):format(t.id, t.x, t.y)
      end
      if arena_mod.box_hits_cells(w.cells, t.x, t.y, T, T) then
        out[#out + 1] = ("tank %d: overlaps a solid cell at %d,%d"):format(t.id, t.x, t.y)
      end
      for j = i + 1, #w.tanks do
        local o = w.tanks[j]
        if o.present and geom.overlaps(t.x, t.y, T, T, o.x, o.y, T, T) then
          out[#out + 1] = ("tank %d overlaps tank %d"):format(t.id, o.id)
        end
      end
    end
  end
  local active = {}
  for _, b in ipairs(w.bullets) do
    active[b.owner] = (active[b.owner] or 0) + 1
    if b.x ~= math.floor(b.x) or b.y ~= math.floor(b.y) then
      out[#out + 1] = ("bullet %d: non-integer position"):format(b.id)
    end
  end
  for _, t in ipairs(w.tanks) do
    local limit = M.bullet_limit(w, t)
    if (active[t.id] or 0) > limit then
      out[#out + 1] = ("tank %d: %d active bullets, limit %d"):format(t.id, active[t.id], limit)
    end
  end
  return out
end

-- Active-bullet limit of a tank: by upgrade level for players, 1 for dummies.
function M.bullet_limit(w, t)
  if t.kind == "player" then
    return w.tuning.bullet_limit[t.level + 1]
  end
  return 1
end

return M
