-- The shared mid-battle composition, rendered for a given concept:
--   A: tile 24, canvas 640 x 360, playfield 312 x 312 at (164, 24)
--   B: tile 32, canvas 768 x 432, playfield 416 x 416 at (176, 8)
-- Positions are in tile units (multiples of 1/4 tile, exact on both grids).
local canvas = require("lib.canvas")
local fx = require("art.fx")
local hq = require("art.hq")
local forest = require("art.forest")
local noise = require("lib.noise")
local palette = require("lib.palette")
local sprite = require("lib.sprite")
local terrain = require("art.terrain")

local P = palette.idx
local M = {}

-- 13 x 13 tiles. B brick, S steel, W water, I ice, F forest, H HQ, . ground
M.MAP = {
  ".............",
  ".BB...S...BB.",
  ".BB...S...BB.",
  ".....BB..B...",
  "SS...BB..B...",
  "..........FFF",
  "WWWW......FFF",
  "WWWW..BB..FFF",
  ".BB...IIII...",
  ".BB..SIIII.SS",
  ".....S.......",
  ".BB..BBB..BB.",
  ".B...BHB...B.",
}

-- Damaged brick tiles: 4 x 4 destruction cells, '.' = shot away.
M.DAMAGE = {
  ["6,11"] = { "1..1", "1111", "1111", "1111" },
  ["7,11"] = { "1111", "111.", "1111", "1111" },
  ["5,11"] = { "..11", "1111", "1111", "1111" },
  ["6,3"] = { "1..1", "1111", "1111", "1111" },
  ["7,7"] = { "11..", "111.", "1111", "1111" },
  ["2,8"] = { "1111", "111.", "11..", "1111" },
  ["10,2"] = { "1111", "1111", "1111", "1..1" },
  ["1,1"] = { "..11", "1111", "1111", "1111" },
  ["9,4"] = { "1111", "1111", "1111", ".111" },
  ["9,3"] = { "1111", "1111", "1111", "1111" },
  ["2,11"] = { "1111", "1111", "1111", "11.." },
  ["10,11"] = { "1..1", "1111", "1111", "1111" },
}

-- Cracks in the ice field (tile units).
M.ICE_CRACKS = {
  { { 6.3, 8.1 }, { 6.9, 8.6 }, { 7.2, 8.5 }, { 7.6, 9.1 }, { 7.5, 9.6 } },
  { { 6.9, 8.6 }, { 6.6, 9.2 }, { 6.8, 9.8 } },
  { { 9.7, 8.2 }, { 9.2, 8.7 }, { 9.3, 9.3 } },
}

-- Hairline cracks in the asphalt (tile units).
M.CRACKS = {
  { { 0.2, 3.4 }, { 0.8, 3.2 }, { 1.4, 3.6 }, { 2.1, 3.5 }, { 2.6, 3.9 } },
  { { 7.2, 3.3 }, { 7.6, 3.8 }, { 8.2, 4.1 }, { 8.4, 4.7 } },
  { { 3.7, 11.2 }, { 4.2, 11.6 }, { 4.4, 12.5 } },
  { { 11.2, 3.3 }, { 11.8, 3.9 }, { 12.6, 4.1 } },
  { { 8.4, 11.3 }, { 8.9, 12.0 }, { 9.7, 12.4 } },
  { { 2.6, 5.2 }, { 3.3, 5.4 }, { 3.8, 5.1 } },
}

M.TANKS = {
  -- kind, design, tile x, tile y, facing
  { "p1", "player", 3, 10, "up" },
  { "p2", "player", 8, 10, "up" },
  { "enemy", "power", 3, 2, "down" },
  { "enemy", "armor", 7, 1, "down" },
  { "enemy", "scout", 9.5, 6, "left" },
}

local function materials(kind)
  local r = palette.ramps
  if kind == "p1" then
    return { body = r.gold, metal = r.metal, accent = r.lampwarm }
  elseif kind == "p2" then
    return { body = r.teal, metal = r.metal, accent = r.lampwarm }
  end
  return { body = r.steel, metal = r.metal, accent = r.lampcool, armor = r.armor }
end
M.materials = materials

