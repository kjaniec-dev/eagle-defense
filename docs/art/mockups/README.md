# G1 visual direction spike: concept mockups

**Status: concept art.** These files are not shipped, not final and not part of the `.love`. They exist so the owner can choose the pixel density and the art direction. G3 produces the final asset set (animation, all directions and states, shaders).

Two static gameplay concepts show the same original mid-battle composition:

| Concept | Tile | Internal canvas | Playfield (13 × 13) | At 1920 × 1080 |
|---|---|---|---|---|
| **A** | 24 px | 640 × 360 | 312 × 312 at (164, 24) | 3× integer, exact fill |
| **B** | 32 px | 768 × 432 | 416 × 416 at (176, 8) | 2× integer (1536 × 864, letterboxed) or 2.5× sharp-bilinear fit |

Both concepts show the following. Each 32 px sprite is authored separately and is not an upscale of the 24 px one.

- Two original player tanks ("Lancer", gold P1 and teal P2).
- Three enemy designs:
  - "Wasp", a fast 4-wheel scout car.
  - "Hammer", a power tank with a long gun.
  - "Bastion", an armored 4-hit tank with armour skirts in the dedicated armour ramp.
- An original HQ: a geometric eagle with raised V wings and a crimson chest shield, on a hexagonal slate plinth with a warm beacon.
- Terrain:
  - brick with chipped and shot-away cells and rubble
  - riveted tread-plate steel
  - water with shore shadow, foam and wave crests
  - forest with a canopy over a half-hidden scout and a fair, see-through edge band
  - ice with sheen, frost and cracks
  - dark asphalt with cracks and tread marks
- Effects and lighting:
  - a P1 shell with a trail and a muzzle flash
  - an enemy shell
  - one explosion with restrained debris, sparks, smoke and a scorch decal
  - an enemy spawn marker
  - restrained palette-remap lighting: muzzle, shell and explosion glows and the HQ beacon
  - drop shadows down-right of every raised object
- An original side-panel HUD:
  - P1 on the left and P2 on the right, each with a slanted badge, a portrait window, the score, lives, power stars and a kill tally by enemy type
  - the stage flag and number on the left
  - the enemy reserve on the right, as a segmented 20-cell gauge plus a counter (no icon grid and no grey right-hand column)

## Regenerating

```sh
make mockups        # = love tools/mockup docs/art/mockups
```

The renderer is a headless LÖVE 11.5 app in `tools/mockup/` (`conf.lua`, `main.lua`, sprite sources under `art/`, helpers under `lib/`). The window, graphics and audio modules are disabled. Every pixel is computed on the CPU into palette-indexed buffers and encoded with `ImageData:encode("png")`, so no GPU or Xvfb is needed.

**Output is byte-deterministic.** All maths that reaches a pixel is integer or exactly rational, including the sharp-bilinear fit, and noise comes from an integer hash. Running `make mockups` twice in the sandbox produced identical SHA-256 sums for every file.

A zoomed review sheet of the tanks in all four directions can be produced with `love tools/mockup --sheet <out.png> [24|32]`.

## Files

| File | Size (px) | SHA-256 |
|---|---|---|
| `A-native.png` | 640 × 360 | `ef8ab53f179aac5fce595f26fcb23f1a485c6e9eb7a303b102665496dfeb6665` |
| `B-native.png` | 768 × 432 | `cdcda7d41ac2163376b1872ce8a420d13ee5985df3cd97628db6324aca4ea719` |
| `A-1920x1080.png` | 1920 × 1080 (A, 3× nearest) | `0bf56e03660ea56d260e4a8f55960235ac5b95e01fd5ff166fbdb86856ce85e3` |
| `B-1920x1080-integer.png` | 1920 × 1080 (B, 2× nearest, centred, black bars of 192 / 108 px) | `bdb4176b593688aafa7f7419df9151c71e3f084672d71d6a78b41fc969af13d1` |
| `B-1920x1080-fit.png` | 1920 × 1080 (B, 2.5× sharp bilinear: 3× nearest prescale to 2304 × 1296, then one bilinear resample) | `ed0b7e0a7b9d77fbbf261a8a5b7b4bf482ad1736dd39f39f790f9f5008f706fb` |
| `compare-1920x1080.png` | 1920 × 1080 | `dacc78d07e182a171d4e52dc1262fc760c418f4feb2568a6cb8b0c8cf14ce355` |
| `palette.gpl` | 48 colours (GIMP palette) | `290963ae2ecb798c16e6fe0ece4151dab56bc628042c8228726c7f8de52b3f94` |

