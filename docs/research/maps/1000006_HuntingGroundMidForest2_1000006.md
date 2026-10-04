# Map 1000006: "Hunting Ground Middle of the Forest II". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/1000006.struct.json`. It uses the same tier ids as this brief. The ground chain T23 is split into T23a-T23g at its slope breaks; all seven pieces carry `"chain":"T23"`.

**Tags used in this brief**
- No tag: a fact taken from data. The source file or URL is given.
- **[inference]**: my reading of the data. The data does not state it.
- **[memory]**: something I remember about the game. No source was checked.
- **[proposal]**: a design suggestion for MisoStory.

**Sources**
- `docs/research/raw/gms_v8/1000006.json`, from `https://maplestory.io/api/GMS/8/map/1000006`. Every portal parses in v8. The geometry is identical in `raw/gms_v22/1000006.json` and in `https://maplestory.io/api/GMS/40/map/1000006`.
- Raw v8 WZ under `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001000006.img`: `/portal/7` (it confirms `out00`), `/back/<n>`, `/<layer>/obj/<n>` and `/<layer>/info/tS`.
- Sprites were viewed at `.../Data/Map/Obj/acc1.img/midForest/...`, `.../darkWood/...` and `.../Back/grassySoil.img/...` in a temp folder only. All object names are my identification from those sprites.
- Mob names and levels: `https://maplestory.io/api/GMS/8/mob/100100`, `/100101`, `/120100`, `/130101` and `/1210102`.
- Reference images, viewed but not copied: `ref_renders/v8_1000006_render.png` and `v8_1000006_minimap.png`. This render includes the objects (trees, fences, flowers, door, ropes).
- Hidden Street 2005, archived at `https://web.archive.org/web/20051210065940/http://www.hidden-street.net:80/maps/miamherst.php`. It calls this map "Hunting Ground in the Middle of the Forest II".

## 0. Map card

| field | value (v8) |
|---|---|
| Street / name | "Rainbow Street" / "Hunting Ground Middle of the Forest II" |
| isTown / returnMap | `false` / `1010000` (Amherst) |
| BGM | `Bgm00/RestNPeace` |
| mapMark / mobRate | `Amherst` / 1 |
| Foothold extent | x -1119..1029 (2148 px wide). The walkable surfaces run from y -2125 to -745 (1380 px). Walls go down to y=-540. |
| Walkable tiers | 30 in total: 1 continuous valley ground (7 pieces, 3 of them slopes), 1 door block and 22 floating platforms. |
| Climbables | 10: 1 rope ladder and 9 ropes. |
| Mobs | 51: Snail 13, Blue Snail 17, Shroom 9, Red Snail 6 and **Orange Mushroom 6**. |
| NPCs | none. |
| Exits | 1: `out00` at (133, -1346), on the floating centre island, goes to 1000000 `in05`. There are no edge exits. |

## 1. Structure

### 1.1 Tiers
The ids are sorted from top to bottom, so T0 is the highest. In the table, "rope" and "ladder" give the climbable's x position and "hop" means a 60-px jump.

