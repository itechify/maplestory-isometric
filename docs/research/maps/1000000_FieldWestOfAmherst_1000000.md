# Map 1000000: "The Field West of Amherst". Structural analysis and 3D translation brief

Phase-1 research, MisoStory. Classic GMS v8 data. All dimensions are MapleStory pixels (px) or tier counts. y increases downward, so a smaller y is higher up.

Tags used in this file:
- No tag: a fact taken from data. The source is cited.
- **[memory]**: something recalled from playing or reading. It is not verified here.
- **[proposal]**: a design suggestion for MisoStory.

Sources:
- **[D]** `docs/research/raw/gms_v8/1000000.json`, from maplestory.io `/api/GMS/8/map/1000000`. Used for footholds, ladderRopes, mobs and info.
- **[WZ]** The raw WZ tree through the maplestory.io WZ explorer, at `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001000000.img/...`. Used for `portal/*`, `info`, `back/*`, `<layer>/obj/*`, `<layer>/info` and `<layer>/tile`. **This source recovered all 8 portals that the /map JSON returns as `null`.**
- **[WZ-spr]** Object and background sprites, viewed (never copied) at `.../Data/Map/Obj/<oS>.img/<l0>/<l1>/<l2>/0` and `.../Data/Map/Back/grassySoil.img/back/<n>`. They were used to name the objects.
- **[R]** `docs/research/ref_renders/v8_1000000_render.png` and `v8_1000000_minimap.png`, viewed.
- **[V40]** `https://maplestory.io/api/GMS/40/map/1000000`. A later pre-Big-Bang version, used **only** for comparison.
- Mob names come from `docs/research/raw/entities/mob_v8_*.json`.

Machine-readable companion: `docs/research/maps/1000000.struct.json`. It uses the same tier IDs as this file.

---

## 0. Map card

| Field | Value | Source |
|---|---|---|
| Name / street | The Field West of Amherst / Rainbow Street | [D] |
| Role | **Hub field.** West exit leads to A Split Road, east exit leads to Amherst, and **6 side portals** lead to the six Amherst-forest training sub-maps (1000001 to 1000006) | [WZ] portals |
| isTown / returnMap | false / 1010000 (Amherst) | [D], [WZ] info |
| BGM | `Bgm00/RestNPeace` | [D], [WZ] info |
| mobRate | 1.3 | [D] |
| Tileset | `grassySoil`. Layer 0 has 72 tiles, layer 1 has 733, layers 2 to 7 have 0. Layers 4 to 7 carry the default `brownBrick` tS name but contain no tiles. | [WZ] `<L>/info`, `<L>/tile` |
| Background set | `grassySoil` back 0 to 4 | [WZ] back |
| Foothold extent | x -489..3459 (3948 px). Walkable y runs from -1045 (summit) to 455 (lowest floor). The map-edge walls extend down to y 660. | [D] |
| Vertical span | Lowest floor y 455 to summit y -1045 = **1500 px, about 25 steps of 60 px** | [D] |
| Footholds / tiers | 493 footholds. After cleaning: **10 ground levels (G1 to G10) and 39 platform levels (P01 to P36, with P11 split into a/b and P26 into a/b/c)** | [D] + analysis |
| Ropes / ladders | 13 (3 ladders, 10 ropes) | [D] |
| Mobs | 90 spawns: Red Snail 26, Shroom 21, Blue Snail 20, Snail 16, Orange Mushroom 7 | [D] |
| NPCs | none | [D] |

---

## 1. Structure

Method: footholds were grouped into connected chains through their prev/next links. Each chain was split into flat levels at its wall steps.
- A ground step of 60 px is a normal "stair" in this tileset.
- Floaters are almost always 168 px wide (2 tiles plus edges). Larger ledges are 258 to 798 px.
- Every y value in this map sits on a 60 px grid, except P01 (y 305).
- Floaters show 25 px of soil below their top. Ledges show 85 px (P26 shows 145 px).

### 1.1 Ground band (one continuous chain, west to east)

