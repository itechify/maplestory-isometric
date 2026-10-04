# 40000 Snail Hunting Ground I (`SnailHuntingGround1_40000`)

Phase-1 structural analysis and 3D-translation brief. Machine-readable companion: [`40000.struct.json`](40000.struct.json).

> **SUPERSEDED PORTAL POSITION (verification fix pass).** This brief first gave east00 at (2812,397), taken from the out-of-era parsed API `/api/GMS/39/map/40000` because the parsed v8 entry is null. The raw GMS v8 WZ node `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/000040000.img/portal/6` gives **east00 = (2692,392)** -> 40001:west00, 120 px further west, still on T22. The portal table and sketch below have been corrected. The authoritative portal table is `docs/topology.json`.

**Provenance labels used below**
- Unlabelled numbers come from the data: `docs/research/raw/gms_v8/40000.json` (maplestory.io `/api/GMS/8/map/40000`). Other sources are cited inline.
- **[minimap]**: read from the v8 minimap image. Map px = minimap px × 16 − `miniMap.center` (centerX 350, centerY 1021, magnification 4). Accuracy is about ±50 px.
- **[render]**: read from `ref_renders/v8_40000_render.png`.
- **[memory]**: recalled from memory, not checked against a source.
- **[proposal]**: a design suggestion.
- **[inferred]**: a conclusion drawn from the data that the data does not state directly.

All units are MapleStory px (y increases downward). Sizes are given as px or tier counts only.

| Field | Value |
|---|---|
| Street / name | Maple Road / Snail Hunting Ground I |
| isTown | false |
| BGM | `Bgm00/RestNPeace` |
| mapMark | MushroomVillage |
| returnMap | 60000 (Southperry) |
| Foothold count | 265 |
| Footholds extent | x −309 .. 2919 (3228 px), y −805 .. 600 |
| Walkable surfaces | y −805 (top islet) .. 395 (ground floor), so 1200 px of vertical play. The y 395..600 range contains only the map-edge walls that run down under the ground. |

---

## 1. Structure

### 1.1 Grid
Every tier sits on MapleStory's standard 90 px horizontal tile module and 60 px vertical step module:
- Every ground step is exactly 60 px.
- Floating blocks are 168 px long (2 tiles minus the edge pieces).
- Neighbouring blocks are separated by 12 px seams, which a player crosses in one hop.
- Every ledge end has a 25 px "lip" wall. The lip is the visible edge of the tile, not a barrier: players walk off ledge ends and fall.

### 1.2 Vertical layering (5 bands)
| Band | y range | Tiers |
|---|---|---|
| Top | −805 | T0 (islet) |
| Upper | −505 .. −685 | T1, T3 (long ledges) + stair blocks T6, T5, T4, T2 |
| Mid | −145 .. −325 | T7, T10, T8 (ledges) + T12, T11, T9 (blocks) |
| Low | 35 | T13 |
| Ground | 215 .. 395 | One continuous foothold chain from x −309 to 2919: T15, T18, T21, T19, T16, T14, T17, T20, T22 |

### 1.3 Tiers
Tier IDs are those used in the struct.json, sorted from the top down. "Len" is the horizontal length.

