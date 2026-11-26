-- CLI: luajit tools/check_dpi.lua
-- Fails (exit 1) when a graphics resource in src/ relies on LÖVE's implicit
-- display-DPI default (see tools/lib/dpi_audit.lua).

package.path = "./?.lua;" .. package.path
local dpi_audit = require("tools.lib.dpi_audit")
local fs = require("tools.lib.fs")

local problems, checked = {}, 0
for _, path in ipairs(fs.list_files("src", "%.lua$")) do
  checked = checked + 1
  for _, p in ipairs(dpi_audit.check_source(path, assert(fs.read(path)))) do
    problems[#problems + 1] = p
  end
end

if #problems > 0 then
  for _, p in ipairs(problems) do
    io.stderr:write(p, "\n")
  end
  io.stderr:write(("dpi: %d implicit-DPI resource(s)\n"):format(#problems))
  os.exit(1)
end
print(("dpi: OK (%d files in src/ checked)"):format(checked))