| ID | x-range | y | Length | Notes |
|---|---|---|---|---|
| G1 | -489..219 | 275 | 708 | **West edge.** The map wall at x -489 runs from y 660 to 275. The `west00` portal is at x -391. The spawn point sp is at (-91,181). The bottom of the left floater stack P02 starts here. |
| G2 | 219..591 | 335 | 372 | A shallow 60 px dip. You step down 60 px at x 219 and back up 60 px at x 591. |
| G3 | 591..1299 | 275 | 708 | The "rope yard": ropes at x 718, 898, 1085 and 1167 rise to P05, P07 and P10. |
| G4 | 1299..1389 | 335 | 90 | Stair down |
| G5 | 1389..1479 | 395 | 90 | Stair down |
| G6 | 1479..2301 | 455 | 822 | **Sunken hollow, the lowest floor.** Portals `in02` (x 1740) and `in03` (x 1908) sit in the front face of mound P01. Rope x 2197 rises to P11b. **The east side is a 180 px cliff at x 2301 (y 455 to 275). You cannot jump it.** |
| G7 | 2301..2829 | 275 | 528 | Top of the cliff. Ladder x 2528 rises to P08. A vine-wrapped signpost stands at x 2750. |
| G8 | 2829..2919 | 335 | 90 | Stair down |
| G9 | 2919..3009 | 395 | 90 | Stair down. The bottom of rope x 3001 hangs 163 px above this floor, too high to grab. |
| G10 | 3009..3459 | 455 | 450 | **East edge.** The `east00` portal is at x 3338. A sunflower patch is here, plus the **"Amherst ->" signboard** at x 3250. Rope x 3064 (bottom 72 px above the floor) rises to P12. The map wall at x 3459 runs from 455 to 660. |

So the ground profile is: plateau, dip, plateau, 3-step descent into a hollow, 180 px cliff, plateau, 3-step descent to the east gate. The two ends sit 180 px apart in height (G1 is 275, G10 is 455).

### 1.2 Platforms

The map stacks up to about 25 steps. Bands are listed from low to high. "BLOCK" means the platform's side walls reach the floor below, so it reads as a solid knoll rather than a floater.

**Low band (y 305 to -25)**

| ID | x-range | y | Length | Kind | Connects |
|---|---|---|---|---|---|
| P01 | 1626..2064 | **305** | 438 | ledge, BLOCK (walls 145 px, layer 0) | A **grassy mound standing in the hollow G6** (150 px above it). **The doors for in02 and in03 are set into its front face.** In v8 the top can only be reached by dropping from P11a. Clover grows on top. |
| P02 / P03 / P04 | -39..129 | 215 / 155 / 95 | 168 each | floating | **A vertical stack of three floaters** above G1. You climb by jumping up through each one, then continue to P06 and P09. |
| P06 | 51..219 | 35 | 168 | floating | From P04 to P09 |
| P09 | 141..309 | -25 | 168 | floating | **Dead end.** Nothing is within reach above it, so the left stack is a lookout. |
| P05 | 681..849 | 95 | 168 | floating | Rope x 718 from G3. Jump up to P07. |
| P07 | 861..1029 | 35 | 168 | floating | Rope x 898 from G3. Jump up to P10. |
| P10 | 1041..1209 | -25 | 168 | floating | Ropes x 1085 and x 1167 from G3. Jump up to P11a. |
| P08 | 2481..2649 | 35 | 168 | floating | Ladder x 2528 from G7. Jump up to P11b. |

**Mid band: the central plateau and the east balcony (y -25 to -85)**

| ID | x-range | y | Length | Kind | Connects |
|---|---|---|---|---|---|
| P11a | 1221..2019 | -85 | 798 | ledge | **Central plateau, west half.** It overhangs the hollow. From here the V-fork stairs (P13) rise. |
| P11b | 2019..2469 | -25 | 450 | ledge | **Central plateau, east half,** 60 px lower than P11a. Rope x 2197 hangs down to G6. **Four barrels** stand at x 2111 to 2261, and their tops are tiny standable footholds at y about -81. Dropping off the east end lands on G7 or P08. |
| P12 | 2931..3459 | -85 | 528 | ledge | **East balcony above the east gate.** Rope x 3064 goes to G10 (jump-grab, 72 px), rope x 3001 goes to G9 (163 px gap, one-way down), and rope x 3148 comes down from P26c (132 px gap, one-way down). **Two tall beige stalk-mushroom clusters** and a red toadstool cluster grow here. |

