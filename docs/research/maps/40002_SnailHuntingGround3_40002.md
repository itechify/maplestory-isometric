# 40002 Snail Hunting Ground III (`SnailHuntingGround3_40002`)

Phase-1 structural analysis and 3D-translation brief. Machine-readable companion: [`40002.struct.json`](40002.struct.json).

> **SUPERSEDED PORTAL POSITIONS (verification fix pass).** This brief was written while both exit portals were null in the parsed v8 JSON. The raw GMS v8 WZ nodes settle them: **west00 = (-19,274)** on T19, `/api/wz/GMS/8/Data/Map/Map/Map0/000040002.img/portal/6`, -> 40001:east00; **east00 = (2822,-1164)** at the east end of summit T3, `.../000040002.img/portal/5`, -> 50000:west00. The portal table, the T24 fallback-exit proposal and the sketches below have been corrected. There is **no** exit at the east end of ground T24. The authoritative portal table is `docs/topology.json`.

**Provenance labels used below**
- Unlabelled numbers come from the data: `docs/research/raw/gms_v8/40002.json` (maplestory.io `/api/GMS/8/map/40002`). Other sources are cited inline.
- **[minimap]**: read from the v8 minimap image. Map px = minimap px × 16 − `miniMap.center` (centerX 350, centerY 1778). Accuracy is about ±50 px.
- **[render]**: read from `ref_renders/v8_40002_render.png`.
- **[memory]**: recalled from memory, not checked against a source.
- **[proposal]**: a design suggestion.
- **[inferred]**: a conclusion drawn from the data that the data does not state directly.

All units are MapleStory px (y increases downward).

| Field | Value |
|---|---|
| Street / name | Maple Road / Snail Hunting Ground III |
| isTown | false |
| BGM | `Bgm00/RestNPeace` |
| mapMark | MushroomVillage |
| returnMap | 60000 (Southperry) |
| Foothold count | 256 |
| Footholds extent | x −309 .. 2919 (3228 px), y −1285 .. 600 |
| Walkable surfaces | y −1285 (summit ridge) .. 395 (ground), so **1680 px** of vertical play: the tallest of the three Snail grounds |

**Relation to 40000:** this map is largely a variant of Snail Hunting Ground I.
- The ground west of x 1659 is identical, as are the five spawn points.
- The mid and upper ledges are nearly identical.
- The differences are a sheer east face on the knoll, a west "chimney" climb, and a **summit ridge** across the top of the map.

This matters for asset reuse.

---

## 1. Structure

### 1.1 Vertical layering (6 bands, 25 tiers)
| Band | y range | Tiers |
|---|---|---|
| Summit ridge | −1165 .. −1285 | T1 (west, −1225), **T0 (centre, −1285, the highest walkable point)**, T2 (step), T3 (east, −1165, reaches the east edge) |
| Chimney | −805 .. −1045 | T6, T5, T4: three stacked blocks above the west end of T7 |
| Upper | −505 .. −685 | T7 (upper-west), T8 (upper-east), stair blocks T11/T10 (stacked) and T9 |
| Mid | −205 .. −325 | T12 (mid-west), T15 (central), T16/T14 (stacked), T13 (mid-east) |
| Low | 35 | T17 |
| Ground | 215 .. 395 | T19, T21, T23, T22, T20, T18 (hilltop), T24 |

