-- Asset provenance rules (docs/ART_DIRECTION.md §7).
-- Every shipped file under assets/ must have a manifest entry with author,
-- license, source and tool. Placeholder status must match the filename.

local M = {}

M.EXEMPT = {
  ["assets/manifest.lua"] = true,
  ["assets/PROVENANCE.md"] = true,
}
M.REQUIRED_FIELDS = { "author", "license", "source", "tool" }

-- files: a sorted list of paths found on disk. manifest: { files = { [path] = entry } }.
function M.check(files, manifest)
  local problems = {}
  local entries = (manifest and manifest.files) or {}
  local on_disk = {}

  for _, path in ipairs(files) do
    if not M.EXEMPT[path] then
      on_disk[path] = true
      local e = entries[path]
      if not e then
        problems[#problems + 1] = path .. ": missing manifest entry"
      else
        for _, field in ipairs(M.REQUIRED_FIELDS) do
          if type(e[field]) ~= "string" or e[field] == "" then
            problems[#problems + 1] = path .. ": manifest entry lacks '" .. field .. "'"
          end
        end
        local named = path:find("PLACEHOLDER", 1, true) ~= nil
        if named ~= (e.placeholder == true) then
          problems[#problems + 1] = path
            .. ": 'placeholder' flag must match PLACEHOLDER in the filename"
        end
      end
    end
  end

  local listed = {}
  for path in pairs(entries) do
    listed[#listed + 1] = path
  end
  table.sort(listed)
  for _, path in ipairs(listed) do
    if not on_disk[path] then
      problems[#problems + 1] = path .. ": manifest entry has no file"
    end
  end
  return problems
end

return M
