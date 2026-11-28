-- CLI: luajit tools/validate_levels.lua [--profile=campaign|arena FILE ...]
--
-- Validates level files with the non-executing loader (src/sim/level.lua,
-- G2 plan §11). Without arguments it checks every file under levels/ by
-- its location: levels/NN.lua with the campaign profile (and id = NN),
-- levels/arenas/<name>.lua with the arena profile (and name = <name>). Any
-- other file under levels/ is an error. Exits 1 on any problem.

package.path = "./?.lua;" .. package.path
local fs = require("tools.lib.fs")
local levels = require("tools.lib.levels")
local level = require("src.sim.level")

local M = {}

-- Returns a list of problems for one file (empty when valid).
function M.check_file(path, profile, expect)
  local text, err = fs.read(path)
  if not text then
    return { path .. ": cannot read: " .. tostring(err) }
  end
  local built, problems = level.parse(text, profile)
  local out = {}
  if not built then
    for _, p in ipairs(problems) do
      out[#out + 1] = path .. ": " .. p
    end
    return out
  end
  if profile == "campaign" and expect and built.meta.id ~= expect then
    out[#out + 1] = ("%s: id %s does not match the file name (%02d)"):format(
      path,
      tostring(built.meta.id),
      expect
    )
  elseif profile == "arena" and expect and built.name ~= expect then
    out[#out + 1] = ("%s: name %s does not match the file name (%s)"):format(
      path,
      built.name,
      expect
    )
  end
  return out
end

-- Checks every file under levels/. Returns problems and the file count.
function M.check_tree()
  local problems, files = {}, fs.list_files("levels")
  for _, path in ipairs(files) do
    local profile, expect = levels.profile_of(path)
    if not profile then
      problems[#problems + 1] = path
        .. ": not a level file location (levels/NN.lua or levels/arenas/<name>.lua)"
    else
      for _, p in ipairs(M.check_file(path, profile, expect)) do
        problems[#problems + 1] = p
      end
    end
  end
  return problems, #files
end

local function main(argv)
  local problems, n
  local profile = nil
  local files = {}
  for _, a in ipairs(argv) do
    local p = a:match("^%-%-profile=(%w+)$")
    if p then
      profile = p
    else
      files[#files + 1] = a
    end
  end
  if #files > 0 then
    if not level.PROFILES[profile] then
      io.stderr:write("validate_levels: --profile=campaign|arena required with files\n")
      os.exit(2)
    end
    problems = {}
    for _, f in ipairs(files) do
      for _, p in ipairs(M.check_file(f, profile)) do
        problems[#problems + 1] = p
      end
    end
    n = #files
  else
    problems, n = M.check_tree()
  end
  if #problems > 0 then
    for _, p in ipairs(problems) do
      io.stderr:write(p, "\n")
    end
    io.stderr:write(("levels: %d problem(s)\n"):format(#problems))
    os.exit(1)
  end
  print(("levels: OK (%d files)"):format(n))
end

if arg and arg[0] and arg[0]:match("validate_levels%.lua$") then
  main(arg)
end

return M
