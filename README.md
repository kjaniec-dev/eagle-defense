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
make bootstrap   # pinned local toolchain → .rocks/<platform>/, .tools/<platform>/
make check       # fmt-check + lint + test + validate + smoke (required before every PR)
make test        # unit tests only
make love        # dist/eagle-defense.love (+ .sha256)
make evidence    # review evidence package → evidence/
```

Native tools are installed per platform (`make toolchain` shows the resolved key, e.g. `darwin-arm64` or `linux-arm64`). A macOS host and a Linux container can share one checkout: run `make bootstrap` once in each, and neither overwrites the other's binaries. See [docs/CI.md](docs/CI.md#toolchain-layout).

## Documentation

- [Game design](docs/GAME_DESIGN.md)
- [Technical design](docs/TECHNICAL_DESIGN.md)
- [Art direction](docs/ART_DIRECTION.md)
- [Roadmap](docs/ROADMAP.md)
- [CI](docs/CI.md)
- [Agent instructions](AGENTS.md)

## License

- **Source code:** [PolyForm Noncommercial 1.0.0](LICENSE). Use, study, modify and share for any noncommercial purpose. Commercial use requires permission.
- **Game content** (`assets/`, `levels/`, name and logo): proprietary, all rights reserved.

See [NOTICE.md](NOTICE.md) for details and third-party licenses.
