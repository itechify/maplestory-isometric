#!/usr/bin/env bash
# Reproducibility check for the canonical snapshot: re-run every extractor with --offline (the cache plus the dated
# captures under tools/*/captures, no network) into a temporary copy of the repository, then compare what they write
# with game/data/canonical and game/data/misostory/map_id_crosswalk.json byte for byte.
#
#   bash scripts/check_canonical.sh               # exit 0 = every extractor reproduces the committed files
#   bash scripts/check_canonical.sh --keep        # keep the temporary copy (its path is printed) to inspect a diff
#   CHECK_CANONICAL_DIR=<dir> bash scripts/check_canonical.sh   # use <dir> (emptied first) instead of mktemp; refused
#                                                 # unless it is new or empty, or an earlier run's folder, and it is
#                                                 # neither /, $HOME, the repository (or above it) nor inside it outside
#                                                 # _scratch/ (exit 2)
#
# The extractors run in their documented order (docs/canonical/README.md "Regenerating"): maps, npcs, quests, shops,
# formulas, items, monsters (+ drops and breakables), then build_sources_index. The order matters from an empty tree:
# extract_items reads shops/ and formulas/beginner.json, and extract_monsters resolves drop members against the local
# items/ and quests/ (tools/sources/drops_merge.mjs loadLocalItems / loadLocalQuests), so both run before it. Each
# starts from an empty output folder in the copy, so a committed file that no extractor writes any more shows up as
# "only in the repository".
# docs/canonical/topology_diff.md (also written by extract_maps.mjs) is compared too, but a difference there is only
# reported: it also reads Blender-side files (docs/manifest.json, src/misostory/layout.py) that change with every world
# build, so it is a report to refresh (node tools/meowdb/extract_maps.mjs), not canonical data.
#
# Needs tools/meowdb/.cache (git-ignored: copy it from a checkout that has it). Every extractor runs with --offline
# (tools/meowdb/lib.mjs), so the check makes no request: a page missing from the cache fails the extractor ("not
# cached") instead of being fetched.
# Exit codes: 0 reproduced, 1 differences, 2 an extractor failed or the cache is missing.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEEP=0
for a in "$@"; do
  case "$a" in
    --keep) KEEP=1 ;;
    *) echo "check_canonical: unknown argument '$a' (flags: --keep)"; exit 2 ;;
  esac
done

if [[ ! -d "$REPO/tools/meowdb/.cache" ]]; then
  echo "check_canonical: tools/meowdb/.cache is missing (git-ignored); copy it from a checkout that has it"
  echo "CANONICAL_CHECK_FAILED"
  exit 2
fi

MARKER=".check_canonical_workdir"
if [[ -n "${CHECK_CANONICAL_DIR:-}" ]]; then
  # The folder is emptied, so refuse anything that is not clearly a scratch folder of this script: the filesystem
  # root, $HOME, the repository, a folder that contains the repository, a folder inside it other than _scratch/, or a
  # non-empty folder an earlier run of this script did not create (it leaves $MARKER).
  if ! mkdir -p "$CHECK_CANONICAL_DIR" 2>/dev/null; then
    echo "check_canonical: cannot create CHECK_CANONICAL_DIR '$CHECK_CANONICAL_DIR'"
    echo "CANONICAL_CHECK_FAILED"
    exit 2
  fi
  WORK="$(cd "$CHECK_CANONICAL_DIR" && pwd -P)"
  repo_real="$(cd "$REPO" && pwd -P)"
  home_real="$(cd "${HOME:-/}" 2>/dev/null && pwd -P || echo /)"
  refuse=""
  if [[ "$WORK" == "/" || "$WORK" == "$home_real" || "$repo_real/" == "$WORK/"* ]]; then
    refuse="it is /, \$HOME, the repository or a folder containing it"
  elif [[ "$WORK/" == "$repo_real/"* && "$WORK/" != "$repo_real/_scratch/"?* ]]; then
    refuse="it is inside the repository but not under _scratch/"
  elif [[ -n "$(ls -A "$WORK" 2>/dev/null)" && ! -e "$WORK/$MARKER" ]]; then
    refuse="it is not empty and was not created by this script (no $MARKER)"
  fi
  if [[ -n "$refuse" ]]; then
    echo "check_canonical: refusing CHECK_CANONICAL_DIR '$CHECK_CANONICAL_DIR' ($WORK): $refuse; it would be emptied"
    echo "CANONICAL_CHECK_FAILED"
    exit 2
  fi
  rm -rf "$WORK"
  mkdir -p "$WORK"
