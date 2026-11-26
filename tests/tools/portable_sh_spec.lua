-- tools/lib/portable.sh: the PNG header reader and C-locale printf shared by
-- tools/smoke.sh and tools/hidpi_sim.sh. The helpers run under the system
-- `bash` and `od`, so on macOS this spec exercises /bin/bash 3.2 and BSD od.
--
-- Regression (PR #2, native macOS): BSD od printed an extra empty line, the
-- per-line awk parser turned it into a second "0x0" result, and smoke.sh
-- failed with "unexpected canvas size 640x360\n0x0" after SMOKE OK.

local fs = require("tools.lib.fs")

local LIB = "tools/lib/portable.sh"
local FIX = "tests/fixtures/od/"

-- The pre-fix parser from tools/smoke.sh and tools/hidpi_sim.sh (kept here only
-- to prove that the fixture reproduces the observed failure).
local LEGACY_AWK = [[{print ($1*16777216+$2*65536+$3*256+$4) "x" ($5*16777216+$6*65536+$7*256+$8)}]]

local function q(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function tmpfile(content)
  local path = os.tmpname()
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
  return path
end

-- Runs `script` in bash with the library sourced and stdin from `stdin_path`.
-- Returns stdout (stderr discarded) and the exit code.
local function sh(script, stdin_path, env)
  local cmd = ('%sbash -c %s < %s 2>/dev/null; echo "__exit=$?"'):format(
    env or "",
    q(". " .. LIB .. "; " .. script),
    q(stdin_path or "/dev/null")
  )
  local p = assert(io.popen(cmd))
  local out = p:read("*a")
  p:close()
  local code = tonumber(out:match("__exit=(%d+)\n?$"))
  return (out:gsub("__exit=%d+\n?$", "")), code
end

local function parse(text)
  local path = tmpfile(text)
  local out, code = sh("png_dims_from_od", path)
  os.remove(path)
  return out, code
end

-- od -An -tu1 style text for a list of byte values, 16 per line.
local function od_text(bytes)
  local lines, line = {}, {}
  for i, b in ipairs(bytes) do
    line[#line + 1] = ("%4d"):format(b)
    if i % 16 == 0 then
      lines[#lines + 1] = table.concat(line)
      line = {}
    end
  end
  if #line > 0 then
    lines[#lines + 1] = table.concat(line)
  end
  return table.concat(lines, "\n") .. "\n"
end

local SIG_IHDR = { 137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82 }

local function header(w_bytes, h_bytes)
  local t = {}
  for _, list in ipairs({ SIG_IHDR, w_bytes, h_bytes }) do
    for _, b in ipairs(list) do
      t[#t + 1] = b
    end
  end
  return t
end

local CANVAS = header({ 0, 0, 2, 128 }, { 0, 0, 1, 104 }) -- 640x360

local function with(bytes, i, v)
  local t = { unpack(bytes) }
  t[i] = v
  return t
end

local function bytes_string(bytes)
  local chars = {}
  for i, b in ipairs(bytes) do
    chars[i] = string.char(b)
  end
  return table.concat(chars)
end

describe("tools/lib/portable.sh", function()
  describe("png_dims_from_od (od output parser)", function()
    it("reads 640x360 from real GNU od output", function()
      local out, code = sh("png_dims_from_od", FIX .. "gnu-canvas-640x360.txt")
      assert.are.equal(0, code)
      assert.are.equal("640x360\n", out)
    end)

    it("reads 640x360 from real BSD/macOS od output (padding + trailing empty line)", function()
      local text = fs.read(FIX .. "bsd-macos-canvas-640x360.txt")
      assert.is_truthy(
        text:find(" +\n\n$"),
        "fixture must keep the BSD padding and empty last line"
      )
      local out, code = sh("png_dims_from_od", FIX .. "bsd-macos-canvas-640x360.txt")
      assert.are.equal(0, code)
      assert.are.equal("640x360\n", out) -- exactly one line
    end)

    it(
      "regression: the BSD fixture reproduces the observed native failure with the old parser",
      function()
        local out = sh("awk " .. q(LEGACY_AWK), FIX .. "bsd-macos-ihdr-dims-observed.txt")
        -- native build/native-check.log: "unexpected canvas size 640x360\n0x0"
        assert.are.equal("640x360\n0x0\n", out)
        -- The same 8 bytes as GNU od prints them gave one line, so Linux passed.
        local gnu = tmpfile("   0   0   2 128   0   0   1 104\n")
        assert.are.equal("640x360\n", (sh("awk " .. q(LEGACY_AWK), gnu)))
        os.remove(gnu)
      end
    )

    it("ignores harmless whitespace and blank lines", function()
      local one_line = table.concat(CANVAS, " ")
      local variants = {
        od_text(CANVAS),
        one_line .. "\n",
        "\n\n" .. one_line .. "\n\n\n",
        "   \n\t" .. table.concat(CANVAS, "\t") .. "   \n \n",
        table.concat(CANVAS, "\n") .. "\n",
        one_line, -- no final newline
      }
      for i, text in ipairs(variants) do
        local out, code = parse(text)
        assert.are.equal(0, code, "variant " .. i)
        assert.are.equal("640x360\n", out, "variant " .. i)
      end
    end)

    it("reads other sizes (the 640x360 requirement stays in the callers)", function()
      assert.are.equal("1280x720\n", (parse(od_text(header({ 0, 0, 5, 0 }, { 0, 0, 2, 208 })))))
      assert.are.equal("1x1\n", (parse(od_text(header({ 0, 0, 0, 1 }, { 0, 0, 0, 1 })))))
      assert.are.equal(
        "2147483647x65536\n",
        (parse(od_text(header({ 127, 255, 255, 255 }, { 0, 1, 0, 0 }))))
      )
    end)

    it("rejects missing, truncated or malformed input", function()
      local truncated = { unpack(CANVAS, 1, 23) }
      local extra = { unpack(CANVAS) }
      extra[25] = 0
      local cases = {
        empty = "",
        blank_lines_only = "\n\n   \n",
        dims_only_8_bytes = fs.read(FIX .. "bsd-macos-ihdr-dims-observed.txt"),
        truncated_23 = od_text(truncated),
        extra_25 = od_text(extra),
        byte_over_255 = od_text(with(CANVAS, 19, 256)),
        negative = od_text(CANVAS):gsub(" 128", "-128", 1),
        hex_token = od_text(CANVAS):gsub(" 128", "  80h", 1),
        address_column = "0000000 " .. od_text(CANVAS),
        carriage_return = od_text(CANVAS):gsub("\n", "\r\n"),
        not_png_signature = od_text(with(CANVAS, 1, 136)),
        not_ihdr_type = od_text(with(CANVAS, 13, 74)),
        ihdr_length_not_13 = od_text(with(CANVAS, 12, 14)),
        width_zero = od_text(header({ 0, 0, 0, 0 }, { 0, 0, 1, 104 })),
        height_zero = od_text(header({ 0, 0, 2, 128 }, { 0, 0, 0, 0 })),
        width_high_bit = od_text(header({ 128, 0, 2, 128 }, { 0, 0, 1, 104 })),
        height_high_bit = od_text(header({ 0, 0, 2, 128 }, { 255, 0, 1, 104 })),
      }
      for name, text in pairs(cases) do
        local out, code = parse(text)
        assert.are.equal(1, code, name)
        assert.are.equal("", out, name)
      end
    end)
  end)

  describe("png_dims (files, with this system's od)", function()
    local function dims_of(content)
      local path = tmpfile(content)
      local out, code = sh("png_dims " .. q(path))
      os.remove(path)
      return out, code
    end

    it("reads a PNG header followed by more data", function()
      local out, code = dims_of(bytes_string(CANVAS) .. string.rep("\0", 100))
      assert.are.equal(0, code)
      assert.are.equal("640x360\n", out)
    end)

    it("rejects truncated, empty, non-PNG, missing and non-regular paths", function()
      for name, content in pairs({
        truncated = bytes_string({ unpack(CANVAS, 1, 20) }),
        empty = "",
        text = "640x360 is not a PNG at all, really\n",
      }) do
        local out, code = dims_of(content)
        assert.are.equal(1, code, name)
        assert.are.equal("", out, name)
      end
      local missing = os.tmpname()
      os.remove(missing)
      assert.are.same({ "", 1 }, { sh("png_dims " .. q(missing)) })
      assert.are.same({ "", 1 }, { sh("png_dims tests") })
    end)
  end)

  describe("printf_c", function()
    local PL = "LANG=pl_PL.UTF-8 LC_ALL=pl_PL.UTF-8 "

    it(
      "formats with '.' under a decimal-comma locale and leaves the caller's locale alone",
      function()
        local out, code =
          sh([[printf_c 'default_dpi=%.2f probe=%.2f' 1.25 2; echo " caller=$LC_ALL"]], nil, PL)
        assert.are.equal(0, code)
        assert.are.equal("default_dpi=1.25 probe=2.00 caller=pl_PL.UTF-8\n", out)
      end
    )
    -- The locale only bites where pl_PL is installed (macOS has it; minimal
    -- Linux containers fall back to C, where this test cannot fail).
  end)

  describe("callers", function()
    it(
      "smoke.sh and hidpi_sim.sh use the shared reader and keep the strict 640x360 check",
      function()
        local smoke, hidpi = fs.read("tools/smoke.sh"), fs.read("tools/hidpi_sim.sh")
        for _, src in ipairs({ smoke, hidpi }) do
          assert.is_truthy(src:find('. "$ROOT/tools/lib/portable.sh"', 1, true))
          assert.is_falsy(src:find("-j16 -N8", 1, true))
          assert.is_truthy(src:find('dims="$(png_dims ', 1, true))
        end
        assert.is_truthy(smoke:find('[[ "$dims" == "640x360" ]] ||', 1, true))
        assert.is_truthy(hidpi:find('[[ "$dims" != "640x360" ]]', 1, true))
        assert.is_truthy(hidpi:find("expected_probe=\"$(printf_c 'default_dpi=%.2f", 1, true))
      end
    )
  end)
end)
