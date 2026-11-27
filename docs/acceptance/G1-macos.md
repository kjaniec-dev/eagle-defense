# G1 — native macOS acceptance (feel and art direction)

Fill this in on a real Mac, using a keyboard and, if available, a gamepad. Sandbox evidence (Linux, Xvfb, software GL) does **not** count here. Plan: `docs/plans/G1_PLAN.md` §10.

**Status: PASS** (owner, 2026-11-27): automated gate, manual feel and art choice. Gamepad: NOT TESTED (optional, non-blocking). Final independent technical review: PASS. Merge of PR #3 authorized at the reviewed HEAD `c82ff864c96b4ab8497fc5ec307b023b2b14e58a`.

Native artifacts: `native-evidence/g1-final-native-acceptance-c82ff86-2026-11-27/` (outside Git and `build/`; `SHA256SUMS` SHA-256 `74133cbf9bf61b019a731a6cb504209063fdfeecaadd057b0c779d754ce7aa99`; provenance in its `README.txt`). Summary: `docs/evidence/SUMMARY.md`, "Native acceptance".

## Environment

| Field | Value |
|---|---|
| Date | 2026-11-27 |
| Mac model / chip | Apple M3 Pro |
| macOS version | macOS (version not recorded); renderer `OpenGL / 4.1 Metal - 91.7 / Apple / Apple M3 Pro` |
| Display / refresh rate (60 / 120 Hz) | Retina, DPI 2.00; refresh rate not recorded |
| LÖVE version (`love --version`) | not recorded (project pins 11.5) |
| Commit SHA (`git rev-parse HEAD`) | `c82ff864c96b4ab8497fc5ec307b023b2b14e58a` (owner-reported; the shared working tree's reflog has HEAD at `c82ff86`, clean, during both runs) |
| Gamepad model (if used) | none (gamepad NOT TESTED) |

## 1. Automated gate (Terminal, repo root)

```sh
git fetch origin && git checkout g1/combat && git pull --ff-only
git rev-parse HEAD
make check 2>&1 | tee build/native-check.log; echo "make check exit=${PIPESTATUS[0]}"
grep -E '^SMOKE (OK|FAIL)' build/smoke*.log
grep -E '^(CASE|hidpi-sim:)' build/native-check.log
```

Expected: `make check exit=0`; 3 × `SMOKE OK … state=arena p1=1408,2688 p2=1664,2652 hash=581f15d4 … problems=none` (the same sim hash as in the sandbox, which proves cross-platform determinism of the 120-tick script); `hidpi-sim: OK`, 8 × `CASE … PASS`. The golden replays (`tests/sim/replay_spec.lua`) run in `make test` and must match natively too. If the harness's 1366×768 window does not fit, run `HIDPI_SIM_INTEGER_SIZE=1280x720 make hidpi-sim`.

**Result (native, 2026-11-27): PASS.**
- Formatting: PASS.
- Lint: 0 warnings / 0 errors in 98 files.
- Shellcheck: PASS.
- Busted: 283 successes, 0 failures, 0 errors, 0 pending. The golden replays match natively.
- Boundaries: OK, 15 pure files.
- Assets: OK.
- DPI: OK, 30 files.
- Smoke: 3/3 `SMOKE OK` at 800x600, 1024x640 and 1280x720 (physical ×2). Every line is `ticks=120 state=arena p1=1408,2688 p2=1664,2652 hash=581f15d4`, with `mismatches=0`, `letterbox_bad=0` and `problems=none`. The sim hash is the same as in the sandbox.
- HiDPI harness: 8 × `CASE … PASS` with the integer window overridden to 1280x720, then `hidpi-sim: OK`. This is SIMULATED resource DPI on a real DPI-2 window.
- The PR #2 BSD `grep: empty (sub)expression` message no longer appears.
- Exit code: the log ends with `make check exit=` and no value, because the pipe status was not captured. No numeric exit code is recorded. The log reaches the final gate step, and the owner reports a successful finish.

## 2. Feel (`/Applications/love.app/Contents/MacOS/love .`)

The arena opens directly. P1: WASD + Space (gold). P2: arrows + Right Ctrl (teal). Grey targets count hits; the turret at the top of column 10 fires down its lane every 2 s.

| # | Check | Expected | Pass/Fail | Notes |
|---|---|---|---|---|
| 1 | Start / stop | Tanks start and stop instantly, with no perceived lag | PASS | |
| 2 | Lane entry | From the corridor, the 1-tile lanes (columns 6 and 10, and the gaps in the block row) can be entered on the first try at an intersection | PASS | turning and narrow corridor entry |
| 3 | Speeds | Movement and bullet speeds feel classic. Sign off the values (see "Tuning sign-off") or ask for changes | PASS | player 7, bullets 17/34 approved |
| 4 | Shooting | One press = one shot (holding fire does not repeat). At level 0 a second shot only fires after the first bullet is gone. With F5 → `arena_player_level` = 2: two bullets in flight; level ≥ 1 bullets are clearly faster | PASS | normal and fast bullets; two active bullets at level 2 |
| 5 | Cancellation | Standing in the corridor under the turret's lane and firing up cancels its bullets visibly and reliably | PASS | |
| 6 | Smoothness | Motion is smooth at 60 Hz with no hitching (120 Hz ProMotion is acceptable; F3 shows ticks/frame 0/1 alternating) | PASS | |
| 7 | Gamepad (if available) | D-pad / left stick move P1, A or B fires; second pad drives P2 | NOT TESTED | optional, non-blocking; gamepads are a G6 native gate |
| 8 | Respawn | When the turret hits you, the tank reappears at its spawn on the next tick; if the other tank sits on the spawn, it waits until the spawn is free | PASS | respawn after being hit |

### Tuning sign-off
**Done (owner, 2026-11-27):** `player_speed = 7`, `bullet_speed_normal = 17`, `bullet_speed_fast = 34`, committed as `TUNED (owner, 2026-11-27)`. The rest of this section describes how to request further changes.

F5 opens the debug editor (an in-memory copy; the HUD shows `TUNING MODIFIED`). `[` / `]` select, `-` / `=` adjust (each change restarts the arena), Backspace restores the committed values. Nothing is written to disk. Report the values you want; they are then committed to `config/tuning.lua` with the tag `TUNED (owner, <date>)`, and the golden replays are regenerated with `tools/update_goldens.lua` (called out in the PR). Subjective tuning is never tagged MEASURED.

Optional for bug reports: F8 saves the current input recording to `~/Library/Application Support/LOVE/eagle-defense/replays/` as `arena-<date-time>-t<tick>.lua` (a new file each time; the HUD shows `REPLAY SAVED`, or `REPLAY SAVE FAILED` with the reason in the terminal). Pressing F8 again later in the same run saves a second, longer recording; both replay correctly.

**Repeated F8 saves (native): PASS.** In one session the owner saved five separate replay files, at ticks 2159, 2269, 2346, 2360 and 2373. The files stay in the owner's save directory and are not copied into the evidence.

## 3. Art direction (decision G1-D4)

Open the PNGs in `docs/art/mockups/` on the real display at 100 % (no viewer scaling): `A-1920x1080.png` (24 px tiles, 3×), `B-1920x1080-integer.png` and `B-1920x1080-fit.png` (32 px tiles, 2× letterboxed / 2.5× fit), and `compare-1920x1080.png`. The trade-offs and the recommendation are in `docs/art/mockups/README.md`.

| # | Check | Result |
|---|---|---|
| 9 | Choice | **A approved** (owner, 2026-11-27): internal canvas 640×360, 24 px tiles, 312×312 px battlefield; the simulation stays resolution-independent. Recorded in ART_DIRECTION §3 |
| 10 | Quality bar | The concept is approved, not final production art. The G3 improvement requirements stand (ART_DIRECTION §3a). No external commission yet: G3 first explores AI-authored improvements and, if appropriate, the bounded Blender MCP pipeline |

## Result

Record PASS / FAIL / NOT TESTED per item. Never mark an item that was not run as passed. Move `build/native-check.log` and `build/smoke*` to `native-evidence/g1-<date>/` (with `SHA256SUMS`) if they should survive `make clean`.

**Recorded 2026-11-27:**
- Automated gate: PASS.
- Feel items 1–6 and 8: PASS.
- Repeated F8 saves: PASS.
- Item 7 (gamepad): NOT TESTED.
- Art: A approved.

Artifacts were preserved before any further sandbox run, in `native-evidence/g1-final-native-acceptance-c82ff86-2026-11-27/`:

| Folder | Content |
|---|---|
| `run-a-make-check-2213/` | full `make check` log, smoke and harness |
| `run-b-smoke-hidpi-2316/` | second smoke and harness run; no console log on disk |
| `aborted-2212/` | an empty log |

Key SHA-256:

| File | SHA-256 |
|---|---|
| `run-a…/native-check.log` | `cf8c0f3d65437efbf93d757834dd791dae14e0071f6cd2e3b31627daaecdcd6d` |
| smoke canvas (all six smoke PNGs, both runs) | `bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3` |
