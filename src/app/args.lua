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

-- Scripted input for smoke runs in the G1 arena. P1 drives up, then right;
-- P2 drives left, then up. Both press fire a few times (held for 3 ticks).
-- The result is deterministic by tick; tests/app/arena_spec.lua pins the
-- 120-tick outcome that tools/smoke.sh checks.
local P1_PRESSES = { [1] = true, [40] = true, [90] = true }
local P2_PRESSES = { [20] = true, [100] = true }

local function held(presses, tick)
  return presses[tick] or presses[tick - 1] or presses[tick - 2] or false
end

function M.smoke_frame(tick)
  local first = tick <= 60
  return {
    {
      dir = first and "up" or "right",
      fire = held(P1_PRESSES, tick),
      fire_pressed = P1_PRESSES[tick] == true,
      pause_pressed = false,
    },
    {
      dir = first and "left" or "up",
      fire = held(P2_PRESSES, tick),
      fire_pressed = P2_PRESSES[tick] == true,
      pause_pressed = false,
    },
  }
end

return M