else
  WORK="$(mktemp -d)"
fi
touch "$WORK/$MARKER"
cleanup() { [[ "$KEEP" == "1" ]] || rm -rf "$WORK"; }
trap cleanup EXIT

# The copy holds exactly what the extractors read: the tools (with the cache and the captures), the canonical and
# adaptation data, the Iteration One docs extract_maps.mjs cross-checks, and the Blender layout it parses.
mkdir -p "$WORK/game/data" "$WORK/docs/canonical" "$WORK/src/misostory"
(cd "$REPO" && tar --exclude=./tools/node_modules -cf - ./tools) | (cd "$WORK" && tar -xf -)
cp -r "$REPO/game/data/canonical" "$REPO/game/data/misostory" "$WORK/game/data/"
cp -r "$REPO/docs/topology.json" "$REPO/docs/manifest.json" "$REPO/docs/research" "$WORK/docs/"
cp "$REPO/docs/canonical/topology_diff.md" "$WORK/docs/canonical/"
cp "$REPO/src/misostory/layout.py" "$WORK/src/misostory/"
# Every extractor starts from an empty output folder; build_sources_index.mjs rewrites the index from what they wrote.
for d in "$WORK"/game/data/canonical/*/; do rm -rf "$d"; done
rm -f "$WORK/game/data/canonical/canonical_sources.json" "$WORK/game/data/misostory/map_id_crosswalk.json" \
  "$WORK/docs/canonical/topology_diff.md"

STEPS=(extract_maps extract_npcs extract_quests extract_shops extract_formulas extract_items extract_monsters
  build_sources_index)
failed_steps=()
for step in "${STEPS[@]}"; do
  log="$WORK/$step.log"
  if (cd "$WORK" && node "tools/meowdb/$step.mjs" --offline >"$log" 2>&1); then
    echo "ok    $step"
  else
    echo "FAIL  $step (last lines of its output:)"
    tail -n 15 "$log" | sed 's/^/      /'
    failed_steps+=("$step")
  fi
done
if [[ ${#failed_steps[@]} -gt 0 ]]; then
  KEEP=1
  echo "check_canonical: ${#failed_steps[@]} extractor(s) failed: ${failed_steps[*]} (copy kept at $WORK)"
  echo "CANONICAL_CHECK_FAILED"
  exit 2
fi

# Compare. diff -r names every file that differs or exists on one side only.
differences=0
compare() {  # <repository path> [info]: with "info" a difference is reported but does not fail the check
  local rel="$1"
  local out
  if ! out="$(diff -r --brief "$REPO/$rel" "$WORK/$rel" 2>&1)"; then
    if [[ "${2:-}" == "info" ]]; then
      echo "note  $rel differs from a fresh run (a report, not canonical data: refresh it with node tools/meowdb/extract_maps.mjs)"
      return
    fi
    differences=1
    echo "DIFF  $rel"
    echo "$out" | sed -e "s#$REPO/#repository: #g" -e "s#$WORK/#regenerated: #g" -e 's/^/      /'
  else
    echo "same  $rel"
  fi
}
compare game/data/canonical
compare game/data/misostory/map_id_crosswalk.json
compare docs/canonical/topology_diff.md info
if [[ "$differences" == "1" ]]; then
  KEEP=1
  echo "check_canonical: the regenerated files differ (copy kept at $WORK; diff a file against the repository to see how)"
  echo "CANONICAL_CHECK_FAILED"
  exit 1
fi
[[ "$KEEP" == "1" ]] && echo "check_canonical: copy kept at $WORK"
echo "CANONICAL_CHECK_PASSED"
exit 0
