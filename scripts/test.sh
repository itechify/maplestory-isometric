#!/usr/bin/env bash
# Run MisoStory's headless GDScript unit tests.
#
#   bash scripts/test.sh                         # every test file
#   bash scripts/test.sh combat inventory        # only test files whose name contains a filter
#   ISOLATE=<name> bash scripts/test.sh ...      # run in a private copy (_scratch/godot_runs/<name>/game) so several
#                                                # agents/processes can test concurrently without fighting over .godot/
#   ISOLATE=<name> INCLUDE_WORLD=1 bash ...      # same, but also mirror assets/world (needed by world/actor tests)
#                                                # (an isolated copy always gets tools/*/captures next to game/)
#
# An import pass runs first so new class_name scripts are registered. Prints TESTS_PASSED / TESTS_FAILED and exits
# non-zero on failure.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"

if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE"
  mkdir -p "$DEST/game"
  # Mirror everything except the import cache and the (large) exported world; logic tests do not need the world.
  (cd "$PROJECT" && tar --exclude=./.godot --exclude=./assets/world -cf - .) | (cd "$DEST/game" && tar -xf -)
  # Drop files deleted from the source since the last mirror.
  (cd "$DEST/game" && find . -type f ! -path './.godot/*' ! -path './assets/world/*' | while read -r f; do [[ -e "$PROJECT/$f" ]] || rm -f "$f"; done)
  if [[ "${INCLUDE_WORLD:-0}" == "1" && -d "$PROJECT/assets/world" ]]; then
    mkdir -p "$DEST/game/assets"
    cp -ru "$PROJECT/assets/world" "$DEST/game/assets/"
  else
    # No world requested: drop any partial world a previous run (e.g. validate_data.sh sidecars) left behind, so
    # world tests see "no export" instead of sidecars without their glbs.
    rm -rf "$DEST/game/assets/world"
  fi
  # Mirror the dated source captures (tools/*/captures): the data validator checks that every capture a record cites
  # exists, and looks for tools/ next to the project (res://../tools), as in the repository.
  rm -rf "$DEST/tools"
  for d in "$REPO"/tools/*/captures; do
    [[ -d "$d" ]] || continue
    rel="${d#"$REPO"/}"
    mkdir -p "$DEST/$rel"
    cp -r "$d/." "$DEST/$rel/"
  done
  PROJECT="$DEST/game"
fi

# Not named GODOT: that is the binary override godot.sh reads.
GODOT_CMD=(bash "$REPO/scripts/godot.sh")
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
# The outer timeout is a last resort for a Godot that never quits (e.g. a runner that cannot compile).
timeout --kill-after=10 "${TEST_TIMEOUT_S:-900}" "${GODOT_CMD[@]}" --headless --path "$PROJECT" res://tests/test_runner.tscn -- "$@" 2>&1 | grep -vE '^(Godot Engine v|WARNING: .*leaked|   at: |Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: 1 resources still in use|ERROR: .* resources still in use)'
exit "${PIPESTATUS[0]}"
