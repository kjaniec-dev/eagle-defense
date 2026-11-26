# G0 — native macOS acceptance checklist

Fill this in on a real Mac. Automated sandbox evidence (Linux, Xvfb, software GL) does **not** count here.

## Environment

| Field | Value |
|---|---|
| Date | |
| Tester | owner |
| Mac model / chip | e.g. MacBook Pro 14" M3 |
| macOS version | |
| Display(s) / resolution / scaling | e.g. built-in Retina 3024×1964 "default"; external 2560×1440 |
| LÖVE version (`love --version`) | 11.5 |
| Commit SHA (`git rev-parse HEAD`) | |
| How it was run | `love .` from a checkout, or `.love` from the CI artifact |

## Run

```sh
git fetch origin && git checkout g0/foundation
/Applications/love.app/Contents/MacOS/love .
```

## Checklist

| # | Check | Expected | Pass/Fail | Notes |
|---|---|---|---|---|
| 1 | Launch | A window titled "Eagle Defense" opens within ~2 s, with no error screen | | |
| 2 | Test pattern | "PLACEHOLDER - G0 TEST PATTERN" text, a 13×13 grid, and gold and teal squares at the bottom | | |
| 3 | Pixel-perfect | The 1-px checkerboard (bottom-left) is a crisp, even checker with no moiré or blur. The red corner pixels are visible. | | |
| 4 | F3 overlay | Shows FPS ≈ display refresh rate, ticks/frame 1 (or 0/1 alternating on 120 Hz ProMotion), `scale integer N` | | |
| 5 | Retina scale | On the built-in display, F3 shows `dpi 2.0`, and the scale is an integer in *physical* pixels (e.g. 4 on a 14" MBP) | | |
| 6 | Resize | Dragging the window edge keeps the image centered, letterboxed and crisp at each integer step | | |
| 7 | Fullscreen | F11 and Alt(Option)+Enter enter and exit fullscreen. The image stays crisp and centered. | | |
| 8 | F4 fit mode | Fills more of the screen with slight smoothing. F4 again returns to integer mode. | | |
| 9 | P1 keyboard | WASD moves the gold square. The last pressed key wins: hold W, press D → right; release D → up again. | | |
| 10 | P2 keyboard | Arrow keys move the teal square independently and at the same time as P1 | | |
| 11 | Gamepad (if available) | Pad 1 D-pad and left stick move P1. A second pad moves P2. Unplugging and replugging works. Record the pad model. | | |
| 12 | Frame pacing | The markers move smoothly with no periodic hitching over 1 min of movement | | |
| 13 | Quit | Esc closes the app cleanly | | |
| 14 | Stability | Left idle for 10 min with F3 on: no crash, and FPS stays stable | | |

## Optional: automated native smoke

`make smoke` (prerequisites in `docs/CI.md`) runs the pixel-perfect check in physical pixels on the real display. Paste the `SMOKE OK` lines here. Check that they show `dpi=2.00` and a physical size of twice the logical size on Retina.

## Result

- [ ] All checks passed
- [ ] Issues found (list them above, with screenshots in `docs/acceptance/G0-macos/`)
