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
Shipped data on the integrated Iteration Three build (2026-10-05): 0 errors and 54 warnings, all `drop_unresolved`
(the drop members no source gives a chance or an item for, listed by design), so `--strict` exits 1; 158 out-of-scope
references skipped (listed per rule in every report); 192 canonical records, 37 adaptation files, 47 portals, 25
sidecars, 203 capture paths, 172 per-property sources, 7 schema v2 drop records with 75 entries, 2,194 references and
3,260 names checked; the quest, NPC and dialogue validation ran.

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
   ├─ DropRecordChecks                drop_record (+ provenance): schema v2 drop records (contract C1)
   ├─ DropChecks                      drop_policy, drop_unresolved: the drop policy over the shipped records
   ├─ ReferenceChecks                 reference (+ skill references), dialogue_link, portal (+ portal graph), drop_owner,
   │                                  drop_table, consistency; counts refs.<Phase 16 category>
   ├─ IntegrityChecks                 chair, name (placeholders), duplicate
   ├─ AdaptationChecks                adaptation (convention + per-file schemas), crosswalk (+ Blender sidecars, index.json)
   └─ GameplayDataChecks              quest_data, npc_data, dialogue_data: the game's own QuestCatalog, NpcCatalog and
                                      NpcDialogueBuilder validation (only when everything above found no error)
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
| `provenance` | error | no `source`; `source.authority` ≠ `"MeowDB MS Classic"`; `source.url` not under `https://meowdb.com/msclassic`, `https://meowdb.com/_data/` or `https://meowdb.com/api/` (path-boundary match, so `meowdb.com.evil` or `/msclassicfake` fail); `source.retrieved_at` not an ISO 8601 date-time with a zone, or not a real date and time (month 13, Feb 30, hour 24 fail); a `field_sources` URL (`url`, `fallback_url`, `pages[].url`, `urls[]`) outside `https://meowdb.com/` without a matching `external` entry; a JSON file directly in `game/data/canonical/` other than `canonical_sources.json` (no domain, so no id, provenance or index check would see it). **v2, per property:** a source object (record-level `provenance.<property>`, a v2 drop entry's `membership_source` / `chance_source`, the meso `amount_source` / `chance_source`, an adaptation file's `provenance.<property>`) that breaks the [authority registry](#provenance-authorities): an unregistered authority, an authority that may not supply that property, a URL off the authority's site, a missing or non-ISO `read_at`, a missing `capture` or `decision`. **Captures:** any `capture` key (any depth, canonical or adaptation) that is not a repo path under `tools/<site>/captures/` or names a file that does not exist |
| `drop_record` | error | a schema v2 drop record (contract C1) that breaks the [v2 rules](#drop-records-schema-v2); a `schema_version` other than 2 or absent on a drop record |
| `drop_policy` | error (one warning) | `DropChecks` (`scripts/core/validation/drop_checks.gd`) holds the shipped records to the drop policy: `data/misostory/drop_rates.json` supplies no chance, quantity or meso number and names the meso distribution the roller implements (`DropRates.validate`); every drop record is schema v2; membership comes from Hidden Street for monsters and MeowDB for breakables; every resolved chance comes from KuroDB and every meso amount from MeowDB or Hidden Street; `normalized_probability`, `probability`, the conversion text, the quantity (`Qty`), KuroDB's quest flag and the meso range equal an exact re-reading of the raw value (`DropChance`); a reactor row's quantity is a labelled adaptation with `verified: false`; a resolved item exists locally; quest gates follow the C1 rule (D3-9) and say `verified: false`; no `excluded_kuro_only` row is an entry's chance source; an unresolved member whose item, or one of its MeowDB candidates, a Maple Island quest objective asks for is a progression blocker. A resolved chance of 0 is a warning (it never drops) |
| `drop_unresolved` | warning | each drop member or meso value that never rolls because a source leaves its chance or its item unresolved, so missing probabilities stay visible (54 on the shipped data); an unresolved member whose MeowDB candidate has become a local item asks for a crosswalk review |
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
| `quest_data` | error | `QuestCatalog.validate()`: an unknown objective kind, an unsupported `other` objective (the quest could never complete), an unsupported prerequisite kind, a missing prerequisite or follow-up quest, a quiz without its question, an empty random/selection group or a non-positive weight, an adaptation file without its reason or verified flag |
| `npc_data` | error | `NpcCatalog.validate()`: an NPC whose map, quests or shop do not exist, that has nothing to say, or that its map does not list (the game could not place it); a quest whose start / end NPC does not list it |
| `dialogue_data` | error | `NpcDialogueBuilder.validate_all()`: every NPC's generated conversation with its override file applied: unknown node types, dangling node targets, line specs that resolve to no text, malformed conditions and actions, an override file for an unknown NPC |
| `validator` | error | a script error inside the validator (the report is incomplete; the tool exits 2) |

The `quest_data`, `npc_data` and `dialogue_data` checks are the game's own data validation (the classes the quest
engine, the NPC presenter and the dialogue window use), run headless. They read the data the way the game does, which
assumes structurally valid data, so `GameplayDataChecks` runs them only when every check above found no error; the
stat `gameplay_checks_run` (or `gameplay_checks_skipped`) says which happened. A parse error in one of those classes
also makes the validator exit 2.

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
`chance_source`, `amount_source`, which hold KuroDB and Hidden Street ids), items' `sources` and `used_in` (every
place in the whole game an item comes from or goes to, mostly Victoria Island), and maps' `portals[].to_map_id` (the
portal check reports it). A v2 drop entry's `item_id` and `quest_gate.quest_id` are swept (a null `item_id`, an
unresolved member, is skipped like any unset reference).

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
[ITERATION_THREE_CONTRACTS.md](ITERATION_THREE_CONTRACTS.md); decisions D3-1 to D3-9 in
[ITERATION_LOG.md](../ITERATION_LOG.md)). One registry holds the rules:
`ProvenanceAuthorities.REGISTRY` in `scripts/core/validation/provenance_authorities.gd`.

