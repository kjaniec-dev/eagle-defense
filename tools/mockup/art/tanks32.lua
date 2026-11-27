-- 32 px tanks (concept B), authored facing up, left half only (mirrored).
-- Not upscales of the 24 px set: 6 px tracks with four-step cleats, 4 px
-- guns, cupolas, louvres and exhausts use the extra resolution.
-- Each half row = margin (1) + running gear (6) + body (9) = 16 px.
-- Legend: see lib/sprite.lua. Heights: 1 track, 2 hull, 3 turret, 4 gun.
local M = {}

-- tread, period 4: cleat top (lit), body, underside, gap
local TREAD = { "AWWWWD", "ASSSSD", "AXXXXD", "766667" }

-- gear(r) returns the 6 px running-gear segment for row r.
local function tracks(t0, t1)
  return function(r)
    if r == t0 - 1 then
      return "QWWWWE"
    elseif r == t1 + 1 then
      return "ZXXXXC"
    elseif r >= t0 and r <= t1 then
      return TREAD[(r - t0) % 4 + 1]
    end
    return "......"
  end
end

local function compose(gear, body)
  local rows = {}
  for r = 0, #body - 1 do
    rows[r + 1] = "." .. gear(r) .. body[r + 1]
  end
  return rows
end

-- P1/P2 "Lancer"
M.player = {
  mirror = true,
  rows = compose(tracks(7, 29), {
    ".........", -- 0
    "......QWW", -- 1 muzzle brake
    "......A8S", -- 2
    "......A67", -- 3 vent slot
    "......ZXX", -- 4
    ".......a4", -- 5 barrel
    ".......a4", -- 6
    ".qwwwwwa4", -- 7 hull front
    "q++4444a4", -- 8 headlights
    "a444444a4", -- 9 glacis
    "a444444a4", -- 10
    "a3xxxxxa4", -- 11 glacis seam
    "a331111qw", -- 12 turret line, mantlet
    "a31qwwwa4", -- 13
    "a1q4444zx", -- 14
    "a1aq44444", -- 15 roof, spec
    "a1aa44333", -- 16
    "a1aa43333", -- 17
    "a1aa33333", -- 18
    "a1aa33333", -- 19
    "a1a333333", -- 20
    "a1a333333", -- 21
    "a1z333333", -- 22
    "a1zxxxxxx", -- 23
    "a31xxxxxx", -- 24
    "a33111111", -- 25 turret rear line
    "a24242424", -- 26 engine louvres
    "a24242424", -- 27
    "a23232323", -- 28
    "z7Sxxxxxx", -- 29 rear plate, exhaust
    ".........", -- 30
    ".........", -- 31
  }),
  heights = {
    { 1, 1, 6, 6, 30 },
    { 2, 7, 7, 15, 29 },
    { 3, 10, 12, 15, 12 },
    { 3, 9, 13, 15, 13 },
    { 3, 8, 14, 15, 23 },
    { 3, 9, 24, 15, 24 },
    { 3, 10, 25, 15, 25 },
    { 4, 13, 1, 15, 4 },
    { 4, 14, 5, 15, 14 },
  },
  -- commander cupola (right) and a periscope glint: asymmetric details
  patches = {
    { 18, 17, "qwwe" },
    { 18, 18, "a22d" },
    { 18, 19, "a21d" },
    { 18, 20, "zxxc" },
  },
}

-- Enemy "Wasp": light 4-wheel scout car, wedge nose, small turret.
local WHEEL = { "QWWWE.", "AXSXD.", "A8W8D.", "AX9XD.", "A8W8D.", "AXSXD.", "ZXXXC." }
local function wheels(r)
  if r >= 12 and r <= 18 then
    return WHEEL[r - 11]
  elseif r >= 21 and r <= 27 then
    return WHEEL[r - 20]
  end
  return "......"
end

M.scout = {
  mirror = true,
  rows = compose(wheels, {
    ".........", -- 0
    ".........", -- 1
    "........W", -- 2 thin gun
    "........A", -- 3
    "........A", -- 4
    "........A", -- 5
    "........A", -- 6
    ".....q+wA", -- 7 nose + lamp
    "....qw44A", -- 8
    "...qw444A", -- 9
    "..qw4444A", -- 10
    ".qa44433A", -- 11
    "qa443333A", -- 12
    "a33331111", -- 13 turret line
    "a3331qwww", -- 14
    "a331q4444", -- 15
    "a331aq444", -- 16
    "a331a4333", -- 17
    "a331a3333", -- 18
    "a331a3333", -- 19
    "a331z3333", -- 20
    "a3331xxxx", -- 21
    "a33331111", -- 22
    "a32323232", -- 23 rear deck louvres
    "a32323232", -- 24
    "a33333333", -- 25
    "a2S2S2S2S", -- 26 exhaust grille
    "zxxxxxxxx", -- 27
    ".........", -- 28
    ".........", -- 29
    ".........", -- 30
    ".........", -- 31
  }),
  heights = {
    { 1, 1, 12, 5, 27 },
    { 2, 7, 7, 15, 27 },
    { 3, 11, 13, 15, 13 },
    { 3, 10, 14, 15, 21 },
    { 3, 11, 22, 15, 22 },
    { 4, 15, 2, 15, 12 },
  },
  patches = {
    { 18, 18, "!" },
  },
}

