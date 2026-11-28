-- Tank movement (TECHNICAL_DESIGN §6): instant start and stop, one axis per
-- tick, alignment-based turn snapping and clamp-to-contact.

local units = require("src.sim.units")
local geom = require("src.sim.geom")
local terrain = require("src.sim.terrain")

local M = {}

local T, F, CELL, SNAP = units.TANK, units.FIELD, units.CELL, units.SNAP
local CELLS = units.CELLS
local BLOCKS_TANKS = terrain.BLOCKS_TANKS

-- Nearest multiple of SNAP; an exact tie (offset SNAP/2) goes to the lower
-- coordinate (up / left). Assumption, tagged UNV in GAME_DESIGN §4.1.
function M.snap_target(v)
  local r = v % SNAP
  if r <= SNAP / 2 then
    return v - r
  end
  return v - r + SNAP
end

-- True when a tank box at (x, y) would overlap a tank-blocking cell (block,
-- brick, steel, water), leave the field or overlap another present tank
-- (`self` is ignored).
function M.box_blocked(w, x, y, self)
  if x < 0 or y < 0 or x + T > F or y + T > F then
    return true
  end
  if terrain.box_hits(w.cells, x, y, T, T, BLOCKS_TANKS) then
    return true
  end
  for _, o in ipairs(w.tanks) do
    if o ~= self and o.present and geom.overlaps(x, y, T, T, o.x, o.y, T, T) then
      return true
    end
  end
  return false
end

local function solid(w, c, r)
  return BLOCKS_TANKS[w.cells[r * CELLS + c + 1] + 1]
end

-- Distance to the first tank-blocking cell ahead, scanning at most `limit` u.
-- Horizontal motion scans cell columns across the rows the box covers;
-- vertical motion scans rows across its columns.
local function cell_limit(w, t, d, limit)
  if limit <= 0 then
    return 0
  end
  local horizontal = d.dx ~= 0
  local lo = horizontal and t.y or t.x -- perpendicular extent [lo, lo + T)
  local a0, a1 = math.floor(lo / CELL), math.floor((lo + T - 1) / CELL)
  local pos = horizontal and t.x or t.y
  local sign = horizontal and d.dx or d.dy
  local first, last, step
  if sign > 0 then
    local front = pos + T
    first, last, step = math.floor(front / CELL), math.floor((front + limit - 1) / CELL), 1
  else
    first, last, step = math.floor((pos - 1) / CELL), math.floor((pos - limit) / CELL), -1
  end
  for k = first, last, step do
    for a = a0, a1 do
      local hit
      if horizontal then
        hit = solid(w, k, a)
      else
        hit = solid(w, a, k)
      end
      if hit then
        local dist = sign > 0 and (k * CELL - (pos + T)) or (pos - (k + 1) * CELL)
        return dist > 0 and dist or 0
      end
    end
  end
  return limit
end

-- Largest displacement <= max along direction d that keeps tank t clear of
-- bounds, tank-blocking cells and other present tanks (clamp to contact).
function M.free_distance(w, t, d, max)
  local limit = max
  local bound
  if d.dx > 0 then
    bound = F - (t.x + T)
  elseif d.dx < 0 then
    bound = t.x
  elseif d.dy > 0 then
    bound = F - (t.y + T)
  else
    bound = t.y
  end
  if bound < limit then
    limit = bound
  end
  limit = cell_limit(w, t, d, limit)
  for _, o in ipairs(w.tanks) do
    if o ~= t and o.present then
      local gap
      if d.dx ~= 0 then
        if t.y < o.y + T and o.y < t.y + T then
          if d.dx > 0 and o.x >= t.x + T then
            gap = o.x - (t.x + T)
          elseif d.dx < 0 and o.x + T <= t.x then
            gap = t.x - (o.x + T)
          end
        end
      elseif t.x < o.x + T and o.x < t.x + T then
        if d.dy > 0 and o.y >= t.y + T then
          gap = o.y - (t.y + T)
        elseif d.dy < 0 and o.y + T <= t.y then
          gap = t.y - (o.y + T)
        end
      end
      if gap and gap < limit then
        limit = gap
      end
    end
  end
  if limit < 0 then
    limit = 0
  end
  return limit
