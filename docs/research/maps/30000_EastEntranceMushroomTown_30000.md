# Map 30000: "East Entrance to Mushroom Town". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/30000.struct.json`

**Tags used in this brief**
- No tag: a fact taken from data. The source is given.
- **[inference]**: my reading of the data.
- **[memory]**: something I remember about the game, unsourced.
- **[proposal]**: a design suggestion.

**Sources**
- `docs/research/raw/gms_v8/30000.json`, from `https://maplestory.io/api/GMS/8/map/30000`.
  - This is the only one of the five maps whose API JSON has no `null` portal.
  - out00 (1433,-924) leading to 40000:in00 also matches raw WZ `https://maplestory.io/api/wz/GMS/8/Map/Map/Map0/000030000.img/portal/2`.
- Objects come from `.../000030000.img/<layer>/obj/<n>`.
- Sprites were viewed at `https://maplestory.io/api/wz/GMS/8/Map/Obj/...`, in a temp folder only.
- NPC: `https://maplestory.io/api/GMS/8/npc/2002`.
- Renders: `ref_renders/v8_30000_render.png` and `v8_30000_minimap.png`.
- Version comparison:
  - `raw/gms_v22/30000.json`.
  - `https://maplestory.io/api/GMS/22/mob/9300018`.
  - `https://maplestory.io/api/GMS/22/npc/2004`.

## 0. Map card

| field | value (v8) |
|---|---|
| Street / name | "Maple Road" / "East Entrance to Mushroom Town" |
| isTown / returnMap | `true` / `30000` |
| BGM / mapMark | `Bgm00/FloralLife` / `MushroomVillage` |
| Foothold extent | x -309..1569 (1878 px). **Walkable y runs -925..215: 1140 px, which is 19 tiers of 60 px.** Wall bottoms reach y=420. |
| Walkable tiers | 22 |
| Ladders and ropes | 4: 2 ladders and 2 ropes. |
| Mobs | none in v8 |
| Portals | in00 is the arrival point at the bottom-west. out00 is at the **top-east summit** and leads to 40000 (Snail Hunting Ground I). |

This is the tallest of the five maps and the island's first real vertical climb. It ends at the exit from the tutorial town.

## 1. Structure

### 1.1 Tiers

"Units" counts steps of 60 px above G1 (y=215). **Every tier in this map sits exactly on that 60 px grid.**

| id | kind | x-range | y | length | units | footholds | connects to |
|---|---|---|---|---|---|---|---|
| G1 | ground (west valley floor) | -309..231 | 215 | 540 | 0 | 42,2,43,34,1,4,3,7 | West wall x=-309 (map edge). Ladder x=-136 up to W1. Rises 60 px at x=231 to G2. |
| G2 | ledge (hill step W) | 231..321 | 155 | 90 | +1 | 9,6,10 | Rises to G3 at x=321. |
| G3 | ledge (hilltop, yellow house) | 321..939 | 95 | 618 | +2 | 13,14,15,17,19,16,5,35,36 | Drops 60 px at x=939 to G4. |
| G4 | ledge (hill step E) | 939..1119 | 155 | 180 | +1 | 39,23,20 | Drops 60 px at x=1119 to G5. |
| G5 | ground (east valley floor) | 1119..1569 | 215 | 450 | 0 | 24,26,25,30,33,27 | Rope x=1434 up to E1. East wall x=1569 (map edge). |
| W1 | floating islet | -219..-51 | -25 | 168 | +4 | 101,104,102 | Ladder x=-136 down to G1. |
| W2 | floating islet | -129..39 | -85 | 168 | +5 | 106,109,107 | Overlaps W1 and W3 in x. |
| W3 | floating islet | -39..129 | -145 | 168 | +6 | 59,57,60,55 | **Dead end.** M3 is 300 px higher; M3's underside wall bottoms out at y=-300. |
| E1 | floating islet | 1311..1479 | -25 | 168 | +4 | 91,94,92 | Rope x=1434 down to G5. Rope x=1359 up to E2. |
| E2 | floating islet | 1311..1479 | -265 | 168 | +8 | 62,65,63 | Hop west to E3. |
| E3 | floating slab | 951..1299 | -325 | 348 | +9 | 71,72,69,68,66 | Hop west to M1. |
| M1 | floating slab, east part (low) | 630..939 | -385 | 309 | +10 | 87,76,75,73 | M2 to the west. |
| M2 | slope | 540..630 | -445→-385 | 90 run, 60 rise | +11→+10 | 88 | Joins M3 to M1. |
| M3 | floating slab, west part (high terrace) | -39..540 | -445 | 579 | +11 | 81,83,77,79,85,84,86 | Ladder x=107 up to U1. West face is a wall x=-39 from -445 down to -300 (145 px thick). |
| M4 | floating (log-bench top) | 241..358 | -474→-471 | 117 | about +11.5 | 89 | Sits on M3, 26–29 px up. |
| U1 | floating islet | 51..219 | -625 | 168 | +14 | 111,114,112 | Ladder x=107 down to M3. |
| U2 | floating islet | 141..309 | -685 | 168 | +15 | 117,115,118,119,120 | Overlaps U1 and U3. |
| U3 | floating islet | 231..399 | -745 | 168 | +16 | 98,99,95 | Hop east to U4 (12 px gap). |
| U4 | floating slab | 411..759 | -805 | 348 | +17 | 49,46,50,54,47,51,52 | Hop east to S1 (12 px gap). |
| S1 | floating (summit approach) | 771..1080 | -865 | 309 | +18 | 132,135,136,134 | S2 to the east. |
| S2 | slope | 1080..1170 | -865→-925 | 90 run, 60 rise | +18→+19 | 133 | Joins S1 to S3. |
| S3 | floating (summit) | 1170..1569 | -925 | 399 | +19 | 129,128,127,122,123,124 | Peter at x=1314, **out00 at x=1433**. East end is a wall x=1569 from -925 down to -780 (map edge). |

