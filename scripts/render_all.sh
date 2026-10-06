#!/usr/bin/env bash
# Render every camera of MapleIsland.blend into renders/<TAG>/ using N parallel Blender processes.
# Usage: scripts/render_all.sh <TAG> [N=3] [extra render_review.py flags, e.g. --res 1600x900]
# Prints the number of cameras rendered last. Exit 1 when the .blend lists no camera or not every camera rendered
# (the worker logs are _scratch/render_<TAG>_<worker>.log).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="$1"; N="${2:-3}"; shift; shift || true
B="${BLENDER:-$(command -v blender || echo "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe")}"
BLEND="$ROOT/MapleIsland.blend"
mkdir -p "$ROOT/_scratch"
rm -f "$ROOT"/_scratch/render_"${TAG}"_*.log   # a log left by an earlier run with more workers would be counted
# list cameras
CAMS=$("$B" -b "$BLEND" --python-expr "import bpy; print('CAMS:' + ','.join(sorted(o.name for o in bpy.data.objects if o.type == 'CAMERA')))" 2>/dev/null | grep '^CAMS:' | sed 's/^CAMS://')
IFS=',' read -ra ARR <<< "$CAMS"
echo "cameras: ${#ARR[@]}"
if [[ ${#ARR[@]} -eq 0 ]]; then
  echo "render_all: no camera listed by $BLEND (is it there, and does Blender run?)" >&2
  exit 1
fi
for ((w=0; w<N; w++)); do
  SUB=()
  for ((i=w; i<${#ARR[@]}; i+=N)); do SUB+=("${ARR[$i]}"); done
  [[ ${#SUB[@]} -eq 0 ]] && continue   # with no camera names render_review.py would render them all
  "$B" -b "$BLEND" --python "$ROOT/scripts/render_review.py" -- "$TAG" "${SUB[@]}" --exact "$@" > "$ROOT/_scratch/render_${TAG}_$w.log" 2>&1 &
done
wait
DONE=$(cat "$ROOT"/_scratch/render_"${TAG}"_*.log 2>/dev/null | grep -c "RENDERED")
echo "$DONE"
if [[ "$DONE" -ne ${#ARR[@]} ]]; then
  echo "render_all: rendered $DONE of ${#ARR[@]} cameras (logs: _scratch/render_${TAG}_*.log)" >&2
  exit 1
fi
