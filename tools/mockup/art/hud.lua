-- Side-panel HUD in our own layout and iconography: P1 plate on the left,
-- P2 plate on the right; stage flag (left) and a segmented enemy-reserve
-- gauge (right). No icon grid, no grey right-hand column (ART_DIRECTION §5).
local canvas = require("lib.canvas")
local font = require("lib.font")
local noise = require("lib.noise")
local palette = require("lib.palette")
local sprite = require("lib.sprite")

local P = palette.idx
local M = {}

-- Bold 7 x 10 score digits (2 px strokes).
local DIGITS = {
  ["0"] = {
    ".#####.",
    "##...##",
    "##...##",
    "##..###",
    "##.#.##",
    "###..##",
    "##...##",
    "##...##",
    "##...##",
    ".#####.",
  },
  ["1"] = {
    "...##..",
    "..###..",
    ".####..",
    "...##..",
    "...##..",
    "...##..",
    "...##..",
    "...##..",
    "...##..",
    ".######",
  },
  ["2"] = {
    ".#####.",
    "##...##",
    ".....##",
    ".....##",
    "....##.",
    "..###..",
    ".##....",
    "##.....",
    "##.....",
    "#######",
  },
  ["3"] = {
    "######.",
    ".....##",
    ".....##",
    ".....##",
    "..####.",
    ".....##",
    ".....##",
    ".....##",
    "##...##",
    ".#####.",
  },
  ["4"] = {
    "....##.",
    "...###.",
    "..####.",
    ".##.##.",
    "##..##.",
    "##..##.",
    "#######",
    "....##.",
    "....##.",
    "....##.",
  },
  ["5"] = {
    "#######",
    "##.....",
    "##.....",
    "######.",
    ".....##",
    ".....##",
    ".....##",
    ".....##",
    "##...##",
    ".#####.",
  },
  ["6"] = {
    "..####.",
    ".##....",
    "##.....",
    "##.....",
    "######.",
    "##...##",
    "##...##",
    "##...##",
    "##...##",
    ".#####.",
  },
  ["7"] = {
    "#######",
    ".....##",
    ".....##",
    "....##.",
    "...##..",
    "..##...",
    "..##...",
    "..##...",
    "..##...",
    "..##...",
  },
  ["8"] = {
    ".#####.",
    "##...##",
    "##...##",
    "##...##",
    ".#####.",
    "##...##",
    "##...##",
    "##...##",
    "##...##",
    ".#####.",
  },
  ["9"] = {
    ".#####.",
    "##...##",
    "##...##",
    "##...##",
    "##...##",
    ".######",
    ".....##",
    ".....##",
    "....##.",
    ".####..",
  },
}

local FACTION = {
  p1 = {
    ramp = palette.ramps.gold,
    label = "1P",
    name = "PLAYER ONE",
    score = "012400",
    lives = 3,
    stars = 2,
    kills = { 4, 2, 1 },
  },
  p2 = {
    ramp = palette.ramps.teal,
    label = "2P",
    name = "PLAYER TWO",
    score = "008350",
    lives = 2,
    stars = 1,
    kills = { 3, 1, 0 },
  },
}

-- Mini tank icon (role sprite, left half): lives and enemy reserve.
local MINI = {
  mirror = true,
  rows = {
    "...a",
    "...a",
    "AWqw",
    "AXa4",
    "AWa3",
    "AXa3",
    "AWzx",
    "AX..",
  },
}

local STAR = {
  "....5....",
  "....4....",
  "...443...",
  "544444332",
  ".4444333.",
  "..44333..",
  "..43.32..",
  ".43...32.",
  ".3.....2.",
}

local FLAG = {
  "pp........",
  "pWWWWWWr..",
  "pWrrrrWWr.",
  "pWWWWWWr..",
  "pcccccc...",
  "p.........",
  "p.........",
  "p.........",
  "p.........",
  "ss........",
}