### 1.2 Tiers
| ID | Label | x range | y (L → R) | Len | Kind | Connects to |
|---|---|---|---|---|---|---|
| T0 | summit ridge, centre | 1221..2199 | −1285 | 978 | ledge | 12 px seam from T1 (60 px up); 60 px step down to T2 |
| T1 | summit ridge, west | 321..1209 | −1225 | 888 | ledge | **ladder x361** down to T4 |
| T2 | ridge step | 2199..2289 | −1225 | 90 | floating | step down to T3 |
| T3 | summit ridge, east | 2289..2919 | −1165 | 630 | ledge | reaches the east edge; east00 at x 2822 (v8 WZ, §2) |
| T4 | chimney block 3 | 231..399 | −1045 | 168 | floating | rope x296 down to T5 |
| T5 | chimney block 2 | 231..399 | −925 | 168 | floating | rope x355 down to T6 |
| T6 | chimney block 1 | 321..489 | −805 | 168 | floating | rope x453 down to T7 |
| T7 | upper-west ledge | 321..1479 | −685 (x 321..720) → 90 px ramp → −625 (x 810..1479) | 1158 | slope | ladder x395 down to T12; rope x873 down to T15; east end overhangs T10/T11 across a 12 px seam |
| T8 | upper-east ledge | 1851..2649 | −685 | 798 | ledge | ladder x2585 and rope x2520 down to T13 |
| T9 | upper stair block | 1671..1839 | −625 | 168 | floating | seams: up to T8, down to T10 (60 px each) |
| T10 / T11 | stacked stair blocks | 1491..1659 | −565 / −505 | 168 | floating | rope x1530 from T11 down to T15 |
| T12 | mid-west ledge | −309..579 | −325 (x ≤ 0) → −265 (x 90..579) | 888 | slope | starts at the west edge; ladder x395 up to T7. Its east end has **no stepping block to T15**: a 192 px gap with a 60 px drop (40000 has a block there), so treat it as unconnected **[estimate]** |
| T13 | mid-east ledge | 2391..2919 | −325 | 528 | ledge | reaches the east edge |
| T14 / T16 | stacked blocks | 2211..2379 | −265 / −205 | 168 | floating | rope x2270 from T16 down to T17 |
| T15 | central mid ledge | 771..2019 | −205 | 1248 | ledge | ladders x1335/x1418 down to the hilltop; one-way ropes x1867/x1913 |
| T17 | low ledge over the east ground | 2211..2559 | 35 | 348 | floating | ladder x2496 down to T24 |
| T18 | hilltop | 1311..1659 | 215 | 348 | ground | **sheer 180 px east face** at x 1659 |
| T19 | west entry plateau | −309..309 | 275 | 618 | ground | spawn points; west00 at x -19 (v8 WZ) |
| T20, T22 | knoll west steps | 1221..1311 / 1131..1221 | 275 / 335 | 90 | ground | 60 px steps |
| T21 | plateau step-down | 309..399 | 335 | 90 | ground | |
| T23 | west basin | 399..1131 | 395 | 732 | ground | |
| T24 | east ground | 1659..2919 | 395 | 1260 | ground | ladder x2496 |

**Walls and cliffs**
- 60 px ground steps at x 309, 399, 1131, 1221 and 1311.
- A **180 px cliff at x 1659**: the knoll is stepped on its west side and sheer on its east side.
- The summit ridge descends in two 60 px steps toward the east (x 2199 and 2289).
- Map edges at x −309 and 2919. T12 touches the west edge; T3, T13 and T24 touch the east edge.

### 1.3 Ladders and ropes (15 total: 6 ladders, 9 ropes)
| x | y1 → y2 | Type | Bottom tier → top tier | Bottom gap | Note |
|---|---|---|---|---|---|
| 296 | −1043 → −927 | rope | T5 → T4 | 2 | chimney |
| 355 | −923 → −807 | rope | T6 → T5 | 2 | chimney |
| **361** | −1223 → −1047 | **ladder** | T4 → T1 | 2 | top of chimney, onto the ridge |
| 395 | −683 → −267 | **ladder** | T12 → T7 | 2 | |
| 453 | −803 → −687 | rope | T7 → T6 | 2 | foot of chimney |
| 873 | −623 → −277 | rope | T15 → T7 | 72 | jump to grab |
| 1335 | −203 → 98 | **ladder** | T18 → T15 | 117 | jump to grab (borderline) |
| 1418 | −203 → 186 | **ladder** | T18 → T15 | 29 | |
| 1530 | −503 → −207 | rope | T15 → T11 | 2 | |
| 1867 | −203 → −7 | rope | (T24) ← T15 | **402** | descend only |
| 1913 | −203 → 113 | rope | (T24) ← T15 | **282** | descend only |
| 2270 | −203 → 33 | rope | T17 → T16 | 2 | |
| 2496 | 37 → 393 | **ladder** | T24 → T17 | 2 | |
| 2520 | −683 → −367 | rope | T13 → T8 | 42 | |
| 2585 | −683 → −327 | **ladder** | T13 → T8 | 2 | |

**Route to the summit (the only one):**
1. From the ground, either take the hilltop ladders to T15 and rope x873 to T7, or go up the east side (x2496 → x2270 → T14 → T13 → x2585 → T8) and cross T9 → T10/T11. In the second case, rope x1530 drops to T15; from there take rope x873 up to T7.
2. From T7, climb the chimney: rope x453 → T6 → rope x355 → T5 → rope x296 → T4 → ladder x361 → **T1**.
3. Walk east along the ridge: T1 → T0 → T2 → **T3**.

---

