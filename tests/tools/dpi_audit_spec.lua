local dpi_audit = require("tools.lib.dpi_audit")
local fs = require("tools.lib.fs")

describe("dpi audit (explicit pixel density for graphics resources)", function()
  it("current src/ states the pixel density of every canvas and font", function()
    local checked = 0
    for _, path in ipairs(fs.list_files("src", "%.lua$")) do
      checked = checked + 1
      assert.are.same({}, dpi_audit.check_source(path, fs.read(path)))
    end
    assert.is_true(checked > 0)
  end)

  it("pins the three internal resources and the native overlay font", function()
    local screen = fs.read("src/render/screen.lua")
    assert.is_truthy(screen:find("newCanvas(self.w, self.h, { dpiscale = 1 })", 1, true))
    assert.is_truthy(screen:find("newCanvas(self.w * k, self.h * k, { dpiscale = 1 })", 1, true))
    assert.is_truthy(fs.read("src/render/test_pattern.lua"):find('newFont(10, "mono", 1)', 1, true))
    assert.is_truthy(fs.read("src/render/debug_overlay.lua"):find(dpi_audit.NATIVE_MARKER, 1, true))
  end)

  it("flags canvases and fonts that rely on the display-DPI default", function()
    local src = table.concat({
      "local c = love.graphics.newCanvas(640, 360)",
      "local d = love.graphics.newCanvas(640, 360, { msaa = 0 })",
      'local f = love.graphics.newFont(10, "mono")',
      "local g = love.graphics.newFont(10)",
      "love.graphics.setNewFont(12)",
    }, "\n")
    assert.are.equal(5, #dpi_audit.check_source("x.lua", src))
  end)

  it("flags explicit values other than 1 unless marked native", function()
    local src = table.concat({
      "local c = love.graphics.newCanvas(640, 360, { dpiscale = 2 })",
      "local d = love.graphics.newCanvas(640, 360, { dpiscale = 1.5 })",
      'local f = love.graphics.newFont(10, "mono", love.graphics.getDPIScale())',
      "local w = love.graphics.newCanvas(640, 1)",
    }, "\n")
    assert.are.equal(4, #dpi_audit.check_source("x.lua", src))
  end)

  it("accepts explicit density 1 and marked screen-space resources", function()
    local src = table.concat({
      "local c = love.graphics.newCanvas(640, 360, { dpiscale = 1 })",
      "local d = love.graphics.newCanvas(w, h, { format = 'rgba8', dpiscale = 1 })",
      'local f = love.graphics.newFont(10, "mono", 1)',
      'local g = love.graphics.newFont("a.ttf", 8, "mono", 1)',
      "local o = love.graphics.newFont(14, 'mono', lg.getDPIScale()) -- dpi: native (overlay)",
      "-- love.graphics.newCanvas(1, 1) in a comment is ignored",
      "local id = canvas:newImageData()",
    }, "\n")
    assert.are.same({}, dpi_audit.check_source("x.lua", src))
  end)
end)
