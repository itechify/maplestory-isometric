# Map 1010001: "Amherst Weapon Store". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/1010001.struct.json` (tier ids T01..T16 match it).

**Tags**: no tag = data fact (source given). **[visual]** = my reading of a v8 object sprite or render. **[inference]**, **[memory]** and **[proposal]** mean the same as in the other briefs.

**Sources**
- `docs/research/raw/gms_v8/1010001.json` (`/api/GMS/8/map/1010001`): footholds, the rope, the NPC and vrBounds. Its parsed `portals[]` has 1 `null`.
- Raw GMS v8 WZ: `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001010001.img/{portal,life,back,info,<layer>/obj}`.
- Object sprite sizes and origins: `https://maplestory.io/api/wz/GMS/8/Data/Map/Obj/<oS>.img/...`. Viewed in a temp folder only, not copied.
- NPC name: `/api/GMS/8/npc/11000`.
- Render, viewed but not copied: `ref_renders/v8_1010001_render.png`. The `_minimap.png` file is an API error message. The map has no minimap (`miniMap` is empty).

## 0. Map card

| field | value |
|---|---|
| Name | "Amherst Weapon Store" (Rainbow Street), `isTown=true`, returnMap 1010000 |
| BGM | `Bgm00/FloralLife` |
| Room / camera | vrBounds x -400..400, y -300..300. That is a fixed 800 x 600 view with the floor at y=182. |
| Walkable tiers | 16: 1 floor and 15 props / furniture tops. |
| Height range | Floor y=182. Highest walkable is the ceiling beam at y=-263, 445 px above the floor. |
| Ropes | 1 (x=75). |
| Exits | 1: `out00`. |
| Mobs | none |

## 1. Structure

### 1.1 Room shape
- The whole room is one 800 x 600 backdrop object, `insideGS/house0/basic/0`.
  - A floor-strip object (`basic/2`, y 180..207) and a roof-frame object (`basic/1`) sit over it.
- From the render [visual], the floor is a wooden plank strip. The roof frame has timber beams lashed with blue bands, plus a wooden pillar on the left wall.
- The render shows only those roof beams and the pillar. Everything else below comes from the WZ object list.

### 1.2 Tiers

All tiers except T01 are prop tops. The "above floor" column is 182 − y.

| id | kind | x-range | y | above floor | what it is [visual] |
|---|---|---|---|---|---|
| T01 | ground | -400..400 | 182 | 0 | plank floor |
| T02 | floating | 19..113 | 158 | 24 | low step at the foot of the forge machine (grindstone base) |
| T03 | floating | 158..198 | 156 | 26 | metal stair step |
| T04 | floating | 172..214 | 127 | 55 | stair step |
| T05 | floating | 189..301 | 97 | 85 | wide step by the red gauge |
| T06 | floating | 162..202 | 57 | 125 | stair step |
| T07 | floating | 184..228 | 20 | 162 | stair step |
| T08 | floating | 46..263 | -19 | 201 | forge scaffold deck. The rope's bottom is 65 px above it. |
| T09 | slope | 114..173 | -45 → peak -59 → -51 | about 230 | hump of a curved pipe arch |
| T10 | floating | 174..252 | -98 → peak -108 → -97 | about 285 | dome of the green glass tank |
| T11 | floating | 247..342 | -183 | 365 | right roof beam |
| T12 | floating | -185..311 | -263 | 445 | ceiling beam/pipe. The rope's top. |
| T13 | floating | 328..365 | 131 | 51 | barrel top by the right wall |
| T14 | floating | -119..-16 | 139 | 43 | sill of the armor alcove. The `sp` (-114,115) sits right above it. |
| T15 | floating | -345..-208 | -13 | 195 | roof of the NPC booth |
| T16 | floating | -338..-227 | 140 | 42 | Sid's stand inside the booth |

**Ceilings and the booth box**
- The booth is two closed foothold boxes.
- Outer box: walls at x=-345 and -208 running y -13..150. Top -13 is walkable. Underside at y=150 is a ceiling (right-to-left foothold).
- Inner box: floor 140 for the NPC, walls at x=-338 and -227, ceiling at y=13.
- [inference] The walls stop at y=150, above floor level, so the player walks freely along the floor in front of the booth.
- [inference] You cannot jump onto the booth roof (195 px) from the floor. You can only drop onto it from the left end of the ceiling beam T12 (x=-185), about 250 px higher and 23 px to the right.

### 1.3 Rope

| x | y1→y2 | type | from → to | climb | bottom gap |
|---|---|---|---|---|---|
| 75 | -261→-84 | rope | T08 → T12 | 177 | 65 (jump to grab from the scaffold deck) |

- The rope object is `connect/rope/1/0` at (45,-173), WZ layer 2.

### 1.4 Climb route [inference]
1. Floor T01.
2. T02 or T03.
3. T04.
4. T05.
5. T06.
6. T07: a zig-zag "staircase" of 24..40 px hops up the right side of the forge machine.
7. Scaffold deck T08.
8. Jump-grab the rope.
9. Ceiling beam T12.

Side perches:
- From T08, the pipe arch T09 and then the tank dome T10.
- From the dome, the roof beam T11, 75 px higher.

This is an optional "climb into the rafters" mini-course. There is nothing to collect up there in the data.

- [inference] Some hops in this route are above the 60 px standard step: the 65 px rope grab from T08 and the 75 px dome→roof-beam hop. Whether they clear depends on the real jump height, which I did not check.

