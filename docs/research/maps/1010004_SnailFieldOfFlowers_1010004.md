# Map 1010004: "Snail Field of Flowers". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/1010004.struct.json`. It uses the same tier ids as this brief.

**Tags used in this brief**
- No tag: a fact taken from data. The source file or URL is given.
- **[inference]**: my reading of the data. The data does not state it.
- **[memory]**: something I remember about the game. No source was checked.
- **[proposal]**: a design suggestion for MisoStory.

**Sources**
- `docs/research/raw/gms_v8/1010004.json`, from `https://maplestory.io/api/GMS/8/map/1010004`. The floors, ladders, mobs and spawn points are identical in `raw/gms_v22/1010004.json` and in `/api/GMS/40`, `/55` and `/62/map/1010004`.
- Raw v8 WZ under `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001010004.img`: `/portal/11` (the exit; the parsed JSON has a `null` at index 3 because it orders portals differently), `/back/<n>`, `/<layer>/obj/<n>` and `/<layer>/info/tS`.
- The reverse link comes from raw v8 WZ `.../001010002.img/portal/2`: Amherst Townstreet `west00` (-492, 275) → `1010004:east00`.
- Sprites were viewed at `.../Data/Map/Obj/acc1.img/grassySoil/...`, `.../Obj/connect.img/rope/3/...` and `.../Back/grassySoil.img/...` in a temp folder only. All object names are my identification from those sprites.
- Mob names and levels: `https://maplestory.io/api/GMS/8/mob/100100`, `/100101` and `/130101`.
- Reference images, viewed but not copied: `ref_renders/v8_1010004_render.png` (tiles plus most objects, no ropes) and `v8_1010004_minimap.png`.

## 0. Map card

| field | value (v8) |
|---|---|
| Street / name | "Rainbow Street" / "Snail Field of Flowers" |
| isTown / returnMap | `false` / `1010000` (Amherst) |
| BGM | `Bgm00/FloralLife` |
| mapMark / mobRate | `Amherst` / **1.2**, a faster respawn than the other Rainbow Street pockets |
| Foothold extent | x -1029..849 (1878 px wide). The walkable surfaces run from y -625 to 575 (1200 px). Basin walls go down to y=780. |
| Walkable tiers | 19 in total: 1 full-width rim slab, 5 basin ground pieces and 13 floating platforms. |
| Climbables | 11, **all green leafy vines** (sprite `connect/rope/3`). There are no ladders. 2 vines are dead-ends. |
| Mobs | 43: Snail 10, Blue Snail 16 and Red Snail 17. |
| NPCs | none. |
| Exits | 1: `east00` at (559, -623), **on the top rim**, goes to 1010002 Amherst Townstreet `west00`. There are no edge exits. |

## 1. Structure

### 1.1 Tiers
The ids are sorted from top to bottom, so T0 is the highest. All tiers are flat. In the table, "vine" gives the climbable's x position and "hop" means a 60-px jump.

| id | kind | x1..x2 | y | width | links / notes |
|---|---|---|---|---|---|
| T0 | ground (rim) | -1029..849 | -625 | 1878 | **Top rim slab.** It spans the full width and is about 205-235 px thick: its side walls reach y-420 and the render underside is at about y-390. It is the arrival level (11 spawn points) and holds the exit `east00` at x559. Vines x-637, x-263, x41 and x650 go down to the mid row. Wooden rail fence alternating with big bushes. No mobs. |
| T1 | floating | -939..-501 | -145 | 438 | West meadow. Vines x-637 (up to the rim), x-577 (dead-end) and x-837 (down to T9). Purple flowers. |
| T2 | floating | -309..219 | -145 | 528 | Centre meadow. Vines x-263 and x41 (up to the rim). Clover patch. |
| T3 | floating | 411..759 | -145 | 348 | East meadow. Vines x650 (up to the rim), x576 (dead-end) and x640 (down to T10). Orange flowers. |
| T4 | floating | -489..-321 | -85 | 168 | Dip stone between T1 and T2 (60 lower, 12-px gaps). Vine x-453 down to T7. |
| T5 | floating | 231..399 | -85 | 168 | Dip stone between T2 and T3. Vine x363 down to T8. |
| T6 | floating | -219..309 | 95 | 528 | **Centre flower island** with an orange flower bed. Hop up from T8. It is the top of the east stair. |
| T7 | floating | -759..-411 | 155 | 348 | Vine x-453 up to T4. Hop up from T9. Big bush and orange flowers. |
| T8 | floating | 321..489 | 155 | 168 | Vine x363 up to T5. Stair: T10 → T8 → T6. |
| T9 | floating | -939..-771 | 215 | 168 | Vines x-837 (up to T1) and x-897 (down to T14). |
| T10 | floating | 501..669 | 215 | 168 | Vine x640 up to T3. Stair stone. |
| T11 | floating | 411..579 | 275 | 168 | Stair stone. |
| T12 | floating | 321..489 | 335 | 168 | Stair stone. |
| T13 | floating | 231..399 | 395 | 168 | Bottom stair stone. Hop up from T15. |
| T14 | ground | -1029..-591 | 455 | 438 | West basin rim. Vine x-897 up to T9. Clover. |
| T16 | ground | -591..-501 | 515 | 90 | Riser step (60). |
| T18 | ground | -501..321 | 575 | 822 | **Basin floor**, the lowest surface. Clover carpet and big bushes. |
| T17 | ground | 321..411 | 515 | 90 | Riser step (60). |
| T15 | ground | 411..849 | 455 | 438 | East basin rim. Clover and bushes. |

