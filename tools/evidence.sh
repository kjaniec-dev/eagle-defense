#!/usr/bin/env bash
# Builds the review evidence package. It FAILS CLOSED (review P2-4).
#
#   tools/evidence.sh         final review evidence: evidence/eagle-defense-<sha>.tar.gz
#   tools/evidence.sh --dev   development snapshot: evidence/eagle-defense-<sha>-DEV.tar.gz
#                             (a dirty tree is allowed; the package is marked NOT review evidence)
#
# Final mode refuses to produce a package unless:
#   * the source tree is clean: no modified, staged or untracked files, and
#     no ignored files inside source paths (tools/lib/evidence.lua)
#   * every mandatory check passes (fmt-check, lint, test, validate, smoke,
#     hidpi-sim, love)
#   * every preserved native artifact set (native-evidence/<set>/, outside
#     Git and `make clean`) verifies against its SHA256SUMS, and each of its
#     hashes is recorded in a committed docs/evidence/ report
#   * the .love is built from the exact commit (git archive) and its
#     recorded commit matches
#   * every mandatory file is present and non-empty, and every smoke log
#     says SMOKE OK
#   * internal checksums verify, both before and after archiving
#   * HEAD and the tree are unchanged after the checks ran
#
# Everything the package produces is AUTOMATED SANDBOX/CI EVIDENCE, not native
# acceptance. hidpi-sim/ is SIMULATED HiDPI evidence. native/ holds artifacts
# preserved from earlier native runs, as recorded; this package did not
# produce them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="final"
if [[ "${1:-}" == "--dev" ]]; then MODE="dev"; fi
BASE="${EVIDENCE_BASE:-origin/main}"
LUAJIT="${LUAJIT:-luajit}"

die() {
  echo "evidence: FAIL: $*" >&2
  exit 1
}
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}
sha256_check() {
  # stdout is discarded; the exit status reports any mismatch (portable to macOS shasum).
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$@" >/dev/null; else shasum -a 256 -c "$@" >/dev/null; fi
}

SHA="$(git rev-parse HEAD)"
SHORT="$(git rev-parse --short=12 HEAD)"
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || die "base ref '$BASE' not found (git fetch?)"

if [[ "$MODE" == "final" ]]; then
  "$LUAJIT" tools/evidence_gate.lua pre || die "source tree is not clean; commit or remove files (or use --dev)"
  NAME="eagle-defense-$SHORT"
  LOVE_MODE="--commit"
else
  NAME="eagle-defense-$SHORT-DEV"
  LOVE_MODE="--worktree"
fi

OUTROOT="$ROOT/evidence"
DIR="$OUTROOT/$NAME"
rm -rf "$DIR" "$OUTROOT/$NAME.tar.gz" "$OUTROOT/$NAME.tar.gz.sha256"
mkdir -p "$DIR/checks" "$DIR/screenshots" "$DIR/build"

# --- checks: all mandatory; every failure is recorded and then fails --------
failed=0
step() {
  local name="$1"
  shift
  if "$@" >"$DIR/checks/$name.txt" 2>&1; then
    echo "PASS $name" >>"$DIR/checks/SUMMARY.txt"
    echo "PASS $name"
  else
    echo "FAIL $name" >>"$DIR/checks/SUMMARY.txt"
    echo "FAIL $name (see $DIR/checks/$name.txt)" >&2
    failed=1
  fi
}
step fmt-check make --no-print-directory fmt-check
step lint make --no-print-directory lint
step test make --no-print-directory test
step validate make --no-print-directory validate
step smoke ./tools/smoke.sh 120 "$DIR/screenshots/smoke.png"
step hidpi-sim ./tools/hidpi_sim.sh "$DIR/hidpi-sim"
step love ./tools/build_love.sh "$LOVE_MODE"
[[ $failed -eq 0 ]] || die "mandatory check(s) failed; no package produced"

cp dist/eagle-defense.love dist/eagle-defense.love.sha256 dist/eagle-defense.love.commit "$DIR/build/"
(cd "$DIR/build" && sha256_check eagle-defense.love.sha256) || die ".love checksum mismatch after copy"

