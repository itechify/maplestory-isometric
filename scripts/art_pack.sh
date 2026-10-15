#!/usr/bin/env bash
# The pinned art pack (Project art: Jarvis's 3D asset pack; ADR 0002): fetch it from its GitHub Release, verify every
# file against the committed checksum manifest, and install it where Godot and the Blender build both read it.
#
#   bash scripts/art_pack.sh fetch    # (default) install/repair game/assets/art_pack from the pinned release
#   bash scripts/art_pack.sh verify   # exit 0 only when the installed pack matches the manifest file for file
#   bash scripts/art_pack.sh where    # print the install directory, the cache file and the pinned tag
#
# The pin is game/data/misostory/art_pack.json ("release": tag, asset, asset_bytes, asset_sha256, url and the
# checksum manifest, tools/art_pack/<tag>.files.tsv with path<TAB>bytes<TAB>sha256 per file). The release asset is
# cached outside the repo, like the Godot binary (Windows %LOCALAPPDATA%/MisoStory/art-pack/<tag>/, Linux
# ~/.local/share/MisoStory/art-pack/<tag>/), so a warm cache works offline. The install directory is git-ignored.
#
# fetch: does nothing when the install already verifies (so Godot never re-imports an unchanged pack). Otherwise it
# takes the cached asset (or downloads it) only when its SHA-256 matches the pin, extracts it to a temporary
# directory, checks every file against the manifest, then copies it into place, removes files the manifest does not
# list (Godot's *.import files are kept) and verifies the result. Any mismatch fails loudly with exit 1, and nothing
# is installed from an asset that failed its check. A corrupted install is repaired from the verified asset.
#
# Overrides (tests): ART_PACK_PIN, ART_PACK_DIR (install dir), ART_PACK_CACHE (cache root), ART_PACK_URL.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="${1:-fetch}"

PIN="${ART_PACK_PIN:-$REPO/game/data/misostory/art_pack.json}"
DIR="${ART_PACK_DIR:-$REPO/game/assets/art_pack}"

die() { echo "[art_pack] FAILED: $*" >&2; exit 1; }
[[ -f "$PIN" ]] || die "no pin file at $PIN"