local function make_field(T, ox, oy)
  local f = { T = T, C = T / 4, cols = 13, rows = 13, ox = ox, oy = oy }
  function f.tile(tx, ty)
    if tx < 0 or ty < 0 or tx >= 13 or ty >= 13 then
      return "#"
    end
    return M.MAP[ty + 1]:sub(tx + 1, tx + 1)
  end
  function f.tile_of_cell(cx, cy)
    return f.tile(math.floor(cx / 4), math.floor(cy / 4))
  end
  function f.cell_solid(cx, cy)
    local tx, ty = math.floor(cx / 4), math.floor(cy / 4)
    if f.tile(tx, ty) ~= "B" then
      return false
    end
    local mask = M.DAMAGE[tx .. "," .. ty]
    if not mask then
      return true
    end
    local lx, ly = cx - tx * 4, cy - ty * 4
    return mask[ly + 1]:sub(lx + 1, lx + 1) == "1"
  end
  return f
end

-- Tread imprints behind a tank (fading), drawn on ground/ice.
local function track_marks(c, f, x, y, dir, len)
  local T = f.T
  local tw = T == 24 and 4 or 6
  local period = T == 24 and 3 or 4
  for i = 0, len - 1 do
    for k = 1, tw - 2 do
      for side = 0, 1 do
        local lx = side == 0 and (1 + k) or (T - 2 - k)
        local px, py
        if dir == "up" then
          px, py = x + lx, y + T + i
        elseif dir == "down" then
          px, py = x + lx, y - 1 - i
        else
          px, py = x + T + i, y + lx
        end
        -- fades out over the length; ordered dither keeps it crisp
        local fade = (i + 2) / (len + 2)
        local along = (dir == "left") and px or py
        local phase = along % period
        if noise.bayer(px, py) / 16 >= fade then
          local v = canvas.get(c, px, py)
          local ground = f.tile(math.floor((px - f.ox) / T), math.floor((py - f.oy) / T)) == "."
          if v and ground then
            if phase == 0 then
              canvas.set(c, px, py, palette.shadow[palette.shadow[v]])
            elseif phase == 1 then
              canvas.set(c, px, py, palette.shadow[v])
            end
          end
        end
      end
    end
  end
end