# --- preserved native artifacts (outside Git and `make clean`) ---------------
native_sets=()
if [[ -d "$ROOT/native-evidence" ]]; then
  for set in "$ROOT"/native-evidence/*/; do
    set="${set%/}"
    [[ -d "$set" ]] || continue
    name="$(basename "$set")"
    [[ -s "$set/SHA256SUMS" ]] || die "native evidence '$name' has no SHA256SUMS"
    (cd "$set" && sha256_check SHA256SUMS) || die "native evidence '$name': checksum mismatch"
    while read -r hash _; do
      grep -rqF "$hash" docs/evidence/ || die "native evidence '$name': $hash is not recorded in docs/evidence/"
    done <"$set/SHA256SUMS"
    mkdir -p "$DIR/native"
    cp -R "$set" "$DIR/native/"
    native_sets+=("$name")
  done
fi

# --- metadata ----------------------------------------------------------------
version_of() { "$@" 2>&1 | head -1 || echo "n/a"; }
{
  echo "commit:     $SHA"
  echo "branch:     $(git rev-parse --abbrev-ref HEAD)"
  echo "base:       $BASE ($(git rev-parse "$BASE"))"
  if [[ "$MODE" == "final" ]]; then
    echo "tree:       clean (verified by tools/evidence_gate.lua pre)"
    echo "mode:       FINAL review evidence"
  else
    echo "tree:       $(git status --porcelain | wc -l | tr -d ' ') changed/untracked path(s)"
    echo "mode:       DEV SNAPSHOT - NOT REVIEW EVIDENCE"
  fi
  echo "created:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host:       $(uname -srm)"
  echo "platform:   $(make --no-print-directory -s toolchain | sed -n 's/^platform=//p') (toolchain in .rocks/<platform>/, .tools/<platform>/)"
  echo "love:       $(version_of love --version)"
  echo "luajit:     $(version_of luajit -v)"
  echo "busted:     $(version_of make --no-print-directory -s busted-version)"
  echo "zip:        $(zip -v 2>/dev/null | sed -n 2p | sed 's/^ *//' || echo n/a)"
  echo "luacheck:   $(version_of make --no-print-directory -s luacheck-version)"
  echo "stylua:     $(version_of make --no-print-directory -s stylua-version)"
  echo "shellcheck: $(shellcheck --version 2>/dev/null | sed -n 2p || echo n/a)"
  echo
  echo "native:     ${native_sets[*]:-none} (native/: preserved native artifacts, not produced by this run)"
  echo
  echo "EVIDENCE CLASS: automated sandbox/CI evidence (Linux, Xvfb, software GL)."
  echo "hidpi-sim/ is SIMULATED HiDPI evidence (implicit resource DPI forced to 1/1.25/1.5/2)."
  echo "This is NOT native macOS/Windows acceptance evidence."
} >"$DIR/MANIFEST.txt"

git diff "$BASE"...HEAD >"$DIR/diff.patch"
git log --oneline "$BASE"..HEAD >"$DIR/commits.txt"
cp docs/evidence/SUMMARY.md "$DIR/SUMMARY.md"

# --- completeness gate -------------------------------------------------------
if [[ "$MODE" == "final" ]]; then
  "$LUAJIT" tools/evidence_gate.lua post "$DIR" "$SHA" || die "package incomplete"
else
  "$LUAJIT" tools/evidence_gate.lua post "$DIR" "$SHA-dirty-worktree" || die "package incomplete"
fi

# --- internal checksums (written outside $DIR first, so the file never lists itself)
sums="$(mktemp)"
(cd "$DIR" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do sha256 "$f"; done) >"$sums"
mv "$sums" "$DIR/SHA256SUMS"
(cd "$DIR" && sha256_check SHA256SUMS) || die "internal checksum verification failed"

# --- nothing changed underneath us ------------------------------------------
[[ "$(git rev-parse HEAD)" == "$SHA" ]] || die "HEAD moved during evidence generation"
if [[ "$MODE" == "final" ]]; then
  "$LUAJIT" tools/evidence_gate.lua pre || die "tree changed during evidence generation"
fi

# --- archive, then verify the archive round trip ------------------------------
tar -C "$OUTROOT" -czf "$OUTROOT/$NAME.tar.gz" "$NAME"
(cd "$OUTROOT" && sha256 "$NAME.tar.gz" >"$NAME.tar.gz.sha256")
verify="$(mktemp -d)"
tar -C "$verify" -xzf "$OUTROOT/$NAME.tar.gz"
(cd "$verify/$NAME" && sha256_check SHA256SUMS) || die "archive round-trip checksum verification failed"
rm -rf "$verify"

cat "$DIR/checks/SUMMARY.txt"
echo "evidence: mode=$MODE commit=$SHA"
echo "evidence: $OUTROOT/$NAME.tar.gz"
cat "$OUTROOT/$NAME.tar.gz.sha256"
