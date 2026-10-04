# Map 1000005: "Hunting Ground Middle of the Forest I". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/1000005.struct.json`. It uses the same tier ids as this brief.

**Tags used in this brief**
- No tag: a fact taken from data. The source file or URL is given.
- **[inference]**: my reading of the data. The data does not state it.
- **[memory]**: something I remember about the game. No source was checked.
- **[proposal]**: a design suggestion for MisoStory.

**Sources**
- `docs/research/raw/gms_v8/1000005.json`, from `https://maplestory.io/api/GMS/8/map/1000005`. The geometry is identical in `raw/gms_v22/1000005.json`.
- Raw v8 WZ under `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001000005.img`: `/portal/6` (the exit, which the JSON shows as `null`), `/back/<n>`, `/<layer>/obj/<n>` and `/<layer>/info/tS`.
- Sprites were viewed at `.../Data/Map/Obj/acc1.img/...` and `.../Back/grassySoil.img/...` in a temp folder only. All object names are my identification from those sprites.
- Mob names and levels: `https://maplestory.io/api/GMS/8/mob/100100`, `/100101`, `/120100` and `/130101`.
- Reference images, viewed but not copied: `ref_renders/v8_1000005_render.png` and `v8_1000005_minimap.png`.
- Cross-checks:
  - `https://maplestory.io/api/GMS/40/map/1000005`: the exit portal parses there. All 157 v8 floor footholds are present and the mobs are identical. v40 also adds geometry; see §7.
  - Hidden Street 2005, archived at `https://web.archive.org/web/20051210065940/http://www.hidden-street.net:80/maps/miamherst.php`. It calls this map "Hunting Ground in the Middle of the Forest I".

## 0. Map card

| field | value (v8) |
|---|---|
| Street / name | "Rainbow Street" / "Hunting Ground Middle of the Forest I" |
| isTown / returnMap | `false` / `1010000` (Amherst) |
| BGM | `Bgm00/RestNPeace` |
| mapMark / mobRate | `Amherst` / 1 |
| Foothold extent | x -759..1209 (1968 px wide). The walkable surfaces run from y -1405 to 215 (1620 px). Walls go down to y=420. This is the tallest of the four maps. |
| Walkable tiers | 38 in total: 5 ground pieces, 1 door block, 3 log-pile tops and 29 floating platforms. Most are 168-px stones. |
| Climbables | 10: 4 ladders and 6 ropes. |
| Mobs | 59: Snail 21, Blue Snail 16, Shroom 12 and Red Snail 10. |
| NPCs | none. |
| Exits | 1: `out00` at (132, 155) goes to 1000000 `in04`. There are no edge exits. |

## 1. Structure

### 1.1 Tiers
The ids are sorted from top to bottom, so T0 is the highest. All tiers are flat except the three log-pile tops, which tilt by about 3 px. In the table, "rope" and "ladder" give the climbable's x position and "hop" means a 60-px jump.

