-- Forest canopy: overlapping leaf clusters on a jittered lattice, lit from the
-- top-left, drawn above tanks. The outermost band is partly see-through
-- (darkened) so a tank hiding at the edge stays fair (ART_DIRECTION §2.5).
local noise = require("lib.noise")
local palette = require("lib.palette")

local P = palette.idx
local M = {}

local LEAF = { P("leaf1"), P("leaf2"), P("leaf3"), P("leaf4"), P("leaf5") }

function M.build(f)
  local T = f.T
  local S = T == 24 and 7 or 9 -- lattice spacing
  local R = T == 24 and 6 or 7 -- cluster radius
  local blobs = {}
  -- lattice over the whole field; only clusters near forest tiles matter
  local n = math.floor(f.cols * T / S) + 2
  for j = -1, n do
    for i = -1, n do
      local cx = i * S + (j % 2) * math.floor(S / 2) + noise.rand(i, j, 51, 3) - 1
      local cy = j * S + noise.rand(i, j, 52, 3) - 1
      local tx, ty = math.floor(cx / T), math.floor(cy / T)
      local near = false
      for dy = -1, 1 do
        for dx = -1, 1 do
          if f.tile(tx + dx, ty + dy) == "F" then
            near = true
          end
        end
      end
      if near then
        blobs[#blobs + 1] = {
          x = cx,
          y = cy,
          r = R - noise.rand(i, j, 53, 3),
          seed = noise.rand(i, j, 54, 1000),
          -- canopy layers: lower clusters sit one tone deeper
          depth = noise.rand(i, j, 56, 3) == 0 and 1 or 0,
        }
      end
    end
  end

  local function in_forest(x, y)
    return f.tile(math.floor(x / T), math.floor(y / T)) == "F"
  end

  -- distance (in px, capped) from (x, y) to the nearest non-forest pixel
  local function edge_dist(x, y, cap)
    for d = 0, cap do
      if
        not in_forest(x - d - 1, y)
        or not in_forest(x + d + 1, y)
        or not in_forest(x, y - d - 1)
        or not in_forest(x, y + d + 1)
      then
        return d
      end
    end
    return cap + 1
  end

  -- canopy colour for (x, y) or nil if outside forest
  return function(x, y, under)
    if not in_forest(x, y) then
      return nil
    end
    -- topmost covering cluster = last in lattice order (lower rows overlap)
    local best
    for k = #blobs, 1, -1 do
      local b = blobs[k]
      local dx, dy = x - b.x, y - b.y
      if dx * dx + dy * dy <= b.r * b.r then
        best = b
        break
      end
    end
    local col
    if not best then
      col = LEAF[1]
    else
      local dx, dy = x - best.x, y - best.y
      local d = math.sqrt(dx * dx + dy * dy) / best.r
      -- facing the top-left light: +1 on the NW rim, -1 on the SE rim
      local light = -(dx + dy) / (best.r * 1.4142)
      -- leaf clumps on a 2 px grid so the canopy reads as foliage, not noise
      local tex = noise.rand(math.floor(x / 2) + best.seed, math.floor(y / 2), 55, 100)
      light = light + (tex - 50) / 300
      local t
      if d > 0.78 and light < -0.05 then
        t = 1
      elseif light > 0.55 and d > 0.45 and tex > 55 then
        t = 5
      elseif light > 0.15 then
        t = 4
      elseif light > -0.35 then
        t = 3
      else
        t = 2
      end
      t = math.max(1, t - best.depth)
      col = LEAF[t]
    end
    -- fair edge hint: the outer band lets darkened ground/tanks show through
    local e = edge_dist(x, y, 2)
    if e == 0 and (x + y) % 2 == 0 then
      return palette.shadow[under]
    elseif e == 1 and (x % 2 == 0 and y % 2 == 0) then
      return palette.shadow[under]
    end
    return col
  end
end

return M