local function put_fn(c)
  return function(x, y, v)
    canvas.set(c, x, y, v)
  end
end

local function icon(c, rows, map, x, y)
  for yy = 1, #rows do
    local r = rows[yy]
    for xx = 1, #r do
      local ch = r:sub(xx, xx)
      if ch ~= "." then
        canvas.set(c, x + xx - 1, y + yy - 1, map[ch])
      end
    end
  end
end

local function bevel_box(c, x, y, w, h, fill, light, dark, outline)
  canvas.fill_rect(c, x, y, w, h, outline)
  canvas.fill_rect(c, x + 1, y + 1, w - 2, h - 2, fill)
  canvas.fill_rect(c, x + 1, y + 1, w - 2, 1, light)
  canvas.fill_rect(c, x + 1, y + 1, 1, h - 2, light)
  canvas.fill_rect(c, x + 1, y + h - 2, w - 2, 1, dark)
  canvas.fill_rect(c, x + w - 2, y + 1, 1, h - 2, dark)
end

-- engraved separator line
local function groove(c, x, y, w)
  canvas.fill_rect(c, x, y, w, 1, P("void"))
  canvas.fill_rect(c, x, y + 1, w, 1, P("steel2"))
end

local function big_digits(c, text, x, y, top, mid, low)
  for i = 1, #text do
    local g = DIGITS[text:sub(i, i)]
    local gx = x + (i - 1) * 8
    for gy = 0, #g - 1 do
      for k = 0, 6 do
        if g[gy + 1]:sub(k + 1, k + 1) == "#" then
          canvas.set(c, gx + k + 1, y + gy + 1, P("void"))
        end
      end
    end
    for gy = 0, #g - 1 do
      for k = 0, 6 do
        if g[gy + 1]:sub(k + 1, k + 1) == "#" then
          local col = gy < 3 and top or (gy < 7 and mid or low)
          canvas.set(c, gx + k, y + gy, col)
        end
      end
    end
  end
end

local function text(c, s, x, y, face, color, shadow)
  font.draw(put_fn(c), s, x, y, face, { color = color, shadow = shadow or P("void") })
end

-- Panel plate with machined texture.
local function plate(c, x, y, w, h, ramp)
  bevel_box(c, x, y, w, h, P("steel1"), P("steel2"), P("ink"), P("void"))
  -- subtle diagonal machining
  for yy = y + 2, y + h - 3 do
    for xx = x + 2, x + w - 3 do
      if (xx + yy * 2) % 6 == 0 and noise.rand(xx, yy, 71, 3) > 0 then
        canvas.set(c, xx, yy, P("ink"))
      end
    end
  end
  -- faction stripe along the top edge
  canvas.fill_rect(c, x + 2, y + 2, w - 4, 2, ramp[3])
  canvas.fill_rect(c, x + 2, y + 2, w - 4, 1, ramp[4])
  canvas.fill_rect(c, x + 2, y + 4, w - 4, 1, ramp[1])
  -- corner screws
  for _, p in ipairs({
    { x + 4, y + 7 },
    { x + w - 6, y + 7 },
    { x + 4, y + h - 6 },
    { x + w - 6, y + h - 6 },
  }) do
    canvas.set(c, p[1], p[2], P("steel3"))
    canvas.set(c, p[1] + 1, p[2] + 1, P("void"))
    canvas.set(c, p[1] + 1, p[2], P("steel2"))
    canvas.set(c, p[1], p[2] + 1, P("steel2"))
  end
end

