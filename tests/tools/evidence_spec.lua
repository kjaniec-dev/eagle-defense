local evidence = require("tools.lib.evidence")

local SHA = "0123456789abcdef0123456789abcdef01234567"

local function complete_package()
  local files = {}
  for _, f in ipairs(evidence.REQUIRED_FILES) do
    files[f] = 10
  end
  local summary = {}
  for _, s in ipairs(evidence.STEPS) do
    files["checks/" .. s .. ".txt"] = 10
    summary[#summary + 1] = "PASS " .. s
  end
  return files,
    {
      summary = table.concat(summary, "\n") .. "\n",
      love_commit = SHA .. "\n",
      smoke_logs = { ["screenshots/smoke.log"] = "SMOKE start ticks=120\nSMOKE OK ticks=120\n" },
    }
end

describe("evidence rules (review P2-4)", function()
  describe("clean tree", function()
    it("accepts a clean tree with ignored tooling outside source paths", function()
      local porcelain = "!! .rocks/\n!! .tools/\n!! build/\n!! dist/\n!! evidence/\n!! .serena/\n"
      assert.are.same({}, evidence.tree_problems(porcelain))
    end)

    it(
      "accepts per-platform toolchain directories (.rocks/<platform>/, .tools/<platform>/)",
      function()
        local porcelain =
          "!! .rocks/darwin-arm64/\n!! .rocks/linux-arm64/\n!! .tools/darwin-arm64/stylua\n"
        assert.are.same({}, evidence.tree_problems(porcelain))
      end
    )

    it("rejects untracked files", function()
      local p = evidence.tree_problems("?? src/new_module.lua\n")
      assert.are.equal(1, #p)
      assert.matches("untracked", p[1])
    end)

    it("rejects modified and staged files", function()
      assert.are.equal(2, #evidence.tree_problems(" M src/core/loop.lua\nA  tools/x.sh\n"))
    end)

    it("rejects ignored files under docs/ (evidence copies docs/evidence/SUMMARY.md)", function()
      assert.are.equal(1, #evidence.tree_problems("!! docs/evidence/SUMMARY.md\n"))
    end)

    it("rejects ignored files inside source paths", function()
      local p = evidence.tree_problems("!! src/core/debug.love\n!! main.lua.orig\n")
      assert.are.equal(1, #p) -- main.lua.orig is not main.lua
      assert.matches("ignored file inside a source path", p[1])
    end)
  end)

  describe("package completeness", function()
    it("accepts a complete package", function()
      local files, texts = complete_package()
      assert.are.same({}, evidence.package_problems(files, texts, SHA))
    end)

    it("rejects a missing or empty mandatory file", function()
      local files, texts = complete_package()
      files["screenshots/smoke-window.png"] = nil
      files["diff.patch"] = 0
      local p = evidence.package_problems(files, texts, SHA)
      assert.are.equal(2, #p)
    end)

    it("rejects a failed or missing check", function()
      local files, texts = complete_package()
      texts.summary = texts.summary:gsub("PASS smoke", "FAIL smoke")
      local p = evidence.package_problems(files, texts, SHA)
      assert.is_true(#p >= 2) -- smoke did not pass, and the summary contains FAIL
    end)

    it("rejects a build from a different commit or a dirty worktree", function()
      local files, texts = complete_package()
      texts.love_commit = SHA .. "-dirty-worktree"
      assert.are.equal(1, #evidence.package_problems(files, texts, SHA))
      texts.love_commit = ("f"):rep(40)
      assert.are.equal(1, #evidence.package_problems(files, texts, SHA))
    end)

    it("rejects smoke logs without SMOKE OK, or with SMOKE FAIL", function()
      local files, texts = complete_package()
      texts.smoke_logs["screenshots/smoke-800x600.log"] = "SMOKE FAIL mismatches=3\n"
      local p = evidence.package_problems(files, texts, SHA)
      assert.are.equal(2, #p)
    end)

    it("rejects a package without smoke logs", function()
      local files, texts = complete_package()
      texts.smoke_logs = {}
      assert.are.equal(1, #evidence.package_problems(files, texts, SHA))
    end)
  end)

  describe("integration with git (temporary repository)", function()
    local root = io.popen("pwd"):read("*l")
    local tmp

    local function sh(cmd)
      local ok = os.execute(cmd .. " >/dev/null 2>&1")
      return ok == true or ok == 0
    end

    before_each(function()
      tmp = os.tmpname()
      os.remove(tmp)
      assert(sh(("mkdir -p '%s'"):format(tmp)))
      -- A minimal fixture repository that holds the *current* tool versions.
      assert(sh(([[
        cd '%s' && git init -q . && git config user.email t@t && git config user.name t &&
        mkdir -p src tools/lib && echo 'return 1' > main.lua && echo 'return 2' > src/a.lua &&
        cp '%s/tools/build_love.sh' '%s/tools/evidence_gate.lua' tools/ &&
        cp '%s/tools/lib/evidence.lua' '%s/tools/lib/fs.lua' tools/lib/ &&
        printf 'dist/\n*.love\n' > .gitignore &&
        git add -A && git commit -q -m fixture
      ]]):format(tmp, root, root, root, root)))
    end)

    after_each(function()
      sh(("rm -rf '%s'"):format(tmp))
    end)

    local function gate_pre()
      return sh(("cd '%s' && luajit tools/evidence_gate.lua pre"):format(tmp))
    end

    it("the pre gate passes on a clean checkout", function()
      assert.is_true(gate_pre())
    end)

    it("the pre gate fails on an untracked source file", function()
      assert(sh(("echo x > '%s/src/untracked.lua'"):format(tmp)))
      assert.is_false(gate_pre())
    end)

    it("the pre gate fails on an ignored file inside src/", function()
      assert(sh(("echo x > '%s/src/sneaky.love'"):format(tmp)))
      assert.is_false(gate_pre())
    end)

    it("a commit build excludes untracked files and records the exact SHA", function()
      assert(sh(("echo 'return 3' > '%s/src/untracked.lua'"):format(tmp)))
      assert(sh(("cd '%s' && ./tools/build_love.sh --commit"):format(tmp)))
      local list = io.popen(("unzip -Z1 '%s/dist/eagle-defense.love'"):format(tmp)):read("*a")
      assert.matches("src/a.lua", list)
      assert.is_nil(list:find("untracked", 1, true))
      local head = io.popen(("cd '%s' && git rev-parse HEAD"):format(tmp)):read("*l")
      local recorded = io.open(tmp .. "/dist/eagle-defense.love.commit"):read("*l")
      assert.are.equal(head, recorded)
    end)

    it("a worktree build includes untracked files and is marked dirty", function()
      assert(sh(("echo 'return 3' > '%s/src/untracked.lua'"):format(tmp)))
      assert(sh(("cd '%s' && ./tools/build_love.sh --worktree"):format(tmp)))
      local list = io.popen(("unzip -Z1 '%s/dist/eagle-defense.love'"):format(tmp)):read("*a")
      assert.matches("src/untracked.lua", list)
      local recorded = io.open(tmp .. "/dist/eagle-defense.love.commit"):read("*l")
      assert.matches("%-dirty%-worktree$", recorded)
    end)
  end)
end)
