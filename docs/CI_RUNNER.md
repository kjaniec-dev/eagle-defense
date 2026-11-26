# Self-hosted CI runner setup

CI runs **only** on self-hosted runners (owner requirement). As of 2026-11-26, **no runner is registered** for this repository, so CI cannot run until the owner completes the steps below.

## Security first

The repository is currently **public**. A self-hosted runner on a public repo is dangerous: a pull request from a fork could run arbitrary code on your machine.

- **Decision Q-G0-2 (approved): make the repository private until release.** Use Settings → General → Danger Zone → Change visibility. The owner performs this step.
- The workflow already skips fork PRs (`head.repo.full_name == github.repository`). This is defence in depth, not a replacement for making the repo private.
- Also set Settings → Actions → General → "Fork pull request workflows" to require approval for all outside collaborators.
- Run the runner under a dedicated, unprivileged user account. Do not use your main account.

## Linux runner (required): labels `self-hosted, Linux, eagle-defense`

Any x86_64 or arm64 Linux host works, such as a VM, a home server or a Docker host.

1. Install the prerequisites (Ubuntu/Debian):
   ```sh
   sudo apt-get install -y love luajit luarocks liblua5.1-0-dev build-essential \
     xvfb zip unzip curl git shellcheck
   love --version   # must print 11.5
   ```
2. Go to Settings → Actions → Runners → **New self-hosted runner** → Linux, and follow the download and `./config.sh` steps. When `config.sh` asks for additional labels, enter `eagle-defense`. GitHub adds `self-hosted` and `Linux` automatically.
3. Run it as a service: `sudo ./svc.sh install && sudo ./svc.sh start`.

## macOS runner (optional, native smoke): labels `self-hosted, macOS, ARM64, eagle-defense`

1. Install [LÖVE 11.5](https://github.com/love2d/love/releases/tag/11.5) into `/Applications/love.app`. Then run `brew install luajit luarocks`.
2. Register the runner as above (macOS / ARM64) with the extra label `eagle-defense`.
3. The smoke test opens a real window, so the runner must run **in a logged-in GUI session**: use `./run.sh` in Terminal, or a LaunchAgent, not a LaunchDaemon.
4. Enable the job: Settings → Secrets and variables → Actions → Variables → `MACOS_RUNNER = 1`.

A macOS runner's smoke results are automated native evidence. They do **not** replace the owner's manual acceptance checklist (input feel, gamepads, audio, Retina appearance).

## Verify

Push a commit to a `g*/` branch or open a PR. The **CI / Linux checks** job should pick up the job on your runner. Its artifacts include `dist/eagle-defense.love` and the smoke screenshots.