| Authority | URLs | May supply | Must carry |
|---|---|---|---|
| `MeowDB MS Classic` | `https://meowdb.com/msclassic`, `/_data/`, `/api/` (path boundary) | any property | `url`, `read_at` (or its cache stamp `retrieved_at`); `capture` optional |
| `KuroDB` | `https://playkuro.com/database/#...` | `probability`, `mesos.probability` | `url`, `read_at`, `capture` |
| `Hidden Street` | `https://bc.hidden-street.net/...` | `membership`, `mesos.amount` (monster owners only, `owner_kinds`) | `url`, `read_at`, `capture` |
| `Project owner` | none needed | any property | `decision`: a decision id such as `D3-5`, or the Iteration Three brief (`ITERATION_THREE_BRIEF`) |

A **source object** is `{authority, url | urls, read_at, capture, decision?, raw_value?, ...}`: `urls` (a non-empty
list) replaces `url` when one value was read from several pages of a site (the Wooden Box chances come from four
KuroDB item pages). `capture` is the repo-relative path of the dated capture the value was read from
(`tools/kurodb/captures/100100.json`); every `capture` key anywhere in a record must name an existing file under
`tools/<site>/captures/`. A `decision` given to any authority must be a valid reference. Where source objects appear:

- `provenance.<property>` at the top of any canonical record or adaptation file (a record without the block keeps the
  v1 rules exactly: `source` is MeowDB and covers everything);
- in a schema v2 drop record, `entries[].membership_source` (property `membership`), `entries[].chance_source`
  (`probability`), `meso.amount_source` (`mesos.amount`) and `meso.chance_source` (`mesos.probability`)
  (`ProvenanceAuthorities.SOURCE_PROPERTIES`).

To let an authority supply another property, add the name to its `properties`; to add an authority, add a row. The
record's own `source` stays a MeowDB page (v1 rule), and `field_sources` URLs off meowdb.com still need an
`external` entry: the registry does not loosen v1. `canonical_sources.json` lists each record's `capture_files` and
`property_sources` (authorities and URLs per property).

### Drop records (schema v2)

`DropRecordChecks` (`scripts/core/validation/drop_record_checks.gd`) validates drop records with
`"schema_version": 2` (contract C1); records without it are v1 and checked as before. Rules (check `drop_record`
unless noted):

- **Entries.** `key` (unique) and `name` are non-empty strings. `item_resolution.state` is `resolved`, `ambiguous`,
  `not_in_snapshot` or `not_in_classic`, and `method` is `exact`, `normalized`, `alias_with_evidence` or `none`;
  `item_id` is a string exactly when the state is `resolved` (with a method other than `none`), else null. No two
  entries resolve to the same item. A resolved `item_id` must exist and a `quest_gate` is `null` or
  `{quest_id, basis}` whose quest exists (both through the reference sweep, check `reference`).