**V-fork stairs (y -145 to -325)**: floaters above the middle of P11a.

| ID | x-range | y | Notes |
|---|---|---|---|
| P13 | 1761..1929 | -145 | First step up from P11a |
| P14 | 1761..1929 | -205 | Stacked on P13 |
| P15 / P16 | 1671..1839 / 1851..2019 | -265 | **The fork splits west and east.** You can jump across between the two. |
| P18 / P19 | 1581..1749 / 1941..2109 | -325 | West arm continues to P22. East arm continues to P26a. |

**Upper band (y -325 to -505)**

| ID | x-range | y | Length | Kind | Connects |
|---|---|---|---|---|---|
| P17 | 141..489 | -325 | 348 | ledge | Below P20 and P21, reached by dropping from P21 |
| P20 | -219..129 | -385 | 348 | ledge | **The `in00` portal (In a Small Forest).** A wooden door, a "DANGER (!)" sign and bushes stand here. Block P27 sits on top of it. |
| P21 | 501..849 | -385 | 348 | ledge | Hub between P23, P24 and P17 |
| P22 | 1221..1569 | -385 | 348 | ledge | Top of the west arm. Rope x 1537 rises to P28. |
| P23 | 411..579 | -445 | 168 | floating | From P21 to P25 |
| P24 | 861..1209 | -445 | 348 | ledge | From P22 or P21 |
| P25 | 231..399 | -505 | 168 | floating | Ladder x 300 rises to P29 |
| P26a | 2121..2661 | -385 | 540 | ledge | **Upper-east shelf**, steps up eastward. Reached from P19. |
| P26b | 2661..2751 | -445 | 90 | ledge | Step |
| P26c | 2751..3189 | -505 | 438 | ledge | **The `in01` portal (Dangerous Forest)** at x 2987. A wooden DANGER notice board, hanging ivy and butterflies are here. Rope x 3148 hangs down to P12. |
| P27 | -174..84 | -535 | 258 | BLOCK top | **Knoll above P20. Unreachable in v8** because it sits 150 px above P20. |

**High band and summit (y -565 to -1045)**

| ID | x-range | y | Length | Kind | Connects |
|---|---|---|---|---|---|
| P28 | 1491..1659 | -565 | 168 | floating | Rope x 1537 from P22. Rope x 1598 rises to P31. |
| P29 | 231..579 | -685 | 348 | ledge | **The `in04` portal (Hunting Ground Middle of the Forest I).** A door, a skull "DANGER" sign and shrubs are here. Ladder x 300 comes up from P25. Block P33 sits on top of it. |
| P30 | 591..939 | -745 | 348 | ledge | **The `in05` portal (Hunting Ground Middle of the Forest II).** A door, a tilted skull warning sign and flowers are here. **In the render a raised block with no v8 footholds stands above it (see section 7).** |
| P31 | 1311..1659 | -745 | 348 | ledge | Ladder x 1554 rises to P34 |
| P32 | 951..1299 | -805 | 348 | ledge | Jump up from P30 or P31 |
| P33 | 276..534 | -835 | 258 | BLOCK top | **Knoll above P29. Unreachable in v8.** Two trees stand on it. |
| P34 / P35 | 1491..1659 / 1581..1749 | -925 / -985 | 168 | floating | Two steps from P31 to the summit |
| P36 | 1761..2559 | **-1045** | 798 | ledge | **Summit ledge** with a tree grove (5 trees), bushes and berry bushes. It holds 4 of the 7 Orange Mushrooms. |

Minor footholds were excluded from the tier list (they are in `minor_footholds` of the struct):
- 4 barrel-top slivers (37 px) at y about -81 on P11b.
- 3 wall-only fragments, at x 1581, 2919 and 3021.
- 4 leftover flats lying directly under a higher level of the same chain: 411..489@-265, 1980..2019@-25, 2661..2700@-385 and 2751..2790@-445. [V40] removes the first of these.