`compare-1920x1080.png` crops the same region from the three real 1920 × 1080 outputs: tiles 2–7 × 8–12, which contain the P1 tank, the steel and brick corner and the HQ. The crops are shown **1:1 with the screen pixels**, so each one is exactly the physical size it would have on the same 1080p monitor:

- A at 3× gives 1 tile = 72 px.
- B at 2.5× fit gives 1 tile = 80 px, with soft edges.
- B at 2× integer gives 1 tile = 64 px.

The second row zooms a detail (the P1 tank, muzzle flash and shell) by 2× nearest so the fit softness is visible. The footer covers 1440p and Steam Deck.

## Palette

The master palette has 48 colours (the limit), shared by both concepts:

| Group | Colours |
|---|---|
| Outline, asphalt and gunmetal | `void`, `ink`, `asph1`–`asph4`, `metal3`–`metal5` |
| Enemy steel | `steel1`–`steel5`, `white` |
| P1 | `gold1`–`gold5` |
| P2 | `teal1`–`teal5` |
| Brick | `brick1`–`brick5` (desaturated terracotta) |
| Water | `water1`–`water5`, `foam` |
| Foliage | `leaf1`–`leaf5` (yellow-leaning, kept away from P2 teal) |
| Ice | `ice2`, `ice3` |
| Fire / danger | `orange`, `red`, `crimson` |
| Armour ramp | `violet1`, `violet2` |

The ramps are hue-shifted: shadows drift cool or purple and highlights drift warm. Shadows and glows are palette remaps through hand-made LUTs (`lib/palette.lua`), so even "semi-transparent" shadows and light stay inside the palette. Faction hues are reserved as follows:

- Gold, teal and cool steel appear only on tanks and HUD faction accents.
- Terrain uses terracotta, blue, foliage green and pale ice.
- Bullets have the highest value contrast: a white core and a dark outline.

## How the art is made (Pipeline A)

Every sprite is a hand-placed, text-indexed pixel map in `tools/mockup/art/`: tanks in `tanks24.lua` and `tanks32.lua`, the HQ in `hq.lua`, and icons and fonts in `hud.lua` and `lib/font.lua`. Terrain textures (`terrain.lua`, `forest.lua`) are hand-written per-pixel rules (bevels, bricks, rivets, wave stamps, leaf clusters) with deterministic noise. Cracks are hand-placed polylines.

Tank characters encode a material plus either a tone or a **surface facing**, and the helpers in `lib/sprite.lua` work as follows:

- Facings are resolved against a fixed top-left light **after** mirroring and rotation, so a tank turned to face down is still lit from the top-left.
- Mirrored halves are authored once, with a west/east facing swap.
- Rotation works in quarter turns on the grid.
- A height map adds 1 px contact shadows down-right of the turret and gun.
- A 1 px outline is added automatically against the background.
- Asymmetric patches (hatches, glints) are allowed.

No new dependencies were added. Blender was not used: a pre-rendered 3D look would conflict with the crisp hand-pixel style, and at 24–32 px it would still need full hand clean-up.

## A vs B

