-- Arena data: validation and conversion to simulation units.
--
-- Arena tables are data only (see config/arenas/g1_arena.lua). The map is a
-- 26 x 26 grid of half-tile characters; each character covers 2 x 2
-- destruction cells. Entity positions are in half-tiles.

local units = require("src.sim.units")
local terrain = require("src.sim.terrain")
local hash = require("src.core.hash")

local M = {}

M.HALF = 26 -- half-tiles per side
-- G1 config arenas know only empty and the indestructible block (terrain
-- codes 0 and 1, G2-D1); level-format arenas use src/sim/level.lua.
M.MAP_CHARS = { ["."] = terrain.CODE.empty, X = terrain.CODE.block }
-- Arenas in the G1 config format (config/arenas/<name>.lua). Any other
-- arena name is a level-format arena (levels/arenas/<name>.lua, G2 plan
-- §11). tests/sim/data_spec.lua checks this list against config/arenas/.
M.CONFIG = { g1_arena = true }
M.KINDS = { player = true, target = true, turret = true }
M.MAX_ENTITIES = 16

local HALF_U = units.SNAP -- one half-tile in u (128)

local function is_int(v)
  return type(v) == "number" and v == math.floor(v)
end

-- Builds the flat cell array (row-major, 52 x 52) from the map rows.
local function build_cells(map, problems)
  local cells = {}
  local n = units.CELLS
  for i = 1, n * n do
    cells[i] = 0
  end
  if type(map) ~= "table" or #map ~= M.HALF then
    problems[#problems + 1] = ("map: expected %d rows"):format(M.HALF)
    return cells
  end
  for r = 1, M.HALF do
    local row = map[r]
    if type(row) ~= "string" or #row ~= M.HALF then
      problems[#problems + 1] = ("map row %d: expected %d characters"):format(r, M.HALF)
    else
      for c = 1, M.HALF do
        local ch = row:sub(c, c)
        local code = M.MAP_CHARS[ch]
        if not code then
          problems[#problems + 1] = ("map row %d col %d: unknown character %q"):format(r, c, ch)
        elseif code ~= 0 then
          local cx, cy = (c - 1) * 2, (r - 1) * 2
          for dy = 0, 1 do
            for dx = 0, 1 do
              cells[(cy + dy) * n + (cx + dx) + 1] = code
            end
          end
        end
      end
    end
  end
  return cells
end

-- Validates arena data and converts it to simulation units. Returns
-- { name, cells, entities = { { kind, slot, x, y, facing } (u) } } or raises
-- an error listing every problem.
function M.build(data)
  local problems = {}
  assert(type(data) == "table", "arena: table expected")
  if type(data.name) ~= "string" or not data.name:match("^[%w_]+$") then
    problems[#problems + 1] = "name: identifier expected"
  end
  local cells = build_cells(data.map, problems)
  local entities = {}
  local list = data.entities
  if type(list) ~= "table" or #list < 2 or #list > M.MAX_ENTITIES then
    problems[#problems + 1] = ("entities: 2..%d expected"):format(M.MAX_ENTITIES)
    list = {}
  end
  local max_pos = M.HALF - 2
  for i, e in ipairs(list) do
    local where = ("entity %d"):format(i)
    local ok = type(e) == "table"
      and M.KINDS[e.kind]
      and is_int(e.x)
      and is_int(e.y)
      and e.x >= 0
      and e.y >= 0
      and e.x <= max_pos
      and e.y <= max_pos
      and units.DIRS[e.facing] ~= nil
    if not ok then
      problems[#problems + 1] = where .. ": kind, x, y (0.." .. max_pos .. ") and facing required"
    else
      local expect_slot = i <= 2 and i or nil
      if
        (e.kind == "player") ~= (expect_slot ~= nil) or (expect_slot and e.slot ~= expect_slot)
      then
        problems[#problems + 1] = where .. ": players must come first, as slots 1 and 2"
      end
      local ent = {
        kind = e.kind,
        slot = e.slot,
        x = e.x * HALF_U,
        y = e.y * HALF_U,
        facing = e.facing,
      }
      if terrain.box_hits(cells, ent.x, ent.y, units.TANK, units.TANK, terrain.BLOCKS_TANKS) then
        problems[#problems + 1] = where .. ": overlaps a solid cell"
      end
      for j, o in ipairs(entities) do
        if
          ent.x < o.x + units.TANK
          and o.x < ent.x + units.TANK
          and ent.y < o.y + units.TANK
          and o.y < ent.y + units.TANK
        then
          problems[#problems + 1] = ("%s: overlaps entity %d"):format(where, j)
        end
      end
      entities[#entities + 1] = ent
    end
  end
  if #problems > 0 then
    error("arena: " .. table.concat(problems, "; "), 0)
  end
  return { name = data.name, cells = cells, entities = entities }
end

-- True when `name` is a G1 config-format arena.
function M.is_config(name)
  return M.CONFIG[name] == true
end

-- Loads and validates config/arenas/<name>.lua.
function M.load(name)
  assert(type(name) == "string" and name:match("^[%w_]+$"), "arena: invalid name")
  assert(M.is_config(name), "arena: " .. name .. " is not a config arena")
  return M.build(require("config.arenas." .. name))
end

local KIND_CODE = { player = 1, target = 2, turret = 3 }

-- Arena identity (G2 plan §14, clarification C3): 8-hex hash of a built
-- battlefield's cells and entities (spawns and dummies). Replays record it;
-- the runner refuses a replay whose id differs from the loaded arena.
function M.id(built)
  local h = hash.new()
  h:int(#built.cells)
  for i = 1, #built.cells do
    h:int(built.cells[i])
  end
  h:int(#built.entities)
  for _, e in ipairs(built.entities) do
    h:int(KIND_CODE[e.kind]):int(e.slot or 0):int(e.x):int(e.y):int(units.DIRS[e.facing].code)
  end
  return h:hex()
end

return M
