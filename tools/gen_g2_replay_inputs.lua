-- Generates the InputFrames of the G2 terrain golden replays (one-off
-- authoring aid, kept for provenance; G2 plan §14). It writes the fixtures
-- with empty checkpoints; then run `luajit tools/update_goldens.lua` to
-- compute them.
--   luajit tools/gen_g2_replay_inputs.lua
-- Running it again overwrites the fixtures, which is a golden regeneration
-- and must be called out in the PR.
--
-- The routes are goal-driven, the G2 form of G1's distance-based authoring:
-- each segment drives a tank until a position (or contact) is reached, at
-- the committed tuning, against a live simulation of the terrain arena, so
-- a tuning change keeps the same routes. Waits and fire timings are in
-- ticks. The generator asserts the intermediate positions it relies on.
-- Each fixture records the arena_id of levels/arenas/g2_terrain.lua
-- (clarification C3) and, where it matters, player_level.
package.path = "./?.lua;" .. package.path
local replay = require("src.sim.replay")
local serialize = require("src.core.serialize")
local rng = require("src.core.rng")
local tuning = require("src.sim.tuning")
local sim = require("src.sim.sim")
local level = require("src.sim.level")
local arena = require("src.sim.arena")
local levels = require("tools.lib.levels")

local ARENA = "g2_terrain"
local ACTIVE = tuning.load()
local BUILT = level.load_arena(ARENA, levels.read_arena)
local ARENA_ID = arena.id(BUILT)

local G = {}
G.__index = G

local function new(name, desc, player_level)
  local g = setmetatable({ name = name, desc = desc, codes = {}, level = player_level }, G)
  g.w = sim.new({ arena = BUILT, tuning = ACTIVE.values, seed = 1, player_level = player_level })
  return g
end

