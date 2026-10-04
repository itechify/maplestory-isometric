# Map 1010002: "Amherst Townstreet". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/1010002.struct.json` (tier ids T01..T04 match it).

**Tags**: no tag = data fact (source given). **[visual]** = my reading of a v8 object sprite or render. **[inference]**, **[memory]** and **[proposal]** mean the same as in the other briefs.

**Sources**
- `docs/research/raw/gms_v8/1010002.json` (`/api/GMS/8/map/1010002`): footholds and the ladder. Its parsed `portals[]` has 2 `null`.
- Raw GMS v8 WZ, which has both exits: `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001010002.img/portal/{1,2}`. The same tree gives `life` (empty), `back`, `info` and `1/obj`.
- Object sprite sizes: `https://maplestory.io/api/wz/GMS/8/Data/Map/Obj/...`. Viewed in a temp folder only, not copied.
- Render, viewed but not copied: `ref_renders/v8_1010002_render.png`. It shows only the grass-and-earth ground strip and one embedded rock. The house is missing.
- `_minimap.png` is an API error. The map has no minimap data.

## 0. Map card

| field | value |
|---|---|
| Name | "Amherst Townstreet" (Rainbow Street), `isTown=true`, returnMap 1010000 |
| BGM | `Bgm00/FloralLife` |
| Foothold extent | x -579..399 (978 px). Walkable y 47..275. Edge walls reach down to y=480. vrBounds is empty. |
| Walkable tiers | 4: street, house ground floor, under-house strip, house upper floor. |
| Ladders | 1 (x=77, a real ladder). |
| Exits | 2. `out00` goes back to Amherst. **`west00` goes on to 1010004 "Snail Field of Flowers"**. |
| Mobs / NPCs | none / none |

## 1. Structure

### 1.1 Tiers

| id | kind | x-range | y | length | notes |
|---|---|---|---|---|---|
| T01 | ground: street west of the house | -579..-221 | 275 | 358 | West wall at x=-579. `west00` and `sp` are here. At x=-221 a 29 px wall rises to T02. |
| T02 | ledge: house ground floor | -221..129 | 246 | 350 | A 29 px doorstep above the street. Right wall at x=129 (y 69..246). Ceiling at y=69 over x -141..129. A partial left wall at x=-141 hangs down from the ceiling to y=152. Ladder x=77 goes up from here. |
| T03 | ground: strip under/behind the house | -221..399 | 275 | 620 | East wall at x=399. [inference] It is reachable only by dropping down from T02: the street foothold's `next` link at x=-221 is the 29 px wall, so you cannot walk onto it from T01. |
| T04 | floating: house upper floor | -142..138 | 47 | 280 | A closed room: walls at x=-142 and x=138 run y -117..47, and the ceiling is at y=-117 (164 px headroom). Ladder x=77 arrives here. |

**House shell, read from the footholds [inference]**
- Ground-floor room:
  - x -221..129, floor 246, ceiling 69 (177 px of headroom).
  - The doorway is on the **west** side: between x=-221 (doorstep) and the lintel wall at x=-141, which ends at y=152.
  - That leaves a 94 px opening (y 152..246).
- Floor slab between storeys: y 47..69, 22 px thick.
  - Object `insideGS/house1/basic/3`, bbox y 47..69, matches it exactly.
- Upper room: x -142..138, floor 47, ceiling -117.

### 1.2 Ladder

| x | y1→y2 | type | from → to | climb | bottom gap |
|---|---|---|---|---|---|
| 77 | 49→244 | **ladder** | T02 → T04 | 195 | 2 |

- The ladder object is `connect/ladder/1/0` at (77,142).
- It passes through the floor slab, as in the data.

## 2. Portals (raw WZ; `inferred=false`)

| name | pt | x, y | tier | target | notes |
|---|---|---|---|---|---|
| out00 | 2 | -167, 244 | T02 | 1010000:in01 (Amherst, the orange-spotted house door at x=2276) | Just inside the house's west doorway. You arrive here from Amherst. |
| west00 | 2 | -492, 275 | T01 | **1010004:east00 (Snail Field of Flowers)** | 87 px in from the west wall. A DANGER sign stands 80 px east of it. |

- `sp` at (-329,241) on T01.
- `out00` was also parsed by `/api/GMS/44/map/1010002`. `west00` appears only in the raw WZ.

## 3. Spawns
None. `life` is empty in WZ, and `npcs`/`mobs` are empty in the JSON.

## 4. Look (WZ objects; descriptions are [visual])

