-- G1 visual direction spike: CPU-only, headless mockup renderer.
-- Run from the repo root: love tools/mockup docs/art/mockups
-- No window, no graphics module: every pixel is written into ImageData on the
-- CPU, so the output PNGs are byte-deterministic and need no GPU or Xvfb.
function love.conf(t)
  t.identity = "eagle-defense-mockup"
  t.version = "11.5"
  t.console = false
  t.window = false
  t.modules.window = false
  t.modules.graphics = false
  t.modules.audio = false
  t.modules.sound = false
  t.modules.joystick = false
  t.modules.keyboard = false
  t.modules.mouse = false
  t.modules.touch = false
  t.modules.physics = false
  t.modules.video = false
  t.modules.event = false
  t.modules.timer = false
  t.modules.system = false
end
