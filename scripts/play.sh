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
GODOT_DIR="${LOCALAPPDATA:-$HOME/AppData/Local}"
GODOT_DIR="$(cygpath -u "$GODOT_DIR" 2>/dev/null || echo "$GODOT_DIR")/MisoStory/godot/${GODOT_VERSION:-4.7.2}"
bash "$REPO/scripts/godot.sh" --version >/dev/null   # downloads Godot on first use
GUI="${GODOT_GUI:-$GODOT_DIR/Godot_v${GODOT_VERSION:-4.7.2}-stable_win64.exe}"
case "${1:-}" in
  --editor) exec "$GUI" --path "$REPO/game" --editor ;;
  --fullscreen) exec "$GUI" --path "$REPO/game" --fullscreen ;;
  *) exec "$GUI" --path "$REPO/game" --resolution 1600x900 ;;
esac
