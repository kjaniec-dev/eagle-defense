-- Master palette shared by concept A (24 px) and concept B (32 px).
-- Hue-shifted ramps: shadows drift toward cool/purple, highlights toward warm.
-- Faction hues are reserved (ART_DIRECTION §2): gold = P1, green-teal = P2,
-- cool grey-steel = enemies. Terrain uses low-saturation or distinct hues.
local M = {}

-- Order is the index order in palette.gpl. Index 0 is "transparent" in sprites.
local COLORS = {
  -- neutrals: outline, ink, asphalt, gunmetal
  { "void", "0a0910" },
  { "ink", "141421" },
  { "asph1", "1b1c24" },
  { "asph2", "22232c" },
  { "asph3", "292a34" },
  { "asph4", "31323d" },
  { "metal3", "3c3d4b" },
  { "metal4", "5b5d70" },
  { "metal5", "8f93a8" },
  -- enemy steel (cool grey-blue)
  { "steel1", "1f2438" },
  { "steel2", "3a4361" },
  { "steel3", "64708f" },
  { "steel4", "9ba7c4" },
  { "steel5", "dde6f4" },
  { "white", "ffffff" },
  -- P1 gold
  { "gold1", "40200f" },
  { "gold2", "8f4a14" },
  { "gold3", "d48c1c" },
  { "gold4", "f6c53e" },
  { "gold5", "fff2a3" },
  -- P2 green-teal
  { "teal1", "0b2a2e" },
  { "teal2", "115b56" },
  { "teal3", "1b9a80" },
  { "teal4", "47d3a0" },
  { "teal5", "b9f7d2" },
  -- brick (desaturated terracotta)
  { "brick1", "2a1517" },
  { "brick2", "5a2723" },
  { "brick3", "8a4234" },
  { "brick4", "b2654b" },
  { "brick5", "d4916f" },
  -- water
  { "water1", "0b1736" },
  { "water2", "122f66" },
  { "water3", "1b4e96" },
  { "water4", "2c7bc2" },
  { "water5", "6fb6e8" },
  { "foam", "d6f0ff" },
  -- forest (yellow-leaning greens, kept away from P2 teal)
  { "leaf1", "0c2214" },
  { "leaf2", "17391b" },
  { "leaf3", "245a22" },
  { "leaf4", "3f7f2b" },
  { "leaf5", "7dac3c" },
  -- ice
  { "ice2", "7fa4c9" },
  { "ice3", "b0d2ec" },
  -- fire / danger
  { "orange", "f08424" },
  { "red", "cf3a2c" },
  { "crimson", "721a24" },
  -- armor ramp (armored enemy plates, armor hit stages)
  { "violet1", "3e2a63" },
  { "violet2", "7b5bb5" },
}

M.colors = {}
M.index = {}
M.rgb = {}
for i, c in ipairs(COLORS) do
  local name, hex = c[1], c[2]
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)
  M.colors[i] = { name = name, hex = hex, r = r, g = g, b = b }
  M.index[name] = i
  M.rgb[i] = { r, g, b }
end
M.count = #COLORS
assert(M.count <= 48, "master palette exceeds 48 colors")

local function idx(name)
  local i = M.index[name]
  if not i then
    error("unknown palette color " .. tostring(name), 2)
  end
  return i
end
M.idx = idx

local function ramp(names)
  local r = {}
  for i, n in ipairs(names) do
    r[i] = idx(n)
  end
  return r
end

-- Five-tone material ramps (1 = deepest, 5 = specular).
M.ramps = {
  gold = ramp({ "gold1", "gold2", "gold3", "gold4", "gold5" }),
  teal = ramp({ "teal1", "teal2", "teal3", "teal4", "teal5" }),
  steel = ramp({ "steel1", "steel2", "steel3", "steel4", "steel5" }),
  metal = ramp({ "ink", "asph4", "metal3", "metal4", "metal5" }),
  darkmetal = ramp({ "void", "ink", "asph3", "metal3", "metal4" }),
  armor = ramp({ "void", "violet1", "violet2", "steel4", "steel5" }),
  lampwarm = ramp({ "gold2", "orange", "gold4", "gold5", "white" }),
  lampcool = ramp({ "steel2", "water4", "water5", "foam", "white" }),
  lampviolet = ramp({ "violet1", "violet2", "violet2", "steel5", "white" }),
  lampred = ramp({ "crimson", "red", "orange", "gold5", "white" }),
  ivory = ramp({ "steel2", "steel3", "steel4", "steel5", "white" }),
  slate = ramp({ "ink", "steel1", "steel2", "steel3", "steel4" }),
}