| id | kind | x1..x2 | y (L/R) | width | links / notes |
|---|---|---|---|---|---|
| T0 | floating | -489..-51 | -2125 | 438 | Summit. Rope x-407 down to T5. Hop down east to T1. Daffodils. |
| T1 | floating | -39..129 | -2065 | 168 | Rope ladder x29 down to T4. |
| T2 | floating | 321..489 | -1945 | 168 | Hop up from T4. 12-px gap to T3. |
| T3 | floating | 501..939 | -1945 | 438 | Rope x627 down to T7. Daffodils. |
| T4 | floating | -129..309 | -1885 | 438 | Rope ladder x29 up to T1. Hops to T2 and T6. Giant umbrella-leaf plant and olive bushes. |
| T5 | floating | -759..-321 | -1825 | 438 | Ropes x-407 (up to T0) and x-696 (down to T9). Lily-of-the-valley. |
| T6 | floating | -309..-141 | -1825 | 168 | Rope x-200 down to T8. 12-px gap to T5. |
| T7 | floating | 591..759 | -1705 | 168 | Rope stop: x627 (up to T3) and x714 (down to T14). |
| T8 | floating | -309..-141 | -1585 | 168 | Rope x-200 up to T6. It sits directly over T11. |
| T9 | floating | -1029..-591 | -1525 | 438 | Rope x-696 up to T5. Lily-of-the-valley. |
| T10 | floating | -579..-411 | -1525 | 168 | Joiner between T9 and T13. |
| T11 | floating | -309..-141 | -1525 | 168 | Stair stone. |
| T12 | **ledge** | 6..264 | -1495 | 258 | **Door block.** A layer-0 earth block on island T17; its walls run from y-1495 down to y-1350, so it is 150 px tall. The exit door is on its front face. It has no ladder: the only way onto its top is a 390-px drop from T4. |
| T13 | floating | -399..-231 | -1465 | 168 | Stair stone. |
| T14 | floating | 591..939 | -1465 | 348 | Rope x714 up to T7. Lily-of-the-valley. |
| T15 | floating | -309..-141 | -1405 | 168 | Rope x-272 down to T21. Hop up from T17. |
| T16 | floating | 411..579 | -1405 | 168 | Hop up from T18. |
| T17 | floating | -129..309 | -1345 | 438 | **Centre island, arrival hub.** 4 spawn points and the exit. Door block, autumn twin tree and stake fence. Thick rounded underside, with walls to y-1260. |
| T18 | floating | 321..489 | -1345 | 168 | Same height as T17 with a 12-px gap. |
| T19 | floating | 411..579 | -1285 | 168 | Step down from T18. |
| T20 | floating | 591..759 | -1285 | 168 | Rope x643 down to the east plateau T23g. |
| T21 | floating | -669..-231 | -1165 | 438 | Ropes x-272 (up to T15) and x-597 (down to T23a). Lily-of-the-valley. |
| T22 | floating | -219..-51 | -1105 | 168 | Rope x-167 down to T23d. |
| T23a | ground | -1119..-540 | -865 | 579 | West plateau. 2 autumn twin trees and stake fences. |
| T23b | slope | -540..-450 | -865 → -805 | 90 | Slopes down 60. |
| T23c | ground | -450..-180 | -805 | 270 | Middle shelf. Lily-of-the-valley. |
| T23d | slope | -180..-90 | -805 → -745 | 90 | Slopes down 60. |
| T23e | ground | -90..180 | -745 | 270 | Valley floor, the lowest point. Yellow twin tree and stake fences. |
| T23f | slope | 180..540 | -745 → -985 | 360 | **Long slope up**: 240 px of rise over 360 px. |
| T23g | ground | 540..1029 | -985 | 489 | East high plateau. Yellow twin tree and stake fences. |

### 1.2 Ladders and ropes
`from` is the tier at the bottom end and `to` is the tier at the top end.

| x | y1 → y2 | length | type | from → to |
|---|---|---|---|---|
| -597 | -1163 → -904 | 259 | rope | T23a → T21 |
| -167 | -1103 → -846 | 257 | rope | T23d (slope, y≈-796) → T22 |
| 643 | -1283 → -1026 | 257 | rope | T23g → T20 |
| -272 | -1403 → -1203 | 200 | rope | T21 → T15 |
| 714 | -1703 → -1504 | 199 | rope | T14 → T7 |
| 627 | -1943 → -1743 | 200 | rope | T7 → T3 |
| -200 | -1823 → -1624 | 199 | rope | T8 → T6 |
| -696 | -1823 → -1564 | 259 | rope | T9 → T5 |
| -407 | -2123 → -1895 | 228 | rope | T5 → T0 |
| 29 | -2063 → -1917 | 146 | **rope ladder** | T4 → T1 |

The sprites are `connect/rope/0` (hemp rope with a wooden peg top, visible in the render) and `connect/ladder/0`, which the render shows as a rope ladder with wooden rungs.