### 1.3 Ladders and ropes

| x | y1 to y2 | Type | From (bottom) to (top) | Bottom gap to floor |
|---|---|---|---|---|
| 718 | 97 to 273 | rope | G3 to P05 | 2 |
| 898 | 37 to 273 | rope | G3 to P07 | 2 |
| 1085 | -23 to 273 | rope | G3 to P10 | 2 |
| 1167 | -23 to 173 | rope | G3 to P10 | 102 (hard to grab) |
| 2197 | -23 to 417 | rope (440 px, the longest) | G6 to P11b | 38 |
| 2528 | 37 to 273 | **ladder** | G7 to P08 | 2 |
| 3064 | -83 to 383 | rope | G10 to P12 | 72 (jump-grab) |
| 3001 | -83 to 232 | rope | G9 to P12 | 163 (down only) |
| 3148 | -503 to -217 | rope | P12 to P26c | 132 (down only) |
| 1537 | -563 to -425 | rope | P22 to P28 | 40 |
| 1598 | -743 to -604 | rope | P28 to P31 | 39 |
| 300 | -683 to -541 | **ladder** | P25 to P29 | 36 |
| 1554 | -923 to -782 | **ladder** | P31 to P34 | 37 |

The WZ objects confirm that the ladders are drawn with `connect/ladder/0/*` and the ropes with `connect/rope/0/*` [WZ].

### 1.4 Reachability (from analysis; assumptions are approximate [memory])

Assumptions:
- One 60 px step up is a normal jump. The 77 px apex comes from the classic 555 px/s jump and 2000 px/s² gravity [memory].
- An up-jump can bridge a horizontal gap of about 50 px or less. A level jump can bridge about 75 px.
- Floaters are one-way, so you can jump up through them from below.
- A rope can be grabbed if its bottom is about 100 px or less above the floor.

Results:
- **Walking east is blocked at x 2301.** The 180 px cliff on the east side of the hollow stops you. To continue east you must climb rope 2197 (440 px) to P11b and drop onto G7. The other route is G3 ropes to P10, then P11a, then P11b. Walking west is free, because you just drop off the cliff.
- Hops (portal to portal, counting steps, jumps, climbs and drops):

| From | in02 / in03 | in01 | in00 | in05 | in04 | Other edge |
|---|---|---|---|---|---|---|
| west00 | 5 | 11 | 13 | 13 | 14 | east00: 9 |
| east00 | 4 | 13 | 15 | 15 | 16 | west00: 9 |

- Example routes from west00:
  - in01: G3 rope 1085, P10, P11a, P13, P14, P16, P19, P26a, P26b, P26c.
  - in00: ... P18, P22, P24, drop to P21, drop to P17, jump up to P20.
  - in05: ... P22, rope 1537, P28, rope 1598, P31, P32, drop to P30.
  - in04: ... P24, drop to P21, P23, P25, ladder 300, P29.
- Dead ends:
  - The P02 to P09 stack.
  - P12, which you reach by jump-grabbing rope 3064 or by dropping from P26c.
  - The P01 mound top, which you can only drop onto.
- Unreachable: the P27 and P33 knoll tops.
- [V40] adds ropes at x 805, 1487, 1720, 1829 (hollow floor to mound top) and 2348, and lengthens rope 3148. This is good evidence that the v8 layout was judged hard to navigate.

### 1.5 Side elevation (generated from the struct data)

Lowercase labels are placed beside short platforms. P01 is really at y 305 but is drawn on the 335 row. Barrel slivers are omitted.

