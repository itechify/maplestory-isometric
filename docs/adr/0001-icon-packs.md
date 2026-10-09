# 0001: Icons resolve through icon packs over the procedural base

Status: Accepted, 2026-10-09 (the project owner's decisions)

## Context

Every item and skill icon in the UI was drawn in code: a shape and a tint per item, a picture per skill. The owner
wants Classic World's own icons. Names and values come only from the project's two sources, MeowDB MS Classic and
Henesys.gg ([`GLOSSARY.md`](../../GLOSSARY.md), Canonical). maplestory.io serves Classic World's art by ID: region
`MCW`, version `CBT2` (Classic World's second closed test, August 2026) has all 94 `game_item_id`s the game data
names, under the same names, and the three Beginner skills. The art is Nexon's, so the decision is where it lives: in
git, in the builds, or with the player.

## Decision

- Item and skill icons resolve through an ordered list of **icon packs**. The first pack that has a picture for an ID
  and variant wins, and the procedural icons are always underneath: with no pack, the game looks as it did before.
  Items are keyed by `game_item_id`, skills by `skill_id`. The pack format (format 1), the resolver and the display
  rules are in [`docs/runtime/UI.md`](../runtime/UI.md) (#49).
- The pack's pictures are **Source art**: they never supply a name or a value.
- A fetcher in `tools/icons/` (#50) builds the `maplestory_io` pack from maplestory.io `MCW/CBT2`. The PNGs it fetches
  are git-ignored and never committed; only the pack's manifest, `pack.json`, is tracked. The version is pinned in one
  place, and moving it to Classic World's launch version is #57.
- For now the builds bundle the pack: `scripts/build_runtime.sh` runs the fetcher before its Godot import, and
  `scripts/export_game.sh` ships whatever the pack holds. This is temporary. It ends when the build stops running the
  fetcher.
- The end state is bring-your-own packs (#54): a player adds a pack in a user folder, the fetcher is the documented way
  to build one, and the game itself ships no Nexon art.
- Icon packs change only the icons drawn in the UI. Ground drops, meso coins on the ground and the thrown Three Snails
  shell stay procedural 3D.

## Consequences

- A fresh clone has no pack PNGs, and neither has a build made with `--offline` from an empty cache. Both draw every
  icon procedurally, so the procedural base must keep covering every item and skill
  (`test_every_canonical_item_has_a_procedural_icon`).
- Tests never need the network or Nexon art: they layer small fake packs over the base.
- `pack.json` is the committed record of the pack: what each picture was fetched from and its checksum, and which IDs
  maplestory.io does not have. Anything the repository reports about the pack is built from it, not from the PNGs a
  checkout happens to hold.
- The rule that `docs/research/ref_*` and `raw` are never redistributed is unchanged. That reference material is not
  an icon pack, and the icon pack lives apart from it, under `game/assets/icon_packs/`.
- Git LFS is no way around this: it keeps every version of a file it tracks
  ([`CONTRIBUTING.md`](../../CONTRIBUTING.md)).

## Alternatives considered

- **Committing the PNGs.** Git history would keep the Nexon art even after the files are deleted.
- **Downloading the icons at runtime.** The game must work offline.
- **maplestory.io's GMS v83 data.** It numbers items differently: only 19 of the 94 `game_item_id`s match there,
  against 94 of 94 in `MCW`. Its Recovery icon is also a different picture.
