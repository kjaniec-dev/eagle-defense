-- Bullet vs terrain and destruction (G2 plan §6, decisions G2-D2, G2-D3;
-- clarification C1; TECHNICAL_DESIGN §6).
--
-- Impacts are resolved in batches: the spawn phase is one batch, and step
-- (d) of every bullet-phase sub-step is one batch. Every impact of a batch
-- is calculated against the cell state at the start of the batch (cells are
-- only changed by `apply`), and the batch removes the union of the cells.
-- A cell claimed by several impacts is reported once, in the
-- terrain_destroyed event of the first impact in batch order. So the final
-- terrain and the consumed bullets never depend on the impact order; only
-- the event attribution does.

local units = require("src.sim.units")
local terrain = require("src.sim.terrain")

local M = {}

local N, CELL, F = units.CELLS, units.CELL, units.FIELD
local BLOCKS_BULLETS, DESTROY, NAME = terrain.BLOCKS_BULLETS, terrain.DESTROY, terrain.NAME
local PRECEDENCE = terrain.PRECEDENCE

local function clamp(v)
  if v < 0 then
    return 0
  elseif v > N - 1 then
    return N - 1
  end
  return v
end

-- Cell boundary (multiple of 64 u) nearest to v; an exact tie (v = 32
-- mod 64) goes to the lower coordinate, like the snap tie (UNV).
function M.nearest_boundary(v)
  local r = v % CELL
  if r <= CELL / 2 then
    return v - r
  end
  return v - r + CELL
end

-- Width in cells of the steel strip (G2-D3; contract, not tuning): 1/2 tile,
-- the map-character granularity. It is independent of brick_strip_cells, so
-- a wider brick strip never widens steel destruction (owner tuning,
-- 2026-11-28).
M.STEEL_STRIP_CELLS = 2

-- The `width` cells centered on the cell boundary nearest `center` (cells
-- boundary/64 - width/2 .. boundary/64 + width/2 - 1), clipped to the field.
local function strip(center, width)
  local bc = M.nearest_boundary(center) / CELL
  local half = math.floor(width / 2)
  local lo, hi = bc - half, bc + (width - half) - 1
  if lo < 0 then
    lo = 0
  end
  if hi > N - 1 then
    hi = N - 1
  end
  return lo, hi
end

function M.out_of_bounds(b)
  return b.x < 0 or b.y < 0 or b.x + b.size > F or b.y + b.size > F
end

