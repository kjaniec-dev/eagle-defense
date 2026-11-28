# Eagle Defense

A retro top-down tank arcade game, with single player and 2-player local co-op, built with [LÖVE](https://love2d.org) 11.5. It is a commercial project targeting Steam.

> **Status: G2 — battlefield, terrain and destruction (Draft PR).** The app opens the G2 terrain test arena: destructible brick, steel that level-3 shots break, water, forest, ice slides, and the original G1 combat. It is drawn with **PLACEHOLDER** shapes. Final art is G3, at the approved concept A (24 px tiles, 640×360).

## Requirements

| | Linux | macOS |
|---|---|---|
| Run | `love` 11.5 | [LÖVE 11.5](https://github.com/love2d/love/releases/tag/11.5) (`love.app`, universal) |
| Develop | `luajit`, `luarocks`, `gcc`, `curl`, `unzip`, `zip`, `xvfb` (smoke tests) | `brew install luajit luarocks` |

## Run

```sh
love .                                          # Linux / love on PATH
/Applications/love.app/Contents/MacOS/love .    # macOS
love . --arena=g1_arena                         # start in the G1 combat arena
```

Controls in the test arenas (`g2_terrain`, the default, and `g1_arena`):

| Action | Keys |
|---|---|
| P1 move / fire | WASD / Space |
| P2 move / fire | arrow keys / Right Ctrl or keypad Enter |
| Gamepads | first pad → P1, second pad → P2 (D-pad / left stick, A or B fires) |
| Restart the arena (keeps the arena, the level and the F5 copy) | F2 |
| Debug tuning editor (in-memory copy) | F5, then `[` `]` select, `-` `=` adjust, Backspace reset |
| Switch arena (terrain ↔ G1) | F6 |
| Players' upgrade level 0 → 1 → 2 → 3 (3 breaks steel) | F7 (restarts the arena; recorded in replays) |
| Save the input recording (replay) | F8 (a new file in the LÖVE save directory, `replays/`; never overwrites; the HUD shows `REPLAY SAVED` or `REPLAY SAVE FAILED`) |
| Fullscreen | F11 or Alt+Enter |
| Debug overlay | F3 |
| Scale mode (integer / fit) | F4 |
| Quit | Esc |

## Develop

```sh
make bootstrap   # pinned local toolchain → .rocks/<platform>/, .tools/<platform>/
make check       # fmt-check + lint + test + validate + smoke (both arenas) + hidpi-sim (required before every PR)
make test        # unit tests only
make love        # dist/eagle-defense.love (+ .sha256)
make evidence    # review evidence package → evidence/
make mockups     # re-render the G1 art-direction concepts (docs/art/mockups/)
luajit tools/update_goldens.lua [--check]   # regenerate / verify golden replays
luajit tools/validate_levels.lua            # validate levels/ (also in make validate)
```

Native tools are installed per platform (`make toolchain` shows the resolved key, e.g. `darwin-arm64` or `linux-arm64`). A macOS host and a Linux container can share one checkout: run `make bootstrap` once in each, and neither overwrites the other's binaries. See [docs/CI.md](docs/CI.md#toolchain-layout).

## Documentation

- [Game design](docs/GAME_DESIGN.md)
- [Technical design](docs/TECHNICAL_DESIGN.md)
- [Art direction](docs/ART_DIRECTION.md)
- [Roadmap](docs/ROADMAP.md) and the [G1 plan](docs/plans/G1_PLAN.md)
- [CI](docs/CI.md)
- [Agent instructions](AGENTS.md)

## License

- **Source code:** [PolyForm Noncommercial 1.0.0](LICENSE). Use, study, modify and share for any noncommercial purpose. Commercial use requires permission.
- **Game content** (`assets/`, `levels/`, name and logo): proprietary, all rights reserved.

See [NOTICE.md](NOTICE.md) for details and third-party licenses.
