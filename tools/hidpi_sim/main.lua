-- SIMULATED HiDPI resource defaults for tools/hidpi_sim.sh.
-- Results produced through this file are SIMULATED HiDPI evidence, never
-- native macOS/Windows evidence.
--
-- LÖVE 11 creates canvases (newCanvas) and fonts (newFont) at
-- love.graphics.getDPIScale() when the caller passes no DPI scale. Under
-- Xvfb that is always 1, so a missing explicit DPI setting is invisible in
-- the Linux sandbox. This entry point runs the real, unchanged app from
-- EAGLE_APP_ROOT, but makes those two implicit defaults HIDPI_SIM_SCALE, as
-- a HiDPI display would (Retina 2.0, Windows 125 % / 150 %). Explicit values
-- passed by the app are never changed.
--
-- Not simulated: the window itself keeps its real DPI, so the logical ->
-- physical presentation transform of a real HiDPI window is only covered by
-- the pure viewport tests and by native acceptance.

local app_root = assert(os.getenv("EAGLE_APP_ROOT"), "hidpi_sim: EAGLE_APP_ROOT is not set")
local scale = tonumber(os.getenv("HIDPI_SIM_SCALE") or "")
assert(scale and scale > 0, "hidpi_sim: HIDPI_SIM_SCALE must be a positive number")
package.path = app_root .. "/?.lua;" .. app_root .. "/?/init.lua;" .. package.path

local lg = love.graphics
local new_canvas, new_font = lg.newCanvas, lg.newFont

-- newCanvas(w, h [, settings]). Other forms would bypass the simulation, so
-- they are refused instead of silently passed through.
lg.newCanvas = function(w, h, settings, ...)
  assert(type(w) == "number" and type(h) == "number", "hidpi_sim: newCanvas needs width/height")
  assert(settings == nil or type(settings) == "table", "hidpi_sim: unsupported newCanvas form")
  assert(select("#", ...) == 0, "hidpi_sim: unsupported newCanvas form")
  local s = {}
  for k, v in pairs(settings or {}) do
    s[k] = v
  end
  if s.dpiscale == nil then
    s.dpiscale = scale
  end
  return new_canvas(w, h, s)
end

-- newFont(size [, hinting [, dpiscale]]) and
-- newFont(filename [, size [, hinting [, dpiscale]]]). LÖVE's default size
-- is 12 and the default hinting "normal".
lg.newFont = function(a, b, c, d)
  if type(a) == "number" then
    return new_font(a, b or "normal", c or scale)
  elseif type(a) == "string" and (b == nil or type(b) == "number") then
    return new_font(a, b or 12, c or "normal", d or scale)
  end
  return new_font(a, b, c, d)
end

-- Prove that the simulation is in effect (checked by tools/hidpi_sim.sh).
print(
  (
    "HIDPI_SIM SIMULATED default_dpi=%.2f probe_canvas_dpi=%.2f probe_font_dpi=%.2f"
    .. " window_dpi=%.2f"
  ):format(
    scale,
    lg.newCanvas(8, 8):getDPIScale(),
    lg.newFont(10):getDPIScale(),
    lg.getDPIScale()
  )
)

local App = require("src.app.app")
love.run = App.run
