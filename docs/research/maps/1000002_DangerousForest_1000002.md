# Map 1000002: "Dangerous Forest". Structural analysis and 3D translation brief

Phase-1 research, MisoStory. Classic GMS v8 data. All dimensions are MapleStory pixels (px) or tier counts. y increases downward, so a smaller y is higher up.

Tags used in this file:
- No tag: a fact taken from data. The source is cited.
- **[memory]**: something recalled from playing or reading. It is not verified here.
- **[proposal]**: a design suggestion for MisoStory.

Sources:
- **[D]** `docs/research/raw/gms_v8/1000002.json`, from maplestory.io `/api/GMS/8/map/1000002`.
- **[WZ]** `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001000002.img/...`. Used for `portal/*`, `info`, `back/*`, `<layer>/obj/*`, `<layer>/info` and `<layer>/tile`.
- **[WZ-spr]** Sprites, viewed (never copied).
- **[R]** `docs/research/ref_renders/v8_1000002_render.png` and `_minimap.png`, viewed.
- **[V40]** `https://maplestory.io/api/GMS/40/map/1000002`. Comparison only.

Companion: `docs/research/maps/1000002.struct.json`.

---

## 0. Map card

| Field | Value | Source |
|---|---|---|
| Name / street | Dangerous Forest / Rainbow Street | [D] |
| Role | **Dead-end side map** off The Field West of Amherst (entered from 1000000 `in01`, the portal on the upper-east shelf with the DANGER board) | [WZ] |
| isTown / returnMap | false / 1010000 | [D] |
| BGM / mobRate | `Bgm00/RestNPeace` / **1.0** (1000000 and 1000001 use 1.3) | [D], [WZ] info |
| Tileset | `grassySoil` on layer 1 (308 tiles). All other layers are empty. | [WZ] |
| Background | `grassySoil` back 0 to 4 | [WZ] |
| Foothold extent | x -399..1749 (2148 px). Walkable y runs from -925 to 215. The edge walls go down to 420. | [D] |
| Vertical span | 215 to -925 = **1140 px, 19 steps** | [D] |
| Tiers | 139 footholds. **3 ground levels (G1 to G3)** and **9 platform levels** (P01a to P01c, P02 to P07) | analysis |
| Ropes | 7, all ropes. They are drawn as **green leafy vines** (`connect/rope/3`) [WZ]. | [D], [WZ] |
| Mobs | 35: Snail 15, **Orange Mushroom 12**, Red Snail 5, Blue Snail 3 | [D] |
| NPCs | none | [D] |

---

## 1. Structure

The map is a **three-band sandwich**:
- **Forest floor** (G1 to G3) rising eastward;
- **a thick middle shelf** (P01a to P01c) that descends eastward;
- **a crenellated top row** of alternating-height platforms.

Long vines (358 to 453 px) link the bands. Every y value is on a 60 px grid.

### 1.1 Tiers

| ID | x-range | y | Length | Kind | Connects / notes |
|---|---|---|---|---|---|
| G1 | -399..141 | 215 | 540 | ground | West end of the floor. West wall (215 to 420). |
| G2 | 141..861 | 155 | 720 | ground | 60 px step up from G1. **Four vines** rise from here to P01b: x 410, 504, 664 and 756. |
| G3 | 861..1749 | 95 | 888 | ground | 60 px step up from G2. Vine x 1410 rises to P01c. East wall (95 to 420). |
| P01a | -219..399 | -445 | 618 | ledge | **Middle shelf, west (highest part).** It sits 660 px (11 H) above G1. Vine x 286 rises to P04. 4 spawn points hover above it (y about -547). |
| P01b | 399..1029 | -385 | 630 | ledge | Middle shelf, centre. 60 px below P01a. 4 vines go down to G2. |
| P01c | 1029..1479 | -325 | 450 | ledge | Middle shelf, east (lowest part), 420 px (7 H) above G3. Vine x 1410 goes down to G3. Vine x 1349 rises to P02. |
| P02 | 1221..1389 | -805 | 168 | floating | East end of the top row. Vine x 1349 from P01c. Jump up to P05. |
| P03 | -399..39 | -865 | 438 | ledge | **Arrival platform, top-left: the `out01` portal at x -310.** 4 spawn points hover above it (y about -943). Purple flowers and bushes. |
| P04 | 231..399 | -865 | 168 | floating | Top of vine x 286. Jump up to P06 and P07. |
| P05 | 591..1209 | -865 | 618 | ledge | Long top ledge. 6 mobs. Red-berry bushes and 2 trees. |
| P06 | 51..219 | -925 | 168 | floating | **Highest point.** The link between P03 and P04. |
| P07 | 411..579 | -925 | 168 | floating | The link between P04 and P05 |

Notes on the middle shelf:
- It has very thick soil faces (205 px). In the render [R] it reads as a massive floating earth slab.
- Because the floor rises east and the shelf falls east, **the gap between them narrows from 11 H in the west to 7 H in the east**.
- The top row alternates between y -865 and -925 (P03 low, P06 high, P04 low, P07 high, P05 low, P02 at -805), so it looks like battlements.

No leftover footholds.

