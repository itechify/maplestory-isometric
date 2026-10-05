#!/usr/bin/env bash
# Run the every-quest real-game set (docs/runtime/PLAYTEST_HARNESS.md "The every-quest set"): the `quest` scenario
# once per chain of the canonical Maple Island quests, then one table of per-quest results.
#
#   bash scripts/playtest_quests.sh                          # every chain, 3 at a time, seed 1
#   bash scripts/playtest_quests.sh 1013-1019 1002           # only these chains
#   bash scripts/playtest_quests.sh --jobs 4 --seed 2 --out _scratch/quests/seed2
#   bash scripts/playtest_quests.sh --list                   # the chains
#
#   --jobs <n>    chains run in parallel in n private copies of the game (ISOLATE=<prefix>_<i>; default 3). Each copy is
#                 mirrored and imported once; later chains in the same copy reuse it (PLAYTEST_REUSE_COPY=1)
#   --seed <n>    passed to every run (default 1)
#   --out <dir>   one sub-directory per chain (its report.json, report.md, saves) plus quests.md and quests.json
#                 (default _scratch/playtest/quests-<time>)
#   --isolate <p> the copies' name prefix (default "quests")
# A chain is "1000-1001" (consecutive ids) or "1006,1009,1010". The default list is one chain per canonical quest
# line plus each standalone quest (PlaytestQuestPlan.chains; test_playtest_quest_plan.gd keeps the two equal).
# Exit code: 0 when every quest passed, 1 otherwise, 2 on a bad command line or a missing world export.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHAINS_DEFAULT="1000-1001 1002 1003-1004 1005 1006,1009,1010 1007-1008 1011 1012 1013-1019"

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

JOBS=3; SEED=1; OUT=""; PREFIX="quests"; CHAINS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) JOBS="${2:-3}"; shift 2 ;;
    --seed) SEED="${2:-1}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --isolate) PREFIX="${2:-quests}"; shift 2 ;;
    --list) for c in $CHAINS_DEFAULT; do echo "$c"; done; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "playtest_quests.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) CHAINS+=("$1"); shift ;;
  esac
done
if [[ ${#CHAINS[@]} -eq 0 ]]; then read -r -a CHAINS <<< "$CHAINS_DEFAULT"; fi
if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then echo "playtest_quests.sh: --jobs needs a positive number" >&2; exit 2; fi
if [[ ! -f "$REPO/game/assets/world/index.json" ]]; then
  echo "playtest_quests.sh: game/assets/world is missing: run  bash scripts/build_runtime.sh  first." >&2
  exit 2
fi
if [[ -z "$OUT" ]]; then OUT="$REPO/_scratch/playtest/quests-$(date +%Y%m%d-%H%M%S)"; fi
[[ "$OUT" = /* || "$OUT" =~ ^[A-Za-z]: ]] || OUT="$PWD/$OUT"
mkdir -p "$OUT"
OUT="$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")"

# One worker per copy; chain i goes to worker i % JOBS. The first chain of a worker mirrors and imports its copy.
run_worker() {
  local w="$1"; shift
  local reuse=0
  for chain in "$@"; do
    local dir="${chain//,/_}"
    echo "playtest_quests.sh: [${PREFIX}_$w] $chain"
    ISOLATE="${PREFIX}_$w" PLAYTEST_REUSE_COPY="$reuse" bash "$REPO/scripts/playtest.sh" quest --quest "$chain" \
      --seed "$SEED" --out "$OUT/$dir" > "$OUT/$dir.log" 2>&1
    echo "playtest_quests.sh: [${PREFIX}_$w] $chain -> exit $? ($(grep -m1 -o 'PLAYTEST quest: [A-Z]*' "$OUT/$dir.log" || echo 'no result'))"
    reuse=1
  done
}

declare -a PIDS=()
for ((w = 0; w < JOBS; w++)); do
  mine=()
  for ((i = w; i < ${#CHAINS[@]}; i += JOBS)); do mine+=("${CHAINS[$i]}"); done
  [[ ${#mine[@]} -eq 0 ]] && continue
  run_worker "$w" "${mine[@]}" &
  PIDS+=($!)
done
for p in "${PIDS[@]}"; do wait "$p"; done

PROJECT="$REPO/_scratch/godot_runs/${PREFIX}_0/game"
bash "$REPO/scripts/godot.sh" --headless --path "$PROJECT" --script res://tools/playtest/playtest_quest_summary.gd -- \
  --out "$OUT" --chains "${CHAINS[*]}" --seed "$SEED" 2>&1 | grep -E '^(PLAYTEST_QUESTS|ERROR|SCRIPT ERROR)'
code=${PIPESTATUS[0]}
if [[ -f "$OUT/quests.md" ]]; then cat "$OUT/quests.md"; fi
exit "$code"