| id | kind | x1..x2 | y | width | links / notes |
|---|---|---|---|---|---|
| T0 | floating | 681..1029 | -1405 | 348 | Summit. Rope x904 down to T4. Hop down west to T1. Clover and orange flowers. |
| T1 | floating | 501..669 | -1345 | 168 | Descending stair, summit → T3. |
| T2 | floating | 411..579 | -1285 | 168 | Descending stair. |
| T3 | floating | -39..399 | -1225 | 438 | Big bush, strawberry bushes and purple flowers. Hop down west to T5. |
| T4 | floating | 861..1029 | -1225 | 168 | Ladder x980 (to T6) and rope x904 (up to T0). |
| T5 | floating | -489..-51 | -1165 | 438 | Rope x-367 down to T7. Young green tree and a bush. |
| T6 | floating | 591..1119 | -1045 | 528 | Ladders x651 (down to T8) and x980 (up to T4). Bushes and clover. |
| T7 | floating | -489..-321 | -925 | 168 | Rope stop: x-367 (from T5) and x-438 (down to T10). |
| T8 | floating | 231..759 | -805 | 528 | Ladder x651 up to T6 and rope x716 down to T16. Top of the jump tower (hop up from T9). Bushes and clover. |
| T9 | floating | 51..219 | -745 | 168 | Tower stone. |
| T10 | floating | -579..-141 | -685 | 438 | West shelf of the tower. Rope x-438 up to T7. Teal tree, bush and shrubs. |
| T11 | floating | -39..129 | -685 | 168 | Tower stone. |
| T12 | floating | -129..39 | -625 | 168 | Tower stone. |
| T13 | floating | -129..39 | -565 | 168 | Tower stone. It sits directly under T12 at the same x. |
| T14 | **ledge** | 821..938 | -536/-533 | 117 | **Object foothold:** the top of a stacked log pile (obj `grassySoil/artificiality/6` at x886) standing on T16, about 31 px tall. |
| T15 | floating | -39..129 | -505 | 168 | Tower stone. |
| T16 | floating | 681..1029 | -505 | 348 | Rope x716 up to T8. Log pile, orange flowers and a bush. |
| T17 | **ledge** | 449..566 | -474/-471 | 117 | **Object foothold:** a log pile (obj at x514) standing on T19, about 29 px tall. |
| T18 | floating | -129..39 | -445 | 168 | Tower stone. |
| T19 | floating | 231..669 | -445 | 438 | Ladder x315 (down to T24). Hop up to T16. Log pile, purple flowers and a bush. |
| T20 | floating | -39..129 | -385 | 168 | Tower stone. |
| T21 | floating | -129..39 | -325 | 168 | Tower stone. |
| T22 | floating | -669..-231 | -265 | 438 | Rope x-296 down to T28. Hop down to T25. Young autumn tree and a bush. |
| T23 | floating | -129..39 | -265 | 168 | Tower stone. |
| T24 | floating | 231..399 | -265 | 168 | Ladder x315 up to T19. |
| T25 | floating | -219..-51 | -205 | 168 | Tower stone. Hop up to T22 or T23. |
| T26 | floating | 51..219 | -205 | 168 | Tower stone. Hop up to T23 or T24. |
| T27 | floating | -39..129 | -145 | 168 | Tower base. Rope x78 down to the door-block roof. |
| T28 | floating | -399..-231 | -25 | 168 | West stack. Rope x-296 up to T22. |
| T29 | **ledge** | 6..264 | 5 | 258 | **Door block.** A layer-0 earth block standing on T34; its walls run from y5 down to y150, so it is 150 px tall. The exit door is on its front face. Ladder x52 (down to T34) and rope x78 (up to T27). |
| T30 | floating | -399..-231 | 35 | 168 | West stack. |
| T31 | **ledge** | 949..1066 | 67/70 | 117 | **Object foothold:** a log pile (obj at x1014) standing on T33, about 27 px tall. |
| T32 | floating | -309..-141 | 95 | 168 | West stack. Hop up from T34. |
| T33 | ground | 771..1209 | 95 | 438 | East high ground, a dead-end corner. Log pile, bush and mixed tree. |
| T34 | ground | -219..309 | 155 | 528 | Central mound. Spawn points, the door block and the exit. |
| T35 | ground | 681..771 | 155 | 90 | Riser step. |
| T36 | ground | -759..-219 | 215 | 540 | West low ground. Young green tree and a bush. |
| T37 | ground | 309..681 | 215 | 372 | Low ground east of the mound. **Rainbow fountain.** |

### 1.2 Ladders and ropes
`from` is the tier at the bottom end and `to` is the tier at the top end.

| x | y1 → y2 | length | type | from → to |
|---|---|---|---|---|
| 52 | 7 → 149 | 142 | ladder | T34 → T29 (door-block roof) |
| 78 | -143 → -8 | 135 | rope | T29 → T27 (tower base) |
| -296 | -263 → -67 | 196 | rope | T28 → T22 |
| 315 | -443 → -302 | 141 | ladder | T24 → T19 |
| 716 | -803 → -547 | 256 | rope | T16 → T8 |
| -438 | -923 → -728 | 195 | rope | T10 → T7 |
| -367 | -1163 → -969 | 194 | rope | T7 → T5 |
| 651 | -1043 → -855 | 188 | ladder | T8 → T6 |
| 980 | -1223 → -1080 | 143 | ladder | T6 → T4 |
| 904 | -1403 → -1225 | 178 | rope | T4 → T0 (summit) |

