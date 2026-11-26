-- Application wiring: the LÖVE callbacks, the fixed-step loop, input, the
-- state machine, presentation and smoke mode.

local loop_mod = require("src.core.loop")
local statemachine = require("src.core.statemachine")
local mapper_mod = require("src.input.mapper")
local devices_mod = require("src.input.devices")
local screen_mod = require("src.render.screen")
local overlay = require("src.render.debug_overlay")
local args_mod = require("src.app.args")
local upscale_check = require("src.app.upscale_check")
local bindings = require("config.bindings")

local App = {}

function App.load(argv)
  App.opts = args_mod.parse(argv)
  if App.opts.smoke then
    io.stdout:setvbuf("no")
    -- In smoke runs an error must fail the process instead of showing the
    -- interactive error screen.
    love.errorhandler = function(msg)
      print("SMOKE FAIL " .. debug.traceback(tostring(msg), 2))
      return function()
        return 1
      end
    end
  end
  App.loop = loop_mod.new()
  App.mapper = mapper_mod.new(bindings)
  App.devices = devices_mod.new(bindings)
  App.screen = screen_mod.new()
  App.overlay_on = false
  App.last_frame = mapper_mod.empty_frame()
  App.stats = { sim_ms = 0, ticks_last = 0, frame_ms = 0 }
  App.exit_code = nil

  local ctx = {}
  ctx.quit = function()
    App.exit_code = 0
  end
  App.machine = statemachine.new({
    states = {
      boot = require("src.app.states.boot").new(ctx),
      sandbox = require("src.app.states.sandbox").new(ctx),
    },
    transitions = {
      boot = { sandbox = true },
    },
  })
  ctx.machine = App.machine
  App.machine:start("boot")

  love.graphics.setDefaultFilter("nearest", "nearest")
  if App.opts.window_w then
    local _, _, flags = love.window.getMode()
    love.window.setMode(App.opts.window_w, App.opts.window_h, flags)
  end
  if App.opts.smoke then
    print(("SMOKE start ticks=%d"):format(App.opts.smoke))
  end
end

local function on_tick(tick)
  local frame
  if App.opts.smoke then
    frame = args_mod.smoke_frame(tick)
  else
    frame = App.mapper:update(App.devices:sample())
  end
  App.last_frame = frame
  App.machine:flush()
  App.machine:dispatch("tick", frame)
end

function App.frame(dt)
  if App.opts.smoke then
    dt = App.loop.step -- one tick per frame: deterministic, independent of the clock
  end
  local t0 = love.timer.getTime()
  App.stats.ticks_last = App.loop:advance(dt, on_tick)
  App.stats.sim_ms = (love.timer.getTime() - t0) * 1000
  App.stats.frame_ms = dt * 1000
end

local function write_file(path, bytes)
  local f, err = io.open(path, "wb")
  if not f then
    return false, err
  end
  f:write(bytes)
  f:close()
  return true
end

