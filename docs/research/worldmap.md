# Maple Island geography (classic, GMS v8-v40 world map)

Phase-1 research for MisoStory. Topic: where the 25 canonical Maple Island maps sit relative to each other on the island.

Labels used throughout:
- **[fact]**: read directly from data or images; the source is cited.
- **[derived]**: computed from facts. The method is stated.
- **[memory]**: recalled from memory and not checked against a source.
- **[proposal]**: my own design suggestion.

All coordinates are either **world-map illustration pixels** (the 411x348 world-map image) or **MapleStory map pixels** (in-map coordinates, y pointing down). Every number says which one it is. **Nothing here is a world scale.** Illustration-pixel distances do not convert to map pixels or meters.

---

## 1. Source and method

**Main source [fact]:** the game's own world-map sheet for Maple Island, read from the WZ data through maplestory.io:

- `https://maplestory.io/api/GMS/8/map/worldmap` returns `["WorldMap0","WorldMap1"]`. WorldMap0 is Maple Island and WorldMap1 is Victoria Island. According to this API listing, GMS v8 has **no** parent world sheet that shows both islands. That describes the listing, not a direct inspection of the WZ files.
- `https://maplestory.io/api/GMS/8/map/worldmap/WorldMap0` (fetched 2026-10-03) returns `baseImage` (one PNG, 411x348, `origin` = (205,174)), `links: []`, and 11 `maps[]` "spots" (below).
- `https://maplestory.io/api/GMS/40/map/worldmap/WorldMap0` returns a **byte-identical** base image and an identical `maps[]` array. The classic Maple Island world map therefore did not change from v8 to v40.
- `/api/GMS/12/map/worldmap` and `/api/GMS/22/map/worldmap` each list only `"WorldMap"`, and `/worldmap/WorldMap` returns HTTP 500 for both versions. Of the classic-era versions, only v8 gives usable world-map data.
- v62 lists `WorldMap00`, `WorldMap`, and others. `/api/GMS/62/map/worldmap/WorldMap` returns a parent world sheet of about 616 KB. I did not examine it (see open questions).

**No web or wiki search was done.** The WZ world-map sheet is the game's own primary data, so it is a better source than wikis or fan maps for this question. The local per-map JSON (`raw/gms_v8/<id>.json`) and the minimap images supplied the supporting facts.

**Files written:**
| File | What it is |
|---|---|
| `docs/research/ref_web/worldmap_1.png` | The decoded WorldMap0 base image (411x348 RGBA). **PROPRIETARY Nexon art. For reference only. Do not copy it into assets.** |
| `docs/research/ref_web/worldmap_1_spots_annotated.png` | The same image upscaled 2x, with red crosses and labels 0-10 at the spot coordinates. **A derivative of proprietary art. For reference only.** |
| `docs/research/raw/gms_v8_worldmap0_spots.json` | The WorldMap0 JSON with the base64 image removed: `origin`, `links`, and all 11 `maps[]` entries. |

**Coordinate convention of the spots [fact, verified]:** maplestory.io returns `spot` values that are already **image-pixel coordinates**, with (0,0) at the top-left of the 411x348 image. To check this, I drew the spots onto the image (`worldmap_1_spots_annotated.png`). All 11 land on the road drawn in the art: Mushroom Town on the mushroom houses, Amherst on the Amherst houses, Southperry beside the lighthouse and ship. If the spots were relative to `origin` (205,174), most of them would fall outside the image. For anyone using raw WZ data, the origin-relative values are also given below (`spot - origin`).

---

## 2. What the world map shows (described from `worldmap_1.png`) [fact: visual description]

Extents below are eyeballed in illustration pixels, with normalized values in brackets (x/411, y/348).

