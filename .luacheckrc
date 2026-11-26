-- luacheck configuration. Gameplay-pure modules (src/core, src/sim) must not
-- see the `love` global; everything else may.
std = "luajit+love"
max_line_length = 100
codes = true
self = false -- unused implicit `self` in methods is fine

exclude_files = { ".rocks/", ".tools/", ".worktrees/", "build/", "dist/" }

files["src/core/"] = { std = "luajit" }
files["src/sim/"] = { std = "luajit" }
files["tools/"] = { std = "luajit" }
files["tests/"] = { std = "luajit+busted" }
-- Golden replays: canonical data written by tools/update_goldens.lua.
files["tests/fixtures/replays/"] = { max_line_length = false }
files["conf.lua"] = { globals = { "love" } }
files["main.lua"] = { globals = { "love" } }
-- HiDPI simulation entry point: a LÖVE game directory that wraps
-- love.graphics constructors (tools/hidpi_sim.sh).
files["tools/hidpi_sim/"] = { std = "luajit+love", globals = { "love" } }