**Data-derived constants**
- **Step unit:** every intended hop is exactly **60 px** up.
- **Hop gap:** horizontal gaps between hop targets are **12 px** (for example 1299→1311, 939→951, 399→411, 759→771), or the platforms overlap.
- **Standard islet:** **168 px** wide (W1–W3, E1, E2, U1–U3).
- **Slabs:** 309–579 px.
- **Slopes:** 90 px run for 60 px rise.
- **Climbs:** every rise larger than 60 px has a ladder or rope, of 236 px (4 units) or 176 px (3 units).

**Vertical bands, bottom to top**
1. **Valley**, 0..+2: G1–G5, with a stepped central hill.
2. **Low islets**, +4..+6: W1–W3 in the west and E1 in the east.
3. **Mid band**, +8..+11: E2, E3, then the M1/M2/M3 slab.
4. **Upper stepping stones**, +14..+17: U1–U4.
5. **Summit**, +18..+19: S1–S3.

### 1.2 Ladders and ropes

| x | y1 (top) → y2 (bottom) | type | joins | length |
|---|---|---|---|---|
| -136 | -23 → 213 | ladder | G1 → W1 | 236 px (4 units) |
| 1434 | -23 → 213 | **rope** (`isLadder: false`) | G5 → E1 | 236 px |
| 1359 | -263 → -27 | **rope** | E1 → E2 | 236 px |
| 107 | -623 → -447 | ladder | M3 → U1 | 176 px (3 units) |

The rope sprites are `connect/rope/0` and the ladder sprites are `connect/ladder/0`, both on layer 2.

### 1.3 Route

[inference] This route follows from the 60 px / 12 px pattern and the ladders.

**Main route, alternating east → west → east.** Horizontal travel is about 4,300 px: 1,652 + 75 + 1,252 + 1,326. On top of that come 884 px of ladder and rope climbing.
1. Start at in00 on G1 (bottom-west).
2. Walk east over the hill: G2, G3, G4.
3. Continue to G5.
4. Climb the rope at x=1434 to E1.
5. Climb the rope at x=1359 to E2.
6. Hop west to E3.
7. Hop west to M1.
8. Walk up the M2 slope to M3.
9. Walk west to the ladder at x=107 and climb it to U1.
10. Hop east up U2, U3 and U4.
11. Hop to S1 (signpost).
12. Walk up the S2 slope to S3.
13. Talk to Peter and take out00.

