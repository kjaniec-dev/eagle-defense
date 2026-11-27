-- Terrain shaders evaluated per pixel in playfield space (Classic environment).
-- Every function returns a palette index. Shapes scale with the tile size T
-- (24 or 32) and the destruction cell C = T / 4, so both concepts share the
-- same shape language while 32 px gets genuinely finer texture.
local noise = require("lib.noise")
local palette = require("lib.palette")

local P = palette.idx
local M = {}

local C_ASPH = { P("asph1"), P("asph2"), P("asph3"), P("asph4"), P("metal3") }

-- Dark asphalt: large soft mottling, sparse aggregate, rare pits.
function M.ground(f, x, y)
  local T = f.T
  local v = (noise.value(x, y, T, 11) * 5 + noise.value(x, y, math.floor(T / 3), 12) * 3) / 8
  v = v + (noise.bayer(x, y) - 8) * 2
  local i
  if v < 100 then
    i = 1
  elseif v < 170 then
    i = 2
  else
    i = 3
  end
  local r = noise.rand(x, y, 13, 1000)
  if r < 22 then
    i = math.min(i + 1, 4)
  elseif r < 34 then
    i = 1
  elseif r < 36 then
    i = 5
  end
  return C_ASPH[i]
end

-- Hairline cracks: polylines in tile units, dark seam with a lit lower lip.
local function line(x0, y0, x1, y1, fn)
  local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx - dy
  while true do
    fn(x0, y0)
    if x0 == x1 and y0 == y1 then
      return
    end
    local e2 = 2 * err
    if e2 > -dy then
      err = err - dy
      x0 = x0 + sx
    end
    if e2 < dx then
      err = err + dx
      y0 = y0 + sy
    end
  end
end

function M.cracks(set, f, list, dark, lip, filter)
  local T = f.T
  for _, poly in ipairs(list) do
    for k = 1, #poly - 1 do
      local a, b = poly[k], poly[k + 1]
      line(
        math.floor(a[1] * T),
        math.floor(a[2] * T),
        math.floor(b[1] * T),
        math.floor(b[2] * T),
        function(x, y)
          if filter(x, y) then
            set(x, y, dark)
            if filter(x + 1, y + 1) and noise.rand(x, y, 14, 3) > 0 then
              set(x + 1, y + 1, lip)
            end
          end
        end
      )
    end
  end
end

------------------------------------------------------------------------------
-- Water: recessed basin, shore shadow on the north/west banks, foam on the
-- south/east banks, staggered wave crests with troughs and glints.

-- crest stamps: row 0 highlight, row 1 shoulders (water4)
local CREST = {
  [24] = { ".5555.", "4....4" },
  [32] = { "..5555..", ".4....4.", "4......4" },
}

function M.water(f, x, y)
  local T = f.T
  local tx, ty = math.floor(x / T), math.floor(y / T)
  local lx, ly = x - tx * T, y - ty * T
  local wet = function(ax, ay)
    return f.tile(ax, ay) == "W"
  end
  -- base depth: broad soft bands between water2 and water3
  local v = noise.value(x * 2, y * 3, T * 2, 21) + (noise.bayer(x, y) - 8) * 3
  local col = v < 105 and P("water2") or P("water3")
  -- wave crests on a staggered lattice
  local stamp = CREST[T]
  local sw, sh = #stamp[1], #stamp
  local py = T == 24 and 6 or 8
  local px = T == 24 and 12 or 16
  local row = math.floor(y / py)
  local ry = y - row * py - 1
  local cx = x + noise.rand(row, 7, 22, px)
  local cell = math.floor(cx / px)
  local jitter = noise.rand(cell, row, 23, px - sw + 1)
  local wx = cx - cell * px - jitter
  local active = noise.rand(cell, row, 24, 10) < 5
  if active and wx >= 0 and wx < sw and ry >= 0 and ry < sh then
    local ch = stamp[ry + 1]:sub(wx + 1, wx + 1)
    if ch == "5" then
      col = (wx == math.floor(sw / 2) and noise.rand(cell, row, 25, 4) == 0) and P("foam")
        or P("water5")
    elseif ch == "4" then
      col = P("water4")
    end
  end
  -- banks: land shadow on the north/west, broken foam on the south/east
  local n_land = not wet(tx, ty - 1)
  local w_land = not wet(tx - 1, ty)
  local s_land = not wet(tx, ty + 1)
  local e_land = not wet(tx + 1, ty)
  local lip = T == 24 and 2 or 3
  if n_land and ly < lip then
    col = ly == lip - 1 and P("water2") or P("water1")
  end
  if w_land and lx < lip - 1 then
    col = lx == lip - 2 and P("water2") or P("water1")
  end
  if s_land and ly == T - 1 then
    col = noise.rand(math.floor(x / 2), y, 26, 5) == 0 and P("water4") or P("foam")
  elseif s_land and ly == T - 2 then
    col = noise.rand(math.floor(x / 3), y, 27, 3) == 0 and P("foam") or P("water4")
  end
  if e_land and lx == T - 1 and not (n_land and ly < lip) then
    col = noise.rand(x, math.floor(y / 2), 28, 3) == 0 and P("foam") or P("water4")
  end
  return col
