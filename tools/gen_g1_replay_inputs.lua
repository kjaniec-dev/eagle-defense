-- Generates the InputFrames of the G1 golden replays (one-off authoring
-- aid, kept for provenance). It writes the fixtures with empty checkpoints;
-- then run `luajit tools/update_goldens.lua` to compute them.
--   luajit tools/gen_g1_replay_inputs.lua
-- Running it again overwrites the fixtures, which is a golden regeneration
-- and must be called out in the PR.
package.path = "./?.lua;" .. package.path
local replay = require("src.sim.replay")
local serialize = require("src.core.serialize")
local rng = require("src.core.rng")

local function new(name, desc)
  return { name = name, desc = desc, codes = {} }
end
-- add n ticks: p1/p2 = { dir, press_every } ; presses happen on the first tick of each period
local function add(r, n, p1, p2)
  for i = 1, n do
    local frame = {}
    for p, spec in ipairs({ p1 or {}, p2 or {} }) do
      local press = spec.every and ((i - 1) % spec.every == 0) or false
      local held = spec.every and ((i - 1) % spec.every < 3) or false
      frame[p] = { dir = spec.dir, fire = held, fire_pressed = press }
    end
    r.codes[#r.codes + 1] = replay.encode_frame(frame)
  end
end
local function write(r)
  local t = {
    format = 1,
    name = r.name,
    description = r.desc,
    arena = "g1_arena",
    seed = 1,
    tuning_id = "00000000",
    tuning_version = 1,
    debug_tuned = false,
    checkpoint_every = 60,
    frames = replay.compress(r.codes),
    checkpoints = {},
  }
  local f = assert(io.open("tests/fixtures/replays/" .. r.name .. ".lua", "wb"))
  f:write(serialize.encode(t))
  f:close()
  print(r.name, #r.codes, #t.frames)
end

-- 1. movement tour
local r = new(
  "movement_tour",
  "Both players drive the G1 arena without shooting (the turret fires on its "
    .. "schedule): wall contact, lane entries through intersections, turns against "
    .. "walls, reversals."
)
add(r, 130, { dir = "up" }, { dir = "left" })
add(r, 214, { dir = "right" }, { dir = "up" })
add(r, 140, { dir = "up" }, { dir = "right" })
add(r, 60, { dir = "left" }, { dir = "down" })
add(r, 5, { dir = "up" }, {})
add(r, 100, { dir = "right" }, { dir = "left" })
add(r, 50, { dir = "down" }, { dir = "up" })
add(r, 300, { dir = "left" }, { dir = "right" })
add(r, 200, { dir = "up" }, { dir = "down" })
add(r, 3, { dir = "down" }, { dir = "up" })
add(r, 3, { dir = "up" }, { dir = "down" })
add(r, 120, { dir = "right" }, { dir = "left" })
add(r, 90, { dir = "down" }, {})
add(r, 30, {}, {})
write(r)

-- 2. shooting gallery
r = new(
  "shooting_gallery",
  "P1 climbs lane 6 to the top area and shoots the target dummy and walls; P2 "
    .. "shoots along the bottom; one shot per press, bullet limit 1 at level 0."
)
add(r, 130, { dir = "up", every = 25 }, { every = 30 })
add(r, 86, { dir = "right" }, { dir = "left", every = 20 })
add(r, 341, { dir = "up", every = 50 }, { dir = "up", every = 40 })
add(r, 1, { dir = "left" }, {})
add(r, 300, { every = 7 }, { dir = "right", every = 33 })
add(r, 40, { dir = "down", every = 9 }, {})
add(r, 120, { every = 15 }, { every = 1 })
write(r)

-- 3. cancellation duel
r = new(
  "cancellation_duel",
  "P1 drives under the turret's lane (column 10), waiting for a turret bullet to "
    .. "pass, then fires up repeatedly: turret bullets are cancelled and P1's shots that "
    .. "get through hit the turret."
)
add(r, 130, { dir = "up" }, {})
add(r, 214, { dir = "right" }, {})
add(r, 140, { dir = "up" }, {})
add(r, 30, {}, {}) -- let the turret bullet in column 10 pass before crossing
add(r, 43, { dir = "right" }, {})
add(r, 1, { dir = "up" }, {})
add(r, 600, { every = 40 }, { dir = "up", every = 60 })
add(r, 200, { every = 23 }, {})
write(r)

-- 4. stress
r = new(
  "stress_run",
  "Pseudo-random input for both players (xorshift seed 2026, hold 1..30 ticks, "
    .. "~1/12 press rate), 3600 ticks."
)
local g = rng.new(2026)
local dirs = { "up", "down", "left", "right", nil }
local hold, cur = { 0, 0 }, { nil, nil }
for _ = 1, 3600 do
  local frame = {}
  for p = 1, 2 do
    if hold[p] == 0 then
      cur[p] = dirs[g:range(1, 5)]
      hold[p] = g:range(1, 30)
    end
    hold[p] = hold[p] - 1
    local press = g:range(1, 12) == 1
    frame[p] = { dir = cur[p], fire = press, fire_pressed = press }
  end
  r.codes[#r.codes + 1] = replay.encode_frame(frame)
end
write(r)
