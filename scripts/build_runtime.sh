#!/usr/bin/env bash
# One command from source to a playable game: Blender island -> runtime export -> Godot import -> data validation.
#
#   bash scripts/build_runtime.sh            # (re)build MapleIsland.blend if missing or older than the Blender source,
#                                            # then export, fetch the art pack, import, validate
#   bash scripts/build_runtime.sh --rebuild  # always rebuild MapleIsland.blend first
#   BLENDER=/path/to/blender bash scripts/build_runtime.sh
#   SKIP_ART_PACK=1 bash scripts/build_runtime.sh   # without fetching the art pack (offline with a cold cache)
#
# Takes about 6 minutes on the dev machine (island build ~1 min, export ~4 min, Godot import ~15 s). The export goes
# to game/assets/world/ (git-ignored), the art pack to game/assets/art_pack/ (git-ignored; scripts/art_pack.sh; its first
# import takes about a minute more). Afterwards, play with:  bash scripts/play.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
if [[ -n "${BLENDER:-}" ]]; then
  B="$BLENDER"
elif command -v blender >/dev/null 2>&1; then
  B="$(command -v blender)"
else
  B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
fi

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

# The pinned art pack (ADR 0002) must be in place before the import, which normalises its models. A failed fetch or
# checksum stops the build; SKIP_ART_PACK=1 builds without it (the game then uses its procedural placeholders).
if [[ "${SKIP_ART_PACK:-0}" == "1" ]]; then
  echo "[build_runtime] SKIP_ART_PACK=1: not fetching the art pack"
else
  echo "[build_runtime] fetching the pinned art pack into game/assets/art_pack"
  bash scripts/art_pack.sh fetch
fi

echo "[build_runtime] importing into the Godot project"
bash scripts/godot.sh --headless --path game --import >/dev/null 2>&1 || true

echo "[build_runtime] validating canonical data"
bash scripts/validate_data.sh
echo "[build_runtime] done. Play with: bash scripts/play.sh"
