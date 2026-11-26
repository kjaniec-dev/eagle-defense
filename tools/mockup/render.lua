-- Renders every deliverable into an output directory:
--   A-native.png, B-native.png, A-1920x1080.png (3x), B-1920x1080-integer.png
--   (2x, letterboxed), B-1920x1080-fit.png (2.5x sharp bilinear),
--   compare-1920x1080.png and palette.gpl.
local canvas = require("lib.canvas")
local compare = require("compare")
local palette = require("lib.palette")
local scene = require("scene")

local M = {}

M.SPECS = {
  A = { T = 24, W = 640, H = 360, fx = 164, fy = 24 },
  B = { T = 32, W = 768, H = 432, fx = 176, fy = 8 },
}

local function write_file(path, bytes)
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
end

function M.concept(name)
  local spec = M.SPECS[name]
  spec.tanks = require(spec.T == 24 and "art.tanks24" or "art.tanks32")
  spec.hud = require("art.hud").draw
  spec.materials = scene.materials
  return scene.render(spec), spec
end

function M.all(outdir)
  local pal = palette.rgb
  local a, aspec = M.concept("A")
  local b, bspec = M.concept("B")

  local a_native = canvas.to_rgb(a, pal, 1)
  local b_native = canvas.to_rgb(b, pal, 1)
  local a3 = canvas.to_rgb(a, pal, 3)
  local b2 = canvas.rgb_new(1920, 1080, 0, 0, 0)
  canvas.rgb_blit_nearest(b2, b, pal, 2, (1920 - 768 * 2) / 2, (1080 - 432 * 2) / 2)
  local bfit = canvas.rgb_sharp_bilinear(b, pal, 3, 1920, 1080)

  write_file(outdir .. "/A-native.png", canvas.rgb_to_png(a_native))
  write_file(outdir .. "/B-native.png", canvas.rgb_to_png(b_native))
  write_file(outdir .. "/A-1920x1080.png", canvas.rgb_to_png(a3))
  write_file(outdir .. "/B-1920x1080-integer.png", canvas.rgb_to_png(b2))
  write_file(outdir .. "/B-1920x1080-fit.png", canvas.rgb_to_png(bfit))
  local cmp = compare.build({
    a3 = a3,
    bfit = bfit,
    b2 = b2,
    aspec = aspec,
    bspec = bspec,
  })
  write_file(outdir .. "/compare-1920x1080.png", canvas.rgb_to_png(cmp))
  write_file(outdir .. "/palette.gpl", palette.gpl())
end

return M
