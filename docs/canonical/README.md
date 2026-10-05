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
| quests | the 20 Maple Island quests (1000–1019), with the live tracker's tags (all "Missable", "COT2") | [quests.md](quests.md) |
| shops | Pan, Sid, Lucy | [shops.md](shops.md) |
| items | the 96 items those reference (Green Apple, 242, built from a hand-read API capture) | [items.md](items.md) |
| formulas | EXP table, Beginner rules, damage, accuracy, derived stats, attack speed and styles, spawn model, HP/MP gain, movement, recovery, death, loot rules | [formulas.md](formulas.md) |
| parity vectors (tests only) | 818 golden vectors computed by MeowDB's own calculators → `game/tests/data/parity_vectors.json` | [oracles.md](oracles.md) |

Ids are MeowDB's own (maps `"000000010"`, monsters `"2"`, items `"541"`, quests `"1002"`), not GMS ids.

## Reuse policy and how this data was collected

MeowDB's [Content Reuse Policy](https://meowdb.com/reuse) welcomes reuse of individual facts and figures with
credit and a link, but asks that bulk collection, mirroring, or a dataset "whose substance is our collection" be
cleared with **contact@meowdb.com** first. Its [Terms of Service](https://meowdb.com/terms) forbid automated
collection without permission.

The extractors in `tools/meowdb/` made 524 requests once (2026-10-04, one per 1.2 s, into a git-ignored local cache)
before those terms were reviewed: about 230 pages, 210 `/msclassic/api/` calls and 84 JavaScript bundles. Since then:

- The extractors are cache-only (Iteration Three decision D3-1, `docs/ITERATION_LOG.md`): `tools/meowdb/lib.mjs`
  never touches the network unless `MEOWDB_ALLOW_NETWORK=1` is set, and that stays off unless MeowDB grants
  permission. Newer MeowDB facts come in as dated captures of pages read by hand in a normal browser
  (`tools/meowdb/captures/`, next to the KuroDB and Hidden Street captures; see "Sources" below).
- Verbatim MeowDB site code (`docs/canonical/oracles/*.js.txt`) and the raw page cache stay out of git.
- Before MisoStory is published or the dataset redistributed, ask MeowDB for permission (their policy says they
  grant most good-faith requests), and keep the attribution line above in credits.

## Sources

MeowDB MS Classic stays the authority for everything except what the project owner moved elsewhere (Iteration Three,
decisions D3-1 to D3-9 in `docs/ITERATION_LOG.md`, contract C7 in `docs/runtime/ITERATION_THREE_CONTRACTS.md`):

| Authority | May supply | Read from |
|---|---|---|
| MeowDB MS Classic | everything | the local cache, plus hand-read captures in `tools/meowdb/captures/` |
| KuroDB (`https://playkuro.com/database/#...`) | drop and meso-drop probabilities only | `tools/kurodb/captures/` |
| Hidden Street, Before Chaos archive (`https://bc.hidden-street.net/...`) | monster drop membership and meso amounts only | `tools/hiddenstreet/captures/` |
| Project owner | a decision (cites its id, e.g. D3-5, or the Iteration Three brief) | `docs/ITERATION_LOG.md` |

A record names a different authority per property with `provenance.<property>` (schema v2 drop records also cite one
per entry); every non-MeowDB value carries its URL, `read_at` and the capture file it was read from. The validator
enforces these rules from one registry (`game/scripts/core/validation/provenance_authorities.gd`; see
[DATA_VALIDATION.md](../runtime/DATA_VALIDATION.md)).

The captures are never fetched by a tool. `tools/sources/captures.mjs` loads every capture file offline into
structured objects (KuroDB drop and meso rows, reactor values, Hidden Street drop lists and meso amounts, MeowDB live
monster, breakable and quest pages, item API bodies), and `tools/sources/parse.mjs` turns raw values into numbers
exactly (KuroDB `"0.0700% base"` is 0.0007; `"Chance value 4"` is 1/4, an interpretation by decision D3-7; Hidden
Street `"Mesos: 4-6"`), keeping every raw string. Tests: `node --test tools/sources/test/`.

## Regenerating

Every file is reproducible offline from the local cache (`tools/meowdb/.cache`, git-ignored) and the dated captures
(`tools/*/captures/`, in git). `tools/meowdb/lib.mjs` reads the cache first; on a miss it serves a MeowDB API body
captured by hand for exactly that URL (`tools/meowdb/captures/items_api.json`, through
`tools/sources/captures.mjs`), and otherwise stops with "not cached":

```bash
node tools/meowdb/extract_maps.mjs        # also writes game/data/misostory/map_id_crosswalk.json + topology_diff.md
node tools/meowdb/extract_monsters.mjs    # monsters/, drops/, breakables/
node tools/meowdb/extract_npcs.mjs
node tools/meowdb/extract_quests.mjs      # + missable / tracker_tags from the quest tracker capture
node tools/meowdb/extract_shops.mjs
node tools/meowdb/extract_formulas.mjs
node tools/meowdb/extract_items.mjs       # Green Apple (242) from its item API capture (API-only record)
node tools/meowdb/oracle_vectors.mjs      # tests/data/parity_vectors.json (+ local-only oracle extracts)
node tools/meowdb/build_sources_index.mjs # canonical_sources.json (capture files and per-property authorities too)
```

Validate the result against the game's own loader with `bash scripts/validate_data.sh`.

**Reproducibility.** `bash scripts/check_canonical.sh` proves the snapshot is regenerable: it copies what the
extractors read (the tools with the cache and the captures, the data, the Iteration One docs, `src/misostory/layout.py`)
into a temporary folder, empties every output folder there, runs the extractors above in order with network access off
(`MEOWDB_ALLOW_NETWORK` cleared), then diffs `game/data/canonical` and `game/data/misostory/map_id_crosswalk.json` byte
for byte against the repository (`CANONICAL_CHECK_PASSED`; exit 1 on a difference, 2 when an extractor fails or the
cache is missing; `--keep` keeps the copy). A file no extractor writes any more shows up as "only in the repository".
`docs/canonical/topology_diff.md` is compared too but only reported, because it also reads Blender-side files that
change with each world build; refresh it with `node tools/meowdb/extract_maps.mjs`. `extract_maps.mjs` checks its
parse of `layout.py` against `docs/topology.json` (`LINKS` and `DOOR_LINKS` join exactly its 24 map pairs; every
`ONE_WAY` anchor is an arrival point there), so a layout change does not break the extractor, and the diff says whether
`ONE_WAY` still equals the landing anchors of MeowDB's one-way links. The cache is git-ignored, so the check runs
locally; run it before each milestone.

**Reports.** `bash scripts/validate_data.sh --report` writes the provenance validation report
([`../PROVENANCE_REPORT.md`](../PROVENANCE_REPORT.md): every record and property with its authority, URL, read time
and capture; every unresolved value; every adaptation), and `node tools/parity/build_parity.mjs` the parity manifest
([`../MAPLE_ISLAND_PARITY.md`](../MAPLE_ISLAND_PARITY.md)) from the data, that report and the test evidence.

## Rules for using it

- Never edit canonical JSON by hand; fix the extractor and re-run it.
- A value MeowDB does not publish stays `null` and is listed under the record's `gaps`. If the game needs a value
  anyway, it goes in `game/data/misostory/` with a `reason` and `"verified": false`, never in canonical data.
- When two MeowDB pages disagree, the record's `discrepancies` says which value was chosen and why.

## Known MeowDB gaps the game fills with marked adaptations

| Gap | Where the value or adaptation lives |
|---|---|
| Item drop chances, meso drop chances, most meso amounts (MeowDB lists drops and votes only) | Not adaptations any more: KuroDB chances and Hidden Street membership and amounts, by the owner's decisions D3-3 to D3-7, in the schema v2 drop records (contract C1). A value neither source gives stays unresolved and never drops. Until the drop records are v2, the runtime rolls the Iteration Two placeholders of `game/data/misostory/drop_rates.json` (the provenance report and the parity manifest list each one) |
| Drop ground lifetime and ownership time | `game/data/misostory/drops.json` |
| Natural HP regeneration (10 HP per 10 s of eligible time) | The project owner's rule (brief "Natural HP Regeneration", contract C4): authority `Project owner`, `verified: true` against that brief section, in `game/data/misostory/recovery.json` (the mechanics package; Iteration Two's placeholder was `combat.json natural_recovery`). MP has no natural recovery: MeowDB documents none |
| Bare-handed attack (MeowDB leaves Beginner bare-hand damage unmodeled) | `game/data/misostory/combat.json` |
| Player knockback distance, monster knockback distance and stagger time, post-hit invincibility | `game/data/misostory/combat.json` |
| HP/MP after respawning; which player spawn point a respawn uses | `game/data/misostory/death.json` |
| How many Roger's Apples Roger hands out (quest 1002) | `game/data/misostory/quests/1002.json` |
| The start map of a new character (inferred: 000000001) | `game/data/misostory/new_character.json` |