| ID | Label | x range | y (L → R) | Len | Kind | Connects to |
|---|---|---|---|---|---|---|
| T0 | top islet | 321..489 | −805 | 168 | floating | rope x453 down to the T1 hump |
| T1 | upper-west ledge with hump | −129..1479 | −625; hump −685 at x 270..720 (two 90 px ramps: 180→270 up, 720→810 down) | 1608 | slope | ladder x395 and ropes x−51/x873 down; rope x453 up to T0. East end (−625) overhangs T5/T6 across a 12 px seam, 60/120 px above them |
| T2 | upper stair block 4 | 1671..1839 | −685 | 168 | floating | 12 px seam to T3 (same height); 60 px above T4 |
| T3 | upper-east ledge | 1851..2649 | −685 | 798 | ledge | ladder x2585 and rope x2520 down to T8 |
| T4 | upper stair block 3 | 1581..1749 | −625 | 168 | floating | 60 px below T2, 60 px above T5 |
| T5 | upper stair block 2 | 1491..1659 | −565 | 168 | floating | stacked 60 px above T6 |
| T6 | upper stair block 1 | 1491..1659 | −505 | 168 | floating | rope x1530 down to T10 |
| T7 | mid-west ledge | −309..669 | −325 (x ≤ 0) → −265 (x 90..540) → −205 (x 630..669) | 978 | slope | starts at the west map edge; ladder x395 and rope x−51 up to T1; east end drops 60 px onto T12 |
| T8 | mid-east ledge | 2391..2919 | −325 | 528 | ledge | reaches the east edge; ladder x2585 and rope x2520 up to T3; 12 px seam to T9 (60 px up) |
| T9 | mid-east stacked block (upper) | 2211..2379 | −265 | 168 | floating | stacked 60 px above T11 |
| T10 | central mid ledge | 771..2019 | −205 | 1248 | ledge | ropes x873 (up to T1) and x1530 (up to T6); ladders x1335/x1418 down to the hilltop; one-way ropes x1867/x1913 |
| T11 | mid-east stacked block (lower) | 2211..2379 | −205 | 168 | floating | rope x2270 down to T13 |
| T12 | stepping block | 591..759 | −145 | 168 | floating | 12 px seam to T10, 60 px up |
| T13 | low ledge over the east ground | 2211..2559 | 35 | 348 | floating | ladder x2496 down to T22 (360 px above it); rope x2270 up to T11 |
| T14 | hilltop | 1311..1659 | 215 | 348 | ground | ladders x1335/x1418 up to T10 |
| T15 | west entry plateau | −309..309 | 275 | 618 | ground | arrival in00, spawn points, Robin; 60 px step down to T18 |
| T16 | knoll, west step 2 | 1221..1311 | 275 | 90 | ground | 60 px steps to T19/T14 |
| T17 | knoll, east step 2 | 1659..1749 | 275 | 90 | ground | 60 px steps |
| T18 | plateau step-down | 309..399 | 335 | 90 | ground | 60 px steps |
| T19 | knoll, west step 1 | 1131..1221 | 335 | 90 | ground | 60 px steps |
| T20 | knoll, east step 1 | 1749..1839 | 335 | 90 | ground | 60 px steps |
| T21 | west basin floor | 399..1131 | 395 | 732 | ground | lowest ground |
| T22 | east ground floor | 1839..2919 | 395 | 1080 | ground | east00 exit; ladder x2496 |

**Walls and cliffs**
- The ground chain has eight 60 px step walls: down at x 309 and 399; up at x 1131, 1221 and 1311; down at x 1659, 1749 and 1839. Together they form one **symmetric stepped knoll**: base x 1131..1839 (708 px), top 348 px wide, 180 px high, three steps up on each side. It is the most recognisable ground feature.
- Map-edge walls stand at x −309 (west, from y 275 down) and x 2919 (east, from y 395 down). T7 (mid) and T8 (mid) also touch the west and east edges respectively.
- There are no pits in the ground. The west plateau sits 120 px above the basin.

### 1.4 Ladders and ropes (13 total: 5 ladders, 8 ropes)
| x | y1 → y2 | Type | Bottom tier → top tier | Bottom gap | Note |
|---|---|---|---|---|---|
| −51 | −623 → −365 | rope | T7 → T1 | 40 | |
| 395 | −683 → −267 | **ladder** | T7 → T1 (hump) | 2 | longest climb, 416 px |
| 453 | −803 → −687 | rope | T1 (hump) → T0 | 2 | |
| 873 | −623 → −277 | rope | T10 → T1 | 72 | jump to grab |
| 1335 | −203 → 98 | **ladder** | T14 → T10 | 117 | jump to grab (borderline) |
| 1418 | −203 → 186 | **ladder** | T14 → T10 | 29 | |
| 1530 | −503 → −207 | rope | T10 → T6 | 2 | |
| 1867 | −203 → −7 | rope | (T22) ← T10 | **402** | descend only |
| 1913 | −203 → 113 | rope | (T22) ← T10 | **282** | descend only |
| 2270 | −203 → 33 | rope | T13 → T11 | 2 | |
| 2496 | 37 → 393 | **ladder** | T22 → T13 | 2 | |
| 2520 | −683 → −367 | rope | T8 → T3 | 42 | |
| 2585 | −683 → −327 | **ladder** | T8 → T3 | 2 | |