```
x: -489..3459, 1 col = 60px, 1 row = 60px; '#'=ground '='=platform '|'=rope 'H'=ladder '@'=portal (drawn one row above its floor)
 -1045                                       =====P36======
  -985                                    P35
  -925                                  P34=
  -865                                   H
  -805              =P33=   @  ==P32==   H
  -745                @  ==P30==     ==P31==
  -685             ==P29==                |
  -625              H                     |
  -565              H                   P28=                     @
  -505      =P27== P25=                  |                   ==P26c==
  -445        @       P23=    =P24==     |                  ==p26b  |
  -385      =P20==      =P21==      =P22==         ===P26a===       |
  -325            =P17==                  P18   P19                 |
  -265                                     P15P16=                  |
  -205                                       P14                    |
  -145                                       P13
   -85                              =====P11a=====              ===P12====
   -25            P09            P10             ==P11b==        ||
    35          P06=          P07| |                |    P08     ||
    95         P04         P05|  | |                |    H       ||
   155         P03         |  |  | |                |    H       ||
   215   @     P02         |  |  |                  |    H       ||
   275 #####G1######     #####G3######              | ###G7####   |
   335 :           ##G2###           G4   ===P01=== | :       G8# |
   395 :           :     :           :G5#   @  @    | :       : G9|    @
   455 :           :     :           :: ######G6#######       : :###G10###
```

Portal markers, left to right: west00 (row 215), in00 (above P20), in04 (above P29), in05 (above P30), in02 and in03 (above G6), in01 (above P26c), east00 (above G10).

---

## 2. Portals (all sourced from [WZ] `portal/<n>`; none inferred)

| # | Name | Position | Tier | Target | Notes |
|---|---|---|---|---|---|
| 0 | sp | (-91,181) | above G1 | (spawn point) | pt 0 |
| 1 | **west00** | (-391,276) | G1 | **50000 A Split Road : east00** | pt 2. Left edge. |
| 2 | **east00** | (3338,456) | G10 | **1010000 Amherst : west00** | pt 2. Right edge, beside the "Amherst ->" sign. |
| 3 | in00 | (-60,-385) | P20 | 1000001 In a Small Forest : out00 | door object at (-57,-435) |
| 4 | in01 | (2987,-508) | P26c | 1000002 Dangerous Forest : **out01** | no door object. DANGER board at (3033,-572). |
| 5 | in02 | (1740,455) | G6 | 1000003 Mushroom Garden : out00 | door at (1739,405) in the face of mound P01 |
| 6 | in03 | (1908,456) | G6 | 1000004 Snail Garden : out00 | door at (1905,405) in the face of mound P01. **168 px from in02.** |
| 7 | in04 | (389,-688) | P29 | 1000005 Hunting Ground Middle of the Forest I : out00 | door at (395,-736) |
| 8 | in05 | (757,-747) | P30 | 1000006 Hunting Ground Middle of the Forest II : out00 | door at (758,-795). Matches the known-good 1000006 out00 -> 1000000:in05. |

- The `/map` JSON [D] parsed only the `sp`. Its 8 `null` entries correspond one-to-one to WZ portals 1 to 8.
- All exit portals have type pt=2.
- In 5 of the 6 side portals, the data places a `door/grassySoil/door/0` wooden door sprite about 50 px above the portal point. So **the side maps are entered through little wooden doors**.

---

## 3. Spawns

90 mobs, all on ledges at least 348 px long or on the ground. **None spawn on the 168 px floaters.** Levels come from the entity files: Snail 1, Blue Snail 2, Shroom 2, Red Snail 4, Orange Mushroom 8.

| Mob (id) | Count | Where |
|---|---|---|
| Red Snail (130101) | 26 | Ground 11 (G6 3, G3 3, G7 2, G1, G2, G10). Then P32 3, P11a 2, P26a 2, and 1 each on P11b, P12, P17, P21, P22, P24, P26c, P30. |
| Shroom (120100) | 21 | Ground 7. **P30 4.** P12 2, P26a 2, and 1 each on P11a, P11b, P17, P21, P22, P24. |
| Blue Snail (100101) | 20 | Ground 1 (G2). P11a 3, P11b 2, P12 2, P22 2, P26a 2, P31 2, and 1 each on P17, P21, P24, P29, P32, P36. |
| Snail (100100) | 16 | Ground 5 (G2 2, G1, G3, G7). **P29 4**, P31 3, **P36 3**, P12 1. |
| Orange Mushroom (1210102) | 7 | **P36 summit 4**, P26c 2 (by the Dangerous Forest portal), P11b 1. **No Orange Mushrooms on the ground.** |

