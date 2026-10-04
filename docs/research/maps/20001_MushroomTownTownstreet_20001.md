# Map 20001: "Mushroom Town Townstreet". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/20001.struct.json`

**Tags used in this brief**
- No tag: a fact taken from data. The source is given.
- **[inference]**: my reading of the data.
- **[memory]**: something I remember about the game, unsourced.
- **[proposal]**: a design suggestion.

> **Important: this map is a house interior, not a street.** The canonical name is "Mushroom Town Townstreet", and the name in the data agrees. But the v8 footholds and objects describe the **inside of a two-storey mushroom house**:
> - The objects are `insideGS/house1`, the furniture props `prop/grassySoil/fur/*`, a bed, a chest and a window.
> - Two stacked floors are joined by a ladder.
> - The only exit is a door that leads back to 20000's house door (`in01`).
>
> I keep the given slug. See the open questions.

**Sources**
- `docs/research/raw/gms_v8/20001.json`, from `https://maplestory.io/api/GMS/8/map/20001`.
- Raw WZ:
  - The API JSON has `portals[1] = null`. `https://maplestory.io/api/wz/GMS/8/Map/Map/Map0/000020001.img/portal/1` gives `pn=out00 pt=2 tm=20000 tn=in01 x=-167 y=244`.
  - Objects come from `.../000020001.img/1/obj/<n>`.
  - The GMS v28 parsed API shows the same portal directly: `https://maplestory.io/api/GMS/28/map/20001`.
- Sprites were viewed at `https://maplestory.io/api/wz/GMS/8/Map/Obj/insideGS.img/house1/basic/0..4/0` and `.../prop.img/grassySoil/...`, in a temp folder only.
- NPC: `https://maplestory.io/api/GMS/8/npc/2001`.
- Render: `ref_renders/v8_20001_render.png`.
- There is **no minimap**. `/api/GMS/8/map/20001/minimap` returns "endpoint does not exist", and the saved `v8_20001_minimap.png` is that error JSON. The map JSON also has no `miniMap` field.

## 0. Map card

| field | value (v8) |
|---|---|
| Street / name | "Maple Road" / "Mushroom Town Townstreet" |
| isTown / returnMap | `true` / `20001` (itself) |
| BGM / mapMark | `Bgm00/FloralLife` / `MushroomVillage` |
| Foothold extent | x -579..489 (1068 px), y -117..480. **Play space is about x -221..138 and y -117..246, i.e. 360 × 363 px.** |
| Walkable tiers | 3: the yard, the ground floor and the upper floor. |
| Ladders | 1 |
| Mobs | none |
| Portals | 1 door, out00, leading to 20000:in01. Plus 1 `sp` outside. |

## 1. Structure

### 1.1 Tiers, walls and ceilings

| id | kind | x-range | y | length | notes |
|---|---|---|---|---|---|
| T1 | ground (front yard, outside) | -579..-221 | 275 | 358 | Outside the house's west wall. The `sp` (respawn) is here at x=-329. There is a 29 px step up (wall x=-221, 275→246) onto T2. |
| T2 | ground (ground floor, inside) | -221..129 | 246 | 350 | out00 at x=-167. Sen at x=24. Ladder foot at x=77. |
| T3 | ledge (upper floor / loft, inside) | -142..138 | 47 | 280 | Reached by the ladder at x=77. Enclosed on all sides. |

**Walls and ceilings** (footholds; x1>x2 marks a ceiling, i.e. the underside)

| element | coordinates | meaning |
|---|---|---|
| Ground-floor ceiling | y=69, x -141..129 (fh27, drawn right to left) | Clear height over T2 is 246−69 = **177 px**. |
| Door lintel | wall x=-141, y 69→152 (fh28) | Leaves a **94 px** high opening (152..246) between the entry nook (x -221..-141, 80 px wide) and the main room (x -141..129, 270 px wide). |
| East wall, ground floor | x=129, y 246→69 (fh26) | Closes the room's east side. |
| Upper room box | floor y=47 (fh30), walls x=-142 and x=138 (y -117..47), ceiling y=-117 (fh32) | A closed rectangle, 280 px wide with **164 px** clear height. |
| Floor slab between storeys | 47..69 | 22 px thick. It matches the `house1/basic/3` floor-board sprite, which is 22 px tall and anchored at y=58. |

