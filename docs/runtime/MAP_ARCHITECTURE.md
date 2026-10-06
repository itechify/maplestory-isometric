# MisoStory runtime map architecture (Iteration Two; as built through Iteration Three)

Status: **decided**, 2026-10-04. This is the map/world contract that [`ARCHITECTURE.md`](ARCHITECTURE.md) points to. It
covers map identity, portals, transitions, per-map gameplay state, saves, export chunking, the camera, performance
and traversal validation. The exporter internals are in [`blender_export.md`](blender_export.md). This document
fixes only the contract the exporter must meet.

Ids are MeowDB strings everywhere (`"000000040"`). GMS v8 ids (`40000`) survive only in the crosswalk and in Blender
collection names.

---

## 1. Decision

**Option C wins: the "instanced continuous" island.** One continuous, always-resident island holds geometry and
collision. Gameplay state is partitioned into MeowDB map instances, and exactly one instance is live at a time.
`current_map` changes only through one function, `MapSession.transition()`. Walking a trail into the next map
and pressing Up at its portal both end in the same logical state.

Why C:

- It keeps Iteration One's main result, a walkable floating island. That world is "a physical region of one
  scene" (DEFERRED.md), with 447 m of trail validated walkable (`trail_walk` 20/20).
- It keeps classic MapleStory semantics. You are always in exactly one map, only that map simulates, and spawns,
  `returnMap`, `isTown`, BGM and portals all come from MeowDB.
- **It contains Option A as a degenerate mode.** Every link has a `link_mode` of `edge` (walkable trail) or `warp`
  (press Up only). With every link set to `warp`, the runtime behaves like Option A: closed boundaries, press-Up
  transitions, and the rest of the island as scenery. The implementation order (section 6) ships warp mode first.
  So walk-through gates, trail containment and full residency are **not on the critical path to Test A**. If any
  of them slips, Test A still ships.

What was not taken:

- **From C itself:**
  - **Approach preview:** frozen destination mobs past a trail's midpoint. It is replaced by an optional,
    presentation-only ambient layer (section 4.7.6).
  - **Per-map NavigationRegion3D for monsters:** replaced by B's probe-based platform walker with a region clamp.
  - **The v8 portal name as the primary destination key:** replaced by A's MeowDB-derived resolution order.
  - **Capacity from `mobRate`:** wrong. MSC ignores `mobRate` (section 3.2).
- **From B:**
  - **Spatially inferred map identity:** rejected. It is kept only as an invariant check (`RegionIndex`).
  - **Multi-map monster activation:** rejected.
  - **`maximum_alive = spawn-point count`:** wrong (section 3.2).
- **From A:**
  - **Island as non-interactive backdrop:** rejected as the default. It survives as `warp` link mode.
  - **Decimated backdrop duplicate of every map:** rejected. One representation per map.

Grafted from the runners-up (each is marked where it is used):

- **From A:**
  - the destination resolution order: override, then unique reciprocal, then spawn point;
  - arrivals 1.5 m inward along the anchor normal, with the arrival portal disarmed until the player leaves its
    trigger;
  - `markers.json` as the gameplay authority, with glTF used for geometry only;
  - the exporter ownership assertion;
  - saves blocked during transitions, and the save fallback chain;
  - per-portal arrival tests (±0.1 m, grounded within 10 frames);
  - per-map bot runs cached by content hash;
  - the SCC allowlist for 30 → 40.
- **From B:**
  - the generated crosswalk validated like a compile error;
  - map-local save coordinates;
  - flood-fill reachability coverage;
  - "every marker inside its own map's inset";
  - the platform-walker monster AI with a region clamp;
  - stairs collided as ramps;
  - MultiMesh per (chunk, kit asset);
  - the street/destination HUD line on trails;
  - occluder dithering;
  - the ledge-height CI invariant for the one-way link.

## 2. Scoring

Scores run 1–10. Each one judges the proposal as submitted, before grafts.

| Criterion | A: per-map scenes | B: continuous, inferred identity | C: instanced continuous |
|---|---|---|---|
| 1. Faithful MapleStory map semantics | **9**: `current_map` is explicit state with one live instance. Press-Up portals, the one-way 30 → 40 and the hidden type-1 portal are reproduced exactly with no geometry. | **6**: map identity is inferred from polygons with a sticky rule, monsters simulate in several maps at once, and map entry happens by crossing a region. Capacity is wrongly set to the point count. | **8**: `current_map` is explicit and changed only by `transition()`, with one live instance. Walk-through gates are a declared non-canonical adaptation. `mobRate`-based capacity is wrong (fixed here). |
| 2. Robustness and simplicity in Godot 4.7 GDScript | **8**: swapping one child scene is the standard Godot pattern and chunks are small. The risk sits in the exporter and the backdrop split, and both are testable. | **4**: region identity, multi-map activation sets, distance-LOD AI, cross-boundary rules and all-loaded performance must all be right at the same time. | **6**: the core is one transition function. Gates, containment rings, trail ownership, the preview and full residency add parts, and performance is unproven until a perf scene exists. |
| 3. Automated and real traversal validation of all 25 maps | **8**: per-map, per-portal and graph tests are deterministic, run in parallel and cache by hash. The tour is composed of parts, not one continuous walk, and trails are untested because they are not gameplay. | **7**: one continuous bot run, flood-fill coverage and directed reachability. It is thorough but heavy, and it validates a derived identity. | **9**: static graph and containment proofs, bot walks of every link in both directions (40 → 30 must fail), press-Up equivalence, and a per-tick `RegionIndex` invariant. Both ways of moving are covered. |
| 4. Playability and feel ("can somebody sit down and play") | **6**: a fade at every edge, even across the 5 m Amherst pair. Invisible walls stand next to visible neighbours you cannot reach, and the island becomes scenery. | **7**: seamless walking with live neighbours and an optional warp. Long trails are dead time, and boundary edge cases can leak into feel. | **7**: seamless walking, an optional warp and a clean moment of map entry. Neighbours look empty and spawns pop in at commit. |
| 5. Fit with the Blender pipeline and the one-island identity | **4**: per-map collections export cleanly, but 447 m of validated trail becomes backdrop, and every map needs a second, decimated representation. | **9**: uses the island as built. Trails, layout and validators carry over, and fixes go back to Blender. | **9**: same as B. In addition, `trail_walk`, `m.route` polylines and layout anchors become runtime test inputs. |
| 6. Scaling to Victoria Island and Iteration Three | **9**: cost is linear per map. Non-planar graphs, dungeons and scripted warps are just more maps. | **5**: needs a continuous geography per continent, real streaming and pockets for vertical maps, and identity stays tied to geometry. | **8**: link mode is chosen per link, and identity is independent of geometry. Victoria can be warp-only wherever geography does not fit, and streaming sits behind one interface. |
| **Total (unweighted)** | **44** | **38** | **47** |

Weighting semantics and playability double (the Final Acceptance Standard) gives A 59, B 51, C 62. The order does
not change. A wins criterion 2 outright, and the design below takes that seriously: warp mode ships first, and every
C-specific mechanism can be switched off without touching gameplay code.

## 3. Facts this design rests on

All of the following were checked against the local MeowDB cache (`tools/meowdb/.cache`, map pages
`maps/000000001` … `maps/000001021`) and Iteration One's `docs/manifest.json`, `docs/build_report.json` and
`src/misostory/layout.py`.

### 3.1 Topology

- MeowDB lists **47 portals** on the 25 maps. They form **24 links**: 20 trail links and 4 door links. 23 links are
  two-way and one is one-way: `000000030.out00 → 000000040`, because Snail Hunting Ground I has no portal back.
- Every MeowDB portal matches Iteration One's v8 topology by name and destination. For every portal except
  `000000030.out00`, the destination map holds **exactly one** portal pointing back, and that portal's name equals
  the v8 `to_portal`. So destination portals can be derived from MeowDB alone. The v8 names are only a cross-check.
- Iteration One marks `in00` of 10000, 20000, 30000 and 40000 as arrival-only (`layout.ONE_WAY`). In MeowDB the
  first three are ordinary two-way portals, and 000000040 has no `in00` at all.
- `000001020.in00` (to Tomato Field) is MeowDB **type 1** (hidden). The other 46 portals are type 2.
- Interiors 000000021, 000000061, 000001011 and 000001013 sit on the interior stage (Blender x 2400–3000 m) and
  connect only by doors. 000001012 (Amherst Townstreet) is outdoors. It joins Amherst `in01` by a 5 m stair trail
  and continues west to 000001014.
- The full link table is in Appendix A.

### 3.2 Spawns (MeowDB spawn model, which corrects all three proposals)

