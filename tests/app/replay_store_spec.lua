-- F8 replay storage (review P2-1): never overwrites an earlier file, from
-- this or a previous session, and reports write failures.

local replay_store = require("src.app.replay_store")
local serialize = require("src.core.serialize")

-- In-memory stand-in for love.filesystem (dot-call API).
local function fake_fs(opts)
  opts = opts or {}
  local fs = { files = {}, writes = {} }
  for name, data in pairs(opts.existing or {}) do
    fs.files[name] = data
  end
  fs.createDirectory = function()
    return opts.mkdir ~= false
  end
  fs.getInfo = function(name)
    return fs.files[name] and { type = "file" } or nil
  end
  fs.write = function(name, data)
    fs.writes[#fs.writes + 1] = name
    if opts.write_error then
      return false, opts.write_error
    end
    fs.files[name] = data
    return true
  end
  fs.getSaveDirectory = function()
    return "/save"
  end
  return fs
end

local function rec(tick)
  return {
    format = 1,
    name = "arena",
    checkpoints = tick > 0 and { { tick, "0000abcd" } } or {},
    frames = {},
  }
end

describe("app.replay_store", function()
  it("writes the serialized recording and returns its full path", function()
    local fs = fake_fs()
    local path = replay_store.save(fs, rec(150), "20261127-101500")
    assert.are.equal("/save/replays/arena-20261127-101500-t150.lua", path)
    local data = fs.files["replays/arena-20261127-101500-t150.lua"]
    assert.are.same(rec(150), serialize.decode(data))
  end)

  it("never overwrites a file from an earlier session with the same name", function()
    local old = "replays/arena-20261127-101500-t150.lua"
    local fs = fake_fs({ existing = { [old] = "earlier session" } })
    local p1 = replay_store.save(fs, rec(150), "20261127-101500")
    local p2 = replay_store.save(fs, rec(150), "20261127-101500")
    assert.are.equal("/save/replays/arena-20261127-101500-t150-2.lua", p1)
    assert.are.equal("/save/replays/arena-20261127-101500-t150-3.lua", p2)
    assert.are.equal("earlier session", fs.files[old])
    for _, name in ipairs(fs.writes) do
      assert.are_not.equal(old, name)
    end
  end)

  it("names a tick-0 recording t0", function()
    local fs = fake_fs()
    assert.are.equal("/save/replays/arena-s-t0.lua", replay_store.save(fs, rec(0), "s"))
  end)

  it("returns nil and the reason when the write fails", function()
    local fs = fake_fs({ write_error = "disk full" })
    local path, err = replay_store.save(fs, rec(60), "s")
    assert.is_nil(path)
    assert.are.equal("cannot write replays/arena-s-t60.lua: disk full", err)
  end)

  it("returns nil when the directory cannot be created", function()
    local path, err = replay_store.save(fake_fs({ mkdir = false }), rec(60), "s")
    assert.is_nil(path)
    assert.matches("cannot create the replays directory", err)
  end)

  it("gives up instead of overwriting when every candidate name exists", function()
    local fs = fake_fs()
    fs.getInfo = function()
      return { type = "file" }
    end
    local path, err = replay_store.save(fs, rec(60), "s")
    assert.is_nil(path)
    assert.matches("no free file name", err)
    assert.are.equal(0, #fs.writes)
  end)
end)
