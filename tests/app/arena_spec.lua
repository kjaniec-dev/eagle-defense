-- G1 arena app state (without LÖVE): the smoke script outcome, the F5
-- debug tuning editor and recordings.

local fs = require("tools.lib.fs")
local args = require("src.app.args")
local arena_state = require("src.app.states.arena")
local tuning_edit = require("src.app.tuning_edit")
local tuning = require("src.sim.tuning")
local replay = require("src.sim.replay")
local sim = require("src.sim.sim")

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

local function new_state()
  local ctx = { quit_called = false, saved = {} }
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
      st:tick(args.smoke_frame(tick))
    end
    local info = st:smoke_info()
    local line = ("p1=%s p2=%s hash=%s"):format(info.p1, info.p2, info.hash)
    local pinned = fs.read("tools/lib/smoke_expect.sh"):match('SMOKE_EXPECT_120="([^"]+)"')
    assert.are.equal(pinned, line)
    assert.are.equal(4, st.counts.shots)
  end)

  it("records live play as a replay that verifies against the committed tuning", function()
    local st, ctx = new_state()
    for tick = 1, 150 do
      st:tick(args.smoke_frame(tick))
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
        st:tick(args.smoke_frame(st.world.tick + 1))
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
      st:tick(args.smoke_frame(tick))
    end
    st:keypressed("f8")
    st:keypressed("f8")
    for tick = 121, 180 do
      st:tick(args.smoke_frame(tick))
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
    st:tick(args.smoke_frame(1))
    local ok, err = pcall(st.keypressed, st, "f8")
    _G.print = real_print
    assert(ok, err)
    assert.is_false(st.save_status.ok)
    assert.are.equal("REPLAY SAVE FAILED", st.save_status.text)
    assert.are.equal("arena: recording NOT saved: disk full", printed[1])
    for _ = 1, arena_state.SAVE_STATUS_TTL do
      st:tick(args.smoke_frame(1))
    end
    assert.is_nil(st.save_status) -- the HUD message expires
    assert.are.equal(1, #st.recording.frames) -- the live recording keeps going
  end)

  it("quits on pause (Esc) like the G0 scene", function()
    local st, ctx = new_state()
    local frame = args.smoke_frame(1)
    frame[1].pause_pressed = true
    st:tick(frame)
    assert.is_true(ctx.quit_called)
    assert.are.equal(0, st.world.tick)
  end)

  it("F5 edits a copy, restarts the arena and tags recordings debug_tuned", function()
    local st, ctx = new_state()
    local committed = require("config.tuning").entries.player_speed[1]
    for _ = 1, 10 do
      st:tick(args.smoke_frame(1))
    end
    st:keypressed("f5")
    assert.is_true(st.edit.open)
    st:keypressed("=") -- player_speed + 1
    assert.is_true(st.edit:modified())
    assert.are.equal(0, st.world.tick) -- restarted with the modified copy
    assert.are.equal(committed + 1, st.world.tuning.player_speed)
    assert.are.equal(committed, tuning.load().values.player_speed) -- file untouched
    st:tick(args.smoke_frame(1))
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
    st:tick(args.smoke_frame(1))
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
      assert.is_true(item.min >= rule.min and item.max <= rule.max, item.key)
    end
  end)
end)
