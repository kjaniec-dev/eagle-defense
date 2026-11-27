-- Headquarters: an original geometric eagle (wings raised in a V, head in
-- profile, crimson chest shield) on a hexagonal slate plinth with a warm
-- beacon. Authored as a plinth sprite plus an emblem sprite per tile size.
local canvas = require("lib.canvas")
local sprite = require("lib.sprite")

local M = {}

local LEGEND = {
  k = "void",
  n = "ink",
  ["1"] = "steel1",
  ["2"] = "steel2",
  ["3"] = "steel3",
  ["4"] = "steel4",
  W = "white",
  E = "steel5",
  F = "steel4",
  G = "steel3",
  r = "red",
  c = "crimson",
  o = "orange",
  y = "gold4",
  Y = "gold5",
}

-- right half one tone darker (light from the top-left)
local SHADE_RIGHT = { W = "E", E = "F", F = "G", ["4"] = "3", ["3"] = "2", r = "c" }

local PLINTH24 = {
  "............",
  "............",
  ".....kkkkkkk",
  "....k4444444",
  "....k3222222",
  "...k43222222",
  "...k32222222",
  "..k432222222",
  "..k322222222",
  ".k4322222222",
  ".k3222222222",
  ".k3222222222",
  ".k2222222222",
  ".k1222222222",
  "..k122222222",
  "..k112222222",
  "...k12222222",
  "...k11222222",
  "....k1222222",
  "....k1111111",
  "....kn111111",
  ".....knnnnnn",
  "......kkkkkk",
  "............",
}

local EAGLE24 = {
  "W.W......",
  "EWEW.....",
  "EEEEW....",
  "FEEEEW...",
  "FFEEEEW..",
  ".FFFEEEWW",
  "....FFEEE",
  "......EEr",
  "......Err",
  "......Fcr",
  ".......WE",
  "......WFE",
  "......F.F",
}

-- head in profile (beak to the left), overlaid on the mirrored emblem
local HEAD24 = {
  { 8, 0, "WWE" },
  { 7, 1, "WnnEF" },
  { 5, 2, "yyEYEEF" },
  { 5, 3, "noWEEF" },
  { 7, 4, "EEEF" },
}

local PLINTH32 = {
  "................",
  "................",
  ".......kkkkkkkkk",
  "......k444444444",
  "......k433333333",
  ".....k4322222222",
  ".....k4222222222",
  "....k43222222222",
  "....k42222222222",
  "...k432222222222",
  "...k422222222222",
  "..k4322222222222",
  "..k4222222222222",
  ".k43222222222222",
  ".k42222222222222",
  ".k32222222222222",
  ".k22222222222222",
  ".k12222222222222",
  "..k1222222222222",
  "..k1122222222222",
  "...k122222222222",
  "...k112222222222",
  "....k12222222222",
  "....k11222222222",
  ".....k1222222222",
  ".....k1122222222",
  "......k122222222",
  "......k111111111",
  "......kn11111111",
  ".......knnnnnnnn",
  "........kkkkkkkk",
  "................",
}

local EAGLE32 = {
  "W...........",
  "EW.W........",
  "EEWEW.W.....",
  "FEEEWEW.....",
  "FEEEEEEW....",
  ".FEEEEEEW...",
  ".FFEEEEEEW..",
  "..FFFEEEEEWW",
  "....FFFEEEEE",
  "......FFEEEE",
  "........EErr",
  "........EErW",
  "........FrWc",
  ".........rcc",
  ".........Ecc",
  "..........WE",
  ".........WFE",
  ".........F.F",
}

local HEAD32 = {
  { 10, 0, "WWWE" },
  { 9, 1, "WWEEEF" },
  { 8, 2, "WnnnEEF" },
  { 6, 3, "yyyEYEEEF" },
  { 6, 4, "nyoEEEEF" },
  { 7, 5, "noWEEEF" },
  { 10, 6, "EEEF" },
}

local SPECS = {
  [24] = {
    plinth = PLINTH24,
    eagle = EAGLE24,
    head = HEAD24,
    beacon_patch = { { 10, 20, "yY" }, { 10, 21, "oo" } },
    eagle_at = { 2, 4 },
    beacon = { 11, 20 },
  },
  [32] = {
    plinth = PLINTH32,
    eagle = EAGLE32,
    head = HEAD32,
    beacon_patch = { { 14, 28, "yY" }, { 14, 29, "oo" } },
    eagle_at = { 3, 6 },
    beacon = { 15, 28 },
  },
}

function M.build(T)
  local spec = SPECS[T]
  local plinth = sprite.direct({
    rows = spec.plinth,
    legend = LEGEND,
    mirror = true,
    mirror_map = { ["4"] = "3", ["3"] = "2" },
    patches = spec.beacon_patch,
  })
  local eagle = sprite.direct({
    rows = spec.eagle,
    legend = LEGEND,
    mirror = true,
    mirror_map = SHADE_RIGHT,
    patches = spec.head,
    outline = "ink",
    pad = 1,
  })
  local s = canvas.new(T, T, 0)
  canvas.blit(s, plinth, 0, 0)
  canvas.blit(s, eagle, spec.eagle_at[1], spec.eagle_at[2])
  return {
    sprite = s,
    beacon = spec.beacon, -- glow centre, sprite-local
  }
end

return M