"Bottom gap" is the distance from the rope's lower end to the floor below it. The reachability thresholds are an **[estimate]** based on recalled MapleStory physics **[memory]** (jump apex about 70–80 px): gaps up to about 120 px can be grabbed with a jump; larger gaps mean the rope can only be used going down.

**Climb routes up from the ground**
- **East route:** ladder x2496 to T13 → rope x2270 to T11 → hop up to T9 → hop across the seam to T8 → ladder x2585 to T3.
- **Centre route:** from the hilltop, ladders x1335/x1418 to T10 → rope x1530 to T6 → stair blocks T6 → T5 → T4 → T2 → T3; or rope x873 to T1 → rope x453 to T0.
- **West route:** T7 cannot be reached from the ground. It is entered from above, by dropping or climbing down ladder x395 or rope x−51 from T1.

---

## 2. Portals (7 entries in v8; 1 of them null in the parsed API JSON, all 7 present in the raw WZ)
| Name | Type | x, y | Target | Status |
|---|---|---|---|---|
| in00 | 1 (invisible) | −172, 278 | arrival point of **30000 out00** (from `raw/gms_v8/30000.json`: out00 at 1433,−924 → 40000:in00) | from data |
| east00 | 2 (visible) | **2692, 392** | **40001:west00** | **[data]** Raw v8 WZ node `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/000040000.img/portal/6` (compiled in `docs/research/portals_xml.json`); on T22, 227 px from the east edge. *Superseded draft value: (2812, 397) from the out-of-era parsed API `/api/GMS/39/map/40000` (v39 moved it 120 px east).* |
| sp ×5 | 0 | x −213..1, y ≈ 182 | — | spawn points above T15 (not exits) |

**Edge exits:** the west edge (T15 near x −172) is the arrival point from East Entrance to Mushroom Town. The east edge exit is east00 on T22 at x 2692 (v8 WZ). **[inferred]** No visible portal back to 30000 appears in v8, v22 or v28–v39 data: the only west-side portal is the type-1 arrival point in00. That makes the entry from Mushroom Town one-way; the way out is east00 (or the return map, Southperry). MapleStory Classic data also lists 30000 and 40001 as this map's neighbours (https://meowdb.com/msclassic/maps/000000040), but that site reflects a later revision.

---

## 3. Spawns
| Mob | id (level, from `/api/GMS/8/mob/<id>`) | Count | By tier |
|---|---|---|---|
| Snail | 100100 (lvl 1, 8 HP) | 33 | T1 ×7, T21 ×5, T22 ×5, T3 ×5, T7 ×4, T8 ×3, T10 ×3, T13 ×1 |
| Blue Snail | 100101 (lvl 2, 15 HP) | 16 | T22 ×3, T10 ×3, T21 ×2, T7 ×2, T1 ×2, T3 ×2, T13 ×1, T8 ×1 |

Spawns are spread over every band except the top islet and the stair blocks. Per band: ground 15, low 2, mid 16, upper 16.

