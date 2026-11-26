-- tools/lib/hidpi_labels.sh: maps in-app smoke problem codes to the
-- regression labels used by tools/hidpi_sim.sh. It runs under the system
-- bash, so on macOS this spec exercises /bin/bash 3.2.
--
-- Regression (PR #2 native macOS run): the classifier used
-- `grep -v -E '^(...|)$' || true`. BSD grep rejects the empty alternative
-- ("grep: empty (sub)expression", exit 2), `|| true` swallowed the error and
-- the other-check label was never produced on macOS.

local fs = require("tools.lib.fs")

local LIB = "tools/lib/hidpi_labels.sh"

local function q(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Returns the labels printed for `problems`, the exit code and stderr.
local function labels(problems)
  local err = os.tmpname()
  local cmd = ('bash -c %s 2>%s; echo "__exit=$?"'):format(
    q("set -euo pipefail; . " .. LIB .. "; labels_for_problems " .. q(problems)),
    err
  )
  local p = assert(io.popen(cmd))
  local out = p:read("*a")
  p:close()
  local stderr = fs.read(err) or ""
  os.remove(err)
  local code = tonumber(out:match("__exit=(%d+)\n?$"))
  local list = {}
  for l in out:gsub("__exit=%d+\n?$", ""):gmatch("[^\n]+") do
    list[#list + 1] = l
  end
  return list, code, stderr
end

describe("tools/lib/hidpi_labels.sh", function()
  it("reports no label for a passing run", function()
    for _, problems in ipairs({ "none", "" }) do
      local list, code, stderr = labels(problems)
      assert.are.same({}, list, problems)
      assert.are.equal(0, code)
      assert.are.equal("", stderr)
    end
  end)

  it("maps each known code to its own regression label", function()
    assert.are.same({ "game-canvas-dpi" }, (labels("canvas_dpi:2.00")))
    assert.are.same({ "game-canvas-dpi" }, (labels("canvas_pixels:1280x720")))
    assert.are.same({ "prescale-canvas-dpi" }, (labels("prescale_dpi:2.00")))
    assert.are.same({ "prescale-canvas-dpi" }, (labels("prescale_pixels:3840x2160")))
    assert.are.same({ "fit-filtering" }, (labels("blended:0")))
  end)

  it("regression: an unrecognised code yields other-check, with no tool error", function()
    local list, code, stderr = labels("mismatches:12")
    assert.are.same({ "other-check" }, list)
    assert.are.equal(0, code)
    assert.are.equal("", stderr) -- the BSD failure printed "empty (sub)expression" here
  end)

  it("keeps other-check next to known labels in a mixed list", function()
    assert.are.same(
      { "game-canvas-dpi", "fit-filtering", "other-check" },
      (labels("canvas_dpi:2.00;blended:0;letterbox_bad:4"))
    )
    assert.are.same({ "game-canvas-dpi" }, (labels("canvas_dpi:2.00;canvas_pixels:1280x720")))
    assert.are.same({ "other-check" }, (labels(";;viewport:outside;")))
  end)

  it("hidpi_sim.sh uses the library, and no tool script has an empty regex alternative", function()
    local hidpi = fs.read("tools/hidpi_sim.sh")
    assert.is_truthy(hidpi:find('. "$ROOT/tools/lib/hidpi_labels.sh"', 1, true))
    assert.is_falsy(hidpi:find("labels_for_problems() {", 1, true))
    local scripts = fs.list_files("tools", "%.sh$")
    assert.is_true(#scripts >= 6)
    for _, path in ipairs(scripts) do
      local src = fs.read(path)
      for line in src:gmatch("[^\n]+") do
        if line:find("grep") and not line:match("^%s*#") then
          -- "(|", "||" inside a quoted pattern, or "|)": empty alternatives
          -- that BSD regcomp rejects with REG_EMPTY.
          for pattern in line:gmatch("'([^']*)'") do
            local empty = pattern:find("(|", 1, true)
              or pattern:find("|)", 1, true)
              or pattern:find("||", 1, true)
            assert.is_falsy(empty, path .. ": empty alternative in grep pattern " .. pattern)
          end
        end
      end
    end
  end)
end)
