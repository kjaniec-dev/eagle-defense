#!/usr/bin/env bash
# Builds dist/eagle-defense.love plus .sha256 and .commit sidecar files.
#
#   tools/build_love.sh            # default: exactly the committed HEAD (git archive)
#   tools/build_love.sh --worktree # development: working tree, including
#                                  # untracked but not ignored files; marked -dirty
#
# File timestamps are normalised to the commit time in UTC, so a commit
# build is reproducible.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---commit}"
DIST="$ROOT/dist"
OUT="$DIST/eagle-defense.love"
STAGE="$(mktemp -d)"
export TZ=UTC
trap 'rm -rf "$STAGE"' EXIT
cd "$ROOT"

PATHS=(main.lua conf.lua src config levels assets)
SHA="$(git rev-parse HEAD)"

case "$MODE" in
  --commit)
    existing=()
    for p in "${PATHS[@]}"; do
      if git cat-file -e "HEAD:$p" 2>/dev/null; then existing+=("$p"); fi
    done
    git archive --format=tar HEAD -- "${existing[@]}" | tar -x -C "$STAGE"
    COMMIT_ID="$SHA"
    ;;
  --worktree)
    # shellcheck disable=SC2016 # $1/$2 are expanded by the inner sh, on purpose
    git ls-files -z --cached --others --exclude-standard -- "${PATHS[@]}" \
      | xargs -0 -I{} sh -c 'mkdir -p "$1/$(dirname "$2")" && cp "$2" "$1/$2"' _ "$STAGE" {}
    COMMIT_ID="$SHA-dirty-worktree"
    ;;
  *)
    echo "usage: $0 [--commit|--worktree]" >&2
    exit 2
    ;;
esac

mkdir -p "$DIST"
rm -f "$OUT" "$OUT.sha256" "$OUT.commit"
stamp="$(git log -1 --format=%cd --date=format-local:%Y%m%d%H%M.%S)"
find "$STAGE" -exec touch -t "$stamp" {} +
(cd "$STAGE" && find . -type f | LC_ALL=C sort | sed 's|^\./||' | zip -q -X -9 "$OUT" -@)

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$DIST" && sha256sum eagle-defense.love >eagle-defense.love.sha256)
else
  (cd "$DIST" && shasum -a 256 eagle-defense.love >eagle-defense.love.sha256)
fi
echo "$COMMIT_ID" >"$OUT.commit"
echo "love: $(cat "$OUT.sha256")"
echo "love: $(unzip -Z1 "$OUT" | wc -l | tr -d ' ') files, source $COMMIT_ID"
