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
| reviewed, intended dead ends | `game/data/misostory/stuck_allowlist.json` (empty) |
| the guard in the suite | `game/tests/unit/test_stuck_scan.gd` |
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
- it is above the map's `kill_y`.

### 2. Edges

Every number comes from `MovementModel.from_db()` (canonical MeowDB values through `WorldScale`, plus
`data/misostory/movement.json`). Edges come in two kinds, because the two searches need opposite errors:

| Kind | Used by | Edges |
|---|---|---|
| **certain** | both searches | **walk** to the first surface of a neighbour column within `step_up` above and `snap_down` below the feet (the controller's feet rule); **drop** off an edge onto the first surface below, with the capsule swept across and down; **ladder** for every node in a ladder's, rope's or vine's grab band along its whole length (Up from the line, a jump with Up held from below the band, Down from the top), to its top exit and its foot (descend-only ropes only down); **jump** (refined, see below) |
| **into** | the forward search only | **long drop** (momentum carries a walk-off up to 5 columns), **slide** (a walk-off whose fall brushes a wall: the body is pushed onto the nodes beside the landing), **hop** (a jump up to `jump_apex + step_up` or across a gap, swept as an L) |

An escape the graph claims must be real, since nothing re-checks it, so certain edges are strict; into edges may be
generous, because the verification stage clears what the controller cannot get into.

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

A CONFIRMED component that the allowlist does not list fails `test_stuck_scan.gd`.

## Limits

- The scan follows the player's mask and the containment as built, in each link's configured mode (edge mode: every
  trail walkable). A pocket reachable only in warp mode is not scanned separately.
- One ray per column: a surface narrower than a column can be missed or misjudged; the verification stage absorbs
  this.
- The buried-surface test needs closed, outward-facing solids. On a map whose trimesh is double-sided
  (`collision.double_sided_trimesh`: Southperry) rays also see back faces and the count cannot tell a buried surface;
  there the capsule test and the verification stage carry the check.
- Into edges model the ways in that matter for traps (walking off, falling, hopping); a way in that needs a precise
  jump sequence over several ledges may be missed. UNENTERABLE components are listed in the report, not failed.
- Knockback, crouch drop-through (the controller has none) and mid-air rope catches out of a fall are not modelled
  as edges.
- The escape search is short range (3 s tries): a component whose only way out is far away and needs several
  deliberate moves may be CONFIRMED where a patient player escapes. Every CONFIRMED component is inspected by hand
  before it is fixed or allowlisted.

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
# the guard in the suite (all 25 maps, verified)
ISOLATE=stuck INCLUDE_WORLD=1 bash scripts/test.sh stuck_scan
# a spot in the real game, with real input (escape = escapable ground by the live scan, a portal or a gate)
TRAP_MAP=000001010 TRAP_LOCAL="76.70,-2.50,-37.57" bash scripts/playtest.sh trap_probe
# the Blender-side guard
"$B" -b MapleIsland.blend --python scripts/validate.py      # check ring_band
```

The tool exits 1 when a CONFIRMED component is not allowlisted.

## Results

### The runs of Iteration Three (2026-10-05)

Every run covers all 25 maps with verification (the scanner itself changed between some rounds; the last two rows
are the final scanner). Times are wall times on the dev machine, the island build (about 1 s) not included.

| Run | World | Flagged nodes | Components | CONFIRMED | CLEARED | UNENTERABLE | Time |
|---|---|---|---|---|---|---|---|
| first full scan | the base export | 59,893 | 93 | 42 in 13 maps | 25 | 26 | 325 s |
| after fix round 1 | world.py corner rule, first fills | 5,979 | 76 | 32 in 11 maps | 25 | 19 | 254 s |
| after fix round 2 | more fills, ropes, a vine, a stepping stone | 1,219 | 51 | 5 in 5 maps | 28 | 18 | 77 s |
| after fix round 3 | the last fills | 935 | 42 | 0 | 24 | 18 | 61 s |
| **final** | rooms and shafts closed (below) | 419 | 38 | **0** | 24 | 14 | 54 s |

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
The two pockets the harness package suspected in 000001000 (map-local (29.0, 0, -40.6) and (62.5, 0, -37.5)) lie
under the fills of round 1 (`P21_P29_Gap_Fill`, `P26b_Notch_Fill`): no node stands at plinth level there, and
`trap_probe` lands on the fills and escapes at once.

Every former trap is in `trap_probe`'s `KNOWN_TRAPS` (51 spots), which `test_playtest_traps.gd` runs in the real game.
With the world in the suite, `test_stuck_scan.gd` takes 55-85 s and `test_playtest_traps.gd` about 2 minutes (the
probe itself 111 s of wall time); the full suite with the world ran 1,193 tests in 6 minutes.

### The final scan, per map

`docs/runtime/stuck_report.json` is this run: 491,625 nodes, 3.63 M certain and 1.37 M into edges, 4,925 fall-outs
(walk-offs onto nothing above kill_y: FallRecovery's case), 54 s.

| Map | Name | Nodes | Reachable | Flagged | CLEARED | UNENTERABLE | CONFIRMED |
|---|---|---|---|---|---|---|---|
| 000000001 | Mushroom Town - West Entrance | 7,807 | 7,321 | 0 | 0 | 0 | 0 |
| 000000010 | Mushroom Town | 13,321 | 13,003 | 0 | 0 | 0 | 0 |
| 000000020 | Mushroom Town | 13,782 | 12,870 | 0 | 0 | 0 | 0 |
| 000000021 | Mushroom Town Townstreet | 1,515 | 1,327 | 0 | 0 | 0 | 0 |
| 000000030 | East Entrance to Mushroom Town | 14,411 | 13,378 | 19 | 2 | 0 | 0 |
| 000000040 | Snail Hunting Ground I | 29,744 | 28,379 | 3 | 2 | 0 | 0 |
| 000000041 | Snail Hunting Ground II | 45,671 | 24,420 | 0 | 0 | 0 | 0 |
| 000000042 | Snail Hunting Ground III | 45,628 | 25,792 | 26 | 6 | 0 | 0 |
| 000000050 | A Split Road | 24,045 | 23,360 | 3 | 1 | 1 | 0 |
| 000000060 | Southperry | 32,180 | 27,995 | 28 | 1 | 4 | 0 |
| 000000061 | Southperry Armor Store | 1,519 | 1,224 | 42 | 2 | 0 | 0 |
| 000001000 | The Field West of Amherst | 67,270 | 36,276 | 174 | 2 | 4 | 0 |
| 000001001 | In a Small Forest | 13,271 | 11,795 | 13 | 4 | 0 | 0 |
| 000001002 | Dangerous Forest | 12,726 | 12,082 | 0 | 0 | 0 | 0 |
| 000001003 | Mushroom Garden | 10,476 | 9,660 | 17 | 2 | 1 | 0 |
| 000001004 | Snail Garden | 11,467 | 11,186 | 0 | 0 | 0 | 0 |
| 000001005 | Hunting Ground Middle of the Forest I | 14,529 | 14,218 | 7 | 1 | 0 | 0 |
| 000001006 | Hunting Ground Middle of the Forest II | 20,865 | 19,962 | 80 | 0 | 1 | 0 |
| 000001010 | Amherst | 51,804 | 23,923 | 0 | 0 | 0 | 0 |
| 000001011 | Amherst Weapon Store | 1,488 | 1,147 | 0 | 0 | 0 | 0 |
| 000001012 | Amherst Townstreet | 7,665 | 6,383 | 0 | 0 | 0 | 0 |
| 000001013 | Amherst Department Store | 1,451 | 1,035 | 4 | 1 | 0 | 0 |
| 000001014 | Snail Field of Flowers | 14,881 | 12,953 | 0 | 0 | 0 | 0 |
| 000001020 | The Field East of Amherst | 18,283 | 17,460 | 3 | 0 | 3 | 0 |
| 000001021 | Tomato Field | 15,826 | 14,903 | 0 | 0 | 0 | 0 |

**CLEARED (24):** false positives of the graph. In every one the real controller got back to escapable ground: by
a hop onto a ledge about 1.2 m up (above the certain jump's reach, which keeps a 0.2 m margin), by walking or hopping
across to same-level ground the graph did not link (a lip or a gap one column wide in its sampling), or by a drop
the swept drop rejected.

**UNENTERABLE (14), reviewed by hand** (with `--inspect`) and kept:

| Component | Map-local point | What it is |
|---|---|---|
| 000000050#1 | (48.37, 2.2, -28.03) | one column of floor 3.2 m below the terrace around it: the opening above is narrower than the body |
| 000000060#1-#4 | (69.75-76.64, 4.6, 1.3-1.5) | the top of Southperry's containment ring, 1.9 m under the front terrain: inside the solid terrain, which the face-count test cannot see on Southperry's double-sided trimesh (Limits) |
| 000001000#0, 000001006#0 | (65.4, 8.0, -98.37) / (14.14, -3.0, 4.78) | one place seen from both ends of the trail 000001000 in05 - 000001006 out00: Dangerous Forest's ground 9.9 m under the trail, outside every map region at that height; the trail's side walls keep the body on the trail (in a release build RegionMonitor would recover a body there) |
| 000001000#2 | (65.88, 10.97, -101.81) | the same under that trail, on 000001006's ground |
| 000001000#3, #5 | (9.95, 0, -39.94), (80.63, 0, -48.5) | one column of plinth floor between terraces, 8.4 m and 4.2 m down: openings narrower than the body |
| 000001003#0 | (29.82, 5.2, -17.37) | 1.8 m² of P03's floor under the caps of the mid mushroom stair, against P10's wall: the gaps between the cap rims and the wall are 0.2-0.55 m, narrower than the body |
| 000001020#0-#2 | (39.91, 0, -23.59), (31.66, 5.0, -30.22), (21.03, 5.6, -30.26) | one column each, 5-5.8 m below the bands: openings narrower than the body |

Every UNENTERABLE component's ways in are slides (a fall along a wall that the body's sweep does not clear) and, for
000000050#1, 000001000#3 and 000001020#0, long drops; the verification replayed them all (walking, creeping, hopping)
without getting in.