### 1.2 Ropes (all vines)

| x | y1 to y2 | From (bottom) to (top) | Length | Bottom gap |
|---|---|---|---|---|
| 410 | -248 to 153 | G2 to P01b | 401 | 2 |
| 504 | -307 to 105 | G2 to P01b | 412 | 50 |
| 664 | -383 to 70 | G2 to P01b | 453 | 85 (jump-grab) |
| 756 | -244 to 153 | G2 to P01b | 397 | 2 |
| 1410 | -323 to 40 | G3 to P01c | 363 | 55 |
| 1349 | -803 to -353 | P01c to P02 | 450 | 28 |
| 286 | -863 to -505 | P01a to P04 | 358 | 60 |

### 1.3 Reachability (approximate rules as in the 1000000 brief [memory])

- **You arrive on top (P03) and the map is a descent.** P01a and the floor are each 1 drop away.
- **The way back to the exit is 6 hops:** G1 to G2, vine 410 to P01b, step up to P01a, vine 286 to P04, jump to P06, drop to P03.
  - The other way is P01c, vine 1349 to P02, then P05, P07, drop to P04, P06, P03.
- Everything is reachable. Ropes are the only way up between bands.
- [V40] adds vines at x -96 (P03 to P01a, a direct return line), -135 and 838, and removes 18 footholds. Do not use for v8.

### 1.4 Side elevation (generated)

```
x: -399..1749, 1 col = 40px, 1 row = 60px; '#'=ground '='=platform '|'=rope 'H'=ladder '@'=portal (drawn one row above its floor)
  -925   @        =P06=    =P07=
  -865 ====P03=====    =P04=    ======P05=======
  -805                  |                       =P02=
  -745                  |                          |
  -685                  |                          |
  -625                  |                          |
  -565                  |                          |
  -505                  |                          |
  -445      ======P01a======                       |
  -385                     ======P01b=======       |
  -325                        |   |        ====P01c====
  -265                     |  |   | |               |
  -205                     |  |   | |               |
  -145                     |  |   | |               |
   -85                     |  |   | |               |
   -25                     |  |   | |               |
    35                     |  |   | |               |
    95                     |  |   | |  ##########G3###########
   155               ########G2#########
   215 ######G1#######                 :
```

---

## 2. Portals (from [WZ] `portal/<n>`)

| # | Name | Position | Tier | Target |
|---|---|---|---|---|
| 0 to 3 | sp ×4 | (-204,-944), (-148,-943), (-85,-942), (-25,-941) | above P03 | spawn points |
| 4 to 7 | sp ×4 | (-68,-550), (142,-543), (43,-547), (245,-550) | above P01a | spawn points |
| 8 | **out01** | (-310,-864) | P03 | **1000000 The Field West of Amherst : in01** |