### 1.3 Layering, gaps and walls
- **Ground** is one continuous foothold chain shaped like a valley.
  - It runs from the west plateau (y-865) down a 60-px slope to the middle shelf (y-805), down another 60-px slope to the valley floor (y-745), then up a long 240-px slope to the east plateau (y-985).
  - It has no risers. It is all smooth slopes.
  - The side walls at x=-1119 and x=1029 drop to y=-540.
- **The centre island** (T17 + T18, y-1345) floats 600 px above the valley floor. It carries the door block T12, 150 px tall.
- **Low-mid band (y-1105..-1285):**
  - On the west, T21 and T22 hang above the west plateau and the middle shelf.
  - On the east, T19 and T20 step down from the island toward the east plateau.
- **Mid band (y-1405..-1585):** a west staircase T15 → T13 → T10/T11 → T8, with the long shelf T9 at the far west. On the east, T16 and T14.
- **Upper band (y-1705..-1945):** T5/T6 (west), T4 (centre), T2/T3 (east) and the rope stop T7.
- **Top (y-2065/-2125):** T1 and the summit T0.
- **Total rise:** the summit is 1380 px above the valley floor. That is about 5 bands: valley, low-mid, island/mid, upper and top.

### 1.4 Routes [inference]
- **Arrival:** in mid-air, on the centre island. The spawn points are at (-68..230, about -1412) on T17, (381,-1390) on T18, (-203,-1434) on T15 and (-332,-1486) on T13. The exit door is right there, so this is a hub you leave and return to.
- **Upper loop (clockwise in 2D):**
  1. From T17, hop up west through the stair T15 → T13 → T11 → T8.
  2. Rope x-200 to T6, then step across to T5 or hop up to T4.
  3. From T5, rope x-407 to summit T0, then step down to T1 and take the rope ladder x29 down to T4.
  4. Hop up to T2 and walk onto T3.
  5. Rope x627 down to T7, rope x714 down to T14, hop up to T16, and drop to T18 and T17.
- **Down to the valley:**
  - West: T15 → rope x-272 → T21 → rope x-597 → west plateau. Or T21 → T22 → rope x-167 → slope T23d.
  - East: T18 → T19/T20 → rope x643 → east plateau.
- **Back up:** the three ground ropes, at x-597, x-167 and x643, each about 258 px.

## 2. Portals
- The parsed v8 JSON has 8 entries and no nulls: 7 `sp` (listed above) and **`out00`, type 2, at (133, -1346), going to 1000000 `in05`**. This is one of the connections already known before this brief.
- Raw WZ `/portal/7` confirms it. The door object `door/grassySoil/door/0` stands at (130, -1395) on the face of block T12, and the render shows a wooden banded door there.
- On the other side, `in05` is in The Field West of Amherst at (757, -747), up on that map's upper level, and links back to `1000006:out00`. Source: raw v8 WZ `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001000000.img/portal/8`, also recorded in `1000000.struct.json`.
- **No edge exits.** Both perimeter walls run to the map bottom. This is a dead-end pocket; Hidden Street lists only "Field West of Amherst".

## 3. Spawns
- **Snail** (lv 1): 13.
- **Blue Snail** (lv 2): 17.
- **Shroom** (lv 2): 9.
- **Red Snail** (lv 4): 6.
- **Orange Mushroom** (1210102, lv 8): 6. It is the only lv-8 mob in the four maps briefed here.
- That matches Hidden Street 2005: "Snail, Blue Snail, Red Snail, Shroom, Orange Mushroom".

| tier | Snail | Blue | Shroom | Red | Orange Mush. |
|---|---|---|---|---|---|
| T23a west plateau | 2 | 1 | – | – | 1 |
| T23b slope | – | 1 | – | – | – |
| T23c mid shelf | 1 | 2 | – | – | – |
| T23e valley floor | – | 2 | – | – | 1 |
| T23f long slope | 1 | 2 | – | – | – |
| T23g east plateau | 1 | 2 | – | – | 1 |
| T21 | 2 | 3 | – | – | – |
| T14 | 2 | 1 | – | – | – |
| T9 | 2 | – | – | 3 | – |
| T5 | – | – | 4 | 2 | – |
| T4 | 2 | – | 2 | – | 1 |
| T3 | – | 3 | 1 | 1 | – |
| T0 summit | – | – | 2 | – | 2 |