MeowDB documents the MS Classic spawn engine in
[guides/spawn-engine-respawn-and-map-capacity](https://meowdb.com/msclassic/guides/spawn-engine-respawn-and-map-capacity)
and [formulas/spawns](https://meowdb.com/msclassic/formulas/spawns):

- **Global respawn tick: 7.56 s.** A dead point refills at the first tick at or after `death + cooldown`.
- **Cooldown:** 5 s for a wave point (the default). A timed point (`mobTime > 0`) uses its own timer instead.
- **Capacity:** `floor(spawn_points × PlayerScalar)`, where `PlayerScalar = min(1, 0.75 + 0.05 × (players − 1))`.
  Solo play gives **75%**.
- **The map `mobRate` is ignored: a MisoStory decision between MeowDB pages that disagree** (Iteration Three spawns
  audit). The spawn-engine guide (2026-08-24), the glossary (2026-09-04) and `/formulas/spawns` say MSC ignores it
  and capacity comes only from the spawn points and the player scalar. The map pages and the monster-page MOB RATE
  tooltip say it multiplies capacity ("about 63 up at a time instead of 42" on 000000050), a reading they call their
  best guess from closed-beta play, which contradicts the same pages' own player scalar and exceeds the spawn-point
  count. No page says it changes respawn speed. The switch is `data/misostory/presentation.json`
  `map_mob_rate.apply` (false); turned on, `SpawnModel.capacity_for_map` multiplies the capacity by the map's
  canonical rate, capped at the spawn-point count (one monster per spawn point). Iteration Two stated "MSC ignores
  the map mobRate" as a fact and read the switch from canonical data; `formulas/spawn_rate.json`
  `applied_by_msc` now stays only as MeowDB's own statement.
- **Unverified on MeowDB's own page:** the exact player-count curve, whether timed points sit outside the cap, and
  whether the tick slips under load. The values are stored as canonical, with MeowDB's verification notes copied
  into the record.

So proposal A's "no MeowDB page exists" is wrong, as are B's `maximum_alive = point count` and C's `mobRate`-based
capacity.

Every Maple Island spawn has `mobTime 0`, so all points are wave points. The island has **577 spawn points**. The
largest map is 000001000 with 66 points, a **solo cap of 49 live**. Per-map numbers are in Appendix B.

MeowDB counts replace Iteration One's v8 counts. For example, 000000040 has 40 Snails (v8 had 33 Snails and 16
Blue Snails), and 000000042 has one Red Snail (v8 had 13).

**`isTown` and spawns are independent.** 000000030 has `isTown: true` and 6 Tutorial Jr. Sentinel spawns (mob
`"1"`). Every spawned species (`1, 2, 3, 4, 5, 9`) has a cached MeowDB monster page.

### 3.3 NPC parity (MeowDB versus what Iteration One built)

| Map | MeowDB NPCs | Built in Blender | Action (Critical Rule: fix the source world) |
|---|---|---|---|
| 000000030 | Peter (6), Todd (7) | Peter | add Todd |
| 000000040 | Robin (8), Sam (9) | Robin | add Sam |
| 000000050 | Maria (10), Mai (11) | Maria | add Mai |
| 000000060 | Biggs (12), Yoona (13), Bari (14), Shanks (15) | these, plus Tia, Maple Administrator and Paul | remove Tia, Maple Administrator and Paul from the runtime NPC set and from the proxies |
| 000001010 | Lucas (17), Pio (18), Rain (19) | these, plus Mai | move Mai to 000000050 |

All other maps match. The runtime creates NPCs **only from the MeowDB lists** and takes their 3D positions from
Blender NPC markers, matched by name.

### 3.4 Other numbers used below

- The island has 20 trails, 447.3 m in total. The longest go to 000001006 (61 m), 000001004 (50.3 m), 000001014
  (42.2 m) and Southperry (37.5 m). The shortest is the 5 m Amherst `in01` ↔ Townstreet stair.
- 17,618 objects and 9,146,414 evaluated triangles, including instances. The WORLD layer is 3.30 M of those, and
  the per-map budget is 400 k.
- AUTHORING.md rules: a 4.5 m architecture-free corridor at every edge anchor, walking steps of at most 0.45 m,
  slopes of at most 38°, one-way drops of at most 2.6 m, and terrain overhanging the footprint by at most 1 m.
- MeowDB movement: walking speed is 150 px/s at Speed 100, and jump height is 77 px at Jump 100 and 111 px at the
  Jump cap of 120. World scale is about 0.02 m/px horizontally and 0.55–0.7 m per 60 px tier vertically, so the
  highest possible jump is at most about 1.30 m.

## 4. Final design

### 4.1 Vocabulary

| Term | Meaning |
|---|---|
| **map** | One MeowDB map id. It is the unit of gameplay state. |
| **world space** | A connected physical space: `maple_island` (the 21 outdoor maps and their trails) or `interior_stage` (the 4 interiors). |
| **chunk** | A unit of exported geometry: `map:<id>`, `trail:<trail_id>` or `scenery:<i>_<j>`. |
| **trail** | Walkable ground joining two edge portals of neighbouring maps. It has no canonical counterpart. |
| **link** | An undirected pair of portal ends with a direction for each side (`a_to_b`, `b_to_a`). Its `link_mode` is `edge` (trail walkable) or `warp` (press Up only). |
| **portal** | The canonical MeowDB portal, or an adaptation arrival point. It has a press-Up trigger and an arrival transform. |
| **gate** | The walk-through commit plane at the inner end of a trail, at a map's footprint edge. Gates exist only on `edge`-mode links. |
| **instance** | The live gameplay state of the current map: monsters, drops and spawn timers. |

### 4.2 Data: files and ownership

| File | Kind | Contents |
|---|---|---|
| `game/data/canonical/maps/<id>.json` | canonical, committed | MeowDB map record, kept verbatim: `name, streetName, isTown, returnMap, fieldLimit, bgm, mobRate, portals[name,type,x,y,toMapId], spawns[mobId,x,y,mobTime], playerSpawns[x,y], npcs[id,name,x,y]`, plus `source{authority,url,retrieved_at}` |
| `game/data/canonical/formulas/spawns.json` | canonical, committed | `tick_s: 7.56`, `wave_cooldown_s: 5`, `player_scalar: {base: 0.75, per_extra_player: 0.05, max: 1.0}`, `uses_map_mob_rate: false`, `verification: "meowdb_model; player-count curve unverified by MeowDB"`, plus `source` |
| `game/data/misostory/map_id_crosswalk.json` | adaptation, committed, hand-checked | 25 rows: `{map_id, gms_v8_id, blender_slug, kind, world_space}`. There is no formula: `0 ↔ 000000001` breaks the obvious one. |
| `game/data/misostory/portal_adaptations.json` | adaptation, committed | Per-link `link_mode` overrides, destination overrides and arrival-only gates, each entry with a `reason` |
| `game/data/misostory/maps/<id>.json` | adaptation, committed, hand-authored | Per-map overrides: `environment_preset`, `camera.ortho_size_scale`, `spawn_slot_overrides`, notes. Never written by tools. |
| `game/data/misostory/world_scale.json` | adaptation | px → m conversions (exists per ARCHITECTURE.md) |
| `game/data/misostory/movement.json` | adaptation | walk speed, jump apex, step-up and floor angle for the controller (owned by the controller doc). This doc reads `jump_apex_m_at_cap` and `step_up_m`. |
| `game/assets/world/export/**` | generated by Blender, git-ignored | chunk glTFs, `instances.json`, `<id>.markers.json`, `maple_island.json` (section 4.10) |
| `game/assets/world/maple_island.scn`, `chunks/*.scn`, `world_index.json` | generated by the Godot assembler, git-ignored | the assembled world plus every canonical-to-geometry join: resolved portals, gates, spawn slots, NPC placements, containment and region polygons |

The join of canonical data and geometry happens **in one place**, `game/tools/assemble_world.gd`, which runs
headless after the Blender export. MeowDB decides *what* (species, counts, NPC ids, destinations), Blender decides
*where* (regions, anchors, markers), and the assembler joins them. If a canonical value changes, rerun the
assembler, not Blender.

### 4.3 Map identity

**`MapSession`** (autoload, `game/scripts/autoload/map_session.gd`) owns:

```gdscript
var current_map: String               # always exactly one MeowDB id once the world has started
var state: State                      # BOOT, IDLE, WARP_OUT, SWAP, WARP_IN, ARRIVING, DEAD
var respawn_reference: String         # canonical returnMap of current_map
var last_arrival: ArrivalRef          # {map_id, portal_id} or {map_id, spawn_index}
var last_transition: TransitionRecord # {from, to, via, portal_id, arrival, t_game}
func transition(req: TransitionRequest) -> Error
func request_portal(portal: PortalDef) -> Error     # press Up / interact
func debug_warp(map_id: String, portal_id := "") -> Error
func can_save() -> bool                             # state == IDLE and the player is alive with a valid SafeGround
```

- `current_map` is **never** inferred from position. It changes only inside `transition()`.
- `via` is one of `gate`, `press_up`, `door`, `respawn`, `load`, `debug`.
- Every change emits the existing `Events` signals in this order: `map_left(old)`, `map_entered(new, old)`, then
  `portal_used(old, portal, new)`, the last only when `via` is `gate`, `press_up` or `door`. Listeners that need
  `via` read `MapSession.last_transition`. Nobody needs a new signal.

**`MapDefinition`** (`game/scripts/core/maps/map_definition.gd`, a pure RefCounted object built from canonical data,
adaptation data and `world_index.json`) is the per-map API the brief asks for:

```gdscript
var map_id: String
var map_name: String
var street_name: String
var world_space: StringName
var portals: Array[PortalDef]
var destination_maps: PackedStringArray           # unique toMapIds, derived
var monster_spawn_definitions: Array[SpawnSlot]   # index == MeowDB spawns[] index
var npc_definitions: Array[NpcPlacement]          # MeowDB npc id + 3D transform
var player_spawns: Array[Transform3D]             # index == MeowDB playerSpawns[] index; [0] required
var respawn_location: ArrivalRef                  # {map_id: returnMap, spawn_index: 0}
var environment_configuration: Dictionary         # bgm, is_town, field_limit (raw), preset, ortho_size
var frame: Transform3D                            # map-local -> world (from layout)
var footprint: PackedVector2Array                 # world XZ polygon (footprint + 1 m)
var camera_bounds: PackedVector2Array             # section 4.11
```

`MapDefinitions` (one instance held by `MapSession`) holds all 25 definitions, keyed by id.

> **Status (2026-10-04, M2).** Built as specified, pure, in `game/scripts/core/maps/region_index.gd` (the z-band of a
> map footprint is its chunk bounds from 2 m below to 4 m above, the containment ring's span); the 10 Hz invariant
> runs in `game/scripts/world/region_monitor.gd`, the gates in `gate_monitor.gd`. See WORLD_RUNTIME.md "Trails and
> gates" and "Region index".

**`RegionIndex`** (`game/scripts/world/region_index.gd`) answers `region_of(pos) -> {kind: map|trail|void, id}`. It
uses map footprints (+1 m, z-band from base − 5 m to base + 25 m), trail zones (ribbon width + 1 m, z-band ±5 m
along the centreline), and interior room boxes. Map footprints take precedence over trail zones. It is used for:

1. **The identity invariant.** Ten times a second, the player's last ground point must lie in
   `{current_map} ∪ trails touching current_map ∪ {map of any armed gate}`. If the rule is broken for 5 samples in
   a row, `push_error` reports the position. Dev and test builds then fail; release builds recover to `SafeGround`.
2. Save snapping (section 4.9), the HUD line on trails, the debug overlay and camera bounds.

### 4.4 Portals, doors and edges

**One portal class**, `PortalDef` (data) plus `portal.tscn` (node: an `Area3D` trigger, a visual and a prompt
anchor). There is no per-map portal script. The fields:

| Field | Value |
|---|---|
| `portal_id` | the MeowDB portal name (`east00`), or `arrival:<trail_id>` for an adaptation arrival gate |
| `source_map_id` | the map that owns the portal |
| `destination_map_id` | MeowDB `toMapId` (`""` for arrival-only portals) |
| `destination_portal_id` | resolved (below); `""` means use `destination_spawn_index` |
| `destination_spawn_index` | used when there is no destination portal (the 30 → 40 case) |
| `spawn_transform` | where a traveller **arriving at this portal** appears: the anchor + 1.5 m along the inward normal (`layout.anchor_normal_world` for edges, the door's facing for doors), facing inward and grounded by raycast |
| `portal_type` | `edge`, `door` or `arrival` |
| `canonical_type` | the MeowDB type (`1` hidden, `2` visible), or `-1` for an adaptation |
| `interaction_type` | `press_up` (doors, and any edge in warp mode), `press_up_or_walk` (edges in edge mode) or `walk_only` (arrival gates) |
| `link_mode` | `edge` or `warp`, from `portal_adaptations.json`. Trail links default to `edge` and door links to `warp`. |
| `trail_id` | for edges, `T_<mapA>_<portalA>__<mapB>_<portalB>` |
| `provenance` | `{meowdb_url, v8_name_match: bool, override_reason?}` |

**Destination resolution** (`PortalGraph.resolve`, pure, from A), in order:

1. An explicit override in `portal_adaptations.json`, which must carry a `reason`.
2. The **unique reciprocal**: the one portal in the destination whose `toMapId` is the source. This holds for 46
   of the 47 portals.
3. Otherwise, the destination's `playerSpawns[0]`. This is the `000000030.out00` case.

Zero or several reciprocals without an override is a validation error. A disagreement with the v8 `to_portal` in
`docs/topology.json` is also a validation error. Today there are none (section 3.1).

**Interaction:**

- `press_up` means the player is inside the portal trigger (4.5 m wide, 3 m tall, 1.6 m deep) and presses the
  `portal_enter` action. That action is bound to the Up arrow; the `interact` key also works when the portal is the
  nearest interactable. It must be a fresh press: `just_pressed` after the arrival.
- Type 2 portals show the portal swirl and a prompt. **Type 1 (`000001020.in00`) shows no swirl and no prompt, but
  pressing Up works**, as in classic. Its hedge lane trail stays walkable.
- **Anti ping-pong (A):** the portal you arrive at is disarmed until the player leaves its trigger.
- **Doors:** always `warp`. Entering teleports to the interior's `out00.spawn_transform` on the interior stage, and
  leaving is symmetric.
- **Arrival-only gate:** `arrival:T_000000030_out00__000000040` sits at 40's former `in00` anchor. It has no
  swirl and no prompt, and its `spawn_transform` **is** `player_spawns[0]` of 000000040. A press-Up from 30 and a
  walk down the trail therefore land in the same place. MeowDB's 40 player spawns sit at the west end (x ≈ −213…1
  px), which matches that anchor. A commit through a `walk_only` arrival gate records
  `last_arrival = {map_id: "000000040", spawn_index: 0}`, the same value a press-Up from 30 records, so the two are
  equivalent.

**Gates (walk-through commit, edge mode only).** Each `edge`-mode link has a gate at **both** trail ends. A gate is
a vertical plane perpendicular to the anchor's outward normal, placed **at footprint + 1.0 m**. That is the same line as the
map's `RegionIndex` boundary and the containment-ring gap (sections 4.3 and 4.6). These three must coincide, or a
player resting at a trail mouth would sit inside the next map's region with no gate armed and trip the identity
invariant. The gate has inward normal `n`, lateral half-width 2.25 m (the 4.5 m corridor) and a height of 3 m above
ground, more than twice the maximum jump of about 1.3 m. The portal's press-Up trigger stays centred on the anchor,
and `spawn_transform` stays 1.5 m inward of the anchor (2.5 m inward of the gate plane). Each physics tick,
`GateMonitor` tests only the **far-end gates of trails touching `current_map`**, at most 8 (000001000). The test
uses the player's feet position `p` (it does not use `Area3D` events):

```
d_prev = dot(p_prev - G.origin, n);  d_now = dot(p_now - G.origin, n)
in_box = |dot(p_now - G.origin, lateral)| <= 2.25 and -1.0 <= p_now.y - G.origin.y <= 3.0
if d_prev <= 0 < d_now and in_box:  G.armed = true          # crossed inward (possibly mid-jump)
if d_now < -0.25:                   G.armed = false         # walked back out onto the trail
if G.armed and d_now > 0 and player.is_on_floor() and not player.in_hitstun:
    if PortalGraph.has_direction(current_map -> G.map): MapSession.transition(gate=G); G.armed = false
    else: push_error once ("gate without link")             # containment should make this impossible
```

- A crossing mid-jump or under knockback arms the gate, and the commit happens on the first grounded tick after
  hit-stun ends.
- **The trail belongs to the map you came from.** Turning back is a no-op, and gates of `current_map` itself are
  never tested, so the player cannot ping-pong.
- The Amherst `in01` ↔ Townstreet `out00` pair (5 m apart) leaves 3 m of trail between the two gate planes.
- **Equivalence of walking and pressing Up is logical, not positional.** After a gate commit the player stands at
  the gate plane, not at `spawn_transform`. Both paths must produce the same `current_map`, `last_arrival`,
  `respawn_reference`, live instance and event sequence (tested, section 4.13).

**The one-way link 30 → 40** is enforced in the source world, not at runtime:

- The 30 → 40 trail ends in a **2.4 m ledge** whose face lies **on 40's arrival gate plane** (footprint + 1 m,
  ±0.1 m; checked in L1), with the upper landing outside the plane and 40's ground below it (`trails.py`, see
  section 5). The player stays outside the plane until stepping off the ledge, so the gate arms mid-fall and commits
  on landing, below the ledge. If the face sat outward of the plane, the commit would fire on the upper landing,
  and the open trail back to 30 would leave the player in 30's region while `current_map` was 40.
