function love.conf(t)
  t.identity = "eagle-defense"
  t.version = "11.5"
  t.console = false

  t.window.title = "Eagle Defense"
  t.window.width = 1280
  t.window.height = 720
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.resizable = true
  t.window.highdpi = true
  t.window.vsync = 1

  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
end
