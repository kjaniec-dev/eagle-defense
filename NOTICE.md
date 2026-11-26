# Notices

## Source code

The source code is licensed under the **PolyForm Noncommercial License 1.0.0**. See [LICENSE](LICENSE) and <https://polyformproject.org/licenses/noncommercial/1.0.0>.

Any noncommercial purpose is permitted, including reading, studying, modifying and sharing the code. Commercial use, such as selling the game or a derivative, requires a separate license from the copyright holder.

## Game content (proprietary)

Copyright (c) 2026 kjaniec-dev. All rights reserved.

The following are **not** covered by the PolyForm license. They may not be copied, redistributed or used in other works without written permission.

- everything under `assets/` (sprites, tilesets, shaders, audio, music, fonts created for the game)
- everything under `levels/`
- the G1 concept art in `docs/art/mockups/` and the pixel-art definitions it is rendered from (`tools/mockup/art/`): authored by an AI agent (Claude) as code-defined pixel art, never shipped (provenance in `docs/art/mockups/README.md`)
- the "Eagle Defense" name, logo and visual identity

Third-party assets inside `assets/` keep their own licenses, which are recorded in `assets/PROVENANCE.md` and `assets/manifest.lua`.

## Third-party software

- **LÖVE** (zlib license) and its bundled libraries are used to run and package the game. See <https://love2d.org/wiki/License>.
- Development tools (busted, luacheck, StyLua, shellcheck) are installed locally by `make bootstrap`. They are not part of this repository or of the distributed game.

## Unaffiliated

Eagle Defense is an independent game. It is not affiliated with, endorsed by, or derived from the assets of Namco/Bandai Namco's *Battle City* or any other game.