-- Player block: badge, portrait, score, lives, power stars.
local function player_block(c, spec, who, x, y, w)
  local F = FACTION[who]
  local ramp = F.ramp
  local T = spec.T
  -- slanted badge
  local bw, bh = 26, 13
  for yy = 0, bh - 1 do
    for xx = 0, bw - 1 do
      local sx = x + xx + math.floor((bh - 1 - yy) / 2)
      local v = ramp[3]
      if yy == 0 then
        v = ramp[5]
      elseif yy == 1 then
        v = ramp[4]
      elseif yy == bh - 1 then
        v = ramp[2]
      end
      canvas.set(c, sx, y + yy, v)
    end
  end
  text(c, F.label, x + 9, y + 3, "big", P("void"), ramp[4])
  text(c, F.name, x + bw + 12, y + 5, "small", ramp[4])

  -- portrait window with the hero sprite at 1x on asphalt
  local py = y + 20
  local pw = T + 14
  bevel_box(c, x, py, pw, pw, P("asph2"), P("void"), P("steel2"), P("void"))
  for yy = py + 2, py + pw - 3 do
    for xx = x + 2, x + pw - 3 do
      local v = P("asph2")
      if noise.rand(xx, yy, 72, 100) < 4 then
        v = P("asph3")
      end
      if (yy % 2) == 0 then
        v = palette.shadow[v]
      end
      canvas.set(c, xx, yy, v)
    end
  end
  local s = sprite.compile(spec.tanks.player, spec.materials(who), "up")
  canvas.blit(c, s, x + 7 + s.ox, py + 7 + s.oy)

  -- score
  local sx = x + pw + 8
  text(c, "SCORE", sx, py + 2, "small", P("steel3"))
  big_digits(c, F.score, sx, py + 10, P("white"), P("steel5"), P("steel4"))
  -- hi marker under the score
  text(c, "HI 050000", sx, py + 24, "small", P("steel2"))

  -- lives
  local ly = py + pw + 8
  groove(c, x, ly - 4, w)
  text(c, "LIVES", x, ly, "small", P("steel3"))
  local mini = sprite.compile(MINI, spec.materials(who), "up")
  for i = 0, F.lives - 1 do
    canvas.blit(c, mini, x + i * 12 + mini.ox, ly + 8 + mini.oy)
  end
  text(c, "x" .. F.lives, x + F.lives * 12 + 2, ly + 9, "big", P("steel5"))

  -- power stars
  local sy = ly + 26
  text(c, "POWER", x, sy, "small", P("steel3"))
  for i = 0, 2 do
    local lit = i < F.stars
    local map = lit
        and {
          ["5"] = P("white"),
          ["4"] = ramp[4],
          ["3"] = ramp[3],
          ["2"] = ramp[2],
        }
      or {
        ["5"] = P("steel2"),
        ["4"] = P("steel2"),
        ["3"] = P("ink"),
        ["2"] = P("ink"),
      }
    icon(c, STAR, map, x + i * 13, sy + 8)
  end

  -- kills by enemy type: the real 1x sprites in small wells
  local ky = sy + 26
  groove(c, x, ky - 4, w)
  text(c, "KILLS", x, ky, "small", P("steel3"))
  local names = { { "scout", "WASP" }, { "power", "HAMMER" }, { "armor", "BASTION" } }
  local well = T + 4
  local step = well + 3
  for i, n in ipairs(names) do
    local wy = ky + 8 + (i - 1) * step
    bevel_box(c, x, wy, well, well, P("ink"), P("void"), P("steel2"), P("void"))
    local es = sprite.compile(spec.tanks[n[1]], spec.materials("enemy"), "up")
    canvas.blit(c, es, x + 2 + es.ox, wy + 2 + es.oy)
    text(c, n[2], x + well + 6, wy + 3, "small", P("steel3"))
    local k = F.kills[i]
    local on = k > 0
    big_digits(
      c,
      tostring(k),
      x + well + 12,
      wy + 10,
      on and P("white") or P("steel2"),
      on and P("steel5") or P("steel2"),
      on and P("steel4") or P("steel1")
    )
    text(c, "x", x + well + 6, wy + 14, "small", P("steel2"))
  end
  return ky + 8 + 3 * step
end

