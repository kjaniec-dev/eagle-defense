-- CLI for the evidence fail-closed rules (see tools/lib/evidence.lua).
--   luajit tools/evidence_gate.lua pre              -- source tree must be clean
--   luajit tools/evidence_gate.lua post DIR SHA     -- assembled package must be complete

package.path = "./?.lua;" .. package.path
local evidence = require("tools.lib.evidence")
local fs = require("tools.lib.fs")

local function fail(problems, what)
  for _, p in ipairs(problems) do
    io.stderr:write("evidence: ", p, "\n")
  end
  io.stderr:write(("evidence: %s check FAILED (%d problem(s))\n"):format(what, #problems))
  os.exit(1)
end

local cmd = arg[1]
if cmd == "pre" then
  local p = assert(io.popen("git status --porcelain=v1 --untracked-files=all --ignored"))
  local out = p:read("*a")
  local ok = p:close()
  if not ok then
    fail({ "git status failed" }, "pre")
  end
  local problems = evidence.tree_problems(out)
  if #problems > 0 then
    fail(problems, "clean-tree")
  end
  print("evidence: source tree clean")
elseif cmd == "post" then
  local dir, sha = arg[2], arg[3]
  assert(dir and sha, "usage: evidence_gate.lua post DIR SHA")
  local files = {}
  for _, path in ipairs(fs.list_files(dir)) do
    local rel = path:sub(#dir + 2)
    local f = assert(io.open(path, "rb"))
    files[rel] = f:seek("end")
    f:close()
  end
  local logs = {}
  for rel in pairs(files) do
    if rel:match("^screenshots/.*%.log$") or rel:match("^hidpi%-sim/.*%.log$") then
      logs[rel] = fs.read(dir .. "/" .. rel)
    end
  end
  local problems = evidence.package_problems(files, {
    summary = fs.read(dir .. "/checks/SUMMARY.txt"),
    love_commit = fs.read(dir .. "/build/eagle-defense.love.commit"),
    smoke_logs = logs,
  }, sha)
  if #problems > 0 then
    fail(problems, "package")
  end
  print("evidence: package complete")
else
  io.stderr:write("usage: evidence_gate.lua pre | post DIR SHA\n")
  os.exit(2)
end
