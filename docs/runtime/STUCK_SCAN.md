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

1. **Getting in.** Up to 8 ways in (walks and drops first, then slides, longer drops and hops, each by the smallest
   height change) are replayed from the escapable node: walking at full speed, creeping at 30 %, and hopping.
2. **Getting out.** From up to 3 members (the one nearest the centre, then the farthest ones) up to 120 scripted tries:
   toward the nearest escapable nodes (walking, hopping with jump held, and a run-up), then in 16 directions
   (walking and hopping). Up is held, re-pressed every 12 ticks, so ladders and ropes are grabbed and climbed. A try
   ending on a new flagged spot more than 1 m away becomes another start (up to 3). A try succeeds when the
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
# the guard in the suite (all 25 maps, verified)
ISOLATE=stuck INCLUDE_WORLD=1 bash scripts/test.sh stuck_scan
# a spot in the real game, with real input (escape = escapable ground by the live scan, a portal or a gate)
TRAP_MAP=000001010 TRAP_LOCAL="76.70,-2.50,-37.57" bash scripts/playtest.sh trap_probe
# the Blender-side guard
"$B" -b MapleIsland.blend --python scripts/validate.py      # check ring_band
```

The tool exits 1 when a CONFIRMED component is not allowlisted.

## Results

(Filled in below with the runs of this iteration.)