-- Enemy "Hammer": power tank, long 4 px gun, big rear-set turret.
M.power = {
  mirror = true,
  rows = compose(tracks(6, 30), {
    "......QWW", -- 0 muzzle brake
    "......A8S", -- 1
    "......A67", -- 2
    "......ZXX", -- 3
    ".......a4", -- 4
    ".......a4", -- 5
    ".qwwwwwa4", -- 6 hull front
    "q+44444a4", -- 7 lamp
    "a444444a4", -- 8
    "a333333a4", -- 9
    "a3xxxxxa4", -- 10 seam
    "a333333a4", -- 11
    "a333333a4", -- 12
    "a333333a4", -- 13
    "a331111qw", -- 14 turret line, mantlet
    "a31qwwwa4", -- 15
    "a1q4444zx", -- 16
    "a1aq44444", -- 17
    "a1aa44333", -- 18
    "a1aa43333", -- 19
    "a1aa33333", -- 20
    "a1aa33333", -- 21
    "a1a333333", -- 22
    "a1a332323", -- 23 bustle vents
    "a1a332323", -- 24
    "a1z333333", -- 25
    "a1zxxxxxx", -- 26
    "a31xxxxxx", -- 27
    "a33111111", -- 28
    "a24242424", -- 29
    "z7Sxxxxxx", -- 30
    ".........", -- 31
  }),
  heights = {
    { 1, 1, 5, 6, 31 },
    { 2, 7, 6, 15, 30 },
    { 3, 10, 14, 15, 14 },
    { 3, 9, 15, 15, 15 },
    { 3, 8, 16, 15, 26 },
    { 3, 9, 27, 15, 27 },
    { 3, 10, 28, 15, 28 },
    { 4, 13, 0, 15, 3 },
    { 4, 14, 4, 15, 16 },
  },
  patches = {
    { 19, 21, "qwe" },
    { 19, 22, "a#d" },
    { 19, 23, "zxc" },
    { 12, 22, "%" },
  },
}

-- Enemy "Bastion": armored 4-hit tank; riveted armour skirts and applique
-- blocks in the dedicated armour ramp; square turret, stubby big gun.
local SKIRT = {
  [5] = "QWWWWE",
  [6] = "ASSSSD",
  [7] = "qwwwwe",
  [8] = "a9444d",
  [9] = "a4444d",
  [17] = "zxxxxc",
  [18] = "qwwwwe",
  [19] = "a9444d",
  [20] = "a4444d",
  [28] = "zxxxxc",
  [29] = "AXXXXD",
  [30] = "ZXXXXC",
}
local function skirts(r)
  if SKIRT[r] then
    return SKIRT[r]
  elseif (r >= 10 and r <= 16) or (r >= 21 and r <= 27) then
    return "a3333d"
  end
  return "......"
end

M.armor = {
  mirror = true,
  rows = compose(skirts, {
    ".........", -- 0
    ".........", -- 1
    "......QWW", -- 2 big muzzle
    "......A8S", -- 3
    "......A67", -- 4
    "......ZXX", -- 5
    ".......a4", -- 6
    "qwwwwwwa4", -- 7 hull front
    "a+44444a4", -- 8 lamp
    "a444444a4", -- 9
    "a3qwwe1qw", -- 10 applique block, mantlet
    "a3a49d1a4", -- 11
    "a3a44d1zx", -- 12
    "a3zxxc1ww", -- 13
    "a31qwwwww", -- 14 turret roof
    "a31aq4444", -- 15
    "a31a44433", -- 16
    "a31a43333", -- 17
    "a31a33333", -- 18
    "a31a33333", -- 19
    "a31a33333", -- 20
    "a31a33333", -- 21
    "a31a33333", -- 22
    "a31z33333", -- 23
    "a31zxxxxx", -- 24
    "a33111111", -- 25
    "a24242424", -- 26 louvres
    "a24242424", -- 27
    "zxxxxxxxx", -- 28
    ".........", -- 29
    ".........", -- 30
    ".........", -- 31
  }),
  heights = {
    { 1, 1, 5, 6, 6 },
    { 1, 1, 29, 6, 30 },
    { 2, 1, 7, 6, 28 },
    { 2, 7, 7, 15, 28 },
    { 3, 9, 10, 12, 13 },
    { 3, 9, 13, 15, 25 },
    { 4, 13, 2, 15, 5 },
    { 4, 14, 6, 15, 12 },
  },
  regions = {
    { "armor", 1, 7, 6, 28 },
    { "armor", 9, 10, 12, 13 },
  },
}

return M
