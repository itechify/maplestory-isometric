# Blender → Godot export (Iteration Two, Phase 1 prototype)

`scripts/export_runtime.py` turns `MapleIsland.blend` into Godot-ready chunks: glTF binary geometry, simplified
collision, and a JSON sidecar of gameplay markers per chunk. It is repeatable and never saves the `.blend`. This
document covers what is exported, the coordinate conventions, how the procedural materials are baked (with
measurements), the collision rules, sizes and timings, how Godot 4.7.2 imports the result, and the known problems.

This is the Phase 1 prototype. [`MAP_ARCHITECTURE.md`](MAP_ARCHITECTURE.md) §4.10 has since fixed a fuller export
contract (MeowDB-id file names, `instances.json` + MultiMesh, per-trail chunks, a scenery grid, `markers.json`). The
gaps between this prototype and that contract are listed at the end ([Contract gap](#gap-to-the-map_architecture-410-contract)).
The source world itself was then changed for the runtime (MAP_ARCHITECTURE §5 items 1–5, 2026-10-04): MeowDB portal
directions and the one-way ledge, the MeowDB NPC set, authored spawn regions and player spawns. A second round
(2026-10-04) fixed what the wave-1 runtime found in the source world (route stalls under the interior eaves and in
Tomato Field, three blocked portal arrivals, route ends a standing player could not start from) and made collision
classes data instead of name words (§5 item 6, [`collision_tags`](#classification-rules)). A third round (M2) made
the last trail walkable: 000001014 (Snail Field of Flowers) moved 12.9 m so the 000001012 ↔ 000001014 trail can leave
Townstreet's corridor and stay outside both containment rings, and the 000000030 yellow house's cap got a collision
prism ([overhead hulls](#classification-rules)). A fourth round made every NPC talkable on foot: Heena, Roger and
Nina stood on perches no player could reach (the game talks in person, classic clicked them from below), so each got
stairs (and Roger a gap in his hedge and fence). The sidecar fields they added are listed in the
[changelog](#sidecar-changelog); every change so far is additive.

## Running it

```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"       # Windows (Git Bash)
PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
B=blender; PY=python3                                                 # Linux
"$B" -b --factory-startup --python scripts/build_island.py            # rebuild MapleIsland.blend (~55 s)
"$B" -b MapleIsland.blend --python scripts/validate.py                # must stay 0 high / 0 medium (~75 s)
"$B" -b MapleIsland.blend --python scripts/export_runtime.py -- --out _scratch/export_check --check   # ~45 s: check.json only
"$B" -b MapleIsland.blend --python scripts/export_runtime.py -- --out _scratch/export_staging
"$PY" src/misostory/sidecar_diff.py --old game/assets/world --new _scratch/export_staging
MISOSTORY_EXPORT_DIR=_scratch/export_staging "$PY" src/misostory/test_sidecar_contract.py   # contract tests
"$PY" src/misostory/test_collision_tags.py                           # the passable-tag registry (no Blender)
cp _scratch/export_staging/*.glb _scratch/export_staging/*.json game/assets/world/   # only when both pass
```

Export into a staging folder first, never straight into `game/assets/world/`: other engineers run the game against
that folder. `src/misostory/sidecar_diff.py` (plain Python, no bpy) then checks the staging output against the
shipped export:

- **files:** every old file exists, every sidecar parses, and every file a sidecar lists under `files` exists;
- **schema:** additive (no key path of an old sidecar or `index.json` is missing or changes type). Only a problem
  list may become empty without counting as a removal (`sidecar_diff.EMPTIABLE`: `blockers`, `exact_fallback`,
  `exact_by_tag`, `offenders`, `overhead`, `instances_skipped`); an emptied `climbables`, `routes` or any other
  marker list fails;
- **totals:** 25 map chunks, 47 portals, 21 NPCs with MeowDB ids, 25 `player_spawns[0]`, 1 arrival point, 1 ledge,
  spawn regions on the 15 maps with MeowDB spawns, 20 trails of which 1 one-way;
- **contract, per map, against `game/data/canonical/maps` (read-only):** the NPC set by MeowDB id and name; the portal
  set by name, destination map and MeowDB's derived destination portal (the one-way portal: `to_spawn_index` 0 and a
  matching arrival point in the destination); spawn regions exactly on the maps with MeowDB spawns, with species
  hints that are MeowDB species of the map; `player_spawns[0]` inside the footprint and clear of the shipped
  collision (`spawn_clearance`); the one-way ledge invariant (`ledge_rules.py`, the same bounds `validate.py` uses:
  height in [jump apex at the cap + step-up + 0.30, 2.6] m from `movement.json`, face within 0.1 m of the gate plane,
  gate plane 1 m outside the footprint and on the runtime's containment ring (`presentation.json` `ring_offset_m`), blocked in reverse); World_Trails one-way flags;
  **portal arrivals** grounded and clear (every blocked or ungrounded one fails; they are also listed as
  `arrival_warnings`); **route ends** clear for the controller's body (`spawn_clearance.route_ends`: the route bot
  starts runs there); no route sample under a **real overhang** (`collision.summary.route_check.overhead_by_kind.body`);
  every portal **reached by a declared route** that enters its press-Up trigger box (`portal_adaptations.json`
  `trigger`, 4.5 × 1.6 m centred on the anchor: a route that stops short no longer proves the portal reachable).

It prints the added key paths, which is the changelog below. Copy only when it prints `SIDECAR_DIFF_OK True`; the
`.import` files Godot keeps next to the glbs stay in place.

`src/misostory/test_sidecar_contract.py` (plain Python `unittest`) runs that contract on a real export (the shipped
one by default, `MISOSTORY_EXPORT_DIR` for staging) and then mutates a temporary copy of its sidecars to prove each
check fails on its defect: an NPC on the wrong map or with a wrong MeowDB id, a portal to the wrong destination
portal, a one-way portal without its spawn index or arrival point, a ledge low enough to climb back or higher than a
drop, a face off the gate plane, a gate plane not at footprint + 1 m or off the containment ring, a blocked or missing or out-of-footprint player
spawn, a non-MeowDB spawn species, a hunting map without regions, a removed or retyped field, a listed file that does
not exist, missing canonical data (a failure, never a silent pass), a blocked or ungrounded portal arrival (even one
the shipped export already had), a blocked route end, a route sample under a real overhang, a door route that stops
1.5 m further from its door (outside the trigger), and an emptied `climbables` or `routes` list.

| Option | Default | Effect |
|---|---|---|
| `--out DIR` | required | Output folder (created). `game/assets/world/` is git-ignored through `game/assets/.gitignore`. |
| `--only A,B` | all | Export only these chunks (map slugs, `World_*`, `_library`). Chunk entries are merged into the existing `index.json`; its run-level fields (timings, bake, materials) then describe the partial run. |
| `--outlines shell\|none` | `shell` | `shell` keeps the inverted-hull ink outlines as real geometry. `none` drops them and writes each node's shell thickness to its extras as `outline`. |
| `--colors vertex\|flat` | `vertex` | `vertex` bakes the albedo into COLOR_0. `flat` gives each material one base color (its mean). |
| `--grid M` | `2.0` | The largest cell allowed on upward faces before the bake (see [Materials](#materials)). |
| `--no-library` | off | Skips `_library.glb`. |
| `--check` | off | Analysis only (about 45 s): writes `<out>/check.json` (per chunk: mesh classes and the rule that decided each one, raw and decimated Ground / Walls triangles, prop hulls, exact fallbacks, the route check, spawn clearance) and prints `CHECK_TOTALS`. No bake, no glb, no sidecar. |
| `--legacy-names` | off | Classifies meshes with the pre-registry name rules (`_Body`, `_Cap`, `_Fringe`, ...) instead of their collision tags. Only for before / after comparisons: two `--check` runs on one `.blend`, with and without it, match object by object except where a tag deliberately corrects the old rules (the 7 interior floor overlays, [below](#classification-rules)). |

A full run takes **4 to 5 min** on the dev machine (RTX 4070 box; the bake runs on the CPU). Phases: analysis 13 s,
collision 28-32 s, densify 15 s, bake 66-72 s, glTF writing 105-122 s. The output is byte-reproducible: two consecutive full
runs on one `.blend` wrote identical glbs (all 62 sha1 hashes match). Across a rebuild of the `.blend` the glbs keep
their sizes, node names and accessor counts but differ at float level, so compare structure, not bytes.

Exporting into `game/` means every first `--import` of the game project (for example `scripts/test.sh`) also imports
these 175 MB of glbs. That adds about 13 s, and the import cache lands in `game/.godot/`, which is ignored.

## What is exported

### Chunks

| Kind | Count | Source | Notes |
|---|---|---|---|
| `map` | 21 | `MAPS/<slug>` (`kind` ≠ interior) | Keyed by the Iteration One slug, e.g. `SnailHuntingGround2_40001`. Each map chunk also owns its `Plinth_<slug>_*` meshes (the map's base ground) and the plinth's cliff stones (anonymous instances, given to the nearest plinth cap within 3 m). |
| `interior` | 4 | `MAPS/<slug>` with `kind = interior` (20001, 60001, 1010001, 1010003) | On the interior stage at Blender x 2400–3000 m. |
| `world` | 6 | `WORLD/*` | `World_IslandBody`, `World_Plinths` (only the 52 outcrop rocks on open island ground are left), `World_Trails`, `World_Scenery`, `World_Forest`, `World_SkyAndSea`. |
| `library` | 1 | portal visuals, `Player_Proxy`, 22 NPC proxies, 5 monster proxies | One root node per asset at the origin, feet at y = 0, front = +Z. Placeholder models for the runtime. |

### Files

| File | Contents |
|---|---|
| `<chunk>.glb` | Visual geometry. One empty per group (`<chunk>__Terrain`, `__Architecture`, `__Vegetation`, `__Props`, `__Plinth`, or the WORLD collection name), with mesh nodes beneath it. |
| `<chunk>.collision.glb` | Collision only: `Ground-colonly`, `Walls-colonly` and `<item>_hull<k>-convcolonly` nodes (see [Collision](#collision)). Not written for chunks without collision. |
| `<chunk>.json` | Gameplay sidecar ([schema](#gameplay-sidecar-chunkjson)). |
| `index.json` | Chunk list with triangle counts, sizes, content hashes, marker counts, collision stats and route checks; the sun and sky (`environment`); per-material bake info (`materials`); timings and settings. |
| `_library.glb`, `_library.json` | Proxy and portal models; the asset list with heights. |

**Instances are realized as linked duplicates.** Every collection instance becomes one real object per source mesh,
and all of them share the source mesh data. The glTF exporter then writes each mesh once and points many nodes at
it, and Godot keeps that sharing (one `ArrayMesh` per glTF mesh). For example, `SnailHuntingGround2_40001` has 874
mesh nodes but 145 meshes, and `World_Forest` has 1,753 nodes but 32 meshes (1.29 MB for 1.8 M rendered triangles).
Node names are the Blender object names. Instance parts are named `<instance>__<part>` when the asset has several
meshes.

**Extras.** Each node's glTF `extras` carry `group` and, where present: `asset`, `category`, `scattered`, `walkable`,
`climbable`, `climb_z0`, `climb_z1`, `descend_only`, `passable`, `outline` and `collision` (the mesh's collision tag,
[below](#classification-rules)). Godot 4.7 imports them as node
metadata `extras` (a Dictionary), for example `{"asset": "Vine_Hanging_A", "category": "Foliage", "group": "Vegetation"}`.
The sidecar remains the gameplay authority; extras are for debugging and tools.

**Not exported as geometry:** `DEBUG` (routes, spawn rings, beacons, labels), `CAMERAS`, `LIGHTING`, the
player / NPC / monster proxies, portal visuals (all become sidecar markers; the models live in `_library.glb`), the
hidden `obj["collider"]` meshes (collision only), curves and text, and the `ENVIRONMENT_ASSETS` sources themselves.
The glbs carry no UVs, textures, cameras or lights.

## Coordinates

- **Godot (x, y, z) = Blender (x, z, −y)**, in meters. This is exactly the glTF exporter's +Y-up conversion (a −90°
  rotation about X). Chunks are in world space with no re-origin, so every glb is instanced at the identity
  transform. The island body covers Godot x −68…351 and z −84…779, its underside reaches y −250, the interiors sit at
  x 2400–3012, and the sea is at y −260. All of that is well inside float precision.
- **Transforms** (`xform`) are 12 floats: the Godot basis columns x, y, z, then the origin:

  ```gdscript
  func xform(a: Array) -> Transform3D:
      return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
          Vector3(a[9], a[10], a[11]))
  ```

- **Objects** (portals, NPCs, spawns, the player, prop collision): basis = C·R·Cᵀ, where C is the axis swap. This is
  how the exporter conjugates node transforms, because mesh data is converted the same way. **Cameras and lights**
  look down their local −Z with +Y up in Blender, glTF and Godot alike, so their basis is C·R; that is the
  exporter's extra −90° X correction. Verified by exporting two cameras, a portal, an NPC and a player proxy with
  the glTF exporter and diffing the node world transforms against the sidecar: the largest difference is 4.5e-5.
- **Facing.** Kit assets face −Y at rotation 0 in Blender, which becomes **+Z in Godot (`Vector3.MODEL_FRONT`)**.
  `yaw_deg` is Godot `rotation.y`, which equals Blender `rotation_euler.z`.
- **Ground polygons** (`*_xz`) are lists of Godot `[x, z]` = Blender `(x, −y)`.
- **Camera size.** Blender's `ortho_scale` is the frame **width** at the 16:9 reference (sensor fit AUTO). Use
  `Camera3D.keep_aspect = KEEP_WIDTH` with `size = godot_size_keep_width`, or Godot's default `KEEP_HEIGHT` with
  `godot_size_keep_height` (= width × 9/16).

## Materials

### The problem

Every Iteration One surface material computes its albedo procedurally and feeds it to the shared group
`MS_Shading` (197 of 201 materials). The albedo comes from noise, Voronoi, wave bands, normal-based top/side tint,
bbox gradients or an object-random tint. glTF cannot carry procedural nodes. A naive export (tested) does read
through the group: materials with a constant albedo (`M_Flat_*`, `M_Glow_*`, `M_Metal`, `M_Window`) come out right,
with roughness 0.75, `KHR_materials_specular` and gloss as clearcoat. But every procedural material (grass, dirt,
wood, bark, leaves, bushes, rock, cobble, mushroom spots) loses its albedo and imports **white**. The ink exports as
a lit black emissive surface rather than an unlit one.

### The pipeline

1. **Densify flat tops.** Terrace caps come from a filled curve, so each top is a fan of long triangles with
   vertices only on the boundary: up to 20 m edges on map caps, 54 m on plinths and 320 m on the island ground.
   Per-vertex color would streak across them. Each flat top is first dissolved into n-gons, then cut on a 2 m grid
   (the grid grows to √(area / 6000) for huge surfaces such as the 197,000 m² island ground). This adds 73 k faces
   net, about 2% of the exported triangles. Cutting the fans directly, without the dissolve first, shredded them
   into slivers and added 922 k faces.
2. **Bake.** `MS_Shading` is temporarily rewired to emit its Albedo input. A Cycles EMIT bake (CPU, 1 sample) then
   writes the albedo into a per-corner byte color layer `Col` on every exported mesh, once per mesh datablock. That
   is 2,627 meshes and 6.5 M corners, baked in 67 s. Batching matters: one bake call re-syncs its whole scene for
   every object, so all 2,627 meshes in one scene took over 15 minutes before it was stopped. The bake runs in
   private scenes of 30 objects (measured on 141 meshes: 11.7 s in one scene, 6.5 s in batches of 20, 74 s one by
   one).
3. **Cell patterns → mean.** Materials with a Voronoi edge-distance mortar pattern cannot be sampled per vertex: the
   mortar lines are centimetres wide and turn into grey speckle on the 2 m grid. Their corners get the material's
   mean color instead (`M_Cobble_Path`, `M_Sand_Path`, `M_X1010000_CobblePale`, `M_Stone_Cliff`, `M_Sand_Cliff`,
   `M_Rock_Cliff`, `M_StoneWall`).
4. **Rewrite materials.** Lit materials become a Principled BSDF with base color = the `Col` attribute (white factor),
   roughness 0.85 − 2 × gloss, and emission = mean albedo × the group's old Emission strength (with
   `KHR_materials_emissive_strength` above 1). `M_Outline` becomes a Background shader, which the exporter writes as
   `KHR_materials_unlit`, single-sided. Portal glows and the 60001 light shafts become emissive alpha-blended
   surfaces. Material names are kept, so the runtime can replace any of them by name.
5. **Export.** COLOR_0 is written by name (`export_vertex_color="NAME"`). The exporter's MATERIAL mode does not
   detect the Color Attribute node, and its "all vertex colors" option writes the layer a second time as COLOR_1.
   Colors arrive in Godot as linear values (checked: a plank face is 0.485 / 0.223 / 0.070 = palette `#B9824B`).

### Measured fidelity

Method (`_scratch/export_probe/look_compare.py`): 6 gameplay cameras plus `CAM_Region_MushroomTownArea`, rendered in
EEVEE at 960×540 with the island's own sun, sky and `MS_Shading` group. Only the albedo changes between variants.
Errors are against the procedural original in sRGB 0–255. "Detail" is the share of the original's high-pass
(5×5) energy that remains.

| Variant | Mean abs error | PSNR | Detail kept |
|---|---|---|---|
| Vertex colors, meshes as built | 4.70 | 30.1 dB | 0.90 |
| Vertex colors after the 2 m grid | 3.67 | 31.6 dB | 0.89 |
| **Shipped:** grid + cell patterns as mean | 3.74 | 31.8 dB | 0.87 |
| One flat color per material | 16.23 | 21.5 dB | 0.79 |

Per camera, the shipped variant scores 1.6 MAE on Mushroom Town, 1.3 on Snail Hunting Ground II and 2.1 on Hunting
Ground Middle of the Forest II, but 6.6 on Amherst and 9.1 on Southperry. **Decision: baked vertex colors.** They
keep the low-frequency painting (grass patches, the darker grass lip, leaf and bush bottom-to-top gradients, rock
tints) at about 1/4 of the flat-color error. Flat colors only hold up in the interiors (4.5 vs 3.5), which are
mostly `M_Flat_*` materials.

What vertex colors lose: every pattern finer than the vertex spacing. That covers the cobblestones and flagstones
of Amherst and Southperry (now a clean mean color), the **spots on mushroom caps** (`M_Spot_*`, an identity cue for
Mushroom Town and Amherst), wood grain (`M_Wood*`, `M_Plank`), cliff strata (`M_Dirt_Cliff`, `M_Rock_Cliff`), and the
per-instance random tint, because all instances share one baked mesh. The [open problems](#known-issues-and-open-problems)
propose the fix.

In Godot (`_scratch/export_probe/shots/godot_*.png`, using the sidecar camera and `index.json` environment): the
painted vertex colors, ink outlines and sun shadows all come through, and the frame matches the Blender gameplay
camera.

### Ink outlines

Iteration One draws ink lines as inverted-hull `SOLIDIFY` shells (flipped normals, back-face culled). By default
the exporter bakes each shell into its source mesh (shared by every copy), with the unlit, single-sided ink
material. In Godot, the shell's front faces are culled exactly as in Blender, so the outlines work with no runtime
code. The cost is 2.30 M of the 8.83 M rendered triangles (26%), 0.9 M of them in `World_Forest`, and 18 MB on disk
(173 → 155 MB with `--outlines none`). For a cheaper runtime outline, use `--outlines none` and a `next_pass`
material with `grow`. Flat-shaded meshes then need smoothed normals for the grow, or the outline cracks at hard
edges.

### Godot 4.7.2 importer bug (worked around)

`modules/gltf/gltf_document.cpp` (4.7.2-stable, lines 1414, 1460 and 1632) keeps `has_vertex_color` per mesh and
tests it *before* decoding the current primitive's COLOR_0. As a result, primitive 0 of every mesh never sets
`vertex_color_use_as_albedo` on its material, and a material used only as some mesh's first primitive imports
without vertex colors and renders white. The first full import hit this on 353 materials (counted per file). The
exporter now appends one unreferenced mesh, `_godot_vertex_color_flags`, to each visual glb. Its primitives 1..n (a
1 mm triangle each) use exactly those materials, so Godot sets the flag on the shared materials, and no node ever
instances the mesh. After re-import, 0 of 7,365 checked surfaces lack the flag. This should be reported upstream;
once it is fixed, `patch_glb_vertex_color_flags` can go.

## Gameplay sidecar (`<chunk>.json`)

Shared fields are `format`, `chunk`, `kind`, `files`, `bounds` (Godot AABB), `visual` (node/mesh/triangle counts),
`lights`, `water` and `collision`. `files` names the chunk's `visual` and `collision` glbs; an empty name means the
file is not written (only `World_SkyAndSea` has no collision). Map and interior chunks add:

| Field | Content |
|---|---|
| `map_id`, `map_name`, `street`, `map_kind` | From the map collection (GMS v8 id; the MeowDB crosswalk lives in `game/data/misostory`) |
| `meowdb_map_id` | The MeowDB map id (string, e.g. `"000000040"`), from `game/data/misostory/map_id_crosswalk.json` |
| `footprint` | Layout rectangle `outline_xz`, `base_y`, and `local_frame` (origin, yaw, L × D) |
| `portals[]` | `name`, `map`, `to_map`, `to_portal`, `kind` (`edge` / `door`), `one_way_arrival` (always `false` now: arrival-only anchors are `arrival_points`), `visual`, `position`, `yaw_deg`, `xform`, `anchor_normal_xz` (edge portals: the outward normal of the footprint edge), `one_way`, `to_arrival`, `to_spawn_index`, `to_meowdb_map_id`. The one-way portal (30000 `out00`) has `one_way: true`, `to_arrival: "in00"` and `to_spawn_index: 0`: the destination has no portal, arrivals use its `player_spawns[0]` (MAP_ARCHITECTURE §4.4). Its `to_portal` stays `"in00"` (Iteration One's v8 target, which `MapDefinitions` cross-checks against the arrival gate's anchor marker); it names the arrival point, not a portal. Otherwise `to_arrival` and `to_spawn_index` are `null`. |
| `arrival_points[]` | Arrival-only anchors (`layout.ONE_WAY`; only 40000 `in00`): `name`, `from_map`, `from_portal`, `from_meowdb_map_id`, `position`, `yaw_deg`, `xform` (facing into the map), `anchor_normal_xz` (outward), `spawn_index` (0). Not a portal: no trigger, no visual. |
| `ledges[]` | One-way trail ledges that end on this map (only 40000): `arrival_point`, `from_map`, `from_portal`, `height_m` (measured on the built ground), `authored_height_m`, `top_y`, `landing_y`, `face_offset_from_gate_m` (largest measured distance of the face from the gate plane), `gate_plane` {`point` (Godot, at landing height), `outward_normal_xz`, `offset_from_footprint_m` (1.0), `half_width_m` (2.25)}, `reverse_blocked_at_face` |
| `npcs[]` | `name`, `npc_id` (Iteration One's GMS id, an int, reference only), `role`, `proxy`, `position`, `yaw_deg`, `xform`, `meowdb_npc_id` (the MeowDB NPC id, a string: the gameplay key). Sorted by MeowDB id. |
| `spawn_points[]` | One per representative monster proxy: `species`, `proxy`, `position`, `yaw_deg` |
| `spawn_areas[]` | One per (species, walkable tier): the top outline of the ground mesh the proxy stands on (`ground`, `surface_y`, `area_m2`, `outline_xz`, `points`). Derived; kept for compatibility. Use `spawn_regions`. |
| `spawn_regions[]` | The **authored** monster spawn areas (`m.mobs` areas and `m.spawn_region`): `name`, `species` (hints; MeowDB decides species and counts), `tiers` (struct.json tier ids where authored), `source`, `proxies`, `polygon_xz` (Godot), `polygon_local` (map-local x, y), `y_band` (Godot y range of the authored height band, or `null`), `surface_y` (median walkable height in the polygon and band, 0.5 m grid on the chunk ground), `area_m2`, `walkable_fraction` |
| `spawn_counts_authored` | Iteration One's `spawns_json` (species and proxy counts) |
| `player_start` | The map's `Player_Proxy` (Iteration One's scale reference, inside the gameplay frame). Not a spawn point. |
| `player_spawns[]` | Authored player spawns (`m.player_spawn`): `index` (= MeowDB `playerSpawns[]` index; only `[0]` is authored, on every map), `position`, `yaw_deg`, `xform`, `note`, `source` (`"authored"`). On 40000, `[0]` is the landing below the one-way ledge; interiors put it just inside the door. |
| `spawn_clearance` | The export's static check of where players appear, against the **shipped** collision of every chunk in the run (prop hulls after the exact fallback, and the Walls trimeshes), mirroring the runtime's `MapDefinitions.settle`: `capsule` {`radius_m`, `height_m`, `lift_m`} (from `presentation.json` `grounding`), `arrival_inset_m` (`portal_adaptations.json` `arrival.inset_m`), `partial` (true for an `--only` run, which cannot see other chunks' hulls), `player_spawns[]` {`index`, `clear`, `blockers`}, `portal_arrivals[]` {`portal`, `clear`, `grounded`, `blockers`} (the arrival point = anchor + inset along the inward normal, grounded from 1 m above to 3 m below), and `route_ends[]` {`route`, `end` (`start` / `end`), `position`, `clear`, `blockers`}: both ends of every route, checked in the controller's own body band `route_end_body_m` [`step_up_m`, `body_height_m`] of `movement.json` (0.45–1.5 m above the feet; lower geometry is stepped onto), where the runtime's route bot starts a run. A blocked player spawn, a blocked or ungrounded arrival or a blocked route end fails `sidecar_diff`. |
| `climbables[]` | `kind` (`ladder` / `rope` / `vine`), `descend_only`, `bottom`, `top` (the validator's climb point: bbox centre xy at `climb_z0` / `climb_z1`), `foot_ground`, `top_exit` (probed standing point on the upper cap) and `facing_xz` |
| `routes[]` | The declared traversal routes as 3D polylines on the real ground (the DEBUG ribbons minus their 0.12 m lift), with `one_way` |
| `cameras.gameplay`, `cameras.overview` | `xform`, `blender_ortho_scale`, `godot_size_keep_width` / `_height`, `pitch_down_deg`, `forward`, `near` / `far`; the gameplay camera also carries `focus_local` and `gameplay_scale` from `docs/build_report.json` |

World chunks add `trails[]` and `sea_level_y` (`World_SkyAndSea`). `World_Trails` `trails[]` has one entry per
inter-map trail (20): `mesh`, `from_chunk`, `from_portal`, `to_chunk`, `to_portal`, `from_map`, `to_map`, `one_way`,
`parts` (every mesh of the trail: causeway, stair flights, landings, the ledge face) and `ledge` (the `ledges[]`
record for the one-way trail, else `null`). The entries come from tags `world.py` puts on each trail mesh
(`trail_link`, `trail_one_way`, `trail_parts`, `trail_ledge`); before that they were parsed from mesh names, which also
listed stair flights and landings as 10 bogus "trails". `index.json` holds `environment`: the sun (`xform`, `direction`, color,
Blender strength 5.5 W/m², angle), the ambient background (`#B9DCFF` × 0.36), the sky gradient and the view transform.

**Totals:** 47 portals (39 edge, 8 door, 1 one-way), 1 arrival point and 1 one-way ledge (40000), 21 NPCs (all with MeowDB ids), 205 spawn points in 175 tier areas, 150 authored spawn regions on 15 maps, 25 player starts and 25 player spawns, 144 climbables (43 ladders, 94 ropes, 7 vines; 2 descend-only), 181 routes (6,231 points, 2 one-way), 50 cameras, 25 footprints, 4 water surfaces, 12 interior lights, 2 authored colliders, and 20 trails.

## Collision

### What Godot gets

`<chunk>.collision.glb` imports, with no code, as:

- `Ground-colonly` → a `StaticBody3D` with a `ConcavePolygonShape3D` (walkable surfaces);
- `Walls-colonly` → a `StaticBody3D` with a `ConcavePolygonShape3D` (cliffs, walls, rails, exact props);
- `<item>_hull<k>-convcolonly` → one `StaticBody3D` with a `ConvexPolygonShape3D` per prop piece. Hull vertices are
  in world space, so no collision shape carries a (possibly non-uniform) scale.

Godot 4.7.2 still honours these suffixes (`nodes/use_node_type_suffixes`, on by default). Across all chunks that is
2,507 bodies: 56 concave and 2,451 convex shapes. The sidecar `collision` block repeats the prop shapes as data:
`prop_shapes` (asset-local convex prisms in Godot axes, shared per asset) and `prop_instances` (`shape`, `kind`,
`xform`). A runtime that builds shapes itself, like the MAP_ARCHITECTURE assembler, can use those. The block also
holds `authored_colliders`, `exact_fallback`, `instances_skipped` and `summary`.

### Classification rules

Collision classes come from data on the object, never from words in its name (MAP_ARCHITECTURE §5 item 6). The
registry is `src/misostory/collision_tags.py` (no bpy): the classes, `tag(obj, cls)`, the asset tag sets and the
collection-group defaults. Non-instanced meshes, in order:

| Rule | Class |
|---|---|
| `obj["collider"]` (`m.collider` perches and lids) | ground |
| `climbable` or `passable` | none (ladders and ropes are sidecar climbables) |
| `walkable` (in a GroundIndex: caps, ramps, stairs, decks, bridges, room floors, plinth caps and skirts, trails, lake banks, waterfall caps) | **ground** |
| `obj["collision"]`, set by the builder: `geo.terrace` body and cap `wall` (a walkable cap is ground by the rule above), fringe `none`; `geo.ramp_lip`, `geo.grass_fringe`, `geo.foam_ring`, `geo.path_ribbon` (`Main_Road`, paths, blends, trail aprons) and `interior.sign_text` lettering `none`; `m.rail`, a one-way trail's `LedgeFace_Body` and trail `BridgeRails` `wall`; `geo.flat_poly` on `M_Water` `water`, on sea / falls / foam `none`; the island underside, lily pads and the waterfall sheets `none` | that class (`exact` counts as wall: a mesh's exact mesh is its wall geometry) |
| Only `M_Water` (untagged) | water (sidecar `water`: outline, surface height, AABB; no solid) |
| Only waterfall / sea / foam materials (untagged) | none |
| Otherwise the collection group: `_Architecture` | **wall** (since #29 every mesh a map builds there is tagged, and `validate.py`'s `collision_tags` check fails an untagged one; room walls, parapets, frames and stalks carry `wall` by tag) |
| `_Props` | prop hull |
| `_Vegetation` (giant stems; vines and strands drop out under the size rule) | prop hull, trunk band, only if ≥ 1 m tall and ≥ 0.3 m² |
| `_Terrain`, a plinth or a WORLD collection | none (and `validate.py`'s `collision_tags` check fails any untagged mesh there, so nothing relies on this) |

The sidecar's `collision.mesh_class_source` counts which rule decided each mesh. On the shipped export: 1,228 by
tag, 740 walkable, 145 climbable or passable, 2 colliders, 94 by group (all in Architecture, Props or
Vegetation), none by material and none by name. Before the registry, the class of terrace bodies, non-walkable
caps, fringes, foam, aprons, rails and sign lettering came from name suffixes (`_Body`, `_Cap`, `_Fringe`,
`_TextMesh`, ...). `--legacy-names` still applies those rules, for comparisons only. When the registry landed, both
runs on one `.blend` gave identical classes for all 2,209 meshes, the same prop hulls and exact fallbacks,
identical raw and decimated Ground / Walls triangle counts, and the same route check and spawn clearance. Since the
review that followed, they differ by design on exactly 7 meshes: the interior floorboard and flagstone overlays
(`interior.plank_floor`: `*_Floor_Planks`, `*_Deck_Planks`, `*_Loft_Planks`, `*_Shelf_Planks`; 60001's
`flag_floor`: `*_Floor_Flags`) are tagged `none`. They are visual-only boards 3-11 mm above the walkable floor slab,
and the Architecture group default had made them a Walls slab over Ground (WORLD_RUNTIME "Current findings"), which
the runtime only accepted through its 0.05 m coplanar-ground tolerance.

Collection instances (14,192 seen, 2,313 colliding, 21 of them by their exact mesh):

| Asset | Rule |
|---|---|
| Markers, monsters, characters | none (markers only) |
| Tags in `collision_tags.PASSABLE_TAGS`: `passable`, `cloud`, `debug`, `portal`, `vine`, `flower`, `grass` | none |
| Tag `collide_exact` (`collision_tags.EXACT_TAGS`; today `Eave_Lashed_4m`) | the **exact mesh** joins the Walls trimesh (`collision.exact_by_tag`) |
| `rock` + `cliff` (the 8,148 `Rock_Cliff_Stone` set into terrace faces) | none: the body wall already blocks |
| Foliage without `hedge` or `landmark` (bushes, flowers, grass, small mushrooms, stumps, logs, crops) | none |
| Trees | trunk hull: band 0.1–1.0 m, never the canopy |
| Rocks, mountains | hull if ≥ 0.9 m tall (`Rock_A` at 0.72 m and `Rock_C` stay passable) |
| Architecture, props, hedges, landmark foliage | hull if ≥ 0.45 m tall (lower is a step) |
| Parts tagged `overhead_hull` (`collision_tags.OVERHEAD_HULL`, set by the asset's builder; today the `_Cap` and `_Brim` of 000000030's `X30000_HouseYellowBrim`) | left out of the body slice; one more prism over all of them, from their lowest point to their top |

**Hull shape.** The asset's geometry is sliced to the player's body band (0.15–1.6 m; trees 0.1–1.0 m). Each
connected piece of the slice gets a 2D convex hull, and overlapping hulls are merged, so a house is one hull but an
arch's two posts stay two. Hulls are simplified to at most 12 points and extruded from 0.3 m below the base to
min(top, 3 m). Trees therefore block at the trunk only, buildings at their walls, and overhangs not at all. The 0.3 m
sink is wrong for a prop that hangs in the air: the interior eaves (wall top 6.6 m) got a prism down to 6.3 m, 1.30 m
above the walkable ceiling beams of 1010001 and 60001, inside a standing player. Such thin overhead pieces carry the
`collide_exact` tag; the exact eave's wall plate is 1.595 m above the beams.

**Overhead prisms.** The body slice leaves an overhang without collision: the 000000030 yellow mushroom house's cap
reaches about 4.1 m from the house's centre (4.6 m at its dormer) while its walls' prism stops at 3.3 m, so a monster
or prop could stand inside the cap. Parts of an asset tagged `overhead_hull` (its builder tags them) are left out of the
body slice and get one more prism: the 2D convex hull of all of them, from their lowest point to their top. The
house's cap prism spans 2.82–6.54 m above its base (asset 2.35–5.45 m at scale 1.2), 2.78–3.66 m above the walkable
ground around the house, so a 1.5 m body walks under it and only the top of a 1.3 m jump touches it. The item keeps
one `prop_instances` entry; its `prop_shapes` entry lists both prisms, each with its own heights (the points carry
their y), and the collision glb gets `<item>_hull1-convcolonly`.

**Routes and portals are authoritative.** Iteration One walked every route over the real geometry. When a hull
covers a route sample inside the body band (0.15–1.5 m above the walk surface, samples within 0.8 m of a climbable
exempt) or covers a portal, the hull is an over-approximation. That item then collides with its **exact mesh**,
which joins the Walls trimesh. This happens for 7 items, all walked over or through on purpose: the 60001 crate heap,
the 1010001 glass tank, the 1010002 cutaway house, the 1010003 high crate, the Southperry gazebo and ship, and the
In a Small Forest giant trunk. (It used to be 16. The 4 Tomato Field plants and the West Entrance laundry basket were
props a route cut through, so the routes and the basket moved instead; the eaves now collide exactly by tag.)

**Simplification.** Ground and walls are welded (1 cm) and planar-decimated (5°). Ground goes from 1.19 M to 363 k
triangles and walls from 919 k to 357 k. The whole collision set is 10.3 MiB.

### Validation

At export, every route is sampled every 0.25 m (15,681 samples) against the shipped collision. Since #28 each sample
is a body, like the traversal validator's: its centre and two points 0.3 m (`grounding.capsule_radius_m`) either side
across the route, so a shoulder that meets a hull or a wall counts, and every `overhead[]` entry names its `ray`
(`centre`, `left`, `right`). With the side rays (2026-10-06 export: 15,782 samples) 1 sample meets a prop hull (1010003
`PoleShelf` passes 0.25 m from the 0.45 m `X1010003_Jar` on the chest shelf, a step for the controller) and 20 have
wall geometry overhead, 16 `step` and 4 `climb_or_drop`, still 0 `body`. The figures below are the single-ray round:

- **0** samples are blocked by a prop hull;
- **12** samples have wall geometry overhead in the body band (an upward ray from 0.15 to 1.5 m). Each is classified
  in `summary.route_check.overhead` (with its position, the height of the hit, the wall object and the nearest
  climbable) and counted in `overhead_by_kind`: **9 `step`** (the hit is below `step_up_m` 0.45 m: a cliff or
  terrace lip at a rope or ladder top, the step onto the 1010001 glass-tank lid or the 1010003 high crate, which the
  controller's feet mount and its floating capsule never touches), **3 `climb_or_drop`** (samples on a climbed or
  dropped segment: the A Split Road rope trio and 1010003's one-way `BeamDrop`), and **0 `body`** (a real overhang
  inside a walking player; `sidecar_diff` fails on any). Before this round there were 20, 7 of them under Tomato
  Field leaves (2 of those inside a walking body) and 1 under the West Entrance laundry basket's rim.

`spawn_clearance` adds the static standing checks: all 25 `player_spawns[0]`, all 47 portal arrival points and all
362 route ends (181 routes, both ends, in the controller's 0.45–1.5 m body band) are clear. The baseline before this
round had 3 blocked arrivals (000001000 `in02` / `in03` in their door mounds, 000001021 `out00` in a trail hedge)
and 9 blocked route ends (the two interior `Rafters` ends under the eave prisms, Tomato Field `Main`'s start in the
same hedge, and six ends 0.1–0.3 m too close to a house, a shop wall or a post: 10000 `ToYellowHouse`, 20000
`ToSensHouse`, 60000 `ArmorStore`, 60001 `TopShelf`, 1010001 `Rope`, 1010003 `PoleShelf`).

**In Godot** (this export, in an isolated copy of the game): the player sandbox's route sweep
(`player_sandbox.tscn -- --sweep all`, PLAYER_AND_CAMERA.md) completes all 360 runs (every route both ways, the two
one-way routes once) with 0 failures and 0 falls; before this round 4 failed (both `Rafters` reverse runs under the
eave prisms, `WestBed` both ways under the tomato leaves). `test_world_static` (the runtime's L1 check) logs no settle
move (it moved the 3 blocked arrivals before), the world smoke (`--world --all`) grounds the player on the first
frame on all 25 maps, and the full suite passes (`ISOLATE=... INCLUDE_WORLD=1 bash scripts/test.sh`: 897 tests).

## Sizes and timings

Final export (`index.json`, `--outlines shell --colors vertex --grid 2`). "Tris" are rendered triangles, counting
each instance; "ink" is the part of them in outline shells.

| Chunk | Tris | Ink | Nodes | Meshes | glb MiB | collision MiB | Ground / wall tris | Prop hulls |
|---|---|---|---|---|---|---|---|---|
| WestEntranceMushroomTown_0 | 125,601 | 33,592 | 332 | 79 | 3.08 | 0.11 | 5,224 / 1,944 | 31 |
| MushroomTown_10000 | 167,763 | 41,027 | 397 | 70 | 3.58 | 0.13 | 3,951 / 2,566 | 61 |
| MushroomTown_20000 | 148,042 | 31,857 | 410 | 76 | 3.51 | 0.12 | 5,286 / 2,516 | 29 |
| EastEntranceMushroomTown_30000 | 196,218 | 40,083 | 619 | 119 | 4.94 | 0.28 | 13,552 / 8,034 | 27 |
| SnailHuntingGround1_40000 | 203,567 | 37,652 | 672 | 124 | 5.70 | 0.33 | 15,832 / 11,310 | 18 |
| SnailHuntingGround2_40001 | 356,575 | 64,438 | 874 | 145 | 8.35 | 0.71 | 23,805 / 33,798 | 50 |
| SnailHuntingGround3_40002 | 348,591 | 52,331 | 1,042 | 203 | 9.54 | 0.66 | 24,795 / 29,380 | 36 |
| ASplitRoad_50000 | 238,040 | 55,785 | 630 | 114 | 6.84 | 0.28 | 10,567 / 9,288 | 51 |
| Southperry_60000 | 429,233 | 99,733 | 413 | 205 | 10.94 | 0.79 | 25,666 / 31,252 | 161 |
| FieldWestOfAmherst_1000000 | 432,404 | 95,391 | 1,355 | 227 | 12.57 | 0.63 | 30,405 / 19,160 | 59 |
| InASmallForest_1000001 | 256,753 | 69,119 | 641 | 145 | 6.05 | 0.41 | 17,098 / 15,960 | 26 |
| DangerousForest_1000002 | 305,474 | 81,533 | 828 | 116 | 5.94 | 0.25 | 10,914 / 7,224 | 46 |
| MushroomGarden_1000003 | 181,734 | 24,684 | 542 | 122 | 4.39 | 0.33 | 21,438 / 4,304 | 38 |
| SnailGarden_1000004 | 237,116 | 38,671 | 700 | 168 | 6.54 | 0.47 | 22,422 / 14,669 | 45 |
| HuntingGroundMidForest1_1000005 | 304,508 | 63,998 | 739 | 175 | 8.28 | 0.55 | 21,968 / 23,468 | 32 |
| HuntingGroundMidForest2_1000006 | 390,355 | 55,344 | 1,171 | 255 | 11.62 | 0.92 | 16,242 / 62,788 | 40 |
| Amherst_1010000 | 289,461 | 65,818 | 429 | 133 | 6.37 | 0.24 | 7,425 / 4,792 | 120 |
| AmherstTownstreet_1010002 | 93,330 | 28,566 | 178 | 61 | 3.08 | 0.13 | 2,184 / 6,014 | 32 |
| SnailFieldOfFlowers_1010004 | 298,822 | 37,565 | 865 | 130 | 5.89 | 0.28 | 12,206 / 10,150 | 24 |
| FieldEastOfAmherst_1020000 | 334,749 | 80,911 | 1,179 | 185 | 8.13 | 0.49 | 24,087 / 15,972 | 34 |
| TomatoField_1020001 | 327,969 | 76,183 | 781 | 119 | 6.57 | 0.44 | 11,876 / 9,938 | 252 |
| SouthperryArmorStore_60001 (interior) | 78,413 | 34,060 | 64 | 44 | 3.26 | 0.13 | 1,284 / 6,608 | 39 |
| MushroomTownTownstreet_20001 (interior) | 39,070 | 12,772 | 49 | 36 | 1.83 | 0.07 | 88 / 3,350 | 34 |
| AmherstWeaponStore_1010001 (interior) | 42,694 | 17,750 | 52 | 36 | 1.61 | 0.10 | 1,580 / 4,746 | 27 |
| AmherstDepartmentStore_1010003 (interior) | 62,438 | 25,234 | 80 | 56 | 2.22 | 0.14 | 3,398 / 5,010 | 39 |
| World_IslandBody | 107,854 | 0 | 4 | 4 | 4.61 | 0.14 | 6,706 / 4,990 | 0 |
| World_Plinths (outcrops) | 5,640 | 2,820 | 53 | 3 | 0.03 | 0.03 | 0 / 0 | 31 |
| World_Trails | 199,663 | 76,000 | 382 | 83 | 2.60 | 0.33 | 11,308 / 572 | 252 |
| World_Scenery | 201,181 | 61,482 | 245 | 67 | 2.80 | 0.31 | 12,798 / 7,840 | 87 |
| World_Forest | 1,846,551 | 914,120 | 1,753 | 32 | 1.29 | 0.52 | 0 / 0 | 730 |
| World_SkyAndSea | 551,764 | 0 | 614 | 3 | 0.56 | 0 | – | 0 |
| _library | 75,212 | – | – | 29 | 1.95 | – | – | – |
| **Total** | **8.88 M** | **2.32 M** | 18,091 | | **164.7** | **10.3** | 364 k / 358 k | 2,451 |

Sidecars total 2.3 MB; the largest is `World_Forest.json` at 198 KB (its 730 prop instances). A map chunk renders
93–432 k triangles including ink (65–337 k without). The visual glbs hold 3.86 M unique triangles.

**Godot 4.7.2 headless import** (`--headless --path _scratch/godot_probe --import`, all 62 glbs, 175 MB):

| Import settings | Time | Errors / warnings | `.godot/imported` |
|---|---|---|---|
| Defaults (LODs and shadow meshes generated) | 13.1 s | 0 / 0 | 118 MB |
| `meshes/generate_lods=false`, `meshes/create_shadow_meshes=false` | 8.5 s | 0 / 0 | 71 MB |

Instantiating every imported scene headless takes 636 ms in total; the slowest is `FieldWestOfAmherst_1000000.glb`
at 36 ms. All 1,243 imported materials are `StandardMaterial3D` with vertex colors as albedo, linear
(`vertex_color_is_srgb = false`), and double-sided like Blender (`cull_mode = disabled`). The ink is unshaded with
back-face culling, and the glows use alpha blending.

## Known issues and open problems

1. **Fine patterns are lost** (cobbles, mushroom spots, wood grain, strata), which hurts Amherst, Southperry and the
   mushroom houses the most. Proposal: a handful of Godot pattern shaders keyed by the preserved material names (a
   Voronoi cobble, Voronoi spots, wave bands), driven by object-space `VERTEX`. Realized copies share the source
   mesh, so object space equals Blender's object space and the patterns land where Blender put them, with the baked
   color as the base. The alternative is a UV unwrap plus a texture bake for those materials only.
2. **Node and draw-call count.** 18,051 `MeshInstance3D` nodes island-wide and up to 1,355 per map, each with 1–8
   surfaces. Godot does not auto-batch them. The fix the contract already plans: MultiMesh per (chunk, asset) from an
   instance list, plus merging each chunk's non-instanced terrain by material.
3. **Triangle budget.** The contract's gate is ≤ 2 M triangles in view; an island overview with `World_Forest` (1.8 M,
   half of it ink) exceeds it. Options: `--outlines none` with a `next_pass` outline, Godot LODs (on by default at
   import), or culling the forest at gameplay zoom.
4. **Spawn areas** (`spawn_areas`) are still the derived tier outlines; use **`spawn_regions`** instead, the authored
   polygons (`m.mobs` areas and `m.spawn_region`, persisted in the map collection's `spawn_regions_json`). A region
   without a `y_band` can span several tiers (for example 40000's `rect(16, 2, 26, 16)` covers the basin and the
   knoll's flank), so place slots by raycasting to the top walkable surface. Regions carry species *hints* (the
   proxies' v8-era species, filtered to MeowDB's species by `validate.py`) and struct.json `tiers` only on 30000;
   the assembler's tier match (MAP_ARCHITECTURE §4.7.1) must fall back to "nearest by depth band" elsewhere.
5. **Godot importer bug** (above): worked around in the export; report it upstream.
6. **Vertex colors are 8-bit linear in Godot.** With attribute compression (the import default), Godot stores
   colors as RGBA8; imported values come back in 1/255 steps. glTF COLOR_0 is linear, so dark colors band slightly. If it shows, a post-import step can store sRGB colors and set `vertex_color_is_srgb`.
7. **Per-instance tint** (`Object Info → Random` in leaf, bush, rock and mountain materials) is the same on every
   copy. It could return as a per-instance shader parameter.
8. **Collision gaps.** Stairs collide as their exact stepped mesh (the contract asks for one inclined ramp per
   flight). There are no containment walls at map or trail edges and no kill volume (use `sea_level_y` or a margin
   under the island). Water is data only. 5 climbables have no `foot_ground` within 1.5 m of `climb_z0` (the
   descend-only vines and ropes over pits). There are 20 overhead hits at lips and climbs (12 before the side rays),
   none inside a walking body (above). Tree canopies, bushes and flowers never collide, by design.
9. **Lighting is approximate in Godot.** Blender sun W/m² and EEVEE indirect light have no exact Godot equivalent.
   The probe used energy = strength / π with ambient `#B9DCFF` and linear tonemapping. A real environment preset
   belongs in `game/data/misostory`.
10. **Export time** is 4 minutes, dominated by glTF writing (105 s) and the bake (67 s). `--only` re-exports single
    chunks.
11. **Portal arrivals are clear (fixed).** 000001000 `in02` / `in03` landed inside their `Barrel_Door_Mound` and
    000001021 `out00` touched a hidden-lane `Hedge_Wall_4m`, so the runtime moved those players 0.5–1.5 m. The mounds
    now stand 3.6–3.8 m behind their portals (the arrival lands on the grass between the swirl and the closed door)
    and the lane's hedges stop at the footprint edge. `sidecar_diff` fails on any blocked arrival. The runtime's
    arrival rule is unchanged (anchor + `inset_m` along the anchor normal), so no new field was needed.
12. **Name heuristics outside the export.** What blocks a route walk is registry data too now:
    `collision_tags.passable` (a climbable or passable flag, the tag `none`, or a `PASSABLE_TAGS` asset tag) decides
    it in `traversal.obstacle_bvh` and in `validate.py`'s `props_near_routes`; the old word list (rope, sign, banner,
    lantern, flag, ...) is gone. The traversal verdicts on the island did not change. `props_near_routes` now lists 5
    more low findings the words had hidden: 4 `Fence_Wood_Seg` beside 000001014's `VineDown_*` routes (the map's slug,
    `SnailFieldOfFlowers`, contains "flower") and 000000060's `Signpost_Notice` ("sign"); both collide in the game.
    `Bush_Flowering_A` gained the `passable` tag, which keeps the validator's old verdict (no collision either way:
    plain foliage). Still name-based in `validate.py`: `ARCH_WORDS` (an archway a route passes through) and the
    floating check's ground and skip lists; they decide what the validator excuses, not what collides.

### Gap to the MAP_ARCHITECTURE §4.10 contract

| Contract item | This prototype |
|---|---|
| Output in `game/assets/world/export/`, files `<id>.visual.glb`, `<id>.collision.glb`, `<id>.instances.json`, `<id>.markers.json` keyed by the MeowDB id | `game/assets/world/<slug>.glb`, `.collision.glb`, `.json`, keyed by the Iteration One slug (as the Phase 1 task asked). A rename plus the crosswalk. |
| Instances in `instances.json` with `kit/<asset>.glb`, as MultiMesh | Realized linked duplicates (mesh reuse inside each glb). `prop_instances` already has the per-instance xforms for colliding assets; extend it to every asset and export the kit glbs. |
| `trail:<id>` chunks; `scenery:<i>_<j>` on a 128 m grid | One `World_Trails` chunk, one chunk per WORLD collection |
| Collision prefixes `walkable__` / `blocking__`, stairs as ramps, trunks as cylinders, assembler builds the shapes | `-colonly` / `-convcolonly` suffixes (Godot builds the shapes), stepped stairs, trunk hulls. The JSON prop shapes are ready for an assembler. |
| `markers.json`: `content_hash`, `frame`, `footprint`, `base_y`, `kill_y`, `camera {ortho_size, focus_local}`, `portals {name, kind, xform, anchor_normal}`, `arrival_points`, `player_spawns`, `npc_anchors`, `spawn_regions {tiers, polygon}`, `climbables`, `routes {climb_segments}`, `ledges` | All present (some under other names: `npcs` for `npc_anchors`, `footprint.local_frame` for `frame`) except `kill_y` (only the world `sea_level_y`) and `climb_segments`. `player_spawns` ships the authored `[0]` only (the other MeowDB indices are not authored); `spawn_regions` carry `tiers` only on 30000. Content hashes are in `index.json`. |
| Ownership assertion (every object in exactly one chunk, diffed against `build_report.json`) | Chunk planning gives each object one owner, but this is not asserted or diffed yet. |
| Non-instanced meshes merged by material per chunk | Not merged |

## Sidecar changelog

Every entry is additive: no field was removed or renamed, and no field changed type (`src/misostory/sidecar_diff.py`
checks this against the shipped export before each copy).

**2026-10-04: Iteration Two source-world changes** (MAP_ARCHITECTURE §5 items 1–5)

| Where | Added field(s) | Notes |
|---|---|---|
| map/interior sidecar | `meowdb_map_id` | MeowDB id string from the crosswalk |
| `portals[]` | `one_way`, `to_arrival`, `to_spawn_index`, `to_meowdb_map_id` | 30000 `out00`: `one_way: true`, `to_arrival: "in00"`, `to_spawn_index: 0`; its `to_portal` stays `"in00"` (it now names an arrival point). `one_way_arrival` is `false` on every portal. |
| map sidecar | `arrival_points[]` | 40000 `in00` only: the arrival marker that replaced the arrival-only portal |
| map sidecar | `ledges[]` | 40000 only: the measured one-way ledge and its gate plane |
| `npcs[]` | `meowdb_npc_id` | MeowDB NPC id (string). `npc_id` stays the GMS id (int). Entries are sorted by MeowDB id. |
| map sidecar | `player_spawns[]` | authored `[0]` on all 25 maps; `player_start` unchanged |
| map sidecar | `spawn_regions[]` | 150 authored regions on the 15 maps with MeowDB spawns; `spawn_areas` unchanged |
| `World_Trails` `trails[]` | `to_portal`, `from_map`, `to_map`, `one_way`, `parts`, `ledge` | One entry per trail (20). The old name-parsed list also had 10 stair-flight/landing meshes as "trails" with invalid `to_chunk` values; those entries are gone. |
| `index.json` `chunks.<name>.markers` | `arrival_points`, `ledges`, `player_spawns`, `spawn_regions`, `trails` | marker counts |

**2026-10-04: review fixes** (same day, after the source-world changes)

| Where | Change | Notes |
|---|---|---|
| map/interior sidecar | added `spawn_clearance` | the export's capsule check of player spawns and portal arrivals against the shipped collision (above) |
| `World_SkyAndSea.json` | `files.collision` `"World_SkyAndSea.collision.glb"` → `""` (same type) | that file was never written (the chunk has no collision), and the runtime logged "lists ... which does not exist" |
| 000001021 `player_spawns[0]` | moved from local (4.0, 12.0) to (4.8, 14.7) | it stood 0.26 m inside the barrel gate's south post hull, so the runtime moved it 1 m on every load |

Value changes that come with the source changes: 47 portals (was 48; 40000 `in00` is an arrival point), the 10000,
20000 and 30000 `in00` portals use `Portal_Swirl` (was `Portal_Arrival`), 21 NPCs (Todd, Sam and Mai on 000000050 in;
Paul, Tia, the Maple Administrator and Mai on Amherst out), 40000's monster proxies are all Snails (MeowDB), 1010004
gains an Orange Mushroom proxy, and `_library.json` drops `Portal_Arrival`, `NPC_Paul`, `NPC_Tia` and
`NPC_MapleAdministrator` and gains `NPC_Todd` and `NPC_Sam`. The 30000 → 40000 trail is 1 m shorter (it ends on the
gate plane) and gains `…_LedgeFace_Body` (a wall) and 8 `Rock_Cliff_Stone` boulders (no collision).

**2026-10-04: source-world fixes, round 2** (requested by the wave-1 runtime: WORLD_RUNTIME "Current findings",
PLAYER_AND_CAMERA route sweep; MAP_ARCHITECTURE §5 item 6)

| Where | Added field(s) | Notes |
|---|---|---|
| `spawn_clearance` | `route_ends[]` {`route`, `end`, `position`, `clear`, `blockers`}, `route_end_body_m` | both ends of every route in the controller's body band; all 362 clear |
| `collision` | `exact_by_tag` (list), `mesh_class_source` (rule -> count) | instances colliding by their exact mesh because their asset is tagged `collide_exact`; which rule classified each mesh (`tag`, `walkable`, `climbable/passable`, `collider`, `group`, `material`) |
| `collision.summary.route_check` | `overhead_by_kind` {`step`, `climb_or_drop`, `body`}, `overhead[]` {`route`, `at`, `hit_above_m`, `kind`, `wall`, `nearest_climb_m`} | every wall-overhead route sample, classified; `body` must be 0 |
| visual glb node extras | `collision` | the mesh's collision tag (debugging; the sidecar stays the authority) |

`sidecar_diff` now fails on any blocked or ungrounded portal arrival (it used to fail only when their number grew),
on a blocked route end and on a route sample under a real overhang. A list or data-keyed dict that is merely empty
(no blockers left, no exact fallback) no longer counts as a removed field, and `route_check.offenders` keys are data.

Value changes (no field removed, renamed or retyped):

- **Interior eaves** (1010001, 60001, 1010003): `Eave_Lashed_4m` is tagged `collide_exact`, so its 21 instances
  collide by their exact mesh (`exact_by_tag`) instead of 17 prop prisms plus 4 exact fallbacks. The prism started
  0.3 m below the 6.6 m wall top, 1.30 m above the walkable ceiling beams; the exact wall plate is 1.595 m above them.
  The `Rafters` routes of 1010001 and 60001 now run both ways (the reverse run started inside the prism).
- **Tomato Field** (000001021): `WestBed` walks round the planted ridges' ends instead of through their first and last
  plants, and `EastYard` runs down the east side of the 55.0 bank ridge and round its tip. The 4 `Tomato_Plant`
  exact fallbacks are gone (252 prop hulls, was 248) and so are the 7 overhead samples under leaves.
- **Portal arrivals**: 000001000's `DoorMound_in02` / `DoorMound_in03` stand 3.6 / 3.8 m behind their portals (was
  2.4; `in03`'s mound now faces the camera, yaw 0, and its collision reaches 0.7 m past the east edge, was 1.6 m), and the
  1020000 → 1020001 hidden lane's 20 `Hedge_Wall_4m` are laid per straight stretch, ending at the footprint edges
  (one reached 2.7 m into Tomato Field across `out00`). All 47 arrivals are clear; the runtime moves none.
- **Route ends** moved 0.1–0.35 m clear of what a standing body touched: 10000 `ToYellowHouse`, 20000 `ToSensHouse`
  (0.4 m short of `in01`), 60000 `ArmorStore` (0.4 m short of `in00`), 60001 `TopShelf`, 1010001 `Rope` (start),
  1010003 `PoleShelf`.
- **West Entrance** (000000001): Sera's laundry basket stands on her west side (it sat on the `BluffLadder` walk, so it
  collided as an exact mesh the player clipped through); it is a prop prism again (31 hulls, was 30).
- Route check: 12 overhead samples (was 20), none inside a walking body. Collision: 2,417 prop hulls (was 2,429),
  Walls 359 k triangles (was 353 k: the exact eaves).

**2026-10-04: round 2, review fixes** (adversarial review of the round above)

| Where | Change | Notes |
|---|---|---|
| interior sidecars (20001, 60001, 1010001, 1010003) | value changes only: `collision.mesh_classes`, `collision.mesh_class_source` (`group` −7, `tag` +7), `collision.summary.walls_tris(_raw)` | The 7 visual floor overlays (`interior.plank_floor`, 60001 `flag_floor`) are tagged `none`. Walls: 60001 7,194 → 6,608, 20001 3,770 → 3,350, 1010001 5,102 → 4,746, 1010003 5,334 → 5,010 triangles. Ground is unchanged; players now stand on the walkable slab, 11 mm under the board tops, and no interior floor relies on the runtime's coplanar tolerance any more. |
| `sidecar_diff` | stricter schema gate; one more contract check | An emptied list or data dict is accepted only for the problem lists in `EMPTIABLE` (round 2 had accepted any emptied container, so an export that dropped every climbable or route of a map would have passed). New: every portal must be entered by a declared route inside its press-Up trigger (all 47 are; the tightest are Amherst `in00` / `in02`, 0.75 / 0.7 m from the anchor). 30 contract tests. |

No field was added. The rebuild also moves a handful of decimated Ground / Walls counts by up to 20 triangles in
five exterior chunks (float-level differences across a rebuild; the raw counts, prop hulls, route check and
clearance are identical). Route sweep 360 / 360, world smoke 25 / 25, `IslandWorld` 0 warnings.

**2026-10-04: source-world fixes, round 3** (M2 walkability: WORLD_RUNTIME "Source world status" item 1 and the
000000030 house cap)

No field was added, removed or retyped (`sidecar_diff`: `added_paths []`, `SIDECAR_DIFF_OK True`; 30 contract tests
pass on the staged export). Value changes:

- **000001014 moved; the 000001012 ↔ 000001014 trail re-routed.** Re-shaping the trail alone was impossible: at the old
  layout 000001014's east edge ran 3.43 m from 000001012's west edge where the two footprints overlap (their last
  2.9 m), and every way from `west00` to `east00` passes that slot (Amherst and the Dangerous Forest close the others),
  but a 3.8 m trail between two rings needs 3.8 + 2 × 1.5 m = 6.8 m. `layout.LINKS` now places 000001014 52 m from
  `west00` (was 39 m, same bearing 98°), 12.9 m further back: every position in `SnailFieldOfFlowers_1010004.json`
  (portal, player spawn, spawn regions, routes, climbables, cameras, footprint) moves by Godot (+7.82, 0, −10.38);
  its routes keep their shapes (4 vine routes differ by up to 0.15 m in length, re-draped on the ground). The trail
  follows an authored route (`layout.TRAIL_ROUTES`, filleted corners, radius 4–5 m): 2 m straight out of `west00`,
  north up Townstreet's west side, round its back-west corner between the two maps' rings, north along the field's
  east side, 3.4 m straight into `east00`. It is 64.9 m long (was 42.2 m), a 10.7° ramp (rise 12.1 m) with no stairs;
  its `World_Trails.json trails[]` entry is unchanged (one part, the trail mesh). Its centreline now stays 3.46 m
  from 000001014's ring wall and 3.74 m from 000001012's (the half-width is 1.9 m), and passes each gate jamb at the
  gap's 2.2 m; before, a ring wall stood 0.003 m from it and its centreline ran inside 000001012's ring line.
  `validate.py` measures this for every trail now (`trail_ring_band`, below). Iteration One's trail walk passes both
  ways. In an isolated copy of the game with the `link_modes.overrides` entry removed, `traversal_bot.tscn` walks
  it both ways in edge mode (22.4 s, 68.5 m, the `map_left → map_entered → portal_used` sequence through the gate,
  equivalent to press-Up): 87 link runs with 0 failures, the edge-mode tour walks both 1012 ↔ 1014 legs, 0
  recoveries, stalls, invariant violations and teleports, L1 0 errors and 0 warnings, routes 360 / 360.
- **Knock-on of the move:** 000001014 is a vertex of the island outline, so `World_IslandBody` grew there (ground
  6,706 / walls 4,990 triangles, was 6,400 / 4,852); the seeded forest draws over the island's bounding box, so
  `World_Forest` is re-scattered island-wide (1,753 nodes, 730 trunk hulls, was 1,708 / 702); one plinth outcrop
  moved from `DangerousForest_1000002` to `World_Plinths` (53 outcrops) and 3 plinth stones joined 000001014;
  `World_SkyAndSea` has 614 cloud nodes (was 608). Nothing in the runtime names a forest tree.
- **Trail rails follow their bends.** Each `Trail_Rail` (a 1.8 m `Fence_Wood_Seg`, built from its origin along +X)
  now aims at the rail line 1.8 m on (its chord) instead of the centreline's tangent, so on the inner side of a bend
  it no longer cuts into the walkable top (straight runs are unchanged). `World_Trails`: 252 prop hulls (was 247:
  the longer trail's rails), 382 nodes.
- **The 000000030 yellow house's cap collides.** `X30000_HouseYellowBrim`'s `_Cap` and `_Brim` parts carry the new
  collision class `overhead_hull` (`collision_tags.OVERHEAD_HULL`): the asset gets a second prism, 2.82–6.54 m above
  its base, about 4.1 m around the centre (4.6 m at the dormer), and the walls' prism is unchanged. Under the brim
  the walkable ground is 2.78–3.66 m below the prism, so walking is unaffected. In the sidecar: `prop_shapes
  ["X30000_HouseYellowBrim"]` lists 2 prisms (was 1; the points carry their own y), still one `prop_instances` entry
  (the 000000030 `spawn_keepouts` `around_prop` still finds it), `summary.prop_hulls` 27 (was 26), `exact_fallback`
  still empty, no route sample, spawn, arrival or route end touches it.
- Totals: 2,451 prop hulls (was 2,417), 2,507 collision bodies; route check 15,681 samples (was 15,695), 12 overhead
  samples (9 step, 3 climb or drop, 0 body) as before; all 25 player spawns, 47 arrivals and 362 route ends clear.
  The other chunks differ only by float-level decimation (up to 28 Ground triangles).
- Checks on this export: `validate.py` 0 high / 0 medium (21 low: the 16 `props_near_routes` as before and the 5
  `trail_ring_band` narrowings below); the full suite (`ISOLATE=… INCLUDE_WORLD=1 bash scripts/test.sh`) ran 1,099
  tests with 1 failure, `test_interaction_main_flow`'s quest-accept checks, which fail identically on the previous
  export (an in-progress dialogue change, not the world); the route sweep, link runs, both tours, `test_world_static`
  and the world checks pass with the link still overridden to warp.

`validate.py` gained `trail_ring_band`: the build (`world.py`, `trails.ring_clearance`) samples every map's ring wall
(footprint + `ring_offset_m`, `wall_thickness_m` thick, square corners, open only at the trail's own gate gaps of
min(gate half-width, half-width + `side_wall_offset_m`), all read from `game/data/misostory`) and records in
`build_report.json trails[i].ring_clearance` how close it comes to the trail's centreline, away from and beside its
own gaps, plus any centreline point inside another map's ring line. High when a ring wall comes within the capsule
radius of the centreline or the centreline enters another map's region; low (listed) when a wall stands on a ribbon's
edge or a gate jamb is closer than the gap: today 5, all on trails the runtime already walks (the 000001006 bridge
past 000001002's ring, 0.49 m; 000001004's ring on its trail's edge, 0.76 m; the A Split Road east exits; the
Tomato Field lane's jamb).

**2026-10-04: source-world fixes, round 4** (NPC access: WORLD_RUNTIME "NPC talk zones"; the `npcs` playtest
survey found 5 of 21 NPCs a walking player could not talk to)

No field was added, removed or retyped (`sidecar_diff`: `added_paths []`, `SIDECAR_DIFF_OK True`; 30 contract tests
pass on the staged export). The truth first, with the real controller (a scratch probe on the round-3 export: a
floor height map around each NPC, every standable cell's distance to the talk zone, and real jumps toward the NPC
from 12 directions, holding the move and the jump key): **Heena** (000000001) stands on her bush's collision prism,
1.64 m above the plateau, and **Nina** (000000020) on her stump's islet, 2.0 m above the lawn; both are above the
1.35 m jump reach (apex 0.9 m at Jump 100 + the 0.45 m step), no jump came within reach of the zone and no climbable
leads up. **Roger** (000000010) stands in his garden 3.0 m above the street; the hedge top in front is 1.55 m above
the street, also out of reach. The two shopkeepers Sid and Lucy (and Pan, inside by 8 mm) are a talk-zone matter,
fixed in data (`presentation.json npc.talk_zones`), not here. Value changes:

- **Heena's stair (000000001).** `Steps_HeenaBush`: a wooden flight up the bush's east flank, 8 risers of 0.205 m over
  2.4 m (walked, no jump), 1.2 m wide, its top tread 0.1 m onto the bush's prism top (Heena's feet height) and a 1 m
  landing on over the grass clump, so Blender's ground index reaches the crown. East keeps it off the spawn and the
  `Main` route below the bush's south side; its risers face the camera. Route `ToHeena`: `Main` -> the stair -> the
  crown, 1.1 m from Heena.
- **Roger's garden steps (000000010).** `Steps_RogerGarden`: a stone flight (the map's stone, `M_StoneWall` /
  `M_Rock`) straight up the hedge face from the street to Roger, 15 risers of 0.2 m over 4.9 m, 1.8 m wide, fitted to
  the garden's cap edge. The hedge row stops 0.1 m either side of it (two `Hedge_Wall_4m`, x-scaled 1.325 and 1.125,
  instead of three), and `X10000_VegFence` is now one 3.6 m run of four posts placed twice (x 16.2 to 19.8 and 22.5
  to 26.1) with the opening between them: a single 9.6 m run would have kept its prisms across any gap in its mesh.
  Roger keeps his place in the crop gap, 1.2 m behind the fence line; the street `Planter` moved from (20.4, 18.6) to
  (18.6, 19.0), clear of the flight's foot. Route `ToRoger`: `Main` -> up the steps -> through the gap, 1.1 m from
  Roger. This answers the research's open question ("stay unreachable, or become walkable via a stair?") with a
  visible stair, because Roger starts the first quest (Roger's Apple, Test E).
- **Nina's stump stair (000000020).** `Steps_NinaStump`: a wooden flight up the stump on the camera-facing side
  (bearing 313°, halfway between the roots at 283° and 343°), 10 risers of 0.2 m over 2.8 m, fitted to the islet's
  cap edge. The stump's buttress roots are a separate asset now, `X20000_NinaStumpRoots` (Foliage, `stump`: passable
  like every stump and log): in one asset with the trunk, their tips made the stump's prism a 3.8 m circle, an
  invisible ledge 1.5 m outside the bark, 1.86 m above the lawn, that no stair to the bark could meet.
  `X20000_NinaStump` is the trunk alone: a 2.23 m prism, its top 1.86 m above the lawn. The hanging vine that
  dangled over the stair's head moved to the islet's south-west side. Route `ToNina`: `Main` -> across the lawn -> up
  the stair, 1.1 m from Nina.
- The new stairs are kept out of the maps' scattered grass and flowers (their `avoid` lists).
- Totals: 184 routes (was 181), 6,278 route points (was 6,231), all 368 route ends clear (was 362); 2,452 prop hulls
  (was 2,451: one more fence run, one hedge fewer); route check 15,789 samples, 12 overhead samples (9 step, 3 climb
  or drop, 0 body) as before; Ground triangles +836 / +1,384 / +994 in 000000001 / 000000010 / 000000020 (the
  stairs). The other chunks differ only by float-level decimation.
- Checks on this export: `validate.py` 0 high / 0 medium / 21 low as before (traversal walks the three new routes both
  ways; `props_near_routes` still 16 low); the `npcs` playtest scenario, now hard checks, talks to all 21 NPCs on
  foot from their arrivals, Heena, Roger and Nina over their routes, and every player pressing on toward an NPC
  ends at least 0.4 m inside its talk zone (WORLD_RUNTIME "NPC talk zones"); the full suite
  (`ISOLATE=npc-reach INCLUDE_WORLD=1 bash scripts/test.sh`) ran 1,119 tests with 0 failures and 0 skips: the route
  sweep 366 / 366 (was 360: the three new routes both ways), the link runs 87 / 87 with 20 / 20 trails walkable, both
  tours 0 / 0 / 0 / 0, `test_world_static` 0 errors and 0 warnings, and `smoke` now talks to Roger on foot (0
  warnings, no `goto npc 3`).

## Files

- `scripts/export_runtime.py`: the exporter.
- `src/misostory/sidecar_diff.py`: the staging check (schema additive, files, expected counts, the per-map MeowDB
  contract).
- `src/misostory/test_sidecar_contract.py`: unit tests of that check on a real export plus mutated copies.
- `src/misostory/ledge_rules.py`: the one-way ledge bounds (no bpy), shared by `traversal.py` / `validate.py` and
  `sidecar_diff.py`.
- `src/misostory/collision_tags.py`: the collision-class registry (no bpy): classes (including `overhead_hull` for
  asset parts), `tag()`, the passable and exact asset tags, the group defaults. Builders tag their meshes; the export
  and `validate.py` read the tags.
- `src/misostory/trails.py` `ring_clearance` and `layout.containment_params`: the trails' clearance from the
  runtime's containment rings, recorded in `build_report.json` and checked by `validate.py` (`trail_ring_band`);
  `layout.TRAIL_ROUTES`: authored trail routes.
- `game/assets/world/`: generated output (git-ignored).
- `_scratch/export_probe/`: survey, bake, look-comparison and transform-verification scripts, plus Godot screenshots
  (not tracked).
- `_scratch/godot_probe/`: the throwaway Godot project (`inspect.gd`, `vc_check.gd`, `shot.gd`, `bench_import.sh`).