**Data artifact, excluded from `tiers`:**
- The yard foothold chain continues at y=275 *under* the T2 floor and east to x=489 (fh 23, 2–7, 9, 12, 13).
- The data branches here: fh8's `next` is the step wall fh24, but fh23's `prev` is fh8.
- That strip lies 29 px below the floor and is not meant as play space. It is the ground the house sprite sits on.

**Vertical layering:**
- Yard, at y=275.
- Ground floor, at 246.
- Upper floor, at 47. That is 199 px above the ground floor and reached only by ladder.

### 1.2 Ladders and ropes

| x | y1 (top) → y2 (bottom) | type | joins | length |
|---|---|---|---|---|
| 77 | 49 → 244 | ladder (`isLadder: true`; sprite `connect/ladder/1/0` at (77,142)) | T2 → T3 | 195 px. It passes through the ground-floor ceiling at y=69, so it implies a hatch. |

## 2. Portals

| name | pt | x, y | target | notes |
|---|---|---|---|---|
| sp | 0 | (-329, 241) | n/a | **Outside** in the yard (T1). Used for respawn, since `returnMap` is 20001, and for portal-less entry. |
| **out00** | 2 | **(-167, 244)** | **20000:in01** | Inside the entry nook, next to the exit-door sprite on the west wall at (-220,202). It is also the arrival point when entering from 20000. Recovered from raw WZ. |

- **Edge exits:** none. The only way out is the door, west of the room.

## 3. Spawns

**Mobs:** none.

**NPCs**

| NPC | id | x, y | tier | dialogue (from `/api/GMS/8/npc/2001`) |
|---|---|---|---|---|
| **Sen** | 2001 | (24, 246), walk area -26..74 | T2, ground floor, between the cupboard and the ladder | "I'm... so ... hungry!" / "Can... I... eat this ...?" |

## 4. Visual reference

### 4.1 Terrain

- **What the render shows** (`v8_20001_render.png`): only a single long strip of grassySoil ground tiles (grass over olive-brown dirt) across the full width.
  - This is the yard and the ground under the house.
  - Layer 1 holds 65 tiles.
- **What the render omits:** the whole interior.

### 4.2 Objects

These come from the WZ object list. All are on layer 1. They are listed back to front, then west to east.

- **Shell** (`insideGS/house1/basic/0`, anchored at (32,7), 615×533 px):
  - A cut-away mushroom house.
  - An orange mushroom cap as the roof.
  - Cream plaster walls.
  - A stone-framed arched entrance on the lower west side.
- **Upper room panel** (`basic/1`, at (14,-85)): cream walls between honey-coloured timber posts, with an exposed wooden roof truss under the cap.
- **Ground-floor panel** (`basic/4`, at (-21,146)):
  - The same timber-post walls.
  - A small wooden shelf or bracket on the west side, in the entry nook.
- **Floors:** plank floor boards. `basic/2` at (-3,249) for the ground floor, about 406 px long. `basic/3` at (11,58) for the upper floor, about 350 px long.
- **Ground floor:**
  - The exit door at (-220,202) (`prop/door/0`): a round-topped orange plank door with iron hinges, on the west wall.
  - A **bookshelf/cupboard** with jars and books at (-41,207) (`fur/0`, 90×85 px), roughly x -86..4, against the back wall.
  - A **hanging bell lamp** at (9,98).
  - The **ladder** at x=77, in the room's east part.
- **Upper floor:**
  - An **orange wooden bed** with white pillows at (-66,15) (`fur/1`, 128×67 px), roughly x -130..-2, on the west half.
  - A **curtained window** at (37,-37) (`win/0`), on the back wall at the centre.
  - A **treasure chest** at (80,27) (`fur/2`, 77×41 px), roughly x 41..119, on the east half beside the ladder top.
  - A **hanging bell lamp** at (5,-100).
- **Backgrounds:** grassySoil back 0–3, *static* (`rx=ry=0`). The sky shows behind the cut-away.

## 5. What makes this map recognizable

- **It is the only enterable building on the tutorial island's first stretch.** You enter it through the stone-arched door of the orange mushroom house in 20000.
- **A cosy two-storey cut-away.**
  - Downstairs: a cupboard, a lamp and the hungry boy Sen.
  - Up the ladder: a bedroom with an orange bed, a treasure chest and a curtained window under the mushroom-cap roof.
