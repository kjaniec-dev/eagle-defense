-- PLACEHOLDER — G1 arena presentation. Code-drawn shapes only, not final
-- art (final assets are G3; the art direction is decided from the G1
-- mockups in docs/art/mockups/). Reads sim state through render/layout and
-- never mutates it.

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

function M.draw(st)
  local lg = love.graphics
  if not font then
    -- Drawn into the internal canvas: rasterise at 1x, not at display DPI.
    font = lg.newFont(10, "mono", 1)
    font:setFilter("nearest", "nearest")
  end
  local w = st.world
  local fx0, fy0, fs = pres.FIELD_X, pres.FIELD_Y, pres.FIELD_PX
  local view = layout.build(w, pres.TILE_PX, fx0, fy0)

  lg.clear(COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 1)
  color(COLORS.field)
  rect(fx0, fy0, fs, fs)
  color(COLORS.grid)
  for i = 0, pres.FIELD_TILES do
    rect(fx0 + i * pres.TILE_PX, fy0, 1, fs)
    rect(fx0, fy0 + i * pres.TILE_PX, fs, 1)
  end

  for _, c in ipairs(view.cells) do
    color(COLORS.block_lo)
    rect(c.x, c.y, c.w, c.h)
    color(COLORS.block)
    rect(c.x, c.y, c.w - 1, c.h - 1)
    color(COLORS.block_hi)
    rect(c.x, c.y, c.w - 1, 1)
  end

  local flashing = {}
  for _, f in ipairs(st.fx) do
    if f.type == "tank_hit" and f.ttl % 4 >= 2 then
      flashing[f.tank] = true
    end
  end
  for _, t in ipairs(view.tanks) do
    draw_tank(t, flashing[t.id])
  end
  for _, b in ipairs(view.bullets) do
    color(COLORS.outline)
    rect(b.x - 1, b.y - 1, b.size + 2, b.size + 2)
    color(b.faction == "player" and COLORS.bullet or COLORS.enemy_bullet)
    rect(b.x, b.y, b.size, b.size)
  end
  -- event sparks (presentation only)
  for _, f in ipairs(st.fx) do
    if f.x and f.type ~= "tank_hit" and f.type ~= "shot" then
      local x = fx0 + layout.px(f.x, pres.TILE_PX)
      local y = fy0 + layout.px(f.y, pres.TILE_PX)
      local r = math.max(1, math.floor(3 * f.ttl / f.max))
      color(f.type == "bullet_cancel" and COLORS.hot or COLORS.bullet, f.ttl / f.max)
      rect(x - r, y, 2 * r + 1, 1)
      rect(x, y - r, 1, 2 * r + 1)
    end
  end

  -- HUD side panels
  lg.setFont(font)
  color(COLORS.title)
  lg.print("PLACEHOLDER", 8, 6)
  lg.print("G1 ARENA", 8, 16)
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
  lg.print(("tick %d"):format(w.tick), 8, 94)
  lg.print("P1 WASD+Space", 8, 280)
  lg.print("P2 Arrows+RCtrl", 8, 292)
  lg.print("F2 restart F5 tune", 8, 304)
  lg.print("F8 save replay", 8, 316)
  lg.print("F3 stats Esc quit", 8, 328)
  if st.modified then
    color(COLORS.title)
    lg.print("TUNING MODIFIED", 8, 112)
  end
  if st.save_status then
    color(st.save_status.ok and COLORS.hot or COLORS.title)
    lg.print(st.save_status.text, 8, 124)
  end

  local rx = fx0 + fs + 8
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
  lg.setColor(1, 1, 1, 1)
end

return M