| element | WZ object | bbox [l,t,r,b] | on |
|---|---|---|---|
| **cutaway two-storey mushroom house**: big orange-brown cap, cream walls, timber frame | `insideGS/house1/basic/0` | -275,-259,340,274 | T02 |
| ground-floor room interior | `insideGS/house1/basic/4` | -256,47,214,246 | T02 |
| upper-floor room interior | `insideGS/house1/basic/1` | -208,-217,237,47 | T04 |
| floor strip / floor slab | `insideGS/house1/basic/2`, `/3` | -206,244,200,254 / -164,47,186,69 | |
| wooden arched front door (west wall) | `prop/grassySoil/door/0` | -254,159,-186,246 | T02 |
| bookcase / cabinet | `prop/grassySoil/fur/0` | -86,165,4,250 | T02 |
| bed | `prop/grassySoil/fur/1` | -130,-18,-2,49 | T04 |
| chest | `prop/grassySoil/fur/2` | 42,7,119,48 | T04 |
| curtained window | `prop/grassySoil/win/0` | 1,-68,74,-6 | T04 |
| hanging lamps | `prop/grassySoil/lamp/0` x2 | at (9,98) and (5,-100) | both floors |
| wooden ladder | `connect/ladder/1/0` | x 62..92, y 47..246 | T02→T04 |
| **DANGER sign**: triangular board with a skull | `guide/midForest/danger/2` | -445,195,-378,272 | T01 |
| flower bed (orange flowers) and bush | `acc1/grassySoil/nature/5`, `/6`, `/13`, `/21` | -496..-213, 132..295 | T01 |

- Terrain: grass-topped brown earth with an embedded rock (render). WZ layer 1 lists `tS=grassySoil`.
- Background: `grassySoil` set, `no` 0..3. `no=0` is `type=3` (tiled); `no=1..3` are `type=0` (static), all with parallax 0.

## 5. What makes it recognizable
- Inside the **orange mushroom house** you just entered from Amherst: a doll-house-style cutaway with a bookcase downstairs, and a bed, chest and window upstairs, joined by a wooden ladder (data + [visual]).
- Out the west door is a short garden path with a **DANGER sign**. This is the back way out of town to the Snail Field of Flowers (data).
- [memory] I do not remember this map from play. Everything here is from data and sprites.

## 6. 3D translation [proposal]

### 6.1 Core idea
- Treat Townstreet as **the inside of Amherst's orange house plus its back garden**.
- Build the house as a cutaway with both storeys visible: the front and right walls are removed and the mushroom cap is cut in section.
- The west door opens onto a garden path that leads to the west exit.
- If the framework allows, make it continuous with Amherst: entering `in01` on the east street drops you in this interior.
  - The 3D house exterior in Amherst and this interior should share proportions: an outer shell about 615 px wide, two storeys of about 177 px and 164 px.

### 6.2 Tiers in 3D
- **T02 ground floor**: a raised wooden floor, one 29 px doorstep up from the garden path.
  - Bookcase against the back wall. A lamp.
  - The ladder sits in the back-right corner (x=77).
- **T04 upper floor**: the bedroom, with bed, chest and window on the back wall. You reach it only by the ladder, which comes up through a hatch in the 22 px floor slab.
- **T01 garden path**: 358 px from the door westward. A flower bed and bush, then the DANGER sign just before the `west00` exit.
  - [proposal] Show it as a little gate or a trail-head marker leading into the Snail Field of Flowers.
- **T03 under-house strip**: in 3D, a small **back garden / crawl-space** behind and under the house, 620 px long.
  - Reach it by a gap or trapdoor that drops from the ground floor, matching the data's drop-only access.
  - The framework may also choose to cut it. It holds no content in the data.

### 6.3 Top-down sketch [proposal]

Screen-left = map west.

```
  (back)
  +---------+-----------------------------------+
  | flowers |  [house back wall: bookcase ...]  |  back garden (T03, drop-only)
W>| west00  |  door] T02 ground floor  ladder[] |
  | DANGER  |       (upper floor T04 above)     |
  | sign    |                                   |
  +---------+-----------------------------------+
     garden path T01            (front cut away, toward camera)
```

### 6.4 Side elevation (data heights)

```
 y -117          +======T04 ceiling=====+
 y   47          | bed  T04 floor  chest|   (22px slab to y69)
 y   69   +======+=====ceiling=========[#]  ladder x77
 y  152   | lintel x-141               [#]
 y  246   |door T02 ground floor  case [#]  wall x129
 y  275 ===T01 path==+(29px step)              ====T03 strip (drop-only)====
 x:  -579  -492  -221 -142      77  129                          399
          west00   out00 at x-167
```
