-- Level files: the pure, non-executing loader and its validation profiles
-- (G2 plan §11, decision G2-D6, TECHNICAL_DESIGN §9).
--
-- A level file is a data-only table literal, read only with
-- core/serialize.decode (it is never compiled, run or `require`d). The
-- simulation never reads files: callers pass the text (the app reads it with
-- love.filesystem.read, tests and tools with tools/lib/fs).
--
-- Map: 26 rows x 26 characters, one character per half-tile (2 x 2 cells).
--   terrain  . B S W F I   (+ X in arena files only)
--   markers  1 2 E H       each a 2 x 2 block of the same character
-- Markers are parsed row-major from the top-left: each unclaimed marker
-- character starts a block there whose other three characters must match.
-- A marker's cells are empty ground.
--
-- Profiles:
--   campaign  id 1..50, env, name, roster (sum 20); exactly one 1, 2, H and
--             three E blocks in rows 0-1; no X; HQ at the bottom center
--             inside an intact brick enclosure; every E spawn reaches the HQ
--   arena     name, optional dummies (G1 target/turret entities); exactly
--             one 1 and one 2; no H, no E; X allowed

local serialize = require("src.core.serialize")
local units = require("src.sim.units")
local terrain = require("src.sim.terrain")
local arena = require("src.sim.arena")

local M = {}

M.HALF = 26
M.MAX_BYTES = 32 * 1024
M.PROFILES = { campaign = true, arena = true }
M.ENVS = { classic = true, countryside = true, industrial = true, winter = true, stronghold = true }
M.ROSTER = { "basic", "fast", "power", "armor" }
M.ROSTER_TOTAL = 20
M.MARKERS = { ["1"] = true, ["2"] = true, E = true, H = true }
M.DUMMY_KINDS = { target = true, turret = true }
M.MAX_DUMMIES = 14 -- arena.MAX_ENTITIES minus the two players

-- HQ position and its brick enclosure, in half-tiles (0-based column, row).
M.HQ_POS = { 12, 24 }
M.HQ_ENCLOSURE = {
  { 11, 23 },
  { 12, 23 },
  { 13, 23 },
  { 14, 23 },
  { 11, 24 },
  { 14, 24 },
  { 11, 25 },
  { 14, 25 },
}

local KEYS = {
  campaign = { id = true, env = true, name = true, roster = true, map = true },
  arena = { name = true, map = true, dummies = true },
}

local HALF_U = units.SNAP -- one half-tile in u

-- Problem messages (tests/fixtures/levels/invalid/ match on them).
local NOT_A_BLOCK = "map row %d col %d: marker %q is not a complete 2 x 2 block"
local NO_X = "map row %d col %d: X (test block) is not allowed in campaign levels"
local ENEMY_ROW = "markers: enemy spawn at row %d col %d must be in rows 0-1"
local HQ_AT = "hq: must be at row %d col %d (bottom center), got row %d col %d"
local UNREACHABLE = "reachability: enemy spawn %d (row %d col %d) cannot reach the HQ"

local function is_int(v)
  return type(v) == "number" and v == math.floor(v)
end

