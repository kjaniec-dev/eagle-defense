-- Plain-data serializer and safe parser for a Lua-literal subset.
--
-- encode(value) produces deterministic Lua table-constructor text, with
-- keys sorted. decode(text) parses that subset with a hand-written parser.
-- It NEVER compiles or executes the input, so a tampered save file cannot
-- run code.
--
-- Supported values: booleans, finite numbers, strings, and tables with
-- string or finite-number keys (`nil` only as the whole top-level value).
-- Cycles, functions, userdata, NaN and infinities are rejected.
--
-- Canonical form: equal data always encodes to identical text, regardless
-- of table insertion history. The array part is the contiguous prefix
-- 1..n, and all other keys are sorted (numbers before strings).
--
-- Grammar accepted by decode:
--   chunk  := ['return'] value
--   value  := 'nil' | 'true' | 'false' | number | string | table
--   table  := '{' [field {sep field} [sep]] '}'     sep := ',' | ';'
--   field  := '[' value ']' '=' value | name '=' value | value
-- `--` line comments and whitespace are allowed between tokens.
-- Rejected on decode: duplicate keys (including a positional index
-- colliding with an explicit [n]), nil values inside tables, and nesting
-- deeper than MAX_DEPTH. The encoder enforces the same depth limit.

local M = {}

M.MAX_DEPTH = 32

-- encode ---------------------------------------------------------------------

local function escape_string(s)
  return '"'
    .. s:gsub('[%c"\\\128-\255]', function(c)
      if c == '"' then
        return '\\"'
      elseif c == "\\" then
        return "\\\\"
      elseif c == "\n" then
        return "\\n"
      elseif c == "\r" then
        return "\\r"
      elseif c == "\t" then
        return "\\t"
      end
      return ("\\%03d"):format(c:byte())
    end)
    .. '"'
end

local function encode_number(n)
  if n ~= n or n == math.huge or n == -math.huge then
    error("serialize: non-finite number", 0)
  end
  if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
    return ("%d"):format(n)
  end
  return ("%.17g"):format(n)
end

local IDENT = "^[%a_][%w_]*$"
local KEYWORDS = {
  ["and"] = true,
  ["break"] = true,
  ["do"] = true,
  ["else"] = true,
  ["elseif"] = true,
  ["end"] = true,
  ["false"] = true,
  ["for"] = true,
  ["function"] = true,
  ["goto"] = true,
  ["if"] = true,
  ["in"] = true,
  ["local"] = true,
  ["nil"] = true,
  ["not"] = true,
  ["or"] = true,
  ["repeat"] = true,
  ["return"] = true,
  ["then"] = true,
  ["true"] = true,
  ["until"] = true,
  ["while"] = true,
}

