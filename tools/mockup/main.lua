-- Entry point. `love tools/mockup <outdir>` renders every deliverable;
-- `love tools/mockup --sheet <file.png>` renders a zoomed sprite review sheet.
local canvas = require("lib.canvas")
local palette = require("lib.palette")
local sprite = require("lib.sprite")

local function write_file(path, bytes)
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
end

local function materials(kind)
  local r = palette.ramps
  if kind == "p1" then
    return { body = r.gold, metal = r.metal, accent = r.lampwarm }
  elseif kind == "p2" then
    return { body = r.teal, metal = r.metal, accent = r.lampwarm }
  end
  return { body = r.steel, metal = r.metal, accent = r.lampcool, armor = r.armor }
end

local function sheet(path, size)
  local T = tonumber(size) or 24
  local tk = require(T == 24 and "art.tanks24" or "art.tanks32")
  local entries = {
    { tk.player, "p1" },
    { tk.player, "p2" },
    { tk.scout, "enemy" },
    { tk.power, "enemy" },
    { tk.armor, "enemy" },
  }
  local cell = T + 4
  local c = canvas.new(cell * 4 + 4, cell * #entries + 4, palette.idx("asph2"))
  for i, e in ipairs(entries) do
    for j, dir in ipairs({ "up", "right", "down", "left" }) do
      local s = sprite.compile(e[1], materials(e[2]), dir)
      canvas.blit(c, s, 4 + (j - 1) * cell, 4 + (i - 1) * cell)
    end
  end
  write_file(path, canvas.rgb_to_png(canvas.to_rgb(c, palette.rgb, T == 24 and 8 or 6)))
end

function love.run()
  local args = love.arg.parseGameArguments(arg)
  local ok, err = pcall(function()
    if args[1] == "--sheet" then
      sheet(assert(args[2], "usage: --sheet <file.png> [24|32]"), args[3])
    else
      local render = require("render")
      render.all(assert(args[1], "usage: love tools/mockup <outdir>"))
    end
  end)
  if not ok then
    io.stderr:write("mockup: ", tostring(err), "\n")
    return function()
      return 1
    end
  end
  return function()
    return 0
  end
end
