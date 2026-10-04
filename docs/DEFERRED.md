# Deferred to Iteration Two

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
