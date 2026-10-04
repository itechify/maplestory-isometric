# Map 20000: "Mushroom Town". Structural analysis and 3D translation brief

Machine-readable companion: `docs/research/maps/20000.struct.json`

**Tags used in this brief**
- No tag: a fact taken from data. The source is given.
- **[inference]**: my reading of the data.
- **[memory]**: something I remember about the game, unsourced.
- **[proposal]**: a design suggestion.

**Sources**
- `docs/research/raw/gms_v8/20000.json`, from `https://maplestory.io/api/GMS/8/map/20000`.
- Raw WZ:
  - The API JSON has `portals[4]` and `portals[5]` as `null`. I recovered both from `https://maplestory.io/api/wz/GMS/8/Map/Map/Map0/000020000.img/portal/4` and `/portal/5`:
    - `in01 pt=2 tm=20001 tn=out00 x=557 y=94`
    - `out00 pt=2 tm=30000 tn=in00 x=795 y=96`
  - Objects come from `.../000020000.img/<layer>/obj/<n>`.
- Sprites were viewed at `https://maplestory.io/api/wz/GMS/8/Map/Obj/...`, in a temp folder only.
- NPC: `https://maplestory.io/api/GMS/8/npc/2102`.
- Renders: `ref_renders/v8_20000_render.png` and `v8_20000_minimap.png`.
- Version comparison: `raw/gms_v22/20000.json`.

## 0. Map card

| field | value (v8) |
|---|---|
| Street / name | "Maple Road" / "Mushroom Town" |
| isTown / returnMap | `true` / `20000` |
| BGM / mapMark | `Bgm00/FloralLife` / `MushroomVillage` |
| Foothold extent | x -309..939 (1248 px). Walkable y runs -85..215 (300 px). Wall bottoms reach y=420. |
| Walkable tiers | 5: 3 terrain tiers and 2 floating islets. |
| Ladders | 1 |
| Mobs | none |
| Portals | in00 is the west arrival point. in01 is a house door to 20001. out00 leads east to 30000. |

## 1. Structure

### 1.1 Tiers

"Units" counts steps of 60 px above T1 (y=215).

