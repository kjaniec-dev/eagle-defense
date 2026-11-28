-- Arena state (G1 arena, G2 terrain arena): runs the simulation on fixed
-- ticks with live input, records the InputFrames, feeds presentation
-- effects from sim events and hosts the F5 debug tuning editor.
--
-- Debug keys (G2 plan §12, clarification C2):
--   F2  restart (keeps the arena, the F7 level and the F5 copy)
--   F5  tuning editor ([ ] select, - = adjust, Backspace reset); every
--       change restarts the arena with the modified copy and marks
--       recordings debug_tuned
--   F6  switch arena (g2_terrain <-> g1_arena); keeps the F7 level and the
--       F5 copy, restarts
--   F7  players' upgrade level 0 -> 1 -> 2 -> 3 -> 0; restarts the current
--       arena; recorded as player_level, never debug tuning
--   F8  save the recording (arena, arena_id, player_level) to the save
--       directory
-- The players' level has exactly one control, F7: F5 does not offer it.

local sim = require("src.sim.sim")
local tuning = require("src.sim.tuning")
local replay = require("src.sim.replay")
local level = require("src.sim.level")
local arena_mod = require("src.sim.arena")
local tuning_edit = require("src.app.tuning_edit")
local args = require("src.app.args")

local M = {}

M.ARENAS = args.ARENAS
M.DEFAULT_ARENA = args.DEFAULT_ARENA
M.TITLES = { g1_arena = "G1 ARENA", g2_terrain = "G2 TERRAIN" }
M.SEED = 1
-- Ticks the F8 save result stays on the HUD.
M.SAVE_STATUS_TTL = 180

-- Presentation effects driven by sim events (never feed back into the sim).
local FX_TTL = {
  tank_hit = 12,
  bullet_cancel = 10,
  bullet_hit_solid = 6,
  tank_respawn = 30,
  shot = 4,
}

-- The next arena in the F6 cycle.
function M.next_arena(name)
  for i, a in ipairs(M.ARENAS) do
    if a == name then
      return M.ARENAS[i % #M.ARENAS + 1]
    end
  end
  return M.ARENAS[1]
end

-- Pure: turns one tick's sim events into effect records and ages the old
-- ones. Returns the new list.
function M.update_fx(fx, events)
  local out = {}
  for _, f in ipairs(fx) do
    if f.ttl > 1 then
      f.ttl = f.ttl - 1
      out[#out + 1] = f
    end
  end
  for _, e in ipairs(events) do
    local ttl = FX_TTL[e.type]
    if ttl then
      out[#out + 1] = {
        type = e.type,
        ttl = ttl,
        max = ttl,
        x = e.x,
        y = e.y,
        tank = e.tank,
        kind = e.kind,
        friendly = e.friendly,
      }
    end
  end
  return out
end

-- ctx.read_level(name) -> text reads levels/arenas/<name>.lua (the app uses
-- love.filesystem, tests tools/lib/levels); ctx.arena is the initial arena
-- (default g2_terrain).
function M.new(ctx)
  local state = {}

  function state:start()
    local active = self.edit:active()
    local built = level.load_arena(self.arena_name, ctx.read_level)
    self.world = sim.new({
      arena = built,
      tuning = active.values,
      seed = M.SEED,
      player_level = self.player_level,
    })
    self.recording = replay.new_recording({
      name = "arena",
      arena = self.arena_name,
      arena_id = arena_mod.id(built),
      player_level = self.player_level,
      seed = M.SEED,
      tuning_id = active.id,
      tuning_version = active.version,
      debug_tuned = self.edit:modified(),
    })
    self.fx = {}
    self.counts = { shots = 0, cancels = 0, destroyed = 0 }
  end

  function state:enter()
    self.edit = tuning_edit.new(tuning.load())
    self.arena_name = ctx.arena or M.DEFAULT_ARENA
    -- F7 level; starts at the committed default (C2)
    self.player_level = self.edit.base.values.arena_player_level
    self:start()
  end

  function state:tick(frame)
    if frame[1].pause_pressed then
      ctx.quit()
      return
    end
    sim.step(self.world, frame)
    replay.record(self.recording, frame, self.world)
    local events = self.world.events:drain()
    for _, e in ipairs(events) do
      if e.type == "shot" then
        self.counts.shots = self.counts.shots + 1
      elseif e.type == "bullet_cancel" then
        self.counts.cancels = self.counts.cancels + 1
      elseif e.type == "terrain_destroyed" then
        self.counts.destroyed = self.counts.destroyed + #e.cells
      end
    end
    self.fx = M.update_fx(self.fx, events)
    local ss = self.save_status
    if ss then
      ss.ttl = ss.ttl - 1
      if ss.ttl <= 0 then
        self.save_status = nil
      end
    end
  end

  function state:keypressed(key)
    local edit = self.edit
    local changed = false
    if key == "f2" then
      self:start()
    elseif key == "f6" then
      self.arena_name = M.next_arena(self.arena_name)
      self:start()
    elseif key == "f7" then
      self.player_level = (self.player_level + 1) % 4
      self:start()
    elseif key == "f5" then
      edit:toggle()
    elseif key == "f8" then
      -- Save an independent snapshot; the live recording continues as is.
      local path, err = ctx.save_replay(replay.snapshot(self.recording, self.world))
      if path then
        self.save_status = { ok = true, text = "REPLAY SAVED", ttl = M.SAVE_STATUS_TTL }
        print("arena: recording saved to " .. path)
      else
        self.save_status = { ok = false, text = "REPLAY SAVE FAILED", ttl = M.SAVE_STATUS_TTL }
        print("arena: recording NOT saved: " .. tostring(err))
      end
    elseif edit.open then
      if key == "[" then
        edit:select(-1)
      elseif key == "]" then
        edit:select(1)
      elseif key == "-" then
        changed = edit:adjust(-1)
      elseif key == "=" then
        changed = edit:adjust(1)
      elseif key == "backspace" then
        changed = edit:reset()
      end
    end
    if changed then
      self:start()
    end
  end

  function state:draw()
    require("src.render.arena_view").draw({
      world = self.world,
      fx = self.fx,
      counts = self.counts,
      edit = self.edit,
      modified = self.edit:modified(),
      save_status = self.save_status,
      title = M.TITLES[self.arena_name],
    })
  end

  -- Smoke report fields: player positions (u), the state hash and the arena.
  function state:smoke_info()
    local p1, p2 = self.world.tanks[1], self.world.tanks[2]
    return {
      p1 = ("%d,%d"):format(p1.x, p1.y),
      p2 = ("%d,%d"):format(p2.x, p2.y),
      hash = sim.hash(self.world),
      arena = self.arena_name,
    }
  end

  return state
end

return M
