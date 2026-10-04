# Canonical gameplay data (MeowDB MS Classic)

MisoStory reproduces **MapleStory Classic World** as documented by [MeowDB MS Classic](https://meowdb.com/msclassic)
(NiaMeowDB, rebranding to NiaDB). MeowDB is the development-time source of truth; the game ships a local copy in
`game/data/canonical/` and never contacts MeowDB at runtime.

Gameplay facts courtesy of **NiaMeowDB (meowdb.com)**. Every record links to the page it came from
(`source.url`), and `game/data/canonical/canonical_sources.json` indexes all of them. Game names and text are the
property of Nexon Co., Ltd.

## What is here

| Domain | Files | Doc |
|---|---|---|
| maps | 25 Maple Island maps (MeowDB 9-digit ids), portals, spawns, NPC placements, return maps | [maps.md](maps.md), [topology_diff.md](topology_diff.md) |
| monsters, drops, breakables | Tutorial Jr. Sentinel, Snail, Blue Snail, Shroom, Red Snail, Orange Mushroom; drop lists; the Wooden Box | [monsters.md](monsters.md) |
| npcs | the 21 Maple Island NPCs with dialogue | [npcs.md](npcs.md) |
| quests | the 20 Maple Island quests (1000–1019) | [quests.md](quests.md) |
| shops | Pan, Sid, Lucy | [shops.md](shops.md) |
| items | the 95 items those reference | [items.md](items.md) |
| formulas | EXP table, Beginner rules, damage, accuracy, derived stats, attack speed and styles, spawn model, HP/MP gain, movement, recovery, death, loot rules | [formulas.md](formulas.md) |
| parity vectors (tests only) | 818 golden vectors computed by MeowDB's own calculators → `game/tests/data/parity_vectors.json` | [oracles.md](oracles.md) |

Ids are MeowDB's own (maps `"000000010"`, monsters `"2"`, items `"541"`, quests `"1002"`), not GMS ids.

## Reuse policy and how this data was collected

MeowDB's [Content Reuse Policy](https://meowdb.com/reuse) welcomes reuse of individual facts and figures with
credit and a link, but asks that bulk collection, mirroring, or a dataset "whose substance is our collection" be
cleared with **contact@meowdb.com** first. Its [Terms of Service](https://meowdb.com/terms) forbid automated
collection without permission.

The extractors in `tools/meowdb/` fetched roughly 300 pages once (2026-10-04), rate-limited, into a git-ignored local
cache, before those terms were reviewed. Since then:

- `tools/meowdb/lib.mjs` is **cache-only**: it throws instead of fetching unless `MEOWDB_ALLOW_NETWORK=1` is set.
  Do not set it until MeowDB has granted permission.
- Verbatim MeowDB site code (`docs/canonical/oracles/*.js.txt`) and the raw page cache stay out of git.
- Before MisoStory is published or the dataset redistributed, ask MeowDB for permission (their policy says they
  grant most good-faith requests), and keep the attribution line above in credits.

## Regenerating

Every file is reproducible from the local cache (`tools/meowdb/.cache`, git-ignored):

```bash
node tools/meowdb/extract_maps.mjs        # also writes game/data/misostory/map_id_crosswalk.json + topology_diff.md
node tools/meowdb/extract_monsters.mjs    # monsters/, drops/, breakables/
node tools/meowdb/extract_npcs.mjs
node tools/meowdb/extract_quests.mjs
node tools/meowdb/extract_shops.mjs
node tools/meowdb/extract_formulas.mjs
node tools/meowdb/extract_items.mjs
node tools/meowdb/oracle_vectors.mjs      # tests/data/parity_vectors.json (+ local-only oracle extracts)
node tools/meowdb/build_sources_index.mjs # canonical_sources.json
```

Validate the result against the game's own loader with `bash scripts/validate_data.sh`.

## Rules for using it

- Never edit canonical JSON by hand; fix the extractor and re-run it.
- A value MeowDB does not publish stays `null` and is listed under the record's `gaps`. If the game needs a value
  anyway, it goes in `game/data/misostory/` with a `reason` and `"verified": false`, never in canonical data.
- When two MeowDB pages disagree, the record's `discrepancies` says which value was chosen and why.

## Known MeowDB gaps the game fills with marked adaptations

| Gap | Where the adaptation lives |
|---|---|
| Item drop chances and quantities, meso drop amounts (MeowDB lists drops and votes only) | `game/data/misostory/drop_rates.json` |
| Drop ground lifetime and ownership time | `game/data/misostory/drops.json` |
| Natural HP/MP regeneration amount and interval | `game/data/misostory/recovery.json` |
| Bare-handed attack (MeowDB leaves Beginner bare-hand damage unmodeled) | `game/data/misostory/combat.json` |
| Player knockback distance, monster knockback distance and stagger time, post-hit invincibility | `game/data/misostory/combat.json` |
| HP/MP after respawning; which player spawn point a respawn uses | `game/data/misostory/death.json` |
| How many Roger's Apples Roger hands out (quest 1002) | `game/data/misostory/quests/1002.json` |
| The start map of a new character (inferred: 000000001) | `game/data/misostory/new_character.json` |
