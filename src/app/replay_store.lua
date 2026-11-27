-- Saves replay recordings (F8) into the save directory without ever
-- overwriting an earlier file, including files from previous sessions, and
-- reports write failures instead of a path (G1 review P2-1).
--
-- `fs` is love.filesystem or a test double with the same dot-call API:
-- createDirectory(dir) -> bool, getInfo(path) -> table|nil,
-- write(path, data) -> bool[, message], getSaveDirectory() -> string.

local serialize = require("src.core.serialize")

local M = {}

M.DIR = "replays"
M.MAX_TRIES = 1000

-- First unused file name for a recording: replays/arena-<stamp>-t<tick>.lua,
-- then the same name with -2, -3, ... appended. Returns nil when every
-- candidate up to MAX_TRIES already exists.
function M.free_name(fs, stamp, tick)
  local base = ("%s/arena-%s-t%d"):format(M.DIR, stamp, tick)
  for n = 1, M.MAX_TRIES do
    local name = n == 1 and base .. ".lua" or ("%s-%d.lua"):format(base, n)
    if not fs.getInfo(name) then
      return name
    end
  end
  return nil
end

-- Writes `rec` and returns the full path, or nil and an error message.
-- `stamp` is a wall-clock label for the file name (app layer only).
function M.save(fs, rec, stamp)
  local ok_dir = fs.createDirectory(M.DIR)
  if not ok_dir then
    return nil, "cannot create the " .. M.DIR .. " directory"
  end
  local last = rec.checkpoints[#rec.checkpoints]
  local name = M.free_name(fs, stamp, last and last[1] or 0)
  if not name then
    return nil, "no free file name for this recording"
  end
  local ok_write, msg = fs.write(name, serialize.encode(rec))
  if not ok_write then
    return nil, ("cannot write %s: %s"):format(name, tostring(msg))
  end
  return fs.getSaveDirectory() .. "/" .. name
end

return M
