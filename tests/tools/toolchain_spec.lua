-- Per-platform toolchain isolation: .rocks/<platform>/ and .tools/<platform>/.
-- A macOS host and a Linux container (Docker SBX) share one checkout, so
-- each platform must resolve to its own directories, Makefile and bootstrap
-- must agree on them, and the pinned versions and checksums must not change.

local ROOT = io.popen("pwd"):read("*l")

-- Runs a shell command and returns its combined output and exit code.
local function run(cmd)
  local p = assert(io.popen("(" .. cmd .. ') 2>&1; echo "__exit=$?"'))
  local out = p:read("*a")
  p:close()
  local code = tonumber(out:match("__exit=(%d+)%s*$"))
  return out:gsub("__exit=%d+%s*$", ""), code
end

local function kv(out)
  local t = {}
  for k, v in out:gmatch("([%w_]+)=([^\n]*)") do
    t[k] = v
  end
  return t
end

local function mktemp_dir()
  local dir = os.tmpname()
  os.remove(dir)
  assert(os.execute(("mkdir -p '%s'"):format(dir)))
  return dir
end

-- A directory holding a fake `uname` that reports the given OS and machine.
local function fake_uname(os_name, machine)
  local dir = mktemp_dir()
  local f = assert(io.open(dir .. "/uname", "w"))
  f:write(([[#!/bin/sh
case "$1" in
  -s) echo %s ;;
  -m) echo %s ;;
  *) echo "%s %s" ;;
esac
]]):format(os_name, machine, os_name, machine))
  f:close()
  assert(os.execute(("chmod +x '%s/uname'"):format(dir)))
  return dir
end

local function with_uname(os_name, machine, cmd)
  local dir = fake_uname(os_name, machine)
  local out, code = run(("PATH='%s':\"$PATH\" %s"):format(dir, cmd))
  os.execute(("rm -rf '%s'"):format(dir))
  return out, code
end

-- G0 pins. Changing any of them is a dependency change that needs approval.
local PINS = {
  {
    "Linux",
    "x86_64",
    "linux-x86_64",
    "stylua-linux-x86_64.zip",
    "a485f72bbfa22e4642e77a84b5edc2611a5cab7477b34e2e709dd8f78e919895",
  },
  {
    "Linux",
    "aarch64",
    "linux-arm64",
    "stylua-linux-aarch64.zip",
    "8e67539e5fdf7a81cd03cf592b0df18d3bb96ee17a5ea5d9bf67b86387b903b0",
  },
  {
    "Darwin",
    "arm64",
    "darwin-arm64",
    "stylua-macos-aarch64.zip",
    "dab9b66d340ca5ffc8225211f1dcf89b84783e09b8cbec8c518497eba81f3c42",
  },
  {
    "Darwin",
    "x86_64",
    "darwin-x86_64",
    "stylua-macos-x86_64.zip",
    "90779aa873837b2dff8eb3361bd27950303914c24265a59cae0a0d0629d71585",
  },
}