- The exit portal is named **`out01`**, not `out00`, and it pairs with 1000000's `in01`.
- [D] returns it as `null`.
- No door object. No edge exits: both edges are walls. *(Verification pass: `docs/topology.json` now classes this exit as **edge_west**. There, edge_* is positional: the exit stands on a tier that reaches the map's west (the top-left row x -399..39) foothold limit. It does not mean a walk-off edge, so this line still holds.)*

---

## 3. Spawns

| Mob (id, level) | Count | Tiers |
|---|---|---|
| Snail (100100, 1) | 15 | P01a 4, P01b 3, P05 3, P01c 2, G3 2, P03 1 |
| **Orange Mushroom (1210102, 8)** | **12** | G2 3, G3 3, G1 2, P05 2, P01b 1, P01c 1 |
| Red Snail (130101, 4) | 5 | G1 2, G2 1, P01a 1, P01b 1 |
| Blue Snail (100101, 2) | 3 | G2 1, G3 1, P05 1 |

- The **floor holds 8 of the 12 Orange Mushrooms** (15 mobs in total on the floor). This is the highest Orange Mushroom count of the four maps briefed here, and it explains the name.
- The shelf holds mostly Snails.
- The floaters P02, P04, P06 and P07 are empty.

NPCs: none.

---

## 4. Visual reference

### 4.1 Terrain

- `grassySoil` [WZ]: green grass over khaki soil with mossy rocks [R].
- The middle shelf is a very thick soil slab.
- **The vines are bright green leafy stalks**, visible in the render [R] as long green lines.

### 4.2 Objects ([WZ] obj, names from [WZ-spr])

| What | Where (x,y) to tier |
|---|---|
| Green bushes (`darkWood` set), **21 of them** along every band | G1 (-179, 86). G2 (209, 313, 655, 793). G3 (927, 1146, 1238, 1472, 1548). P01b (434, 611). P01c (1036, 1183). P03 (-331, -174, -108). P05 (665, 811, 1056). |
| White-trunk trees | G1: (-272,56) and (-81,59) twin orange/rust. G2: (195,-27) mixed, (315,-14) teal, (432,15) and (746,15) green/teal, (676,-12) green with orange clump, (831,33) orange autumn. G3: (1222,-61) teal, (1336,-47) and (1664,-46) green/teal, (1529,-75) mixed. P01a: (-88,-603) and (96,-601) twin yellow. P01b: (520,-543) twin yellow. P01c: (1132,-484) twin orange. P05: (767,-1016) green/teal, (1048,-991) orange autumn. |
| Purple flowers | P03 (x -259 to -92, y about -888), next to the exit |
| Red-berry bushes | P05 (780,-885) and (1023,-882) |

The minimap [R] shows the forest as **dense, with yellow and orange canopies** on the shelf and floor, and brown autumn trees at the floor's west end. There are no signs, doors or man-made objects.

### 4.3 Background

`grassySoil` back 0 to 4 [WZ]: blue sky, clouds, distant mushroom-house hill, big tree, meadow band. The same set as 1000000.

### 4.4 Missing from the render

The render omits all trees, bushes, flowers and the background. It shows tiles and vines only.

---

## 5. What makes this map recognizable

- From the data:
  - **You enter from the top-left** and drop into a forest.
  - **A giant floating earth shelf** sits halfway up.
  - **Long green vines** (up to 453 px) are the only way back up.
  - A **battlement row** runs across the top.
  - **12 Orange Mushrooms** roam a floor that rises in two steps to the east.
  - Nothing man-made appears anywhere.
- [memory] The name, together with the DANGER board at its entrance in 1000000, flagged it as the "strong mob" sub-map of the Amherst forest for level 6 to 10 players.

---

## 6. 3D translation [proposal]

Concept: **a forest ravine you descend into.** H = 60 px tier, measured from G1.

1. **Entry bluff (P03, +18 H)** is a grassy clifftop at the back-left (north-west), where out01 sits among purple flowers. The camera should first frame the drop below.
2. **Battlement ridge (P06, P04, P07, P05, P02)** runs east from the entry along the back rim. It alternates between +19 H pillars (P06, P07: 168 px rock or stump pillars) and +18 H ledges (P04, P05). P02 (+17 H) is the last step at the east end. P05 (618 px) is a broad ridge meadow with berry bushes and 2 trees.
3. **The Great Shelf (P01a/b/c, +11/+10/+9 H)** is a massive overhanging forest terrace across the middle depth, about 1700 px long, stepping down 1 H twice toward the east. In 3D, set it **behind the floor and above it**, as a terrace projecting out from the back cliff, so its 205 px soil face reads as a cliff wall.
   - Vine 286 (P01a to P04) and vine 1349 (P01c to P02) hang on the back cliff above it.
4. **Vine curtain**: the four vines (x 410, 504, 664, 756) drape from the shelf's front lip down to the floor at G2. They are the main climb route.
   - Vine 1410 is a lone vine at the east end.
   - Vine 664 ends 85 px above the floor, so model a stump or rock under it to give the "jump-grab" a visible launch point.
5. **Forest floor (G1 to G3, 0 to +2 H)** is the ravine bed, at the front (camera side), rising east in two 1 H steps. **Make the ravine a wedge:** it is deepest at the west (11 H from floor to shelf) and shallowest at the east (7 H). Fill it with white-trunk trees (yellow, orange and teal) and bushes. **This is the Orange Mushroom zone.**

### 6.1 Top-down sketch (screen-left = west, up = north/back)

```
 N (back rim, highest)
 +----------------------------------------------------------------+
 | [P03 ENTRY out01 @]=[P06]=[P04]=[P07]=[==P05 ridge meadow==]=[P02]
 |                            : vine 286                    : vine 1349
 |      [====P01a====][=====P01b=====][===P01c===]  GREAT SHELF   |
 |                      :  :   :  :         :      (overhangs floor)
 |                      vine curtain        vine 1410             |
 |  ~~ trees ~~   ~~ trees ~~   ~~ trees ~~   ~~ trees ~~          |
 | [G1 floor 0H]      [G2 floor +1H]          [G3 floor +2H]       |
 |   Orange Mushrooms x8 + Red Snails on the floor                 |
 +----------------------------------------------------------------+
 S (front, camera)
```

### 6.2 Side elevation of the 3D version (H above G1)

```
 H
 19   @   P06   P07
 18  [P03]   P04   [====P05====]
 17                              P02
 11      [P01a]___                 :
 10               [P01b]___        :
  9                  ::::   [P01c]
       (vines hang 7 to 9 H down to the floor)
  2                                [G3]______
  1                  [G2]________/
  0  [G1]___________/
```

Spawn areas [proposal]:
- Floor: 8 Orange Mushrooms, 3 Red Snails, 2 Snails and 2 Blue Snails.
- Shelf: 9 Snails, 2 Orange Mushrooms and 2 Red Snails.
- Ridge meadow P05: 3 Snails, 2 Orange Mushrooms and 1 Blue Snail.
- Entry bluff: 1 Snail.

---

## 7. Version notes

- [V40] has 121 footholds against 139 in v8 (the 18 dropped footholds have no new flats) and 3 extra vines. The mob list is identical.
- [D] (v8 and v22) returns the portal as `null`. [WZ] gives it in full.

## 8. Open questions

- Should MisoStory keep the "descent-only" feel? The v8 return trip needs two long vine climbs. [V40] later added a direct vine at x -96 back up to the entry.
