# shellcheck shell=bash
# Problem-code classifier for tools/hidpi_sim.sh. Sourced, not executed;
# tested by tests/tools/hidpi_labels_spec.lua under the system bash (on
# macOS: /bin/bash 3.2).
#
# labels_for_problems PROBLEMS
#   PROBLEMS: the `problems=` value of a SMOKE line, codes separated by ';'
#             ("none" when the in-app checks passed).
#   stdout:   one label per line, naming the regression each code reveals:
#             game-canvas-dpi, prescale-canvas-dpi, fit-filtering, and
#             other-check for any code that none of those explain.
#
# Pure bash on purpose: no grep. The previous version filtered known codes
# with `grep -v -E '^(...|)$' || true`. BSD/macOS grep rejects the empty
# alternative ("empty (sub)expression", exit 2), `|| true` swallowed the
# error, and other-check was silently never reported on macOS (PR #2 native
# run). A classifier without an external regex cannot fail that way.
labels_for_problems() {
  local problems="$1" code i rest=0
  local codes=()
  [[ "$problems" == *canvas_pixels* || "$problems" == *canvas_dpi* ]] && echo "game-canvas-dpi"
  [[ "$problems" == *prescale_pixels* || "$problems" == *prescale_dpi* ]] && echo "prescale-canvas-dpi"
  [[ "$problems" == *blended:0* ]] && echo "fit-filtering"
  IFS=';' read -r -a codes <<<"$problems"
  # Index loop: "${codes[@]}" on an empty array fails under `set -u` in bash 3.2.
  for ((i = 0; i < ${#codes[@]}; i++)); do
    code="${codes[$i]}"
    case "$code" in
      "" | none | *canvas_pixels* | canvas_dpi* | prescale_pixels* | prescale_dpi* | blended:0*) ;;
      *) rest=1 ;;
    esac
  done
  [[ $rest -eq 1 ]] && echo "other-check"
  return 0
}
