#!/usr/bin/env bash
# Locate (and if needed download) the Godot 4.7.2 binary used by MisoStory, then run it with the given arguments.
#
#   bash scripts/godot.sh --version
#   bash scripts/godot.sh --headless --path game --script res://tests/run_tests.gd
#
# Override the binary with GODOT=/path/to/Godot_v4.x_console.exe. The default install location is outside the repo
# (%LOCALAPPDATA%/MisoStory/godot/<version>/) so the 180 MB editor binary never ends up in git or in a worktree.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
ROOT="${LOCALAPPDATA:-$HOME/AppData/Local}"
ROOT="$(cygpath -u "$ROOT" 2>/dev/null || echo "$ROOT")"
DIR="$ROOT/MisoStory/godot/$GODOT_VERSION"
CONSOLE="$DIR/Godot_v${GODOT_VERSION}-stable_win64_console.exe"

if [[ -z "${GODOT:-}" ]]; then
  if [[ ! -x "$CONSOLE" ]]; then
    echo "[godot.sh] Godot $GODOT_VERSION not found; downloading to $DIR" >&2
    mkdir -p "$DIR"
    curl -sSL -o "$DIR/godot.zip" \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_win64.exe.zip"
    (cd "$DIR" && unzip -o -q godot.zip && rm godot.zip)
  fi
  GODOT="$CONSOLE"
fi

exec "$GODOT" "$@"
