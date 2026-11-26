# shellcheck shell=bash
# Portable helpers shared by tools/smoke.sh and tools/hidpi_sim.sh. They must
# behave identically on GNU/Linux and on macOS (BSD userland, /bin/bash 3.2).
# Sourced, not executed; tested by tests/tools/portable_sh_spec.lua.

# png_dims_from_od
#   stdin:  the output of `od -An -tu1 -N24 FILE` (the first 24 bytes)
#   stdout: WIDTHxHEIGHT from the IHDR chunk
#   status: 1 (and no output) unless the input holds exactly 24 decimal byte
#           values (0..255) that form the PNG signature and an IHDR chunk of
#           length 13, followed by exactly eight dimension bytes encoding a
#           width and a height in 1..2^31-1.
#
# The od output layout is not portable, so the parser ignores it: GNU od
# prints one line, while BSD/macOS od (hexdump's od mode) pads the line with
# spaces and, with -An, prints an extra empty line. A per-line parser turned
# that empty line into a second "0x0" result (PR #2 native macOS smoke).
# Fixtures: tests/fixtures/od/.
png_dims_from_od() {
  awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i !~ /^[0-9]+$/ || $i + 0 > 255) bad = 1
        b[n++] = $i + 0
      }
    }
    END {
      if (bad || n != 24) exit 1
      split("137 80 78 71 13 10 26 10 0 0 0 13 73 72 68 82", head, " ")
      for (i = 0; i < 16; i++) if (b[i] != head[i + 1]) exit 1
      if (b[16] > 127 || b[20] > 127) exit 1
      w = ((b[16] * 256 + b[17]) * 256 + b[18]) * 256 + b[19]
      h = ((b[20] * 256 + b[21]) * 256 + b[22]) * 256 + b[23]
      if (w < 1 || h < 1) exit 1
      printf "%.0fx%.0f\n", w, h
    }'
}

# png_dims FILE -> prints WIDTHxHEIGHT of a PNG file; status 1 when the file
# is missing, not a regular file, truncated or not a PNG.
png_dims() {
  [[ -f "$1" ]] || return 1
  od -An -tu1 -N24 "$1" | png_dims_from_od
}

# printf_c FORMAT [ARGS...] -> printf in the C locale.
# bash's printf parses and prints %f per LC_NUMERIC, so in a locale with a
# decimal comma (e.g. pl_PL) `printf %.2f 1.25` fails with "invalid number"
# and prints "0,00". LÖVE always prints '.', so values compared with app
# output must be formatted in the C locale. A temporary assignment
# (`LC_ALL=C printf ...`) is not enough: bash 3.2 ignores it for builtins.
printf_c() {
  (
    LC_ALL=C
    export LC_ALL
    # shellcheck disable=SC2059 # the format is this function's argument
    printf "$@"
  )
}
