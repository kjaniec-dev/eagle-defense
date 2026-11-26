-- Shared helpers for simulation scenario tests: compact arenas, InputFrame
-- builders and a stepping loop that asserts the gameplay invariants on
-- every tick.

local sim = require("src.sim.sim")
local tuning = require("src.sim.tuning")
local arena = require("src.sim.arena")
local units = require("src.sim.units")

local H = {}

H.T = units.TANK
H.HALF = units.SNAP

-- Builds arena data. `rows` are 13-character tile rows (each character is
-- doubled) or 26-character half-tile rows, indexed by row (1-based); missing
-- rows are empty.
-- `entities` use half-tile coordinates.
function H.arena_data(rows, entities)
  local map = {}
  local tile_rows = false
  for r = 1, 13 do
    tile_rows = tile_rows or (rows[r] ~= nil and #rows[r] == 13)
  end
  if tile_rows then
    for r = 1, 13 do
      local half = (rows[r] or string.rep(".", 13)):gsub(".", "%0%0")
      map[#map + 1] = half
      map[#map + 1] = half
    end
  else
    for r = 1, 26 do
      map[r] = rows[r] or string.rep(".", 26)
    end
  end
  return { name = "test", map = map, entities = entities }
end

-- Players at the given half-tile positions (facing up), plus dummies.
function H.entities(p1, p2, dummies)
  local list = {
    { kind = "player", slot = 1, x = p1[1], y = p1[2], facing = p1[3] or "up" },
    { kind = "player", slot = 2, x = p2[1], y = p2[2], facing = p2[3] or "up" },
  }
  for _, d in ipairs(dummies or {}) do
    list[#list + 1] = { kind = d[1], x = d[2], y = d[3], facing = d[4] or "down" }
  end
  return list
end

-- Active tuning with optional overrides.
function H.tuning(overrides)
  local values = tuning.load().values
  for k, v in pairs(overrides or {}) do
    values[k] = v
  end
  assert(tuning.check_values(values))
  return values
end

-- A world on a custom arena (rows, entities) or on the G1 arena.
function H.world(opts)
  opts = opts or {}
  local data = opts.arena
  local built = data and arena.build(data) or arena.load("g1_arena")
  return sim.new({ arena = built, tuning = H.tuning(opts.tuning), seed = opts.seed or 1 })
end

-- InputFrame for both players. Each side is nil, a direction string, or
-- { dir = ..., fire = bool, press = bool }.
function H.frame(p1, p2)
  local function one(p)
    if p == nil then
      return { dir = nil, fire = false, fire_pressed = false }
    elseif type(p) == "string" then
      return { dir = p, fire = false, fire_pressed = false }
    end
    return { dir = p.dir, fire = p.fire or p.press or false, fire_pressed = p.press or false }
  end
  return { one(p1), one(p2) }
end

-- Asserts the tick invariants: no overlap, bullet limits, integer positions.
function H.assert_invariants(w)
  local v = sim.violations(w)
  assert(#v == 0, ("tick %d: %s"):format(w.tick, table.concat(v, "; ")))
end

-- Steps n ticks; frame_of(tick) returns the InputFrame (or a frame/nil).
-- Asserts the invariants after every tick and returns all drained events.
function H.run(w, n, frame_of)
  local all = {}
  for _ = 1, n do
    local f = frame_of
    if type(frame_of) == "function" then
      f = frame_of(w.tick + 1)
    end
    sim.step(w, f)
    H.assert_invariants(w)
    for _, e in ipairs(w.events:drain()) do
      all[#all + 1] = e
    end
  end
  return all
end

-- Events of one type.
function H.of_type(events, kind)
  local out = {}
  for _, e in ipairs(events) do
    if e.type == kind then
      out[#out + 1] = e
    end
  end
  return out
end

-- Adds a bullet directly (for collision scenarios). `owner` is a tank id.
function H.add_bullet(w, owner, x, y, dir, speed)
  local t = w.tanks[owner]
  local b = {
    id = w.next_bullet_id,
    owner = owner,
    faction = t.faction,
    x = x,
    y = y,
    size = w.tuning.bullet_size,
    dir = dir,
    speed = speed,
    alive = true,
  }
  w.next_bullet_id = w.next_bullet_id + 1
  w.bullets[#w.bullets + 1] = b
  return b
end

return H
