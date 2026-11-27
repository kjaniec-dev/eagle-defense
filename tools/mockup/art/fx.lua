-- Presentation effects: bullets with trails, muzzle flash, explosion with
-- restrained debris, scorch decal and palette-remap glows.
local canvas = require("lib.canvas")
local noise = require("lib.noise")
local palette = require("lib.palette")
local sprite = require("lib.sprite")

local P = palette.idx
local M = {}

local BULLET_LEGEND = {
  k = "void",
  w = "white",
  y = "gold5",
  o = "gold4",
  c = "steel5",
  s = "steel4",
}

-- Player shell, facing up (4 x 6 at 24 px, 6 x 8 at 32 px), outline included.
local PLAYER_BULLET = {
  [24] = { ".kk.", "kwwk", "kwwk", "kwyk", "kyok", ".kk." },
  [32] = { "..kk..", ".kwwk.", "kwwwyk", "kwwwyk", "kwwyok", "kwyyok", "kyooyk", ".kkkk." },
}
local ENEMY_BULLET = {
  [24] = { ".kk.", "kwwk", "kwck", "kcsk", ".kk." },
  [32] = { "..kk..", ".kwwk.", "kwwwck", "kwwcsk", "kccssk", ".kkkk." },
}

local function rotate(rows, dir)
  local s = sprite.direct({ rows = rows, legend = BULLET_LEGEND })
  local turns = ({ up = 0, right = 1, down = 2, left = 3 })[dir]
  for _ = 1, turns do
    local n = { w = s.h, h = s.w, px = {} }
    for y = 0, s.h - 1 do
      for x = 0, s.w - 1 do
        n.px[x * n.w + (s.h - 1 - y) + 1] = s.px[y * s.w + x + 1]
      end
    end
    s = n
  end
  return s
end

