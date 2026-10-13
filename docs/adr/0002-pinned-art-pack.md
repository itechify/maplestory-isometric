# 0002: Jarvis's 3D asset pack is pinned as a Release asset, not generated in the repo

Status: Accepted, 2026-10-13 (the project owner's decisions on #59)

The island's kit is generated from Python in `src/misostory/` on every build, so a reader would expect the rigged
characters, monsters, items and environment models of Jarvis's asset pack (**Project art**, made in Blender 4.3.2 by
the owner's ChatGPT agent Jarvis) to be generated the same way. They are not. The pack's generators are about 2,500
lines that `exec()` text slices of each other, depend on intermediate `.blend` files the pack leaves out, match NPCs
by name, and were never run on the repo's Blender 5.2. Porting them would be a large refactor with no visible gain.
Instead, the pack's runtime subset (GLBs, icons, `asset_index.json` and manifests, provenance docs, and the generator
source as a not-run reference) is published as a versioned GitHub Release asset (`art-pack-v<major>.<minor>`). Its
checksum manifest is committed, and a fetch script brings it into the build. The kit's `@asset` builders import the
pinned GLBs during the Blender build, so the export still derives collision and checks routes. Characters, monsters
and items go straight to Godot. Everything is looked up by ID through `asset_index.json`, never by filename. Jarvis
keeps the generators outside the repo, and a change to the art arrives as a new pack version and a version bump.

## Considered Options

- Port the generators into `src/misostory/`: rejected for now. A single generator can still be ported later if its
  art needs editing in the repo.
- Commit the GLBs (about 56 MB) or keep them in Git LFS: rejected by `CONTRIBUTING.md`'s binaries policy.
- Layer the pack over the old proxies as an optional pack: rejected. The pack's art is the game's only art; the
  procedural placeholders remain only as the fallback when no art is present (tests, a fresh clone).
