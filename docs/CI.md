# CI

## Current state (owner decision, 2026-11-26)

- **CI is deferred.** The quality gate is a **local `make check`**:
  - `fmt-check`
  - `lint` (luacheck + shellcheck)
  - `test` (busted)
  - `validate` (architecture boundaries, asset manifest)
  - `smoke` (headless LÖVE with pixel-perfect scaling check)
- Every milestone evidence package (`make evidence`) contains the full `make check` output for the exact commit.
- The **target CI platform is the company GitLab**, with self-hosted runners. The project will move there; GitHub is temporary hosting.

## Contract for the future GitLab pipeline

The Makefile is the CI contract, so the pipeline only has to provide the toolchain and call make:

```yaml
# sketch only, not active
check:
  tags: [eagle-defense]          # self-hosted runner tag, to be agreed with company IT
  script:
    - make bootstrap
    - make check
    - make love
  artifacts:
    paths: [dist/, build/]
```

Runner prerequisites (Linux):

```sh
apt-get install -y love luajit luarocks liblua5.1-0-dev build-essential xvfb zip unzip curl git shellcheck
```

`make bootstrap` downloads pinned tools from luarocks.org and from GitHub releases (StyLua). If the company network blocks those hosts, mirror the artifacts internally and keep the SHA-256 pins.

## Toolchain layout

Native tools are installed per platform, so one checkout can be shared by several machines (for example a macOS host and the Docker sandbox that mounts the same directory):

```
.rocks/<platform>/   busted, luacheck and their C modules (luafilesystem, luasystem, lua-term)
.tools/<platform>/   StyLua
```

- `<platform>` is `<os>-<arch>` from `tools/platform.sh`: lowercase `uname -s`, with the architecture normalized to `x86_64` or `arm64`. Supported keys: `darwin-arm64`, `darwin-x86_64`, `linux-arm64`, `linux-x86_64`. An Apple-silicon Mac (`darwin-arm64`) and its Linux container (`linux-arm64`) get different directories.
- `make toolchain` prints the resolved key, the directories and the Lua search paths. `tools/bootstrap.sh --print-plan` prints the same directories plus the pinned versions and the StyLua asset and SHA-256, without installing anything.
- Run `make bootstrap` once per platform. Before that, `make check` on that platform stops with "toolchain for <platform> is not installed … run: make bootstrap" instead of running another platform's binaries.
- Versions and checksums are unchanged: busted 2.3.0-1, luacheck 1.2.0-1, StyLua 2.6.0 with a SHA-256 pin per platform. `tests/tools/toolchain_spec.lua` locks them.
- **Migrating from the flat layout** (`.rocks/bin`, `.rocks/lib`, `.rocks/share`, `.tools/stylua`): it is no longer used. `make bootstrap` reports it but never deletes it, because in a shared checkout it may belong to another machine. Remove it by hand once every machine has bootstrapped: `rm -rf .rocks/bin .rocks/lib .rocks/share .tools/stylua`.

## Running the gate on macOS (prerequisites)

- [LÖVE 11.5](https://github.com/love2d/love/releases/tag/11.5) in `/Applications/love.app`. `tools/smoke.sh` finds it automatically if `love` is not on `PATH`.
- `brew install luajit luarocks shellcheck`, then `make bootstrap`, which installs into `.rocks/darwin-<arch>/` and `.tools/darwin-<arch>/` (not yet verified natively).
- `zip`, `unzip`, `perl`, `od` and `shasum` ship with macOS. GNU `timeout` is **not** required: `tools/smoke.sh` falls back to `gtimeout`, then to `perl`.
- The shell tools must run under macOS `/bin/bash` 3.2 and the BSD userland. Output whose layout differs between GNU and BSD (for example `od`, which on macOS adds an empty line after `-An` output) is parsed by `tools/lib/portable.sh`, never line by line. Numbers that are compared with app output are formatted with `printf_c` (C locale).
- Smoke opens real windows, so run it from a logged-in GUI session. Do not use SSH without a display or a LaunchDaemon.
- Default macOS smoke sizes are the logical sizes `800x600 1024x640 1280x720`. These must fit on the display, otherwise the run fails with "window logical size not applied". Override them with `SMOKE_SIZES="..."`.
- On Retina, physical = logical × 2. The pixel-perfect check runs on physical pixels, so for example logical 1280×720 is verified as 2560×1440 at 4×. The game canvas itself must stay 640×360 texels at DPI 1 on every display (TECHNICAL_DESIGN §2, "Pixel density"); the smoke fails with an explicit `problems=canvas_pixels:…;canvas_dpi:…` otherwise.
- `make check` also runs `tools/hidpi_sim.sh` (SIMULATED HiDPI resource defaults, integer + fit). On macOS it opens real windows at the logical sizes `1366x768` (integer) and `900x600` (fit); override them with `HIDPI_SIM_INTEGER_SIZE` / `HIDPI_SIM_FIT_SIZE` if the display is smaller.

Native macOS smoke results are automated native evidence. They do not replace the owner's manual checklist (`docs/acceptance/`).

## Evidence packages

- `make evidence` produces **final** review evidence. It fails closed: a clean tree is required (no untracked files, and no ignored files in source paths), every check must pass, the `.love` is built from the exact commit (`git archive`), mandatory files must be present, and checksums are verified before and after archiving.
- `make evidence-dev` produces a development snapshot from a dirty tree. It is named `*-DEV` and marked "NOT REVIEW EVIDENCE".
- Packages include `hidpi-sim/` (SIMULATED HiDPI evidence) and `native/`, a copy of every preserved native artifact set in `native-evidence/<set>/`. That directory is gitignored and is **not** removed by `make clean`. Each set must verify against its `SHA256SUMS`, and every hash must be recorded in a committed `docs/evidence/` report; otherwise packaging fails.

## Later (owner note, 2026-11-26)

GitHub may also run CI later, but **tests only** (`make bootstrap && make test`). This is not set up yet. The runner type (self-hosted or GitHub-hosted) will be decided when it is enabled. A GitHub Actions workflow was drafted in G0 and removed; it is in the git history of PR #1 if needed.
