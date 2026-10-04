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

**Why the `.blend` and renders stay out of git.** Git cannot delta-compress them, so every rebuild that changed
would add another full copy (35 MB for the `.blend`, about 165 MB for the renders) to history forever. Twenty
commits like that would add gigabytes, slow every clone, and push the repo past GitHub's recommended size
(under 1 GB). Binary files also cannot be merged, so branches would conflict on them constantly.

## Everyday workflow

```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"   # Blender 5.2.2 LTS

# while authoring one map: build it alone, render its cameras, read MAP_TRAVERSAL_OK / PLAYER_IN_FRAME_OK
"$B" -b --factory-startup --python scripts/build_map.py -- <mapId> --debug

# full island -> MapleIsland.blend (also rewrites docs/build_report.json and the manifest)
"$B" -b --factory-startup --python scripts/build_island.py

# island validation -> docs/VALIDATION.md, docs/validation_report.json
"$B" -b MapleIsland.blend --python scripts/validate.py

# every camera -> renders/final/ (3 parallel Blender processes, debug variants included)
bash scripts/render_all.sh final 3 --debug
```

Commit the source change together with the regenerated text docs it affects (validation report, manifest,
asset catalog), so the docs in each commit describe that commit's island. Keep `docs/ITERATION_LOG.md` and
`docs/DEFERRED.md` current when you fix or defer something notable. The authoring rules for map modules are in
`docs/AUTHORING.md`.

## README images

`docs/images/` holds a handful of small JPGs for the README (about 0.2-0.3 MB each). Refresh them only when the
look changes noticeably or at a milestone:

```bash
"$B" -b --factory-startup --python scripts/readme_images.py   # reads renders/final/, writes docs/images/
```

Don't commit full-size PNG renders. To show another view in the README, add it to `PICKS` in
`scripts/readme_images.py`.

## Releases (how the `.blend` and renders are shared)

Cut a release at each milestone (an iteration, or a notable visual pass), from a clean build of the tagged commit:

```bash
"$B" -b --factory-startup --python scripts/build_island.py
"$B" -b MapleIsland.blend --python scripts/validate.py          # every check should pass
bash scripts/render_all.sh final 3 --debug
powershell -NoProfile -Command "Compress-Archive -Force renders/final renders-final.zip"
gh release create v0.2-<name> MapleIsland.blend renders-final.zip --title "..." --notes "..."
```

Release assets don't touch git history, and each can be up to 2 GB. Download the latest with
`gh release download --repo itechify/maplestory-isometric --pattern "*.blend"`, or simply rebuild from source.
Name releases `v<major>.<minor>-<short-name>` (for example `v0.1-iteration-one`).

## If binaries ever need to live in the repo

Use [Git LFS](https://git-lfs.com) for `*.blend` and `*.png`: `git lfs track "*.blend" "*.png"`, then commit
`.gitattributes`. Clones stay small, but every version still counts against the account's LFS storage and
download quota. For occasional snapshots, Releases remain the better fit.
