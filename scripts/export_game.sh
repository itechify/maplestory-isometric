#!/usr/bin/env bash
# Export the playable game as desktop builds (Windows x86_64 and Linux x86_64) for a GitHub Release.
#
#   bash scripts/build_runtime.sh                 # first: the world in game/assets/world/ is a build output
#   bash scripts/export_game.sh [<label>]         # e.g. v0.3-iteration-three (default: the short commit hash)
#
# Writes game/export/MisoStory-<label>-windows-x86_64.zip and MisoStory-<label>-linux-x86_64.tar.gz (git-ignored).
# Each holds one self-contained executable (the game data is embedded), the font license and a short README.
# Presets: game/export_presets.cfg. On first use the official Godot export templates (about 1.3 GB) are downloaded,
# checked against Godot's SHA512-SUMS.txt, and only the Windows and Linux x86_64 templates are kept.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
LABEL="${1:-$(git rev-parse --short HEAD)}"
OUT="$REPO/game/export"

if [[ ! -f game/assets/world/index.json ]]; then
  echo "export_game.sh: game/assets/world/ is missing; run bash scripts/build_runtime.sh first" >&2
  exit 2
fi

case "$(uname -s)" in
  Linux) TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$GODOT_VERSION.stable" ;;
  *) TPL="$(cygpath -u "${APPDATA:-$HOME/AppData/Roaming}" 2>/dev/null || echo "$APPDATA")/Godot/export_templates/$GODOT_VERSION.stable" ;;
esac
NEED=(version.txt windows_release_x86_64.exe windows_release_x86_64_console.exe linux_release.x86_64)
missing=0
for f in "${NEED[@]}"; do [[ -f "$TPL/$f" ]] || missing=1; done
if [[ $missing == 1 ]]; then
  echo "[export_game] downloading the Godot $GODOT_VERSION export templates to $TPL"
  BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
  TPZ="Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -sSfL -o "$TMP/$TPZ" "$BASE/$TPZ"
  curl -sSfL -o "$TMP/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
  (cd "$TMP" && grep " $TPZ\$" SHA512-SUMS.txt | sha512sum -c -)
  mkdir -p "$TPL"
  unzip -o -j -q "$TMP/$TPZ" $(printf 'templates/%s ' "${NEED[@]}") -d "$TPL"
fi

rm -rf "$OUT/windows" "$OUT/linux"
mkdir -p "$OUT/windows" "$OUT/linux"
bash scripts/godot.sh --headless --path game --import >/dev/null 2>&1 || true
bash scripts/godot.sh --headless --path game --export-release "Windows Desktop" "$OUT/windows/MisoStory.exe"
bash scripts/godot.sh --headless --path game --export-release "Linux" "$OUT/linux/MisoStory.x86_64"
for f in "$OUT/windows/MisoStory.exe" "$OUT/linux/MisoStory.x86_64"; do
  [[ -s "$f" ]] || { echo "export_game.sh: $f was not written" >&2; exit 1; }
done

readme() {  # $1: how to start the game on that platform
  cat <<EOF
MisoStory $LABEL: classic Maple Island as an isometric 3D game.
https://github.com/itechify/maplestory-isometric

Start: $1

Keys: W A S D move, Space jump, J or left click attack, F talk, Up arrow for portals and ladders, Z pick up.
Every control is listed in the pause menu (Esc, Controls) and in the repository README.

Saves are kept in the Godot user folder for "MisoStory"
(Windows: %APPDATA%\\Godot\\app_userdata\\MisoStory, Linux: ~/.local/share/godot/app_userdata/MisoStory).

The font is Nunito, under the SIL Open Font License (OFL.txt).
EOF
}
cp game/assets/fonts/nunito/OFL.txt "$OUT/windows/OFL.txt"
cp game/assets/fonts/nunito/OFL.txt "$OUT/linux/OFL.txt"
readme "double-click MisoStory.exe. It is not code-signed, so Windows SmartScreen may ask: More info, Run anyway." \
  | sed 's/$/\r/' > "$OUT/windows/README.txt"
readme "./MisoStory.x86_64 (Vulkan drivers needed)." > "$OUT/linux/README.txt"

WIN_ZIP="$OUT/MisoStory-$LABEL-windows-x86_64.zip"
LIN_TGZ="$OUT/MisoStory-$LABEL-linux-x86_64.tar.gz"
rm -f "$WIN_ZIP" "$LIN_TGZ"
if command -v zip >/dev/null 2>&1; then
  (cd "$OUT/windows" && zip -q -9 "$WIN_ZIP" MisoStory.exe README.txt OFL.txt)
else
  powershell -NoProfile -Command "Compress-Archive -Force -Path '$(cygpath -w "$OUT/windows")\\*' -DestinationPath '$(cygpath -w "$WIN_ZIP")'"
fi
# Explicit modes keep the Linux binary executable even when the archive is made on Windows.
LIN_TAR="${LIN_TGZ%.gz}"
rm -f "$LIN_TAR"
tar -C "$OUT/linux" --owner=0 --group=0 --mode=0644 -cf "$LIN_TAR" README.txt OFL.txt
tar -C "$OUT/linux" --owner=0 --group=0 --mode=0755 -rf "$LIN_TAR" MisoStory.x86_64
gzip -9 "$LIN_TAR"
ls -la "$WIN_ZIP" "$LIN_TGZ"