local function stage_block(c, x, y, w)
  groove(c, x, y - 6, w)
  text(c, "STAGE", x, y, "small", P("steel3"))
  icon(c, FLAG, {
    p = P("steel4"),
    s = P("steel2"),
    W = P("steel5"),
    r = P("red"),
    c = P("crimson"),
  }, x, y + 9)
  big_digits(c, "07", x + 16, y + 9, P("white"), P("steel5"), P("steel4"))
  text(c, "CLASSIC BRICK", x, y + 25, "small", P("steel2"))
end

local function reserve_block(c, spec, x, y, w)
  groove(c, x, y - 6, w)
  text(c, "RESERVE", x, y, "small", P("steel3"))
  local mini = sprite.compile(MINI, spec.materials("enemy"), "down")
  canvas.blit(c, mini, x + mini.ox, y + 10 + mini.oy)
  big_digits(c, "14", x + 14, y + 9, P("white"), P("steel5"), P("steel4"))
  text(c, "/20", x + 32, y + 14, "small", P("steel3"))
  -- segmented gauge: 20 cells, 14 remaining
  local gy = y + 24
  local cw = spec.T == 24 and 4 or 5
  local ch = spec.T == 24 and 7 or 9
  for i = 0, 19 do
    local gx = x + i * (cw + 1) + math.floor(i / 5) * 2
    if i < 14 then
      canvas.fill_rect(c, gx, gy, cw, ch, P("steel3"))
      canvas.fill_rect(c, gx, gy, cw, 1, P("steel5"))
      canvas.fill_rect(c, gx, gy + 1, 1, ch - 2, P("steel4"))
      canvas.fill_rect(c, gx, gy + ch - 1, cw, 1, P("steel2"))
    else
      canvas.fill_rect(c, gx, gy, cw, ch, P("ink"))
      canvas.fill_rect(c, gx, gy + ch - 1, cw, 1, P("steel1"))
    end
  end
end

function M.draw(c, spec)
  local T = spec.T
  local FW = 13 * T
  local fx, fy = spec.fx, spec.fy
  -- backdrop outside the field: very dark, faint diagonal weave
  for y = 0, spec.H - 1 do
    for x = 0, spec.W - 1 do
      if x < fx - 3 or x >= fx + FW + 3 or y < fy - 3 or y >= fy + FW + 3 then
        local v = P("void")
        if (x + y) % 4 == 0 or (x - y) % 4 == 0 then
          v = P("ink")
        end
        canvas.set(c, x, y, v)
      end
    end
  end
  -- playfield frame: dark inner ring, lit outer bevel
  for i = 1, 3 do
    local col = ({ P("void"), P("steel3"), P("steel1") })[i]
    canvas.fill_rect(c, fx - i, fy - i, FW + 2 * i, 1, col)
    canvas.fill_rect(c, fx - i, fy + FW + i - 1, FW + 2 * i, 1, i == 2 and P("steel2") or col)
    canvas.fill_rect(c, fx - i, fy - i, 1, FW + 2 * i, col)
    canvas.fill_rect(c, fx + FW + i - 1, fy - i, 1, FW + 2 * i, i == 2 and P("steel2") or col)
  end

  local margin = 8
  local lw = fx - 3 - 2 * margin
  local rx = fx + FW + 3 + margin
  local rw = spec.W - rx - margin
  plate(c, margin, fy, lw, FW, FACTION.p1.ramp)
  plate(c, rx, fy, rw, FW, FACTION.p2.ramp)
  local inset = 10
  local top = fy + 12
  player_block(c, spec, "p1", margin + inset, top, lw - 2 * inset)
  player_block(c, spec, "p2", rx + inset, top, rw - 2 * inset)
  local by = fy + FW - (T == 24 and 52 or 60)
  stage_block(c, margin + inset, by, lw - 2 * inset)
  reserve_block(c, spec, rx + inset, by, rw - 2 * inset)
end

return M
