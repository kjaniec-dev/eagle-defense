-- Sprite compiler for hand-authored, text-indexed pixel art.
--
-- Two authoring modes:
--
-- 1. Role sprites (tanks). Every character names a material slot and a role.
--    A role is either a fixed tone (1 = deepest .. 5 = specular) or a surface
--    facing (N, NE, E, SE, S, SW, W, NW). Facings are resolved to tones only
--    after mirroring/rotation, against a fixed top-left light, so a tank turned
--    to face down is still lit from the top-left (no baked-in wrong light).
--    An optional height map adds 1 px contact shadows down-right of raised
--    parts (turret on hull, barrel over deck), again after rotation.
--
--      body  : tones 1 2 3 4 5 (s = 3)  facings q w e / a d / z x c
--      metal : tones 6 7 S 8 9          facings Q W E / A D / Z X C
--      accent: tones % * + !  (2 3 4 5)
--      '#'   : outline colour, '.' : transparent
--
-- 2. Direct sprites (HQ, tiles, icons): every character maps straight to a
--    palette colour name through a per-sprite legend.
--
-- Helpers: mirrored halves (author the left half, mirror with W<->E swap),
-- quarter-turn rotation, automatic 1 px outline facing the background.
local palette = require("lib.palette")

local M = {}

local FACING_CHARS = {
  q = "NW",
  w = "N",
  e = "NE",
  a = "W",
  d = "E",
  z = "SW",
  x = "S",
  c = "SE",
}

-- Light from the top-left.
M.FACING_TONE = { NW = 5, N = 4, W = 4, NE = 3, SW = 3, E = 2, S = 2, SE = 1 }

local ROT_CW = { N = "E", NE = "SE", E = "S", SE = "SW", S = "W", SW = "NW", W = "N", NW = "NE" }
local MIRROR_X = { N = "N", NE = "NW", E = "W", SE = "SW", S = "S", SW = "SE", W = "E", NW = "NE" }

local LEGEND = {}
for ch, f in pairs(FACING_CHARS) do
  LEGEND[ch] = { "body", f }
  LEGEND[ch:upper()] = { "metal", f }
end
for i = 1, 5 do
  LEGEND[tostring(i)] = { "body", i }
end
LEGEND["s"] = { "body", 3 }
LEGEND["6"] = { "metal", 1 }
LEGEND["7"] = { "metal", 2 }
LEGEND["S"] = { "metal", 3 }
LEGEND["8"] = { "metal", 4 }
LEGEND["9"] = { "metal", 5 }
LEGEND["%"] = { "accent", 2 }
LEGEND["*"] = { "accent", 3 }
LEGEND["+"] = { "accent", 4 }
LEGEND["!"] = { "accent", 5 }
LEGEND["#"] = { "outline", 0 }

local function new_grid(w, h)
  local g = { w = w, h = h, cells = {} }
  return g
end

local function gget(g, x, y)
  if x < 0 or y < 0 or x >= g.w or y >= g.h then
    return nil
  end
  return g.cells[y * g.w + x + 1]
end

local function gset(g, x, y, v)
  g.cells[y * g.w + x + 1] = v
end

