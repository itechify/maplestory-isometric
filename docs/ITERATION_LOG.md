# Iteration log

This log records the major problems found during building and review, and how each was corrected, for Iteration One
(the Blender island), Iteration Two (the playable game) and Iteration Three (complete canonical Maple Island). Entries
are grouped by development phase, in order.

# Iteration One: the Blender island

## Phase 1: research and topology

| # | Problem found | Correction |
|---|---|---|
| R1 | The brief's map list had to be checked against Classic data, and the API's map lists differ by version. | maplestory.io map lists for GMS v8, v12 and v22 contain **exactly** the 25 maps in the brief. From v38–v40 onward, map 0 is the Training Camp; v56+ restructures the island; v83+ reuses map IDs for other maps. **Decision:** v8 is the baseline, and nothing from v83+ is used for topology. |
| R2 | The parsed map API drops portals: unparsed entries come back as `null` and targets as `999999999`. | Portal topology comes from the **raw v8 WZ tree** (`/api/wz/GMS/8/...`), corroborated by an independent v62-era XML dump. Completeness passes for 25/25 maps: API-parsed portals plus nulls equal the WZ portal count. |
| R3 | Two maps are both named "Mushroom Town", and the "Townstreet" names are misleading. | Maps are identified by ID everywhere (collection names end in `_<id>`). Portals show 10000 lies **west** of 20000. 20001 "Mushroom Town Townstreet" turns out to be **Sen's two-storey mushroom-house interior**, entered from 20000's house door, so it is built as an interior. |
| R4 | The Mushroom Town chain 0→10000→20000→30000→40000 is one-way in the data. | Recorded in the topology and manifest. Physically the trails exist both ways, but their exits are marked as arrival-only or one-way. |
| R5 | Placeholder monster designs were wrong: generic snails, plus a Slime and a Stump that are not on classic Maple Island. | Monster proxies were remodeled from the v8 sprites. The Snail has its own lavender slug body with a single-eyed head and a teal shell. The Blue and Red Snails share a cream body with lidded eyes and differ only in shell colour. The Shroom (spotted red-orange cap with an angry face) and the Orange Mushroom (white dumpling body, yellow-spotted cap) are separate designs. Slime and Stump were removed from the mob table. |
| R6 | Geography: where does each map sit on a real island? | The game's own classic world map (WorldMap0) was found. Maple Island is a **floating plateau** with conical peaks, a waterfall-fed lake, Mushroom Town in the north-west, a valley road down to the fork, Southperry (lighthouse and ship) on the south rim, and Amherst at the east end. The 3D island follows it, authored in the world-map frame. |

## Phase 2: framework and style

| # | Problem found | Correction |
|---|---|---|
| F1 | The first diorama render had no grass on any terrace top. | `new_from_object` returns curve meshes in local space, so the curve's Z offset was being dropped. The curve's world matrix is now baked into the mesh. |
| F2 | Cel/ramp shading flattened every slope: ramps vanished into the ground and the look was hazy. | Three style variants were compared. **Soft principled shading with Standard colour management** was chosen as more vivid and Maple-like than AgX. Ramps got dirt-trail tops so routes read. |
| F3 | Cast shadows were invisible: they fell behind objects and were washed out by sky fill. | The sun now comes from camera front-right, so shadows fall to screen-left. Sky fill went down, sun strength up, and indirect light down. Shadows are now crisp and readable. |
| F4 | The look needed MapleStory's inked feel. | Inverted-hull outlines (solidify with backface culling) were added per asset category. They cost nothing per instance and give a hand-drawn edge. |
| F5 | The first world layout overlapped 12 map pairs and read as a straight conveyor belt. | Maps are laid out in the world-map frame with a −45° world rotation, so the iso camera shows the island the way the world map draws it. Portal anchors are chained along topology links, and trails lengthen automatically until no footprints overlap. |
| F6 | Scenery (peaks, trees) could hide maps from the fixed camera. | Peaks and forest trees are tested against an occlusion "shadow" region toward the north-east of each candidate. Peaks shrink or are skipped when they would hide a map. |
| F7 | The exemplar maps had unclimbable steps, ramps of 41–45° on the knoll, and ramps ending under terrace lips. | A **traversal validator** walks every declared route over the real geometry: no ground, steps over 0.45 m, slopes over 38°, ladder coverage, portal grounding and bounds. Stairs gained a top landing. Slope is measured over a 1.2 m window so stair risers don't count as slopes. Both exemplars were fixed until they passed. |
| F8 | Portals read as white blobs. | They now use a saturated MapleStory-blue swirl core with pale rings. |
| F9 | Mushroom-house caps hid the façades from the 40° camera. | Stems are taller and bulgy, doors larger with awnings and shrubs, the blue house has a true cone cap, and stripes are softer. Applied in the kit pass. |

## Phase 3: parallel map authoring and integration

Nine author agents built the 23 remaining maps in geographic groups. Each group then went through an
independent critic and a fixer. Critics rated 7 maps "good" and 16 "needs work" before fixes (17 high-severity
issues). All 23 final builds were authored with no errors and passed traversal (`MAP_TRAVERSAL_OK True`).

| # | Problem found | Correction |
|---|---|---|
| I1 | Agents reported shared bugs: stair landings and ramp extensions z-fighting with caps; `MeshBuilder.prism(cap_mat=...)` silently ignored, and crashing with bevel; overlapping path ribbons z-fighting; paths tearing over 0.6 m lips; ropes and butterflies invisible at map scale. | Fixed centrally: stair and landing lift, gentler ramp profile, lifted extensions, prism material assignment via the known top face, ribbon layering, lower lip threshold, thicker ropes, visible butterflies. |
| I2 | The guide claimed "−x faces are visible", which is wrong for many yaws (for example world yaw −103 shows +x faces). | `m.view_dir()` gives the per-map camera direction, `build_map.py` prints it, and the guide now states the visibility rule. Windows, doors and lanterns support every facing. |
| I3 | Four trails cut through map interiors because the neighbour lay off a different edge than the anchor's (Southperry, Small Forest). | Trails now leave each portal perpendicular to its footprint edge and turn only outside maps. Southperry's `west00` moved to its back edge, where the Split Road arrives. Small Forest's `out00` moved to its front edge and the Field West's `in00` to its back edge. |
| I4 | Three trails became 37–61° stairways (very large height differences between neighbouring portals). | Those link gaps were lengthened (30 m, 32 m, 22 m) from the measured portal heights. All 20 trails are now walkable ramps of 27° or less, and the downstream maps shifted automatically. |
| I5 | The full island build took **14 minutes**. | Two O(n²) costs: `unique_name` probed `name_02…` through all objects, and every terrace evaluated the entire scene's depsgraph. Counters plus curve evaluation in a private scene brought it down to **49 s**. |
| I6 | The validator did not check climbables or props standing on routes. | It now reports ladders and ropes with no ground at the foot or top, and routes blocked by geometry under 1.4 m (naming the culprit). A first route-clearing pass removed 96 items from walkways and high-severity issues fell from 39 to 4, but it also deleted authored props; review 1 caught this (see R2-1). |

## Phase 4: island-wide review 1 → fix wave

An eight-critic review of the integrated island (six regions, one island-level critic, one technical critic)
plus a triage agent produced 23 ranked shared fixes and per-map fix lists (`docs/review/iter1_triage.json`).
Verdicts: 1 excellent, 9 good, 15 needs work, island needs work.

| # | Problem found | Correction |
|---|---|---|
| R2-1 | **My route-clearing pass deleted about 96 hand-placed props**, including brief-named landmarks such as the 1000001 giant white trunk and the 50000 mesa birch, so the renders showed a worse island than was authored. | Only instances created by `m.scatter` are tagged and may be cleared. Authored props are never deleted; they are reported as `blocked`, naming the culprit, for authors to move. |
| R2-2 | The validator passed maps whose portals no route reached (1000000 `in00` sat behind a 1.8 m wall after an anchor move), so three maps were cut off from the walkable graph. | `portal_unreachable` check: every portal needs a route point within 1.5 m at its height. Routes are walked in both directions, with `one_way=True` for jump-downs. Climbs are recognised from covering ladders and ropes, and `descend_only` vines are supported. |
| R2-3 | Layout corrections from the review. | Townstreet link shortened to 5 m (its cutaway orange house becomes the house up the lane behind Amherst). Snail Field of Flowers arrival moved to its high rim and its base lowered from 18 m to 9.5 m. Southperry's arrival moved out from behind the dome house. |
| R2-4 | Trails were brown wedges with 12 m vertical walls and floating rails, and the main road could not be traced. | New `trails.py`: smoothed swept causeways with sloped grass flanks; stone flights with landings when steeper than 20°; a pale sand **main road** on the classic Maple Road / Rainbow Street route; rails on the road edge. |
| R2-5 | Stairs read as floating tiles, ramps ended in seams under terrace lips, door portals were a glowing "snowman", and arrival-only portals looked like exits. | Solid stair blocks, ramp blend ribbons, a flat threshold glow with a chevron for doors, and a ground ring with a welcome post for arrival-only points. |
| R2-6 | Southperry was landlocked (its ship in a raised pool 34 m from the rim), and the island read as a thin pancake of stacked plinths. | Per-map rim margins: Southperry's quay is now the island cliff. The underside is a sheer 60 m wall before it tapers, in warm strata. Plinths are one cliff ring plus a sloped grass **hill skirt** with rock outcrops, so maps sit on hills. |
| R2-7 | The lake was a raised oval pool beside a "tin can" mesa, peaks were scattered at random, the forest was a uniform speckle, and the sea was blotched by the island's shadow. | Lobed lake sunk below the island ground (the ground mesh has a hole), with sloped sandy banks. Two-tier waterfall from a crescent rock cliff. Peaks follow authored ridges (cloud-ringed NW and NE massifs, low SW rim hills). The forest has a density mask (meadows, groves) plus clearings and a tree-free rim strip. The sea is self-lit, and the cloud-sea puffs are fewer and puffier. |
| R2-8 | A session limit killed all nine map fixers mid-edit. Some modules were half-changed, and the Amherst rewrite sat unapplied in scratch files. | Recovered each fixer's state from its transcript and file backups, then relaunched the fixers with their predecessor's notes and a durable per-map `PROGRESS.md`. All 25 maps went from 19 to 25 passing traversal. |
| R2-9 | The Amherst exit to Townstreet was blocked by a house hanging off the back edge, and the main-street "stairs" read as loose paving tiles. | The orange house was deleted and the exit is now a garden arch. The stairs became cobble ramps under one continuous street ribbon. The belvedere drums became a timber lookout, and the striped houses became a red tower and a yellow house. |
| R2-10 | Fixer reports surfaced shared problems: grass ramps looked like pale sheets, ribbons left flat flaps over lips and sawtooth joins, ropes read as posts, ink outlines made walkable meshes "no ground", interiors filled only 40% of their frames, and flowers cost 1.27k triangles each. | Shared wave 3, split by file ownership: <ul><li>Grass ramps got lips, fringe and bent normals.</li><li>Ribbons were rewritten with lateral lip clipping and smooth blend ribbons.</li><li>Ropes are now a swept hemp strand draped over the lip to a stake, and descend-only vines are leafy.</li><li>The ground index ignores outlines.</li><li>`m.collider` was added, and interior cameras now fit the room.</li><li>Flowers are cut to 292 triangles, and every map is under the restored 400k budget.</li></ul> |
| R2-11 | The validator's name-based "wall mounted" whitelist hid real problems, and nothing caught props standing on routes. | Floating props are now tested geometrically (on ground, or touching a surface). A new `props_near_routes` report lists solid authored props within 1.5 m of a route. |
| R2-12 | Southperry's ship still hung over 5 m of grass. Map-edge groves merged into the filler forest. The Dangerous Forest sat among bright trees. The hidden Tomato Field portal was a fenced causeway. | <ul><li>Southperry's rim margin went from 5 m to 1 m, with no plinth ring or rim wobble on its front edge and a sheer first underside ring, so the quay is the cliff.</li><li>A low shrub ring now surrounds every map.</li><li>The forest around the Dangerous Forest uses a gloomy pine palette.</li><li>The Tomato Field link is now a hedged grass lane.</li><li>Kit promotions: Hill_Door, Arch_Leafy, Hedge_Tunnel, and a white laundry sheet.</li></ul> |

