-- Append-only event queue.
--
-- The simulation pushes plain-data events, such as
-- { type = "hit_brick", x = 10, y = 4 }. Presentation (VFX, audio) drains
-- them once per frame. Events never carry callbacks or references to live
-- objects.

local M = {}

local Queue = {}
Queue.__index = Queue

function M.new()
  return setmetatable({ items = {}, count = 0 }, Queue)
end

function Queue:push(event)
  assert(type(event) == "table" and type(event.type) == "string", "event needs a string type")
  self.count = self.count + 1
  self.items[self.count] = event
end

-- Returns the pending events in push order and empties the queue.
function Queue:drain()
  local items = self.items
  self.items = {}
  self.count = 0
  return items
end

function Queue:size()
  return self.count
end

return M