### 1.2 Vines (ladderRopes)
`from` is the tier at the bottom end and `to` is the tier at the top end.

| x | y1 → y2 | length | from → to | note |
|---|---|---|---|---|
| -637 | -623 → -172 | 451 | T1 → T0 rim | long rim vine |
| -263 | -623 → -173 | 450 | T2 → T0 rim | long rim vine |
| 41 | -623 → -172 | 451 | T2 → T0 rim | long rim vine |
| 650 | -623 → -174 | 449 | T3 → T0 rim | long rim vine. The exit is 91 px west of its top. |
| -577 | -431 → -147 | 284 | T1 → *none* | **Dead-end.** Its top is inside the slab underside, with no foothold. |
| 576 | -425 → -195 | 230 | T3 → *none* | **Dead-end.** It hangs from the slab underside; its bottom is 50 px above T3. |
| -837 | -143 → 185 | 328 | T9 → T1 | |
| -453 | -83 → 153 | 236 | T7 → T4 | |
| 363 | -83 → 128 | 211 | T8 → T5 | |
| 640 | -143 → 188 | 331 | T10 → T3 | |
| -897 | 217 → 426 | 209 | T14 → T9 | |

The long rim vines stop 27-29 px above the mid-row surface. [memory] In MapleStory you grab such a vine by jumping up to it.

### 1.3 Layering, gaps and walls
- **The rim (y-625)** is a thick full-width slab at the top of the map. The basin is a cliff face 480 px below its walking surface. Only the four ~450-px vines cross that gap.
- **The mid row (y-145)** is three meadows: T1 (west), T2 (centre) and T3 (east). Two dip stones, T4 and T5 at y-85, link them. The result is one continuous walkway with two 60-px dips.
- **The low islands (y95..215):**
  - The centre island T6 (y95).
  - T7 (west) and T8 (east) at y155.
  - T9 (far west) and T10 (east) at y215.
- **The east stair** is a zig-zag of 168-px stones: T15 rim (455) → T13 (395) → T12 (335) → T11 (275) → T10 (215) → T8 (155) → T6 (95). That is 6 hops of 60 px from the east basin rim to the centre island.
- **The basin (y455..575)** is a symmetric stepped bowl: T14 455 → T16 515 → T18 575 → T17 515 → T15 455. The risers are 60 px and the walls run down to y780.
- **Total rise:** the rim is 1200 px above the basin floor. That is 4 bands: rim, mid row, low islands/stair and basin.

### 1.4 Routes [inference]
- **Arrival:** at the top, on the rim, near the exit. 11 spawn points run along the rim at x-794..535, y-700..-743. The rim has no mobs.
- **Descent:** take a long vine down to the mid row. Then go down any of the four short vines to the low islands, or drop off the mid-row edges into the basin.
- **Return:** the only exit is on the rim, so the player must climb back up.
  - From the basin, the east stair leads to T6 and T8. Vine x363 goes up to T5, then vine x41 or x650 to the rim.
  - Or, on the west side: T14 → vine x-897 → T9 → T7 → vine x-453 → T4 → T1 → vine x-637 → rim.
- This makes the map a **descend-then-climb-out bowl**, unlike the other three pockets, which have their exit on the ground.