describe("toolchain isolation", function()
  describe("platform key (tools/platform.sh)", function()
    it("normalizes uname values to <os>-<arch>", function()
      local cases = {
        { "Darwin", "arm64", "darwin-arm64" },
        { "Darwin", "x86_64", "darwin-x86_64" },
        { "Linux", "aarch64", "linux-arm64" },
        { "Linux", "arm64", "linux-arm64" },
        { "Linux", "x86_64", "linux-x86_64" },
        { "Linux", "amd64", "linux-x86_64" },
      }
      for _, c in ipairs(cases) do
        local out, code = run(("./tools/platform.sh %s %s"):format(c[1], c[2]))
        assert.are.equal(0, code, out)
        assert.are.equal(c[3] .. "\n", out)
      end
    end)

    it("gives an Apple-silicon Mac and its Linux container different keys", function()
      local mac = run("./tools/platform.sh Darwin arm64")
      local sbx = run("./tools/platform.sh Linux aarch64")
      assert.are_not.equal(mac, sbx)
    end)

    it("rejects values that cannot form a safe directory name", function()
      local _, code = run("./tools/platform.sh 'Lin ux' x86_64")
      assert.are_not.equal(0, code)
      _, code = run("./tools/platform.sh Linux '../x'")
      assert.are_not.equal(0, code)
    end)
  end)

  describe("Makefile and bootstrap", function()
    it("agree on the toolchain directories of this machine", function()
      local mk, c1 = run("make --no-print-directory -s toolchain")
      local bs, c2 = run("./tools/bootstrap.sh --print-plan")
      assert.are.equal(0, c1, mk)
      assert.are.equal(0, c2, bs)
      mk, bs = kv(mk), kv(bs)
      local key = run("./tools/platform.sh"):gsub("\n", "")
      assert.are.equal(key, mk.platform)
      assert.are.equal(key, bs.platform)
      assert.are.equal(ROOT .. "/.rocks/" .. key, mk.rocks)
      assert.are.equal(ROOT .. "/.tools/" .. key, mk.tools)
      assert.are.equal(mk.rocks, bs.rocks)
      assert.are.equal(mk.tools, bs.tools)
    end)

    it("route every tool invocation of another platform into its own directories", function()
      local out, code =
        with_uname("Darwin", "arm64", "make --no-print-directory -n fmt-check lint test")
      assert.are.equal(0, code, out)
      assert.matches(ROOT .. "/.tools/darwin-arm64/stylua --check", out, 1, true)
      assert.matches(ROOT .. "/.rocks/darwin-arm64/bin/luacheck", out, 1, true)
      assert.matches(ROOT .. "/.rocks/darwin-arm64/bin/busted", out, 1, true)
      -- Nothing may point at the shared legacy locations or at this machine's tree.
      local key = run("./tools/platform.sh"):gsub("\n", "")
      if key ~= "darwin-arm64" then
        assert.is_nil(out:find("/.rocks/" .. key, 1, true))
        assert.is_nil(out:find("/.tools/" .. key, 1, true))
      end
      assert.is_nil(out:find("/.rocks/bin/", 1, true))
      assert.is_nil(out:find("/.tools/stylua", 1, true))
    end)

    it("point the Lua module search paths (incl. C modules) at the platform tree", function()
      local out, code = with_uname("Darwin", "arm64", "make --no-print-directory -s toolchain")
      assert.are.equal(0, code, out)
      local t = kv(out)
      assert.matches(ROOT .. "/.rocks/darwin-arm64/share/lua/5.1/?.lua", t.lua_path, 1, true)
      assert.matches(ROOT .. "/.rocks/darwin-arm64/lib/lua/5.1/?.so", t.lua_cpath, 1, true)
      assert.is_nil(t.lua_cpath:find("/.rocks/lib/", 1, true))
    end)

    it("fails with a bootstrap hint when this platform is not installed", function()
      local out, code = with_uname("Linux", "riscv64", "make --no-print-directory -s fmt-check")
      assert.are_not.equal(0, code)
      assert.matches("toolchain for linux-riscv64 is not installed", out, 1, true)
      assert.matches("make bootstrap", out, 1, true)
    end)
  end)

  describe("pinned versions and checksums", function()
    it("keep the G0 tool versions", function()
      local plan = kv((run("./tools/bootstrap.sh --print-plan")))
      assert.are.equal("2.3.0-1", plan.busted)
      assert.are.equal("1.2.0-1", plan.luacheck)
      assert.are.equal("2.6.0", plan.stylua)
    end)

    it("keep the G0 StyLua asset and SHA-256 for each supported platform", function()
      for _, p in ipairs(PINS) do
        local out, code = with_uname(p[1], p[2], "./tools/bootstrap.sh --print-plan")
        assert.are.equal(0, code, out)
        local plan = kv(out)
        assert.are.equal(p[3], plan.platform)
        assert.are.equal(ROOT .. "/.tools/" .. p[3], plan.tools)
        assert.are.equal(p[4], plan.stylua_asset)
        assert.are.equal(p[5], plan.stylua_sha256)
      end
    end)

    it("refuses a platform without a pinned StyLua checksum", function()
      local out, code = with_uname("Linux", "riscv64", "./tools/bootstrap.sh --print-plan")
      assert.are_not.equal(0, code)
      assert.matches("unsupported platform for StyLua: linux-riscv64", out, 1, true)
    end)
  end)

  describe("legacy flat layout", function()
    local tmp

    before_each(function()
      tmp = mktemp_dir()
      assert(os.execute(([[
        mkdir -p '%s/tools' && cp '%s/tools/bootstrap.sh' '%s/tools/platform.sh' '%s/tools/'
      ]]):format(tmp, ROOT, ROOT, tmp)))
    end)

    after_each(function()
      os.execute(("rm -rf '%s'"):format(tmp))
    end)

    it("is reported but never deleted (it may belong to another machine)", function()
      assert(
        os.execute(
          ("mkdir -p '%s/.rocks/bin' '%s/.tools' && touch '%s/.tools/stylua'"):format(tmp, tmp, tmp)
        )
      )
      local out, code = run(("'%s/tools/bootstrap.sh' --print-plan"):format(tmp))
      assert.are.equal(0, code, out)
      assert.matches("legacy unpartitioned toolchain found", out, 1, true)
      assert.matches(".rocks/bin", out, 1, true)
      assert.matches(".tools/stylua", out, 1, true)
      local _, still =
        run(("test -d '%s/.rocks/bin' && test -f '%s/.tools/stylua'"):format(tmp, tmp))
      assert.are.equal(0, still)
    end)

    it("is not mentioned when only per-platform directories exist", function()
      assert(
        os.execute(
          ("mkdir -p '%s/.rocks/linux-arm64/bin' '%s/.tools/darwin-arm64'"):format(tmp, tmp)
        )
      )
      local out, code = run(("'%s/tools/bootstrap.sh' --print-plan"):format(tmp))
      assert.are.equal(0, code, out)
      assert.is_nil(out:find("legacy", 1, true))
    end)
  end)
end)
