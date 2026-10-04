# 40001 Snail Hunting Ground II (`SnailHuntingGround2_40001`)

Phase-1 structural analysis and 3D-translation brief. Machine-readable companion: [`40001.struct.json`](40001.struct.json).

**Provenance labels used below**
- Unlabelled numbers come from the data: `docs/research/raw/gms_v8/40001.json` (maplestory.io `/api/GMS/8/map/40001`). Other sources are cited inline.
- **[minimap]**: read from the v8 minimap image. Map px = minimap px × 16 − `miniMap.center` (centerX 350, centerY 1652). Accuracy is about ±50 px.
- **[render]**: read from `ref_renders/v8_40001_render.png`.
- **[memory]**: recalled from memory, not checked against a source.
- **[proposal]**: a design suggestion.
- **[inferred]**: a conclusion drawn from the data that the data does not state directly.

All units are MapleStory px (y increases downward).

| Field | Value |
|---|---|
| Street / name | Maple Road / Snail Hunting Ground II |
| isTown | false |
| BGM | `Bgm00/RestNPeace` |
| mapMark | MushroomVillage |
| returnMap | 60000 (Southperry) |
| Foothold count | 368 |
| Footholds extent | x −309 .. 2919 (3228 px), y −1165 .. 600 |
| Walkable surfaces | y −1165 (summit) .. 395 (ground), so **1560 px** of vertical play (second tallest of the three Snail grounds; 40002 is taller) |

---

## 1. Structure

### 1.1 Grid
- 90 px horizontal module, 60 px vertical module.
- Almost every floating piece is a **168 px block**.
- Neighbouring blocks either overlap by 78 px with 60 px of vertical separation (you jump up through them) or sit across a 12 px seam.
- **The map has no ladders, only ropes.**

### 1.2 Vertical layering (6 bands, 37 tiers)
| Band | y range | Content |
|---|---|---|
| Summit | −1105 .. −1165 | T0 (888 px summit ledge, top-east) + step T1 |
| Arch / sky | −745 .. −1045 | the "Λ" arch of floating blocks: T11 → T9 → T7 → T5 → **T4 apex (−925)** → T6 → T8 → T10, plus the summit stair T3 → T2 → T1 |
| Upper | −505 .. −685 | T13 (upper-west, 888 px), T12 (upper-east, 798 px), T14, stacked pairs T15/T17 and T16/T18 |
| Mid | −205 .. −445 | T23 (mid-west), T26 + T27 (central mid ledge split by a 12 px seam), T22 (mid-east), central **pillar** of 4 stacked blocks T24/T21/T20/T19 (−265/−325/−385/−445), stacked pair T28/T25 |
| Low | −25 .. 155 | T32 (rope hub), stepping stones T34 → T33 → T30 → T29, shelf T31 |
| Ground | 215 .. 395 | T35 (west meadow + ramp + mesa top), T36 (east field) |