local function sorted_keys(set)
  local out = {}
  for i in pairs(set) do
    out[#out + 1] = i
  end
  table.sort(out)
  return out
end

-- The impact of bullet b on `cells` (pure; nothing is changed). Returns nil
-- when the bullet overlaps no bullet-blocking cell, else
--   { line = impact line (cell row or column), cell = lowest blocking cell
--     index in that line under the footprint, terrain = "steel" | "brick" |
--     "block" (highest precedence there), brick = { index, ... },
--     steel = { index, ... } (ascending) }.
-- `tu` supplies brick_strip_cells and brick_strip_depth; b.power enables
-- steel breaking, over the fixed STEEL_STRIP_CELLS strip.
function M.impact(cells, b, tu)
  local d = units.DIRS[b.dir]
  local vertical = d.dx == 0
  local sign = vertical and d.dy or d.dx
  -- footprint: along-axis lines a_lo..a_hi, perpendicular cells p_lo..p_hi
  local ax, px = b.y, b.x
  if not vertical then
    ax, px = b.x, b.y
  end
  local a_lo, a_hi = clamp(math.floor(ax / CELL)), clamp(math.floor((ax + b.size - 1) / CELL))
  local p_lo, p_hi = clamp(math.floor(px / CELL)), clamp(math.floor((px + b.size - 1) / CELL))
  local function index(a, p)
    if vertical then
      return a * N + p + 1
    end
    return p * N + a + 1
  end

  -- 1. impact line: the footprint line nearest the shooter with a
  --    bullet-blocking cell (trailing line first).
  local first, last = a_lo, a_hi
  if sign < 0 then
    first, last = a_hi, a_lo
  end
  local line, cell, best
  for a = first, last, sign do
    for p = p_lo, p_hi do
      local i = index(a, p)
      local code = cells[i]
      if BLOCKS_BULLETS[code + 1] then
        if not cell or i < cell then
          cell = i
        end
        local name = NAME[code + 1]
        if not best or PRECEDENCE[name] > PRECEDENCE[best] then
          best = name
        end
      end
    end
    if cell then
      line = a
      break
    end
  end
  if not line then
    return nil
  end

  -- 2. strips, both centered on the cell boundary nearest the bullet's
  --    center: the brick strip is brick_strip_cells wide (tunable), the
  --    steel strip is always STEEL_STRIP_CELLS wide (contract).
  local center = px + math.floor(b.size / 2)
  local b_lo, b_hi = strip(center, tu.brick_strip_cells)

  -- 3. power: every steel cell of each aligned 2 x 2 steel block that holds
  --    a steel cell of the steel strip in the impact line.
  local brick, steel = {}, {}
  if b.power then
    local s_lo, s_hi = strip(center, M.STEEL_STRIP_CELLS)
    for p = s_lo, s_hi do
      local i = index(line, p)
      if DESTROY[cells[i] + 1] == "steel" then
        local row, col = math.floor((i - 1) / N), (i - 1) % N
        row, col = row - row % 2, col - col % 2
        for dr = 0, 1 do
          for dc = 0, 1 do
            local j = (row + dr) * N + (col + dc) + 1
            if DESTROY[cells[j] + 1] == "steel" then
              steel[j] = true
            end
          end
        end
      end
    end
  end

  -- 4. depth: brick_strip_depth lines from the impact line onward, in each
  --    brick-strip column. Brick is removed; removal in a column stops at
  --    the first bullet-blocking cell this impact does not remove (block
  --    always; steel unless step 3 removes it), so brick behind steel that
  --    stays is never removed.
  for p = b_lo, b_hi do
    for k = 0, tu.brick_strip_depth - 1 do
      local a = line + sign * k
      if a < 0 or a > N - 1 then
        break
      end
      local i = index(a, p)
      local code = cells[i]
      if DESTROY[code + 1] == "brick" then
        brick[i] = true
      elseif not steel[i] and BLOCKS_BULLETS[code + 1] then
        break
      end
    end
  end
  return {
    line = line,
    cell = cell,
    terrain = best,
    brick = sorted_keys(brick),
    steel = sorted_keys(steel),
  }
end

-- A new resolution batch.
function M.new_batch()
  return { claimed = {}, remove = {} }
end

local function center_of(b)
  local half = math.floor(b.size / 2)
  return b.x + half, b.y + half
end

-- Resolves bullet b against bounds and terrain within `batch`: emits
-- bullet_hit_solid and terrain_destroyed through `emit` and records the
-- removals. Returns true when the bullet is consumed (b.alive = false).
-- Cells do not change until M.apply(w, batch).
function M.resolve(w, b, batch, at_spawn, emit)
  local kind, hit
  if M.out_of_bounds(b) then
    kind = "bound"
  else
    hit = M.impact(w.cells, b, w.tuning)
    if not hit then
      return false
    end
    kind = "solid"
  end
  b.alive = false
  local cx, cy = center_of(b)
  emit(w, {
    type = "bullet_hit_solid",
    bullet = b.id,
    kind = kind,
    cell = hit and hit.cell or nil,
    terrain = hit and hit.terrain or nil,
    at_spawn = at_spawn,
    x = cx,
    y = cy,
  })
  if hit then
    for _, t in ipairs({ "brick", "steel" }) do
      local mine = {}
      for _, i in ipairs(hit[t]) do
        if not batch.claimed[i] then
          batch.claimed[i] = true
          batch.remove[#batch.remove + 1] = i
          mine[#mine + 1] = i
        end
      end
      if #mine > 0 then
        emit(w, { type = "terrain_destroyed", bullet = b.id, terrain = t, cells = mine })
      end
    end
  end
  return true
end

-- Applies a batch: every claimed cell becomes empty.
function M.apply(w, batch)
  for _, i in ipairs(batch.remove) do
    w.cells[i] = terrain.EMPTY
  end
end

return M