| | A (24 px, 640 × 360) | B (32 px, 768 × 432) |
|---|---|---|
| Pixels per tank frame | 576 | 1024 (1.8×) |
| Detail per tile | Clean silhouettes; 4 px tracks, 10–12 px turrets, 2 px guns. Enough for readable plating, hatches, grilles and lamps. | 6 px tracks with four-step cleats, 4 px guns, louvres, exhausts, cupolas and rivets. Brick and steel get finer texture. |
| 1280 × 720 | 2× exact fill | 1× + bars, or 1.67× fit (soft) |
| **1920 × 1080** | **3× exact fill**, tile = 72 px | 2× + bars (playfield 832 px tall, 77 % of the height) or 2.5× fit (tile = 80 px, slightly soft) |
| 2560 × 1440 | 4× exact fill, tile = 96 px | 3× = 2304 × 1296 + bars, tile = 96 px (crisp) |
| 3840 × 2160 | 6× exact fill | 5× exact fill |
| Steam Deck 1280 × 800 | 2× = 1280 × 720 + 40 px bars, crisp | 1× (tiny) or 1.67× fit (soft) |
| Playfield share of screen height at 1080p | 87 % | 77 % (integer) / 96 % (fit) |
| HUD side panels | 164 px each: badge, portrait, score, lives, power, kills, stage or reserve fit comfortably | 176 px each, plus more height |
| Authoring cost | 12 × 24 half-grid per design. The player tank took 5 visual iterations. | 16 × 32 half-grid per design, about 1.8× the cells. Every animation frame, direction correction and hit state scales the same way. |

**Readability.** Both concepts are readable at 1080p and above. At 1080p, A is the only option that is both crisp and full-screen. B's extra detail is real but subtle at 1080p, because each art pixel becomes smaller (2.5 or 2 screen px instead of 3). It pays off mainly at 1440p (3× crisp) and 4K (5× exact). On Steam Deck, A is clearly better.

## Honest self-assessment

These renders are sandbox evidence only: CPU-rendered on Linux and viewed as PNGs. They have not been checked on a real 1080p, 1440p or 4K monitor or on a Steam Deck. ART_DIRECTION §7.3 requires the owner to view them on a real display.

**Where the art meets a premium bar:**

- **Brick, steel and water:** chunky, crafted and cohesive. Brick damage and rubble read well.
- **HUD:** clean, original and information-rich, with a consistent palette and our own iconography.
- **Lighting and shadows:** restrained, palette-true and consistent with a top-left light.
- **Readability:** faction colours, bullets and the spawn marker read instantly, and the forest edge stays fair.

**Where it falls short:**

- **Tanks.** They are clean and readable with correct lighting in all four directions, but their design language is somewhat generic and boxy. Turret forms, anti-aliasing and selective outlining are simpler than top-tier hand work. The 32 px set mostly refines the 24 px designs instead of adding new character.
- **Eagle emblem.** It reads as a raptor emblem, but at 24 px it is busy and small. It is the hero element that most needs another design pass.
- **Forest and explosion.** Both are rule-based composites. They work for a static frame, but G3 needs hand-animated explosion frames and a less regular canopy.
- **Ice.** It is clean but a little "glass pane".

**Pipeline B.** Pipeline A is strong enough for tiles, UI and effects. For the hero sprites (4 tank designs × 4 directions × 2–3 track frames, plus the HQ intact and destroyed), I recommend that the owner seriously considers commissioning a human pixel artist at G3. Use these mockups as the style and palette brief, and decide after the G3 slice as planned.

## Recommendation

**Choose concept A (24 px tiles, 640 × 360).** The reasons:

- It scales exactly on 720p, 1080p, 1440p, 4K and Steam Deck (2×).
- It fills a 1080p screen crisply. 1080p is the most common Steam resolution, and there B forces a choice between softness and a smaller letterboxed image.
- It costs about 44 % fewer pixels per sprite frame across the whole G3 asset set.
- This spike shows that 24 px is enough for premium-looking, readable hero sprites.

The richer B ideas (four-step cleats, louvres, wider guns) can be condensed into the 24 px set where they help.

Choose B only if the target audience is mainly 1440p or 4K and the owner accepts letterboxing or soft fit at 1080p and on Steam Deck.

## Provenance

- **Author:** an AI agent (Claude, Anthropic), authored as code-defined pixel art in this repository (`tools/mockup/`). It is not traced or derived from any other game. No reference sprites, eagle art, brick or steel patterns, HUD layouts, logos or palettes were used.
- **Status:** original, proprietary game content (see `NOTICE.md`). It is concept art only and is never shipped.
- **Disclosure:** AI-generated content must be disclosed in the Steam AI-content survey (tracked in G9).
- **Fonts:** both bitmap fonts (5 × 7, 3 × 5, plus the bold 7 × 10 score digits) are original and defined in code.
