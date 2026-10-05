# Adding content (Iteration Three and later)

Iterations Two and Three built the systems so that the rest of MapleStory (Victoria Island next) is mostly a
**content-authoring and verification task**. This guide says what to add for each kind of content, where, and how to
prove it works. Three rules hold throughout:

- **Canonical facts come from their sources** and live in `game/data/canonical/` with provenance. MeowDB MS Classic is
  the authority for everything, except that KuroDB supplies drop and meso-drop probabilities and Hidden Street
  supplies monster drop membership and meso amounts (decisions D3-3 to D3-7 in
  [`../ITERATION_LOG.md`](../ITERATION_LOG.md); contract C7). The extractors in `tools/meowdb/` write these files from
  the local cache and the dated captures; they are never edited by hand ([`../canonical/README.md`](../canonical/README.md)).
- **Everything the sources do not publish is a MisoStory adaptation** in `game/data/misostory/`, with a `reason` and
  `"verified": false`. A value marked `"verified": true` must say what it was checked against in `verified_against`
  (the project owner's natural-regen rule is the one case today). Never invent a canonical value, and never change
  canonical data or a test's expected canonical value to make something pass.
- **`bash scripts/validate_data.sh` enforces both rules** (see "What the validator enforces" at the end).

> **Source access.** The extractors are cache-only (decision D3-1): `tools/meowdb/lib.mjs` touches the network only
> with `MEOWDB_ALLOW_NETWORK=1`, which stays off unless MeowDB grants permission (its terms forbid automated
> collection; ask contact@meowdb.com before publishing the dataset). Newer or missing facts come in as **dated
> captures** of pages read by hand in a normal browser ([HOWTO.md](HOWTO.md) "Capture a source page by hand"). KuroDB
> and Hidden Street have no extractor at all: they sit behind a Cloudflare check, and only their captures are read.

## What is already in

| Content | State |
|---|---|
| Maps | All 25 Maple Island maps, with every MeowDB portal, spawn, NPC and return map. Each has a minimap, and the stuck-region scan finds no trap on any of them. |
| Monsters | All 6 Maple Island species, with canonical stats (the stagger time from the live pages), floor-bound pacing and fair hit areas. |
| Drops | 7 schema v2 drop records (6 monsters and the Wooden Box): 75 members, 21 of which roll with a KuroDB chance; 54 never roll because a source leaves the chance or the item unresolved (each listed by the validator). Meso amounts for 5 monsters (MeowDB for the Snail, Hidden Street for the rest) at KuroDB's 40% chance. |
| Breakables | The Wooden Box (0000001): its 19 placements on six maps, 4 hits to break, per-placement respawn, its drops through the same roller. |
| NPCs | All 21 Maple Island NPCs, all reachable and talkable, with speech bubbles of their canonical idle lines. Shanks ends the island at the departure boundary. |
| Quests | All 20 Maple Island quests (1000-1019), each played in the real game by the every-quest set, strict after its setup. |
| Shops | Pan, Sid and Lucy, at canonical prices. A shop refuses to buy a quest item an in-progress quest still needs. |
| Items | The 96 items the data references. The Green Relaxer (522) works as a chair. |
| Skills | The three Beginner skills (Three Snails, Recovery, Nimble Feet), with SP, the Skills window and quickslots. |

Per-entry status: [`../MAPLE_ISLAND_PARITY.md`](../MAPLE_ISLAND_PARITY.md). Every unresolved source value:
[`../PROVENANCE_REPORT.md`](../PROVENANCE_REPORT.md).

## Canonical data from dated captures

1. **Capture** the page (HOWTO "Capture a source page by hand"): `tools/meowdb/captures/`, `tools/kurodb/captures/`
   or `tools/hiddenstreet/captures/`, with a URL and an ISO read time. `tools/sources/captures.mjs` loads every capture
   and refuses a file it does not know.
2. **Regenerate** with the extractor that reads it:
   - a monster or breakable page, a KuroDB page or a Hidden Street drop list: `node tools/meowdb/extract_monsters.mjs`
     (monsters, breakables, and the drop records through `tools/sources/drops_merge.mjs` and the crosswalk below);
   - the quest tracker: `node tools/meowdb/extract_quests.mjs` (`missable` and `tracker_tags` of every quest; a quest
     with no tracker row fails the run, so a new region needs its own tracker capture);
   - an item API body (`tools/meowdb/captures/items_api.json`): `node tools/meowdb/extract_items.mjs` builds an item
     with no cached page from the API body alone (Green Apple, 242).

   `extract_monsters.mjs` resolves drop members against the local items and quests, so after adding an item, re-run
   it. Run an extractor twice: the output must be byte-identical.
3. **Index and check:** `node tools/meowdb/build_sources_index.mjs` (rebuilds `canonical_sources.json`; the validator
   fails a stale index), `node --test tools/sources/test/`, `bash scripts/validate_data.sh`, and
   `bash scripts/check_canonical.sh` (it re-runs every extractor offline and diffs the result; see HOWTO for its
   current extractor-order defect).
4. **Reports:** `bash scripts/validate_data.sh --report` (the provenance report) and the parity manifest
   (`node tools/parity/build_parity.mjs`, HOWTO "Build the parity manifest").

Every value from a capture cites the capture's path next to the page URL (`field_sources`, `provenance.<property>`,
or a drop entry's `membership_source` / `chance_source`). A value no source gives stays `null` and is listed in the
record's `gaps`; two sources that disagree are recorded in `discrepancies` with the choice and why.

## The drop item crosswalk

KuroDB, MeowDB and Hidden Street use unrelated item ids (Snail Shell is 4000019 on KuroDB and 348 locally), so drops
are joined **by name** through `tools/sources/crosswalk/drop_items.json`, never by id. Each member of a membership
list has a row: its local MeowDB item (`resolved`, `ambiguous` or `not_in_snapshot`, with the match method `exact`,
`normalized`, `alias_with_evidence` or `none`, and the evidence), its KuroDB row (`matched` or `none`), and a reviewer
note. `drops_merge.mjs` refuses a member without a row, a KuroDB claim that is not on the captured page, a resolved
item that is not local, or a row without a reviewer note ([`../../tools/sources/crosswalk/README.md`](../../tools/sources/crosswalk/README.md)).

To change a drop: read the capture again, edit the row (evidence and reviewer note), run
`node tools/meowdb/extract_monsters.mjs` twice, then `node tools/meowdb/build_sources_index.mjs`,
`node --test tools/sources/test/` and `bash scripts/validate_data.sh`. Do not resolve an ambiguous name by guessing:
leave it `ambiguous` and say why. When an item file is added for an id a row lists as a candidate,
`extract_monsters.mjs` stops ("candidate N is now a local item; review the crosswalk row") until the row is reviewed.

## Drop records (schema v2)

`game/data/canonical/drops/<owner id>.json` is one record per owner (contract C1 in
[ITERATION_THREE_CONTRACTS.md](ITERATION_THREE_CONTRACTS.md); fields in [`../canonical/monsters.md`](../canonical/monsters.md)):

- `owner {kind: monster | breakable, id}` and `membership_authority` (Hidden Street for monsters, MeowDB for
  breakables).
- `entries[]`: `key`, `name`, `item_id` (null when unresolved) with `item_resolution`, the `membership_source`, the
  `chance_source` (KuroDB, with its raw value, `format` `percent_base` or `reactor_chance_value`, the exact
  conversion and the normalised probability; null when KuroDB has no row), `chance_state`, `probability`, `quantity`,
  `quest_gate` and notes.
- `excluded_kuro_only[]`: KuroDB rows no membership source lists. KuroDB never adds a member.
- `meso`: amount (MeowDB report, else Hidden Street) and chance (KuroDB), each with its state and source; `null` for
  an owner that never drops mesos.

The roller (`DropRoller.roll(owner, db, rng, ctx)`) rolls an entry only when its chance is resolved, its item is
resolved and its quest gate (if any) is in progress in `ctx`; the meso bag only when amount and chance are both
resolved. An entry is gated only when its item is a quest item that a Maple Island quest objective asks for (decision
D3-9: Old Wooden Board and Rusty Screw, gated to 1012). Nothing outside the records supplies a chance, quantity or
meso amount: `game/data/misostory/drop_rates.json` holds only the meso-amount distribution and the gate rule, and
the validator refuses any number put there. Ground lifetime, ownership and scatter stay in
`game/data/misostory/drops.json`. The one adaptation inside a canonical record is the Wooden Box's quantity of 1 per
roll (`quantity.adaptation`, `verified: false`): KuroDB's reactor rows publish none.

Check a record with the console (`drops <owner id> 1000` prints observed against configured rates, each chance's
source and why a member never rolls) and with `bash scripts/test.sh drop`.

## Adaptations

- Put every MisoStory choice in `game/data/misostory/`, never in canonical data or code: the value, a `reason` and
  `"verified": false`. `"verified": true` needs `verified_against` (a canonical record and field, a URL, a decision
  or a brief section). A project owner's decision also carries `provenance.<property> {"authority": "Project owner",
  "decision": "<id>"}`.
- A file in `misostory/<domain>/` is an entity file named after a canonical id (`npcs/15.json`, `quests/1002.json`).
  A file whose name starts with `_` is a shared table of that folder (`monsters/_shared.json`,
  `quests/_quest_items.json`, `npcs/_speech_bubbles.json`, `dialogue/_rules.json`, `dialogue/_system.json`).
- Presentation constants (colours, sizes, timings of a picture) may live in code as named constants with a comment
  (the UI.md convention); a gameplay value never does.
- Iteration Three's adaptation files: `recovery.json` (the owner's natural-regen rule, the chair clock, the sit key),
  `skills.json` (Recovery's tick, the buff cast lockout, Three Snails' whiff costs and projectile, effects at death),
  `breakables.json` (box size, hit rule, respawn clock, placement rules), `stuck_allowlist.json` (reviewed scan
  results), `presentation.json` `spawns` and `map_mob_rate`, `monsters/_shared.json` floors and pacing,
  `combat.json` `monster_knockback`, `drop_rates.json`, `npcs/15.json` `departure`, `npcs/_speech_bubbles.json`,
  `quests/_quest_items.json`, `dialogue/_rules.json` and the new lines in `dialogue/_system.json`.

## Add or change a quest

1. **Canonical record.** `node tools/meowdb/extract_quests.mjs` writes every quest of its region (`REGION_NAME`,
   "Maple Island", read from the quest index; a new region means a new filter and its own tracker capture), then run
   `build_sources_index.mjs`. It is cache-only: the quest pages must be cached or captured. Extract every item, NPC
   and monster a quest references in the same pass. The tracker capture must list every quest.
2. **Nothing else is required.** `QuestEngine` runs any quest built from the supported objective kinds
   (`monster_kills`, `item_collection`, `item_usage`, `npc_talk`, `map_visit`, and `other` for quizzes), rewards (EXP,
   mesos, items, random and selection groups, fame) and prerequisites, and records what a completion gave
   (`rewards_received`, contract C3). `NpcDialogueBuilder` generates the offer, in-progress and completion
   conversation from the canonical dialogue. Markers, the Quest Log's chain steps and the Missable tag follow.
3. **Gaps in the sources** go in `game/data/misostory/quests/<id>.json`: `accept_items` (1002 gives Roger's Apple on
   accept, because MeowDB lists none), `reissue_lost_accept_items` (Roger hands over a lost apple again). Shared quest
   rules are in `quests/_quest_items.json` (the shop's quest-item sell guard). Dialogue overrides go in
   `game/data/misostory/dialogue/<npc_id>.json`; the code-free dialogue rules (which line is the Yes/No, the default
   talk, the quiz rule, the shop title) are in `dialogue/_rules.json`, and system lines (speaker `system`, never NPC
   speech) in `dialogue/_system.json`. Line specs may be `{npc, field, line}`, `{quest, ...}`, `{system, args,
   args_source, live}` or `{npc, route, quote}`; conditions include `unfinished_quests {region}`; actions include
   `depart {route}` ([QUESTS_AND_DIALOGUE.md](QUESTS_AND_DIALOGUE.md)).
4. **Verify:**
   - `bash scripts/validate_data.sh`: an unsupported objective, a dangling conversation node or a missing NPC is an
     error (`quest_data`, `npc_data`, `dialogue_data`), never a silent pass.
   - unit tests like `test_quest_every_quest.gd` (markers for every quest, every quiz answer).
   - **the every-quest set covers a new quest with no code**: `PlaytestQuestPlan` reads its NPCs and maps, level,
     prerequisites, quest line, objectives and rewards from the canonical record and its item sources from the drop
     records and breakables, and `bash scripts/playtest.sh quest --quest <id>` plays it with real input. A
     `map_visit` objective or an `other` type besides the quiz needs support in `PlaytestQuestPlan` and
     `scenarios/quest.gd` first (the plan lists it under `blocked`), and so does an item only an unresolved drop could
     supply. A new quest line changes `PlaytestQuestPlan.chains`; keep `CHAINS_DEFAULT` in
     `scripts/playtest_quests.sh` equal to it (`test_playtest_quest_plan.gd` fails otherwise).

## Add a monster

1. **Canonical record:** `extract_monsters.mjs` writes `monsters/<id>.json` (with the stagger time when a live capture
   shows it) and `drops/<id>.json`. A drop record needs the monster's Hidden Street drop list and KuroDB page captured
   and a crosswalk row per member. Spawns need nothing extra: map pages list `spawns[]`, and the spawn system places
   exactly MeowDB's species and counts.
2. **Adaptation:** `game/data/misostory/monsters/<id>.json`: the model (an Iteration One proxy in `_library.glb`, or a
   new kit asset), scale, collision capsule, AI timings and walk style. Shared defaults are in `_shared.json`,
   including the floor rule (`floor_band_m`: a walker stays within 0.5 m of its spawn height, widened to its spawn
   region's tier) and pacing (`pace_reverse_chance`, `pace_min_run_m`). A jumper may name `hop_floor_rule`
   (`spawn_floor_one_hop`: one floor above or below its spawn floor).
3. **Model:** add the proxy in Blender (`src/misostory/kit/creatures.py`), standing on z = 0, with a footprint close to
   its canonical touch zone (`test_monster_hit_area.gd` allows 1.25x), then rebuild and re-export
   (`bash scripts/build_runtime.sh`).
4. **Verify:** `test_monster_*` for spawn, death, EXP, drops, floors and hit areas; the `test_b_combat` pattern (fight
   it with real attacks and check every hit against `CombatFormula`'s range and the EXP against canonical data);
   `test_b_population` for its maps; `drops <id> 1000` in the console.

## Spawn regions and exclusions

Monsters spawn at slots the runtime plans on Blender's spawn regions; MeowDB's 2D spawn coordinates are not used
([MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) §4.7.1 "As built").

- **In the map module:** `m.mobs(mob_name, area, count, avoid=...)` (Iteration One's layout, which also places the
  Blender proxies) or `m.spawn_region(name, area, species=(...), z_band=..., tiers=..., exclude=...)`. Every `avoid`
  or `exclude` zone (a polygon or a `(cx, cy, r)` circle) is exported with its region as `exclude_xz`, and no slot is
  placed inside it: use it for plazas, flower beds and anywhere a monster should not stand. A region builds a
  representative proxy of each species it names.
- **The planner** (`SpawnSlotPlanner`) gives each species its tagged regions, keeps `spawns.min_area_per_slot_m2`
  (8 m²) of room per slot and spills the rest to the least crowded region only after every species has its own,
  keeps slots 1.2 m apart, 4 m from every arrival and 2.5 m from every NPC (`slot_npc_clearance_m`), and never
  realizes a respawn within 2 m of the player (`respawn_player_clearance_m`); all in
  `game/data/misostory/presentation.json` `spawns`. Species and counts never change. `maps/<id>.json` may add
  `spawn_keepouts` discs and pin a slot with `spawn_slot_overrides`, each with a reason. MeowDB's map mob rate is not
  applied (`presentation.json map_mob_rate.apply` false, a decision between MeowDB pages that disagree).
- **Verify:** `node tools/sources/check_spawn_captures.mjs` (the canonical spawn rows against the dated captures),
  `bash scripts/test.sh spawn`, `test_world_static.gd` with the world, and `bash scripts/playtest.sh test_b_population`.

## Add a breakable

1. **Canonical:** `breakables/<id>.json` (`hits_to_break`), each map's `reactors[]` (`id`, `respawn_s` per placement;
   the index is the placement) and a schema v2 `drops/<id>.json` whose owner kind is `breakable` (membership from
   MeowDB's live breakable page, chances from KuroDB's reactor rows, read as 1/N by decision D3-7).
2. **Positions:** none are authored in Blender. `BreakablePlacementPlanner` places each placement on walkable ground
   of its map, seeded per map, with the clearances and rules in `game/data/misostory/breakables.json` `placement`
   (away from portals, arrivals, NPC talk spaces, spawn slots and other boxes; standing room around it; in the
   gameplay camera's sight). Interiors with no spawn regions sample the map's floor.
3. **Runtime:** `BreakableSystem` reads hits and drops by each placement's breakable id, but the actor it shows is the
   Wooden Box (`WoodenBox`, size `breakables.json box.touch_px`); a breakable that looks or sizes differently needs its
   own actor and size entry. The hit rule (one landed basic attack, nearest box) and the exact respawn clock are in
   `breakables.json`. Box state is never saved.
4. **Verify:** `test_breakables_placement.gd` checks every placement against the real collision (with the world),
   `bash scripts/playtest.sh test_box` breaks every box in the real game, and the `boxes` console command shows the
   current map's boxes.

## Add a skill

1. **Canonical:** the formulas extractor writes each class's `formulas/<class>.json skills[]` (`skill_id`,
   `max_level`, `cast_position`, `levels[]` with `mp_cost`, `item_cost_id`, `fixed_damage`, `hp_total`, `duration_s`,
   `cooldown_s`, `speed_bonus`). `SkillDef` joins the timing row in `attack_speed.json` and the search band in
   `attack_styles.json` by `skill_id`.
2. **Kinds:** a skill with `fixed_damage` is an attack, one with `hp_total` a heal over time, one with `speed_bonus` a
   buff; another kind needs code in `PlayerSkills` and `EffectBook` first.
3. **Gaps** (a heal's tick, a cast time the page calls "Timing unavailable", what a whiff costs) go in
   `game/data/misostory/skills.json` with a reason and `verified: false`.
4. **Verify:** `bash scripts/test.sh skills` and `bash scripts/playtest.sh test_skills` (SP from hunting, the Skills
   window's "+", a key binding, every cast with real keys, persistence across Quit Game).

## Add a chair

Any Setup item whose canonical record has a `setup` block (`hp_recovery_bonus`, `interval_s`) is a chair
(`ItemDef.is_chair()`): it sits in the Set-up tab, can be bound to a quickslot, sits the player down when used and adds
its bonus on its own clock while seated. Its bonus is read from the record at runtime, never copied into adaptation
data. The validator's `chair` check requires the `setup` block to be valid. MeowDB documents no ground sit and no map
benches on Maple Island, so there is nothing to author for them.

## Add an NPC or a shop

1. **NPC:** the canonical NPC record comes from the NPC extractor. It is placed where its map's MeowDB `npcs[]` says.
   Its 3D position comes from the Blender NPC marker: add it in the map module with `m.npc(name, x, y, npc_id=...)`.
   The runtime fails validation if a MeowDB NPC has no marker. Its speech bubbles come from its canonical
   `idle_chatter`, on the timing in `npcs/_speech_bubbles.json`.
2. **Shop:** a canonical shop (`shops/<slug>.json`) is opened from the NPC's dialogue automatically, and the
   shopkeeper's name tag and minimap dot get the coin icon from it. Shopkeepers behind counters use the
   `across_counter` talk-zone profile (`presentation.json` `npc.talk_zones`).
3. **Transport:** a transport NPC needs a `departure` block (`npcs/<id>.json`) while its destination is outside the
   build; Shanks' block makes his boat the end of Maple Island (no travel, no fare taken).
4. **Verify:** the `npcs` scenario (every NPC talkable on foot, hard checks) and a `test_g_shop`-style scenario.

## Add a map (Victoria Island and beyond)

1. **Canonical:** the map extractor writes `maps/<9-digit id>.json` (portals, spawns, NPCs, reactors, player spawns,
   return map) and the crosswalk row.
2. **Geometry:** a map module `src/misostory/maps/m<id>_<Name>.py` written with the `MapCtx` API
   ([`../AUTHORING.md`](../AUTHORING.md)), placed in `src/misostory/layout.py`. The layout has a link (`LINKS` for a
   walkable trail, `DOOR_LINKS` for a door) for each MeowDB connection.
3. **No traps.** The stuck-region scan of Iteration Three found 42 traps in 13 maps; these rules keep new maps clean:
   - a terrace that does not stand on another terrace reaches the ground (`bottom=-0.5`): floating bottoms left
     hidden caverns up to 7 m high;
   - fill any plinth-level gap walled in by terraces to 0.2 m below the terrace it joins, or give it a way up in the
     map's own style (a rope, a vine, a stepping stone);
   - a terrace on the map edge reaches the edge plus 0.9 m, or leaves no body-wide band inside the containment ring;
   - a raised trail mouth over open ground needs the gap under it closed (the ring leaves every gate gap open from top
     to bottom; 000001006's out00 bridge needed an abutment);
   - run `validate.py` (its `ring_band` check guards the map-corner slots) and the stuck scan (HOWTO "Run the
     stuck-region scan") after every edit. A new trap fails `test_stuck_scan.gd`; real traps are fixed in the source,
     never allowlisted.
4. **Link mode:** trails default to walkable gates and doors to warps. A link whose geography does not fit can be set
   to `warp` in `game/data/misostory/portal_adaptations.json`, with a reason (MAP_ARCHITECTURE §4.4).
5. **Rebuild, validate and export:** `validate.py` (traversal, trail walks, player spawns, spawn regions, ring band),
   then the staging export with `sidecar_diff`, then `bash scripts/test.sh` (L0/L1 world checks, the stuck scan) and
   the traversal tools (`bash scripts/test.sh traversal`).
6. **The minimap needs nothing:** it is drawn from the map chunk's `Ground*` collision, the sidecar (camera,
   climbables) and the canonical record (name, street, portals, NPCs). A hidden portal (MeowDB type 1) stays off it.
7. **Verify:** extend the Test A tour (`test_a_traversal.gd`) to the new maps; `ui_minimap` checks the minimap of
   every map.

## Add an item

Items come with whatever references them: the extractors pull every item a drop, quest or shop names. An item needs no
code: inventory tab, stack size, equip slot, requirements, stats, consumable effects and chair data are all read from
its canonical record by `ItemDef`. Equipment visuals on the player are not built yet.

**Never delete an item record a player could already hold.** A save keeps an unknown item id as an inert "Unknown
item <id>", but `test_save_it2_fixtures.gd` (real Iteration Two saves) fails on any item its fixtures hold that the
data no longer defines. Likewise, a change to the meaning of a saved character field needs a `SaveMigrations` step,
an entry in `IT2_STEPS` and the reshape checks in `test_save_it2_fixtures.gd`; never edit the fixture JSON
([SAVES.md](SAVES.md)).

## Prove it: tests, playtests and parity keys

- A unit test file declares which parity rows it proves in an optional `func parity_keys() -> Dictionary` (test name
  to keys such as `["quest:1005", "drop:2/snail-shell"]`); the runner fails a key that names a missing test or is
  malformed. A playtest check carries keys as its fourth argument. Key forms are listed in contract C6 and
  `tools/parity/rules.json` (also `population:<map>/<mob>`, `spawn-rule:<map>`, `monster-stats:<id>`,
  `meso:<owner>`, `objective:<quest>/<kind>/<target>`, `reward:<quest>/...`, `chain:<first quest>`,
  `placement:<map>/<i>` and the `mechanic:*` rows).
- "Implemented" in the parity manifest is only the runtime declaration in `tools/parity/rules.json`; an entry is
  "verified" only by a passing tagged check and no failing one, and quests, objectives, rewards and chains need a
  real-game check.
- After a data change: rebuild `canonical_sources.json`, run `validate_data.sh --report`, and regenerate the parity
  manifest from fresh test and playtest evidence.

## What the validator enforces

`bash scripts/validate_data.sh` ([DATA_VALIDATION.md](DATA_VALIDATION.md)) fails on:

- a reference that does not resolve (maps, portals and the portal graph, monsters, NPCs, items, quests, shops, skills,
  drop owners and gate quests, chairs, dialogue links), an id defined twice, or a placeholder name;
- provenance: a record without its MeowDB source, a property from an authority that may not supply it (KuroDB:
  probabilities only; Hidden Street: monster membership and meso amounts only; Project owner: a cited decision), a
  missing or non-ISO read time, a cited capture file that does not exist, a stale `canonical_sources.json`;
- a drop record that is not schema v2, a probability outside [0, 1] or one that does not re-derive exactly from its
  raw value (N% against 1/N, a missed /100, truncation), a KuroDB-only member, a gate that breaks the D3-9 rule, an
  unresolved member a quest needs (a progression blocker), or any number in `drop_rates.json`;
- an adaptation value without a reason and verified flag, or `verified: true` without `verified_against`;
- the game's own quest, NPC and dialogue validation (unsupported objectives, unplaceable NPCs, dangling nodes).

It warns, by design, about every drop member or meso value that never rolls because a source leaves it unresolved, so
missing probabilities stay visible (54 on the integrated Iteration Three data).