# One "key": value pair of the pin's release block (keys are unique in the file).
pin_field() {
  local v
  v="$(grep -o "\"$1\": *\(\"[^\"]*\"\|[0-9][0-9]*\)" "$PIN" | head -1 | sed 's/^"[^"]*": *//; s/^"//; s/"$//')"
  [[ -n "$v" ]] || die "pin $PIN has no \"$1\""
  echo "$v"
}
TAG="$(pin_field tag)"
ASSET="$(pin_field asset)"
ASSET_SHA="$(pin_field asset_sha256)"
URL="${ART_PACK_URL:-$(pin_field url)}"
MANIFEST="$(pin_field checksum_manifest)"
[[ "$MANIFEST" = /* || "$MANIFEST" =~ ^[A-Za-z]: ]] || MANIFEST="$REPO/$MANIFEST"
[[ -f "$MANIFEST" ]] || die "no checksum manifest at $MANIFEST"

if [[ -n "${ART_PACK_CACHE:-}" ]]; then
  CACHE_ROOT="$ART_PACK_CACHE"
elif [[ "$(uname -s)" == Linux ]]; then
  CACHE_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/MisoStory/art-pack"
else
  CACHE_ROOT="${LOCALAPPDATA:-$HOME/AppData/Local}"
  CACHE_ROOT="$(cygpath -u "$CACHE_ROOT" 2>/dev/null || echo "$CACHE_ROOT")/MisoStory/art-pack"
fi
CACHED="$CACHE_ROOT/$TAG/$ASSET"

# path<TAB>bytes<TAB>sha256 for every file under $1 except Godot's *.import files, sorted like the manifest.
inventory() {
  local root="$1" sizes hashes
  sizes="$(cd "$root" && find . -type f ! -name '*.import' -printf '%P\t%s\n' | LC_ALL=C sort)"
  [[ -n "$sizes" ]] || return 0
  hashes="$(cd "$root" && find . -type f ! -name '*.import' -print0 | xargs -0 sha256sum \
    | sed 's/^\\//; s/^\([0-9a-f]*\) [ *]\.\//\1\t/' | LC_ALL=C sort -t $'\t' -k2,2)"
  LC_ALL=C join -t $'\t' -1 1 -2 2 <(echo "$sizes") <(echo "$hashes") | LC_ALL=C sort
}

# Compare a directory with the manifest; prints each difference, returns 1 on any.
check_dir() {
  local root="$1" diffs
  diffs="$(diff <(LC_ALL=C sort "$MANIFEST" | tr -d '\r') <(inventory "$root") || true)"
  if [[ -n "$diffs" ]]; then
    echo "$diffs" | grep '^[<>]' | sed 's/^< /  expected: /; s/^> /  found:    /' | head -40 >&2
    return 1
  fi
  return 0
}

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

case "$CMD" in
  where)
    echo "install: $DIR"
    echo "cache:   $CACHED"
    echo "tag:     $TAG"
    exit 0
    ;;
  verify)
    [[ -d "$DIR" ]] || die "no art pack at $DIR (run: bash scripts/art_pack.sh fetch)"
    if check_dir "$DIR"; then
      echo "[art_pack] $TAG verified at $DIR"
      exit 0
    fi
    die "$DIR does not match $MANIFEST (run: bash scripts/art_pack.sh fetch)"
    ;;
  fetch) ;;
  *) echo "usage: bash scripts/art_pack.sh [fetch|verify|where]" >&2; exit 2 ;;
esac

if [[ -d "$DIR" ]] && check_dir "$DIR" 2>/dev/null; then
  echo "[art_pack] $TAG is up to date at $DIR"
  exit 0
fi

# 1. A release asset whose SHA-256 matches the pin: the cached copy, or a fresh download.
mkdir -p "$CACHE_ROOT/$TAG"
if [[ -f "$CACHED" && "$(sha_of "$CACHED")" == "$ASSET_SHA" ]]; then
  echo "[art_pack] using the cached $ASSET"
else
  [[ -f "$CACHED" ]] && echo "[art_pack] the cached $ASSET does not match the pinned SHA-256; downloading it again" >&2
  rm -f "$CACHED"
  echo "[art_pack] downloading $URL"
  part="$CACHED.part"
  rm -f "$part"
  if ! curl -fsSL --retry 2 -o "$part" "$URL"; then
    rm -f "$part"
    die "cannot download $URL and there is no valid cached copy at $CACHED"
  fi
  got="$(sha_of "$part")"
  if [[ "$got" != "$ASSET_SHA" ]]; then
    rm -f "$part"
    die "$ASSET has SHA-256 $got, the pin says $ASSET_SHA"
  fi
  mv "$part" "$CACHED"
fi

# 2. Extract to a temporary directory and check every file before anything is installed.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/art_pack.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
unzip -q -o "$CACHED" -d "$STAGE"
if ! check_dir "$STAGE"; then
  die "$ASSET does not match the checksum manifest $MANIFEST"
fi

# 3. Install: copy over, drop what the manifest does not list (and orphaned .import files), verify the result.
if [[ -d "$DIR" ]]; then
  echo "[art_pack] repairing $DIR" >&2
fi
mkdir -p "$DIR"
cp -r "$STAGE/." "$DIR/"
listed="$(cut -f1 "$MANIFEST" | tr -d '\r' | LC_ALL=C sort)"
present="$(cd "$DIR" && find . -type f ! -name '*.import' -printf '%P\n' | LC_ALL=C sort)"
while IFS= read -r stray; do
  [[ -n "$stray" ]] && rm -f "$DIR/$stray" && echo "[art_pack] removed $stray (not in the manifest)" >&2
done < <(LC_ALL=C comm -13 <(echo "$listed") <(echo "$present"))
while IFS= read -r imp; do
  [[ -n "$imp" && ! -e "$DIR/${imp%.import}" ]] && rm -f "$DIR/$imp"
done < <(cd "$DIR" && find . -type f -name '*.import' -printf '%P\n')
check_dir "$DIR" || die "$DIR does not match $MANIFEST after installing"
echo "[art_pack] $TAG installed at $DIR ($(wc -l < "$MANIFEST" | tr -d ' ') files verified)"