- **The look.** Timber-framed cream walls and a visible orange cap cross-section. [memory] This is the template for the inside of a Maple mushroom house.

## 6. 3D translation [proposal]

All of this section is [proposal].

**Concept: an enterable cut-away interior.**
- Build it as a real room inside the 20000 orange mushroom house model. It could be a separate interior scene loaded by the door, matching the portal.
- The camera's near walls fade or cut down to knee height.
- **Camera note.** With a 45° yaw, the camera faces north-east, so the north and east walls are the "back" walls that carry the furniture. The south and west walls are cut away.
- The exit door is on the **west** wall, as in the data (screen-left). Keep its frame and a low wall stub there so the door stays readable.

**Footprint and heights** (px, from data; depth proposed)
- **Ground floor:** 350 px along x (x -221..129). Suggested depth 220–280 px.
  - **Entry nook:** the west 80 px (x -221..-141). It has the exit door on the west wall and a small wall shelf.
  - **Lintel:** the nook is separated from the main room by a beam whose clear height is 94 px above the floor.
  - **Main room:** 270 px wide with **177 px** of clear height.
- **Upper floor:** 280 px wide (x -142..138), the same depth or 20–30 px less. It has 164 px of clear height under a flat ceiling at y=-117. Above that, the mushroom cap forms a domed roof, so the room can show the sloping cap underside and the truss.
- **Floor slab:** 22 px thick. Place a ladder hatch at the north-east, around x≈77.
- **Ladder:** 195 px, in the north-east corner, going up through the hatch.

**Furniture placement**
- **Ground floor:**
  - The cupboard against the north wall, centre-west (x≈-41).
  - Sen standing centre-east (x≈24), near the ladder.
  - The bell lamp hanging centre (x≈9).
  - The out00 interaction point just inside the door (x≈-167).
- **Upper floor:**
  - The bed along the north wall, west half (x≈-130..-2).
  - The window on the north wall, centre (x≈37).
  - The chest north-east (x≈41..119), next to the hatch.
  - The bell lamp centre.

**Yard**
- Because `sp` is outside (x=-329) and `returnMap` is this map, keep a small exterior stoop or yard pad outside the west door. It is the respawn and fallback entry point.
- Alternatively, move the respawn inside and drop the yard. The yard is 358 px of plain grass in the data.

**Top-down sketch [proposal].** North is up. Screen-left is west. Both floors are shown at the same x scale, about 12 px per character.
```
 GROUND FLOOR (T2, y=246)                     UPPER FLOOR (T3, y=47)
 N (back wall)                                N (back wall, under cap)
 +------+---------------------------+         +-----------------------------+
 |shelf |    [CUPBOARD]  (lamp)  [H]|         | [===BED===]  [window] [CHEST]|
 | nook |                 Sen   hatch         |              (lamp)     [H] |
 [DOOR] | lintel(94px)              |         |                       hatch |
 |out00 |                           |         |                             |
 +------+---------------------------+         +-----------------------------+
 x:-221 -141                       129        x:-142                       138
 yard (T1) continues west of the door   S = camera side (walls cut away)
```

**Side elevation / section (map data, y up).**
```
 y
 -117   +===================================+  upper ceiling; mushroom cap dome above
        |  [bed]        [window]    [chest] |
   47   +=====================H=============+  upper floor T3 (-142..138)
   69     . . . . ceiling . . H . . . . . . |  slab 47..69 (22px), hatch at x77
        | (lamp)              H             |  177px clear
  152   |lintel               H             |
        | nook | [cupboard] Sen H           |
  246  [D]=====|=====T2 ground floor========+  (-221..129)
  275  ==== T1 yard (sp -329) ====             (ground also continues under the house: artifact)
       -579   -221 -141   -41  24  77   129
```

## 7. Version notes

- The geometry, NPC and portal are identical in v8, v22 (`raw/gms_v22/20001.json`) and v28 through v39.
- v28 is the first version whose parsed API exposes out00 directly.

## 8. Open questions

- **Name mismatch.** The canonical name and slug say "Townstreet", but the v8 content is Sen's house interior. Should the project rename it, for example "Mushroom Town: Sen's House", or keep the original string?
- **Yard.** Keep the exterior yard and outdoor respawn, or move the respawn inside?
