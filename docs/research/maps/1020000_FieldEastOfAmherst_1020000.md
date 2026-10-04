# Map 1020000: "The Field East of Amherst". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/1020000.struct.json` (tier ids T01..T37 match it).

**Tags**: no tag = data fact (source given). **[visual]** = my reading of a v8 object sprite or render. **[inference]**, **[memory]** and **[proposal]** mean the same as in the other briefs.

**Sources**
- `docs/research/raw/gms_v8/1020000.json` (`/api/GMS/8/map/1020000`): footholds, 12 ladders/ropes, 52 mob spawns. Its parsed `portals[]` has 1 `null`.
- Raw GMS v8 WZ, which has the missing portal: `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001020000.img/portal/10`. The same tree gives `life`, `back`, `info` and `1/obj`, `3/obj`.
- Object sprite sizes: `https://maplestory.io/api/wz/GMS/8/Data/Map/Obj/...`. Viewed in a temp folder only, not copied.
- Mob names and stats: `https://maplestory.io/api/GMS/8/mob/{100100,100101,130101,1210102}`.
- Renders, viewed but not copied: `ref_renders/v8_1020000_render.png` and `v8_1020000_minimap.png`.
- Version check:
  - Footholds are identical in v22, v28, v40, v44 and v46.
  - From v57 on the API shows a **different layout**: other footholds, `in01`→1000005, `in02`→1000006, NPC Mai at (-21,95). Do not mix those later versions in.

## 0. Map card

| field | value |
|---|---|
| Name | "The Field East of Amherst" (Rainbow Street), `isTown=false`, returnMap 1010000 |
| BGM | `Bgm00/FloralLife` |
| Foothold extent | x -489..2199 (2688 px). Walkable y -745..215 (960 px from pit floor to the top platforms). Edge walls reach y=480. |
| Minimap | 174 x 98 px, `centerX 558, centerY 1016`, magnification 4. |
| Walkable tiers | 37: 9 on the ground chain, 1 log-pile top, 27 floating platforms. |
| Vertical layering | Ground (95/155/215) plus 10 platform rows at y -85, -145, -205, -265, -325, -385, -445, -565, -685 and -745, mostly 60 px apart. |
| Ladders / ropes | 12: 5 ladders and 7 ropes. |
| Exits | 2: `west00` → Amherst, and the **hidden** `in00` (pt=1) → Tomato Field. |
| Mobs | 52 spawns: Blue Snail 19, Red Snail 13, Orange Mushroom 12, Snail 8. |

## 1. Structure

### 1.1 Ground chain (one continuous chain, x -489..2199)

The profile is **two pits**, each 120 px deep and entered by two 60 px steps:

| id | kind | x-range | y | length | role |
|---|---|---|---|---|---|
| T01 | ground | -489..129 | 95 | 618 | west plateau. `west00` (-332,90) and 6 `sp` points are here. The ladder x=33 goes up from it. |
| T02 | ground | 129..219 | 155 | 90 | step down |
| T03 | ground | 219..771 | 215 | 552 | **west pit** floor (trees) |
| T04 | ground | 771..861 | 155 | 90 | step up |
| T05 | ground | 861..1029 | 95 | 168 | central mound. The rope x=920 goes up from it. |
| T06 | ground | 1029..1119 | 155 | 90 | step down |
| T07 | ground | 1119..1491 | 215 | 372 | **east pit** floor (tree) |
| T08 | ground | 1491..1581 | 155 | 90 | step up |
| T09 | ground | 1581..2199 | 95 | 618 | east plateau (log pile, giant mushroom). The ladder x=1702 goes up from it. |
| T10 | floating | 1801..1918 | 67→70 | 117 | top of the stacked log pile, about 27 px above T09 |

- The walls between ground steps are all 60 px (x 129, 219, 771, 861, 1029, 1119, 1491, 1581).
- Map edge walls: x=-489 and x=2199, both running y 95..480.
- There are no slopes on the ground.

### 1.2 Floating platforms
- Every platform has short "lip" walls hanging 25..85 px below its edges. They are edge pieces and do not block walking on top.
- Small platforms are **168 px** wide (78+12+78 tile pieces). Long ones are 348, 438 or 528 px.

