#!/usr/bin/env bash
# Builds dist/eagle-defense.love from tracked game files and writes a SHA-256.
# File timestamps are normalised to the last commit time, so the archive is
# reproducible for a given commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
OUT="$DIST/eagle-defense.love"
STAGE="$(mktemp -d)"
export TZ=UTC # identical timestamps regardless of the build machine timezone
trap 'rm -rf "$STAGE"' EXIT

cd "$ROOT"
mkdir -p "$DIST"
rm -f "$OUT"

# Only tracked or not-ignored files go in: no local tooling, no build outputs.
# shellcheck disable=SC2016 # $1/$2 are expanded by the inner sh, on purpose
git ls-files -z --cached --others --exclude-standard -- main.lua conf.lua src config levels assets \
  | xargs -0 -I{} sh -c 'mkdir -p "$1/$(dirname "$2")" && cp "$2" "$1/$2"' _ "$STAGE" {}

stamp="$(git log -1 --format=%cd --date=format:%Y%m%d%H%M.%S 2>/dev/null || date +%Y%m%d%H%M.%S)"
find "$STAGE" -exec touch -t "$stamp" {} +

(cd "$STAGE" && find . -type f | LC_ALL=C sort | sed 's|^\./||' | zip -q -X -9 "$OUT" -@)

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$DIST" && sha256sum eagle-defense.love > eagle-defense.love.sha256)
else
  (cd "$DIST" && shasum -a 256 eagle-defense.love > eagle-defense.love.sha256)
fi
echo "love: $(cat "$DIST/eagle-defense.love.sha256")"
echo "love: $(unzip -Z1 "$OUT" | wc -l | tr -d ' ') files"