-- Parses a role sprite definition into a grid of cells {slot, role, height}.
local function parse(def)
  local rows = def.rows
  local h = #rows
  local hw = #rows[1]
  local w = def.mirror and hw * 2 or hw
  local g = new_grid(w, h)
  for y = 0, h - 1 do
    local row = rows[y + 1]
    assert(#row == hw, ("row %d has width %d, expected %d"):format(y + 1, #row, hw))
    for x = 0, hw - 1 do
      local ch = row:sub(x + 1, x + 1)
      if ch ~= "." then
        local leg = assert(LEGEND[ch], "unknown sprite char '" .. ch .. "'")
        local cell = { slot = leg[1], role = leg[2], h = 0 }
        gset(g, x, y, cell)
        if def.mirror then
          local role = cell.role
          if type(role) == "string" then
            role = MIRROR_X[role]
          end
          gset(g, w - 1 - x, y, { slot = cell.slot, role = role, h = 0 })
        end
      end
    end
  end
  -- asymmetric patches after mirroring: { x, y, "chars..." } (a run to the right)
  for _, p in ipairs(def.patches or {}) do
    local px, py, s = p[1], p[2], p[3]
    for i = 1, #s do
      local ch = s:sub(i, i)
      if ch == "." then
        gset(g, px + i - 1, py, nil)
      elseif ch ~= "_" then
        local leg = assert(LEGEND[ch], "unknown patch char '" .. ch .. "'")
        gset(g, px + i - 1, py, { slot = leg[1], role = leg[2], h = 0 })
      end
    end
  end
  -- slot regions: body cells inside a rect switch to another material slot
  for _, r in ipairs(def.regions or {}) do
    for y = r[3], r[5] do
      for x = r[2], r[4] do
        local cell = gget(g, x, y)
        if cell and cell.slot == (r.from or "body") then
          cell.slot = r[1]
        end
        if def.mirror and r.mirror ~= false then
          local mc = gget(g, w - 1 - x, y)
          if mc and mc.slot == (r.from or "body") then
            mc.slot = r[1]
          end
        end
      end
    end
  end
  -- heights: either a digit grid (same size as rows) or rectangles
  -- { h, x1, y1, x2, y2 } in authored (left-half) coordinates, applied in
  -- order and mirrored
  for _, r in ipairs(def.heights or {}) do
    for y = r[3], r[5] do
      for x = r[2], r[4] do
        local cell = gget(g, x, y)
        if cell then
          cell.h = r[1]
        end
        if def.mirror then
          local mc = gget(g, w - 1 - x, y)
          if mc then
            mc.h = r[1]
          end
        end
      end
    end
  end
  if def.height then
    for y = 0, h - 1 do
      local row = def.height[y + 1]
      for x = 0, #row - 1 do
        local d = tonumber(row:sub(x + 1, x + 1)) or 0
        local cell = gget(g, x, y)
        if cell then
          cell.h = d
        end
        if def.mirror then
          local mc = gget(g, w - 1 - x, y)
          if mc then
            mc.h = d
          end
        end
      end
    end
  end
  return g
end

local function rotate_cw(g)
  local n = new_grid(g.h, g.w)
  for y = 0, g.h - 1 do
    for x = 0, g.w - 1 do
      local cell = gget(g, x, y)
      if cell then
        local role = cell.role
        if type(role) == "string" then
          role = ROT_CW[role]
        end
        gset(n, g.h - 1 - y, x, { slot = cell.slot, role = role, h = cell.h })
      end
    end
  end
  return n
end

local DIR_TURNS = { up = 0, right = 1, down = 2, left = 3 }

-- Compiles a role sprite for a facing direction with a material table
-- { body = ramp, metal = ramp, accent = ramp, <other slots> = ramp }.
function M.compile(def, materials, dir)
  local g = parse(def)
  for _ = 1, DIR_TURNS[dir or "up"] do
    g = rotate_cw(g)
  end
  local outline = palette.idx(def.outline or "void")
  local px = {}
  for y = 0, g.h - 1 do
    for x = 0, g.w - 1 do
      local cell = gget(g, x, y)
      local v = 0
      if cell then
        if cell.slot == "outline" then
          v = outline
        else
          local tone = cell.role
          if type(tone) == "string" then
            tone = M.FACING_TONE[tone]
          end
          -- contact shadow: a higher part up-left of this pixel shades it
          local ul = gget(g, x - 1, y - 1)
          if ul and ul.h > cell.h and cell.h > 0 then
            tone = tone - 1
          end
          if tone < 1 then
            tone = 1
          end
          local r = assert(materials[cell.slot], "no material for slot " .. cell.slot)
          v = r[tone]
        end
      end
      px[y * g.w + x + 1] = v
    end
  end
  -- 1 px transparent margin so the outline may sit outside the body box;
  -- callers blit at (x - 1, y - 1) via `ox`/`oy`.
  local pw, ph = g.w + 2, g.h + 2
  local padded = {}
  for i = 1, pw * ph do
    padded[i] = 0
  end
  for y = 0, g.h - 1 do
    for x = 0, g.w - 1 do
      padded[(y + 1) * pw + x + 2] = px[y * g.w + x + 1]
    end
  end
  local s = { w = pw, h = ph, px = padded, ox = -1, oy = -1 }
  if def.auto_outline ~= false then
    M.add_outline(s, outline)
  end
  return s
end

-- Adds a 1 px outline on transparent pixels 4-adjacent to opaque ones.
function M.add_outline(s, color)
  local add = {}
  for y = 0, s.h - 1 do
    for x = 0, s.w - 1 do
      local i = y * s.w + x + 1
      if s.px[i] == 0 then
        local function op(xx, yy)
          if xx < 0 or yy < 0 or xx >= s.w or yy >= s.h then
            return false
          end
          return s.px[yy * s.w + xx + 1] ~= 0
        end
        if op(x - 1, y) or op(x + 1, y) or op(x, y - 1) or op(x, y + 1) then
          add[#add + 1] = i
        end
      end
    end
  end
  for _, i in ipairs(add) do
    s.px[i] = color
  end
  return s
end

-- Direct sprite: rows of characters, legend maps char -> palette colour name.
-- Optional mirror (left half authored) and patches { x, y, "chars" }.
function M.direct(def)
  local rows = def.rows
  local hw = #rows[1]
  local w = def.mirror and (def.mirror_odd and hw * 2 - 1 or hw * 2) or hw
  local h = #rows
  local px = {}
  for i = 1, w * h do
    px[i] = 0
  end
  local function put(x, y, ch)
    if ch == "." then
      px[y * w + x + 1] = 0
    elseif ch ~= "_" then
      local name = assert(def.legend[ch], "unknown direct char '" .. ch .. "'")
      px[y * w + x + 1] = palette.idx(name)
    end
  end
  for y = 0, h - 1 do
    local row = rows[y + 1]
    assert(#row == hw, ("direct row %d has width %d, expected %d"):format(y + 1, #row, hw))
    for x = 0, hw - 1 do
      local ch = row:sub(x + 1, x + 1)
      put(x, y, ch)
      if def.mirror then
        local mch = def.mirror_map and def.mirror_map[ch] or ch
        put(w - 1 - x, y, mch)
      end
    end
  end
  for _, p in ipairs(def.patches or {}) do
    for i = 1, #p[3] do
      put(p[1] + i - 1, p[2], p[3]:sub(i, i))
    end
  end
  local s = { w = w, h = h, px = px }
  if def.pad then
    -- grow by `pad` px on every side so the outline fits
    local p = def.pad
    local n = { w = w + 2 * p, h = h + 2 * p, px = {} }
    for i = 1, n.w * n.h do
      n.px[i] = 0
    end
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        n.px[(y + p) * n.w + x + p + 1] = px[y * w + x + 1]
      end
    end
    s = n
  end
  if def.outline then
    M.add_outline(s, palette.idx(def.outline))
  end
  return s
end

-- Silhouette mask helper: returns a set of opaque pixel offsets.
function M.opaque(s, x, y)
  if x < 0 or y < 0 or x >= s.w or y >= s.h then
    return false
  end
  return s.px[y * s.w + x + 1] ~= 0
end

return M
