-- Thin LÖVE adapter: records digital input events in chronological order,
-- polls held state, and produces the raw snapshot consumed by
-- input/mapper.lua (see that file for the ordering and latching rules).
--
-- * Keyboard auto-repeat events are ignored. A repeat is not a new press.
-- * Unbound keys are not recorded.
-- * Gamepads are assigned to players in connection order: the first
--   connected pad drives P1 and the second drives P2.

local mapper = require("src.input.mapper")

local M = {}

local Devices = {}
Devices.__index = Devices

function M.new(bindings)
  local self = setmetatable({}, Devices)
  self.bindings = bindings
  self.keys = mapper.bound_keys(bindings)
  self.bound = {}
  for _, k in ipairs(self.keys) do
    self.bound[k] = true
  end
  self.events = {}
  self.pads = {} -- ordered list of Joystick objects
  for _, js in ipairs(love.joystick.getJoysticks()) do
    self:joystick_added(js)
  end
  return self
end

local function push(self, ev)
  self.events[#self.events + 1] = ev
end

function Devices:keypressed(key, _scancode, isrepeat)
  if isrepeat or not self.bound[key] then
    return
  end
  push(self, { kind = "press", device = "key", name = key })
end

function Devices:keyreleased(key)
  if self.bound[key] then
    push(self, { kind = "release", device = "key", name = key })
  end
end

-- Player index for a joystick, or nil when it is not assigned to a player.
function Devices:player_of(js)
  for i, pad in ipairs(self.pads) do
    if pad == js then
      return i <= mapper.PLAYERS and i or nil
    end
  end
  return nil
end

function Devices:gamepadpressed(js, button)
  local p = self:player_of(js)
  if p then
    push(self, { kind = "press", device = "pad", player = p, name = button })
  end
end

function Devices:gamepadreleased(js, button)
  local p = self:player_of(js)
  if p then
    push(self, { kind = "release", device = "pad", player = p, name = button })
  end
end

function Devices:joystick_added(js)
  if not js:isGamepad() then
    return
  end
  for _, existing in ipairs(self.pads) do
    if existing == js then
      return
    end
  end
  self.pads[#self.pads + 1] = js
end

function Devices:joystick_removed(js)
  for i = #self.pads, 1, -1 do
    if self.pads[i] == js then
      table.remove(self.pads, i)
    end
  end
end

-- Builds the raw snapshot for one tick and clears the event log.
function Devices:sample()
  local keys = {}
  for _, k in ipairs(self.keys) do
    if love.keyboard.isDown(k) then
      keys[k] = true
    end
  end

  local pads = {}
  for player = 1, math.min(#self.pads, mapper.PLAYERS) do
    local js = self.pads[player]
    if js:isConnected() then
      local buttons = {}
      for _, names in pairs(self.bindings.gamepad) do
        for _, b in ipairs(names) do
          if js:isGamepadDown(b) then
            buttons[b] = true
          end
        end
      end
      pads[player] = {
        buttons = buttons,
        leftx = js:getGamepadAxis("leftx"),
        lefty = js:getGamepadAxis("lefty"),
      }
    end
  end

  local events = self.events
  self.events = {}
  return { keys = keys, pads = pads, events = events }
end

return M