local function smoke_report(window_image)
  local canvas_image = App.screen.canvas:newImageData()
  local png = canvas_image:encode("png"):getString()
  local out = App.opts.smoke_out
  local ok, err
  if out then
    ok, err = write_file(out, png)
  else
    ok = love.filesystem.write("smoke.png", png)
    out = love.filesystem.getSaveDirectory() .. "/smoke.png"
  end
  if not ok then
    print("SMOKE FAIL cannot write " .. tostring(out) .. ": " .. tostring(err))
    App.exit_code = 1
    return
  end

  -- Pixel-perfect check: the window backbuffer must be an exact integer
  -- upscale of the canvas.
  local vp = App.screen.vp
  local ww, wh = window_image:getDimensions()
  local res = upscale_check.verify(
    function(x, y)
      return canvas_image:getPixel(x, y)
    end,
    canvas_image:getWidth(),
    canvas_image:getHeight(),
    function(x, y)
      return window_image:getPixel(x, y)
    end,
    ww,
    wh,
    vp
  )
  if App.opts.smoke_window_out then
    write_file(App.opts.smoke_window_out, window_image:encode("png"):getString())
  end

  -- Logical (window points) vs physical (framebuffer pixels). On HiDPI
  -- displays they differ by the DPI scale. Integer scaling is defined and
  -- verified in physical pixels only.
  local lw, lh = love.graphics.getDimensions()
  local pw, ph = love.graphics.getPixelDimensions()
  local dpi = love.graphics.getDPIScale()
  local dims_ok = ww == pw and wh == ph
  local m = App.machine.current.markers or {}
  local function pos(i)
    return m[i] and ("%d,%d"):format(m[i].x, m[i].y) or "-"
  end
  local renderer = { love.graphics.getRendererInfo() }
  local passed = dims_ok and res.mismatches == 0 and res.letterbox_bad == 0 and res.checked > 0
  print(
    (
      "SMOKE %s ticks=%d state=%s p1=%s p2=%s logical=%dx%d physical=%dx%d dpi=%.2f "
      .. "screenshot=%dx%d scale=%d offset=%d,%d pixels_checked=%d mismatches=%d "
      .. "letterbox_bad=%d out=%s renderer=%s os=%s"
    ):format(
      passed and "OK" or "FAIL",
      App.loop.tick,
      App.machine.current_name,
      pos(1),
      pos(2),
      lw,
      lh,
      pw,
      ph,
      dpi,
      ww,
      wh,
      vp.scale,
      vp.x,
      vp.y,
      res.checked,
      res.mismatches,
      res.letterbox_bad,
      out,
      table.concat(renderer, " / "),
      love.system.getOS()
    )
  )
  App.exit_code = passed and 0 or 1
end

function App.draw()
  App.screen:begin()
  App.machine:dispatch("draw")
  App.screen:finish()
  local gstats = love.graphics.getStats()
  App.screen:present()

  if App.opts.smoke and not App.smoke_done and App.loop.tick >= App.opts.smoke then
    App.smoke_done = true
    -- The screenshot is taken when this frame is presented.
    love.graphics.captureScreenshot(smoke_report)
  end

  if App.overlay_on then
    local pw, ph = love.graphics.getPixelDimensions()
    overlay.draw({
      fps = love.timer.getFPS(),
      frame_ms = App.stats.frame_ms,
      tick = App.loop.tick,
      ticks_last = App.stats.ticks_last,
      sim_ms = App.stats.sim_ms,
      draw_calls = gstats.drawcalls,
      texture_mb = gstats.texturememory / (1024 * 1024),
      win_w = pw,
      win_h = ph,
      dpi = love.graphics.getDPIScale(),
      mode = App.screen.mode,
      scale = App.screen.vp and App.screen.vp.scale or 0,
      p1 = App.last_frame[1],
      p2 = App.last_frame[2],
    })
  end
end

local function toggle_fullscreen()
  love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
end

function App.keypressed(key, scancode, isrepeat)
  App.devices:keypressed(key, scancode, isrepeat)
  if key == "f3" then
    App.overlay_on = not App.overlay_on
  elseif key == "f4" then
    App.screen:cycle_mode()
  elseif key == "f11" and not isrepeat then
    toggle_fullscreen()
  elseif
    key == "return"
    and not isrepeat
    and (love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt"))
  then
    toggle_fullscreen()
  end
end

function App.keyreleased(key)
  App.devices:keyreleased(key)
end

function App.gamepadpressed(js, button)
  App.devices:gamepadpressed(js, button)
end

function App.gamepadreleased(js, button)
  App.devices:gamepadreleased(js, button)
end

function App.joystickadded(js)
  App.devices:joystick_added(js)
end

function App.joystickremoved(js)
  App.devices:joystick_removed(js)
end

-- Custom main loop: fixed-step simulation, one render per frame.
function App.run()
  -- luacheck: push ignore 143 (parseGameArguments exists in LÖVE 11 but not in the luacheck std)
  App.load(love.arg.parseGameArguments(arg))
  -- luacheck: pop
  love.timer.step()

  return function()
    love.event.pump()
    for name, a, b, c, d, e, f in love.event.poll() do
      if name == "quit" then
        return a or 0
      end
      local handler = App[name]
      if handler then
        handler(a, b, c, d, e, f)
      end
    end

    App.frame(love.timer.step())

    if love.graphics.isActive() then
      love.graphics.origin()
      App.draw()
      love.graphics.present()
    end

    if App.exit_code ~= nil then
      return App.exit_code
    end
    love.timer.sleep(0.001)
  end
end

return App
