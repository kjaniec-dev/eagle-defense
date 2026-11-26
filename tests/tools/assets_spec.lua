local assets = require("tools.lib.assets")

local function entry(extra)
  local e =
    { author = "Team", license = "Proprietary", source = "original", tool = "build_sprites" }
  for k, v in pairs(extra or {}) do
    e[k] = v
  end
  return e
end

describe("asset manifest check", function()
  it("passes when every file has a complete entry", function()
    local files = { "assets/manifest.lua", "assets/sprites/tank.png" }
    local manifest = { files = { ["assets/sprites/tank.png"] = entry() } }
    assert.are.same({}, assets.check(files, manifest))
  end)

  it("flags unlisted files", function()
    local p = assets.check({ "assets/a.png" }, { files = {} })
    assert.are.equal(1, #p)
    assert.matches("missing manifest entry", p[1])
  end)

  it("flags entries without files", function()
    local p = assets.check({}, { files = { ["assets/gone.png"] = entry() } })
    assert.matches("has no file", p[1])
  end)

  it("flags incomplete entries", function()
    local p = assets.check({ "assets/a.png" }, { files = { ["assets/a.png"] = { author = "x" } } })
    assert.are.equal(3, #p)
  end)

  it("requires the placeholder flag to match the filename", function()
    local p = assets.check(
      { "assets/tank_PLACEHOLDER.png" },
      { files = { ["assets/tank_PLACEHOLDER.png"] = entry() } }
    )
    assert.matches("placeholder", p[1])
    p = assets.check(
      { "assets/tank_PLACEHOLDER.png" },
      { files = { ["assets/tank_PLACEHOLDER.png"] = entry({ placeholder = true }) } }
    )
    assert.are.same({}, p)
  end)
end)
