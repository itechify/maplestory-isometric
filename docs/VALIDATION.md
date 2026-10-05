# Validation report

Objects: 17707, triangles (evaluated, incl. instances): 9,199,727

| check | ok | detail |
|---|---|---|
| hierarchy | yes | missing top collections: [] |
| all_maps_present | yes | absent: [] |
| no_placeholders | yes | placeholder maps: [] |
| naming | yes | 0 generic names: [] |
| no_hidden_objects | yes | 0 hidden (colliders exempt): [] |
| materials | yes | 0 meshes missing materials: [] |
| instances | yes | 0 broken instances |
| polygon_budget | yes | maps over 400,000: {}; largest 1000000 (376,067) |
| world_polygon_budget | yes | WORLD layer 3,352,201 triangles (budget 3,500,000) |
| portal_topology | yes | 24 links ok-checked (1 one-way); 47 portal objects vs MeowDB 47 (missing [], extra []); arrival markers ['40000:in00']; extra portals: [] |
| floating_props | yes | 0 of 4083 instances (299 trail dressing) neither on walkable ground nor within 0.15 m of a surface (75 rest against walls/props) |
| props_near_routes | yes | 0 medium (solid at body height < 0.45 m from a route centreline), 16 low; exempt {'archway spanning the route': 2, 'perch the route walks over': 28, 'climb': 1, 'hop-able': 8}; interiors use 0.8 m |
| fidelity | yes | 21 NPC proxies vs MeowDB 21 NPCs (by MeowDB id and name); monster proxies and spawn-region species vs MeowDB species |
| traversal | yes | maps failing traversal: [] |
| portal_split | yes | 25 maps with route groups; portals split in: [] |
| orphan_routes | yes | maps with route groups that reach no portal: [] |
| player_in_gameplay_frame | yes | maps failing: [] (25 from build_report, 0 recomputed from the scene; player at 0.1..0.9 of CAM_<slug>_Gameplay, hunting maps >= 2 mobs in frame) |
| trail_walk | yes | 20/20 trails meet their expectation (19 two-way: ok both ways; 1 one-way: forward ok with its only drop at the ledge, reverse blocked at the face and nowhere else); failing: [] |
| trail_ring_band | yes | 20/20 trails clear of every containment ring wall (ring at footprint + 1.0 m, 0.5 m thick); 5 narrowings listed as low; failing: [] |
| one_way_ledge | yes | 1/1 ledges: [{'trail': 'Trail_EastEntranceMushroomTown_30000_out00_to_SnailHuntingGround1_40000', 'height_m': 2.4, 'height_max_m': 2.4, 'face_offset_max_abs_m': 0.005, 'bounds_m': [2.049, 2.6], 'found |
| player_spawns | yes | 25/25 maps have a grounded player_spawns[0] inside the footprint whose body (0.3 m) clears every press-Up trigger box (4.5 x 1.6 m); arrival map spawn >= 2.5 m inside its gate plane |
| spawn_regions | yes | 15 maps with spawn regions (150 regions) vs 15 maps with MeowDB spawns |
| collision_tags | yes | 1952 Terrain / Plinth / WORLD meshes: 1208 tagged, the rest walkable / collider / climbable / passable; untagged: 0 []; unknown class: [] |
| no_swallowed_exceptions | yes | 0 recorded: [] |

## Triangle budget

Per map: budget 400,000 (evaluated, instances included). The WORLD layer is its own line.

| layer | triangles | budget | ok |
|---|---|---|---|
| 1000000 FieldWestOfAmherst_1000000 | 376,067 | 400,000 | yes |
| 60000 Southperry_60000 | 371,142 | 400,000 | yes |
| 1000006 HuntingGroundMidForest2_1000006 | 342,843 | 400,000 | yes |
| 40001 SnailHuntingGround2_40001 | 308,927 | 400,000 | yes |
| 40002 SnailHuntingGround3_40002 | 299,693 | 400,000 | yes |
| 1020000 FieldEastOfAmherst_1020000 | 294,763 | 400,000 | yes |
| 1020001 TomatoField_1020001 | 291,553 | 400,000 | yes |
| 1000002 DangerousForest_1000002 | 268,476 | 400,000 | yes |
| 1000005 HuntingGroundMidForest1_1000005 | 264,727 | 400,000 | yes |
| 1010004 SnailFieldOfFlowers_1010004 | 263,144 | 400,000 | yes |
| 1010000 Amherst_1010000 | 249,060 | 400,000 | yes |
| 1000001 InASmallForest_1000001 | 223,436 | 400,000 | yes |
| 1000004 SnailGarden_1000004 | 207,473 | 400,000 | yes |
| 50000 ASplitRoad_50000 | 193,647 | 400,000 | yes |
| 30000 EastEntranceMushroomTown_30000 | 161,549 | 400,000 | yes |
| 40000 SnailHuntingGround1_40000 | 160,036 | 400,000 | yes |
| 1000003 MushroomGarden_1000003 | 155,749 | 400,000 | yes |
| 10000 MushroomTown_10000 | 132,989 | 400,000 | yes |
| 20000 MushroomTown_20000 | 117,195 | 400,000 | yes |
| 0 WestEntranceMushroomTown_0 | 99,184 | 400,000 | yes |
| 60001 SouthperryArmorStore_60001 | 75,405 | 400,000 | yes |
| 1010002 AmherstTownstreet_1010002 | 73,052 | 400,000 | yes |
| 1010003 AmherstDepartmentStore_1010003 | 58,720 | 400,000 | yes |
| 1010001 AmherstWeaponStore_1010001 | 38,776 | 400,000 | yes |
| 20001 MushroomTownTownstreet_20001 | 36,964 | 400,000 | yes |
| WORLD (plinth, hull, trails, scenery, clouds) | 3,352,201 | 3,500,000 | yes |
| total | 9,199,727 | | |

## Top 10 assets by instanced triangles

| asset | instances | tris / instance (with outline) | total |
|---|---|---|---|
| `Tree_Round_B` | 177 | 2,472 | 437,544 |
| `Rock_Cliff_Stone` | 8163 | 50 | 408,150 |
| `Tree_Round_A` | 174 | 2,312 | 402,288 |
| `Tree_Birch_Yellow` | 159 | 2,112 | 335,808 |
| `Tree_Tall_A` | 74 | 3,984 | 294,816 |
| `Cloud_Puff_A` | 324 | 880 | 285,120 |
| `Tree_Birch_Orange` | 128 | 2,112 | 270,336 |
| `Cloud_Puff_B` | 306 | 880 | 269,280 |
| `Mob_Snail` | 67 | 2,968 | 198,856 |
| `Tree_Autumn_A` | 79 | 2,312 | 182,648 |

Issues: 0 high, 0 medium, 21 low

- [low] props_near_routes: map 1000004: X1000004_Trellis at (23.5, 25.1) stands 0.83 m from route Summit, solid at body height 0.65 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1000004: X1000004_Trellis at (27.9, 25.1) stands 0.83 m from route Summit, solid at body height 0.65 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1000004: X1000004_Trellis at (35.8, 27.5) stands 0.85 m from route EastLedges, solid at body height 0.67 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1010001: Armor_Stand at (2.9, 5.3) stands 1.17 m from route Main, solid at body height 0.74 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1010001: X1010001_WeaponBarrel at (13.4, 1.5) stands 1.22 m from route ForgeClimb, solid at body height 0.77 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020000: Berry_Bush at (17.6, 25.4) stands 1.48 m from route West_StairsToShelves, solid at body height 0.82 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020000: Berry_Bush at (27.3, 25.3) stands 1.45 m from route West_StairsToShelves, solid at body height 0.79 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: Fence_Wood_Seg at (14.2, 0.3) stands 1.07 m from route WestBed, solid at body height 0.94 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: Fence_Wood_Seg at (16.3, 0.3) stands 1.0 m from route WestBed, solid at body height 0.86 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: Fence_Wood_Seg at (18.3, 0.3) stands 1.0 m from route WestBed, solid at body height 0.92 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: Stump_A at (17.7, 18.4) stands 0.9 m from route Climb_Vine_WestFurrow, solid at body height 0.53 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: Stump_A at (42.2, 18.4) stands 0.9 m from route Climb_Vine_EastFurrow, solid at body height 0.52 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: Crate at (46.9, 19.0) stands 1.5 m from route Canopy, solid at body height 1.03 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: X1020001_CratesTomatoes at (24.1, 22.3) stands 1.28 m from route Canopy, solid at body height 0.76 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: Haystack at (57.0, 2.0) stands 1.5 m from route EastYard, solid at body height 0.71 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] props_near_routes: map 1020001: X1020001_CratesTomatoes at (57.6, 6.0) stands 1.32 m from route EastYard, solid at body height 0.71 m from it (keep m.place props >= 1.5 m from route centrelines; medium below 0.45 m body clearance)
- [low] trail_ring_band: Trail_ASplitRoad_50000_east01_to_Southperry_60000: map 50000's ring wall stands on the trail's edge, 2.233 m from its centreline at [98.57, -533.08] (half-width 2.6 m)
- [low] trail_ring_band: Trail_ASplitRoad_50000_east00_to_FieldWestOfAmherst_1000000: map 50000's gate jamb is 1.747 m from the centreline at [124.73, -521.11] (the gap is 2.25 m either side: the trail turns before leaving it)
- [low] trail_ring_band: Trail_FieldWestOfAmherst_1000000_in05_to_HuntingGroundMidForest2_1000006: map 1000002's ring wall stands on the trail's edge, 0.49 m from its centreline at [235.87, -495.14] (half-width 1.9 m)
- [low] trail_ring_band: Trail_FieldWestOfAmherst_1000000_in03_to_SnailGarden_1000004: map 1000004's ring wall stands on the trail's edge, 0.758 m from its centreline at [201.4, -603.91] (half-width 1.9 m)
- [low] trail_ring_band: Trail_FieldEastOfAmherst_1020000_in00_to_TomatoField_1020001: map 1020001's gate jamb is 1.508 m from the centreline at [284.02, -705.2] (the gap is 2.0 m either side: the trail turns before leaving it)