| row y | tiers (x-range) | notes |
|---|---|---|
| -85 | T11 (1581..1749) | over the east plateau. Ladder x=1702 from T09. |
| -145 | T12 (-39..129), T13 (141..309), T14 (321..489), T15 (501..669), T16 (681..849), T17 (861..1029) | a **row of six stepping stones** spanning x -39..1029 with 12 px gaps. Ladder x=33 from T01 to T12; rope x=920 from T05 to T17. |
| -205 | T18 (51..219) | one step, 60 px above the row |
| -265 | T19 (141..309); T20 (1041..1569, 528 px) | T20 holds the **pink-flower clover bed** |
| -325 | T21 (321..849, 528 px); T22 (861..1029); T23 (1491..1659) | T21 holds the **red-berry shrub row** |
| -385 | T24 (1671..2019, 348 px) | **Tomato Field portal ledge**: DANGER sign, 3 tomato plants, hidden `in00` |
| -445 | T25 (-399..129, 528 px); T26 (141..309) | T25 holds two big bushes |
| -565 | T27 (771..939), T28 (951..1119), T29 (1131..1299), T30 (1311..1479), T31 (1491..1659) | a second **row of five stepping stones**, x 771..1659 |
| -685 | T32 (141..309); T33 (1581..2019, 438 px) | T33 holds small bushes and white mushrooms |
| -745 | T34 (321..759, 438); T35 (771..939); T36 (951..1389, 438); T37 (1401..1569) | the top row. Big bushes with flowers on T34 and T36. |

**Adjacency [inference]**
- Many platforms are joined by a 60 px rise and a 12 px horizontal gap, which is a single hop:
  - T13/T12 row → T18 → T19 → T21: a diagonal staircase up-right from the -145 row.
  - T22 → T20 (down 60, gap 12).
  - T23 → T24 (up 60, gap 12).
  - T25 ↔ T26 (same row).
  - T32 → T34 (up 60, gap 12).
  - T37 → T33 (down 60, gap 12).
  - The -745 row is continuous with 12 px gaps: T34-T35-T36-T37.

### 1.3 Ladders and ropes

| x | y1→y2 | type | from_tier → to_tier | climb | bottom gap |
|---|---|---|---|---|---|
| 33 | -143→45 | ladder | T01 → T12 | 188 | 50 |
| 920 | -143→53 | rope | T05 → T17 | 196 | 42 |
| 979 | -323→-188 | rope | T17 → T22 | 135 | 43 |
| 1702 | -83→57 | ladder | T09 → T11 | 140 | 38 |
| 1618 | -323→-127 | rope | T11 → T23 | 196 | 42 |
| 208 | -443→-302 | ladder | T19 → T26 | 141 | 37 |
| 263 | -683→-487 | rope | T26 → T32 | 196 | 42 |
| 895 | -563→-367 | rope | T22 → T27 | 196 | 42 |
| 1548 | -563→-367 | rope | T23 → T31 | 196 | 42 |
| 837 | -743→-602 | ladder | T27 → T35 | 141 | 37 |
| 1442 | -743→-604 | ladder | T30 → T37 | 139 | 39 |
| 1893 | -683→-457 | rope | T24 → T33 | 226 | **72** (the longest jump-grab) |

- Every ladder/rope bottom hangs 37..72 px above its lower tier, so you jump to grab it.
  - [memory] That is standard classic rope placement.
- Objects: `connect/ladder/0/*` and `connect/rope/0/*` in layer 2.

### 1.4 Key routes [inference]
- **To the Tomato Field portal**:
  1. East plateau T09.
  2. Ladder x=1702 to T11.
  3. Rope x=1618 to T23.
  4. Hop up-right 60 px to T24.
  5. `in00` at (1792,-384).
- Alternative routes: from the top row T37 drop to T33, then drop 300 px to T24. Or come from T33 down the rope x=1893, which runs between T24 and T33.
- **To the top row**:
  1. Central mound T05.
  2. Rope x=920 to T17.
  3. Rope x=979 to T22.
  4. Rope x=895 to T27.
  5. Ladder x=837 to T35 (-745).
- **West column**:
  1. T01.
  2. Ladder x=33 to T12.
  3. Hops to T18, then T19.
  4. Ladder x=208 to T26.
  5. Rope x=263 to T32.
  6. Hop to T34.

## 2. Portals (raw WZ; `inferred=false`)

| name | pt | x, y | tier | target | notes |
|---|---|---|---|---|---|
| west00 | 2 | -332, 90 | T01 | 1010000:east00 (Amherst) | 157 px in from the west wall. Also parsed in the v8 API JSON. |
| **in00** | **1** | 1792, -384 | T24 | 1020001:out00 (Tomato Field) | [memory] pt=1 is an invisible portal that you use by pressing Up. It sits beside the DANGER sign (x 1762..1829) among 3 tomato plants. |

- There is **no east edge exit**. The east plateau ends in a wall at x=2199.
- [inference] Tomato Field is reachable only through the hidden `in00` up in the platform lattice.
- 10 `sp` points:
  - 6 over T01, at x -426..-37 and y -17..6, about 90..110 px above the ground.
  - 1 over T13 (248,-181).
  - 1 over T16 (738,-197).
  - 1 over T28 (1022,-578).
  - 1 over T31 (1533,-587).

