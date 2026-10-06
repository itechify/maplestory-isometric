# Deferred work

The first part lists what Iteration Three (complete canonical Maple Island) leaves open: unresolved source data,
decisions the project owner has not made yet, art, and the open findings of its reviews. The second part says what
became of the Iteration Two list. The third part is the Iteration One backlog (the Blender island), kept for
reference; most of its gameplay items are now done.

# Left open by Iteration Three (to Iteration Four and later)

Iteration Three built Maple Island's remaining content and mechanics on the Iteration Two foundation and played every
quest in the real game (the every-quest set; [`runtime/PLAYTEST_HARNESS.md`](runtime/PLAYTEST_HARNESS.md)). Per-entry
status is in [`MAPLE_ISLAND_PARITY.md`](MAPLE_ISLAND_PARITY.md) and every unresolved source value in
[`PROVENANCE_REPORT.md`](PROVENANCE_REPORT.md) (375 values: the gaps each record lists, among them the drop chance,
quantity and meso values no source publishes, which the owner's rules fill). These items were left on purpose or found
along the way.

## Out of scope

- Shanks' voyage to Lith Harbor and every Victoria Island map. Talking to Shanks at level 7 with 300 mesos ends at the
  "End of Maple Island" screen: nobody travels and no fare is taken (`misostory/npcs/15.json` `departure`).
- Jobs and job advancement, parties, trading, the Cash Shop, final character, monster and UI art, and audio (the
  brief's out-of-scope list).
- **Crouch and the crouching down-jump** (`mechanic:crouch-down-jump`, excluded in `tools/parity/rules.json`
  `out_of_scope` as an isometric adaptation, `verified: false`): the down key walks toward the camera, so there is no
  crouch stance, and the maps have no pass-through floors to drop through. A player reaches a lower floor by walking
  off its edge or by a rope or ladder, and no input reaches the crouched attack.
- Ask MeowDB for permission before extracting more pages or publishing the dataset
  ([canonical/README.md](canonical/README.md)).
- **Ask Henesys.gg before publishing its rarity labels.** Its site says "Unauthorized reproduction or scraping of this
  content is prohibited"; the 64 labels in `tools/henesys/captures/item_rarity.json` were read by hand for this private
  project only (decision D3-11). A public repository, a release or a screenshot of the data needs its permission
  first, and the labels must never be collected automatically.

## Unresolved source data (never guessed; each stays visible in validation)

No source read is pending. What the sources do not give:

- **Drop chances, drop quantities and the meso drop chance.** MeowDB publishes the drop members (its community lists,
  with votes) and player meso reports only; Henesys.gg gives a rarity label per item, not a chance. The project
  owner's table (`misostory/drop_rates.json`, category x rarity, decision D3-11) and meso rule (`meso_rules.json`,
  D3-12) supply them as adaptations (`verified: false`). Every one of the 86 drop members resolves (item, rarity and
  category), so none is left unresolved.
- **Meso amounts of four monsters:** MeowDB has no player report for the Blue Snail, Shroom, Red Snail or Orange
  Mushroom ("No meso reports yet", also on the live pages), so the owner's level formula [level, 2 x level] fills
  them. A report a newer capture or cache shows replaces the formula at the next extraction.
- **Fall damage** (`mechanic:fall-damage`, a source-data gap): MeowDB documents it (canonical `formulas/movement.json`
  `fall_damage`: a landing after at least 45 consecutive fast-falling movement updates deals base 24, rising to 36;
  "Maps can disable fall damage"), but the length of one movement update is not published and neither is which maps
  disable it, so the rule cannot be applied. MisoStory applies none, on a landing or on a fall recovery
  (`presentation.json` `fall_recovery`, an adaptation; MAP_ARCHITECTURE §4.6).
- **The Tutorial Jr. Sentinel's mesos:** MeowDB has no report; by the owner's choice it drops none (D3-12).
- **Natural MP recovery:** MeowDB documents none, so MP does not recover naturally (`recovery.json` `natural_mp`).
- **Ground sitting and map benches:** MeowDB documents neither on Maple Island; only chairs sit
  (`recovery.json` `sitting`). Rain's quiz 1016 mentions chairs and benches, so a marked "[MisoStory]" page after
  its answers says the sit key works on chairs the player owns.
- **Starting SP:** no page states it; 0 at level 1 is arithmetic from the Beginner's guide's "9 SP by level 10, 1 per
  level-up" (`new_character.json` `starting_sp`, `verified: false`).
- **Beginner skill timing:** Recovery and Nimble Feet show "Timing unavailable" (cast instantly, lockout 0); how
  Recovery's heal is spread over its 30 s (5 s equal ticks); what a Three Snails cast with no target costs (MP and the
  shell); whether it checks walls and platforms (it does not). All in `skills.json`, `verified: false`.