## Phase 5: island-wide review 2 → fix wave 2

Nine critics reviewed the integrated island (six regions, one island-level critic, one technical critic and a
Definition-of-Done auditor), comparing every render with iter1. A triage agent merged their findings
(`docs/review/iter2_triage.json`).

Map verdicts moved from 1 excellent, 9 good and 15 needs work in iter1 to 4 excellent, 20 good and 1 needs work
(40002). Every map and the island were judged better than iter1, and the triage found no map that needs a
structural rework. The island layer and the deliverables lagged the maps.

| # | Problem found | Correction |
|---|---|---|
| R3-1 | The review's Definition-of-Done auditor was told to view all 25 Gameplay renders in two iterations. It overflowed its context and looped, re-reading the same images for about 3,000 tool calls, until the session ended. | Restarted with a strict 14-image budget focused on the checklist. The eight finished critics were reused from cache. Rule for every later critic: an explicit image cap and no re-reads. |
| R3-2 | The manifest was stale (written at 03:53, still saying "placeholder"), the README's known limitations were two sentences, and a stale `.blend1` sat in the root. | `build_island.py` now regenerates the manifest after every build using the real built trail lengths. Blender no longer writes `.blend1` backups of the build artifact. The README has a concrete known-limitations list, and DEFERRED.md has the review-2 Iteration Two candidates. |
| R3-3 | The `.blend` opened with no active camera, and the DEBUG labels cluttered the viewport. | `build.save` now opens the file through `CAM_Island_Overview` in material preview, with DEBUG hidden in the viewport. Renders still toggle DEBUG themselves. |
| R3-4 | 25 of 40 trail ends z-fought with map ground, and nothing validated walking from one map to the next. | Trails now start at the footprint edge and sit 4 cm under any map or plinth surface they meet. A draped apron ribbon carries the road surface from the edge to the portal. A new portal-to-portal **trail walk** runs over the combined ground of both maps and the trails, and `validate.py` fails on it. It immediately found that the 4 m plinth rings buried descending trails, so rings are now 0.8 m on edges that carry a portal. Flights under trails only duck 6 cm under their treads, and steep trails trade exit length for gentler flights (about 34°). Result: 20 of 20 trails walk. |
| R3-5 | Three "runway" trails of 58-82 m formed a straight comb across the forest cluster. | A layout sweep script tests bearings and gaps against overlaps, trail growth and lake clearance. 1000005 moved to bearing 84 (58 m to 12 m). 1010004 moved to 39 m / bearing 98, clear of Townstreet's west exit. 1000006 stays about 58 m because it sits behind the Dangerous Forest by design. `resolve()` now records which maps forced a link to lengthen (`LAYOUT_WARN`). Trails longer than 28 m curve through seeded lateral waypoints, and every trail's middle section relaxes away from its end maps and nearby plinths. 1000006's arrival ends in an 8 m plank bridge. |
| R3-6 | Mushroom Town read as farmsteads in a dense forest carpet with no peak pocket; the waterfall was a grey box; the cloud collar looked like rubble and the peak halos like daisies. | <ul><li>Within 60 m of maps 0-30000: grassySoil meadows with spaced big oaks, flower clumps, clear lanes between the plinths, lamp posts along the village trails, and giant toadstools on the hill skirts.</li><li>The Mushroom Town ridge moved 30-45 m out, wrapping round map 0, with hull support so its peaks place (0 rejections, logged).</li><li>The waterfall gained two stepped front tiers, flanking rocky peaks, and a draped stream into the lake.</li><li>The cloud collar is thinner, lower and flatter, and the peak halos were dropped.</li></ul> |
| R3-7 | The route validator could not see disconnected route groups, players outside the gameplay frame, or stairs with plank pads on grass caps. | Wave 0 (framework and kit engineers, working by file ownership with named contracts) added: <ul><li>New checks: a route graph (`portal_split` fails a map, `orphan_routes`), `gameplay_frame_check` / `PLAYER_IN_FRAME`, and graded `props_near_routes`.</li><li>Kit and assets: plumb ropes against the cliff face, warm reshaped `grass_rock`, soft clouds, and 1.3x mob proxies.</li><li>Authoring helpers: stairs that skip the landing on caps, `MAIN_ROAD`, and `OVERVIEW_EXTRA`.</li></ul> |
| R3-8 | After Wave 0, the stricter checks failed broadly: 5 maps with split portal groups, 16 with orphan routes, 15 with the player out of the gameplay frame (two had no player at all), and 5 props standing on routes. | Map fix wave 2 (nine group fixers, durable `PROGRESS.md` per group). <ul><li>Routes now climb mid-route, and the local `climb_route` helpers were deleted.</li><li>Every map has one connected route graph.</li><li>Players stand near each Gameplay focus; 60000's frame now shows the boarding point and Shanks.</li><li>Through-routes carry the cream `MAIN_ROAD`.</li><li>40002's crest walk was opened and given a readable rim.</li><li>40000 got a real floating islet; Mushroom Town's landmarks were scaled up.</li><li>Ramp blend ribbons now inherit the ramp's surface material.</li></ul> **Integrated validation: every check passes. 0 high, 0 medium and 11 low findings; 20/20 trails walk; all maps under budget.** |

## Phase 6: final acceptance check → must-fix pass

Seven bounded verifiers (each with a strict image budget) checked `renders/final` against review 2's acceptance
criteria and the Definition of Done, and a synthesis lead merged their findings (`docs/review/final_acceptance.json`).
Verdicts: **13 excellent, 12 good, 0 needs work**, island good. All eight island criteria passed, and validation was
all yes. Five targeted must-fix items remained:

| # | Problem found | Correction |
|---|---|---|
| F-1 | Southperry's Gameplay frame hid the boarding point: the gangplank sat 0.2 m from the main mast, behind the mast and its shrouds. Shanks's blue coat blended into the ticket booth. | <ul><li>The gangway now sits at the mid-ring position. Ray probes from the Gameplay camera chose it: 85/85 plank points visible, against 26/27 before.</li><li>The shrouds use a distance test and anchor aft of the opening.</li><li>Shanks wears red, and Tia stands on the quay in front of the booth.</li></ul> |
| F-2 | At Gameplay scale, ropes still read as stakes, or as "a pole with a knob". | The kit rope now hangs plumb and ends at the lip in a dark whipping knot, with no over-the-lip bend. A flat peg sits behind the lip, the strand is thicker (r 0.09), and the hemp is a saturated mid ochre. 30000's pale local override was removed. |
| F-3 | The waterfall cliff still read as two stacked blocks. | The crescent is now three overlapping lobes of different heights. The front tiers are irregular and non-concentric, with a low shoulder tier, boulders in the faces and bushes on the lips. |
| F-4 | 1000006's Gameplay frame was about 30% Dangerous Forest foreground, and its plank bridge didn't read as a bridge. | <ul><li>The camera focus came from a ray-cast sweep, which brought the neighbour to under 6% of the frame. One occluding tree was removed.</li><li>The bridge has dark planks, tall posts, two rope rails and deck lamps.</li><li>The sand apron no longer covers the bridge planks, and the bridge lamps now stand on the deck.</li></ul> |
| F-5 | 30000's frame showed a blank trail-flank wedge instead of its rope pitches. | The frame was refocused so both rope pitches read as climbs, and the wedge is cropped. |

Final validation after the pass: every check passes. 0 high, 0 medium and 11 low findings, 20/20 trails walk, and all
maps are under budget. The remaining verifier findings are polish and went to `docs/DEFERRED.md`.

A bounded re-check of the must-fix frames confirmed Southperry's boarding point, the 40001/1020000 ropes and the
removal of 30000's blank wedge. It found three items only partly met, which got one more targeted pass:

| # | Problem found | Correction |
|---|---|---|
| F-6 | <ul><li>Dangerous Forest pines still filled about 7-8% of the bottom of 1000006's frame.</li><li>Rope foot coils read as J-hooks, and the strands were thin at gameplay scale.</li><li>The waterfall lobes still had flat tops.</li></ul> | <ul><li>The Dangerous Forest back-fringe trees under 1000006's camera were removed or lowered; projection through the camera identified them.</li><li>Ropes lost the foot coil and are chunkier (r 0.11).</li><li>Rocky crags, boulders and trees now break the waterfall's lobe tops.</li></ul> Validation stays all yes (0 high, 0 medium, 11 low). The bridge reads as slats at region scale; a bolder bridge read is Iteration Two polish. |

---

# Iteration Two: the playable game

Brief: [`ITERATION_TWO_BRIEF.md`](ITERATION_TWO_BRIEF.md). Runtime: Godot 4.7.2 (`game/`). Gameplay data authority:
MeowDB MS Classic ([`canonical/README.md`](canonical/README.md)).

## Phase R2: canonical research and runtime decisions