**Side branch:**
- From the ladder at x=-136 you reach W1, W2 and W3.
- They top out 300 px below M3 and lead nowhere.
- [inference] It is a jump-practice or decoy staircase right next to the arrival point.

## 2. Portals

| name | pt | x, y | target | notes |
|---|---|---|---|---|
| sp | 0 | (-77, 122) | n/a | Above G1. |
| **in00** | 1 | (-218, 217) | none (`tm 999999999`) | Arrival point for 20000:out00, 91 px from the west wall, at the bottom. |
| **out00** | 2 | **(1433, -924)** | **40000:in00** | On the summit S3, 136 px from the east wall. It is 1140 px above the arrival point. |

- **Edge exits:**
  - There is no west return portal.
  - The east exit is at the *top-right* of the map, not at ground level. G5's east end at x=1569 is a closed wall.

## 3. Spawns

**Mobs:** **none in v8.** In v22, 3× mob 9300018 "Tutorial Jr. Sentinel" were added (level 1, 8 HP, `noAttack`). They stand at:
- (479,-445) on M3
- (1343,215) on G5
- (690,95) on G3

**NPCs**

| NPC | id | x, y | tier | dialogue (from `/api/GMS/8/npc/2002`) |
|---|---|---|---|---|
| **Peter** | 2002 | (1314, -925), walk area 1264..1364 | S3 summit, 119 px west of out00 | "If you want to move on to the next stage, talk to me." / "This is the exit to the Mushroom Town." / "Be careful...once you leave this place, you'll see monsters roaming around." / "We instructors are all related. Roger, my older brother, and Robin, my younger brother, all work together here." |

v22 also adds **Todd** (2004) at (-21,215) on G1. His lines include "Go to North-East~" and "That was 'Mushroom Town'. There are Amherst and South Perry in this Island".

## 4. Visual reference

### 4.1 Terrain

- **Tiles:** layer 1 holds 286 grassySoil tiles: grass fringe over olive/khaki-brown cobbled dirt with grey stones.
- **What the render shows** (`v8_30000_render.png`):
  - A solid valley floor with a two-step central hill. G3 is a raised block and G2/G4 are its shoulders.
  - Two large floating earth slabs with grassy sloped "shoulders": the M slab, and S1–S3 with its slope.
  - Two medium dish-shaped floating slabs with rounded dirt undersides: E3 and U4.
  - Many small oval floating islets: W1–W3, E1, E2 and U1–U3.

### 4.2 Objects

These come from the WZ object list. They are listed by band.

- **Valley:**
  - Clover-and-flower beds on G1 at (-93,184), (54,185), (-21,188) and (127,188).
  - A **wooden signpost with ivy and an arrow board** on G1 at (77,140), as the first marker.
  - On the hill G3:
    - A **cluster of tall pale stalk mushrooms**, about 300 px tall, at (444,-52) to (444,-108).
    - Grass and a bush.
    - **Two burlap sacks** at (594,69) and (635,67).
    - The **yellow mushroom house** (`houseGS/house7`): cream body anchored at (714,14), roughly x 574..854; yellow cap with a brown rim around y -187..-9; a **yellow mushroom-shaped dormer window** at (755,-154); a mushroom-awning porch with a plank door at about (761,38). The door has **no portal**, so it is decorative.
    - A wall lantern at (830,21).
  - An olive bush on G4 at (960,105).
  - On G5:
    - A **mushroom fountain with a rainbow over a stone basin** at (1229,169).
    - A **second ivy signpost with an arrow** at (1463..1484,140), right by the rope.
- **Low islets:** grass tufts on W3 at (62,-169) and E1 at (1393,-51).
- **E3:** grass tufts at (1125,-350).
- **M slab:**
  - Grass at (171,-468).
  - A **log bench** with tiny mushrooms at (306..309,-476). Its top is the M4 foothold, so [inference] you can stand on it.
  - A green bush at (320,-511), a dark bush at (396,-463) and grass at (468,-469).
  - On the M2/M1 shoulder: a bush and tiny pale mushrooms at (674..716,-405..-451) and an olive bush at (810,-435).
- **U4:** grass and a dark bush at (572..593,-822..-830).
- **S1:** a **signpost with ivy and three arrow boards** at (998..1032,-904..-939). It marks the summit approach.
- **Summit S3:**
  - A big green bush at (1286,-992), behind Peter.
  - A **tall pale stalk-mushroom cluster**, flipped, at (1384,-1074..-1130), between Peter and out00.
  - An olive bush at (1444,-975) next to the exit.
