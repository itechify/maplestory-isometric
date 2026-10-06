# What has no ticket

Open work is tracked as GitHub issues ([`../AGENTS.md`](../AGENTS.md), [`agents/issue-tracker.md`](agents/issue-tracker.md)).
This file lists what has **no** ticket, and why: work that is out of scope, canonical values no source publishes, what
the project owner decided against, and a reference list of art ideas. The words are used as
[`../GLOSSARY.md`](../GLOSSARY.md) defines them; nothing here is "deferred", because every deferred item has a ticket.

It replaces the lists that Iterations One to Three kept in this file. On 2026-10-06 the owner went through all of them:
each item became a ticket or moved to one of the sections below. Per-entry status of the canonical content is in
[`MAPLE_ISLAND_PARITY.md`](MAPLE_ISLAND_PARITY.md) (the record of v0.3) and every unresolved source value in
[`PROVENANCE_REPORT.md`](PROVENANCE_REPORT.md).

# Out of scope

Excluded by the briefs. Any of these may come back in a later plan.

- **Shanks' voyage to Lith Harbor and every Victoria Island map.** Talking to Shanks at level 7 with 300 mesos ends at
  the "End of Maple Island" screen: nobody travels and no fare is taken (`misostory/npcs/15.json` `departure`).
- **Jobs and job advancement.** The owner's rules for when jobs come into scope (2026-10-06; adaptations until a
  source page gives them):
  - **SP:** a job grants 1 SP at its job-change level and 3 SP per level after it, until the next job-change level.
    The first job gets 1 first-job SP at level 10, then 3 per level up to and including level 30. (The Beginner pool
    is the 9 SP of levels 2 to 10, below.)
  - **Natural MP recovery:** none for most classes. Magicians will get it from a skill.
- **Parties, trading and the Cash Shop.**
- **Audio.**
- **Final character, monster and UI art.** The reference list at the end of this file collects what was noted.

# Source-data gaps

Canonical values that neither MeowDB MS Classic nor Henesys.gg publishes. They are never guessed, and each stays
visible in validation. Only a page of one of those two sites closes a gap; a value the owner supplies in the meantime
is an adaptation (`verified: false`) and is replaced when a source publishes the real one.

- **Drop chances, drop quantities and the meso drop chance.** MeowDB publishes the drop members (its community lists,
  with votes) and player meso reports only; Henesys.gg gives a rarity label per item, not a chance. The owner's table
  (`misostory/drop_rates.json`, category x rarity, decision D3-11) and meso rule (`meso_rules.json`, D3-12) supply
  them. Every one of the 86 drop members resolves (item, rarity and category).
- **Meso amounts of four monsters:** MeowDB has no player report for the Blue Snail, Shroom, Red Snail or Orange
  Mushroom, so the owner's level formula [level, 2 x level] fills them. A report that a newer capture or cache shows
  replaces the formula at the next extraction.
- **The Tutorial Jr. Sentinel's mesos:** MeowDB has no report. The owner's rule: it drops none (D3-12, confirmed
  2026-10-06).
- **Fall damage:** MeowDB documents it (canonical `formulas/movement.json` `fall_damage`: a landing after at least 45
  consecutive fast-falling movement updates deals base 24, rising to 36; "Maps can disable fall damage"), but not the
  length of one movement update or which maps disable it, so the rule cannot be applied as published. The owner's
  ruling (#4, 2026-10-06): MisoStory has no fall damage (`presentation.json` `fall_recovery`).
- **Natural MP recovery:** MeowDB documents none. The owner's ruling (#4, 2026-10-06): none (`recovery.json`
  `natural_mp`; see "Jobs" above for the future Magician skill).
- **Ground sitting and map benches:** MeowDB documents neither on Maple Island; only chairs sit
  (`recovery.json` `sitting`). Rain's quiz 1016 mentions chairs and benches, so a marked "[MisoStory]" page after
  its answers says the sit key works on chairs the player owns.
- **Starting SP:** no page states it. The owner's ruling (#4, 2026-10-06): 0 at level 1 and 1 per level-up up to and
  including level 10, 9 in all, which is also what the Beginner's guide's "9 SP by level 10" leaves
  (`new_character.json` `starting_sp`; none after level 10, `combat.json` `beginner_sp_after_level_10`).
- **Beginner skill timing:** Recovery and Nimble Feet show "Timing unavailable" (cast instantly, lockout 0), and how
  Recovery's heal is spread over its 30 s is not published (5 s equal ticks). All in `skills.json`,
  `verified: false`.