end

------------------------------------------------------------------------------
-- Ice: pale slab with diagonal sheen bands, fine scratches and a few cracks.

function M.ice(f, x, y)
  local T = f.T
  local tx, ty = math.floor(x / T), math.floor(y / T)
  local lx, ly = x - tx * T, y - ty * T
  local icy = function(ax, ay)
    return f.tile(ax, ay) == "I"
  end
  local col = P("ice2")
  -- broad diagonal sheen bands, soft dithered shoulders
  local d = (x + y) % (T * 3)
  local band = T == 24 and 10 or 13
  if d < band then
    local edge = math.min(d, band - 1 - d)
    if edge >= 3 or noise.bayer(x, y) < edge * 5 then
      col = P("ice3")
    end
    if d == math.floor(band / 2) and noise.rand(x, y, 31, 4) == 0 then
      col = P("foam")
    end
  end
  -- frost: sparse pale specks and darker pits
  local fr = noise.rand(x, y, 34, 1000)
  if fr < 14 then
    col = P("ice3")
  elseif fr < 20 then
    col = P("steel3")
  end
  -- thin secondary streak
  local d2 = (x + y + T) % (T * 3)
  if d2 == 0 and noise.value(x, y, 8, 33) > 110 then
    col = P("ice3")
  end
  -- slab edges: lip shadow top/left, rim light bottom/right
  if not icy(tx, ty - 1) and ly == 0 then
    col = P("steel3")
  elseif not icy(tx - 1, ty) and lx == 0 then
    col = P("steel3")
  elseif not icy(tx, ty + 1) and ly == T - 1 then
    col = P("foam")
  elseif not icy(tx + 1, ty) and lx == T - 1 then
    col = P("ice3")
  end
  return col
end

------------------------------------------------------------------------------
-- Brick: staggered courses (course = 1 cell tall, brick = 2 cells long),
-- dark mortar, top-left bevel, per-brick tint, pits and flecks. Cells can be
-- removed (damage); exposed edges fracture.

local function brick_face(f, x, y)
  local C = f.C
  local course = math.floor(y / C)
  local off = (course % 2) * C
  local bx = (x + off) % (2 * C)
  local by = y - course * C
  local id = math.floor((x + off) / (2 * C))
  local L = 2 * C
  if by == C - 1 or bx == L - 1 then
    return P("brick1")
  end
  local r = noise.rand(id, course, 41, 100)
  local base = r < 22 and P("brick4") or P("brick3")
  local col = base
  local pr = noise.rand(x, y, 42, 100)
  if by == 0 then
    col = (bx < L - 3 and pr < 70) and P("brick5") or P("brick4")
    if bx == 0 then
      col = P("brick4")
    end
  elseif bx == 0 then
    col = P("brick4")
  elseif by == C - 2 then
    col = P("brick2")
  elseif bx == L - 2 then
    col = P("brick2")
  else
    if pr < 9 then
      col = P("brick2")
    elseif pr < 16 then
      col = base == P("brick4") and P("brick3") or P("brick4")
    end
    -- larger bricks (32 px) get a second-level highlight and a hairline crack
    if C >= 8 and by == 1 and bx < 5 and pr < 60 then
      col = P("brick4")
    end
    if C >= 8 and noise.rand(id, course, 43, 7) == 0 and bx == 6 + (by % 2) and by >= 2 then
      col = P("brick2")
    end
  end
  -- chipped corners
  if bx == L - 2 and by == 0 and noise.rand(id, course, 44, 3) == 0 then
    col = P("brick1")
  end
  if bx == 0 and by == C - 2 and noise.rand(id, course, 45, 3) == 0 then
    col = P("brick2")
  end
  return col
