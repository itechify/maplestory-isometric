#!/usr/bin/env bash
# Run an automated playthrough of the REAL game (res://scenes/main.tscn): docs/runtime/PLAYTEST_HARNESS.md.
#
#   bash scripts/playtest.sh <scenario> [--windowed] [--realtime] [--out <dir>] [--seed <n>] [--max-s <s>]
#   bash scripts/playtest.sh --list
#   ISOLATE=<name> bash scripts/playtest.sh smoke   # private copy _scratch/godot_runs/<name>/game (default "playtest";
#                                                   # use your own name when several agents run at once)
#   PLAYTEST_REUSE_COPY=1 ISOLATE=<name> ...        # run on that copy as the last run left it (no mirror, no import):
#                                                   # repeat runs on a frozen tree
#
# The scenario is game/tools/playtest/scenarios/<scenario>.gd (a PlaytestScenario). It runs in a mirror of game/ with
# the exported world, like `ISOLATE=... INCLUDE_WORLD=1 bash scripts/test.sh`, so it never shares a .godot/ import
# cache with another process.
#   headless (default)  --headless --fixed-fps 60: deterministic game time, screenshots are skipped
#   --windowed          a 1600x900 window with --disable-vsync (and still --fixed-fps 60): screenshot() writes PNGs
#   --realtime          with --windowed: no --fixed-fps, game time follows the wall clock (feel checks)
#   --out <dir>         where report.json, report.md, saves/ and shots/ go (default _scratch/playtest/<scenario>-<time>)
#   --seed <n>          Game.rng and MapSession's instance RNG (default 1)
#   --max-s <s>         game-time budget of one phase (default: the scenario's max_seconds())
#   --max-wall-s <s>    wall-time budget of one phase (default: 3 x the game budget, 900 to 3300)
#   --trace             record a state digest (RNG states, position, vitals, monsters) on every step, to diff two
#                       runs of one seed
#   --quest <ids>       for the `quest` scenario: a quest id, a chain "1013-1019" or "1006,1009,1010" (the QUEST
#                       environment variable does the same); scripts/playtest_quests.sh runs every quest
#   --resume            continue a run that stopped between phases (PLAYTEST_STOP_PHASE, below) in --out: its report
#                       and saves are kept and the next phase starts with --continue-run (development only: the report
#                       then mixes the code of two runs)
# A scenario that calls reload_process() runs as several processes (phases) sharing <out>/saves; this script starts
# the next one while the report asks for it (at most 12 phases). PLAYTEST_STOP_PHASE=<n> stops before phase n starts
# and leaves the report RELOADING (exit 1), to be continued with --resume: a long scenario can be developed one
# phase at a time from a copy of its --out directory. Exit code: 0 when the report passes, 1 on a failed check or an
# error, 2 on a bad command line or when no report was written.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCEN_DIR="$REPO/game/tools/playtest/scenarios"
RUNNER="res://tools/playtest/playtest_runner.tscn"
MAX_PHASES=12

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
list() { for f in "$SCEN_DIR"/*.gd; do [[ -e "$f" ]] && basename "$f" .gd; done; }

SCEN=""; WINDOWED=0; REALTIME=0; OUT=""; PASS=(); RESUME=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --windowed) WINDOWED=1; shift ;;
    --resume) RESUME=1; shift ;;
    --realtime) REALTIME=1; shift ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --seed|--max-s|--max-wall-s|--quest) PASS+=("$1" "${2:-}"); shift 2 ;;
    --trace) PASS+=("$1"); shift ;;
    --list) list; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "playtest.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) if [[ -z "$SCEN" ]]; then SCEN="$1"; shift; else echo "playtest.sh: one scenario at a time" >&2; exit 2; fi ;;
  esac
done
if [[ -z "$SCEN" ]]; then usage >&2; exit 2; fi
if [[ ! -f "$SCEN_DIR/$SCEN.gd" ]]; then
  echo "playtest.sh: no scenario '$SCEN' (game/tools/playtest/scenarios/$SCEN.gd). Scenarios:" >&2
  list >&2
  exit 2
fi
if [[ ! -f "$REPO/game/assets/world/index.json" ]]; then
  echo "playtest.sh: game/assets/world is missing: run  bash scripts/build_runtime.sh  first." >&2
  exit 2
fi
if [[ "$REALTIME" == "1" && "$WINDOWED" != "1" ]]; then
  echo "playtest.sh: --realtime needs --windowed (headless runs always use --fixed-fps 60)" >&2
  exit 2
fi

# Output directory: absolute, with forward slashes (Godot reads it as a path of its own file system).
if [[ -z "$OUT" ]]; then OUT="$REPO/_scratch/playtest/$SCEN-$(date +%Y%m%d-%H%M%S)"; fi
[[ "$OUT" = /* || "$OUT" =~ ^[A-Za-z]: ]] || OUT="$PWD/$OUT"
mkdir -p "$OUT"
OUT="$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")"

# The private copy: game/ without its import cache, plus the exported world (as scripts/test.sh with INCLUDE_WORLD=1).
ISO="${ISOLATE:-playtest}"
DEST="$REPO/_scratch/godot_runs/$ISO"
PROJECT_SRC="$REPO/game"
PROJECT="$DEST/game"
GODOT_CMD=(bash "$REPO/scripts/godot.sh")
if [[ "${PLAYTEST_REUSE_COPY:-0}" == "1" && -f "$PROJECT/project.godot" ]]; then
  # A repeat run on a frozen tree (the seed comparison in PLAYTEST_HARNESS.md): the copy stays exactly as the last
  # run left it, whatever changed in game/ since.
  echo "playtest.sh: PLAYTEST_REUSE_COPY=1: reusing $PROJECT as it is (no mirror, no import)"
else
  mkdir -p "$DEST/game"
  (cd "$PROJECT_SRC" && tar --exclude=./.godot --exclude=./assets/world -cf - .) | (cd "$DEST/game" && tar -xf -)
  (cd "$DEST/game" && find . -type f ! -path './.godot/*' ! -path './assets/world/*' | while read -r f; do [[ -e "$PROJECT_SRC/$f" ]] || rm -f "$f"; done)
  mkdir -p "$DEST/game/assets"
  cp -ru "$PROJECT_SRC/assets/world" "$DEST/game/assets/"
  "${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
fi

if [[ "$WINDOWED" == "1" ]]; then
  MODE=(--resolution 1600x900 --disable-vsync)
  [[ "$REALTIME" == "1" ]] || MODE+=(--fixed-fps 60)
else
  MODE=(--headless --fixed-fps 60)
fi

echo "playtest.sh: $SCEN in $PROJECT -> $OUT"
phase=0
code=0
if [[ "$RESUME" == "1" ]]; then
  # Continue a run that stopped between phases: its report must ask for the next phase.
  if [[ ! -f "$OUT/report.json" ]] || ! grep -q '"reload_requested": true' "$OUT/report.json" \
      || ! grep -q '"finished": false' "$OUT/report.json"; then
    echo "playtest.sh: --resume needs a report in $OUT that asks for the next phase" >&2
    exit 2
  fi
  phase="$(grep -o '"end": "reload"' "$OUT/report.json" | wc -l | tr -d ' ')"
  echo "playtest.sh: resuming at phase $phase"
else
  # A report left in a reused --out directory must never stand in for this run's (a runner that dies before it writes
  # would otherwise leave the old result to be read below).
  rm -f "$OUT/report.json" "$OUT/report.md"
fi
while :; do
  if [[ -n "${PLAYTEST_STOP_PHASE:-}" && $phase -ge ${PLAYTEST_STOP_PHASE} && $phase -gt 0 ]]; then
    echo "playtest.sh: PLAYTEST_STOP_PHASE=$PLAYTEST_STOP_PHASE: stopping before phase $phase (continue with --resume)"
    break
  fi
  EXTRA=()
  [[ $phase -gt 0 ]] && EXTRA+=(--continue-run)
  before="$(cksum 2>/dev/null < "$OUT/report.json" || echo none)"
  # The outer timeout is a last resort: the runner has its own game- and wall-time watchdog that writes the report.
  timeout --kill-after=10 "${PLAYTEST_TIMEOUT_S:-3600}" "${GODOT_CMD[@]}" "${MODE[@]}" --path "$PROJECT" "$RUNNER" -- \
    --scenario "$SCEN" --out "$OUT" "${PASS[@]}" "${EXTRA[@]}" 2>&1 \
    | grep -vE '^(Godot Engine v|WARNING: .*leaked|   at: \(|Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: .* resources still in use)'
  code=${PIPESTATUS[0]}
  if [[ $phase -gt 0 && "$(cksum 2>/dev/null < "$OUT/report.json" || echo none)" == "$before" ]]; then
    # The phase wrote nothing (it crashed or hung before its report): running it again would only repeat that.
    echo "playtest.sh: phase $phase wrote no report (exit code $code)" >&2
    exit 2
  fi
  if [[ -f "$OUT/report.json" ]] && grep -q '"reload_requested": true' "$OUT/report.json" \
      && grep -q '"finished": false' "$OUT/report.json"; then
    phase=$((phase + 1))
    if [[ $phase -ge $MAX_PHASES ]]; then echo "playtest.sh: more than $MAX_PHASES phases" >&2; break; fi
    echo "playtest.sh: phase $phase (the scenario reloaded the process)"
    continue
  fi
  break
done

if [[ ! -f "$OUT/report.json" ]]; then
  echo "playtest.sh: no report was written (exit code $code)" >&2
  exit 2
fi
RESULT="$(grep -m1 '"result"' "$OUT/report.json" | sed -E 's/.*"result": "([A-Z]+)".*/\1/')"
echo "PLAYTEST $SCEN: $RESULT (exit $code) - $OUT/report.md"
if [[ "$RESULT" == "PASS" && "$code" == "0" ]]; then exit 0; fi
exit 1
