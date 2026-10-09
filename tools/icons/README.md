# The maplestory.io icon pack fetcher

`fetch_pack.mjs` builds the `maplestory_io` icon pack in `game/assets/icon_packs/maplestory_io/`, in the pack format
the game's icon resolver reads (format 1, #49). It fetches from [maplestory.io](https://maplestory.io), region `MCW`
(Classic World), version `CBT2` (its second closed test). The version is pinned in one place, `SOURCE` in `lib.mjs`.
The PNGs are Nexon art: they are git-ignored and never committed (`docs/adr/0001-icon-packs.md`). Only `pack.json` is
tracked.

## Running it on its own

`scripts/build_runtime.sh` runs the fetcher before its Godot import. To fetch or refresh the icons without rebuilding
the island, run it alone and then import the new PNGs:

```bash
node tools/icons/fetch_pack.mjs                          # fetch what the cache lacks (about 6 minutes from empty)
bash scripts/godot.sh --headless --path game --import    # import the new PNGs so the game can load them
```

| Flag or variable | Effect |
|---|---|
| `--offline` | Never touches the network. The pack gets the PNGs the cache holds, and `pack.json` is left untouched |
| `--refresh` | Fetches every answer again. A variant whose bytes changed gets a new `fetched` date |
| `ICONS_CACHE_DIR=<dir>` | Keeps the cache in `<dir>` instead of `tools/icons/.cache/` (git-ignored), so several checkouts share one |
| `--pack-dir <dir>`, `--data-dir <dir>` | Another pack folder or game data folder (defaults `game/assets/icon_packs/maplestory_io`, `game/data`) |

A run prints one line and exits 0, whatever it could fetch:

```
icons: 94/94 items, 3/3 skills present (maplestory.io MCW/CBT2)
```

An ID is present when every variant's PNG is in the pack folder. When there are any, the line adds the variants
maplestory.io answered do not exist and the variants not reached this run (with why, such as `--offline`,
`network unavailable` or `maplestory.io answered http 500`). Exit 2 means a bad command line.

## What it fetches

Only the IDs the game data refers to, never the whole catalogue (`wantedIds` in `pack.mjs`):

- **Items**: every `game_item_id` in `game/data/canonical/items/*.json`, plus every value of a key named
  `item_icon_key` or `icon_key` anywhere in `game/data` (quests, shops, `formulas/attack_styles.json`). Per item:
  - `https://maplestory.io/api/MCW/CBT2/item/<id>`, the item's JSON, for `metaInfo.iconOrigin` and `iconRawOrigin`;
  - `.../item/<id>/icon` and `.../item/<id>/iconRaw`, the PNGs (`icon` is `iconRaw` plus a soft shadow).
- **Skills**: every `skills[].skill_id` in `game/data/canonical/formulas/*.json` (today `beginner.json`: `0001000` to
  `0001002`), each as `icon`, `iconMouseOver` and `iconDisabled` from
  `https://maplestory.io/api/wz/img/MCW/CBT2/Skill/_Canvas/<job>.img/skill/<id>/<variant>` (32x32). The `.img` file
  is the job's, the skill ID without its last four digits: `000.img` for Beginner.

Paths that do not work for the Beginner skills: the same path without `_Canvas` answers 200 with a blank 1x1 PNG, and
the `/job/.../skillbook` and `/job/skill/...` endpoints answer 500. maplestory.io answers an unknown item's JSON with
200 `null`, which gives no origin.

## How it behaves

- **Cache first** (`lib.mjs`, the pattern of `tools/meowdb/lib.mjs`). An answer is fetched once and kept, so a second
  run makes no request. Only definitive answers are cached: a 200 and a 404. A network error, a timeout (also one in
  the middle of a download), 403, 429 or a 5xx is tried three times, then given up for this run.
- **Giving up.** Counting only the URLs the run asks (a cache hit is not asked): after three in a row could not reach
  maplestory.io (a network error or a timeout), the network is taken to be down and the run stops asking, so a build
  without a network takes seconds. An error status means the network is up. The run then stops asking only after ten
  URLs in a row got one, so one ID maplestory.io cannot serve (an item or a skill has three URLs) never stops it: its
  variants are not reached and the run goes on to the next ID.
- **Polite.** At least 1.2 s between requests across every process sharing the cache, one request at a time, and a
  User-Agent that names the project.
- **Misses.** A 404, a 1x1 image or a body that is not a PNG is a miss: maplestory.io says the variant does not exist.
  A miss never fails the run, and a malformed answer is a miss, not a crash.
- **The PNG itself.** maplestory.io appends a short trailer after each PNG's IEND chunk (`00 dd 01`, then JSON: a
  notice, the serving container, its git hash, the URL and the time the image was generated). The pack keeps the PNG
  through IEND, so a variant's sha256 and `fetched` date follow the picture, not the time the server regenerated it.
  The cache keeps the answer as it came.

## pack.json

```
game/assets/icon_packs/maplestory_io/pack.json                            tracked
game/assets/icon_packs/maplestory_io/items/<game_item_id>/<variant>.png   git-ignored   (icon, iconRaw)
game/assets/icon_packs/maplestory_io/skills/<skill_id>/<variant>.png      git-ignored   (icon, iconMouseOver, iconDisabled)
```

`pack.json` records the last successful fetch of each variant: its URL, sha256, size `[w, h]`, origin `[x, y]` (items
only; absent when maplestory.io gives none) and fetch date. `missing` lists each variant maplestory.io answered does not
exist, with the reason (`http 404`, `blank 1x1 image`, `not a PNG (<content type>)`).

- It changes only when a variant is obtained (new, or with new bytes under `--refresh`) or when maplestory.io answers
  that a variant does not exist. A variant's `fetched` date changes only when its bytes change. An ID the game data no
  longer names is dropped.
- `--offline` never writes it, and neither does a run that stopped asking (the network down, or ten errors in a row),
  even when the game data has dropped an ID. Otherwise a fresh clone's offline build would overwrite the committed
  manifest with every ID missing. What such a run did fetch is cached, and the next run records it. A run that asked
  every URL writes it, even when some got an error: an error is not a miss, so those variants keep their records. What
  is present locally is the summary line's business, not the manifest's.
- The text is stable: a fixed key order, IDs in numeric order, one line per variant. A cache-hit run leaves it
  byte-for-byte unchanged.

`docs/PROVENANCE_REPORT.md` lists the pack's source, version, covered and missing IDs from `pack.json` alone
(`bash scripts/validate_data.sh --report`), so the report does not depend on which PNGs a checkout has.

## Tests

```bash
node --test tools/icons/test/    # the ID list, the 1x1 rejection, misses and their reasons, the pack.json shape,
                                 # cache first, --offline and --refresh, giving up and when pack.json is written;
                                 # fetch is a stub, never the network
```
