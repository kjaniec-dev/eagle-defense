-- F3 debug overlay, drawn in window space after upscaling.
-- It shows frame pacing, simulation and draw statistics.

local M = {}

local font

function M.draw(info)
  local lg = love.graphics
  if not font then
    font = lg.newFont(14, "mono")
  end
  local lines = {
    ("FPS %d   frame %.2f ms"):format(info.fps, info.frame_ms),
    ("tick %d   ticks/frame %d   sim %.3f ms"):format(info.tick, info.ticks_last, info.sim_ms),
    ("draw calls %d   texture mem %.1f MB"):format(info.draw_calls, info.texture_mb),
    ("window %dx%d px  dpi %.1f  scale %s %.2f"):format(
      info.win_w,
      info.win_h,
      info.dpi,
      info.mode,
      info.scale
    ),
    ("P1 %s%s   P2 %s%s"):format(
      info.p1.dir or "-",
      info.p1.fire and "+F" or "",
      info.p2.dir or "-",
      info.p2.fire and "+F" or ""
    ),
  }
  lg.setFont(font)
  local h = #lines * 18 + 8
  lg.setColor(0, 0, 0, 0.7)
  lg.rectangle("fill", 4, 4, 460, h)
  lg.setColor(0.6, 1, 0.6, 1)
  for i, line in ipairs(lines) do
    lg.print(line, 10, 8 + (i - 1) * 18)
  end
  lg.setColor(1, 1, 1, 1)
end

return M