NPCs: none [D].

Pattern: weak mobs are spread everywhere. The strongest mob, the Orange Mushroom, is kept on the summit and by the Dangerous Forest door, as a reward for climbing.

---

## 4. Visual reference

### 4.1 Terrain (from [R] and [WZ] tS)

- Tileset `grassySoil` [WZ]: bright green, spiky grass tops over **khaki / olive-ochre soil** with a clumpy, rocky texture. Small **mossy grey rocks** are embedded in the soil faces [R].
- Ground and ledges show thick soil faces with a wavy, dripping lower edge. Floaters are thin slabs.
- No stone, wood or water appear anywhere in the terrain.

### 4.2 Objects and landmarks (positions from [WZ] `<layer>/obj`; names from viewing [WZ-spr])

| What | Where (x,y) to tier |
|---|---|
| **Wooden plank doors**, used as portal doors | (-57,-435) P20, (395,-736) P29, (758,-795) P30, (1739,405) G6, (1905,405) G6 |
| **Danger signs** beside the doors | triangular "!" DANGER at (15,-422) P20 (in00). Skull DANGER at (470,-727) P29 (in04). Tilted skull sign at (682,-787) P30 (in05). **Wooden DANGER board** at (1629,408) G6 (beside in02) and at (3033,-572) P26c (in01). |
| **"Amherst ->" wooden signboard** | (3250,370) G10, beside east00 |
| Sunflower patch (5 sunflowers, 2 small) | x 3054..3193, y about 415, on G10 |
| Vine-wrapped blank signpost and 2 loose planks | (2750,198) G7 |
| **Barrels** (3 upright, 1 on its side) | x 2111..2261, y about -55, on P11b |
| **Tall beige stalk-mushroom clusters** (sprite 132x294 px) | (3284,-187) and (3355,-236), on P12 |
| Red spotted toadstool clusters | (1412,-136) P11a, (3313,-137) P12 |
| White-trunked trees (`midForest` set: green, teal, orange, yellow and mixed foliage) | G1 x -311 and -143. G2 x 491. G6 x 2198 and 2007 (the squat tree). P27 x -125 and 53. P33 x 444 and 522. P26a x 2300 and 2479. **P36 summit grove** x 2121, 2212, 2294 and 2419. |
| Bushes, clover, berry bushes, small white mushrooms, flowers, butterflies | scattered. Full list in the struct `landmarks` field. |

The minimap [R] shows the same features at low resolution:
- autumn and white-trunk trees at bottom-left and on the summit;
- the red toadstool and bush on the central plateau;
- the pale stalk-mushroom cluster on the east balcony;
- the orange sign and sunflowers at bottom-right.

### 4.3 Background (from [WZ] back, viewed through [WZ-spr])

Back set `grassySoil`:
- back 0: flat blue fill (type 3).
- back 1: big white cumulus clouds on blue sky (type 4).
- back 2: a distant domed grassy hill with an orange mushroom-cap house under a giant tree stump, a winding dirt path, fences and round bushes (type 0).
- back 3: one large leafy oak-like tree (type 0).
- back 4: a grassy meadow band with tall grass and pink flowers (type 1).

[memory] In MapleStory, back type 3 tiles in both directions, type 4 tiles horizontally and scrolls (drifting clouds), and type 1 tiles horizontally.

### 4.4 Missing from the render

The render [R] draws tiles only, plus a few rocks embedded in tiles. Everything listed in 4.2 and 4.3 is absent from it: trees, doors, signs, barrels, mushrooms and background. It also shows a raised soil block above P30 that has no footholds in v8 (see section 7).

---

## 5. What makes this map recognizable

- From the data:
  - **A huge, busy hub.** It is the widest of these maps (3948 px) and has the most layers (about 25 steps). Eight exits are spread across every height band.
  - **Little wooden doors with danger signs** lead off into the side forests.
  - **A sunken hollow with a twin-door mound** (Mushroom Garden and Snail Garden) sits in the middle of the ground road.
  - **A V-shaped fork of stepping-stones** rises out of the central plateau.
  - **An "Amherst ->" sign with sunflowers** stands at the east gate.
  - **Giant pale stalk-mushrooms** grow on the east balcony.
  - **A wooded summit** holds the Orange Mushrooms.
