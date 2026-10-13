# Canonical data validation (brief Phase 22)

MisoStory's content is JSON: MeowDB MS Classic facts in `game/data/canonical/` and MisoStory adaptation data in
`game/data/misostory/`. The validator loads both through the game's own loader (`ContentDB`) and checks that every
reference resolves, every record has provenance, the provenance index is current and every adapted value is
explained. **Broken data references are treated like compile errors:** the tool exits non-zero and the unit test
over the shipped data fails.

```bash
bash scripts/validate_data.sh                      # report + exit code (below)
bash scripts/validate_data.sh --verbose            # also list every reference skipped as out of scope
bash scripts/validate_data.sh --strict             # warnings fail too
bash scripts/validate_data.sh --json report.json   # also write the report as JSON
bash scripts/validate_data.sh --report             # also write the provenance validation report (below):
                                                   # docs/provenance_report.json + docs/PROVENANCE_REPORT.md
bash scripts/validate_data.sh --world-dir <res://...>   # Blender export to check crosswalk slugs against
ISOLATE=<name> bash scripts/validate_data.sh       # private copy under _scratch/godot_runs/<name>/ (as scripts/test.sh)
VALIDATE_TIMEOUT_S=300 bash scripts/validate_data.sh    # outer time limit (default 180 s)
GODOT=/path/to/godot bash scripts/validate_data.sh      # binary override, passed through to scripts/godot.sh
```

| Exit | Meaning |
|---|---|
| 0 | no errors (warnings allowed unless `--strict`) |
| 1 | data errors, or warnings with `--strict` |
| 2 | the validator itself is broken: a script does not compile, a check raised a script error (the report would be incomplete), Godot did not exit in time, or a bad command line (an unknown flag, or a value flag with no value) |

An isolated run copies the small `game/assets/world/*.json` sidecars (and `index.json`) but not the glTF chunks, and
mirrors `tools/*/captures/` next to the copy (as `scripts/test.sh` does), because the validator checks that every
cited capture file exists at `res://../tools/...`. The last line is `VALIDATION_PASSED` or `VALIDATION_FAILED`.
Shipped data on the final Iteration Three build (2026-10-06, commit `1f3120c`): 0 errors and 0 warnings (every one
of the 86 drop members resolves to its item, its Henesys.gg rarity and its table category), so `--strict` passes too;
158 out-of-scope references skipped (listed per rule in every report); 192 canonical records, 40 adaptation files, 47
portals, 25 sidecars, 268 capture paths, 233 per-property sources, 7 schema 3 drop records with 86 entries, 2,151
references and 3,127 names checked; the quest, NPC and dialogue validation ran.

Every report lists the out-of-scope skips grouped by rule (`SKIPPED (out of scope) 125 x monsters.spawns[].map_id ->
maps (maple_island: false)`); `--verbose` adds one line per skipped reference. The summary's stats include one
`refs.<category>` counter per Phase 16 category (below), so a category that silently stops resolving shows as 0.

## Data flow

```
ContentDB.new().load_all()            the loader the game uses (load_errors included)
   │
DataValidator.validate(db, options)   scripts/core/validation/data_validator.gd (pure: no scene tree)
   ├─ ScriptErrorGuard                attached for the whole run; a script error becomes a "validator" error finding
   ├─ ProvenanceChecks                ids, schema, provenance (v1 source + per-property sources + captures), external,
   │                                  sources_index; the rules per authority come from ProvenanceAuthorities.REGISTRY
   ├─ DropRecordChecks                drop_record (+ provenance): schema 3 drop records (contract C1)
   ├─ DropChecks                      drop_policy, drop_unresolved: the drop policy over the shipped records
   ├─ ReferenceChecks                 reference (+ skill references), dialogue_link, portal (+ portal graph), drop_owner,
   │                                  drop_table, consistency; counts refs.<Phase 16 category>
   ├─ IntegrityChecks                 chair, name (placeholders), duplicate
   ├─ AdaptationChecks                adaptation (convention + per-file schemas), crosswalk (+ Blender sidecars, index.json)
   ├─ ArtPackChecks                   art_pack: every required ID has a model in the installed art pack ("no pack" otherwise)
   └─ GameplayDataChecks              quest_data, npc_data, dialogue_data: the game's own QuestCatalog, NpcCatalog and
                                      NpcDialogueBuilder validation (over the records everything above found no error in)
   │
ValidationReport                      findings + out_of_scope (+ per rule) + stats
   ├─ tools/validate_data.gd(.tscn)   prints the report, sets the exit code   ← scripts/validate_data.sh
   │    └─ ProvenanceReport           --report: docs/provenance_report.json + docs/PROVENANCE_REPORT.md
   └─ tests/unit/test_data_validation*.gd
```

`options`: `world_dir` (default `res://assets/world`) and `world_sidecars` (slug → sidecar Dictionary, used by tests
instead of the disk); `repo_root` (the folder holding `tools/*/captures/`, default the folder above `res://`) and
`capture_files` (capture path → true, used by tests instead of the disk).

Every finding is `{severity, domain, id, message, check}`: `severity` is `error` or `warning`; `domain` is a
canonical domain (`maps`, `quests`, ...), `misostory` / `misostory/<folder>` for adaptation files, `crosswalk`,
`canonical_sources`, `canonical` (a loose root file), `load` or `validator`; `id` is the record id (or file
basename); `check` is the rule slug below. Report lines read `VALIDATION ERROR [check] domain/id: message`.

### Why a crashed validator cannot pass

In Godot 4.7 a GDScript runtime error aborts only the current function, which returns its default value, and the
caller carries on. Inside the validator that would silently skip the rest of one check and print
`VALIDATION_PASSED` over a partial report. Three layers prevent it:

1. `DataValidator.validate()` attaches a `ScriptErrorGuard` (an `OS.add_logger` Logger that records
   `ERROR_TYPE_SCRIPT` errors) and turns each recorded error into an error finding with check `validator`. Every
   consumer (tool, tests, a future debug command) therefore gets a failing report. `DataValidator.new(...).run()` is
   the unguarded form.