## 2. Portals

| name | pt | x, y | tier | target |
|---|---|---|---|---|
| out00 | 2 | -48, 181 | T01 | 1010000:in00 (Amherst, the Weapon Store door on the upper plateau) |

- `inferred=false`. Source: WZ `portal/1`, which is also parsed in v44 `/api/GMS/44/map/1010001`.
- The door is a plain visible portal (pt=2) at the floor's centre-left. No door object is drawn there [visual].
- [inference] You arrive at `out00` when you come in from Amherst.
- `sp` (-114,115) is the default spawn and drops you onto T14.

## 3. Spawns

| id | name | x, y | tier |
|---|---|---|---|
| 11000 | Sid | -270, 140 | T16 (inside the booth) |

- Sid's dialogue (`/api/GMS/8/npc/11000`): "On sale! Really CHEAP!", "Welcome!! Hahahaha!".
- [memory] Sid is the Amherst weapon-shop keeper.
- No mobs.

## 4. Look (WZ objects; descriptions are [visual])

| element | WZ object | bbox [l,t,r,b] |
|---|---|---|
| room backdrop: back wall, pipes, timber frame | `insideGS/house0/basic/0` | -400,-300,400,300 |
| wooden NPC booth (Sid), boarded wooden stall | `shop/shop/weapon/20`, `/19` | -356,-147,-141,185 |
| pipe-and-wall panel left of centre | `shop/shop/weapon/5` | -352,-141,39,146 |
| window in the back wall showing big gears | `shop/shop/weapon/16`, `/0` | -132,-142,39,-13 |
| chained dark armor in a wall alcove | `shop/shop/weapon/10` | -121,25,-30,137 |
| small display piece beside the booth | `shop/shop/weapon/7` | -204,54,-136,158 |
| ceiling beam/pipe (carries T12) | `shop/shop/weapon/6` | -265,-344,365,-152 |
| **forge machine**: domed furnace with a glowing mouth, green glass tank, pipes | `shop/shop/weapon/2` | 10,-153,397,183 |
| metal step-scaffold beside the forge | `shop/shop/weapon/18` | 46,-19,301,183 |
| sacks on the floor | `shop/shop/weapon/12` | 241,135,314,183 |
| barrel stuffed with weapons | `shop/shop/weapon/11` | 312,51,391,182 |

- Terrain style: interior only. Wooden plank floor, timber and pipe workshop walls.
- WZ lists `tS=coalMine`, but no tile footholds are drawn; the props make the terrain.
- `back` has one empty entry (`bS=""`), so there is no backdrop beyond the room.

## 5. What makes it recognizable
- It is a **forge workshop**, not a plain store: a glowing domed furnace with a green glass tank, gear-and-pipe walls and a chained armor display (data + [visual]).
- Sid sells from a boarded wooden booth in the back-left corner (data).
- There is a climbable machine and stair stack up to a ceiling beam with a hanging rope (data).

## 6. 3D translation [proposal]

### 6.1 Room
- A cutaway box room, 800 px wide.
- The back wall and left wall are visible. The front and right walls are cut away or fade out.
- Make the room about 300..400 px deep (front-to-back) so the forge machine can sit in the back-right corner with space around it.

### 6.2 Placement
- **Booth**: back-left corner. It is a counter you walk in front of. Sid stands behind it at the T16 height (about 42 px above the floor).
- **Armor alcove and gear window**: back wall, centre-left. The alcove sill T14 becomes a low ledge (43 px).
- **Forge machine**: back-right. The stair steps T02..T07 become a **spiral or switchback metal stair** wrapped around the furnace's front-right side, with each step 24..40 px apart.
  - The scaffold deck T08 is a grated platform over the furnace.
  - The pipe hump T09 and tank dome T10 are perches.
- **Ceiling beam T12**: a rafter running left-to-right across the room at the back, 445 px over the floor. The rope hangs from it at x=75 over the scaffold deck.
  - The beam's left end overhangs the booth roof T15, so the "drop onto the booth" trick stays possible.
- **Exit `out00`**: a doorway in the **front-left** of the room at floor level, near x=-48. It is the spot you arrive at.
  - [proposal] Show it as a door frame in the cut-away front wall plus a glowing floor marker, so it never hides behind props.

### 6.3 Top-down sketch [proposal]

Screen-left = map west.

```
  back wall:  [booth Sid]  [gear window][armor alcove]          [FORGE + tank]
              (T15 roof)        (T14 sill)            switchback stair T02..T07
  +---------------------------------------------------------------+
  |  booth            alcove            scaffold T08 / beam T12 above |
  |                                     rope x75 hangs here           |
  |                    out00 (floor, front-left)     sacks  barrel T13|
  +---------------------------------------------------------------+
  front (cut away, toward camera)
```

### 6.4 Side elevation (data heights)

```
 y-263  ========T12 ceiling beam (-185..311)=========
 y-183                                   T11 beam ==
 y-108                      rope x75   T10 dome
 y -59                         |  T09 arch
 y -19                     ====T08 deck====
 y -13  T15 booth roof            T07 = (20)
 y  57                            T06 = (57)
 y  97                              T05 === (97)
 y 127                             T04 =      T13 barrel(131)
 y 139  T16(140)  T14 sill   T02(158) T03(156)
 y 182  ===========T01 floor===[out00 x-48]===========
 x:    -400  -345 -208  -119 -16  19  113 158  263 301  365 400
```
