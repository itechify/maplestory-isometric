# Canonical data: maps (MeowDB MS Classic)

The 25 Maple Island maps as MeowDB MS Classic documents them (MapleStory Classic World, MeowDB's own ids).
One file per map: `game/data/canonical/maps/<id>.json`. Iteration One crosswalk:
`game/data/misostory/map_id_crosswalk.json`. Differences from Iteration One: [`topology_diff.md`](topology_diff.md).

Regenerate everything (cache-first, deterministic, no network needed while the cache exists):

```sh
node tools/meowdb/extract_maps.mjs
```

The script writes the 25 map files, the crosswalk and `docs/canonical/topology_diff.md`. It fails loudly instead of
guessing: if a reverse portal lookup is ambiguous, if page sections disagree with the structured `map` object, or if
the hand-written headline facts in the diff stop matching the data. This file (`maps.md`) is hand-written.

## Pages read

| Page | retrieved_at (cache meta) | Used for |
|---|---|---|
| https://meowdb.com/msclassic/maps/000000001 ... /000001021 (all 25 below) | 2026-10-04T09:56:36Z to 09:57:12Z | Everything in the map files |
| https://meowdb.com/_next/static/chunks/app/msclassic/%5Blocale%5D/maps/%5Bid%5D/page-a7e2d98c08322572.js | 2026-10-04T10:07:45.500Z | Read by hand once: units (`mobTime` and reactor `respawn` are seconds), the minimap coordinate formula, the respawn legend. The extractor does not load it. |
| https://meowdb.com/msclassic/guides/spawn-engine-respawn-and-map-capacity | 2026-10-04T10:06:30.200Z | Spawn model, and the mob-rate discrepancy below (docs only) |
| https://meowdb.com/msclassic/formulas/spawns | 2026-10-04T10:04:46.189Z | Capacity formula, and the mob-rate and rounding discrepancies below (docs only) |
| https://meowdb.com/msclassic/guides/beginners-guide-first-steps-in-maple-world | 2026-10-04T10:06:38.610Z | Shanks' ship fare and level, used only for the diff (the npcs domain owns it) |

Map pages and their `retrieved_at`:
000000001 09:56:36.674Z, 000000010 09:56:37.734Z, 000000020 09:56:39.214Z, 000000021 09:56:40.709Z, 000000030 09:56:42.256Z,
000000040 09:56:43.779Z, 000000041 09:56:45.244Z, 000000042 09:56:46.784Z, 000000050 09:56:48.241Z, 000000060 09:56:49.733Z,
000000061 09:56:51.245Z, 000001000 09:56:52.757Z, 000001001 09:56:54.266Z, 000001002 09:56:55.751Z, 000001003 09:56:57.262Z,
000001004 09:56:58.769Z, 000001005 09:57:00.260Z, 000001006 09:57:01.870Z, 000001010 09:57:03.267Z, 000001011 09:57:04.784Z,
000001012 09:57:06.279Z, 000001013 09:57:07.799Z, 000001014 09:57:09.307Z, 000001020 09:57:10.812Z, 000001021 09:57:12.305Z
(all 2026-10-04 UTC). Each file's `source.retrieved_at` carries the exact value.

Where the data lives on a map page: the Next.js flight payload (`rsc()`) holds a `map` object (the props of the map viewer
component) plus `mobMovement`, `breakableLabels` and `placedNpcs` beside it. Other facts are server-rendered elements:
the header facts list, "Map overview", "Map Summary" (respawn map, safe-zone line, NPC idle lines, BGM name and length,
the `rates` estimate block), "Monsters" table (movement labels), "Quests on this map", "Map restrictions", and on one
page a "Portals" list. The extractor walks those elements; nothing comes from search snippets.

## Ids included and why

The 25 maps of classic Maple Island, MeowDB ids, in MeowDB's own numbering (not GMS):
000000001 000000010 000000020 000000021 000000030 000000040 000000041 000000042 000000050 000000060 000000061
000001000 000001001 000001002 000001003 000001004 000001005 000001006 000001010 000001011 000001012 000001013
000001014 000001020 000001021.

They are the full Maple Island set that Iteration One built (one Blender collection each). Every portal on them leads
to another map in the set (the extractor asserts it), so the set is closed. Leaving the island is NPC travel
(Shanks, Southperry), not a portal.

| MeowDB id | Name | Street | is_town | safe_zone | return_map_id | BGM | mob_rate | field_limit | Portals | Player spawns | NPCs (MeowDB id) | Monsters (MeowDB id) spawn points | Reactors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 000000001 | Mushroom Town - West Entrance | Maple Road | true | true | 000000001 | Bgm00/FloralLife (Floral Life, 2:18) | 1 | 0 | out00 | 4 | Heena (1), Sera (2) | - | - |
| 000000010 | Mushroom Town | Maple Road | true | true | 000000010 | Bgm00/FloralLife | 1 | 0 | in00, out00 | 1 | Roger (3) | - | - |
| 000000020 | Mushroom Town | Maple Road | true | true | 000000020 | Bgm00/FloralLife | 1 | 0 | in00, in01, out00 | 3 | Nina (4) | - | - |
| 000000021 | Mushroom Town Townstreet | Maple Road | true | true | 000000021 | Bgm00/FloralLife | 1 | 0 | out00 | 1 | Sen (5) | - | - |
| 000000030 | East Entrance to Mushroom Town | Maple Road | true | false | 000000030 | Bgm00/FloralLife | 0.6 | 0 | in00, out00 | 1 | Todd (7), Peter (6) | Tutorial Jr. Sentinel (1) 6 | - |
| 000000040 | Snail Hunting Ground I | Maple Road | false | false | 000000060 | Bgm00/RestNPeace (Rest N Peace, 2:55) | 1 | 0 | east00 | 5 | Robin (8), Sam (9) | Snail (2) 40 | - |
| 000000041 | Snail Hunting Ground II | Maple Road | false | false | 000000060 | Bgm00/RestNPeace | 1 | 0 | west00, east00 | 5 | - | Snail (2) 32, Blue Snail (3) 13 | - |
| 000000042 | Snail Hunting Ground III | Maple Road | false | false | 000000060 | Bgm00/RestNPeace | 1 | 0 | east00, west00 | 5 | - | Snail (2) 20, Blue Snail (3) 21, Red Snail (5) 1 | - |
| 000000050 | A Split Road | Maple Road | false | false | 000000060 | Bgm00/RestNPeace | 1.5 | 0 | west00, east00, east01 | 1 | Maria (10), Mai (11) | Blue Snail (3) 17, Shroom (4) 14, Red Snail (5) 11 | - |
| 000000060 | Southperry | Maple Road | true | true | 000000060 | Bgm00/GoPicnic (Go Picnic, 1:13) | 1 | 4 | west00, in00 | 1 | Yoona (13), Bari (14), Shanks (15), Biggs (12) | - | - |
| 000000061 | Southperry Armor Store | Maple Road | true | true | 000000060 | Bgm00/FloralLife | 1 | 4 | out00 | 1 | Pan (16) | - | - |
| 000001000 | The Field West of Amherst | Rainbow Street | false | false | 000001010 | Bgm00/RestNPeace | 1.3 | 0 | west00, east00, in00-in05 | 1 | - | Snail (2) 7, Blue Snail (3) 13, Shroom (4) 17, Red Snail (5) 24, Orange Mushroom (9) 5 | 5 |
| 000001001 | In a Small Forest | Rainbow Street | false | false | 000001010 | Bgm00/RestNPeace | 1.3 | 0 | out00 | 5 | - | Snail 12, Blue Snail 7, Shroom 12, Red Snail 5, Orange Mushroom 4 | - |
| 000001002 | Dangerous Forest | Rainbow Street | false | false | 000001010 | Bgm00/RestNPeace | 1 | 0 | out01 | 8 | - | Snail 14, Blue Snail 3, Red Snail 5, Orange Mushroom 12 | - |
| 000001003 | Mushroom Garden | Rainbow Street | false | false | 000001010 | Bgm00/RestNPeace | 1 | 0 | out00 | 6 | - | Snail 7, Shroom 23, Orange Mushroom 5 | - |
| 000001004 | Snail Garden | Rainbow Street | false | false | 000001010 | Bgm00/RestNPeace | 1 | 0 | out00 | 6 | - | Snail 11, Blue Snail 19, Red Snail 11 | - |
| 000001005 | Hunting Ground Middle of the Forest I | Rainbow Street | false | false | 000001010 | Bgm00/RestNPeace | 1 | 0 | out00 | 6 | - | Snail 14, Blue Snail 12, Shroom 10, Red Snail 8 | - |
| 000001006 | Hunting Ground Middle of the Forest II | Rainbow Street | false | false | 000001010 | Bgm00/RestNPeace | 1 | 0 | out00 | 7 | - | Snail 10, Blue Snail 16, Shroom 7, Red Snail 6, Orange Mushroom 6 | - |
| 000001010 | Amherst | Rainbow Street | true | true | 000001010 | Bgm00/FloralLife | 1 | 4 | west00, in00, in01, in02, east00 | 1 | Lucas (17), Pio (18), Rain (19) | - | 6 |
| 000001011 | Amherst Weapon Store | Rainbow Street | true | true | 000001010 | Bgm00/FloralLife | 1 | 4 | out00 | 1 | Sid (20) | - | 2 |
| 000001012 | Amherst Townstreet | Rainbow Street | true | true | 000001010 | Bgm00/FloralLife | 1 | 4 | out00, west00 | 1 | - | - | 2 |
| 000001013 | Amherst Department Store | Rainbow Street | true | true | 000001010 | Bgm00/FloralLife | 1 | 0 | out00 | 1 | Lucy (21) | - | 1 |
| 000001014 | Snail Field of Flowers | Rainbow Street | false | false | 000001010 | Bgm00/FloralLife | 1.2 | 0 | east00 | 11 | - | Snail 6, Blue Snail 10, Red Snail 12, Orange Mushroom 6 | 3 |
| 000001020 | The Field East of Amherst | Rainbow Street | false | false | 000001010 | Bgm00/FloralLife | 1 | 0 | in00 (type 1), west00 | 10 | - | Snail 3, Blue Snail 11, Red Snail 12, Orange Mushroom 12 | - |
| 000001021 | Tomato Field | Rainbow Street | false | false | 000001010 | Bgm00/RestNPeace | 1 | 0 | out00 | 9 | - | Snail 9, Blue Snail 8, Red Snail 4, Orange Mushroom 4 | - |

Totals: 47 portals (46 resolved by reverse lookup, 1 with no return portal), 24 map-to-map connections (23 two-way, 1
one-way), 577 monster spawn points, 21 NPCs, 19 Wooden Box reactors.

## Field reference

All keys are snake_case. Ids are strings exactly as MeowDB writes them (map ids 9 digits, reactor ids 7 digits, monster,
NPC and quest ids as plain digit strings). Coordinates are MapleStory px in the map's own 2D frame, y increasing
**downward**, the same frame for every point on one map (portals, spawns, NPCs, reactors, minimap rectangle).

| Field | Meaning | Units / values | MeowDB origin |
|---|---|---|---|
| `id`, `name` | MeowDB map id and name | string | `map.id`, `map.name` |
| `street_name` | Street ("Maple Road", "Rainbow Street") | string | `map.streetName` |
| `region` | Region key | `"MapleIsland"` | `map.region` |
| `location_label` | Header fact "Location" as shown | e.g. "Maple Road / Maple Island" | header facts |
| `is_town` | MeowDB town flag | bool | `map.isTown` |
| `page_map_type_label` | Header fact "Map type" (only shown on town maps without monsters) | "Town" or null | header facts |
| `overview_text` | "Map overview" prose, verbatim | string | page |
| `return_map_id`, `return_map_name` | Respawn map: "Where you return after dying" | map id, name | `map.returnMap`; name from the Map Summary link (asserted equal) |
| `safe_zone`, `safe_zone_text` | The page shows "Safe zone. NPCs and portals, no mobs." | bool; text or null | Map Summary |
| `field_limit` | Raw field-limit integer | int (bit field; not decoded here) | `map.fieldLimit` |
| `field_restrictions[]` | Restrictions the page lists for that field limit: `key`, `label`, `description` | e.g. `summoning-bag`, "No summoning bags" | "Map restrictions" |
| `bgm.path`, `bgm.name`, `bgm.length` | BGM key, display name, length as shown | `"Bgm00/FloralLife"`, `"Floral Life"`, `"2:18"` (m:ss string, kept raw) | `map.bgm`, BGM player props |
| `mob_rate` | Map spawn-rate multiplier (effect disputed, see Discrepancies) | number | `map.mobRate` |
| `total_mob_count` | Number of monster spawn points | int (= `spawns.length`, asserted) | `map.totalMobCount` |
| `page_facts` | Header facts on monster maps: `levels`, `spawns`, `exp_rank` | strings as shown | header facts |
| `connected_maps[]` | `map_id`, `map_name`, `street_name` of every map linked **in either direction** | | `map.connectedMaps` |
| `portals[]` | Exits: `name`, `type`, `x_px`, `y_px`, `to_map_id`, `to_map_name`, `to_street_name` | px; `type` raw int (1 or 2 here) | `map.portals` |
| `portals[].to_portal` | Destination portal name, or null | string or null | **derived**, see below |
| `portals[].to_portal_derivation` | `"reverse_lookup"` or `"none"` | | derived |
| `portals[].arrival_note` | Only when `to_portal` is null: how to arrive | text | derived |
| `portals[].page_label` | Label from the page's "Portals" list (only 000001020 `in00`: "Inside portal") | text | "Portals (N)" section |
| `player_spawns[]` | Player spawn points (`x_px`, `y_px`) | px | `map.playerSpawns` |
| `npcs[]` | `id`, `name`, `x_px`, `y_px`, `idle_speech_lines[]` | px; lines verbatim | `map.npcs`; lines from the Map Summary talkers, matched by NPC link id |
| `monsters[]` | Per species: `id`, `name`, `count` (spawn points), `respawn_min_s`, `respawn_max_s`, `wave_spawn_count` | seconds (all 0 here) | `map.monsters` |
| `monsters[].movement`, `movement_label`, `movement_description` | Movement class and its page text | `walk` = "Stays on its floor", `jump` = "Jumps between floors"; the legend also has "Flies" (`fly`), unused here | `mobMovement`, Monsters table |
| `spawns[]` | Monster spawn points: `mob_id`, `x_px`, `y_px`, `mob_time_s` | px; seconds, 0 = wave-pool spawn | `map.spawns` |
| `intra_portals` | In-map teleports | always `[]` on these maps | `map.intraPortals` |
| `reactors[]` | Breakables: `id`, `name`, `x_px`, `y_px`, `respawn_s` | px; seconds (-1 would mean no respawn per the viewer code; none here) | `map.reactors`, `breakableLabels` |
| `minimap` | `width_px`, `height_px`, `center_x_px`, `center_y_px`, `has_image` | px | `map.minimap*` |
| `bounds_px_derived` | Minimap rectangle in map px: `x_min = -center_x_px`, `x_max = width_px - center_x_px`, same for y | px, or null when the minimap is all zeros (the 3 shop interiors) | **derived** from the viewer formula |
| `quests.starts_here[]`, `quests.progress_here[]` | Quests listed on the page: `id`, `name`, `npc_name` (giver portrait), `level_label`, `area_label`, `exp_reward_label`, `meso_reward_label` (labels verbatim, present only when shown) and, under progress, `objectives_on_this_map[]` (`mob_id`, `text`, `count`) | strings as shown | "Quests on this map" |
| `meowdb_spawn_estimates` | MeowDB's own capacity/EXP-per-hour model (monster maps only): totals, `capacity_solo`, `capacity_full_party`, `exp_rank`, and `per_mob[]` spawn-point split | mobs, EXP per hour | `rates` props |
| `spawn_rules_text`, `mob_rate_text` | The page's "How spawns work" and "About mob rate" text, verbatim (monster maps only) | text | Monsters section |
| `source`, `field_sources`, `notes`, `gaps` | Provenance. `field_sources.to_portal.pages` lists every destination page the lookup read; `field_sources.bounds_px_derived` cites the viewer chunk | | |

No canonical file contains an `external` value: nothing was filled from outside MeowDB.

### Destination portals (`to_portal`)

MeowDB gives `toMapId` but no destination portal name. Rule: `to_portal` is the **unique** portal in the destination
map whose `to_map_id` is the source map (`to_portal_derivation: "reverse_lookup"`). If there is none,
`to_portal` is null (`"none"`) and the arrival must use one of the destination map's `player_spawns`. If there were
more than one, the extractor would stop (it never picks one).

Result: 46 of 47 portals resolve. The one exception is **000000030 `out00` -> 000000040**: Snail Hunting Ground I has
no portal back (its only portal is `east00`), so arriving players appear at one of its 5 player spawns. GMS v8 `tn`
values were not used; they are listed as an external cross-check in `topology_diff.md` section 9 (43 of 47 agree; the
4 that differ are the new back-portals and the one-way arrival).

## Gaps (what MeowDB does not give)

- **Destination portal names.** Derived by reverse lookup (above).
- **Portal `type` meaning.** Raw ints only (2 on 46 portals, 1 on 000001020 `in00`). Neither the page nor the viewer
  code labels them; the page's "Portals" list calls that one type-1 portal an "Inside portal". Whether type 1 is
  invisible is not stated by MeowDB.
- **Geometry.** No footholds, platforms, ladders, ropes, walls or map edges. The minimap rectangle is the only extent,
  and it is not a hard boundary (one Snail spawn on 000001001 sits 10 px outside it). The three shop interiors
  (000000061, 000001011, 000001013) have no minimap at all.
- **y reference.** MeowDB does not say whether NPC/spawn y is the raw WZ life y or a foothold-snapped y. Evidence (docs
  only): Roger, Nina, Pan and Sid sit 2-9 px above the foothold y that Iteration One recorded, matching its note that the
  raw WZ y is that much smaller. MeowDB monster spawn y values sit above the nearest Iteration One v8 foothold tier below
  them at equal x: median about 45 px, mostly 10-120 px, with a few larger outliers. This is an approximate check (nearest
  tier below, against `docs/research/maps/<gms id>.struct.json` tiers), and those maps' layouts may differ. Snap NPCs and
  monsters to the ground in 3D.
- **Which player spawn to use** on arrival (when `to_portal` is null), on respawn after death, or for a new character.
  MeowDB lists the points, not the selection rule. The positions also differ from Iteration One's v8 `sp` points on two
  maps: all 4 on 000000001 (about 345 px lower) and 5 of 9 on 000001021 Tomato Field (about 361 px higher); see
  `topology_diff.md`.
- **Starting map.** MeowDB's beginner guide says only "You start on Maple Island". The map list does not mark a start
  map. 000000001 (4 player spawns, no arrival portal, Heena's tutorial quest) is the natural candidate, but that is an
  inference, not MeowDB data.
- **NPC-scripted warps.** Peter's idle line "If you want to move to the next stage, talk to me." hints at an NPC warp;
  MeowDB map pages show no warp data.
- **Monster respawn timers.** `respawn_min_s`/`respawn_max_s` and every `mob_time_s` are 0 on all 25 maps (wave-pool
  spawns). Their unit (seconds) comes from the viewer code and the spawn guide, not from the map page itself.
- **Field-limit bits.** Only the restriction the page lists ("No summoning bags" for `field_limit` 4) is known; the bit
  field is not decoded here.
- **Reactor contents.** What a Wooden Box drops lives on the breakables page (`game/data/canonical/breakables/`).
- **No in-map teleports** (`intra_portals` empty on all 25).
- **Quest details** (steps, rewards, dialogue) are not on map pages; the quests domain owns them. The map files only list
  which quests start or progress here.

## Discrepancies

1. **Does `mob_rate` change how many monsters stay alive?** Three MeowDB pages disagree.
   - Map pages ("About mob rate"): "Mob rate multiplies how many monsters this map keeps alive at once ... expect about
     63 monsters up at a time instead of 42" (000000050, 1.5x), "best reading from closed-beta play", and "The spawn
     figures above do not apply it yet."
   - Spawn-engine guide: "Other MapleStory servers multiplied map capacity by it. MSC does not. The live game ignores
     it; capacity comes only from spawn-point count and the player scalar."
   - Spawn formula page: `Capacity = floor(SpawnPoints x PlayerScalar)`, no mob rate.

   **Chosen:** the map files store `mob_rate` verbatim (that number is undisputed) plus both texts. Recommendation for the
   spawn system: default to the formula/guide model (capacity ignores `mob_rate`), behind one config switch. Reason: two
   dedicated mechanics pages agree, and the map page itself does not apply the multiplier to its own estimates. It
   matters on 000000030 (0.6), 000000050 (1.5), 000001000 and 000001001 (1.3) and 000001014 (1.2); each of those
   files carries a note.
2. **Capacity rounding.** For 42 spawn points the map page's `rates.capacity` is 31.5 and its text says "~32"; the
   formula page floors (31). `meowdb_spawn_estimates.capacity_solo` keeps MeowDB's raw 31.5. Use the formula page's
   floor in the runtime.
3. **000000030 East Entrance to Mushroom Town: town or hunting ground?** `isTown` is true, but the overview says "is a
   hunting ground", the header shows monster facts instead of "Map type: Town", and there is no "Safe zone" line (it has
   6 Tutorial Jr. Sentinels). **Chosen:** `is_town: true` (the structured field); `safe_zone: false`. Game code must
   not equate "town" with "no monsters"; use `monsters`/`safe_zone`.
4. **`connected_maps` is not the exit list.** 000000040 lists 000000030 as connected, but has no portal to it.
   `connected_maps` is the union of outgoing and incoming links (asserted on all 25 maps). Use `portals` for travel.
5. **Two maps are named "Mushroom Town"** (000000010 and 000000020). Not an error, but always key maps by id.
6. **Shop interiors with no minimap.** 000000061, 000001011 and 000001013 report a 0x0 minimap, while their points
   (portal, NPC, spawn, reactors) are ordinary px values. `bounds_px_derived` is null for them.

No two MeowDB pages disagree on map structure: portal target names and streets agree with each destination's own page,
`rates.perMob` spawn points equal `monsters[].count`, and every quest objective's monster is on that map (all asserted).

## Notes for game programmers

- **MeowDB says what and where-to; Blender says where in 3D.** Use portals' `to_map_id`/`to_portal`, NPC and monster
  sets, counts and timers from these files. Do not project `x_px`/`y_px` onto the 3D world directly: Iteration One's
  geometry follows GMS v8, and on 000000001, 000000020 and 000000042 MeowDB's portal positions (and Heena's spot) differ
  from that layout by 64-484 px. Player spawns differ too: all 4 on 000000001 and 5 of 9 on 000001021 Tomato Field sit
  roughly 350 px from the v8 `sp` points. Use the px values for relative placement only (left/right order, upper/lower tier).
