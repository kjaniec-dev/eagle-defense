# G1 — native macOS acceptance (feel and art direction)

Fill this in on a real Mac, using a keyboard and, if available, a gamepad. Sandbox evidence (Linux, Xvfb, software GL) does **not** count here. Plan: `docs/plans/G1_PLAN.md` §10.

**Status: PENDING** (owner).

## Environment

| Field | Value |
|---|---|
| Date | |
| Mac model / chip | |
| macOS version | |
| Display / refresh rate (60 / 120 Hz) | |
| LÖVE version (`love --version`) | (project pins 11.5) |
| Commit SHA (`git rev-parse HEAD`) | must equal the G1 PR HEAD under review |
| Gamepad model (if used) | |

## 1. Automated gate (Terminal, repo root)

```sh
git fetch origin && git checkout g1/combat && git pull --ff-only
git rev-parse HEAD
make check 2>&1 | tee build/native-check.log; echo "make check exit=${PIPESTATUS[0]}"
grep -E '^SMOKE (OK|FAIL)' build/smoke*.log
grep -E '^(CASE|hidpi-sim:)' build/native-check.log
```

Expected: `make check exit=0`; 3 × `SMOKE OK … state=arena p1=1384,2688 p2=1664,2712 hash=0c5c7a9c … problems=none` (the same sim hash as in the sandbox, which proves cross-platform determinism of the 120-tick script); `hidpi-sim: OK`, 8 × `CASE … PASS`. The golden replays (`tests/sim/replay_spec.lua`) run in `make test` and must match natively too. If the harness's 1366×768 window does not fit, run `HIDPI_SIM_INTEGER_SIZE=1280x720 make hidpi-sim`.

## 2. Feel (`/Applications/love.app/Contents/MacOS/love .`)

The arena opens directly. P1: WASD + Space (gold). P2: arrows + Right Ctrl (teal). Grey targets count hits; the turret at the top of column 10 fires down its lane every 2 s.

| # | Check | Expected | Pass/Fail | Notes |
|---|---|---|---|---|
| 1 | Start / stop | Tanks start and stop instantly, with no perceived lag | | |
| 2 | Lane entry | From the corridor, the 1-tile lanes (columns 6 and 10, and the gaps in the block row) can be entered on the first try at an intersection | | |
| 3 | Speeds | Movement and bullet speeds feel classic. Sign off the values (see "Tuning sign-off") or ask for changes | | |
| 4 | Shooting | One press = one shot (holding fire does not repeat). At level 0 a second shot only fires after the first bullet is gone. With F5 → `arena_player_level` = 2: two bullets in flight; level ≥ 1 bullets are clearly faster | | |
| 5 | Cancellation | Standing in the corridor under the turret's lane and firing up cancels its bullets visibly and reliably | | |
| 6 | Smoothness | Motion is smooth at 60 Hz with no hitching (120 Hz ProMotion is acceptable; F3 shows ticks/frame 0/1 alternating) | | |
| 7 | Gamepad (if available) | D-pad / left stick move P1, A or B fires; second pad drives P2 | | |
| 8 | Respawn | When the turret hits you, the tank reappears at its spawn on the next tick; if the other tank sits on the spawn, it waits until the spawn is free | | |

### Tuning sign-off
F5 opens the debug editor (an in-memory copy; the HUD shows `TUNING MODIFIED`). `[` / `]` select, `-` / `=` adjust (each change restarts the arena), Backspace restores the committed values. Nothing is written to disk. Report the values you want; they are then committed to `config/tuning.lua` with the tag `TUNED (owner, <date>)`, and the golden replays are regenerated with `tools/update_goldens.lua` (called out in the PR). Subjective tuning is never tagged MEASURED.

Optional for bug reports: F8 saves the current input recording to `~/Library/Application Support/LOVE/eagle-defense/replays/`.

## 3. Art direction (decision G1-D4)

Open the PNGs in `docs/art/mockups/` on the real display at 100 % (no viewer scaling): `A-1920x1080.png` (24 px tiles, 3×), `B-1920x1080-integer.png` and `B-1920x1080-fit.png` (32 px tiles, 2× letterboxed / 2.5× fit), and `compare-1920x1080.png`. The trade-offs and the recommendation are in `docs/art/mockups/README.md`.

| # | Check | Result |
|---|---|---|
| 9 | Choice | A (24 px), B (32 px), or a revision request; record it, with feedback, in ART_DIRECTION §3 |
| 10 | Quality bar | Do the concepts meet the premium bar, or should hero sprites be commissioned (ART_DIRECTION §7, Pipeline B)? |

## Result

Record PASS / FAIL / NOT TESTED per item. Never mark an item that was not run as passed. Move `build/native-check.log` and `build/smoke*` to `native-evidence/g1-<date>/` (with `SHA256SUMS`) if they should survive `make clean`.
