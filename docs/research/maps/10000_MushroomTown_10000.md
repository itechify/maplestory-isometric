# Map 10000: "Mushroom Town". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/10000.struct.json`

**Tags used in this brief**
- No tag: a fact taken from data. The source is given.
- **[inference]**: my reading of the data.
- **[memory]**: something I remember about the game, unsourced.
- **[proposal]**: a design suggestion.

**Sources**
- `docs/research/raw/gms_v8/10000.json`, from `https://maplestory.io/api/GMS/8/map/10000`.
- Raw WZ:
  - The API JSON has `portals[2] = null`. `https://maplestory.io/api/wz/GMS/8/Map/Map/Map0/000010000.img/portal/2` gives `pn=out00 pt=2 tm=20000 tn=in00 x=706 y=216`.
  - Objects come from `.../000010000.img/<layer>/obj/<n>`.
- Sprites were viewed at `https://maplestory.io/api/wz/GMS/8/Map/Obj/...`, in a temp folder only.
- NPC: `https://maplestory.io/api/GMS/8/npc/2000` and, for the brothers line, `/npc/2002`.
- Renders: `ref_renders/v8_10000_render.png` and `v8_10000_minimap.png`.
- Version comparison: `raw/gms_v22/10000.json`.

## 0. Map card

| field | value (v8) |
|---|---|
| Street / name | "Maple Road" / "Mushroom Town" |
| isTown / returnMap | `true` / `10000` |
| BGM / mapMark | `Bgm00/FloralLife` / `MushroomVillage` |
| Foothold extent | x -309..849 (1158 px). Walkable y runs 65..275 (210 px). Wall bottoms reach y=480. |
| Walkable tiers | 4 |
| Ladders | 0 |
| Mobs | none |
| Portals | in00 is the arrival point on the far west. out00 leads east to 20000. |

## 1. Structure

### 1.1 Tiers

"Units" counts steps of 60 px above T1 (y=275).

