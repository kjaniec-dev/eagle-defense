-- Command-line parsing for game arguments (pure).
--   --smoke=N          run N fixed ticks with scripted input, capture a PNG, then exit 0
--   --smoke-out=PATH   where to write the canvas PNG (default: save dir smoke.png)
--   --smoke-window-out=PATH  also write the full window (upscaled) PNG
--   --window=WxH       initial window size in pixels
--   --scale-mode=MODE  initial presentation mode: integer (default) or fit

local viewport = require("src.render.viewport")

local M = {}

function M.parse(argv)
  local opts = { smoke = nil, smoke_out = nil }
  for _, a in ipairs(argv or {}) do
    local key, value = a:match("^%-%-([%w%-]+)=(.*)$")
    if key == "smoke" then
      local n = tonumber(value)
      if not n or n < 1 or n ~= math.floor(n) then
        error("--smoke expects a positive integer, got " .. tostring(value), 0)
      end
      opts.smoke = n
    elseif key == "smoke-out" then
      opts.smoke_out = value
    elseif key == "smoke-window-out" then
      opts.smoke_window_out = value
    elseif key == "window" then
      local w, h = value:match("^(%d+)x(%d+)$")
      if not w then
        error("--window expects WxH, got " .. tostring(value), 0)
      end
      opts.window_w, opts.window_h = tonumber(w), tonumber(h)
    elseif key == "scale-mode" then
      local known = false
      for _, m in ipairs(viewport.MODES) do
        known = known or m == value
      end
      if not known then
        error(
          "--scale-mode expects one of " .. table.concat(viewport.MODES, ", ") .. ", got " .. value,
          0
        )
      end
      opts.scale_mode = value
    end
  end
  return opts
end

-- Scripted input for smoke runs: P1 drives right then down while firing,
-- and P2 drives up then left. The result is deterministic by tick.
function M.smoke_frame(tick)
  local first = tick <= 60
  return {
    {
      dir = first and "right" or "down",
      fire = true,
      fire_pressed = tick == 1,
      pause_pressed = false,
    },
    { dir = first and "up" or "left", fire = false, fire_pressed = false, pause_pressed = false },
  }
end

return M