## 3. Spawns

Mob stats from `/api/GMS/8/mob/<id>`:
- Snail (100100): lv1, HP 8
- Blue Snail (100101): lv2, HP 15
- Red Snail (130101): lv4, HP 45
- Orange Mushroom (1210102): lv8, HP 80

Spawns by tier:

| tier | where | spawns |
|---|---|---|
| T01 | west plateau | Blue Snail 1, Snail 1 |
| T02 | step | Blue Snail 1 |
| T03 | west pit | Orange Mushroom 3, Blue Snail 1, Snail 1 |
| T04 | step | Blue Snail 1 |
| T07 | east pit | Orange Mushroom 2, Blue Snail 2 |
| T09 | east plateau | Orange Mushroom 1, Blue Snail 1, Snail 1 |
| T20 | -265 clover bed | Blue Snail 3, Red Snail 3 |
| T21 | -325 berry row | Orange Mushroom 2, Blue Snail 3, Red Snail 2 |
| T24 | -385 portal ledge | Red Snail 3 |
| T25 | -445 west | Blue Snail 2, Red Snail 2, Snail 2 |
| T33 | -685 east | Blue Snail 2, Red Snail 2, Snail 1 |
| T34 | -745 west | Orange Mushroom 2, Blue Snail 1, Snail 1 |
| T36 | -745 centre | Orange Mushroom 2, Blue Snail 1, Red Snail 1, Snail 1 |

- 16 spawns on the ground, 36 on platforms. Every platform spawn is on a **long** platform (348..528 px). No mob spawns on a 168 px stepping stone.
- Red Snails spawn **only** on platforms.
- WZ `life` gives each platform spawn a patrol range (`rx0..rx1`) inside its platform. For example, T21 mobs have rx 341..829.
- No NPCs.

## 4. Look

### 4.1 Terrain (render)
- Grass-topped **olive/brown earth** blocks with embedded grey rocks.
- Floating platforms are grass-topped earth slabs with ragged undersides.
- WZ layer 1 lists `tS=grassySoil`.

### 4.2 Background
- `grassySoil` set, 5 entries:
  - `no=0, type=3`
  - `no=1, type=4` (scrolling)
  - `no=2` and `no=3, type=0` (parallax -10/-3)
  - `no=4, type=1` (parallax -15)
- [memory] Sky, drifting clouds and hills. Not in the render.

### 4.3 Objects (positions are data; descriptions are [visual])

| landmark | WZ objects | bbox [l,t,r,b] | on |
|---|---|---|---|
| big autumn tree (orange/brown foliage) | `acc1/midForest/nature/4` | -510,-223,-204,93 | T01 |
| two small rainbow-and-mushroom spring props | `acc1/grassySoil/artificiality/9` x2 | -321,3,27,92 | T01 |
| autumn tree + pale-yellow tree | `acc1/midForest/nature/4`, `/3` | 206,-103,712,217 | T03 (west pit) |
| pale-yellow tree | `acc1/midForest/nature/3` | 1057,-103,1363,213 | T07 (east pit) |
| red-berry shrub row | `acc1/grassySoil/nature/0` x3, `/1` | 422,-366,773,-324 | T21 |
| pink-flowered clover bed | `acc1/grassySoil/nature/10` x7 | 1138,-329,1465,-258 | T20 |
| **DANGER sign + 3 tomato plants** (marks `in00`) | `guide/midForest/danger/2`, `acc1/grassySoil/nature/9` x3 | 1746,-466,1968,-383 | T24 |
| big bush with orange flowers | `acc1/grassySoil/nature/13`, `/5`, `/6`, `/20` | 378,-855,651,-727 | T34 |
| big bush with flowers and a butterfly | `acc1/grassySoil/nature/13`, `/21`, `/6` x4 | 983,-866,1281,-738 | T36 |
| small bushes and white mushrooms | `acc1/grassySoil/nature/1` x3, `/7` x2 | 1643,-728,1986,-684 | T33 |
| rainbow-spring prop | `acc1/grassySoil/artificiality/9` | 1630,4,1783,92 | T09 |
| stacked log pile (top is T10) | `acc1/grassySoil/artificiality/6`, `/7` | 1800,32,1940,93 | T09 |
| **giant orange mushroom pair**: decorative house13, no portal | `houseGS/house13/basic/0`, `/1` x2 | 1924,-99,2175,99 | T09 |

- `acc1/grassySoil/nature/9` is the tomato-plant sprite: a small bush with red fruit.
  - The same object is repeated 72 times in Tomato Field (data). Its use here, right at the hidden portal, is a deliberate signpost [inference].