function M.render(spec)
  local T = spec.T
  local c = canvas.new(spec.W, spec.H, P("ink"))
  local ox, oy = spec.fx, spec.fy
  local f = make_field(T, ox, oy)
  local FW = 13 * T
  local clip = { ox, oy, FW, FW }
  local tanks = spec.tanks

  -- 1. ground, water, ice
  for y = 0, FW - 1 do
    for x = 0, FW - 1 do
      local t = f.tile(math.floor(x / T), math.floor(y / T))
      local v
      if t == "W" then
        v = terrain.water(f, x, y)
      elseif t == "I" then
        v = terrain.ice(f, x, y)
      else
        v = terrain.ground(f, x, y)
        if t == "B" then
          v = terrain.rubble(f, x, y, v)
        end
      end
      canvas.set(c, ox + x, oy + y, v)
    end
  end

  terrain.cracks(
    function(x, y, v)
      canvas.set(c, ox + x, oy + y, v)
    end,
    f,
    M.ICE_CRACKS,
    P("steel3"),
    P("ice3"),
    function(x, y)
      return x >= 0
        and y >= 0
        and x < FW
        and y < FW
        and f.tile(math.floor(x / T), math.floor(y / T)) == "I"
    end
  )

  -- 2. decals: cracks, scorch under the explosion, tread marks
  terrain.cracks(
    function(x, y, v)
      canvas.set(c, ox + x, oy + y, v)
    end,
    f,
    M.CRACKS,
    P("ink"),
    P("asph4"),
    function(x, y)
      return x >= 0
        and y >= 0
        and x < FW
        and y < FW
        and f.tile(math.floor(x / T), math.floor(y / T)) == "."
    end
  )
  local ex, ey = ox + math.floor(8.5 * T), oy + math.floor(5.5 * T)
  fx.scorch(c, T, ex, ey)
  local sprites = {}
  for _, t in ipairs(M.TANKS) do
    local s = sprite.compile(tanks[t[2]], materials(t[1]), t[5])
    local x, y = ox + math.floor(t[3] * T), oy + math.floor(t[4] * T)
    sprites[#sprites + 1] = { s = s, x = x, y = y, t = t }
  end
  track_marks(c, f, sprites[1].x, sprites[1].y, "up", math.floor(T * 1.25))
  track_marks(c, f, sprites[2].x, sprites[2].y, "up", math.floor(T * 0.75))
  track_marks(c, f, sprites[3].x, sprites[3].y, "down", math.floor(T * 0.75))

  -- 3. drop shadows (single palette remap per pixel)
  local sh = T == 24 and 2 or 3
  local mask = {}
  local function cast(x, y)
    if x >= ox and y >= oy and x < ox + FW and y < oy + FW then
      mask[y * c.w + x + 1] = true
    end
  end
  for y = 0, FW - 1 do
    for x = 0, FW - 1 do
      local t = f.tile(math.floor(x / T), math.floor(y / T))
      local solid = (t == "S")
        or (t == "B" and terrain.brick(f, x, y) ~= nil)
        or (t == "F" and (x + y) % 2 == 0)
      if solid then
        cast(ox + x + sh, oy + y + sh)
      end
    end
  end
  local hqs = hq.build(T)
  local hx, hy = ox + 6 * T, oy + 12 * T
  local function cast_sprite(s, x, y)
    for yy = 0, s.h - 1 do
      for xx = 0, s.w - 1 do
        if s.px[yy * s.w + xx + 1] ~= 0 then
          cast(x + xx + sh, y + yy + sh)
        end
      end
    end
  end
  cast_sprite(hqs.sprite, hx, hy)
  for _, e in ipairs(sprites) do
    cast_sprite(e.s, e.x + e.s.ox, e.y + e.s.oy)
  end
  canvas.apply_mask(c, mask, palette.shadow)

  -- 4. walls
  for y = 0, FW - 1 do
    for x = 0, FW - 1 do
      local t = f.tile(math.floor(x / T), math.floor(y / T))
      if t == "B" then
        local v = terrain.brick(f, x, y)
        if v then
          canvas.set(c, ox + x, oy + y, v)
        end
      elseif t == "S" then
        canvas.set(c, ox + x, oy + y, terrain.steel(f, x, y))
      end
    end
  end

  -- 7. lighting (palette remaps, clipped to the playfield), under the
  -- emitters so the hot cores keep their own colours
  local u = T / 24
  local p1 = sprites[1]
  local muzzle_x, muzzle_y = p1.x + T / 2, p1.y + 1
  local shot_x, shot_y = muzzle_x, oy + math.floor(9.2 * T)
  fx.glow(c, ex, ey, math.floor(9 * u), math.floor(15 * u), math.floor(26 * u), clip)
  fx.glow(c, muzzle_x, muzzle_y, nil, math.floor(5 * u), math.floor(12 * u), clip)
  fx.glow(c, shot_x, shot_y + math.floor(2 * u), nil, math.floor(2 * u), math.floor(7 * u), clip)
  local bcx, bcy = hx + hqs.beacon[1], hy + hqs.beacon[2]
  fx.glow(c, bcx, bcy, nil, math.floor(3 * u), math.floor(10 * u), clip)

  -- 5. HQ and tanks
  canvas.blit(c, hqs.sprite, hx, hy)
  for _, e in ipairs(sprites) do
    canvas.blit(c, e.s, e.x + e.s.ox, e.y + e.s.oy, clip)
  end

  -- 6. forest canopy over tanks
  local canopy = forest.build(f)
  for y = 0, FW - 1 do
    for x = 0, FW - 1 do
      if f.tile(math.floor(x / T), math.floor(y / T)) == "F" then
        local v = canopy(x, y, canvas.get(c, ox + x, oy + y))
        if v then
          canvas.set(c, ox + x, oy + y, v)
        end
      end
    end
  end

  -- 8. projectiles: P1 shell just fired, scout shell heading left
  fx.bullet(c, T, shot_x, shot_y, "up", "player")
  fx.bullet(c, T, ox + math.floor(7.6 * T), oy + math.floor(6.5 * T), "left", "enemy")

  -- 9. spawn marker (top-right spawn point), explosion, muzzle flash
  fx.spawn_marker(c, T, ox + 12 * T, oy)
  fx.explosion(c, T, ex, ey)
  fx.muzzle(c, T, muzzle_x, muzzle_y)

  -- 10. frame and HUD
  if spec.hud then
    spec.hud(c, spec)
  end
  return c
end

return M