The sprites are `connect/ladder/0` and `connect/rope/0` (hemp rope with a wooden peg).

### 1.3 Layering, gaps and walls
- **Ground band (y95..215)** undulates with 60-px risers:
  - T36 y215 → riser up → central mound T34 y155 → riser down → T37 y215 → riser up → T35 y155 → riser up → T33 y95.
  - The **door block T29**, 150 px tall, stands on the mound.
  - The perimeter walls at x=-759 and x=1209 run to y=420.
- **The jump tower** is the defining structure.
  - A column of 168-px stones rises in 60-px steps from T27 (y-145) to T8 (y-805): 11 hops, 660 px of climbing with no rope.
  - The stones alternate between x[-129,39] and x[-39,129], a 90-px zig-zag.
  - At the bottom the column widens to the side stones T25 and T26. At y-685 it has the side shelf T10.
  - T12 and T13 are stacked at the same x.
  - [memory] The tower relies on MapleStory's jump-through platforms: you jump up through the stone above from underneath.
- **The west stack** is three 168-px stones (T32 → T30 → T28) above the west ground, then rope x-296 to T22.
- **The east branch** is T26 → T24 → ladder → T19 → T16 → rope x716 → T8. Its intermediate steps are log piles.
- **The upper ring:**
  - T8 → ladder → T6 → ladder → T4 → rope → summit T0.
  - Then a descending stair T1 → T2 → T3 → T5.
  - Then ropes down the west side: T5 → T7 → T10.
- **Vertical span:** the summit is 1620 px above the lowest ground. That is roughly 4 bands: ground, lower tower, upper tower plus mid shelves, and the upper ring.

### 1.4 Routes [inference]
- **Arrival:** 6 spawn points, at (-214,59), (-326,-41) and four over the mound (x-122..213, y101-114). The mound and the door are the hub.
- **Main loop (counter-clockwise when seen in 2D):**
  1. Ladder x52 to the roof of the door block.
  2. Rope x78 to the tower base.
  3. Climb the tower to T8.
  4. Ladders up to T6 and T4, then the rope to summit T0.
  5. Step down the stair west to T3 and T5.
  6. Ropes down to T7 and T10.
  7. Drop into the tower at T12, or keep dropping to the ground.
- **Side branches:**
  - The west stack leads to T22, which has a Shroom spawn.
  - The east branch with its log piles reaches T16 and T19, then rejoins at T8.
  - The east corner T33 is reached on foot along the ground.

## 2. Portals
- The parsed v8 JSON has 7 entries: 6 `sp` (listed above) and 1 `null`.
- Raw v8 WZ `.../001000005.img/portal/6` gives **`out00`, type 2, at (132, 155), going to 1000000 `in04`**. It stands on the mound T34, in front of the door object `door/grassySoil/door/0` at (129, 106).
- v40 shows the same portal, and the Hidden Street 2005 thumbnail shows the portal glow on the door block.
- On the other side, `in04` is in The Field West of Amherst at (389, -688), on an upper level of that map, and links back to `1000005:out00`. Source: raw v8 WZ `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001000000.img/portal/7`, also recorded in `1000000.struct.json`.
- **No edge exits.** The perimeter walls run to the map bottom. This is a dead-end pocket off The Field West of Amherst; Hidden Street lists only that connection.

## 3. Spawns
- **Snail** (lv 1): 21.
- **Blue Snail** (lv 2): 16.
- **Shroom** (120100, lv 2): 12.
- **Red Snail** (lv 4): 10.
- That matches Hidden Street 2005: "Snail, Blue Snail, Red Snail, Shroom".

| tier | Snail | Blue | Shroom | Red | note |
|---|---|---|---|---|---|
| T36 west ground | – | 1 | 3 | 1 | |
| T34 mound | 1 | – | – | – | |
| T29 door roof | 2 | – | – | – | |
| T37 | 1 | 1 | 2 | – | |
| T33 east corner | 1 | 1 | 2 | – | |
| T22 | – | 2 | 3 | – | |
| T19 | – | 3 | 1 | – | |
| T16 | – | 2 | – | 2 | |
| T10 | 3 | 1 | 1 | – | |
| T8 | 3 | 1 | – | 1 | |
| T6 | 4 | 1 | – | 1 | |
| T5 | 2 | 1 | – | 2 | |
| T3 | 2 | 1 | – | 2 | |
| T0 summit | 2 | 1 | – | 1 | |

