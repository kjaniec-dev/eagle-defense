-- Fail-closed rules for review evidence (review P2-4).
-- Pure functions over text and file listings, so they are unit-testable.
-- The CLI wrapper is tools/evidence_gate.lua.

local M = {}

-- Paths whose content affects the build or the checks. Ignored files
-- inside them would be used by the checks without being part of the
-- commit, so they make the tree "not clean" for final evidence.
M.SOURCE_PATHS = {
  "main.lua",
  "conf.lua",
  "src/",
  "config/",
  "levels/",
  "assets/",
  "tests/",
  "tools/",
  "docs/",
  "Makefile",
  ".busted",
  ".luacheckrc",
  "stylua.toml",
}

M.STEPS = { "fmt-check", "lint", "test", "validate", "smoke", "hidpi-sim", "love" }

M.REQUIRED_FILES = {
  "MANIFEST.txt",
  "SUMMARY.md",
  "diff.patch",
  "commits.txt",
  "checks/SUMMARY.txt",
  "build/eagle-defense.love",
  "build/eagle-defense.love.sha256",
  "build/eagle-defense.love.commit",
  "screenshots/smoke.png",
  "screenshots/smoke-window.png",
  "screenshots/smoke.log",
  -- SIMULATED HiDPI harness (tools/hidpi_sim.sh): both modes at DPI 2.
  "hidpi-sim/integer-dpi2.log",
  "hidpi-sim/fit-dpi2.log",
}

local function in_source(path)
  for _, p in ipairs(M.SOURCE_PATHS) do
    if p:sub(-1) == "/" then
      -- Directory: anything below it, or the directory itself.
      if path:sub(1, #p) == p or path == p:sub(1, -2) then
        return true
      end
    elseif path == p then
      -- File: exact match only (main.lua.orig is not main.lua).
      return true
    end
  end
  return false
end

-- `porcelain` is the output of
--   git status --porcelain=v1 --untracked-files=all --ignored
-- Returns a list of problems. An empty list means the tree is clean.
function M.tree_problems(porcelain)
  local problems = {}
  for line in (porcelain or ""):gmatch("[^\n]+") do
    local status, path = line:sub(1, 2), line:sub(4)
    if status == "!!" then
      if in_source(path) then
        problems[#problems + 1] = "ignored file inside a source path: " .. path
      end
    elseif status == "??" then
      problems[#problems + 1] = "untracked file: " .. path
    else
      problems[#problems + 1] = "uncommitted change: " .. line
    end
  end
  return problems
end

-- Verifies an assembled package.
--   files:   { [relative_path] = size_in_bytes }
--   texts:   { summary = "...", love_commit = "...", smoke_logs = { [path] = text } }
--   sha:     the expected full commit SHA
function M.package_problems(files, texts, sha)
  local problems = {}
  for _, f in ipairs(M.REQUIRED_FILES) do
    if not files[f] then
      problems[#problems + 1] = "missing required file: " .. f
    elseif files[f] == 0 then
      problems[#problems + 1] = "empty required file: " .. f
    end
  end
  for _, step in ipairs(M.STEPS) do
    local f = "checks/" .. step .. ".txt"
    if not files[f] then
      problems[#problems + 1] = "missing check output: " .. f
    end
  end

  local summary = texts.summary or ""
  for _, step in ipairs(M.STEPS) do
    if not summary:find("PASS " .. step .. "\n", 1, true) then
      problems[#problems + 1] = "check did not pass: " .. step
    end
  end
  if summary:find("FAIL", 1, true) then
    problems[#problems + 1] = "summary contains FAIL"
  end

  local commit = (texts.love_commit or ""):gsub("%s+$", "")
  if commit ~= sha then
    problems[#problems + 1] = ("build commit '%s' does not match evidence SHA '%s'"):format(
      commit,
      tostring(sha)
    )
  end

  local logs = 0
  for path, text in pairs(texts.smoke_logs or {}) do
    logs = logs + 1
    if not text:find("\nSMOKE OK ", 1, true) and text:sub(1, 9) ~= "SMOKE OK " then
      problems[#problems + 1] = "smoke log without SMOKE OK: " .. path
    end
    if text:find("SMOKE FAIL", 1, true) then
      problems[#problems + 1] = "smoke log contains SMOKE FAIL: " .. path
    end
  end
  if logs == 0 then
    problems[#problems + 1] = "no smoke logs"
  end

  table.sort(problems)
  return problems
end

return M