- The valley ground holds 18 of the 51 spawns: 15 snails and 3 Orange Mushrooms.
- The upper band (T0, T3, T4, T5) holds 20, including all 9 Shrooms and the other 3 Orange Mushrooms.
- T9, T21 and T14 hold the remaining 13.
- The arrival island and the stair stones have no spawns.

## 4. Visual reference

### 4.1 Terrain
- The tile set is `grassySoil`: grass over olive-brown cobbled dirt with grey boulders.
- The ground has smooth grass-edged slopes, the only slopes in these four maps.
- The centre island has a deep, rounded dirt underside.
- Backgrounds use set `grassySoil` (`back/0..4`): blue sky, drifting clouds, a domed hill, a big leafy tree and a golden meadow strip.

### 4.2 Objects (raw WZ; x,y = object origin; all visible in the v8 render)
- **Exit door:** wooden, banded and arched, at (130, -1395) on the door block. A white stake fence (`midForest/artificiality/1`) stands at x-15 and a big **autumn twin tree** (`midForest/nature/4`) at x-7, both on T17 west of the block.
- **The valley has an autumn colour scheme:**
  - West plateau: 2 autumn-orange twin-trunk white-bark trees (x-968, -797) and stake fences (x-1008, -652).
  - Valley floor: a **yellow** twin tree (`nature/3`) at x42 and stake fences at x-49 and x176.
  - East plateau: a yellow twin tree at x894, stake fences at x638 and x830, and bushes.
- **Flowers:**
  - Lily-of-the-valley (`midForest/nature/9`) on T23c (×3), T21, T9 (×2), T14 and T5.
  - Yellow daffodils (`nature/10`) on summit T0 (×4) and T3 (×3).
- **Giant umbrella-leaf plant** (`midForest/nature/8`) on T4 at x161, with olive bushes (`darkWood/nature/9`).
- Low dark bushes appear throughout.
- The rope tops have wooden pegs. T1-T4 is a rope ladder.

### 4.3 Missing from the render
- This render shows objects. It lacks only the background layers.
- Hidden Street's 2005 thumbnail shows a grey, cloudy backdrop. The WZ data says blue-sky `grassySoil`, so I treat the thumbnail as darkened [inference].

## 5. What makes this map recognizable
- You arrive on a **floating island with a door in a grass block**, high above an **autumn valley**.
- The valley is a smooth V: a west plateau with orange trees, a low floor with a yellow tree, and a **long grassy ramp** up to a high east meadow with white stake fences.
- Around the island is a ring of grass islands with **lily-of-the-valley, daffodils and a giant umbrella leaf**. A rope ladder hangs below the summit.
- It has the **first Orange Mushrooms** (lv 8) among the Rainbow Street pockets briefed here.
- [memory] Nothing more specific.

## 6. 3D translation [proposal]

**Concept: a floating "hub islet" over an autumn dell, ringed by a spiral of sky islands.**
- MapleStory "up" becomes 3D up plus back, but the islands are arranged in a **ring around the hub** rather than in rows.
- The valley ground is the base of the scene and fills the front and the sides.

**Tier mapping**
- **Valley ground (T23a-g) → a curved dell** that wraps around the front of the scene. The slopes become real terrain slopes, with no stairs.
  - T23a is the west plateau, back-left and higher: an autumn grove.
  - T23b, T23c and T23d step down to the valley floor T23e, front-centre and lowest. The yellow tree stands there.
  - The long slope T23f rises 240 px over 360 px up to the east plateau T23g, back-right and the highest ground: the fenced meadow.
  - Keep the proportions: the east plateau is 240 px above the valley floor and 120 px above the west plateau.
- **Centre island T17+T18 → a floating islet** hovering over the dell. Its rounded root-ball underside is visible to the camera.
  - The door mound T12 sits on it with the door facing the camera.
  - The autumn twin tree and the short stake fence stand beside the mound.
  - T18 is a small extension lip on the east side.
