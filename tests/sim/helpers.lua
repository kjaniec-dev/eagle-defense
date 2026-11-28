-- Shared helpers for simulation scenario tests: compact arenas, InputFrame
-- builders and a stepping loop that asserts the gameplay invariants on
-- every tick.

local sim = require("src.sim.sim")
local tuning = require("src.sim.tuning")
local arena = require("src.sim.arena")
local units = require("src.sim.units")
local terrain = require("src.sim.terrain")
local world_mod = require("src.sim.world")

local H = {}

H.N = units.CELLS
H.CELL = units.CELL
H.CODE = terrain.CODE

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
-- opts.terrain: 26 half-tile rows of terrain characters (. X B S W F I),
-- indexed by row (1-based; missing rows are empty), painted over the arena
-- (each character covers 2 x 2 cells). opts.player_level sets the level.
function H.world(opts)
  opts = opts or {}
  local data = opts.arena
  local built = data and arena.build(data) or arena.load("g1_arena")
  if opts.terrain then
    for r = 1, 26 do
      local row = opts.terrain[r]
      if row then
        assert(#row == 26, "terrain row " .. r .. ": 26 characters expected")
        for c = 1, 26 do
          local code = assert(terrain.CHAR[row:sub(c, c)], "unknown terrain character")
          for dy = 0, 1 do
            for dx = 0, 1 do
              built.cells[((r - 1) * 2 + dy) * units.CELLS + (c - 1) * 2 + dx + 1] = code
            end
          end
        end
      end
    end
  end
  return sim.new({
    arena = built,
    tuning = H.tuning(opts.tuning),
    seed = opts.seed or 1,
    player_level = opts.player_level,
  })
end

-- Cell index (1-based) of cell column c, row r (0-based cell coordinates).
function H.idx(c, r)
  return r * units.CELLS + c + 1
end

-- Code of cell (c, r), and setting it.
function H.cell(w, c, r)
  return w.cells[H.idx(c, r)]
end
function H.set(w, c, r, name)
  w.cells[H.idx(c, r)] = terrain.CODE[name]
end
-- Fills the cell rectangle [c0, c1] x [r0, r1] with a terrain type.
function H.fill(w, c0, r0, c1, r1, name)
  for r = r0, r1 do
    for c = c0, c1 do
      H.set(w, c, r, name)
    end
  end
end

-- Counts cells of a terrain type.
function H.count(w, name)
  local code, n = terrain.CODE[name], 0
  for i = 1, #w.cells do
    if w.cells[i] == code then
      n = n + 1
    end
  end
  return n
end

-- The "c,r" keys of the cells that differ between two cell arrays, sorted.
function H.changed(before, after)
  local out = {}
  for i = 1, #after do
    if before[i] ~= after[i] then
      out[#out + 1] = ("%d,%d"):format((i - 1) % units.CELLS, math.floor((i - 1) / units.CELLS))
    end
  end
  table.sort(out)
  return out
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

-- Asserts the tick invariants: no overlap, bullet limits, integer positions,
-- and (with the previous tick's cells) terrain invariant 9.
function H.assert_invariants(w, prev_cells)
  local v = sim.violations(w)
  if prev_cells then
    for _, p in ipairs(world_mod.terrain_violations(prev_cells, w.cells)) do
      v[#v + 1] = p
    end
  end
  assert(#v == 0, ("tick %d: %s"):format(w.tick, table.concat(v, "; ")))
end

-- Steps n ticks; frame_of(tick) returns the InputFrame (or a frame/nil).
-- Asserts the invariants (including invariant 9) after every tick and
-- returns all drained events.
function H.run(w, n, frame_of)
  local all = {}
  for _ = 1, n do
    local f = frame_of
    if type(frame_of) == "function" then
      f = frame_of(w.tick + 1)
    end
    local prev = world_mod.copy_cells(w.cells)
    sim.step(w, f)
    H.assert_invariants(w, prev)
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

-- Adds a bullet directly (for collision scenarios). `owner` is a tank id;
-- `power` (optional) makes it break steel.
function H.add_bullet(w, owner, x, y, dir, speed, power)
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
    power = power or nil,
    alive = true,
  }
  w.next_bullet_id = w.next_bullet_id + 1
  w.bullets[#w.bullets + 1] = b
  return b
end

return H
