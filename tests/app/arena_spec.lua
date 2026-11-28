-- Arena app state (without LÖVE): the smoke script outcomes of both
-- arenas, the F5 debug tuning editor, F6/F7 (clarification C2) and
-- recordings.

local fs = require("tools.lib.fs")
local levels = require("tools.lib.levels")
local args = require("src.app.args")
local arena_state = require("src.app.states.arena")
local tuning_edit = require("src.app.tuning_edit")
local tuning = require("src.sim.tuning")
local replay = require("src.sim.replay")
local sim = require("src.sim.sim")
local serialize = require("src.core.serialize")

local function ticks_of(checkpoints)
  local out = {}
  for i, cp in ipairs(checkpoints) do
    out[i] = cp[1]
  end
  return out
end

local function frame_count(rec)
  local n = 0
  for _, r in ipairs(rec.frames) do
    n = n + r[2]
  end
  return n
end

-- The G1 tests run in the G1 arena explicitly (clarification C4).
local function new_state(arena)
  local ctx = { quit_called = false, saved = {}, arena = arena or "g1_arena" }
  ctx.read_level = levels.read_arena
  ctx.quit = function()
    ctx.quit_called = true
  end
  ctx.save_replay = function(rec)
    ctx.saved[#ctx.saved + 1] = rec
    return "mem:" .. #ctx.saved
  end
  local st = arena_state.new(ctx)
  st:enter()
  return st, ctx
end

describe("app.states.arena", function()
  it("ends the 120-tick smoke script with the outcome pinned for tools/smoke.sh", function()
    local st = new_state()
    for tick = 1, 120 do
      st:tick(args.smoke_frame(tick, "g1_arena"))
    end
    local info = st:smoke_info()
    local line = ("p1=%s p2=%s hash=%s"):format(info.p1, info.p2, info.hash)
    local pinned = fs.read("tools/lib/smoke_expect.sh"):match('SMOKE_EXPECT_120="([^"]+)"')
    assert.are.equal(pinned, line)
    assert.are.equal("p1=1408,2688 p2=1664,2652 hash=581f15d4", line) -- the G1 value
    assert.are.equal(4, st.counts.shots)
    assert.are.equal("g1_arena", info.arena)
  end)

  it("ends the 120-tick terrain smoke script with its pinned outcome", function()
    local st = new_state("g2_terrain")
    local slide_ticks = 0
    for tick = 1, 120 do
      st:tick(args.smoke_frame(tick, "g2_terrain"))
      if st.world.tanks[1].slide_dir then
        slide_ticks = slide_ticks + 1
      end
    end
    local info = st:smoke_info()
    local line = ("p1=%s p2=%s hash=%s"):format(info.p1, info.p2, info.hash)
    local pinned = fs.read("tools/lib/smoke_expect.sh"):match('SMOKE_EXPECT_G2_120="([^"]+)"')
    assert.are.equal(pinned, line)
    assert.are.equal("g2_terrain", info.arena)
    -- what the script is for: P1 slides on ice, P2 digs brick point-blank
    assert.is_true(slide_ticks >= 28)
    assert.are.equal(6, st.counts.shots)
    assert.is_true(st.counts.destroyed >= 8)
  end)

  it("opens the terrain arena by default", function()
    local ctx = { saved = {}, read_level = levels.read_arena, quit = function() end }
    local st = arena_state.new(ctx)
    st:enter()
    assert.are.equal("g2_terrain", st.arena_name)
    assert.are.equal(4, #st.world.tanks)
  end)

  it("records live play as a replay that verifies against the committed tuning", function()
    local st, ctx = new_state()
    for tick = 1, 150 do
      st:tick(args.smoke_frame(tick, "g1_arena"))
    end
    st:keypressed("f8")
    local rec = ctx.saved[1]
    assert.is_false(rec.debug_tuned)
    assert.are.equal(150, rec.checkpoints[#rec.checkpoints][1])
    assert.is_true(replay.verify(rec, tuning.load()))
  end)

  it("saves an empty recording at tick 0 without failing", function()
    local st, ctx = new_state()
    st:keypressed("f8")
    st:keypressed("f8")
    for i = 1, 2 do
      assert.are.same({}, ctx.saved[i].checkpoints)
      assert.are.same({}, ctx.saved[i].frames)
      assert.is_true(replay.verify(ctx.saved[i], tuning.load()))
    end
  end)

  -- Review P2-1: F8 must snapshot the recording, not close the live one.
  it("saves at tick 150, plays on to 200 and saves again: both recordings verify", function()
    local st, ctx = new_state()
    local function play_to(n)
      while st.world.tick < n do
        st:tick(args.smoke_frame(st.world.tick + 1, "g1_arena"))
      end
    end
    play_to(150)
    st:keypressed("f8")
    play_to(200)
    st:keypressed("f8")
    local active = tuning.load()
    local first, second = ctx.saved[1], ctx.saved[2]
    assert.are_not.equal(first, second)
    assert.are.same({ 60, 120, 150 }, ticks_of(first.checkpoints))
    assert.are.same({ 60, 120, 180, 200 }, ticks_of(second.checkpoints))
    assert.is_true(replay.verify(first, active))
    assert.is_true(replay.verify(second, active))
    -- the live recording only has checkpoints on the grid
    assert.are.same({ 60, 120, 180 }, ticks_of(st.recording.checkpoints))
    -- the first snapshot did not change when play continued
    assert.are.equal(150, frame_count(first))
    assert.are.equal(200, frame_count(second))
  end)

  it("repeated saves at checkpoint boundaries give identical, verifying recordings", function()
    local st, ctx = new_state()
    for tick = 1, 120 do
      st:tick(args.smoke_frame(tick, "g1_arena"))
    end
    st:keypressed("f8")
    st:keypressed("f8")
    for tick = 121, 180 do
      st:tick(args.smoke_frame(tick, "g1_arena"))
    end
    st:keypressed("f8")
    local active = tuning.load()
    assert.are.same(ctx.saved[1], ctx.saved[2])
    assert.are.same({ 60, 120 }, ticks_of(ctx.saved[1].checkpoints))
    assert.are.same({ 60, 120, 180 }, ticks_of(ctx.saved[3].checkpoints))
    for i = 1, 3 do
      assert.is_true(replay.verify(ctx.saved[i], active))
    end
    assert.are.same({ 60, 120, 180 }, ticks_of(st.recording.checkpoints))
  end)

  it("reports a failed write as a failure, never as a saved recording", function()
    local st, ctx = new_state()
    ctx.save_replay = function()
      return nil, "disk full"
    end
    local printed = {}
    local real_print = print
    _G.print = function(s)
      printed[#printed + 1] = s
    end
    st:tick(args.smoke_frame(1, "g1_arena"))
    local ok, err = pcall(st.keypressed, st, "f8")
    _G.print = real_print
    assert(ok, err)
    assert.is_false(st.save_status.ok)
    assert.are.equal("REPLAY SAVE FAILED", st.save_status.text)
    assert.are.equal("arena: recording NOT saved: disk full", printed[1])
    for _ = 1, arena_state.SAVE_STATUS_TTL do
      st:tick(args.smoke_frame(1, "g1_arena"))
    end
    assert.is_nil(st.save_status) -- the HUD message expires
    assert.are.equal(1, #st.recording.frames) -- the live recording keeps going
  end)

  it("quits on pause (Esc) like the G0 scene", function()
    local st, ctx = new_state()
    local frame = args.smoke_frame(1, "g1_arena")
    frame[1].pause_pressed = true
    st:tick(frame)
    assert.is_true(ctx.quit_called)
    assert.are.equal(0, st.world.tick)
  end)

  it("F5 edits a copy, restarts the arena and tags recordings debug_tuned", function()
    local st, ctx = new_state()
    local committed = require("config.tuning").entries.player_speed[1]
    for _ = 1, 10 do
      st:tick(args.smoke_frame(1, "g1_arena"))
    end
    st:keypressed("f5")
    assert.is_true(st.edit.open)
    st:keypressed("=") -- player_speed + 1
    assert.is_true(st.edit:modified())
    assert.are.equal(0, st.world.tick) -- restarted with the modified copy
    assert.are.equal(committed + 1, st.world.tuning.player_speed)
    assert.are.equal(committed, tuning.load().values.player_speed) -- file untouched
    st:tick(args.smoke_frame(1, "g1_arena"))
    st:keypressed("f8")
    local rec = ctx.saved[1]
    assert.is_true(rec.debug_tuned)
    assert.are_not.equal(tuning.load().id, rec.tuning_id)
    -- the runner refuses it against the committed tuning
    assert.is_nil((replay.run(rec, tuning.load())))
    st:keypressed("backspace")
    assert.is_false(st.edit:modified())
    assert.are.equal(committed, st.world.tuning.player_speed)
  end)

  it("ignores editor keys while the editor is closed", function()
    local st = new_state()
    st:tick(args.smoke_frame(1, "g1_arena"))
    st:keypressed("=")
    assert.is_false(st.edit:modified())
    assert.are.equal(1, st.world.tick)
  end)

  it("turns sim events into aging presentation effects without touching the sim", function()
    local st = new_state()
    local before = sim.hash(st.world)
    local fx = arena_state.update_fx({}, {
      { type = "tank_hit", tank = 3, x = 10, y = 20 },
      { type = "bullet_cancel", x = 5, y = 6 },
      { type = "respawn_blocked", tank = 1 },
    })
    assert.are.equal(2, #fx)
    for _ = 1, 10 do
      fx = arena_state.update_fx(fx, {})
    end
    assert.are.equal(1, #fx) -- the cancel spark (10 ticks) has expired
    assert.are.equal("tank_hit", fx[1].type)
    assert.are.equal(before, sim.hash(st.world))
  end)
end)

describe("app.tuning_edit", function()
  it("selects cyclically, clamps to ranges and reports changed rows", function()
    local e = tuning_edit.new(tuning.load())
    e:select(-1)
    assert.are.equal(#tuning_edit.ITEMS, e.selected)
    e:select(1)
    assert.are.equal(1, e.selected)
    for _ = 1, 100 do
      e:adjust(-1)
    end
    assert.are.equal(1, e.values.player_speed)
    assert.is_true(e:rows()[1].changed)
    assert.is_false(e:rows()[2].changed)
    assert.is_true(e:reset())
    assert.is_false(e:modified())
  end)

  it("every editable key exists in the tuning schema", function()
    for _, item in ipairs(tuning_edit.ITEMS) do
      local rule = tuning.SCHEMA[item.key]
      assert.is_truthy(rule, item.key)
      if item.one_of then
        assert.are.same(rule.one_of, item.one_of, item.key)
      else
        assert.is_true(item.min >= rule.min and item.max <= rule.max, item.key)
      end
    end
  end)

  -- G2 clarification C2: F7 is the only level selector.
  it("does not offer the players' upgrade level (F7 selects it)", function()
    for _, item in ipairs(tuning_edit.ITEMS) do
      assert.are_not.equal("arena_player_level", item.key)
    end
  end)

  it("offers the G2 terrain keys; enumerated keys step through their allowed values", function()
    local e = tuning_edit.new(tuning.load())
    local pos = {}
    for i, item in ipairs(tuning_edit.ITEMS) do
      pos[item.key] = i
    end
    assert.is_truthy(pos.ice_slide_distance and pos.brick_strip_cells and pos.brick_strip_depth)
    e.selected = pos.ice_slide_distance
    assert.is_true(e:adjust(1))
    assert.are.equal(200, e.values.ice_slide_distance) -- step 8
    e.selected = pos.brick_strip_cells
    assert.is_true(e:adjust(1))
    assert.are.equal(4, e.values.brick_strip_cells)
    assert.is_false(e:adjust(1)) -- clamped at the last allowed value
    assert.is_true(e:adjust(-1))
    assert.are.equal(2, e.values.brick_strip_cells)
    e.selected = pos.brick_strip_depth
    assert.is_true(e:adjust(1))
    assert.are.equal(2, e.values.brick_strip_depth)
    assert.is_true(e:modified())
  end)
end)

describe("app.states.arena F6 / F7 (clarification C2)", function()
  local function play(st, n)
    for _ = 1, n do
      st:tick(args.smoke_frame(st.world.tick + 1, st.arena_name))
    end
  end

  it("F7 cycles the level 0..3, restarts the arena and is not debug tuning", function()
    local st, ctx = new_state("g2_terrain")
    assert.are.equal(0, st.player_level)
    play(st, 10)
    st:keypressed("f7")
    assert.are.equal(1, st.player_level)
    assert.are.equal(0, st.world.tick) -- restarted
    assert.are.same({ 1, 1 }, { st.world.tanks[1].level, st.world.tanks[2].level })
    assert.are.equal(1, st.world.player_level)
    for _ = 1, 3 do
      st:keypressed("f7")
    end
    assert.are.equal(0, st.player_level) -- wrapped
    st:keypressed("f7")
    st:keypressed("f7")
    st:keypressed("f7")
    play(st, 5)
    st:keypressed("f8")
    local rec = ctx.saved[1]
    assert.are.equal(3, rec.player_level)
    assert.is_false(rec.debug_tuned)
    assert.is_false(st.edit:modified())
  end)

  it("F2 keeps the arena, the F7 level and the F5 copy", function()
    local st = new_state("g2_terrain")
    st:keypressed("f7")
    st:keypressed("f5")
    st.edit.selected = 1
    st:keypressed("=") -- player_speed + 1
    play(st, 10)
    st:keypressed("f2")
    assert.are.same({ "g2_terrain", 1, 0 }, { st.arena_name, st.player_level, st.world.tick })
    assert.is_true(st.edit:modified())
    assert.are.equal(st.edit.values.player_speed, st.world.tuning.player_speed)
  end)

  it("F6 switches arenas and keeps the F7 level and the F5 copy", function()
    local st = new_state("g2_terrain")
    st:keypressed("f7")
    st:keypressed("f7")
    st:keypressed("f5")
    st.edit.selected = 1
    st:keypressed("=")
    st:keypressed("f6")
    assert.are.same({ "g1_arena", 2, 0 }, { st.arena_name, st.player_level, st.world.tick })
    assert.are.equal(5, #st.world.tanks) -- the G1 arena's entities
    assert.are.equal(2, st.world.tanks[1].level)
    assert.is_true(st.edit:modified())
    st:keypressed("f6")
    assert.are.equal("g2_terrain", st.arena_name)
  end)

  it("respawned players get the F7 level", function()
    local st = new_state("g2_terrain")
    st:keypressed("f7")
    st:keypressed("f7")
    local p1 = st.world.tanks[1]
    p1.level = 0 -- as if lost on death (G5); the respawn restores the world level
    p1.hit_pending = true
    st:tick(args.smoke_frame(1, "g2_terrain"))
    st:tick(args.smoke_frame(2, "g2_terrain"))
    assert.is_true(p1.present)
    assert.are.equal(2, p1.level)
  end)

  it(
    "an F5 change with any F7 level is debug_tuned and refused against committed tuning",
    function()
      local st, ctx = new_state("g2_terrain")
      st:keypressed("f7")
      st:keypressed("f5")
      st.edit.selected = 1
      st:keypressed("=")
      play(st, 20)
      st:keypressed("f8")
      local rec = ctx.saved[1]
      assert.is_true(rec.debug_tuned)
      assert.are.equal(1, rec.player_level)
      assert.is_nil((replay.run(rec, tuning.load(), { resolve_arena = levels.read_arena })))
    end
  )

  it("F8 at level 3 in the terrain arena: repeated saves replay correctly", function()
    local st, ctx = new_state("g2_terrain")
    for _ = 1, 3 do
      st:keypressed("f7")
    end
    play(st, 90)
    st:keypressed("f8")
    play(st, 30)
    st:keypressed("f8")
    local active = tuning.load()
    local opts = { resolve_arena = levels.read_arena }
    for i = 1, 2 do
      local rec = ctx.saved[i]
      assert.are.same({ "g2_terrain", 3 }, { rec.arena, rec.player_level })
      assert.matches("^%x%x%x%x%x%x%x%x$", rec.arena_id)
      assert.is_true(replay.verify(rec, active, opts))
      -- survives the file round trip (serialize, decode)
      local back = serialize.decode(serialize.encode(rec))
      assert.is_true(replay.verify(back, active, opts))
    end
    assert.is_true(st.counts.destroyed > 0) -- the saves include destruction
  end)

  it("recordings in the G1 arena carry an arena_id too", function()
    local st, ctx = new_state("g1_arena")
    play(st, 30)
    st:keypressed("f8")
    local rec = ctx.saved[1]
    assert.are.equal("g1_arena", rec.arena)
    assert.matches("^%x%x%x%x%x%x%x%x$", rec.arena_id)
    assert.are.equal(0, rec.player_level)
    assert.is_true(replay.verify(rec, tuning.load()))
  end)
end)
