-- Static audit: every LÖVE graphics resource that LÖVE 11 would otherwise
-- create at the display DPI must state its pixel density explicitly
-- (TECHNICAL_DESIGN §2, "Pixel density").
--
--   newCanvas(..., { dpiscale = 1 })            internal pixel-art resources
--   newFont(size, hinting, 1) / (..., 1)        fonts drawn into the canvas
--   ... -- dpi: native (<reason>)               screen-space resources that
--                                               intentionally follow the display
--
-- The explicit setting must be on the constructor's line. Pure Lua; the CLI
-- is tools/check_dpi.lua and the spec is tests/tools/dpi_audit_spec.lua.

local M = {}

M.CANVAS_CONSTRUCTORS = { "newCanvas" }
M.FONT_CONSTRUCTORS = { "newFont", "setNewFont" }
M.NATIVE_MARKER = "-- dpi: native"

local function strip_comment(line)
  -- Good enough for this codebase: "--" does not occur inside strings in
  -- src/. A false positive here only makes the audit stricter.
  return (line:gsub("%-%-.*$", ""))
end

local function calls(code, name)
  return code:find("%f[%w_]" .. name .. "%s*%(") ~= nil
end

-- Returns a list of problems ("path:line: message") for one source file.
function M.check_source(path, src)
  local problems = {}
  local n = 0
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local code = strip_comment(line)
    local native = line:find(M.NATIVE_MARKER, 1, true) ~= nil
    for _, name in ipairs(M.CANVAS_CONSTRUCTORS) do
      if calls(code, name) and not native and not code:find("dpiscale%s*=%s*1%f[^%w_.]") then
        problems[#problems + 1] = ("%s:%d: %s without explicit { dpiscale = 1 } (or '%s')"):format(
          path,
          n,
          name,
          M.NATIVE_MARKER
        )
      end
    end
    for _, name in ipairs(M.FONT_CONSTRUCTORS) do
      if calls(code, name) and not native and not code:find(",%s*1%s*%)") then
        problems[#problems + 1] = ("%s:%d: %s needs DPI scale 1 as last argument (or '%s')"):format(
          path,
          n,
          name,
          M.NATIVE_MARKER
        )
      end
    end
  end
  return problems
end

return M