-- One tick. p1/p2 = nil or { dir = ..., press = bool }.
function G:tick(p1, p2)
  local frame = {}
  for i, spec in ipairs({ p1 or {}, p2 or {} }) do
    frame[i] = { dir = spec.dir, fire = spec.press == true, fire_pressed = spec.press == true }
  end
  self.codes[#self.codes + 1] = replay.encode_frame(frame)
  sim.step(self.w, frame)
  local bad = sim.violations(self.w)
  assert(#bad == 0, self.name .. ": " .. table.concat(bad, "; "))
  self.w.events:drain()
end

function G:tank(slot)
  return self.w.tanks[slot]
end

local function spec_for(slot, mine, other)
  if slot == 1 then
    return mine, other
  end
  return other, mine
end

-- Drives tank `slot` in `dir` until cond(t) holds (at most `max` ticks).
-- `other` is the other player's input on those ticks.
function G:drive(slot, dir, cond, max, other)
  local t = self:tank(slot)
  for _ = 1, max or 2000 do
    if cond(t) then
      return
    end
    self:tick(spec_for(slot, { dir = dir }, other))
  end
  error(
    ("%s: P%d did not reach its goal driving %s (at %d,%d)"):format(self.name, slot, dir, t.x, t.y)
  )
end

-- Drives until the tank stops moving (contact).
function G:drive_to_contact(slot, dir, max)
  local t = self:tank(slot)
  for _ = 1, max or 2000 do
    local x, y = t.x, t.y
    self:tick(spec_for(slot, { dir = dir }, nil))
    if t.x == x and t.y == y and not t.slide_dir then
      return
    end
  end
  error(("%s: P%d never reached contact driving %s"):format(self.name, slot, dir))
end

function G:wait(n, p1, p2)
  for _ = 1, n do
    self:tick(p1, p2)
  end
end

-- Waits until tank `slot` has no bullet in flight (at most `max` ticks).
function G:wait_bullets(slot, max)
  for _ = 1, max or 600 do
    local busy = false
    for _, b in ipairs(self.w.bullets) do
      busy = busy or b.owner == slot
    end
    if not busy then
      return
    end
    self:tick()
  end
  error(self.name .. ": bullets never cleared")
end

-- One tick of input `dir` for tank `slot`: it turns (snapping to the grid
-- like any move) and moves at most one step.
function G:turn(slot, dir)
  self:tick(spec_for(slot, { dir = dir }, nil))
end

-- Fires `n` shots with tank `slot` in its current facing, waiting for each
-- bullet to finish.
function G:shoot(slot, n)
  for _ = 1, n do
    self:tick(spec_for(slot, { press = true }, nil))
    self:wait_bullets(slot)
  end
end

-- Releases the input: the slide starts on the first idle tick (it must,
-- the tank having just moved on ice) and runs to its end.
function G:let_slide(slot)
  local t = self:tank(slot)
  self:tick()
  assert(
    t.slide_dir,
    ("%s: P%d did not start a slide (tick %d)"):format(self.name, slot, self.w.tick)
  )
  for _ = 1, 200 do
    if not t.slide_dir then
      return
    end
    self:tick()
  end
  error(self.name .. ": slide never ended")
end

function G:at(slot, x, y)
  local t = self:tank(slot)
  assert(
    (x == nil or t.x == x) and (y == nil or t.y == y),
    ("%s: P%d at %d,%d, expected %s,%s (tick %d)"):format(
      self.name,
      slot,
      t.x,
      t.y,
      tostring(x),
      tostring(y),
      self.w.tick
    )
  )
end

function G:write()
  local t = {
    format = 1,
    name = self.name,
    description = self.desc,
    arena = ARENA,
    arena_id = ARENA_ID,
    player_level = self.level,
    seed = 1,
    tuning_id = "00000000",
    tuning_version = ACTIVE.version,
    debug_tuned = false,
    checkpoint_every = 60,
    frames = replay.compress(self.codes),
    checkpoints = {},
  }
  local f = assert(io.open("tests/fixtures/replays/" .. self.name .. ".lua", "wb"))
  f:write(serialize.encode(t))
  f:close()
  print(self.name, #self.codes, #t.frames, "ticks / runs")
end

local function y_le(v)
  return function(t)
    return t.y <= v
  end
end
local function y_ge(v)
  return function(t)
    return t.y >= v
  end
end
local function x_le(v)
  return function(t)
    return t.x <= v
  end
end
local function x_ge(v)
  return function(t)
    return t.x >= v
  end
end

-- Half-tile -> u.
local function h(n)
  return n * 128
end

-- Drives tank `slot` horizontally to the grid column x (u): it stops within
-- one step of x, and the next vertical move snaps it onto x.
local function to_column(g, slot, x)
  if g:tank(slot).x < x then
    g:drive(slot, "right", x_ge(x))
  else
    g:drive(slot, "left", x_le(x))
  end
end

-- Route from a spawn row (y = 3072) to the strip above the water channel
-- (rows 10-11, y = 1280) through the 1-tile gap (columns 10-11). The turret
-- lane (rows 8-9) is only dangerous above y = 1168, so the tank stays below.
local function to_upper_lane(g, slot)
  to_column(g, slot, h(10))
  g:drive(slot, "up", y_le(h(10) + 6))
  g:at(slot, h(10), h(10))
end

-- From the upper strip: to column x, face up (one 7 u step, still clear of
-- the turret lane) and fire n shots.
local function shoot_up_at(g, slot, x, n)
  to_column(g, slot, x)
  g:turn(slot, "up")
  g:at(slot, x, nil)
  assert(g:tank(slot).y > 1168, "shoot_up_at: inside the turret lane")
  g:shoot(slot, n)
end

-- 1. terrain tour ------------------------------------------------------------
local g = new(
  "terrain_tour",
  "Both players drive the G2 terrain arena without shooting (the turret fires on its "
    .. "schedule): ice slides ending by distance, at steel and water contact and at the "
    .. "ice edge, forest crossings, contact with water, brick and steel."
)
-- P1 onto the ice field, release: a slide that ends by its distance.
g:drive(1, "up", y_le(2600))
g:let_slide(1)
-- again, close to the steel band: the slide ends at steel contact (y 2048).
g:drive(1, "up", y_le(2150))
g:let_slide(1)
g:at(1, h(2), 2048)
-- right toward the water column: the slide ends at water contact (x 512).
g:drive(1, "right", x_ge(400))
g:let_slide(1)
g:at(1, 512, 2048)
-- down, then right: the turn starts a slide down (it ends by distance), and
-- the right moves snap onto rows 22-23; released near the ice edge, the
-- slide ends off ice.
g:drive(1, "down", y_ge(2604))
g:drive(1, "right", x_ge(700))
g:at(1, nil, h(22))
g:let_slide(1)
assert(g:tank(1).x >= 768, "terrain_tour: the edge slide must end off ice")
-- P2 drives into its brick wall (contact at once), then along the bottom.
g:drive_to_contact(2, "up")
g:at(2, h(18), 3072)
g:drive(2, "right", x_ge(h(22)))
g:drive_to_contact(2, "up") -- up to the water channel (y 1792)
g:at(2, nil, 1792)
-- P1 through the forest patch (columns 12-15) up to the water channel.
to_column(g, 1, h(12))
g:drive_to_contact(1, "up")
g:at(1, h(12), 1792)
-- back down through the forest and onto the ice field from the right;
-- released on the ice, it slides left by its distance.
g:drive(1, "down", y_ge(h(22)))
g:drive(1, "left", x_le(500))
g:at(1, nil, h(22))
g:let_slide(1)
-- P2 back and into the bottom-right corner; both turn in place a little.
g:drive(2, "down", y_ge(h(24)))
g:wait(20)
g:write()

-- 2. brick demolition (level 0) ----------------------------------------------
g = new(
  "brick_demolition",
  "Level 0. P1 digs through the 1/2-, 1- and 2-tile brick walls from below the turret "
    .. "lane (and hits the target behind the 1/2-tile wall); P2 digs a pocket in its wall "
    .. "point-blank; P1 and P2 then shoot the remaining 2-cell wall from opposite sides on "
    .. "the same tick, P1 widens the opening, and P2 drives through it."
)
to_upper_lane(g, 1)
-- the 1/2-tile wall with the partial row (x 256: cells 5-6), then the
-- target behind it
shoot_up_at(g, 1, h(2), 5)
-- the 1-tile wall (x 1024: cells 17-18, 4 cells deep)
shoot_up_at(g, 1, h(8), 5)
-- the 2-tile wall (x 1792: cells 29-30, 8 cells deep), then its remaining
-- edges from x 1664 and x 1920 (strips 26..29 and 30..33)
shoot_up_at(g, 1, h(14), 9)
shoot_up_at(g, 1, h(13), 5)
shoot_up_at(g, 1, h(15), 5)
-- P2 digs a pocket, one muzzle impact at each of three positions: the
-- 4 x 2 strips (owner tuning) open cells 34..41, rows 46-47
for _, x in ipairs({ h(18), h(17), h(19) }) do
  to_column(g, 2, x)
  g:turn(2, "up") -- snaps onto x; the wall blocks the move
  g:at(2, x, 3072)
  g:shoot(2, 1)
end
to_column(g, 2, h(18))
g:drive_to_contact(2, "up") -- into the dug pocket: touching row 45
g:at(2, h(18), 2944)
-- P1 back down through the gap, over to the wall top: touching row 44
to_column(g, 1, h(10))
g:drive(1, "down", y_ge(h(16)))
to_column(g, 1, h(18))
g:drive_to_contact(1, "down")
g:at(1, h(18), 2560)
-- the same tick, from opposite sides, at the same 2-cell wall (rows 44-45)
g:tick({ press = true }, { press = true })
g:wait_bullets(1)
g:wait_bullets(2)
-- P1 widens the opening from above (strips 35-36 and 39-40)
for _, x in ipairs({ h(17), h(19) }) do
  to_column(g, 1, x)
  g:turn(1, "down")
  g:at(1, x, 2560)
  g:shoot(1, 1)
end
g:drive(1, "up", y_le(h(16)))
-- P2 drives through the opening
g:drive(2, "up", y_le(h(19)))
g:wait(30)
g:write()

-- 3. steel and power (level 3) -----------------------------------------------
g = new(
  "steel_and_power",
  "Level 3 (power bullets). P1 breaks the steel band and the brick behind it, and "
    .. "shoots the X block, which never breaks; P2 shoots its brick wall point-blank "
    .. "(the brick strip is the same as at level 0).",
  3
)
to_upper_lane(g, 1)
-- the X block (rows 6-7, x 2304), across the turret lane's water
shoot_up_at(g, 1, h(18), 3)
-- the steel band (rows 4-5) with brick behind (rows 2-3), at two positions
shoot_up_at(g, 1, h(20), 6)
shoot_up_at(g, 1, h(22), 6)
-- P2: point-blank brick at level 3
g:shoot(2, 4)
g:wait(30)
g:write()

-- 4. stress --------------------------------------------------------------
g = new(
  "terrain_stress",
  "Level 3. Pseudo-random input for both players (xorshift seed 2027, hold 1..30 ticks, "
    .. "~1/12 press rate), 3600 ticks in the terrain arena with the turret firing.",
  3
)
local r = rng.new(2027)
local dirs = { "up", "down", "left", "right", nil }
local hold, cur = { 0, 0 }, { nil, nil }
for _ = 1, 3600 do
  local spec = {}
  for p = 1, 2 do
    if hold[p] == 0 then
      cur[p] = dirs[r:range(1, 5)]
      hold[p] = r:range(1, 30)
    end
    hold[p] = hold[p] - 1
    spec[p] = { dir = cur[p], press = r:range(1, 12) == 1 }
  end
  g:tick(spec[1], spec[2])
end
g:write()
