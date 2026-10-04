# Map 1010003: "Amherst Department Store". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/1010003.struct.json` (tier ids T01..T22 match it).

**Tags**: no tag = data fact (source given). **[visual]** = my reading of a v8 object sprite or render. **[inference]**, **[memory]** and **[proposal]** mean the same as in the other briefs.

**Sources**
- `docs/research/raw/gms_v8/1010003.json` (`/api/GMS/8/map/1010003`): footholds, NPC and vrBounds. Its parsed `portals[]` has 1 `null`.
- Raw GMS v8 WZ: `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/001010003.img/{portal,life,back,info,<layer>/obj}`.
- `out00` is also parsed in `docs/research/raw/gms_v22/1010003.json`.
- Object sprite sizes: `https://maplestory.io/api/wz/GMS/8/Data/Map/Obj/shop.img/shop/grocery/<n>/0`, etc. Viewed in a temp folder only, not copied.
- NPC name: `/api/GMS/8/npc/11100`.
- Render, viewed but not copied: `ref_renders/v8_1010003_render.png`. It shows the roof beams, the left pillar, the WELCOME booth and the plank floor.
- `_minimap.png` is an API error; there is no minimap.

## 0. Map card

| field | value |
|---|---|
| Name | "Amherst Department Store" (Rainbow Street), `isTown=true`, returnMap 1010000 |
| BGM | `Bgm00/FloralLife` |
| Room / camera | vrBounds x -400..400, y -300..300 (fixed 800 x 600 view). |
| Floor | y=182. It is duplicated by a second full-width foothold at y=184 on another layer (L3 vs L1). |
| Walkable tiers | 22: 1 floor and 21 furniture tops. |
| Height range | Floor 182. Highest walkable is the ceiling crossbeam at y -127..-129, about 310 px above the floor. |
| Ladders | none |
| Exits | 1: `out00`. |
| Mobs | none |

## 1. Structure

### 1.1 Room shape
- The room backdrop is `insideGS/house0/basic/0`, 800 x 600: the same shell as the Weapon Store.
- On top of it [visual]: a timber-frame back wall with beams (`shop/shop/grocery/0`) and a ceiling crossbeam (`grocery/10`).
- From the render: plank floor, thatch-and-timber roof beams top-left and top-right, a stone-and-wood pillar at the far left.

### 1.2 Tiers (left to right, grouped by furniture)

| id | kind | x-range | y | above floor | what it is [visual] |
|---|---|---|---|---|---|
| T01 | ground | -400..400 | 182 (and 184) | 0 | plank floor |
| T21 | floating | -348..-198 | -27 | 209 | roof of the WELCOME booth (unreachable from the floor) |
| T22 | floating | -333..-213 | 84 | 98 | Lucy's stand inside the booth (enclosed) |
| T03 | floating | -178..-117 | 98 | 84 | upper crate |
| T02 | floating | -160..-99 | 141 | 41 | lower crate. `sp` (-114,115) drops onto it. |
| T04 | floating | -110..28 | 147 | 35 | low bench of books |
| T05 | floating | -100..42 | 103 | 79 | book-table top |
| T06 | floating | -86..4 | 59 | 123 | small shelf above the table |
| T07 | floating | -153..-56 | 31 | 151 | potion shelf, bottom board |
| T08 | floating | -159..-51 | 3 | 179 | potion shelf, middle board |
| T09 | floating | -162..-51 | -25 | 207 | potion shelf, top board |
| T10 | floating | 79..232 | 145 | 37 | pole-shelf, low wide board |
| T11 | floating | 61..108 | 120 | 62 | pole-shelf board with a jar |
| T12 | floating | 108..220 | 103 | 79 | pole-shelf board |
| T13 | floating | 59..109 | 72→73 | 110 | pole-shelf board with a jar |
| T14 | floating | 91..174 | 57 | 125 | pole-shelf board |
| T15 | floating | 62..108 | 22 | 160 | pole-shelf board with a jar |
| T16 | floating | 65..220 | -43 | 225 | pole-shelf top board |
| T17 | floating | 163..259 | 7 | 175 | top of the wall poster frame |
| T18 | floating | 234..358 | -28 | 210 | wall shelf holding the treasure chest |
| T19 | floating | 288..335 | -62 / -60 | 244 | treasure chest lid |
| T20 | floating | -128..305 | -127→-129 | about 310 | ceiling crossbeam |

**Booth boxes**
- The booth is a closed box like the Weapon Store's.
- Outer box: walls at x=-348 and -198 run y -27..92. Top -27 is walkable. Underside 92 is a ceiling.
- Inner box: floor 84 for the NPC, walls at x=-333 and -213, ceiling -12.
- [inference] The walls end at y=92, so the player walks freely along the floor in front of the booth.

**Climb routes [inference]** (hops of about 60 px or less)
- **Left stack**:
  1. Floor.
  2. Bench T04 (35) or crate T02 (41).
  3. Crate T03 (98) or table T05 (103).
  4. Shelf T06 (59).
  5. Potion boards T07, T08, T09 (31, 3, -25), going sideways.
- **Right stack**:
  1. Floor.
  2. T10 (145).
  3. T11 (120) or T12 (103).
  4. T13 (72) or T14 (57).
  5. T15 (22).
  6. Top board T16 (-43).
  7. Then either the wall shelf T18 (-28), across a 14 px gap at x 220→234, or the poster top T17.
  8. Chest lid T19 (-62).
  9. Ceiling beam T20 (-127), a 65 px jump.
