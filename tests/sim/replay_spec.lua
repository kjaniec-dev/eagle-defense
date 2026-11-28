-- Golden replays (G1 plan §7, §8): fixtures match, determinism across
-- processes and presentation scales, tuning identity, and what each golden
-- proves about combat.

local fs = require("tools.lib.fs")
local serialize = require("src.core.serialize")
local replay = require("src.sim.replay")
local tuning = require("src.sim.tuning")
local sim = require("src.sim.sim")
local layout = require("src.render.layout")
local update_goldens = require("tools.update_goldens")

local DIR = "tests/fixtures/replays/"
local NAMES = { "movement_tour", "shooting_gallery", "cancellation_duel", "stress_run" }

local function load(name)
  return assert(serialize.decode(assert(fs.read(DIR .. name .. ".lua"))))
end

local ACTIVE = tuning.load()

-- Event counts per type for a replay run.
local function census(r)
  local counts = {}
  local res = assert(replay.run(r, ACTIVE, {
    on_tick = function(_, _, events)
      for _, e in ipairs(events) do
        local k = e.type
        if e.friendly then
          k = k .. ":friendly"
        end
        counts[k] = (counts[k] or 0) + 1
      end
    end,
  }))
  return counts, res
end

describe("golden replays", function()
  it("has the four G1 fixtures, recorded with the active tuning", function()
    for _, name in ipairs(NAMES) do
      local r = load(name)
      assert.is_true(replay.check(r))
      assert.are.equal(ACTIVE.id, r.tuning_id, name)
      assert.is_false(r.debug_tuned)
      assert.is_true(#r.checkpoints >= 10, name)
    end
    assert.are.equal(#NAMES, #fs.list_files(DIR, "%.lua$"))
  end)

  for _, name in ipairs(NAMES) do
    it(name .. " matches its checkpoint hashes, with the invariants on every tick", function()
      assert.is_true(replay.verify(load(name), ACTIVE))
    end)
  end

  it("each golden exercises the behavior it is named for", function()
    local c = census(load("movement_tour"))
    assert.is_nil(c["tank_hit"]) -- players never shoot
    c = census(load("shooting_gallery"))
    assert.is_true(c["tank_hit"] >= 3) -- the target dummy is hit
    assert.is_true(c["tank_hit:friendly"] >= 1)
    assert.is_true(c["bullet_hit_solid"] >= 20)
    c = census(load("cancellation_duel"))
    assert.is_true(c["bullet_cancel"] >= 3)
    c = census(load("stress_run"))
    assert.is_true(c["shot"] >= 200 and c["tank_hit"] >= 10)
  end)

  -- G2 plan §2, §9; clarification C5: G2 may change only the tuning_id of
  -- the four approved G1 goldens. Their checkpoints must stay byte-identical
  -- to the values frozen at c82ff86.
  it("keeps every G1 checkpoint byte-identical to c82ff86 (only tuning_id changed)", function()
    local frozen = require("tests.sim.g1_frozen_checkpoints")
    for _, name in ipairs(NAMES) do
      local r = load(name)
      local got = {}
      for i, cp in ipairs(r.checkpoints) do
        got[i] = ("%d:%s"):format(cp[1], cp[2])
      end
      assert.are.same(frozen[name], got, name)
      -- the recomputed checkpoints, not just the stored ones
      local res = assert(replay.run(r, ACTIVE))
      local again = {}
      for i, cp in ipairs(res.checkpoints) do
        again[i] = ("%d:%s"):format(cp[1], cp[2])
      end
      assert.are.same(frozen[name], again, name)
      -- the legacy G1 header: no arena_id, no player_level
      assert.is_nil(r.arena_id)
      assert.is_nil(r.player_level)
      assert.are.equal("g1_arena", r.arena)
    end
  end)

  it("refuses a replay recorded with a different tuning id", function()
    local r = load("movement_tour")
    r.tuning_id = "deadbeef"
    local res, err = replay.run(r, ACTIVE)
    assert.is_nil(res)
    assert.matches("tuning_id mismatch", err)
    -- the active tuning changed instead: also refused
    local changed = tuning.copy(ACTIVE.values)
    changed.player_speed = changed.player_speed + 1
    local other = { values = changed, version = ACTIVE.version, id = tuning.id(changed, 1) }
    res, err = replay.run(load("movement_tour"), other)
    assert.is_nil(res)
    assert.matches("tuning_id mismatch", err)
  end)

  it("detects a changed checkpoint", function()
    local r = load("cancellation_duel")
    r.checkpoints[5][2] = "00000000"
    local ok, err = replay.verify(r, ACTIVE)
    assert.is_nil(ok)
    assert.matches("checkpoint 5 differs", err)
  end)

  it("update_goldens reproduces the fixtures and refuses debug-tuned replays", function()
    for _, name in ipairs(NAMES) do
      local r = load(name)
      local regenerated = assert(update_goldens.regenerate(r, ACTIVE))
      assert.are.equal(fs.read(DIR .. name .. ".lua"), serialize.encode(regenerated))
    end
    local tuned = load("movement_tour")
    tuned.debug_tuned = true
    local res, err = update_goldens.regenerate(tuned, ACTIVE)
    assert.is_nil(res)
    assert.matches("debug_tuned", err)
  end)

  it("gives identical hashes in a second LuaJIT process", function()
    local script = [[
      package.path = "./?.lua;" .. package.path
      local fs = require("tools.lib.fs")
      local s = require("src.core.serialize")
      local replay = require("src.sim.replay")
      local active = require("src.sim.tuning").load()
      local names = { "movement_tour", "shooting_gallery", "cancellation_duel", "stress_run" }
      for _, n in ipairs(names) do
        local r = s.decode(fs.read("tests/fixtures/replays/" .. n .. ".lua"))
        io.write(n, " ", assert(replay.run(r, active)).final, "\n")
      end
    ]]
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(script)
    f:close()
    local p = assert(io.popen("luajit " .. path))
    local out = p:read("*a")
    p:close()
    os.remove(path)
    local expected = {}
    for _, name in ipairs(NAMES) do
      expected[#expected + 1] = name .. " " .. assert(replay.run(load(name), ACTIVE)).final
    end
    assert.are.equal(table.concat(expected, "\n") .. "\n", out)
  end)

  it("gives identical hashes with 24 px and 32 px presentation, which never mutates", function()
    for _, tile_px in ipairs({ 24, 32 }) do
      for _, name in ipairs(NAMES) do
        local ok, err = replay.verify(load(name), ACTIVE, {
          on_tick = function(w)
            local before = sim.hash(w)
            local view = layout.build(w, tile_px, 0, 0)
            assert(#view.tanks >= 3)
            assert(sim.hash(w) == before, "presentation mutated the world")
          end,
        })
        assert.is_true(ok, err)
      end
    end
  end)

  it("encodes InputFrames losslessly and compresses runs", function()
    local frames = {
      { { dir = "up", fire = true, fire_pressed = true }, { dir = nil, fire = false } },
      { { dir = "left", fire = true }, { dir = "down", fire = true, fire_pressed = true } },
    }
    for _, fr in ipairs(frames) do
      local code = replay.encode_frame(fr)
      local back = replay.decode_frame(code)
      for p = 1, 2 do
        assert.are.equal(fr[p].dir, back[p].dir)
        assert.are.equal(fr[p].fire == true, back[p].fire)
        assert.are.equal(fr[p].fire_pressed == true, back[p].fire_pressed)
      end
    end
    assert.are.equal("UFP...", replay.encode_frame(frames[1]))
    local runs = replay.compress({ "U.....", "U.....", "......", "U....." })
    assert.are.same({ { "U.....", 2 }, { "......", 1 }, { "U.....", 1 } }, runs)
    assert.are.same({ "U.....", "U.....", "......", "U....." }, replay.expand(runs))
    assert.has_error(function()
      replay.decode_frame("X.....")
    end)
  end)

  it("a recording made while stepping replays to the same checkpoints", function()
    local r = load("shooting_gallery")
    local w = sim.new({ arena = "g1_arena", tuning = ACTIVE.values, seed = r.seed })
    local rec = replay.new_recording({
      name = "rec",
      arena = "g1_arena",
      seed = r.seed,
      tuning_id = ACTIVE.id,
      tuning_version = ACTIVE.version,
    })
    for _, code in ipairs(replay.expand(r.frames)) do
      local frame = replay.decode_frame(code)
      sim.step(w, frame)
      replay.record(rec, frame, w)
    end
    local snap = replay.snapshot(rec, w)
    assert.are.same(r.checkpoints, snap.checkpoints)
    assert.are.same(r.frames, snap.frames)
    assert.is_true(replay.verify(snap, ACTIVE))
  end)
end)