| id | kind | x-range | y | length | height | layer/group | footholds | connects to |
|---|---|---|---|---|---|---|---|---|
| T1 | ground (west lawn) | -309..141 | 215 | 450 | 0 | 1/0 | 12,3,13,6,2,8,7 | West end is a wall at x=-309 (map edge). It rises 60 px at x=141 to T2. |
| T2 | ledge (step) | 141..231 | 155 | 90 | +1 | 1/0 | 31,26,32 | Rises 60 px at x=231 to T3. Ladder foot at x=197 goes up to T5. |
| T3 | ground (upper terrace / town street) | 231..939 | 95 | 708 | +2 | 1/0 | 18,24,10,29,14,9,16,15,21,22 | `in01` at x=557 and `out00` at x=795. East end is a wall at x=939 (map edge). |
| T4 | floating (Nina's flower islet) | -129..39 | 95 | 168 | +2 (120 above T1) | 1/2 | 38,39,35 (walls 37,36) | Nothing. No ladder. |
| T5 | floating (sky islet) | 141..309 | -85 | 168 | +5 (240 above T2) | 1/7 | 41,44,42 (walls 40,43) | Ladder x=197 down to T2. |

**Walls**
- Map edges: x=-309 (y 215..420) and x=939 (y 95..420).
- Step faces: x=141 (215→155) and x=231 (155→95), 60 px each.
- Islet side walls: 25 px stubs.

**Gaps:** none in the walkway. Both islets float freely.

**Vertical layering**
- Low: T1, the lawn.
- Step: T2.
- Upper: T3, the street, and T4, Nina, which is at the same height but off to the west, floating.
- Sky: T5.

**Reachability [inference]**
- T4 sits 120 px above T1, with no ladder.
- Its nearest edge from walkable ground is T2's west end, which is 102 px away horizontally and 60 px lower.
- So Nina's islet is most likely a display perch, talked to from below. Confirm against the jump physics when prototyping.
- T5 holds no objects or NPCs. It is a lookout reached only by the ladder.

### 1.2 Ladders and ropes

| x | y1 (top) → y2 (bottom) | type | joins | length |
|---|---|---|---|---|
| 197 | -83 → 153 | ladder (`isLadder: true`) | T2 → T5 | 236 px |

The ladder is drawn as 6 sprites (`connect/ladder/0`) at x=197, y -92..131.

## 2. Portals

| name | pt | x, y | target | notes |
|---|---|---|---|---|
| sp ×3 | 0 | (-256,122), (-207,123), (-173,125) | n/a | Above the west end of T1. |
| **in00** | 1 | (-207, 218) | none (`tm 999999999`) | Arrival point for 10000:out00, 102 px from the west wall. |
| **in01** | 2 | **(557, 94)** | **20001:out00** | The house door. It sits under the stone-arch doorway (`door/8` and `door/10`), whose sprites cover about x 485..625. Two-way: 20001:out00 returns here. |
| **out00** | 2 | **(795, 96)** | **30000:in00** | East exit, 144 px short of the east wall. It sits at the foot of the stone chimney/oven tower (`house/chimney/3`). That sprite has a small arched door at about (792,55), directly above the portal. |

- **Edge exits:**
  - The west has the arrival point only. There is **no portal back to 10000**.
  - The east exit is `out00`, placed near the east end of the upper street rather than at the very edge.

## 3. Spawns

**Mobs:** none in v8 or v22.

**NPCs**

| NPC | id | x, y | tier | dialogue (from `/api/GMS/8/npc/2102`) |
|---|---|---|---|---|
| **Nina** | 2102 | (-59, 95) | T4, the floating flower islet above the west lawn | "What would be good for dinner?" / "I'm cute, right?" |

## 4. Visual reference

### 4.1 Terrain

- **What the render shows** (`v8_20000_render.png`):
  - The grassySoil tiles: bright grass fringe over olive/khaki-brown cobbled dirt with embedded grey stones.
  - The low west lawn, a one-tile step, and the tall raised upper terrace, drawn as a solid earth block down to the map bottom.
  - Two **oval floating grass islets** with rounded, crumbly dirt undersides: Nina's at T4 and the sky islet at T5.
  - A single clover patch.
- **Tile counts:** layer 1 holds all 108 tiles.

### 4.2 Objects

These come from the WZ object list. They are listed west to east.

- **T4, Nina's islet:**
  - A dark green bush at (-89,85).
  - 5 orange tulip-like flowers (`nature/5`, `nature/6`) at x -37..8.
  - A yellow butterfly at (18,39).
- **T1, west lawn:** clover-and-pink-flower patches at (-25,184) and, in the front layer, (52,188).
- **The ladder** at x=197.
- **T3, upper terrace:**
  - A butterfly and orange flowers at (337,21–67) and a green bush at (380,30).
  - A **stone archway with a plank door** (`door/8` and `door/10`) at x≈555–565. This is the in01 entrance.
  - **The orange mushroom house** (`houseGS/house6`, the same model as map 0's house but without the yellow spots):
    - Cream body anchored at (597,14), roughly x 457..737.
    - Orange cap anchored at (606,-88), roughly x 447..765 and y -175..-1.
  - **Red-spotted amanita mushrooms** at (678,43), beside the house front.
  - **A tall stone chimney/oven tower** (`house/chimney/3`), anchored at (750,-46) and 187×279 px:
    - A round stone base with a small dark arched door.
    - A log pile strapped on the side.
    - A wooden barrel flue on top.
    - It stands against the house's east side. out00 sits at its little door.
  - An olive bush at the east end, (833,44).
- **Backgrounds:** grassySoil back 0, 1, 2, 3, 5 and 6, as on map 0.

### 4.3 Missing from the render

- The house, archway, tower, all flowers and bushes on T3 and T4, the ladder sprite and the sky.
- The minimap shows the orange house, the red amanitas, the dark tower and the bushy islet.

## 5. What makes this map recognizable

- **The orange mushroom house with a stone-arched door** that you can actually *enter*. It leads to 20001, Sen's two-storey house. In these five maps, this is the only building with a working door.
- **The stone oven/chimney tower** with its tiny arched door. The exit to the East Entrance is right in front of it.
- **Nina perched on a floating flower islet** above the lawn.
- **A tall ladder from a single grass step up to an empty sky islet.** [inference] It works as a climbing playground.
- **The layout.** Low west lawn, one step, then a long raised town terrace. Everything in this map steps *up* from west to east.

## 6. 3D translation [proposal]

All of this section is [proposal].

**Concept: "the town terrace".**
- You arrive on a low lawn.
- A broad single step climbs onto a raised town terrace. Its north side is the town's landmark pair: the enterable orange mushroom house and the stone oven tower.
- The exit to the East Entrance passes the tower's little door.

**Tiers to 3D**
- **T1 west lawn** (450 px along x; suggested depth 300–400 px):
  - An open lawn with clover beds. in00 is a pad at its west edge, where players arrive from map 10000's east end.
  - **Nina's islet** (168 px wide, +120 px) floats over the lawn's north-west quarter:
    - An oval floating grass islet with a crumbly dirt underside, a dark bush and orange flowers.
    - Nina sits on it, and the talk radius reaches the lawn.
    - If floating islands are kept out of town scenes, the alternative is a tall mossy rock pillar or a giant tree stump at the same height.
- **T2 step** (90 px along x, +60 px):
  - One broad grass terrace step, 250–350 px deep, running across the lawn's east edge like a long bench of earth.
  - The ladder rises from its north part.
- **T5 sky islet** (168 px wide, +240 px above the step):
  - Keep it as a floating grass islet above the step, reached by a 236 px wooden ladder that hangs from it.
  - Or make it the cap of a giant mushroom with the ladder strapped to the stalk, which fits Mushroom Town.
  - It is a lookout over the town, with no NPCs.
- **T3 upper terrace** (708 px along x; suggested walkable depth 260–340 px; +2 units):
  - The town's main plaza. Its west and south faces are 60 px dirt retaining walls with grass lips.
  - **North side, west to east:**
    1. Flowers and a bush.
    2. The **orange mushroom house**, with its stone-arched door facing south at x≈557. This is the in01 interaction point.
    3. The red amanitas.
    4. The **stone oven tower**, with its little arched door facing south-east.
  - **out00 (x≈795)** sits on the plaza right in front of the tower door. Two options:
    - Make the exit a short passage *through* the tower base, coming out east toward the East Entrance (30000).
    - Or place it in a gap between the tower and the east hedge.
  - The east edge beyond it is closed by bushes.
- **Spawn area:** the 3 `sp` and in00, all at the west end of T1. No mob areas.

**Top-down sketch [proposal].** North is up. Screen-left is map west. About 18 px per character along x.
```
 N (back)
 +----------------------------------------------------------------------+
 | hedge/trees   (o) T4 NINA islet +2      |  ( T5 SKY ISLET +5 )   _______________   ____  |
 |               (flowers, floating)       |     ^ ladder (236px)  / ORANGE MUSHROOM\ |TOWER| bush
 |                                         |     |                 \ HOUSE  [arch]  / |[d]  |
 |                                         |  T2 |   T3 UPPER TERRACE +2   in01 v  (amanitas) v out00 ==> E: to 30000
 |  *in00     T1 WEST LAWN 0     (clover)  | STEP+1                                          |
 |  sp sp sp                               |__/  ~~ south rim: 60px dirt face, grass lip ~~  |
 |   ~~ south verge: flowers / bushes ~~                                                     |
 +----------------------------------------------------------------------+
 W edge: closed (no return)                                          S (front, camera)
```

**Side elevation (map data).** One unit is 60 px above T1 (y=215).
```
 units
 +5 |                      === T5 sky islet (141..309) ===
    |                          H ladder x197 (236px)
 +2 |     == T4 Nina ==        H     ============== T3 ====[in01 557]=========[out00 795]=====|
 +1 |      (-129..39)     ===T2====/  (231)                (house)            (tower)
  0 | =========T1==========|  (141..231)
    +--------------------------------------------------------------------------------------
     -309  in00(-207)  -129  39 141 197 231                557                   795        939
```

## 7. Version notes

- **v22** (`raw/gms_v22/20000.json`) extends T3 east to x=1209, versus 939 in v8. That adds 270 px of street.
- Everything else is the same. The parsed v22 API also has 2 `null` portals.
- I recovered both from v22 raw WZ at `https://maplestory.io/api/wz/GMS/22/Map/Map/Map0/000020000.img/portal/4` and `/5`:
  - in01 is unchanged at (557,94) and leads to 20001:out00.
  - **out00 moved to (1109,97)** and still leads to 30000:in00.
- So in v22 the exit sits about 314 px further east, out on the added street and away from the oven tower.

## 8. Open questions

- Should out00 go *through* the oven tower, or beside it? The 2D portal only sits in front of the tower door.
- Nina's islet: keep it as a floating islet in town, or ground it on a pillar or stump?