- [memory] For a new player this was the first "big" field after Amherst.
- From the data: the side portals use **four different danger-sign variants**: a "!" triangle, a tilted skull triangle, a skull-and-DANGER triangle, and a wooden "!" DANGER notice board. None shows more than one skull. Whether the variants encode difficulty is only a [memory]-level interpretation.
- [memory] The music is the calm Maple Island field theme, "Rest N' Peace".

---

## 6. 3D translation [proposal]

Goal: turn this 2D map into a **hillside meadow that rises away from the camera**. The ground road becomes the front edge, and the platform bands become terraces that climb back and up. Keep west at screen-left and east at screen-right so the exits stay readable. Treat **one 60 px MS step as one terrace tier (H)**, and keep the x proportions of the original.

### 6.1 Massing

1. **The front road (G1 to G10)** runs west to east along the camera-near (south) edge.
   - G1 and G3 are tier 0.
   - G2 is a shallow swale, -1 H.
   - G4 and G5 are two earth steps down into **the Hollow (G6, -3 H)**.
   - The **east wall of the Hollow is a sheer 3 H earthen cliff** (from x 2301). Do not give it stairs, to preserve the "you must climb" moment.
   - G7 is tier 0 again, and G8 to G10 step down 3 H to the **East Gate**.
   - The gap between the west and east gates is 3 H in height.
2. **The Hollow** is a bowl. The **mound P01** (2.5 H tall, about 440 px wide) sits against the bowl's north (back) wall, with **two wooden doors in its face**, 168 px apart. These are in02 Mushroom Garden (with its DANGER board) and in03 Snail Garden. **Rope 2197** becomes a long rope or vine ladder on the bowl's back-right cliff, rising 7 to 8 H to the central plateau.
3. **The Central Plateau (P11a/P11b)** is a mesa directly behind (north of) the Hollow, about 1250 px wide. It stands +5 H (east half) to +6 H (west half) above the road, which is 8 to 9 H above the Hollow floor.
   - The west half is 1 H higher than the east half.
   - The four G3 ropes and the floaters P05, P07 and P10 become **a rising chain of tree-stump steps** climbing north from G3 onto the mesa's west end. Ropes stay ropes where the gap exceeds 1 H.
   - Place the barrels on the east half.
4. **The V-fork (P13 to P19)** is a stack of stump steps on the mesa's back edge. It splits into a **west stair** and an **east stair**, each 4 H tall.
5. **The West Terraces (P17, P20 to P25, P28 to P32)** are a stepped slope rising north-west from +10 H to +18 H above the road. Three **door knolls** sit on it:
   - P20 / P27 holds in00.
   - P29 / P33 holds in04.
   - P30 and its phantom block hold in05.
   Each knoll is a grassy hummock (about 2.5 H tall, 260 to 350 px wide) with a wooden door in its front and the matching danger sign beside it.
   - Ladder 300 and ladder 1554 become wooden ladders on terrace faces.
   - Ropes 1537 and 1598 become ropes hanging from overhangs.
6. **The East Shelf (P26a to P26c)** is a narrow ledge path climbing eastward along the north-east rim (+11 to +13 H above the road). It ends at the **Dangerous Forest portal** (in01) with its DANGER board, ivy and butterflies. Rope 3148 drops from its end down to the **East Balcony (P12)**. P12 is a lookout at +9 H above the East Gate, marked by the giant stalk-mushrooms. Ropes 3001 and 3064 hang from it to the road.
7. **The Summit (P36)** is the highest, furthest-back point (+25 H relative to the Hollow floor), north-centre-east, with the white-trunk tree grove. Reach it from the west terraces through P31, ladder 1554 and P34/P35, which become two stepping stones.
8. **The West Lookout (P02 to P09)** is a stack of three to five stepping stumps by the West Gate. It is optional and a dead end.

### 6.2 Top-down sketch (screen-left = west / west00, screen-up = north = back and higher)