### 1.3 Tiers (main ones; every block is listed in the struct.json)
| ID | Label | x range | y (L → R) | Len | Kind | Connects to |
|---|---|---|---|---|---|---|
| T0 | summit ledge | 2031..2919 | −1165 | 888 | ledge | reaches the east edge; only reachable via the arch → summit stair |
| T1 | summit step | 1851..2031 | −1105 | 180 | floating | 60 px step up into T0 |
| T2, T3 | summit stair | 1671..1839 / 1581..1749 | −1045 / −985 | 168 | floating | each step is 60 px |
| T4 | **arch apex** | 1491..1659 | −925 | 168 | floating | the west leg climbs up to it, the east leg descends from it, the summit stair continues upward |
| T5, T7, T9, T11 | arch west leg | 1311..1479 / 1221..1389 / 1131..1299 / 1131..1299 | −865 / −805 / −745 / −685 | 168 | floating | T11 overlaps the east end of T13 (60 px up) |
| T6, T8, T10 | arch east leg | 1581..1749 / 1671..1839 / 1761..1929 | −865 / −805 / −745 | 168 | floating | T10 overlaps T12 (60 px down) |
| T12 | upper-east ledge | 1851..2649 | −685 | 798 | ledge | rope x2520 down to T22 |
| T13 | upper-west ledge | 321..1209 | −625 | 888 | ledge | rope x412 down to T23 |
| T14 | arch east foot | 1671..1839 | −625 | 168 | floating | 12 px seam to T12 (60 px up) |
| T15 / T17 | west stacked pair | 1221..1389 | −565 / −505 | 168 | floating | T15 reaches T13 across a 12 px seam (60 px up) |
| T16 / T18 | east stacked pair | 1491..1659 | −565 / −505 | 168 | floating | rope x1530 from T18 down to T27; T16 reaches T14 across a seam |
| T19..T24 (T19, T20, T21, T24) | **central pillar** of 4 stacked blocks | 1311..1479 | −445 / −385 / −325 / −265 | 168 | floating | sits directly above the east end of T26; jump up through it |
| T22 | mid-east ledge | 2391..2919 | −325 | 528 | ledge | reaches the east edge |
| T23 | mid-west ledge | 51..759 | −265 | 708 | ledge | 12 px seam to T26 (60 px down) |
| T25 / T28 | mid-east stacked pair | 2211..2379 | −265 / −205 | 168 | floating | rope x2270 from T28 down to T31 |
| T26 | central mid ledge, west half | 771..1479 | −205 | 708 | ledge | rope x997 down to T32 |
| T27 | central mid ledge, east half | 1491..2019 | −205 | 528 | ledge | 12 px seam to T26 (same height); rope x1867 down to T33 |
| T29, T30, T33, T34 | low stepping stones | 2031..2199 / 1941..2109 / 1761..1929 / 1671..1839 | −25 / 35 / 95 / 155 | 168 | floating | climb east-up from the mesa top in 60 px steps |
| T31 | low shelf | 2211..2559 | 35 | 348 | floating | rope x2383 down to the ground |
| T32 | low rope hub | 861..1029 | 95 | 168 | floating | ropes x918 (ground) and x997 (T26) |
| T35 | west ground + ramp + mesa | −309..1659 | 395 (x ≤ 1080) → ramp to 215 at x 1350 (270 px run, 180 px rise, 3 × 60 px segments) → 215 to x 1659 | 1968 | slope | at x 1659 a **sheer 180 px cliff** drops to T36 |
| T36 | east field | 1659..2919 | 395 | 1260 | ground | east00 |

**Walls and cliffs**
- The only ground cliff is the **180 px east face of the mesa at x 1659**: a single wall, not steps.
- Map edges at x −309 and 2919. T0, T22 and T36 touch the east edge.

### 1.4 Ropes (8; no ladders)
| x | y1 → y2 | Bottom tier → top tier | Bottom gap |
|---|---|---|---|
| 412 | −623 → −302 | T23 → T13 | 37 |
| 918 | 97 → 353 | T35 (ground) → T32 | 42 |
| 997 | −203 → 93 | T32 → T26 | 2 |
| 1530 | −503 → −219 | T27 → T18 | 14 |
| 1867 | −203 → 95 | T33 → T27 | 0 |
| 2270 | −203 → 33 | T31 → T28 | 2 |
| 2383 | 37 → 356 | T36 (ground) → T31 | 39 |
| 2520 | −683 → −367 | T22 → T12 | 42 |

All ropes can be climbed in both directions; none has a bottom gap above 42 px.

**Climb routes**
- **West:** ground → rope x918 → T32 → rope x997 → T26 → hop up to T23 → rope x412 → T13 → into the arch's west leg.
- **Centre:**
  1. T26 → jump up the 4-block pillar (T24 → T21 → T20 → T19).
  2. Take the stacked pairs to either T13 or T14/T12.
  3. Alternatively, T27 → rope x1530 → T18.
- **Mesa:** ramp → mesa → stepping stones T34 → T33, then either rope x1867 up to T27, or continue T30 → T29 → drop to T31.
- **East:** east field → rope x2383 → T31 → rope x2270 → T28 → T25 → T22 → rope x2520 → T12 → arch east leg → apex → summit stair → **summit T0**.

---

## 2. Portals (7 entries in v8, 2 of them null)
| Name | Type | x, y | Target | Status |
|---|---|---|---|---|
| west00 | 2 | −219, 393 | **40000:east00** | **[data]** Confirmed by the raw v8 WZ node `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/000040001.img/portal/5` (verification fix pass). *This brief first took the same values from the out-of-era parsed API `/api/GMS/40/map/40001` because the parsed v8 entry is null.* |
| east00 | 2 | 2792, 395 | **40002:west00** | **[data]** Confirmed by the raw v8 WZ node `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/000040001.img/portal/6` (verification fix pass). *This brief first took the same values from `/api/GMS/34/map/40001` and `/39/` because the parsed v8 entry is null.* |
| sp ×5 | 0 | x −219..−4, y ≈ 315 | — | spawn points above the west ground |

