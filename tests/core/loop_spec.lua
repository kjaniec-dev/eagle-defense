local loop_mod = require("src.core.loop")

local function run_frames(dts)
  local loop = loop_mod.new()
  local ticks = 0
  for _, dt in ipairs(dts) do
    loop:advance(dt, function()
      ticks = ticks + 1
    end)
  end
  return ticks, loop
end

local function frames_at(hz, seconds)
  local dts = {}
  for i = 1, math.floor(hz * seconds + 0.5) do
    dts[i] = 1 / hz
  end
  return dts
end

describe("core.loop", function()
  it("runs exactly one tick per 1/60 s frame (no float drift)", function()
    local loop = loop_mod.new()
    for frame = 1, 3600 do
      local ran = loop:advance(1 / 60, function() end)
      assert.are.equal(1, ran, "frame " .. frame)
    end
    assert.are.equal(3600, loop.tick)
  end)

  it("produces the same tick count at 30, 60, 75, 144 and 240 Hz rendering", function()
    for _, hz in ipairs({ 30, 60, 75, 144, 240 }) do
      local ticks = run_frames(frames_at(hz, 10))
      assert.is_true(math.abs(ticks - 600) <= 1, hz .. " Hz gave " .. ticks .. " ticks")
    end
  end)

  -- Regression guard: without the epsilon tolerance, 144 frames of 1/144 s
  -- sum to slightly less than 60 steps and one tick is deferred.
  it("runs exactly 60 ticks for exactly one second of 144 Hz frames", function()
    local ticks = run_frames(frames_at(144, 1))
    assert.are.equal(60, ticks)
  end)

  it("handles irregular frame times without losing ticks", function()
    local dts = {}
    for i = 1, 1000 do
      dts[i] = (i % 3 == 0) and 0.031 or 0.0045
    end
    local total = 0
    for _, dt in ipairs(dts) do
      total = total + dt
    end
    local ticks = run_frames(dts)
    assert.is_true(math.abs(ticks - math.floor(total * 60)) <= 1)
  end)

  it("caps ticks per frame and drops the backlog after a stall", function()
    local loop = loop_mod.new({ max_steps = 5, max_frame_dt = 0.25 })
    local ran = loop:advance(10, function() end)
    assert.are.equal(5, ran)
    assert.are.equal(0, loop.accumulator)
    assert.is_true(loop.dropped > 0)
    -- The next normal frame runs a single tick again.
    assert.are.equal(1, loop:advance(1 / 60, function() end))
  end)

  it("ignores negative and NaN frame deltas", function()
    local loop = loop_mod.new()
    assert.are.equal(0, loop:advance(-1, function() end))
    assert.are.equal(0, loop:advance(0 / 0, function() end))
    assert.are.equal(0, loop.tick)
  end)

  it("passes the increasing tick index to the callback", function()
    local loop = loop_mod.new()
    local seen = {}
    loop:advance(3 / 60, function(t)
      seen[#seen + 1] = t
    end)
    assert.are.same({ 1, 2, 3 }, seen)
  end)

  it("exposes a presentation alpha in [0, 1)", function()
    local loop = loop_mod.new()
    loop:advance(1.5 / 60, function() end)
    assert.is_true(math.abs(loop:alpha() - 0.5) < 1e-6)
  end)
end)
