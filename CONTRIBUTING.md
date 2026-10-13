# Working on this repo

MisoStory is generated: the Python in `src/` and `scripts/`, plus the data and docs, is the source of truth.
`MapleIsland.blend` and the renders are **build outputs**. They are not committed; they are rebuilt from source and
published as GitHub Release assets at milestones.

## What goes in git

| Tracked | Not tracked (and why) |
|---|---|
| `src/misostory/**` (framework, kit, 25 map modules) | `MapleIsland.blend`: a 35 MB compressed binary, rebuilt in about 50 s by `scripts/build_island.py` |
| `scripts/`, `tools/` (without `node_modules`) | `renders/`: the full render set is about 330 MB and regenerable with `scripts/render_all.sh` |
| `docs/**`: guides, research briefs, reviews, iteration log | `_scratch/`: agent sandboxes, test builds and logs |
| Generated text docs: `docs/VALIDATION.md`, `validation_report.json`, `build_report.json`, `manifest.json`, `MAPLE_ISLAND_MANIFEST.md`, `ASSET_CATALOG.md` | `docs/research/ref_renders`, `ref_sprites`, `ref_web`, `raw`: proprietary Nexon reference material that must never be redistributed |
| `docs/images/*.jpg`: a few small README images | Blender backups (`*.blend1`), caches, `node_modules/` |
| The art pack's pin and checksum manifest: `game/data/misostory/art_pack.json`, `tools/art_pack/<tag>.files.tsv` | `game/assets/art_pack/`: the pinned art pack (about 56 MB of GLBs), fetched from its Release (below) |

**Why the `.blend` and renders stay out of git.** Git cannot delta-compress them, so every rebuild that changed
would add another full copy (35 MB for the `.blend`, about 165 MB for the renders) to history forever. Twenty
commits like that would add gigabytes, slow every clone, and push the repo past GitHub's recommended size
(under 1 GB). Binary files also cannot be merged, so branches would conflict on them constantly.

## Everyday workflow

```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"   # Blender 5.2.2 LTS (Windows, Git Bash)
B=blender                                                         # Linux: Blender 5.2 on PATH

# the island's trees and foliage come from the pinned art pack: without it both builds below stop with exit 1
bash scripts/art_pack.sh fetch

# while authoring one map: build it alone, render its cameras, read MAP_TRAVERSAL_OK / PLAYER_IN_FRAME_OK
"$B" -b --factory-startup --python scripts/build_map.py -- <mapId> --debug

# full island -> MapleIsland.blend (also rewrites docs/build_report.json and the manifest)
"$B" -b --factory-startup --python scripts/build_island.py

# island validation -> docs/VALIDATION.md, docs/validation_report.json
"$B" -b MapleIsland.blend --python scripts/validate.py

# every camera -> renders/final/ (3 parallel Blender processes, debug variants included)
bash scripts/render_all.sh final 3 --debug

# the three review steps in one: render every camera, validate, tile renders/final/contact_sheet.png
bash scripts/review_island.sh final 3 --debug
```

`scripts/review_island.sh` runs `render_all.sh`, `validate.py` and `tools/contact_sheet.js` in that order on the
existing `MapleIsland.blend` and returns one exit code: 0 when all three pass, 1 when any fails. A step fails when a
camera did not render, when validation reports a high or medium finding or a check that is not ok (or Blender fails),
or when the sheet cannot be built; the last line names the failed steps (`REVIEW_FAILED: validate`). Validation runs
even after a failed render; the sheet needs the renders and `npm ci` in `tools/` once. `VALIDATE_OUT=<dir>` writes the
validation report there instead of `docs/`.

Commit the source change together with the regenerated text docs it affects (validation report, manifest,
asset catalog), so the docs in each commit describe that commit's island. Open work is tracked as GitHub
issues (`AGENTS.md`, `docs/agents/`). `docs/DEFERRED.md` lists only what has no ticket (out of scope, source-data
gaps, decisions against), so update it when one of those changes; `docs/ITERATION_LOG.md` is the record of the three
iterations. The authoring rules for map modules are in
`docs/AUTHORING.md`.

## README images

`docs/images/` holds a handful of small JPGs for the README (about 0.2-0.3 MB each). Refresh them only when the
look changes noticeably or at a milestone:

```bash
"$B" -b --factory-startup --python scripts/readme_images.py   # reads renders/final/, writes docs/images/
```

Don't commit full-size PNG renders. To show another view in the README, add it to `PICKS` in
`scripts/readme_images.py`.

## Releases (how the game, the `.blend` and the renders are shared)

Cut a release at each milestone (an iteration, or a notable visual pass), from a clean build of the tagged commit:

```bash
"$B" -b --factory-startup --python scripts/build_island.py
"$B" -b MapleIsland.blend --python scripts/validate.py          # every check should pass
bash scripts/render_all.sh final 3 --debug
powershell -NoProfile -Command "Compress-Archive -Force renders/final renders-final.zip"
bash scripts/build_runtime.sh                                    # exports the world into game/assets/world/
bash scripts/export_game.sh v0.4-<name>                          # desktop builds into game/export/
gh release create v0.4-<name> MapleIsland.blend renders-final.zip \
  game/export/MisoStory-v0.4-<name>-windows-x86_64.zip game/export/MisoStory-v0.4-<name>-linux-x86_64.tar.gz \
  --title "..." --notes "..."
```

`scripts/export_game.sh` exports the two presets in `game/export_presets.cfg` (Windows and Linux x86_64, one
self-contained executable each, without `tests/` and `tools/`). On first use it downloads the official Godot export
templates and checks them against Godot's published SHA-512 sums. The release templates can't load another scene from
the command line. To playtest an exported build, export a copy of `game/` with `tools/` included and
`run/main_scene` set to `res://tools/playtest/playtest_runner.tscn`, then run
`MisoStory.exe --headless --fixed-fps 60 -- --scenario <name> --out <dir>`.

In exported builds, only imported resources exist under `res://`: a `.glb` or `.ttf` is there as its imported copy,
not as the original file. Check for them with `ResourceLoader.exists()`, not `FileAccess.file_exists()`. JSON data
(and `*.txt`) is packed as is, through the presets' include filter.

Release assets don't touch git history, and each can be up to 2 GB. Download the latest with
`gh release download --repo itechify/maplestory-isometric --pattern "*.blend"`, or simply rebuild from source.
Name releases `v<major>.<minor>-<short-name>` (for example `v0.1-iteration-one`).

## Art pack releases (the pinned Project art)

The game's models and icons come from Jarvis's 3D asset pack (**Project art**), pinned as a GitHub Release asset and
never committed (ADR 0002, `docs/adr/0002-pinned-art-pack.md`). Art packs have their own tags,
**`art-pack-v<major>.<minor>`** (for example `art-pack-v1.0`), separate from the game's `v<major>.<minor>-<name>`
milestones. An art-pack release holds one asset, `MisoStory_Art_Pack_v<major>.<minor>.zip`, and is published with
`--latest=false` so it never displaces the latest game release.

```bash
bash scripts/art_pack.sh fetch    # install the pinned pack into game/assets/art_pack (build_runtime.sh does this)
bash scripts/art_pack.sh verify   # check the install file for file against the checksum manifest
bash scripts/validate_data.sh     # includes the coverage check: "ART PACK coverage: covered | missing | no pack"
```

The fetch caches the asset outside the repo (`%LOCALAPPDATA%/MisoStory/art-pack/`, Linux
`~/.local/share/MisoStory/art-pack/`), so a warm cache works offline; it fails on any checksum mismatch, and it leaves
a verified install alone so Godot does not re-import it. Without the pack the game falls back to its procedural
placeholders, and `NO_ART_PACK=1` leaves it out of the isolated copies of `test.sh`, `validate_data.sh` and
`playtest.sh`. Godot normalises every pack model as it imports it (`game/scripts/core/art/art_import.gd`).

**Bumping the pinned version** when Jarvis delivers a new pack (for example v1.1 from #61):

1. Download the delivery's ZIPs into a new, empty directory outside the repo. They are untrusted data: never run
   their scripts or open their `.blend` files.
2. Package the runtime subset into another new, empty directory (Python run isolated, from outside the delivery):
   ```bash
   "$PY" -I tools/art_pack/build_release.py --tag art-pack-v1.1 --out-dir <out> <delivery>/*.zip
   ```
   Remove an entry from `RENAMES` in `build_release.py` once the delivery fixes what it worked around (v1.1 drops the
   `bed.glb` rename), and keep `"$PY" -I tools/art_pack/test_build_release.py` passing.
3. Publish: `gh release create art-pack-v1.1 <out>/MisoStory_Art_Pack_v1.1.zip --latest=false --title "..." --notes "..."`.
4. Copy `<out>/art-pack-v1.1.files.tsv` to `tools/art_pack/`, delete the old manifest, and update the `release` block
   of `game/data/misostory/art_pack.json` (tag, asset, `asset_bytes`, `asset_sha256`, url, `checksum_manifest`) and
   its `project_art` record (delivery, packaging changes).
5. `bash scripts/art_pack.sh fetch`, then `bash scripts/validate_data.sh --report` (the coverage check, and the
   regenerated provenance report records the new tag), `bash scripts/test.sh art_` and the performance baseline
   check (`docs/runtime/PERF_BASELINE.md`). Commit the pin, the manifest and the regenerated docs together.

## If binaries ever need to live in the repo

Use [Git LFS](https://git-lfs.com) for `*.blend` and `*.png`: `git lfs track "*.blend" "*.png"`, then commit
`.gitattributes`. Clones stay small, but every version still counts against the account's LFS storage and
download quota. For occasional snapshots, Releases remain the better fit.