- **Background:** a purple-blue sea chart with parchment texture, decorative grid numbers (40, 50, 60, 70 along the top; 120, 130, 140 down the right edge), and a large sun face in the upper right. Bits of other land show at the image edges: dark forest bottom-left, mountains top-left, coast bottom-right.
- **Island form:** Maple Island is drawn as a **raised plateau with sheer grey-beige cliff walls**. Under the plateau the rock tapers to a point near (150-170, ~300) [0.37-0.41, ~0.86], with white cloud puffs around the cliff base. The island appears to hover above the sea chart. By contrast, the v8 Victoria Island sheet (WorldMap1, viewed but not saved) draws Victoria flat in the water with an ordinary coastline. Whether "floating" is meant literally or is just art style is an interpretation, not a fact.
- **Plateau top:** a bright-green surface whose long axis runs **NW to SE**. Roughly from the NW corner (~50,70) [0.12,0.20] and the north rim (~100-200, 15-30) [0.24-0.49, 0.04-0.09] to the east tip (~356,165) [0.87,0.47]. The south rim sits around the lighthouse (~200-240, ~220) [0.49-0.58, 0.63], and the SE rim around (~330,200) [0.80,0.57].
- **Mountain ranges:** olive-green conical peaks. Some peaks at the NW tip and NE of the lake have white cloud rings around their tops.
  - **West ridge:** runs NW to SE between the central valley and the west and south-west cliff edge.
  - **East ridge:** runs between the valley and the waterfall and lake.
  - **North-east massif:** north and north-east of the lake.
  - **Southern ridge:** a row of peaks along the lake's south shore that separates the lake from the road.
  - **Peaks south-west of Amherst:** a cluster between Amherst and the Split Road / Southperry area.
- **Waterfall:** drops from a high rock outcrop at about (195-220, 50-110) [0.47-0.54, 0.14-0.32].
- **Lake:** a purple-blue lake the waterfall feeds, at about (202-277, 97-137) [0.49-0.67, 0.28-0.39]. It is **inland**, NE of the valley road, north of the Split Road / Field West of Amherst stretch, and walled off from the road by the southern ridge.
- **Road:** a pale sandy road starts just south of Mushroom Town and runs SE down a broad green valley. It reaches a **fork** at the Split Road spot. One branch runs a short distance SE to Southperry on the south rim. The other runs east along the plateau, south of the lake ridge, into Amherst's plaza, then turns **south** out of Amherst toward the SE rim.
- **Mushroom Town:** a pocket of dark-green hedges and trees on the **north rim** with four mushroom houses: a blue cone roof, a small yellow one, a grey-brown cap, and a large orange cap. Area about (115-160, 25-60) [0.28-0.39, 0.07-0.17].
- **Southperry:** on the **south rim**.
  - A cream lighthouse with gold bands, a blue dome, and an orange-red cap at about (205-235, 140-220) [0.50-0.57, 0.40-0.63].
  - A small white building with a blue roof to its west.
  - A large blue-tiled roof to its east at about (228-270, 167-207) [0.55-0.66, 0.48-0.59].
  - A large sailing ship with bulky side barrels or engines **docked just SE of the town, over the rim**, at about (225-335, 190-300) [0.55-0.82, 0.55-0.86]. The ship's sails overlap the road's end at the Southperry spot.
- **Amherst:** at the **east end**, on a pale blue-white cobbled plaza at about (287-337, 150-180) [0.70-0.82, 0.43-0.52]. It has at least five mushroom houses (blue, yellow, orange-brown, light blue, orange-red). Mountains lie north of the plaza and the east cliff edge is just beyond it.

---

## 3. Spot table (11 spots from WorldMap0) [fact; descriptions from the image]

`type` is the WZ spot type as returned by maplestory.io. In this sheet, `type=0` is used exactly for the three towns (Mushroom Town, Southperry, Amherst) and `type=1` for everything else.

Labels 0-10 match `worldmap_1_spots_annotated.png`.

| Label | mapNumbers | type | spot px (x,y) | normalized (x,y) | spot - origin | What is drawn there | Rim / inland | Drawn water nearby |
|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 1 | (104,38) | (0.253,0.109) | (-101,-136) | West end of the Mushroom Town pocket, beside cloud-ringed peaks at the NW tip | **NW rim** (cliff drop beyond) | none (sea chart beyond the cliff) |
| 1 | 10000, 20000, 20001 | 0 | (132,48) | (0.321,0.138) | (-73,-126) | On the mushroom houses (orange-cap house) | **north rim** | none |
| 3 | 30000 | 1 | (141,67) | (0.343,0.193) | (-64,-107) | Start of the road, just south of the orange house | inland, just below the rim | none |
| 4 | 40000 | 1 | (160,86) | (0.389,0.247) | (-45,-88) | Road in the broad valley between the west and east ridges | inland valley | none |
| 5 | 40001 | 1 | (180,118) | (0.438,0.339) | (-25,-56) | Valley road, level with the waterfall base, which lies about 20-30 illustration px east across the east ridge | inland valley | waterfall and lake to the E, behind the ridge |
| 6 | 40002 | 1 | (213,144) | (0.518,0.414) | (8,-30) | Road just north of the lighthouse top, where the valley opens out | inland, near the south rim | lake to the NE, behind the ridge |
| 7 | 50000 | 1 | (249,170) | (0.606,0.489) | (44,-4) | **The road fork**: SE branch to Southperry, E branch to Amherst | inland, close to the south rim | lake to the N, behind the ridge |
| 2 | 60000, 60001 | 0 | (262,187) | (0.637,0.537) | (57,13) | Road end on the south rim. Lighthouse and blue-roof buildings to the W, docked ship to the SE | **south rim, the port** | ship drawn in the air beside the cliff S/SE; no sea surface drawn (only the purple-blue chart background) |
| 8 | 1000000-1000006 (7 maps) | 1 | (273,164) | (0.664,0.471) | (68,-10) | East branch of the road, south of the lake's southern ridge | inland strip between the ridge and the south rim | lake to the N/NW, behind the ridge |
| 9 | 1010000-1010004 (5 maps) | 0 | (312,165) | (0.759,0.474) | (107,-9) | Amherst plaza and mushroom houses | **east end**, near the E rim | none drawn (the plaza is pale blue-tinted paving, not water) |
| 10 | 1020000, 1020001 | 1 | (321,189) | (0.781,0.543) | (116,15) | Road leaving Amherst southward | near the **SE rim** | ship to the SW (drawn in the air; no sea surface drawn) |

