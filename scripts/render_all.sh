#!/usr/bin/env bash
# Render every camera of MapleIsland.blend into renders/<TAG>/ using N parallel Blender processes.
# Usage: scripts/render_all.sh <TAG> [N=3] [extra render_review.py flags, e.g. --res 1600x900]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="$1"; N="${2:-3}"; shift; shift || true
B="${BLENDER:-$(command -v blender || echo "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe")}"
BLEND="$ROOT/MapleIsland.blend"
# list cameras
CAMS=$("$B" -b "$BLEND" --python-expr "import bpy; print('CAMS:' + ','.join(sorted(o.name for o in bpy.data.objects if o.type == 'CAMERA')))" 2>/dev/null | grep '^CAMS:' | sed 's/^CAMS://')
IFS=',' read -ra ARR <<< "$CAMS"
echo "cameras: ${#ARR[@]}"
for ((w=0; w<N; w++)); do
  SUB=()
  for ((i=w; i<${#ARR[@]}; i+=N)); do SUB+=("${ARR[$i]}"); done
  "$B" -b "$BLEND" --python "$ROOT/scripts/render_review.py" -- "$TAG" "${SUB[@]}" --exact "$@" > "$ROOT/_scratch/render_${TAG}_$w.log" 2>&1 &
done
wait
grep -h "RENDERED" "$ROOT"/_scratch/render_"${TAG}"_*.log | wc -l