- CI invariant: `jump_apex_m_at_cap + step_up_m + 0.30 ≤ ledge_height_m ≤ 2.6` (the Blender validator's drop cap).
  The values come from `movement.json` and the exported ledge marker. Expect about 1.30 + 0.45 + 0.30 = 2.05 ≤ 2.4.
- The 40-side gate is `walk_only`, and 000000040 has no press-Up portal back.
- The bot must fail to reach 30 from 40 (section 4.13).

**Link modes.** For each link, `link_mode` is read from `portal_adaptations.json`. A global
`force_link_mode: "warp"` setting there exists for the fallback and for debugging. `warp` mode on a trail link:

1. disables both gates;
2. enables the two containment **plugs** that close the gate gaps;
3. switches both portals to `press_up`;
4. leaves the trail visible as scenery.

The debug console can switch link modes at runtime.

### 4.5 Transition flow

**States:**

```
BOOT -> IDLE
IDLE -(gate)------------------------------------------> SWAP -> IDLE
IDLE -(press_up | door | debug)-> WARP_OUT -> SWAP -> WARP_IN -> ARRIVING -> IDLE
IDLE -(hp == 0)-> DEAD -(confirm)-> WARP_OUT -> SWAP -> WARP_IN -> ARRIVING -> IDLE   (via = respawn)
BOOT -(load | new game)-> SWAP -> WARP_IN -> ARRIVING -> IDLE                          (via = load)
```

**`transition(req)`.** `req = {to_map, arrival: ArrivalRef | Transform3D, via, source_portal}`.

1. **Guard.** Reject unless `state == IDLE` (or `DEAD`/`BOOT` for `respawn`/`load`). For `gate`, `press_up` and
   `door`, also reject unless the link direction exists. Rejections return an error and log; they never assert in
   release.
2. **Resolve the arrival** before any fade, so a failure never leaves the screen black. `ArrivalResolver` turns
   the request into a `Transform3D`: a portal's `spawn_transform`, a `player_spawns[i]`, or a validated save
   position (section 4.9). If it fails, reject as in step 1. For `gate`, the arrival is the gate's portal
   (`{spawn_index: 0}` for an arrival gate), and the transform is not used.
3. **Warp out** (all kinds except `gate`). `state = WARP_OUT`. Freeze player input and physics (`process_mode`
   disabled on the body, velocity zeroed). Fade to black over 0.2 s (`ScreenFader`).
4. **`state = SWAP`.** Steps 5–13 run in **one frame**, in this order.
5. `Events.map_left.emit(old)`.
6. **Release the old instance.** `MapInstanceView.release()` returns monster nodes to their pools and frees drop
   nodes. `MapStateCache.put(old, instance_state.snapshot(Game.clock.now))`. Disable the old map's NPC interaction
   prompts and portal prompts.
7. `current_map = to_map`. `respawn_reference = defs[to_map].respawn_location.map_id`. `last_arrival` is set to
   the arrival reference.
8. **Activate the new instance.** Restore it from the cache, `MapStateCache.take(to)`, fast-forwarded to `now`
   (section 4.7), or create `MapInstanceState.fresh(def, rng)`. Then `MapInstanceView.realize(state, arrival_pos)`
   queues monster spawns nearest-first, at most 8 per frame, each fading in over 0.3 s. It enables NPC interaction
   for this map, arms the map's portals, and disarms the arrival portal until the player leaves its trigger.
9. **Place the player** (warps only). `player.teleport(xform)` sets the transform, zeroes velocity, clears jump
   and coyote state, and resets `SafeGround` to the arrival point.
10. **Camera.** `camera.set_bounds(def.camera_bounds, def.ortho_size, blend = 0.35 s for gate, 0 for warps)`.
    Warps also call `camera.snap()`.
11. **Environment.** Tween the lighting preset (0.5 s for gate, instant under a fade). Crossfade the BGM over 0.5 s
    only when `bgm` differs. Show the HUD banner (map name and street).
12. Emit `Events.map_entered(to, old)`. Emit `Events.portal_used(old, source_portal, to)` when `via` is `gate`,
    `press_up` or `door`.
13. `last_transition = record`. Append it to the transition log, a ring buffer of 64 entries used by the debug
    overlay and the bot assertions.
14. **Warp in.** Fade in over 0.2 s, then `state = ARRIVING`. Input stays frozen until the player `is_on_floor()`,
    which the L2 tests require within 10 physics frames. After 30 frames without floor, `push_error` and re-place
    the player at `player_spawns[0]`; the bot fails on this. For a gate, return straight to `IDLE`.
15. `state = IDLE`. Request an autosave, which runs only while `can_save()` holds.

Budgets: a whole warp takes at most 0.6 s including both fades, and a gate commit frame takes at most 33 ms (spawns
are staggered).

### 4.6 Containment and fall recovery

Every map is fully walled. Exits are only portals, and on `edge` links also the trail mouths.

- **Footprint ring.** An invisible `StaticBody3D` wall, 4 m tall, on the `containment` layer (the player collides
  with it; monsters do not). It runs along each map footprint at **+1.0 m**, just outside the 1 m terrain overhang
  that AUTHORING.md allows. On `edge` links it has 4.5 m gaps where the gate planes cross it (the authored
  corridor). Each gap carries a plug body that is enabled in `warp` mode.
- **Trail side walls.** These follow the trail ribbon edges at +0.3 m, are 3 m tall, and run continuously from
  gate to gate.
- **Interiors.** A ring around the room footprint, including the open cutaway front.
- **Non-walkable scenery.** The island body, plinth skirts beyond +1 m, forest, peaks and clouds get **no
  walkable collision**. No reachable ground exists outside a map region or a trail zone, which the flood-fill test
  proves (section 4.13).
- **Fall recovery.** `SafeGround` records the player's position every tick in which the player is on the floor,
  not in hit-stun, and standing on a `walkable` collider inside the current region. If the player is airborne
  below `kill_y` (per map, from markers: the lowest walkable y of the map and its trails minus 6 m), they return to
  the last `SafeGround` point. There is no damage. Each recovery logs one line, and the traversal tour requires
  zero recoveries.
- **Fall damage.** MeowDB documents fall damage (canonical `formulas/movement.json` `fall_damage`: a landing after at
  least 45 consecutive fast-falling movement updates deals base 24, rising to 36; "Maps can disable fall damage").
  MisoStory applies none, on a landing or a recovery: a MisoStory adaptation (`presentation.json` `fall_recovery`,
  `verified: false`), not a canonical rule. The canonical rule cannot be applied as published, because the length of
  one movement update is not documented and MeowDB does not say which maps disable fall damage (a source-data gap,
  parity row `mechanic:fall-damage`).
- **Feel.** Wherever an invisible wall reads badly, dress the footprint edge in Blender (hedge, fence or cliff lip)
  rather than adding runtime hacks. These are tracked under the World Review.

### 4.7 Monster, NPC and drop lifetime

#### 4.7.1 Spawn slots (the canonical-to-geometry join, done in the assembler)

1. Blender authors **spawn regions** per map: `m.spawn_region(name, polygon, tiers=["T1", "T3"])`, a local polygon
   on walkable ground, tagged with the struct.json tier ids it represents. This is new authoring work (section 5).
2. For each MeowDB `spawns[i] = {mobId, x, y}`:
   - Pick the **tier**. It is the struct.json tier whose foothold profile lies under `(x, y)`; if none does, the
     nearest tier by px distance, with a warning.
   - Pick the **region** tagged with that tier. If no region carries the tag, fall back to the nearest region by
     depth band, with a warning.
   - Place the point at the normalised position `u = (x − tier.x1) / (tier.x2 − tier.x1)` along the region's long
     axis, with deterministic depth jitter (`seed = hash(map_id, i)`).
   - Raycast onto `walkable`. Relax the point to at least 1.2 m from other slots and at least 4 m from every
     portal or gate `spawn_transform`, then shape-cast the monster capsule to check clearance.
3. The output is `SpawnSlot {index: i, mob_id, transform, region}`, with the **index equal to MeowDB's** index.
   Validation: per-species counts equal MeowDB's exactly, and every slot is grounded, clear, and inside its own
   map's region inset of 2 m. `spawn_slot_overrides` in `maps/<id>.json` may pin a slot's transform, with a
   reason. The species and count can never be overridden.

**As built (Iteration Three, `SpawnSlotPlanner`).** Step 2's tier projection of MeowDB's `x, y` was never built; the
planner places by Blender's species-tagged regions instead (the v8-era `m.mobs` layout and 000000030's
`m.spawn_region` tiers):