- **Three Snails with no target, and walls:** MeowDB says neither what a cast with no monster in reach costs nor
  whether walls and platforms stop the shell. The owner's rule (2026-10-06): the cast spends the shell and the MP and
  the shell flies and hits nothing; walls block it (the wall test has a ticket).
- **Monster knockback distance:** the 20 px push is an adaptation; the stagger time is canonical.
- **Peter's possible scripted warp:** his idle line hints at one (`docs/canonical/maps.md`); he only talks.

# Decided, not doing

The owner's decisions of 2026-10-06 that end without a ticket, each with its reason, so that a later review does not
raise them again.

## Decided: stays as it is

- **The hidden portal to Tomato Field (000001020 in00) is never shown on the minimap**, as in classic. The world shows
  no swirl or prompt there either; a player finds the hedge lane.
- **MeowDB's in-game street name stays in the data.** The owner's case-insensitive search for the two removed websites
  still matches the street name MeowDB gives some Victoria Island maps: 15 `street_name` values on out-of-scope spawn
  rows in `game/data/canonical/monsters/2.json`, `3.json`, `4.json`, `5.json` and `9.json`, and one line of captured
  page text in `tools/meowdb/captures/monster_9.json`. They are MeowDB data; changing them would falsify it.
- **The drop table and the meso rule are unchanged.** Every cell of `misostory/drop_rates.json` and the rule in
  `meso_rules.json` stay the owner's to change at any time (a few unit tests pin today's values on purpose, listed in
  `runtime/CONTENT_AUTHORING.md` "Drop records (schema 3)"). The measured economy is in
  [`ITERATION_LOG.md`](ITERATION_LOG.md) ("Final evidence run") and
  [`runtime/PLAYTHROUGH_REPORT.md`](runtime/PLAYTHROUGH_REPORT.md) ("Loot and mesos").
- **Monster touch zones stay square.** The corners reach √2 times further on the diagonals, but the canonical touch
  boxes are rectangles and every combat test and scenario is tuned on them.
- **The map mob rate stays ignored** (`presentation.json map_mob_rate.apply` false): three MeowDB mechanics pages say
  the live game ignores it; the map pages that say otherwise call it their best reading. The switch stays in the data.
- **The parity manifest is the record of v0.3 and is not rebuilt** (a ticket marks it as a snapshot). The tests and the
  playtest scenarios guard against regressions without it, and each rebuild costs a full evidence run. Its open review
  findings are therefore not pursued: stale evidence is only a warning, `--check` cannot run without the git-ignored
  evidence files, no evidence digest is committed, a unit test's need for the world is read from the text
  `INCLUDE_WORLD`, and one `playtest_tags` rule matched no check. The rebuild command stays in `runtime/HOWTO.md`.

## Won't fix

- **Crouch and the crouching down-jump** (`mechanic:crouch-down-jump` in `tools/parity/rules.json`): the down key
  walks toward the camera, so there is no crouch stance, and the maps have no pass-through floors to drop through. A
  player reaches a lower floor by walking off its edge or by a rope or ladder.
- **Trail lengths and the East Entrance detour.** Trails take 32% of a full tour (the longest each way are
  1012 ↔ 1014 at 21.8 s, 1000 ↔ 1006 at 20.3 s and 1000 ↔ 1004 at 16.8 s), and the walk across East Entrance
  (000000030) takes 38 s for a 39 m straight line. Shortening either means re-spacing maps in the island layout, which
  every route, collision and scan result depends on.
- **A collider for the interior kit's crate:** no map uses that crate.
- **`BreakableSystem.wanted()` rebuilding a quest definition every 0.1 s** while quest 1012 is active: harmless with
  one gate quest.
- **The stuck-region scan's modelling limits** ([`runtime/STUCK_SCAN.md`](runtime/STUCK_SCAN.md)): verification replays
  only the last edge into a component, hops are swept as an L at apex height, a body wedged on two rims over a narrow
  gap is not modelled, `validate.py ring_band` measures only from the map's base height, and the containment ring
  leaves every gate gap open from top to bottom. The scan reports 0 confirmed traps. (000001000 is at 391,938 of its
  400,000-triangle budget.)
- **One monster fewer while the player stands on a spawn slot** (the map is at capacity again once the player moves),
  and the ±0.5 m strip a walker gets in `m.mobs` regions without a `z_band`.
