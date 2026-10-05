# Deferred work

The first part lists what Iteration Three (complete canonical Maple Island) leaves open: unresolved source data,
decisions the project owner has not made yet, art, and the open findings of its reviews. The second part says what
became of the Iteration Two list. The third part is the Iteration One backlog (the Blender island), kept for
reference; most of its gameplay items are now done.

# Left open by Iteration Three (to Iteration Four and later)

Iteration Three built Maple Island's remaining content and mechanics on the Iteration Two foundation and played every
quest in the real game (the every-quest set; [`runtime/PLAYTEST_HARNESS.md`](runtime/PLAYTEST_HARNESS.md)). Per-entry
status is in [`MAPLE_ISLAND_PARITY.md`](MAPLE_ISLAND_PARITY.md) and every unresolved source value in
[`PROVENANCE_REPORT.md`](PROVENANCE_REPORT.md) (519 values: record gaps plus unresolved drop and meso values). These
items were left on purpose or found along the way.

## Out of scope

- Shanks' voyage to Lith Harbor and every Victoria Island map. Talking to Shanks at level 7 with 300 mesos ends at the
  "End of Maple Island" screen: nobody travels and no fare is taken (`misostory/npcs/15.json` `departure`).
- Jobs and job advancement, parties, trading, the Cash Shop, final character, monster and UI art, and audio (the
  brief's out-of-scope list).
- Ask MeowDB for permission before extracting more pages or publishing the dataset
  ([canonical/README.md](canonical/README.md)). KuroDB and Hidden Street were read by hand only, after the project
  owner passed their Cloudflare checks; the same caution applies to them.

## Unresolved source data (never guessed; each stays visible in validation)

- **54 of the 75 drop members never roll** (`bash scripts/validate_data.sh` lists each as a `drop_unresolved`
  warning). 24 have a local item but no KuroDB chance (Blue Potion, Orange Potion, Arrow for Bow and the like); 30
  have no unambiguous local item. Named cases ([`../tools/sources/crosswalk/README.md`](../tools/sources/crosswalk/README.md)):
  - **Omok Piece : Mushroom** (Orange Mushroom, KuroDB 1%): a source-data gap, not an unread page. Hidden Street and
    KuroDB name the drop, but MeowDB has three items of that name (486, 495, 498; their item API bodies are in
    `tools/meowdb/captures/items_api.json`), all quest items with no drop source, so no source says which one it is
    and none is chosen (D3-8). The member never drops; only an owner pick (an adaptation) would settle it.
  - **Scroll for Shoes for Jump 10%** (Orange Mushroom): resolved to MeowDB 177, but KuroDB's possible row "Scroll for
    Shoes for Jump" (2040705, 0.03%) has no success rate, and its item page was not read (D3-8). A hand read of KuroDB
    item 2040705.
  - **Egg on the Wooden Box**: KuroDB lists no reactor-2001 value for it.
  - **Gender-suffixed names with two MeowDB items each:** Blue Cloth Vest (M) (949/958), Black Cloth Pants (M)/(F)
    (1170/1179), Blue Cloth Pants (M) (1169/1178). The genders of 944, 949/958, 1169/1178 and 1170/1179 cannot be
    checked offline.
  - **No MeowDB item in the local cache:** Pan Lid, Wooden Samurai Sword, Pistol (whether MeowDB has them was not
    checked).
  - **20 MeowDB ids without a local item** (`not_in_snapshot`: 944, 916, 625, 727, 721, 720, 650, 722, 1319, 717,
    1435, 943, 951, 735, 617, 1318, 718, 672, 956, 680). None has a KuroDB chance, so none would drop even with an
    item file; adding one makes `extract_monsters.mjs` stop until its crosswalk row is reviewed.
- **The Tutorial Jr. Sentinel's mesos:** Hidden Street says "?" and KuroDB has no meso row, so it drops none.
- **Natural MP recovery:** MeowDB documents none, so MP does not recover naturally (`recovery.json` `natural_mp`).
- **Ground sitting and map benches:** MeowDB documents neither on Maple Island; only chairs sit
  (`recovery.json` `sitting`).
- **Beginner skill timing:** Recovery and Nimble Feet show "Timing unavailable" (cast instantly, lockout 0); how
  Recovery's heal is spread over its 30 s (5 s equal ticks); what a Three Snails cast with no target costs (MP and the
  shell); whether it checks walls and platforms (it does not). All in `skills.json`, `verified: false`.
