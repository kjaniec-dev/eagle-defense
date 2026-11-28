# G2 — native macOS acceptance (terrain, destruction, ice)

Fill this in on a real Mac. Sandbox evidence (Linux, Xvfb, software GL) does **not** count here. Plan: `docs/plans/G2_PLAN.md` §16 and §19. The owner's native acceptance **includes** the brick-destruction feel and the ice-slide tuning.

**Status: NOT RUN.**

## Environment

| Field | Value |
|---|---|
| Date | |
| Mac model / chip | |
| macOS version | |
| Display / refresh rate | |
| LÖVE version (`love --version`) | |
| Commit SHA (`git rev-parse HEAD`) | |

## 1. Automated gate (Terminal, repo root)

```sh
git fetch origin && git checkout g2/battlefield && git pull --ff-only
git rev-parse HEAD
make check 2>&1 | tee build/native-check.log; echo "make check exit=${PIPESTATUS[0]}"
grep -E '^SMOKE (OK|FAIL)' build/smoke*.log | sed 's/ out=.*//'
grep -E '^(CASE|hidpi-sim:)' build/native-check.log
```

Expected:
- `make check exit=0`, with the golden replays (G1 and G2) matching natively in `make test`.
- 6 × `SMOKE OK`, at 800x600, 1024x640 and 1280x720, with `problems=none`:
  - 3 × `p1=1408,2688 p2=1664,2652 hash=581f15d4 arena=g1_arena` (the G1 smoke, unchanged);
  - 3 × `p1=512,2688 p2=2304,3072 hash=4b7aaef1 arena=g2_terrain` (the terrain smoke).
- `hidpi-sim: OK` with 8 × `CASE … PASS`. If its 1366×768 window does not fit, run `HIDPI_SIM_INTEGER_SIZE=1280x720 make hidpi-sim`.

| Check | Result |
|---|---|
| `make check` exit code | |
| Busted (successes / failures) | |
| Smoke G1 × 3 (hash `581f15d4`) | |
| Smoke terrain × 3 (hash `4b7aaef1`) | |
| hidpi-sim 8/8 | |

## 2. Manual checks (`love .`, the terrain arena opens by default)

F6 switches to the G1 arena and back. F7 sets the players' level (shown on the HUD as `LEVEL n (F7)`).

| # | Check | Pass / fail / notes |
|---|---|---|
| 1 | **Brick feel.** P2 (arrows + Right Ctrl) starts touching its wall: point-blank shots dig 2 cells wide × 1 cell deep per shot. A tank cannot pass a 2-cell hole; three neighbouring strips let it through. Is the ½-tile strip (G2-D2) acceptable, or should it change (e.g. 4 cells wide, or 2 deep)? F5 offers `brick_strip_cells` and `brick_strip_depth` to try. | |
| 2 | **Steel.** Normal shots are absorbed by the steel band at the top right. F7 to `LEVEL 3`: each shot breaks 1 tile × ½ tile of steel, then the brick behind it. The X block (rows 6–7) never breaks, at any level. | |
| 3 | **Water.** Tanks cannot enter the channel; they pass the 1-tile gap. Bullets cross water (the turret lane, and shots fired up over the channel). | |
| 4 | **Forest.** Tanks and bullets in the forest patches are fully hidden; tanks drive through. | |
| 5 | **Ice feel.** P1 (WASD) drives up onto the ice and releases: it slides **192 u = ¾ tile** (UNV). Turning or reversing on the ice also slides; pressing the slide direction cancels it. Slides stop at the steel above and the water on the right, and end on leaving the ice. Sign off `ice_slide_distance` as `TUNED (owner, date)`, or ask for a change (try values with F5, step 8 u). | |
| 6 | **Smoothness.** Motion stays smooth at 60 Hz while terrain is being destroyed (F3 shows FPS and frame time). | |
| 7 | **Replays.** In the terrain arena at `LEVEL 3`, press F8 several times during play (`REPLAY SAVED`). Copy the saved files from the LÖVE save directory (`replays/`) for the evidence; they must replay identically (`tests/sim` runner; the sandbox can verify them). | |

## 3. Owner decisions recorded here

| Item | Decision |
|---|---|
| `brick_strip_cells` × `brick_strip_depth` (default 2 × 1, UNV) | |
| `ice_slide_distance` (default 192 u, UNV) | |
| Anything else to change before merge | |