| # | Problem found | Correction |
|---|---|---|
| R2-1 | MeowDB documents **MapleStory Classic World** (2026), which has its own id scheme: maps are `000000001`…`000001021`, Snail is `"2"`, the Sword is `"541"`. None of Iteration One's GMS v8 ids (`0`, `10000` … `1020001`) exist there, and no arithmetic rule maps one to the other (`0 ↔ 000000001` breaks the obvious one). | MeowDB ids are the runtime ids everywhere. `game/data/misostory/map_id_crosswalk.json` joins them to Iteration One's Blender collections, matched by evidence per map, and is validated like a compile error. |
| R2-2 | MeowDB's topology differs from Iteration One's v8 graph in exactly two ways: the Mushroom Town `in00` links are two-way, and `000000030 → 000000040` is one-way (Snail Hunting Ground I has no portal back). MeowDB also gives no destination portal names. | Destination portals are derived from MeowDB alone (the unique reciprocal portal; 46 of 47 resolve, and all agree with v8 names). The one-way link lands on the destination's player spawn and becomes a drop-down ledge in the source world. `docs/canonical/topology_diff.md` lists all 69 differences (NPCs, spawns, names). |
| R2-3 | Map contents differ from v8: Todd, Sam and Mai stand in new places, Paul, Tia and the Maple Administrator do not exist, East Entrance (a town) has 6 Tutorial Jr. Sentinels, and MeowDB's 577 spawn points replace v8's 737. | The runtime creates NPCs and spawns only from MeowDB data; Blender provides positions. The Blender NPC set is brought to parity (MAP_ARCHITECTURE §5). |
| R2-4 | Capacity rules were contradictory across proposals (spawn-point count, `mobRate`). | MeowDB's spawn-engine guide and spawn formula agree: a 7.56 s global tick, a 5 s wave cooldown, capacity `floor(points × 0.75)` solo, and MS Classic ignores `mobRate`. Stored in `formulas/spawn_rate.json`; the map pages' contrary reading is recorded as a discrepancy. |
| R2-5 | Several mechanics have no MeowDB value: drop chances and meso amounts, drop lifetime, natural regeneration, bare-handed damage, player and monster knockback distances, HP/MP after respawn, and how many Roger's Apples Roger gives. | Each stays `null` in canonical data with a recorded gap. The game uses isolated adaptation values in `game/data/misostory/` marked `"verified": false` (list in `docs/canonical/README.md`). |
| R2-6 | The quest the brief suggested (Roger's Apple, 1002) gives no reward in MS Classic, so it cannot prove "exact canonical reward". | Sam's Suggestion (1006: kill 10 Snails, 30 EXP + 3 Eggs) is the primary end-to-end quest; Roger's Apple is implemented alongside it for the item-use objective. |
| R2-7 | MeowDB's Terms forbid automated collection without permission, and its reuse policy asks that bulk datasets be cleared first. This was only checked after the one-time extraction (524 requests: about 230 pages, 210 API calls and 84 JavaScript bundles, rate-limited and cached; first logged here as "about 300 pages"). | The extractors are now cache-only (`MEOWDB_ALLOW_NETWORK=1` is required to fetch). Verbatim MeowDB site code stays out of git. Every record carries its source URL, and permission must be requested before MisoStory or its dataset is published. |
| R2-8 | Runtime map model: per-map scenes would discard Iteration One's 447 m of validated trails, while a continuous world with inferred map identity breaks MapleStory's one-map semantics. | A 3-proposal judge panel chose the "instanced continuous" island ([`runtime/MAP_ARCHITECTURE.md`](runtime/MAP_ARCHITECTURE.md)). One continuous island is resident, exactly one MeowDB map instance is live, and `MapSession.transition()` is the only thing that changes it. Press-Up warp mode ships first, and walkable trail gates come second. |
| R2-9 | The first perf gate read 4 fps with 265 ms of CPU per frame, even for an empty scene. | A background window's vsync presentation is throttled by the OS. Measured with `--disable-vsync`, every gameplay view runs at 2–3.5 ms per frame and the island overview at 11.6 ms, so all 31 chunks stay resident and no streaming is needed. |
| R2-10 | A plain glTF export turned every procedural material white, and Godot 4.7.2's importer drops "vertex color as albedo" on each mesh's first primitive. | The exporter bakes albedo into vertex colors with Cycles (mean error 3.7/255 against the Blender render) and adds an unused dummy primitive per mesh as a workaround (`blender_export.md`). |
| R2-11 | Later (2026-10-04, after F1): the cache-only rule of R2-7 blocked fetching any page not already cached. | At the project owner's request, `lib.mjs` fetches uncached pages live again (still cache-first and 1.2 s apart; `--refresh` re-fetches). The owner made this call; it is not a permission from MeowDB, so R2-7's rule about publishing still applies. |

## Phase S2: core systems (wave 1: eight engineers, each followed by an adversarial reviewer)

Combat mathematics, items, quests and dialogue, saves, the world runtime (warp mode), the player controller and
camera, source-world fixes, and data validation were built in parallel on disjoint file ownership against contract
stubs (`docs/runtime/ARCHITECTURE.md`). Reviewers found 86 defects and fixed 80; the rest were cross-system requests,
resolved by the orchestrator or carried into wave 2. Result: 642 tests, all 818 MeowDB parity vectors exact.

| # | Problem found | Correction |
|---|---|---|
| S2-1 | The validator and the test runner could fail open: a GDScript runtime error only aborts the current function, so a crashed check printed `VALIDATION_PASSED`, and a test file with a parse error counted as 0 tests. A parse error in a validator dependency hung the tool forever. | `ScriptErrorGuard` (an `OS` logger) turns any script error during validation or a test into a failure. Uncompilable test files count as failed. Both shell scripts run under an outer timeout. |
| S2-2 | A save slot left with only its `.bak` (Windows rename removes the old file first) was treated as empty, so a new game overwrote the backup: real data loss. | Backup-only slots are recognised and restored; atomic writes and restore failures are checked. |
| S2-3 | After a load, MapSession kept the player in the old map and its periodic location capture overwrote the loaded character's position. Autosave on map arrival called a method that did not exist. | MapSession reacts to `Game.character_replaced` with a load transition; autosave goes through `Game.request_autosave`. |
| S2-4 | MapSession read the floor flag before the player body moved, so a mid-air warp arrival counted as grounded on frame 1. A portal request could also be redirected to a different neighbour of the current map. | ARRIVING runs after the player's physics step. Requests are checked against the portal's own destination and arrival. |
| S2-5 | Picking up an item whose record carried a `mesos` key paid mesos instead of the item. A non-string item id in a save crashed loading. A purchase quantity overflowed 64-bit price math. | The pickup shape is explicit; ids are normalised on load; quotes are overflow-guarded. All are covered by new tests. |
| S2-6 | A quest's EXP reward emitted a single `leveled_up` and no HP/MP events, so the HUD went stale after a quest level-up. A refused quiz completion still marked the quiz answered. | Quest rewards go through the same event path as `Game.gain_exp`. Refused completions change nothing. |
| S2-7 | The controller false-landed on ledge edges, flickered between ground and air in V-shaped crevices, and could record a "safe" point on a fence top. | Landings need a feet ray over walkable floor. Wedges are their own state, and SafeGround accepts walkable collision inside the current region only. |
| S2-8 | The 30000 → 40000 trail walk accepted any 2.6 m drop anywhere, and the export gate checked only island-wide totals, so a misplaced NPC or a blocked spawn would pass. | The one-way trail must drop exactly at its ledge (2.4 m, face 5 mm from the gate plane). `sidecar_diff` checks NPC ids, destinations, regions, ledges and spawn clearance per map. |
| S2-9 | Equipment requirements, shield guard and the bare-hands W.ATK line read different sources from the stat totals, so they could disagree. | One `StatCalculator.bonuses()` feeds totals, guard, requirements and the stat window. |

## Phase P2: the playable game (wave 2: shell, monsters and combat, NPC UI and loot, HUD, debug tools, Blender round 2)

The game became playable end to end: title → character creation (canonical creation weapons, 9 AP) → loading →
the island with live MeowDB spawns, attacks, damage numbers, contact damage, EXP and level-ups, drops and pickup,
NPC dialogue and quests, shops, the HUD and windows, death and respawn, a debug console and overlay. Reviewers
probed the running game rather than sandboxes and found 32 defects; the worst are below. Suite: 922 tests.

| # | Problem found | Correction |
|---|---|---|
| P2-1 | After the debug console closed, the player could never move again: the console swapped the player's input source, and the attack lock re-wrapped the swapped source instead of restoring the keyboard. | The attack lock no longer mutates sources it did not create. Console sessions are fenced and fully restored, with a regression test in the real main scene. |
| P2-2 | A monster-contact death announced `player_died` twice. A dialogue or shop open at death survived the respawn and let the player walk under a modal. A load from the death screen left the shell stuck in its DEAD state. | Death is announced once (the HP watch defers to MapSession's death entry). Modals close on death, and the shell flow resets on any load. |
| P2-3 | Closing the window while dead skipped the canonical EXP penalty, because saving is refused while DEAD and the penalty waited for the OK button. | Recorded as a fidelity exploit; fixed in phase P3 by applying the penalty at the moment of death (classic behaviour). |
| P2-4 | Dragging an item from the inventory to a quickslot swung the weapon, and a title-bar drag read the OS cursor. Default window positions overlapped at 1600×900. | UI drags and clicks never reach the attack; windows have non-overlapping defaults and raise on any click. |
| P2-5 | The Tutorial Jr. Sentinel on 000000030 stood inside a mushroom-house cap (the cap has no collision), and nothing verified that every species can be killed. | A physics probe of every monster body against blocking geometry on all 15 monster maps, plus a kill test for every species. The slot clearance is per species (P3). |
| P2-6 | Seven visual-only interior floor overlays collided as walls, and the export gate accepted a field that silently became an empty list. | Source-world fix through the collision-tag registry (names no longer decide collision). `sidecar_diff` fails on emptied containers. |
| P2-7 | Blocked portal arrivals in 000001000 (two barrel-door mounds) and 000001021 (a hedge), and eaves over the Rafters route ends in two interiors. | Fixed in the Blender source (moved mounds, ended the hedge lane, trimmed eaves). The world builds with 0 settle moves, and the route sweep passes 360/360 both ways. |

## Phase P3: integration fixes and the walkable island (M2)

| # | Problem found | Correction |
|---|---|---|
| P3-1 | Up could still enter a portal while a dialogue or shop was open, and the end of a warp handed input back under an open modal. | PortalInteractor ignores presses unless MapSession is idle and the player is alive with input on and no modal open. The end-of-warp hand-back is refused while a modal is open. |
| P3-2 | Quit to title left MapSession IDLE with the old map, cache and last arrival. | `MapSession.reset()` returns to BOOT on `detach_world`, including in the middle of a warp. |
| P3-3 | Quitting while dead skipped the death EXP penalty (fidelity exploit from P2-3). | The death is committed at the moment of death, as in classic: penalty, HP/MP after respawn, and the location set to the return town, then an autosave. OK only travels, and a death-quit-reload applies the penalty exactly once (Test F checks in 000000040 and 000001014). |
| P3-4 | Trees hid the player in Snail Hunting Ground I: occluders faded only to 70%, and the X-ray silhouette did not read through them. | Occlusion now covers the whole body and nearby monsters, dithers occluders out around the player, and draws a see-through outline. Terrain never fades. |
| P3-5 | A click on a UI button over the world swung the weapon, and a debug kill skipped EXP and drops. | Mouse attacks come only from unhandled input. `debug_kill()` runs the normal death path, and debug spawns (slot −1) never report or respawn. `ready_time(-1)` no longer reads the last slot through a negative index. |
| P3-6 | The house cap on 000000030 has no collision, so a 1.7 m Tutorial Jr. Sentinel slot stood inside it. | Slot clearance is per species, and the map has a keep-out disc. A blocking cap hull in Blender is still requested. |
| P3-7 | Trails between maps were closed scenery (warp mode only). | M2: walk-through gates commit the map change on the first grounded tick past the gate plane. Trail side walls, ring gaps with plugs, the RegionIndex identity invariant and `MapSession.trail_changed` are in. 19 of 20 trails are walkable; 000001012 ↔ 000001014 stays warp because its hairpin climbs inside the ring band. Traversal report: 360 route runs and 85 link runs with 0 failures, 40 → 30 blocked at the ledge, and the Test A tour passes both walking (2,625 m) and in warp mode. |

## Phase P4: known fixes and the playtest harness

| # | Problem found | Correction |
|---|---|---|
| P4-1 | 000001012 ↔ 000001014 could not be made walkable by reshaping the trail: the two footprints left a 3.43 m slot where a trail between two containment rings needs 6.8 m. | Snail Field of Flowers moved 12.9 m along its bearing in `layout.py`, and the trail follows an authored route through the west00 corridor. All 20 trails are walkable. |
| P4-2 | Southperry's ship lies up to 5.5 m outside the map's layout rectangle: the deck counted as "void", the ring wall crossed the gangplank, and the ship's one-sided collision dropped players into the sea. | An authored region extension for the ship (`misostory/maps/000000060.json`), a concave containment ring around it, and double-sided collision for that chunk until Blender closes the hull (requested). |
| P4-3 | Roger's offer showed the item-use instructions as a Yes/No question, because MeowDB has no on-accept text for 1002. | The offer is the canonical journal summary with a generic system prompt; the canonical instructions follow the accept. |
| P4-4 | Monsters behind cliffs (terrain never fades) were invisible, and a potion could be used under the death notice. | Monsters get a stencil-based see-through silhouette. Consumables check the death state, not `hp <= 0`. |
| P4-5 | Ad-hoc test drivers kept being rewritten. | `game/tools/playtest/`: a real-input driver for the real main scene with scenario scripts and reports (`bash scripts/playtest.sh <scenario>`). On its first run it found that 5 of the 21 NPCs could not be reached on foot (Roger, Heena, Nina, Sid, Lucy). |

## Phase V1: real-game playthroughs (Tests A–G) and the movement, camera, combat and world reviews

Eight playtesters wrote harness scenarios (`game/tools/playtest/scenarios/test_*`) that play the real main scene with
real input; console use is setup-only and counted separately. Every Test A–G scenario passes: 25/25 maps and 47/47
portals visited on foot, every hit inside CombatFormula's range, EXP per kill canonical, levels gained purely by
killing, inventory/equipment/quickslots persisting across a process restart, Sam's Suggestion's exact reward (30 EXP,
3 Eggs) across a save/quit/reload at 5/10, the death penalty applied once across quit and reload, and canonical prices
at all three shops. A triage lead verified 60 findings against the code and data, merged duplicates, and rejected 10
as working-as-canonical or harness artefacts.

| # | Problem found | Correction |
|---|---|---|
| V1-1 | 5 of 21 NPCs could not be talked to on foot. Heena (1.64 m bush), Nina (2.0 m stump) and Roger (3.0 m garden behind a hedge) are above the 1.35 m jump reach; Sid and Lucy stood 1–18 cm outside their talk zones behind counters. | Source world: walkable stairs (8–15 risers of about 0.2 m) up to all three, keeping their classic places. Counter NPCs get an `across_counter` talk-zone profile (2.4 m sphere, an adaptation). The `npcs` scenario is a hard check: 21/21, every margin at least 0.6 m. |
| V1-2 | BLOCKER: a pocket beside A Split Road's T4 ramp traps a walking player (walls 2.1–3.8 m against a 1.35 m reach), and Continue resumed inside it. 7 of 31 hunts there got trapped. | Fixed in the Blender source in phase F1, with a trap-survey scenario to catch the class. |
| V1-3 | MAJOR: Hunting Ground Middle of the Forest I's out00 arrival sat inside a mound, 2.7 m from a ladder foot, so Up both grabbed the ladder and warped. | Anchor fix in Blender, plus export-gate checks that no climbable's grab zone meets a portal trigger (phase F1). |
| V1-4 | MAJOR fidelity: no HP regeneration existed at all, although MeowDB documents that standing still slowly restores HP (without numbers). Low-level characters death-spiralled. | Natural regeneration as a labelled adaptation (phase F1). |
| V1-5 | Pressed jumps against a face missed ledges well under the documented 1.35 m reach. Space confirmed the death notice while also being the jump key. The stats window grid reflowed at 0 AP. | Fix round F1. |

## Phase F1: the playtest fix round

The fix round was launched as eight owner-scoped groups. Partway through, every agent stopped on an account usage limit, which left partial work: the shell, UI and shop fixes and the world talk-range fallback were complete, and the rest had not started. The orchestrator reviewed and kept the finished work (the full suite stayed green) and finished the critical items directly:

| # | Problem found | Correction |
|---|---|---|
| F1-1 | BLOCKER: the A Split Road pocket (V1-2). | `T4_UpperRoad_Low` now runs up to T4_Ramp's north edge, so the pocket is filled at the upper-road height (2.2 m). `test_d_stuck` asserts that the top surface over the old pocket is the cap (y 6.20). |
| F1-2 | 000001005 out00 (V1-3). | The door block's face moved back to y 3.4–3.6 (the arrival at y 2.5 is clear), and the ladder moved to x 11.8, 1.55 m outside the trigger. Route DoorRoof follows it. `test_a_probe_1005`: Up at the ladder climbs, and the arrival walks to the Floor route. |
| F1-3 | No natural HP regeneration (V1-4). | `NaturalRecoveryRule` + `NaturalRecovery`, from `combat.json natural_recovery` (10 HP per 10 s, standing still, 5 s out of combat; verified false). The `regen` scenario checks it in the real game. |
| F1-4 | Space confirmed the death notice; the controls panel listed keys with no feature behind them. | The notice ignores jump keys and key repeat. Sit, Skills and Minimap are hidden until built. |
| F1-5 | The stats grid reflowed at 0 AP; the Quest Log's "nearby" read a field canonical NPCs do not have; identical gain lines were deduplicated; the shop omitted gender requirements; the NPC talk fallback used the global radius. | Fixed, each with tests. |
| F1-6 | A commit swept in a 186 MB backup of the exported world (`game/assets/world.prev/`), because the ignore rule covered only `world/`. | The just-pushed commit was rewritten without it (force-push with lease on the feature branch), and `game/assets/.gitignore` now ignores `world.*/` as well. |
| F1-7 | Combat fidelity: held attacks repeated every 733 ms (lockouts rounded up to whole ticks, canonical 720 ms); Orange Mushrooms hit mid-hop never staggered; the monster push stopped one tick short (35 of 36); an attack pressed while dead fired after the respawn. | The lockout carries its sub-tick overshoot (20 held swings average 720 ms); a mid-hop hit staggers (the KB rule has no airborne exception); the push runs before the brain's tick; presses are only buffered while the player is alive with input. Each has a regression test. |
| F1-8 | Nothing stopped a ladder from standing inside a portal's press-Up trigger (the 000001005 class). | sidecar_diff fails when a climbable's foot is within the grab radius of a trigger box at a height a standing body reaches, with a mutation test. The shipped export passes. |
| F1-9 | The final Test C replay failed one check, "every kill gave its canonical monster EXP": its phase 2 had 0 kills. The hunter had fallen into a second walled pocket, in The Field West of Amherst (000001000, local x 10-12.7, y 32.9-36.6, between P17, P20, P21 and P25), and autosave plus Continue resumed it there. A new `trap_probe` scenario confirmed it: no try got further than 3.95 m from the spot or gained any height. | A filler terrace `P17_P25_Fill` at 6.2 m (one walkable 0.2 m step to every lower neighbour, no coplanar caps). `trap_probe` now probes every known former trap from its landing surface, and `test_playtest_traps.gd` keeps both escapable. A real-game monster check that raced the 7.56 s spawn tick under full-suite load now reads the slots at once. |

The suite has 1140 tests, all passing; `validate.py` reports 0 high and 0 medium; and the export gates pass. Deliverables written: `docs/runtime/PLAYTHROUGH_REPORT.md`, `HOWTO.md`, `CONTENT_AUTHORING.md`, and the Iteration Two section of `docs/DEFERRED.md`.

---

# Iteration Three: complete canonical Maple Island

Brief: [`ITERATION_THREE_BRIEF.md`](ITERATION_THREE_BRIEF.md). Started 2026-10-05 from the Iteration Two build (commit
b85dec0).

## Phase B3: baseline

The build, Blender validation (0 high, 0 medium, 21 low), the full suite with the exported world (1145 tests) and
canonical data validation all pass. Of the eleven real-game scenarios, ten pass. `test_b_combat` fails one check, its
reach probe, with 2 "behind" hits out of 6. The audit showed this is a harness defect, not a combat defect. The probe
counted a hit on *any* monster as a hit on the probe Snail, and both hits landed on a second Snail in front of the
player and to its left, inside the canonical swing window. The probe Snail stayed 1.34–1.40 m behind and was never hit.
`test_c_progression` (killing only, no quests) reaches level 8 in about 2.2 hours of game time and picks up 1,649 mesos
under the old placeholder rates.

## Phase A3: read-only audit (11 domain auditors)

The auditors compared every domain with the cache and the dated captures (raw results:
`review/it3_audit.json`, removed from the tree on 2026-10-06; it is in git history at commit f9b2bc5). The quest, NPC, shop, item and monster-stat data, and all 577 spawn counts, already match
MeowDB. Random quest rewards are weighted draws, the Rain quizzes are real menus, and the quest markers and the most
important world feedback exist. What is missing or wrong:

- **Blockers:**
  - There is no Wooden Box runtime, so Pio's quest (1012) cannot be completed.
  - The Green Relaxer cannot be sat on, because there is no sitting at all.
  - The validator rejects every non-MeowDB authority, and no capture is ever read, so drops still run on placeholders.
  - There is no minimap.
  - A new class of player traps exists: slots 2.3–2.6 m deep where a map corner's rounded plinth meets the square
    containment ring. One was confirmed with real input, and `trap_probe` wrongly passes another.
- **Missing features:** natural recovery resets instead of pausing; the Beginner skills, the skill window and SP use
  are absent; quest-gated drops are absent; and the save does not record the random rewards received.
- **Gaps elsewhere:** 16 of 20 quests have never been played in the real game; the quest log shows no chain progress;
  monster spawns ignore NPC spaces and can respawn inside the player; floor-walking monsters can leave their floor;
  and no stuck-region scan or clean end-to-end playthrough exists.

Interfaces for the parallel work are fixed in [`runtime/ITERATION_THREE_CONTRACTS.md`](runtime/ITERATION_THREE_CONTRACTS.md).

## Phase D3: sources and data decisions

| # | Problem found | Decision |
|---|---|---|
| D3-1 | The brief forbids repeating Iteration Two's automated MeowDB collection, but `tools/meowdb/lib.mjs` had been set to fetch live again (R2-11). | The extractors are cache-only again (they need `MEOWDB_ALLOW_NETWORK=1`). Newer MeowDB facts come in as dated captures of pages read by hand in a normal browser (`tools/meowdb/captures/`). One exception, recorded honestly: three item records (495, 498, 242) were read through the page's own `fetch()` at human pace instead of by navigating. |
| D3-2 | Is the cached quest list (2026-10-04) still the complete Maple Island set? | The live quest tracker, read once in a browser on 2026-10-05, lists the same 20 quests (1000–1019): 5 chains and 4 standalone quests, all "Missable". The total of 278 quests also matches the cache. |
| D3-3 | Replaced. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| D3-4 | Replaced. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| D3-5 | Replaced. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| D3-6 | Replaced. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| D3-7 | Replaced. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| D3-8 | Replaced. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| D3-9 | Quest-gated drops: MeowDB does not say who may loot a quest item. | Orchestrator's derivation (`verified: false`; reworded on 2026-10-06 for the owner's decision): an entry is gated only when its item's MeowDB subtype is "Quest Item" **and** a Maple Island quest requires it; it drops only while that quest is in progress. Old Wooden Board and Rusty Screw are gated to Pio's quest (1012). Jr. Sentinel Shellpiece (MeowDB subtype "Monster Drop") is not. |
| D3-10 | Replaced. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| D3-11 | The project owner's decision of 2026-10-06: the only sources of truth are MeowDB MS Classic and Henesys.gg (https://henesys.gg/loot, MapleStory Classic World). What may each monster and the Wooden Box drop, how rare is it, and how often does it drop? | **Membership** is MeowDB's community list "Drops (MS Classic)" for the owner, every entry, its votes recorded in provenance and nothing excluded for votes, from the newest dated source: the live captures `tools/meowdb/captures/monster_<id>.*` (2026-10-05) for the six monsters and `breakable_0000001.txt` for the Wooden Box. MeowDB's "MSEA reference drops" list is reference only, never a member. Each member resolves to its local item by name; where two local items share a name (Red Cloth Pants: 1168 and 1177) the id MeowDB's own cached drop entry for that monster carries decides (1168), and the record says so. **Rarity** is Henesys.gg's per-item label (Common, Rare, Very Rare or Extremely Rare; per item, not per monster), read by hand on 2026-10-06 into `tools/henesys/captures/item_rarity.json`: 64 items, all Common except Overall Armor DEF Scroll: Intermediate (Rare). Henesys.gg's terms prohibit unauthorized reproduction or scraping, so its labels are for this private project only: ask Henesys.gg before publishing them, and never collect them automatically. **Chance** is the owner-approved MisoStory table by item category x rarity (an adaptation: authority Project owner, `verified: false`), one file the owner can tune, `game/data/misostory/drop_rates.json`: own leftover (Etc, subtype "Monster Drop") 100 / 50 / 20 / 5%; quest-gated (D3-9) 100% at every rarity; other Etc 3 / 1 / 0.3 / 0.1%; Use consumables 2 / 0.5 / 0.1 / 0.02%; Use scrolls 0.1 / 0.03 / 0.01 / 0.003%; Equip 0.1 / 0.04 / 0.01 / 0.002%; Set-up 0.05 / 0.02 / 0.005 / 0.001% (Common / Rare / Very Rare / Extremely Rare). One item per drop; the same table for the Wooden Box. The canonical drop records (schema 3, contract C1) hold only sourced facts (membership, item, rarity, category inputs), never a probability. Result: 86 members on 7 owners, all resolved. |
| D3-12 | Mesos: MeowDB has a player meso report for one Maple Island monster (the Snail: 2 per kill) and publishes no meso drop chance. | The owner's rule (an adaptation, `game/data/misostory/meso_rules.json`, `verified: false`): MeowDB's player report where one exists; otherwise a uniform integer in [level, 2 x level] of the monster's canonical level (Blue Snail 2-4, Shroom 3-6, Red Snail 4-8, Orange Mushroom 8-16). Mesos drop with chance 60%, also for the Snail (MeowDB publishes no chance). The Tutorial Jr. Sentinel drops no mesos (the owner's choice) and the Wooden Box none. When a newer MeowDB capture or cache gains a report for another monster, `extract_monsters.mjs` writes it into that record and the runtime uses it: the formula only fills what MeowDB lacks. |

