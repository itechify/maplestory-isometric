# World runtime (Iteration Two, milestone M2: walkable island)

This is the runtime side of [`MAP_ARCHITECTURE.md`](MAP_ARCHITECTURE.md): the island loaded in Godot, the 25 MeowDB
maps as gameplay instances, portals, `MapSession`, spawns, NPC placement, containment, fall recovery and, since
milestone **M2**, the walkable trails. Players walk from map to map along Iteration One's 20 trails, or press Up at
any portal. There is always exactly one current map: a walk changes it only at a **gate** (MAP_ARCHITECTURE §4.4),
through the same `MapSession.transition()` a press-Up uses. Flood fill (L1), ambient neighbours and occluder
dithering are not built; their seams are listed at the end.

## Files

| Path | What |
|---|---|
| `game/scripts/autoload/map_session.gd` | `MapSession` autoload: `current_map`, the state machine, `transition()`, death/respawn, load, the save location, the trail under the player (`trail_changed`) |
| `game/scripts/core/maps/` | pure rules (no scene tree): `MapDefinitions` (the join), `MapDefinition`, `PortalDef`, `PortalGraph`, `ArrivalRef`, `TransitionRequest`, `TransitionRecord`, `ArrivalResolver`, `SpawnModel`, `SpawnSlot`, `SpawnSlotPlanner`, `MapInstanceState`, `MapStateCache`, `NpcPlacement`, `RegionIndex`, `GroundQuery`, `WorldSidecars`, `WorldTuning`; M2: `TrailDef` (a trail: ends, ribbon, zone), `GateDef` (a gate and its arm/commit rule), `TrailGeometry` (the ribbon from the trail mesh) |
| `game/scripts/world/` | scene side: `IslandWorld`, `WorldLayers`, `PhysicsGroundQuery`, `ProxyLibrary`, `ContainmentBuilder` (rings, gaps, plugs, trail walls), `WorldPortal`, `WorldNpc`, `MapInstanceView`, `PortalInteractor`, `FallRecovery`, `ScreenFader`, `WorldTestPlayer` (tests only), `world_preview.gd`, `checks/world_checks.gd`; M2: `TrailLoader` (reads the trail meshes), `GateMonitor` (gate commits), `RegionMonitor` (the identity invariant, the trail HUD line) |
| `game/scenes/world/` | `world.tscn` (what the game composes), `portal.tscn`, `world_preview.tscn` (developer preview), `checks/world_checks.tscn` (L2 checks) |
| `game/data/misostory/portal_adaptations.json` | portal adaptations: link modes (`force_link_mode`, defaults, per-link overrides), destination overrides, the arrival gate, gate sizes, trigger size, arrival inset, hidden types |
| `game/data/misostory/presentation.json` | world feel constants: fades, frame budgets, spawn-slot rules, grounding, containment, trails (walls, zones), the region invariant, fall recovery, NPC talk range |
| `game/data/misostory/death.json` | the world runtime reads only `respawn_player_spawn_index` (the rest is the game shell's death adaptation) |
| `game/data/misostory/maps/<id>.json` | optional per-map overrides (`environment_preset`, `camera.ortho_size_scale`, `spawn_slot_overrides`, `spawn_keepouts`, `region_extensions`, `collision.double_sided_trimesh`); `000000030.json` keeps spawn slots out from under the yellow house's cap; `000000060.json` brings Southperry's moored ship into the map's region and ring and makes its collision double-sided |
| `game/tools/traversal_bot.gd` | `TraversalBot`: L2 per-map route runs (every route of every map, both ways) |
| `game/tools/traversal_walker.gd`, `traversal_paths.gd`, `traversal_nav.gd` | the traversal bot in the real world: `TraversalWalker` (IslandWorld + the game's PlayerController + BotInput + the MapSession autoload, on real physics frames), `TraversalPaths` (resampling, stepping around props), `TraversalNav` (in-map paths over the map's routes) |
| `game/tools/traversal_trails.gd`, `traversal_tour.gd` | `TraversalTrails` (L2 per link: walk, press-Up, equivalence, the 40 -> 30 ledge, the trails-walkable count), `TraversalTour` (L3: the Test A tour in edge and in warp mode) |
| `game/tools/traversal_bot_tool.gd`, `traversal_bot.tscn` | the headless runner that writes `docs/runtime/traversal_report.json` |
| `game/tools/traversal_shots.gd`, `traversal_shots.tscn` | windowed screenshots of the real game walking a trail across a gate and down the one-way ledge |
| `docs/runtime/traversal_report.json` | the last traversal run: L1 build, L2 routes, L2 links, L3 tour (edge and warp), every trail's ribbon |

## Data flow

```
data/canonical/maps/<id>.json ─┐  WHAT: portals + toMapId, spawns[] (species, index), npcs[], playerSpawns count,
data/misostory/map_id_crosswalk ┤        returnMap, bgm, isTown, fieldLimit
assets/world/<slug>.json ───────┤  WHERE: portal anchors + normals, arrival_points, NPC markers, player_spawns /
assets/world/World_Trails.*  ───┤         player_start, spawn_regions / spawn_areas, footprint, frame, bounds, cameras,
data/misostory/*.json ──────────┘         trails[] (ends, meshes, the one-way ledge) + the trail meshes
          │  MapDefinitions.build()                         pure; works without the export (no geometry)
          ▼
   MapDefinitions ── PortalGraph (resolution, links, link modes, BFS/SCC) ── TrailDef + GateDef per trail link
          │  IslandWorld: load collision (+ visuals); TrailLoader: trail ribbons; ground_all(PhysicsGroundQuery);
          │  finish_trails(): kill_y and camera bounds with the trails; RegionIndex (maps + trail zones)
          ▼
   grounded arrivals, player spawns, NPCs, gates; SpawnSlotPlanner places 577 slots; rings with gaps, plugs, walls
          │
   MapSession.transition() ─► MapInstanceState (pure) ─► MapInstanceView (nodes), WorldPortal / WorldNpc enabling
          ▲                    ▲
   PortalInteractor (Up, F)   GateMonitor (walking across a gate)
```

`MapDefinitions.build(db, sidecars)` is the one place where canonical data and geometry are joined (the assembler's
job in MAP_ARCHITECTURE §4.10, done at load time: about 1 s headless including collision and the trail ribbons, so no
generated `world_index.json` is needed). MeowDB decides what exists and where it leads; the sidecar only places it.

## MapDefinition (per map)

`map_id`, `map_name`, `street_name`, `world_space` (`maple_island` or `interior_stage`, from the sidecar kind),
`portals` (MeowDB's, in MeowDB order, plus the arrival gate), `destination_maps`, `monster_spawn_definitions`
(`SpawnSlot`, index = MeowDB `spawns[]` index), `npc_definitions` (`NpcPlacement`, MeowDB ids), `player_spawns`
(size = MeowDB's count; `[0]` is the sidecar's authored `player_spawns[0]`, else `player_start`; unauthored indices
repeat `[0]`), `respawn_location` (`{returnMap, spawn_index 0}`), `environment_configuration` (`bgm`, `bgm_name`,
`is_town`, `safe_zone`, raw `field_limit`, raw `mob_rate`, `preset`, `ortho_size` = gameplay camera
`godot_size_keep_width` x `camera.ortho_size_scale`, `ortho_size_keep_height`, camera pitch/forward/xform), `frame`
(map-local to world, from `footprint.local_frame`), `footprint` (layout rectangle + 1 m, united with the map's
region extensions: the region edge and the ring line),
`camera_bounds` (§4.11: the footprint united with the zones of the edge-mode trails touching the map; recomputed
when a link mode changes), plus `footprint_base` (layout + 1 m without extensions), `region_extensions` (see
"Region extensions"), `slug`, `kill_y` (the lowest walkable point of the map **and its trails** minus 6 m),
`y_min`/`y_max`, `spawn_areas`, `mob_names`, `content_hash`.

## Portals and links

- **One `PortalDef` per MeowDB portal (47)** plus one adaptation arrival gate,
  `arrival:T_000000030_out00__000000040` (walk-only, no trigger node; it anchors on the sidecar `arrival_points`
  entry, or on the old `in00` portal marker). Fields follow MAP_ARCHITECTURE §4.4 (`portal_id`, `source_map_id`,
  `destination_map_id`, `destination_portal_id`, `destination_spawn_index`, `spawn_transform`, `portal_type`,
  `canonical_type`, `interaction_type`, `link_mode`, `trail_id`/`link_id`, `provenance`).
- **Resolution** (`PortalGraph.resolve_destinations`): an override in `portal_adaptations.json` (none), then the
  unique reciprocal (46 portals), then the destination's `playerSpawns[0]` (`000000030.out00`). Each result is
  checked against MeowDB's own reverse lookup and against Iteration One's v8 `to_portal` / `to_arrival` in the sidecar.
- **Links**: 24 (20 trail, 4 door; 1 one-way). A link is a door when a portal's sidecar marker is a door, so without
  the export every link is a trail.
- **Link modes** (§4.4). `force_link_mode` is `""`, so each link takes its override (`link_modes.overrides`), else
  `default_link_mode` by kind: trails `edge`, doors `warp` (doors are always warp). All 20 trails are `edge` and
  `link_modes.overrides` is empty: the 000001012 ↔ 000001014 trail was overridden to `warp` until the Blender round-3
  export re-routed it (see "Source world status"). An `edge`
  link's portals are `press_up_or_walk` and its gates commit; a `warp` link's portals are `press_up`, its gates are
  off and its plugs close the trail mouths. `force_link_mode: "warp"` is the M1 fallback (every link press-Up).
  - `PortalGraph.set_link_mode(link_id | "all", mode)` switches at runtime: `edge` on a trail link, `warp` on any;
    `edge` on a door link is `ERR_UNAVAILABLE`, an unknown link `ERR_DOES_NOT_EXIST`, a bad mode
    `ERR_INVALID_PARAMETER`; `"all"` + `edge` switches every trail link and leaves the doors warp. It emits
    `link_mode_changed(link_id, mode)` per actual change; the world re-applies plugs, gates and camera bounds.
  - `MapDefinitions.apply_configured_link_modes()` restores what the data says (a traversal run, a debug session).
  - The debug console reaches it through `linkmode warp|edge [link|all]` (the debug system's command) and
    `map_link_mode <link|all> <warp|edge>` (MapSession's).
  - Fixed in M2: M1 appended each link's ends and maps through an `as PackedStringArray` cast, which appends to a
    copy, so every link had empty `ends`/`maps` and `set_link_mode` never reached the portals (a typed local now).
- **Arrival transform**: the grounded anchor + `arrival.inset_m` (1.5 m) along `inward` (minus the sidecar's
  outward `anchor_normal_xz` for edges, the door marker's +Z facing for doors), facing inward, then grounded and
  settled (below).
- **Node** (`portal.tscn`, `WorldPortal`): an `Area3D` trigger 4.5 x 3 x 1.6 m (`portal_adaptations.json trigger`)
  centred on the grounded anchor with its depth along `inward`, on the interactables layer watching the player
  layer; the `Portal_Swirl` / `Portal_Door` visual from `_library.glb` at the anchor (Iteration One's
  `Portal_Arrival` markers on 10/20/30 `in00` become swirls, since MeowDB lists them as visible type 2); a
  `PromptAnchor` marker at the top. **Type 1** (`000001020.in00`) has no visual and `shows_prompt()` is false, but
  pressing Up works, and its hedge lane is walked like any trail.
- **Anti ping-pong**: the portal you arrive at is disarmed until the player has been outside its trigger.
- **Interaction** (`PortalInteractor`, physics priority 100, after the player): `portal_enter` (Up) fresh press
  inside an armed trigger of the current map, or `interact` (F) when that portal is
  `IslandWorld.nearest_interactable()`. Presses come from `player.input_source.just_pressed()` when the player has an
  `InputSource` (so the bot can press), else from `Input`. Pressing Up works on every portal in every mode.
- **Input gating.** A press counts only when MapSession is `IDLE` and `IslandWorld.player_input_block()` is `""`.
  It is `"dead"` when `player.is_dead()`, `"input off"` when `player.is_input_enabled()` (else the
  `input_enabled` property) is false, and `"modal"` while a modal is open (`IslandWorld.is_modal_active()`).
  `PortalInteractor.last_block` keeps the reason of the last ignored press. So a dialogue's Up arrow, the console's
  history keys and a death notice never warp.
  - **Modal source.** `is_modal_active()` asks `modal_provider` (a `() -> bool` Callable) when one is set. Else it
    asks the context given to `set_context(ctx)` (duck-typed `is_modal_active()`, the `GameContext`). Else, as a
    fallback, it asks the `ctx` property of the nearest ancestor that has one (`GameSession` owns the context and
    is the world's parent). With none of these, there is no modal.
  - **Hand-back.** `IslandWorld.set_player_input(true)`, which MapSession calls when a warp ends, is refused while a
    modal is open. Turning input off always goes through. The context turns input back on when its last modal
    closes (`GameContext.pop_modal`), so input comes back exactly once, at the right moment.
- **Query API for prompts**: `IslandWorld.portal_under_player()`, `nearest_interactable(pos) ->
  {kind: "portal"|"npc", node, id, distance}`, `portals_of(map_id)`, `portal_node(map_id, portal_id)`,
  `WorldPortal.shows_prompt()`, `.prompt_anchor`, signals `player_entered/player_exited(portal)`.

## Trails and gates (milestone M2)

- **`TrailDef`** (one per trail link, built by `MapDefinitions.build`): the link, its two ends in the sidecar's
  order (`maps`, `portal_keys`; the 000000040 end of the one-way trail is its arrival gate), `one_way`, `hidden`, the
  two gates, and the ribbon:
  - `centre`, `left`, `right`, `half_widths`: rows every 0.5 m from end 0 to end 1 (centreline, idealized edges,
    half-width);
  - `side_a`, `side_b`: the walkable top's own edges (the side walls follow them);
  - `zone_contains(p)`: within half-width + `trails.zone_margin_m` (1 m) of the centreline and within
    `trails.zone_band_m` (5 m) of its height there (§4.3); `zone_polygon()` for camera bounds and debug drawing;
    `nearest()`, `point_at()`, `centreline_from(map)`, `gate_into(map)`, `other_map(map)`, `portal_key_of(map)`.
- **Where the ribbon comes from.** The export's `World_Trails.json trails[]` names each trail's meshes but has no
  centreline yet (requested from the Blender export). `MapDefinitions` uses a sidecar `centreline` (+ `half_width_m`
  or `half_widths_m`) when present; until then `TrailLoader` reads the trail's main mesh from the `World_Trails`
  visual glb (the live chunk, or the glb itself when visuals are off: ~10 ms) and `TrailGeometry.ribbon()` derives
  it:
  1. keep the faces within `trails.top_max_slope_deg` (45°) of level: the top (flanks are 49.6° or steeper, so this
     also works on the hidden lane, whose top and flanks share one material);
  2. weld, take the boundary edges, chain the longest loop: the ribbon outline;
  3. cut spikes and zigzags (135° or more: grid-cut T-junctions, folds on sharp bends);
  4. the corners are the square turns (65°–125°); of the runs between them, the one nearest each gate is that end's
     cap; the runs between the caps are the two sides, untangled where they cross themselves (the inner edge of a
     sharp bend) and cleaned of reversals;
  5. rows: one side every 0.5 m paired with the nearest point of the other; the half-width is the median (one width
     per trail by construction) and each centre lies that far from its side point.
  The 000001006 causeway stops where its plank bridge begins: the `*_BridgeDeck` planks are appended, one row per
  plank (its centre, its long axis as the lateral, half its length). All 20 trails derive cleanly: widths 5.2 m (11
  main-road trails), 3.8 m (8), 3.4 m (the hidden lane), the bridge 3 m; every cap 1 m inside its gate and centred on
  it (the ledge end exactly on 000000040's gate plane).
- **Gates** (`GateDef`, two per trail): the vertical plane where the portal's outward ray crosses its map's ring line
  (footprint + `containment.ring_offset_m`), normal = the portal's `inward`, height = the ground just inside the map
  (the 000000040 gate sits on the landing below the ledge, matching the sidecar's `ledges[].gate_plane` to 0.1 m).
  Box: `gates.half_width_m` (2.25) across, `gates.below_m` (1) below to `gates.height_m` (3) above. A gate's
  `source_portal` is the other end's portal when it leads into the gate's map; the 000000030 end of the one-way
  trail has none.
- **`GateMonitor`** (physics priority 150: after the player and PortalInteractor, before MapSession). Each tick while
  MapSession is `IDLE` it tests `MapDefinitions.far_gates(current_map)`: the gate into the OTHER map of every
  edge-mode trail touching current_map (at most 8, 000001000). `GateDef.step(p_prev, p_now, on_floor, in_hitstun)`
  is §4.4's rule on the player's feet: an inward crossing inside the box arms it (also mid-jump or under knockback),
  walking back out past `gates.disarm_back_m` (0.25) disarms it, and the first grounded tick out of hit-stun with the
  feet inside commits it:
  `MapSession.transition(TransitionRequest.make(gate map, defs.arrival_for(source_portal), "gate", source_portal))`.
  - The trail belongs to the map you came from: current_map's own gates are never tested, so turning back on a
    trail changes nothing, and after a commit the trail you walked belongs to the new map.
  - A tick that moves the feet more than `gates.teleport_step_m` (2 m) is a teleport (warp, recovery, load), never a
    crossing; any teleport, transition and `set_player` also resets it.
  - A gate whose map cannot be entered from current_map (`PortalGraph.has_direction` false: the 30 end of the
    one-way trail) reports one error; the 2.4 m ledge makes it unreachable.
  - `commits`, `errors`, `armed_maps()`, `active_gates()`, signal `gate_committed(gate)`.
- **The one-way 30 → 40.** Walking down: the trail ends on the ledge top at 000000040's gate plane; stepping off arms
  the arrival gate mid-fall, landing commits `000000030.out00` and records `last_arrival = {000000040,
  spawn_index 0}`, exactly what pressing Up at `000000030.out00` records. Walking up: the 2.4 m face cannot be
  climbed (jump apex 1.30 + step 0.45 + 0.3 margin ≤ 2.4, `test_portal_one_way_ledge`); the bot spams jump against it
  for 10 s and stays in 000000040, outside 000000030's region and off the trail.
- **Equivalence** (§4.4): a walk and a press-Up from identical state give the same `current_map`, `last_arrival`,
  `respawn_reference`, live instance and event sequence; only the player's position differs (a walk stands at the
  gate, a press-Up at the arrival).

## Region index and the identity invariant

`RegionIndex.from_defs()` (rebuilt once the trails have geometry): map footprints (+1 m, with their region
extensions; the ring's vertical span, the chunk bounds from 2 m below to 4 m above) and the 20 trail zones. `region_of(pos, prefer)` returns
`{kind: "map" | "trail" | "void", id, maps}`; map footprints win over trail zones, and `prefer` (current_map) wins
among several. `allowed(pos, current_map, armed_maps)`: in current_map, else (outside every footprint) on a trail
touching it, else in the map of an armed gate.

- **`RegionMonitor`** samples at `region_invariant.sample_hz` (10 Hz) while IDLE: the player's last ground point
  (the feet the last tick it stood on the floor or a ladder) must be `allowed`. `violation_samples` (5) failures in a
  row are one violation: `push_error` with the position, `violations` counts it (the traversal bot asserts zero),
  `violated(position, current_map, region)`; release builds also recover to SafeGround.
- **The trail HUD line.** The same sample reports the trail under the live position to
  `MapSession.set_trail(link_id, dest_map_id)`, which emits `trail_changed(dest_map_id)` when the destination changes
  (`""` off trails, and on every map change). `MapSession.trail_destination` / `trail_link_id` hold the current
  value. The HUD is meant to show "→ <destination map name>" from it (the HUD system's part). **Not wired yet:**
  nothing under `game/scripts/ui` listens to `trail_changed`, so in the game a walk along a trail shows only the map
  banner of the map you left (seen in the review's windowed run, 000000040 → 000000041). Requested from the HUD.
- **SafeGround** (`FallRecovery.is_safe_point`): `allowed(pos, current_map)` without armed gates: the map or one of
  its trails.

### Region extensions

A map's region is its layout rectangle + 1 m, unless something walkable the export builds for that map lies outside
it. `maps/<id>.json region_extensions` then adds it (`MapDefinitions.apply_region_extensions`, at build time):

- `ring_line_local`: a polygon in the map's local frame (the sidecar's `footprint.local_frame`, metres, x and y as in
  the Blender map source; world = `frame * Vector3(x, 0, -y)`). It is the region's edge itself, where the ring wall's
  inner face stands, so it is **not** grown by `ring_offset_m`. It must overlap the footprint: the union
  (`Geometry2D.merge_polygons`) has to be one polygon, else the entry is refused with a build error (also without a
  reason or with fewer than 3 points). A map without export geometry (no footprint) is left alone.
- The union becomes `footprint`, so everything that reads it follows: `RegionIndex` (the identity invariant,
  SafeGround, saves), the containment ring, `footprint_contains`, the gate ring points and the camera bounds.
  `footprint_base` keeps the layout ring (+1 m); the mob region still uses the layout rectangle.
- `keep_footprint_ring_below_y` (optional, world height): where the extension opens the layout's own ring line, that
  wall still stands from the ring's foot up to this height ("Kept" pieces of the ring body). Ground under the
  extension stays closed while a walkway crosses the old line above it.

**Southperry (000000060): the ship <Victoria>.** The Blender source moors the ship outside the layout's front edge
(local y < 0; centre (74.5, -4.3), walkable decks to y = -5.85). The end of the Main route and the ShipDecks,
ShipForecastle and ClimbMast routes (47 authored points, with the MastRope) lay up to 5.5 m outside the layout,
4.5 m beyond the ring line: the layout ring's wall stood across the gangplank, and a player on the deck read as
"void" (`[RegionMonitor] identity invariant: ... lies in void`). The extension's ring line hugs the ship's deck-level
outline (bulwarks and deck edges, probed in the export's collision with rays from 10.5 m down to 5 m), so no
body-sized pocket is left between the ship and the wall:

- port side: 0.31 to 0.41 m outside the bulwarks. The margin is tight on purpose: the stern barrel engine's top
  (7.4 m) sits 2.5 m below the quarterdeck bulwark, so a player who dropped onto it could not get back, and with
  0.35 m between bulwark and wall no 0.6 m body fits down there (the fore engine likewise);
- stern: on the quarterdeck's stern edge (x 63.2; the deck ends at x 63.3, a 0.05 m transom sliver at 8.9 m runs at
  x 63.2 to 63.25). The first version stood 0.3 m further out (x 62.9): a player who walked off the quarterdeck
  dropped onto the sliver and hung behind the stern in mid-air, and could not walk back without jumping;
- bow: across the forecastle's bow notch at x 84.85 (the bulwark tips reach x 84.95 at y -3.1 and -5.5, the deck
  ends at x 84.5 between them; the bowsprit runs through the wall). At x 85.5, the first version left a 1 m void in
  front of the notch, where a player jumping off the bow fell into the sea (a fall recovery) or hung on the stem
  pieces in mid-air.

The layout ring under the ship (y = -1, x 63.2 to 83) keeps a wall up to 5.6 m: the base strip in front of the quay
(1.0 m, one 0.8 m step below the sunken street) stays closed instead of opening onto the sea under the hull, and the
gangway crosses that line at 7.4 m. A player who jumps off the starboard side lands on that strip and walks back to
the town through the sunken street.

The ship's collision is part of Southperry's one-sided trimesh, whose faces point outward. On the deck the player is
inside it, so `maps/000000060.json` sets `collision.double_sided_trimesh` (see "World loading, collision and
containment"). Without it, two pushes toward port fell out to kill_y: one slipped through the bulwark under the
sloping quarterdeck handrail (local x 68.4), the other ran in under the forecastle deck past the end of its aft
bulkhead (x 81 to 82.6) and fell through the hollow hull. One known slot remains (`KNOWN_EXTENSION_SLOTS` in
`world_checks.gd`, a Blender request under "Source world status"): below the forecastle the main deck stops short of
the port hull, so a body pushed there drops about 0.45 m between deck edge and hull, wedged, and walks back out.

Checked: `test_region_routes` (every authored point in its own map), `test_world_static` (no ring wall within a body of
any route point, the kept wall), `test_world_transitions` (the real player pushed at every metre of the extension's
ring with jumps: on the floor afterwards, walks back, no fall recovery, no invariant violation; the first version's
ring with one-sided collision fails it 13 times: 9 ring pockets at the stern and the bow, 4 fall-outs through the
one-sided collision), and the game's PlayerController in main.tscn walking Main onto the ship and pushing off the
stern, the bow, the forecastle and the port side with jumps: 0 recoveries, 0 violations.

## MapSession

States `BOOT, IDLE, WARP_OUT, SWAP, WARP_IN, ARRIVING, DEAD`. `transition(req)` follows §4.5:

1. Guard: `IDLE` (debug also from `BOOT`, load from `BOOT/IDLE/DEAD`, respawn only from `DEAD`); portal vias (gate,
   press_up, door) need the portal to be in `current_map` and `PortalGraph.has_direction(current_map, to)` (so
   40 → 30 is impossible), and the request's `to_map` and arrival must be that portal's own (`destination_map_id`,
   `arrival_for(portal)`): a request cannot redirect a portal to another neighbour or another arrival.
2. `ArrivalResolver.resolve()` before any fade; a failure rejects with nothing changed.
3. **Gate** (`via "gate"`): `SWAP` and back to `IDLE` in the same call, no fade, the player not placed and its input
   not touched (a window that turned input off keeps it off); monsters realize nearest-first around the player; the
   camera bounds blend over `transition.gate_blend_s` (0.35 s) and the environment over `environment_blend_s`.
4. Warps: `WARP_OUT`: player input off, physics frozen (`process_mode` disabled, velocity zeroed), `ScreenFader` 0.2 s.
5. `SWAP` in one frame: `Events.map_left(old)` (skipped on the very first entry, where there is no old map),
   release the old instance into `MapStateCache`, set `current_map` / `respawn_reference` / `last_arrival`, restore
   or `fresh()` the new instance and realize it, enable that map's portals and NPCs, disarm the arrival portal, place
   the player (warps), camera `set_bounds(...)` (+ `snap()` for warps), `IslandWorld.environment_changed`,
   `Events.map_entered(new, old)`, `Events.portal_used(old, portal, new)` for gate/press_up/door, the record into
   `last_transition` and the 64-entry `transition_log`, the trail line cleared, and the location into the character.
6. `WARP_IN` fade 0.2 s, then `ARRIVING`: physics back on, input still off until `is_on_floor()`; budget 10 frames
   (warning beyond), re-place at `player_spawns[0]` after 30 (error, `record.replaced = true` for the bot). Then
   input back on (unless a modal is open: see "Input gating"), `IDLE`, `transition_finished(record)`, and
   `Saves.request_autosave()` if the save system provides it.
   MapSession's `process_physics_priority` is 200 (after the player at 0, PortalInteractor at 100 and GateMonitor at
   150), so the ARRIVING check reads the floor state the player produced this frame. At the default priority an
   autoload runs first and reads the pre-warp floor flag (the controller defers its settle while frozen), so a
   mid-air arrival counted as grounded on frame 1 and the re-place rule could never fire.

`transition()` returns as soon as the request is accepted; await `transition_finished` for completion. Without a
world (pure tests) every transition completes synchronously. If the world leaves the tree mid-warp
(`detach_world()`), a committed swap completes without it and an uncommitted one is dropped (back to the state it
started from); the fading coroutine notices the abort and stops. Then the session resets (below).

- `request_portal(portal)`, `debug_warp(map_id, portal_id := "")`, `can_save()`: IDLE, a map, and a valid
  SafeGround point when a player exists; or DEAD once the death is committed (below).
- **Trail line**: `set_trail(link_id, dest_map_id)`, `trail_changed(dest_map_id)`, `trail_destination`,
  `trail_link_id` (see "Region index"). `refresh_camera()` re-applies the current map's bounds (the world calls it
  when a link mode changes them).
- **Reset** (quit to title). `reset()` returns the session to `BOOT`, as before the first map:
  - `current_map`, `respawn_reference`, `last_arrival` and `last_transition` are cleared, and the trail line;
  - the transition log is empty, there is no live instance, and the instance cache is empty, so the last session's
    drops and dead slots are gone;
  - nothing is pending (a queued load, a death, a commit), and a warp in flight is abandoned.

  Collaborators stay: `defs`, `world`, `camera`, `character`, the clock, the RNG, `death_rules` and `death_commit`.
  Their owners detach them. It emits `state_changed` and `session_reset`.

  `detach_world()` calls it after settling any warp, and `IslandWorld._exit_tree` calls `detach_world()`. So the
  shell's quit to title leaves a clean session. The next `GameSession.start` finds `BOOT` (its step 0 calls
  `reset()` itself if a session was left past `BOOT`) and enters the world exactly as the first time:
  `start_new_game()`, or `load_character(Game.character)`, which uses the saved `resume` point. The first
  `map_entered` names no old map. Seen in the real game (review): a quit to title mid-warp leaves `BOOT` with no
  current map, instance or cache, and Continue lands on the last save with a one-entry transition log.
- **Death** (§4.8):
  - `enter_dead()` sets state DEAD, turns input off, runs the commit below, then emits `Events.player_died(map)`.
  - MapSession also enters DEAD when someone else emits `Events.player_died`.
  - A death during a warp, by either path, enters DEAD (with its commit) as soon as the warp completes.

  `respawn()` transitions `via respawn` to `returnMap` `player_spawns[death.json respawn_player_spawn_index]`
  (0, open question 1), then emits `Events.player_respawned(map)`. A load started from DEAD (a death screen's load)
  also emits it.
- **Death commit.** Classic MapleStory takes the loss at the moment of death. `death_commit` is a
  `Callable(character: CharacterState) -> Variant`, and `DeathRules.apply` fits it. When it is set, every way into
  DEAD does this, in order:
  1. state DEAD, input off;
  2. `death_commit.call(Game.character)`, exactly once for this death;
  3. the character's `location` becomes `respawn_location()`, `{map_id: returnMap, entry: {map_id, spawn_index}}`
     with no resume point, and its `respawn_reference` becomes that town's;
  4. `death_committed(map_id, report)` is emitted. `report` is the hook's return value. `last_death_commit` holds
     `{map_id, location, report}`;
  5. `Saves.request_autosave()`;
  6. only for `enter_dead()`: `Events.player_died`.

  **While DEAD after a commit:**
  - `is_death_committed()` and `can_save()` are true;
  - `save_world()` and `capture_location()` return the respawn location and the town's respawn reference. Every
    save (pause menu, autosave, Game's save when the window closes) therefore writes the post-death character in
    town: quitting while dead cannot dodge the loss, and a reload starts at the return map;
  - `respawn()` skips `death_rules`.

  The flag clears whenever DEAD is left (a respawn, or a load), and on `reset()`. `commit_death()` runs the commit
  by hand: use it if the hook was installed after the death. It returns `ERR_UNAVAILABLE` when not DEAD,
  `ERR_ALREADY_EXISTS` when already committed, and `ERR_UNCONFIGURED` without the hook.

  **Without `death_commit`** nothing changes: `death_rules` (the old hook) runs in `respawn()`, and saving while
  DEAD is refused.

  **Helpers:** `respawn_location(map_id := current_map)` and `respawn_reference_of(map_id)`.
- **Load** (§4.9): `enter_from_location(location, saved_respawn)`: `resume` (validated by the world: same map region,
  walkable within the grounding probe, capsule clear, not inside a trigger) → `entry` → `player_spawns[0]` → unknown
  map: `session.fallback_map_id` (000000001) with an error. `start_new_game()` uses `new_character.json
  start_location`; `load_character(c)` uses `c.location` and `c.respawn_reference` (canonical returnMap wins).
  MapSession listens to `Game.character_replaced`: once the world has started (not in BOOT), a new game, load or
  reset during play runs `load_character(Game.character)` at once, or right after a warp in flight (with the
  location copied when the signal arrived). Without this the player stayed in the old map and the 0.25 s location
  refresh overwrote the loaded character's location. In BOOT the main scene starts the session itself.
- **Location model**: `capture_location()` writes `{map_id, entry: last_arrival, resume: {local_pos (map frame),
  facing_deg (a yaw in the map frame too), map_content_hash}}` into `Game.character.location` and
  `respawn_reference` on every commit and every `session.location_refresh_s` while IDLE; `resume` comes from
  SafeGround, never the live position. **On a trail** (§4.9: the SafeGround point lies in a trail zone) there is no
  `resume`, and `entry` becomes current_map's portal at that trail, so a load lands at that portal's arrival.
  `save_world()` returns `{location, respawn_reference}` (SaveService calls it).
- **Debug**: `debug_info()` (current map, name, state, region, last arrival/transition, link modes (forced or
  counts), the trail line, capacity, alive slots, cached maps, `death_committed`, live monsters, position),
  `reload_map()`, `report_monster_killed(node)`, and console commands `map_warp <map> [portal]`, `map_info`,
  `map_link_mode <link|all> <mode>`, `map_reload` registered with `Debug`. `IslandWorld.debug_info()` adds
  `gate_commits`, `armed_gates`, `region_violations` and `link_modes`.

## Spawns, instances and NPCs

- **`SpawnModel`** reads `formulas/spawn_rate.json`: tick `global_respawn_tick_s` (7.56 s, anchored at game-clock 0),
  wave cooldown `wave_point_cooldown_s` (5 s; timed points use their mobTime), capacity `floor(points x scalar_pct /
  100)` from `capacity.player_scalar_table` in integer math (solo 75%), `map_spawn_rate_multiplier.applied_by_msc =
  false` (mobRate ignored). Island: 577 points, solo capacity 426 (Appendix B).
- **`SpawnSlotPlanner`** (M1 rule). Areas and quotas:
  - each species' slots go to the map's `spawn_regions` (authored; else the derived `spawn_areas`) tagged with
    that species, else to any area, else to the whole mob region;
  - areas are clipped to the mob region (footprint inset 2 m) and share slots by largest remainder of `points` /
    area. Every map exports areas today.

  Samples are seeded by `hash("<map_id>:<index>")`. A sample is accepted when:
  - it hits walkable as the topmost surface, first on the area's own tier (its `y_band`, else within 0.6 m of
    `surface_y`);
  - its clearance capsule is clear. The capsule is 0.35 m in radius and **as tall as the species' body**
    (`clearance_height(mob_id)`): the canonical `sprite_size_px[1]` x `WorldScale.actor` when the species'
    `monsters/<id>.json` (or `monsters/_shared.json`) `model_fit` is `sprite_height`, else its `capsule_height_m`,
    and never below `spawns.clearance_height_m` (0.8 m). The Tutorial Jr. Sentinel is 1.7 m, the Orange Mushroom
    1.45 m, and the snails and Shroom keep 0.8 m. `SpawnSlotPlanner.species_body_heights(db)` reads them, and
    `MapDefinitions.body_heights` holds them;
  - it lies outside every `maps/<id>.json spawn_keepouts` disc. A disc is `around_prop` (every instance of that prop
    shape in the sidecar's `collision.prop_instances`) or a world `center`, plus `radius_m`, a reason and
    `verified`. See `keepouts_of()` and `in_keepout()`;
  - it stands 1.2 m from other slots and 4 m from every arrival.

  Species and counts are never changed. `maps/<id>.json spawn_slot_overrides` may pin a position.
- **`MapInstanceState`** (pure):
  - `fresh()` fills to capacity at once with a seeded RNG (open question 6);
  - `tick(now)` processes the tick boundaries since the last call (closed form, so a day away replays in
    microseconds);
  - `kill(i, now)`; `snapshot()` / `from_snapshot()` (fast-forwarded); survivors keep their HP.

  Only MeowDB spawn points are slots. `SpawnSlot.NO_SLOT` (-1, placement `"debug"`: the debug console's `spawn`
  builds such a slot itself, `SpawnSlot.synthetic(...)` makes the same shape) and any out-of-range index are "no
  slot": `MapInstanceState.has_slot()` (and `SpawnSlot.is_spawn_point()`) is false, `kill()` refuses them, they are
  never alive, never respawned and have no HP, and `ready_time(-1)` is `INF` (it used to wrap to the last slot).

  **Drops** are the loot system's records, identified by `"uid"` (`DROP_UID_KEY`):
  - `add_drop(record)` stores a copy;
  - `find_drop(uid)` returns the stored record, or `{}`;
  - `has_drop(uid)`;
  - `remove_drop(uid)` returns the removed record, or `{}`;
  - `expire_drops(now)` removes and returns every record at or past `expires_at`. `tick()` and `snapshot()` call it
    too.
- **`MapStateCache`**: LRU of the 4 most recently left maps; eviction means the next visit is `fresh()`.
- **`MapInstanceView`** (current map only): realizes nearest-first, at most 8 per frame, with default proxies fading
  in over 0.3 s. It ticks on `Game.clock`, and `release()` writes survivor HP back.
  - **Hooks for the monster system.** `monster_factory: Callable(mob_id: String, slot: SpawnSlot) -> Node3D`. The
    default is the static `_library.glb` proxy: sidecar species → proxy, else `Mob_<Name>`, else a labelled
    placeholder (for example the Tutorial Jr. Sentinel). `monster_releaser: Callable(node)` is optional.
  - **Spawned nodes** carry metadata `spawn_slot`, `mob_id`, `map_id`. Report deaths with `notify_killed(slot)` or
    `notify_node_killed(node)`, or give the node a `died` signal.
  - `notify_node_killed(node)` and `slot_of(node)` accept only the node this view spawned for that slot. A debug
    spawn, or a node released by an earlier realize, never kills a live slot, and `notify_killed(-1)` is false.
  - **`debug_kill(node) -> {own_death, slot, recorded}`** is a kill for tools and the console. The console's `kill`
    does not call it today: it has its own equivalent path (DEBUG_TOOLS.md "Kill": the monster's `debug_kill()`,
    else `MapSession.report_monster_killed`), which reaches the same slot rules through `died` /
    `notify_node_killed`. It does:
    - a node with a zero-argument `die()` (the monster system's `Monster`) runs its own death: EXP, drops and
      `monster_killed`. A slot monster's `died` then records the kill; a debug spawn's is not connected and records
      nothing;
    - else a slot monster: `notify_killed(slot)`;
    - else (a `NO_SLOT` node with no death of its own): it is released and nothing is recorded.

    Debug spawns are made by the console through `monster_factory` and parented here, but they are never in
    `nodes`.
- **NPCs**: all 21 MeowDB NPCs are created once at load (`WorldNpc`: proxy model, metadata `npc_id` (MeowDB),
  `npc_name`, `map_id`, group `npcs`, a `TalkArea` Area3D: the NPC's talk zone, below). Markers are matched by
  `meowdb_npc_id`, else by name; Blender NPCs MeowDB does not list are ignored and reported; a MeowDB NPC without a
  marker is placed next to `player_spawns[0]` with a warning. Interaction is enabled only in `current_map`.

### NPC talk zones

The interact key talks to a current-map NPC whose talk zone overlaps the player's body (`WorldNpc.in_range`, through
`IslandWorld.nearest_interactable`; a body off the player layer falls back to its feet within
`npc.interaction_radius_m` of the NPC's). The zone is the NPC's `TalkArea`, a `SphereShape3D` centred above the NPC's
feet, sized by `WorldTuning.talk_zone(npc_id)` (`WorldNpc.talk_radius_m`, `talk_centre_height_m`, `talk_profile`):

| Profile | NPCs | Radius | Centre above the feet | Why |
|---|---|---|---|---|
| `default` | every NPC no profile lists (18) | `npc.interaction_radius_m`, 1.6 m | `npc.talk_centre_height_m`, 0.8 m | a little more than the 1.5 m body: the player walks up to the NPC |
| `across_counter` | Pan (16), Sid (20), Lucy (21): the NPC of every canonical shop | 2.4 m | 0.8 m | shopkeepers serve across their counter (Test G). A player pressed against the counter stands 1.90, 2.10 and 1.90 m from them and 0.45, 0.45 and 0.8 m lower; the 1.6 m sphere left that body 0.00, 0.20 and 0.04 m outside |

`presentation.json npc.talk_zones` holds the profiles (`npcs`, `radius_m`, `centre_height_m`, `reason`, `verified`).
The first profile by name that lists an NPC wins. `WorldTuning.talk_zone_errors()` reports a profile without NPCs, a
radius, a centre height or a reason, and an NPC listed by two profiles; `IslandWorld` adds those and any listed NPC no
map places to its build errors (the L1 build must have none). The centre height used to be half the radius; it is
its own key now, so a larger zone reaches further without rising. A larger zone is only for scenery a player talks
across: an NPC standing where no player can go is fixed in the source world (blender_export.md, round 4: Heena,
Roger and Nina).

**Reach on foot.** The `npcs` playtest scenario (`game/tools/playtest/scenarios/npcs.gd`, PLAYTEST_HARNESS.md) is the
check: for every NPC, a console warp to its map (setup), then `talk_to()` from the map's arrival with real input
(the routes, with their stairs and ladders, and the grid planner) and the interact key. Every conversation must open
(a hard check, no `soft_check`). Then, with the window closed, the player presses on toward the NPC with real movement
input for at most 1.5 s, and must end **at least 0.4 m inside the zone** (`talk_gap <= -0.4`) with the prompt still
offering that NPC. The margins are logged (one note per NPC, and `report.json carry.npc_margins`);
`test_npc_reach_scenario.gd` runs it. On the round-4 export (2026-10-04, headless, seed 1, about 26 s wall): 21 of 21
open on foot, Heena, Roger and Nina over their new stairs (`ToHeena`, `ToRoger`, `ToNina`). Pressed in, the 18
NPCs in the open end 1.63 to 1.67 m inside their zone (the feet 0.23 to 0.27 m from the NPC's), and the three
shopkeepers end against their counters: Pan 0.83 m inside (feet 1.87 m from him), Sid 0.61 m (2.09 m), Lucy 0.79 m
(1.87 m). Before (round 3, the 1.6 m zone): Heena 0.52 m short, Roger and Nina no path at all, Sid 0.18 m and Lucy
0.01 m short, Pan 0.008 m inside.


## World loading, collision and containment

`IslandWorld.build()` runs in `_ready()` and emits `load_progress(fraction, stage)` every frame (the loading-screen
hook) and `world_ready()` at the end (about 1.5 s with visuals on the dev machine); `build_now()` is the
synchronous variant for tests and tools. All 31 chunks stay resident (`AllResident`, §4.12). Stages: data, sky/sun,
chunks, **trails** (`TrailLoader`), ground (`ground_all`, gate heights, `finish_trails()`, `RegionIndex`), nodes.

Collision comes from the `.collision.glb` files (Godot builds the `-colonly` / `-convcolonly` shapes); the world
then reassigns layers by body name:

| Bit (layer) | Name | Contents | Who collides |
|---|---|---|---|
| 1 (1) | walkable | `Ground` of map, interior and `World_Trails` chunks | player, monsters, ground probes |
| 2 (2) | blocking | `Walls` and `*_hull*` of those chunks | player, monsters |
| 4 (3) | containment | the map rings, the gate plugs (warp-mode links), the trail side walls | player only |
| 8 (4) | player | the player body | portal triggers, NPC talk areas, the kill plane |
| 16 (5) | monsters | monster bodies | the kill plane |
| 32 (6) | interactables | portal triggers, NPC talk areas (Area3D) | they monitor the player layer |
| 64 (7) | scenery | collision of the other world chunks (island body, plinth outcrops, scenery, forest) | player |
| 128 (8) | kill | the sea-level kill plane (Area3D) | |

The exported trimeshes (`Ground`, `Walls`) are one-sided, their faces pointing outward. A map whose
`maps/<id>.json` sets `collision.double_sided_trimesh` (with a reason) gets copies of its chunk's trimesh shapes with
`backface_collision` on (`IslandWorld.double_sided_trimesh`, counted in `stats.double_sided_trimeshes`). Today only
Southperry sets it, for its ship (see "Region extensions").

`WorldLayers.PLAYER_MASK` = walkable, blocking, containment, scenery; `MONSTER_MASK` = walkable, blocking.

- **Environment**: sun (`index.json environment.sun` xform and colour; energy = strength x
  `environment.sun_energy_per_w_m2`), procedural sky from `sky_gradient_srgb`, ambient from `world_backgrounds[0]`.
- **Sea kill plane** at `sea_level_y` spanning every chunk's bounds.
- **Containment** (`ContainmentBuilder.build` → `rings`, `plugs`, `trail_walls`, `ring_gaps`):
  - **Rings**: one body per map, a box wall per edge of footprint + 1 m (with its region extensions), spanning the
    chunk's whole height (2 m below to 4 m above its bounds; the spec's "4 m tall" assumes flat maps, but terraces
    rise ~10 m above `base_y`). The inner face lies on the ring line, the wall outside it: outside by the polygon's
    winding (`outward_side`, `edge_outward`), so a concave ring such as Southperry's works. Pieces are lengthened by
    the wall thickness only at convex corners (`convex_corners`); at a concave corner the two walls already overlap,
    and a lengthened piece would stand 0.5 m inside the region. A region extension's
    `keep_footprint_ring_below_y` adds the "Kept" low wall (`add_kept_ring`).
  - **Gaps**: at every gate into the map, the wall leaves a gap centred on the gate, as wide as the corridor between
    the trail's side walls and never wider than the gate (`min(gates.half_width_m, half-width +
    trails.side_wall_offset_m)` each side), so no slot opens beside a side wall. 40 gaps.
  - **Plugs**: one body per gap filling it, enabled (containment layer) while its link is `warp`, disabled in `edge`
    (`ContainmentBuilder.set_plugs`, re-applied on `link_mode_changed`). Warp mode therefore closes every map
    exactly like M1.
  - **Trail side walls**: one body per trail, a box per segment of each raw ribbon edge pushed
    `trails.side_wall_offset_m` (0.3 m) outward, from `trails.side_wall_below_m` (2.5 m) under the edge to
    `side_wall_height_m` (3 m) above it, trimmed to the stretch between the two gate planes (the first and last
    crossings only: a curving trail passes the far side of a gate's infinite plane elsewhere). The flanks are
    walkable collision steeper than the 38° floor angle, which is why the walls reach under the edge.
- **Grounding** (`MapDefinitions.ground_all`): a point is grounded when a ray from 1 m above to 3 m below hits
  walkable first; a blocking surface within 0.05 m above walkable counts as that ground (interior floors carry a
  `Walls` slab 3 mm above `Ground`). Arrivals, player spawns and fallback NPCs are **settled**: if the point is
  ungrounded, its 0.3 x 1.5 m capsule is blocked, or it lies in a trigger, the nearest valid point on rings of 0.5 m
  up to 5 m (inward first) is used and a warning names the blocker. NPC markers are only snapped down, never moved.
  Gate heights are probed 0.3 m inside the gate.
- **Fall recovery** (`FallRecovery`): below the map's `kill_y` (lowest walkable height of the map and its trails
  minus 6 m: the 30 → 40 trail falls 9.8 m below 000000030; or the sidecar's own `kill_y`) or in the sea plane, the
  player returns to the last SafeGround point (one log line, `recoveries` counter). It uses `player.safe_ground` (the
  controller's `SafeGround`) when present and installs `is_safe_standing(pos, floor_collider)` as
  `player.safe_ground_filter`: walkable collision within 0.3 m under the feet (not a hull, fence or rock top the feet
  may also sense) and inside the current map's region or one of its trails (§4.6). Otherwise it records SafeGround
  itself with the same rule.

## Contracts with other systems

**Player** (duck-typed, any `Node3D`, origin at the feet): `teleport(xform)` (sets the transform, zeroes velocity,
resets jump/coyote state and its SafeGround), `is_on_floor()`, `global_position`, `velocity`; optional
`set_input_enabled(bool)` / `is_input_enabled()` (or an `input_enabled` property), `is_dead()`,
`input_source: InputSource`, `safe_ground: SafeGround`, `safe_ground_filter: Callable(pos: Vector3) -> bool`,
`in_hitstun: bool` (GateMonitor waits for it to clear), `is_climbing()`, `climbables` +
`add_climbables_from_sidecar(arr)`. The body should be on `WorldLayers.PLAYER` with `WorldLayers.PLAYER_MASK`.
Register it with `IslandWorld.set_player(player)`, which enforces that: a `CollisionObject3D` player is put on
`WorldLayers.PLAYER` and `PLAYER_MASK` is added to its mask (portal triggers, NPC talk areas and the kill plane watch
the player layer; walls, rings and scenery stop it). **Since M2 `set_player` also registers every map sidecar's
`climbables[]` (144 ladders, ropes and vines) with a player that has none yet** (`register_climbables`), so ladders
work in the real game, not only in the player sandbox and the bot.

**Camera rig**: `MapSession.attach_camera(rig)`; the rig implements `set_bounds(bounds: PackedVector2Array,
ortho_size: float, blend_s: float)` (ortho size is the frame width, `Camera3D.KEEP_WIDTH`) and `snap()`. A gate
commit blends the bounds over 0.35 s without a snap; a link-mode change re-applies them (`refresh_camera`).

**HUD**: `MapSession.trail_changed(dest_map_id)` / `MapSession.trail_destination` for the trail line "→ <map name>"
(`""` off trails); `Events.map_entered` for the map banner, as before (a gate commit emits it like any warp).

**Main scene**: instance `scenes/world/world.tscn`, drive a loading screen from `load_progress`, on `world_ready` add
the player and call `set_player()`, give the world the context with `world.set_context(ctx)`, then
`MapSession.start_new_game()` or `MapSession.load_character(Game.character)`.

**Game shell: what to call.**

| When | Call | Effect |
|---|---|---|
| After the `GameContext` exists (`GameSession.start` step 4) | `world.set_context(ctx)` | Warps never hand input back under a modal, and portal keys pressed in a modal are ignored. Until then, the world reads `GameSession.ctx` through its parent |
| Death rules at the moment of death | `MapSession.death_commit = Callable(rules, "apply")`, instead of `death_rules` | See "Death commit". Listen to `MapSession.death_committed(map_id, report)` for the report. Detach it with `death_commit = Callable()` |
| Saving while dead | nothing new | `Game.save_game()` works once the death is committed (`can_save()` is true). The file holds the post-death character at `respawn_location()` |
| Quit to title | nothing | `IslandWorld._exit_tree` → `detach_world` → `reset()`. Continue and New Game go through `BOOT` |
| Respawn spawn index | `defs.tuning.respawn_spawn_index()` (or `MapSession.respawn_location(map_id)`) | death.json `respawn_player_spawn_index`. The old `tuning.count("respawn", "player_spawn_index")` still answers through an alias |

## Canonical sources used

- `game/data/canonical/maps/<id>.json` (MeowDB map pages): `name`, `street_name`, `is_town`, `safe_zone`,
  `return_map_id`, `field_limit`, `bgm`, `mob_rate` (carried raw, ignored), `portals[]` (`name`, `type`, `to_map_id`,
  `to_portal` as a cross-check), `player_spawns[]` (count), `spawns[]` (`mob_id`, `mob_time_s`, index),
  `monsters[]` (`id`, `name`, `count`), `npcs[]` (`id`, `name`), `meowdb_spawn_estimates.capacity_solo` (test oracle).
- `game/data/canonical/formulas/spawn_rate.json` (meowdb.com/msclassic/formulas/spawns and the spawn-engine guide):
  `global_respawn_tick_s`, `wave_point_cooldown_s`, `capacity.player_scalar_table`,
  `map_spawn_rate_multiplier.applied_by_msc`.
- `game/data/canonical/monsters/`, `npcs/` (ids checked by the tests); `monsters/<id>.json sprite_size_px` (the
  species body height of the spawn clearance).
- Adaptation data read but owned elsewhere: `map_id_crosswalk.json`, `new_character.json` (`start_location`),
  `monsters/<id>.json` and `monsters/_shared.json` (`model_fit`, `capsule_height_m`: the monster system's),
  `death.json` (the game shell's file; this runtime owns only `respawn_player_spawn_index`).


## Adaptations

Every value below lives in data with its reason; none is in code.

| File:key | Value | Why |
|---|---|---|
| `portal_adaptations.json:force_link_mode` | `""` | M2: links take their configured mode; `"warp"` is the M1 fallback (every link press-Up, plugs closed) |
| `portal_adaptations.json:default_link_mode` | trail `edge`, door `warp` | §4.4 |
| `portal_adaptations.json:link_modes.overrides` | none | every trail walks; 000001012 ↔ 000001014 was `warp` until the Blender round-3 re-route (Source world status) |
| `portal_adaptations.json:arrival_gates` | `arrival:T_000000030_out00__000000040` at 40's `in00` anchor, spawn index 0 | MeowDB's one-way link needs an arrival point; it is the walk-through gate at the foot of the ledge |
| `portal_adaptations.json:gates` | half-width 2.25 m, 3 m above, 1 m below, disarm 0.25 m behind, teleport step 2 m | §4.4: the 4.5 m corridor, twice the max jump, a crossing mid-jump still arms |
| `portal_adaptations.json:one_way_allowlist` | 30 → 40 | canonical one-way link for the SCC check |
| `portal_adaptations.json:hidden_portal_types` | `[1]` | MeowDB does not label type 1; classic hides it |
| `portal_adaptations.json:trigger` | 4.5 x 3 x 1.6 m | the authored 4.5 m corridor, > 2x jump height, arrival outside it |
| `portal_adaptations.json:arrival.inset_m` | 1.5 m | §4.4; outside the trigger |
| `portal_adaptations.json:anti_ping_pong` | on | holding Up never bounces back |
| `portal_adaptations.json:one_way_ledge` | margin 0.3 m, max drop 2.6 m, gate plane ±0.1 m | §4.4 CI invariant: the 30 → 40 ledge can be dropped down, never climbed |
| `portal_adaptations.json:interaction.interact_also_enters` | on | F works on the nearest portal too |
| `presentation.json:transition` | fades 0.2/0.2 s, grounded in 10 frames, re-place after 30, gate blend 0.35 s, environment blend 0.5 s | §4.5 budgets |
| `presentation.json:spawns` | 8/frame, fade-in 0.3 s, spacing 1.2 m, arrival clearance 4 m, 48 attempts, tier 0.6 m, mob region inset 2 m, probe 0.35 m wide and at least 0.8 m tall (taller species use their body height) | §4.5, §4.7.1, §4.7.4 |
| `presentation.json:grounding` | ray 1 m up / 3 m down, 0.3 m tolerance, 0.05 m coplanar, capsule 0.3 x 1.5 m lifted 0.05 m, search 5 m / 0.5 m | §4.9, §4.13 L1; settle blocked points |
| `presentation.json:containment` | ring at +1 m, 0.5 m thick, 2 m below / 4 m above the chunk bounds; gaps at the gates, plugs in warp mode | §4.6; terraces are taller than 4 m |
| `presentation.json:trails` | side walls 0.3 m out, 3 m above / 2.5 m below the edge; zone margin 1 m, band ±5 m; top faces within 45° of level | §4.3, §4.6; the flanks are walkable and steeper than the floor angle |
| `presentation.json:region_invariant` | 10 Hz, 5 samples in a row | §4.3 |
| `presentation.json:fall_recovery` | kill_y = lowest walkable of the map and its trails - 6 m, sea slab 2 m | §4.6 |
| `presentation.json:npc` | talk zone: a 1.6 m sphere centred 0.8 m above the NPC's feet; `talk_zones.across_counter`: 2.4 m for Pan, Sid and Lucy; fallback spacing 2.5 m | no MeowDB talk range (classic NPCs are clicked); shopkeepers serve across their counter ("NPC talk zones") |
| `presentation.json:session` | fallback map 000000001, location refresh 0.25 s | §4.9 step 4; fresh save points |
| `death.json:respawn_player_spawn_index` | 0 | MeowDB gives the returnMap, not which player spawn (open question 1). Moved from `presentation.json:respawn.player_spawn_index`; `WorldTuning.value("respawn", "player_spawn_index")` still answers through `MOVED_KEYS` |
| `maps/000000060.json:region_extensions` | `ship_victoria`: the ship's ring line on its deck-level outline (bulwarks + 0.31 to 0.41 m, the quarterdeck's stern edge, across the bow notch), the layout ring kept below 5.6 m under it | the ship is moored outside the layout rectangle; without it the deck is "void" and the ring stands across the gangplank; a looser line leaves pockets to hang in or fall through ("Region extensions") |
| `maps/000000060.json:collision.double_sided_trimesh` | true | the export's trimesh faces point outward; on the ship the player stands inside them and slipped through the bulwark and under the forecastle deck into the sea ("Region extensions") |
| `maps/000000030.json:spawn_keepouts` | 6.5 m around `X30000_HouseYellowBrim` | the yellow house's cap (12 m wide) overhangs its colliding walls; a Sentinel slot stood under it and read as inside the roof. Goes once the Blender cap collides |
| `presentation.json:environment` | sun energy = W/m² x 0.3183, preset `island_day` | Blender-to-Godot light match |
| `presentation.json:ambient_neighbours` | false | M3, not built |

## Testing

```bash
ISOLATE=world bash scripts/test.sh map_ portal_ spawn_ gate_ region_                     # L0, pure (no export needed)
ISOLATE=world INCLUDE_WORLD=1 bash scripts/test.sh map_ portal_ spawn_ gate_ region_ world_ traversal_   # + sidecar, L1, L2, L3
# one L2 pass by hand with the game's PlayerController instead of the test capsule (in an ISOLATE copy):
bash scripts/godot.sh --headless --fixed-fps 60 --quit-after 60000 --path game res://scenes/world/checks/world_checks.tscn -- --player real
bash scripts/godot.sh --headless --fixed-fps 60 --quit-after 60000 --path game res://scenes/world/checks/world_checks.tscn [-- --only gating]
bash scripts/godot.sh --path game --disable-vsync res://scenes/world/world_preview.tscn -- --map 000000040 --shot shot.png --quit
# the traversal report (L1 build, L2 routes, L2 links, L3 tours); exit 0 only when every section is clean:
bash scripts/godot.sh --headless --fixed-fps 60 --path game res://tools/traversal_bot.tscn -- [--only l1,routes,trails,tour] \
    [--map <id|slug>[,...]] [--links <link id>[,...]] [--tour edge|warp|both] [--legs <from>-<to>] --out <abs path>/docs/runtime/traversal_report.json
# windowed screenshots of the real game walking across a gate and down the ledge:
bash scripts/godot.sh --path game --resolution 1600x900 --disable-vsync res://tools/traversal_shots.tscn -- --out <dir>
```

(Use an ISOLATE copy, `_scratch/godot_runs/<name>/game`, for manual runs.)

| Test file | Level | Checks |
|---|---|---|
| `test_portal_graph.gd` | L0 | 47 PortalDefs (exactly one each), 1 arrival gate with a reason, resolution 46 reciprocal + 1 player spawn agreeing with MeowDB's lookup, directed graph = MeowDB's, BFS from 000000001 reaches 25, SCCs {1,10,20,21,30} + rest with only 30 → 40 crossing (allowlisted), every map reaches its returnMap; link modes from the data (every link two ends and two maps; portals follow their link; the arrival gate walk-only); with the export 20 trail and 4 door links, all 20 trails edge, no override (1012 ↔ 1014 edge); `force_link_mode` warp as the M1 fallback; `set_link_mode` both ways, one `link_mode_changed` per change, doors refuse edge, `all`; hidden type 1 |
| `test_gate_rules.gd` | L0 | `GateDef.step`: a grounded crossing commits at once; mid-jump arms and commits on landing; hit-stun delays the commit to its first grounded tick after; walking back past `disarm_back` disarms; no arming beside, above or below the box, or without a crossing; sizes from the data |
| `test_gate_monitor.gd` | L0 (export) | GateMonitor on a fake world and session: walking across the far gate commits via gate with the source portal and its arrival; current_map's own gate never commits; a 3.5 m jump in one tick is a teleport; hit-stun delays, a warp-mode link never commits; the one-way ledge commits 30 → 40 on landing and reports the gate into 30 as a gate without a link |
| `test_region_index.gd` | L0 (+ export) | map footprints win over trail zones; zone margin and band; the identity invariant (current map, its trails, an armed gate's map; never another map or another trail); with the export every trail's middle is trail, its mouths in its maps, both maps own it |
| `test_region_routes.gd` | L0 (export) | the identity invariant on every authored path: every route point of every map, every climbable's foot, top and top exit, every player spawn, portal anchor and NPC marker is in its own map's region and `allowed`; Southperry's ship routes (Main's end, ShipDecks, ShipForecastle, ClimbMast) lie outside the layout ring and inside the region only through the extension, in no other map; every trail centreline row lies in one of its two maps or its own zone |
| `test_world_containment.gd` | L0 | concave rings: walls outside by winding (both windings of an L shape), corners lengthened only where convex (no pillar inside the concave corner, every corner closed); `add_kept_ring`; `apply_region_extensions` in a yawed map frame (merge, `footprint_base`, kept height) and its refusals (no reason, too few points, detached); a map without a footprint is left alone |
| `test_world_trail_geometry.gd` | L0 (+ export) | `TrailGeometry` on a hand-built L-shaped trail (caps, sides, centre half the width from both sides, on the top); resampling; deck rows; with the export all 20 ribbons derived from the meshes, one width each (11 x 5.2, 8 x 3.8, 1 x 3.4 m), the bridge appended, every cap 1 m inside its gate and centred on it (the ledge end on the plane) |
| `test_map_camera_bounds.gd` | L0 (export) | camera bounds reach along every edge-mode trail and leave out the warp-mode one; warp mode gives the footprint; kill_y below every trail |
| `test_map_session_gates.gd` | L0 | on a fake world: a gate commit is one frame, places nothing, never touches input, realizes around the player, emits the three events with the source portal and records its arrival; a press-Up still takes and gives back input; 40 → 30 refused, 30 → 40 through the arrival gate records `player_spawns[0]`; `trail_changed` once per change, cleared by a map change and by reset; a save on a trail keeps current_map's portal as entry, no resume |
| `test_portal_interactor.gd` | L0 | input gating on an unbuilt IslandWorld with a stubbed session: Up and F enter when the player may act; input off, a dead player, a modal (even with input on) and a non-idle session block them, with `last_block` naming why; `set_player_input(true)` is refused under a modal and off always goes through; `set_context(GameContext)`, the parent's `ctx` fallback and `modal_provider` precedence |
| `test_map_definitions.gd` | L0 | crosswalk bijective (25), per-map API vs canonical, returnMap examples, the respawn spawn index read from death.json (and the moved-key alias); with the export: sidecar + geometry for all 25, v8 names agree, 4 door links / 20 trail links / 8 door portals, NPC parity report |
| `test_spawn_model.gd` | L0 | 50 → 37 solo, 40 → 30, 42 → 31, 45 x 80% = 36, respawn at the first tick at or after death + 5 s, timed points, mobRate ignored, capacity table = Appendix B = MeowDB's own estimates (577 / 426) |
| `test_spawn_slots.gd` | L0 | per-map per-species slot counts = MeowDB (577); the clearance capsule as tall as the species; keep-out discs; with the export: every slot placed, 1.2 m apart, 4 m from arrivals, inside the mob region, deterministic, no Sentinel under the 000000030 house cap |
| `test_map_instance_state.gd` | L0 | fresh fill, determinism, kill/respawn on the tick, capacity cap, snapshot/fast-forward, HP kept, closed form, LRU of 4; drops by uid; `NO_SLOT` never alive |
| `test_map_instance_view.gd` | L0 | the view with a stub factory; debug spawns never kill or occupy a slot; `debug_kill`; a released node cannot kill a re-realized slot |
| `test_map_session.gd` | L0 | guards, event order, 40 → 30 rejected, walk-only gate rejected by press, doors, death/respawn (4 maps), ring buffer, cache round trip and eviction, load chain, save block, debug hooks (edge works, doors refuse it); `reset()`; the death commit |
| `test_portal_one_way_ledge.gd` | L0/L1 | the 30 → 40 ledge invariant: `MovementModel.jump_apex_at_cap()` + `step_up` + 0.3 m ≤ the exported ledge height (2.4 m) ≤ 2.6 m; the face on 40's arrival gate plane (footprint + 1 m) within 0.1 m; player_spawns[0] on the landing |
| `test_map_sidecar_tolerance.gd` | L0 | missing Todd/Sam/Mai markers → logged fallback; the Phase 1 export shape; unknown added fields; authored fields win |
| `test_world_talk_zones.gd` | L0 | `WorldTuning.talk_zone`: the default zone from `npc.interaction_radius_m` / `talk_centre_height_m` (where the old half-the-radius rule put it); `across_counter` lists exactly the NPCs of the canonical shops, reaches further and is not raised, has a reason and `verified: false`; the shipped profiles are sound and `talk_zone_errors` catches a duplicate listing, a missing reason or radius and an empty profile (the first profile by name wins); `WorldNpc` builds its sphere with the zone's radius at its centre height (NAN keeps half the radius) |
| `test_npc_reach_scenario.gd` | L2 (export) | the `npcs` playtest scenario in child processes: PASS with no soft check, 21 NPCs talked to on foot from their arrival, each with a player pressing on at least 0.4 m inside its talk zone (`carry.npc_margins`), only `warp` console steps |
| `test_world_static.gd` | L1 | the island builds with **0 errors and 0 warnings**; collision layered; every arrival, player_spawns[0], NPC and slot grounded, capsule-clear, in its own map, outside other triggers and keep-outs; every ring closed except its gate gaps (probed along every ring line), the gaps open in edge mode and plugged in warp mode; 20 trails, 20 wall bodies, 40 plugs; every gate on its ring line with its portal's normal; the ribbon between the gates in no map region and in its zone; kill_y below the trails; side walls beside every ribbon edge and never on it; no other map's ring on a ribbon (except the one known case, `KNOWN_RING_CROWDING`); the ledge gate = the sidecar's gate plane; no gap wider than its corridor; no containment wall within a body capsule of any route point (every trail mouth plugged); a region extension's ring vertices on the map's ring line, and its kept wall closed below its height and open above |
| `test_traversal_routes.gd` | L2 | the route sweep (`TraversalBot.sweep`): every route of all 25 maps, both ways (one_way once), 360 runs, **0 failures** |
| `test_traversal_links.gd` | L2/L3 | three child processes of `traversal_bot.tscn`: the link runs (87, **0 failures**, all 20 trails walkable, the ledge blocks 40 → 30), the Test A tour walking the trails and the tour in warp mode (each 38 legs, ok, **0 recoveries, 0 stalls, 0 violations, 0 teleports**) |
| `test_world_transitions.gd` | L2 | `world_checks.tscn` in a child process: a build with 0 warnings; all 47 press-Up transitions, 4 doors, death in 40/1014/21/1011, the load chain, the save round trip at every map, monsters, fall recovery, the mid-air re-placement, NPC scope, portal visuals, layers and physics order, gating, commit; with the real player the **containment** walk twice: every link warp (each map closed by its ring and plugs) and the configured modes (doors closed; edge portals open onto their trails, held by the side walls, or committed through the far gate; no recovery, no invariant violation); then the region-extension rings (`_check_extension_rings`): at every metre of an extension's ring outside the layout ring, the player walks at it from the deck 1.2 to 3 m inside, jumping, then walks back without jumping: on the floor, back within 0.75 m, no recovery, no violation (`KNOWN_EXTENSION_SLOTS`, printed as WORLD_KNOWN: the main-deck slot below Southperry's forecastle) |

## Traversal (M2)

`docs/runtime/traversal_report.json` is the run on the Blender round-3 export (`traversal_bot.tscn`, `--fixed-fps 60`,
about 55 s on the dev machine). Summary:

| Section | Result |
|---|---|
| L1 build | 0 errors, 0 warnings; 20 trails with ribbons, 40 plugs, 25 rings |
| L2 routes | 25 maps, 360 runs, 0 failures |
| L2 links | 87 runs, 0 failures; `l2_links.trails_walkable`: **20 / 20 trails walkable** (20 in edge mode, no warp override). Every trail walked in each direction it allows (both ways, the one-way 30 → 40 down the ledge) with the exact `map_left → map_entered → portal_used` sequence through the gate, every link pressed in warp mode (doors both ways), walk and press-Up equivalent on every edge direction. 000001012 ↔ 000001014: 22.4 s and 68.5 m each way, 0 recoveries, 0 violations. 40 → 30: 10 s of jump spam at the ledge, the player stays in 000000040 and never reaches 30's region or the trail |
| L3 tour, edge | 38 legs over all 25 maps from a new game at 000000001, 901 s of game time, 2,758 m; 0 fall recoveries, 0 stalls, 0 invariant violations, 0 teleports; every trail leg walked (1012 → 1014 and back included), every door pressed |
| L3 tour, warp | the same 38 legs, every link pressed (`set_link_mode("all", "warp")`, which gives the same modes as `force_link_mode: "warp"`; `test_force_link_mode_warp_is_the_m1_fallback`), 631 s, 1,875 m; 0 / 0 / 0 / 0 |

The bot walks with the game's PlayerController through the real MapSession, GateMonitor and RegionMonitor. Its paths
are the trail centreline (and, in maps, Iteration One's routes, joined into a graph by `TraversalNav`); where a prop
stands on the walkable top (a trail sign or rail on a sharp bend's inner side, the 000001006 bridge's rope rails at
its bend) `TraversalPaths` replans that stretch on a 0.25 m grid with the body's own radius, as a player steps around
it. Times are game time at 60 ticks/s.

## Source world status

The Blender source is clean for warp mode (blender_export.md, "source-world fixes, round 2"): the L1 build settles
nothing and warns about nothing, the route sweep passes every route both ways (366 runs since round 4 added three).
Since round 3 all 20 trails walk (M2); since round 4 every NPC is talked to on foot. Findings:

1. **000001012 ↔ 000001014: fixed in round 3, now walked.** It was kept warp: the trail turned back in a hairpin and
   climbed inside 000001012's 1 m ring band (25 ribbon points up to 2.31 m inside its ring line), so the ring wall
   stood across the walkable top and the bot stalled. Round 3 moved 000001014 12.9 m out and re-routed the trail
   (64.9 m, 3.46 m from 000001014's ring wall and 3.74 m from 000001012's, blender_export.md); the `link_modes`
   override is gone and the traversal walks it both ways (above).
2. **000001000 → 000001006 bridge (walkable, tight; round-2 finding).** The rope rails (`*_BridgeRails`, wall class) cut across the
   inner corner of the bridge's sharp bend, leaving a squeeze about 0.5 m wide at (236.1, 22.7, 495.3), and
   `Trail_Rail_116` stands across the causeway/bridge junction at (233.1, 22.1, 493.6) with a ~0.6 m way round its
   north end. The bridge also runs 1.04 m from 000001002's ring line at (236.5, 22.8, 495.6), so that ring's wall
   narrows the deck (`KNOWN_RING_CROWDING` in `test_world_static`; Blender's own `trail_ring_band` check reports
   0.49 m in round 3). Fix: the bridge ≥ 2.5 m from 000001002's footprint. Round 3 made every `Trail_Rail` follow
   its bend (blender_export.md), which may clear `Trail_Rail_116`; the bridge's rope rails are not re-probed here.
3. **000001000 → 000001004.** 5 ribbon points lie up to 0.40 m inside 000001004's ring line at (200.88, 4.49,
   606.00), so its ring wall clips the trail edge (still walkable; `trail_ring_band` reports 0.76 m in round 3).
4. **Props on sharp bends (round-2 finding).** The trail sign at the end of 000001000 `in03`'s exit (AABB
   (186.6..187.5, 587.4..588.5)) and `Trail_Rail_151` at the 000001004 end (210.0..211.5, 615.2..616.7) stood on the
   inner side of sharp bends, inside the walkable top (the bot steps around them). The round-3 rails follow their
   bends; the sign is unchanged.
5. **Southperry's ship lies outside its layout rectangle** (handled at runtime, "Region extensions"). The ship
   <Victoria> and its decks are moored beyond 000000060's front edge, so the runtime authors the ship's ring line in
   `maps/000000060.json`. Request: carry it in the export (the ship inside the map's footprint polygon, or a
   `footprint.region_extensions` list of world XZ ring lines), so the authored polygon can go. The ship's collision
   is also built to be seen from outside: one-sided trimesh faces pointing outward (bulwarks, hull, the forecastle
   deck), an aft forecastle bulkhead that stops short of the port side (nothing at local y -6.6 from x 80 to 84),
   and a main deck that stops short of the port hull below the forecastle (x 81.2 to 82.6). The runtime turns the
   chunk's trimeshes double-sided (`collision.double_sided_trimesh`), and the deck gap stays a known slot
   (`KNOWN_EXTENSION_SLOTS`). Request: closed or double-sided collision for the hull, the bulwarks and the
   forecastle, the bulkhead across the full beam, and the main deck out to the hull; then both runtime stopgaps go.
6. **Trail centrelines in the export.** `World_Trails.json trails[]` should carry `centreline` ([[x, y, z], ...] from
   the from end) and `half_width_m` (or per-point `half_widths_m`); the runtime then stops deriving them from the
   meshes (`TrailGeometry`, a stopgap that has to cut grid T-junctions and bend folds).

7. **NPC access: fixed in round 4.** Heena (on her bush, 1.64 m above the plateau), Nina (on her stump, 2.0 m above
   the lawn) and Roger (in his garden, 3.0 m above the street, behind a hedge 1.55 m high) stood where no walk or
   jump reaches (the reach is 1.35 m); classic players clicked them from below. Round 4 gave each a walked stair (and
   Roger a gap in his hedge and fence) and a route to them, and split the roots off Nina's stump so its prism is the
   bark (blender_export.md). The shopkeepers behind counters are a talk-zone adaptation instead ("NPC talk zones").

The yellow mushroom house on 000000030: its cap overhangs its colliding walls (the brim is 12 m across and starts
2.8 m to 3 m above the ground). Round 3 gave the cap and brim an `overhead_hull` prism, 2.82 to 6.54 m above the
house base but only about 4.1 m around the centre (4.6 m at the dormer; blender_export.md), so a clearance capsule
still cannot see the outer 1.5 m of the brim. `maps/000000030.json spawn_keepouts` therefore still keeps slots 6.5 m
from the house's centre; a prism out to the brim's 6 m would let it go.

## Not built yet (M3 seams)

- **Flood-fill coverage** (§4.13 L1): not built. The trail walls, ring gaps and region checks are proved by the L1
  probes and the L2/L3 walks instead.
- **Result caching** of the per-map route runs by content hash (the whole traversal takes about a minute).
- `assemble_world.gd` / `world_index.json`: the join still runs at load (about 1 s with the trail ribbons).
- Ambient neighbours, occluder dithering (the camera system has its own), lighting presets and BGM playback (only
  the `environment_changed` signal).
- `player_spawns[1..]` repeat `[0]` until authored. Death and spawn arrivals use `[0]` (death.json
  `respawn_player_spawn_index`, open question 1).
