#!/usr/bin/env bash
# Run MisoStory's headless GDScript unit tests.
#
#   bash scripts/test.sh                         # every test file
#   bash scripts/test.sh combat inventory        # only test files whose name contains a filter
#   ISOLATE=<name> bash scripts/test.sh ...      # run in a private copy (_scratch/godot_runs/<name>/game) so several
#                                                # agents/processes can test concurrently without fighting over .godot/
#   ISOLATE=<name> INCLUDE_WORLD=1 bash ...      # same, but also mirror assets/world (needed by world/actor tests)
#                                                # (an isolated copy always gets tools/*/captures next to game/)
#   TEST_EVIDENCE_OUT=<file> bash scripts/test.sh   # also write the machine-readable test evidence (contract C6):
#                                                # {run_at, commit, dirty, world_present, totals,
#                                                #  tests: [{file, name, ok, parity, needs_world}]}
#                                                # dirty: game/, tools/ or scripts/ differ from the commit (tracked
#                                                # changes or untracked files); world_present: the run saw the export
#                                                # (INCLUDE_WORLD=1), without which world tests SKIP and prove nothing
#
# An import pass runs first so new class_name scripts are registered. Prints TESTS_PASSED / TESTS_FAILED and exits
# non-zero on failure.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"

# The evidence path is resolved before Godot runs (an ISOLATE run executes in a mirror), and the commit under test is
# recorded with it (tools/parity/build_parity.mjs reports it).
if [[ -n "${TEST_EVIDENCE_OUT:-}" ]]; then
  out="$TEST_EVIDENCE_OUT"
  [[ "$out" = /* || "$out" =~ ^[A-Za-z]: ]] || out="$PWD/$out"
  mkdir -p "$(dirname "$out")"
  TEST_EVIDENCE_OUT="$(cygpath -m "$out" 2>/dev/null || echo "$out")"
  export TEST_EVIDENCE_OUT
  if [[ -z "${TEST_EVIDENCE_COMMIT:-}" ]]; then
    TEST_EVIDENCE_COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
  fi
  export TEST_EVIDENCE_COMMIT
  # Whether the tested tree is the commit: "1" when game/, tools/ or scripts/ hold changes or untracked files (ignored
  # files such as the exported world and _scratch do not count), "0" when clean, "" when git cannot tell.
  if [[ -z "${TEST_EVIDENCE_DIRTY:-}" ]]; then
    if st="$(git -C "$REPO" status --porcelain -- game tools scripts 2>/dev/null)"; then
      if [[ -n "$st" ]]; then TEST_EVIDENCE_DIRTY=1; else TEST_EVIDENCE_DIRTY=0; fi
    fi
  fi
  export TEST_EVIDENCE_DIRTY="${TEST_EVIDENCE_DIRTY:-}"
fi

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