- **Monster knockback distance** (the 20 px push stays an adaptation; the stagger time is now canonical).
- **Peter's possible scripted warp** (his idle line hints at one; `docs/canonical/maps.md`).
- **Quest timestamps:** `started_at` / `completed_at` are per-process `Game.clock` values (informational only).
- The shop records' `field_sources` cite `{item_id}` template URLs; the real per-item URLs are in `items[]`. A fix
  needs the canonical shop format and the validator's URL handling changed together (`extract_shops.mjs`).

## Decisions for the project owner

- Show the **hidden portal to Tomato Field** (000001020 in00) on the minimap: always, faintly, after the first visit,
  or never (today: never, as in classic).
- Protect **The Green Relaxer** (522, untradeable, cannot be obtained again) from being **sold**: no in-progress
  quest needs it, so the quest-item sell guard does not hold it.
- **The Snail's meso amount:** MeowDB's one player report (2) is kept over Hidden Street's 1. This is the
  orchestrator's reading of the brief ("do not replace MeowDB values"), not an owner decision (D3-5).
- **Skills as Wooden Box hits:** MeowDB says boxes break after 4 "basic attacks" and nothing about skills. Three
  Snails counts as one hit today (one target per cast, the nearest of the monsters and boxes in its band;
  `breakables.json hit_rule`, `verified: false`). Confirm, or have skills search monsters only.
- **Which Omok Piece : Mushroom** (486, 495 or 498) the Orange Mushroom drops, if any: the sources leave it a gap
  (above), so only an owner pick would make it drop.
- **Sera's and Sen's mid-quest lines** ("Did you give my mirror to Heena?", "What did my sister say?") show after
  completion under the default-talk rule; `dialogue/_rules.json` or an override could move them.
- A **player-facing quest forfeit** in the Quest Log (today only the console forfeits; Roger re-issues a lost apple
  instead).
- **Combat reach shapes:** the touch zone is a square prism whose corners reach √2 times further on the diagonals (a
  disc instead?), and the 60 px isometric attack depth reaches monsters up to ±1.21 m (Snail) and ±1.54 m (Orange
  Mushroom) to the side, now drawn with every swing.
- The **map mob rate** is ignored (`presentation.json map_mob_rate.apply` false), a choice between MeowDB pages that
  disagree; the switch exists.
- The **Wooden Box's quantity** of 1 per roll is an adaptation stored inside a canonical record
  (`drops/0000001.json quantity.adaptation`), because C1 lets nothing outside the record supply one. Confirm, or
  move it.

## Art and presentation

- Monster and character proxies stay Iteration One's chibi models with procedural motion; the Tutorial Jr. Sentinel
  proxy is new (a stone sentinel fitted to its 68 px sprite height). Small monsters are about 30 px tall at
  1600x900, and Shroom caps resemble the decorative red mushrooms.
- No skill art: skill icons and the thrown shell are procedural. No buff indicator on the HUD (only a quickslot's
  cooldown sweep).
- The sit pose is a settle and lean onto a procedural chair (the proxy has no skeleton). No seated indicator on the
  HUD.
