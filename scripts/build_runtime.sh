#!/usr/bin/env bash
# One command from source to a playable game: Blender island -> runtime export -> icon pack -> Godot import -> data
# validation.
#
#   bash scripts/build_runtime.sh            # (re)build MapleIsland.blend if missing or older than the Blender source,
#                                            # then export, fetch the icon pack, import, validate
#   bash scripts/build_runtime.sh --rebuild  # always rebuild MapleIsland.blend first
#   bash scripts/build_runtime.sh --offline  # take the icon pack from the fetcher's cache only, never the network
#                                            # (combines with --rebuild)
#   BLENDER=/path/to/blender bash scripts/build_runtime.sh
#   ICONS_CACHE_DIR=<dir> bash scripts/build_runtime.sh   # the icon fetcher's cache (default tools/icons/.cache/)
#
# Takes about 6 minutes on the dev machine (island build ~1 min, export ~4 min, Godot import ~15 s); the first icon
# fetch adds about 6 minutes, later runs read the cache (tools/icons/README.md). The export goes to game/assets/world/
# and the icons to game/assets/icon_packs/maplestory_io/ (both git-ignored). Afterwards, play with:  bash scripts/play.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
rebuild=0
icon_flags=()
for a in "$@"; do
  case "$a" in
    --rebuild) rebuild=1 ;;
    --offline) icon_flags+=(--offline) ;;
    *) echo "build_runtime.sh: unknown argument '$a' (flags: --rebuild, --offline)" >&2; exit 2 ;;
  esac
done
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
if [[ $rebuild == 1 || ! -f MapleIsland.blend || -n "$stale" ]]; then
  echo "[build_runtime] building MapleIsland.blend${stale:+ (source is newer than the .blend: $stale)}"
  "$B" -b --factory-startup --python scripts/build_island.py
fi

echo "[build_runtime] exporting the runtime world to game/assets/world"
"$B" -b MapleIsland.blend --python scripts/export_runtime.py -- --out game/assets/world

# Before the import, so new icon PNGs are imported in the same build. The pack is a layer over the procedural icons,
# so a missing Node or a failed fetch is reported and the build goes on with what the pack holds.
echo "[build_runtime] fetching the icon pack (cache first)"
if command -v node >/dev/null 2>&1; then
  node tools/icons/fetch_pack.mjs ${icon_flags[@]+"${icon_flags[@]}"} \
    || echo "[build_runtime] the icon fetcher failed; the game draws its procedural icons where the pack has none"
else
  echo "[build_runtime] node not found, no icon pack fetched; the game draws its procedural icons where the pack has none"
fi

echo "[build_runtime] importing into the Godot project"
bash scripts/godot.sh --headless --path game --import >/dev/null 2>&1 || true

echo "[build_runtime] validating canonical data"
bash scripts/validate_data.sh
echo "[build_runtime] done. Play with: bash scripts/play.sh"
