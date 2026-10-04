#!/usr/bin/env bash
# One command from source to a playable game: Blender island -> runtime export -> Godot import -> data validation.
#
#   bash scripts/build_runtime.sh            # (re)build MapleIsland.blend if missing or older than the Blender source,
#                                            # then export, import, validate
#   bash scripts/build_runtime.sh --rebuild  # always rebuild MapleIsland.blend first
#   BLENDER=/path/to/blender.exe bash scripts/build_runtime.sh
#
# Takes about 6 minutes on the dev machine (island build ~1 min, export ~4 min, Godot import ~15 s). The export goes
# to game/assets/world/ (git-ignored). Afterwards, play with:  bash scripts/play.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
B="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"

# A .blend left over from another branch (e.g. the Iteration One release) is stale whenever the generator changed.
stale=""
if [[ -f MapleIsland.blend ]]; then
  stale="$(find src scripts/build_island.py -newer MapleIsland.blend -print -quit 2>/dev/null || true)"
fi
if [[ "${1:-}" == "--rebuild" || ! -f MapleIsland.blend || -n "$stale" ]]; then
  echo "[build_runtime] building MapleIsland.blend${stale:+ (source is newer than the .blend: $stale)}"
  "$B" -b --factory-startup --python scripts/build_island.py
fi

echo "[build_runtime] exporting the runtime world to game/assets/world"
"$B" -b MapleIsland.blend --python scripts/export_runtime.py -- --out game/assets/world

echo "[build_runtime] importing into the Godot project"
bash scripts/godot.sh --headless --path game --import >/dev/null 2>&1 || true

echo "[build_runtime] validating canonical data"
bash scripts/validate_data.sh
echo "[build_runtime] done. Play with: bash scripts/play.sh"