- **Backgrounds:** grassySoil back 0, 1, 2, 3, 5 and 6, as in the other maps.

### 4.3 Missing from the render

- The house, all mushrooms, the fountain, the 3 signposts, the bench, bushes, sacks, ladder and rope sprites, and the sky.
- The minimap (`v8_30000_minimap.png`) confirms the house on the hill, the tall mushrooms at the hill and the summit, the signposts, the fountain, and the ladders and ropes as white strips.

## 5. What makes this map recognizable

- **The big climb out of town.**
  - A 19-tier vertical map.
  - You start at the bottom-left, climb ropes on the right, cross a long middle terrace to the left, take a ladder and stepping stones back to the right, and reach the top-right summit.
  - [memory] For new players this was the first platforming challenge. The "climb to Peter" feeling is the map's identity.
- **Peter on the summit** guarding "the exit to the Mushroom Town", with the warning that monsters wait beyond.
  - In this map's data, in00 is arrival-only, so you cannot go back west to 20000.
  - This map's data cannot show whether 40000 links back here. The sibling brief `docs/research/maps/40000.struct.json` reports no usable return portal in v8, v22 or v28–v39.
  - [memory] Players remember that once you leave Mushroom Town you cannot return.
- **The yellow mushroom house** with its dormer window on the valley hill.
- **The tall pale stalk mushrooms**, one cluster at the bottom and one at the summit, act as vertical landmarks.
- **Smaller props:** the rainbow mushroom fountain, the ivy signposts, and the log bench on the middle terrace.

## 6. 3D translation [proposal]

All of this section is [proposal].

**Concept: "the switchback mountain".**
- The 2D zig-zag (east, west, east) becomes a **switchback climb that wraps into depth** around a central terraced massif.
- The bands move progressively *north*, away from the camera, as they rise. The camera sees the whole ascent stacked like a terraced hill, and the player physically turns at every switchback instead of scrolling along a wall.

**Bands to 3D**
1. **Valley, south/front, 0..+2:**
   - A broad valley floor across the full width, 1878 px along x. Suggested depth 300–400 px.
   - The **house hill** (G2/G3/G4) is a raised grass mound in the middle, south of the cliff line.
     - It has 60 px terraced shoulders on the west and east.
     - The yellow mushroom house sits on its north-east part, facing south.
     - The tall mushroom cluster stands on its west side.
     - The sacks are by the house.
   - in00 is a pad at the far west. The first signpost points east.
   - The fountain is at the east foot of the hill.
   - The second signpost stands at the foot of the **east cliff**.
2. **East cliff with the rope pitches, +4 and +8:**
   - At the valley's east end, the massif's south-east corner rises as a cliff.
   - Two **rope pitches** of 236 px each go up its face.
   - E1 (168 px) is a small grassy rock shelf partway up, at +4. E2 is a second shelf at +8.
   - Ropes hang from wooden stakes at each shelf lip.
3. **Mid terrace, +9..+11, mid-depth:**
   - From E2, two 60 px hops *west* onto E3 (348 px) and M1 (309 px), as stepped rock ledges along the massif's south face.
   - Then the M2 grass ramp (90 px, +60).
   - Then the long **M3 high terrace** (579 px), running west along the massif with a view down onto the valley and the house roof.
   - Put the **log bench** here as a rest spot facing the valley (south).
   - The terrace's west end is a 145 px thick cliff lip above the valley.
4. **Upper stepping stones, +14..+17, further north:**
   - At x≈107 a 176 px ladder climbs the massif's next cliff band to U1.
   - U1 to U3 (168 px each) become **stepping-stone islets or mushroom-cap platforms** rising east.
   - U4 (348 px) is a wider slab.
   - Keep all hops at 60 px up with 12 px gaps, or with overlaps, so the platforming matches the data.
5. **Summit, +18..+19, back/north-east:**
   - S1 is a grassy ridge with the three-arrow signpost.
   - The S2 ramp (90 px) leads up to S3, the summit plateau (399 px), in the north-east corner of the scene.
   - Peter stands at its west part.
   - **out00** is an archway or portal at the east part, framed by the tall stalk mushrooms and the olive bush. Beyond it the path leads to Snail Hunting Ground I.