**Edge exits:** both exits are at ground level, at the far west (x −219) and far east (x 2792) ends. The two nulls in the parsed v8 JSON correspond exactly to west00 and east00; the raw v8 WZ has both.

---

## 3. Spawns
| Mob | id (level) | Count | By tier |
|---|---|---|---|
| Snail | 100100 (lvl 1) | 43 | T36 ×7, T13 ×6, T35 ×5, T12 ×5, T23 ×5, T22 ×4, T26 ×4, **T0 ×4**, T15 ×1, T27 ×1, T31 ×1 |
| Blue Snail | 100101 (lvl 2) | 24 | T35 ×4, **T0 ×4**, T36 ×3, T27 ×3, T31 ×2, T13 ×2, T12 ×2, T26 ×1, T23 ×1, T22 ×1, T1 ×1 |

Total 67 (the densest of the three Snail grounds). The summit T0 holds 8 spawns, which makes it a reward area. No NPCs.

---

## 4. Visual reference
**Terrain tiles [render]:** the same grass-topped olive-brown dirt set as 40000, with a few embedded rocks on the faces of T13 and T12. The arch, pillar and stair blocks are all small 168 px grass-capped earth lozenges. The mesa is a solid earth block with a 45°-looking grassy ramp on its west side and a vertical east face.

**Objects [minimap]:**
- **West meadow:**
  - **White picket fences** at x ≈ −222..−30 and at the foot of the ramp, x ≈ 866..1138.
  - A **dense grove** of yellow and orange autumn trees at x ≈ −140..480, with more yellow trees at x ≈ 630..910.
  - An **unidentified flat, light-coloured object with a dark shadow beneath it**, at ground level, x ≈ 444..642. It could be a log or stump, a small bridge or a hole cover; it cannot be identified at minimap resolution.
- **Mesa top:** a yellow autumn tree at x ≈ 1500.
- **East field:** a bush and an orange sapling below the cliff (x ≈ 1820), yellow trees (x ≈ 2300..2600), and a teal-leaved tree with a bush (x ≈ 2760).
- **T13:** an orange tree with bushes (x ≈ 800..1000).
- **T23:** yellow tufts/flowers (x ≈ 100..350).
- **T26:** an orange tree and a red-leaf tree (x ≈ 1060..1330).
- **T27:** a bush (x ≈ 1810).
- **T12:** green bushes (x ≈ 2190..2510).
- **T22:** a bush (x ≈ 2760).
- **Summit T0:** a **grove of yellow, orange and teal trees** (x ≈ 2370..2820), which makes it visibly the "top prize".

**Likely missing from the render [memory]:** the sky and hill parallax background, trees and fences (confirmed by the minimap), rope sprites, portal sprites and mobs.

---

## 5. What makes this map recognizable
- **Data:**
  - The **"Λ" arch of floating blocks** in the centre of the sky, with a vertical **4-block pillar** under it and a block stair continuing to a **summit ledge with its own grove** at the top-right.
  - A long flat west meadow that ends in a **grassy ramp up onto a mesa**, which then drops off a **sheer cliff** into the east field.
  - A map built entirely from ropes (no ladders).
- **[minimap]:** white picket fences and a dense autumn grove at the west entrance.

---

## 6. [proposal] 3D translation

**Concept: the Arch Rock.** The centre of the map becomes one big rock massif: a natural stone arch whose legs and summit spur are wrapped by a **spiral of 168 px ledge-steps**, rather than literal floating lozenges. Ledge steps rise 60 px each and cover a 90 px tread offset, matching the data. The rest of the map frames the massif as a horseshoe of terraces, so the player circles it in depth instead of only moving left to right.

**Ground (front)**
- **West meadow** (T35 flat part, 1389 px) along the front, fenced on its outer (south) edge, with the grove near west00.
- **Ramp:** 270 px run, 180 px rise. It climbs onto the **mesa** (309 px top), a promontory jutting toward the camera.
- **Mesa east face:** a 180 px sheer cliff dropping into the **east field** (1260 px), which leads to east00.
- The unidentified flat object at x ≈ 450..640 should be kept as a small ground prop once identified.

**Low band (just behind the ground)**
- **T32** becomes a rock knob with two ropes: down to the meadow and up to the mid terrace.
- **T34 → T33 → T30 → T29** become stepping stones climbing out of the mesa's back side, going east and up. They end above the **T31** shelf, which has a rope down to the east field.

