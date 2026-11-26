-- Explicit game-state machine.
--
-- States are tables with optional enter(params), exit(), tick(frame),
-- update(dt) and draw() functions. Only whitelisted transitions are allowed.
-- Transition requests are deferred and applied at the next `flush()`, so a
-- state never switches while one of its own callbacks is running.

local M = {}

local Machine = {}
Machine.__index = Machine

-- spec = {
--   states = { name = state_table, ... },
--   transitions = { from_name = { to_name = true, ... }, ... },
-- }
function M.new(spec)
  assert(type(spec) == "table" and type(spec.states) == "table", "states required")
  local self = setmetatable({}, Machine)
  self.states = spec.states
  self.transitions = spec.transitions or {}
  self.current = nil
  self.current_name = nil
  self.pending = nil
  return self
end

local function call(state, method, ...)
  local fn = state and state[method]
  if fn then
    return fn(state, ...)
  end
end

-- Enter the initial state immediately. This may be called only once.
function Machine:start(name, params)
  assert(self.current == nil, "state machine already started")
  local state = self.states[name]
  assert(state, "unknown state: " .. tostring(name))
  self.current, self.current_name = state, name
  call(state, "enter", params)
end

function Machine:can_transition(to)
  local allowed = self.transitions[self.current_name]
  return allowed ~= nil and allowed[to] == true
end

-- Request a transition; it is validated now and applied on flush().
function Machine:request(to, params)
  assert(self.states[to], "unknown state: " .. tostring(to))
  if not self:can_transition(to) then
    error(("illegal transition %s -> %s"):format(tostring(self.current_name), to), 2)
  end
  self.pending = { name = to, params = params }
end

-- Apply a pending transition, if any. Returns true when a switch happened.
function Machine:flush()
  local p = self.pending
  if not p then
    return false
  end
  self.pending = nil
  call(self.current, "exit")
  self.current, self.current_name = self.states[p.name], p.name
  call(self.current, "enter", p.params)
  return true
end

-- Forward a callback to the current state.
function Machine:dispatch(method, ...)
  return call(self.current, method, ...)
end

return M