---

## 4. Per-map position (all 25 canonical maps)

The world map gives a position for each **spot**, not for each map. Maps listed under the same spot have **no individual position** on the world map.

| ID | Name | Spot | mapMark [fact, raw/gms_v8] | streetName | Position notes |
|---|---|---|---|---|---|
| 0 | West Entrance to Mushroom Town | 0 | MushroomVillage | Maple Road | Own spot, NW tip. The westernmost map on the island |
| 10000 | Mushroom Town | 1 | MushroomVillage | Maple Road | Shares spot 1 with 20000 and 20001 |
| 20000 | Mushroom Town | 1 | MushroomVillage | Maple Road | Shares spot 1 with 10000 and 20001 |
| 20001 | Mushroom Town Townstreet | 1 | MushroomVillage | Maple Road | Shares spot 1 with 10000 and 20000 |
| 30000 | East Entrance to Mushroom Town | 3 | MushroomVillage | Maple Road | Own spot, SE of the town |
| 40000 | Snail Hunting Ground I | 4 | MushroomVillage | Maple Road | Own spot, upper valley |
| 40001 | Snail Hunting Ground II | 5 | MushroomVillage | Maple Road | Own spot, mid-valley, opposite the waterfall |
| 40002 | Snail Hunting Ground III | 6 | MushroomVillage | Maple Road | Own spot, lower valley, N of the lighthouse |
| 50000 | A Split Road | 7 | MushroomVillage | Maple Road | Own spot, the road fork |
| 60000 | Southperry | 2 | SouthPerry | Maple Road | Shares spot 2 with 60001. South rim port |
| 60001 | Southperry Armor Store | 2 | SouthPerry | Maple Road | Interior. Shares spot 2 |
| 1000000 | The Field West of Amherst | 8 | Amherst | Rainbow Street | Shares spot 8 with 6 side maps |
| 1000001 | In a Small Forest | 8 | Amherst | Rainbow Street | No individual world-map position |
| 1000002 | Dangerous Forest | 8 | Amherst | Rainbow Street | No individual world-map position |
| 1000003 | Mushroom Garden | 8 | Amherst | Rainbow Street | No individual world-map position |
| 1000004 | Snail Garden | 8 | Amherst | Rainbow Street | No individual world-map position |
| 1000005 | Hunting Ground Middle of the Forest I | 8 | Amherst | Rainbow Street | No individual world-map position |
| 1000006 | Hunting Ground Middle of the Forest II | 8 | Amherst | Rainbow Street | No individual world-map position |
| 1010000 | Amherst | 9 | Amherst | Rainbow Street | Shares spot 9. East-end town |
| 1010001 | Amherst Weapon Store | 9 | Amherst | Rainbow Street | Interior |
| 1010002 | Amherst Townstreet | 9 | Amherst | Rainbow Street | Shares spot 9 |
| 1010003 | Amherst Department Store | 9 | Amherst | Rainbow Street | Interior |
| 1010004 | Snail Field of Flowers | 9 | Amherst | Rainbow Street | Field map grouped with the **town** spot, not with a field spot. No individual position |
| 1020000 | The Field East of Amherst | 10 | Amherst | Rainbow Street | Shares spot 10 with 1020001. SSE of Amherst |
| 1020001 | Tomato Field | 10 | Amherst | Rainbow Street | No individual world-map position |