| NPC | id | x, y | Tier | Notes |
|---|---|---|---|---|
| Robin | 2003 | 69, 275 | T15 | Walk area x 19..119. Dialogue (https://maplestory.io/api/GMS/8/npc/2003): "You need to time the attack right to take down the monsters easily." / "The town you just saw is called Mushroom Town. You'll also find places called Southperry and Amherst on this island." |

---

## 4. Visual reference
**Terrain tiles [render]:** grass-topped olive-brown dirt with a cobbled-earth texture. The grass edge is a bright green fringe. A few grey-green rocks are embedded in the dirt faces of T1, T3 and T7. Floating ledges have ragged, tapered undersides; the ground band is a solid earth mass down to the bottom of the map.

**Objects [minimap]** (the render omits them):
- West plateau: a cluster of yellow-leaved, white-trunked (birch-like) autumn trees at x ≈ −14..338, and a small orange sapling at x ≈ −120.
- Basin: a yellow autumn tree at x ≈ 660..930, plus grass tufts.
- East foot of the knoll: an orange sapling at x ≈ 1900.
- East meadow: a large orange autumn tree and a green bush at x ≈ 2610..2914.
- T1: a small tree at x ≈ 140; an orange tree and bush beside the hump at x ≈ 900.
- T3: two round green bushes at x ≈ 2210..2530.
- T7: a bright green sprout at x ≈ −170; yellow tufts/flowers at x ≈ 100..350.
- T10: an orange tree, a red-leaf tree and bushes at x ≈ 1000..1330; a large bush at x ≈ 1810.
- T8: a bush at x ≈ 2520.
- The ropes and ladders appear in the minimap as thin dark vertical lines.

**Likely missing from the render [memory]:**
- The parallax background (bright sky with clouds and distant green hills, typical of the Maple Island fields).
- Tree and bush sprites (confirmed by the minimap).
- Rope and ladder sprites, portal sprites, Robin and the mobs.

---

## 5. What makes this map recognizable
- **Data:**
  - The symmetric **stepped knoll** in the middle of the ground (3 × 60 px steps up and 3 down).
  - A raised west entry plateau with Robin standing beside the arrival point.
  - A long upper-west ledge with a **trapezoid hump**, and a tiny islet floating above it.
  - A **four-block staircase** linking the two upper ledges.
  - Two dangling ropes over the east meadow that only go down.
  - Snails and Blue Snails only, with the calm "Rest N Peace" BGM.
- **[minimap]:** autumn colour (orange and yellow trees with white trunks) mixed with round green bushes.
- **[memory]:** this is the first hunting field after leaving Mushroom Town, where new players kill their first snails.

---

## 6. [proposal] 3D translation (orthographic camera about 40° down, 45° yaw)

**Concept: a terraced autumn hillside wrapped around a valley.** The 2D x axis becomes the main west→east route. Each higher y band steps **back** (away from the camera, "north") as it rises, so all four bands stay visible and the map reads as an amphitheatre rather than an extruded strip.

**Ground band = valley floor (front)**
- **Entry plateau (T15):** a 618 px raised grassy shelf at the front-left.
  - in00 is a path mouth on the west side with Robin beside it.
  - Two 60 px earthen steps (T18) descend into the basin.
- **Basin (T21):** a shallow bowl, 732 px across.
- **Knoll (T19/T16/T14/T17/T20):** a **3-tier stepped mound** with an oval or round plan, so players can also walk *around* it (this adds depth). Base about 708 px, top about 348 px, each tier 60 px. Its back side butts against the cliff of the mid band, which is where the two ladders x1335 and x1418 climb.
- **East meadow (T22):** 1080 px. east00 is at its east end, framed by the large orange tree.

**Low band**
- **T13** becomes a rock shelf (348 px long, 360 px above the meadow) at the back-right of the east meadow. Ladder x2496 is fixed to its front face.

**Mid band = second terrace ring (middle depth)**
- **T7** becomes a ridge path along the back of the west plateau. It descends east in two 60 px ramps, matching the 2D slopes, and ends in a drop onto the stepping stone T12.
- **T10** (1248 px) is the long central terrace behind the knoll.
- **T11/T9** are two stacked boulders (60 px apart) leading to **T8**, the east terrace.
- **One-way ropes x1867/x1913:** hanging vines down T10's cliff. They are descend-only, or can be replaced by a drop-down notch.

**Upper band = back terrace ring (back depth)**
- **T1** is the back-left high terrace with a grassy **mound** (the hump: 450 px long, 60 px high, 90 px ramps).
- **T3** is the back-right high terrace.
- **T6 → T5 → T4 → T2** become a **stone stepping-stair** climbing diagonally up a cliff corner between T1 and T3. Each step is 60 px; the first two are stacked.
- **T0** is a small rock spire 120 px above the mound, reached by rope x453.

**Ladders and ropes**
- Ladders (isLadder=true: x395, x1335, x1418, x2496, x2585) become wooden ladders fixed to cliff faces.
- Ropes become hanging ropes or vines on cliff faces.
- No ramps or stairs need to be invented: every 60 px ground step stays a walk-up or jump-up step (or a short stair).

**Route.** The main line runs along the front: arrival (west) → plateau → basin → over or around the knoll → meadow → east00. The terraces form an optional upper loop:
1. Climb in from either end (east: ladder x2496 chain; centre: knoll ladders).
2. Cross the upper ring via the stone stair.
3. Return down through the west ridge (T7) or the vines.

**Spawns.** Snails and Blue Snails go on every terrace (ground 15, mid 16, upper 16, low shelf 2). Keep the entry plateau free of mobs: the data has none on T15.

**Proportions.** Overall about 3228 × 1200 px in 2D, with 5 bands. Suggested depth split: ground band about 40% of the depth, mid about 30%, upper about 30%; the top islet sits on the upper band.

### 6.1 Top-down sketch [proposal] (screen-left = west / in00; top = back = higher)
```
 BACK (higher)
 +-------------------------------------------------------------------------------------------+
 | UPPER  [T1 high terrace ~~mound~~ (T0 spire)]---------.   b b b b   [T3 high terrace east]  |
 |          |rope-51   H395     |rope873        |1530   '--stair-'        H2585 |2520         |
 | MID    [T7 ridge path >> slopes down E] o T12 [T10 long mid terrace ...]  [T11/T9] [T8 mid-east]|
 |                                    H1335 H1418    (vines 1867/1913 drop)  |2270           |
 | LOW                                                          [T13 rock shelf]              |
 |                                                                H2496                       |
 | GROUND in00>*[T15 plateau Robin]=>steps=>[T21 basin]  ( knoll 3 tiers )  [T22 meadow ]*>east00 |
 +-------------------------------------------------------------------------------------------+
 FRONT (camera side)            WEST ------------------------------------------> EAST
```

### 6.2 Side elevation (from data; rows are walk levels, NOT to vertical scale; 1 char = 50 px)
```
x -309 .. 2919; = flat, / \ slope, H ladder, | rope, P portal (row above its tier), n NPC
  -805 |             ====                                                 | T0
  -685 |           //=========                  ====================      | T1(hump),T2,T3
  -625 |    =======   H       \============== ====               |H       | T1,T4
  -565 |     |        H         |           ====                 |H       | T5
  -505 |     |        H         |           ====                 |H       | T6
  -325 |=======\      H         |            |                ============| T7,T8
  -265 |        \=========\     |            |            =====           | T7,T9
  -205 |                   \= ==========================  =====           | T7,T10,T11
  -145 |                  ====           H H        |       |             | T12
    35 |                                 H H        |     ========        | T13
   215 |   P    n                       ========                H         | T14 (P=in00, n=Robin)
   275 |=============                  ==      ===              H         | T15,T16,T17
   335 |            ===              ===         ===            H   P     | T18,T19,T20 (P=east00, v8 WZ x 2692)
   395 |              ================             =======================| T21,T22
```

---

## 7. Differences in v22 (`docs/research/raw/gms_v22/40000.json`), for reference only
- No T0 islet and no rope x453; the top of the map is −685.
- **No Blue Snails**: 33 Snails only.
- An extra NPC 2005 stands on the hilltop at (1602, 215). Its v22 dialogue says "My name is Sam..." (https://maplestory.io/api/GMS/22/npc/2005).
- Everything else, including the ground, the knoll and the mid and upper ledges, is identical.
- v8 remains the canonical layout.
