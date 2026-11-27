-- F5 debug tuning editor (G1 plan §7). Pure: it edits an in-memory copy of
-- the tuning values and never writes config/tuning.lua or any fixture.
-- While the copy differs from the committed tuning, the HUD shows
-- TUNING MODIFIED and recordings are tagged debug_tuned = true. Signed-off
-- values go into config/tuning.lua by a normal commit.

local tuning = require("src.sim.tuning")

local M = {}

-- Editable entries: key, step and inclusive range.
M.ITEMS = {
  { key = "player_speed", step = 1, min = 1, max = 32 },
  { key = "bullet_speed_normal", step = 1, min = 1, max = 256 },
  { key = "bullet_speed_fast", step = 1, min = 1, max = 256 },
  { key = "bullet_size", step = 2, min = 8, max = 64 },
  { key = "arena_player_level", step = 1, min = 0, max = 3 },
  { key = "fast_bullet_level", step = 1, min = 0, max = 3 },
  { key = "turret_period", step = 10, min = 10, max = 600 },
  { key = "turret_bullet_speed", step = 1, min = 1, max = 256 },
}

local Edit = {}
Edit.__index = Edit

-- base = { values, version, id } (the committed tuning).
function M.new(base)
  return setmetatable({
    base = base,
    values = tuning.copy(base.values),
    selected = 1,
    open = false,
  }, Edit)
end

function Edit:toggle()
  self.open = not self.open
end

function Edit:select(delta)
  local n = #M.ITEMS
  self.selected = (self.selected - 1 + delta) % n + 1
end

-- Adjusts the selected value by delta steps, clamped to its range.
-- Returns true when the value changed.
function Edit:adjust(delta)
  local item = M.ITEMS[self.selected]
  local old = self.values[item.key]
  local v = old + delta * item.step
  if v < item.min then
    v = item.min
  elseif v > item.max then
    v = item.max
  end
  self.values[item.key] = v
  assert(tuning.check_values(self.values))
  return v ~= old
end

-- Back to the committed values. Returns true when anything changed.
function Edit:reset()
  local changed = self:modified()
  self.values = tuning.copy(self.base.values)
  return changed
end

function Edit:id()
  return tuning.id(self.values, self.base.version)
end

function Edit:modified()
  return self:id() ~= self.base.id
end

-- The tuning the arena should run with: { values, version, id }.
function Edit:active()
  return { values = self.values, version = self.base.version, id = self:id() }
end

-- Display rows: { label, value text, selected, changed }.
function Edit:rows()
  local rows = {}
  for i, item in ipairs(M.ITEMS) do
    local v = self.values[item.key]
    rows[i] = {
      label = item.key,
      value = tostring(v),
      selected = i == self.selected,
      changed = v ~= self.base.values[item.key],
    }
  end
  return rows
end

return M
