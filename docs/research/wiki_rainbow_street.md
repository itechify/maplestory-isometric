# Rainbow Street (Amherst region): descriptive, visual and narrative reference

Phase-1 research for MisoStory. Scope: the 14 classic Maple Island maps on **Rainbow Street**:
1000000-1000006, 1010000-1010004, 1020000-1020001 (GMS v0.08-v0.22 IDs and names).

## How to read this document

| Marker | Meaning |
|---|---|
| (no marker) + source link | Taken from a data file or web page. The link or file path is given. |
| **[derived]** | Computed by me from the sourced data (for example foothold statistics or portal reciprocity). The method is stated. |
| **[viewed]** | What I saw in a local partial render or minimap (`ref_renders/v8_<id>_render.png`, `v8_<id>_minimap.png`). These are first-hand visual observations, but the images are partial: houses, trees and backgrounds are often missing. |
| **[memory]** | Recalled from general knowledge and not verified against a source in this session. Treat it as a lead, not a fact. |
| **[proposal]** | My design suggestion for MisoStory. Not a fact about the original game. |

Units: MapleStory pixels and tier counts only (y increases **downward**, so a smaller y means higher up).

### Primary sources used

- **maplestory.io WZ API**: `https://maplestory.io/api/GMS/<ver>/map/<id>`, `/mob/<id>`, `/npc/<id>`, `/map/<id>/minimap`.
  Local copies are in `docs/research/raw/gms_v8/` and `gms_v22/`. To recover portals that v8 failed to parse, I also fetched
  v28, v32, v34, v37, v38, v39 and v40-v55 (all pre-revamp, same IDs and names).
- **Local partial renders and minimaps**: `docs/research/ref_renders/v8_<id>_render.png` and `v8_<id>_minimap.png`. I viewed all 14 renders and the 11 minimaps that exist; the 3 interior maps (1010001-1010003) have no minimap. To read the 6-14 px house sprites, I made 6x nearest-neighbour enlargements of the minimaps in a temp folder outside the repo; no copies are in the project.
- **NiaMeowDB / meowdb "MapleStory Classic" database**: `https://meowdb.com/msclassic/maps/0000010xx`. It describes *MapleStory Classic World*, a modern Nexon re-creation of early GMS, so it is a **secondary** source. Its quest text is a modern re-localisation, and its spawn counts differ from v8, so I use it only for NPC roles, quest names and breakables. Its ID scheme is its own (Amherst = `000001010`), so do not mix it with WZ IDs.
- **Hidden Street (2005-2006, via archive.org)**: these are the best classic-era sources found.
  - The Amherst page: https://web.archive.org/web/20060414135927/http://www.hidden-street.net/maps/amherst.php
  - An **annotated Rainbow Street connection diagram** captured in Dec 2005, saved as `ref_web/1010000_1.gif`: https://web.archive.org/web/20051220152556/http://www.hidden-street.net/maps/images/miamherst.gif
  - An **in-game screenshot of The Field East of Amherst** captured in Jun 2006, saved as `ref_web/1020000_1.jpg`: https://web.archive.org/web/20060626033208/http://www.hidden-street.net/maps/images/rstomatoisland.jpg
- **Official MapleGlobal (GMS) site, 2006**: the Maple Island map blurb at https://web.archive.org/web/20060528204733/http://www.mapleglobal.com/WZ.ASPX?PART=/Guide/GameLibrary/MapleWorldMap/MapMaple
- **MapleTip location library (Nov 2007 snapshot)**: https://web.archive.org/web/20071112044538/http://www.mapletip.com/locations_view.php?town=Amherst. It independently confirms the portal links and mob stats.
- **MapleWiki / Wikia (May 2008 snapshot)**: https://web.archive.org/web/20080515183439/http://maplestory.wikia.com/wiki/Amherst
- More web sources are listed per section and in the Sources list at the end.

### Narrative framing (sourced)

- **Official GMS text (MapleGlobal, 2006)**, verbatim:

  > "In this island, there are: the Mushroom Village, the first town of the game; Southperry, the harbor town; and **Amherst, the town of quests**. At this island, novice travelers learn various skills and techniques with the help of NPC. ... <Maple Island>, an island floating somewhere in the sky of <Maple World>, is a mysterious island of no-return, once it is left behind for Victoria Island."

- **Hidden Street (2006)**, verbatim:

  > "The town of quests. Most of the beginner's quests can be found in this town. There are 2 types of store available here, which is the Weapon store and Potion store."

- **MapleWiki (2008)**, verbatim with the original spelling:

  > "Amherst is consider to be Maple Islands biggest town follow by Southperry. The town holds true to the general scenery of the island, with the grassy ground and mushroom-shaped houses. Be aware Maple Islands strongest monsters lives right outside of the town. Amherst also feature the only weapon shop of the whole island many travel here for quests."

  This snapshot already lists "Mushroom Town Training Camp", so it describes the island just after the v40-era change. The Amherst description itself matches the classic data.

