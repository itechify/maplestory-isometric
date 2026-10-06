# MisoStory: Maple Island

> What would classic Maple Island have felt like if MapleStory had originally been an isometric 3D game?

**Iteration One** builds **all 25 classic Maple Island maps** (GMS v0.08–v0.22 era) as one geographically
coherent, floating 3D island in **Blender 5.2**. It uses an orthographic isometric camera and a stylized,
hand-crafted, MapleStory-inspired look. Python generates everything deterministically: the `.blend` is a build
artifact, and the scripts and data are the source. The `.blend` and renders are not committed. Build them with one
command, or download them from the [latest release](https://github.com/itechify/maplestory-isometric/releases/latest).
**Iteration Two** turns that island into a playable game, and **Iteration Three** makes it the complete canonical
Maple Island, from character creation to Shanks' boat in Southperry (below).

![Island overview](docs/images/island_overview.jpg)

## Play it (Iterations Two and Three)

Iteration Two turns the island into a playable **Godot 4.7** game (`game/`), using gameplay data from
[MeowDB MS Classic](https://meowdb.com/msclassic) (see [`docs/canonical/README.md`](docs/canonical/README.md)).
Briefs: [`docs/ITERATION_TWO_BRIEF.md`](docs/ITERATION_TWO_BRIEF.md),
[`docs/ITERATION_THREE_BRIEF.md`](docs/ITERATION_THREE_BRIEF.md). Architecture:
[`docs/runtime/ARCHITECTURE.md`](docs/runtime/ARCHITECTURE.md). How-to (build, test, validate, playtest, debug):
[`docs/runtime/HOWTO.md`](docs/runtime/HOWTO.md). Adding content:
[`docs/runtime/CONTENT_AUTHORING.md`](docs/runtime/CONTENT_AUTHORING.md). What was found and fixed:
[`docs/ITERATION_LOG.md`](docs/ITERATION_LOG.md).

To play without building, download the Windows (`.zip`) or Linux (`.tar.gz`) build from the
[latest release](https://github.com/itechify/maplestory-isometric/releases/latest), unpack it and run
`MisoStory.exe` or `./MisoStory.x86_64`. To build and run from source:

```bash
bash scripts/build_runtime.sh   # once (~6 min): builds MapleIsland.blend, exports the world, imports it into Godot
bash scripts/play.sh            # launches the game (Godot 4.7.2 is downloaded on first use)
bash scripts/test.sh            # 1580+ headless tests;  bash scripts/validate_data.sh checks the canonical data
bash scripts/playtest_quests.sh # every Maple Island quest played in the real game with real input (one table)
```

| Keys | Action |
|---|---|
| W A S D | move (8 directions, relative to the camera) |
| Space / Alt | jump |
| J / Ctrl / left click | attack (and break Wooden Boxes) |
| F | talk to the NPC in front of you |
| Up arrow | enter a portal, grab a ladder or rope (W/S or Up/Down to climb) |
| Z | pick up drops |
| X | sit on your chair, or stand up |
| I / E / C / Q / K | inventory, equipment, character stats (spend AP), quest log, skills (spend SP) |
| 1 – 8 | quickslots (potions, food, a chair or a learned skill) |
| M | fold or unfold the minimap |
| Esc | close the newest window, else the pause menu (save, load, controls, quit) |
| ` (backtick) / F3 | developer console (`help`, `warp <map>`, `give <item> [qty]`, `exp <n>`, `level <n>`, `mesos <n>`) / debug overlay |

### Status

Iteration Three is complete by its own exit criterion. In the final evidence run (2026-10-06, commit `1f3120c`, on the
owner's drop and meso sources of decisions D3-11 and D3-12) the full test suite with the exported world passes (1564
tests), canonical data validation passes (0 errors, 0 warnings), and every real-game scenario passes: all 20 quests on
three seeds, and one clean character played from the creation screen to Shanks with no developer help on three seeds
headless and once in a window. The parity manifest ([`docs/MAPLE_ISLAND_PARITY.md`](docs/MAPLE_ISLAND_PARITY.md)) has
652 entries: 646 verified and 3 source-data gaps (values the sources were read for and do not give), with none left
open; every drop row is verified on its MeowDB membership and Henesys.gg rarity, its chance the owner's table. Maple
Island holds 20 quests, 6 monster species and the Wooden Box, 21 NPCs and 3 shops. Open work is tracked as GitHub
issues; what has no ticket (out of scope, source-data gaps, decisions against) is in
[`docs/DEFERRED.md`](docs/DEFERRED.md); the final report is the last section
of [`docs/ITERATION_LOG.md`](docs/ITERATION_LOG.md).

### What Iteration Three adds

- **Canonical drops with their sources kept apart** (the project owner's decision of 2026-10-06: MeowDB MS Classic and
  Henesys.gg are the only sources). What a monster or the Wooden Box drops is MeowDB's community list "Drops (MS
  Classic)", every entry; each item's rarity is Henesys.gg's label (read by hand); how
  often it drops is the owner's table by item category x rarity, a labelled MisoStory adaptation. Mesos are MeowDB's
  player report where one exists (the Snail), else the owner's level formula, at a 60% chance. Every sourced value
  keeps its raw text, URL and dated capture (decisions D3-11 and D3-12 in the iteration log; the quest-gate rule D3-9
  is the orchestrator's reading of the brief, not an owner decision).
- **Beginner mechanics:** natural HP recovery by the project owner's rule (10 HP per 10 s standing still or sitting,
  paused by moving, jumping or attacking), sitting and The Green Relaxer (with a seated cue on the HUD), the three
  Beginner skills with SP, a Skills window, skill quickslots and an effects bar for the timed buffs.
- **The Wooden Box** on its 19 canonical placements, in the camera's sight: 4 hits (basic attacks or Three Snails),
  per-placement respawn, Pio's quest items while his quest is in progress, a gold marker while a quest wants a box.
- **Every quest playable and played:** all 20 Maple Island quests run through the real game with real input in the
  every-quest set, strict (no developer help) after a logged setup, and again in one clean-character playthrough from
  character creation to Shanks with no developer help at all. The Quest Log shows chain progress, NPC maps and the
  Missable tag; the island ends at Shanks' "End of Maple Island" screen.
- **World:** a minimap on all 25 maps, NPC speech bubbles, monsters that stay on their floor and pace, visible attack
  areas, spawns clear of NPCs and the player, and a stuck-region scan of every map (its first run confirmed 42 traps
  in 13 maps; they and the ones its review found are fixed in the Blender source, and the final scan confirms none).
- **Saves v2** with a migration from Iteration Two saves (real Iteration Two saves are test fixtures).
- **A harness that clicks only what a player can:** headless runs use the windowed 1600x900 screen, a click on a
  control off the screen or under another fails, and every window stays on screen above the HUD's status bar.
- **Provenance and parity reports:** [`docs/PROVENANCE_REPORT.md`](docs/PROVENANCE_REPORT.md) (every record and
  property with its authority, URL, read time and capture; every unresolved value; every adaptation) and
  [`docs/MAPLE_ISLAND_PARITY.md`](docs/MAPLE_ISLAND_PARITY.md) (every canonical entry's state, from test and playtest
  evidence), each with a machine-readable JSON copy.

## Quick start

| What | Command (Git Bash on Windows; on Linux use `blender` and `python3`) |
|---|---|
| Get the built island without building | Download `MapleIsland.blend` and `renders-final.zip` from the [latest release](https://github.com/itechify/maplestory-isometric/releases/latest), or `gh release download --repo itechify/maplestory-isometric` |
| Build the whole island → `MapleIsland.blend` | `blender -b --factory-startup --python scripts/build_island.py` |
| Build + render every camera | `... --python scripts/build_island.py -- --render final` |
| Render cameras from an existing .blend | `blender -b MapleIsland.blend --python scripts/render_review.py -- <tag> [camera filters] [--debug]` |
| Build/render one map while authoring | `blender -b --factory-startup --python scripts/build_map.py -- <mapId> --debug` |
| Validate the island | `blender -b MapleIsland.blend --python scripts/validate.py` → `docs/VALIDATION.md` |
| Export the topology manifest | `"<blender>/5.2/python/bin/python.exe" scripts/export_manifest.py` (Linux: `python3 scripts/export_manifest.py`) |
| Asset gallery | `blender -b --factory-startup --python scripts/asset_gallery.py -- out.png Asset_A Asset_B ...` |

**Blender version:** 5.2.2 LTS, with EEVEE, Standard view transform and soft principled shading. A full build
takes well under a minute; rendering all cameras takes a few minutes on an RTX 4070.

## Viewing the island in Blender

Open `MapleIsland.blend`. It opens looking through `CAM_Island_Overview` in material preview (press Home over the
viewport to fit the camera frame if your window size differs). Every camera lives in
`CAMERAS`; set any of them active (Ctrl+Numpad 0 on a selected camera) to look through it:

- `CAM_Island_Overview`, `CAM_Island_Hero` (low angle showing the floating underside), `CAM_Island_WorldMapStyle`
  (a steeper view that reads like the classic world map), and `CAM_Island_Overview_Close`.
- `CAM_Region_*`: Maple Road, the Mushroom Town area, the Snail Hunting Grounds, Southperry and the Split Road,
  Rainbow Street, the Amherst area, and the west Amherst forests.
- `CAM_<Map>_Overview` frames a whole map; `CAM_<Map>_Gameplay` is a closer view at gameplay scale.

The `DEBUG` collection is hidden in the viewport and excluded from renders by default. Turn it on (the eye icon
in the outliner) to see traversal routes (magenta), spawn rings, NPC beacons and map labels.

## World organization

```
MAPLE_ISLAND
├─ MAPS/<Slug_ID>/{_Terrain,_Architecture,_Vegetation,_Props}   one collection per classic map (IDs disambiguate the two "Mushroom Town" maps)
├─ WORLD/{World_IslandBody, World_Plinths, World_Trails, World_Scenery, World_Forest, World_SkyAndSea}
├─ ENVIRONMENT_ASSETS/{Trees, Foliage, Rocks, Terrain, Architecture, Props, Markers}   excluded asset library; instanced everywhere
├─ CHARACTER_PROXIES/{_CharacterLibrary, Player, NPCs_<Slug>}
├─ MONSTER_PROXIES/{_MonsterLibrary, Mobs_<Slug>}
├─ PORTALS/Portals_<Slug>      portal objects carry map_id / portal_name / to_map / to_portal
├─ CAMERAS/{Cams_<Slug>, Cams_Island}
├─ LIGHTING                    one sun + sky for the whole island
└─ DEBUG/Debug_<Slug>          routes, spawn rings, NPC beacons, labels
```

- **Geography** follows the game's own classic world map (WorldMap0). Maple Island is a floating plateau.
  Mushroom Town sits in the north-west pocket, and the valley road runs south-east through the Snail Hunting
  Grounds to the fork at A Split Road. Southperry, with its lighthouse and moored ship, is on the south rim.
  Rainbow Street runs east through the Field West of Amherst, with its forest and garden side maps, to Amherst
  and the far fields. A waterfall-fed lake and conical peaks fill the interior. The layout is authored in the
  world-map frame and rotated −45°, so the isometric overview reads like the classic map.
- **Topology** is authoritative in `docs/topology.json` (raw GMS v8 WZ portal data) and is mirrored by
  `src/misostory/layout.py` (`LINKS`, `DOOR_LINKS`). Neighbouring maps are joined by physical trails between
  their edge portals. Interiors (20001, 60001, 1010001, 1010003) are cutaway rooms on a remote "interior stage"
  reached by door portals.

## Asset generation approach

- `src/misostory/geo.py`: bmesh and curve primitives. The signature MapleStory **terrace** is a rounded grass cap
  overhanging an earthen or stone body, with a jagged grass fringe and stones embedded in the cliff. There are
  also ramps, stairs, paths, water and foam.
- `src/misostory/materials.py`: procedural "painted" materials (two-tone noise, top/side tinting, gradients,
  cobble, strata, spots, streaks). They all feed one shared shading group, so the whole island can be restyled
  in one place. Inked outlines are inverted-hull solidify shells.
- `src/misostory/kit/`: a **reusable asset library** (about 120 assets) built once and instanced everywhere.
  Trees, bushes, flowers and mushrooms; rocks and peaks; Maple Island mushroom houses, cottages, shops, the
  lighthouse, the ship and docks; fences, signs, ladders and props; portal, spawn and NPC markers; the chibi
  player and NPC proxies; and the five classic monsters modeled from the v8 sprites. See `docs/ASSET_CATALOG.md`.
- `src/misostory/mapkit.py`: `MapCtx`, the authoring API every map uses. It works in map-local coordinates,
  grounds props by raycast and fails loudly when there is no ground. It also handles portals with topology
  lookup, NPCs from `npcs.py`, representative spawns, traversal routes and per-map cameras.
- `src/misostory/maps/m<ID>_<Name>.py`: one module per classic map, translating that map's research brief
  (tiers, ladders, landmarks, NPCs, monsters) into 3D.
- `src/misostory/world.py`: the island body and floating underside, map plinths, trails, the lake and
  waterfall, occlusion-aware peaks and forest, clouds and the sea far below.
- `src/misostory/traversal.py`: walks every declared route over the real geometry, checking steps, slopes,
  ladders, gaps and portal grounding.

Authoring rules and the API reference are in `docs/AUTHORING.md`.

## Working on this repo

The `.blend` and renders are build outputs: they stay out of git and are published as release assets at milestones.
See [CONTRIBUTING.md](CONTRIBUTING.md) for what to commit, the build and validate loop, how to refresh the README
images, and how to cut a release.

## Research and documentation

| Document | Contents |
|---|---|
| `docs/MAP_INVENTORY.md` | Researched inventory of all 25 classic maps: IDs, connections, NPCs, monsters, landmarks, discrepancies and decisions |
| `docs/topology.json`, `docs/topology.mmd` | Authoritative topology (portal → destination) and a Mermaid graph |
| `docs/MAPLE_ISLAND_MANIFEST.md`, `docs/manifest.json` | Built-world manifest: every map, its placement, exits and destinations, built NPCs, monsters and routes |
| `docs/research/maps/<id>_*.md` | Per-map structural analysis and 3D translation briefs |
| `docs/research/*.md` | Wiki and landmark notes, geography (classic world map), entities (NPCs and mobs) |
| `docs/ITERATION_LOG.md` | Major problems found and corrected, and the source decisions, per iteration and phase |
| `docs/DEFERRED.md` | What has no ticket: out of scope, source-data gaps, decisions against, the art reference list (open work is in the GitHub issues) |
| `docs/VALIDATION.md` | Latest Blender validation results |
| `docs/canonical/`, `game/data/canonical/` | The canonical data (MeowDB MS Classic, with Henesys.gg rarity labels on the drop records), how it was collected and its gaps |
| `tools/meowdb/captures/`, `tools/henesys/captures/` | Dated source pages read by hand in a browser (Iteration Three) |
| `docs/PROVENANCE_REPORT.md`, `docs/provenance_report.json` | Every canonical value's authority, URL, read time and capture; every unresolved value; every adaptation (`bash scripts/validate_data.sh --report`) |
| `docs/MAPLE_ISLAND_PARITY.md`, `docs/maple_island_parity.json` | Every canonical Maple Island entry with its state (missing, partial, implemented, verified) and evidence (`node tools/parity/build_parity.mjs`) |
| `docs/runtime/` | The game's architecture, systems, how-to, content authoring, playtest harness, stuck scan and reports |
| `docs/review/` | Island reviews 1 and 2 (raw critiques and triage) and the final acceptance check. The raw Iteration Three audit (`it3_audit.json`) is in git history at commit f9b2bc5 |
| `docs/images/` | Small README images (refresh with `scripts/readme_images.py`) |
| `renders/final/` | Final validation renders for every camera, plus debug variants. Generated and not in git: run `scripts/render_all.sh final 3 --debug`, or get `renders-final.zip` from a release |
| `CONTRIBUTING.md` | What goes in git, the everyday build/validate workflow, README images and releases |

## Representative renders

| | |
|---|---|
| ![Mushroom Town](docs/images/mushroom_town.jpg) Mushroom Town | ![Amherst](docs/images/amherst.jpg) Amherst |
| ![Southperry](docs/images/southperry.jpg) Southperry | ![Snail Hunting Ground II](docs/images/snail_hunting_ground.jpg) Snail Hunting Ground II |

![The floating island from below the rim](docs/images/island_hero.jpg)

Full-resolution renders of every camera are generated into `renders/final/`, or come in `renders-final.zip` on each
release:

| Subject | Files in `renders/final/` |
|---|---|
| Full island | `Island_Overview.png`, `Island_Overview_Close.png`, `Island_Hero.png`, `Island_WorldMapStyle.png` |
| Mushroom Town | `Region_MushroomTownArea.png`, `MushroomTown_10000_Gameplay.png`, `MushroomTown_20000_Gameplay.png`, `WestEntranceMushroomTown_0_Gameplay.png` |
| Amherst | `Region_AmherstArea.png`, `Amherst_1010000_Gameplay.png`, `Amherst_1010000_Overview.png` |
| Southperry | `Region_SouthperryAndSplitRoad.png`, `Southperry_60000_Gameplay.png`, `Southperry_60000_Overview.png` |
| Snail Hunting Grounds | `Region_SnailHuntingGrounds.png`, `SnailHuntingGround1_40000_Gameplay.png`, `SnailHuntingGround2_40001_Gameplay.png`, `SnailHuntingGround3_40002_Gameplay.png` |
| Western Amherst hunting areas | `Region_WestAmherstForests.png`, `DangerousForest_1000002_Gameplay.png`, `HuntingGroundMidForest1_1000005_Gameplay.png`, `HuntingGroundMidForest2_1000006_Gameplay.png`, `InASmallForest_1000001_Gameplay.png` |

Every map has `<Slug>_Overview.png` and `<Slug>_Gameplay.png`. In the final validation every check passes: hierarchy,
naming, hidden objects, materials, instances, triangle budgets, portal topology, floating props, props near routes,
traversal, route connectivity, player in the gameplay frame, the portal-to-portal walk of all 20 inter-map trails, and
swallowed exceptions.

**Proprietary reference material:** `docs/research/ref_renders`, `ref_sprites`, `ref_web` and `raw` hold Nexon
game data and art, fetched only as reference. None of it is loaded into the `.blend` or used as a texture; all
geometry and materials are original. Do not redistribute those folders.

## Known limitations

Open work: the GitHub issues. Out of scope, unsourced or decided against: `docs/DEFERRED.md`. Current validator state:
`docs/VALIDATION.md`.

- **Placeholder art.** Characters and monsters are static chibi proxies (no rigs or animation beyond procedural bob,
  lunge and a simple sit pose); skill icons and effects are procedural. There is no audio.
- **Maple Island only.** One Beginner, from character creation to Southperry: no job advancement, no Victoria Island
  (Shanks' boat ends at an "End of Maple Island" screen; nobody travels and no fare is taken), no multiplayer.
- **Drop chances are the owner's, not MapleStory's.** No source publishes drop chances: MeowDB lists who drops what
  (with votes) and Henesys.gg gives a rarity per item. The chance of each of the 86 members is the project owner's
  table by item category x rarity (`game/data/misostory/drop_rates.json`), and four of five meso amounts come from the
  owner's level formula (`meso_rules.json`); both are labelled adaptations the owner can tune. Details:
  [`docs/DEFERRED.md`](docs/DEFERRED.md).
- **MisoStory choices are labelled.** Where no source gives a value the game needs (the chair clock, skill tick and
  cast times, box placement, spawn spacing, knockback push, ground lifetime of drops), the value is an adaptation in
  `game/data/misostory/` with its reason, marked unverified. Two canonical mechanics are not applied: fall damage
  (MeowDB's rule needs a movement-update length and a per-map switch it does not publish) and crouch with the
  down-jump (the isometric maps have no pass-through floors).
- **The decisions left pending by Iteration Three were made on 2026-10-06.** Those that change the game have tickets
  (protecting The Green Relaxer from being sold, the Skills window overlapping the Quest Log, Three Snails no longer
  hitting Wooden Boxes); the others are listed with their reasons in `docs/DEFERRED.md` ("Decided, not doing").
- **Playthroughs are automated.** Every quest, Tests A-G and the Iteration Three scenarios run as scripted real-input
  playthroughs of the real game ([`docs/runtime/PLAYTEST_HARNESS.md`](docs/runtime/PLAYTEST_HARNESS.md)), headless and
  (the clean-character playthrough, the skills, the boxes and the kit) windowed; a human playthrough is still to come.
- **Approximate platform translation.** Maps keep the classic tier structure, ladders, ropes, landmarks and route
  rhythm, not pixel-exact footholds. Vertical scale is about 0.55-0.7 m per classic 60 px tier, capped near 14 m.
- **Interiors are staged remotely.** The four interiors (20001, 60001, 1010001, 1010003) are cutaway rooms on an
  "interior stage" far from the island. They are linked to their exterior doors by portals only, with no visual link.
- **Trail lengths are a layout choice.** Maps sit where the classic world map puts them, and trails stretch until
  footprints stop overlapping, so some side-map trails are longer than any classic distance.
- **One one-way link.** MeowDB MS Classic makes the `in00` portals of 10000, 20000 and 30000 ordinary two-way
  portals (Iteration One had followed the v8 arrival-only chain). Only 30000 `out00` → 40000 is one-way: 40000's
  `in00` is an arrival marker, not a portal, and the trail into it ends in a drop-down ledge you cannot climb back.
- **Mushroom Town stays on-data.** Each Mushroom Town map keeps its classic single landmark house, so from the
  island cameras the area reads as a hamlet in grassySoil meadows rather than a dense town.
- **Procedural look.** Materials are procedural painted noise with inverted-hull ink outlines. There are no
  hand-painted texture atlases, animation, water motion, particles or audio.
