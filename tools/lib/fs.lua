-- Minimal filesystem helpers for tools (POSIX `find`, which works on Linux and macOS).

local M = {}

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Lists regular files under `dir`, recursively and sorted. Returns {} if
-- the directory is missing.
function M.list_files(dir, pattern)
  local cmd = "find " .. shell_quote(dir) .. " -type f 2>/dev/null"
  local p = assert(io.popen(cmd))
  local files = {}
  for line in p:lines() do
    if not pattern or line:match(pattern) then
      files[#files + 1] = line
    end
  end
  p:close()
  table.sort(files)
  return files
end

function M.read(path)
  local f, err = io.open(path, "rb")
  if not f then
    return nil, err
  end
  local s = f:read("*a")
  f:close()
  return s
end

return M
