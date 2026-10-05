#!/usr/bin/env bash
# Validate MisoStory's local content (game/data/canonical + game/data/misostory) with the game's own loader.
# Broken references are treated like compile errors: the exit code is non-zero on any error.
#
#   bash scripts/validate_data.sh                        # print the report; exit 1 on errors
#   bash scripts/validate_data.sh --verbose              # also list references skipped as out of scope
#   bash scripts/validate_data.sh --strict               # warnings fail too
#   bash scripts/validate_data.sh --json report.json     # also write the report as JSON
#   bash scripts/validate_data.sh --world-dir res://...  # Blender export to check the crosswalk slugs against
#   ISOLATE=<name> bash scripts/validate_data.sh ...     # run in a private copy (_scratch/godot_runs/<name>/game), as
#                                                        # scripts/test.sh does, so concurrent runs never share .godot/
#   VALIDATE_TIMEOUT_S=300 bash scripts/validate_data.sh # outer time limit in seconds (default 180)
#
# The crosswalk check also looks for the Blender export sidecars (game/assets/world/<slug>.json). An isolated run
# copies only those small JSON sidecars, not the glTF chunks; without an export the check is skipped with a warning.
# Prints VALIDATION_PASSED / VALIDATION_FAILED last. Exit codes: 0 pass, 1 data errors (or warnings with --strict),
# 2 the validator is broken (does not compile, raised a script error, timed out) or a bad command line.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"
TIMEOUT_S="${VALIDATE_TIMEOUT_S:-180}"

# Resolve --json to an absolute path before Godot changes the frame of reference.
ARGS=()
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--json" && $# -gt 1 ]]; then
    out="$2"
    [[ "$out" = /* || "$out" =~ ^[A-Za-z]: || "$out" = res://* ]] || out="$PWD/$out"
    out="$(cygpath -m "$out" 2>/dev/null || echo "$out")"
    ARGS+=("--json" "$out")
    shift 2
  else
    ARGS+=("$1")
    shift
  fi
done

if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE"
  mkdir -p "$DEST/game"
  # Same mirror as scripts/test.sh: everything except the import cache and the exported world.
  (cd "$PROJECT" && tar --exclude=./.godot --exclude=./assets/world -cf - .) | (cd "$DEST/game" && tar -xf -)
  (cd "$DEST/game" && find . -type f ! -path './.godot/*' ! -path './assets/world/*' | while read -r f; do [[ -e "$PROJECT/$f" ]] || rm -f "$f"; done)
  # Refresh the sidecars from scratch so a sidecar removed from the export cannot linger in the mirror.
  rm -f "$DEST/game/assets/world/"*.json
  if [[ -d "$PROJECT/assets/world" ]]; then
    mkdir -p "$DEST/game/assets/world"
    cp "$PROJECT"/assets/world/*.json "$DEST/game/assets/world/" 2>/dev/null || true
  fi
  PROJECT="$DEST/game"
fi

# Not named GODOT: that is the binary override godot.sh reads, and bash cannot export an array.
GODOT_CMD=(bash "$REPO/scripts/godot.sh")
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
# The outer timeout is the last resort for a Godot that never quits. The tool exits 2 by itself when the validator
# does not compile or raises a script error, but if the tool script itself cannot compile Godot idles forever.
timeout --kill-after=10 "$TIMEOUT_S" "${GODOT_CMD[@]}" --headless --path "$PROJECT" res://tools/validate_data.tscn -- \
  "${ARGS[@]+"${ARGS[@]}"}" 2>&1 \
  | grep -vE '^(Godot Engine v|WARNING: .*leaked|   at: |Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: 1 resources still in use|ERROR: .* resources still in use)'
code="${PIPESTATUS[0]}"
if [[ "$code" == 124 || "$code" == 137 ]]; then
  echo "VALIDATION ERROR Godot did not exit within ${TIMEOUT_S} s (killed; see SCRIPT ERROR / Parse Error lines above)"
  echo "VALIDATION_FAILED"
  exit 2
fi
exit "$code"