2. `tools/validate_data.gd` keeps its exit code in a member that starts at 2 and is lowered only when `run()` reaches
   its end, runs loading and formatting under its own guard, and exits 2 on any script error or `validator`
   finding. It loads `ContentDB`, `DataValidator` and the guard with `load()` rather than by class name: a parse
   error in any of them would otherwise stop the tool script itself from compiling, and Godot would then idle forever
   with a script-less node. Now that case prints `... does not compile` and exits 2 within a second.
3. `scripts/validate_data.sh` runs Godot under `timeout` (default 180 s; exit 124/137 become exit 2) as the last
   resort, and the in-scene watchdog (120 s) covers an endless loop.

The test fixture fails any negative test whose validator run produced a `validator` finding, so a check that crashes
on broken input cannot make a negative test pass for the wrong reason.

## Checks

| check | severity | What fails |
|---|---|---|
| `load` | error | `ContentDB.load_errors` (unparsable JSON; a domain file whose top level is not an object); no canonical data at all |
| `ids` | error | a record without a string `id`; `id` ≠ file basename; the same `id` in two files of one domain |
| `schema` | error | a field consumers rely on is missing or mistyped (`REQUIRED_FIELDS` in `provenance_checks.gd`: e.g. maps need `portals`, `player_spawns`, `return_map_id`; monsters `level`, `hp`, `exp`) |
| `provenance` | error | no `source`; `source.authority` ≠ `"MeowDB MS Classic"`; `source.url` not under `https://meowdb.com/msclassic`, `https://meowdb.com/_data/` or `https://meowdb.com/api/` (path-boundary match, so `meowdb.com.evil` or `/msclassicfake` fail); `source.retrieved_at` not an ISO 8601 date-time with a zone, or not a real date and time (month 13, Feb 30, hour 24 fail); a `field_sources` URL (`url`, `fallback_url`, `pages[].url`, `fallback_pages[].url`, `urls[]`) outside `https://meowdb.com/` without a matching `external` entry; a URL template (a placeholder such as `{item_id}` or `<id>` in `source.url`, a `field_sources` URL or a per-property source's `url`/`urls`: cite each real page, as the shop records' `pages` do); a JSON file directly in `game/data/canonical/` other than `canonical_sources.json` (no domain, so no id, provenance or index check would see it). **Per property:** a source object (record-level `provenance.<property>`, a schema 3 drop entry's `membership_source` / `rarity.source`, the meso `amount_source`, an adaptation file's `provenance.<property>`) that breaks the [authority registry](#provenance-authorities): an unregistered authority, an authority that may not supply that property, a URL off the authority's site, a missing or non-ISO `read_at`, a missing `capture` or `decision`. **Captures:** any `capture` key (any depth, canonical or adaptation) that is not a repo path under `tools/<site>/captures/` or names a file that does not exist |
| `drop_record` | error | a schema 3 drop record (contract C1) that breaks the [schema 3 rules](#drop-records-schema-3); a `schema_version` other than 3 or absent on a drop record |
| `drop_policy` | error | `DropChecks` (`scripts/core/validation/drop_checks.gd`) holds the shipped records to the drop policy (decisions D3-9, D3-11, D3-12): `data/misostory/drop_rates.json` is the complete chance table (every category x rarity a chance in [0, 1], decision D3-11, `verified: false`, quantity 1) and `meso_rules.json` a valid meso rule (D3-12) (`DropRates.validate`); every drop record is schema 3 with MeowDB MS Classic as its membership authority; each record cites its owner's own page capture (`monster_<id>.*` or `breakable_<id>.txt` and its URL), the newest dated capture of that page; the membership equals MeowDB's community list "Drops (MS Classic)" on that capture exactly (names, order, each raw block and its votes), and no MSEA-only item is a member; every rarity is the Henesys.gg capture's label and row, and a member the capture has no row for has rarity null; a resolved item exists locally, its `category_inputs` are the item's MeowDB type and subtype, and its `chance_category` follows the rule; quest gates follow the D3-9 rule; a reported meso amount is MeowDB's, its raw value verbatim in its capture, and a player report the owner's page shows is in the record unless a newer source in `sources_compared` decides; an unresolved member whose item a Maple Island quest objective asks for is a progression blocker when [no other source](#progression-blockers) gives the item |
| `drop_unresolved` | warning | each drop member that never rolls because its item, its Henesys.gg rarity or its table category is unresolved, so missing values stay visible (none on the shipped data) |
| `external` | error | an `external` entry (canonical or adaptation) without `field`, an http(s) `source_url`, a `reason`, or `verified: false` |
| `sources_index` | error | `canonical_sources.json` missing; a record not listed; a listed record that no longer exists; a row whose `name`, `file`, `authority`, `url`, `retrieved_at`, `field_source_urls`, `external` entries (`field`, `source_url`, `verified`, in order), `gap_count`, `discrepancy_count`, `capture_files` or `property_sources` (`{property: {authorities, urls}}`; both written only when non-empty) differs from what `tools/meowdb/build_sources_index.mjs` would write now; `totals` off (`records`, `distinct_source_urls` (property source URLs included), `external_values`, `capture_files`); a nested canonical folder (the builder does not index them). Fix: rerun the builder |
| `reference` | error | an id that does not resolve (rules below), or an id that is not a string |
| `portal` | error | `to_map_id` missing or unknown; `to_portal` names no portal of the destination; `to_portal_derivation` other than `reverse_lookup`/`none` (absent = an explicit `to_portal`); a `reverse_lookup` `to_portal` that does not lead back, or whose destination has more than one portal back (maps.md requires the unique one); `none` with a `to_portal`, or `none` while the destination does have a portal back (stale: rerun `extract_maps.mjs`); a null `to_portal` whose destination has no `player_spawns`; two portals with one name on a map. **Portal graph** (MAP_ARCHITECTURE §4.13 L0): a map not reachable through portals from `new_character.json` `start_location.map_id`; a one-way link (no portal back) missing from `portal_adaptations.json` `one_way_allowlist` (each half skipped when its adaptation file is absent) |
| `drop_owner` | error | a drop table without `owner {kind: monster/breakable, id}`, an unknown owner, or `owner.id` ≠ table id |
| `drop_table` | error | a monster's or breakable's `drop_table` not of the form `drops/<id>.json`, or naming a missing table |
| `dialogue_link` | warning | a dialogue link (`ref: {kind\|type, id}`) with an unknown kind or no string id (anywhere); a link in an **adaptation** file to a record not in the dataset (the game still shows the text and the reference, with no record behind it). A canonical link outside the dataset is skipped as out of scope instead (see [Dialogue links](#dialogue-links)) |
| `consistency` | warning | one-sided facts: a map places an NPC whose `locations` omit it (or the reverse); a shop's NPC does not name the shop; a quest NPC stands on none of the quest's maps; a map's `monsters[]` and `spawns[]` disagree; a drop table owned by another record |
| `chair` | error / warning | a chair reference (formulas `chairs[].item_id`, `formulas/recovery.json`) that is not a usable chair (contract C5): not type `Setup`, no `setup` block, `setup.hp_recovery_bonus` not a number ≥ 0 or `setup.interval_s` not > 0; an item with a `setup` block whose type is not `Setup`; a formulas chair whose `additional_hp_per_tick` / `tick_interval_s` disagree with the item's `setup` (warning) |
| `name` | error | a placeholder name: any `name` or `*_name` string (canonical or adaptation, outside the provenance and commentary subtrees) that is empty, `?`, contains "placeholder", the words TODO / TBD / FIXME, starts with "Unknown", or reads "Item 1234". Two records may share a real name (Red Cloth Pants, 1168 male and 1177 female) |
| `duplicate` | error | an id defined twice: a `skill_id` in two formulas `skills[]` entries; the same id twice in a list whose entries are distinct things (a map's `npcs[].id` and `monsters[].id`, a shop's `items[].item_id`, a v1 drop table's `entries[].item_id`, a quest's objective lists (an NPC talk per `npc_id` + `purpose`) and `rewards.items[].item_id`). Map `reactors[]` are placements and may repeat; v2 drop tables are checked by `drop_record` |
| `adaptation` | error / warning | the reason/verified convention and the per-file schemas below; `verified: true` without `verified_against` is an error |
| `crosswalk` | error / warning | the crosswalk is not bijective onto the canonical maps; a Blender slug has no sidecar, a sidecar without a numeric `map_id` or with the wrong one, or (when the export has `index.json`) no chunk; a map chunk in `index.json` that no row names (warning); no export at all (one warning) |
| `art_pack` | error | with the art pack installed (`game/assets/art_pack`, `bash scripts/art_pack.sh fetch`): a required ID with no imported model, one finding per ID (`npc:21`, `kit:Sign_Board`). Required: every canonical NPC, monster, item and breakable, and the kit names the island places (`misostory/kit_assets_placed.json`, written by `scripts/kit_usage.py`). Without the pack nothing fails; `stats.art_pack` (printed as `ART PACK coverage:`) is `covered`, `missing` or `no pack` |
| `quest_data` | error | `QuestCatalog.validate()`: an unknown objective kind, an unsupported `other` objective (the quest could never complete), an unsupported prerequisite kind, a missing prerequisite or follow-up quest, a quiz without its question, an empty random/selection group or a non-positive weight, an adaptation file without its reason or verified flag |
| `npc_data` | error | `NpcCatalog.validate()`: an NPC whose map, quests or shop do not exist, that has nothing to say, or that its map does not list (the game could not place it); a quest whose start / end NPC does not list it |
| `dialogue_data` | error | `NpcDialogueBuilder.validate_all()`: every NPC's generated conversation with its override file applied: unknown node types, dangling node targets, line specs that resolve to no text, malformed conditions and actions, an override file for an unknown NPC |
| `validator` | error | a script error inside the validator (the report is incomplete; the tool exits 2) |

The `quest_data`, `npc_data` and `dialogue_data` checks are the game's own data validation (the classes the quest
engine, the NPC presenter and the dialogue window use), run headless. They read the data the way the game does, which
assumes structurally valid data, so `GameplayDataChecks` hands them only the records that every check above found no
error in. Each record with an error finding (canonical, `misostory/<folder>/<id>` or a `misostory` table), and each
file that failed to load, is left out of a copy of the content; the three validations run on that copy, and every
other record's findings are reported, so one structural error no longer hides the quest, NPC and dialogue findings
of the rest. A finding is withheld when it falls on a left-out record (it would be read over broken data) or names one
by its whole id (quest `1005`, also inside a dialogue node id such as `q1005.offer.1`): leaving the record out makes
other records report it missing ("prerequisite quest 1005 does not exist", "quest 1005 not in canonical quests"), and
the run already fails on its own error. Errors with no record behind them (the sources index, the crosswalk) leave
nothing out. The stat `gameplay_checks_run` counts the run, and `gameplay_records_left_out` (only when some were) the
records left out; on clean data the summary is unchanged. A parse error in one of those classes also makes the
validator exit 2.

### Progression blockers

A drop member that never rolls (its item, Henesys.gg rarity or table category unresolved) is a `drop_unresolved`
warning. When a Maple Island quest objective (`objectives.item_collection`) asks for its item, it is also a
`drop_policy` error, a progression blocker, unless another source gives the item (`DropChecks.other_sources`):

- another drop record, a monster's or a Wooden Box's, whose member with that item rolls (item, rarity and category
  resolved and a chance above 0, as `DropRates.effective_entries` reads it);
- a shop that stocks it (`items[].item_id`);
- a quest that hands it out: `rewards.items`, `rewards.random[].items`, `rewards.selection[].items`,
  `items_given_on_accept`, `next_quest_grants[].items`, or the adaptation's `accept_items`. The completion rewards of a
  quest that asks for the item do not count, since they come only after its objective.

No member is unresolved on the shipped data, so no blocker is reported either way.

### Phase 16 cross-references

The brief's "Content Cross-Reference Validation" matrix and where each row is checked (`ReferenceChecks.PHASE16_CATEGORIES`;
each resolved reference is counted as `refs.<category>`, and `test_every_phase16_category_counts_references` fails if
one is 0 on the shipped data):

| Category | Rule |
|---|---|
| `quest-reward-item`, `quest-objective-item`, `quest-monster`, `quest-npc` | typed keys in quest records (`rewards.*` vs objectives, accept items, hand-ins, prerequisites) |
| `monster-drop`, `breakable-drop` | `item_id` in drop tables, by the table owner's kind |
| `shop-item` | `item_id` in shop stock |
| `map-monster`, `map-npc` | explicit rules on maps `monsters[].id`, `spawns[].mob_id`, `npcs[].id` |
| `portal-destination` | `_check_portals` (destination map and portal) and the portal graph |
| `skill-reference` | `skill_id` / `skill_ids` anywhere, against the skill definitions in formulas `skills[]` |
| `chair-item` | `IntegrityChecks` chair rule |

Duplicate ids and placeholder names are the `duplicate` and `name` checks; "no silent missing references" is the
per-category counters plus the out-of-scope skips listed per rule in every report.

### Reference rules

**Typed keys** resolve at any depth in canonical and adaptation records (`ReferenceChecks.TYPED_KEYS`). A value is a
string id, an array of string ids, null (no reference), or an object whose `value` is one of those (the adaptation
files' `{"value": ..., "reason": ..., "verified": ...}` style):

| Keys | Domain |
|---|---|
| `item_id`, `item_ids`, `item_cost_id`, `required_ammunition_item_id`, `weapon_id` | items |
| `mob_id(s)`, `monster_id(s)` | monsters |
| `npc_id(s)`, `start_npc_id`, `complete_npc_id`, `end_npc_id` | npcs |
| `map_id(s)`, `to_map_id`, `from_map_id`, `return_map_id`, `sold_at_map_id`, `start_map_id`, `respawn_map_id` | maps |
| `quest_id(s)` | quests |
| `shop_id(s)` | shops |
| `breakable_id(s)` | breakables |
| `skill_id(s)` | skills: the pseudo-domain of every formulas record's `skills[].skill_id` (Three Snails, Recovery, Nimble Feet in `formulas/beginner.json`); the definitions themselves (`formulas` `skills[].skill_id`) are not swept |

This covers drops, quest objectives (kills, item collection and usage, NPC talk), rewards (items, random, selection),
accept items, prerequisites, follow-ups and quest lines, shop stock, NPC shop blocks and locations, the Beginner
starter weapons (`formulas/beginner.json starter_weapons`, `attack_speed`/`attack_styles` `beginner_weapons`), the
Three Snails item costs, the recovery examples (`formulas/recovery.json consumables.beginners_guide_examples`,
`chairs`) and the example maps of `death` and `spawn_rate`, with no per-field code.

**Explicit rules** (`EXPLICIT_RULES`) cover ambiguous `id` keys and win over the sweep at their path: `maps`
`npcs[].id` → npcs, `monsters[].id` and `meowdb_spawn_estimates.per_mob[].id` → monsters, `reactors[].id` →
breakables, `quests.starts_here[].id` / `quests.progress_here[].id` → quests; `npcs` `quests.given/turned_in[].id`
and `quests.started_here/completed_here[]` → quests; `formulas` `map_page_display.example_map.monsters[].id`.

**Not swept:** commentary and provenance (`source`, `field_sources`, `cross_checks`, `discrepancies`, `notes`,
`gaps`, `change_history`, `external`, and the per-property source objects `provenance`, `membership_source`,
`rarity`, `amount_source`, `sources_compared`), items' `sources` and `used_in` (every place in the whole game an item
comes from or goes to, mostly Victoria Island), and maps' `portals[].to_map_id` (the portal check reports it). A
schema 3 drop entry's `item_id` and `quest_gate.quest_id` are swept (a null `item_id`, an unresolved member, is
skipped like any unset reference).

**Out of scope, skipped (not findings; every report lists the count per rule, `--verbose` each reference):**

| Rule | Why | Shipped count |
|---|---|---|
| `maps.quests.progress_here[]`, `monsters.quests[]` whose `area_label`/`region` is not a region of the shipped quests (`quests/*.region` ∪ the labels of quests starting on a shipped map) | Henesys, Kerning City and Victoria Island quests (10009, 10123, 10303) whose kill targets also live on Maple Island | 30 |
| `monsters.spawns[]` with `maple_island: false` | a monster's spawn maps off the island | 125 |
| `npcs.transport.routes[].to_map_id` | Shanks' boat to Lith Harbor (010000000) | 1 |
| a dialogue link in a **canonical** record to an id outside the dataset, after the quest correction below (one line per record and target) | MeowDB links content off the island: "Grendel the Really Old" (npc 313, a Victoria Island NPC) in Todd's quest 1005 text, in `npcs/7` and `quests/1005` | 2 |

A quest that **starts** on a shipped map must exist whatever its label (its NPC stands there).

#### Dialogue links

A dialogue link is a `ref` object (`{kind|type, id}`) on a dialogue segment, found at any depth (canonical NPC and
quest dialogue; an adaptation file may carry one too). `ReferenceChecks.LINK_KINDS` maps `npc`, `map`, `item`,
`monster`, `quest` and `shop` to their domains. A dangling link never fails validation, because it cannot break
play: the game follows no link. `DialogueText` only marks the resolved ref `known: false`, and the dialogue window
(`DialogueRichText`) still emphasises the reference by its kind (item, monster, npc, map or quest) whatever its id.
In the real game, Todd's quest 1005 offer shows
"Grendel the Really Old" (npc 313, not in the dataset) in NPC green, like "Peter" (review, 2026-10-04).

- **Canonical records:** the link is MeowDB's raw href (docs/canonical/npcs.md "File format" and "Referenced ids";
  quests.md §4 and the "Dialogue only" ids of §11), and MeowDB covers the whole game, so a link to an id outside the
  dataset names content off the island. It is skipped as out of scope (table above), not a finding; the line names
  the first path it was seen at.
- **Adaptation files:** the link was written by hand, so an id outside the dataset is a mistake: `dialogue_link`
  warning.
- **Malformed links** (a kind not in `LINK_KINDS`, or no string id): `dialogue_link` warning, canonical or not.
- **Quest dialogue is checked as the game links it.** The quests domain keeps MeowDB's raw link ids, while the NPC
  domain stores a corrected link as `ref.id` with the raw one in `ref.meowdb_link_id` (docs/canonical/npcs.md
  "Discrepancies"). `DialogueText._remap_for` rewrites a quest's dialogue links with the corrections found in every
  NPC's `quest_dialogue` block for that quest, so `ReferenceChecks._link_remap` applies the same corrections to
  `quests/<id>.json` `dialogue` before the lookup (`QUEST_DIALOGUE_ROOT`). Quest 1005 links "Jr. Sentinel Shellpiece"
  as item 2584 (a different item with the same name); Todd's and Peter's blocks correct it to 347, which the game
  links, so the validator resolves 347 and reports nothing. In the real game, Todd's accepted line resolves
  "Jr. Sentinel Shellpieces" to `{kind: item, id: "347", known: true}` (review, 2026-10-04). A correction to an id
  outside the dataset is skipped like any canonical link, naming both ids. The two functions must stay in step: a
  change to the runtime's remap rule needs the same change in `_link_remap`. `test_link_remap_matches_the_game_remap`
  compares them for every shipped quest, and `test_npc_corrected_quest_links_are_not_reported` fails if the shipped
  corrections are reported (both also fail if the shipped data has no correction left, so they cannot pass
  vacuously). The validator mirrors the rule instead of calling `_remap_for` because the runtime caches the result
  per `ContentDB` instance in a static, which would go stale across runs over one mutated copy (the test fixture).

### Provenance authorities

Iteration Three lets a record take different properties from different authorities (contract C7 in
[ITERATION_THREE_CONTRACTS.md](ITERATION_THREE_CONTRACTS.md); decisions D3-1, D3-11 and D3-12 in
[ITERATION_LOG.md](../ITERATION_LOG.md)). One registry holds the rules:
`ProvenanceAuthorities.REGISTRY` in `scripts/core/validation/provenance_authorities.gd`.

| Authority | URLs | May supply | Must carry |
|---|---|---|---|
| `MeowDB MS Classic` | `https://meowdb.com/msclassic`, `/_data/`, `/api/` (path boundary) | any property | `url`, `read_at` (or its cache stamp `retrieved_at`); `capture` optional |
| `Henesys.gg` | `https://henesys.gg/` | `rarity` only (the label of a drop member) | `url`, `read_at`, `capture` |
| `Project owner` | none needed | any property | `decision`: a decision id such as `D3-11`, or the Iteration Three brief (`ITERATION_THREE_BRIEF`) |

A **source object** is `{authority, url | urls, read_at, capture, decision?, raw_value?, ...}`: `urls` (a non-empty
list) replaces `url` when one value was read from several pages of a site. `capture` is the repo-relative path of the
dated capture the value was read from (`tools/henesys/captures/item_rarity.json`); every `capture` key anywhere in a
record must name an existing file under `tools/<site>/captures/`. A `decision` given to any authority must be a valid
reference. Where source objects appear:

- `provenance.<property>` at the top of any canonical record or adaptation file (a record without the block keeps the
  v1 rules exactly: `source` is MeowDB and covers everything);
- in a schema 3 drop record, `entries[].membership_source` (property `membership`), `entries[].rarity.source`
  (`rarity`) and `meso.amount_source` (`mesos.amount`) (`ProvenanceAuthorities.SOURCE_PROPERTIES`). A drop chance or
  a meso chance has no source object: it is the project owner's rule file, never canonical data.

To let an authority supply another property, add the name to its `properties`; to add an authority, add a row. The
record's own `source` stays a MeowDB page (v1 rule), and `field_sources` URLs off meowdb.com still need an
`external` entry: the registry does not loosen v1. `canonical_sources.json` lists each record's `capture_files` and
`property_sources` (authorities and URLs per property).

### Drop records (schema 3)

`DropRecordChecks` (`scripts/core/validation/drop_record_checks.gd`) validates the drop records (contract C1, schema
3); a record with another or no `schema_version` is an error. Rules (check `drop_record` unless noted):

- **Record.** `owner` is `{kind: monster | breakable, id: the record id, name}`; `membership_authority` is a registered
  authority allowed to supply `membership` (check `provenance`); `membership_list` is `"Drops (MS Classic)"`. No key
  anywhere outside the commentary names a chance or quantity (`probability`, `chance`, `chance_source`,
  `chance_state`, `normalized_probability`, `quantity`, `rate`, `drop_chance`): the records hold sourced facts only.
- **Entries.** `key` (unique, the slug of the name) and `name` are non-empty strings. `item_resolution` is `{state:
  resolved | ambiguous | not_in_snapshot, method: exact_name | meowdb_drop_entry | none, candidates, evidence}`;
  `item_id` is a string exactly when the state is `resolved`; `exact_name` lists only the item, `meowdb_drop_entry`
  two or more local items including the one chosen. No two entries resolve to the same item. A resolved `item_id`
  must exist and a `quest_gate` is `null` or `{quest_id, basis, decision: "D3-9", verified: false}` whose quest
  exists (through the reference sweep, check `reference`).
- **Membership.** `membership_source` is a source object for `membership` (check `provenance`) with the record's
  membership authority and list, a `raw_value` block `"<name>\n<subtype>\n▲\n<up>\n▼\n<down>"` that names the entry,
  and `votes {up, down, score = up - down}` that match it.
- **Rarity.** `null` (unresolved: the entry never drops) or `{label: Common | Rare | Very Rare | Extremely Rare,
  source}`, the source a source object for `rarity` (check `provenance`) whose `row` ends with the label.
- **Category.** `category_inputs {item_type, item_subtype, quest_gated, item}`; `chance_category` is null or one of
  the table's categories.
- **Meso.** A monster record's `meso` is `{amount_state: reported | not_reported, min, max, amount_source, gaps}`:
  reported needs whole numbers 1 ≤ min ≤ max and an `amount_source` for `mesos.amount` whose `"Mesos: a[-b] per
  kill"` raw value gives them; not_reported needs `min`, `max` and `amount_source` null. A breakable's `meso` is
  `null`.

`DropChecks` (check `drop_policy`, above) then holds the records to the captures, the item data and the owner's two
rule files. Every shipped drop record is schema 3 (written by `tools/meowdb/extract_monsters.mjs` through
`tools/sources/drops_merge.mjs`), and the runtime reads only schema 3: an entry rolls only with a resolved item,
rarity and category and, if gated, its quest in progress, at the table cell's chance ([ITEMS.md](ITEMS.md)). The
fixture `tests/data/breakables/drops_0000001.json` is a valid Wooden Box record.

### The adaptation convention (game/data/misostory)

Every adapted value carries a **reason** and a **verified** flag. A value is any leaf (number, bool, string, null)
under a non-metadata key. It has a reason when:

1. its object has a sibling `<key>_reason`, or `<prefix>_reason` where the key starts with `<prefix>_`
   (`drops.json ground_lifetime_reason`; `world_scale.json horizontal_reason` explains `horizontal_px_to_m`), or
2. its object has a `reasons` map with a non-empty string under its key (`camera.json`, `movement.json`), or
3. its object or **any enclosing object** has a non-empty string `reason` (`combat.json` sections, `quests/1002.json`).

It has a verified flag when its object has `<key>_verified` (or `<prefix>_verified`), or its object or any enclosing
object has `verified`. Both must be bools; `reason`, `*_reason` and `reasons` values must be non-empty strings. A key
that is covered covers everything nested under it, and arrays are transparent, so one top-level `reason` +
`verified` covers a whole file and per-entry reasons refine it.

**`verified: true` is accepted only with `verified_against`** on the same object (for a `<key>_verified: true`
sibling flag, `<key>_verified_against` or `verified_against`): a non-empty string or a non-empty list of them naming
what the value was checked against (a canonical record and field, a URL, or a decision or brief section). Anything
else is an error: a value nobody can say was checked is `verified: false` with its reason. The older free-form keys
(`verification`, `verified_by`, `source_url`) remain descriptive metadata and no longer count. The project owner's
natural-regen rule is the model case (contract C4; the mechanics package writes it as
`game/data/misostory/recovery.json`):

```json
{"natural_recovery": {"hp": {"amount": 10, "interval_s": 10.0, "eligible_activities": ["still", "seated"]},
  "reason": "The project owner's rule ...", "verified": true,
  "verified_against": "docs/ITERATION_THREE_BRIEF.md: Resolve Iteration Two Placeholder: Natural HP Regeneration"},
 "provenance": {"natural_recovery": {"authority": "Project owner", "decision": "ITERATION_THREE_BRIEF: Natural HP Regeneration"}}}
```

Rule 3 is deliberately lenient at the file level: in the shipped data only per-record files (`dialogue/*`,
`npcs/15`, `quests/1002`) and `drop_rates.json`'s structural key `canonical` rely on the file's top-level `reason`;
every tuning value in the table files has its own.

Metadata keys need no reason: `id`, `kind`, `description`, `title`, `name`, `label`, `note(s)`, `comment(s)`,
`reason(s)`, `verified`, `verification`, `verified_by`, `verified_against`, `source(s)`, `source_url(s)`,
`retrieved_at`, `schema`, `schema_version`, `version`, `see`, `doc(s)`, `external`, `gaps`, `discrepancies`,
`match_basis`, `provenance`, any key ending in `_reason`, `_note(s)`, `_verified`, `_verified_against`, `_source`,
`_source_url`, `_description`, `_comment`, `_doc`, `_label`, and any key starting with `_`.

Also, for every adaptation file: typed keys resolve (as above); `external` lists follow the canonical rule; a
top-level `provenance` block follows the [authority registry](#provenance-authorities) (the project owner's
natural-regen rule cites `{"authority": "Project owner", "decision": "..."}`) and every `capture` key names an
existing capture; a file in
`misostory/<domain>/` where `<domain>` is a canonical domain is an **entity file**: it must be named after a canonical
id of that domain, and its `id` / `<singular>_id` (e.g. `quest_id`) must equal the basename.

**Shared tables.** In such a folder, a file whose basename starts with `_` (`AdaptationChecks.SHARED_TABLE_PREFIX`) is
a shared adaptation table, not an entity file: it holds values the folder's entity files share.
`misostory/monsters/_shared.json` is the shipped one; `MonsterDef` reads it first and lays the species file
`monsters/<id>.json` over it. A shared table's basename is not matched against canonical ids and its `id` (if any)
need not equal the basename (no canonical id starts with `_`, so the prefix cannot hide an entity file). Everything
else still applies: the reason/verified convention, the typed-reference sweep, the `external` rule and the folder's
`FILE_SCHEMAS` entry. The same prefix marks `dialogue/_<name>.json` shared-line files (`dialogue/_system.json`), which
the `dialogue/*` check exempts from its `<npc id>.json` naming rule (`AdaptationChecks.is_shared_table`).

### Per-file schemas

`AdaptationChecks.FILE_SCHEMAS` maps a file pattern (`<basename>`, `<folder>/<basename>`, `<folder>/*`; exact wins)
to `{convention, sweep, check, required}`. New files need no entry; add one only for rules the generic checks cannot
see (ids used as map keys, index ranges, vocabularies), as a method of `AdaptationChecks`.

| File | Checks |
|---|---|
| `map_id_crosswalk.json` (required; convention and sweep off) | rows `{meowdb_id\|map_id, iteration_one_slug\|blender_slug, gms_v8_id, match_basis}`; one row per canonical map (count = canonical map count), no duplicate MeowDB id, slug or GMS id; each row has a `match_basis`. Each slug has `game/assets/world/<slug>.json` with a numeric `map_id` equal to `gms_v8_id`, and a chunk in the export's `index.json`; every map chunk in `index.json` has a row (warning); no export at all is a single warning |
| `world_scale.json` | `horizontal_px_to_m`, `vertical_px_to_m`, `actor_px_to_m` are positive numbers (WorldScale reads them) |
| `drop_rates.json`, `meso_rules.json` | required (an error when missing). Their content, the complete chance table (decision D3-11) and the meso rule (D3-12), is checked by `drop_policy` (`DropChecks` / `DropRates.validate`) |
| `new_character.json` | `start_location.spawn_index` is one of the start map's player spawns (its `map_id` also seeds the portal-graph reachability check) |
| `inventory.json` | every canonical weapon's subtype has a `weapon_subtypes` entry; every `shop.protected_items` entry names a canonical item (an id that does not exist is an error here and in the typed-key sweep) |
| `combat.json` | `fixed_damage_skills` keys are canonical skill ids (`formulas/*.json skills[].skill_id`) |
| `portal_adaptations.json` | link ids `T_<map>_<portal>__<map>[_<portal>]`, `"<map>.<portal>"` refs, `destination_portal_id`, spawn indexes and arrival gates name real portals and spawns; each `one_way_allowlist` link exists and really has no way back (warning when stale); the portal-graph check requires the converse (every one-way link is listed) |
| `dialogue/*` | named `<npc id>.json` (or `_<name>.json` for shared lines, the shared-table prefix) with a matching `npc_id`; `{npc, field, line}` line specs index an existing NPC line (0-based, as `DialogueText` reads them); `{quest, ...}` specs name a canonical quest |
| `npcs/*` | `disabled_behaviors` entries are NpcDef behaviours (`quest`, `shop`, `transport`, `talk`; a typo would be ignored at runtime and leave the behaviour on); disabling one the NPC does not have is a warning (stale) |

## Current warnings on the shipped data

None. All 86 drop members of the schema 3 records resolve (item, Henesys.gg rarity and table category), so there is no
`drop_unresolved` warning, and `--strict` exits 0 on the shipped data with the Blender export present. Runs without
the export (plain `ISOLATE=` test runs) add one `crosswalk/world_assets` warning. A member that ever stops resolving
(a new MeowDB list entry with no Henesys.gg row, say) shows up as a `drop_unresolved` warning, listed in the record's
`gaps` and in [`../PROVENANCE_REPORT.md`](../PROVENANCE_REPORT.md), and never rolls.

The last data warning was `misostory/new_character` `starting_sp`, `verified: true` with nothing saying against what.
No MeowDB page states a starting SP number: the Beginner's guide says only "You earn 9 SP by the time you hit level 10
(1 per level-up, 9 level-ups from 1 to 10)", so 0 at level 1 is arithmetic, not a published value. The entry is now
`verified: false` with that reason (an adaptation, never a restated canonical value). `portal_adaptations.json
one_way_allowlist` named its check in a `verification` key, now `verified_against`.

Earlier runs also warned about three dialogue links. Two of them, "Grendel the Really Old" (npc 313) in `npcs/7` and
`quests/1005`, are MeowDB links to an off-island NPC and are now skipped as out of scope. The third, "Jr. Sentinel
Shellpiece" as item 2584 in `quests/1005`, was a validator false positive: the game links the NPC files' corrected id
347, and the validator now checks that one ([Dialogue links](#dialogue-links)).

## The provenance validation report

`bash scripts/validate_data.sh --report` (or `--report-json <path>` / `--report-md <path>`) also writes the brief's
Phase 17 report through `ProvenanceReport` (`scripts/core/validation/provenance_report.gd`) to
[`docs/provenance_report.json`](../provenance_report.json) and [`docs/PROVENANCE_REPORT.md`](../PROVENANCE_REPORT.md):

- **records**: every canonical record with its property rows. Row `(record)` is the record's own `source` (it covers
  every value no other row names); then each `field_sources.<field>` (MeowDB, or `external` when its URL is declared in
  `external`); then each per-property source: `provenance.<property>` (contract C7) and, in schema 3 drop records,
  each entry's `membership_source` / `rarity.source` and the meso `amount_source`. Each row has the
  authority, URLs, `read_at` (or the cache's `retrieved_at`), capture, decision and raw value. The record also carries
  its validation findings, which the parity generator reads.
- **unresolved**, by domain: every record's `gaps` (a value the source does not give: null or absent, never guessed),
  and in drop records every member whose item, rarity or table category did not resolve (it never drops) and each
  meso block's gaps (no MeowDB report or chance: the owner's meso rule supplies them). The current counts are in the
  report's summary.
- **adaptations**: every object in `game/data/misostory` that carries a verified flag, with `verified_against` and its
  reason (its own, its `<key>_reason`s or reasons map, or the nearest enclosing one).
- **counts**: records per domain, property rows per authority, capture files, unresolved values per domain,
  adaptations verified and not.

It records no clock time, so regenerating it over unchanged data gives the same files; regenerate it whenever the
data changes. The parity manifest reads it when someone rebuilds the manifest, but the committed manifest is the record
of v0.3 at its evidence commit and is not kept current (HOWTO "Build the parity manifest").

## Sources and adaptations

The validator holds no gameplay values, so it neither uses nor adds canonical numbers or adaptations. Its rules come
from the schema docs in `docs/canonical/*.md` (maps.md "Destination portals", monsters.md "Drop table file", npcs.md,
quests.md, shops.md), `tools/meowdb/build_sources_index.mjs` (the index it re-derives), MAP_ARCHITECTURE.md §4.2,
§4.10 and §4.13 (crosswalk, sidecars, the L0 graph checks) and `scripts/core/npcs/npc_def.gd` (the NPC behaviour
names), and from the Iteration Three source decisions (`docs/ITERATION_LOG.md` D3-1, D3-9, D3-11 and D3-12, contracts C1 and C7).
Its policy constants (the authority registry, the allowed URL prefixes, the derivation names, the schema 3 drop vocabularies)
are provenance rules, not game data.

## Tests

```bash
ISOLATE=<name> bash scripts/test.sh data_                   # the files below (148 tests)
ISOLATE=<name> INCLUDE_WORLD=1 bash scripts/test.sh data_   # same, with the real export for the shipped-data test
ISOLATE=<name> bash scripts/validate_data.sh                # the tool itself
```

| File | Covers |
|---|---|
| `tests/unit/test_data_validation.gd` | the shipped data has no errors and did not crash the validator (each error is printed); every record, portal and adaptation file was checked; finding shape; quest dialogue links the NPC files correct are neither warned nor skipped, and the validator's link remap equals `DialogueText._remap_for` for every quest; `ScriptErrorGuard` (records only script errors, attach/detach); the tool's exit code starts at 2 and its command-line parsing |
| `tests/unit/test_data_validation_references.gd` | injected broken references in every domain, portals (destination, to_portal, reverse lookup, unknown/stale/ambiguous derivations, arrival spawns, duplicate names), the portal graph (unreachable map, unlisted one-way link), drop tables, starter weapons, recovery examples; dialogue links (a canonical link outside the dataset is skipped, an adaptation one warns, a malformed one warns, a quest link is checked as its NPC correction, a correction's null or numeric ids are read as `DialogueText` reads them); out-of-scope rules |
| `tests/unit/test_data_validation_provenance.gd` | the quest tracker tags (`missable`, `tracker_tags`) cite their capture; ids, duplicates, source blocks, URL prefixes and look-alikes, real ISO dates, external entries, the sources index (missing, stale, deleted, external contents, capture files and property sources), loose root files, required fields, loader errors; per-property provenance: MeowDB, Henesys.gg and Project owner sources accepted, each misuse rejected (Henesys.gg as membership, a chance or a meso amount, a missing or non-ISO `read_at`, a missing `capture`, a capture file that does not exist or a path outside `tools/*/captures/`, an unknown authority, a URL off the authority's site, a Project owner citation without a decision, in canonical and adaptation files), v1 rules unchanged, the capture lookup live on the shipped data (a drop record's page capture), the registry rules |
| `tests/unit/test_data_validation_drops.gd` | schema 3 drop records: the shipped records pass with no finding; corrupted copies fail (a probability in a canonical record, Henesys.gg supplying anything but rarity, membership from another authority, an MSEA reference item as a member, a wrong rarity label or row, votes that do not match the raw block, a malformed meso block, an unknown `schema_version`, duplicate keys and items, a quest gate without its rule); an unresolved member is valid and listed |
| `tests/unit/test_data_validation_adaptation.gd` | every accepted reason spelling, convention failures, `verified: true` only with `verified_against` (the older keys and empty values rejected; the owner natural-regen shape accepted), adaptation references (plain and `{"value": ...}`-wrapped), domain folders and their shared tables, the crosswalk, injected sidecars and an on-disk export (sidecars, index.json, unlisted chunks), each per-file schema |
| `tests/unit/test_data_validation_integrity.gd` | every Phase 16 category counts references on the shipped data; skill references resolve and a skill defined twice is an error; chairs are Setup items with valid setup data (and the shipped ones are); a setup block on another item type; placeholder names (patterns and injected cases) and none in the shipped data; duplicate list entries, while repeated reactor placements and shared names are not duplicates; breakable and monster drop categories; out-of-scope skips listed per rule without `--verbose` |
| `tests/unit/test_data_validation_gameplay.gd` | the quest / NPC / dialogue validation runs on the shipped data and finds nothing; an unsupported objective, a dangling dialogue target and an NPC its map does not list are reported; a broken record's own findings are withheld, while a structural error in one quest (a mistyped field, or a file that no longer parses) leaves another quest's finding reported, and nothing else; message prefixes name the record; a left-out record is named by its whole id |
| `tests/unit/test_data_validation_report.gd` | the provenance report: one entry per record with its own source first and every field and per-property source; schema 3 drop sources (MeowDB membership, Henesys.gg rarity, the meso report) and unresolved members; every gap listed; adaptations with flag, reason and `verified_against`; deterministic output; findings attached to their record |
| `tests/unit/test_data_fixture.gd` | `DataValidationTestCase`: deep-copies the shipped ContentDB, injects sidecars, compares against the unbroken copy so each negative test asserts only the finding it caused, and fails a test whose validator run crashed |

Each file declares in `parity_keys()` (contract C6) which Phase 16 rows (`xref:<category>`, `xref:no-duplicate-ids`,
`xref:no-placeholder-names`, `xref:no-silent-missing-refs`) and canonical-verification rows (`canon:*`) its tests prove;
the parity manifest ([`../MAPLE_ISLAND_PARITY.md`](../MAPLE_ISLAND_PARITY.md); the record of v0.3, not kept current
and not a gate) reads them from the test evidence when it is rebuilt. Most
`canon:*` tests check the validator rule on fixtures, so the rows that describe the drop data
(`provenance-per-property`, `membership-rarity-separate`, `no-probability-in-canonical`) also need the shipped data
in that state (`tools/parity/rules.json` `requires`: every drop record schema 3). The manifest (format 3) also
separates two kinds of open value it finds in the records and rules: a `source_data_gap` (the sources were read and
give nothing: a `drop_unresolved` member with no Henesys.gg rarity, an item no local record has; excused) and a
`pending_source_read` (the value is published on a page nobody has read yet, declared in `tools/parity/rules.json`
`pending_source_reads`; never excused; none is declared). The validator itself treats both the same way (an
unresolved value stays visible in `gaps` or as `drop_unresolved`); the label is the manifest's. A drop row's chance is
neither: it is the owner's table, an adaptation the row names. The drop policy's own tests are `test_drop_sources.gd`,
`test_drops_data.gd`, `test_drops_roller.gd` and `test_drop_simulation.gd` ([ITEMS.md](ITEMS.md)).

The negative tests pick their victims from the data (the first quest with a kill objective, ...) and inject only
made-up ids, so they hold when the content grows. Script-error handling in the tool was verified by hand in an
`ISOLATE` mirror (a test cannot raise a real script error without printing `SCRIPT ERROR`): an injected runtime error
in `ReferenceChecks.run()` now exits 2 (it used to print `VALIDATION_PASSED` and exit 0 with the portal checks
skipped), and a parse error in `validation_report.gd` exits 2 in under a second (it used to hang forever).