end

-- returns palette index, or nil if the pixel is open ground (removed cell)
function M.brick(f, x, y)
  local C = f.C
  local cx, cy = math.floor(x / C), math.floor(y / C)
  if not f.cell_solid(cx, cy) then
    return nil
  end
  local lx, ly = x - cx * C, y - cy * C
  -- fracture along edges next to removed brick cells (not field/terrain edges)
  local function removed(ax, ay)
    return f.tile_of_cell(ax, ay) == "B" and not f.cell_solid(ax, ay)
  end
  local exposed = (lx == 0 and removed(cx - 1, cy))
    or (lx == C - 1 and removed(cx + 1, cy))
    or (ly == 0 and removed(cx, cy - 1))
    or (ly == C - 1 and removed(cx, cy + 1))
  if exposed then
    local r = noise.rand(math.floor(x / 2), math.floor(y / 2), 46, 100)
    if r < 45 then
      return nil
    end
    return P("brick1")
  end
  local near = (lx == 1 and removed(cx - 1, cy))
    or (lx == C - 2 and removed(cx + 1, cy))
    or (ly == 1 and removed(cx, cy - 1))
    or (ly == C - 2 and removed(cx, cy + 1))
  if near and noise.rand(math.floor(x / 2), math.floor(y / 2), 47, 100) < 45 then
    return P("brick2")
  end
  return brick_face(f, x, y)
end

-- rubble on open ground inside damaged brick tiles: sparse 2 x 2 chunks
function M.rubble(_, x, y, under)
  local gx, gy = math.floor(x / 3), math.floor(y / 3)
  if noise.rand(gx, gy, 48, 100) < 22 then
    local ox, oy = x - gx * 3, y - gy * 3
    local jx = noise.rand(gx, gy, 49, 2)
    local jy = noise.rand(gx, gy, 50, 2)
    local u, v = ox - jx, oy - jy
    if u == 0 and v == 0 then
      return P("brick4")
    elseif u >= 0 and v >= 0 and u <= 1 and v <= 1 then
      return (u + v == 2) and P("brick1") or P("brick3")
    end
  end
  return under
end

------------------------------------------------------------------------------
-- Steel: riveted blocks (2 x 2 per tile, matching the 2 x 2-cell steel
-- granularity), double bevel, diamond tread-plate face.

function M.steel(f, x, y)
  local B = f.C * 2
  local bx, by = x % B, y % B
  local last = B - 1
  -- outer bevel
  if by == 0 and bx < last then
    return bx == 0 and P("white") or P("steel5")
  end
  if bx == 0 and by < last then
    return P("steel5")
  end
  if by == last or bx == last then
    return (by == last and bx == 0 or bx == last and by == 0) and P("metal4") or P("ink")
  end
  -- inner bevel
  if by == 1 and bx < last - 1 then
    return P("metal5")
  end
  if bx == 1 and by < last - 1 then
    return P("metal5")
  end
  if by == last - 1 or bx == last - 1 then
    return P("metal3")
  end
  -- corner rivets (32 px: 2 x 2 heads)
  local ri = B >= 16 and 3 or 2
  local rx = (bx == ri or bx == last - ri - 1)
  local ry = (by == ri or by == last - ri - 1)
  if rx and ry then
    return P("white")
  end
  if (bx == ri + 1 or bx == last - ri) and (by == ri + 1 or by == last - ri) then
    return P("metal3")
  end
  -- diamond tread plate
  local s = B >= 16 and 4 or 3
  local u, v = (bx + by) % s, (bx - by) % s
  if B >= 16 then
    if u == 0 and v == 0 then
      return P("metal5")
    elseif u == 1 and v == 1 then
      return P("metal3")
    end
  elseif u == 0 and v == 0 and bx > 2 and by > 2 and bx < last - 2 and by < last - 2 then
    return P("metal5")
  end
  -- soft diagonal sheen across the plate
  if (bx + by) >= last - 1 and (bx + by) <= last + (B >= 16 and 2 or 1) then
    return P("metal5")
  end
  return P("metal4")
end

return M
