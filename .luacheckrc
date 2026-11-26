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
files["conf.lua"] = { globals = { "love" } }
files["main.lua"] = { globals = { "love" } }