## 2. Portals (7 entries in v8; 2 of them null in the parsed API JSON, all 7 present in the raw WZ)
| Name | Type | x, y | Target | Status |
|---|---|---|---|---|
| west00 | 2 | **−19, 274** | **40001:east00** | **[data]** Raw v8 WZ node `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/000040002.img/portal/6` (compiled in `docs/research/portals_xml.json`). It stands on the west entry plateau T19, 290 px in from the west edge, among the spawn points (x −213..1). *Superseded draft value: ≈ (−200, 275), inferred while the parsed API entry was null.* |
| east00 | 2 | **2822, −1164** | **50000:west00** | **[data]** Raw v8 WZ node `.../000040002.img/portal/5`. It stands at the east end of summit T3 (2289..2919 @ −1165), 97 px from the east edge. *Superseded draft value: ≈ (2800, −1165), inferred by analogy with v38, plus a T24 fallback candidate that does not exist in v8.* For comparison, v22-v55 move it to (2753, −685) on their upper-east ledge (not used). |
| sp ×5 | 0 | x −213..1, y ≈ 182 | — | spawn points above T19 (identical to 40000) |

---

## 3. Spawns
| Mob | id (level) | Count | By tier |
|---|---|---|---|
| Snail | 100100 (lvl 1) | 36 | T23 ×5, T24 ×5, T0 ×4, T7 ×4, T12 ×4, T1 ×3, T3 ×3, T15 ×3, T8 ×2, T13 ×2, T17 ×1 |
| Blue Snail | 100101 (lvl 2) | 26 | T15 ×3, T24 ×3, T7 ×3, T23 ×2, T12 ×2, T8 ×2, T1 ×2, T0 ×2, T3 ×2, T19 ×2, T17 ×1, T13 ×1, T18 ×1 |
| **Red Snail** | 130101 (lvl 4, 45 HP) | 13 | T3 ×2, T0 ×2, T12 ×2, T7 ×2, T1 ×1, T15 ×1, T24 ×1, T13 ×1, T8 ×1 |

Total 75. The summit ridge (T0–T3) holds 21 of them, 5 of which are Red Snails. This is the first map on the route with **Red Snails**, the strongest mob so far. No NPCs.

---

## 4. Visual reference
**Terrain tiles [render]:** the same grass-topped olive-brown dirt as 40000 and 40001, with embedded rocks on T1, T0 and T7. The summit ridge pieces are thick earth slabs. T3 hangs lower than T0 and has a deeper earth body beneath it, which reads as a stepped cliff-top.

**Objects [minimap]:**
- **West plateau:** a large orange autumn tree (x ≈ 0..290).
- **Basin:** a yellow tree (x ≈ 790).
- **Hilltop:** yellow flowers (x ≈ 1540).
- **East ground:**
  - A bush and an orange sapling at the cliff foot (x ≈ 1820).
  - The same **unidentified flat, light object with a dark shadow** seen in 40001, at ground level (x ≈ 1986..2210).
  - A green sprout (x ≈ 2300) and a teal tree with a bush (x ≈ 2750).
- **T12:** a sprout and yellow flowers.
- **T15:** an orange tree, a red-leaf tree and bushes (x ≈ 1060..1330 and 1810).
- **T7:** an orange tree with bushes (x ≈ 900).
- **T8:** bushes (x ≈ 2110..2550).
- **T13:** a bush (x ≈ 2750).
- **Summit:**
  - Plants on T1 (x ≈ 610..930).
  - A **grove of teal and green birch trees with bushes and orange saplings** on T0 (x ≈ 1350..2080).
  - A yellow, white-trunked tree with flowers on T3 (x ≈ 2400..2690).

**Likely missing from the render [memory]:** the sky and hill background, trees, ropes and ladders, portals and mobs.

---

## 5. What makes this map recognizable
- **Data:**
  - The same west half as Snail Hunting Ground I (plateau, basin, stepped knoll), but the **knoll ends in a sheer east cliff**.
  - A narrow **chimney** of three stacked blocks with short ropes and a ladder at the far west.
  - A **summit ridge** spanning almost the whole map width (x 321..2919) at the very top, where Red Snails roam.
- **[minimap]:** a birch grove on the ridge crest.

---

## 6. [proposal] 3D translation

**Concept: climb the chimney, walk the ridge.** The map's progression is "in at the front-left, up the back-left chimney, along the crest, out at the back-right", so the 3D layout naturally gains depth: the exit is high and far.

**Ground (front)**
- Reuse the 40000 west-half kit: entry plateau T19 → 60 px steps → basin T23 → west steps of the knoll → hilltop T18 (348 px).
- Unlike 40000, the knoll's east side is a **180 px rock face** dropping to the east ground T24 (1260 px). Make that face a visible cliff with exposed rock.
- **T17** becomes a rock shelf at the back-right of the east ground with ladder x2496.

