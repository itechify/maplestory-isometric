# Adding content (for Iteration Three)

Iteration Two built the systems so that the rest of Maple Island (and later Victoria Island) is mostly a
**content-authoring and verification task**. This guide says what to add for each kind of content, where, and how to
prove it works. Two rules hold throughout:

- **Canonical facts come from MeowDB** and live in `game/data/canonical/` with provenance. They are produced by the
  extractors in `tools/meowdb/` and never edited by hand ([`../canonical/README.md`](../canonical/README.md)).
- **Everything MeowDB does not publish is a MisoStory adaptation** in `game/data/misostory/`, with a `reason` and
  `"verified": false`. `bash scripts/validate_data.sh` enforces both rules.

> **MeowDB access.** The extractors fetch uncached pages live (rate-limited) and re-read cached ones; `--refresh`
> re-fetches. MeowDB's reuse policy still asks that a published dataset be cleared with contact@meowdb.com
> ([`../canonical/README.md`](../canonical/README.md)).

## What is already in

| Content | State |
|---|---|
| Maps | All 25 Maple Island maps, with every MeowDB portal, spawn, NPC and return map. |
| Monsters | All 6 Maple Island species, plus the Wooden Box breakable record (data only; breakables are not built). |
| NPCs | All 21 Maple Island NPCs, all reachable and talkable. |
| Quests | All 20 Maple Island quests (1000–1019) are live through the generic engine. 1002, 1006 and 1007 → 1008 are verified by real-game playthroughs; the rest by unit tests (objective kinds, quizzes 1013–1019, random and selection rewards, chains). |
| Shops | Pan, Sid and Lucy, all verified at canonical prices. |
| Items | The 95 items those reference. |

## Add a quest

1. **Canonical record.** If the quest is not in `game/data/canonical/quests/`, add its id to the quest extractor's id
   list, then run `node tools/meowdb/extract_quests.mjs` (with network permission) and
   `node tools/meowdb/build_sources_index.mjs`. Extract every item, NPC and monster it references in the same pass.
2. **Nothing else is required.** `QuestEngine` runs any quest built from the supported objective kinds
   (`monster_kills`, `item_collection`, `item_usage`, `npc_talk`, `map_visit`), rewards (EXP, mesos, items,
   random and selection groups, fame) and prerequisites. `NpcDialogueBuilder` generates the offer, in-progress and
   completion conversation from the canonical dialogue. The start NPC's marker appears automatically.
3. **Gaps in MeowDB** go in `game/data/misostory/quests/<id>.json`. For example, 1002 gives Roger's Apple on accept
   because MeowDB has no accept items. Dialogue overrides go in `game/data/misostory/dialogue/<npc_id>.json`.
4. **Verify:**
   - `bash scripts/validate_data.sh`: an unsupported objective kind is an error, never a silent pass.
   - a unit test like `test_quest_engine.gd`.
   - a playthrough scenario like `test_e_quest.gd`: walk, talk, accept, progress, turn in, and check the exact
     canonical reward.

## Add a monster

1. **Canonical record:** the monster extractor writes `monsters/<id>.json` and `drops/<id>.json`. Spawns need nothing
   extra: map pages list `spawns[]`, and the spawn system places exactly MeowDB's species and counts.
2. **Adaptation:**
   - `game/data/misostory/monsters/<id>.json`: the model (an Iteration One proxy asset in `_library.glb`, or a new kit
     asset), scale, collision capsule and AI timings. Shared defaults are in `_shared.json`.
   - Drop chances: `game/data/misostory/drop_rates.json`. MeowDB publishes no rates; every placeholder is marked
     unverified.
3. **Model:** add the proxy in Blender (`src/misostory/kit/creatures.py`), rebuild, and re-export
   (`bash scripts/build_runtime.sh`).
4. **Verify:**
   - `test_monster_*` for spawn, death, EXP and drops.
   - the `test_b_combat` pattern: fight it with real attacks and check every hit against `CombatFormula`'s range and
     the EXP against canonical data.

## Add an NPC or a shop

1. **NPC:** the canonical NPC record comes from the NPC extractor. It is placed where its map's MeowDB `npcs[]` says.
   Its 3D position comes from the Blender NPC marker: add it in the map module with `m.npc(name, x, y, npc_id=...)`.
   The runtime fails validation if a MeowDB NPC has no marker.
2. **Shop:** a canonical shop (`shops/<slug>.json`) is opened from the NPC's dialogue automatically. Shopkeepers behind
   counters use the `across_counter` talk-zone profile (`presentation.json` `npc.talk_zones`).
3. **Verify:** the `npcs` scenario (every NPC talkable on foot, hard checks) and a `test_g_shop`-style scenario.

## Add a map (Victoria Island and beyond)

1. **Canonical:** the map extractor writes `maps/<9-digit id>.json` (portals, spawns, NPCs, player spawns, return map)
   and the crosswalk row.
2. **Geometry:** a map module `src/misostory/maps/m<id>_<Name>.py` written with the `MapCtx` API
   ([`../AUTHORING.md`](../AUTHORING.md)), placed in `src/misostory/layout.py`. The layout has a link (`LINKS` for a
   walkable trail, `DOOR_LINKS` for a door) for each MeowDB connection.
3. **Link mode:** trails default to walkable gates and doors to warps. A link whose geography does not fit can be set
   to `warp` in `game/data/misostory/portal_adaptations.json`, with a reason (MAP_ARCHITECTURE §4.4). Victoria
   dungeons and towers are expected to be warp links to pocket stages, like the interiors.
4. **Rebuild, validate and export:** `validate.py` (traversal, trail walks, player spawns, spawn regions), then the
   staging export with `sidecar_diff`, then `bash scripts/test.sh` (L0/L1 world checks) and the traversal tools
   (`bash scripts/test.sh traversal`), which walk every route and link with the real player.
5. **Verify:** extend the Test A tour (`test_a_traversal.gd`) to the new maps.

## Add an item

Items come with whatever references them: the extractors pull every item a drop, quest or shop names. An item needs no
code: inventory tab, stack size, equip slot, requirements, stats and consumable effects are all read from its
canonical record by `ItemDef`. Equipment visuals on the player are not built yet.
