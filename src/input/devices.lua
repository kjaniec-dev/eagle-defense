-- Thin LÖVE adapter: polls the keyboard and gamepads and produces the raw
-- snapshot consumed by input/mapper.lua.
--
-- Key presses are latched between samples, so a press and release that both
-- happen within one 16.7 ms tick still register for that tick.
-- Gamepads are assigned to players in connection order: the first
-- connected pad drives P1 and the second drives P2.

local mapper = require("src.input.mapper")

local M = {}

local Devices = {}
Devices.__index = Devices

function M.new(bindings)
  local self = setmetatable({}, Devices)
  self.bindings = bindings
  self.keys = mapper.bound_keys(bindings)
  self.latched = {}
  self.pads = {} -- ordered list of Joystick objects
  for _, js in ipairs(love.joystick.getJoysticks()) do
    self:joystick_added(js)
  end
  return self
end

function Devices:keypressed(key)
  self.latched[key] = true
end

function Devices:gamepadpressed(js, button)
  self.latched_pad = self.latched_pad or {}
  self.latched_pad[js:getID()] = self.latched_pad[js:getID()] or {}
  self.latched_pad[js:getID()][button] = true
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

-- Builds the raw snapshot for one tick and clears the latches.
function Devices:sample()
  local keys = {}
  for _, k in ipairs(self.keys) do
    if self.latched[k] or love.keyboard.isDown(k) then
      keys[k] = true
    end
  end
  self.latched = {}

  local pads = {}
  local latched_pad = self.latched_pad or {}
  for player = 1, math.min(#self.pads, mapper.PLAYERS) do
    local js = self.pads[player]
    if js:isConnected() then
      local buttons = {}
      local latched = latched_pad[js:getID()] or {}
      for _, names in pairs(self.bindings.gamepad) do
        for _, b in ipairs(names) do
          if latched[b] or js:isGamepadDown(b) then
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
  self.latched_pad = {}

  return { keys = keys, pads = pads }
end

return M
