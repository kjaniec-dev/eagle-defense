-- Deterministic integer hashing, value noise and ordered dithering.
local bit = require("bit")

local M = {}

-- 32-bit multiply without losing precision in doubles.
local function mul32(a, b)
  local alo = a % 65536
  local ahi = (a - alo) / 65536
  return bit.tobit(bit.tobit(ahi * b) * 65536 + alo * b)
end

-- Hash of integer coordinates -> integer in [0, 2^31).
function M.hash(x, y, seed)
  local h = bit.tobit(x * 374761 + y * 668265 + (seed or 0) * 2246822)
  h = bit.bxor(h, bit.rshift(h, 15))
  h = mul32(h % 4294967296, 2246822519)
  h = bit.bxor(h, bit.rshift(h, 13))
  h = mul32(h % 4294967296, 3266489917)
  h = bit.bxor(h, bit.rshift(h, 16))
  return bit.band(h, 0x7fffffff)
end

-- Hash -> integer in [0, n).
function M.rand(x, y, seed, n)
  return M.hash(x, y, seed) % n
end

-- Value noise in [0, 255], lattice spacing `cell` px, bilinear (integer).
function M.value(x, y, cell, seed)
  local gx, gy = math.floor(x / cell), math.floor(y / cell)
  local fx, fy = x - gx * cell, y - gy * cell
  local a = M.rand(gx, gy, seed, 256)
  local b = M.rand(gx + 1, gy, seed, 256)
  local c = M.rand(gx, gy + 1, seed, 256)
  local d = M.rand(gx + 1, gy + 1, seed, 256)
  local top = a * (cell - fx) + b * fx
  local bot = c * (cell - fx) + d * fx
  return math.floor((top * (cell - fy) + bot * fy) / (cell * cell))
end

local BAYER4 = {
  { 0, 8, 2, 10 },
  { 12, 4, 14, 6 },
  { 3, 11, 1, 9 },
  { 15, 7, 13, 5 },
}

-- Ordered-dither threshold in [0, 15].
function M.bayer(x, y)
  return BAYER4[y % 4 + 1][x % 4 + 1]
end

return M