-- Shadow and light lookup tables (palette index -> palette index). Drop
-- shadows and glows are palette remaps, so every output pixel stays in the
-- master palette ("semi-transparent" looks without alpha).
local SHADOW = {
  void = "void",
  ink = "void",
  asph1 = "ink",
  asph2 = "ink",
  asph3 = "asph1",
  asph4 = "asph2",
  metal3 = "asph3",
  metal4 = "metal3",
  metal5 = "metal4",
  steel1 = "ink",
  steel2 = "steel1",
  steel3 = "steel2",
  steel4 = "steel3",
  steel5 = "steel4",
  white = "steel5",
  gold1 = "void",
  gold2 = "gold1",
  gold3 = "gold2",
  gold4 = "gold3",
  gold5 = "gold4",
  teal1 = "void",
  teal2 = "teal1",
  teal3 = "teal2",
  teal4 = "teal3",
  teal5 = "teal4",
  brick1 = "void",
  brick2 = "brick1",
  brick3 = "brick2",
  brick4 = "brick3",
  brick5 = "brick4",
  water1 = "void",
  water2 = "water1",
  water3 = "water2",
  water4 = "water3",
  water5 = "water4",
  foam = "water5",
  leaf1 = "void",
  leaf2 = "leaf1",
  leaf3 = "leaf2",
  leaf4 = "leaf3",
  leaf5 = "leaf4",
  ice2 = "steel3",
  ice3 = "ice2",
  orange = "brick3",
  red = "crimson",
  crimson = "brick1",
  violet1 = "steel1",
  violet2 = "violet1",
}

-- Warm light: one step brighter and warmer.
local LIGHT = {
  void = "ink",
  ink = "brick1",
  asph1 = "brick1",
  asph2 = "brick1",
  asph3 = "brick1",
  asph4 = "brick2",
  metal3 = "brick2",
  metal4 = "brick4",
  metal5 = "brick5",
  steel1 = "violet1",
  steel2 = "metal4",
  steel3 = "brick5",
  steel4 = "brick5",
  steel5 = "gold5",
  white = "white",
  gold1 = "gold2",
  gold2 = "gold3",
  gold3 = "gold4",
  gold4 = "gold5",
  gold5 = "white",
  teal1 = "teal2",
  teal2 = "teal3",
  teal3 = "teal4",
  teal4 = "teal5",
  teal5 = "white",
  brick1 = "brick2",
  brick2 = "brick3",
  brick3 = "brick4",
  brick4 = "brick5",
  brick5 = "gold5",
  water1 = "water2",
  water2 = "water3",
  water3 = "water4",
  water4 = "water5",
  water5 = "foam",
  foam = "white",
  leaf1 = "leaf2",
  leaf2 = "leaf3",
  leaf3 = "leaf4",
  leaf4 = "leaf5",
  leaf5 = "gold5",
  ice2 = "ice3",
  ice3 = "foam",
  orange = "gold4",
  red = "orange",
  crimson = "red",
  violet1 = "violet2",
  violet2 = "steel5",
}

M.shadow = {}
M.light = {}
for i, c in ipairs(M.colors) do
  M.shadow[i] = idx(assert(SHADOW[c.name], "no shadow entry for " .. c.name))
  M.light[i] = idx(assert(LIGHT[c.name], "no light entry for " .. c.name))
end
M.shadow[0] = 0
M.light[0] = 0

function M.gpl()
  local out = {
    "GIMP Palette",
    "Name: Eagle Defense master (G1 concept)",
    "Columns: 8",
    "#",
    "# Shared by mockup concepts A (24 px) and B (32 px). Concept art, not final.",
  }
  for _, c in ipairs(M.colors) do
    out[#out + 1] = ("%3d %3d %3d\t%s"):format(c.r, c.g, c.b, c.name)
  end
  return table.concat(out, "\n") .. "\n"
end

return M