- Wooden Boxes: lighter, faintly glowing planks keep them apart from the decorative crates. Camera sight is checked
  against collision only, so a box can stand under a colliderless canopy (000001010:4 under the orange tree by Pio's
  neighbour's house); a crate's rotated corner can clip slightly into a wall.
- The attack's hit-area footprint is a flat quad 3 cm above the feet, partly hidden on uneven ground.
- Quest markers over NPCs are drawn even where the HUD bar covers them.
- Flat untextured green slopes fill 40-50% of the arrival frames at 000000040, 000000050 and 000001010.
- The minimap's fold state lasts for the session only; there is no "Map [M]" button on the status bar; on
  000001000 three of eight exit names show only on hover (43 of the island's 46 named in the suite's layout).

## Gameplay and feel

- A pressed jump against a face misses some ledges below the documented 1.35 m reach (6 route ledges need jumps).
- Knockback direction looks random when the monster stands on the player's feet (an offset under 5 cm).
- The canopy dither leaves the player mostly hidden at the moment of contact under the 000001020 autumn trees.
- A ladder-top exit moves the body 0.8 m in one tick, which jolts the camera.
- A 0.25 s snag on the rope-anchor posts in Southperry (000000060).
- East Entrance (000000030): the walk from in00 to out00 takes 38 s for a 39 m straight line (a 2.9x detour).
- Trails take 32% of a full tour; the longest each way are 1012 ↔ 1014 (21.8 s), 1000 ↔ 1006 (20.3 s) and
  1000 ↔ 1004 (16.8 s). Shortening them means re-spacing maps in the island layout.
- Nina's stump roots are passable, so a body clips through them (blender_export.md round 4).
- Holding a skill key casts once per press (no repeat, no input buffer during the lockout).
- While the player stands on a spawn slot (a respawn, a resumed load), the map is at capacity but shows one monster
  fewer until the player moves. `m.mobs` regions without a `z_band` give a walker on sloped ground a ±0.5 m strip
  around its own spawn height.

## Open review findings (verified still open on the integrated build)

- **The parity manifest's one open entry** (`MAPLE_ISLAND_PARITY.md`, built from the final evidence run: 638 entries,
  580 verified, 0 implemented, 56 partial, 0 missing, 2 out of scope): 55 of the partial entries are source-data gaps
  (excused) and one is a pending source read, `drop:9/scroll-for-shoes-for-jump-10` (KuroDB item page 2040705, above),
  which stays open for the exit criterion until that page is read. Two `playtest_tags` rules matched no check in this
  run, both conditional checks whose condition did not occur (`test_c_progression` had no death, so no death-penalty
  check; `ui_minimap` found nothing dropped nearby, so no pickup-announcement check); both keys are verified by other
  evidence.
- **Validation code:** `GameplayDataChecks` is all-or-nothing: any structural error hides the quest, NPC and dialogue
  findings. The progression-blocker check is conservative (it ignores other sources of an item). The test evidence
  records `git rev-parse HEAD` even for a dirty tree, and `build_parity.mjs --check` neither detects stale evidence nor
  runs without the git-ignored evidence files.
- **Crosswalk notes:** the 65 crosswalk reviewer notes were written by script from checked facts; an owner pass may
  be wanted.
- **The stuck-region scan's limits** ([`runtime/STUCK_SCAN.md`](runtime/STUCK_SCAN.md)): verification replays only the
  last edge into a component; hops are swept as an L at apex height; a body wedged on two rims over a narrow gap is not
  modelled; Southperry's double-sided trimesh defeats the buried-surface test (4 ring-top components are listed
  UNENTERABLE). `validate.py ring_band` measures only from the map's base height, and the containment ring leaves every
  gate gap open from top to bottom (the one raised trail mouth, 000001006 out00, is closed in the source). Not built:
  caching scan results by collision content hash (the scan costs 80-110 s in the suite); the reachability of every NPC
  talk zone, spawn slot, portal trigger and Wooden Box placement from the map's entries is checked by `ReachCheck`
  (`test_reachability.gd`). 000001000 is at 391,938 of its 400,000-triangle budget.