## Phase W1: Maple Island content and mechanics (wave 1: eleven packages, each followed by an adversarial reviewer)

Eleven packages were built in parallel git worktrees against the contracts, each reviewed by an adversarial reviewer
who probed the running game, and merged in this order: drops and mesos; provenance, validation, test evidence and the
parity generator; natural recovery, player activity, sitting and chairs; Beginner skills; save schema v2; quests,
dialogue, NPCs, shops and Shanks' departure; the Wooden Box; monster behaviour, hit areas and spawn placement; the
minimap and world feedback; the playtest harness and the every-quest set; and the stuck-region scanner with its trap
fixes. Integrated result (4b61650): the island rebuilds and validates with 0 high, 0 medium and 21 low findings; the
full suite with the world passes (1509 tests in 167 files); canonical data validation passes with 0 errors and 54
warnings (drop members the earlier drop sources left unresolved). On that build (runs of 2026-10-05, seed 1) the
every-quest set passes 20 of 20 quests in the real game, every chain strict; Test A walks all 25 maps and 47
portals (475 checks, 0 failed, no death in that run; a review run of the same seed passed 477 checks with two deaths,
each leg retried after a warp); and Test C levels a clean Beginner to 10 by killing only (77 checks, 0
failed; its seed 1 had failed on the 000001000 trap before the stuck-scan fills).

