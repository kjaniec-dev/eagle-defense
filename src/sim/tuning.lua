-- Tuning tables: validation, plain value tables and the tuning id.
--
-- config/tuning.lua stores { value, provenance, note } entries. The
-- simulation reads a plain table of values ("values"), produced here.

local serialize = require("src.core.serialize")
local hash = require("src.core.hash")

local M = {}

local PROVENANCE = { UNV = true, DOC = true }

-- Schema: every key the simulation reads, with its allowed range
-- ({ min, max }), list length ({ list, min, max }) or allowed values
-- ({ one_of = { ... } }).
M.SCHEMA = {
  player_speed = { min = 1, max = 64 },
  bullet_speed_normal = { min = 1, max = 512 },
  bullet_speed_fast = { min = 1, max = 512 },
  bullet_size = { min = 8, max = 128 },
  bullet_limit = { list = 4, min = 1, max = 8 },
  fast_bullet_level = { min = 0, max = 3 },
  arena_player_level = { min = 0, max = 3 },
  turret_first_shot = { min = 1, max = 100000 },
  turret_period = { min = 1, max = 100000 },
  turret_bullet_speed = { min = 1, max = 512 },
  -- G2 terrain (G2 plan §9)
  brick_strip_cells = { one_of = { 2, 4 } },
  brick_strip_depth = { one_of = { 1, 2 } },
  steel_break_level = { min = 1, max = 3 },
  ice_slide_distance = { min = 0, max = 512 },
}

local function is_int(v)
  return type(v) == "number" and v == math.floor(v)
end

local function provenance_ok(tag)
  if type(tag) ~= "string" then
    return false
  end
  if PROVENANCE[tag] then
    return true
  end
  -- "TUNED (owner, YYYY-MM-DD)" / "MEASURED (method, source, date)"
  return tag:match("^TUNED %(.+, %d%d%d%d%-%d%d%-%d%d%)$") ~= nil
    or tag:match("^MEASURED %(.+, .+, %d%d%d%d%-%d%d%-%d%d%)$") ~= nil
end

-- Validates a values table against the schema. Returns true, or nil and a
-- list of problems.
function M.check_values(values)
  local problems = {}
  for key, rule in pairs(M.SCHEMA) do
    local v = values[key]
    if rule.list then
      if type(v) ~= "table" or #v ~= rule.list then
        problems[#problems + 1] = key .. ": expected a list of " .. rule.list .. " integers"
      else
        for i = 1, rule.list do
          if not is_int(v[i]) or v[i] < rule.min or v[i] > rule.max then
            problems[#problems + 1] = ("%s[%d]: integer in %d..%d expected"):format(
              key,
              i,
              rule.min,
              rule.max
            )
          end
        end
      end
    elseif rule.one_of then
      local ok = false
      for _, allowed in ipairs(rule.one_of) do
        ok = ok or v == allowed
      end
      if not ok then
        local names = {}
        for i, allowed in ipairs(rule.one_of) do
          names[i] = tostring(allowed)
        end
        problems[#problems + 1] = ("%s: one of %s expected, got %s"):format(
          key,
          table.concat(names, ", "),
          tostring(v)
        )
      end
    elseif not is_int(v) or v < rule.min or v > rule.max then
      problems[#problems + 1] = ("%s: integer in %d..%d expected, got %s"):format(
        key,
        rule.min,
        rule.max,
        tostring(v)
      )
    end
  end
  for key in pairs(values) do
    if not M.SCHEMA[key] then
      problems[#problems + 1] = key .. ": unknown tuning key"
    end
  end
  table.sort(problems)
  if #problems > 0 then
    return nil, problems
  end
  return true
end

-- Validates a config/tuning.lua style table and returns its plain values.
function M.from_config(cfg)
  assert(type(cfg) == "table" and is_int(cfg.version), "tuning: version required")
  assert(type(cfg.entries) == "table", "tuning: entries required")
  local values, problems = {}, {}
  for key, e in pairs(cfg.entries) do
    if type(e) ~= "table" or e[1] == nil or not provenance_ok(e[2]) or type(e[3]) ~= "string" then
      problems[#problems + 1] = key .. ": entry must be { value, provenance, note }"
    else
      values[key] = e[1]
    end
  end
  local ok, value_problems = M.check_values(values)
  if not ok then
    for _, p in ipairs(value_problems) do
      problems[#problems + 1] = p
    end
  end
  if #problems > 0 then
    table.sort(problems)
    error("tuning: " .. table.concat(problems, "; "), 0)
  end
  return values
end

-- Deep copy of a values table (the F5 debug overlay edits a copy).
function M.copy(values)
  return serialize.decode(serialize.encode(values))
end

-- Tuning identity: hash of the canonical serialization of the version and
-- the values. Equal tuning always gives the same id.
function M.id(values, version)
  assert(is_int(version), "tuning id: version required")
  return hash.string(serialize.encode({ version = version, values = values }))
end

-- The active tuning from config/tuning.lua: values, version and id.
function M.load()
  local cfg = require("config.tuning")
  local values = M.from_config(cfg)
  return { values = values, version = cfg.version, id = M.id(values, cfg.version) }
end

return M
