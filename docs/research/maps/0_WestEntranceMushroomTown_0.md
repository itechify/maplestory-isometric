# Map 0: "West Entrance to Mushroom Town". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/0.struct.json`

**Tags used in this brief**
- No tag: a fact taken from data. The source file or URL is given.
- **[inference]**: my reading of the data. The data does not state it.
- **[memory]**: something I remember about the game. No source was checked.
- **[proposal]**: a design suggestion for MisoStory.

**Sources**
- `docs/research/raw/gms_v8/0.json`, from `https://maplestory.io/api/GMS/8/map/0`. Supplies footholds, ladders, NPCs and map info.
- Raw WZ nodes. The parsed API JSON has `portals[4] = null`. I recovered that portal from the raw WZ tree:
  - `https://maplestory.io/api/wz/GMS/8/Map/Map/Map0/000000000.img/portal/4` gives `pn=out00 pt=2 tm=10000 tn=in00 x=1052 y=365`.
  - Object lists come from `.../000000000.img/<layer>/obj/<n>`.
  - Backgrounds come from `.../000000000.img/back/<n>`.
- Object sprites were identified by viewing `https://maplestory.io/api/wz/GMS/8/Map/Obj/<oS>.img/<l0>/<l1>/<l2>/0`. I viewed them in a temp folder only and did not copy them into the project.
- NPC names and dialogue: `https://maplestory.io/api/GMS/8/npc/2100` and `/npc/2101`.
- Reference renders, viewed but not copied: `ref_renders/v8_0_render.png` and `v8_0_minimap.png`.
- Version comparison: `docs/research/raw/gms_v22/0.json`.

## 0. Map card

| field | value (v8) |
|---|---|
| Street / name | "Maple Road" / "West Entrance to Mushroom Town" |
| isTown / returnMap | `true` / `0` (itself) |
| BGM | `Bgm00/FloralLife` |
| mapMark | `MushroomVillage` |
| Foothold extent | x -264..1254 (1518 px wide). Walkable y runs 50..365 (315 px). Wall bottoms reach y=570. |
| Walkable tiers | 9 in total: 4 main terrain tiers, 1 raised bluff and 4 small perches. |
| Mobs | **none**. `life` has only 2 NPCs. |
| Exits | 1: `out00` goes east to 10000. There is no west exit. |

## 1. Structure

### 1.1 Tiers

MapleStory y grows downward, so a smaller y is higher. "Units" counts steps of 60 px above T4, the lowest walkway.

