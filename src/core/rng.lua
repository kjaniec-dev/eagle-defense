-- Deterministic, seedable PRNG (xorshift32, shifts 13/17/5).
--
-- Built on LuaJIT's `bit` library, so results are bit-identical on every
-- platform. Gameplay code must use this instead of math.random or
-- love.math.random.

local bit = require("bit")

local bxor, lshift, rshift, tobit = bit.bxor, bit.lshift, bit.rshift, bit.tobit

local M = {}

local Rng = {}
Rng.__index = Rng

local TWO32 = 4294967296
local DEFAULT_SEED = 0x6D2B79F5

local function to_u32(x)
  if x < 0 then
    return x + TWO32
  end
  return x
end

local function normalize_seed(seed)
  assert(type(seed) == "number" and seed == math.floor(seed), "seed must be an integer")
  local s = tobit(seed % TWO32)
  if s == 0 then
    s = tobit(DEFAULT_SEED) -- xorshift must never hold zero
  end
  return s
end

function M.new(seed)
  return setmetatable({ state = normalize_seed(seed or DEFAULT_SEED) }, Rng)
end

-- Next raw value as an unsigned 32-bit integer in [0, 2^32).
function Rng:next_u32()
  local x = self.state
  x = bxor(x, lshift(x, 13))
  x = bxor(x, rshift(x, 17))
  x = bxor(x, lshift(x, 5))
  self.state = x
  return to_u32(x)
end

-- Uniform integer in [lo, hi] (inclusive), without modulo bias.
function Rng:range(lo, hi)
  assert(lo <= hi, "range: lo must be <= hi")
  local span = hi - lo + 1
  assert(span <= TWO32, "range: span too large")
  local limit = TWO32 - (TWO32 % span) -- largest multiple of span
  local v
  repeat
    v = self:next_u32()
  until v < limit
  return lo + (v % span)
end

-- True with probability num/den (integers, 0 <= num <= den).
function Rng:chance(num, den)
  return self:range(1, den) <= num
end

-- Serializable state, as an unsigned integer.
function Rng:get_state()
  return to_u32(self.state)
end

function Rng:set_state(state)
  self.state = normalize_seed(state)
end

return M
