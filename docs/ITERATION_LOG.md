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
`review/it3_audit.json`). The quest, NPC, shop, item and monster-stat data, and all 577 spawn counts, already match
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
| D3-3 | KuroDB, the brief's source for drop probabilities, sits behind a Cloudflare bot check: automated requests get HTTP 403. | The project owner passed the check in the browser preview. The 6 Maple Island monster pages and 4 item pages (for the Wooden Box drops) were then read one at a time and saved verbatim in `tools/kurodb/captures/`. |
| D3-4 | KuroDB, MeowDB and Hidden Street use unrelated item ids. Snail Shell is 4000019 on KuroDB and has `game_item_id` 4000001 on MeowDB, and some items are named differently on each site. | Drops are joined through a reviewed name crosswalk. Each entry records how it matched (exact, normalized, alias with evidence, or none), and ambiguous names stay unresolved. |
| D3-5 | MeowDB has a meso amount for only one Maple Island monster (Snail: 2 per kill, from one player report). The other five say "No meso reports yet", both in the cache and live. | By the owner's decision, Hidden Street's Before Chaos archive gives the missing amounts: Blue Snail 4, Shroom 4–6, Red Snail 8–12, Orange Mushroom 9–13. The Tutorial Jr. Sentinel's amount is "?", and KuroDB gives it no meso row, so it drops no mesos. The Snail keeps MeowDB's 2, with Hidden Street's 1 recorded as a discrepancy. This last point is the orchestrator's inference from the brief's "do not replace MeowDB values when MeowDB provides them", not an owner decision: the owner's chosen option left the Snail as an open question. The meso drop chance comes from KuroDB: 40% for each of the five regular monsters. |
| D3-6 | MeowDB's monster drop lists are community votes: some entries are voted down, and the live lists already differ from the cache (The Green Relaxer is gone from the Snail's). | By the owner's decision, **monster item-drop membership comes from Hidden Street's per-monster drop lists**, which overrides the brief's "membership = MeowDB". Hidden Street's archive is post-Big-Bang GMS v0.96, a different game version, and its provenance says so. KuroDB supplies chances only for items on both lists. A Hidden Street item without a KuroDB chance stays in the table as unresolved and never drops, and a KuroDB-only item is never added. MeowDB's own lists stay in the records as reference, with their votes. |
| D3-7 | KuroDB shows breakable (reactor) drops as "Chance value N", not as a percentage. The Wooden Box's Old Wooden Board and Rusty Screw are on the path through Pio's quest. | By the owner's decision, N is read as 1/N and labelled an interpretation; this matches the OdinMS-family reactor code. Board and Screw are 100% (quest-gated to Pio's quest), Apple is 25%, and Egg is unresolved, because KuroDB lists no Egg drop for this reactor. The Wooden Box keeps MeowDB's drop membership, because Hidden Street has no breakables. |
| D3-8 | Hidden Street's "Omok Piece : Mushroom", an Orange Mushroom drop with a KuroDB chance of 1%, matches three MeowDB items (486, 495, 498). All three are quest items with no drop sources. | Left unresolved instead of guessing. The same applies to the Orange Mushroom's "Scroll for Shoes for Jump 10%": KuroDB's "Scroll for Shoes for Jump" (item 2040705, 0.03%) may be MeowDB's "Shoes Jump Scroll: Greater" (177, a 10% scroll), but the KuroDB item page could not be checked (the Cloudflare check had returned). |
| D3-9 | Quest-gated drops: KuroDB flags some drops "Quest N", but the brief limits KuroDB to probabilities. | Orchestrator's derivation (`verified: false`): an entry is gated only when the membership source or MeowDB's item subtype marks it a quest item **and** a Maple Island quest requires it. Old Wooden Board and Rusty Screw are gated to Pio's quest (1012). Jr. Sentinel Shellpiece (MeowDB "Monster Drop") is not, even though KuroDB flags it. |