- **Monster knockback distance** (the 20 px push stays an adaptation; the stagger time is canonical).
- **Peter's possible scripted warp** (his idle line hints at one; `docs/canonical/maps.md`).
- **Quest timestamps:** `started_at` / `completed_at` are per-process `Game.clock` values (informational only).
- The shop records' `field_sources` cite `{item_id}` template URLs; the real per-item URLs are in `items[]`. A fix
  needs the canonical shop format and the validator's URL handling changed together (`extract_shops.mjs`).

## Decisions for the project owner

- Show the **hidden portal to Tomato Field** (000001020 in00) on the minimap: always, faintly, after the first visit,
  or never (today: never, as in classic, and the world shows no swirl or prompt there either, so a player has to find
  the hedge lane; the playthrough reaches it because the harness reads the canonical portal list).
- Protect **The Green Relaxer** (522, untradeable, cannot be obtained again) from being **sold**: no in-progress
  quest needs it, so the quest-item sell guard does not hold it.
- **The owner's search for the removed sources still matches MeowDB data.** The case-insensitive search the owner
  gave on 2026-10-06 finds no mention of the two removed websites any more, but it does match
  MeowDB's own in-game street name of some Victoria Island maps (the region the game calls by those two words): 15
  `street_name` values in `game/data/canonical/monsters/2.json` (1), `3.json` (3), `4.json` (2), `5.json` (4) and
  `9.json` (5), all on out-of-scope spawn rows (`maple_island: false`, which the validator skips), and the verbatim
  page text "An Empty House" + that street name in `tools/meowdb/captures/monster_9.json`. Changing them would falsify
  MeowDB data, and captured page text is never edited. Decide: accept them as MeowDB data, or drop the out-of-scope
  spawn rows from the monster records (an extractor change; the capture line stays either way).
- **Tune the drop table and the meso rule** if play shows a need: every cell of `misostory/drop_rates.json` and the
  meso rule in `meso_rules.json` are the owner's to change (no record or test pins a number). The measured economy of
  the final evidence run is in [`ITERATION_LOG.md`](ITERATION_LOG.md) ("Final evidence run") and
  [`runtime/PLAYTHROUGH_REPORT.md`](runtime/PLAYTHROUGH_REPORT.md) ("Loot and mesos"): meso bags and items per kill
  as the tables predict, sales 183-395 mesos per playthrough because ores and gems drop (one Amethyst Ore sells for
  200), 440-824 mesos at Shanks, and no equipment drop in the three playthroughs (the 0.1% Common Equip cell predicts
  0.75-1.23 pieces per playthrough; Test C's bag held three by level 9).
- **Square or disc touch zones:** a monster's touch zone is a square prism whose corners reach √2 times further on
  the diagonals (a disc instead?), and the 60 px isometric attack depth reaches monsters up to ±1.21 m (Snail) and
  ±1.54 m (Orange Mushroom) to the side, drawn with every swing.
- **The Skills window overlaps the Quest Log** when both are open: the five windows are wider together than the
  1600 px screen, and the Skills window (one fixed size, about 570 px tall) fits its full height only above the
  Quest Log's bottom edge (`UI.md` "Known gaps"). Place it elsewhere, shorten it, or keep it (either can be dragged).
- **Whether Three Snails may hit Wooden Boxes:** MeowDB says boxes break after 4 "basic attacks" and nothing about
  skills. Three Snails counts as one hit today (one target per cast, the nearest of the monsters and boxes in its
  band; `breakables.json` `hit_rule`, `verified: false`). Confirm, or have skills search monsters only.

- **Sera's and Sen's mid-quest lines** ("Did you give my mirror to Heena?", "What did my sister say?") show after
  completion under the default-talk rule; `dialogue/_rules.json` or an override could move them.
- A **player-facing quest forfeit** in the Quest Log (today only the console forfeits; Roger re-issues a lost apple
  instead).
- The **map mob rate** is ignored (`presentation.json map_mob_rate.apply` false), a choice between MeowDB pages that
  disagree; the switch exists, and every spawn-rule row of the parity manifest names this adaptation.

- **The Wooden Box's reach rim:** the warm rim that shows while a swing can reach a box is faint (0.06 m); the gold
  marker shown while a quest wants a box's drops reads clearly. Make the rim stronger if wanted (`wooden_box.gd`
  `REACH_RIM_M`, `REACH_COLOR`).

