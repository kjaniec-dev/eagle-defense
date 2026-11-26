-- Raw device state -> per-player actions -> InputFrame.
--
-- This module is pure. The LÖVE adapter (input/devices.lua) builds the raw
-- snapshot, and this module turns it into an InputFrame once per simulation
-- tick.
--
-- Raw snapshot (everything since the previous sample):
--   {
--     keys   = { [key_name] = true, ... },  -- polled: currently held
--     pads   = { [player] = { buttons = { [name] = true }, leftx = n, lefty = n } },
--     events = { -- digital events in the order they happened
--       { kind = "press"|"release", device = "key", name = "d" },
--       { kind = "press"|"release", device = "pad", player = 1, name = "dpup" },
--     },
--   }
--
-- InputFrame (a fresh table per tick; treat it as immutable):
--   { [1] = { dir = "up"|"down"|"left"|"right"|nil, fire = bool,
--             fire_pressed = bool, pause_pressed = bool }, [2] = { ... } }
--
-- Direction policy: "last pressed wins".
--   1. Press events are applied in chronological order. Each pressed
--      direction moves to the top of the player's priority stack, so
--      "D then W" between two ticks yields up, and "W then D" yields right.
--   2. A change of the analog stick's 4-way direction is detected by
--      polling, so it is treated as happening after all digital events of
--      that interval.
--   3. Reconciliation with the polled state: a direction that is held
--      (or was pressed during the interval) but is not on the stack is
--      appended. Ties between such genuinely simultaneous or polled-only
--      directions are broken by the fixed order up, down, left, right
--      (the later one wins). A direction that is neither held nor pressed
--      during the interval is removed, which restores the previous one.
--   4. Latching: a press and release within one interval still counts as
--      held for that tick, so quick taps are never lost.

local M = {}

M.DIRECTIONS = { "up", "down", "left", "right" }
M.PLAYERS = 2

local Mapper = {}
Mapper.__index = Mapper

local function any_held(set, names)
  if not set or not names then
    return false
  end
  for i = 1, #names do
    if set[names[i]] then
      return true
    end
  end
  return false
end

-- Converts an analog stick to at most one of 4 directions, with hysteresis.
-- `held` is the previously engaged stick direction, or nil.
function M.stick_direction(x, y, held, cfg)
  x, y = x or 0, y or 0
  local ax, ay = math.abs(x), math.abs(y)
  local function dominant()
    if math.max(ax, ay) <= cfg.deadzone then
      return nil
    end
    if ax > ay then
      return x < 0 and "left" or "right"
    end
    return y < 0 and "up" or "down"
  end

  if held then
    local along, across, sign_ok
    if held == "left" or held == "right" then
      along, across = ax, ay
      sign_ok = (held == "left") == (x < 0)
    else
      along, across = ay, ax
      sign_ok = (held == "up") == (y < 0)
    end
    if sign_ok and along >= cfg.release then
      if across > cfg.deadzone and across > along + cfg.switch_margin then
        return dominant()
      end
      return held
    end
  end
  return dominant()
end

function M.new(bindings)
  assert(bindings and bindings.keyboard and bindings.gamepad, "bindings required")
  local self = setmetatable({ bindings = bindings, players = {} }, Mapper)
  for p = 1, M.PLAYERS do
    self.players[p] = { order = {}, fire = false, pause = false, stick = nil }
  end
  return self
end

local function remove_value(list, value)
  for i = #list, 1, -1 do
    if list[i] == value then
      table.remove(list, i)
    end
  end
end

-- Actions bound to an event, as a list of { player, action }.
local function event_actions(bindings, ev)
  local out = {}
  if ev.device == "key" then
    for p = 1, M.PLAYERS do
      local kb = bindings.keyboard[p] or {}
      for action, names in pairs(kb) do
        for i = 1, #names do
          if names[i] == ev.name then
            out[#out + 1] = { p, action }
          end
        end
      end
    end
  elseif ev.device == "pad" and ev.player then
    for action, names in pairs(bindings.gamepad) do
      for i = 1, #names do
        if names[i] == ev.name then
          out[#out + 1] = { ev.player, action }
        end
      end
    end
  end
  -- pairs() order is unspecified: sort for deterministic processing.
  table.sort(out, function(x, y)
    if x[1] ~= y[1] then
      return x[1] < y[1]
    end
    return x[2] < y[2]
  end)
  return out
end

local IS_DIRECTION = { up = true, down = true, left = true, right = true }

local function contains(list, value)
  for i = 1, #list do
    if list[i] == value then
      return true
    end
  end
  return false
end

local function promote(order, d)
  remove_value(order, d)
  order[#order + 1] = d
end

-- Samples one tick. Returns a new InputFrame.
function Mapper:update(raw)
  raw = raw or {}
  local keys = raw.keys or {}
  local pads = raw.pads or {}
  local events = raw.events or {}

  -- 1. Chronological digital events.
  local pressed = {}
  for p = 1, M.PLAYERS do
    pressed[p] = {}
  end
  for _, ev in ipairs(events) do
    if ev.kind == "press" then
      for _, pa in ipairs(event_actions(self.bindings, ev)) do
        local p, action = pa[1], pa[2]
        if pressed[p] then
          pressed[p][action] = true
          if IS_DIRECTION[action] then
            promote(self.players[p].order, action)
          end
        end
      end
    end
  end

  local frame = {}
  for p = 1, M.PLAYERS do
    local st = self.players[p]
    local kb = self.bindings.keyboard[p] or {}
    local gp = self.bindings.gamepad
    local pad = pads[p]
    local buttons = pad and pad.buttons
    local latched = pressed[p]

    -- 2. Analog stick (polled): a newly engaged direction counts as pressed
    --    after this interval's digital events.
    local stick = nil
    if pad then
      stick = M.stick_direction(pad.leftx, pad.lefty, st.stick, self.bindings.stick)
    end
    if stick and stick ~= st.stick then
      promote(st.order, stick)
    end
    st.stick = stick

    -- 3. Reconcile with the polled state (fixed-order tie-break).
    for _, d in ipairs(M.DIRECTIONS) do
      local active = latched[d] or any_held(keys, kb[d]) or any_held(buttons, gp[d]) or stick == d
      local present = contains(st.order, d)
      if active and not present then
        st.order[#st.order + 1] = d
      elseif not active and present then
        remove_value(st.order, d)
      end
    end

    local fire = latched.fire or any_held(keys, kb.fire) or any_held(buttons, gp.fire) or false
    local pause = latched.pause or any_held(keys, kb.pause) or any_held(buttons, gp.pause) or false

    frame[p] = {
      dir = st.order[#st.order],
      fire = fire,
      fire_pressed = (latched.fire or (fire and not st.fire)) == true,
      pause_pressed = (latched.pause or (pause and not st.pause)) == true,
    }
    st.fire, st.pause = fire, pause
  end
  return frame
end

-- All key names referenced by the keyboard bindings. The device adapter
-- polls only these keys.
function M.bound_keys(bindings)
  local seen, list = {}, {}
  for _, actions in pairs(bindings.keyboard) do
    for _, names in pairs(actions) do
      for _, k in ipairs(names) do
        if not seen[k] then
          seen[k] = true
          list[#list + 1] = k
        end
      end
    end
  end
  table.sort(list)
  return list
end

-- A neutral frame, with no input, for both players.
function M.empty_frame()
  local frame = {}
  for p = 1, M.PLAYERS do
    frame[p] = { dir = nil, fire = false, fire_pressed = false, pause_pressed = false }
  end
  return frame
end

return M