**Mid band (middle depth)**
- **T23 + T26 + T27** become one continuous curved mid terrace behind the meadow. The 12 px seam at x 1479/1491 is where the **pillar** (T24 → T19, 4 × 60 px) rises out of the terrace, as a column-like rock with jump-up ledges cut into it.
- **T28/T25 → T22** become the east mid terraces.

**Upper band and arch (back)**
- **T13** (upper-west) and **T12** (upper-east) are high terraces left and right of the massif.
- The arch's **west leg** (T11, T9, T7, T5) and **east leg** (T6, T8, T10) are ledges spiralling up the massif's flanks. Placing west-leg ledges on the massif's front face and east-leg ledges on its back face gives real depth.
- **T4** is the keystone platform on top of the arch.
- **T3 → T2 → T1** form a narrow stair climbing further back and right to the **summit bluff T0** (888 px, grove, 8 spawns) at the back-right corner, the highest point of Maple Road's Snail grounds after 40002.

**Ropes:** all 8 become hanging ropes or vines on cliff faces, with no conversions to ladders. There are no one-way drops in this map.

**Route.** Main line: west00 → meadow → ramp → mesa → drop off the cliff → east field → east00. Everything above the ground is an optional climb whose payoff is the summit.

### 6.1 Top-down sketch [proposal] (screen-left = west00; top = back = higher)
```
 BACK (higher)
 +----------------------------------------------------------------------------------------------+
 | SUMMIT                                       stair T3>T2>T1 ---> [T0 summit bluff + grove]     |
 | ARCH                     W-leg T11>T9>T7>T5 --( T4 keystone )-- E-leg T6>T8>T10              |
 | UPPER [T13 upper-west terrace]  [T15/T17]   ( PILLAR T24..T19 )   [T16/T18] T14 [T12 upper-east]|
 |            |412                                        |1530                     |2520       |
 | MID   [T23 mid-west]==[T26 mid terrace W]==(pillar foot)==[T27 mid E]  [T28/T25] [T22 mid-east]|
 |                         |997                  |1867             |2270                       |
 | LOW              [T32 knob]          T34>T33>T30>T29 stepping stones   [T31 shelf]            |
 |                     |918                                                 |2383              |
 | GROUND west00>[ meadow: fences, grove ]/ramp/[ MESA ]| cliff 180 |[ east field ]>east00       |
 +----------------------------------------------------------------------------------------------+
 FRONT (camera side)              WEST ----------------------------------------------> EAST
```

### 6.2 Side elevation (from data; rows are walk levels, NOT to vertical scale; 1 char = 50 px)
```
x -309 .. 2919; = flat, / \ slope, | rope, P portal (row above its tier)
 -1165 |                                               ===================| T0
 -1105 |                                           =====                  | T1
 -1045 |                                        ====                      | T2
  -985 |                                      ====                        | T3
  -925 |                                    ====                          | T4 (apex)
  -865 |                                ===== ====                        | T5,T6
  -805 |                               ====     ====                      | T7,T8
  -745 |                             ====        =====                    | T9,T10
  -685 |                             ====          =================      | T11,T12
  -625 |             ==================         ====             |        | T13,T14
  -565 |              |                ==== ====                 |        | T15,T16
  -505 |              |                ==== ====                 |        | T17,T18
  -445 |              |                 =====|                   |        | T19 (pillar)
  -385 |              |                 =====|                   |        | T20
  -325 |              |                 =====|                ============| T21,T22
  -265 |       ===============          =====|            =====           | T23,T24,T25
  -205 |                      ==========================  =====           | T26,T27,T28
   -25 |                          |                 |  ==== |             | T29
    35 |                          |                 |==== ========        | T30,T31
    95 |                       =====             =====        |           | T32,T33
   155 |                         |              ====          |           | T34
   215 |  P                      |     ///======              |       P   | T35 mesa (P=west00 / east00)
   395 |=============================//        ===========================| T35,T36
```

---

## 7. Differences in v22 (`docs/research/raw/gms_v22/40001.json`), for reference only
- 301 footholds instead of 368, but the overall layout is the same: the arch, pillar, summit, mesa and cliff are all present.
- The low stepping stones east of the mesa are arranged slightly differently. v22 has blocks at 1581..1749 @155, 1671..1839 @95, 1761..1929 @35 and 1941..2109 @35.
- Mobs: Snail 44 and Blue Snail 11 (v8: 43 and 24).
- v8 remains the canonical layout.
