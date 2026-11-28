-- PLACEHOLDER — arena presentation (G1 arena, G2 terrain arena).
-- Code-drawn shapes only, not final art: final terrain art, water and ice
-- animation, the forest edge hint and destruction VFX are G3, at the
-- approved concept A (24 px tiles, 6 px cells; ART_DIRECTION §3, §3a).
-- Reads sim state through render/layout and never mutates it. Layers are
-- drawn in layout.LAYERS order: ground, tanks, bullets, forest (above
-- tanks and bullets, G2-D5), effects, HUD.

local pres = require("config.presentation")
local layout = require("src.render.layout")

local M = {}

local font

local COLORS = {
  bg = { 0.07, 0.08, 0.10 },
  field = { 0.12, 0.13, 0.15 },
  grid = { 0.15, 0.16, 0.19 },
  block = { 0.42, 0.45, 0.52 },
  block_hi = { 0.60, 0.63, 0.70 },
  block_lo = { 0.25, 0.27, 0.32 },
  -- G2 PLACEHOLDER terrain (distinct flat/patterned looks per type)
  brick = { 0.62, 0.30, 0.20 },
  brick_mortar = { 0.33, 0.17, 0.13 },
  brick_hi = { 0.78, 0.44, 0.30 },
  steel = { 0.55, 0.60, 0.66 },
  steel_hi = { 0.86, 0.89, 0.93 },
  steel_lo = { 0.30, 0.33, 0.38 },
  water = { 0.12, 0.27, 0.55 },
  water_hi = { 0.30, 0.50, 0.80 },
  forest = { 0.13, 0.36, 0.16 },
  forest_dark = { 0.07, 0.22, 0.09 },
  forest_hi = { 0.24, 0.52, 0.24 },
  ice = { 0.72, 0.84, 0.90 },
  ice_hi = { 0.95, 0.98, 1.00 },
  p1 = { 0.95, 0.75, 0.20 },
  p2 = { 0.20, 0.80, 0.70 },
  dummy = { 0.55, 0.58, 0.64 },
  turret = { 0.40, 0.43, 0.50 },
  outline = { 0.03, 0.03, 0.04 },
  bullet = { 1, 1, 1 },
  enemy_bullet = { 1, 0.45, 0.35 },
  text = { 0.72, 0.74, 0.80 },
  title = { 1, 0.35, 0.35 },
  hot = { 1, 0.9, 0.4 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", x, y, w, h)
end

local function draw_tank(t, flash)
  local s = t.size
  local body = COLORS.dummy
  if t.kind == "player" then
    body = t.slot == 1 and COLORS.p1 or COLORS.p2
  elseif t.kind == "turret" then
    body = COLORS.turret
  end
  color(COLORS.outline)
  rect(t.x, t.y, s, s)
  color(flash and COLORS.bullet or body)
  rect(t.x + 1, t.y + 1, s - 2, s - 2)
  -- tracks along the movement axis
  color(COLORS.outline, 0.45)
  if t.facing == "up" or t.facing == "down" then
    rect(t.x + 1, t.y + 1, 4, s - 2)
    rect(t.x + s - 5, t.y + 1, 4, s - 2)
  else
    rect(t.x + 1, t.y + 1, s - 2, 4)
    rect(t.x + 1, t.y + s - 5, s - 2, 4)
  end
  -- turret disc and barrel toward the facing
  local c = math.floor(s / 2)
  color(COLORS.outline)
  rect(t.x + c - 4, t.y + c - 4, 8, 8)
  local barrel = {
    up = { c - 1, 0, 3, c },
    down = { c - 1, c, 3, s - c },
    left = { 0, c - 1, c, 3 },
    right = { c, c - 1, s - c, 3 },
  }
  local b = barrel[t.facing]
  rect(t.x + b[1], t.y + b[2], b[3], b[4])
  if t.kind ~= "player" then
    -- dummy marker: a cross so targets never read as tanks
    color(COLORS.outline, 0.6)
    rect(t.x + 3, t.y + 3, 3, 3)
    rect(t.x + s - 6, t.y + s - 6, 3, 3)
  end
end

-- Ground-layer cell looks (one 6 px cell at 24 px tiles, 8 px at 32 px).
local GROUND = {
  block = function(c)
    color(COLORS.block_lo)
    rect(c.x, c.y, c.w, c.h)
    color(COLORS.block)
    rect(c.x, c.y, c.w - 1, c.h - 1)
    color(COLORS.block_hi)
    rect(c.x, c.y, c.w - 1, 1)
  end,
  brick = function(c)
    -- running bond: a mortar line below, a joint offset on odd rows
    color(COLORS.brick)
    rect(c.x, c.y, c.w, c.h)
    color(COLORS.brick_hi)
    rect(c.x, c.y, c.w - 1, 1)
    color(COLORS.brick_mortar)
    rect(c.x, c.y + c.h - 1, c.w, 1)
    rect(c.x + (c.row % 2 == 0 and c.w - 1 or 0), c.y, 1, c.h - 1)
  end,
  steel = function(c)
    color(COLORS.steel_lo)
    rect(c.x, c.y, c.w, c.h)
    color(COLORS.steel)
    rect(c.x, c.y, c.w - 1, c.h - 1)
    color(COLORS.steel_hi)
    rect(c.x, c.y, c.w - 1, 1)
    rect(c.x, c.y, 1, c.h - 1)
  end,
  water = function(c)
    color(COLORS.water)
    rect(c.x, c.y, c.w, c.h)
    color(COLORS.water_hi)
    if (c.col + c.row) % 2 == 0 then
      rect(c.x + 1, c.y + 2, c.w - 3, 1)
    end
  end,
  ice = function(c)
    color(COLORS.ice)
    rect(c.x, c.y, c.w, c.h)
    color(COLORS.ice_hi)
    rect(c.x + c.w - 2, c.y + 1, 1, 1)
    rect(c.x + 1, c.y + c.h - 2, 1, 1)
  end,
}

local function draw_forest_cell(c)
  -- fully opaque in G2 (classic concealment); the edge hint is G3 art
  color(COLORS.forest)
  rect(c.x, c.y, c.w, c.h)
  color(COLORS.forest_dark)
  rect(c.x + 1, c.y + 1, 2, 2)
  color(COLORS.forest_hi)
  rect(c.x + c.w - 3, c.y + c.h - 3, 1, 1)
end

-- Layer painters, called in layout.LAYERS order with the draw context
-- { lg, st, w, view, fx0, fy0, fs }.
M.PAINTERS = {}

function M.PAINTERS.ground(d)
  color(COLORS.field)
  rect(d.fx0, d.fy0, d.fs, d.fs)
  color(COLORS.grid)
  for i = 0, pres.FIELD_TILES do
    rect(d.fx0 + i * pres.TILE_PX, d.fy0, 1, d.fs)
    rect(d.fx0, d.fy0 + i * pres.TILE_PX, d.fs, 1)
  end
  for _, c in ipairs(d.view.cells) do
    GROUND[c.kind](c)
  end
end

function M.PAINTERS.tanks(d)
  local flashing = {}
  for _, f in ipairs(d.st.fx) do
    if f.type == "tank_hit" and f.ttl % 4 >= 2 then
      flashing[f.tank] = true
    end
  end
  for _, t in ipairs(d.view.tanks) do
    draw_tank(t, flashing[t.id])
  end
end

function M.PAINTERS.bullets(d)
  for _, b in ipairs(d.view.bullets) do
    color(COLORS.outline)
    rect(b.x - 1, b.y - 1, b.size + 2, b.size + 2)
    color(b.faction == "player" and COLORS.bullet or COLORS.enemy_bullet)
    rect(b.x, b.y, b.size, b.size)
  end
end

function M.PAINTERS.forest(d)
  for _, c in ipairs(d.view.forest) do
    draw_forest_cell(c)
  end
end

function M.PAINTERS.effects(d)
  -- event sparks (presentation only)
  for _, f in ipairs(d.st.fx) do
    if f.x and f.type ~= "tank_hit" and f.type ~= "shot" then
      local x = d.fx0 + layout.px(f.x, pres.TILE_PX)
      local y = d.fy0 + layout.px(f.y, pres.TILE_PX)
      local r = math.max(1, math.floor(3 * f.ttl / f.max))
      color(f.type == "bullet_cancel" and COLORS.hot or COLORS.bullet, f.ttl / f.max)
      rect(x - r, y, 2 * r + 1, 1)
      rect(x, y - r, 1, 2 * r + 1)
    end
  end
end

function M.PAINTERS.hud(d)
  local lg, st, w = d.lg, d.st, d.w
  lg.setFont(font)
  color(COLORS.title)
  lg.print("PLACEHOLDER", 8, 6)
  lg.print(st.title or "ARENA", 8, 16)
  local p1, p2 = w.tanks[1], w.tanks[2]
  color(COLORS.p1)
  lg.print(("P1  L%d  hit %d"):format(p1.level, p1.hits), 8, 40)
  color(COLORS.p2)
  lg.print(("P2  L%d  hit %d"):format(p2.level, p2.hits), 8, 52)
  color(COLORS.text)
  local dummies = {}
  for _, t in ipairs(w.tanks) do
    if t.kind ~= "player" then
      dummies[#dummies + 1] = tostring(t.hits)
    end
  end
  lg.print("dummy hits " .. table.concat(dummies, "/"), 8, 70)
  lg.print(("shots %d  cancels %d"):format(st.counts.shots, st.counts.cancels), 8, 82)
  lg.print(("cells destroyed %d"):format(st.counts.destroyed or 0), 8, 94)
  lg.print(("tick %d"):format(w.tick), 8, 106)
  color(COLORS.hot)
  lg.print(("LEVEL %d (F7)"):format(w.player_level), 8, 148)
  color(COLORS.text)
  lg.print("P1 WASD+Space", 8, 256)
  lg.print("P2 Arrows+RCtrl", 8, 268)
  lg.print("F2 restart F5 tune", 8, 280)
  lg.print("F6 arena F7 level", 8, 292)
  lg.print("F8 save replay", 8, 304)
  lg.print("F3 stats Esc quit", 8, 316)
  if st.modified then
    color(COLORS.title)
    lg.print("TUNING MODIFIED", 8, 124)
  end
  if st.save_status then
    color(st.save_status.ok and COLORS.hot or COLORS.title)
    lg.print(st.save_status.text, 8, 136)
  end

  local rx = d.fx0 + d.fs + 8
  if st.edit.open then
    color(COLORS.hot)
    lg.print("TUNING (debug copy)", rx, 6)
    color(COLORS.text)
    lg.print("[ ] select  - = adjust", rx, 18)
    lg.print("Backspace reset", rx, 30)
    for i, row in ipairs(st.edit:rows()) do
      if row.selected then
        color(COLORS.hot)
      elseif row.changed then
        color(COLORS.title)
      else
        color(COLORS.text)
      end
      lg.print(("%s %s"):format(row.label, row.value), rx, 46 + (i - 1) * 12)
    end
  end
end

function M.draw(st)
  local lg = love.graphics
  if not font then
    -- Drawn into the internal canvas: rasterise at 1x, not at display DPI.
    font = lg.newFont(10, "mono", 1)
    font:setFilter("nearest", "nearest")
  end
  local w = st.world
  local d = {
    lg = lg,
    st = st,
    w = w,
    view = layout.build(w, pres.TILE_PX, pres.FIELD_X, pres.FIELD_Y),
    fx0 = pres.FIELD_X,
    fy0 = pres.FIELD_Y,
    fs = pres.FIELD_PX,
  }
  lg.clear(COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 1)
  for _, name in ipairs(layout.LAYERS) do
    M.PAINTERS[name](d)
  end
  lg.setColor(1, 1, 1, 1)
end

return M