- **Regions.** Each sidecar `spawn_regions` entry is clipped to the mob region; its authored exclusions
  (`exclude_xz`: the `avoid` zones of `m.mobs`, such as A Split Road's junction plaza, Snail Garden's flower beds and
  Dangerous Forest's glade) are taken out of its room (their union: overlapping beds count once) and no slot
  samples inside them.
- **Shares and density.** Two passes. First, slot by slot, a species' slot goes to its tagged region with the most
  weight per slot of that species already there (a proportional share), as long as the region keeps at least
  `spawns.min_area_per_slot_m2` (8 m²) of room per slot counting every slot placed so far; a slot no tagged region
  can take waits. Then the waiting slots spill to the least crowded region of the map. Spilling only after every
  species has its own regions keeps one species' overflow from taking another species' room (the first Iteration
  Three planner spilled at once, in species order, and moved 83 slots, 25 of 45 on 000001006). On the shipped export
  57 of 577 slots spill (test_spawn_slots, flat-ground planning), all on maps with under 18 m² of region room per slot;
  Tomato Field's 25 slots have 5.1 m² each in all, so there the spill only evens the crowding out; 000001001's
  BlueSnail_6 no longer holds 16 slots in 88 m² (11 now).
- **Clearances.** A slot stands at least `slot_min_spacing_m` (1.2 m) from other slots, `slot_portal_clearance_m`
  (4 m) from every arrival and player_spawns[0], and `slot_npc_clearance_m` (2.5 m: the 1.6 m talk sphere plus the
  widest touch-zone half-width) from every NPC of the map (Sam stood inside 000000040's Snail_3 region). Sampling
  tries the region's own tier first, then any walkable top surface; it never accepts a "forced" placement on the
  shipped export (test_world_static, test_spawn_placement, the `test_b_population` playtest).
- `SpawnSlotPlanner.arrival_points(def)` and `npc_points(def)` give these clearances to other placed things
  (breakables).

#### 4.7.2 MapInstanceState (pure, `game/scripts/core/maps/map_instance_state.gd`)

- It holds `slots[i] = {alive: bool, hp: int, died_at: float}`, `drops[] = {item_id|mesos, amount, pos_local,
  expires_at, owner}` and `capacity`.
- `capacity = SpawnModel.capacity_for_map(map_id, points, players = 1)`, which is `floor(points × 0.75)` while
  `presentation.json map_mob_rate.apply` is false (section 3.2).
- `fresh(def, rng)` fills to capacity **immediately**, choosing random slots with a seeded RNG. Immediate fill is
  an adaptation, because classic maps are populated when you enter them (open question 6).
- `tick(now)` runs on the global `SpawnClock` boundaries (period `tick_s`, anchored at game start on the pausable
  `Game.clock`). Every dead slot whose `died_at + cooldown ≤ boundary` is eligible. While `alive_count <
  capacity`, eligible slots respawn in seeded random order.
- `snapshot(now)` and `fast_forward(now)` replay the missed tick boundaries in closed form. On Maple Island this
  usually refills to capacity after about 13 s away.
- Survivors restore **at their slot**, with their HP kept. Drops past `expires_at` are discarded.
- **Breakables** (Iteration Three, contract C8): `breakables[i] = {id, hits, respawn_at, respawn_s}`, one per canonical
  `reactors[i]` (the placement index). `hit_breakable(i, now, hits_to_break)` counts landed hits;
  `tick_breakables(now)` brings a broken box back exactly `respawn_s` after the break on the game clock (not on the
  spawn tick). They are in the snapshot, parked with the map in `MapStateCache`, and never saved. Their 3D positions
  come from `BreakablePlacementPlanner`, the way spawn slots come from `SpawnSlotPlanner` (MeowDB's `x_px`/`y_px`
  are not used).

#### 4.7.3 MapStateCache

An LRU of the 4 most recent non-live maps. Eviction discards the state, and the next entry gets `fresh()`.
Monster and drop state is **never** written to save files (drops vanish on logout, as in classic).

#### 4.7.4 Live monsters (`MapInstanceView`, only for `current_map`)

- **Pools.** Per-species `CharacterBody3D` pools are pre-warmed at world load. Each pool's size is the largest
  `min(points_of_species, capacity)` over all maps (Snail: 32, from 000000041).
- **AI** is the classic simple loop, idle, pace back and forth and turn, done as a **platform walker** (B):
  - before stepping, probe 0.6 m ahead for ground within ±0.45 m; a probe that finds none means a ledge, so turn;
  - probe for a wall at 0.3 m height;
  - clamp to the map's **mob region**, which is the footprint inset by 2 m, minus 4 m discs around portals and
    gates;
  - stay on its **floor** ('Stays on its floor'): the ground ahead must lie within `floor_band_m` (0.5 m) of the
    spawn height, widened to the spawn region's authored tier, so a walker never climbs a ramp to another terrace.
    The Orange Mushroom ('Jumps between floors') may hop from its spawn floor to one floor above or below it and
    back, never two floors away (MONSTERS_AND_COMBAT_RUNTIME.md "Behaviour").
- Monsters never enter trails, never cross gates and ignore the containment layer.
- **No respawn on the player.** A slot the respawn tick brings back is not realized while the player's feet are
  within `spawns.respawn_player_clearance_m` (2 m) of it; it waits at the back of the queue (alive in
  `MapInstanceState`, so capacity and counts stay canonical) until the player has moved away. The same holds for the
  arrival's own fill: a portal arrival is 4 m from every slot, but a game loaded at its saved resume point can stand
  on one, and that slot's monster waits too.
- **Contact damage, hits, knockback and death** belong to the monster and combat docs. On death,
  `Events.monster_killed(monster_id, map_id)` fires, and the slot records `died_at`.

#### 4.7.5 NPCs

- All MeowDB NPCs, about 21, are instantiated **once at world load** at their markers and stay resident (idle
  animation), so towns never look empty from next door.
- **Interaction** (prompt, dialogue, shop, quest markers) is enabled only when `npc.map_id == current_map`.
- Quest NPC lookups key by MeowDB NPC id.

#### 4.7.6 Ambient neighbours (presentation only, milestone M3, behind a flag)

Live monsters exist only in the current map, so neighbouring hunting maps look empty. The design mitigates this
explicitly instead of accepting it silently:

- For each hunting map within link distance 1 of `current_map`, one `MultiMeshInstance3D` per species shows its
  alive slots, taken from the cached snapshot or from a deterministic `fresh()` if never visited.
- Each mob gets an idle bob in the vertex shader. There are **no** physics bodies, AI, collision or nodes per mob.
- On commit, the new live map's ambient layer hides as live monsters spawn on **the same slots**, so nothing pops,
  and the map you left shows its snapshot.
- Flag: `data/misostory/presentation.json: ambient_neighbours`. The World Review decides whether it stays on.
- It replaces C's approach preview and needs no turn-back logic and no leak tests.

#### 4.7.7 Drops

- Drops are owned by the instance.
- **Ground lifetime** is an adaptation value in `data/misostory/drops.json`, marked unverified until MeowDB
  provides one.
- When the player leaves, drops survive in the snapshot with their remaining lifetime and are restored on return.

### 4.8 Death and respawn

1. HP reaches 0. The player enters `DEAD`, input is disabled, and `Events.player_died(current_map)` fires. The
   death UI waits for confirmation.
2. The penalty hook (`DeathRules.apply(character)`) is empty for now; the canonical rules arrive with Phase 9.
3. `transition({to: defs[current].respawn_location.map_id, arrival: {spawn_index: 0}, via: respawn})`.
   Examples:
   - Maple Road fields 040–050 go to 000000060.
   - Rainbow Street fields go to 000001010.
   - Towns respawn in themselves.
   - 000000021 respawns in itself.
   - 000000061 goes to 000000060.
   - 000001011, 000001012 and 000001013 go to 000001010.
4. HP and MP after respawn follow the canonical death rules, which the Phase 9 doc owns.
   `Events.player_respawned(map)` fires.

The respawn location is `playerSpawns[0]` of `returnMap`. MeowDB does not say which spawn point is used, so this is
open question 1.

> **Status (2026-10-04, world runtime).** The spawn index lives in `data/misostory/death.json`
> `respawn_player_spawn_index`. The penalty can be applied at the moment of death, as in classic, through
> `MapSession.death_commit`. Saving while `DEAD` is then legal and stores the respawn point, and `respawn()` skips the
> step 2 hook (`death_rules`). A quit to title resets `MapSession` to `BOOT` (`reset()`). See
> [`WORLD_RUNTIME.md`](WORLD_RUNTIME.md) "MapSession".

### 4.9 Save position model

The save stores logical state only, versioned with the save schema:

```json
"location": {
  "map_id": "000001000",
  "entry": {"map_id": "000001000", "portal_id": "west00"},
  "resume": {"local_pos": [31.2, 4.05, -17.8], "facing_deg": 135.0, "map_content_hash": "9f1c..."}
},
"respawn_reference": "000001010"
```

- **`entry`** is `MapSession.last_arrival`, which is either a portal id or `{"spawn_index": n}`.
- **`resume`** is optional. `local_pos` is in the map's own frame (`MapDefinition.frame.affine_inverse() *
  world`). This graft from B means a `layout.py` move of a map does not invalidate saves. The position comes from
  **`SafeGround`**, never from the live position, so a save made mid-jump or mid-knockback stores the last safe
  ground point.
- **On a trail** (`RegionIndex` reports a trail zone): `resume` is omitted, and `entry` becomes the current map's
  portal at that trail's start.

Saving is allowed only when `MapSession.can_save()`, which means state `IDLE` and the player alive. Autosave runs on
every commit once `IDLE` is reached.

**Load** is a `transition(via = load)` whose arrival comes from this fallback chain (from A):

1. **`resume`.** `world = frame * local_pos` is accepted only if all of these hold:
   - `region_of(world)` is the saved map;
   - a ray from 1 m above to 3 m below hits `walkable`;
   - a capsule shape cast at the hit point + 0.05 m is clear;
   - the point is not inside any portal trigger, except the trigger of the saved `entry` portal: the load arrives
     through that portal and disarms it as a real arrival does, and crossing a trail's far gate leaves the player
     inside it (G1; `IslandWorld.validate_resume`).

   Before that validation, a saved `map_content_hash` that differs from the map's current one (the map chunk's
   collision plus every shared world chunk overlapping its region, `MapDefinitions.resume_hash`) skips this step:
   the point was vetted against geometry that changed (`ArrivalResolver.stale_resume`). Without both hashes only the
   validation applies.
2. **`entry`**: that portal's `spawn_transform`, or the spawn point.
3. **`player_spawns[0]`** of `map_id`.
4. **Unknown map id:** use 000000001 `player_spawns[0]` and log an error.

`respawn_reference` is saved because the brief requires it. On load it is recomputed from canonical `returnMap`.
If the two differ, canonical wins and the mismatch is logged.

### 4.10 Export chunking (the contract that `blender_export.md` implements)

> **Decision (2026-10-04, after the M0 measurements): M1 builds on the exporter as it exists.** The Phase 1
> exporter (`blender_export.md`) already ships everything warp mode needs: per-map visual and collision glbs, and a
> sidecar per chunk with portals, NPC markers, player starts, spawn areas, climbables, routes, cameras and
> footprints. So for M1 and M2:
>
> - Files stay keyed by **Blender slug** in `game/assets/world/` (`<slug>.glb`, `<slug>.collision.glb`,
>   `<slug>.json`). The runtime maps slug ↔ MeowDB id through `map_id_crosswalk.json`.
> - The **sidecar `<slug>.json` is the gameplay-marker authority** (what this section calls `markers.json`).
> - Collision comes from the `-colonly` / `-convcolonly` nodes in `.collision.glb`, or the runtime builds shapes
>   from those meshes. The `walkable__` / `blocking__` naming below is not required.
> - `export/` subfolder, `instances.json` + MultiMesh, trail chunks and the 128 m scenery grid are **deferred**.
>   The perf gate (§4.12) passed with plain instanced nodes, so they are only needed if Victoria-scale streaming or
>   a later measurement demands them.
> - Exporter changes are additive: new sidecar fields are fine; renaming or removing fields needs a runtime change in
>   the same pass.
>
> The original contract text follows for reference.

`scripts/export_runtime.py` runs headless Blender on `MapleIsland.blend`. Its output goes to
`game/assets/world/export/`. Coordinates are Godot world space: Y-up meters, `godot = (x, z, −y)`, with no
re-origin.

| Chunk | Contents | Files |
|---|---|---|
| `map:<id>` | `MAPS/<slug>/*`, `Plinth_<slug>_*` (top within footprint + 1 m), `<slug>_Collision`; portal, NPC, monster and route objects **as markers only** (proxies are not exported as geometry) | `<id>.visual.glb`, `<id>.collision.glb`, `<id>.instances.json`, `<id>.markers.json` |
| `trail:<trail_id>` | `World_Trails` objects of that trail, plus its dressing | `.visual.glb`, `.collision.glb`, `.instances.json` |
| `scenery:<i>_<j>` | island body, scenery, forest, sky and sea, on a 128 m grid by bounding-box centre; meshes larger than one cell are bisected into cells on a temporary copy | `.visual.glb`, `.instances.json` (no collision) |
| `kit` | one glb per instanced kit asset (`Rock_Cliff_Stone`, trees, clouds …) | `kit/<asset>.glb` |
| world | `maple_island.json`: chunk list with content hashes and `world_space`; map frames; trails (endpoints, centreline, zone polygon, `one_way`, `hidden`, ledge); `layout_hash` | one file |

Rules:

- **Ownership (A).** Every exported object belongs to exactly one chunk. The exporter asserts this, fails on any
  unowned or double-owned object, and prints per-chunk counts diffed against `build_report.json`.
- **Visual.** Non-instanced meshes are merged by material per chunk on a temporary copy. Collection instances are
  written to `instances.json` as `{asset: [transforms]}` and become one `MultiMeshInstance3D` per (chunk, asset)
  (B). Godot's `EXT_mesh_gpu_instancing` import is not relied on.
- **Collision** uses three classes, recorded as mesh-name prefixes in `collision.glb`:
  - **`walkable__`:** terrace caps and bodies, ramps, **stairs exported as one inclined ramp per flight** (B), bridges,
    decks, `<slug>_Collision`, and the plinth top within the footprint + 1 m. The exporter fails if a stair ramp is
    steeper than `floor_max_angle − 2°`.
  - **`blocking__`:** architecture hulls or boxes, fences (one box per segment), large rocks, and tree trunks (as
    cylinders in `instances.json`).
  - **None:** grass, flowers, small stones, mushrooms, canopies and clutter, decided by a **passable-tag
    registry**, not by name words (DEFERRED.md code debt).
- **`markers.json` is authoritative for gameplay** (A). The glTF files carry geometry only. Markers hold:
  - `content_hash`, `frame`, `footprint`, `base_y`, `kill_y`;
  - `camera {ortho_size from GAMEPLAY_SCALE, focus_local}`;
  - `portals [{name, kind, xform, anchor_normal}]`;
  - `arrival_points`, and `player_spawns` mapped from MeowDB px by `WorldScale` with `[0]` authored;
  - `npc_anchors [{name, xform}]`;
  - `spawn_regions [{name, tiers, polygon}]`;
  - `climbables [{name, kind, bottom, top, descend_only}]`;
  - `routes [{name, points, climb_segments}]`;
  - `ledges`.
- **The assembler** (`game/tools/assemble_world.gd`, headless Godot) builds `maple_island.scn` and per-chunk
  `chunks/*.scn` and joins canonical data into `world_index.json`:
  - portal resolution and gates;
  - spawn slots;
  - NPC placements matched by name, where a missing marker for a MeowDB NPC is an **error**;
  - containment walls and plugs;
  - region polygons and camera bounds.

  It builds collision shapes **directly from the collision meshes** (`ConcavePolygonShape3D` for `walkable__`,
  convex or box shapes for `blocking__`). It does not depend on importer name suffixes. Any L0 or L1 failure
  (section 4.13) fails the assembly.
- `scripts/build_runtime.sh` runs export, assembly and then `scripts/test.sh` in one command.

### 4.11 Camera bounds

- **Projection.** Iteration One's orthographic camera, pitched 40° down and looking toward world +X+Y, with a fixed
  orientation. The ortho size per map comes from `markers.camera.ortho_size` (the map module's `GAMEPLAY_SCALE`)
  times `camera.ortho_size_scale` from the map's adaptation file.
- **Bounds polygon** = the current map's footprint (+1 m) ∪ the zones of every trail touching the map. Interiors
  use the room box.
- **Clamp.** Project the bounds polygon onto the camera's right axis and its ground-projected forward axis to get
  an AABB in camera-plane coordinates. Clamp the follow focus so the view rectangle stays inside that AABB plus a
  6 m overscan, in the spirit of classic VR bounds while still showing island context. On any axis where the
  expanded AABB is smaller than the view, centre the focus on that axis.
- **Follow.** A dead zone of 0.15 × the view size. Vertical follow tracks `SafeGround` height, smoothed, so jumps
  do not bob the camera.
- **On commit.** Bounds and ortho size blend over 0.35 s for a gate, which is a small shift because the player is
  already at the seam. Warps snap.
- **Occlusion (B).** Objects tagged `occluder` on a camera-to-player ray dither out.
- **On trails.** The HUD shows the current map name with a subtitle "→ <destination map name>" (B's road line,
  presentation only). Built: `MisoHud` on `MapSession.trail_changed`, drawn with an ASCII "-> " because the HUD font
  has no arrow glyph (UI.md "Decisions and adaptations").

### 4.12 Streaming and performance

> **M0 perf gate result (2026-10-04): PASS with `AllResident`.** `game/tools/perf_probe.tscn` loaded all 31
> visual chunks (18,171 nodes) in 0.72 s and measured, at 1920×1080 on the RTX 4070 dev machine with sun shadows on:
>
> | View | Frame (ms) | Draw calls | Primitives |
> |---|---|---|---|
> | 000001000 The Field West of Amherst, gameplay | 3.27 | 3,802 | 1.81 M |
> | 000000060 Southperry, gameplay | 3.30 | 4,338 | 1.51 M |
> | 000000050 A Split Road, gameplay | 2.56 | 3,189 | 1.38 M |
> | 000001010 Amherst, gameplay | 3.50 | 4,324 | 1.83 M |
> | 000000041 Snail Hunting Ground II, gameplay | 1.98 | 2,428 | 1.12 M |
> | island overview (3.2× zoomed out) | 11.59 | 13,133 | 6.44 M |
>
> Every gameplay view runs well over 60 fps. Draw calls exceed the 3k target but cost little, because Godot's Forward+
> batches by material and the shadow passes dominate the count. **Measurement caveat:** run the probe with
> `--disable-vsync`. A background window's vsync presentation is throttled by the OS to about 4 fps, which first
> made the gate look like a catastrophic CPU stall (265 ms "process" per frame even with an empty scene).

- **Default policy: `AllResident`.** Everything loads at start, behind a loading screen, with a target of 10 s or
  less.
- **Performance gate (milestone M0)** is a scripted flythrough of the worst gameplay views: 000001000, 000000060,
  000000050 and 000001010, plus an island overview. Targets on the dev machine, an RTX 4070 at 1080p:
  - 60 fps with at most 11 ms GPU frame time (30% headroom);
  - at most 2 M triangles and 3 k draw calls in view.
- Tools for meeting the gate:
  - MultiMesh per (chunk, asset), and material merging;
  - ortho frustum culling, with per-chunk AABBs and the 128 m scenery grid;
  - import LODs on kit assets;
  - replacing the inverted-hull outline shells with a `next_pass` outline material, which halves the exported
    triangles.
- **Fallback policy: `GraphRadius`**, behind the `WorldResidency.set_focus(map_id)` interface:
  - visuals for maps within link distance 2 of `current_map`, plus scenery cells in the frustum;
  - collision for the current map, its trails and its direct neighbours.

  Gameplay code reads only `current_map` and `MapDefinition`, so switching policy changes no gameplay code.
  Victoria uses this policy.
- **Physics.** One Jolt space with static concave shapes for the island, plus the interior stage. Monster count is
  bounded by the live map (at most 49).

### 4.13 Traversal validation strategy

Every layer writes into `docs/runtime/traversal_report.json`, regenerated by the tools and committed at milestones.

> **Status (2026-10-04, milestone M2).** `game/tools/traversal_bot.tscn` (`--fixed-fps 60`) writes into
> `traversal_report.json`: the L1 build (0 errors, 0 warnings), the L2 per-map route runs (25 maps, 360 runs,
> 0 failures), the L2 per-link runs (every edge-mode trail walked in each allowed direction with the exact
> `map_left → map_entered → portal_used` sequence through the gate, every link pressed in warp mode, walk/press-Up
> equivalence, 40 → 30 blocked by the ledge for 10 s of jump spam: 87 runs, 0 failures, `trails_walkable` 20 of 20
> with no warp override) and the L3 tour in edge mode and in warp mode (38 legs each, 0 fall recoveries, 0 stalls,
> 0 invariant violations). The 000001012 ↔ 000001014 trail, kept warp until the Blender round-3 re-route, is walked
> both ways; `portal_adaptations.json link_modes.overrides` is empty (WORLD_RUNTIME.md "Source world status").
> Result caching is not built. The press-Up, door, death, load, save and containment checks run in
> `world_checks.tscn` (WORLD_RUNTIME.md "Testing"). The flood fill became the **stuck-region scan** in Iteration
> Three (L1 below, [`STUCK_SCAN.md`](STUCK_SCAN.md)): `game/tools/stuck_scan_tool.tscn` writes
> `docs/runtime/stuck_report.json`, and `tests/unit/test_stuck_scan.gd` fails on any confirmed trap that
> `data/misostory/stuck_allowlist.json` does not list.

**L0 – data and graph checks** (pure GDScript in `game/tests/unit/test_map_graph.gd` and
`game/tools/validate_data.gd`, no physics):

- The crosswalk has 25 rows and is bijective. Every id has canonical data, a markers file and a chunk.
- Every MeowDB portal has exactly one `PortalDef`. Every non-canonical `PortalDef` (arrival gates) has an
  adaptation entry with a reason.
- Destination resolution is unique per portal and agrees with the v8 `to_portal` names.
- The directed graph (walk and warp edges) equals MeowDB's directed graph plus the listed adaptations.
- BFS from 000000001 reaches all 25 maps. The SCC report allowlists the canonical one-way 30 → 40 (1, 10, 20, 21, 30
  form a source component), and every map reaches its `returnMap`.
- Spawn parity: the per-map, per-species slot counts equal MeowDB's, and the capacity table equals Appendix B.
- NPC parity: every MeowDB NPC has an anchor, and no runtime NPC lacks a MeowDB entry.
- `SpawnModel` unit tests use MeowDB's worked numbers: a 50-point map caps at 37 solo, a wave point respawns at the
  first 7.56 s boundary at or after death + 5 s, and `mobRate` is ignored.
- The 30 → 40 ledge invariant (section 4.4).

**L1 – static geometry** (headless Godot inside the assembler, physics queries only):

- Every portal `spawn_transform`, `player_spawns[0]`, NPC anchor and spawn slot is raycast-grounded on `walkable`
  within 0.3 m, capsule-clear, inside its **own** map's inset (B), and outside every other trigger.
- The containment rings are closed except at the gate gaps. Every gap aligns with a gate plane at footprint + 1 m,
  no wall segment crosses an Iteration One route polyline (2D segment test), and the one-way ledge face lies on
  its arrival gate plane within ±0.1 m.
- **Stuck-region scan (B)** (built in Iteration Three as `StuckScan`, `game/tools/stuck_scan.gd`; the method, its
  limits and the per-map results are in [`STUCK_SCAN.md`](STUCK_SCAN.md)). Per map, over its region and the zones
  of its trails, it samples every surface the feet can stand on in 0.35 m columns (repeated rays on the player's
  mask for stacked floors; floor angle, a clear body capsule, and not buried inside a closed solid). Its edges use
  the controller's own numbers (`MovementModel`):
  - walks to the first surface within `step_up_m` above and `snap_down_m` below the feet (8 neighbours);
  - drops off an edge onto the first surface below, swept with the body capsule (longer drops, slides down a wall
    and running jumps are kept for the forward search only, each as far as the walk speed over its air time carries
    the body: a jump off a high ledge reaches several metres);
  - ladders, ropes and vines along their whole grab band;
  - running jumps along a capsule-swept arc, at most `jump_apex + step_up_m - 0.2 m` high (computed for flagged
    nodes only).

  Forward reachability runs from every player spawn, portal arrival and authored route point; backward
  reachability from the press-Up triggers and the far gates of the map's trails. A node reached but not able to
  get back is flagged; flagged components are then verified with the real `PlayerController` on the same
  collision (CLEARED, CONFIRMED or UNENTERABLE). `tests/unit/test_stuck_scan.gd` fails on a CONFIRMED one that
  `data/misostory/stuck_allowlist.json` `entries` does not list, on an UNENTERABLE one its reviewed `unenterable`
  list does not hold, and on escapable ground outside every map region and trail zone (the main traversal graph
  must stay inside the regions; the Iteration Three review found 000001006's dell open under its out00 bridge).
  Not built from the original plan: the assertion that no sample in 000000030's region is reachable from
  000000040's (the L2 link runs still prove 40 → 30 blocked); the scan samples the ground inside the regions and
  trail zones only.
- **The band inside the ring** (Blender side, `scripts/validate.py` check `ring_band`): along every exterior
  map's ring line inset by the body radius, the walkable ground lies within `step_up_m` of the map's base
  (gate corridors and rim edges skipped). It guards the corner-slot class the scan found in Iteration Three
  (the plinth's rounded top left 2.3-2.6 m deep slots inside the ring's square corners). It measures against the
  base height only, so a slot inside the ring above the base (000001021's behind its west hedges, 1.2 m up) is the
  scan's to find.

**L2 – bot runs with the real player** (`game/tools/traversal_bot.gd`, run as
`bash scripts/godot.sh --headless --fixed-fps 60 --path game res://tools/traversal_bot.tscn -- --map <id>`):

- **Setup.** The player controller reads intent from an `InputSource`, which is the keyboard in play and the bot in
  tests. The bot therefore drives the identical `CharacterBody3D` with identical parameters. It steers by pure
  pursuit with 1 m lookahead along the exported route polylines and trail centrelines, jumps where the next sample
  rises more than `step_up_m`, and climbs on `climb_segments`.
- **Failures.** Any of these fails the run:
  - no progress along the arc length for 2 s (stall);
  - any fall recovery;
  - leaving `kill_y`;
  - a `RegionIndex` invariant violation;
  - an unexpected `map_left` → `map_entered` → `portal_used` sequence.

  Every failure reports its position.
- **Per map.** Every route, in both directions. Results are cached by `hash(map content_hash, movement.json, player
  controller sources)` (A).
- **Per link, walk.** Every trail, in each allowed direction, asserting the exact event sequence
  `map_left → map_entered → portal_used`.
  - **40 → 30 must fail.** The bot walks to the ledge and spams jump for 10 s. The test asserts that
    `current_map` stays 000000040 and that the player never enters 000000030's region.
  - The Field East hidden lane is walked like any other trail.
- **Per portal, press Up** (47 portals, A). Assert:
  - `current_map`;
  - `last_arrival`;
  - arrival within ±0.1 m of the destination `spawn_transform`;
  - `is_on_floor()` within 10 frames;
  - no re-trigger in the next 2 s while Up is held;
  - transition time against its budget.
- **Equivalence.** For each edge link, walk and press Up from the same start and compare logical state
  (section 4.4).
- **Doors.** In and out, for all 4 interiors.
- **Death.** In 000000040, 000001014, 000000021 and 000001011, kill the player and assert the returnMap and
  spawn point.
- **Save round-trip.** A round-trip at `player_spawns[0]` of every map, plus one mid-trail save and one saved
  mid-jump.

**L3 – the Test A tour** (an automated run of the brief's Test A). One continuous bot session from a new game at
000000001 `sp0`:

```
1 → 10 → 20 → 21 → 20 → 30 → 40 → 41 → 42 → 50 → 60 → 61 → 60 → 50 → 1000
  → (1001, 1002, 1003, 1004, 1005, 1006: each out and back)
  → 1010 → 1011 → 1010 → 1013 → 1010 → 1012 → 1014 → 1012 → 1010 → 1020 → 1021 → 1020
```

The tour walks every trail it uses and enters every door, visiting all 25 maps. A second pass runs the same order
with press-Up only and must also pass in `force_link_mode: warp`, which proves the fallback. The tour always runs
before a milestone and is never served from the cache.

**L4 – the human playthrough.** Test A by hand, from a checklist generated from Appendix A (every portal in each
allowed direction), recorded in the playthrough validation report.

The Blender gates stay in force: `traversal.py`, `trail_walk` (it gains a one-way expectation for 30 → 40), and
`PLAYER_IN_FRAME`.

### 4.14 Debug tool hooks

| Tool | Hook |
|---|---|
| teleport to map or portal | `MapSession.debug_warp(map_id, portal_id)` |
| show current map, region, state and last transition | overlay reading `MapSession` and `RegionIndex` |
| show collision, containment, gates, portal data, spawn regions and slots, region polygons, camera bounds | `DebugDraw` layers fed by `world_index.json` |
| reload map | `MapInstanceView.release()`, then `MapInstanceState.fresh()`, then `realize()` |
| toggle a link's mode | `PortalGraph.set_link_mode(link, mode)`, where `mode` is `edge` or `warp` |
| spawn or kill a monster | debug spawns are flagged non-canonical and never occupy a slot |

### 4.15 Victoria Island and Iteration Three

- **Iteration Three content** (all of Maple Island) needed only data on the map side, as planned: canonical maps,
  NPC and monster records, and spawn regions. As built, the map model gained the Wooden Box placements in
  `MapInstanceState` (above), spawn exclusions and clearances (§4.7.1 "As built"), a ground query for the minimap
  (`IslandWorld.ground_faces`), and the L1 flood fill as the stuck-region scan (§4.13); the rest of Iteration Three
  (drops, skills, chairs, quests, the minimap) lives in other systems.
- **Victoria** adds `world_space` values per continent. Links are `edge` only where a continuous geography is
  authored. Dungeons, towers, the subway and multi-portal pairs are `warp` links to pocket stages, like the
  interiors.
- **The Southperry ship** to Lith Harbor is a `door`-kind warp between world spaces, behind a loading screen.
- **Residency** switches to `GraphRadius`. Each world space has its own origin, and float32 holds sub-millimetre
  precision at 3 km.
- **Per-map authoritative instances** follow MapleStory's server model, so parties later need no rework. The
  `PlayerScalar` input to capacity already exists.

## 5. Source-world changes required (Critical Rule)

| # | Change | Where |
|---|---|---|
| 1 | Remove `(10000, in00)`, `(20000, in00)` and `(30000, in00)` from `ONE_WAY`, so they render as ordinary exit portals. `(40000, in00)` becomes an arrival marker with no portal object. | `src/misostory/layout.py`, `mapkit.py` |
| 2 | One-way trails: the 30000 out00 → 40000 trail ends in a 2.4 m ledge whose face lies on 40's arrival gate plane (footprint + 1 m, section 4.4), with a rock face that reads as a drop-down. `trail_walk` checks forward ok and reverse blocked. | `src/misostory/trails.py`, `traversal.py` |
| 3 | NPC parity per section 3.3: add Todd (30000), Sam (40000) and Mai (50000); remove Tia, Maple Administrator and Paul (60000) and Mai (1010000). | `src/misostory/npcs.py`, map modules |
| 4 | `m.spawn_region(name, polygon, tiers)` on the 15 maps with spawns (000000030 and the 14 hunting and field maps). Remove `m.mobs` proxies from export, keeping them as optional debug visuals. | `mapkit.py`, map modules |
| 5 | Author `player_spawns[0]` per map near the MeowDB `sp` position: the 40000 arrival landing, and interiors at the door. | map modules |
| 6 | A passable-tag registry, so collision classes stop depending on name words. | kit |
| 7 | Edge dressing where containment walls feel invisible. Tighten the longest trails (61, 50.3 and 42.2 m) through layout gaps if the World Review flags them; at walk speed (150 px/s ≈ 3 m/s) the 61 m trail takes about 20 s. | map modules, `layout.py` |

## 6. Implementation order

| Milestone | Delivers | Exit criteria |
|---|---|---|
| **M0 Pipeline** | `export_runtime.py`, `assemble_world.gd`, `build_runtime.sh`, crosswalk, canonical maps, L0 and L1 checks, perf flythrough | all 25 maps load in one scene; L0 and L1 green; perf gate measured. On failure, adopt `GraphRadius` before M1. |
| **M1 Playable in warp mode** | `MapSession`, `PortalGraph`, `portal.tscn`, doors, `force_link_mode: warp`, closed containment, `SafeGround`, spawns and instances, death and respawn, save location, camera bounds | per-portal, door, death and save L2 tests green; the L3 tour green in warp mode. **This is Option A's playable result, and Test A is unblocked here.** |
| **M2 Walkable island** | gates, `GateMonitor`, gate gaps and plugs, trail walls, `RegionIndex` invariant, Blender changes 1–2, flood fill, trail bot runs, equivalence tests, trail HUD line | full L1–L3 green in edge mode, including 40 → 30 failing; `force_link_mode: warp` still green. **Status 2026-10-04:** runtime done (gates, plugs, walls, invariant, `MapSession.trail_changed`); L1, L2 links and the L3 tour green in edge and warp mode with all 20 trails walkable (000001012 ↔ 000001014 since the Blender round-3 re-route, no `link_modes.overrides`); the trail HUD line shows: `MisoHud` listens to `trail_changed` and holds "-> <destination map name>" under the map name while the player is on a trail (WORLD_RUNTIME.md "Region index and the identity invariant", UI.md); flood fill not built (Iteration Three built it as the stuck-region scan, STUCK_SCAN.md) |
| **M3 Feel** | ambient neighbours (flag), occluder dithering, environment presets, World Review changes (Blender 7) | the playthrough report signs off on movement, camera and the World Review |

## 7. Open questions

1. **Respawn spawn point.** MeowDB lists up to 11 `playerSpawns` per map but does not say which one death or a
   spawn-arrival uses. We use index 0 until a MeowDB page settles it (`death.json respawn_player_spawn_index`).
2. **Drop ground lifetime** and owner-only pickup timing are not in MeowDB. They are adaptation values marked
   unverified (`drops.json`).
3. **`fieldLimit` bits.** The value is 4 on 000000060, 000000061, 000001010, 000001011 and 000001012. It is carried
   raw and not interpreted until a MeowDB page documents the bits.
4. **Spawn model verification.** MeowDB flags its player-count curve and the tick-under-load behaviour as
   unverified. Solo play uses only the 75% point. Re-check the page at each milestone; it was last updated
   2026-08-24.
5. **Hidden portal UX.** Type 1 gets no swirl and no prompt. Confirm in playtest that players find the Tomato Field
   lane; the hedge lane is the in-world hint. The Iteration Three minimap leaves the portal off too (as classic
   minimaps do); whether to show it is an open owner decision (DEFERRED.md).
6. **First fill.** A fresh instance fills to capacity immediately, rather than waiting for the first 7.56 s tick.
   This matches classic feel but is not stated by MeowDB.
7. **Walk-through gates** are an adaptation, since every MeowDB portal is press-Up. Keep them on by default and
   revisit if playtests show accidental map changes.
8. **Ambient neighbours.** Ship on or off? Decided at the M3 World Review.
9. **Trail lengths.** Tighten the 61, 50.3 and 42.2 m trails in `layout.py`? World Review, after the M2 playtest.
10. **Mushroom Town knoll** (DEFERRED.md). It is compatible: maps 000000001, 000000010 and 000000020 keep separate
    footprints, and their lanes become short trails with gates. Confirm the 1.5 m footprint margin still holds.
11. **Amherst `in01` ↔ Townstreet `out00`.** Keep the 5 m stair trail as an edge, or render it as one door-style
    marker (DEFERRED.md)? Both work with this design; this is a feel call.
12. **Perf gate outcome.** It decides `AllResident` versus `GraphRadius` for Iteration Two. Only `WorldResidency`
    changes either way.

---

## Appendix A: Maple Island links (MeowDB)

| # | End A (map.portal) | End B (map.portal) | Kind | Trail (m) | Notes |
|---|---|---|---|---|---|
| 1 | 000000001.out00 | 000000010.in00 | edge | 10.1 | Iteration One renders `in00` as arrival-only; fix (section 5, item 1) |
| 2 | 000000010.out00 | 000000020.in00 | edge | 14.1 | same |
| 3 | 000000020.out00 | 000000030.in00 | edge | 10.0 | same |
| 4 | 000000020.in01 | 000000021.out00 | door | – | |
| 5 | 000000030.out00 | 000000040 `arrival:` | edge | 28.0 | **one-way** 30 → 40; destination is `playerSpawns[0]`; 2.4 m ledge |
| 6 | 000000040.east00 | 000000041.west00 | edge | 12.0 | |
| 7 | 000000041.east00 | 000000042.west00 | edge | 18.2 | |
| 8 | 000000042.east00 | 000000050.west00 | edge | 30.0 | |
| 9 | 000000050.east01 | 000000060.west00 | edge | 37.5 | |
| 10 | 000000050.east00 | 000001000.west00 | edge | 12.5 | |
| 11 | 000000060.in00 | 000000061.out00 | door | – | |
| 12 | 000001000.in00 | 000001001.out00 | edge | 18.1 | |
| 13 | 000001000.in04 | 000001005.out00 | edge | 10.6 | |
| 14 | 000001000.in01 | 000001002.out01 | edge | 12.0 | |
| 15 | 000001000.in05 | 000001006.out00 | edge | 61.0 | longest trail; 8 m bridge end |
| 16 | 000001000.in02 | 000001003.out00 | edge | 24.5 | |
| 17 | 000001000.in03 | 000001004.out00 | edge | 50.3 | |
| 18 | 000001000.east00 | 000001010.west00 | edge | 12.1 | |
| 19 | 000001010.in01 | 000001012.out00 | edge | 5.0 | gates 3.4 m apart |
| 20 | 000001010.east00 | 000001020.west00 | edge | 18.4 | |
| 21 | 000001010.in00 | 000001011.out00 | door | – | |
| 22 | 000001010.in02 | 000001013.out00 | door | – | |
| 23 | 000001012.west00 | 000001014.east00 | edge | 42.2 | |
| 24 | 000001020.in00 | 000001021.out00 | edge | 20.7 | `in00` is **type 1 (hidden)**; hedge lane |

That makes 47 MeowDB portals, 40 gates (39 portal gates plus 1 arrival gate) and 8 door portals.

## Appendix B: crosswalk and spawn capacity

| MeowDB id | v8 id | Blender slug | Name | isTown | returnMap | Spawn points | Solo cap |
|---|---|---|---|---|---|---|---|
| 000000001 | 0 | WestEntranceMushroomTown_0 | Mushroom Town - West Entrance | yes | 000000001 | 0 | 0 |
| 000000010 | 10000 | MushroomTown_10000 | Mushroom Town | yes | 000000010 | 0 | 0 |
| 000000020 | 20000 | MushroomTown_20000 | Mushroom Town | yes | 000000020 | 0 | 0 |
| 000000021 | 20001 | MushroomTownTownstreet_20001 | Mushroom Town Townstreet | yes | 000000021 | 0 | 0 |
| 000000030 | 30000 | EastEntranceMushroomTown_30000 | East Entrance to Mushroom Town | yes | 000000030 | 6 | 4 |
| 000000040 | 40000 | SnailHuntingGround1_40000 | Snail Hunting Ground I | no | 000000060 | 40 | 30 |
| 000000041 | 40001 | SnailHuntingGround2_40001 | Snail Hunting Ground II | no | 000000060 | 45 | 33 |
| 000000042 | 40002 | SnailHuntingGround3_40002 | Snail Hunting Ground III | no | 000000060 | 42 | 31 |
| 000000050 | 50000 | ASplitRoad_50000 | A Split Road | no | 000000060 | 42 | 31 |
| 000000060 | 60000 | Southperry_60000 | Southperry | yes | 000000060 | 0 | 0 |
| 000000061 | 60001 | SouthperryArmorStore_60001 | Southperry Armor Store | yes | 000000060 | 0 | 0 |
| 000001000 | 1000000 | FieldWestOfAmherst_1000000 | The Field West of Amherst | no | 000001010 | 66 | 49 |
| 000001001 | 1000001 | InASmallForest_1000001 | In a Small Forest | no | 000001010 | 40 | 30 |
| 000001002 | 1000002 | DangerousForest_1000002 | Dangerous Forest | no | 000001010 | 34 | 25 |
| 000001003 | 1000003 | MushroomGarden_1000003 | Mushroom Garden | no | 000001010 | 35 | 26 |
| 000001004 | 1000004 | SnailGarden_1000004 | Snail Garden | no | 000001010 | 41 | 30 |
| 000001005 | 1000005 | HuntingGroundMidForest1_1000005 | Hunting Ground Middle of the Forest I | no | 000001010 | 44 | 33 |
| 000001006 | 1000006 | HuntingGroundMidForest2_1000006 | Hunting Ground Middle of the Forest II | no | 000001010 | 45 | 33 |
| 000001010 | 1010000 | Amherst_1010000 | Amherst | yes | 000001010 | 0 | 0 |
| 000001011 | 1010001 | AmherstWeaponStore_1010001 | Amherst Weapon Store | yes | 000001010 | 0 | 0 |
| 000001012 | 1010002 | AmherstTownstreet_1010002 | Amherst Townstreet | yes | 000001010 | 0 | 0 |
| 000001013 | 1010003 | AmherstDepartmentStore_1010003 | Amherst Department Store | yes | 000001010 | 0 | 0 |
| 000001014 | 1010004 | SnailFieldOfFlowers_1010004 | Snail Field of Flowers | no | 000001010 | 34 | 25 |
| 000001020 | 1020000 | FieldEastOfAmherst_1020000 | The Field East of Amherst | no | 000001010 | 38 | 28 |
| 000001021 | 1020001 | TomatoField_1020001 | Tomato Field | no | 000001010 | 25 | 18 |
| **total** | | | | | | **577** | **426** |