- **Saves:** `skill_used` and `skill_leveled` are not autosave triggers (the Skills window requests one itself). A
  save made on a trail arrives at the trail's mouth on Continue, by design (MAP_ARCHITECTURE §4.9).
- **Mechanics:** `PlayerController.activity()` reads `attacking`, not `seated`, on the one tick an attack or cast
  starts from the chair (use `is_seated()` to detect sitting). The "fall" stand-up would fire on a surface where a
  still player's ground state flickers. The natural clock is saved and never reset, so a tick can land within a
  fraction of a second of a Continue or a respawn. Pressing Up at a real portal while seated is tested only through
  the console warp.
- **Quests and NPCs:** `flags.maple_island_departure_ready_at` records the latest boarding, not the first.
- **Harness:** `test_b_combat`, `test_d_inventory`,
  `test_f_death` and `test_g_shop` still carry their own copies of kit helpers. `unstick()` is verified only on the
  talk path. Strict mode's ledger reconciles EXP, mesos, items and quests only; AP, SP, stats, HP and position rest on
  a source scan. Two runs of one seed can part ways on a physics outcome, so a long run is one sample. In the final
  evidence run `test_a_traversal` passes (seed 1: 476 checks, 0 failed, 3 warnings: the walker died once, on leg 30 in
  000001000, and retried the leg; earlier runs died on legs 22 and 46, so "no death" is still not reliable) and so
  does `test_c_progression` (seed 1: 76 checks, 0 failed, 0 warnings, level 10 by killing only with no death).
- **`test_box` breaks 17 of the 19 boxes** (its header says so): Pio's quest takes three of Amherst's six (1/1 Board
  and Screw while it is in progress) and Three Snails one more; two of Amherst's are never broken in the real game.
  Breaking the rest of Amherst after the quest would close it.

## Prevention and tooling

- An export-gate check that the anchor-to-arrival segment is clear at body height (the climbable-vs-trigger check is
  done).
- Harness: seed repeatability across windowed and headless runs; console commands that set HP and MP.
- A human (L4) playthrough of Test A and the gameplay checklist.

# What became of the Iteration Two list

| Iteration Two item | Iteration Three |
|---|---|
| Verify the remaining quests by playthrough | Done: the every-quest set plays all 20 in the real game, strict after setup (20 of 20 on seed 1) |
| Breakables (19 Wooden Box placements) | Done: placement, hits, respawn and quest-gated drops; all 19 stand on real collision (`test_breakables_placement`), and `test_box` breaks 17 of them in the real game (Pio's quest needs three of Amherst's six, Three Snails breaks one more, two are only shown) |
| Beginner skills and the skills window | Done: SP, the Skills window (K), typed quickslots, the three skills |
| Sitting and chairs | Done: X, The Green Relaxer, the chair's own bonus clock |
| Drop chances and meso amounts as placeholders | Done: KuroDB chances on Hidden Street (monsters) and MeowDB (Wooden Box) membership, meso amounts from MeowDB and Hidden Street; what no source gives is unresolved and never rolls |
| Natural regeneration as an adaptation | Done: the project owner's rule (10 HP per 10 s still or seated; pause, never reset) |
| Proxy monsters wider than their touch boxes; the grey Tutorial Jr. Sentinel | Done: footprints within 1.25x of the touch zones, a Sentinel proxy |
| A flood-fill trap survey | Done: the stuck-region scan (0 confirmed traps; 54 former trap spots replayed) |
| No minimap; no exit in view at first arrival | Done: the minimap shows the map's exits with their destinations (the hidden Tomato Field portal excepted) |
| Harness: precise pickup, monster-aware walking | Done: `PlaytestKit.pickup` and the survival policy |
| Continue resumes wherever the last safe ground was | Partly: a resume point whose map collision changed falls back to the saved entry (the shared chunks are not covered) |
| Shanks' ship, Victoria Island, MeowDB permission, the feel items, trail lengths, art | Still open (above) |

# The Iteration One backlog (deferred to Iteration Two)

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
