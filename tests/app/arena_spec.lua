-- G1 arena app state (without LÖVE): the smoke script outcome, the F5
-- debug tuning editor and recordings.

local fs = require("tools.lib.fs")
local args = require("src.app.args")
local arena_state = require("src.app.states.arena")
local tuning_edit = require("src.app.tuning_edit")
local tuning = require("src.sim.tuning")
local replay = require("src.sim.replay")
local sim = require("src.sim.sim")

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
