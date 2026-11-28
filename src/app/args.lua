-- Command-line parsing for game arguments (pure).
--   --smoke=N          run N fixed ticks with scripted input, capture a PNG, then exit 0
--   --smoke-out=PATH   where to write the canvas PNG (default: save dir smoke.png)
--   --smoke-window-out=PATH  also write the full window (upscaled) PNG
--   --window=WxH       initial window size in pixels
--   --scale-mode=MODE  initial presentation mode: integer (default) or fit
--   --arena=NAME       initial arena: g2_terrain (default) or g1_arena

local viewport = require("src.render.viewport")

local M = {}

-- Arenas the app can open (F6 cycles them in this order). The first is the
-- default (G2 plan §12).
M.ARENAS = { "g2_terrain", "g1_arena" }
M.DEFAULT_ARENA = M.ARENAS[1]

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
    elseif key == "arena" then
      local known = false
      for _, name in ipairs(M.ARENAS) do
        known = known or name == value
      end
      if not known then
        error("--arena expects one of " .. table.concat(M.ARENAS, ", ") .. ", got " .. value, 0)
      end
      opts.arena = value
    end
  end
  return opts
end

-- Scripted input for smoke runs, per arena. Deterministic by tick;
-- tests/app/arena_spec.lua pins the 120-tick outcomes that tools/smoke.sh
-- checks (tools/lib/smoke_expect.sh).
--
-- G1 arena: P1 drives up, then right; P2 drives left, then up. Both press
-- fire a few times (held for 3 ticks). Unchanged from G1.
local P1_PRESSES = { [1] = true, [40] = true, [90] = true }
local P2_PRESSES = { [20] = true, [100] = true }

-- G2 terrain arena: P1 drives up onto the ice and releases (a slide), then
-- right and releases (a slide into the water column); P2 stays at its
-- brick wall and shoots it point-blank, then through the hole it digs.
local G2_P2_PRESSES =
  { [1] = true, [21] = true, [41] = true, [61] = true, [81] = true, [101] = true }

local function held(presses, tick)
  return presses[tick] or presses[tick - 1] or presses[tick - 2] or false
end

local function g2_frame(tick)
  local dir
  if tick <= 30 then
    dir = "up"
  elseif tick > 60 and tick <= 90 then
    dir = "right"
  end
  return {
    { dir = dir, fire = false, fire_pressed = false, pause_pressed = false },
    {
      dir = nil,
      fire = held(G2_P2_PRESSES, tick),
      fire_pressed = G2_P2_PRESSES[tick] == true,
      pause_pressed = false,
    },
  }
end

-- The arena is required: each arena has its own script and expectation.
function M.smoke_frame(tick, arena)
  assert(arena == "g1_arena" or arena == "g2_terrain", "smoke_frame: arena required")
  if arena == "g2_terrain" then
    return g2_frame(tick)
  end
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