- **Membership.** `membership_source` is a source object for `membership` (check `provenance`) whose authority is the
  record's `membership_authority` (registered and allowed to supply membership), and whose `raw_value` names the
  entry. An entry may not also be an `excluded_kuro_only` row (`{kuro_item_id, name, raw_value, reason}`): KuroDB
  never adds a member (D3-6).
- **Chance.** `chance_state` is `resolved` or `unresolved`. Resolved: `probability` is a number in [0, 1];
  `chance_source` is present (a source object for `probability`); its `normalized_probability` equals `probability`
  and re-derives from `raw_value` by `format` within 1e-12: `percent_base` (`"<p>% base | ..."`, p / 100; an item
  row, not a `Meso drop` row) or `reactor_chance_value` (`"Chance value N"`, 1 / N, with a non-empty
  `interpretation`, D3-7). This catches a 1/N read as N% (or the reverse), a missed or doubled /100, and integer
  truncation. `quantity` is `{min, max}`, whole numbers, 1 ≤ min ≤ max. Unresolved: `probability` is null (the entry
  never rolls); a `chance_source` or `quantity` that is given is still checked.
- **Meso** (`null` = the owner never drops mesos). `amount_state` resolved: whole `min`/`max` with 1 ≤ min ≤ max and an
  `amount_source` for `mesos.amount` whose `"Mesos: a[-b]"` raw value (when it has that form) gives the same numbers;
  unresolved: `min`/`max` null. `chance_state` as for entries, with a `chance_source` for `mesos.probability` whose
  raw value is a `Meso drop` row.

`quantity.source` (`"KuroDB 'Qty 1'"` in C1) is free text, not a source object, so the registry does not apply to it;
a `provenance.quantity` naming KuroDB would be rejected (KuroDB supplies probabilities only). Every shipped drop record
is schema v2 (written by `tools/meowdb/extract_monsters.mjs` through `tools/sources/drops_merge.mjs`), and the runtime
reads only v2 records: an entry rolls only with a resolved chance and item and, if gated, its quest in progress
([ITEMS.md](ITEMS.md)). The fixture `tests/data/drops_v2/fixture_2.json` is a valid v2 Snail record built from the
captures.

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
| `drop_rates.json` | Iteration Two's placeholder structure (`item_overrides`, `owner_item_overrides`, `mesos.by_owner`, `type_rates`): keys resolve and chances lie in [0, 1]. The shipped file has none of these keys any more (it holds only `meso_amount_distribution` and `quest_gate_rule`), so this check finds nothing; the rule that the file supplies no number is `drop_policy` (`DropChecks` / `DropRates.validate`) |
| `new_character.json` | `start_location.spawn_index` is one of the start map's player spawns (its `map_id` also seeds the portal-graph reachability check) |
| `inventory.json` | every canonical weapon's subtype has a `weapon_subtypes` entry |
| `combat.json` | `fixed_damage_skills` keys are canonical skill ids (`formulas/*.json skills[].skill_id`) |
| `portal_adaptations.json` | link ids `T_<map>_<portal>__<map>[_<portal>]`, `"<map>.<portal>"` refs, `destination_portal_id`, spawn indexes and arrival gates name real portals and spawns; each `one_way_allowlist` link exists and really has no way back (warning when stale); the portal-graph check requires the converse (every one-way link is listed) |
| `dialogue/*` | named `<npc id>.json` (or `_<name>.json` for shared lines, the shared-table prefix) with a matching `npc_id`; `{npc, field, line}` line specs index an existing NPC line (0-based, as `DialogueText` reads them); `{quest, ...}` specs name a canonical quest |
| `npcs/*` | `disabled_behaviors` entries are NpcDef behaviours (`quest`, `shop`, `transport`, `talk`; a typo would be ignored at runtime and leave the behaviour on); disabling one the NPC does not have is a warning (stale) |

## Current warnings on the shipped data