**Supporting per-map facts [fact, from `raw/gms_v8/<id>.json`]:**
- **mapMark zones match the world-map regions.** `MushroomVillage` covers 0 through 50000, so A Split Road still belongs to the Mushroom Town zone. `SouthPerry` covers 60000 and 60001. `Amherst` covers every 10xxxxx map.
- **streetName splits the island in two.** Every 0-60001 map is "Maple Road" and every 10xxxxx map is "Rainbow Street".
- **returnMap.** 40000, 40001, 40002 and 50000 all have `returnMap = 60000` (Southperry). Every 10xxxxx field has `returnMap = 1010000` (Amherst). The town maps 0-30000 return to themselves (`isTown = true`).
- **Background music.**
  - `Bgm00/FloralLife`: the Mushroom Town maps, Amherst, the Southperry armor store, Snail Field of Flowers, and Field East of Amherst.
  - `Bgm00/RestNPeace`: the snail grounds, Split Road, Field West of Amherst and its forest/garden side maps, and Tomato Field.
  - `Bgm00/GoPicnic`: Southperry.

---

## 5. Directions: side-view travel compared with world-map compass

The world map has no compass rose. **Assumption:** image-up = north, the usual reading of a sea chart. Bearings are measured on the image (0° = east/right, +90° = south/down), and distances are **illustration px. They are not a scale and must not be related to map sizes.**

| From spot -> to spot | Bearing | Rough compass | Illustration px |
|---|---|---|---|
| 0 West Entrance -> 1 Mushroom Town | 20° | E by S | 29.7 |
| 1 Mushroom Town -> 3 East Entrance | 65° | SSE | 21.0 |
| 3 East Entrance -> 4 SHG I | 45° | SE | 26.9 |
| 4 SHG I -> 5 SHG II | 58° | SE by S | 37.7 |
| 5 SHG II -> 6 SHG III | 38° | SE | 42.0 |
| 6 SHG III -> 7 Split Road | 36° | SE | 44.4 |
| 7 Split Road -> 2 Southperry | 53° | SE | 21.4 |
| 7 Split Road -> 8 Field West of Amherst | -14° | E (slightly N) | 24.7 |
| 8 Field West -> 9 Amherst | 1° | E | 39.0 |
| 9 Amherst -> 10 Field East of Amherst | 69° | SSE | 25.6 |

Bearings are between **spots**. The 0 -> 1 -> 3 order follows the map names (West / town / East Entrance). The world map itself does not order 10000, 20000 and 20001, because they share spot 1.

**How side-view left/right relates to these bearings [derived from portal x positions in local JSON]:**
- **Maple Road advances left to right in side view.** Within 30000, the entrance `in00` is at x = -218 and the exit `out00` (to 40000:in00) is at x = 1433. The exit is therefore about 1650 map px to the right of the entrance. In 40000, the arriving `in00` is at x = -172. Source: `raw/gms_v8/30000.json`, `raw/gms_v8/40000.json`. Side-view "rightward" along Maple Road therefore corresponds to **SE** on the world map.
- **Amherst's far-right portal leads to the Field East of Amherst.** In Amherst, the `in00` and `tp` portals cluster at x = 169-621, while `east00` (to 1020000:west00) is at x = 3055, far to their right (`raw/gms_v22/1010000.json`). In 1020000, `west00` is at x = -332 (`raw/gms_v8/1020000.json`). On the world map this "east" exit heads **SSE**. Portal names like `east00` / `west00` are side-view directions, not compass directions.
- **Ends of a map.** Statements like "left end" or "right end" for a single portal rely on the API `miniMap` `centerX`/`width` span, which I have not verified. On that basis, 40000 spans about x -350..2984, 1020000 about -558..2237, and 1020001 about -486..2597. That puts 40000 `in00`, 1020000 `west00` and 1020001 `out00` (x = -275, to 1020000:in00) all near the left ends of their maps.
- **Forest II exits from the top.** 1000006 `out00` (to 1000000:in05) is at x = 133, y = -1346, near the top of the map. This is a vertical exit.
- **Southperry has its dock at the right end** [fact: `ref_renders/v8_60000_minimap.png`]. The ship sits on a raised stone dock at the right edge of the minimap. The lighthouse is in the middle, white and blue-roof houses are on the left, and the ground is stone or cobble throughout. This agrees with the world map, which puts the ship SE of the Southperry spot.
  - The armor store entrance (`in00` to 60001) is at x = 699 (`raw/gms_v22/60000.json`). `gm00` is at x = -65.
  - Which end of Southperry connects to A Split Road cannot be determined: all its parsed portals point to 999999999 (target unknown) or are null.

