# od(1) output fixtures

Byte-exact captures of `od` output for the PNG header reader in
`tools/lib/portable.sh`, used by `tests/tools/portable_sh_spec.lua`. Do not
reformat: trailing spaces and the final empty line are the data.

All three were produced from the native macOS canvas PNG of the PR #2 Retina
re-run (`native-evidence/pr2-retina-fixed-800x600-2026-11-26/smoke.png`,
SHA-256 `0bb5bb198021179823c555e5754fb2a64cf53b32d0e597daef17d73fcce47cde`,
640x360).

| File | Command | `od` implementation |
|---|---|---|
| `gnu-canvas-640x360.txt` | `od -An -tu1 -N24` | GNU coreutils (Linux sandbox) |
| `bsd-macos-canvas-640x360.txt` | `od -An -tu1 -N24` | Apple `od` |
| `bsd-macos-ihdr-dims-observed.txt` | `od -An -tu1 -j16 -N8` (the pre-fix command) | Apple `od` |

"Apple `od`" is `hexdump` (which acts as `od` when invoked under that name)
from `apple-oss-distributions/shell_cmds`, tag `shell_cmds-329`, directory
`hexdump/`, compiled on Linux with `-D__APPLE__`. Its `parse.c` forces an extra
blank line for `-A n` ("Force -A n to dump extra blank line like default od
behavior"), and the last data line is padded with spaces. These fixtures were
captured in the sandbox, not on a Mac. To confirm them natively, run on the
Mac after a smoke run (every LÖVE 640x360 canvas PNG has the same first 24
bytes):

```sh
od -An -tu1 -N24 build/smoke.png | cmp - tests/fixtures/od/bsd-macos-canvas-640x360.txt
```
