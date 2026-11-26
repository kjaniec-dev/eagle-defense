# Eagle Defense

A retro top-down tank arcade game, with single player and 2-player local co-op, built with [LÖVE](https://love2d.org) 11.5. It is a commercial project targeting Steam.

> **Status: G0 — project foundation.** There is no gameplay yet. The app opens a debug sandbox with a **PLACEHOLDER** test pattern.

## Requirements

| | Linux | macOS |
|---|---|---|
| Run | `love` 11.5 | [LÖVE 11.5](https://github.com/love2d/love/releases/tag/11.5) (`love.app`, universal) |
| Develop | `luajit`, `luarocks`, `gcc`, `curl`, `unzip`, `zip`, `xvfb` (smoke tests) | `brew install luajit luarocks` |

## Run

```sh
love .                                          # Linux / love on PATH
/Applications/love.app/Contents/MacOS/love .    # macOS
```

Controls in the G0 sandbox:

| Action | Keys |
|---|---|
| Move P1 marker | WASD |
| Move P2 marker | arrow keys |
| Gamepads | first pad → P1, second pad → P2 (D-pad / left stick) |
| Fullscreen | F11 or Alt+Enter |
| Debug overlay | F3 |
| Scale mode (integer / fit) | F4 |
| Quit | Esc |

## Develop

```sh
make bootstrap   # pinned local toolchain → .rocks/, .tools/
make check       # fmt-check + lint + test + validate + smoke (required before every PR)
make test        # unit tests only
make love        # dist/eagle-defense.love (+ .sha256)
make evidence    # review evidence package → evidence/
```

## Documentation

- [Game design](docs/GAME_DESIGN.md)
- [Technical design](docs/TECHNICAL_DESIGN.md)
- [Art direction](docs/ART_DIRECTION.md)
- [Roadmap](docs/ROADMAP.md)
- [CI runner setup](docs/CI_RUNNER.md)
- [Agent instructions](AGENTS.md)

## License

Proprietary. All rights reserved. See [LICENSE](LICENSE). Third-party tooling used only for development (busted, luacheck, StyLua, actionlint) is not distributed with the game.
