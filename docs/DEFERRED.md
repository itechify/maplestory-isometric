# Deferred work

The first part lists what Iteration Two (the playable game) leaves for Iteration Three and later. The second part is the
Iteration One backlog (the Blender island), kept for reference; most of its gameplay items are now done.

# Deferred from Iteration Two (to Iteration Three and later)

Iteration Two built the gameplay foundation and proved it with real-game playthroughs
([runtime/PLAYTHROUGH_REPORT.md](runtime/PLAYTHROUGH_REPORT.md)). These items were found along the way and left on
purpose.

## Content (Iteration Three: mostly data, see [runtime/CONTENT_AUTHORING.md](runtime/CONTENT_AUTHORING.md))

- Verify the remaining Maple Island quests by playthrough. All 20 are live through the generic engine; 1002, 1006 and
  1007 → 1008 are verified in the real game, and the others only by unit tests.
- Breakables (the 19 Wooden Box reactors on Maple Island maps): the canonical records exist, but the runtime is not
  built.
- Beginner skills (Three Snails, Recovery, Nimble Feet): the canonical data is extracted, but there is no skill
  system or skills window yet (the K key is reserved).
- Sitting (X) and chairs (recovery.json chairs 522/525: +30 HP per 10 s on top of natural recovery). They need a sit
  pose and the chair items.
- Shanks' ship to Victoria Island, and every Victoria Island map (out of Iteration Two scope).
- Drop chances and meso amounts stay labelled placeholders until MeowDB, or player reports, publish them.
- Ask MeowDB for permission before extracting more pages or publishing the dataset ([canonical/README.md](canonical/README.md)).

## Gameplay polish found in the playtests

- The proxy monster models are 1.1–1.5× wider than their canonical touch boxes, so a visible edge can be whiffed (art).
- The Tutorial Jr. Sentinel is a grey placeholder, and its HP bar crosses its name tag.
- A pressed jump against a face misses some ledges below the documented 1.35 m reach (6 route ledges need jumps).
- Knockback direction looks random when the monster stands on the player's feet (an offset under 5 cm).
- The canopy dither leaves the player mostly hidden at the moment of contact under the 000001020 autumn trees.
- A ladder-top exit moves the body 0.8 m in one tick, which jolts the camera.
- A 0.25 s snag on the rope-anchor posts in Southperry (000000060).
- East Entrance (000000030): the walk from in00 to out00 takes 38 s for a 39 m straight line (a 2.9× detour).

## Prevention and tooling

- An export-gate check that the anchor-to-arrival segment is clear at body height (the climbable-vs-trigger check is
  done: sidecar_diff fails when a ladder is grabbable with Up from inside a press-Up trigger).
