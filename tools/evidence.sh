#!/usr/bin/env bash
# Builds the review evidence package: evidence/eagle-defense-<sha>.tar.gz.
# It contains the commit SHA, the diff against main, all check outputs,
# smoke screenshots, the .love build, the summary and SHA256SUMS.
# Everything in it is AUTOMATED SANDBOX/CI EVIDENCE, not native acceptance.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
BASE="${EVIDENCE_BASE:-origin/main}"
SHA="$(git rev-parse HEAD)"
SHORT="$(git rev-parse --short HEAD)"
DIR="$ROOT/evidence/eagle-defense-$SHORT"
rm -rf "$DIR"
mkdir -p "$DIR/checks" "$DIR/screenshots" "$DIR/build"

dirty="clean"
if ! git diff --quiet || ! git diff --cached --quiet; then
  dirty="DIRTY (uncommitted changes present; evidence does not match the SHA exactly)"
fi

step() {
  local name="$1"; shift
  if "$@" >"$DIR/checks/$name.txt" 2>&1; then
    echo "PASS $name" | tee -a "$DIR/checks/SUMMARY.txt"
  else
    echo "FAIL $name" | tee -a "$DIR/checks/SUMMARY.txt"
  fi
}

step fmt-check make --no-print-directory fmt-check
step lint make --no-print-directory lint
step test make --no-print-directory test
step validate make --no-print-directory validate
step smoke make --no-print-directory smoke BUILD="$DIR/screenshots"
step love make --no-print-directory love
cp dist/eagle-defense.love dist/eagle-defense.love.sha256 "$DIR/build/" 2>/dev/null || true

{
  echo "commit: $SHA"
  echo "branch: $(git rev-parse --abbrev-ref HEAD)"
  echo "base:   $BASE ($(git rev-parse --short "$BASE" 2>/dev/null || echo n/a))"
  echo "tree:   $dirty"
  echo "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host:   $(uname -srm)"
  echo "love:   $(love --version 2>/dev/null || echo n/a)"
  echo "luajit: $(luajit -v 2>/dev/null || echo n/a)"
  echo
  echo "EVIDENCE CLASS: automated sandbox/CI evidence (Linux, Xvfb, software GL)."
  echo "This is NOT native macOS/Windows acceptance evidence."
} > "$DIR/MANIFEST.txt"

git diff "$BASE"...HEAD > "$DIR/diff.patch" 2>/dev/null || git diff > "$DIR/diff.patch"
git log --oneline "$BASE"..HEAD > "$DIR/commits.txt" 2>/dev/null || true
[[ -f docs/evidence/SUMMARY.md ]] && cp docs/evidence/SUMMARY.md "$DIR/SUMMARY.md"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}
# Hash list is written outside $DIR first, so it never lists itself.
sums="$(mktemp)"
(cd "$DIR" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do sha256 "$f"; done) >"$sums"
mv "$sums" "$DIR/SHA256SUMS"

tar -C "$ROOT/evidence" -czf "$ROOT/evidence/eagle-defense-$SHORT.tar.gz" "eagle-defense-$SHORT"
(cd "$ROOT/evidence" && sha256 "eagle-defense-$SHORT.tar.gz" >"eagle-defense-$SHORT.tar.gz.sha256")

cat "$DIR/checks/SUMMARY.txt"
echo "evidence: $ROOT/evidence/eagle-defense-$SHORT.tar.gz"
cat "$ROOT/evidence/eagle-defense-$SHORT.tar.gz.sha256"
! grep -q '^FAIL' "$DIR/checks/SUMMARY.txt"