end

-- Moves tank t one tick in direction `dir` at `speed` u/tick. The facing
-- always changes. The perpendicular coordinate must be on the 128 u grid
-- before the tank moves; if it is not, the snap is attempted first, and a
-- blocked snap means the tank turns in place without moving. Returns
-- "moved", "blocked_snap" or "stopped" (no free distance), and the forward
-- distance moved along `dir` (0 unless "moved"; a snap is not forward
-- movement, G2 clarification C6).
function M.move_tank(w, t, dir, speed)
  local d = units.DIRS[dir]
  t.facing = dir
  if d.dx ~= 0 then
    local ty = M.snap_target(t.y)
    if ty ~= t.y then
      if M.box_blocked(w, t.x, ty, t) then
        return "blocked_snap"
      end
      t.y = ty
    end
  else
    local tx = M.snap_target(t.x)
    if tx ~= t.x then
      if M.box_blocked(w, tx, t.y, t) then
        return "blocked_snap"
      end
      t.x = tx
    end
  end
  local dist = M.free_distance(w, t, d, speed)
  if dist == 0 then
    return "stopped", 0
  end
  t.x = t.x + d.dx * dist
  t.y = t.y + d.dy * dist
  return "moved", dist
end

-- True when tank t's box overlaps at least one slippery (ice) cell.
function M.on_ice(w, t)
  return (terrain.box_hits(w.cells, t.x, t.y, T, T, terrain.SLIPPERY))
end

-- Clears a tank's ice state (hit, respawn).
function M.clear_ice(t)
  t.ice_dir, t.slide_dir, t.slide_rem = nil, nil, 0
end

local function slide_step(w, t, speed)
  local want = speed < t.slide_rem and speed or t.slide_rem
  local d = units.DIRS[t.slide_dir]
  local dist = M.free_distance(w, t, d, want)
  if dist == 0 then
    t.slide_dir, t.slide_rem = nil, 0 -- contact: the slide ends, the tick is used
    return
  end
  t.x = t.x + d.dx * dist
  t.y = t.y + d.dy * dist
  t.slide_rem = t.slide_rem - dist
  if t.slide_rem == 0 then
    t.slide_dir = nil
  end
end

-- One tick of movement for tank t with input direction `dir` (nil for no
-- input), including ice (G2 plan §7, TECHNICAL_DESIGN §6, clarification C6):
--   * "on ice" = the box overlaps an ice cell at the start of the movement;
--   * ice_dir is armed only by an input move with forward displacement > 0
--     that ends on ice, and cleared by every other outcome, so a slide never
--     re-triggers itself;
--   * a slide starts on ice with ice_dir set and an input that is none,
--     perpendicular or reverse, and moves on that same tick;
--   * a slide moves min(speed, slide_rem) along slide_dir, clamped to
--     contact, with no snap; the facing follows the input;
--   * it ends when slide_rem reaches 0, on a 0 u step (contact), when the
--     tank is off ice at the start of a tick (normal input then runs), or on
--     an input equal to slide_dir (normal movement on the same tick).
function M.tank_tick(w, t, dir, speed)
  local on_ice = M.on_ice(w, t)
  if t.slide_dir then
    if on_ice and dir ~= t.slide_dir then
      if dir then
        t.facing = dir
      end
      t.ice_dir = nil
      slide_step(w, t, speed)
      return
    end
    t.slide_dir, t.slide_rem = nil, 0 -- off ice, or cancelled by the same direction
  elseif on_ice and t.ice_dir and dir ~= t.ice_dir and w.tuning.ice_slide_distance > 0 then
    t.slide_dir, t.slide_rem = t.ice_dir, w.tuning.ice_slide_distance
    if dir then
      t.facing = dir
    end
    t.ice_dir = nil
    slide_step(w, t, speed)
    return
  end
  if not dir then
    t.ice_dir = nil
    return
  end
  local result, forward = M.move_tank(w, t, dir, speed)
  if result == "moved" and forward > 0 and M.on_ice(w, t) then
    t.ice_dir = dir
  else
    t.ice_dir = nil
  end
end

return M
