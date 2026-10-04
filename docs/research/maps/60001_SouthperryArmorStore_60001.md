# 60001 Southperry Armor Store (`SouthperryArmorStore_60001`)

Phase-1 structural analysis and 3D-translation brief. Machine-readable companion: [`60001.struct.json`](60001.struct.json).

**Provenance labels used below**
- Unlabelled numbers come from the data: `docs/research/raw/gms_v8/60001.json` (maplestory.io `/api/GMS/8/map/60001`). Other sources are cited inline.
- **[render]**: read from `ref_renders/v8_60001_render.png`. The render is 800 × 600 and matches vrBounds, so map px = render px − (400, 300).
- **[memory]**: recalled from memory, not checked against a source.
- **[proposal]**: a design suggestion.
- **[inferred]**: a conclusion drawn from the data that the data does not state directly.

All units are MapleStory px (y increases downward).

**No minimap exists.** `ref_renders/v8_60001_minimap.png` is not an image: it is a saved API error, "The requested endpoint GET /api/GMS/8/map/60001/minimap does not exist", and the JSON has no `miniMap` block.

| Field | Value |
|---|---|
| Street / name | Maple Road / Southperry Armor Store |
| isTown | true (no mobs) |
| BGM | `Bgm00/FloralLife` |
| mapMark | SouthPerry |
| returnMap | 60000 |
| Foothold count | 27 (identical in v22 and v39) |
| View bounds (vrBounds) | x −400..400, y −300..300, so the room is an **800 × 600 view** |
| Footholds extent | x −400..400, y −263..183 |

---

## 1. Structure: room layout

### 1.1 Shell
- **Floor:** T17, x −400..400 at **y 183**. It is a single foothold running wall to wall (800 px).
- **Height:** no ceiling foothold exists. The highest walkable surface is the beam T0 at −263, and vrBounds stops at −300, so the room is about **480 px tall** from floor to ceiling.
- **Walls:** there are no side-wall footholds. The view bounds close the room at x ±400.

### 1.2 Fixtures (from footholds)
| ID | What | x range | y | Kind | Notes |
|---|---|---|---|---|---|
| T17 | **shop floor** | −400..400 | 183 | ground | out00 door at x −48 |
| T5 | **Pan's kiosk, roof** | −345..−208 | −13 | floating | The kiosk is a solid closed block (137 px wide) spanning y −13..150. Its underside at 150 is a ceiling-only foothold (excluded from tiers) that sits 33 px above the floor, so **[inferred]** players walk freely underneath |
| T13 | **Pan's recess floor** | −338..−227 | 140 | floating | Pan stands here, 43 px above the floor. The recess is closed above by a ceiling-only foothold at y 13 (excluded), so it is a **booth window about 127 px tall** cut into the kiosk |
| T12 | low step above the door spot | −119..−16 | 139 | floating | the spawn point (−114, 115) lands here; 44 px above the floor, directly over and beside the door at x −48 |
| T16 | low crate or bench | 19..113 | 159 | floating | 24 px above the floor; start of the ware pile |
| T15, T10, T9, T8, T7 | **ware pile, steps** | 158..301 | 156, 127, 97, 57, 20 | floating | short pieces (40–112 px) about 30–40 px apart in height; a climbable heap |
| T4 | ware pile, wide shelf | 46..263 | −19 | floating | 217 px; rope x75 starts 65 px above it |
| T3, T2 | ware pile, rounded item tops | 114..173 / 174..252 | ≈ −50 / ≈ −100 | floating | bumpy profiles (sloped segments), i.e. round goods such as helmets or pots **[inferred]** |
| T1 | ware pile, top shelf | 247..342 | −183 | floating | 80 px below the beam |
| T11 | small prop by the east wall | 328..365 | 132 | floating | |
| T0 | **ceiling beam / loft** | −185..311 | −263 | ledge | 496 px; head of rope x75 |

**Rope:** x 75, −261 → −84 (rope, not ladder). It joins the beam T0 to the area above the wide shelf T4 (65 px gap, grab with a jump).

**Climb route [inferred]:** floor → T16 → T15/T10 → T9 → T8 → T7 → T4 → (T3 → T2 → T1) or rope x75 → beam T0. From the beam's west end (x −185, y −263), a jump west can reach the kiosk roof T5 (−13).

### 1.3 Front view of the room (elevation, from data; left = west; not to scale)
```
y -263   ..........[======== T0 ceiling beam / loft (496) =========]......
y -183                                            |rope75     [T1 top]
y -100                                            |      (T2)
y  -50                                            |   (T3)
y  -19   [T5 kiosk roof]                   [=== T4 wide shelf ===]
y   20                                                  [T7]
y   57   | Pan's booth  |                             [T8]
y   97   |  (recess)    |                                [T9 ====]
y  140   |  Pan @-270   |     [T12 step]                [T10]          [T11]
y  159   |______________|                 [T16]       [T15]
y  183   ===================== floor ===  DOOR out00 @-48 ======================
         x -400        -208     -119 -16  19   113   158        301   365 400
```

---