## 2. Portals
- The parsed v8 JSON has 12 entries: 11 `sp` (listed above, all over T0) and 1 `null` at index 3.
- Raw v8 WZ `.../001010004.img/portal/11` gives **`east00`, type 2, at (559, -623), going to 1010002 `west00`**. It stands on the rim T0, 290 px from the slab's east end.
- The reverse link is Amherst Townstreet `west00` at (-492, 275) → `1010004:east00` (raw WZ `.../001010002.img/portal/2`).
- v40 parses the same portal.
- **No edge exits.** The rim slab ends in walls at x-1029 and x849, the basin walls run to y780, and there is no other non-spawn portal. *(Verification pass: `docs/topology.json` now classes this exit as **edge_east**. There, edge_* is positional: the exit stands on a tier that reaches the map's east (the full-width rim x -1029..849) foothold limit. It does not mean a walk-off edge, so this line still holds.)*
- The portal is named `east00`, and its target `west00` is the westernmost portal in Amherst Townstreet: x-492, against that map's `sp` at x-329 and `out00` at x-167 (raw WZ `.../001010002.img/portal/0..2`). So the field lies west of the Townstreet house [inference].

## 3. Spawns
- **Snail** (lv 1): 10.
- **Blue Snail** (lv 2): 16.
- **Red Snail** (lv 4): 17.

| tier | Snail | Blue | Red | total |
|---|---|---|---|---|
| T1 west meadow | 2 | 2 | 1 | 5 |
| T2 centre meadow | 1 | 3 | 3 | 7 |
| T3 east meadow | 1 | 1 | 2 | 4 |
| T6 centre island | 2 | 2 | 2 | 6 |
| T7 | 1 | 2 | 1 | 4 |
| T14 west rim | 1 | 2 | 2 | 5 |
| T15 east rim | – | 1 | 3 | 4 |
| T18 basin floor | 2 | 3 | 3 | 8 |

- The rim T0, the dip stones, the stair stones and T9 have no spawns.
- Red Snails are the most common mob here; this map has the highest share of Red Snails of the four.

## 4. Visual reference

### 4.1 Terrain
- The tile set is `grassySoil` (layer 1; layer 0 has no tiles). It is the same grass over olive-brown cobbled dirt with grey boulders.
- The rim slab is a very thick dirt band, about 230 px.
- Backgrounds use set `grassySoil` (`back/0..5`):
  - Blue sky (no.0), drifting clouds (no.1), a domed hill (no.2) and a big leafy tree (no.3).
  - Two meadow strips, no.5 and **no.6**. No.6 is a meadow with a broken wooden fence, rocks and a yellow tree. They replace the no.4 strip used by the other three maps.

### 4.2 Objects (raw WZ layer 1; x,y = object origin)
- **Rim T0:**
  - 6 wooden rail fences (`grassySoil/artificiality/3`) at x-822, -672, -259, 30, 443 and 735.
  - 4 big round bushes at x-542, -399, -110 and 257.
  - 5 low dark bushes.
  - In the render it reads as a fenced hedge-lined path along the top.
- **Mid row:**
  - T1: purple flowers ×5 and a pink butterfly.
  - T2: a clover patch ×6, bushes and a pink butterfly.
  - T3: orange flowers ×3, a bush and a yellow butterfly.
- **The centre island T6** is a dense **orange flower bed** (13 orange flower sprites), with 4 bushes and an orange butterfly.
- **T7:** a big bush, orange flowers ×4 and a yellow butterfly.
- **Basin:**
  - T18: a **white-pink clover carpet** ×12 and big bushes ×3 at the west end.
  - T14 and T15: clover with bushes, and pink butterflies.
  - One pink butterfly floats mid-air over the basin at (-75, 446).
- **Vines:** all 11 climbables use `connect/rope/3`, a green leafy vine sprite. The other Rainbow Street pockets use hemp ropes.

### 4.3 Missing from the render
- The render shows tiles and objects but no vines and no background.
- The minimap draws the vines as dark-green lines from the rim.

## 5. What makes this map recognizable
- **You arrive at the top**, on a fenced, hedge-lined rim road, and look down into a flower-filled bowl.
- **Long green vines** curtain down the rim's cliff face.
- Three flower meadows (purple, clover, orange) at mid height. A **centre island covered in orange flowers**.
- A **zig-zag stone stair** up the east side of the bowl.
- A **clover-carpeted basin** full of snails.
- The music is `FloralLife`, which differs from the hunting grounds' `RestNPeace`.
- Butterflies are everywhere.
- [memory] Nothing more specific.

## 6. 3D translation [proposal]

**Concept: a sunken flower valley seen from a fenced cliff-top lane.**
- The rim runs along the **back** of the scene.
- The valley falls toward the camera. The basin floor is the front of the scene and the lowest point.
- The cliff face under the rim faces the camera, so the vine curtain is the scene's backdrop and its signature.

**Tier mapping**
- **Rim T0 → a cliff-top lane** along the back edge, about 1880 px long.
  - It has a wooden rail fence and hedge bushes on the valley side, with gaps in the fence where the four long vines start.
  - The exit `east00` sits at the east end of the lane, where it would lead toward Amherst Townstreet.
  - The lane is safe ground with no mobs.
- **The 480-px drop → a sheer earthen cliff face** with the four long vines (about 450 px) hanging down it. The two dead-end vines hang from an overhang just under the lip; they are decorative and can be climbed but lead nowhere.
- **Mid row → a ledge shelf** partway down the cliff:
  - T1 (purple), T2 (clover) and T3 (orange) become three flower meadows.
  - The dip stones T4 and T5 become two sunken stepping hollows between them.
- **Low islands → free-standing flower knolls** in the bowl:
  - T6 is the large central orange-flower knoll, the visual centrepiece seen from the lane.
  - T7 and T9 are west knolls; T8 and T10 are east knolls.
  - The short vines become vines hanging from the shelf edge onto these knolls.
- **East stair → a curving flight of stepping stones** that winds up from the east basin rim (T15) to the centre knoll. Six 60-px steps with alternating offsets read naturally as a spiral flight.
- **Basin → a clover-carpeted bowl floor:** T18 as the floor, T16 and T17 as one-step banks, and T14 and T15 as the west and east rims of the bowl.

**Route through 3D space**
1. Enter at the back-top lane, east end.
2. Walk west along the lane and look down into the bowl.
3. Descend a vine to the shelf, then to the knolls or the bowl floor.
4. Hunt across the bowl from west to east.
5. Climb out by the east stair, the shelf and a vine, back to the lane and the exit.

The west-to-east axis is kept: screen-left is west and screen-right is east. Depth carries the vertical drop from the back lane to the front basin.

**Spawn areas**
- The bowl floor and rims hold 17 spawns: T18 8, T14 5 and T15 4.
- The shelf meadows hold 16.
- The knolls T6 and T7 hold 10.
- The lane, the stair and the stepping hollows stay clear.

**Top-down sketch.** Screen-left is the map's west end. Up is back and higher.
```
 back/high  ==fence==bush==fence=====[ T0 cliff-top lane ]=====fence==bush==fence==[EXIT east00]
               vine x-637  (x-577)  vine x-263   vine x41        (x576)  vine x650
            ~~~~~~~~~~~~~~~~~~~~~~ cliff face (vine curtain) ~~~~~~~~~~~~~~~~~~~~~~~~
            [T1 purple meadow](T4 dip)[ T2 clover meadow ](T5 dip)[T3 orange meadow]
             |vine x-837   |vine x-453               |vine x363     |vine x640
         (T9)  [T7 knoll]        [ T6 ORANGE FLOWER KNOLL ]  (T8)  (T10)
          |vine x-897                                  ^ (T11)
                                                       stair (T12)
                                                      (T13)
 front/low [T14 W rim]\T16\[____ T18 clover bowl floor ____]/T17/[T15 E rim]
           W ------------------------------------------------------------------> E
```

**Side elevation.** y in MapleStory px with up = higher; this is not to scale.
```
 y -625  T0 =====================================================[exit]==  (rim, ~230 px thick)
 y -390  ######################### slab underside ##########################
           |vine          |vine         |vine                 |vine   (~450 px each)
 y -145  T1 =======    T2 ===========         T3 =======
 y  -85         T4 ==            T5 ==
 y   95                  T6 ==========
 y  155    T7 ======               T8 ==
 y  215 T9 ==                        T10 ==
 y  275                            T11 ==
 y  335                          T12 ==
 y  395                        T13 ==
 y  455 T14 ======\                       /T15 =======
 y  515           T16\                 /T17
 y  575               \_____T18_______/
```

## 7. Version notes
- v8, v22, v40, v55 and v62 share all 111 floor footholds and the same 43 mobs and spawn points. This map was stable across those versions.
- v75 reports 146 footholds and 47 mobs. I did not use it.
- A modern "MapleStory Classic" database page (`https://meowdb.com/msclassic/maps/000001014`) lists 34 spawns, including Orange Mushroom. That does not match v8, so I did not use it.

## 8. Open questions
- Should the rim lane connect visually to the Amherst Townstreet house through a gate or path at its east end? The 2D map only has the portal.
- Should the two dead-end vines stay climbable dead-ends, or become purely decorative in 3D?
