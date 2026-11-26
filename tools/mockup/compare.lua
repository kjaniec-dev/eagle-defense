-- compare-1920x1080.png: the same playfield region (P1 tank, the steel and
-- brick corner, the HQ) cropped from the real 1920 x 1080 outputs, shown 1:1
-- with the physical screen pixels:
--   A at 3x (exact), B at 2.5x sharp-bilinear fit, B at 2x integer.
-- A second row zooms a detail 2x (nearest) to expose fit softness.
local canvas = require("lib.canvas")
local font = require("lib.font")
local palette = require("lib.palette")

local P = palette.idx
local M = {}

-- region in tiles (shared by both concepts)
local REGION = { x = 2, y = 8, w = 6, h = 5 }
local DETAIL = { x = 2.75, y = 9, w = 1.5, h = 2 }

local function put_rgb(img)
  return function(x, y, v)
    local col = palette.rgb[v]
    canvas.rgb_fill(img, x, y, 1, 1, col)
  end
end

local function label(img, s, x, y, face, scale, color)
  font.draw(put_rgb(img), s, x, y, face, { color = color, shadow = P("void"), scale = scale })
end

local function centered(img, s, cx, y, face, scale, color)
  local w = font.width(s, face) * scale
  label(img, s, cx - math.floor(w / 2), y, face, scale, color)
end

local function frame(img, x, y, w, h)
  canvas.rgb_fill(img, x - 3, y - 3, w + 6, h + 6, palette.rgb[P("steel2")])
  canvas.rgb_fill(img, x - 1, y - 1, w + 2, h + 2, palette.rgb[P("void")])
end

function M.build(o)
  local img = canvas.rgb_new(1920, 1080, 10, 9, 16)
  local cols = {
    {
      src = o.a3,
      ox = o.aspec.fx * 3,
      oy = o.aspec.fy * 3,
      tile = 72,
      title = "A  24 PX TILE  X3",
      lines = {
        "640X360 CANVAS, EXACT 1920X1080 FILL",
        "1 TILE = 72 SCREEN PX, CRISP",
      },
    },
    {
      src = o.bfit,
      ox = math.floor(o.bspec.fx * 5 / 2),
      oy = math.floor(o.bspec.fy * 5 / 2),
      tile = 80,
      title = "B  32 PX TILE  X2.5 FIT",
      lines = {
        "768X432, 3X NEAREST THEN LINEAR DOWN",
        "1 TILE = 80 SCREEN PX, SOFT EDGES",
      },
    },
    {
      src = o.b2,
      ox = (1920 - 768 * 2) / 2 + o.bspec.fx * 2,
      oy = (1080 - 432 * 2) / 2 + o.bspec.fy * 2,
      tile = 64,
      title = "B  32 PX TILE  X2 INTEGER",
      lines = {
        "1536X864 + 192/108 PX BARS",
        "1 TILE = 64 SCREEN PX, CRISP",
      },
    },
  }

  centered(img, "EAGLE DEFENSE  G1 PIXEL DENSITY COMPARISON", 960, 24, "big", 3, P("white"))
  centered(
    img,
    "CONCEPT ART, NOT FINAL. SAME REGION, CROPPED FROM THE REAL 1920X1080 OUTPUTS, SHOWN 1:1.",
    960,
    56,
    "small",
    2,
    P("steel4")
  )

  -- row 1: same region, 1:1 screen pixels
  local widths = {}
  local total = 0
  for i, c in ipairs(cols) do
    widths[i] = REGION.w * c.tile
    total = total + widths[i]
  end
  local gap = math.floor((1920 - total) / 4)
  local x = gap
  local top = 100
  for i, c in ipairs(cols) do
    local w, h = widths[i], REGION.h * c.tile
    c.x = x
    frame(img, x, top, w, h)
    canvas.rgb_copy(img, c.src, c.ox + REGION.x * c.tile, c.oy + REGION.y * c.tile, w, h, x, top, 1)
    local ly = top + 400 + 14
    label(img, c.title, x, ly, "big", 2, P("white"))
    for k, line in ipairs(c.lines) do
      label(img, line, x, ly + 22 + (k - 1) * 14, "small", 2, P("steel4"))
    end
    x = x + w + gap
  end

  -- row 2: detail zoom x2 (nearest) of the same screen pixels
  local ry = 600
  centered(
    img,
    "DETAIL: P1 TANK, MUZZLE FLASH AND SHELL. SCREEN PIXELS ZOOMED X2 FOR INSPECTION.",
    960,
    ry,
    "small",
    2,
    P("steel4")
  )
  for i, c in ipairs(cols) do
    local w = math.floor(DETAIL.w * c.tile)
    local h = math.floor(DETAIL.h * c.tile)
    local sx = c.ox + math.floor(DETAIL.x * c.tile)
    local sy = c.oy + math.floor(DETAIL.y * c.tile)
    local dx = c.x + math.floor((widths[i] - w * 2) / 2)
    local dy = ry + 26
    frame(img, dx, dy, w * 2, h * 2)
    canvas.rgb_copy(img, c.src, sx, sy, w, h, dx, dy, 2)
  end

  local fy = 1000
  centered(
    img,
    "2560X1440: A X4 = 96 PX TILE (EXACT FILL). B X3 = 96 PX TILE (2304X1296 + BARS). BOTH CRISP.",
    960,
    fy,
    "small",
    2,
    P("steel5")
  )
  centered(
    img,
    "STEAM DECK 1280X800: A X2 = 1280X720 + BARS. B X1 = 768X432 + BARS, OR X1.67 FIT (SOFT).",
    960,
    fy + 20,
    "small",
    2,
    P("steel5")
  )
  return img
end

return M
