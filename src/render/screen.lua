-- Owns the fixed-resolution game canvas and presents it to the window.
-- The placement math lives in render/viewport.lua, which is pure and
-- tested; this file is the LÖVE adapter.

local viewport = require("src.render.viewport")

local M = {}

local Screen = {}
Screen.__index = Screen

function M.new(w, h)
  local self = setmetatable({}, Screen)
  self.w, self.h = w or viewport.CANVAS_W, h or viewport.CANVAS_H
  self.canvas = love.graphics.newCanvas(self.w, self.h)
  self.canvas:setFilter("nearest", "nearest")
  self.mode = "integer"
  self.prescaled = nil -- intermediate canvas for "fit" mode
  self.vp = nil
  return self
end

function Screen:begin()
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 1)
end

function Screen:finish()
  love.graphics.setCanvas()
end

function Screen:cycle_mode()
  self.mode = viewport.next_mode(self.mode)
end

local function ensure_prescaled(self, k)
  local c = self.prescaled
  if c and c:getWidth() == self.w * k then
    return c
  end
  c = love.graphics.newCanvas(self.w * k, self.h * k)
  c:setFilter("linear", "linear")
  self.prescaled = c
  return c
end

-- Draws the canvas into the window. It must be called with no canvas active.
function Screen:present()
  local pw, ph = love.graphics.getPixelDimensions()
  local dpi = love.graphics.getDPIScale()
  local vp = viewport.compute(pw, ph, self.w, self.h, self.mode)
  self.vp = vp

  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  if self.mode == "integer" then
    love.graphics.draw(self.canvas, vp.x / dpi, vp.y / dpi, 0, vp.scale / dpi)
  else
    local k = vp.prescale
    local pre = ensure_prescaled(self, k)
    love.graphics.setCanvas(pre)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.draw(self.canvas, 0, 0, 0, k)
    love.graphics.setCanvas()
    love.graphics.draw(pre, vp.x / dpi, vp.y / dpi, 0, (vp.scale / k) / dpi)
  end
end

-- Encodes the current canvas contents as PNG bytes.
function Screen:capture_png()
  return self.canvas:newImageData():encode("png"):getString()
end

return M