- Shrooms live only on the low and mid band, at y ≥ -685, i.e. no higher than the T10 shelf. Red Snails grow more common higher up [inference from the table].
- The jump-tower stones have no spawns.

## 4. Visual reference

### 4.1 Terrain
- The tile set is `grassySoil`, the same grass over olive-brown cobbled dirt with grey boulders as the other three maps (v8 render).
- Backgrounds use set `grassySoil` (`back/0..4`): blue sky, drifting cumulus clouds, a domed hill, one big leafy tree and a golden meadow strip.
- The Hidden Street 2005 thumbnail shows the big tree (back no.3) as a dark tree shape on the east side.

### 4.2 Objects (raw WZ; x,y = object origin)
- **Exit door** at (129, 106) on the door block. Five small round shrubs (`grassySoil/nature/1`, layer 1) sit around its base, at x40-227.
- **Rainbow fountain** (`grassySoil/artificiality/9`) at (557, 167) on T37: a ring of stones, an orange mushroom-shaped spout and a rainbow arc. It suits "Rainbow Street" [inference].
- **Log piles with tiny mushrooms and a ladybug** (`artificiality/6` + `/7`) at x514 (on T19), x886 (on T16) and x1014 (on T33). Their tops are the object footholds T17, T14 and T31.
- **Trees (`midForest`):**
  - Young green trees at x-586 (T36) and x-365 (T5).
  - Young autumn trees at x-34 (on the mound, beside the door block) and x-560 (T22).
  - A teal tree at x-494 (T10).
  - A mixed green, teal and orange tree at x1102 (T33).
- **Bushes:** big round bushes on T36, T34, T37, T33, T10, T8 (×2), T6 (×2), T5 and T3. Low dark bushes on T37, T22, T19 and T16.
- **Flowers:**
  - Clover (white and pink) on T0, T6 and T8.
  - Orange flowers on T0 and T16.
  - Purple flowers on T3 and T19.
  - Strawberry bushes on T3.
  - Butterflies: orange on T0, yellow on T16, pink on T3 and T19.

### 4.3 Missing from the render
- The v8 render shows tiles only: no objects, door, ropes, ladders or background.
- In the minimap the log piles look like crates. The WZ sprites show they are stacked logs.

## 5. What makes this map recognizable
- **The zig-zag jump tower:** a long column of tiny grass stones climbed purely by jumping. It is the map's signature.
- The **door in a block on a central mound**, with a short ladder-and-rope climb from it straight into the tower.
- A **summit loop:** ladders up the east side, a stair of stones stepping down west, then ropes down the west side.
- Shrooms on the lower west shelves, log piles and a rainbow fountain on the forest floor.
- [memory] Nothing specific beyond that.

## 6. 3D translation [proposal]

**Concept: a forest clearing around one giant tree, where the jump tower spirals up the trunk.**
- The "Middle of the Forest" name and the big background tree (back no.3) support using a giant tree trunk as the central pillar.
- MapleStory "up" becomes 3D up plus around and back.

**Tier mapping**
- **Ground → the forest floor**, front of the scene.
  - The mound T34 becomes a raised knoll in the centre-front.
  - The door block T29 becomes a grassy hummock with the door facing the camera. The ladder x52 goes up its side.
  - T36 becomes the west hollow and T37 the east hollow. The rainbow fountain sits in T37.
  - T35 and T33 become a two-step bank up to an east corner nook with a log pile and a tree.
  - The 60-px risers become low grassy banks with 1-2 step stairs.
- **Jump tower → a spiral of stepping stones or shelf-fungus ledges** wrapping the giant trunk. The trunk stands just behind the knoll.
  - Keep the count: 11 hops of 60 px each from the base T27 to the top T8.
  - Each step rotates around the trunk instead of zig-zagging in a plane, which gives the tower real depth.
  - The rope x78 from the door-block roof to the tower base becomes a short root ladder.
- **West stack + T22 + T10 + T7 + T5 → west-side branches and ledges** on the trunk's west flank, linked by hanging ropes.
- **East branch (T24, T19, T16 + log piles) → a run of three branch platforms** on the east flank.
  - The log piles stay as step-up props on those platforms.
  - The ladder x315 and the rope x716 become a ladder and a rope on the branch faces.
