-- Raw device state -> per-player actions -> InputFrame.
--
-- This module is pure. The LÖVE adapter (input/devices.lua) builds the raw
-- snapshot, and this module turns it into an InputFrame once per simulation
-- tick.
--
-- Raw snapshot:
--   {
--     keys = { [key_name] = true, ... },  -- held, or pressed since the last sample
--     pads = { [player] = { buttons = { [name] = true }, leftx = n, lefty = n } },
--   }
--
-- InputFrame (a fresh table per tick; treat it as immutable):
--   { [1] = { dir = "up"|"down"|"left"|"right"|nil, fire = bool,
--             fire_pressed = bool, pause_pressed = bool }, [2] = { ... } }
--
-- Direction policy: the most recently pressed direction that is still held
-- wins, across all of the player's devices. A tank has no diagonal movement.

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

-- Samples one tick. Returns a new InputFrame.
function Mapper:update(raw)
  raw = raw or {}
  local keys = raw.keys or {}
  local pads = raw.pads or {}
  local frame = {}

  for p = 1, M.PLAYERS do
    local st = self.players[p]
    local kb = self.bindings.keyboard[p] or {}
    local gp = self.bindings.gamepad
    local pad = pads[p]
    local buttons = pad and pad.buttons

    if pad then
      st.stick = M.stick_direction(pad.leftx, pad.lefty, st.stick, self.bindings.stick)
    else
      st.stick = nil
    end

    for _, d in ipairs(M.DIRECTIONS) do
      local held = any_held(keys, kb[d]) or any_held(buttons, gp[d]) or st.stick == d
      local present = false
      for i = 1, #st.order do
        if st.order[i] == d then
          present = true
          break
        end
      end
      if held and not present then
        st.order[#st.order + 1] = d
      elseif not held and present then
        remove_value(st.order, d)
      end
    end

    local fire = any_held(keys, kb.fire) or any_held(buttons, gp.fire)
    local pause = any_held(keys, kb.pause) or any_held(buttons, gp.pause)

    frame[p] = {
      dir = st.order[#st.order],
      fire = fire,
      fire_pressed = fire and not st.fire,
      pause_pressed = pause and not st.pause,
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