54 `drop_unresolved` warnings, one per drop member that never rolls (the Wooden Box's Egg; 53 members of the six
monsters' lists): 24 have a local item but no KuroDB chance, and 30 have no unambiguous local item (ambiguous names,
items missing from the local snapshot). They are the brief's "missing probability stays visible" rule, not defects;
each is in the record's `gaps` and in [`../PROVENANCE_REPORT.md`](../PROVENANCE_REPORT.md), and
[`../DEFERRED.md`](../DEFERRED.md) names the open cases. `--strict` therefore exits 1 on the shipped data. Runs
without the Blender export (plain `ISOLATE=` test runs) add one `crosswalk/world_assets` warning.

The last data warning was `misostory/new_character` `starting_sp`, `verified: true` with nothing saying against what.
Its reason quotes `formulas/beginner.json sp.calculator_caveat` ("a Beginner has 0 SP at level 1"), so it now carries
that as `verified_against`. `portal_adaptations.json one_way_allowlist` named its check in a `verification` key, now
`verified_against`.

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
  `external`); then each per-property source: `provenance.<property>` (contract C7) and, in schema v2 drop records,
  each entry's `membership_source` / `chance_source` and the meso `amount_source` / `chance_source`. Each row has the
  authority, URLs, `read_at` (or the cache's `retrieved_at`), capture, decision and raw value. The record also carries
  its validation findings, which the parity generator reads.
- **unresolved**, by domain: every record's `gaps` (a value the source does not give: null or absent, never guessed),
  and in drop records every member without a chance (unresolved, never drops; a v1 record would also list its
  placeholder rates, and none ships), every unresolved item and every unresolved meso value. On the integrated
  Iteration Three data: 523 unresolved values, and 117 adaptation objects, 3 of them verified.
- **adaptations**: every object in `game/data/misostory` that carries a verified flag, with `verified_against` and its
  reason (its own, its `<key>_reason`s or reasons map, or the nearest enclosing one).
- **counts**: records per domain, property rows per authority, capture files, unresolved values per domain,
  adaptations verified and not.

It records no clock time, so regenerating it over unchanged data gives the same files; regenerate it whenever the
data changes (the parity manifest reads it).

## Sources and adaptations

The validator holds no gameplay values, so it neither uses nor adds canonical numbers or adaptations. Its rules come
from the schema docs in `docs/canonical/*.md` (maps.md "Destination portals", monsters.md "Drop table file", npcs.md,
quests.md, shops.md), `tools/meowdb/build_sources_index.mjs` (the index it re-derives), MAP_ARCHITECTURE.md §4.2,
§4.10 and §4.13 (crosswalk, sidecars, the L0 graph checks) and `scripts/core/npcs/npc_def.gd` (the NPC behaviour
names), and from the Iteration Three source decisions (`docs/ITERATION_LOG.md` D3-1 to D3-9, contracts C1 and C7).
Its policy constants (the authority registry, the allowed URL prefixes, the derivation names, the v2 drop vocabularies)
are provenance rules, not game data.

## Tests

```bash
ISOLATE=<name> bash scripts/test.sh data_                   # the 9 files below (160 tests)
ISOLATE=<name> INCLUDE_WORLD=1 bash scripts/test.sh data_   # same, with the real export for the shipped-data test
ISOLATE=<name> bash scripts/validate_data.sh                # the tool itself
```

| File | Covers |
|---|---|
| `tests/unit/test_data_validation.gd` | the shipped data has no errors and did not crash the validator (each error is printed); every record, portal and adaptation file was checked; finding shape; quest dialogue links the NPC files correct are neither warned nor skipped, and the validator's link remap equals `DialogueText._remap_for` for every quest; `ScriptErrorGuard` (records only script errors, attach/detach); the tool's exit code starts at 2 and its command-line parsing |
| `tests/unit/test_data_validation_references.gd` | injected broken references in every domain, portals (destination, to_portal, reverse lookup, unknown/stale/ambiguous derivations, arrival spawns, duplicate names), the portal graph (unreachable map, unlisted one-way link), drop tables, starter weapons, recovery examples; dialogue links (a canonical link outside the dataset is skipped, an adaptation one warns, a malformed one warns, a quest link is checked as its NPC correction, a correction's null or numeric ids are read as `DialogueText` reads them); out-of-scope rules |
| `tests/unit/test_data_validation_provenance.gd` | the quest tracker tags (`missable`, `tracker_tags`) cite their capture; ids, duplicates, source blocks, URL prefixes and look-alikes, real ISO dates, external entries, the sources index (missing, stale, deleted, external contents, capture files and property sources), loose root files, required fields, loader errors; provenance v2: per-property KuroDB / Hidden Street / MeowDB sources accepted, each misuse rejected (KuroDB as membership, Hidden Street as a probability, a missing or non-ISO `read_at`, a missing `capture`, a capture file that does not exist or a path outside `tools/*/captures/`, an unknown authority, a URL off the authority's site, a Project owner citation without a decision, in canonical and adaptation files), v1 rules unchanged, the capture lookup live on the shipped data (item 242), the registry rules |
| `tests/unit/test_data_validation_drops_v2.gd` | schema v2 drop records: the C1 fixture `tests/data/drops_v2/fixture_2.json` passes with no new finding; corrupted copies fail (probability 1.5 or negative, a KuroDB-only item added as a member with a KuroDB or a copied Hidden Street source, a resolved entry without `chance_source`, an unknown item or gate quest, 1/N read as N% and the reverse, truncation, a reactor value without an interpretation, mismatched or unordered quantities and meso amounts, a meso chance that is an item row, Hidden Street on a breakable, an unknown `schema_version`, duplicate keys and items); `DropRates` survives a v2 table |
| `tests/unit/test_data_validation_adaptation.gd` | every accepted reason spelling, convention failures, `verified: true` only with `verified_against` (the older keys and empty values rejected; the owner natural-regen shape accepted), adaptation references (plain and `{"value": ...}`-wrapped), domain folders and their shared tables, the crosswalk, injected sidecars and an on-disk export (sidecars, index.json, unlisted chunks), each per-file schema |
| `tests/unit/test_data_validation_integrity.gd` | every Phase 16 category counts references on the shipped data; skill references resolve and a skill defined twice is an error; chairs are Setup items with valid setup data (and the shipped ones are); a setup block on another item type; placeholder names (patterns and injected cases) and none in the shipped data; duplicate list entries, while repeated reactor placements and shared names are not duplicates; breakable and monster drop categories; out-of-scope skips listed per rule without `--verbose` |
| `tests/unit/test_data_validation_gameplay.gd` | the quest / NPC / dialogue validation runs on the shipped data and finds nothing; an unsupported objective, a dangling dialogue target and an NPC its map does not list are reported; it waits for structurally valid data; message prefixes name the record |
| `tests/unit/test_data_validation_report.gd` | the provenance report: one entry per record with its own source first and every field and per-property source; v2 drop sources (Hidden Street membership, KuroDB chances, meso) and unresolved members; every gap listed; adaptations with flag, reason and `verified_against`; deterministic output; findings attached to their record |
| `tests/unit/test_data_fixture.gd` | `DataValidationTestCase`: deep-copies the shipped ContentDB, injects sidecars, compares against the unbroken copy so each negative test asserts only the finding it caused, and fails a test whose validator run crashed |

Each file declares in `parity_keys()` (contract C6) which Phase 16 rows (`xref:<category>`, `xref:no-duplicate-ids`,
`xref:no-placeholder-names`, `xref:no-silent-missing-refs`) and canonical-verification rows (`canon:*`) its tests
prove; the parity manifest ([`../MAPLE_ISLAND_PARITY.md`](../MAPLE_ISLAND_PARITY.md)) reads them from the test
evidence. Most `canon:*` tests check the validator rule on fixtures, so the rows that describe the drop data
(`provenance-per-property`, `membership-chance-separate`, `probability-conversion`, `kuro-only-excluded`,
`unresolved-visible`) also need the shipped data in that state (`tools/parity/rules.json` `requires`: every drop record
schema v2). Since the drops package's records landed they are verified by the tests alone; before, the manifest kept
them `partial`. The drop policy's own tests are `test_drop_sources.gd`, `test_drop_chance.gd`, `test_drops_data.gd`,
`test_drops_roller.gd` and `test_drop_simulation.gd` ([ITEMS.md](ITEMS.md)).

The negative tests pick their victims from the data (the first quest with a kill objective, ...) and inject only
made-up ids, so they hold when the content grows. Script-error handling in the tool was verified by hand in an
`ISOLATE` mirror (a test cannot raise a real script error without printing `SCRIPT ERROR`): an injected runtime error
in `ReferenceChecks.run()` now exits 2 (it used to print `VALIDATION_PASSED` and exit 0 with the portal checks
skipped), and a parse error in `validation_report.gd` exits 2 in under a second (it used to hang forever).
