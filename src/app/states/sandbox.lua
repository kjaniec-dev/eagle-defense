-- Debug sandbox scene (G0). This is NOT gameplay. Two placeholder markers
-- move with the P1/P2 InputFrame on fixed ticks. They prove the
-- input -> fixed tick -> render path and the scaling.

local geo = require("config.geometry")

local M = {}

M.SPEED = 24 -- subpixels per tick (1.5 px), an arbitrary debug value

-- Pure: creates the marker state.
function M.initial_markers()
  local sub, t = geo.SUB, geo.TILE
  local base_y = geo.FIELD_Y + geo.FIELD_PX - t
  return {
    { x = (geo.FIELD_X + 4 * t) * sub, y = base_y * sub, facing = "up" },
    { x = (geo.FIELD_X + 8 * t) * sub, y = base_y * sub, facing = "up" },
  }
end

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Pure: advances the markers by one tick for the given InputFrame.
function M.step_markers(markers, frame)
  local sub = geo.SUB
  local min_x, min_y = geo.FIELD_X * sub, geo.FIELD_Y * sub
  local max_x = (geo.FIELD_X + geo.FIELD_PX - geo.TILE) * sub
  local max_y = (geo.FIELD_Y + geo.FIELD_PX - geo.TILE) * sub
  for i, m in ipairs(markers) do
    local input = frame[i]
    local d = input and input.dir and DELTA[input.dir]
    if d then
      m.facing = input.dir
      m.x = math.min(max_x, math.max(min_x, m.x + d[1] * M.SPEED))
      m.y = math.min(max_y, math.max(min_y, m.y + d[2] * M.SPEED))
    end
  end
end

function M.new(ctx)
  local state = { markers = nil }

  function state:enter()
    self.markers = M.initial_markers()
  end

  function state:tick(frame)
    if frame[1].pause_pressed then
      ctx.quit()
      return
    end
    M.step_markers(self.markers, frame)
  end

  function state:draw()
    require("src.render.test_pattern").draw(self.markers)
  end

  return state
end

return M