---

## 6. Facts that constrain the 3D island layout

These are facts, or direct readings of facts.

1. **Mushroom Town is at the north / north-west rim.** It is the start of the island, and West Entrance (map 0) is the island's extreme NW map.
2. **Maple Road runs NW to SE down a single valley** between two mountain ridges, passing Mushroom Town East Entrance, SHG I, SHG II, SHG III, then A Split Road, at spot spacing of roughly 20-45 illustration px.
3. **A waterfall and inland lake** sit NE of the valley, roughly level with SHG II / SHG III. A mountain ridge separates them from the road.
4. **A Split Road is the only fork.** It sits just inland of the south rim, about 60% of the way across the image.
5. **Southperry is the port on the south rim,** just SE of the fork. Its landmarks are a lighthouse and blue-roofed buildings, and the ship docks on the seaward SE side, which is the right end in side view.
6. **The Rainbow Street maps run east** from the fork, south of the lake ridge, to Amherst at the east end of the island. Field East of Amherst / Tomato Field lie SSE of Amherst, toward the SE rim near the ship.
7. **Six forest/garden side maps share one spot** with The Field West of Amherst. Snail Field of Flowers shares Amherst's spot, and Tomato Field shares Field East's spot. The world map does not place any of these individually.
8. **Unconfirmed link [derived, NOT in parsed portal data].** The link 50000 A Split Road -> 1000000 The Field West of Amherst is **inferred** from three things: the drawn road branch, the adjacency of spots 7 and 8, and the mapMark/streetName boundary between 50000 and 1000000. All three portals of 50000 and all eight of 1000000 are `null` in the v8 API data, as are 1000000's eight portals in v22.

---

## 7. [proposal] Placing the maps that have no individual world-map position

These are design suggestions only, not sourced facts.

- **[proposal] Field West of Amherst side maps (1000001-1000006).** The Field West spot sits on a narrow strip between the lake's southern ridge (to the N) and the south rim (to the S). Place the forest maps **north of the field**, filling the forested and mountainous belt between the road and the lake:
  - In a Small Forest and Dangerous Forest as the nearer and further forest pockets.
  - Hunting Ground Middle of the Forest I and II stacked deeper toward the lake ridge. 1000006 exits from its top into 1000000 (`in05`), which fits a "climb back down/out" arrangement.
  - Put Mushroom Garden and Snail Garden as small clearings on the **south side** of the road. Use the peak cluster between Field West and Amherst, at about illustration (270-295, 167-190), which lies east of Southperry's blue-tiled roofs and north of the ship.
  - Whatever arrangement is chosen should keep all six closer to spot 8 than to spots 7 or 9.
- **[proposal] Snail Field of Flowers (1010004).** It is grouped with the Amherst town spot, so keep it right beside Amherst, for example on the slope north of the plaza under the north-east massif. It shares Amherst's `FloralLife` BGM, which supports making it a "town garden".
- **[proposal] Tomato Field (1020001).** It joins Field East of Amherst at its left end, so make it a **spur off Field East** toward the SE rim, between Amherst and the ship's anchorage.
- **[proposal] Mushroom Town internal order.** West Entrance (0), then Mushroom Town (10000 / 20000), then Townstreet (20001), then East Entrance (30000), running W to E along the north-rim pocket and bending SE into the valley head. Townstreet's exact place among the town maps is not established here.
- **[proposal] Island silhouette.** Follow the world map: an elongated plateau with its long axis NW-SE, cliff walls all round, the snail valley in the west half, the lake and waterfall in the north-centre, the lighthouse port in the south-centre, and Amherst on the east tip. Whether the island visibly floats (rock underside, clouds) or rises from the sea is an art-direction choice. The source art shows a tapering rock underside with clouds, while the same era's Victoria sheet is drawn flat in water.

---

## 8. Not determined here

- Exact portal topology inside the Mushroom Town group, A Split Road (three null portals), Southperry (which end leads to Split Road), and The Field West of Amherst hub (eight null portals).
- Where Maple Island sits relative to Victoria Island. The v8 data has no parent sheet. The v62 `WorldMap` parent sheet exists but was not examined. It is post-classic and may differ.
- Any absolute scale. The world-map art is schematic, and illustration px must not be converted to map pixels.
