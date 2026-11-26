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

A native macOS smoke test can run on a macOS runner in a logged-in GUI session with
`make smoke LOVE=/Applications/love.app/Contents/MacOS/love`. This does not replace the owner's manual checklist (`docs/acceptance/`).

## Later (owner note, 2026-11-26)

GitHub may also run CI later, but **tests only** (`make bootstrap && make test`). This is not set up yet. The runner type (self-hosted or GitHub-hosted) will be decided when it is enabled. A GitHub Actions workflow was drafted in G0 and removed; it is in the git history of PR #1 if needed.