| # | Problem found | Correction |
|---|---|---|
| W1-1 | Drops: the drop records were still MeowDB's community lists, rolled with Iteration Two's placeholder rates, and no tool read the dated captures. | `tools/sources/drops_merge.mjs`, called by `extract_monsters.mjs` (the one writer of `drops/*.json`), builds the drop records offline from the dated captures; every entry keeps its membership source and its quest gate, and the roller reads only the versioned records (`DropRoller.roll(owner, db, rng, ctx)`), so no placeholder rate is left. Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| W1-2 | Drops: the sources named items differently. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| W1-3 | Drops: the live monster pages publish "STAGGER 0.6 seconds", which the 2026-10-04 cache predates. | `stagger_ms` 600 in the six monster records, cited to the captures; `MonsterDef` reads it before the hit1 clip. |
| W1-4 | Drops review: `DropRates.validate` ran only in a unit test; the real-game loot checks of `test_b_combat` and `test_d_inventory` accepted any member, so an unresolved member that dropped would pass; an unresolved item a quest needs was not a progression blocker. | `DropChecks` reports `drop_policy` errors in the data validator; the loot checks accept only rolling members; an unresolved member a quest needs is a progression blocker. Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| W1-5 | Provenance: nothing produced machine-readable test evidence, a provenance report or a parity manifest, and the quest, NPC and dialogue validation ran only inside the game. | `TEST_EVIDENCE_OUT` (contract C6) with `parity_keys()` per test file; `validate_data.sh --report` (`docs/PROVENANCE_REPORT.md`); `tools/parity/build_parity.mjs` (missing, partial, implemented, verified; quests, objectives, rewards and chains need a real-game check; an unresolved drop chance is a source-data gap); `GameplayDataChecks`; the Phase 16 checks (skill references, chairs, placeholder names, duplicate ids); `verified: true` needs `verified_against`; quests carry `missable` and `tracker_tags` from the tracker capture. |
| W1-6 | Provenance: `extract_maps.mjs` had stopped since Iteration Two ("20 LINKS, 4 DOOR_LINKS, 1 ONE_WAY") because `layout.py` kept only the arrival of the one-way link, so canonical data was not reproducible. | The parse is checked against `docs/topology.json` instead of fixed counts; the maps and the crosswalk regenerate byte for byte. `scripts/check_canonical.sh` re-runs every extractor offline and diffs the result. |
| W1-7 | Provenance review: `check_canonical.sh` emptied `CHECK_CANONICAL_DIR` unchecked (`.` would have deleted the repository); two same-named v1 drops shared one parity key; five `canon:*` rows read "verified" from fixture tests while the shipped drops were still v1; 23 cited URLs were missing from `canonical_sources.json`. | Unsafe folders are refused; keys get the item id; those rows require schema v2 data (`rules.json` `requires`); the index builder and the validator share one URL rule. |
| W1-8 | Mechanics: natural recovery reset on any activity and waited 5 s out of combat (an Iteration Two adaptation). | The project owner's rule in `recovery.json` `natural_hp` (authority Project owner, `verified: true` against the brief): 10 HP per 10 s of still or seated time; every other activity pauses the clock and nothing resets it; the clock holds at full HP and is saved (`natural_recovery.hp_rest_s`). `PlayerController.activity()` (C4). MP has none (a source gap). The `regen` scenario plays the brief's example (6 s still, 5 s walking, 4 s still: one tick). |
| W1-9 | Mechanics: no sitting, so The Green Relaxer was only an inventory record. | A seated state on the ground: sitting needs a grounded, still, alive player with no modal; a move, jump, attack, cast, X, knockback, death, climb, warp, a replaced character or losing the chair stands the player up. `Chairs.use` through `ItemService.use_item` (the Set-up tab, a quickslot) and X (the first chair owned). The chair's canonical 30 HP per 10 s runs on its own clock. |
| W1-10 | Mechanics review: the tick an attack started from the chair counted as seated time; a seated player whose floor went kept sitting in the air; a zero tick length could loop forever; the regen scenario's pause checks would pass a clock that reset. | `activity()` reads `attacking` on that tick; a "fall" stand-up; the tick guard; the checks compare the size of the change. |
| W1-11 | Skills: no skills, no Skills window and no SP use. | `SkillDef`, `SkillBook` and `EffectBook` from canonical `beginner.json`; `PlayerSkills` casts (Three Snails through `CombatFormula.resolve_fixed_damage` and the basic attack's hit path; Recovery and Nimble Feet as timed effects); cooldowns and effects as remaining seconds; the Skills window on K; typed quickslots `{kind, id}`; an SP badge. `test_skills` passes 44 checks in the real game (the package's run; 50 of 50 on the integrated build in a review run, after the skills review added checks). |
| W1-12 | Skills review: the console's `cast` was always refused as "busy" (the open console holds the player's input); `effects_on_death.keep_cooldowns` was read but never applied; `three_snails.terrain_check: true` silently did nothing. | `cast(id, ignore_input_hold)` for the console only; the flag is applied; an unsupported terrain check is an error. |
| W1-13 | Saves: v1 saves had bare quickslot ids and no reward records, and one `.bak` generation lost the v1 file on the second save. | `save_version` 2 with one step (`v1_typed_quickslots_quest_rewards`): typed quickslots, quests format 2 with completed entries `rewards_received {recorded: false}` (never inferred from the bag). Six real Iteration Two saves are pinned fixtures. A one-time `<slot>.json.pre-v<N>` copy, unknown item ids kept and reported, resume points dropped when the map's collision hash changed, and quest progress autosaves. |
| W1-14 | Saves review: one hand-edited value of the wrong type made `decode()` return null and `list_saves()` drop every slot, so the title lost Continue. | Malformed values load as defaults; `decode()` never returns null; a failed pre-migration copy is removed. |
| W1-15 | Quests: the Quest Log showed no chain progress, NPC maps or Missable tag, said "Return to X" for an NPC never met, and completions recorded no random draw. | QuestLog format 2 records `rewards_received` (EXP, mesos, items, random picks); chain steps, start and turn-in NPCs with their maps, the Missable tag and the received reward show; a turn-in row says "Return to X" only once X was dealt with through a quest. |
| W1-16 | Quests: Shanks only talked; selling Roger's Apple during 1002 made it uncompletable; dialogue rules lived in code. | Shanks' departure boundary (the canonical level and fare checked, no fare taken, no travel, a flag set, unfinished quests listed as a warning) and the "End of Maple Island" screen; a shop refuses a quest item an in-progress quest still needs (`QuestItemGuard`); Roger re-issues a lost apple; the rules in `dialogue/_rules.json`; speech bubbles from the canonical idle lines. |
| W1-17 | Quests review: `QuestLog.from_dict` dropped entries it could not read (a newer build's status), contradicting its forward-safe claim. | Such entries are kept and written back. |
| W1-18 | Breakables: no Wooden Box runtime, so Pio's quest (1012) could not be completed. | `BreakablePlacementPlanner` places the 19 canonical placements on walkable ground (seeded; interiors sample their floor), `MapInstanceState.breakables` keeps hits and the respawn time (exact `respawn_s` on the game clock; never saved), and `BreakableSystem` shows a `WoodenBox` per placement. One landed basic attack is one hit on the nearest box; at 4 it breaks and rolls the C2 roller with the quest context. |
| W1-19 | Breakables: the first windowed playtest found a box tucked in a corner behind a house. | A box needs 5 of 8 standing points and a clear line toward the gameplay camera; lighter, faintly glowing planks set it apart from the decorative crates. |
| W1-20 | Breakables review: a respawn due before another box's hit came back in the state but not on its node; the declared hit rule was read by nothing (the cap was a literal); the box FX drew from the global `randf()`; `test_box` broke only Amherst's six boxes and its reload checks could pass empty. | One helper restores due placements before a hit; `boxes_per_attack` feeds the attack query; the box has its own RNG; after Pio's quest `test_box` also breaks every box of the other five maps (16 of the 19 broken in one run: the quest needs only three of Amherst's six). |
| W1-21 | Monsters: the baseline `test_b_combat` failure (B3). | Reach probes are classified by the hit target's identity after a clear-front check: 53 checks pass on seeds 1, 2 and 3. |
| W1-22 | Monsters: walkers re-rolled random 3D headings and could climb a ramp to another terrace ("Stays on its floor"); the Orange Mushroom could hop anywhere; a hit in mid-hop had no rule; the stagger was the hit1 clip. | A floor band (0.5 m around the spawn height, widened to the region's tier), pacing back and forth on a line, one-hop floors counted from the spawn floor, a mid-hop hit cancels the hop and pushes; the canonical stagger first. |
| W1-23 | Monsters: spawn slots ignored NPC spaces (Sam stood inside a Snail region), crowded small regions and could respawn on the player; Iteration Two stated "MS Classic ignores mobRate" as fact. | Slots keep 2.5 m from NPCs and 8 m² of room each (the rest spill), authored `m.mobs` avoid zones become exclusions (`exclude_xz`), a respawn waits until the player is 2 m away; the mob rate is a recorded decision between MeowDB pages that disagree, with a switch (`map_mob_rate.apply` false). |
| W1-24 | Monsters: the grey Tutorial Jr. Sentinel stand-in, floating proxies wider than their touch zones, invisible attack areas. | `Mob_TutorialJrSentinel`; every proxy on z = 0 with a footprint near its touch zone; `AttackFx` draws the canonical attack box with every swing; `check_spawn_captures.mjs` compares the 51 spawn rows with the captures. |
| W1-25 | Monsters review: the density cap spilled at once in species order, so one species' overflow took another's own region (83 slots moved). | Two passes: every species takes its own regions first; 57 of 577 slots spill on the integrated export (`test_spawn_slots`' flat-ground planning, MAP_ARCHITECTURE §4.7.1; the package measured 58 on its own export before the merges). |
| W1-26 | Minimap: there was none, and MeowDB's 2D minimap block is Nexon art (0x0 for the shops). | Drawn from the runtime collision's `Ground` faces through the gameplay camera's projection: terraces by tier, exits with destination names, NPC dots with quest markers and role icons, the player arrow and the trail tag. M folds it, F3 shows the map id, hidden portals stay off. Shop and boat icons on name tags; a level-up announces unspent SP. |
| W1-27 | Minimap: a test process aborted silently after about ten island builds. | The minimap's world tests share one build; at integration the limit was traced to Jolt's body cap and raised (W1-37). |
| W1-28 | Minimap review: the label layout named 36 of 46 exits; a dashed stub led back up the one-way 30 → 40 trail. | 43 of 46 named in the suite's layout (`test_ui_minimap_world`, the player away); the three left to the hover text are all on the eight-exit 000001000, and every other map names all its exits; a one-way trail keeps only its from-end stub. |
| W1-29 | Harness: scenarios copied their helpers, nothing proved a run used no developer help, checks had no parity keys, and 16 of 20 quests had never been played in the real game. | `PlaytestKit`; strict mode (`Debug.commands_run`, `PlaytestLedger`, the report's `strict` block); parity keys on checks; `PlaytestQuestPlan` from canonical data; the every-quest set (`scenarios/quest.gd`, `scripts/playtest_quests.sh`): 19 of 20 on seeds 1-3 before the Wooden Box landed. Test A's walker survives more often (no death in 54 legs in the package's run; it died on legs 22 and 32 before, and a review run on the integrated build still died on legs 22 and 46). |
| W1-30 | Harness review: the strict scan let service calls through (`items.gain`, `quests.accept`, `allocate_ap`); 1012's box path skipped the mid-quest restart; a quest could pass over an unattributed failure; a ledge corner at A Split Road stranded the hunter. | The scan refuses them; the restart happens in the box hunt; the summary rule; `PlaytestKit.unstick`; 1000-1001 runs strict from character creation. |
| W1-31 | Stuck regions: the audit's map-corner slots, and no systematic scan. | `StuckScan`: a walkability graph per map on the real collision, forward and backward searches, and each suspect component replayed with the real `PlayerController`. The first full scan confirmed 42 traps in 13 maps. |
| W1-32 | Stuck regions: the corner class was a rounded plinth top against the containment ring's square corner; other traps were plinth-level pockets, caverns under floating terraces and walled-in yards. | The `world.py` plinth rule, `validate.py ring_band`, fills, terraces down to the ground, a rope, a vine and a stepping stone: four rounds, 0 confirmed. `trap_probe` now passes only an escape to escapable ground, a trigger or a gate (its old "4 m flat or 1 m rise" passed a real trap) and replays all 54 former spots. |
| W1-33 | Stuck-scan review: the search's hops and walk-offs were shorter than the controller's reach; with it the real controller confirmed two more traps (000001021 behind the west hedges; 000001006, a walk-out under the out00 bridge). | `WestHedge_Back_Fill` and `Bridge_Abutment` in the source; the scan fails on escapable ground outside every region and on an UNENTERABLE component without a review entry. |

Decisions recorded as adaptations in this wave (all `verified: false`, each with its reason in `game/data/misostory/`):

| # | Question | Decision |
|---|---|---|
| W1-D1 | Recovery's heal over 30 s, the buff cast time ("Timing unavailable"), a Three Snails cast with no target, walls and platforms, effects at death. | Six equal ticks every 5 s (4/8/12 HP; the split always sums to the canonical total); Recovery and Nimble Feet cast instantly (lockout 0); a whiff spends MP and the shell; no terrain check; the thrown shell is presentation and the hit resolves at the throw; effects end at death and cooldowns keep counting (`skills.json`). Three Snails keeps the skill page's 50 px search start over the targeting page's 65 px. |
| W1-D2 | The chair's bonus clock and the sit key. | Its own clock, restarted at each sit, held at full HP; X sits on the first chair owned; no ground sit or benches (a source gap). |
| W1-D3 | How a Wooden Box is hit and comes back. | One landed basic attack is one hit on the nearest box (no MISS, damage ignored); exactly `respawn_s` per placement (the map pages' per-placement values over the breakable page's single 120 s); not solid; MeowDB's 2D coordinates unused; the interior fallback, open-ground and camera-sight rules (`breakables.json`). |
| W1-D4 | How the roller reads the records. | A meso amount is a uniform integer in [min, max]; one item per drop; a gated entry still consumes its random roll, so a quest starting or ending does not shift the other entries' rolls. |
| W1-D5 | Monster floors, pacing and spawns. | `floor_band_m` 0.5; `pace_reverse_chance` 0.35 and `pace_min_run_m` 1.0; the Orange Mushroom's `spawn_floor_one_hop`; NPC clearance 2.5 m, 8 m² per slot, respawn clearance 2 m; the mob rate ignored; the Sentinel proxy sized to its 21 px touch zone (`_shared.json`, `9.json`, `1.json`, `presentation.json`, `combat.json`). |
| W1-D6 | Quest wording, selling, losses and the boundary. | "Return to X" only for an NPC met through a quest; a shop refuses only the quantity of a quest-critical item (quest item, untradeable or handed out on accept) that an in-progress quest still needs; Roger's re-issue instead of a player-facing forfeit; Shanks' boundary as W1-16; speech-bubble timing (first after 2-10 s, then every 14-26 s, 5 s each) and the dialogue rules as data. |
| W1-D7 | What the minimap draws and when a parity entry is verified. | The runtime collision, not MeowDB's art; hidden portals stay off; the map id only in debug mode (F3). An entry is verified by a passing tagged check and no failing one; quests, objectives, rewards and chains need a real-game check; "implemented" is only a declaration in `tools/parity/rules.json`. |

**Integration (the orchestrator).** The packages each passed alone; the merges needed these seams fixed:

| # | Problem found | Correction |
|---|---|---|
| W1-34 | Chairs on quickslots: the skills package emitted `Events.chair_use_requested` for a bound chair, which nothing answered, while the mechanics package already sat the player through `ItemService.use_item`. | At the merge, `MisoQuickslots.use` hands a bound chair to `ItemService.use_item` (`Chairs.use`), the signal path is gone, and the inventory window's Sit/Stand button and Set key follow `MisoQuickslots.can_bind`, which accepts chairs. |
| W1-35 | Skill stand-up: `PlayerSkills._stand_up` was duck-typed against a sitting API its branch did not have. | It calls `PlayerController.stand_up(&"skill")`. |
| W1-36 | The C2 roller in breakables: `BreakableRules.roll_drops` switched on `DropRoller.roll`'s arity until the drops package landed, and the gated-drop test printed SKIP. | A direct four-argument call; the test runs (ec40365). |
| W1-37 | The merged suite builds the island more than ten times in one process and aborted with exit code 3, printing nothing and no totals. The object count and static memory stayed flat, and raising Jolt's body cap removed the abort, so Godot 4.7.2's Jolt integration evidently does not reuse the body slots of freed collision objects within a process (an inference: the engine side was not root-caused). | `physics/jolt_physics_3d/limits/max_bodies` 65536 in `project.godot` (default 10240): 16 builds pass, and the suite runs to its totals. The game builds the island once (a0003a2). |
| W1-38 | Merge conflicts: `canonical_sources.json`, `data_validator.gd` and two validation tests (drops and provenance); `controls_panel.gd`'s `NOT_AVAILABLE` and `test_shell_screens.gd` (mechanics, skills, minimap); `quickslots.gd` (skills and saves); `UI.md`, `npc_presenter.gd`, `hud.gd` and `test_shell_installer.gd` (minimap). | Resolved by hand; the island was rebuilt, exported and validated, and the build, validation and provenance reports regenerated (4b61650). |

## Phase W2: playthroughs, integration fixes, parity and documentation (wave 2: four packages, each reviewed)

Wave 2 ran four packages in parallel worktrees on the integrated build of W1 (4b61650), each followed by an
adversarial reviewer, and merged them in this order: integration fixes and reachability; the clean-character
playthrough and the every-quest report; the parity manifest; documentation.

| # | Problem found | Correction |
|---|---|---|
| W2-1 | Documentation: `HOWTO.md`, `CONTENT_AUTHORING.md`, `DEFERRED.md`, `README.md` and `ARCHITECTURE.md` still described Iteration Two, and several system documents were stale after the merges (chairs "not usable", `--strict` "passes", drop records "still v1", the flood fill "not built", the Tutorial Jr. Sentinel a placeholder). | Rewritten against the integrated code and data, with every command run (or a quick variant); `tools/meowdb/captures/README.md` added; this phase's W1 entries written from the packages' reports, reviews and commits. |
| W2-2 | `scripts/check_canonical.sh` exits 2 on the integrated build: it empties `game/data/canonical/items` and runs `extract_items` after `extract_monsters`, which now resolves drop members against the local items and quests. | Reported (`DEFERRED.md`); a copy with `extract_items` and `extract_quests` before `extract_monsters` reproduces every canonical file. Not changed here (the documentation package touches no code). |
| W2-3 | The committed parity manifest (`MAPLE_ISLAND_PARITY.md`, 537 entries, 34 missing) predates the merges. | To be regenerated from the final evidence. A build on the integrated suite's evidence and the every-quest set's reports gives 511 entries: 222 verified, 233 implemented, 54 partial (all source-data gaps), 0 missing. |
| W2-4 | `validate_data.sh --strict` now fails: the 54 `drop_unresolved` warnings are by design. | Documented in HOWTO and DATA_VALIDATION. |
| W2-5 | Documentation review: claims the reviewer's own runs did not bear out. `test_box` was said to break all 19 boxes (it breaks 16: the quest needs three of Amherst's six); 000001000 was said to leave two of eight exit names to the hover text (the suite measures 43 of 46 named, all three missing on 000001000); Test A's "no death" did not hold in a second seed-1 run (two deaths, legs retried after a warp); the Jolt body-slot cause was stated as fact (the integration commit infers it); the spill count quoted a pre-merge 58 (57 on the integrated export); SP "each level from 2" (2 to 10 only); the W1-27 cross-reference; D3-3 to D3-9 called owner decisions in the README. The review's real-game runs also found `ui_minimap` failing 1 of 231 checks on the integrated build: the scenario still expects "SP to distribute" where the skills package's HUD says "SP to spend". | Corrected in HOWTO, CONTENT_AUTHORING, DEFERRED, README, UI, ARCHITECTURE, WORLD_RUNTIME, MONSTERS_AND_COMBAT_RUNTIME and this log. The `ui_minimap` line and `test_box`'s header ("all 19 boxes") are code, so they are reported in DEFERRED for the harness owner, not changed here. |
| W2-6 | Playthrough: no run had ever played Maple Island from a new character to its end without developer help. | `scenarios/playthrough.gd` is one run from the real title and creation screens to Shanks' "End of Maple Island" screen. It is strict from the step after creation: 0 console steps, 0 api fallbacks, 0 developer commands and 0 ledger mismatches. It runs in 8 processes (7 Quit Game/Continue restarts). Every "Gameplay" item of the Definition of Done is a passing check: all 20 quests, all 25 maps, all 21 NPCs, all 6 monster types, drops and meso bags, levelling with exact canonical EXP per kill and per quest, AP through the stats window, consumables, gear (the quest hat and knife included), buying and selling at Pan, Sid and Lucy, the three skills learned and cast, sitting on The Green Relaxer, a death and respawn, saves and reloads, and the boundary. It passes seeds 1, 2 and 3 (615-619 checks, 0 failed; 2,197-2,540 s of game time). |
| W2-7 | Playthrough: the every-quest set could not pass Pio's quest before the Wooden Box landed, and the Shanks boundary and the speech bubbles had only uncommitted scratch checks. | The every-quest set passes 20 of 20 on seeds 1, 2 and 3; 1012 breaks real boxes, and a box broken before the accept drops no gated item. `docs/runtime/QUEST_PLAYTHROUGH_REPORT.md` gives each quest's availability, acceptance, progress, completion, rewards (with the random draw and its `rewards_received` record), follow-ups and its mid-quest restart. The scratch checks became `npc_shanks` (with the 300-meso fare refusal) and `npc_bubbles`. |
| W2-8 | Playthrough: harness defects the runs exposed: the survival guard spun on a monster it could not reach; `break_box` approached a box at a terrace foot from the terrace above; Three Snails aimed at a Snail on another tier and never threw; `let_monsters_win` never touched monsters; a run continued from a copied `--out` wrote into the original folder; some checks carried parity tags that named no entry. | Fixed in `PlaytestKit` and the runner (H1-H6 in `PLAYTHROUGH_REPORT.md`). The runs also logged two game observations. G1: a Continue just past a trail gate refused the saved resume point (fixed in W3-6). G2: the Fruit Knife, 1011's random reward, needs level 8, one more than Shanks' level 7. G2 is canonical data, so it is unchanged. |
| W2-9 | Integration fixes: `Game.clock` ran through the title screen and the threaded island load, so two runs of one seed diverged (the same-seed differences in `test_b_combat` and `test_d_inventory`). Also: a pause-menu Load took back the parked live map instance, so broken boxes stayed broken; the resume guard ignored the shared `World_*` chunks where the trap fixes landed; and several smaller defects (the right column). | The clock stands still until gameplay; a load never inherits live breakable state; the guard also hashes the shared chunks a map's region overlaps. The smaller fixes: `loot` rolls with the quest context; the chair's level refusal no longer talks about equipping; the in-game loot check and `test_monster_combat` accept only rolling members; a long recovery step cannot leave the clock at or above a tick; a huge saved capacity cannot exhaust memory; the HUD shows active timed effects (Nimble Feet, Recovery) with time left; the spawn planner weighs regions by the room left after exclusions. |
| W2-10 | Reachability (the brief's "avoid unreachable terrain"): nothing proved that every placement can be reached from where the player enters a map. | `ReachCheck` (`game/tools/reach_check.gd`, `test_reachability.gd`) walks the StuckScan graph using only edges the controller can certainly take. All 664 targets on the 25 maps are reachable from the map entries: 21 NPC talk zones, 47 portal triggers, 577 spawn slots and 19 Wooden Boxes. A reviewed UNENTERABLE pocket is not (the negative check). The review made the check fail when it skips a canonical portal. |
| W2-11 | Parity: the manifest predated the merges, and some tags claimed more than their tests prove. | Rebuilt from real evidence, with categories added for monster behaviour and spawning, drop rules, persistence, UI and world feedback, and the clean playthrough. The review removed three false "verified" claims: `test_portal_graph` claiming respawn information, items 1440 and 541 verified on partial comparisons, and over-broad `test_b_combat` rules. |

## Phase W3: polish and item verification (wave 3: two packages, each reviewed)

| # | Problem found | Correction |
|---|---|---|
| W3-1 | `test_f_death` failed every time: HP 60 after a respawn, where 50 was expected. | The game is right. Natural recovery pauses while the player is dead and during the respawn warp, and never resets. So a clock banked before the death can tick in the half second after the respawn: `death.json` fixes HP only at the moment of death. The scenario now expects `death.json`'s HP plus the ticks the clock allows. It also checks that the clock holds while dead and survives a quit. |
| W3-2 | `ui_minimap` expected the old "SP to distribute" line. | It now expects "SP to spend", which is what the HUD says. |
| W3-3 | `check_canonical.sh` exited 2 (W2-2). | The steps run items and quests before monsters, and every canonical file reproduces byte for byte. |
| W3-4 | `formulas/movement.json` still said the monster stagger is unpublished. | The extractor text is fixed; only `movement.json` changed. |
| W3-5 | `breakables.json` said Three Snails hits Wooden Boxes, but the runtime never routed a cast to a box. | A cast picks the nearest monster or intact box in its canonical band (one target per cast), and a box takes it as one landed hit. Whether Three Snails may hit boxes at all is still a MisoStory choice (`verified: false`). |
| W3-6 | G1 (W2-8). | `validate_resume` refused any point inside a portal trigger, but crossing a trail's far gate leaves the player inside the trigger of the portal they arrived through. It now accepts the save's own entry portal, which the load disarms as on a real arrival. Covered by the new `resume_gate` scenario (23 checks). A save made on a trail still arrives at the trail's mouth, by design (MAP_ARCHITECTURE 4.9). |
| W3-7 | `test_skills` was not reproducible on seed 1. | With the clock standing still on the title and during the load (W2-9), three traced seed-1 runs are identical. `--trace` now records `Game.clock`, not the boot frame counter. |
| W3-8 | No committed scenario covered a pause-menu Load. | `pause_load` (12 checks) loads through the real menu (`PlaytestDriver.load_from_pause_menu`). |
| W3-9 | About 73 item rows could not be verified: no test compared a runtime item definition with its canonical record. | `test_items_canonical.gd` compares all 96 items through the game's own code paths (ItemDef, Inventory, ItemService, Equipment, StatCalculator, ShopService, WeaponProfile), one field family at a time, each with a mutation test that proves the comparison can fail. Its review added weapon hit boxes, the creation-weapon flag and the shop sell-back price, and made two mutation tests able to fail on the runtime side. |
| W3-10 | A drop chance published on a page nobody had read yet was excused as a source-data gap. | A new parity label, `pending_source_read`: never excused, listed separately, and still open for the exit criterion. Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| W3-11 | Green Apple (242), then a drop of four monsters, had no published stack size or tradeable tag: only its API preview had been captured, so the game held one apple per slot. | Its MeowDB item page was read by hand (`tools/meowdb/captures/item_242.txt`, 2026-10-05). The extractor's API-only path now takes Max per Stack 100, Tradeable and the per-unit sell-back from that text capture, each value citing the capture. `check_canonical.sh` still reproduces every file. |
| W3-12 | A playthrough report stopped early (`PLAYTHROUGH_STOP`) still counted as a clean run, so the parity manifest could mark the playthrough rows verified from half a run. | A report counts as clean only if its final "ready to depart" boundary check passed and it has no stop flag (a node test covers each case). |

## Phase A4: final acceptance check (four independent critics)

Four read-only critics tested the completion claim on 37073b8, each through a different lens:

- **Definition of Done audit:** re-ran the key checks, including a playthrough on a seed never used before (seed 4:
  619 checks, strict, pass) and one quest chain on seed 7.
- **Canonical fidelity spot check:** traced about 700 values from source page to canonical record to the value the
  game uses, and found 0 mismatches. A 200,000-kill drop simulation stayed within about 1σ of every configured chance.
- **Play-as-a-game critic:** ran the game windowed and judged it from screenshots.
- **Deliverables and docs critic:** ran the documented commands and checked the docs against the code and data.

Their verdict: the claim holds in substance but was overstated in the places below.

| # | Problem found | Correction |
|---|---|---|
| A4-1 | The parity exit criterion was not met: one drop source page had never been read. | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| A4-2 | The Skills window grew off the bottom of a 1600×900 screen once skills were learned: its Set key could not be reached, and it covered the HUD status bar. Every headless run had passed anyway: headless, the display reports a 64×64 window, which the project's `canvas_items/expand` stretch turned into a 1600×1600 GUI, and the driver clicked controls a player cannot see. | W4-1 and W4-2. |
| A4-3 | Canonical fall damage (MeowDB's damage-taken formula: 24, capped at 36 in COT2) contradicted the adaptation text "matching classic's lack of fall damage". Neither fall damage nor crouch/down-jump appeared in the parity inventory or DEFERRED. | W4-5. |
| A4-4 | Smaller overclaims and gaps: the playthrough's skill checks passed with zero casts; the strict-mode source scan skipped five harness files; the starting SP of 0 was labelled `verified: true` although the guide only gives "9 SP by level 10"; the spawn-rule rows claimed a mob rate the runtime ignores; evidence recorded no commit; the chair, the Wooden Boxes and two canonical tutorial lines were hard to read or misleading in play. | W4-3, W4-4, W4-6 and W4-7. |

## Phase W4: acceptance fixes (wave 4: two packages, each reviewed)

| # | Problem found | Correction |
|---|---|---|
| W4-1 | A4-2: windows clamped only once, when they opened. | Every `MisoWindow` re-clamps its whole rect into the screen above the HUD status bar on open, drag, resize and a viewport resize. The Skills window keeps one size and opens where it fits. `test_ui_window_fit` opens every window with its largest realistic content at exactly 1600×900. |
| W4-2 | A4-2: headless runs did not see the real screen. | Headless runs are pinned to 1600×900. `click`, `find_control` and the kit's double-click and drag refuse any control whose centre is off screen or that another control covers, and the refusal is a failed check. With the new gate and the old UI, headless `test_skills` fails on the Set key at y 948, exactly where the windowed run failed; after the UI fix it passes in both modes. |
| W4-3 | The playthrough's skill summary could pass with no casts. | It requires real casts, plus the effect or the MP spent for each buff. |
| W4-4 | Readability. | A HUD seated cue ("Seated · +10 HP / 10 s · The Green Relaxer +30 HP / 10 s") and a dark frame on the chair. Wooden Boxes get a warm rim within swing reach and a gold marker while 1012 still needs their items. Box placement now also tests tree canopies (Amherst boxes :2, :4 and :5 moved). The Quest Log's [ready] tag comes first. Speech bubbles hide under modals. The player keeps a 0.8 m gap when talking to an NPC. Marked "[MisoStory]" hint pages follow Heena's mouse-click line and Rain's chair answers; the canonical lines are unchanged. |
| W4-5 | A4-3. | The text now says MeowDB documents fall damage and MisoStory applies none (an adaptation). `mechanic:fall-damage` is a source-data gap, because the movement-update tick and the maps that disable it are unpublished. `mechanic:crouch-down-jump` is excluded as an isometric adaptation. |
| W4-6 | A drop source page could not be applied once read, and one bucket mixed "no member" with "not yet read". | Earlier drop and meso sources were replaced on 2026-10-06 by owner decision (D3-11, D3-12). |
| W4-7 | Proof and honesty. | `starting_sp` is now `verified: false`. The spawn-rule rows name the mob-rate adaptation. `test_monster_def` compares M.DMG, P.DEF, M.DEF and EVA. Playtest reports and unit evidence record the commit, a dirty flag and whether the world was present, and `build_parity` warns on stale evidence. The strict scan covers the driver, walker, grid navigation, input and runner. The natural-recovery clock is clamped into [0, tick) on load. |

## Phase O3: the owner's drop and meso sources (2026-10-06)

The project owner replaced the drop and meso sources on 2026-10-06 (decisions D3-11 and D3-12): MeowDB MS Classic and
Henesys.gg are the only sources of truth. The data and runtime switch, its review, and the documentation pass:

| # | Problem found | Correction |
|---|---|---|
| O3-1 | No rarity source had been read. | `tools/henesys/captures/item_rarity.json` (314e990): Henesys.gg's label for the 64 items on the seven owners' MeowDB community lists, read by hand through the page's own search (no requests to the site during the reads); its README quotes the site's terms (private use only, ask before publishing). |
| O3-2 | The drop records joined the replaced sources. | Schema 3 drop records (d14a860, contract C1): membership from MeowDB's community list on the owner's newest dated capture, every entry with its votes; items by name (Red Cloth Pants by MeowDB's own cached drop entry: 1168); Henesys.gg rarity; the chance category from the item's MeowDB type and subtype and the D3-9 gate; no probability. The owner's chance table (`drop_rates.json`) and meso rule (`meso_rules.json`). The earlier captures, their readers and parsers, and the cross-site name crosswalk were deleted. |
| O3-3 | The runtime, the validators and the tests read the old records. | `DropRates` reads each member's chance from the table and the meso bag from the rule; the authority registry keeps MeowDB, the project owner and Henesys.gg (rarity only); `DropRecordChecks` holds the schema 3 shape, and `DropChecks` holds membership to the capture, rarity to the Henesys.gg capture, the category rule, the gate and the completeness of both rule files (0f5b768); contracts C1 and C7 (462bab0). |
| O3-4 | With the new rolls the gameplay RNG runs differently: on seed 1 `test_d_inventory`'s player died walking through A Split Road before it reached Mai. | The scenario answers that death as its hunts do (the notice's OK, the walk back) and talks again; seeds 1, 2 and 3 pass (044b1a6). |
| O3-5 | Review: `DropChecks` compared membership with whatever capture a record cited, so another owner's list passed; `captures.mjs` chose between two captures of one page by file name; `drops_merge.mjs` could record an older list as the newest; a record could leave out MeowDB's meso report unnoticed; schema leftovers in the validation code; an unnamed mention of a removed source in `src/`. | Every record must cite its owner's own page capture, the newest; the later `read_at` wins (a tie is an error); a newer cache that names other members stops the build; the validator refuses a dropped meso report and a raw value not verbatim in its capture; the leftovers and the mention are gone. Each with a test (1fab2b2, f4a8231). |
| O3-6 | The parity rows did not say which part of a drop row is sourced and which is the owner's. | Each drop row names its membership (the MeowDB capture) and rarity (the Henesys.gg capture), which its tagged tests check, and its chance as the table cell with its value: an owner-approved adaptation (D3-11, `verified: false`), never a source-data gap. Meso rows name MeowDB's report or the level-formula range and the 60% chance (D3-12). The manifest lists the adaptations its entries rest on (0fc524a). |
| O3-7 | The two removed websites were still named in the docs, the raw wave-0 audit, the Iteration One research notes and both briefs. | Every mention is gone. The Iteration Three brief opens with the owner's amendment and states the amended rule where it named them; the Iteration Two brief's list of sources not to mix says "archived fan-site pages"; the audit file is in git history (f9b2bc5); the research notes keep their other sources and drop the claims that rested only on the removed ones; the log keeps a one-line note per replaced decision. What the owner's search pattern still finds is MeowDB data (see the final report). |
| O3-8 | The first final evidence run on these sources (0fc524a) failed seed 2 of the every-quest set: 1006,1009,1010's trail hop out of Snail Hunting Ground I walked 10 m to a ledge corner at map-local (27.0, 1.0, -13.1) and stalled, and its retry stalled there at once. `travel_to` measured the retry from where the hop began (9.3 m back), so it never stepped off. `trap_probe` calls the spot escapable ground: a harness defect. | `PlaytestKit.retry_stalled()`: the retry's own start counts, so `unstick()` runs; a unit test with the run's positions; the chain then passes on seed 2 with one unstick (08df2a7). |
| O3-9 | In the same run Test C's hunter chased a Shroom up a ladder on A Split Road and rested on it: 15 rests of the 150 s budget, 2,250 s of game time, without one natural-recovery tick. A logged diagnostic showed `activity()` "climbing" in all 226 samples: natural recovery pauses while climbing (contract C4), so the game was right and the harness wrong. | `PlaytestKit.rest()` first gets off the climbable (`leave_climb()`: Down to the foot, else Up over the top). The `regen` scenario checks it on 000000001's ladder (HP 40% of 50: 3 s on the ladder change neither the clock nor HP, then the rest climbs down and heals to 40); without the fix the player stays on the ladder and heals nothing (08df2a7; the check moved from `kit` to `regen` in the next commit, because `kit` must stay free of api steps). The evidence set was then run again. |
| O3-10 | The next run (on 7f24d8e) failed `test_death_flow`: the death check scene's new game had not left LOADING after its 2400-frame wait, about 2.5 s with the boot, while three Godot runs shared the machine. A headless frame with nothing to draw can take well under a millisecond, and a threaded island load takes about 2 s on a quiet machine, so the frame budget alone left almost no margin: a latent flake of the three in-game check scenes. | `CheckWait.keep_waiting`: a default-budget wait (a load, a warp, a respawn) lasts its 2400 frames and at least 60 s of wall time; short settle waits keep their frame budget. Nothing a check asserts changes. `test_check_wait.gd` (7ac55c2). The whole evidence set was run again on the final commit. |

## Phase S3: the drop-source switch, stage by stage (2026-10-06)

Phase O3 above holds each problem and its correction. This table follows the switch as one stage: what changed, the
data review, the evidence runs, and how the stage was finished after its documentation agent stopped.

| # | Stage | What happened |
|---|---|---|
| S3-1 | What changed | The owner's decisions D3-11 and D3-12 made MeowDB MS Classic and Henesys.gg the only sources. Drop membership is MeowDB's community list on the owner's newest dated capture, every entry (86 members on 7 owners, all resolved to local items); rarity is Henesys.gg's per-item label (64 items read by hand, 314e990); the chance is the owner's category x rarity table and the mesos the owner's rule. Schema 3 drop records hold no probability (d14a860); the runtime, validators and tests read them (0f5b768); contracts C1 and C7 (462bab0); the earlier captures, their readers and parsers and the cross-site name crosswalk were deleted (O3-1 to O3-3). |
| S3-2 | The data review: 6 defects, all fixed with a test (1fab2b2, f4a8231; O3-5) | 1. `DropChecks` compared membership with whatever capture a record cited, so another owner's list passed: each record must now cite its owner's own page capture, the newest. 2. `captures.mjs` chose between two captures of one page by file name: the later `read_at` wins and a tie is an error. 3. `drops_merge.mjs` could record an older list as the newest: a newer cache that names other members stops the build. 4. A record could leave out MeowDB's meso report unnoticed: the validator refuses a dropped meso report and a raw value not verbatim in its capture. 5. Schema leftovers stayed in the validation code: removed. 6. An unnamed mention of a removed source stayed in `src/`: removed. |
| S3-3 | Fallout in play, parity and docs | `test_d_inventory`'s death on the way to Mai under the new rolls (O3-4, 044b1a6); drop and meso parity rows that say what is sourced and what is the owner's (O3-6, 0fc524a); the removed websites gone from the docs, the briefs, the research notes and the raw audit (O3-7, 64fe2eb). |
| S3-4 | Evidence runs | On 0fc524a: seed 2 of the every-quest set failed a trail hop and Test C rested on a ladder (O3-8, O3-9; fixed in 08df2a7 and 72a9205). On 7f24d8e: `test_death_flow` timed out on a load (O3-10; 7ac55c2). On 1f3120c: every run passed (below). |
| S3-5 | The interruption | The documentation and evidence agent stopped on an API error. Its evidence run on 1f3120c had completed (`_scratch/final3/summary.txt`: every run passed on a clean tree), and its commits up to 1f3120c (the docs, the harness findings H7 and H8, phase O3's rows) were in. Left undone: a two-line uncommitted edit of `DEFERRED.md`, the provenance report, the parity manifest, both playthrough reports, the economy re-measure and this log's final evidence section. |
| S3-6 | How the stage was completed | Nothing under `game/`, `tools/` or `scripts/` had changed after 1f3120c, so the completed run was used as it stood and nothing was re-run. The `DEFERRED.md` edit was checked against the run (seed 2's 1006 chain unstuck once; `regen`'s ladder checks pass) and committed (cb22ca2). A verified drop row now says plainly that its membership and rarity are what its checks verified (a wording change in `tools/parity`, which no Godot test or scenario runs; its node tests pass; 6cfaa72). The provenance report and the manifest were regenerated (35da973), the per-quest tables were regenerated with `PlaytestQuestSummary --combine`, both playthrough reports were rewritten to the run and the economy was re-measured, not re-tuned (d20b979). This section was then rewritten, the zero-reference check run and the evidence archived (`iteration-three/evidence-final3-1f3120c.zip`, outside the repository). |

## Final evidence run

All runs were on code `1f3120c` (2026-10-06; waves 1-4 merged, the owner's drop and meso sources of decisions D3-11
and D3-12 applied, and the harness fixes of phase O3), a clean tree: the unit evidence and every one of the 54 playtest
reports record that commit with `dirty: false`. The world export matches the source (since 4b61650 only a docstring
line under `src/` changed). Wave 4 pinned headless runs to the windowed 1600x900 screen and made a click on a control
a player cannot see or reach fail, so every headless result below is from that harness. The evidence is in
`_scratch/final3/` (git-ignored) and archived as `iteration-three/evidence-final3-1f3120c.zip` outside the repository.

- **Unit suite with the world:** 1564 tests in 174 files, 0 failed, no SKIP line (`TEST_TIMEOUT_S=3000`, 12 minutes).
  The Node tests pass: 49 (31 for sources, 18 for parity). `scripts/check_canonical.sh` reproduces every canonical file
  byte for byte.
- **Canonical data validation:** 0 errors and 0 warnings (192 records; every one of the 86 drop members resolves).
- **Real-game scenarios on seed 1, headless:** all pass: Test A (475 checks, 3 warnings: legs 11, 30 and 50 were not
  walked cleanly, a stretch blocked by props or a stalled route retried, but every leg arrived; no death), B (53, 1
  warning: one Blue Snail skipped after two 4 s approaches), B population (79), C (76, 0 warnings: level 10 by killing
  only in 5,432 s of play, no death), D (90), E (103, 1 warning: its walk from Snail Hunting Ground I to II stalled, and
  the scenario, which is not a strict one, warped on with the console), F (237, 1 warning: no death whose killing
  touch landed mid-jump in 3 tries), G (184), `regen` (32), `test_skills` (51), `test_box` (40: 17 of the 19 boxes
  broken), `trap_probe` (55), `npcs` (66), `npc_shanks` (26), `npc_bubbles` (7), `ui_minimap` (231),
  `save_it2_continue` (55), `pause_load` (12), `resume_gate` (23) and `kit` (21).
- **Windowed (one at a time):** the clean-character playthrough on seed 1 (695 checks, strict), `test_skills` (51),
  `test_box` (40) and `kit` (21): all pass, 0 failed, 0 warnings.
- **Every-quest set:** 20 of 20 on seeds 1, 2 and 3 (520, 523 and 523 quest checks), every chain strict after its
  setup; seed 2's 1006 chain unstuck once at the corner of finding H7.
- **Clean-character playthrough:** passes strict on seeds 1, 2 and 3 headless: 625, 623 and 622 checks, 0 failed, 0
  console or api steps, 8 processes each. It ends at level 8, 8 and 7 with 824, 749 and 440 mesos, after 2,585, 2,534
  and 2,267 s of game time.
- **Economy, re-measured on the owner's tables (nothing re-tuned;
  [`runtime/PLAYTHROUGH_REPORT.md`](runtime/PLAYTHROUGH_REPORT.md) "Loot and mesos").** Per kill the tables give 0.6
  meso bags (none for the Tutorial Jr. Sentinel) worth 1.2 (Snail, MeowDB's 2), 1.8 (Blue Snail), 2.7 (Shroom), 3.6
  (Red Snail) and 7.2 mesos (Orange Mushroom), and 1.13-1.22 items (1.00 of them the species' own leftover;
  equipment 0.6-1.2%; the Tutorial Jr. Sentinel only its Shellpiece). The headless playthroughs picked up 0.52-0.64
  bags, 1.99-2.71 mesos and 1.15-1.18 monster items per kill (329, 322 and 157 mesos in 79, 76 and 41 bags; 142, 141
  and 92 items), each run (the windowed one too) within 1.7 standard deviations of the tables' prediction for its own
  kills; Test C 2.51 mesos per kill (1,500 from 598 kills, predicted 1,535) and `test_d_inventory` 2.51 (153 from 61
  kills, every drop counted). Each species' own leftover was picked once per kill (Snail Shell 53 of
  53 Snail kills, Blue Snail Shell 96 of 97, Mushroom Spore 75 of 75, Red Snail Shell 83 of 84). No equipment dropped
  in the playthroughs (the tables predict 1.23, 1.15 and 0.75 pieces for their kills: a 4% outcome); Test C's bag at
  level 9 holds three dropped pieces (Brown Duo, Razor, Blue Jean Shorts; about 4 predicted). Ores and gems now drop, so
  sales brought 183-395 mesos per playthrough instead of 79-84, and the runs end with 440-824 mesos.
- **Parity manifest** (`docs/MAPLE_ISLAND_PARITY.md`, built from that evidence): 652 entries, 646 verified, 0
  implemented, 3 partial and 0 missing (plus 3 out of scope: item and chair 525, which belong to Victoria Island, and
  `mechanic:crouch-down-jump`, excluded as an isometric adaptation). The 3 partial entries are source-data gaps: fall
  damage (the movement-update length and the maps that disable it are unpublished), no map seats, and no natural MP
  recovery. All 86 drop rows are verified on their MeowDB membership and Henesys.gg rarity, their chance the owner's
  table (an adaptation, D3-11, not a source-data gap); the 6 meso rows on MeowDB's report or the owner's level formula
  and 60% chance (D3-12). No source read is pending, so **0 entries are open for the exit criterion**.

**Final report** (the brief's "Final Deliverables" list):

| What | Count |
|---|---|
| Quests | 20 (MeowDB 1000-1019): 5 chains and 4 standalone quests, all played in the real game |
| Monsters | 6 species (Tutorial Jr. Sentinel, Snail, Blue Snail, Shroom, Red Snail, Orange Mushroom), plus 1 breakable (the Wooden Box, 19 placements) |
| NPCs | 21 |
| Shops | 3 (Pan, Sid, Lucy) |
| Unresolved source-data fields | 375 values ([`PROVENANCE_REPORT.md`](PROVENANCE_REPORT.md) "Unresolved values": the gaps each record lists, among them the drop chance, quantity and meso values no source publishes, which the owner's rules fill); in the parity manifest they leave 3 entries partial, all source-data gaps (above) |
| Deliberate MisoStory adaptations | 122 objects with a verified flag ([`PROVENANCE_REPORT.md`](PROVENANCE_REPORT.md) "Adaptations"): 2 verified (the owner's natural-regen rule, checked against the brief, and the one-way portal allowlist, checked against the canonical maps), 120 not, among them the owner's drop chance table (D3-11) and meso rule (D3-12) |

The deliberate choices. Source decisions: MeowDB cache-only with dated captures read by hand (D3-1); MeowDB's community
drop list on the owner's newest capture as drop membership, every entry, and Henesys.gg's per-item rarity (D3-11; its
labels are for this private project only: Henesys.gg prohibits unauthorized reproduction or scraping, so ask it before
publishing them); the owner's chance table by item category x rarity (D3-11) and meso rule, MeowDB's report or [level,
2 x level] at 60%, none for the Tutorial Jr. Sentinel and the Wooden Box (D3-12); the quest-gate rule (D3-9). MisoStory
adaptations: recovery's tick and the buff cast timing, the chair clock and the sit key (W1-D1, W1-D2); how a Wooden Box
is hit, placed (in the camera's sight, canopies included) and how its drops roll (W1-D3, W1-D4); monster floors,
pacing and spawn spacing, the mob rate not applied (W1-D5); quest wording, the sell guard and Shanks' boundary (W1-D6);
the minimap drawn from the runtime collision (W1-D7); no fall damage, no crouch or down-jump, starting SP 0, and the
marked "[MisoStory]" hint pages after Heena's control lines and Rain's chair answers. Every one has its reason in
`game/data/misostory/` and is listed in the provenance report. What stays open is in [`DEFERRED.md`](DEFERRED.md).