- **Upper ring (T8, T6, T4, T0, then T1, T2, T3, T5) → canopy platforms** around the top of the trunk.
  - T8 and T6 are broad canopy shelves, joined by a ladder.
  - T0 is the crown lookout, the summit.
  - T1 and T2 are a stepping stair down to the T3 and T5 canopy shelves on the west.
- **Ropes → hanging ropes from branch undersides.** Ladders → wooden ladders against the trunk.

**Route through 3D space**
- The loop circles the trunk:
  1. Start at the door on the knoll, front-centre.
  2. Climb the spiral counter-clockwise to the east canopy.
  3. Go up the ladders to the crown.
  4. Come down the west stair and the ropes.
- The west-to-east 2D order is kept as the left-to-right layout. The trunk adds depth: stones on the back side of the spiral are partly hidden, so keep the camera-facing half of each turn readable.

**Landmarks**
- The door hummock sits front-centre.
- The rainbow fountain sits front-right, in the east hollow.
- The giant trunk is the backdrop to the whole scene.

**Spawn areas**
- Forest floor and low west shelves: Shrooms plus mixed snails, 21 spawns on T36, T34, T29, T37, T33 and T22.
- East branch: 8 spawns on T16 and T19.
- Canopy shelves: snails and Red Snails, 30 spawns on T0, T3, T5, T6, T8 and T10.
- Tower stones: no spawns. Keep them clear so players can climb.

**Top-down sketch.** Screen-left is the map's west end. Up is back.
```
 back      (T5 shelf)   (T3)  <-stair- (T2)(T1) [T0 crown]
             |rope x-367        canopy ring         |rope x904
           (T7)              ___________________  (T4)
             |rope x-438    /  GIANT TRUNK       \  |ladder x980
           [T10 shelf]--   | spiral of stones T27-> T9 ->[T8]==ladder x651==[T6]
           [T22 branch]    |  winds around trunk |       |rope x716
             |rope x-296    \___________________/   [T16]+logs  [T19]+logs
           (T28)(T30)(T32)       |rope x78              |ladder x315 (T24)
 front    [T36 west hollow] [T34 knoll + DOOR HUMMOCK T29] [T37 hollow + RAINBOW FOUNTAIN] [T35][T33 nook+logs]
           W ------------------------------------------------------------------------------> E
```

**Side elevation.** y in MapleStory px with up = higher; this is not to scale.
```
 y-1405                                         T0 ======
 y-1345                                     T1 ==   |rope
 y-1285                                  T2 ==      |
 y-1225                    T3 ========             T4 ==
 y-1165          T5 ========                         |ladder
 y-1045           |rope                      T6 ===========
 y -925          T7 ==                          |ladder
 y -805           |rope          T8 ===========  
 y -745                       T9 ==     |rope x716
 y -685          T10 ======  T11 ==       |
 y -625..-325                 T12..T21 zig-zag stones (60-px hops)
 y -505                                    T16 ======(log)
 y -445                               T19 ========(log)
 y -265      T22 =======   T23 ==   T24 ==  ^ladder
 y -205                  T25 == T26 ==
 y -145                     T27 ==
 y  -25..95     T28/T30/T32 stack  |rope x78
 y     5                     [T29 door block]
 y 95..215  T36 ======= /T34 mound======\ T37 (fountain) /T35/ T33 ======(log)
```

## 7. Version notes
- v8 and v22 are identical.
- **v40 adds 3 floor footholds and 5 ropes.** The footholds form a new 168-px stone at y-205, x771-939, above the east corner (v40 group 21; v8 has no group 21). The ropes are at x860, x852, x120, x170 and x526. These are later-patch additions and are excluded here.
- v55 and v62 are re-layouts: only 59 of 157 floors are shared, with 42 and 25 mobs.

## 8. Open questions
- Should the jump tower stay a pure jump challenge in 3D (11 hops), or get a fallback rope? The v40 additions suggest Nexon later added ropes to make the map easier.
- Is the giant-trunk framing acceptable, or should the tower stay a free-standing column of stones? The 2D data has no trunk; the trunk is my proposal.