6. **West islet stair W1–W3, +4..+6:**
   - Floating stepping islets or tree-stump pillars at the valley's west end, beside the arrival point, reached by a 236 px ladder.
   - Since they are a dead end, either make them an optional lookout with a small reward or prop at W3, or a jump-training spot.
   - This fits v22's Todd ("You should attack the monsters with the right timing"), who stands right there.

- **Spawn areas:** in00 and `sp` on G1 only. v8 has no mobs. If the v22 tutorial sentinels are wanted, put one each on G3, G5 and M3, as in v22.
- **Proportions to keep:**
  - The total rise is 19 units against a width of about 31 units (1878/60).
  - The climb should feel *taller than wide* in screen space. Raise the camera bounds rather than compressing the heights.

**Top-down sketch [proposal].** North is up, away from the camera. Screen-left is map west. About 25 px per character along x. Rows move north as the route climbs.
```
 N (back / highest)
 +-----------------------------------------------------------------------------+
 |                        U4 ====> S1[sign] =/S2/= S3 SUMMIT +19 [Peter] (mush) *out00 ==> 40000
 |              U2 > U3 /                                                      |
 |          U1 ^ (ladder x107, 3u)                                             |
 |   cliff  == M3 HIGH TERRACE +11 (bench) ==\M2\== M1 +10 <=hop= E3 +9 <=hop= E2 +8
 |   lip                                                              rope x1359 |
 |  W3+6                                                              E1 +4 shelf|
 |   W2+5    (dead end)                                            rope x1434 |  |
 |  W1+4 ^ladder x-136                                    EAST CLIFF  [sign]     |
 | *in00 sp  [sign]  G1 VALLEY 0  /G2+1  G3 HILL +2 [YELLOW HOUSE] G4+1\ G5 0 (fountain) |
 |  (flowers)            (tall mushrooms)         (sacks)                       |
 +-----------------------------------------------------------------------------+
 S (front / camera, lowest)
```

**Side elevation (map data).** One row is 60 px above G1 (y=215) and one column is 25 px.
- `=` marks a platform and `/` or `\` a slope.
- `H` marks a ladder and `|` a rope.
- `P` is Peter and `*` is a portal.
- The log-bench top (M4, x 241..358) sits about half a unit above M3 and is not drawn.

```
 20 |                                                                   out00
 19 |                                                          /=S3===P====*=====
 18 |                                           =S1==========//
 17 |                             =U4============
 16 |                      =U3====
 15 |                  =U2=====
 14 |              =U1=====
 13 |                 H
 12 |                 H
 11 |           =M3=====================\\
 10 |                                     \\M1==========
  9 |                                                  =E3============
  8 |                                                                 =E2=====
  7 |                                                                   |
  6 |           =W3=====                                                |
  5 |       =W2=====                                                    |
  4 |    =W1====                                                      =E1=====
  3 |       H                                                              |
  2 |       H                 =G3=======================                   |
  1 |  in00 H              =G2=                        =G4=====            |
  0 |=G1=*==================                                  =G5================
    +-----------------------------------------------------------------------------
     -309        0         231         540             939    1119              1569
```

## 7. Version notes

These compare `raw/gms_v22/30000.json` with `raw/gms_v8/30000.json`.

- **Valley:** identical.
- **E2:** moved to x 1221..1389 at y=-385. Its rope moved to x=1342 and now runs y -383..-34.
- **Upper section:** re-laid as islets at -805 (141..309), -745 (231..579), -805 (501..669) and -865 (591..759). A **rope at x=183 (-803..-455)** replaces the ladder at x=107.
- **Added:** NPC Todd (2004) on G1 and 3× Tutorial Jr. Sentinel (9300018).
- **out00 unchanged:** v22 raw WZ `portal/2` is still (1433,-924) and leads to 40000:in00.

This brief follows v8.

## 8. Open questions

- Should the dead-end W1–W3 stair get a purpose, such as a reward or lookout, or stay a pure decoy as in the data?
- Include v22's tutorial sentinels and Todd, or stay with v8's mob-free map?