## Art and presentation

- Monster and character proxies stay Iteration One's chibi models with procedural motion; the Tutorial Jr. Sentinel
  proxy is new (a stone sentinel fitted to its 68 px sprite height). Small monsters are about 30 px tall at
  1600x900, and Shroom caps resemble the decorative red mushrooms.
- No skill art: skill icons and the thrown shell are procedural. The HUD's effects bar (top right) shows Nimble Feet
  and Recovery with their time left, but its icons are small (about 24 px) and far from the status bar.
- The sit pose is a settle and lean onto a procedural chair (the proxy has no skeleton). The HUD shows a seated cue
  above the HP gauge ("Seated · +10 HP / 10 s · The Green Relaxer +30 HP / 10 s"), and the chair has a dark wooden
  frame around its green cushions. The frame has not been seen on grass: in the final windowed playthrough the player
  sits on Amherst's grey road, where the cue reads clearly but the chair under the leaning body hardly shows.
- Wooden Boxes: lighter planks, a warm rim while in reach (faint, above) and a gold marker while a quest wants their
  drops set them apart from the decorative crates. Camera sight is now also checked against the tree canopies
  (`breakables.json` `placement.canopies`, measured from the export; Amherst boxes 000001010:2, :4 and :5 moved out from
  under them). If the Blender tree assets change, rerun `test_breakables_canopies` and update that table. A crate's
  rotated corner can clip slightly into a wall.
- The attack's hit-area footprint is a flat quad 3 cm above the feet, partly hidden on uneven ground.
- Quest markers over NPCs are drawn even where the HUD bar covers them.
- Flat untextured green slopes fill 40-50% of the arrival frames at 000000040, 000000050 and 000001010.
- The minimap's fold state lasts for the session only; there is no "Map [M]" button on the status bar; on
  000001000 three of eight exit names show only on hover and the labels crowd the terrain (43 of the island's 46
  named in the suite's layout).

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

## Open review findings (verified still open on the final build)

- **The parity manifest** (final evidence run at `1f3120c`: 652 entries, 646 verified, 0 implemented, 3 partial, all
  source-data gaps, 0 missing, 3 out of scope, 0 open for the exit criterion) rests on git-ignored evidence (archived
  outside the repository as `iteration-three/evidence-final3-1f3120c.zip`). Each input
  now records its commit, a dirty flag and (unit evidence) whether the exported world was present, and
  `build_parity.mjs` warns on the console about missing or mixed commits, dirty trees and code trees that differ from
  HEAD; but stale evidence is only a warning (an older unit evidence file could still verify a drop entry whose data
  changed after it ran), `--check` cannot run without the evidence files, and no compact evidence digest is committed. A
  unit test's need for the world is read from the text `INCLUDE_WORLD` in its file (`test_gate_monitor.gd` needs the
  world without saying so; it carries no parity keys today). One `playtest_tags` rule matched no check in that run:
  `test_c_progression`'s "each death took the canonical EXP penalty" runs only when the hunter dies, which it did not;
  its key, `mechanic:death-respawn`, is verified by other checks (142 passing). The manifest's build also warns that
  `tools/` differs from the evidence commit: only the drop rows' wording in `tools/parity` changed after the run.
- **Validation code:** `GameplayDataChecks` is all-or-nothing: any structural error hides the quest, NPC and dialogue
  findings. The progression-blocker check is conservative (it ignores other sources of an item).
- **Research notes edited by hand:** `docs/MAP_INVENTORY.md`, `docs/topology.json` and `docs/topology.mmd` are
  generated by Iteration One's `docs/research/raw/synthesis/build_topology.js` (git-ignored, in the main checkout,
  not in this worktree). On 2026-10-06 the first two were edited by hand to remove the citations of the removed
  sources; the generator's template and research inputs still carry them, so edit them before regenerating.