-- Draws a bullet whose nose is at (x, y) travelling in `dir`, with a fading
-- trail behind it. Returns the bullet's centre for lighting.
function M.bullet(c, T, x, y, dir, kind)
  local rows = (kind == "enemy" and ENEMY_BULLET or PLAYER_BULLET)[T]
  local s = rotate(rows, dir)
  local trail = kind == "enemy" and { P("steel5"), P("steel4"), P("steel3"), P("steel2") }
    or { P("gold5"), P("gold4"), P("orange"), P("red"), P("crimson") }
  local len = T == 24 and 5 or 7
  local bw = T == 24 and 2 or 2 -- trail core width
  -- unit vectors
  local vx, vy = 0, 0
  if dir == "up" then
    vy = -1
  elseif dir == "down" then
    vy = 1
  elseif dir == "left" then
    vx = -1
  else
    vx = 1
  end
  -- top-left of sprite so that the nose sits at (x, y)
  local sx, sy
  if dir == "up" then
    sx, sy = x - math.floor(s.w / 2), y
  elseif dir == "down" then
    sx, sy = x - math.floor(s.w / 2), y - s.h + 1
  elseif dir == "left" then
    sx, sy = x, y - math.floor(s.h / 2)
  else
    sx, sy = x - s.w + 1, y - math.floor(s.h / 2)
  end
  -- trail starts at the tail of the sprite
  local tail_x = sx + math.floor(s.w / 2) - (vx > 0 and s.w - 1 or 0) * 0
  local tail_y = sy + math.floor(s.h / 2)
  local blen = (vx ~= 0) and s.w or s.h
  for i = 0, len - 1 do
    local d = math.floor(blen / 2) + i
    local px = tail_x - vx * d
    local py = tail_y - vy * d
    local ti = math.min(#trail, 1 + math.floor(i * #trail / len))
    for k = -1, bw - 2 do
      local qx = px + (vy ~= 0 and k or 0)
      local qy = py + (vx ~= 0 and k or 0)
      -- dither the tail end
      if i < len - 2 or (qx + qy) % 2 == 0 then
        canvas.set(c, qx, qy, trail[ti])
      end
    end
  end
  canvas.blit(c, s, sx, sy)
  return sx + math.floor(s.w / 2), sy + math.floor(s.h / 2)
end

------------------------------------------------------------------------------
-- Muzzle flash, facing up (5 x 5 / 7 x 7), centre at the barrel tip.

local FLASH_LEGEND = { w = "white", y = "gold5", o = "gold4", r = "orange" }
local FLASH = {
  [24] = {
    "..y..",
    ".yoy.",
    "rwwwr",
    ".ywy.",
    "..o..",
  },
  [32] = {
    "...y...",
    "..yoy..",
    ".oywyo.",
    "rywwwyr",
    ".oywyo.",
    "..yoy..",
    "...r...",
  },
}

function M.muzzle(c, T, x, y)
  local s = sprite.direct({ rows = FLASH[T], legend = FLASH_LEGEND })
  canvas.blit(c, s, x - math.floor(s.w / 2), y - s.h + 1)
end

------------------------------------------------------------------------------
-- Explosion: hand-placed fire lobes over smoke lobes, dithered heat ramp.

local FIRE = {
  P("crimson"),
  P("red"),
  P("orange"),
  P("gold4"),
  P("gold5"),
  P("white"),
}

local LOBES = {
  [24] = {
    fire = {
      { 0, 0, 7, 1.0 },
      { -4, -3, 5, 0.85 },
      { 4, -4, 5, 0.8 },
      { 4, 4, 4, 0.7 },
      { -4, 4, 4, 0.75 },
      { 0, -8, 3, 0.55 },
      { -8, 1, 3, 0.5 },
      { 8, 1, 2, 0.45 },
    },
    smoke = {
      { -6, -7, 4 },
      { 5, -9, 4 },
      { 9, -3, 3 },
      { -10, -2, 3 },
      { 7, 7, 3 },
      { -6, 8, 3 },
    },
    debris = {
      { -13, -6, "a" },
      { 12, -11, "b" },
      { 13, 8, "a" },
      { -11, 11, "b" },
      { 2, -15, "c" },
    },
    sparks = { { -10, -12, -1, -1 }, { 14, -3, 1, 0 }, { 8, 13, 1, 1 } },
  },
  [32] = {
    fire = {
      { 0, 0, 9, 1.0 },
      { -6, -4, 6, 0.85 },
      { 5, -6, 6, 0.8 },
      { 6, 5, 5, 0.7 },
      { -5, 6, 5, 0.75 },
      { 1, -11, 4, 0.55 },
      { -11, 1, 4, 0.5 },
      { 11, 0, 3, 0.45 },
      { -2, 10, 3, 0.45 },
    },
    smoke = {
      { -8, -9, 5 },
      { 7, -12, 5 },
      { 12, -4, 4 },
      { -13, -2, 4 },
      { 9, 9, 4 },
      { -8, 11, 4 },
      { 0, -15, 3 },
    },
    debris = {
      { -17, -8, "a" },
      { 16, -15, "b" },
      { 17, 11, "a" },
      { -15, 15, "b" },
      { 3, -20, "c" },
      { -19, 4, "c" },
    },
    sparks = { { -13, -16, -1, -1 }, { 19, -4, 1, 0 }, { 11, 17, 1, 1 }, { -18, 10, -1, 1 } },
  },
}

-- debris chunks (dark armour fragments with a lit edge)
local DEBRIS_LEGEND = { k = "void", m = "metal4", d = "metal3", l = "metal5", g = "steel3" }
local DEBRIS = {
  a = { "kk.", "kld", ".kd" },
  b = { ".k", "kl", "kd" },
  c = { "kl", "dk" },
}

function M.explosion(c, T, cx, cy)
  local L = LOBES[T]
  local x0, y0 = cx - T, cy - T
  for y = y0, cy + T do
    for x = x0, cx + T do
      local heat = 0
      for _, l in ipairs(L.fire) do
        local dx, dy = x - (cx + l[1]), y - (cy + l[2])
        local d2 = dx * dx + dy * dy
        if d2 <= l[3] * l[3] then
          local h = l[4] * (1 - math.sqrt(d2) / (l[3] + 0.5))
          if h > heat then
            heat = h
          end
        end
      end
      local th = (noise.bayer(x, y) - 7.5) / 90
      if heat > 0 then
        local v = heat + th
        local t
        if v > 0.62 then
          t = 6
        elseif v > 0.47 then
          t = 5
        elseif v > 0.32 then
          t = 4
        elseif v > 0.18 then
          t = 3
        elseif v > 0.07 then
          t = 2
        else
          t = 1
        end
        canvas.set(c, x, y, FIRE[t])
      else
        -- smoke under/around the fire
        for _, s in ipairs(L.smoke) do
          local sx, sy = cx + s[1], cy + s[2]
          local dx, dy = x - sx, y - sy
          local d2 = dx * dx + dy * dy
          if d2 <= s[3] * s[3] then
            local lam = -(dx + dy) / s[3] + (noise.bayer(x, y) - 7.5) / 12
            local col
            if d2 > (s[3] - 1) * (s[3] - 1) and dx + dy > 0 then
              col = P("asph3")
            elseif lam > 0.75 then
              col = P("metal5")
            elseif lam > 0.1 then
              col = P("metal4")
            elseif lam > -0.6 then
              col = P("metal3")
            else
              col = P("asph4")
            end
            canvas.set(c, x, y, col)
            break
          end
        end
      end
    end
  end
  -- sparks: short bright streaks flying out
  for _, s in ipairs(L.sparks) do
    canvas.set(c, cx + s[1], cy + s[2], P("white"))
    canvas.set(c, cx + s[1] - s[3], cy + s[2] - s[4], P("gold5"))
    canvas.set(c, cx + s[1] - 2 * s[3], cy + s[2] - 2 * s[4], P("orange"))
  end
  -- debris chunks
  for _, d in ipairs(L.debris) do
    local s = sprite.direct({ rows = DEBRIS[d[3]], legend = DEBRIS_LEGEND })
    canvas.blit(c, s, cx + d[1], cy + d[2])
  end
end

-- Scorch decal: darkened ground ring with a few embers (drawn on ground).
function M.scorch(c, T, cx, cy)
  local R = math.floor(T * 0.62)
  for y = cy - R, cy + R do
    for x = cx - R, cx + R do
      local dx, dy = x - cx, y - cy
      local d2 = dx * dx + dy * dy
      local wob = noise.rand(math.floor(x / 2), math.floor(y / 2), 61, 5)
      local r2 = (R - wob) * (R - wob)
      local v = canvas.get(c, x, y)
      if v and d2 <= r2 then
        local inner = d2 <= (R * 0.55) * (R * 0.55)
        v = palette.shadow[v]
        if inner and noise.bayer(x, y) < 10 then
          v = palette.shadow[v]
        end
        if inner and noise.rand(x, y, 62, 100) < 3 then
          v = P("crimson")
        end
        canvas.set(c, x, y, v)
      end
    end
  end
end

-- Enemy spawn marker (original): four corner brackets closing in on a cool
-- diamond core, one frame of the ~1 s warning before a tank appears.
function M.spawn_marker(c, T, x, y)
  local arm = T == 24 and 6 or 8
  local inset = T == 24 and 3 or 4
  local function bracket(cx, cy, sx, sy)
    for i = 0, arm - 1 do
      local col = i < 2 and P("white") or (i < arm - 2 and P("foam") or P("water5"))
      canvas.set(c, cx + sx * i, cy, col)
      canvas.set(c, cx, cy + sy * i, col)
      -- dark backing so the bracket reads on any terrain
      canvas.set(c, cx + sx * i + 1, cy + 1, canvas.get(c, cx + sx * i + 1, cy + 1) and P("void"))
      canvas.set(c, cx + 1, cy + sy * i + 1, canvas.get(c, cx + 1, cy + sy * i + 1) and P("void"))
    end
  end
  local a, b = inset, T - 1 - inset
  bracket(x + a, y + a, 1, 1)
  bracket(x + b, y + a, -1, 1)
  bracket(x + a, y + b, 1, -1)
  bracket(x + b, y + b, -1, -1)
  -- diamond core
  local r = T == 24 and 3 or 4
  local cx, cy = x + T / 2, y + T / 2
  for dy = -r, r do
    for dx = -r, r do
      local d = math.abs(dx) + math.abs(dy)
      if d <= r then
        local col
        if d == r then
          col = P("water4")
        elseif d == 0 then
          col = P("white")
        elseif dx + dy < 0 then
          col = P("foam")
        else
          col = P("water5")
        end
        canvas.set(c, cx + dx, cy + dy, col)
      end
    end
  end
end

-- Palette-remap glow. Inside r1: light once; r1..r2: dithered falloff;
-- inside r0 (optional): light twice. Pixels outside clip are untouched.
function M.glow(c, cx, cy, r0, r1, r2, clip)
  for y = cy - r2, cy + r2 do
    for x = cx - r2, cx + r2 do
      if x >= clip[1] and y >= clip[2] and x < clip[1] + clip[3] and y < clip[2] + clip[4] then
        local dx, dy = x - cx, y - cy
        local d = math.sqrt(dx * dx + dy * dy)
        local v = canvas.get(c, x, y)
        if v and d <= r2 then
          local n = 0
          if d <= r1 then
            n = 1
          else
            local t = (d - r1) / (r2 - r1) -- 0..1
            if noise.bayer(x, y) / 16 >= t then
              n = 1
            end
          end
          if r0 and d <= r0 then
            n = 2
          end
          for _ = 1, n do
            v = palette.light[v]
          end
          canvas.set(c, x, y, v)
        end
      end
    end
  end
end

return M
