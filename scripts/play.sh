#!/usr/bin/env bash
# Launch MisoStory (the Godot runtime). Run scripts/build_runtime.sh once first so game/assets/world exists.
#
#   bash scripts/play.sh                     # windowed 1600x900
#   bash scripts/play.sh --fullscreen
#   bash scripts/play.sh --editor            # open the project in the Godot editor instead
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -f "$REPO/game/assets/world/index.json" ]]; then
  echo "game/assets/world is missing: run  bash scripts/build_runtime.sh  first (about 6 minutes)." >&2
  exit 1
fi
# godot.sh picks the right binary for the platform (and downloads Godot on first use); GODOT_GUI overrides it.
if [[ -n "${GODOT_GUI:-}" ]]; then GUI=("$GODOT_GUI"); else GUI=(bash "$REPO/scripts/godot.sh" --gui); fi
case "${1:-}" in
  --editor) exec "${GUI[@]}" --path "$REPO/game" --editor ;;
  --fullscreen) exec "${GUI[@]}" --path "$REPO/game" --fullscreen ;;
  *) exec "${GUI[@]}" --path "$REPO/game" --resolution 1600x900 ;;
esac
