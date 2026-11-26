local boundaries = require("tools.lib.boundaries")
local fs = require("tools.lib.fs")

describe("architecture boundaries", function()
  it("current src/core and src/sim are pure", function()
    local checked = 0
    for _, dir in ipairs(boundaries.PURE_DIRS) do
      for _, path in ipairs(fs.list_files(dir, "%.lua$")) do
        checked = checked + 1
        assert.are.same({}, boundaries.check_source(path, fs.read(path)))
      end
    end
    assert.is_true(checked > 0)
  end)

  it("detects love references", function()
    local p = boundaries.check_source("x.lua", "local t = love.timer.getTime()")
    assert.are.equal(1, #p)
  end)

  it("detects forbidden requires", function()
    local p = boundaries.check_source("x.lua", 'local r = require("src.render.screen")')
    assert.are.equal(1, #p)
    p = boundaries.check_source("x.lua", "local a = require 'src.app.app'")
    assert.are.equal(1, #p)
  end)

  it("ignores comments and strings", function()
    local src = '-- love is fine here\nlocal s = "love"\n--[[ love ]]\nlocal glove = 1\n'
    assert.are.same({}, boundaries.check_source("x.lua", src))
  end)
end)
