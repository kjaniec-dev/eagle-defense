-- CLI: luajit tools/check_boundaries.lua
-- Fails (exit 1) when a pure module (src/core, src/sim) violates the
-- architecture boundary.

package.path = "./?.lua;" .. package.path
local boundaries = require("tools.lib.boundaries")
local fs = require("tools.lib.fs")

local problems, checked = {}, 0
for _, dir in ipairs(boundaries.PURE_DIRS) do
  for _, path in ipairs(fs.list_files(dir, "%.lua$")) do
    checked = checked + 1
    for _, p in ipairs(boundaries.check_source(path, assert(fs.read(path)))) do
      problems[#problems + 1] = p
    end
  end
end

if #problems > 0 then
  for _, p in ipairs(problems) do
    io.stderr:write(p, "\n")
  end
  io.stderr:write(("boundaries: %d violation(s)\n"):format(#problems))
  os.exit(1)
end
print(("boundaries: OK (%d pure files checked)"):format(checked))
