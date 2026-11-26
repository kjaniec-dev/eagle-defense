-- CLI: luajit tools/check_assets.lua
-- Verifies assets/manifest.lua covers every file under assets/.

package.path = "./?.lua;" .. package.path
local assets = require("tools.lib.assets")
local fs = require("tools.lib.fs")
local serialize = require("src.core.serialize")

local text = assert(fs.read("assets/manifest.lua"), "assets/manifest.lua missing")
local manifest, err = serialize.decode(text)
if not manifest then
  io.stderr:write("assets: cannot parse manifest: ", tostring(err), "\n")
  os.exit(1)
end

local files = fs.list_files("assets")
local problems = assets.check(files, manifest)
if #problems > 0 then
  for _, p in ipairs(problems) do
    io.stderr:write(p, "\n")
  end
  io.stderr:write(("assets: %d problem(s)\n"):format(#problems))
  os.exit(1)
end
print(("assets: OK (%d files, manifest consistent)"):format(#files))
