#!/usr/bin/env bash
# Locate (and if needed download) the Godot 4.7.2 binary used by MisoStory, then run it with the given arguments.
#
#   bash scripts/godot.sh --version
#   bash scripts/godot.sh --headless --path game --script res://tests/run_tests.gd
#   bash scripts/godot.sh --gui --path game        # Windows: the GUI exe instead of the console one (same on Linux)
#
# Override the binary with GODOT=/path/to/godot. On Linux a `godot` on PATH is used when its version matches;
# otherwise the official build is downloaded. The default install location is outside the repo
# (Windows: %LOCALAPPDATA%/MisoStory/godot/<version>/, Linux: ~/.local/share/MisoStory/godot/<version>/) so the
# 180 MB editor binary never ends up in git or in a worktree.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GUI=0
if [[ "${1:-}" == "--gui" ]]; then GUI=1; shift; fi

case "$(uname -s)" in
  Linux)
    case "$(uname -m)" in
      aarch64|arm64) PLATFORM="linux.arm64" ;;
      *) PLATFORM="linux.x86_64" ;;
    esac
    DIR="${XDG_DATA_HOME:-$HOME/.local/share}/MisoStory/godot/$GODOT_VERSION"
    ZIP="Godot_v${GODOT_VERSION}-stable_${PLATFORM}.zip"
    CONSOLE="$DIR/Godot_v${GODOT_VERSION}-stable_${PLATFORM}"
    WINDOWED="$CONSOLE"
    ;;
  *)
    ROOT="${LOCALAPPDATA:-$HOME/AppData/Local}"
    ROOT="$(cygpath -u "$ROOT" 2>/dev/null || echo "$ROOT")"
    DIR="$ROOT/MisoStory/godot/$GODOT_VERSION"
    ZIP="Godot_v${GODOT_VERSION}-stable_win64.exe.zip"
    CONSOLE="$DIR/Godot_v${GODOT_VERSION}-stable_win64_console.exe"
    WINDOWED="$DIR/Godot_v${GODOT_VERSION}-stable_win64.exe"
    ;;
esac

if [[ -z "${GODOT:-}" ]]; then
  # A system Godot (e.g. from the distro) is fine as long as it is the pinned version: `godot --version` prints
  # e.g. 4.7.2.stable.arch_linux.
  if [[ "$(uname -s)" == Linux ]] && command -v godot >/dev/null 2>&1 \
      && [[ "$(godot --version 2>/dev/null)" == "${GODOT_VERSION}.stable"* ]]; then
    GODOT="$(command -v godot)"
  else
    if [[ ! -x "$CONSOLE" ]]; then
      echo "[godot.sh] Godot $GODOT_VERSION not found; downloading to $DIR" >&2
      mkdir -p "$DIR"
      curl -sSfL -o "$DIR/godot.zip" \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/$ZIP"
      (cd "$DIR" && unzip -o -q godot.zip && rm godot.zip)
      chmod +x "$CONSOLE" "$WINDOWED"
    fi
    if [[ "$GUI" == 1 ]]; then GODOT="$WINDOWED"; else GODOT="$CONSOLE"; fi
  fi
fi

exec "$GODOT" "$@"