```
 N (back, high)
 +--------------------------------------------------------------------------+
 |   (P33 knoll)      [P32]     [P34]>[P35]>( P36  SUMMIT GROVE  )          |
 | [P29 knoll in04]-[P30 knoll in05]  [P31]=H                               |
 | (P27 knoll) [P25]H  [P24]  [P28]          [P26c in01 DANGER]--rope--+    |
 | [P20 in00] [P23] [P21]  [P22]<--west--V-FORK--east-->[P26b][P26a]    |    |
 |   [P17]                       P18 P15|P16 P19                       v    |
 |                                   P14/P13                     [P12 balcony]
 | lookout   [P10]<[P07]<[P05]  ===P11a======|==P11b(barrels)===   stalk-mush|
 | stack        stump steps        ^ rope 2197      [P08]=H        ropes |    |
 | P02-P09       ^ ropes            \__HOLLOW G6__/     |              v    |
 | G1 west00  G2  G3  G4 G5 \  [P01 mound: in02 in03] |CLIFF G7  G8 G9 G10 east00
 |  (sp)     swale          steps      DANGER board    |   signpost  Amherst-> sunflowers
 +--------------------------------------------------------------------------+
 S (front, camera side)
```

### 6.3 Side elevation of the 3D version (looking north; heights in H = 60 px tiers relative to the Hollow floor)

```
 H (60 px tiers above the Hollow floor G6)
 25                                          ______P36 summit______
 23-24                                   P34 P35
 21     (P33 knoll)       P32
 19-20  [P29 in04] [P30 in05]   P31
 17                          P28
 16   (P27 knoll) P25                                          P26c in01
 15                P23  P24                                 P26b
 14   [P20 in00]  P21  P22                              P26a
 13        P17                P18 ... V-fork ... P19
 10-12                          P13 / P14 / P15-P16
  9                     ====P11a====                           ===P12 balcony===
  8                 P10            ====P11b====
  3   G1___    ____G3____                       ____G7____
  2        \G2/          \G4                    |          \G8
  1                         \G5    [P01 2.5H]   | CLIFF 3H    \G9
  0                            \_____HOLLOW G6__|                \___G10 east00
      west00                       in02  in03                        "Amherst ->"
```

### 6.4 Spawn areas [proposal]

| Area | Mobs |
|---|---|
| Road and Hollow | Red Snail and Shroom, with a few Snails |
| Plateau and V-fork landings | Blue Snail and Red Snail |
| West terraces | Snail and Blue Snail, plus 4 Shroom near in05 |
| East shelf and summit | Orange Mushroom pocket |

Keep the 168 px floaters (stump steps) free of mobs, as in the data.

---

## 7. Version notes

- **Phantom block above P30.** The render [R] shows a soil block at about x 611..841, top about y -900, above P30. v8 has **no footholds** there, so in v8 the block is decorative and the in05 door is drawn into its face. [V40] adds footholds `636..894@-895`, which makes it walkable. **Proposal:** model it as a decorative knoll (not walkable) to match v8.
- [V40] has 385 footholds against 492 in v8. Both counts are distinct geometries; v8 has 493 foothold records. 121 v8 footholds are absent and 14 are new. The mob list is identical.
- [V40] adds ropes at x 805, 1487, 1720, 1829 and 2348, and extends rope 3148 to y -140. Do **not** use v40 for topology. These are post-era accessibility changes.
- In v8 the maplestory.io `/map` JSON returns 8 `null` portals. The WZ explorer returns them intact. v22 [D] has the same nulls.

## 8. Open questions

- Which danger-sign variant maps to which perceived difficulty? Sign 0 ("!") is at In a Small Forest. Skull signs 1 and 2 are at the Hunting Grounds. Board 3 is at Mushroom Garden and Dangerous Forest. Snail Garden has no sign. This is a data fact; the meaning is unconfirmed.
- Is the in01 portal (pt 2, no door object) drawn as a plain swirl portal in-game? [memory suggests yes]
- The `west00` target is `50000 A Split Road : east00`. Whoever writes the 50000 brief should confirm that the reverse link exists.
