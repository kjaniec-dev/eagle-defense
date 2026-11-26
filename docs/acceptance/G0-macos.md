# G0 — native macOS acceptance checklist

Fill this in on a real Mac. Automated sandbox evidence (Linux, Xvfb, software GL) does **not** count here.

## Environment

| Field | Value |
|---|---|
| Date | 2026-11-26 (date the result was reported) |
| Tester | owner |
| Mac model / chip | not reported |
| macOS version | not reported |
| Display(s) / resolution / scaling | not reported |
| LÖVE version (`love --version`) | not reported (project pins 11.5) |
| Commit SHA (`git rev-parse HEAD`) | `4497b373a979dd0650de7d8cfda01724aa33df4f` (independently reviewed G0 HEAD named in the owner's acceptance and merge authorization) |
| How it was run | not reported |

## Run

```sh
git fetch origin && git checkout g0/foundation
/Applications/love.app/Contents/MacOS/love .
```

## Checklist

| # | Check | Expected | Pass/Fail | Notes |
|---|---|---|---|---|
| 1 | Launch | A window titled "Eagle Defense" opens within ~2 s, with no error screen | PASS | Owner-reported (manual) |
| 2 | Test pattern | "PLACEHOLDER - G0 TEST PATTERN" text, a 13×13 grid, and gold and teal squares at the bottom | PASS | Owner-reported (manual) |
| 3 | Pixel-perfect | The 1-px checkerboard (bottom-left) is a crisp, even checker with no moiré or blur. The red corner pixels are visible. | PASS | Owner-reported (manual) |
| 4 | F3 overlay | Shows FPS ≈ display refresh rate, ticks/frame 1 (or 0/1 alternating on 120 Hz ProMotion), `scale integer N` | PASS | Owner-reported (manual) |
| 5 | Retina scale | On the built-in display, F3 shows `dpi 2.0`, and the scale is an integer in *physical* pixels (e.g. 4 on a 14" MBP) | PASS | Owner-reported (manual) |
| 6 | Resize | Dragging the window edge keeps the image centered, letterboxed and crisp at each integer step | PASS | Owner-reported (manual) |
| 7 | Fullscreen | F11 and Alt(Option)+Enter enter and exit fullscreen. The image stays crisp and centered. | PASS | Owner-reported (manual) |
| 8 | F4 fit mode | Fills more of the screen with slight smoothing. F4 again returns to integer mode. | PASS | Owner-reported (manual) |
| 9 | P1 keyboard | WASD moves the gold square. The last pressed key wins: hold W, press D → right; release D → up again. | PASS | Owner-reported (manual) |
| 10 | P2 keyboard | Arrow keys move the teal square independently and at the same time as P1 | PASS | Owner-reported (manual) |
| 11 | Gamepad (if available) | Pad 1 D-pad and left stick move P1. A second pad moves P2. Unplugging and replugging works. Record the pad model. | NOT TESTED | Not verified natively; no gamepad result reported. Gamepad support remains covered only by sandbox unit/scenario tests. |
| 12 | Frame pacing | The markers move smoothly with no periodic hitching over 1 min of movement | PASS | Owner-reported (manual) |
| 13 | Quit | Esc closes the app cleanly | PASS | Owner-reported (manual) |
| 14 | Stability | Left idle for 10 min with F3 on: no crash, and FPS stays stable | PASS | Owner-reported (manual) |

## Optional: automated native smoke

`make smoke` (prerequisites in `docs/CI.md`) runs the pixel-perfect check in physical pixels on the real display. Paste the `SMOKE OK` lines here. Check that they show `dpi=2.00` and a physical size of twice the logical size on Retina.

**Status: NOT RUN.** No native `make smoke` output was reported, so the automated pixel-perfect check has no native evidence.

## Result

Owner verdict (2026-11-26): **PASS for the manually verified functionality.**

- [x] All manually verified checks passed (1–10, 12–14)
- [ ] Issues found
- Not tested: #11 gamepad. Not run: optional automated native smoke.

The owner reported a summary verdict, not per-item notes or environment details. Fields marked "not reported" were left blank on purpose rather than guessed. This is native macOS evidence from the owner and is kept separate from the sandbox evidence in `docs/evidence/SUMMARY.md`.