- **Label crowding on 000001000's minimap:** three of its eight exit names show only on hover; hovering always gives
  the name.
- **A crate's rotated corner can clip slightly into a wall.**
- **Informational timestamps:** a quest's `started_at` / `completed_at` are per-process `Game.clock` values, and
  `flags.maple_island_departure_ready_at` records the latest boarding, not the first. Nothing reads them.
- **The traversal walker can die in `test_a_traversal`:** the scenario records a death as a warning and retries the
  leg, and it passes.

## By design

- `skill_used` and `skill_leveled` are not autosave triggers (the Skills window requests a save itself). A save made on
  a trail arrives at the trail's mouth on Continue (MAP_ARCHITECTURE §4.9).
- The natural-recovery clock is saved and never reset (the owner's rule: pause, never reset), so a tick can land
  within a fraction of a second of a Continue or a respawn.
- The box scenario does not break every Wooden Box of Amherst: breaking the rest after Pio's quest would close it.
- Only windowed runs load the visual chunks, so a check about what is drawn needs a windowed run and a look at its
  screenshots.
- Camera sight of the Wooden Boxes is checked against the tree canopies (`breakables.json` `placement.canopies`,
  measured from the export). If the Blender tree assets change, rerun `test_breakables_canopies` and update that table.

# Reference: art and world ideas

Final art is out of scope, so none of this has a ticket. The list is kept so that the notes are not lost. It was
checked against the source on 2026-10-06: what Iterations One to Three already built was removed.

## In the game

- Monster and character proxies stay Iteration One's chibi models with procedural motion (bob, hop, flinch, a settle
  and lean for the sit pose); the proxies have no skeleton. Small monsters are about 30 px tall at 1600x900, and
  Shroom caps resemble the decorative red mushrooms.
- No skill art: skill icons and the thrown shell are procedural.
- Equipment and customization on the player proxy; individual NPC face and hair detail beyond silhouette and colour.
- Flat untextured green slopes fill 40-50% of the arrival frames at 000000040, 000000050 and 000001010.

## World and art (the Blender island)

- **Exact platform fidelity:** maps translate the classic tier structure and rhythm, not pixel-exact footholds.
  A follow-up could add a foothold-overlay debug view to compare each map with its 2D source.
- Hand-sculpted terrain detail (unique rock formations, eroded edges). Terrain uses the procedural terrace
  language.
- Painted texture maps (diffuse atlases) to replace the procedural material noise, and a final toon/outline
  shader tuning pass.
- Ambient life: animated water, falling-water particles, drifting clouds, swaying grass, butterflies, birds and
  smoke from chimneys.
- Time of day and weather (each map's classic BGM mood: FloralLife, RestNPeace, GoPicnic).
- Interiors: richer furniture sets and a visual link (cutaway or swap) between an exterior building and its
  interior stage.
- Victoria Island in the distance (Lith Harbor, where Shanks sails to) and other world-map context.
- Level-of-detail meshes and impostors for the distant forest.
- A visual diff tool to compare render iterations side by side.

## From island review 2

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
- **Ground detail:** scatter on the hill skirts outside Mushroom Town, and groves on the south-garden skirts.
- **Map polish:** a lawn ramp on 20000; broken-up cliff faces on 30000.

## From Iteration One's final acceptance check

- **Island hull:** it reads as a flat-bottomed striped slab in the low hero shot. Fix with underside crags and
  hanging spires (see above).
- **Peak placement:** the north-rim and NE ridge peaks are evenly spaced cones. Jitter their scale, yaw and offset,
  cluster them, and mix in hills.
- **Cloud collar:** it is soft, but it forms a continuous band that renders grey in the island's shadow. Lift the
  shadow side or break the band up.
- **Trail flanks:** the large green flank wedges under the long stair trails (30000 → 40000, 40002 → 50000) need
  fringe, outcrops and toe bushes.
- **Forest cluster north of Amherst:** it still reads as a grid of rectangular plates.
- **Dangerous Forest:** only the canopy is dark. A darker floor (the `grass_dark` style above) and local light would
  finish its mood.
- **Hidden lane:** the hedges on the 1020000 → 1020001 lane are uniform tubes. Give them a more irregular hedge
  silhouette.
- **Ribbon seams:** visible on the 30000 valley road, the 1010004 knoll and basin, and the 50000 T4 ramp seam.
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