- The beam spans x -128..305 and joins the two stacks overhead.
- [inference] The final chest-lid→beam jump (65 px) is above the 60 px standard step. Whether it clears depends on the real jump height, which I did not check.

## 2. Portals (raw WZ; `inferred=false`)

| name | pt | x, y | tier | target |
|---|---|---|---|---|
| out00 | 2 | 300, 182 | T01 | 1010000:in02 (Amherst, the Department Store door on the middle terrace) |

- `out00` is drawn in front of the **wooden exit door with a "Thank you" sign**, `shop/shop/grocery/3`, bbox 264..368 x 42..186, at the right end of the room [visual].
- You arrive here from Amherst.
- `sp` is at (-114,115).

## 3. Spawns

| id | name | x, y | tier |
|---|---|---|---|
| 11100 | Lucy | -258, 84 | T22 (inside the booth) |

- Lucy's dialogue (`/api/GMS/8/npc/11100`): "Ok, cheap goods! Really cheap!!", "Hey you!! Don't even think about stealing in here...", "You definitely need potions to travel".
- No mobs.

## 4. Look (WZ objects; descriptions are [visual])

| element | WZ object | bbox [l,t,r,b] |
|---|---|---|
| room backdrop (timber-frame shop interior) | `insideGS/house0/basic/0` | -400,-300,400,300 |
| **WELCOME booth**: orange "WELCOME" arch sign, cream banner with a money-bag emblem, a pinned note | `shop/shop/grocery/12`, `/13` | -356,-153,-180,183 |
| back-wall beams and ceiling crossbeam | `shop/shop/grocery/0`, `/10` | -350,-143,358,101 |
| wall shelf with red and blue potion bottles | `shop/shop/grocery/1`, `/6`, `/7` x2 | -178,-64,-36,48 |
| two stacked wooden crates | `shop/shop/grocery/5` x2 | -181,98,-99,184 |
| low table with books | `shop/shop/grocery/4` | -117,59,48,183 |
| **tall post with plank shelves and lidded jars** | `shop/shop/grocery/15`, `/2` | 58,-228,322,182 |
| parchment poster/map on the wall | `shop/shop/grocery/14` | 153,12,253,128 |
| wall shelf with a red-and-gold treasure chest | `shop/shop/grocery/16`, `/19` | 234,-62,358,4 |
| arched wooden exit door with a "Thank you" plaque | `shop/shop/grocery/3` | 264,42,368,186 |

- Terrain style: interior. Plank floor, timber frame, thatch roof beams.
- `back` has one empty entry, so there is no backdrop beyond the room.

## 5. What makes it recognizable
- The **WELCOME booth** with its money-bag banner on the left, and the "Thank you" door on the right (data + render).
- Potion bottles on a wall shelf (Lucy: "You definitely need potions to travel").
- The jar-laden **pole shelf** and the **treasure chest** high on the right wall (data + [visual]).
- The same 800 x 600 shell and roof beams as the Weapon Store, so the two shops read as a pair (data).

## 6. 3D translation [proposal]

### 6.1 Room
- A cutaway box room, 800 px wide, sharing the shell with the Weapon Store. That lets one kit serve both shops.
- Depth about 300..400 px.
- Back wall: the potion shelf, the poster and the chest shelf. Left wall: the booth.

### 6.2 Placement
- **Booth** (back-left corner): a counter facing the room. Lucy stands about 98 px above the floor behind it, so only her upper body shows, as in the data (NPC y=84 against a booth front reaching down to y 183).
- **Left stack** (centre-left, against the back wall): crates, then the book table, then the potion shelf. A clear 35-60 px hop staircase.
- **Pole shelf** (centre-right, free-standing): a "shelf tree" post with 7 boards spiralling around it (T10..T16). In 3D, rotate the boards around the post so the climb spirals in depth.
- **Ceiling crossbeam T20**: a beam across the back of the room at about 310 px. It is the hidden top route linking the pole-shelf top, the chest shelf and the left stack.
- **Exit door**: on the right wall near the front corner (x≈300), with the "Thank you" plaque. It is the arrival point.

### 6.3 Top-down sketch [proposal]

Screen-left = map west.

```
  back wall: [booth Lucy] [potion shelf][book table]  [pole-shelf]  [poster][chest shelf]
  +-------------------------------------------------------------------------------+
  | booth     crates                       (ceiling beam T20 above, -128..305)    |
  |                                                                  out00 door ->|
  +-------------------------------------------------------------------------------+
  front (cut away, toward camera)
```

### 6.4 Side elevation (data heights)

```
 y-129     ==========T20 ceiling crossbeam (-128..305)==========
 y -62                                              T19 chest
 y -43                          T16 ==========      T18 shelf (-28)
 y -27  T21 booth roof   T09 potion
 y   3                   T08 potion          T17 poster (7)
 y  31                   T07 potion   T15 =
 y  57               T06 =             T14 ==
 y  72                                T13 =
 y  84  T22 Lucy     T03 crate(98)  T05 table(103)  T12 == (103)
 y 120                                T11 =
 y 141               T02 crate  T04 bench(147)  T10 ===== (145)
 y 182  ================T01 floor========================[out00 x300]==
 x:   -400  -348 -198 -178 -99  -110 42   59    220 234  358 400
```
