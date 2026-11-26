local serialize = require("src.core.serialize")

local function roundtrip(v)
  local text = serialize.encode(v)
  local out, err = serialize.decode(text)
  assert.is_nil(err)
  return out, text
end

describe("core.serialize", function()
  it("round-trips nested plain data", function()
    local data = {
      version = 1,
      name = 'Eagle "Defense"\n\t\\ end',
      flags = { true, false, true },
      scores = { { name = "AAA", score = 12300 }, { name = "BBB", score = -5 } },
      ratio = 0.1,
      big = 2 ^ 40,
      [10] = "sparse",
      ["with space"] = 1,
      ["end"] = "keyword key",
      bytes = "\0\1\127\200\255",
    }
    assert.are.same(data, (roundtrip(data)))
  end)

  it("is deterministic (sorted keys)", function()
    local a = serialize.encode({ b = 1, a = 2, c = { z = 1, y = 2 } })
    local b = serialize.encode({ c = { y = 2, z = 1 }, a = 2, b = 1 })
    assert.are.equal(a, b)
  end)

  it("preserves floating-point values exactly", function()
    for _, v in ipairs({ 0.1, 1 / 3, -2.5e-12, 123456789.123 }) do
      assert.are.equal(v, roundtrip({ v })[1])
    end
  end)

  it("rejects unsupported values", function()
    assert.has_error(function()
      serialize.encode({ f = function() end })
    end)
    assert.has_error(function()
      serialize.encode({ 0 / 0 })
    end)
    assert.has_error(function()
      serialize.encode({ math.huge })
    end)
    local cyc = {}
    cyc.self = cyc
    assert.has_error(function()
      serialize.encode(cyc)
    end)
  end)

  it("accepts hand-written data with comments and both separators", function()
    local v = serialize.decode([[
      -- level metadata
      return {
        id = 3; name = 'Gate', -- inline comment
        roster = { basic = 14, fast = 4, },
        map = { "B.S", "WFI" },
      }
    ]])
    assert.are.same(
      { id = 3, name = "Gate", roster = { basic = 14, fast = 4 }, map = { "B.S", "WFI" } },
      v
    )
  end)

  describe("never executes input", function()
    local attacks = {
      'return os.execute("echo pwned")',
      "return (function() return 1 end)()",
      "return { x = io.open('/etc/passwd') }",
      "while true do end",
      "return { a = 1 } ; os.exit(1)",
      "return { [[long]] }",
      "return { a = 1 .. 2 }",
      "return {a=1}--[[ block ]]",
      "\27LuaJ bytecode",
      "return { a = 0x10 }",
      "return { a = 1, a = 2 }",
      "return {",
      "return 'unterminated",
    }
    for _, text in ipairs(attacks) do
      it("rejects: " .. text:gsub("%c", "?"), function()
        local v, err = serialize.decode(text)
        assert.is_nil(v)
        assert.is_string(err)
      end)
    end
  end)

  it("rejects nesting beyond MAX_DEPTH", function()
    local deep = ("{"):rep(serialize.MAX_DEPTH + 2) .. ("}"):rep(serialize.MAX_DEPTH + 2)
    local v, err = serialize.decode(deep)
    assert.is_nil(v)
    assert.matches("too deep", err)
  end)

  it("enforces the size limit", function()
    local v, err = serialize.decode("return {}" .. (" "):rep(100), { max_bytes = 50 })
    assert.is_nil(v)
    assert.matches("too large", err)
  end)
end)