- A flood-fill trap survey of every map (MAP_ARCHITECTURE L1's "flood fill" is not built). The A Split Road pocket is
  fixed in the source, and `test_d_stuck` guards it.
- Harness:
  - a precise pickup approach (RouteBot stops 0.75 m away, outside the 0.625 m canonical pickup box)
  - seed repeatability across windowed and headless runs
  - monster-aware walking
  - console commands that set HP and MP
- A human (L4) playthrough of Test A and the gameplay checklist.

## World and wayfinding

- Trails take 32% of a full tour (266.5 of about 830 s). The longest each way are 1012 ↔ 1014 (21.8 s), 1000 ↔ 1006
  (20.3 s) and 1000 ↔ 1004 (16.8 s), with nothing on them. Shortening them means re-spacing maps in the island layout;
  revisit in a world and wayfinding pass.
- Flat untextured green slopes fill 40–50% of the arrival frames at 000000040, 000000050 and 000001010 (environment
  art dressing).
- No exit is in view at any first arrival (16.5–77 m away), and there is no minimap. A minimap with portal markers is a
  later feature (M is reserved).
- Small monsters are about 30 px tall at 1600×900. Shroom caps resemble the decorative red mushrooms, and the Orange
  Mushroom reads as a dome. This is proxy art; revisit it with final character art.
- Nina's stump roots are passable, so a body clips through them (a documented trade-off, blender_export.md round 4).
- Continue resumes wherever the last safe ground was. A runtime unstick or resume-point validation is not built; the
  fix for traps stays in the source world plus the trap survey.

# Deferred to Iteration Two (the Iteration One backlog)

Iteration One answers *what the whole of classic Maple Island looks and moves like in isometric 3D*. The items
below were deliberately left out of scope, or found during review but judged better handled in the next iteration.

## Gameplay and systems (out of scope for Iteration One)

- Player controller, collision and navmesh. Traversal is validated by route-walking raycasts, not by a
  simulated character.
- Combat, monster AI and spawning logic, drops, quests, dialogue, shops, inventories, skills, levelling, the ship
  ride to Victoria Island, networking and accounts.
- Portal transitions (fades or loading) and runtime map streaming. Each classic map is a physical region of one
  scene.

## Characters and monsters

- Rigged, animated characters. The current NPC and monster proxies are static chibi models built from
  primitives: idle bobbing, hopping Orange Mushrooms and crawling snails are deferred.
- Equipment and customization on the player proxy.
- Individual NPC face and hair detail beyond silhouette and colour.

## World and art

- **Exact platform fidelity:** maps translate the classic tier structure and rhythm, not pixel-exact footholds.
  A follow-up could add a foothold-overlay debug view to compare each map with its 2D source.
- Hand-sculpted terrain detail (unique rock formations, eroded edges). Terrain uses the procedural terrace
  language.
- Painted texture maps (diffuse atlases) to replace the procedural material noise, and a final toon/outline
  shader tuning pass.
- Ambient life: animated water, falling-water particles, drifting clouds, swaying grass, butterflies, birds and
  smoke from chimneys.
- Time of day and weather (each map's classic BGM mood: FloralLife, RestNPeace, GoPicnic).
- Audio.
- Interiors: richer furniture sets and a visual link (cutaway or swap) between an exterior building and its
  interior stage.
- Victoria Island in the distance (Lith Harbor, where Shanks sails to) and other world-map context.
- Level-of-detail meshes and impostors for the distant forest; game-engine export (glTF) with collision meshes.

## Tooling

- One-click "render all + validate + contact sheet" CI job.
- A visual diff tool to compare render iterations side by side.

## Found in island review 2 (Iteration Two candidates)

These came up in the second island-wide review (`docs/review/iter2_triage.json`) and were judged polish or
structural work for the next iteration, not blockers for Iteration One.

- **Mushroom Town knoll:** one shared plinth so maps 0, 10000 and 20000 sit on a single knoll joined by at-grade
  village lanes.
- **Island silhouette:** underside crags and hanging spires; a deeper sea (about -420 m); rim bays and promontories;
  a coastal palm and sand treatment east of Southperry.
- **Dark forest style:** a kit `grass_moss`/`grass_dark` terrain style with a matching filler palette, replacing the
  Dangerous Forest's module-local material swaps.
- **Layout-level identity items:**
  - 1000000: a sunken hollow with a twin-door mound shared by its two garden doors.
  - 1000002: entered from the top, so the map becomes a descent.
  - 1000004: a free-standing door mound.
  - Amherst in01 / Townstreet out00: a single marker for the paired portals 7 m apart.
- **Trail polish:** landings or dog-legs on the long main-road stair trails, and a tapered flank on the 40000 → 40001
  ramp.
- **Shading and ribbon polish:** grass hop-ramp side skirts, the ramp-under-lip step (about 0.25 m) where a ramp
  tucks under a cap, residual ribbon lip flaps on the 1000000 road, and a softer door-threshold decal.
- **Code debt:**
  - Workarounds to remove: the 1000002 `_vine` copy and the `climb_route`/`_check_climb` workarounds.
  - Proper structures to add: a crate collider in `kit/interior`, a stored climb position instead of loose
    vertices, and a "passable" tag registry instead of name words.
  - Validator upgrades: a 3-ray blocking test, and checks on non-instance `_Architecture` meshes.
- **Ground detail:** scatter on hill skirts, and groves on the south-garden skirts.
- **Map polish:**
  - 20000: a lawn ramp.
  - 30000: broken-up cliff faces.
  - Amherst: a market band and the six Mystic Door marker stones.
  - 1010003: a front-floor display.
  - Southperry: barrel engines on the ship.

## From the final acceptance check

Judged polish or structural work, so not blockers (`docs/review/final_acceptance.json`, deferrable):

- **Island hull:** it reads as a flat-bottomed striped slab in the low hero shot. Fix with underside crags and
  hanging spires (see above).
- **Peak placement:** the north-rim and NE ridge peaks are evenly spaced cones. Jitter their scale, yaw and offset,
  cluster them, and mix in hills.
- **Cloud collar:** it is soft, but it forms a continuous band that renders grey in the island's shadow. Lift the
  shadow side or break the band up.
- **Trail flanks:** the large green flank wedges under the long stair trails (30000 → 40000, 40002 → 50000) need
  fringe, outcrops and toe bushes.
- **Forest cluster north of Amherst:** it still reads as a grid of rectangular plates. The 1000006 trail (about 60 m)
  is long by layout necessity.
- **Dangerous Forest:** only the canopy is dark. A darker floor (the `grass_dark` style above) and local light would
  finish its mood.
- **Hidden lane:** the hedges on the 1020000 → 1020001 lane are uniform tubes. Give them a more irregular hedge
  silhouette.
- **Ribbon seams:** visible on the 30000 valley road, the 1010004 knoll and basin, and the 50000 T4 ramp seam.
- **Gameplay framing polish:** some house caps clip the top edge (10000, map 0, 1010002).
- **Southperry polish:** a larger ship hovering further out with keel puffs, and the jib still overlapping the
  lighthouse base.
- **1000005:** the jump-tower spire renders as a banded silo, not a mossy rock spire.
- **Flight readability:** map 0's upper flight and the 40000 west knoll flight.
- **Scatter hygiene:** flowers grow from 1000001's stair planks, and a blue toadstool intersects a boulder.
- **Interiors:** 20001's entry-nook lintel, and the 1010003 spiral-stair foot near the Thank-you door.
- **1020001:** the local trellis vine tips show pale hooked stakes.
- **Autumn palette:** the Snail Hunting Grounds and 1020000 share it.
- **30000 rope contrast:** the rope pitches read, but the ropes stay subtle against the dark striped cliff at
  gameplay distance, and the red-and-white climb-flag posts draw the eye more than the ropes.
- **Southperry stern engine pods:** at the stern, the barrel-engine pod reads as if it clips through the hull. Mount
  it on a visible bracket, or move it clear of the hull planking.
- **1000006 bridge at region scale:** the 8 m plank bridge shows its slats close up but is small in the region view.
  A longer or bolder span (contrasting planks, taller lamp posts) would read better.
