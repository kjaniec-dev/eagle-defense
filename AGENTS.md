# AGENTS.md — Eagle Defense

A retro top-down tank arcade game built on LÖVE 11.5 (LuaJIT). It has a single-player mode and a 2-player local co-op mode. It is a commercial release targeting Steam.

## Read first
- `docs/GAME_DESIGN.md`: rules, the reference behavior matrix (with confidence tags) and invariants
- `docs/TECHNICAL_DESIGN.md`: architecture, module boundaries, units and testing
- `docs/ART_DIRECTION.md`: visual rules and the IP-distance rules
- `docs/ROADMAP.md`: milestones; only the current approved milestone is in scope

## Commands
```sh
make bootstrap   # local toolchain (.rocks/, stylua)
make check       # fmt-check + lint + test + validate + smoke  — must be green before any PR
make test        # busted --lua=luajit
love .           # run the game
```

## Hard rules
- **Scope:** implement only the approved milestone. Scope changes, gameplay-rule changes, contract or invariant changes, and art-direction changes all require owner approval.
- **Architecture:** `src/core` and `src/sim` are pure Lua. They must not reference `love`, `render`, `audio`, `input`, `ui` or `app`, and a test enforces this.
- **Determinism:** the simulation runs at a fixed 60 Hz, uses integer subpixel math and the project RNG only, and always iterates arrays in order. `math.random`, `os.time` and `pairs()`-dependent ordering are not allowed in sim.
- **Presentation:** VFX and audio consume sim events and never mutate sim state.
- **Fidelity:** never present an unverified reference behavior as fact. Record it as UNV or as an assumption in GAME_DESIGN.
- **IP:** never copy code, ROM data, sprites, maps, audio, logos or eagle art from Battle City / Tank 1990 or any other game. Every shipped asset needs an entry in `assets/manifest.lua` and `assets/PROVENANCE.md`.
- **Placeholders:** placeholder assets must carry `PLACEHOLDER` in their filename and their manifest entry.
- **Tests (owner rule):** tests must pass and must **prove the game works**, not just exercise units. Every gameplay feature gets scenario tests that drive the simulation with InputFrames and assert observable outcomes (positions, hits, destruction, score, stage state). The headless smoke test runs the real app. Add tests with each behavior change, and add a regression test for each bug fixed. Never weaken or skip a test to make it pass. Golden fixtures may be regenerated only with `tools/update_goldens.lua`, and the regeneration must be called out in the PR.
- **Evidence:** keep sandbox evidence (Linux, Xvfb, software GL) separate from native evidence. Never claim native rendering, audio, performance or controller behavior was verified unless it was actually tested on that platform.
- **CI:** deferred. The target is the company GitLab with self-hosted runners (`docs/CI.md`). Until then, run `make check` locally before every PR/MR and include its output in the evidence.
- **Git:** work on a milestone branch and open a Draft PR. **Never merge without explicit owner authorization**, and never start the next milestone automatically.
- **Dependencies:** no new runtime dependencies or frameworks (ECS, OOP libraries, etc.) without approval.

## Style
- StyLua formatting and clean luacheck. Use 2-space indentation, `local` everywhere and one module per file returning a table.
- Prefer small pure functions over class hierarchies. Data goes in `config/` and `levels/`.