- **Map ids.** Join Blender collections through `game/data/misostory/map_id_crosswalk.json` (`meowdb_id` ->
  `gms_v8_id`, `iteration_one_slug`). The crosswalk was matched by evidence (identical portal coordinates, NPCs, spawn
  counts), not by id arithmetic; there is no arithmetic rule (0 -> 000000001, 20001 -> 000000021).
- **Arrivals.** If `to_portal` is a name, place the player at that portal in the destination. If it is null (only
  000000030 `out00`), place the player at a player spawn of 000000040.
- **Death.** Respawn on `return_map_id`. The Mushroom Town maps (000000001-000000030) and Southperry return to
  themselves; the Snail Hunting Grounds, A Split Road and the Southperry Armor Store return to Southperry (000000060);
  every Rainbow Street map returns to Amherst (000001010).
- **Spawns.** Every spawn here is a wave-pool point (`mob_time_s` 0). MeowDB's model: one global 7.56 s respawn tick,
  a 5 s per-point cooldown after death, a mob reappears on the first tick at or after death + cooldown; at most
  `floor(spawn points x scalar)` alive, with scalar 75% solo, +5% per extra player, 100% at 6+. Each spawn point is
  bound to one `mob_id`.
- **Movement.** `walk` monsters stay on the floor they spawn on; `jump` (Orange Mushroom) can hop to a floor above or
  below. No flyers on Maple Island.
- **Reactors.** Wooden Box (`0000001`) respawns after `respawn_s` (90, 120 or 180 s here). Drops: breakables domain.
- **Restrictions.** Southperry, its Armor Store, Amherst, the Amherst Weapon Store and Amherst Townstreet
  (`field_limit` 4) forbid summoning bags. The Amherst Department Store is `field_limit` 0.
- **Overlaps with other domains.** `npcs[].idle_speech_lines` duplicate the npcs domain's idle chatter (same text, read
  from the map page). `quests` is an index only. Monster level/HP/EXP are not copied here (monsters domain).
- **Quests indexed on these maps:** starts here: 1000, 1001 (000000001), 1002 (000000010), 1003 (000000020), 1004
  (000000021), 1005 (000000030), 1006 (000000040), 1007, 1009, 1010 (000000050), 1011 (000000060), 1008, 1012-1019
  (000001010). Progress here (monster objectives): 1005, 1006, 1009, 1010, plus Victoria Island quests 10009, 10123 and
  10303 whose targets also live here.
