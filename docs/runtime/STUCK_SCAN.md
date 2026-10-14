# The stuck-region scan

Iteration Two found two places where a player could fall into an enclosed pocket, both by playing. Iteration Three's
brief (Phase 13) asks for a systematic scan of all 25 maps instead: find every walkable place the player can get
into but not back out of, to the main traversal graph, a portal or an intended path, and fix the real ones in the
Blender source (no teleport failsafes over bad terrain).

| Piece | Path |
|---|---|
| the scanner (`StuckScan`) | `game/tools/stuck_scan.gd` |
| the command line | `game/tools/stuck_scan_tool.gd`, `stuck_scan_tool.tscn` |
| the report | `docs/runtime/stuck_report.json` (regenerated at milestones) |
| reviewed results: intended dead ends (none) and reviewed UNENTERABLE components (9) | `game/data/misostory/stuck_allowlist.json` |
| the guard in the suite | `game/tests/unit/test_stuck_scan.gd` |
| the cache of the results (git-ignored) | `_scratch/stuck_scan_cache/` |
| the former-trap regression | `game/tools/playtest/scenarios/trap_probe.gd`, `game/tests/unit/test_playtest_traps.gd` |
| the Blender-side guard | `scripts/validate.py` check `ring_band` |

## Method

The scan runs in Godot on the island's real collision: `IslandWorld.build_now()` with visuals off builds every
collision chunk with the world's own layer table, the containment rings, plugs and trail side walls (about 1 s).
Only Godot can do this, because the rings, region extensions and layer classes are built at runtime, and only Godot
can run the real `PlayerController` for the verification stage.

### 1. Nodes

Per map, the scan covers the map's region (its footprint polygon, which is the containment ring line, with its region
extensions) and the zones of its trails. On a world-aligned grid of 0.35 m columns it casts repeated downward rays on
the player's collision mask (`WorldLayers.PLAYER_MASK`, the mask of the controller's feet rays) and records every
surface of the column, top down. A surface is a **node** (a place the feet can stand) when all of these hold:

- its normal is within the controller's `floor_max_angle` (38 degrees);
- the body capsule (`body_radius` 0.3 m, from `step_up` 0.45 m to `body_height` 1.5 m above the feet, exactly the
  controller's collision shape) overlaps nothing;
- it is not buried inside a closed solid: going down the column, every surface met above the feet enters a solid;
  going up from the feet, every face met is the bottom of one. More tops than bottoms means the feet are inside a
  solid. (Jolt reports no back faces, to rays or to point queries, and a capsule inside a hollow trimesh overlaps no
  triangle, so this face count is the only reliable test. Under a one-sided sheet, such as a plinth skirt or a
  trail's shell, also counts as buried; the body passes such sheets only from below.)
- under a double-sided trimesh (`collision.double_sided_trimesh`: Southperry's chunk), feet that stand on something
  else (a ring's box, a prop's hull) are not inside one of its solids: the first of its faces below the feet is not a
  back face. A double-sided trimesh shows its back faces to a ray that asks for them (`hit_back_faces`), a one-sided
  one never does. The face count misses such feet where two solids' tops lie in one plane (see Limits); feet standing
  on a double-sided face are left to the count, since the ship's decks lie inside its hull;
- it is above the map's `kill_y`.

### 2. Edges

Every number comes from `MovementModel.from_db()` (canonical MeowDB values through `WorldScale`, plus
`data/misostory/movement.json`). Edges come in two kinds, because the two searches need opposite errors:

| Kind | Used by | Edges |
|---|---|---|
| **certain** | both searches | **walk** to the first surface of a neighbour column within `step_up` above and `snap_down` below the feet (the controller's feet rule); **drop** off an edge onto the first surface below, with the capsule swept across and down; **ladder** for every node in a ladder's, rope's or vine's grab band along its whole length (Up from the line, a jump with Up held from below the band, Down from the top), to its top exit and its foot (descend-only ropes only down); **jump** (refined, see below) |
| **into** | the forward search only | **long drop** (momentum carries a walk-off as far as the walk speed over the fall time of that drop), **slide** (a walk-off whose fall brushes a wall: the body is pushed onto the nodes beside the landing), **hop** (a running jump from an edge node: up to `jump_apex + step_up` high, or as far as the walk speed over the jump's air time carries it to a lower landing, down to 12 m below; swept as an L) |

An escape the graph claims must be real, since nothing re-checks it, so certain edges are strict; into edges may be
generous, because the verification stage clears what the controller cannot get into. They must not be short: a way
in the forward search lacks hides every trap behind it. The air time counts gravity, the `max_fall_speed` cap and
`coyote_time` (a jump pressed just after walking off still fires); a running jump off a 3.4 m ledge carries the body
about 3.2 m. (Until the Iteration Three review the hops stopped at 3 columns and 1.5 m down and the long drops at 5
columns; the review's scan with the controller's reach found two traps the real controller confirmed, below.)

### 3. Searches and components

- **Entries** (forward seeds): every player spawn, every portal's arrival (`spawn_transform`, including the arrival
  gates such as 000000040's), and every point of the map's authored routes.
- **Exits** (backward seeds): the press-Up triggers of the canonical portals (the hidden type-1 000001020.in00
  included), and a crossing of the far gate of each of the map's trails (past the plane, inside its corridor and
  height band: GateMonitor's arm rule).
- A node that the forward search reaches and the backward search does not is **flagged**.
- **Refinement:** for flagged nodes only, certain jump edges are computed (they are the expensive edges): a running
  jump lands when the controller would land, while descending with the feet within `step_up` below the surface, at
  most `jump_apex + step_up - 0.2 m` above the take-off, and at no more than the walk speed. The capsule is swept
  along the arc, and the feet must not meet another surface first. A jump that reaches an escapable node makes the
  node escapable, and the backward search continues from it.
- The remaining flagged nodes are grouped into **components** (union-find over any edge between them). Each one gets
  its map-local and Blender-local position, height span, floor colliders, entries inside it and the likeliest ways in.
- **Outside the regions:** the reachable nodes in no map region and no trail zone (`RegionIndex`) are counted per map
  (`outside_regions`). An escapable one means the main traversal graph leaves the regions (the containment let the
  body out; RegionMonitor fails dev builds there), and fails the test. The review found 6 in 000001006: the dell
  under the out00 bridge opened through the ring's gate gap onto the hill outside.

### 4. Verification with the real controller

For each component the game's `PlayerController` runs synchronously in a `PlayerTestWorld` on the same island
collision:

1. **Getting in.** Up to 8 ways in are replayed from the escapable node: walking at full speed, creeping at 30 %, and
   hopping. They are taken in turns from every kind present (walks and drops, then slides, longer drops and hops),
   within a kind by the smallest height change and from take-off nodes not used yet, so a component with many slides
   still has its long drops and hops tried.
2. **Getting out.** From up to 3 members (the one nearest the centre, then the farthest ones) up to 120 scripted tries:
   toward the nearest escapable nodes (walking, hopping with jump held, and a run-up), then in 16 directions
   (walking and hopping). Up is held, re-pressed every 12 ticks, so ladders and ropes are grabbed and climbed; on a
   climbable only Up is held (a direction toward the camera would read as Down), and a climb under way may run 10 s
   past the try. A try ending on a new flagged spot more than 1 m away becomes another start (up to 3). The first
   tries are the graph's own guesses: walk to a member beside escapable ground and hop onto it. A try succeeds when the
   controller stands on escapable ground, stands in a press-Up trigger or crosses a gate.

| Verdict | Meaning |
|---|---|
| CLEARED | every sample got out: a false positive of the graph |
| CONFIRMED | a sample could not get out, and the controller got in (or an entry lies inside): a trap |
| UNENTERABLE | a sample could not get out, but no replayed way in got the controller there |

`test_stuck_scan.gd` fails on a CONFIRMED component that the allowlist (`stuck_allowlist.json` `entries`) does not
list, on an UNENTERABLE one that its reviewed list (`unenterable`, each with why no body gets there) does not list,
on an escapable node outside every region, and on a map whose scan has no entries, exits or reachable ground. An
UNENTERABLE verdict is not proof: the replays cover the last edge into a component, not every way a player could
reach it, and four UNENTERABLE rooms and shafts of the first scans were real traps (closed below). So a new one is
inspected by hand, then fixed or listed.

## Limits

- The scan follows the player's mask and the containment as built, in each link's configured mode (edge mode: every
  trail walkable). A pocket reachable only in warp mode is not scanned separately.
- One ray per column: a surface narrower than a column can be missed or misjudged; the verification stage absorbs
  this.
- The buried-surface test needs closed, outward-facing solids, and a column sees two faces in one plane as one: where
  a solid's top is level with another's (Southperry's quay front: a wall whose top is level with the planks lying on
  it), the count meets one top for two solids and can balance with the feet inside. Double-sidedness does not change
  the count (the scan's rays skip back faces either way), but it makes the back faces visible, so under a
  double-sided trimesh the back-face test (section 1) catches it. That case gave four UNENTERABLE components on the
  ring top inside the quay wall until issue #34. Elsewhere such feet stay a node, and the verification stage
  carries the check.
- Into edges model the ways in that matter for traps (walking off, falling, running jumps); a way in that needs a
  precise jump sequence over several ledges, or steering in the air, may be missed. A hop is swept as an L (up to the
  apex, across at the apex height, down), which can block a long low jump under an overhang.
- The verification replays only the last edge into a component; the take-off node's own reachability is the forward
  graph's (generous) word. A CONFIRMED verdict is checked by hand before a fix.
- Knockback, crouch drop-through (the controller has none) and mid-air rope catches out of a fall are not modelled
  as edges.
- The escape search is short range (3 s tries): a component whose only way out is far away and needs several
  deliberate moves may be CONFIRMED where a patient player escapes. Every CONFIRMED component is inspected by hand
  before it is fixed or allowlisted.
- A body wedged on two rims over a gap narrower than itself (resting without reaching the floor) is not modelled; the
  single-column UNENTERABLE gaps are such places.
- `validate.py ring_band` measures the band inside the ring against the map's base height, so a slot above the base
  (000001021's, 1.2 m up on the west bank) passes it: the scan is the guard there.

## How to run

```bash
# every map, verified; writes docs/runtime/stuck_report.json (run on the real game/ directory, not an ISOLATE copy)
bash scripts/godot.sh --headless --path game res://tools/stuck_scan_tool.tscn
# some maps, graph only, with top-down pictures (green escapable, red confirmed, purple flagged, grey unreachable)
bash scripts/godot.sh --headless --path game res://tools/stuck_scan_tool.tscn -- --map 000000041,000001010 \
    --no-verify --png "$PWD/_scratch/stuck_png" --out "$PWD/_scratch/stuck.json"
# what the graph says about map-local points (regions, every surface of the column with its node state, the forward
# path from an entry, the nearest escapable ground): the way to inspect a finding by hand
bash scripts/godot.sh --headless --path game res://tools/stuck_scan_tool.tscn -- --map 000001004 --no-verify \
    --inspect "35.44,0,-27.75;30.65,0,-26.4"
# the guard in the suite (all 25 maps, verified; from the cache when nothing changed)
ISOLATE=stuck INCLUDE_WORLD=1 bash scripts/test.sh stuck_scan
# the same, scanning every map whatever the cache holds (the tool: --no-cache)
STUCK_SCAN_CACHE=0 ISOLATE=stuck INCLUDE_WORLD=1 bash scripts/test.sh stuck_scan
# a spot in the real game, with real input (escape = escapable ground by the live scan, a portal or a gate)
TRAP_MAP=000001010 TRAP_LOCAL="76.70,-2.50,-37.57" bash scripts/playtest.sh trap_probe
# the Blender-side guard
"$B" -b MapleIsland.blend --python scripts/validate.py      # check ring_band
```

The tool exits 1 when a CONFIRMED component is not allowlisted, an UNENTERABLE one is not reviewed, or an escapable
node lies outside every region.

## The cache

A full scan takes 80-110 s and gives the same result for the same collision, so `StuckScan.run()` keeps each map's
result (the report's row and components, with their nodes' positions) and reads it back when nothing it depends on
changed. A STUCK_CACHE line of the tool, and the island test's STUCK line, say how many maps came from the cache.

- **The key** (`StuckScan.cache_key()`) is a SHA-256 over what a result depends on:
  - the collision the player meets, as built (`collision_digest()`): every collision object on the player's mask
    under the island, by path, with its layer, its transform and its shapes' stored properties (a trimesh's faces and
    sidedness, a box's size). It covers the exported collision meshes and the rings, plugs and trail walls the island
    builds at runtime, so it changes with one vertex of one map's collision. The exported glbs and sidecars are not
    hashed as files: what they build is;
  - every map's graph inputs (`map_graph()`): its region polygons, kill_y, entries, climbables, exit portals' triggers
    and gates. Every map's, since another map's region decides what counts as outside every region;
  - the movement model's numbers, the cell size and whether components are verified;
  - the scanner's code (`StuckScan.SOURCES`): the scanner and the controller, model, input and definitions its
    verification runs, as source text, so any edit to them (a comment too) scans again. An edit elsewhere that changes
    how the controller moves (a stat formula, say) does not change the key: scan with the cache off after one.
- **Not in the key: the allowlist.** Every run matches the components, stored or scanned, against
  `stuck_allowlist.json` as it is then, so reviewing a component or removing an entry needs no new scan.
- **Where:** `_scratch/stuck_scan_cache/` in the repository that holds the project (`_scratch/` is git-ignored). An
  ISOLATE copy under `_scratch/godot_runs/<name>/` finds the same directory, so the copies share it and the mirror
  never wipes it; one file per key (`stuck_scan_<key>.bin`, Godot's `store_var`, about 90 KB), the 4 newest kept.
  `STUCK_SCAN_CACHE=<dir>` puts it elsewhere; outside a git checkout it is `user://stuck_scan_cache`.
- **Off:** `STUCK_SCAN_CACHE=0` (or `off`), the tool's `--no-cache`, or `StuckScan.create(..., {"cache": ""})`. A run
  with `--png` scans every map it draws (the pictures need the graph).
- **Same results:** a run from the cache reports what a fresh scan does, but for the timings (`ms`, `sample_ms`,
  `edges_ms`, `verify_ms`, which are the stored run's) and the report's `cache` field. `test_stuck_scan.gd` checks
  this on two maps, and the full report of a fresh scan and one from the cache differed only there (2026-10-06).

## Results

### The runs of Iteration Three (2026-10-05)

Every run covers all 25 maps with verification (the scanner itself changed between some rounds; the last two rows
are the final scanner, with the running-jump reach of the review). Times are wall times on the dev machine, the island build (about 1 s) not included.

| Run | World | Flagged nodes | Components | CONFIRMED | CLEARED | UNENTERABLE | Time |
|---|---|---|---|---|---|---|---|
| first full scan | the base export | 59,893 | 93 | 42 in 13 maps | 25 | 26 | 325 s |
| after fix round 1 | world.py corner rule, first fills | 5,979 | 76 | 32 in 11 maps | 25 | 19 | 254 s |
| after fix round 2 | more fills, ropes, a vine, a stepping stone | 1,219 | 51 | 5 in 5 maps | 28 | 18 | 77 s |
| after fix round 3 | the last fills | 935 | 42 | 0 | 24 | 18 | 61 s |
| engineer's final | rooms and shafts closed (below) | 419 | 38 | 0 | 24 | 14 | 54 s |
| review: running-jump reach | the same world | 433 | 49 | 4 in 2 maps | 33 | 12 | 78 s |
| **final** | 000001021 fill, 000001006 bridge abutment | 408 | 38 | **0** | 25 | 13 | 86 s |

The first scan's 42 traps fell into four groups, all fixed in the Blender source:

- **Map-corner slots** (6 maps: 000000041, 000000050, 000001000, 000001001, 000001010, 000001012, the six spots of
  the audit among them): 2.3-2.7 m deep slots between the plinth's rounded top and the containment ring's square
  corner. (The run's two largest components, 28,252 and 25,182 nodes of the island body under 000001000 and
  000001010, are gone since round 1, in which both the scanner and the corners changed.) Fixed by the plinth rule
  in `world.py` (`THIN_MARGIN_M`, `corner_radius`):
  portal sides get a 1.2 m margin, and every corner covers the footprint corner pushed out 0.85 m, the farthest a
  body's centre gets inside the ring. `validate.py ring_band` guards the class.
- **Plinth-level pockets walled in by terraces** (000000041, 000000042, 000000060, 000001000, 000001001, 000001004,
  000001014, 000001020, and terraces that stopped short of the ring in 000000041, 000000060 and 000001005): filled
  0.2 m below the terrace they join, or the terrace reaches the ring band.
- **Caverns under floating terraces** (000001003, 000001004): the terraces reach the ground.
- **Walled-in yards** whose fix is a way up in the map's own idiom: a rope in 000000041 (the slot behind T22), a
  stepping stone in 000000042 (the courtyard on T15), a vine in 000001002 (the back yard behind the battlements).

The last round closed four components the real controller could not get into (UNENTERABLE) but that were real open
space no one could have left: 000001004's 61 m² room under the upper ledges and top beds (they now reach the ground,
and the 0.8 m slot between stone T7 and ledge T4 is filled), 000000041's crevice between T30, T29 and the T31 shelf,
000000042's hole in the ring corner under the ridge T3, and 000001005's shaft between the branch T8 and the canopy.
The review of the package (same day) found that the forward search's hops stopped at 3 columns and 1.5 m down and its
walk-offs at 5 columns, while a running jump off a ledge carries the body much further (section 2). With the
controller's reach the real controller confirmed two more traps, both fixed in the Blender source:

- **000001021, slots behind the west hedges** (three components at map-local (-0.6, 1.2, -15.7 to -17.6)): a player
  hops from the furrow onto the back hedge (1.1 m), walks along the hedge tops, hops up where they cross onto the west
  bank, and steps off the west hedges' back into the 0.75 m band of bank between them and the containment ring, 1.6 m
  down, with no way back up. `WestHedge_Back_Fill` fills the band to just under the hedge tops. `validate.py
  ring_band` could not see it: the slot is 1.2 m above the map's base.
- **000001006, the walk-out under the out00 bridge**: the ring leaves a gap for the trail's mouth from the bottom of
  the map to the sky, and the bridge crosses it 7 m up; a player in the front of the dell walked out under the bridge,
  outside every region, down the hill below the plinth and hopped into a pocket of the Dangerous Forest's ground
  under the trail (80 nodes, 9.87 m below the deck) with no way out. The engineer's review had listed that pocket
  UNENTERABLE and said the trail's side walls keep the body on the trail; they do on the deck, not under it.
  `Bridge_Abutment`, a stone pier from the dell to just under the planks across the gap, closes it. The scan now
  counts escapable ground outside every region and fails on it.

The two pockets the harness package suspected in 000001000 (map-local (29.0, 0, -40.6) and (62.5, 0, -37.5)) lie
under the fills of round 1 (`P21_P29_Gap_Fill`, `P26b_Notch_Fill`): no node stands at plinth level there, and
`trap_probe` lands on the fills and escapes at once.

Every former trap is in `trap_probe`'s `KNOWN_TRAPS` (54 spots, the three 000001021 slots included), which
`test_playtest_traps.gd` runs in the real game. The probe stands on the old floor when the live graph still has open
ground at the spot's height, else on the first surface over the spot (a fill, a terrace that now reaches the ground):
landing from above alone stood on the terrace over a cavern that would reopen under it, and passed (it passed
000001006's pocket from the bridge deck 10 m above). The 000001006 pocket is not in `KNOWN_TRAPS`: its fix makes it
unreachable, not filled, so the scan guards it. With the world in the suite, `test_stuck_scan.gd` takes about
80-100 s (since issue #33, 114 s when it scans and 17 s when the cache holds the results, on 2026-10-06 beside other
agents' runs) and `test_playtest_traps.gd` about 2 minutes.

### Issue #34: the ring top inside Southperry's quay wall (2026-10-06)

Four of the final run's UNENTERABLE components, 000000060#1-#4 (16 nodes at map-local (69.75-76.97, 4.6, 1.1-1.5)),
stood on the top of the layout ring's wall that `keep_footprint_ring_below_y` keeps up to 5.6 m (4.6 m local) under
the ship. That top lies inside a `Walls` solid at the quay's front (from about 3.5 m local up to 6.5 m, under the
planks), and the face count missed it: the column meets the planks' top (`Ground`, 6.52 m) and one top for the solid
and the `Walls` planks on it (6.50 m), then going up the two planks' undersides (6.27 m, 6.30 m), so two tops balance
two bottoms. The allowlist blamed the double-sided trimesh; switching it back to one-sided gives the same
count. The back-face test of section 1 now takes these 16 surfaces out of the graph, and their four `unenterable`
entries are gone. The full scan before and after differs only in 000000060: 16 nodes, these four components and the
edges and fall-outs of their nodes; every other map's result is unchanged. (The regenerated report also differs from
the one before it in the edge counts of 000000041, 000000060 and 000001012 and in Southperry's reachable count, by up
to 117 edges and 2 nodes: the scan before the change already gave those on the current export.)

### The art pack (#59, 2026-10-13)

With every kit category and the landmark aliases from the pack (#72-#75) the scan gives 35 components and 472 flagged
nodes (before: 34 and 392), still 0 CONFIRMED, 0 new traps and the same 9 reviewed UNENTERABLE components; the per-map
table below is the scan before the pack. Three of the new components are escapable pockets (CLEARED: the real
controller gets out of every sample by one jump):

| Component | Map-local point | What it is |
|---|---|---|
| 000001021#0, #1 | (19.19, 0, 0.5), (41.58, 0, 0.51) | Tomato Field: 60 and 21 nodes of the strip of ground between the front rail fence (#74's pack fence, at y 0.3) and the map's front edge. The pack fence's posts carry flat 0.34 m caps 1.27 m up (the kit's were pointed), so a player who reaches a cap can step off it into the strip; a jump onto the cap gets them out again |
| 000000060#1 | (60.7, 5.6, -25.56) | Southperry: one column beside a #73 pack prop, entered by a creep off the ledge 2.4 m above |

They are left as they are and documented: the swap's spec can scale a pack node only about the model's origin, so
the caps cannot be narrowed in place, and leaving them out or moving the fence changes the art or the map for a
pocket nobody can be stuck in.

### The final scan, per map

`docs/runtime/stuck_report.json` is this run: 491,614 nodes, 3.63 M certain and 2.90 M into edges, 4,881 fall-outs
(walk-offs onto nothing above kill_y: FallRecovery's case), 160 reachable nodes outside every region (the two
UNENTERABLE pockets under the 000001000 / 000001006 trail; none escapable), 74 s with the cache off (regenerated
for issue #34 on 2026-10-06).

| Map | Name | Nodes | Reachable | Flagged | CLEARED | UNENTERABLE | CONFIRMED |
|---|---|---|---|---|---|---|---|
| 000000001 | Mushroom Town - West Entrance | 7,807 | 7,321 | 0 | 0 | 0 | 0 |
| 000000010 | Mushroom Town | 13,321 | 13,003 | 0 | 0 | 0 | 0 |
| 000000020 | Mushroom Town | 13,782 | 12,870 | 0 | 0 | 0 | 0 |
| 000000021 | Mushroom Town Townstreet | 1,515 | 1,340 | 0 | 0 | 0 | 0 |
| 000000030 | East Entrance to Mushroom Town | 14,411 | 13,386 | 19 | 2 | 0 | 0 |
| 000000040 | Snail Hunting Ground I | 29,744 | 28,401 | 3 | 2 | 0 | 0 |
| 000000041 | Snail Hunting Ground II | 45,671 | 24,444 | 0 | 0 | 0 | 0 |
| 000000042 | Snail Hunting Ground III | 45,628 | 25,816 | 26 | 6 | 0 | 0 |
| 000000050 | A Split Road | 24,045 | 23,381 | 3 | 1 | 1 | 0 |
| 000000060 | Southperry | 32,164 | 28,557 | 12 | 1 | 0 | 0 |
| 000000061 | Southperry Armor Store | 1,519 | 1,228 | 42 | 2 | 0 | 0 |
| 000001000 | The Field West of Amherst | 67,265 | 36,271 | 163 | 3 | 3 | 0 |
| 000001001 | In a Small Forest | 13,271 | 11,820 | 13 | 4 | 0 | 0 |
| 000001002 | Dangerous Forest | 12,726 | 12,156 | 0 | 0 | 0 | 0 |
| 000001003 | Mushroom Garden | 10,476 | 9,662 | 17 | 2 | 1 | 0 |
| 000001004 | Snail Garden | 11,467 | 11,188 | 0 | 0 | 0 | 0 |
| 000001005 | Hunting Ground Middle of the Forest I | 14,529 | 14,223 | 7 | 1 | 0 | 0 |
| 000001006 | Hunting Ground Middle of the Forest II | 20,850 | 19,943 | 80 | 0 | 1 | 0 |
| 000001010 | Amherst | 51,804 | 24,295 | 0 | 0 | 0 | 0 |
| 000001011 | Amherst Weapon Store | 1,488 | 1,147 | 0 | 0 | 0 | 0 |
| 000001012 | Amherst Townstreet | 7,665 | 6,383 | 0 | 0 | 0 | 0 |
| 000001013 | Amherst Department Store | 1,451 | 1,035 | 4 | 1 | 0 | 0 |
| 000001014 | Snail Field of Flowers | 14,881 | 12,956 | 0 | 0 | 0 | 0 |
| 000001020 | The Field East of Amherst | 18,283 | 17,460 | 3 | 0 | 3 | 0 |
| 000001021 | Tomato Field | 15,851 | 15,206 | 0 | 0 | 0 | 0 |

**CLEARED (25):** false positives of the graph. In every one the real controller got back to escapable ground: by
a hop onto a ledge about 1.2 m up (above the certain jump's reach, which keeps a 0.2 m margin), by walking or hopping
across to same-level ground the graph did not link (a lip or a gap one column wide in its sampling), or by a drop
the swept drop rejected.

**UNENTERABLE (9), reviewed by hand** (with `--inspect`), kept and listed with their reasons in
`stuck_allowlist.json` `unenterable` (a new one fails the test until it is reviewed):

| Component | Map-local point | What it is |
|---|---|---|
| 000000050#1 | (48.37, 2.2, -28.03) | one column of floor 3.2 m below the terrace around it: the opening above is narrower than the body |
| 000001000#0, 000001006#0 | (65.4, 8.0, -98.37) / (14.14, -3.0, 4.78) | the same ground under the trail 000001000 in05 - 000001006 out00, seen from the zones of both maps (80 nodes, 9.87 m down, on both): Dangerous Forest's ground under the trail, outside every map region. The graph reaches it only by a slide off the deck, which the trail's side walls stop. Before `Bridge_Abutment` the real controller got in by walking out under the bridge (the review's CONFIRMED 000001006#0) |
| 000001000#2, #5 | (9.95, 0, -39.94), (80.63, 0, -48.5) | one column of plinth floor between terraces, 8.4 m and 4.2 m down: openings narrower than the body |
| 000001003#0 | (29.82, 5.2, -17.37) | 1.8 m² of P03's floor under the caps of the mid mushroom stair, against P10's wall: the gaps between the cap rims and the wall are 0.2-0.55 m, narrower than the body |
| 000001020#0-#2 | (39.91, 0, -23.59), (31.66, 5.0, -30.22), (21.03, 5.6, -30.26) | one column each, 5-5.8 m below the bands: openings narrower than the body |

Every UNENTERABLE component's ways in are slides (a fall along a wall that the body's sweep does not clear) and,
for 000000050#1, 000001000#2, 000001003#0 and 000001020#0, long drops; the verification replayed them all (walking,
creeping, hopping) without getting in.
