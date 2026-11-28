-- Level-file access for tests and tools (the simulation never reads files;
-- src/sim/level.lua parses the text it is given).

local fs = require("tools.lib.fs")

local M = {}

M.ARENA_DIR = "levels/arenas/"

-- Reader for level-format arenas: name -> text (or nil, error).
function M.read_arena(name)
  assert(type(name) == "string" and name:match("^[%w_]+$"), "levels: invalid arena name")
  return fs.read(M.ARENA_DIR .. name .. ".lua")
end

-- Profile of a file under levels/: levels/NN.lua is a campaign level,
-- levels/arenas/<name>.lua an arena; anything else is not a level file.
function M.profile_of(path)
  if path:match("^levels/%d%d%.lua$") then
    return "campaign", tonumber(path:match("^levels/(%d%d)%.lua$"))
  elseif path:match("^levels/arenas/[%w_]+%.lua$") then
    return "arena", path:match("^levels/arenas/([%w_]+)%.lua$")
  end
  return nil
end

return M
