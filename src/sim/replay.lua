-- Deterministic replays: InputFrame encoding, run-length compression, the
-- replay runner and recordings (G1 plan §7, §8).
--
-- Replay table (data only; fixtures in tests/fixtures/replays/):
--   {
--     format = 1, name = "...", description = "...",
--     arena = "g1_arena", seed = 1,
--     tuning_id = "8 hex", tuning_version = 1, debug_tuned = false,
--     checkpoint_every = 60,
--     frames = { { "U.PR..", 12 }, ... },   -- run-length encoded frame codes
--     checkpoints = { { 60, "8 hex" }, ... }, -- state hash at those ticks
--   }
-- A frame code has 3 characters per player (P1 then P2): direction
-- (U, D, L, R or "."), fire held (F or "."), fire pressed (P or ".").

local sim = require("src.sim.sim")
local arena_mod = require("src.sim.arena")

local M = {}

M.FORMAT = 1

local DIR_TO_CODE = { up = "U", down = "D", left = "L", right = "R" }
local CODE_TO_DIR = { U = "up", D = "down", L = "left", R = "right" }

-- Encodes an InputFrame (players 1 and 2) as a 6-character code.
function M.encode_frame(frame)
  local parts = {}
  for p = 1, 2 do
    local f = frame and frame[p] or {}
    parts[#parts + 1] = (DIR_TO_CODE[f.dir] or ".")
      .. (f.fire and "F" or ".")
      .. (f.fire_pressed and "P" or ".")
  end
  return table.concat(parts)
end

-- Decodes a 6-character frame code into an InputFrame. Raises on bad input.
function M.decode_frame(code)
  assert(type(code) == "string" and #code == 6, "replay: frame code must have 6 characters")
  local frame = {}
  for p = 1, 2 do
    local d, f, pr =
      code:sub(p * 3 - 2, p * 3 - 2), code:sub(p * 3 - 1, p * 3 - 1), code:sub(p * 3, p * 3)
    assert(d == "." or CODE_TO_DIR[d], "replay: bad direction code " .. d)
    assert(f == "." or f == "F", "replay: bad fire code " .. f)
    assert(pr == "." or pr == "P", "replay: bad press code " .. pr)
    frame[p] = { dir = CODE_TO_DIR[d], fire = f == "F", fire_pressed = pr == "P" }
  end
  return frame
end

-- Run-length compression of a list of frame codes.
function M.compress(codes)
  local runs = {}
  for _, c in ipairs(codes) do
    local last = runs[#runs]
    if last and last[1] == c then
      last[2] = last[2] + 1
    else
      runs[#runs + 1] = { c, 1 }
    end
  end
  return runs
end

-- Expands runs into a list of frame codes.
function M.expand(runs)
  local codes = {}
  for i, r in ipairs(runs) do
    assert(type(r) == "table" and type(r[1]) == "string", "replay: bad run " .. i)
    assert(type(r[2]) == "number" and r[2] >= 1 and r[2] == math.floor(r[2]), "replay: bad count")
    M.decode_frame(r[1]) -- validates
    for _ = 1, r[2] do
      codes[#codes + 1] = r[1]
    end
  end
  return codes
end

-- Structural validation. Returns true, or nil and a message.
function M.check(replay)
  if type(replay) ~= "table" then
    return nil, "replay: table expected"
  end
  if replay.format ~= M.FORMAT then
    return nil, "replay: unsupported format " .. tostring(replay.format)
  end
  for _, k in ipairs({ "name", "arena", "tuning_id" }) do
    if type(replay[k]) ~= "string" then
      return nil, "replay: " .. k .. " (string) required"
    end
  end
  for _, k in ipairs({ "seed", "tuning_version", "checkpoint_every" }) do
    if type(replay[k]) ~= "number" or replay[k] ~= math.floor(replay[k]) then
      return nil, "replay: " .. k .. " (integer) required"
    end
  end
  if replay.checkpoint_every < 1 then
    return nil, "replay: checkpoint_every must be >= 1"
  end
  if type(replay.debug_tuned) ~= "boolean" then
    return nil, "replay: debug_tuned (boolean) required"
  end
  if type(replay.frames) ~= "table" or type(replay.checkpoints) ~= "table" then
    return nil, "replay: frames and checkpoints required"
  end
  local ok, err = pcall(M.expand, replay.frames)
  if not ok then
    return nil, tostring(err)
  end
  return true
end

-- Runs a replay against the active tuning ({ values, version, id }).
-- Refuses a replay recorded with a different tuning id. Asserts the tick
-- invariants on every tick. opts.on_tick(world, tick, events) is called after
-- each step with that tick's events (presentation probes; it must not mutate
-- the world).
-- Returns { checkpoints = { { tick, hash }, ... }, final = hash, world = w }
-- or nil and an error message.
function M.run(replay, active, opts)
  opts = opts or {}
  local ok, err = M.check(replay)
  if not ok then
    return nil, err
  end
  if replay.tuning_id ~= active.id or replay.tuning_version ~= active.version then
    return nil,
      (
        "replay %s: tuning_id mismatch (recorded %s v%d, active %s v%d); regenerate it with "
        .. "tools/update_goldens.lua if the tuning change is intended"
      ):format(
        replay.name,
        replay.tuning_id,
        replay.tuning_version,
        active.id,
        active.version
      )
  end
  local w = sim.new({
    arena = arena_mod.load(replay.arena),
    tuning = active.values,
    seed = replay.seed,
  })
  local codes = M.expand(replay.frames)
  local checkpoints = {}
  local every = replay.checkpoint_every
  for i, code in ipairs(codes) do
    sim.step(w, M.decode_frame(code))
    local bad = sim.violations(w)
    if #bad > 0 then
      return nil,
        ("replay %s: invariant violated at tick %d: %s"):format(
          replay.name,
          w.tick,
          table.concat(bad, "; ")
        )
    end
    local events = w.events:drain()
    if opts.on_tick then
      opts.on_tick(w, w.tick, events)
    end
    if i % every == 0 or i == #codes then
      checkpoints[#checkpoints + 1] = { w.tick, sim.hash(w) }
    end
  end
  return { checkpoints = checkpoints, final = sim.hash(w), world = w }
end

-- Runs the replay and compares its checkpoints with the recorded ones.
-- Returns true, or nil and the first difference.
function M.verify(replay, active, opts)
  local result, err = M.run(replay, active, opts)
  if not result then
    return nil, err
  end
  local want = replay.checkpoints
  if #want ~= #result.checkpoints then
    return nil,
      ("replay %s: %d checkpoints recorded, %d computed"):format(
        replay.name,
        #want,
        #result.checkpoints
      )
  end
  for i, cp in ipairs(result.checkpoints) do
    if want[i][1] ~= cp[1] or want[i][2] ~= cp[2] then
      return nil,
        ("replay %s: checkpoint %d differs at tick %d (recorded %s, computed %s)"):format(
          replay.name,
          i,
          cp[1],
          tostring(want[i][2]),
          cp[2]
        )
    end
  end
  return true
end

-- A new recording for live play (src/app). Tagged debug_tuned when the
-- tuning was modified with the F5 overlay.
function M.new_recording(meta)
  return {
    format = M.FORMAT,
    name = meta.name,
    description = meta.description or "recorded in the G1 arena",
    arena = meta.arena,
    seed = meta.seed,
    tuning_id = meta.tuning_id,
    tuning_version = meta.tuning_version,
    debug_tuned = meta.debug_tuned == true,
    checkpoint_every = meta.checkpoint_every or 60,
    frames = {},
    checkpoints = {},
  }
end

-- Appends one tick (its InputFrame and the resulting world) to a recording.
function M.record(rec, frame, w)
  local code = M.encode_frame(frame)
  local last = rec.frames[#rec.frames]
  if last and last[1] == code then
    last[2] = last[2] + 1
  else
    rec.frames[#rec.frames + 1] = { code, 1 }
  end
  if w.tick % rec.checkpoint_every == 0 then
    rec.checkpoints[#rec.checkpoints + 1] = { w.tick, sim.hash(w) }
  end
end

-- Closes a recording: adds the final checkpoint if it is not on the grid.
function M.finish(rec, w)
  local last = rec.checkpoints[#rec.checkpoints]
  if w.tick > 0 and (not last or last[1] ~= w.tick) then
    rec.checkpoints[#rec.checkpoints + 1] = { w.tick, sim.hash(w) }
  end
  return rec
end

return M