local function key_less(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then
    return ta == "number" -- numbers before strings
  end
  return a < b
end

local encode_value

-- `level` is the nesting level of `t`: the top-level table is level 1.
-- Encoder and decoder share the same limit: level > MAX_DEPTH is rejected.
local function encode_table(t, level, seen)
  if seen[t] then
    error("serialize: cycle detected", 0)
  end
  if level > M.MAX_DEPTH then
    error("serialize: table nesting too deep", 0)
  end
  seen[t] = true

  -- Canonical array part: the longest prefix 1..n of non-nil values, found by
  -- direct indexing. `#t` is NOT used, because for tables with holes Lua may
  -- return any border, which depends on insertion history.
  local n = 0
  while t[n + 1] ~= nil do
    n = n + 1
  end

  local keys = {}
  for k in pairs(t) do
    local kt = type(k)
    if kt == "number" then
      if k ~= k or k == math.huge or k == -math.huge then
        error("serialize: invalid numeric key", 0)
      end
      if not (k >= 1 and k <= n and k == math.floor(k)) then
        keys[#keys + 1] = k
      end
    elseif kt == "string" then
      keys[#keys + 1] = k
    else
      error("serialize: unsupported key type " .. kt, 0)
    end
  end
  table.sort(keys, key_less)

  if n == 0 and #keys == 0 then
    seen[t] = nil
    return "{}"
  end

  local pad = ("  "):rep(level)
  local parts = {}
  for i = 1, n do
    parts[#parts + 1] = pad .. encode_value(t[i], level, seen)
  end
  for _, k in ipairs(keys) do
    local ks
    if type(k) == "string" and k:match(IDENT) and not KEYWORDS[k] then
      ks = k
    elseif type(k) == "string" then
      ks = "[" .. escape_string(k) .. "]"
    else
      ks = "[" .. encode_number(k) .. "]"
    end
    parts[#parts + 1] = pad .. ks .. " = " .. encode_value(t[k], level, seen)
  end
  seen[t] = nil
  return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. ("  "):rep(level - 1) .. "}"
end

-- `level` is the nesting level of the enclosing table (0 at top level).
encode_value = function(v, level, seen)
  local tv = type(v)
  if tv == "nil" then
    return "nil"
  elseif tv == "boolean" then
    return v and "true" or "false"
  elseif tv == "number" then
    return encode_number(v)
  elseif tv == "string" then
    return escape_string(v)
  elseif tv == "table" then
    return encode_table(v, level + 1, seen)
  end
  error("serialize: unsupported value type " .. tv, 0)
end

-- Returns the text "return <value>\n". Raises an error on unsupported input.
function M.encode(value)
  return "return " .. encode_value(value, 0, {}) .. "\n"
end

-- decode ---------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

function Parser:fail(msg)
  error(("parse error at byte %d: %s"):format(self.pos, msg), 0)
end

function Parser:skip()
  local s = self.src
  while true do
    local _, e = s:find("^%s+", self.pos)
    if e then
      self.pos = e + 1
    end
    if s:sub(self.pos, self.pos + 1) == "--" then
      if s:sub(self.pos + 2, self.pos + 3) == "[[" then
        self:fail("block comments are not supported")
      end
      local nl = s:find("\n", self.pos, true)
      self.pos = nl and (nl + 1) or (#s + 1)
    else
      return
    end
  end
end

function Parser:peek(n)
  return self.src:sub(self.pos, self.pos + (n or 1) - 1)
end

function Parser:expect(tok)
  self:skip()
  if self:peek(#tok) ~= tok then
    self:fail("expected '" .. tok .. "'")
  end
  self.pos = self.pos + #tok
end

local ESCAPES = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["'"] = "'", ["\\"] = "\\" }

function Parser:string()
  local s, quote = self.src, self:peek()
  self.pos = self.pos + 1
  local out = {}
  while true do
    local c = s:sub(self.pos, self.pos)
    if c == "" or c == "\n" then
      self:fail("unterminated string")
    elseif c == quote then
      self.pos = self.pos + 1
      return table.concat(out)
    elseif c == "\\" then
      local nxt = s:sub(self.pos + 1, self.pos + 1)
      if ESCAPES[nxt] then
        out[#out + 1] = ESCAPES[nxt]
        self.pos = self.pos + 2
      else
        local digits = s:match("^%d%d?%d?", self.pos + 1)
        if not digits then
          self:fail("invalid escape")
        end
        local code = tonumber(digits)
        if code > 255 then
          self:fail("escape out of range")
        end
        out[#out + 1] = string.char(code)
        self.pos = self.pos + 1 + #digits
      end
    else
      out[#out + 1] = c
      self.pos = self.pos + 1
    end
  end
end

function Parser:number()
  local lexeme = self.src:match("^-?%d+%.?%d*[eE][-+]?%d+", self.pos)
    or self.src:match("^-?%d+%.?%d*", self.pos)
  local n = lexeme and tonumber(lexeme)
  if not n or n ~= n or n == math.huge or n == -math.huge then
    self:fail("invalid number")
  end
  self.pos = self.pos + #lexeme
  return n
end

function Parser:value(depth)
  self:skip()
  local c = self:peek()
  if c == "{" then
    return self:table(depth + 1)
  elseif c == '"' or c == "'" then
    return self:string()
  elseif c == "-" or c:match("%d") then
    return self:number()
  end
  local word = self.src:match("^[%a_][%w_]*", self.pos)
  if word == "true" or word == "false" or word == "nil" then
    self.pos = self.pos + #word
    if word == "nil" then
      return nil
    end
    return word == "true"
  end
  self:fail("unexpected token")
end

function Parser:table(depth)
  if depth > M.MAX_DEPTH then
    self:fail("table nesting too deep")
  end
  self.pos = self.pos + 1 -- '{'
  local t, n, seen = {}, 0, {}
  while true do
    self:skip()
    if self:peek() == "}" then
      self.pos = self.pos + 1
      return t
    end
    local key, val
    if self:peek() == "[" and self:peek(2) ~= "[[" then
      self.pos = self.pos + 1
      key = self:value(depth)
      if key == nil or (type(key) ~= "string" and type(key) ~= "number") then
        self:fail("invalid key")
      end
      self:expect("]")
      self:expect("=")
      val = self:value(depth)
    else
      local name = self.src:match("^[%a_][%w_]*", self.pos)
      local after = name and self.src:match("^%s*=", self.pos + #name)
      if name and after and not KEYWORDS[name] then
        self.pos = self.pos + #name
        self:expect("=")
        key = name
        val = self:value(depth)
      else
        n = n + 1
        key = n
        val = self:value(depth)
      end
    end
    -- Keys are tracked separately from values, so `{ a = nil, a = 1 }` is
    -- still caught as a duplicate.
    if seen[key] then
      self:fail("duplicate key")
    end
    seen[key] = true
    if val == nil then
      self:fail("nil values are not allowed inside tables")
    end
    t[key] = val
    self:skip()
    local sep = self:peek()
    if sep == "," or sep == ";" then
      self.pos = self.pos + 1
    elseif sep ~= "}" then
      self:fail("expected ',' or '}'")
    end
  end
end

-- Parses `text`. Returns value on success, or nil plus an error message.
-- opts.max_bytes (default 1 MiB) bounds the input size.
function M.decode(text, opts)
  opts = opts or {}
  local max_bytes = opts.max_bytes or 1024 * 1024
  if type(text) ~= "string" then
    return nil, "input is not a string"
  end
  if #text > max_bytes then
    return nil, "input too large"
  end
  if text:byte(1) == 27 then
    return nil, "binary chunks are not allowed"
  end
  local p = setmetatable({ src = text, pos = 1 }, Parser)
  local ok, result = pcall(function()
    p:skip()
    if p.src:match("^return%f[^%w_]", p.pos) then
      p.pos = p.pos + 6
    end
    local v = p:value(0)
    p:skip()
    if p.pos <= #p.src then
      p:fail("trailing data")
    end
    return v
  end)
  if not ok then
    return nil, result
  end
  return result
end

return M