- **Island ring:**
  - West ascending arc: T15 → T13 → T11/T10 → T8, a spiral of small stepping islets climbing counter-clockwise behind the hub. T9 is a large west island hanging out on the far left.
  - Upper arc: T6/T5 (west) → T4 (centre-back, the umbrella-leaf island) → T2/T3 (east, daffodils).
  - Crown: T1 and the summit T0, back-centre and highest.
  - East descending arc: T7 → T14 → T16 → T18, back down to the hub.
- **Climbs:**
  - Ropes become hanging ropes or rope ladders dangling from the islet undersides.
  - The rope ladder x29 stays a rope ladder; it is a recognizable prop.
  - The three long ground ropes (about 258 px) become the "elevators" between the dell and the islands. Put a visible anchor stake at the foot of each.
- **The 600-px gap** between the hub and the valley floor becomes empty air. Falling from the hub lands you in the dell, and you climb back by a ground rope.

**Route through 3D space**
- Start on the hub islet in the middle of the scene. The exit door is right there.
- The upper loop circles the hub: up the west, across the back crown, down the east.
- The dell below is a separate ring-shaped hunting floor. West-to-east order is kept: west grove on the left, valley floor in the centre, fenced meadow on the right.

**Spawn areas**
- The dell holds 15 snails plus 3 Orange Mushrooms, spread along its whole length.
- The upper islands T3, T4, T5 and T0 hold Shrooms, Red Snails and 3 Orange Mushrooms; the summit has 2 Orange Mushrooms and 2 Shrooms.
- T9 holds snails and Red Snails, and T21 and T14 hold snails.
- The hub and the stair islets stay mob-free.

**Top-down sketch.** Screen-left is the map's west end. Up is back and higher.
```
 back/high                     [T0 summit]-(T1)
                  rope x-407 /         | rope ladder x29
               [T5]-(T6)          [T4 umbrella leaf]-(T2)-[T3 daffodils]
              rope|x-696 \x-200                                 |rope x627
          [T9 big west]  (T8)                                   (T7)
                (T10)(T11)                                       |rope x714
                   (T13)                                     [T14]
                     (T15)      ( HUB ISLET T17 + DOOR MOUND T12 )(T18)(T16)
             rope x-272|                                     (T19)(T20)
               [T21]-(T22)                                         |rope x643
   rope x-597 |    rope x-167|
 [T23a west grove]\_[T23c]_\__[T23e valley floor]__/ long ramp T23f /[T23g fenced meadow]
 front/low   W --------------------------------------------------------------------> E
```

**Side elevation.** y in MapleStory px with up = higher; this is not to scale.
```
 y-2125            T0 ========
 y-2065                        T1 ==
 y-1945                          |ladder     T2 == T3 ========
 y-1885                      T4 =========                |rope
 y-1825   T5 ======== T6 ==                               |
 y-1705      |rope      |rope                          T7 ==
 y-1585                T8 ==                              |rope
 y-1525 T9 ======= T10 T11 ==                             |
 y-1495                     [T12 door block]              |
 y-1465               T13 ==       |               T14 ======
 y-1405                 T15 ==     |          T16 ==
 y-1345                    T17 =========  T18 ==
 y-1285                      (island)        T19 == T20 ==
 y-1165     T21 ========                                |rope
 y-1105              T22 ==                             |
 y -985      |rope      |rope                    _____T23g======
 y -865 T23a=======\                          __/  (long ramp T23f)
 y -805             \T23c===\              __/
 y -745                      \___T23e_____/
```

## 7. Version notes
- v8, v22 and v40 are identical: floors, ladders, mobs and spawn points.
- I did not fetch v55 or v62 for this map.

## 8. Open questions
- Should the door-block roof T12, which in 2D can only be reached by a long drop from T4, become a reachable perch in 3D or just a decorative roof?
- How far apart should the hub islet and the island ring be in 3D depth? The 2D gaps (12-px joints, 60-px hops) only make sense once the framework fixes jump reach.
