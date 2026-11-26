-- Architecture boundary rules (docs/TECHNICAL_DESIGN.md §4).
-- src/core and src/sim must stay pure: no `love` references and no
-- requires of presentation, input or app modules.

local M = {}

M.PURE_DIRS = { "src/core", "src/sim" }
M.FORBIDDEN_REQUIRE = { "src%.render", "src%.audio", "src%.input", "src%.ui", "src%.app" }

-- Removes comments and string literals so they cannot cause false positives.
function M.strip(source)
  local out = source:gsub("%-%-%[(=*)%[.-%]%1%]", " ")
  out = out:gsub("%-%-[^\n]*", " ")
  out = out:gsub("%[(=*)%[.-%]%1%]", '""')
  out = out:gsub('"[^"\n]*"', '""')
  out = out:gsub("'[^'\n]*'", "''")
  return out
end

-- Returns a list of violation messages for one file's source.
function M.check_source(path, source)
  local problems = {}
  local code = M.strip(source)
  local line = 1
  for text in (code .. "\n"):gmatch("([^\n]*)\n") do
    if text:find("%f[%w_]love%f[^%w_]") then
      problems[#problems + 1] = ("%s:%d: references `love` in a pure module"):format(path, line)
    end
    line = line + 1
  end
  -- Requires are checked against the original text, because the module
  -- names live inside string literals.
  line = 1
  for text in (source .. "\n"):gmatch("([^\n]*)\n") do
    local code_part = text:gsub("%-%-.*$", "")
    for _, pat in ipairs(M.FORBIDDEN_REQUIRE) do
      if code_part:find("require%s*%(?%s*[\"']" .. pat) then
        problems[#problems + 1] = ("%s:%d: forbidden require (%s)"):format(path, line, pat)
      end
    end
    line = line + 1
  end
  return problems
end

return M