| id | kind | x-range | y | length | height above T4 | layer | footholds | connects to |
|---|---|---|---|---|---|---|---|---|
| T1 | ground (west plateau) | -264..354 | 185 | 618 | +180 (3 units) | 2 | 54,28,55,24,23,29,33,36,34 | West end is a wall at x=-264 (map edge). East end drops 60 px at x=354 to T2. |
| T2 | ledge (step) | 354..444 | 245 | 90 | +120 (2) | 2 | 41,38 | Drops 60 px to T3 at x=444. |
| T3 | ledge (step) | 444..534 | 305 | 90 | +60 (1) | 2 | 44,42 | Drops 60 px to T4 at x=534. |
| T4 | ground (lower lane) | 534..1254 | 365 | 720 | 0 | 2 | 45,46,31,47,48,49,51,50,25 | Ladder x=975 up to T5. `out00` is at x=1052. East end is a wall at x=1254 (map edge). |
| T5 | ledge (laundry bluff) | 726..1254 | 125 | 528 | +240 (4) | **0** | 7,4,8,3,10,11,9,12,13 | Reached only by the ladder at x=975. Walls at x=726 (y 125..390) and x=1254. |
| T6 | floating (Heena's perch) | -84..-6 | 65 | 78 | +300 (2 units above T1) | 2 | 66 (walls 65,67) | Nothing. It is 120 px above T1 and has no ladder. |
| T7 | floating (barrel top) | 185..238 | 137→130→135 (domed) | 53 | 48–55 px above T1 | 2 | 62,63,64 | Sits on T1. |
| T8 | floating (barrel top) | 245..282 | 131 | 37 | 54 px above T1 | 2 | 61 | Sits on T1. |
| T9 | floating, sagging (clothesline) | 918..1031 | 50→54→52 | 113 | ~71–75 px above T5 | 0 | 19,20 | Sits over T5. There is no ladder. |

**Walls and cliffs**
- West map wall: x=-264, y 185..570.
- East map wall: x=1254, y 125..570. The data has both the T5 chain and the T4 chain ending on this wall.
- The three step faces at x=354, 444 and 534 are 60 px each.
- The bluff's west face is at x=726 and runs y 125..390, which is 265 px tall.

**Data observation on the bluff's west face**
- That face crosses the height of the T4 walkway (y=365).
- The ladder foot (975,363) and `out00` (1052,365) are both east of the face.
- [inference] Players must be able to walk along T4 past x=726, so T4 runs *in front of* the bluff. The bluff is the back of the scene. The render backs this up: the T4 grass strip is drawn across the foot of the bluff's dirt face. T5 being on layer 0 while T4 is on layer 2 fits this too ([memory] lower layer index is drawn further back).
- I am not asserting the client's wall-collision rules here.

**Pits and gaps:** none. The terrain is one continuous descent from T1 to T4, plus one raised bluff.

**Vertical layering, top to bottom**
- Perches: T9 (clothesline) and T6 (Heena).
- Upper band: T5, the bluff.
- Middle band: T1, the plateau, and the barrel tops T7/T8.
- Steps: T2 and T3.
- Ground: T4, the lane.

**Reachability [inference]**
- Every step that is clearly meant to be walked is 60 px, and the ladder covers 236 px.
- The barrel tops (48–55 px) and the clothesline (~73 px) are probably jumpable, since [memory] a base jump is about 70–80 px.
- Heena's perch (120 px above T1, no ladder) is probably *not* reachable. She is a display NPC you talk to from below.

### 1.2 Ladders and ropes

| x | y1 (top) → y2 (bottom) | type | joins | length |
|---|---|---|---|---|
| 975 | 127 → 363 | ladder (`isLadder: true`; WZ `l=1`) | T4 (bottom) → T5 (top) | 236 px |

The ladder is drawn with 6 sprite segments (`connect/ladder/0/0..3`) at x=975, y 116..344.

## 2. Portals

The API JSON lists 5 entries: 4× `sp` and 1× `null`. I resolved the `null` from raw WZ.

| name | pt | x, y | target | notes |
|---|---|---|---|---|
| sp ×4 | 0 | (-206,102), (-162,103), (-127,101), (-112,101) | n/a | Spawn points about 80 px above the west end of T1. The character drops onto T1. |
| **out00** | 2 | **(1052, 365)** | **10000:in00** | On T4, 202 px short of the east wall and 77 px east of the ladder foot. Raw WZ source given above. |

- **Edge exits:**
  - There is no west exit. The west edge is a dead end and the map is the start.
  - The only exit sits on the *low* lane (T4), not on the bluff, even though both run all the way to x=1254. Climbing to the bluff is optional.
- **Portal types:** [memory] `pt 0` is a spawn point and `pt 2` is a visible portal that you enter with ↑.
- **New-character start:** [memory] new characters were created into this map while it existed in this form. The data fits: 4 `sp`, `returnMap` is itself, there are no mobs, and the NPCs give tutorial dialogue.
- **Which versions have this map:** the maplestory.io data has this map 0 in GMS v8 through **v37 at least** (`https://maplestory.io/api/GMS/37/map/0`). **GMS v39 already shows the "Mushroom Town Training Camp"** (`https://maplestory.io/api/GMS/39/map/0`), which is earlier than the v40 boundary assumed in the project's map-set note.

## 3. Spawns

**Mobs:** none in v8 or in v22.

**NPCs**

| NPC | id | x, y | tier | dialogue (from `/api/GMS/8/npc/<id>`) |
|---|---|---|---|---|
| **Heena** | 2101 | (-48, 65), `flip=true` in the data | T6, on top of the big bush west of the house | "Press left Alt key and you'll be able to jump." / "Press the arrow keys to move around here and there." / "Beautiful day today!" |
| **Sera** | 2100 | (833, 125) | T5, the bluff, west of the clothesline | "It's a neverending pile of laundry I'm hanging up here." / "Have you met up with my sister Heena before?" / "Press↑ and you'll be able to climb up the ladder or a rope." / "Double-click on us, and you'll be able to talk to us." |

The two NPCs are sisters, according to Sera's lines. Together they cover the controls tutorial: move, jump, climb and talk.

## 4. Visual reference

### 4.1 Terrain

- The render (`v8_0_render.png`) shows only the grassySoil tile set.
  - The tiles are a bright green grass fringe over olive/khaki-brown cobbled dirt, with scattered grey stones set into the earth.
  - The terrain reads as solid earth blocks with vertical cliff faces.
  - A small floating grass clump sits where T6 is.
- Tile counts by layer, from WZ:
  - Layer 0 (the bluff): 42 grassySoil tiles.
  - Layer 2: 122 grassySoil tiles.
  - Layers 4–7 are set to `brownBrick` but contain no tiles.

### 4.2 Objects

These come from the WZ object list. All are data except where tagged. They are listed west to east.

- **x -133..-17, around y 119–133:** an olive bush and a large green bush/tree. Heena stands on the top of the bush (T6).
- **x 0..141: the orange mushroom house with yellow spots** (`houseGS/house6`).
  - Cream stalk body anchored at (126,104).
  - Orange cap with yellow spots anchored at (135,2) and (141,1).
  - Mushroom-cap awning door frame with a wooden plank door at (71,118)–(74,139).
  - Wall lantern at (0,120).
  - In the minimap the house is the biggest object in the map and is clearly visible.
- **x 212 and 264: two wooden barrels.** Their tops are the T7 and T8 footholds, so [inference] the barrels can be stood on.
- **x 569–728, foot of the steps:** a tiny mushroom cluster, a green bush, a red-spotted amanita cluster and an olive bush.
- **x 870 (y 337): a row of 4 mushrooms** in cream, orange, red and green, at the foot of the bluff. This row and its neighbours are among the few objects the render shows.
- **x 975:** the ladder.
- **x 918–1031, on T5: the clothesline.**
  - Two Y-shaped wooden posts joined by a rope, anchored at (977,68).
  - A hanging shirt at (935,74) and hanging trousers with a white sheet at (992,73).
  - A yellow butterfly on a post at (1023,9).
  - The rope itself is the T9 foothold. [inference] You can walk on the laundry line.
- **x 1051 (y 104): a red-berry bush** on the bluff.
- **Background layers (WZ `back`)**, all grassySoil:
  - A flat blue sky tile.
  - A big scrolling cumulus cloud band.
  - A distant rolling hill with a little mushroom house under a big tree, a winding path and fences.
  - A large leafy tree.
  - Two meadow strips.

### 4.3 Missing from the render

- The render is missing the house, door, lantern, barrels, bushes, clothesline, laundry, berry bush, ladder sprite and the whole sky.
- The minimap includes all of these.

## 5. What makes this map recognizable

- **It is the first map of the game.** The data shows it as the spawn map: 4 `sp`, `returnMap` is itself, the NPC lines are controls tutorials and there are no monsters. [memory] For GMS players of that era, it is the first screen they ever saw.
- **The big orange mushroom house with yellow spots** on a high grassy plateau, with barrels beside its door.
- **The three-step descent.** Three 60 px grass steps go down from the house plateau to the lane.
- **The laundry bluff.**
  - A raised grass block reached by one ladder.
  - Sera hangs laundry there: a shirt, trousers and a sheet on a rope between Y-shaped posts.
  - The rope is a walkable foothold.
- **Heena standing on top of a bush,** teaching how to jump.
- **The music.** The BGM `FloralLife` is shared by all five Mushroom Town maps. [memory] Players strongly link this tune with Maple Island.

## 6. 3D translation [proposal]

All of this section is [proposal]. Sizes are in MapleStory px, and depth (Z, north–south) is also given in px so it can be compared with x.

**Concept: "the hamlet on the hill".**
- The 2D strip becomes a small L-shaped hillside.
- You spawn on a broad plateau in the north-west, with the mushroom house at its back edge.
- A terraced grass slope steps down to the south-east into a sunken lane.
- The lane runs east along the foot of the laundry bluff, which rises behind it to the north. The lane then leaves east.

**Tiers to 3D**
- **T1 west plateau** (618 px along x; suggested depth 350–450 px, about 0.6–0.7 of its length):
  - A wide grass terrace with an olive-brown cobbled dirt rim.
  - The **house** sits on the plateau's north edge, front door facing south-east toward the spawn and the path.
  - The two **barrels** stand by the door's east side. Keep them standable at +48–55 px, as a jump-practice prop.
  - **Heena's bush** is a large rounded bush or small tree at the plateau's west/north-west corner, near the spawn. Heena stands on its crown at +120 px and is talked to from below.
- **T2/T3 steps** (2 × 90 px along x, each 60 px tall):
  - Two broad grass terraces with dirt retaining faces.
  - They curve from east toward south-east, so the descent reads as a terraced slope across both axes instead of a straight staircase.
  - Make them wider in depth than in x (for example 250–350 px deep) so they look like real terraces.
- **T4 sunken lane** (720 px along x; suggested walkable depth 160–220 px):
  - A grass lane along the bottom of the hollow.
  - On its south side, add a low earth bank and hedges or bushes to bound the play space.
  - At its west end, place the amanita cluster and bushes at the foot of the steps.
- **T5 laundry bluff** (528 × about 250–300 px deep, +240 px):
  - A raised grass block **north of the lane**, filling the lane's back side.
  - Its south face is a 4-unit dirt cliff, matching the data where the lane passes in front of the bluff face.
  - The clothesline runs east–west across the top, near its south edge so the laundry is visible from the camera.
  - Sera stands west of the line and the berry bush sits near the east end.
  - The rope can be a thin walkable balance beam at about +73 px for skilled jumpers. This is optional.
- **Ladder (236 px):** a wooden ladder fixed to the bluff's south cliff face at x≈975, landing at the top edge.
- **Mushroom row:** at the foot of the cliff just west of the ladder (x≈870), as a visual "climb here" marker.
- **out00:**
  - Put it at the lane's east end (x≈1052), 200 px before the map wall.
  - Show it as a visible portal swirl or a gap in the hedge where the lane continues east toward Mushroom Town.
  - Keep the west edge closed: a hedge or cliff, since there is no west exit.
- **Spawn area:** the west end of T1, x -206..-112. No mob areas.
- **Tutorial beats to keep:**
  - Move: Heena, on the plateau.
  - Jump: the steps and barrels.
  - Climb: Sera, the ladder and the bluff.
  - Talk: Sera.

**Top-down sketch [proposal].** North is up and away from the camera. Screen-left is map west. About 20 px per character along x.
```
 N (back)
 +----------------------------------------------------------------------------+
 | hedge/trees      ________________                ####### T5 BLUFF +4 ######|
 |  (BUSH)        /  ORANGE MUSHROOM \  (bbl)(bbl)   # Sera  Y~laundry~Y      #|
 |  Heena^       |   HOUSE  [door]-->|               #             (berries)  #|
 |   sp sp sp    '-------------------'               #######H##################|
 |        T1 WEST PLATEAU +3                          cliff  H ladder         |
 |                              \__ T2 +2             (4 mushrooms)           |
 |                                  \__ T3 +1                                 |
 |                       (amanitas+bushes) \___ T4 SUNKEN LANE 0 ____[out00]==> E: to 10000
 |  ~~ south rim: low bank / hedges / flowers bounding the lane ~~            |
 +----------------------------------------------------------------------------+
 W edge: closed (start map)                                    S (front, camera)
```

**Side elevation (map data, y up).** One unit is 60 px above T4 (y=365).
```
 units
 +5.2 |                                              ~T9~ clothesline 918-1031
 +5   |      T6 Heena(-84..-6)
 +4   |                                        T5 ============================ 726-1254
 +3.8 |              T7 T8 barrels               |          H
 +3   | ========== T1 ==========                 | cliff    H ladder x975
 +2   |                         == T2 ==         | 265px    H (236px)
 +1   |                                 == T3 == |          H
  0   |                                       ====== T4 ===========*out00======
      +----------------------------------------------------------------------
       -264        0           354    444    534  726       975  1052     1254
```

## 7. Version notes

Source: `docs/research/raw/gms_v22/0.json` against `raw/gms_v8/0.json`.

- **v22 inverts the west half.**
  - The west plateau is at y=485, *below* the lane. Steps go *up* through 425 to 365.
  - Heena's perch is at y=305.
  - The `sp` are at y≈437–452.
- The east half, meaning the bluff, ladder, clothesline and Sera, is identical in both versions.
- v22's 4th portal is also `null` in the API. From v22 raw WZ (`https://maplestory.io/api/wz/GMS/22/Map/Map/Map0/000000000.img/portal/4`) it is `out00` at **(1116,365)**, leading to 10000:in00. That is 64 px east of v8's position.
- This brief follows v8. Choose one version for MisoStory. v8 is the "descend from the house" reading.
- In GMS v39 and later, map 0 is "Entrance - Mushroom Town Training Camp", a different map (`https://maplestory.io/api/GMS/39/map/0`). Do not use it.

## 8. Open questions

- Heena's perch and the clothesline: keep them non-walkable as in the original feel, or make them reachable bonus spots?
- The v8 and v22 west halves differ. Confirm which one the project treats as canonical.