**Mid and upper bands (middle depth):** reuse the 40000 terrace ring.
- **T12** is the west ridge path (ramp −325 → −265). It is a **dead end** toward the centre: the 192 px gap to T15 should stay a visible chasm.
- **T15** is the central terrace behind the knoll, reached by the knoll ladders.
- **T16/T14 → T13** are the east terraces.
- **T7** is the high west terrace with its 60 px ramp.
- **T11/T10 → T9 → T8** form the stone stair to the high east terrace. This version has three steps; 40000's has four.

**Chimney (back-left)**
- **T6, T5, T4** become three ledges inside a vertical crack or chimney in the back-left cliff. Each 116 px rope between them becomes a short rope or ladder pitch, and ladder x361 (176 px) tops out on the crest.
- This is the map's single "gate" to the summit, so it should read clearly from below, for example with a rope ladder and a banner.

**Summit ridge (back, skyline)**
- **T1 → T0 → T2 → T3** become a continuous crest path running along the very back of the map: 888 + 978 + 90 + 630 px, with one 60 px step up and two 60 px steps down.
- Plant the birch grove on T0 and the yellow tree on T3.
- Put the east exit (east00 → A Split Road) at the far east end of T3 (v8 WZ: (2822, −1164)) as a gap in the crest leading over the hill. The ground T24 has no exit; its east end is a wall.

**One-way ropes x1867/x1913:** vines from T15's edge, descend only.

### 6.1 Top-down sketch [proposal] (screen-left = west00; top = back = higher)
```
 BACK (higher)
 +-------------------------------------------------------------------------------------------+
 | RIDGE      H361 [T1 crest west]=[T0 crest centre: birch grove]=T2=[T3 crest east]> east00   |
 | CHIMNEY  [T4]|296                                                                          |
 |          [T5]|355                                                                          |
 |          [T6]|453                                                                          |
 | UPPER   [T7 high west terrace \ramp\ ]  T11/T10>T9>  [T8 high east terrace]                  |
 |            H395          |873       |1530                 H2585 |2520                       |
 | MID  [T12 west ridge path]  (chasm)  [T15 central terrace]  [T16/T14] [T13 mid-east]          |
 |                               H1335 H1418  (vines 1867/1913)  |2270                          |
 | LOW                                                  [T17 shelf]                             |
 |                                                         H2496                                |
 | GROUND west00>[T19 plateau]=>steps=>[T23 basin]=>(knoll W steps, top)|cliff|[T24 east ground] (no exit) |
 +-------------------------------------------------------------------------------------------+
 FRONT (camera side)            WEST ----------------------------------------------> EAST
```

### 6.2 Side elevation (from data; rows are walk levels, NOT to vertical scale; 1 char = 50 px)
```
x -309 .. 2919; = flat, / \ slope, H ladder, | rope, P portal (row above its tier; both portals at their raw v8 WZ positions)
 -1285 |                               ====================               | T0
 -1225 |             ==================                   ===         P   | T1,T2  (P = east00, v8 WZ x 2822)
 -1165 |             H                                      ==============| T3
 -1045 |           ====                                                   | T4
  -925 |           ====                                                   | T5
  -805 |             ====                                                 | T6
  -685 |             =========                     =================      | T7,T8
  -625 |              H       \==============   ====             |H       | T7,T9
  -565 |              H         |           ====                 |H       | T10
  -505 |              H         |           ====                 |H       | T11
  -325 |=======\      H         |            |                ============| T12,T13
  -265 |        \==========     |            |            =====           | T12,T14
  -205 |                      ==========================  =====           | T15,T16
    35 |                                 H H        |     ========        | T17
   215 |      P                         ========                H         | T18 (P = west00, v8 WZ x −19)
   275 |=============                  ==                       H         | T19,T20
   335 |            ===              ===                        H         | T21,T22
   395 |              ================         ===========================| T23,T24
```
(The short ropes between the chimney blocks do not show because adjacent rows have nothing between them.)

---

## 7. Differences in other versions, for reference only
- **v22** (`docs/research/raw/gms_v22/40002.json`, 213 footholds):
  - **No summit ridge and no chimney**; the top of the map is −685.
  - The upper-east ledge runs 1851..2919 @−685 to the east edge.
  - The mid-east area has different blocks (1941..2289 and 2391..2559 @−265; 2031..2199 and 2301..2469 @−205; 2571..2919 @−325).
  - Mobs: Snail 25, Blue Snail 15, **Red Snail 1** (v8: 36, 26, 13).
- **v38** (https://maplestory.io/api/GMS/38/map/40002, 228 footholds): close to v22, and its east00 sits at (2753, −685) on that upper-east ledge.
- v8 (the version with the summit) remains the canonical layout.