- **[memory]** In the classic flow, players walk from Mushroom Town east along Maple Road to A Split Road. There they turn north-east to Amherst (Maria's letter quest pushes them there) or south to Southperry and the boat to Victoria. Maria's Classic dialogue ("Amherst is northeast from here") supports the direction; the route itself is from memory.

---

## Region overview

### Mobs on Rainbow Street (GMS v8 stats)

Source: `https://maplestory.io/api/GMS/8/mob/<id>`.

| Mob ID | Name | Lv | HP | EXP | Where on Rainbow Street (v8 spawn entries) |
|---|---|---|---|---|---|
| 100100 | Snail | 1 | 8 | 3 | every field map |
| 100101 | Blue Snail | 2 | 15 | 4 | every field map except Mushroom Garden |
| 120100 | Shroom | 2 | 20 | 5 | 1000000, 1000001, 1000003 (dominant), 1000005, 1000006 |
| 130101 | Red Snail | 4 | 45 | 8 | every field map except Mushroom Garden |
| 1210102 | Orange Mushroom | 8 | 80 | 15 | 1000000, 1000001, 1000002 (dominant), 1000003, 1000006, 1020000, 1020001 |

There are no bosses. Orange Mushroom (Lv 8) is the strongest mob on the street.

### Music (BGM)

Source: the `backgroundMusic` field of each map JSON.

- `Bgm00/FloralLife` plays in Amherst, its 3 interiors, **Snail Field of Flowers** (1010004) and **The Field East of Amherst** (1020000).
- `Bgm00/RestNPeace` plays in The Field West of Amherst, all six forest/garden sub-maps and **Tomato Field** (1020001).
- So the east side of town (and the flower field behind Townstreet) keeps the town theme. The west hub and its forest pockets use the calmer field theme.
- meowdb lists the track lengths as Floral Life 2:18 and Rest N Peace 2:55.

Every Rainbow Street map has `mapMark = Amherst` and `returnMap = 1010000`, so dying anywhere on the street returns you to Amherst.

### Two terrain families

All **[viewed]** in the v8 renders.

1. **Town cobblestone (Amherst only).** Pale blue-grey and tan rounded flagstones in an irregular mosaic, with a thin bright grass lip on every top edge. A short wooden-plank ramp/stair joins the levels. This is the only map in the set that is not built from soil.
2. **"Grassy soil" (all 10 field maps and Townstreet).** Olive and ochre crumbly earth cliffs with a tufted bright-green grass cap. Small grey boulders with moss are embedded in the cliff faces. Floating islands come in two kinds:
   - long slabs (about 1-2 tiles deep);
   - small oval "stepping-stone" tufts, often stacked as zig-zag staircases.

   **[derived]** The walkable heights in these maps sit on a **60 px vertical grid**: foothold y-values step in multiples of 60, for example 455/395/335/275 in 1000000. That makes 60 px the natural tier unit for these maps.

### Sky and background atmosphere

- **Sourced**, for Field East only: the Jun 2006 screenshot (`ref_web/1020000_1.jpg`) shows a **bright blue sky with puffy white clouds**, **soft out-of-focus green hills and round trees** in the distance, and a **giant tree trunk** in the mid-background.
- **[inference]** The other Rainbow Street field maps probably share this daytime "meadow under a huge tree" backdrop. The maplestory.io JSON has no background data, and the renders omit backgrounds, so this is not verified per map.
- **[memory]** Maple Island fields are always sunny daytime; there is no night or dusk variant in the classic era.

### Recurring props (what to build once and reuse)

All **[viewed]** in renders and minimaps.

- **Barrel-door hillside houses.** A round-topped wooden plank door, banded like a barrel, set into a small grass-capped earth mound. This is how the field portals look:
  - the Field West of Amherst sub-map entrances;
  - the exits inside Mushroom Garden, Snail Garden, Hunting Ground I and Hunting Ground II.
- **White-barked birch-like trees** with spiky, star-shaped leaf clusters in three palettes: fresh green and teal, autumn orange-rust, and mustard yellow. These are the main "forest" prop. Autumn colours dominate in Dangerous Forest, Hunting Ground II, Tomato Field and The Field East of Amherst.
- **Round dark-green shrubs** (clumps of 2-3 domes).
- **Flower beds:** white/pink clover blossoms, red berry bushes, orange marigold-like flowers, purple irises, yellow daffodils, and large **lily-of-the-valley** (white bell flowers on arching stems, Hunting Ground II).
- **Fences:** a white weathered picket fence (Hunting Ground II), an orange-brown wooden rail fence (Snail Field of Flowers top level), and a short brown fence on the ground (Snail Garden).
- **Climbables:**
  - green leafy **vines** (Dangerous Forest);
  - knotted **hemp ropes** hanging from a wooden peg (Hunting Ground II, Mushroom Garden);
  - **rope-and-plank ladders** (Mushroom Garden, Hunting Ground II).
- **Butterflies** (pink and orange; Snail Field of Flowers).
- **Tomato plants**: bushy green plants with red tomatoes. Seen close up in the Field East screenshot, and as a ground row in the Tomato Field minimap.
- **Small white-capped mushrooms** growing on island tops (Field East screenshot).
- **Mushroom houses** (Amherst, Field East's far-east ground, Townstreet): mushroom-cap roofs in yellow, red and orange.

---

## Connection map (portal graph)

Portal data in the maplestory.io API is lossy: an entry can be `null`, and parse failures depend on the version. I took the union of every version that parsed each portal. A portal that **no** version parsed is reconstructed from the portal on the other side that points back to it ("inferred").

| From map | Portal | Pos (x, y) | To map | To portal | Status | Parsed in |
|---|---|---|---|---|---|---|
| 1000000 Field West of Amherst | west00 | (-391, 276) | 50000 A Split Road | east00 | parsed | v37 |
| 1000000 | east00 | (3338, 456) | 1010000 Amherst | west00 | parsed | v37 |
| 1000000 | in00 | (-60, -385) | 1000001 In a Small Forest | out00 | parsed | v37 |
| 1000000 | in01 | (2987, -508) | 1000002 Dangerous Forest | out01 | parsed | v37 |
| 1000000 | in02 | (1740, 455) | 1000003 Mushroom Garden | out00 | parsed | v37, v38, v39 |
| 1000000 | in03 | (1908, 456) | 1000004 Snail Garden | out00 | parsed | v37 |
| 1000000 | in04 | (389, -688) | 1000005 Hunting Ground Mid. Forest I | out00 | parsed | v37 |
| 1000000 | in05 | (757, -747) | 1000006 Hunting Ground Mid. Forest II | out00 | parsed | v37 |
| 1000001 In a Small Forest | out00 | (1153, -56) | 1000000 | in00 | parsed | v34 |
| 1000002 Dangerous Forest | out01 | (-310, -864) | 1000000 | in01 | parsed | v39 |
| 1000003 Mushroom Garden | out00 | not parsed | 1000000 | in02 | **inferred** | none |
| 1000004 Snail Garden | out00 | (980, 329) | 1000000 | in03 | parsed | v28, v39 |
| 1000005 Hunting Ground I | out00 | (132, 155) | 1000000 | in04 | parsed | v39 |
| 1000006 Hunting Ground II | out00 | (133, -1346) | 1000000 | in05 | parsed | v8 |
| 1010000 Amherst | west00 | (-291, 276) | 1000000 | east00 | parsed | v37, v40, v55 |
| 1010000 | in00 | (227, -175) | 1010001 Weapon Store | out00 | parsed | v22, v32, v45 |
| 1010000 | in01 | (2276, 275) | 1010002 Townstreet | out00 | parsed | v32, v40, v45 |
| 1010000 | in02 | not parsed | 1010003 Department Store | out00 | **inferred** | none |
| 1010000 | east00 | (3055, 274) | 1020000 Field East of Amherst | west00 | parsed | v22, v32 |
| 1010001 Weapon Store | out00 | not parsed | 1010000 | in00 | **inferred** | none |
| 1010002 Townstreet | out00 | not parsed | 1010000 | in01 | **inferred** | none |
| 1010002 Townstreet | west00 | not parsed | 1010004 Snail Field of Flowers | east00 | **inferred** | none |
| 1010003 Department Store | out00 | (300, 182) | 1010000 | in02 | parsed | v22, v39 |
| 1010004 Snail Field of Flowers | east00 | (559, -623) | 1010002 | west00 | parsed | v32, v37, v40, v48, v50 |
| 1020000 Field East of Amherst | west00 | (-332, 90) | 1010000 | east00 | parsed | v8, v37, v38 |
| 1020000 | in00 | not parsed | 1020001 Tomato Field | out00 | **inferred** | none |
| 1020001 Tomato Field | out00 | (-275, 214) | 1020000 | in00 | parsed | v8, v38, v39 |

Where I inferred a portal name, the count of `null` entries left in that map's portal list matches the number of portals still missing. For example, 1010002 has `[sp, null, null]`, which is exactly out00 and west00.

**Independent classic-era confirmation of the graph**:

- **Hidden Street's Dec 2005 diagram** (`ref_web/1010000_1.gif`) draws every one of these links on top of minimap captures:
  - Field West of Amherst to all six pockets, to Amherst, and to "Split Road to Mushroom Town and Southperry";
  - Amherst to Field East, and Field East to Tomato Field;
  - Amherst to "House in Townstreet", and that house to "Small Field of Flowers".
- **MapleTip (2007)** lists Townstreet's portals as exactly "Amherst" and "Snail Field of Flowers", and the Department Store's as "Amherst".
- So all five inferred portals are confirmed in their destination, though not in name or position.

### Topology sketch

**[derived]** from the table above.

```
 50000 A Split Road (Maple Road)
        |  west00/east00
 1000000 The Field West of Amherst  ----east00/west00----  1010000 AMHERST (town)  ----east00/west00----  1020000 The Field East of Amherst
   in00 -> 1000001 In a Small Forest     (door, upper-left)    in00 -> 1010001 Weapon Store (door on upper plateau)      in00 -> 1020001 Tomato Field
   in01 -> 1000002 Dangerous Forest      (door, upper-right)   in02 -> 1010003 Department Store
   in02 -> 1000003 Mushroom Garden       (door, ground centre) in01 -> 1010002 Amherst Townstreet --west00--> 1010004 Snail Field of Flowers
   in03 -> 1000004 Snail Garden          (door, ground centre)
   in04 -> 1000005 Hunting Ground I      (door, high left)
   in05 -> 1000006 Hunting Ground II     (door, high left-centre)
```

- **The Field West of Amherst is a hub with 6 dead-end pockets.** Each forest/garden sub-map has exactly one exit, back to the door it came from.
- **Snail Field of Flowers can only be reached through Amherst Townstreet.** It is the one non-obvious topology fact in this set: the flower field is entered from the town, not from a field map.
- **Tomato Field is a dead-end pocket off The Field East of Amherst.**
- In GMS v8, **The Field East of Amherst has no other exit**: only west00 and in00 appear in its portal list. Rainbow Street therefore ends there. The road to Southperry runs from A Split Road (50000), on the other side of the Field West.

---

## 1000000: The Field West of Amherst

**Data** (`raw/gms_v8/1000000.json`; https://maplestory.io/api/GMS/8/map/1000000)

- Street: Rainbow Street. Not a town. BGM: `Bgm00/RestNPeace`.
- Foothold extent: x -489..3459 (3948 px wide) by y -1045..455 (1500 px tall).
- **[derived]** 22 distinct walkable heights on the 60 px grid.
- 13 climbables: 3 ladders and 10 ropes, for example a rope at x=2197 from y -23 to 417 and a ladder at x=2528.
- Mob spawn entries (v8): Snail 16, Blue Snail 20, **Shroom 21**, Red Snail 26, Orange Mushroom 7. That is 90 entries, the largest mob table on the street.
- No NPCs (v8).
- Portals: 8 exits (see the connection table): west to A Split Road, east to Amherst, and 6 doors (`in00`-`in05`) to the forest/garden pockets.

**Secondary (meowdb, MapleStory Classic)**: https://meowdb.com/msclassic/maps/000001000

- Described as "a hunting ground in Rainbow Street, Maple Island", with monsters Lv 1-8.
- Lists 8 connected maps (the same set as the WZ data) and 5 Wooden Box breakable spawns.
- Quest targets here include "Mai's Training" (Blue Snail x10, Shroom x10, Red Snail x5), "Mai's Final Training" (Orange Mushroom x1) and "Sam's Suggestion" (Snail x10).

**Visual identity**

All **[viewed]** in `v8_1000000_render.png` and the minimap.

- The widest field on the street. A long grassy-soil ground band undulates in big rectangular steps (several 60-120 px risers).
- Above it, a dense "sky archipelago" fills the upper two-thirds of the map: dozens of floating slabs and oval tufts, many arranged as zig-zag stepping-stone staircases.
- The six sub-map doors are barrel doors set into small earth mounds, and their positions are legible in the minimap:
  - **two doors side by side in one raised ground block at the centre** (in02 Mushroom Garden at x 1740, in03 Snail Garden at x 1908);
  - door houses on the upper-left floating islands (in00 at (-60, -385); in04 at (389, -688); in05 at (757, -747));
  - one on the stepped upper-right plateau (in01, Dangerous Forest, at (2987, -508)).
- A large floating island at the top centre-right carries a thicket of green and teal trees.
- Autumn trees stand on the far-left ground near the A Split Road exit.
- Near the east exit there is an island with a cluster of tall pale stalks and an orange/brown object on the ground by the exit. I could not identify either at minimap resolution.

**What makes it recognizable**

- The **six-door hub**. Players return here again and again to pick a pocket.
- The vertical stepping-stone mazes above the ground.
- The **Shroom** population. Shroom appears only on the west side.

**Player memory (sourced, Jan 2007).** "Islanders" (players who never left Maple Island) hunted for "pillars": hard-to-reach ledges. One islander wrote:

> "in the Field West of Amherst, the platform above the Mushroom Garden portal, is just too far to jump on top of unless you get bumped by a monster"

Source: https://web.archive.org/web/20070202084419/http://www.basilmarket.com/forum/191098/1//Maple_Island_Glitches.html

**[derived]** The Mushroom Garden door (`in02`) is in the raised centre ground block. **[proposal]** Keep one "secret" ledge above that block that is only reachable by knock-back, as an islander easter egg.

**Era notes**

- **Geometry changed within the canonical window**: v8 has 493 footholds, v22 has 396, while ladders, ropes and the mob table are identical (`raw/gms_v8/1000000.json` vs `raw/gms_v22/1000000.json`). The geometry team should decide which version is canonical.
- **v55** (https://maplestory.io/api/GMS/55/map/1000000) adds **Stump (130100), Slime (210100, Lv 6) and Pig (1210100, Lv 7)** here. **Do not use them**: they are anachronistic for 2005.
- **v62** adds the NPC **Yoona (20100)** here, with a dialogue about training with Maya (https://maplestory.io/api/GMS/62/npc/20100). This is also anachronistic.
- In v83+ the ID 1000000 is **Amherst** itself; never use v83 data for this map.

---

## 1000001: In a Small Forest

**Data** (`raw/gms_v8/1000001.json`)

- BGM `RestNPeace`.
- Foothold extent: x -624..1434 (2058 px) by y -535..605 (1140 px).
- **[derived]** 20 heights on the 60 px grid.
- 6 climbables: 1 ladder (x 1142) and 5 ropes, three of them clustered at x 811-981 in the upper area.
- Mobs (v8): Snail 16, Blue Snail 10, Shroom 11, Red Snail 5, Orange Mushroom 4.
- Exit: `out00` at (1153, -56) leads to 1000000 `in00`.

**Secondary**: https://meowdb.com/msclassic/maps/000001001 lists Lv 1-8 mobs and 1 connected map.

**Visual identity**

All **[viewed]**.

- A broad, flat ground slab along the bottom with a **stepped mound at the right**: four 60 px steps up to a plateau. A young green birch, an autumn birch and shrubs sit on the steps.
- Above, long floating slabs alternate with a **vertical column of small oval tufts**: two parallel zig-zag ladders of stepping stones up the centre-left.
- In the minimap, the ground row is lined with groves of autumn-orange and mustard birches, and a tall green sapling stands on the top-left island.

**What makes it recognizable**: a small, cosy "pocket forest". Its signature is the long stepping-stone column in the middle, plus mixed green and autumn birches.

**Era notes**: according to the task brief, v83 reuses ID `40000` for a map named "In a Small Forest". That is a different, re-IDed map; do not use it.

---

## 1000002: Dangerous Forest

**Data** (`raw/gms_v8/1000002.json`)

- BGM `RestNPeace`.
- Foothold extent: x -399..1749 (2148 px) by y -925..215 (1140 px).
- **[derived]** Only 9 heights, grouped in **three clear tiers**:
  - ground at 95-215;
  - a middle shelf at -445..-325;
  - a top row at -925..-805.
- 7 climbables, all ropes. They are long, about 360-450 px each, for example x 664 from y -383 to 70 and x 1349 from -803 to -353.
- Mobs (v8): Snail 15, Blue Snail 3, Red Snail 5, **Orange Mushroom 12**. This is the highest Orange Mushroom density on the west side. No Shroom.
- Exit: `out01` (not out00) at (-310, -864), on the top-left island, leads to 1000000 `in01`.

**Secondary**: https://meowdb.com/msclassic/maps/000001002 lists 34 spawns, with Orange Mushroom 12 the largest group.

**Visual identity**

All **[viewed]**.

- The render shows **green leafy vines** hanging from the shelves as the climbables. This is the only map in the set with vine ropes.
- The minimap shows **dense groves of autumn birches** (rust-orange and mustard) on both main tiers, with a few green/teal birches. It is the most "autumn-forest" looking map on the west side.
- The layout is a three-storey "bookshelf": wide stepped slabs stacked vertically and linked by long vines.

**What makes it recognizable**

- The name and the Orange Mushroom pressure. For a Lv 3-6 beginner this is the "dangerous" pocket.
- Long vines dropping between three wide shelves under an autumn canopy.

**Player memory (sourced, Feb 2007).** A beginner "islander" advised:

> "Just train at dangerous forest till 20ish till you slow down alot ... Its fastest training since there are no ksers and barely any hackers."

Source: https://web.archive.org/web/20070210135604/http://www.basilmarket.com/forum/203966/1/Maple_Islander_Level.html

This makes Dangerous Forest the "endgame" grinding spot of Rainbow Street.

---

## 1000003: Mushroom Garden

**Data** (`raw/gms_v8/1000003.json`)

- BGM `RestNPeace`.
- Foothold extent: x 1041..2919 (1878 px) by y -355..515 (870 px).
- **[derived]** 14 heights.
- 3 climbables: 2 ladders (x 1512 and x 2598) and 1 rope.
- Mobs (v8): Snail 9, **Shroom 28**, Orange Mushroom 5. This is the **Shroom capital** of the street; there are no snails other than the basic Snail.
- Exit `out00` was never parsed; **inferred** to lead to 1000000 `in02`. The spawn points cluster at x 2346-2834, y 264-396 (right side), next to the barrel door.

**Secondary**: https://meowdb.com/msclassic/maps/000001003 lists Snail 7, Shroom 23 and Orange Mushroom 5.

**Visual identity**

All **[viewed]**. This is the most decorated of the field renders.

- The ground is lined with **white birches** (green/teal and autumn tints) and **red berry bushes**.
- The right side is a stepped hill with a **barrel door** (the exit) under a crown of **orange flowers and clover blossoms**.
- The floating islands are garden beds topped with clover blossoms, red berries and purple irises.
- A rope ladder hangs from a small island on the left, and a knotted rope hangs from a larger left island.
- Despite the name, the mushroom feel comes from the mobs. No giant mushroom props were visible in the render or minimap.

**What makes it recognizable**: a flowery, cultivated garden full of Shrooms, and the barrel-door hill on the right.

---

## 1000004: Snail Garden

**Data** (`raw/gms_v8/1000004.json`)

- BGM `RestNPeace`.
- Foothold extent: x 771..2919 (2148 px) by y -445..515 (960 px).
- **[derived]** 14 heights.
- 11 climbables, a mix of ladders and ropes.
- Mobs (v8): Snail 17, Blue Snail 19, Red Snail 11. **Snails only**: no Shroom, no Orange Mushroom.
- Exit: `out00` at (980, 329), on the left raised block, leads to 1000000 `in03`.

**Secondary**: https://meowdb.com/msclassic/maps/000001004 lists Lv 1-4 mobs and 41 spawns.

**Visual identity**

All **[viewed]**.

- A tall stepped block at the left holds the **barrel-door exit**. The ground descends in steps to a long flat bottom, then rises to a block at the right.
- Two rows of floating islands sit above: 4 long slabs at the top, plus small tufts and two mid slabs.
- In the minimap there is a short **brown wooden fence** on the central ground. Green and autumn birches and shrubs stand on the ground, and small flowers grow on the upper islands.

**What makes it recognizable**: the safest pocket (Lv 1-4, snails only), with a simple, open, symmetric layout.

**Era notes**: according to the task brief, v83 reuses ID `20000` for a map named "Snail Garden". The v83 map at `1000004` is also named "Snail Garden" (Rainbow Street), but on the re-IDed island, with a different mob table: Snail 9, Blue Snail 12, Red Snail 3 (https://maplestory.io/api/GMS/83/map/1000004). Use only the v8/v22 data.

---

## 1000005: Hunting Ground Middle of the Forest I

**Data** (`raw/gms_v8/1000005.json`)

- BGM `RestNPeace`.
- Foothold extent: x -759..1209 (1968 px) by y -1405..215 (**1620 px tall**).
- **[derived]** 20 heights.
- 10 climbables.
- Mobs (v8): Snail 21, Blue Snail 16, Shroom 12, Red Snail 10. No Orange Mushroom.
- Exit: `out00` at (132, 155), a door in a small raised block on the ground, leads to 1000000 `in04`.

**Secondary**: https://meowdb.com/msclassic/maps/000001005 lists Lv 1-4 mobs.

**Visual identity**

All **[viewed]**.

- A **tall vertical climb**: the ground at the bottom has a central raised block with the barrel door.
- A long **zig-zag stepping-stone column** rises through the middle (about 10 small tufts).
- Long slabs alternate left and right up to the top islands.
- The minimap shows sparse birches, shrubs, and a couple of wooden bench/crate-like props on the mid islands (shape only; unclear at this resolution).

**What makes it recognizable**: verticality. It is the "climb the forest" map, with a central stepping-stone spine.

---

## 1000006: Hunting Ground Middle of the Forest II

**Data** (`raw/gms_v8/1000006.json`)

- BGM `RestNPeace`.
- Foothold extent: x -1119..1029 (2148 px) by y -2125..-745 (1380 px).
- **[derived]** 15 heights, and 6 sloped segments: the ground is a real valley with slopes.
- 10 climbables: 1 ladder (x 29) and 9 ropes.
- Mobs (v8): Snail 13, Blue Snail 17, Shroom 9, Red Snail 6, Orange Mushroom 6.
- Exit: `out00` at (133, -1346) leads to 1000000 `in05`. This is the only Rainbow Street exit that v8 parsed (it is listed in the task brief).

**Secondary**: https://meowdb.com/msclassic/maps/000001006

**Visual identity**

All **[viewed]**. This is the most distinctive field render in the set.

- **The ground is a V-shaped valley**: a high left bank, a slope down to a dip, and a long slope up to a high right bank.
- **White weathered picket fences** run along both banks.
- **Large lily-of-the-valley plants** (white bells on arching stems) grow on the islands and in the dip, and clumps of **yellow daffodils** sit on the top islands.
- **Big autumn birches** stand on the ground: rust-orange on the left, mustard-yellow in the dip and on the right bank.
- The exit is a **floating central island with an earth hut and a barrel door**, flanked by an autumn birch.
- Hemp ropes hang from wooden pegs under many islands.
- A rope ladder and **giant round lily-pad-like leaves** sit on the upper-centre island.

**What makes it recognizable**: the valley floor with picket fences, lilies of the valley, and the floating door-hut in mid-air.

---

## 1010000: Amherst (town)

**Data** (`raw/gms_v8/1010000.json`; https://maplestory.io/api/GMS/8/map/1010000)

- `isTown: true`. BGM: **`Bgm00/FloralLife`**. Return map: itself.
- Foothold extent: x -398..3278 (3676 px) by y -228..274 (502 px).

**Elevations [derived]** (from merged footholds):

| Level | y | x span | Notes |
|---|---|---|---|
| Ground, west | 274 | -398..720 | Then a wooden ramp up to 214 at x 720-810 |
| Middle terrace | 154 | 862..2018 | 120 px above the ground; the town square |
| Ground, east | 274 | 2108..3278 | |
| Upper plateau | -176 | -83..893 | 450 px above the ground; plus a step at -116 for x 893-1073 |
| Small floating ledges | -146 / -86 | 2032-2198 | Two stacked; a rope at x 2072 runs from a ledge at y 94 |
| Tiny bits | -228 | 733-824 | Possibly roof tops |

- **Climbables**: a ladder at x 991 and a rope at x 917 (both y -114..152) climb from the middle terrace to the upper plateau. A rope at x 2072 (y -84..92).
- **Exits**:
  - `west00` (-291, 276) leads to the Field West of Amherst.
  - `in00` (227, -175) **on the upper plateau** leads to the Weapon Store.
  - `in01` (2276, 275) on the east ground leads to Townstreet.
  - `in02` (position not parsed) leads to the Department Store.
  - `east00` (3055, 274) leads to the Field East of Amherst.
- Six `tp` (type 6) points at y≈274, x 169-621. **[memory]** These are Mystic Door arrival points; they have no gameplay role for beginners.
- No mobs.

### NPCs (v8)

Names and dialogue from `https://maplestory.io/api/GMS/8/npc/<id>`.

| NPC | ID | Pos | Role | v8 idle dialogue (verbatim) |
|---|---|---|---|---|
| **Lucas** | 12000 | (1790, 154), middle terrace | Chief of Amherst (Classic quest text: "the chief of Amherst", "Chief Lucas"; meowdb role: "Quest Giver"); receives Maria's letter | "Stranger...what are you doing here?" / "I'm not too fond of the strangers. I'm only worried about the peace of this town." / "You...if you're strong and powerful, can you take care of the monsters around town?" |
| **Mai** | 12100 | (628, -176), upper plateau | Fighter/trainer (v8 only in Amherst; see era notes) | "Do you know me by any chance? You don't? What's wrong with you?" / "If you are thinking of challenging me, I suggest you keep dreaming..." / "Is there anyone that can satisfy my desire to fight...?" |
| **Rain** | 12101 | (103, 274), west ground, near the entrance from the Field West | Tutorial girl; Maple Quiz | "Isn't it nice out here today?" / "To jump, press the left Alt key." / "Press the arrow keys to move around here and there." |
| **Pio** | 10000 | (547, 274), west ground at the foot of the ramp | Handyman and recycler | "Do you need my help by any chance? I can handle machinery really well..." / "I just ate a little bit ago...and yet I'm hungry already...!!" / "Phew...work is hard. I need to take a break." |

**Quests on this map** (secondary: meowdb, MapleStory Classic; https://meowdb.com/msclassic/maps/000001010):

- **Letter for Lucas / Lucas's Reply.** **Maria** (NPC 2103, at **A Split Road** (50000), *not* in Amherst in v8: `raw/gms_v8/50000.json` lists only NPC 2103) sends you with a letter to "the chief of Amherst". Lucas writes a reply, and Maria rewards you with a hat (a random beginner skullcap or headband).
  - Maria's Classic dialogue: "Amherst is northeast from here... He is probably walking in front of the general store today."
  - Maria's own v8 idle lines confirm the letter plot: "Ahh...I need to get this letter sent...", "Why isn't anyone passing by!!"
  - Sources: https://meowdb.com/msclassic/quest-tracker/1007, https://meowdb.com/msclassic/quest-tracker/1008, https://maplestory.io/api/GMS/8/npc/2103.
- **Pio's Collecting Recycled Goods** (Lv 5+). Break the Wooden Boxes around town and bring back Rusty Screw x3 and Old Wooden Board x3. Reward: The Green Relaxer (a chair), 100 EXP, 150 mesos. https://meowdb.com/msclassic/quest-tracker/1012
- **Rain's Maple Quiz 1-7** (Lv 5+). Controls, ladders, job advancement trivia. https://meowdb.com/msclassic/quest-tracker/1013
- **Breakables**: meowdb lists **6 Wooden Box spawn points** in Amherst (2 more in the Weapon Store, 2 in Townstreet, 1 in the Department Store). These boxes are the Pio-quest props.

**Classic-era fansite description** (Hidden Street, 2006 archive, https://web.archive.org/web/20060414135927/http://www.hidden-street.net/maps/amherst.php), verbatim:

> "The town of quests — Most of the beginner's quests can be found in this town. There are 2 types of store available here, which is the Weapon store and Potion store."

### Visual identity

All **[viewed]** in the render and minimap: the v8 render shows only tiles and the post box, and the minimap shows the house art.

- **Ground**: pale grey-blue and tan **cobblestone** mosaic with a grass lip. It is unique in the set; every other map is soil.
- **Upper-left plateau** (a high cobblestone wall block, x≈-83..893): a big **yellow/orange-capped two-storey wooden house** sits on top, flanked by green and autumn trees. Its door is `in00`, the **Weapon Store**.
- **Ground level in front of that wall** (west ground):
  - a **yellow-capped mushroom house**;
  - a **red-capped mushroom house with a chimney** (orange/white stripes);
  - green shrubs and an autumn tree;
  - a **red post box** at the far west end (rendered at about x -190). **[memory]** In other classic towns this red box is a mail/notice box prop.
- **Middle terrace** (town square, x 862..2018): a long low **lime-yellow-capped mushroom house with a chimney** and a thin autumn tree. This is the **Department Store** (`in02`, the potion shop). Evidence:
  - Hidden Street's Dec 2005 diagram labels this house "potions", with "Lucas" just to its right.
  - The Classic text says Lucas walks "in front of the general store".

  The x position of `in02` itself is still unparsed. **[derived]** From the diagram it is roughly x 1500-1600.
- **Two small stacked floating ledges plus a rope** at x≈2032-2198. In the minimap they read like a two-board signpost; the render shows they are tiled ledges.
- **East ground**:
  - an **orange-capped mushroom house with a stone chimney** at about x 2276; its door (`in01`) leads to **Townstreet**;
  - a small **red-and-white** and a small **yellow** mushroom hut together, at about x 2550-2800;
  - at the far east, around the exit to the Field East (`east00` at x 3055), a **big leafy tree with a house built into its trunk** (orange roofs, round windows, dark doorway at the base). This "big tree" is the town's most striking landmark. **[proposal]** Make the east exit pass by or through the tree-house.

**Classic-era annotation (Hidden Street diagram, Dec 2005, `ref_web/1010000_1.gif`).** The diagram overlays labels on the Amherst minimap:

- "**weapons**" and "**Mai**" on the upper-left plateau;
- "**Rain & Pio**" at the lower left;
- "**potions**" under the middle-terrace house;
- "**Lucas**" to its right.

An arrow runs from the east-ground orange mushroom house to a picture captioned "**HOUSE IN TOWNSTREET**", and on to "Small Field of Flowers". So in late-2005 GMS, Mai was still in Amherst, and every shop and NPC sits where the v8 coordinates put them.

### Landmarks from the brief that were not found

- **Clock or tower**: I looked for one and found none. Sources checked:
  - the v8, v62 and v83 Amherst minimaps;
  - the v8 render;
  - Hidden Street's Dec 2005 diagram;
  - the 2006 Field East screenshot.

  None shows a clock or tower in Amherst or on Rainbow Street. **[memory]** The Maple Island "tower" is Southperry's lighthouse; the classic world map, Hidden Street `map001.jpg`, shows it at Southperry, not Amherst.
- **Signs**: the only sign I could confirm is the orange **"WELCOME" board** inside the Department Store (1010003 render). The two-board shape that reads like a **signpost** in the Amherst minimap (x≈2032-2198) turns out, in the v8 render and footholds, to be **two small stacked cobblestone ledges plus the rope at x 2072**. It is not a signpost object.
  - **[proposal]** A directional signpost at the west and east gates would still fit the town and help navigation.

### What makes it recognizable

- A **cobblestone hill town of mushroom-roofed houses** in three tiers:
  - the tall upper-left plateau with the Weapon Store;
  - the middle square;
  - the low east end with the tree-house.
- **Floral Life** music.
- The beginner NPC cluster at the west gate: Rain right at the entrance, Pio by the ramp.

### Era notes

- **Mai (12100)** stands on the upper plateau in **v8**. Hidden Street's **Dec 2005** diagram still labels "Mai" there. By v22 she has moved to **A Split Road (50000)** at (1891, -175) with new training lines: "You can be much stronger, if you get to be trained by me..." (`raw/gms_v22/50000.json`; https://maplestory.io/api/GMS/22/npc/12100). v22, v40, v55 and v62 Amherst have only Lucas, Rain and Pio.
  - **[proposal]** Choose one placement for MisoStory: v8 Amherst, or the v22 Split Road position.
- **Maria in Amherst** is a **post-revamp** state: in v83 Amherst (re-IDed to `1000000`) she stands at (1101, 154) next to Lucas, Rain and Pio (https://maplestory.io/api/GMS/83/map/1000000). Classic Maria belongs at A Split Road.
- **v83 re-ID** (Maple Island revamp):
  - Amherst becomes `1000000`, Weapon Store `1000001`, Townstreet `1000002`, Department Store `1000003`.
  - `1010000` becomes "Entrance to Adventurer Training Center" (Maple Road).
  - `1020000` becomes "Split Road of Destiny".
  - The v83 Amherst minimap is narrower (175 px wide vs 234 px in v8). It keeps the same house art but drops the east-ground orange house area, so **use v8/v22 data for layout**.
- v62 Amherst looks identical to v8 in the minimap (https://maplestory.io/api/GMS/62/map/1010000/minimap), so the town art was stable through at least v62.

---

## 1010001: Amherst Weapon Store

**Data** (`raw/gms_v8/1010001.json`)

- `isTown`. BGM `FloralLife`.
- A **single-screen room**: VR bounds 800x600, x -400..400. Floor at y 182 across the full width.
- About 20 short furniture/shelf platforms, plus one rope (x 75, y -261..-84) up to a loft at y -263 (x -185..311).
- NPC: **Sid** (11000), weapon seller, at (-270, 140), standing on a counter-height platform (y 140, x -338..-227).
  - v8 lines: "On sale! Really CHEAP!" / "Welcome!! Hahahaha!" (https://maplestory.io/api/GMS/8/npc/11000).
- Exit `out00` was not parsed; **inferred** to lead to Amherst `in00`. The spawn point is at (-114, 115).

**Secondary**

- meowdb: Sid, "Weapon Seller"; a 4-item shop (Sword, Hand Axe, Wooden Club, Razor; Classic-World prices); 2 Wooden Box spawns. https://meowdb.com/msclassic/npcs/20
- Hidden Street 2006 calls it the "Weapon store".

**Visual identity**

All **[viewed]**, partial render: only the frame is rendered.

- A heavy **timber post-and-beam interior**: thick wooden columns with grey stone caps and corbels.
- A thatch-like roof of **lashed wooden planks bound with dark blue cord** at the top corners.
- A dark slate roof underside.

**[proposal]** Furnish it with weapon racks on the many small platforms; the platforms are almost certainly shelves and props in the original.

---

## 1010002: Amherst Townstreet

**Data** (`raw/gms_v8/1010002.json`)

- `isTown`. BGM `FloralLife`. No NPCs, no mobs.
- Foothold extent: x -579..399 (978 px). Ground at y 275 across the width.
- A central **two-level structure**: platforms at y 69/47 and a roof at y -117, all x≈-142..138, plus a step at y 246 (x -221..129).
- One ladder at x 77 (y 49..244) climbs from the ground to the first level.
- Portals: `sp` plus 2 unparsed; **inferred** `out00` to Amherst and `west00` to Snail Field of Flowers.

**Secondary**: https://meowdb.com/msclassic/maps/000001012 confirms it connects to Amherst and Snail Field of Flowers and lists 2 Wooden Box spawns.

**Visual identity**

- **[viewed]** The render shows only a **grassy-soil ground strip** (field tiles, not cobblestone) with an embedded boulder. The central structure is object art and is not rendered.
- **Hidden Street's Dec 2005 diagram** captions this map "**HOUSE IN TOWNSTREET**". Its thumbnail shows a large **orange-capped mushroom house with windows**, seen from outside on grass (`ref_web/1010000_1.gif`).
- **Analog (not this map)**: the official 2005 MapleGlobal screenshot of *Mushroom Town Townstreet* (map 20001) shows the same "Townstreet" concept: a **giant mushroom house cut away to show two wooden floors**, joined by a wooden ladder, furnished with a bed, chest, shelves and hanging flower lamps, and standing on a grass strip under blue sky. https://web.archive.org/web/20051216083528/http://image.mapleglobal.com/download/screen_shot/003.jpg
  - **[inference]** Amherst Townstreet's footholds fit that template: two floors at y 69/47 over a ground at 275, a roof line at -117, and a ladder at x 77 from the ground to the first floor.

**What makes it recognizable**: you walk *into* the orange mushroom house's two-storey cutaway interior. It is also the only way to reach the flower field (1010004).

**[proposal]** Model it as a cutaway two-storey mushroom house over a short grass lane, with a ladder between floors. The flower-field exit sits at the west end.

---

## 1010003: Amherst Department Store

**Data** (`raw/gms_v8/1010003.json`)

- `isTown`. BGM `FloralLife`. Single-screen room, 800x600.
- Floor at y 184.
- About 30 short furniture platforms: counters at y 84/92 (x -348..-198), shelves at y -27 to 147, and a high shelf row at y -127/-129.
- NPC: **Lucy** (11100), grocer/potion seller, at (-258, 84), behind the counter.
  - v8 lines: "Ok, cheap goods! Really cheap!!" / "Hey you!! Don't even think about stealing in here..." / "You definitely need potions to travel" (https://maplestory.io/api/GMS/8/npc/11100).
- Exit: `out00` at (300, 182) leads to Amherst `in02` (parsed in v22 and v39).

**Secondary**

- meowdb: Lucy, "Grocer"; 6-item shop (Red Potion, Orange Potion, Apple, Egg, Orange, Pet Food; Classic-World stock, so pet food may not be 2005-accurate); 1 Wooden Box spawn. https://meowdb.com/msclassic/npcs/21
- Hidden Street 2006 calls it the "Potion store" / "Item Store".

**Visual identity**: **[viewed]**

- The same timber-and-plank-roof frame as the Weapon Store.
- A **wooden shop booth with an orange "WELCOME" sign** (white lettering on an orange plank board, bolted at both ends).
- A **cream cloth banner/curtain with a dark mushroom/snail emblem** hanging on the booth.
- A **pinned paper note with a red pin** on the left post.
- A **brick-edged wooden plank floor**.

**Analog (not this map).** The official 2005 MapleGlobal screenshot of the *Lith Harbor Department Store* shows the **same interior kit**:

- the timber frame and lashed-plank roof;
- the booth with a cream mushroom-emblem banner and a red-pinned note;
- plus potion shelves, hanging cloth sacks, a brass bird cage and a big plush bear.

https://web.archive.org/web/20060429004535/http://image.mapleglobal.com/download/screen_shot/004.jpg

**[inference]** The Amherst store reuses this generic shop kit. It is good reference for dressing the many shelf platforms.

**What makes it recognizable**: the orange "WELCOME" sign over Lucy's counter.

---

## 1010004: Snail Field of Flowers

**Data** (`raw/gms_v8/1010004.json`)

- Not a town, but BGM **`FloralLife`** (the town theme).
- Foothold extent: x -1029..849 (1878 px) by y -625..575 (1200 px).
- **[derived]** 12 heights.
- 11 climbables, **all ropes**. Several long ones (about 450 px) drop from the top deck at y -623 to about -172.
- Mobs (v8): Snail 10, Blue Snail 16, Red Snail 17. Snails only.
- Exit: `east00` at (559, -623), at the right end of the **top deck**, leads to Townstreet `west00`. Most spawn points are also on the top deck (y≈-700..-743).

**Secondary**: https://meowdb.com/msclassic/maps/000001014

- meowdb's Classic data adds Orange Mushroom x6 here. **v8 has none.**
- 3 Wooden Box spawns.

**Visual identity**

All **[viewed]**.

- **The top of the map is one long continuous deck** (about 1850 px) lined with an **orange-brown wooden rail fence** and big round shrubs. You arrive here.
- Below, three bands of floating flower-bed islands carry **purple irises, white/pink clover blossoms, orange marigolds and orange lilies**.
- A broad bottom ground has a flowery dip in the middle, full of clover blossoms and shrubs.
- **Pink and orange butterflies** flutter in the render. This is the only map in the set where they appear.

**What makes it recognizable**: the flower meadow with butterflies under a fenced top promenade. It is reached through town, not from the fields.

---

## 1020000: The Field East of Amherst

**Data** (`raw/gms_v8/1020000.json`)

- BGM **`FloralLife`**.
- Foothold extent: x -489..2199 (2688 px) by y -745..215 (960 px).
- **[derived]** 13 heights.
- 12 climbables: 5 ladders and 7 ropes.
- Mobs (v8): Snail 8, Blue Snail 19, Red Snail 13, Orange Mushroom 12. No Shroom.
- Exits: `west00` at (-332, 90) leads to Amherst `east00`; `in00` (not parsed; **inferred**) leads to Tomato Field.
  - Spawn points sit at the west end (x -426..-37) and on upper islands (for example (1022, -578) and (1533, -587)).

**Secondary**: https://meowdb.com/msclassic/maps/000001020 lists 2 connections and labels the Tomato Field link "Inside portal".

**Visual identity**

All **[viewed]**.

- The ground is a long grassy-soil band with **raised blocks at both ends and in the middle** and dips between them.
- Above, a big grid of floating slabs and identical small tufts forms a **regular "lattice"** of 3-4 rows, very orderly compared with the West field.
- **Clover-blossom** bushes grow on a mid island.
- The minimap shows **autumn birch groves** (orange and mustard) on the ground and an **orange mushroom-cap house at the far east ground**. **[inference]** This house is probably the door to Tomato Field. In Amherst, doors to sub-maps are houses, and the portal list has only one sub-map door here.

**Classic in-game screenshot** (Hidden Street, captured Jun 2006; `ref_web/1020000_1.jpg`; https://web.archive.org/web/20060626033208/http://www.hidden-street.net/maps/images/rstomatoisland.jpg). The minimap window title reads "Rainbow Street / The Field East of Amherst". **[viewed]** The screenshot shows:

- **Background**: a bright blue sky with white cumulus clouds; soft, painterly distant green hills with round blurred trees; and, in the mid-background, a **gigantic tree** whose wide trunk fills the screen centre, with an orange mushroom-cap shape at its foot.
- **Foreground**: grassy-soil islands with mossy boulders, and **knotted hemp ropes hanging from wooden pegs**.
- **Tomato plants**: bushy green plants hung with **red tomatoes** on the ground platform.
- **Small white-capped mushrooms** growing on the top island.
- **Red Snails** around a beginner character.

So the tomato-plant prop is not exclusive to Tomato Field.

**What makes it recognizable**

- The east-side field with the lattice of floating platforms.
- The town music still playing.
- Orange Mushrooms everywhere (12 entries).
- The giant tree looming in the background.

**Era notes**: in v83, `1020000` is "Split Road of Destiny" (Maple Road). Do not use it.

---

## 1020001: Tomato Field

**Data** (`raw/gms_v8/1020001.json`)

- BGM `RestNPeace`.
- Foothold extent: x -399..2559 (2958 px) by y -325..275 (600 px).
- **[derived]** Only **5 heights**, so it is a very flat map:
  - a ground band at 155-275 with gentle slopes (5 sloped segments);
  - one row of floating tufts at -325..-145.
- 5 long ropes (about 330-450 px) reach the floating row.
- Mobs (v8): Snail 9, Blue Snail 8, Red Snail 4, Orange Mushroom 4.
- Exit: `out00` at (-275, 214), at the west end, leads to 1020000 `in00`.

**Secondary**: https://meowdb.com/msclassic/maps/000001021 lists 25 spawns and 1 connection.

**Visual identity**

All **[viewed]**.

- A long, low, gently rolling ground: a raised hump at the left, a central hump, and a high bank at the right, with sloped transitions.
- A **single row of about 17 small floating tufts** runs along the sky in two staggered lines.
- The minimap shows a **continuous row of small dark-green plants with red dots along the whole ground**. These are almost certainly the **tomato plants** that give the field its name. The same prop (bushy plants with red tomatoes) is visible close up in the 2006 Field East screenshot (`ref_web/1020000_1.jpg`). **[inference]** The individual plant sprites are too small to identify in the minimap itself.
- Autumn birches stand at the left end; mustard-yellow birches stand in the centre and at the right.

**What makes it recognizable**: a flat "farm strip" with a tomato-plant row along the ground and a sky row of stepping stones. It is the quietest, simplest map in the set.

**Era notes**: in v62, Tomato Field's mob table is smaller (Snail 2, Blue Snail 5, Red Snail 8; https://maplestory.io/api/GMS/62/map/1020001). Use v8/v22.

---

## Cross-map era notes (avoid anachronisms)

1. **Use only v8-v22 data for these IDs.** From about v83 the whole island is re-IDed. I confirmed via the v83 API that Amherst becomes 1000000, 1010000 becomes "Entrance to Adventurer Training Center", and 1020000 becomes "Split Road of Destiny". The task brief adds that 40000 and 20000 are reused for "In a Small Forest" and "Snail Garden"; I did not re-check those two.
2. **Mai**: in Amherst in v8; at A Split Road from v22.
3. **Maria**: at A Split Road in v8 and v22; in Amherst only after the revamp (v83).
4. **No Stump, Slime or Pig** on Rainbow Street: they appear only from about v55. **No Yoona**: she appears from about v62.
5. **Field West of Amherst geometry differs between v8 and v22** (493 vs 396 footholds). Flag this for the geometry team.
6. meowdb's MapleStory Classic data is a modern re-creation:
   - its spawn counts differ from v8 (for example, it lists Orange Mushroom in Snail Field of Flowers);
   - its shops include later items (Pet Food).

   Use it only for names, roles and quest structure.

---

## What players remember (summary)

**Sourced**:

- **"The town of quests"**: the official 2006 GMS site and Hidden Street 2006 both use the phrase.
- **The only weapon shop on the island.** In-era support: Hidden Street 2006 Amherst, "There are 2 types of store available here, which is the Weapon store and Potion store" (https://web.archive.org/web/20060414135927/http://www.hidden-street.net/maps/amherst.php); Hidden Street 2006 Southperry, "Only the armour store is available here"; and the v8 map set has no other weapon-store map. MapleWiki 2008 says the same (secondary, after the era).
- Maple Island's **strongest monsters live right outside the town** (MapleWiki 2008). In the data this means Orange Mushroom, Lv 8, in the Field East and Dangerous Forest.
- A 2007 Basilmarket poster advised training in **Dangerous Forest** "till 20ish" before leaving the island (the poster left at level 21, so this is not an islander's account).
- Islanders hunting for hard-to-reach "pillar" ledges, such as the one **above the Mushroom Garden door** in The Field West of Amherst (Basilmarket 2007).

**Sourced via meowdb (Classic re-creation)**, describing the same quest content as classic GMS:

- Rain's tutorial chatter ("To jump, press the left Alt key") and the **7-part Maple Quiz**.
- **Pio's box-breaking recycling quest** (Rusty Screws and Old Wooden Boards from Wooden Boxes around town).
- The **Maria-to-Lucas letter** errand that rewards your first hat.

**[memory]** Not verified:

- Floral Life is strongly associated with Henesys as well. Hearing it in Amherst foreshadows Victoria Island.
- The cobblestone "mushroom village on a hill" look is the prototype for Henesys's mushroom houses.

---

## Reference images

All are classic-era and **reference only**: proprietary, and must not be shipped or traced into assets.

| File | What | Source |
|---|---|---|
| `docs/research/ref_web/1010000_1.gif` | Hidden Street's annotated Rainbow Street connection diagram (Dec 2005). It shows minimap captures of all 11 outdoor maps plus a picture of the "House in Townstreet", with portal arrows and NPC/shop labels for Amherst. | https://web.archive.org/web/20051220152556/http://www.hidden-street.net/maps/images/miamherst.gif |
| `docs/research/ref_web/1020000_1.jpg` | In-game screenshot of The Field East of Amherst (Jun 2006): background tree, tomato plants, ropes on pegs, Red Snails. | https://web.archive.org/web/20060626033208/http://www.hidden-street.net/maps/images/rstomatoisland.jpg |

Viewed but **not copied**:

- The local partial renders and minimaps `ref_renders/v8_<id>_render.png` / `_minimap.png` for all 14 maps (the 3 interiors have no minimap).
- The classic Maple Island world map, Hidden Street `map001.jpg` (Dec 2005). Amherst is the cluster of colourful mushroom houses on the island's right-middle edge. A teammate already keeps a world map in `ref_web/worldmap_1.png`.
- Official 2005 MapleGlobal screenshots `003.jpg` (Mushroom Town Townstreet, the Townstreet analog) and `004.jpg` (Lith Harbor Department Store, the shop-interior analog). URLs are given in the 1010002 and 1010003 sections.

---

## Sources

- maplestory.io API (WZ-derived):
  - map JSON: https://maplestory.io/api/GMS/8/map/1010000 (and the same path for each ID and version cited: 22, 28, 32, 34, 37, 38, 39, 40-55, 62, 83);
  - mobs: https://maplestory.io/api/GMS/8/mob/100100, /100101, /120100, /130101, /1210102;
  - NPCs: https://maplestory.io/api/GMS/8/npc/12000, /12100, /12101, /10000, /11000, /11100, /2103; /api/GMS/22/npc/12100; /api/GMS/62/npc/20100;
  - minimaps: /api/GMS/62/map/1010000/minimap and /api/GMS/83/map/1000000/minimap.
- Local data: `docs/research/raw/gms_v8/*.json`, `docs/research/raw/gms_v22/*.json`, `docs/research/ref_renders/v8_*`.
- Hidden Street (archive.org):
  - https://web.archive.org/web/20060414135927/http://www.hidden-street.net/maps/amherst.php
  - https://web.archive.org/web/20070125111743/http://www.hidden-street.net/maps/amherst.php
  - the two images above;
  - https://web.archive.org/web/20051226120239/http://www.hidden-street.net/maps/images/map001.jpg
- MapleGlobal official (archive.org):
  - https://web.archive.org/web/20060528204733/http://www.mapleglobal.com/WZ.ASPX?PART=/Guide/GameLibrary/MapleWorldMap/MapMaple
  - screenshot gallery: https://web.archive.org/web/20051227021232/http://www.mapleglobal.com/WZ.ASPX?PART=/Downloads/ScreenShot
- MapleTip (archive.org): https://web.archive.org/web/20071112044538/http://www.mapletip.com/locations_view.php?town=Amherst
- MapleWiki / Wikia (archive.org): https://web.archive.org/web/20080515183439/http://maplestory.wikia.com/wiki/Amherst
- Basilmarket forum (archive.org):
  - https://web.archive.org/web/20070202084419/http://www.basilmarket.com/forum/191098/1//Maple_Island_Glitches.html
  - https://web.archive.org/web/20070210135604/http://www.basilmarket.com/forum/203966/1/Maple_Islander_Level.html
- NiaMeowDB, MapleStory Classic (modern re-creation; secondary):
  - maps: https://meowdb.com/msclassic/maps/000001000 through `000001006`, `000001010` through `000001014`, `000001020`, `000001021`;
  - NPCs: https://meowdb.com/msclassic/npcs/17 (Lucas), /18 (Pio), /19 (Rain), /20 (Sid), /21 (Lucy);
  - quests: https://meowdb.com/msclassic/quest-tracker/1007, /1008, /1012, /1013.
- Not reachable this session:
  - maplestory.fandom.com (HTTP 402/403 to both WebFetch and curl);
  - strategywiki.org (403; its archived Maple Island pages are post-2010 or empty);
  - bbb.hidden-street.net (403).

## Open questions

1. **Unparsed portal positions**: 1010000 `in02` (Department Store door; estimated from the diagram at x≈1500-1600 on the middle terrace), 1010001 `out00`, 1010002 `out00`/`west00`, 1020000 `in00`, and 1000003 `out00`. Destinations are confirmed; exact coordinates are not. A raw WZ dump (for example HaRepacker on a v0.08-v0.22 `Map.wz`) would settle them.
2. **Field West of Amherst geometry**: v8 has 493 footholds and v22 has 396. Which is canonical for MisoStory?
3. **Mai's placement**: on the Amherst upper plateau (v8, Dec 2005) or at A Split Road (v22)?
4. **Backgrounds**: only Field East has a sourced background (sky, hills, giant tree). The other field maps' backdrops are unverified.
5. **Unidentified props**: the tall pale stalk cluster on an east-side island and the orange object by the east exit in 1000000; the bench/crate-like props in 1000005.