local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do
    out[#out + 1] = tostring(k)
  end
  table.sort(out)
  return out
end

-- Reads the 26 x 26 character grid. Returns grid[r][c] (0-based) or nil.
local function read_map(map, problems)
  if type(map) ~= "table" or #map ~= M.HALF then
    problems[#problems + 1] = ("map: %d rows expected"):format(M.HALF)
    return nil
  end
  for _, k in ipairs(sorted_keys(map)) do
    local n = tonumber(k)
    if not n or not is_int(n) or n < 1 or n > M.HALF then
      problems[#problems + 1] = "map: unexpected key " .. k
      return nil
    end
  end
  local grid = {}
  local ok = true
  for r = 1, M.HALF do
    local row = map[r]
    if type(row) ~= "string" or #row ~= M.HALF then
      problems[#problems + 1] = ("map row %d: %d characters expected"):format(r - 1, M.HALF)
      ok = false
    else
      grid[r - 1] = {}
      for c = 1, M.HALF do
        grid[r - 1][c - 1] = row:sub(c, c)
      end
    end
  end
  return ok and grid or nil
end

-- Claims the 2 x 2 marker blocks. Returns { ch = { {c, r}, ... } } in
-- row-major order of their top-left half-tiles.
local function parse_markers(grid, problems)
  local claimed, blocks = {}, { ["1"] = {}, ["2"] = {}, E = {}, H = {} }
  for r = 0, M.HALF - 1 do
    claimed[r] = {}
  end
  for r = 0, M.HALF - 1 do
    for c = 0, M.HALF - 1 do
      local ch = grid[r][c]
      if M.MARKERS[ch] and not claimed[r][c] then
        local ok = r + 1 < M.HALF and c + 1 < M.HALF
        if ok then
          for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
            local rr, cc = r + d[2], c + d[1]
            ok = ok and grid[rr][cc] == ch and not claimed[rr][cc]
          end
        end
        if ok then
          for dr = 0, 1 do
            for dc = 0, 1 do
              claimed[r + dr][c + dc] = true
            end
          end
          local list = blocks[ch]
          list[#list + 1] = { c, r }
        else
          problems[#problems + 1] = (NOT_A_BLOCK):format(r, c, ch)
          claimed[r][c] = true -- report each stray character once
        end
      end
    end
  end
  return blocks
end

-- Builds the 52 x 52 cell array. Marker characters become empty ground.
local function build_cells(grid, profile, problems)
  local n = units.CELLS
  local cells = {}
  for i = 1, n * n do
    cells[i] = terrain.EMPTY
  end
  for r = 0, M.HALF - 1 do
    for c = 0, M.HALF - 1 do
      local ch = grid[r][c]
      local code = terrain.CHAR[ch]
      if M.MARKERS[ch] then
        code = terrain.EMPTY
      elseif code == nil then
        problems[#problems + 1] = ("map row %d col %d: unknown character %q"):format(r, c, ch)
        code = terrain.EMPTY
      elseif code == terrain.CODE.block and profile == "campaign" then
        problems[#problems + 1] = (NO_X):format(r, c)
      end
      for dr = 0, 1 do
        for dc = 0, 1 do
          cells[(r * 2 + dr) * n + c * 2 + dc + 1] = code
        end
      end
    end
  end
  return cells
end

-- Overlap of two 2 x 2 half-tile boxes given by their top-left half-tiles.
local function boxes_overlap(a, b)
  return a[1] < b[1] + 2 and b[1] < a[1] + 2 and a[2] < b[2] + 2 and b[2] < a[2] + 2
end

-- Campaign reachability (GAME_DESIGN §5): a 4-neighbour search over the
-- top-left half-tiles of 2 x 2 tank boxes, where S and W block and every
-- other character is passable. True when the box reaches a position that
-- overlaps the HQ.
function M.reachable(grid, from, hq)
  local function free(c, r)
    if c < 0 or r < 0 or c > M.HALF - 2 or r > M.HALF - 2 then
      return false
    end
    for dr = 0, 1 do
      for dc = 0, 1 do
        local ch = grid[r + dr][c + dc]
        if ch == "S" or ch == "W" or ch == "X" then
          return false
        end
      end
    end
    return true
  end
  local seen = { [from[2] * M.HALF + from[1]] = true }
  local queue, head = { from }, 1
  while head <= #queue do
    local p = queue[head]
    head = head + 1
    if boxes_overlap(p, hq) then
      return true
    end
    for _, d in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
      local c, r = p[1] + d[1], p[2] + d[2]
      local key = r * M.HALF + c
      if not seen[key] and free(c, r) then
        seen[key] = true
        queue[#queue + 1] = { c, r }
      end
    end
  end
  return false
end

local function check_header(data, profile, problems)
  for _, k in ipairs(sorted_keys(data)) do
    if not KEYS[profile][k] then
      problems[#problems + 1] = ("%s: unknown key %q"):format(profile, k)
    end
  end
  if type(data.name) ~= "string" or not data.name:match("^[%w_]+$") or #data.name > 40 then
    problems[#problems + 1] = "name: identifier expected (letters, digits, _; at most 40)"
  end
  if profile ~= "campaign" then
    return
  end
  if not is_int(data.id) or data.id < 1 or data.id > 50 then
    problems[#problems + 1] = "id: integer 1..50 expected"
  end
  if not M.ENVS[data.env] then
    problems[#problems + 1] =
      "env: one of classic, countryside, industrial, winter, stronghold expected"
  end
  local roster = data.roster
  if type(roster) ~= "table" then
    problems[#problems + 1] = "roster: table expected"
    return
  end
  local sum, known = 0, {}
  for _, k in ipairs(M.ROSTER) do
    known[k] = true
    local v = roster[k]
    if not is_int(v) or v < 0 then
      problems[#problems + 1] = ("roster.%s: integer >= 0 expected"):format(k)
    else
      sum = sum + v
    end
  end
  for _, k in ipairs(sorted_keys(roster)) do
    if not known[k] then
      problems[#problems + 1] = ("roster: unknown key %q"):format(k)
    end
  end
  if sum ~= M.ROSTER_TOTAL then
    problems[#problems + 1] = ("roster: %d enemies expected, got %d"):format(M.ROSTER_TOTAL, sum)
  end
end

local function check_markers(blocks, profile, problems)
  local want = profile == "campaign" and { ["1"] = 1, ["2"] = 1, H = 1, E = 3 }
    or { ["1"] = 1, ["2"] = 1, H = 0, E = 0 }
  for _, ch in ipairs({ "1", "2", "E", "H" }) do
    local got = #blocks[ch]
    if got ~= want[ch] then
      problems[#problems + 1] = ("markers: %d %q block(s) expected, got %d"):format(
        want[ch],
        ch,
        got
      )
    end
  end
  if profile == "campaign" then
    for _, e in ipairs(blocks.E) do
      if e[2] ~= 0 then
        problems[#problems + 1] = (ENEMY_ROW):format(e[2], e[1])
      end
    end
  end
end

local function check_hq(grid, blocks, problems)
  local hq = blocks.H[1]
  if not hq then
    return
  end
  if hq[1] ~= M.HQ_POS[1] or hq[2] ~= M.HQ_POS[2] then
    problems[#problems + 1] = (HQ_AT):format(M.HQ_POS[2], M.HQ_POS[1], hq[2], hq[1])
    return
  end
  for _, p in ipairs(M.HQ_ENCLOSURE) do
    if grid[p[2]][p[1]] ~= "B" then
      problems[#problems + 1] = ("hq: enclosure half-tile row %d col %d must be B"):format(
        p[2],
        p[1]
      )
    end
  end
  for i, e in ipairs(blocks.E) do
    if not M.reachable(grid, e, hq) then
      problems[#problems + 1] = (UNREACHABLE):format(i, e[2], e[1])
    end
  end
end

-- Dummies (arena profile): { kind, x, y (half-tiles), facing }, not on
-- tank-blocking terrain and not overlapping markers or each other.
local function read_dummies(list, cells, blocks, problems)
  local out = {}
  if list == nil then
    return out
  end
  if type(list) ~= "table" or #list > M.MAX_DUMMIES then
    problems[#problems + 1] = ("dummies: list of at most %d expected"):format(M.MAX_DUMMIES)
    return out
  end
  local markers = {}
  for _, ch in ipairs({ "1", "2", "E", "H" }) do
    for _, b in ipairs(blocks[ch]) do
      markers[#markers + 1] = b
    end
  end
  for i, d in ipairs(list) do
    local where = ("dummy %d"):format(i)
    local ok = type(d) == "table"
      and M.DUMMY_KINDS[d.kind]
      and is_int(d.x)
      and is_int(d.y)
      and d.x >= 0
      and d.y >= 0
      and d.x <= M.HALF - 2
      and d.y <= M.HALF - 2
      and units.DIRS[d.facing] ~= nil
    if not ok then
      problems[#problems + 1] = where
        .. ": kind (target, turret), x, y (0.."
        .. (M.HALF - 2)
        .. ") and facing required"
    else
      for _, k in ipairs(sorted_keys(d)) do
        if k ~= "kind" and k ~= "x" and k ~= "y" and k ~= "facing" then
          problems[#problems + 1] = ("%s: unknown key %q"):format(where, k)
        end
      end
      local box = { d.x, d.y }
      if
        terrain.box_hits(
          cells,
          d.x * HALF_U,
          d.y * HALF_U,
          units.TANK,
          units.TANK,
          terrain.BLOCKS_TANKS
        )
      then
        problems[#problems + 1] = where .. ": overlaps tank-blocking terrain"
      end
      for _, m in ipairs(markers) do
        if boxes_overlap(box, m) then
          problems[#problems + 1] = ("%s: overlaps the marker at row %d col %d"):format(
            where,
            m[2],
            m[1]
          )
        end
      end
      for j, o in ipairs(out) do
        if boxes_overlap(box, { o.x / HALF_U, o.y / HALF_U }) then
          problems[#problems + 1] = ("%s: overlaps dummy %d"):format(where, j)
        end
      end
      out[#out + 1] = { kind = d.kind, x = d.x * HALF_U, y = d.y * HALF_U, facing = d.facing }
    end
  end
  return out
end

-- Parses level text with a profile ("campaign" or "arena"). Returns the
-- battlefield
--   { name, cells, entities, hq, enemy_spawns, meta }
-- (entities: the players as slots 1 and 2, facing up, then dummies; hq and
-- enemy_spawns are top-left positions in u, ignored by world.new until G4;
-- meta = { profile, id, env, roster }), or nil and a list of problems.
function M.parse(text, profile)
  assert(M.PROFILES[profile], "level: unknown profile " .. tostring(profile))
  local data, err = serialize.decode(text, { max_bytes = M.MAX_BYTES })
  if data == nil then
    return nil, { "level: " .. tostring(err) }
  end
  if type(data) ~= "table" then
    return nil, { "level: table expected" }
  end
  local problems = {}
  check_header(data, profile, problems)
  local grid = read_map(data.map, problems)
  if not grid then
    return nil, problems
  end
  local blocks = parse_markers(grid, problems)
  local cells = build_cells(grid, profile, problems)
  check_markers(blocks, profile, problems)
  if profile == "campaign" then
    check_hq(grid, blocks, problems)
  end
  local dummies = read_dummies(profile == "arena" and data.dummies or nil, cells, blocks, problems)
  if #problems > 0 then
    return nil, problems
  end
  local entities = {}
  for slot, ch in ipairs({ "1", "2" }) do
    local b = blocks[ch][1]
    entities[slot] =
      { kind = "player", slot = slot, x = b[1] * HALF_U, y = b[2] * HALF_U, facing = "up" }
  end
  for _, d in ipairs(dummies) do
    entities[#entities + 1] = d
  end
  local spawns = {}
  for i, e in ipairs(blocks.E) do
    spawns[i] = { x = e[1] * HALF_U, y = e[2] * HALF_U, facing = "down" }
  end
  local hq = blocks.H[1]
  return {
    name = data.name,
    cells = cells,
    entities = entities,
    hq = hq and { x = hq[1] * HALF_U, y = hq[2] * HALF_U } or nil,
    enemy_spawns = spawns,
    meta = { profile = profile, id = data.id, env = data.env, roster = data.roster },
  }
end

-- Resolves an arena name to a built battlefield (G2 plan §11 selection
-- rule): a config arena uses the G1 loader; any other name is read through
-- `read(name) -> text` (levels/arenas/<name>.lua) and parsed with the arena
-- profile, and its `name` must equal the requested one. Raises on failure.
function M.load_arena(name, read)
  assert(type(name) == "string" and name:match("^[%w_]+$"), "level: invalid arena name")
  if arena.is_config(name) then
    return arena.load(name)
  end
  assert(type(read) == "function", "level: arena " .. name .. " needs a level reader")
  local text, err = read(name)
  if not text then
    error(("level: cannot read arena %s: %s"):format(name, tostring(err)), 0)
  end
  local built, problems = M.parse(text, "arena")
  if not built then
    error(("level: arena %s: %s"):format(name, table.concat(problems, "; ")), 0)
  end
  if built.name ~= name then
    error(("level: arena file %s declares name %s"):format(name, built.name), 0)
  end
  return built
end

return M
