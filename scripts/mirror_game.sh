#!/usr/bin/env bash
# Sourced by scripts/test.sh, validate_data.sh and playtest.sh (not run on its own): the private copy of game/ an
# ISOLATE run works in.
#
#   source "$REPO/scripts/mirror_game.sh"
#   mirror_game "$REPO/game" "$DEST/game"
#
# Mirrors everything except the import cache (.godot) and the exported world (assets/world, which each caller copies
# as it needs), then drops files deleted from the source since the last mirror. The art pack (game/assets/art_pack)
# is mirrored unless NO_ART_PACK=1 asks for a run without it, in which case any copy of it is removed.

mirror_game() {
  local src="$1" dest="$2"
  local art_exclude=()
  mkdir -p "$dest"
  if [[ "${NO_ART_PACK:-0}" == "1" ]]; then
    art_exclude=(--exclude=./assets/art_pack)
    rm -rf "$dest/assets/art_pack"
  fi
  (cd "$src" && tar --exclude=./.godot --exclude=./assets/world "${art_exclude[@]}" -cf - .) | (cd "$dest" && tar -xf -)
  (cd "$dest" && find . -type f ! -path './.godot/*' ! -path './assets/world/*' | while read -r f; do
    [[ -e "$src/$f" ]] || rm -f "$f"
  done)
}
