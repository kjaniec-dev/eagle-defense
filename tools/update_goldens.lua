-- CLI: luajit tools/update_goldens.lua [--check] [FIXTURE ...]
--
-- The only way to (re)generate golden replay checkpoints
-- (TECHNICAL_DESIGN §10). For every fixture (default: all of
-- tests/fixtures/replays/*.lua) it runs the recorded InputFrames with the
-- active tuning from config/tuning.lua, then rewrites tuning_id,
-- tuning_version and checkpoints in canonical form. Every regeneration must
-- be called out in the PR.
--
--   --check  only verify; exit 1 when a fixture is out of date
--
-- Replays recorded with a debug-tuned (F5 overlay) tuning are refused:
-- they do not represent committed tuning.
--
-- Arena identity (G2 clarification C3): this tool never writes arena_id. A
-- fixture of a level-format arena without arena_id, or with an arena_id
-- that does not match the arena file, is refused, so a regeneration cannot
-- silently absorb an arena change; re-author the inputs with the generator
-- (tools/gen_g2_replay_inputs.lua) and call it out in the PR.

package.path = "./?.lua;" .. package.path
local fs = require("tools.lib.fs")
local serialize = require("src.core.serialize")
local tuning = require("src.sim.tuning")
local replay = require("src.sim.replay")
local levels = require("tools.lib.levels")

local DIR = "tests/fixtures/replays"

local M = {}

-- Regenerates one replay table in memory. Returns the updated table, or nil
-- and an error message. opts.resolve_arena defaults to levels/arenas/.
function M.regenerate(r, active, opts)
  opts = opts or {}
  local ok, err = replay.check(r)
  if not ok then
    return nil, err
  end
  if r.debug_tuned then
    return nil,
      ("replay %s is debug_tuned (F5 overlay); refusing to make it a golden"):format(r.name)
  end
  local copy = serialize.decode(serialize.encode(r))
  copy.tuning_id, copy.tuning_version = active.id, active.version
  local result, run_err = replay.run(copy, active, {
    resolve_arena = opts.resolve_arena or levels.read_arena,
  })
  if not result then
    return nil, run_err
  end
  copy.checkpoints = result.checkpoints
  return copy
end

local function main(argv)
  local check_only = false
  local files = {}
  for _, a in ipairs(argv) do
    if a == "--check" then
      check_only = true
    else
      files[#files + 1] = a
    end
  end
  if #files == 0 then
    files = fs.list_files(DIR, "%.lua$")
  end
  local active = tuning.load()
  local failed = 0
  for _, path in ipairs(files) do
    local text = assert(fs.read(path), "cannot read " .. path)
    local r, err = serialize.decode(text)
    local updated
    if r then
      updated, err = M.regenerate(r, active)
    end
    if not updated then
      io.stderr:write(path, ": ", tostring(err), "\n")
      failed = failed + 1
    else
      local out = serialize.encode(updated)
      if out == text then
        print(("goldens: %s up to date (%d checkpoints)"):format(path, #updated.checkpoints))
      elseif check_only then
        io.stderr:write(path, ": out of date; run luajit tools/update_goldens.lua\n")
        failed = failed + 1
      else
        local f = assert(io.open(path, "wb"))
        f:write(out)
        f:close()
        print(("goldens: %s REGENERATED (%d checkpoints)"):format(path, #updated.checkpoints))
      end
    end
  end
  if failed > 0 then
    os.exit(1)
  end
end

if arg and arg[0] and arg[0]:match("update_goldens%.lua$") then
  main(arg)
end

return M