| id | kind | x-range | y | length | height | layer | footholds | connects to |
|---|---|---|---|---|---|---|---|---|
| T1 | ground (west meadow) | -309..0 | 275 | 309 | 0 | 1 | 31,15,32,16,18 | West end is a wall at x=-309 (map edge). T2 at x=0. |
| T2 | slope (ramp) | 0..90 | 275→215 | 90 run, 60 rise (≈34°) | 0→+1 | 1 | 24 | Joins T1 to T3. |
| T3 | ground (main street) | 90..849 | 215 | 759 | +1 | 1 | 25,28,26,21,22,23,27,17,13 | East end is a wall at x=849 (map edge). `out00` at x=706. |
| T4 | ledge (Roger's garden terrace) | 186..444 | 65 | 258 | +150 over T3 (2.5 units) | **0** | 7,8,10,1 | Solid block. Walls at x=186 and x=444 run from y=65 down to 210. It has no ladder or ramp. |

**Walls**
- Map edges: x=-309 (y 275..480) and x=849 (y 215..480).
- T4's block faces: 145 px each.

**Gaps and pits:** none.

**Vertical layering**
- Low: T1, the west meadow.
- Main: T3, the street.
- High: T4, which is display only.

**Reachability [inference]**
- T4 is 150 px above the street with no ladder, so you cannot jump onto it ([memory] a base jump is about 70–80 px).
- Roger is meant to be clicked from the street.
- T4 is on layer 0 while the hedges in front of it are layer-1 objects. [inference] The terrace sits *behind* a hedge.

### 1.2 Ladders and ropes

None.

## 2. Portals

The API lists 3 entries: `sp`, `in00`, and one `null`. I recovered the `null` from raw WZ.

| name | pt | x, y | target | notes |
|---|---|---|---|---|
| sp | 0 | (-91, 181) | n/a | Default spawn point, above T1. |
| **in00** | 1 | (-195, 278) | none (`tm 999999999`) | Arrival point for 0:out00, 114 px from the west wall. |
| **out00** | 2 | **(706, 216)** | **20000:in00** | On T3, 143 px short of the east wall. Recovered from raw WZ. |

- **Edge exits:**
  - The west side has only the arrival point. There is **no portal back to map 0**.
  - The east exit is `out00`, near the east end of the street.
- **Portal types:** [memory] `pt 1` is an invisible portal used here as an arrival-only point.

## 3. Spawns

**Mobs:** none in v8 or v22.

**NPCs**

| NPC | id | x, y | tier | dialogue (from `/api/GMS/8/npc/2000`) |
|---|---|---|---|---|
| **Roger** | 2000 | (233, 65) | T4, on top of the hedge garden next to the vegetable fence | Inventory tutorial: "Open your item inventory and you'll find equip., use, set-up, and etc. tabs." / "Double-click on an item in the item inventory and you'll be able to use it" / "You'll die once your HP reaches 0..." / "You want to go travel now? Then come talk to me..." |

Peter (2002, map 30000) says Roger is his older brother: "Roger, my older brother, and Robin, my younger brother".

## 4. Visual reference

### 4.1 Terrain

- **Tiles:**
  - Layer 0 holds the T4 block: 16 grassySoil tiles.
  - Layer 1 holds the ground: 79 grassySoil tiles.
- **What the render shows:** `v8_10000_render.png` shows **no tiles at all**, only the two vegetable-garden fences.
- **What the minimap shows** (`v8_10000_minimap.png`):
  - The usual grass fringe over olive-brown cobbled dirt.
  - The low west meadow and the ramp.
  - A yellow mushroom house with a chimney, framed by large bushes.

### 4.2 Objects

These come from the WZ object list. They are listed west to east.

- **T1 west meadow, x -261..-116:**
  - A sunflower patch of 5 sunflowers (`nature/22-24`) at y 228–249.
  - A yellow butterfly at (-261,182).
  - An olive bush at (-116,223).
  - The arrival point in00 stands among the sunflowers.
- **T4, Roger's terrace, x 186..444:**
  - Big green hedge bushes form its visible face: (296,160), (362,105), (363,147).
  - A **vegetable-garden fence** sits on top at (327,44): wooden posts, a blue rope and leafy crops, 234 px wide.
- **The yellow mushroom house** (`houseGS/house8`):
  - A cream cylindrical body with a brown band, anchored at (485,138), so roughly x 374..596.
  - A wide yellow cap with brown streaks, anchored at (481,56), so roughly x 309..653 and y -14..126.
  - An arched doorway with a wooden plank door with a keyhole, at about (448,168). It faces the street.
  - A barrel-shaped wooden chimney with a little yellow hat on the cap at (588,-16).
  - The house's west side touches the east face of T4 (x=444).
- **A vegetable-garden fence on T3** in front of the house at (547,190), covering about x 430..664.
- **Bushes east of the house** at (599,167) and (645,164).
- **out00** at (706,216).
- **Backgrounds:** grassySoil back 0, 1, 2, 3 and 6. These are the same sky, clouds, distant hill and tree as map 0.

### 4.3 Missing from the render

- All tiles.
- The house, chimney, bushes, sunflowers and backgrounds.

## 5. What makes this map recognizable

- **A yellow mushroom house** with a brown-streaked cap and a barrel chimney, standing right on the street.
- **Roger standing above the street** in a hedge-walled vegetable garden, out of reach, teaching inventory basics.
- **The arrival meadow of sunflowers,** low on the west, rising by a short ramp onto the main street.
- **Size.** It is a very short, calm town screen: no ladders, no mobs, 1158 px wide.
- [memory] Together with 20000, this is "Mushroom Town" proper: the hub of the tutorial village between the west and east entrances.

## 6. 3D translation [proposal]

All of this section is [proposal].

**Concept: "the village green".**
- You arrive in a sunken sunflower meadow on the west.
- A short earthen ramp leads up onto a village street that bends gently east.
- On the street's north side are Roger's raised hedge garden and the yellow mushroom house, side by side.
- The exit is east of the house.

**Tiers to 3D**
- **T1 west meadow** (309 px along x; suggested depth 280–360 px):
  - A slightly sunken, bowl-like meadow full of sunflowers.
  - in00 is a portal pad at its west edge. That is where players arrive from map 0's lane, so match the art of map 0's east end.
- **T2 ramp** (90 px run, +60 px):
  - A packed-earth ramp with grass verges.
  - Let it rise toward the north-east, so the player turns slightly into the depth of the scene.
- **T3 main street** (759 px along x; suggested walkable depth 200–260 px):
  - A grass and earth street.
  - Its north side carries the landmarks. Its south side is a low flowered verge with bushes, and below that the meadow and background hills.
- **T4 Roger's garden** (258 px along x; suggested depth 150–200 px; +150 px, 2.5 units):
  - A raised garden plot on the north side of the street.
  - Its south face is a thick hedge wall, matching the layer-1 bushes in front of the layer-0 block.
  - The vegetable fence and crops run along its top edge.
  - Roger stands among the crops, visible over the hedge, with a talk radius reaching the street.
  - Keep it non-walkable, as in the original, or add a hidden back stair as an Easter egg.
- **Yellow mushroom house:**
  - Directly east of the garden, on the north side of the street, with its arched door facing south onto the street at x≈448.
  - The cap overhangs the garden's east corner, as it does in 2D.
  - The barrel chimney sits on the cap.
- **Vegetable patch:**
  - South-east of the door, between the street and the house front (x≈430..664 in 2D).
  - Leave a clear path from the street to the door on the patch's west side.
- **out00:**
  - At x≈706, past the eastern bushes, where the street leaves the frame east toward map 20000's west lawn.
  - The east edge beyond it is closed by hedges or trees.
- **Spawn area:** the `sp` point and in00, both on T1. No mob areas.

**Top-down sketch [proposal].** North is up. Screen-left is map west. About 18 px per character along x.
```
 N (back)
 +-----------------------------------------------------------------+
 | trees         hedge-row | T4 ROGER'S GARDEN +2.5 |  ____YELLOW____  bushes|
 |                         | [veg fence] Roger      | /  MUSHROOM    \ (chimney)
 |                         |  (hedge face, S side)  | \  HOUSE [door]/       |
 |                         +------------------------+  ``|``v``````` [veg patch]
 | (sunflowers)            ======= T3 MAIN STREET +1 ===================*out00==> E: to 20000
 |  *in00   T1 MEADOW 0   / T2 ramp                                         |
 |  (arrive from map 0)  /                                                  |
 |   olive bush       __/        ~~ south verge: flowers / low bushes ~~    |
 +-----------------------------------------------------------------+
 W edge: closed (no return)                                  S (front, camera)
```

**Side elevation (map data).** One unit is 60 px above T1 (y=275).
```
 units
 +3.5 |                 ===== T4 Roger (186..444) =====
      |                 |  veg fence, hedge face 145px |
 +1   |           /=========================[door~448]========== T3 ======*out00=====|
  0   | ====T1====/ T2 ramp (0..90)
      +----------------------------------------------------------------------------
       -309  in00(-195)  0  90  186                  444                 706     849
```

## 7. Version notes

- The v22 geometry, NPC and portals are identical to v8 (`raw/gms_v22/10000.json`).
- v28 through v39 also keep 34 footholds and the same in00 (`https://maplestory.io/api/GMS/28/map/10000`).

## 8. Open questions

- Should Roger's garden stay unreachable, which keeps the 2D "NPC on a perch" feel, or become walkable via a back stair?
