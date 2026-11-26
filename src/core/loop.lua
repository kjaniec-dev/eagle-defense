-- Fixed-timestep accumulator.
--
-- Converts variable frame deltas into a whole number of fixed simulation
-- ticks. It is pure Lua: the caller supplies the frame delta and a tick
-- callback, so it can be tested without LÖVE.
--
-- Invariants:
--   * Simulation ticks always have exactly `step` seconds of duration.
--   * At most `max_steps` ticks run per frame. A long stall drops the
--     backlog rather than entering a spiral of death.
--   * Frame deltas are clamped to `max_frame_dt` (also negative -> 0).

local M = {}

local Loop = {}
Loop.__index = Loop

-- Tolerance for float accumulation error (seconds). Prevents a tick from
-- being deferred by one frame when frame dt is exactly `step`.
local EPSILON = 1e-9

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Loop)
  self.step = opts.step or (1 / 60)
  self.max_frame_dt = opts.max_frame_dt or 0.25
  self.max_steps = opts.max_steps or 5
  self.accumulator = 0
  self.tick = 0 -- total ticks executed
  self.dropped = 0 -- total seconds discarded due to max_steps
  assert(self.step > 0, "step must be positive")
  assert(self.max_steps >= 1, "max_steps must be >= 1")
  return self
end

-- Advance by `frame_dt` seconds, calling `on_tick(tick_index)` for each
-- fixed step. Returns the number of ticks executed during this frame.
function Loop:advance(frame_dt, on_tick)
  if frame_dt ~= frame_dt or frame_dt < 0 then -- NaN or negative
    frame_dt = 0
  elseif frame_dt > self.max_frame_dt then
    frame_dt = self.max_frame_dt
  end

  self.accumulator = self.accumulator + frame_dt
  local ran = 0
  while self.accumulator + EPSILON >= self.step do
    if ran >= self.max_steps then
      self.dropped = self.dropped + self.accumulator
      self.accumulator = 0
      break
    end
    self.accumulator = self.accumulator - self.step
    self.tick = self.tick + 1
    ran = ran + 1
    on_tick(self.tick)
  end
  if self.accumulator < 0 then
    self.accumulator = 0
  end
  return ran
end

-- Fraction of a step left in the accumulator in [0, 1). Presentation may
-- use it for optional interpolation; the simulation never does.
function Loop:alpha()
  return self.accumulator / self.step
end

return M
