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
| monsters, drops, breakables | Tutorial Jr. Sentinel, Snail, Blue Snail, Shroom, Red Snail, Orange Mushroom; schema v2 drop records (Hidden Street or MeowDB membership, KuroDB chances, meso amounts and chances); the Wooden Box | [monsters.md](monsters.md) |
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
node tools/meowdb/extract_npcs.mjs
node tools/meowdb/extract_quests.mjs      # + missable / tracker_tags from the quest tracker capture
node tools/meowdb/extract_shops.mjs
node tools/meowdb/extract_formulas.mjs
node tools/meowdb/extract_items.mjs       # Green Apple (242) from its item API capture (API-only record)
node tools/meowdb/extract_monsters.mjs    # monsters/, drops/ (through tools/sources/drops_merge.mjs), breakables/
node tools/meowdb/oracle_vectors.mjs      # tests/data/parity_vectors.json (+ local-only oracle extracts)
node tools/meowdb/build_sources_index.mjs # canonical_sources.json (capture files and per-property authorities too)
```

Validate the result against the game's own loader with `bash scripts/validate_data.sh`. The order matters from an
empty tree: `extract_monsters.mjs` resolves drop members against the local items and quests (the crosswalk,
`tools/sources/crosswalk/drop_items.json`), so it runs after `extract_quests.mjs` and `extract_items.mjs`. Run each
extractor twice when you change one: the output must be byte-identical.

**Reproducibility.** `bash scripts/check_canonical.sh` proves the snapshot is regenerable: it copies what the
extractors read (the tools with the cache and the captures, the data, the Iteration One docs, `src/misostory/layout.py`)
into a temporary folder, empties every output folder there, runs the extractors in order with network access off
(`MEOWDB_ALLOW_NETWORK` cleared), then diffs `game/data/canonical` and `game/data/misostory/map_id_crosswalk.json` byte
for byte against the repository (`CANONICAL_CHECK_PASSED`; exit 1 on a difference, 2 when an extractor fails or the
cache is missing; `--keep` keeps the copy). A file no extractor writes any more shows up as "only in the repository".
`docs/canonical/topology_diff.md` is compared too but only reported, because it also reads Blender-side files that
change with each world build; refresh it with `node tools/meowdb/extract_maps.mjs`. `extract_maps.mjs` checks its
parse of `layout.py` against `docs/topology.json` (`LINKS` and `DOOR_LINKS` join exactly its 24 map pairs; every
`ONE_WAY` anchor is an arrival point there), so a layout change does not break the extractor, and the diff says whether
`ONE_WAY` still equals the landing anchors of MeowDB's one-way links. The cache is git-ignored, so the check runs
locally; run it before each milestone. **On the integrated Iteration Three build it exits 2**: its step list still runs
`extract_monsters` before `extract_items`, so the drop merge finds no items folder. With the order above (a copy of the
script with `extract_items` and `extract_quests` moved first) every canonical file reproduces byte for byte
(`docs/DEFERRED.md`).

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
| Item drop chances, meso drop chances, most meso amounts (MeowDB lists drops and votes only) | Not adaptations: KuroDB chances and Hidden Street membership and amounts, by the owner's decisions D3-3 to D3-7, in the schema v2 drop records (contract C1); every shipped record is v2. A value neither source gives stays unresolved and never drops (54 of 75 members; the provenance report lists each). The roller's own readings (a meso amount is a uniform integer in [min, max]; the D3-9 quest-gate rule) are in `game/data/misostory/drop_rates.json`, which holds no number; the Wooden Box's quantity of 1 per roll is a labelled adaptation inside `drops/0000001.json` |
| Drop ground lifetime and ownership time | `game/data/misostory/drops.json` |
| Natural HP regeneration (10 HP per 10 s of eligible time) | The project owner's rule (brief "Natural HP Regeneration", contract C4): authority `Project owner`, `verified: true` against that brief section, in `game/data/misostory/recovery.json` `natural_hp` (Iteration Two's placeholder was `combat.json natural_recovery`). MP has no natural recovery: MeowDB documents none (`natural_mp`, an unresolved source gap) |
| When a chair's bonus clock starts and whether it holds at full HP; the sit key; ground sitting and map benches (none documented) | `game/data/misostory/recovery.json` `chair_bonus`, `sitting` |
| Beginner skills: Recovery's tick, the buff cast time ("Timing unavailable"), a Three Snails cast with no target, its terrain check, effects at death | `game/data/misostory/skills.json` |
| Wooden Box size, which attacks count as hits, the respawn clock, 3D placement (MeowDB's coordinates are 2D) | `game/data/misostory/breakables.json` |
| Monster floors and pacing in 3D, spawn placement (NPC clearance, density, exclusions), the map mob rate (MeowDB pages disagree) | `game/data/misostory/monsters/_shared.json`, `monsters/<id>.json`, `presentation.json` `spawns` and `map_mob_rate` |
| Bare-handed attack (MeowDB leaves Beginner bare-hand damage unmodeled) | `game/data/misostory/combat.json` |
| Player knockback distance, monster knockback distance, post-hit invincibility (the monsters' stagger time is canonical since the live pages publish it: `stagger_ms`) | `game/data/misostory/combat.json` |
| Speech-bubble timing, the dialogue rules MeowDB is silent on, the quest-item sell guard, Roger's apple re-issue, Shanks' departure boundary | `game/data/misostory/npcs/_speech_bubbles.json`, `dialogue/_rules.json`, `quests/_quest_items.json`, `quests/1002.json`, `npcs/15.json` |
| HP/MP after respawning; which player spawn point a respawn uses | `game/data/misostory/death.json` |
| How many Roger's Apples Roger hands out (quest 1002) | `game/data/misostory/quests/1002.json` |
| The start map of a new character (inferred: 000000001) | `game/data/misostory/new_character.json` |
