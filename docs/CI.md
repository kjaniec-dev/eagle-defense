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

## Running the gate on macOS (prerequisites)

- [LÖVE 11.5](https://github.com/love2d/love/releases/tag/11.5) in `/Applications/love.app`. `tools/smoke.sh` finds it automatically if `love` is not on `PATH`.
- `brew install luajit luarocks shellcheck`, then `make bootstrap` (not yet verified natively).
- `zip`, `unzip`, `perl`, `od` and `shasum` ship with macOS. GNU `timeout` is **not** required: `tools/smoke.sh` falls back to `gtimeout`, then to `perl`.
- Smoke opens real windows, so run it from a logged-in GUI session. Do not use SSH without a display or a LaunchDaemon.
- Default macOS smoke sizes are the logical sizes `800x600 1024x640 1280x720`. These must fit on the display, otherwise the run fails with "window logical size not applied". Override them with `SMOKE_SIZES="..."`.
- On Retina, physical = logical × 2. The pixel-perfect check runs on physical pixels, so for example logical 1280×720 is verified as 2560×1440 at 4×.

Native macOS smoke results are automated native evidence. They do not replace the owner's manual checklist (`docs/acceptance/`).

## Evidence packages

- `make evidence` produces **final** review evidence. It fails closed: a clean tree is required (no untracked files, and no ignored files in source paths), every check must pass, the `.love` is built from the exact commit (`git archive`), mandatory files must be present, and checksums are verified before and after archiving.
- `make evidence-dev` produces a development snapshot from a dirty tree. It is named `*-DEV` and marked "NOT REVIEW EVIDENCE".

## Later (owner note, 2026-11-26)

GitHub may also run CI later, but **tests only** (`make bootstrap && make test`). This is not set up yet. The runner type (self-hosted or GitHub-hosted) will be decided when it is enabled. A GitHub Actions workflow was drafted in G0 and removed; it is in the git history of PR #1 if needed.