- **Green Apple (242) and Shoes Jump Scroll: Greater (177)**, drop members under the earlier drop sources, stay in the
  item subset (`extract_items.mjs` `ITEM_IDS`), although since the owner's 2026-10-06 decision neither is a drop member,
  a quest item or a shop item (177 is only on the Orange Mushroom's MSEA reference list). Harmless; remove them if the
  subset should hold only items the game can give.
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
  the console warp. `BreakableSystem.wanted()` rebuilds a QuestDef every 0.1 s while quest 1012 is active (harmless
  at one gate quest; could be cached).
- **Quests and NPCs:** `flags.maple_island_departure_ready_at` records the latest boarding, not the first.
- **Harness:** `test_b_combat`, `test_d_inventory`, `test_f_death` and `test_g_shop` still carry their own copies of kit
  helpers. `unstick()` is verified on the talk path and on a trail hop (seed 2 of the every-quest set's 1006 chain,
  since the 2026-10-06 fix); `leave_climb()` by the `regen` scenario. Strict mode's ledger reconciles EXP, mesos, items
  and quests only; AP, SP, stats, HP and position rest on a source scan, which now covers the strict scenarios, the
  kit, the quest runner, the driver, the walker, the grid planner, the input and the runner, but not the scenario base,
  the process runner or the ledger. Two of the wave-4 playtest checks are weak (the unit tests behind them are not):
  the playthrough's "no speech bubble while a shop is open" depends on the bubble schedule, and `test_box`'s cue check
  reads the box's flags, not its meshes. Two runs of one seed can part ways on a physics outcome, so a long run is one
  sample. In the final evidence run `test_a_traversal` passes (seed 1: 475 checks, 0 failed, 3 warnings: legs 11, 30
  and 50 were not walked cleanly, a stretch blocked by props or a stalled route retried; no death this time, but the
  walker has died in earlier runs, so "no death" is still not reliable) and so does `test_c_progression` (seed 1: 76
  checks, 0 failed, 0 warnings: level 10 by killing only in 5,432 s of play, no death; it rested 9 times, once after
  climbing off a ladder).
- **`test_box` breaks 17 of the 19 boxes** (its header says so): Pio's quest takes three of Amherst's six (1/1 Board and
  Screw while it is in progress) and Three Snails one more; two of Amherst's are never broken in the real game. Breaking
  the rest of Amherst after the quest would close it.

## Prevention and tooling

- An export-gate check that the anchor-to-arrival segment is clear at body height (the climbable-vs-trigger check is
  done).
- Harness: console commands that set HP and MP. Headless runs now use the windowed 1600x900 GUI area and click only
  what a player could (PLAYTEST_HARNESS.md "Headless and windowed"), but only windowed runs load the visual chunks, so
  a check about what is drawn still needs a windowed run and a look at its screenshots.
- A human (L4) playthrough of Test A and the gameplay checklist. Every playthrough so far is scripted: the harness
  reads canonical data for quiz answers, NPC maps and monster positions, so "quest states are understandable without
  debug mode" rests on automated checks that the markers, Quest Log rows and notices exist, plus the screenshots of
  the windowed runs.

# What became of the Iteration Two list

| Iteration Two item | Iteration Three |
|---|---|
| Verify the remaining quests by playthrough | Done: the every-quest set plays all 20 in the real game, strict after setup (20 of 20 on seeds 1, 2 and 3), and the clean-character playthrough plays them all from character creation |
| Breakables (19 Wooden Box placements) | Done: placement, hits, respawn and quest-gated drops; all 19 stand on real collision (`test_breakables_placement`), and `test_box` breaks 17 of them in the real game (Pio's quest needs three of Amherst's six, Three Snails breaks one more, two are only shown) |
| Beginner skills and the skills window | Done: SP, the Skills window (K), typed quickslots, the three skills |
| Sitting and chairs | Done: X, The Green Relaxer, the chair's own bonus clock, a seated cue on the HUD |
| Drop chances and meso amounts as placeholders | Done: MeowDB community-list membership, Henesys.gg rarity and the owner's chance table by category x rarity (D3-11); MeowDB's meso report or the owner's level formula at 60% (D3-12) |
| Natural regeneration as an adaptation | Done: the project owner's rule (10 HP per 10 s still or seated; pause, never reset) |
| Proxy monsters wider than their touch boxes; the grey Tutorial Jr. Sentinel | Done: footprints within 1.25x of the touch zones, a Sentinel proxy |
| A flood-fill trap survey | Done: the stuck-region scan (0 confirmed traps; 54 former trap spots replayed) |
| No minimap; no exit in view at first arrival | Done: the minimap shows the map's exits with their destinations (the hidden Tomato Field portal excepted) |
| Harness: precise pickup, monster-aware walking | Done: `PlaytestKit.pickup` and the survival policy |
| Continue resumes wherever the last safe ground was | Done: a resume point whose map collision changed, or a shared `World_*` chunk its region overlaps, falls back to the saved entry (`MapDefinitions.resume_hash`; SAVES.md) |
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
