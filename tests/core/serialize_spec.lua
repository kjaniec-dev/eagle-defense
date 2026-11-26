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

  describe("canonical output (review P2-3)", function()
    it("encodes sparse tables independently of insertion history", function()
      local a = { 1, 2, nil, 4 }
      local b = {}
      b[4] = 4
      b[2] = 2
      b[1] = 1
      local c = {}
      for i = 1, 4 do
        c[i] = i
      end
      c[3] = nil -- #c may now report 4 or 2; output must not depend on it
      local ea, eb, ec = serialize.encode(a), serialize.encode(b), serialize.encode(c)
      assert.are.equal(ea, eb)
      assert.are.equal(ea, ec)
      assert.matches("%[4%] = 4", ea)
      assert.are.same({ 1, 2, [4] = 4 }, serialize.decode(ea))
    end)

    it("encodes a table whose array part starts after a hole with explicit keys", function()
      local t = { [2] = "b", [3] = "c" }
      local out = serialize.encode(t)
      assert.matches('%[2%] = "b"', out)
      assert.are.same(t, serialize.decode(out))
    end)

    it("is identical across independent LuaJIT processes", function()
      local script = os.tmpname()
      local f = assert(io.open(script, "w"))
      f:write([[
        package.path = "./?.lua;" .. package.path
        local s = require("src.core.serialize")
        local t = {}
        if arg[1] == "reverse" then
          for i = 50, 1, -1 do t["k" .. i] = i end
          t[7] = "x"; t[1] = "a"; t[2] = "b"
        else
          t[1] = "a"; t[2] = "b"; t[7] = "x"
          for i = 1, 50 do t["k" .. i] = i end
        end
        io.write(s.encode(t))
      ]])
      f:close()
      local function run(mode)
        local p = assert(io.popen("luajit " .. script .. " " .. mode))
        local out = p:read("*a")
        p:close()
        return out
      end
      local forward, reverse = run("forward"), run("reverse")
      os.remove(script)
      assert.is_true(#forward > 0)
      assert.are.equal(forward, reverse)
    end)
  end)

  describe("strict decoding (review P2-3)", function()
    local cases = {
      ["nil keyed value"] = "return { a = nil }",
      ["nil positional value"] = "return { 1, nil, 3 }",
      ["duplicate key hidden by nil"] = "return { a = nil, a = 1 }",
      ["positional then explicit [1]"] = 'return { "x", [1] = "y" }',
      ["explicit [1] then positional"] = 'return { [1] = "y", "x" }',
      ["same numeric key as int and float"] = "return { [1] = 1, [1.0] = 2 }",
    }
    for name, text in pairs(cases) do
      it("rejects " .. name, function()
        local v, err = serialize.decode(text)
        assert.is_nil(v)
        assert.is_string(err)
      end)
    end
  end)

  describe("nesting limit is identical for encode and decode (review P2-3)", function()
    local function nested(levels)
      local root = {}
      local cur = root
      for _ = 2, levels do
        local child = {}
        cur.c = child
        cur = child
      end
      return root
    end

    it("accepts exactly MAX_DEPTH levels in both directions", function()
      local text = serialize.encode(nested(serialize.MAX_DEPTH))
      local v, err = serialize.decode(text)
      assert.is_nil(err)
      assert.is_table(v)
    end)

    it("rejects MAX_DEPTH + 1 levels in both directions", function()
      assert.has_error(function()
        serialize.encode(nested(serialize.MAX_DEPTH + 1))
      end)
      local deep = ("{"):rep(serialize.MAX_DEPTH + 1) .. ("}"):rep(serialize.MAX_DEPTH + 1)
      local v, err = serialize.decode(deep)
      assert.is_nil(v)
      assert.matches("too deep", err)
      local ok = ("{"):rep(serialize.MAX_DEPTH) .. ("}"):rep(serialize.MAX_DEPTH)
      assert.is_table(serialize.decode(ok))
    end)
  end)

  it("enforces the size limit", function()
    local v, err = serialize.decode("return {}" .. (" "):rep(100), { max_bytes = 50 })
    assert.is_nil(v)
    assert.matches("too large", err)
  end)
end)
