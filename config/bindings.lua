-- Default input bindings (see docs/GAME_DESIGN.md §7).
-- Key names follow love.keyboard KeyConstants; gamepad names follow
-- love.joystick GamepadButton.

return {
  keyboard = {
    [1] = {
      up = { "w" },
      down = { "s" },
      left = { "a" },
      right = { "d" },
      fire = { "space" },
      pause = { "escape", "p" },
    },
    [2] = {
      up = { "up" },
      down = { "down" },
      left = { "left" },
      right = { "right" },
      fire = { "rctrl", "kpenter" },
      pause = {},
    },
  },
  gamepad = {
    up = { "dpup" },
    down = { "dpdown" },
    left = { "dpleft" },
    right = { "dpright" },
    fire = { "a", "b" },
    pause = { "start" },
  },
  -- Left stick to 4-way conversion.
  stick = {
    deadzone = 0.35, -- a stick direction engages above this magnitude
    release = 0.25, -- an engaged direction stays held until it drops below this
    switch_margin = 0.10, -- the other axis must exceed the held axis by this much
  },
}
