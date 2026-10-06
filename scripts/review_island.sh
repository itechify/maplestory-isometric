#!/usr/bin/env bash
# One command to review the built island: render every camera, run the Blender validation, build the contact sheet.
#
#   bash scripts/review_island.sh                          # renders/final/ (3 Blender processes), docs/VALIDATION.md,
#                                                          # renders/final/contact_sheet.png
#   bash scripts/review_island.sh <TAG> [N=3] [flags]      # flags go to render_review.py (e.g. --debug, --res 1600x900)
#   VALIDATE_OUT=_scratch/val bash scripts/review_island.sh   # write VALIDATION.md + validation_report.json there
#                                                          # instead of docs/
#   SHEET_COLS=6 SHEET_TILE_W=320 bash scripts/review_island.sh   # contact sheet layout (these are the defaults)
#   BLENDER=/path/to/blender bash scripts/review_island.sh
#
# Works on the existing MapleIsland.blend (build it first: scripts/build_island.py). The steps run in this order:
#   1. render    scripts/render_all.sh <TAG> <N> [flags]: fails unless every camera rendered
#   2. validate  scripts/validate.py: fails on a Blender or script error, a missing VALIDATION_SUMMARY line, any high or
#                medium finding, or a check that is not ok (low findings are allowed)
#   3. sheet     tools/contact_sheet.js over renders/<TAG>/*.png (debug renders and the sheet itself excluded): needs
#                `npm ci` in tools/ once; skipped when rendering failed
# Validation runs even when rendering failed, so one run reports both. Each step prints a "[review] <step>: PASS|FAIL"
# line; the last line is REVIEW_PASSED, or REVIEW_FAILED with the failed steps. Exit codes: 0 every step passed,
# 1 a step failed, 2 no MapleIsland.blend. Logs: _scratch/review_<TAG>_validate.log and _scratch/render_<TAG>_*.log.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
TAG="${1:-final}"; N="${2:-3}"; shift; shift || true
COLS="${SHEET_COLS:-6}"
TILE_W="${SHEET_TILE_W:-320}"
if [[ -n "${BLENDER:-}" ]]; then
  B="$BLENDER"
elif command -v blender >/dev/null 2>&1; then
  B="$(command -v blender)"
else
  B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
fi
export BLENDER="$B"   # render_all.sh uses the same Blender
if [[ ! -f MapleIsland.blend ]]; then
  echo "[review] MapleIsland.blend is missing: build it with scripts/build_island.py"
  echo "REVIEW_FAILED: no MapleIsland.blend"
  exit 2
fi
mkdir -p _scratch
FAILED=()

# 1. render
echo "[review] render: renders/$TAG/ with $N Blender processes"
if bash scripts/render_all.sh "$TAG" "$N" "$@"; then
  RENDER_OK=1
  echo "[review] render: PASS"
else
  RENDER_OK=0
  FAILED+=("render")
  echo "[review] render: FAIL (see _scratch/render_${TAG}_*.log)"
fi

# 2. validate
VLOG="_scratch/review_${TAG}_validate.log"
VARGS=()
if [[ -n "${VALIDATE_OUT:-}" ]]; then
  mkdir -p "$VALIDATE_OUT"
  VARGS=(-- --out "$(cd "$VALIDATE_OUT" && pwd)")
fi
echo "[review] validate: scripts/validate.py -> ${VALIDATE_OUT:-docs}/VALIDATION.md"
"$B" -b MapleIsland.blend --python-exit-code 1 --python scripts/validate.py "${VARGS[@]}" > "$VLOG" 2>&1
VSTATUS=$?
SUMMARY="$(grep -a '^VALIDATION_SUMMARY ' "$VLOG" | tail -1)"
why=""
if [[ $VSTATUS -ne 0 ]]; then
  why="Blender exited with $VSTATUS"
elif [[ -z "$SUMMARY" ]]; then
  why="no VALIDATION_SUMMARY line"
else
  high="$(sed -n 's/.*"high": \([0-9]*\).*/\1/p' <<< "$SUMMARY")"
  medium="$(sed -n 's/.*"medium": \([0-9]*\).*/\1/p' <<< "$SUMMARY")"
  low="$(sed -n 's/.*"low": \([0-9]*\).*/\1/p' <<< "$SUMMARY")"
  not_ok="$(grep -o '"[A-Za-z0-9_]*": false' <<< "$SUMMARY" | sed 's/": false//; s/"//' | paste -sd, -)"
  if [[ "${high:-x}" != "0" || "${medium:-x}" != "0" ]]; then
    why="${high:-?} high, ${medium:-?} medium findings"
  fi
  if [[ -n "$not_ok" ]]; then
    why="${why:+$why; }checks not ok: $not_ok"
  fi
fi
if [[ -z "$why" ]]; then
  echo "[review] validate: PASS (0 high, 0 medium, ${low:-?} low)"
else
  FAILED+=("validate")
  echo "[review] validate: FAIL ($why; see $VLOG)"
fi

# 3. contact sheet
SHEET="renders/$TAG/contact_sheet.png"
if [[ $RENDER_OK -ne 1 ]]; then
  echo "[review] sheet: skipped (rendering failed)"
elif [[ ! -d tools/node_modules/jimp ]]; then
  FAILED+=("sheet")
  echo "[review] sheet: FAIL (tools/node_modules/jimp is missing: run npm ci in tools/)"
else
  IMGS=()
  for f in "renders/$TAG"/*.png; do
    [[ -f "$f" && "$f" != "$SHEET" ]] && IMGS+=("$f")
  done
  echo "[review] sheet: ${#IMGS[@]} renders -> $SHEET"
  if [[ ${#IMGS[@]} -gt 0 ]] && node tools/contact_sheet.js "$SHEET" "$COLS" "$TILE_W" "${IMGS[@]}"; then
    echo "[review] sheet: PASS"
  else
    FAILED+=("sheet")
    echo "[review] sheet: FAIL"
  fi
fi

if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "REVIEW_PASSED"
  exit 0
fi
echo "REVIEW_FAILED: ${FAILED[*]}"
exit 1
