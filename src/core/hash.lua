-- 32-bit checksum builder (Jenkins one-at-a-time over bytes).
--
-- Pure Lua on LuaJIT's `bit` library, so results are bit-identical on every
-- platform. It is used for simulation state hashes (golden replays, desync
-- checks) and for content identities such as the tuning id. It is a
-- checksum, not a cryptographic hash.

local bit = require("bit")

local band, bxor, lshift, rshift, tobit = bit.band, bit.bxor, bit.lshift, bit.rshift, bit.tobit

local M = {}

local Hasher = {}
Hasher.__index = Hasher

local TWO32 = 4294967296

function M.new()
  return setmetatable({ h = 0 }, Hasher)
end

local function byte(h, b)
  h = tobit(h + b)
  h = tobit(h + lshift(h, 10))
  return bxor(h, rshift(h, 6))
end

-- Feeds an integer. Values must be integers in [-2^31, 2^32); each is fed
-- as 4 little-endian bytes of its 32-bit two's complement form.
function Hasher:int(v)
  assert(type(v) == "number" and v == math.floor(v), "hash: integer expected")
  assert(v >= -2147483648 and v < TWO32, "hash: integer out of 32-bit range")
  local x = tobit(v)
  local h = self.h
  h = byte(h, band(x, 0xff))
  h = byte(h, band(rshift(x, 8), 0xff))
  h = byte(h, band(rshift(x, 16), 0xff))
  h = byte(h, band(rshift(x, 24), 0xff))
  self.h = h
  return self
end

-- Feeds a boolean as one int (0/1).
function Hasher:bool(b)
  return self:int(b and 1 or 0)
end

-- Feeds a string: its length, then its bytes.
function Hasher:str(s)
  assert(type(s) == "string", "hash: string expected")
  self:int(#s)
  local h = self.h
  for i = 1, #s do
    h = byte(h, s:byte(i))
  end
  self.h = h
  return self
end

-- Final value as an unsigned 32-bit integer.
function Hasher:value()
  local h = self.h
  h = tobit(h + lshift(h, 3))
  h = bxor(h, rshift(h, 11))
  h = tobit(h + lshift(h, 15))
  if h < 0 then
    h = h + TWO32
  end
  return h
end

-- Final value as 8 lowercase hex digits.
function Hasher:hex()
  return ("%08x"):format(self:value())
end

-- Convenience: hash of a string, as 8 hex digits.
function M.string(s)
  return M.new():str(s):hex()
end

return M