## 2. Portals (2 entries in v8, 1 of them null)
| Name | Type | x, y | Target | Status |
|---|---|---|---|---|
| out00 | 2 | −48, 181 | **60000:in00** (Southperry street, x 699) | v8 entry null; from https://maplestory.io/api/GMS/39/map/60001, whose 27 footholds and NPC are identical to v8 |
| sp | 0 | −114, 115 | — | spawn point, lands on T12 |

The **exit door is on the floor slightly left of centre (x −48)**. The player appears just west of it on the low step T12.

---

## 3. NPCs
| NPC | id | x, y | Tier | Notes |
|---|---|---|---|---|
| Pan | 21000 | −270, 140 | T13 (booth recess) | Walk area x −318..−220. Dialogue (https://maplestory.io/api/GMS/8/npc/21000): "Let's see...I'm ready to make some money..." / "Hello everyone! I've got some goods here for sale!!". Listed as the armor vendor by https://meowdb.com/msclassic/maps/000000061 (later revision). His shop inventory was not checked |

No mobs.

---

## 4. Visual reference
**[render]** Only fragments of the room are drawn:
- **Timber ceiling beams bound with blue iron bands** at the top-left (x −400..−115, y −255..−45) and top-right (x 210..400, y −255..−100).
- A **wooden post with grey stone caps** on the west side (x −400..−340, y −100..225).

**Missing from the render:** the back wall, the floor art, Pan's booth, the wares, the door, Pan himself, and any windows or signage.

**Style cues:**
- From the render: a wooden interior (timber and stone accents).
- From the exterior seen on the Southperry minimap (a white house with a blue slanted roof and a chimney): a whitewashed interior with blue accents would match. **[proposal]**, not sourced.

---

## 5. What makes this map recognizable
- **Data:**
  - A single small shop room with **Pan in a booth window** on the west side.
  - A **heap of wares** on the east side that players can climb up to a **ceiling beam**.
  - The door in the floor area, centre-left.
  - The "Floral Life" BGM, which differs from the town's "Go Picnic".
- **[memory]:** I do not have reliable recollection of this interior's art. Treat its appearance as open.

---

## 6. [proposal] 3D translation

**Room:** one rectangular room.
- **Width:** 800 px.
- **Height:** about 480 px from the floor to the beams.
- **Depth:** suggested at about 0.5–0.6 × the width (about 400–480 px).
- For the iso camera, cut away the front (south) and east-front walls, or fade them, and keep the west wall, the back (north) wall and the ceiling beams.

**Entrance**
- The door (out00) sits in the **front-left wall** at x ≈ −48, so the camera looks into the room from the entrance side.
- **T12** becomes a 44 px raised **entry mat or step** just inside the door. It is where the player appears.

**West wall: Pan's kiosk**
- A **booth** 137 px wide and about 196 px tall (floor to roof), standing against the west wall.
- It has a **counter window** (the recess: x −338..−227, 127 px tall, its floor 43 px above the room floor) where Pan stands facing into the room.
- Its **roof is walkable** (T5, −13).
- The stone-capped wooden post from the render frames the booth.

**East wall: the ware heap**
- A **stepped pile of merchandise**: crates, barrels, armor stands, shields and helmets.
- It climbs in 30–40 px steps from a low crate (T16) to a wide shelf (T4, 202 px above the floor) and on to a top shelf (T1, 366 px above the floor).
- Players can climb it, as in the data.

**Ceiling**
- **Timber beams with blue iron bands** span the room.
- One beam (**T0**, 496 px, 446 px above the floor) is a walkable loft reached by **rope x75** hanging down over the wide shelf.

**Spawns:** none.

### 6.1 Top-down sketch [proposal] (screen-left = west; top = back wall)
```
 BACK WALL (north)
 +-----------------------------------------------------------------+
 | [Pan's kiosk ]          (ceiling beam T0 runs W-E overhead)       |
 | [ booth window]                                   [ ware heap   ] |
 | [  Pan  ->   ]                                    [ T16..T4..T1 ] |
 | [roof walkable]                         rope x75 ->[ climbable   ] |
 | west wall                                                  east wall |
 |                 [T12 entry step]                                  |
 +----------------------[ DOOR out00 ]--------------------------------+
 FRONT WALL (camera side, cut away)      door at x -48 (slightly left of centre)
```

### 6.2 Side elevation (from data; rows are walk levels, NOT to vertical scale; 1 char = 12 px)
```
x -400 .. 400; = flat, / \ bumpy top, | rope, P portal (row above its tier), n NPC
  -263 |                  ==========================================        | T0 beam/loft
  -183 |                                        |             =========     | T1 top shelf
  -100 |                                        |       ///==\\             | T2
   -50 |                                        |   ///\\\                  | T3
   -19 |     ============                    ===================            | T5 kiosk roof (-13), T4 wide shelf (-19)
    20 |                                                 ====               | T7
    57 |                                               ====                 | T8
    97 |                                                 ==========         | T9
   127 |           n                                    ====         ====   | T10, T11 (n = Pan, stands at 140)
   140 |     ==========        ==========                                   | T13 Pan's recess floor, T12 entry step
   159 |                             P     =========   ====                 | T16, T15 (P = out00 on the floor)
   183 |====================================================================| T17 floor
```