- The minimap shows the same trees, bushes and ropes. The render shows only terrain and the clover bed.

## 5. What makes this map recognizable
1. **A dense lattice of floating grass platforms** stacked 10 rows high (960 px) over a meadow with two sunken hollows. It is the tallest map in this group (data).
2. Rows of **small stepping-stone platforms**: 6 at -145 and 5 at -565 (data).
3. **Ladder-and-rope climbing**: 12 climbables (data).
4. The **hidden Tomato Field entrance** high on the east side, marked by a DANGER sign and tomato plants (data).
5. A **giant orange mushroom** at the far east end, and autumn trees in the hollows (data + [visual]).
6. Easy mobs: snails and Orange Mushrooms (data).

## 6. 3D translation [proposal]

### 6.1 Core idea
- Turn the vertical lattice into a **hillside that climbs away from the camera**.
- The meadow (ground chain) stays at the front.
- Each higher platform row is placed **further back and higher**, so altitude becomes altitude plus depth.
  - Rows -85..-205 become low earth mesas and stepping stones just behind the meadow.
  - Rows -265..-445 are mid-hill terraces.
  - Rows -565..-745 form the hill crown at the back.
- Ladders and ropes go on the cliff faces between terraces. Where the 2D data has a plain hop (60 px up, 12 px gap), use a step or a short earth ramp.
- Keep the 60 px unit as the standard step height, and the 168 px stepping stone as a reusable "earth pillar" piece.

### 6.2 Tier by tier
- **Ground T01..T09**:
  - The west plateau T01 is the arrival meadow: `west00` gate from Amherst, autumn tree, rainbow springs.
  - It dips into the **west hollow** T03 (two 60 px terrace steps down, trees inside), rises to the **central mound** T05, dips into the **east hollow** T07, and rises again to the **east plateau** T09.
  - T09 holds the log pile (standable, about 27 px) and the giant mushroom pair, which closes the east end in place of the wall at x=2199.
  - The two hollows are the low-level hunting areas. Most ground spawns (OM, Blue Snail) are there.
- **Stepping-stone rows (T12..T17 at -145, T27..T31 at -565)**:
  - Rows of 168 px earth pillars rising out of the slope.
  - In 3D, put them on a gentle **diagonal** across the hill rather than a straight line, so the row reads in depth.
  - Spacing stays 12 px gaps (hop) with an equal 60 px top height within a row.
- **Long platforms (T20, T21, T25, T33, T34, T36)**: broad terraces. They are the mid-level hunting shelves (Red Snails, OM) and carry the flower and berry beds.
- **T24 portal ledge**: a secluded nook terrace on the east flank, set into the hillside behind the T23 pillar. It carries the DANGER sign, three tomato plants and a hidden path or cave mouth (`in00`) leading to the Tomato Field.
  - Show the path only on approach, to keep the "hidden" quality of pt=1.
- **Top row T34..T37**: the hill crown. Four terraces linked by hops, with big flowering bushes.

### 6.3 Top-down sketch [proposal]

Screen-left = map west. Up = away from the camera, which here is also higher.

```
  (back, highest)   T32   T34 =big bush=  T35  T36 =big bush=  T37    T33 bushes
                       \                rope/ladders                   |  rope x1893
  (mid)        T25 bushes  T26    T21 berries   T22   T27..T31 row   T23 -> T24 [DANGER+tomatoes, in00]
                        \         /      \           T20 clover bed     |
  (low)          T12-T13-T14-T15-T16-T17 stepping stones   T18/T19       T11
                    | ladder x33           | rope x920                  | ladder x1702
  (front)  W> west00 [T01 meadow]\_T03 west hollow_/[T05 mound]\_T07 east hollow_/[T09 plateau logs][GIANT MUSHROOM]
```

### 6.4 Side elevation (data heights)

```
 y-745              T34======  T35= T36=======  T37=
 y-685    T32=  (rope263)                              T33=======
 y-565                       T27= T28= T29= T30= T31=   (rope1893)
 y-445 T25=========  T26=                              
 y-385                                                T24==== [in00]
 y-325               T21==========  T22=      T23=
 y-265          T19=           T20=============== (clover)
 y-205       T18=
 y-145  T12= T13= T14= T15= T16= T17=
 y -85                                       T11=
 y  95 ==T01=====+           +=T05=+             +====T09====[logs][mushroom]
 y 155           +=T02+  T04=+     +=T06+   T08=+
 y 215                +==T03 hollow==+     +==T07 hollow==+
 x:  -489      129 219      771 861 1029 1119    1491 1581              2199
```
