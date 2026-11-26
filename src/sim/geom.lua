-- Integer geometry for the simulation. All boxes are half-open AABBs
-- [x, x + w) x [y, y + h) in simulation units; touching edges do not overlap.

local M = {}

function M.overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

-- Fractions are { num, den } with den > 0. nil means -infinity (as an
-- enter time) or +infinity (as an exit time).
local function less(a, b)
  return a[1] * b[2] < b[1] * a[2]
end

-- Open time interval (in units of the sub-step) during which one axis
-- overlaps, for relative position p, relative displacement v and the open
-- overlap range lo < p + v t < hi. Returns false when the axis never
-- overlaps, or enter, exit (either may be nil for an unbounded side).
local function axis_interval(p, v, lo, hi)
  if v == 0 then
    if lo < p and p < hi then
      return true, nil, nil
    end
    return false
  elseif v > 0 then
    return true, { lo - p, v }, { hi - p, v }
  end
  return true, { p - hi, -v }, { p - lo, -v }
end

-- Continuous collision of two boxes that both move linearly during one
-- sub-step: box a from (ax, ay) by (adx, ady), box b from (bx, by) by
-- (bdx, bdy). True when they overlap at some time t in [0, 1].
--
-- This is the exact test on the relative motion, in integer arithmetic. It
-- catches head-on boxes that would pass through each other at any speed or
-- phase, and it does not report boxes whose swept regions merely cross at
-- different times (e.g. perpendicular bullets).
function M.sweep_overlap(ax, ay, aw, ah, adx, ady, bx, by, bw, bh, bdx, bdy)
  local enter, exit = nil, nil
  local axes = {
    { ax - bx, adx - bdx, -aw, bw },
    { ay - by, ady - bdy, -ah, bh },
  }
  for i = 1, 2 do
    local a = axes[i]
    local ok, e, x = axis_interval(a[1], a[2], a[3], a[4])
    if not ok then
      return false
    end
    if e and (enter == nil or less(enter, e)) then
      enter = e
    end
    if x and (exit == nil or less(x, exit)) then
      exit = x
    end
  end
  -- Some t in [0, 1] lies in the open interval (enter, exit).
  if exit and exit[1] <= 0 then
    return false -- exit <= 0
  end
  if enter and enter[1] >= enter[2] then
    return false -- enter >= 1
  end
  if enter and exit and not less(enter, exit) then
    return false
  end
  return true
end

return M
