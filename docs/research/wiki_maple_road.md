# Maple Road reference: descriptive, visual and narrative notes (classic GMS v8 to v22)

Maps covered: 0, 10000, 20000, 20001, 30000, 40000, 40001, 40002, 50000, 60000, 60001
(all on street "Maple Road", Maple Island). Phase-1 research for MisoStory.

## How to read this file

- **Labels.** Every claim carries one of these labels:
  - `[S#]`: sourced. Source numbers are listed below. "WZ" means the raw map data served by maplestory.io's WZ endpoint for **GMS v8**, saved locally under `docs/research/raw/gms_v8_wz/<id>.json`. v22 data is saved under `docs/research/raw/gms_v22_wz/` for comparison.
  - `[memory]`: something I recall but did not verify against a source in this session.
  - `[reading]`: my own visual interpretation of a sprite or screenshot. The image itself was viewed, but the meaning I give it is mine.
  - `[proposal]`: a design suggestion for MisoStory.
- **Units.** All coordinates and sizes are MapleStory pixels. y increases **downward**. Map extents come from the foothold bounding box in `raw/gms_v8/<id>.json`. Tier descriptions are qualitative, read from the renders and minimaps. Exact geometry belongs to the topology owners.
- **Object paths.** These are given as `oS/l0/l1/l2 @x,y`, the WZ object-set path plus the placement position. They identify the exact sprite.
- **Proprietary images.** The images under `ref_renders/` and `ref_web/` are proprietary reference material. No sprite images were copied into the project. Object sprites were viewed only from a temp folder and are cited here by WZ path.

## Sources

| # | Source | URL / path |
|---|---|---|
| S1 | maplestory.io map API, GMS v8 (lossy portals) | `docs/research/raw/gms_v8/<id>.json` (= https://maplestory.io/api/GMS/8/map/<id>), plus `gms_v22/` |
| S2 | maplestory.io **WZ endpoint**, GMS v8: full layers (tileset `tS`, objects `oS/l0/l1/l2`, backgrounds `bS`, portals `pn/pt/tm/tn`, life). Crawled this session. | https://maplestory.io/api/wz/GMS/8/Map/Map/Map0/000000000.img (pattern `.../Map0/<9-digit id>.img/<path>`); object sprites at `.../api/wz/GMS/8/Map/Obj/<set>.img/...`, backgrounds at `.../Map/Back/<set>.img/back/<n>`. Saved: `docs/research/raw/gms_v8_wz/*.json`, `docs/research/raw/gms_v22_wz/*.json` |
| S3 | maplestory.io NPC API (names and idle dialogue strings) | https://maplestory.io/api/GMS/8/npc/<id> (v22 for 2004, 2005, 12100) |
| S4 | maplestory.io mob API (stats) | https://maplestory.io/api/GMS/22/mob/<id> |
| S5 | Official GMS site, Maple Island map page, Jan 2005 and May 2006 captures | https://web.archive.org/web/20050107004204/http://www.mapleglobal.com:80/library/map_maple.aspx and https://web.archive.org/web/20060528204733/http://www.mapleglobal.com:80/WZ.ASPX?PART=/Guide/GameLibrary/MapleWorldMap/MapMaple |
| S6 | Official GMS site screenshot gallery, image 001 (map 0) | https://web.archive.org/web/20050720140333/http://www.mapleglobal.com/gallery/screen_shot/001.jpg (gallery page: https://web.archive.org/web/20050113054458/http://www.mapleglobal.com:80/gallery/screen_shot/001.html). Local copy: `ref_web/0_1.jpg` |
| S7 | Hidden Street, Maple Island maps index, Oct 2005 | https://web.archive.org/web/20051026010039/http://www.hidden-street.net:80/maps/mapleis.php |
| S8 | Hidden Street, "Mushroom Town / Southperry" map list, Nov 2005 | https://web.archive.org/web/20051126212258/http://www.hidden-street.net:80/maps/misouthperry.php |
| S9 | Hidden Street, Southperry page, Feb 2006, plus its screenshot | https://web.archive.org/web/20060220061844/http://www.hidden-street.net:80/maps/southperry.php ; image https://web.archive.org/web/20060529110122/http://www.hidden-street.net:80/maps/images/southperry01.jpg. Local copy: `ref_web/60000_1.jpg` |
| S10 | Hidden Street, Maple Island quests, Feb 2006 | https://web.archive.org/web/20060225085306/http://www.hidden-street.net:80/quests/mpislandquestall.php (and `mpislandquest_001.php` ... `_010.php`, same capture era) |
| S11 | Hidden Street guide "Maple Story FAQ / Tips For Beginners" by fillet2, v1.20 Aug 2005 | https://web.archive.org/web/20051013071907/http://www.hidden-street.net:80/guides/beginner_001.php |
| S12 | Hidden Street guide "D1Super Noob Guide" by DivineNoob, 9 Jul 2005 | https://web.archive.org/web/20051013063720/http://www.hidden-street.net:80/guides/beginner_003.php |
| S13 | StrategyWiki, MapleStory/Towns, Nov 2006 | https://web.archive.org/web/20061108042857/http://strategywiki.org/wiki/MapleStory/Towns |
| S14 | StrategyWiki, Mushroom Town & Mushroom Town Training Camp (page modified 2 May 2007) | https://web.archive.org/web/20070513072813/http://strategywiki.org:80/wiki/MapleStory/Towns/Mushroom_Town_&_Mushroom_Town_Training_Camp |
| S15 | StrategyWiki, Southperry (armor store list; modified 14 Sep 2006) | https://web.archive.org/web/20070106061115/http://www.strategywiki.org:80/wiki/MapleStory/Towns/Southperry |
| S16 | StrategyWiki, Quests/Maple Island (modified 8 Mar 2007) | https://web.archive.org/web/20070420131407/http://strategywiki.org:80/wiki/MapleStory/Quests/Maple_Island |
| S17 | StrategyWiki 2014 (post-Big Bang) Southperry and Maple Tree Hill | https://web.archive.org/web/20140330181101/http://strategywiki.org/wiki/MapleStory/Southperry ; https://web.archive.org/web/20140330193344/http://strategywiki.org/wiki/MapleStory/Maple_Tree_Hill |
| S18 | MapleWiki (wikia), 2007 | https://web.archive.org/web/20070717091248/http://maplestory.wikia.com:80/wiki/Maple_Island ; https://web.archive.org/web/20071204190056/http://maplestory.wikia.com:80/wiki/Southperry ; https://web.archive.org/web/20071205001415/http://maplestory.wikia.com:80/wiki/Mushroom_Town ; https://web.archive.org/web/20070703154736/http://maplestory.wikia.com/wiki/Mushroom_Town_Training_Camp |
| S19 | MapleStory Fandom wiki (modern), read via api.php | https://maplestory.fandom.com/wiki/Southperry , /wiki/Mushroom_Town_Training_Camp , /wiki/Maple_Tree_Hill , /wiki/Snail_Park , /wiki/Split_Road_of_Destiny_(Maple_Island) , /wiki/Port , /wiki/Biggs , /wiki/Pan |
| S20 | maplestorywiki.net (modern) | https://maplestorywiki.net/w/Maple_Island , /w/Southperry , /w/Mushroom_Town_Training_Camp |
| S21 | MapleStory Music wiki | https://maplestory-music.fandom.com/wiki/Floral_Life , /wiki/Rest_'N_Peace , /wiki/Go_Picnic |
| S22 | meowdb "MapleStory Classic" database (modern; **different map IDs**) | https://meowdb.com/msclassic/maps/000000001 , /000000010 , /000000020 , /000000021 |
| S23 | Local partial renders and minimaps (viewed, not copied) | `docs/research/ref_renders/v8_<id>_render.png`, `v8_<id>_minimap.png` |

---

## 1. Island-level facts (apply to every Maple Road map)

**Official framing, GMS site 2005 and 2006 [S5].** Quoted verbatim:

> "It is similar to <Victoria Island>, the main island, in that it has shops, houses, and monsters that appear in the real game for the beginners to adapt to the game. In this island, there are: the Mushroom Village, the first town of the game; Southperry, the harbor town; and Amherst, the town of quests. At this island, novice travelers learn various skills and techniques with the help of NPC. Once several quests are completed and a certain level is reached, the traveler can finally board on the ship <Victoria>, anchored at Southperry, to go to Victoria Island. <Maple Island>, an island floating somewhere in the sky of <Maple World>, is a mysterious island of no-return, once it is left behind for Victoria Island."

Hidden Street paraphrased this in 2005 and 2006 [S7, S9].

**One-way exit.**
- The ship fare was 150 mesos, and you could not come back. Four independent era sources agree:
  - S8 (Nov 2005): "Lith Harbor (pay 150 mesos)"
  - S11 (Aug 2005): "You'll need 150 mesos for the ship ride from South Perry. When you leave you won't be able to come back."
  - S13 (Nov 2006)
  - S18 (2007)
- A later-era web summary quoted 500 mesos. I did not verify which version changed the fare.

**Street name.**
- All 11 maps have `streetName` "Maple Road" [S1]. "Maple Road" also appears on map 1020000 [S19].
- Hidden Street's 2005 map list labels every Mushroom Town, Snail Hunting Ground and Split Road map "**Rainbow Street**: ..." [S8]. The Southperry entry has no prefix. That list was "translated from MapleStory Maps" by LanzeNL [S7].
- [memory] "Rainbow Street" probably comes from the Korean street name. CMS calls the island 彩虹岛 "Rainbow Island" [S20].

**Map marks.** Maps 0 to 50000 use the map-mark icon `MushroomVillage`. Maps 60000 and 60001 use `SouthPerry` [S1, S2].

**Music.**

| BGM | Maps | Notes |
|---|---|---|
| `Bgm00/FloralLife` | towns: 0, 10000, 20000, 20001, 30000, **and the Southperry Armor Store 60001** | 2:17 [S21] |
| `Bgm00/RestNPeace` | fields: 40000, 40001, 40002, 50000 | 2:55, 90 BPM [S21] |
| `Bgm00/GoPicnic` | Southperry 60000 | 1:12 [S21] |

- All three tracks are credited to CODASOUND [S21].
- S21 says Floral Life "was played in areas around old version of Maple Island", Rest 'N Peace in the "old version of Maple Island field", and Go Picnic "was also used as Southperry's bgm in the past". These tracks are now associated with Henesys.

**Return map and towns.**
- The fields 40000 to 50000 have `returnMap` 60000 (Southperry) [S1].
- The Mushroom Town maps return to themselves, because they are `town=1` [S2].
- 50000 has `mobRate` 1.5. The snail grounds are at 1.0 [S2].

**Tilesets and backgrounds (the island's visual vocabulary)** [S2; sprites viewed via the S2 object and background paths]:

| Kind | WZ set | What it looks like [reading] | Used on |
|---|---|---|---|
| Tileset | `grassySoil` | Olive/khaki lumpy earth blocks (base tile 90x60) with a bright green tufted-grass top edge (90x38). Small grey rocks with grass are embedded in the faces. | 0, 10000, 20000, 20001, 30000, 40000-40002, 50000 |
| Tileset | `whiteMarble` | Cream/white irregular flagstone ("crazy paving") with grey grout (90x60); thin flagstone edge strips | 60000 |
| Background set | `grassySoil` back 0-6 | Flat mid-blue sky tile; huge white cumulus cloud band (1024x579); a very wide distant rounded hill with a tiny tree and path (2493x340); a big leafy oak canopy (315x268); golden-green grass rolling-hill strips (1024x257); a hill strip with stone ruins and a golden tree | town maps 0-30000, 20001 (and sky/clouds on 60000) |
| Background set | `midForest` back 0-4 | Sky tile; misty pastel mountains reflected in a lake (635x719); strips of white-barked trees with olive/orange/teal tufted canopies over golden grass (~1024x440-500) | 40000, 40001, 40002, 50000 |
| Background set | `portTown` back 3-6 | Free-standing white cumulus clouds | 60000 |

- Background `type` values seen: 0, 1, 3, 4.
- [memory] Type 3 means tiled in both directions (sky fill). Type 1 means tiled horizontally. Type 4 means horizontally tiled and drifting (moving clouds).

**Recurring prop vocabulary** (WZ object sets) [S2, reading of sprites]:
- `houseGS/house6`: orange mushroom cap on a cream stem. Optional `deco/0` adds yellow spots.
- `houseGS/house7`: yellow cap with a dark brim band.
- `houseGS/house8`: yellow cap with dark streaks, on a stem with a wooden collar.
- `door/grassySoil/*`: mushroom-awning doors, plank doors, and a round yellow dormer window.
- `house/grassySoil/chimney/0`: wooden barrel chimney with a yellow lid.
- `house/grassySoil/chimney/3`: barrel chimney on a stone oven base.
- `house/grassySoil/lamp/2`: black iron wall lantern.
- `acc1/grassySoil/nature/*`: bushes (13), red-spotted toadstool clusters (14), rows of small coloured mushrooms (17), tall pale stalk-mushroom clusters (11, 25), sunflowers (22-24), clover with pink flowers (10), small flowers and butterflies (5, 6, 19-21), red-berry shrub row (0).
- `acc1/darkWood/nature/*`: dark grass tufts (16-19) and dark/olive bushes (9, 20).
- `acc1/midForest/nature/*`: white-barked, birch-like trees with spiky tufted canopies in green, teal, orange and olive-yellow (0-7); big leafy plant (8); lily-of-the-valley (9); daffodils (10); dirt clumps (11).
- `guide/midForest/wood/*`: wooden signposts with green vines, and plank arrow boards.
- `connect/ladder/0`, `connect/rope/0`: ladder and rope sprites.

**NPC sprite reuse.**
- The NPC API marks Todd (2004) and Sam (2005) with `"link": 2003`, meaning they reuse Robin's sprite [S3].
- Viewing the NPC icons [reading]: Peter (2002), Robin (2003), Todd and Sam are the same brown-haired man in a navy uniform. Nina (2102) and Yoona (20100) share a blue-haired bunny-ear girl sprite. Sera (2100) and Maria (2103) share a wavy-haired woman in a brown dress with a white apron.
- [proposal] MisoStory can reuse character models the same way. That is era-faithful.

---

## 2. The Mushroom Town maps by ID (the "which Mushroom Town is which" question)

Two maps share the name "Mushroom Town" (10000 and 20000). 20001 is "Mushroom Town Townstreet". They differ as follows:

| | **0** West Entrance | **10000** "Mushroom Town" (1st) | **20000** "Mushroom Town" (2nd) | **20001** "Townstreet" | **30000** East Entrance |
|---|---|---|---|---|---|
| NPC (v8) | Heena 2101, Sera 2100 | **Roger 2000** | **Nina 2102** | **Sen 2001** | Peter 2002 (Todd 2004 added by v22) |
| House | `houseGS/house6` **orange cap with yellow spots** (`deco/0`), barrels, wall lantern | `houseGS/house8` **yellow cap with dark streaks**, barrel chimney `chimney/0`, plank door | `houseGS/house6` **orange cap, no spot overlay in v8**, stone-oven chimney `chimney/3`, mushroom-awning door that is the portal into 20001 | **Interior**: cutaway orange mushroom house `insideGS/house1` with bed, bookshelf, chest, curtained window, hanging lamps | `houseGS/house7` **yellow cap with dark brim**, dormer window, lantern |
| Other identifiers | Clothesline with laundry beside Sera; ladder up a cliff; tiny floating grass clump | Vine-and-rope picket fences; sunflower patch at the arrival point | Ladder (x=197) to a high floating grass island; flowers and clover | No minimap node | Tall vertical climb; wooden signposts; tall pale mushroom clusters |
| Exits (WZ portals) | `out00`@1052,365 to 10000:`in00` | `out00`@706,216 to 20000:`in00` | `in01`@557,94 to 20001:`out00` (house door); `out00`@795,96 to 30000:`in00` | `out00`@-167,244 to 20000:`in01` | `out00`@1433,-924 to 40000:`in00` |

Evidence for the identifications:

- **Hidden Street (Nov 2005) labels.** It calls the middle two maps "Mushroom Town I" and "Mushroom Town II" [S8]. Its thumbnails are 98x54, 77x49, 82x51 and 122x116. These match the local v8 minimap sizes to within 1 px: 0 = 99x54, **10000 = 77x49**, **20000 = 82x51**, 30000 = 122x116 [S23]. Snail Hunting Ground I is also within 1 px: 207x104 there, 208x105 locally. So **Mushroom Town I = 10000 and Mushroom Town II = 20000**. Hidden Street chains them West Entrance, then Mushroom Town I, then Mushroom Town II, then East Entrance [S8].
- **Map 20001 is Sen's house.**
  - StrategyWiki 2007: "Nina can be found in the third map of Mushroom Town" and "Walk towards the right and press 'Up' on the portal to go into the house. Double click on Sen ..." [S16]. The third map counting from 0 is 20000.
  - Hidden Street 2006: "Head into the house which is the same map and talk to Sen" [S10].
  - WZ: the door portal `in01` in 20000 sits at x=557, right on the house doors `door/grassySoil/door/8, /10` @555-565. Its target is 20001, where Sen (2001) stands among `insideGS/house1` interior objects [S2].
  - meowdb's modern "Classic" database lists Mushroom Town (Nina) connecting to "Mushroom Town Townstreet" (Sen), which is a dead end [S22]. Its IDs differ (000000020, 000000021).
- **Roger is in the second screen.** S11 (2005): "In the 2nd screen, a creepy looking guy called Roger ...". This matches 10000.

---

## 3. Per-map sections

### 0: West Entrance to Mushroom Town (slug `WestEntranceMushroomTown_0`)

**Data [S1, S2].**
- Street Maple Road; `town=1`; BGM FloralLife; mapMark MushroomVillage; returnMap 0.
- Extents x[-264,1254], y[50,570]: about 1518 x 520 px.
- Tileset `grassySoil` (164 tiles over layers 0 and 2).
- Backgrounds `grassySoil` 0, 1, 2, 3, 5, 6: sky, drifting cumulus, distant hill, big oak canopy, two grass-hill strips.
- Portals: 4 spawn points (`sp`) at x -206..-112, y≈102 (new characters appear on the left plateau). One visible exit `out00`@1052,365 leads to 10000:`in00`. There is no portal back into map 0.

**Terrain (render, minimap) [S23]:**
- High left plateau (spawn level).
- Two small steps down to a lower valley floor. The valley runs right to the exit.
- A tall right-hand block, top at y=125, rising above the valley. It is reached by a ladder at x=975 (y 127..363).
- A tiny floating grass clump at the upper left, near Heena.

**NPCs:**

| ID | Name | Position (v8) | Role and evidence |
|---|---|---|---|
| 2101 | Heena | -48,65 (above the spawn, on the floating clump) | Movement tutor. Dialogue: "Press left Alt key and you'll be able to jump." / "Press the arrow keys to move around here and there." / "Beautiful day today!" [S3]. Starts the mirror quest ("Sarah's Mirror" in S10, "Sera's Mirror" in S16): fetch Sera's mirror, 1 EXP. StrategyWiki: "Heena can be found right above your head when you first start the game" [S16]. |
| 2100 | Sera | 833,125 (top of the right block) | Heena's sister, hanging laundry. Dialogue: "It's a neverending pile of laundry I'm hanging up here." / "Why isn't Heena helping me hang this load of laundry up?" / "Press↑ and you'll be able to climb up the ladder or a rope." [S3]. That last line fits the ladder at x=975 right next to her. |

**Monsters:** none (town).

**Landmarks [S2; sprites read by me]:**
- **Orange mushroom house with yellow spots.**
  - Parts: `houseGS/house6/basic/0` (stem) @126,104; `basic/1` (cap) @135,2; `deco/0` (spots) @141,1.
  - Doors `door/grassySoil/door/9` @71,118 (mushroom-awning door frame) and `door/11` @74,139.
  - Iron wall lantern `house/grassySoil/lamp/2` @0,120.
  - Barrels `acc1/grassySoil/artificiality/10, 11` @264,157 and 212,156.
- **Sera's clothesline.**
  - `acc1/grassySoil/artificiality/18` @977,68: two forked wooden poles with a rope.
  - `/19` @935,74: a hanging shirt.
  - `/20` @992,73: jeans and a white cloth.
  - Red-berry shrub row `nature/0` @1051,104; butterfly `nature/20`.
- **Mushroom clumps in the valley.**
  - `nature/17` @870,337: row of small white, orange, red and green mushrooms, visible in the render.
  - `nature/14` @604,312: red-spotted toadstools.
  - `nature/18` @569,345: tiny white mushrooms.
- Bushes: `grassySoil/nature/13` @-17,119 and 579,299; olive bushes `darkWood/nature/9` @-133,133 and 728,313.
- Ladder sprite column `connect/ladder/0` at x=975.

**Era screenshot.** `ref_web/0_1.jpg`, the official GMS gallery shot [S6]. Its minimap matches the v8 map 0 minimap. What it shows:
- A level-1 "Novice" in a white T-shirt beside the big orange mushroom house with yellow spots. The house has a wooden door, barrels and a wooden barrel stack.
- Heena sits with a "DOUBLE CLICK" hint bubble on a small grassy floating clump at the upper left, by a black iron lantern.
- The background has a huge gnarled oak with spreading canopy, rolling grass hills and a field of wooden stakes and fences on the right, under a bright blue sky with big fluffy clouds.
- Ground is the olive rock-and-grass tile. The chat line reads "[Welcome] Welcome to MapleStory!!".

**Atmosphere.** Bright, pastoral and gentle: blue sky, cartoon cumulus, green and gold rolling hills, a giant oak. The FloralLife town theme plays.

**What makes it recognizable.**
- The very first screen of the game.
- The orange, yellow-spotted mushroom house.
- Heena perched just above the spawn point.
- Sera's laundry line up on the cliff.
- [memory] Classic first-day memories: double-clicking Heena, fetching the mirror.

**Player memory [S11, 2005]:**
> "In the first screen, you will see two Non-Player Characters (NPCs). Talk to Heena, she will explain BASIC MOVEMENT ... don't press up at the portal (the place with the glowing light from the ground). Talk to Sera, she will give you a mirror. Then go talk to Heena, she will take you to the next screen/map."

The later official "World Archive" retrospective says: "All new travelers were once greeted by Heena and Sera, but these two have settled down to lead a quiet life." [S20]. This is modern flavour text, not 2005 content.

---

### 10000: Mushroom Town, the first one (slug `MushroomTown_10000`)

**Data [S1, S2].**
- town; BGM FloralLife; returnMap 10000.
- Extents x[-309,849], y[65,480]: about 1158 x 415 px.
- Tileset `grassySoil` (95 tiles).
- Backgrounds `grassySoil` 0, 1, 2, 3, 6 (6 is horizontally tiled).
- Portals: `sp`@-91,181; `in00` (type 1, arrival point only)@-195,278; `out00`@706,216 to 20000:`in00`. There is no portal back to map 0.
- **Note:** the local render `v8_10000_render.png` lost its tiles. It shows only two fences. Use the minimap and WZ data instead [S23].

**Terrain (minimap) [S23].** Lower ground on the left rises by one slope to a higher right tier that carries the house.

**NPCs:**

| ID | Name | Position | Role and evidence |
|---|---|---|---|
| 2000 | Roger | 233,65 | Inventory and potion tutor. Dialogue covers the item inventory tabs, double-clicking items to use them, HotKeys, "You'll die once your HP reaches 0, so it's for your own good to take a potion or food before it's too late." [S3]. S11 (2005): "a creepy looking guy called Roger will take away some of your health! Press I to open your Inventory ... double-click the Apple. Talk to Roger again, he'll give you 3 Red Potions." meowdb lists the quest as "Roger's Apple" [S22]. Peter calls Roger his older brother [S3]. |

**Monsters:** none.

**Landmarks [S2]:**
- **Yellow-capped mushroom house with dark streaks.** Parts: `houseGS/house8/basic/1` (cap) @481,56; `basic/0` (stem with wooden collar) @485,138; `deco/0` (arched doorway) @445,169; `door/grassySoil/door/13` (plank door) @450,167.
- **Barrel chimney with a yellow lid** `house/grassySoil/chimney/0` @588,-16.
- **Vine-wrapped picket fences tied with blue rope** `acc1/grassySoil/artificiality/2` @327,44 and @547,190. These are the only things the render drew.
- Sunflower patch at the left arrival point: `nature/22, 23, 24` @-227..-144, 228..249; butterfly `nature/20` @-261,182.
- Bushes `nature/13` ×3 and `darkWood/nature/9` ×3.

**Atmosphere.** Same pastoral sky and hills as map 0. A smaller, cosier single-house screen.

**What makes it recognizable.**
- Roger: in the 2005 player's words, the "creepy" guy who hurts you so you learn to eat an apple [S11].
- The yellow, striped-cap house with a barrel chimney.

---

### 20000: Mushroom Town, the second one (slug `MushroomTown_20000`)

**Data [S1, S2].**
- town; BGM FloralLife.
- Extents x[-309,939], y[-85,420]: about 1248 x 505 px.
- Tileset `grassySoil` (108 tiles).
- Backgrounds `grassySoil` 0, 1, 2, 3, 5, 6.
- Portals: 3 `sp` at x -256..-173, y≈123; `in00` (arrival)@-207,218; **`in01`@557,94 to 20001:`out00` (the house door)**; `out00`@795,96 to 30000:`in00`.

**Terrain (render, minimap) [S23].**
- Low ground on the left, one step up, then a broad right plateau carrying the house.
- Floating grass islands: a high central one reached by the ladder at x=197 (y -83..153), and a smaller left one with a clover plant.

**NPCs:**

| ID | Name | Position | Role and evidence |
|---|---|---|---|
| 2102 | Nina | -59,95 | Dinner quest-giver. Dialogue: "What would be good for dinner?" / "I'm cute, right?" [S3]. Quest "Nina and Sen's Dinner Menu": ask Sen inside the house what he wants, then report back, 3 EXP [S10, S16]. |

**Monsters:** none.

**Landmarks [S2]:**
- **Orange-capped mushroom house.** `houseGS/house6/basic/0` @597,14 and `basic/1` @606,-88. The v8 data has no `deco/0` spot overlay here, unlike map 0.
- Two mushroom-awning doors `door/grassySoil/door/8` @555,40 and `door/10` @565,50. This is the entrance to Sen's house: portal `in01` at x=557.
- **Stone-oven chimney with barrel stack** `house/grassySoil/chimney/3` @750,-46.
- Ladder column `connect/ladder/0` at x=197 up to the high floating island.
- Small yellow and orange flowers `nature/5, 6` on the platforms; pink-flowered clover `nature/10` @-25,184 and @52,188.
- Red toadstools `nature/14` @678,43.
- Bushes: `nature/13`, `darkWood/nature/20` (dark bush) @-89,85, `darkWood/nature/9` @833,44.

**What makes it recognizable.** Nina the bunny-eared girl, an orange mushroom house you can walk into, and the ladder to the floating island.

---

### 20001: Mushroom Town Townstreet, Sen's house (slug `MushroomTownTownstreet_20001`)

**Data [S1, S2].**
- town; BGM FloralLife; **no `miniMap` node** (the API minimap is a broken 215-byte file).
- Extents x[-579,489], y[-117,480]: about 1068 x 597 px.
- Main ground at y=275 across the full width.
- A raised floor at y=246 from x -221..129, an upper floor at y=69 (x -141..129), and a closed box above at y 47..-117 (x -142..138).
- Ladder at x=77 (y 49..244).
- Tileset `grassySoil` (65 tiles: just the street strip).
- Backgrounds `grassySoil` 0 (sky), 1 (clouds) @112,10, 2 (hill) @324,163, 3 (big oak) @203,-141. **The interior is drawn as a cutaway house standing outdoors, with sky, hill and oak visible behind it.**
- Portals: `sp`@-329,241; `out00`@-167,244 to 20000:`in01`. This is a dead end.

**NPCs:**

| ID | Name | Position | Role and evidence |
|---|---|---|---|
| 2001 | Sen | 24,246 (ground floor) | Hungry little boy. Dialogue: "I'm... so ... hungry!" / "Can... I... eat this ...?" [S3]. Answers Nina's dinner question [S10, S16]. The later official retrospective: "Sen, who used to keep careful watch over his house, still loves to eat Nina's candy" [S20, modern flavour]. |

**Landmarks: interior props [S2; sprites read by me]:**
- `insideGS/house1/basic/0` @32,7: a cutaway orange mushroom house with a stone-arched doorway (615x533).
- `basic/1` @14,-85 and `basic/4` @-21,146: rooms with timber beams and plaster walls. `basic/2, 3` are floor strips.
- `prop/grassySoil/fur/0` @-41,207: a wooden bookshelf or cupboard.
- `fur/1` @-66,15: a bed with pillows.
- `fur/2` @80,27: a small treasure chest.
- `prop/grassySoil/win/0` @37,-37: a window with orange curtains.
- `prop/grassySoil/lamp/0` ×2: hanging lamps.
- `prop/grassySoil/door/0` @-220,202: a round-topped wooden door, at the exit.
- `connect/ladder/1/0` @77,142: indoor ladder between the floors.

**What makes it recognizable.** A two-storey dollhouse-like mushroom interior with Sen inside. The name "Townstreet" is misleading; every source calls it "the house".

[proposal] Model 20001 as a cutaway (open-front) mushroom house sitting on a short grassy street strip, keeping the outdoor sky behind it. That matches the WZ composition.

---

### 30000: East Entrance to Mushroom Town (slug `EastEntranceMushroomTown_30000`)

**Data [S1, S2].**
- town; BGM FloralLife.
- Extents x[-309,1569], y[-925,420]: about 1878 x 1345 px, **a tall map**.
- Tileset `grassySoil` (286 tiles including 8 slope tiles).
- Backgrounds `grassySoil` 0, 1, 2, 3, 5, 6.
- Portals: `sp`@-77,122; `in00` (arrival)@-218,217; `out00`@**1433,-924** (top right) to 40000:`in00`.
- Climbing aids:
  - ladders at x=-136 (y -23..213) and x=107 (y -623..-447)
  - ropes at x=1359 (-263..-27) and x=1434 (-23..213)

**Terrain (render, minimap) [S23].** About four main tiers climbed from bottom-left to top-right:
- A wide ground band with a raised two-step central mesa carrying the house.
- Diagonal runs of small floating step-stones on the left.
- A long middle tier with a slope.
- A bowl-shaped floating island.
- A top tier, sloped up at the right, holding the exit.

**NPCs:**

| ID | Name | Position | Role and evidence |
|---|---|---|---|
| 2002 | Peter | 1314,-925 (beside the exit) | Gatekeeper and instructor. Dialogue: "This is the exit to the Mushroom Town." / "If you want to move on to the next stage, talk to me." / "Be careful...once you leave this place, you'll see monsters roaming around." / "We instructors are all related. Roger, my older brother, and Robin, my younger brother, all work together here." [S3]. S11 (2005): "In the 4th screen talk to Peter, he'll give you some experience." [reading] Whether Peter also warps the player is not established. A walkable exit portal sits next to him. |
| 2004 | Todd | **v22 only**, -21,215 (at the entrance) | Hunting tutor, added after v8. Quest "Todd's How-To Hunt": kill 1 weakened Jr. Sentinel, bring the Shellpiece, 10 EXP [S10, S16]. The two sources disagree on who gives and who completes it: S16 says Todd gives it and Peter completes it; S10 says the reverse. Todd near the entrance and Peter at the exit in the v22 data favours S16. |

**Monsters:**
- v8: none.
- v22: 3× **Tutorial Jr. Sentinel** (9300018: level 1, 8 HP, `noAttack`) [S1 v22, S4].
- StrategyWiki: "Jr. Sentinels, weakened for easy defeat, spawn for new player to train on at the end of town" [S14]; "The Jr. Sentinels are weakened and can't attack" [S16].

**Landmarks [S2]:**
- **Yellow mushroom house with a dark brim.** `houseGS/house7` (cap @694,-98; stem @714,14; brim `deco/0` @700,-41); doors `door/17, 19` @758-764; **round yellow dormer window** `door/grassySoil/window/16` @755,-154; lantern @830,21.
- Grain sacks `artificiality/23, 24` @594-635,67.
- **Small stone-ringed water feature with a rainbow arc and a mushroom** `artificiality/9` @1229,169 [reading].
- **Log bench** `artificiality/6` @306,-476, with tiny mushrooms `/7`.
- **Tall pale stalk-mushroom clusters** `nature/11 + 25` @444,-52/-108 and @1384,-1074/-1130. The pale "trees" on the minimap are these mushrooms, not trees.
- **Wooden signposts** `guide/midForest/wood/0, 1, 4, 5` in three places: at the start (77-106,140), bottom right (1463-1484,140) and by the exit (998-1032,-904..-939).
- Clover, toadstools, dark grass tufts and bushes.

**What makes it recognizable.** The first real vertical climb. The town gives way to signposts and the exit at the top, with Peter waiting there.

---

### 40000: Snail Hunting Ground I (slug `SnailHuntingGround1_40000`)

**Data [S1, S2].**
- **Field** (`town=0`); BGM **RestNPeace**; returnMap 60000; mobRate 1.0.
- Extents x[-309,2919], y[-805,600]: about 3228 x 1405 px.
- Tileset `grassySoil` (489 tiles).
- Backgrounds **`midForest`** 0 (sky), 1 (misty mountains and lake, tiled), 2 (white-barked forest, tiled), 4, 3 (forest strips).
- Portals: 5 `sp`; `in00` (arrival)@-172,278; `east00`@2692,392 to 40001:`west00`.
- 13 ladders and ropes (5 ladders, 8 ropes). A `seat` node is present in the WZ data.

**Terrain (render) [S23].** Roughly three to four tiers:
- A long ground band with a small stepped hill in the middle.
- Two long floating tiers with gentle slopes above it.
- Many small floating stepping-stones and a few mid-size floating slabs at the right.

**NPCs:**

| ID | Name | Position | Role and evidence |
|---|---|---|---|
| 2003 | Robin | 69,275 (near the arrival point) | Combat tutor, youngest of the instructor brothers. Dialogue: "Be careful! You'll see monsters around here." / "Press the left Ctrl key to attack the monster." / "Press Z and you'll be able to pick up the item the monster drops." / "The town you just saw is called Mushroom Town. You'll also find places called Southperry and Amherst on this island." / "If you want to head over to a bigger, wider area, try heading up northeast." [S3] |
| 2005 | Sam | **v22 only**, 1602,215 ("near the middle of the bottom level" [S16]) | Quest "Sam's Suggestion": kill 10 Snails, 30 EXP, then points you to Mai [S16]. Dialogue: "You can be even stronger, if you get a lesson from Mai" [S3 v22]. |

**Monsters:**

| ID | Name | v8 spawn points | Stats |
|---|---|---|---|
| 100100 | Snail | 33 | Lv1, 8 HP, 3 EXP |
| 100101 | Blue Snail | 16 | Lv2, 15 HP, 4 EXP |

- Stats are from v22 data [S4]. S11 (2005) lists the same HP/EXP: "Green Snails 8 / 3", "Blue Snails 15 / 4".
- Hidden Street 2005 also lists "Snail, Blue Snail" [S8].
- The v22 data has **Snails only** here (33) [S1 v22].
- Sprites [reading]: a small snail with a green spiral shell; a blue-shelled snail.

**Landmarks [S2]:**
- Wooden signposts at the arrival point: `guide/midForest/wood/0, 2, 3` @-144..-99, 195..227.
- **White-barked tufted trees** `midForest/nature/1-4, 6` (green, teal, orange and autumn canopies); daffodils `nature/10` ×5; big leafy plant `nature/8` @-169,-371; dirt clumps `nature/11`.
- Red-berry shrubs `grassySoil/nature/0` @2335-2442,13.
- Dark grass tufts and bushes.
- `midForest/artificiality/9` @2124,427: a small dark piece, the edge of a pit [reading].

**Atmosphere.**
- The sky and pastoral hills of Mushroom Town give way to a light, autumn-tinted woodland.
- Behind it: pale misty mountains over a mirror lake, and rows of birch-like trees with olive, orange and teal crowns over golden grass.
- The relaxed field theme Rest 'N Peace plays.

**What makes it recognizable.** The first monsters: slow green and blue snails everywhere. S11: "Beginners that plan to become Magicians should hunt in the Snail Hunting Ground I or II ... full of Green and Blue Snails."

---

### 40001: Snail Hunting Ground II (slug `SnailHuntingGround2_40001`)

**Data [S1, S2].**
- Field; RestNPeace; returnMap 60000.
- Extents x[-309,2919], y[-1165,600]: about 3228 x 1765 px.
- Tileset `grassySoil` (581 tiles); background `midForest` as in 40000.
- Portals: 5 `sp`; `west00`@-219,393 to 40000:`east00`; `east00`@2792,395 to 40002:`west00`.
- 8 ropes; `seat` node present.

**Terrain (render) [S23].**
- A ground band with one large ramp-hill (a slope up to a flat-topped mound) in the middle.
- Above it, a **pyramid or arch of small stepping-stone platforms** climbing to an apex between two long mid-level tiers. This is the most distinctive silhouette of the three grounds.
- A long upper-right tier and several mid tiers.

**NPCs:** none (v8 and v22).

**Monsters:**
- v8: Snail ×43, Blue Snail ×24 [S2]. v22 API: Snail 44, Blue Snail 11 [S1 v22].
- Hidden Street 2005: "Snail, Blue Snail" [S8].

**Landmarks [S2]:**
- **Birch-log picket fence** `midForest/artificiality/1` ×3 @-126,352; 895,359; 1056,357.
- **A rickety plank bridge over a dark grassy-edged pit** `midForest/artificiality/7, 8, 9` @511-553, 375-422 [reading]. It shows as a dark rectangle on the minimap.
- Signposts at the arrival point `guide/midForest/wood/0, 3, 4`.
- Many white-barked trees (`midForest/nature/0-4, 6, 9-11`).

**Atmosphere.** The same autumn-woodland look and Rest 'N Peace theme as 40000.

**What makes it recognizable.** The inverted-V "pyramid" of floating stepping stones in the middle of the map, the birch-log fences, and the little plank bridge over a pit.

---

### 40002: Snail Hunting Ground III (slug `SnailHuntingGround3_40002`)

**Data [S1, S2].**
- Field; RestNPeace; returnMap 60000.
- Extents x[-309,2919], y[-1285,600]: about 3228 x 1885 px, the tallest of the three.
- Tileset `grassySoil` (588 tiles); background `midForest`.
- Portals: 5 `sp`; `west00`@-19,274 to 40001:`east00`; **`east00`@2822,-1164 (top right)** to 50000:`west00`.
- 6 ladders and 9 ropes.

**Terrain (render) [S23].**
- A ground band with a stepped hill.
- Four to five stacked tiers of floating platforms, linked by small stepping stones and ropes.
- The exit sits on the highest tier at the top right. You have to climb out.

**NPCs:** none.

**Monsters:**
- v8: Snail ×36, Blue Snail ×26, **Red Snail ×13** (Lv4, 45 HP, 8 EXP [S4]; red-shelled snail sprite).
- v22 API: Snail 25, Blue 15, Red 1.
- Hidden Street 2005: "Snail, Blue Snail, Red Snail" [S8].
- S11: "Red Snails 45 [HP] 8 [EXP] Beginner Magicians shouldn't waste time on these."

**Landmarks [S2]:**
- Plank-bridge-over-pit set `midForest/artificiality/7, 8, 9` @2089-2124, 377-427.
- **Signposts by the high exit** `guide/midForest/wood/0, 4, 5` @2022-2069, -1335..-1363, plus arrival signs at the bottom left.
- Lily-of-the-valley `nature/9`, big leafy plants `nature/8`, white-barked trees, sunflowers and butterflies.

**What makes it recognizable.** The tallest snail map, the first Red Snails, and the climb to a signposted top exit.

---

### 50000: A Split Road (slug `ASplitRoad_50000`)

**Data [S1, S2].**
- Field; RestNPeace; returnMap 60000; **mobRate 1.5**.
- Extents x[-624,3234], y[-175,570]: about 3858 x 745 px, **long and low**.
- Tileset `grassySoil` on two tile layers (256 + 263 tiles), which gives layered hill masses.
- Background `midForest`.
- Portals:
  - `sp`@-183,120
  - `west00`@-505,246 to 40002:`east00`
  - **`east00`@3041,7 (upper right) to 1000000:`west00` (The Field West of Amherst)**
  - **`east01`@3046,361 (lower right) to 60000:`west00` (Southperry)**
- 2 ladders, 6 ropes.

**Terrain (render) [S23].**
- A long low ground band with a dip at the left.
- A large, layered hill mass in the middle-right with slopes and a few floating ledges.
- On the right the road **forks**: an upper plateau toward Amherst and the lower ground toward Southperry.

**NPCs:**

| ID | Name | Position | Role and evidence |
|---|---|---|---|
| 2103 | Maria | 159,65 | Letter quest. Dialogue: "Ahh...I need to get this letter sent..." / "Why isn't anyone passing by!!" / "Whoa, time's going fast...it may be too late..." [S3]. Quest: carry Maria's letter to Lucas in Amherst and bring his reply back. Reward: a random level-5 hat (skullcap or headband) and 10 EXP [S10, S16]. S11: "Soon you will see Maria ... she'll give you a hat (a bandana or skullcap)." |
| 12100 | Mai | **v22 only**, 1891,-175 ("on a platform above the middle of the area" [S16]) | Training quest: kill 10 Snails, 10 Blue Snails and 10 Shrooms, then 10 Orange Mushrooms. Rewards 70 EXP, then 150 EXP + 300 mesos [S16]. Sprite [reading]: girl with brown pigtails in a red qipao, holding a curved sword. Dialogue: "Is there anyone that can satisfy my desire to fight...?" [S3 v22]. |

**Monsters:**

| ID | Name | v8 spawn points | Stats [S4] |
|---|---|---|---|
| 100101 | Blue Snail | 25 | |
| 130101 | Red Snail | 13 | |
| 120100 | Shroom | 18 | Lv2, 20 HP, 5 EXP |

- The Shroom sprite is a small orange-capped walking mushroom [reading].
- Hidden Street 2005 gives the same set [S8]. The v22 counts are identical.

**Landmarks [S2; sprites read by me]:**
- **Red mailbox** with heart and envelope icons on a post, `acc1/grassySoil/artificiality/16` @105,36. It stands about 55 px from Maria, who is waiting to send her letter.
- **Two direction signboards at the fork**, `signboard/maypleIsland/*` (the WZ name is spelled "mayple"):
  - `board/1` @2932,-82 on the upper path reads "**Amherst →**".
  - `board/0` @2819,280 on the lower path reads "**South perry →**".
- Wooden guide signs `guide/midForest/wood/0, 2, 3, 4` @321-370, 282-323.
- White-barked autumn trees (`midForest/nature/0-7`), big bushes, clover, flowers, a toadstool cluster.

**What makes it recognizable.** The literal fork in the road, with wooden arrow signs to Amherst (up) and Southperry (down), and Maria by her mailbox. [proposal] This is the island's main navigation decision point, so the two signs are worth reproducing faithfully.

---

### 60000: Southperry (slug `Southperry_60000`)

**Data [S1, S2].**
- **town**; BGM **GoPicnic**; mapMark **SouthPerry**; returnMap 60000.
- Extents x[-662,4082], y[-1145,720]: about 4744 x 1865 px.
- Tileset **`whiteMarble`** (531 tiles). Two other layers have tileset `woodBridge` but no tiles. Layer 0 holds the ship hull and masts; layer 2 holds the ladders and ropes.
- **Backgrounds: sky tile and clouds only.** `grassySoil/0` (sky), `grassySoil/1` (cumulus), `portTown/3-6` (free clouds, drifting).
- **There is no sea or water background or object in the v8 data.** This is consistent with the official "island floating somewhere in the sky" [S5].
- Portals:
  - `sp`@-37,177
  - `west00`@-547,286 to 50000:`east01` (from Split Road)
  - **`in00`@699,527 to 60001:`out00` (Armor Store door)**
  - hidden `h001` (type 1)@-1,43, purpose unknown. v22 replaces it with `gm00`@-65,43.
  - 6 `tp` portals (type 6) at x 870..1327, y≈524. [memory] Type-6 "tp" points are Mystic Door landing spots.
- Climbing: ladders at x=405 and x=1649; ropes at x=364 and 442 (long drops to the lower street), and x=2955 (y -1141..-339). [reading] That last rope runs up the ship's mast area.

**Terrain (render, minimap) [S23].**
- West end: a high stone plateau (the arrival from Split Road).
- It drops into a long lower street with the houses and the Armor Store.
- A raised floating ledge with a market canopy sits upper-left of centre, with small stone slabs as steps.
- A grand **stepped staircase of white flagstone** climbs to the right, up to the dock plateau where the ship is moored.

**NPCs (v8 positions [S1]; dialogue [S3]):**

| ID | Name | Position | Role and evidence |
|---|---|---|---|
| 22000 | **Shanks** | 3223,-13 (on the dock by the ship) | Ship captain to Victoria Island (150 mesos, one-way, see section 1). "I am the captain, dang it!! Don't be looking down on me!" / "I'll take you anywhere you want". Sprite [reading]: young blond captain in a big blue feathered tricorn and a gold-trimmed blue coat. |
| 20002 | **Biggs** | 950,-193 (upper area) | Sailor who wants to captain the ship. "One of these days, I'll be the one operating that huge ship, and take off to a far bigger land..." / "Hmm...looks like I'm still the best looking man in this town." Quest "Bigg's Collection of Items": 30 Blue Snail Shells + 10 Orange Mushroom Caps, reward Razor or Fruit Knife + 30 EXP [S10, S16]. StrategyWiki: "found in Southperry, at the top of the port" [S16]. Sprite: grey-haired, scowling sailor in a sailor cap. |
| 20001 | Bari | 1013,527 (lower street, by the Armor Store) | Sailor: "Working hard there~" / "Salute~". Visible in the era screenshot. |
| 20100 | Yoona | -18,287 | "Whoa, what are you looking at?!?!" (bunny-girl sprite shared with Nina) |
| 9000000 | Paul | 4,47 (west end, high) | "Where's my brother...?" / "I need to get to where the event takes place..." [memory] Paul is one of the GM-event guide NPCs. Sprite: boy in a yellow cap with a skateboard. |
| 9010001 | Tia | -450,287 (west entrance) | "Hey all!" / "Hope you all have a wonderful day today". Replaced by Ria (9010003) in v22 [S1 v22]. Sprite: girl in pink with balloons. |
| 9010000 | Maple Administrator | -181,287 (west entrance) | "To play the game the right way, we strongly suggest you don't use hacking tools to ruin it for others." Sprite: man in a white "W" cap with a briefcase. |

**Landmarks [S2; sprites read by me]:**
- **The ship `vehicle/ship/victoria/0-6`**, spanning about x 2581..3326, masts up to about y -731.
  - The WZ set is literally named "victoria". The official 2005 text calls it the ship <Victoria> [S5].
  - Parts: a dark hull silhouette (back layer); three masts with cream canvas sails; a wooden hull with a **golden winged figurehead** and green-and-gold deck rails; **twin wooden-barrel engines with steel rings and a propeller** [reading: a sail/airship hybrid, as in the sky-ship design].
  - In the local render only the masts and part of the deck drew [S23]. The minimap shows the whole ship.
- **Boarding gangway** (wooden scaffold ramp) `acc1/portTown/artificiality/22` @3236,-77, right at Shanks.
- Cargo: "PASS N.S POST" stamped crate `/9` @3448,-66; burlap bales `/0` ×4; papers and ticket `/10, 11`; blue cloth `/13`.
- **Market canopy** (canvas gazebo on posts) `/18` @1127,-314 on the upper ledge.
- **Rolled carpets or fabric bolts** (red/green, purple/grey) `/15, 16` @1322-1386, 425-429; iron-bound chest `/14` @1756,370.
- **Blue ceramic pots** `/3, 4` @597-685, -170; rope lines on forked poles `/5, 6` @24-69, 172-192.
- **Santorini-style buildings** `housePT/*`. Fandom and maplestorywiki.net: "Southperry is based on Santorini, like Lith Harbor" [S19, S20]. StrategyWiki 2014: "the buildings and ground appear similar to Lith's" [S17].
  - `house0` @-88,98: white building with a **blue dome** and a tall arched wall, with stairs and starfish decorations (`deco/0`).
  - `house1` @738,358: **the Armor Store exterior**. White walls, wavy **blue-tiled roof**, chimney topped with barrels, arched double door, barrels.
  - `house2` @1201,340: square white tower with a blue dome and a drainpipe.
  - `house3/basic/1` @2029,-13: a **lighthouse**. White tower with a blue dome cap, wooden balcony and a blue-roofed annex. It sits atop `house3/basic/0` @2025,343, a rocky outcrop with carved stairs.
- **Armor Store sign**: a wooden board hanging from a curled post, with a **green shield-and-cross icon**. `signboard/grassySoil/board/4` @502,443 and `icon/4` @517,438.
- **Two face-in-the-hole photo boards** [reading] near the dock end, at @3691,-113 and @3826,-68:
  - `acc1/midForest/artificiality/10`: a blonde figure in a billowing white dress, face cut out.
  - `/11`: an orange ring on clouds with a chick.
  - In the render the first looks like a statue. The sprite has an empty face circle.
- Trees and bushes (`darkWood/nature/*`, `grassySoil/nature/13`).

**Era screenshot.** `ref_web/60000_1.jpg`, from Hidden Street's Southperry page, archived 2006 [S9]. The file's EXIF date is 2004-12-13. That is file metadata, not proof of when or where it was captured. It shows:
- The Armor Store: white plaster walls, a wavy blue-tiled roof, a chimney topped with wooden barrels, an arched pinkish wooden door with a soft glowing portal in front.
- A barrel and bushes against the wall.
- The hanging wooden sign with the green shield-cross emblem on a curled post.
- Bari, a small sailor in white, saying "Working hard there~".
- Cream flagstone ground under a blue sky with white clouds.
- Its minimap shows the ship at the right.

**Atmosphere.**
- A sunny Mediterranean (Santorini) harbour, but in the sky: whitewashed walls, blue domes, flagstones, market goods, clouds drifting past.
- Lighter, busier and more "civilised" than the Mushroom Town meadows.
- Go Picnic's short, cheerful loop plays.

**What makes it recognizable.**
- The big ship on the high dock and Shanks's one-way ticket off the island.
- The lighthouse and blue domes.
- Hidden Street 2006: "This is where beginners can finally can depart from Maple Island to Victoria Island by boarding on the ship. ... Only the armour store is available here." [S9]

---

### 60001: Southperry Armor Store (slug `SouthperryArmorStore_60001`)

**Data [S1, S2].**
- town; BGM **FloralLife** (not GoPicnic); mapMark SouthPerry; returnMap 60000.
- **Single screen.** VR bounds x -400..400, y -300..300 (800 x 600). Floor at y=183 across the full width. Small shelf and counter footholds. One rope (API: x=75, y -261..-84).
- No `miniMap` node. A `seat` node is present.
- Portals: `sp`@-114,115; `out00`@-48,181 to 60000:`in00`.

**NPC:**

| ID | Name | Position | Role and evidence |
|---|---|---|---|
| 21000 | Pan | -270,140 | Armor seller (Fandom: function "Armor Seller" [S19]). "Hello everyone! I've got some goods here for sale!!" / "Anyone that steals will not go unpunished!!" [S3]. Sprite: stocky man in a blue suit and sunglasses. |

**Stock (StrategyWiki, Sep 2006 [S15]).** All items cost 50 mesos:
- White Undershirt (M), Undershirt (M), Grey T-Shirt (M)
- White Tank Top (F), Yellow Cotton Shirt (F), Green Cotton Shirt (F), Red-Striped Top (F)
- Blue Jean Shorts (M), Brown Cotton Shorts (M)
- Red Mini Skirt (F), Indigo Mini Skirt (F)
- Red Rubber Boots, Leather Sandals

**Landmarks [S2].**
- Shop interior `insideGS/house0/basic/0-2`: plaster walls, heavy timber beams and brackets, a plank floor, and a blue-banded wooden-plank roof. The local render shows the roof beams.
- Shop props `shop/shop/weapon/*` (12 objects), including cogwheel brackets and dark wall niches.

**Atmosphere.** A warm, single-screen interior in timber and plaster. It plays the gentle FloralLife town theme instead of Southperry's harbour tune.

**What makes it recognizable.** Pan in his blue suit and sunglasses behind the counter, a rack of 50-meso beginner clothes, and the heavy beamed roof.

---

## 4. "What players remember" (sourced first, memory marked)

- **Order of the first screens** (S11, 2005): Heena → Sera's mirror → Roger (lose HP, eat the apple, get 3 Red Potions) → "another simple quest" → Peter gives EXP. Quoted: "the portal (the place with the glowing light from the ground)."
- **Leaving is final.** "When you leave you won't be able to come back." [S11]. "Maple Island is a mysterious island of no-return" [S5, S9].
- **Training advice of the day.** Snail Hunting Ground I/II for future magicians; Biggs's quest is "hard" for weak beginners; Orange Mushrooms are "to the right of Amherst" [S11, S16].
- **Perma-beginners.** The 2005 "Super Noob" guide: "You don't have to stay on Maple Island. I guess that was supposedly the 'true' path of the Super Noob in the past" [S12]. This shows that staying on Maple Island as a beginner was already a known subculture in 2005. [memory] Later called "islanders".
- **Mushroom Town as a quiet tutorial town.** "Before the Training Camp was built, Mushroom Town was a quiet little town where NPCs teach new players the basic of MapleStory" [S14]. "Amherst is a small, peaceful town that holds true to Maple Island's scenery - grass and mushroom-shaped houses" [S18].
- **Modern official nostalgia** (World Archive text, post-2020 flavour, not era content) [S20]: "Sen, who used to keep careful watch over his house, still loves to eat Nina's candy ... Todd and Peter, who used to teach combat lessons, have moved to Victoria Island with Robin and the others."

---

## 5. Era notes: avoid anachronisms

**v8 vs v22** (both inside our target era; measured from S1 and S2, v22 data in `raw/gms_v22_wz/`):
- **Added by v22:**
  - Todd (2004) and 3 Tutorial Jr. Sentinels (9300018) at 30000.
  - Sam (2005) at 40000.
  - Mai (12100) at 50000.
  - Hidden Street lists the quests "Todd's How-to-Hunt", "Sam's Suggestion" and "Mai's Training" by **Feb 2006** [S10].
- 40000 lost its Blue Snail spawns (Snails only) in v22.
- **Map 0 was re-laid out.** Everything sits about 300 px lower in v22 (house y 104 → 408; Heena y 65 → 305; spawns y≈102 → 437-452), and the exit moved from x 1052 to 1116.
- 20000 was extended east: exit x 795 → 1109, plus extra bushes and props.
- 30000 had its climbing aids reshuffled. The rope at x=1359 moved to x=1342, and the ladder at x=107 was replaced by a rope at x=183.
- v22 adds `guide/maple/key/0`, a small "↑" key icon hint at map 0's ladder and 20000's house door. It is **not** in v8.
- Southperry: Tia (9010001) became Ria (9010003); hidden portal `h001` became `gm00`.
- [proposal] Pick one baseline (v8 is the cleanest "pure" layout) and treat the v22 tutorial NPCs and props as an optional "late 2005/2006" variant.

**Mushroom Town Training Camp (GMS v40+ per the task brief).**
- It replaced map 0 and the tutorial in GMS, JMS and EMS only.
- Description from StrategyWiki (May 2007) [S14]:
  - The player starts in "an area that resembles the backstage of a movie set".
  - Players wear "a costume that resembles a green apple that cannot be unequipped".
  - Props and backdrops depict Victoria Island and Ossyria towns; you ride "a conveyor belt".
  - NPCs wear red maple-leaf suits.
  - "Drum Bunnies and Leatty" replace the old Jr. Sentinels.
- Fandom: the original Mushroom Town "was re-added shortly after the release of Explorer Pirates"; the Training Camp's theme was "First Step Master" [S19, S20].
- **None of this belongs in classic Maple Road.**

**Later ID changes (do not use for topology).**
- v62 added 50001 "The Field West of Southperry" (task brief).
- From v83, map IDs were reused for other maps.

**Big Bang and the later Maple Island revamp.**
- Modern Maple Island renames and re-IDs everything. The modern Fandom map templates carry these IDs [S19]:

  | Modern name | Modern ID | Note |
  |---|---|---|
  | Maple Tree Hill | 10000 | NPCs Bush, Sugar |
  | Snail Park | 20000 | |
  | Split Road of Destiny | 1020000 | job instructors' preview |
  | Southperry | **2000000** | |
  | Port | 2000100 | NPC Vasily |

- "Destroyed" variants with the WoundedLeaf BGM exist (110000, 120000, 1120000, 2100000) [S19].
- Modern BGM for these maps is "The Beginnig of The Adventure" [S19].
- Explorers now start in "a dark place" and meet Mai and Sugar [S17, S20]. The ship is "The Sangri-La" to Lith Harbor. Return is via the Maple Return skill or Olaf in Lith Harbor [S20].
- **Rain, Olaf, Sugar, Vasily, Bush, Sangri-La, Maple Return and the Adventurer Training Center are anachronisms for v8-v22 Maple Road.**
  - Rain existed in the era but in **Amherst**: "Rain can be found in Amherst, near the entrance portal" [S16].
  - Olaf is a later Lith Harbor NPC [S20].
- **meowdb "MapleStory Classic"** [S22] is a modern re-creation with **different IDs**: West Entrance = 000000001, Mushroom Town = 000000010 / 000000020, Townstreet = 000000021, Snail Hunting Grounds = 000000040-42. It also uses "Mushroom Town - West Entrance" naming. Use it for flavour only.
- The "World Archive" text quoted in section 4 is a modern retrospective [S20].

---

## 6. Open questions for later phases

1. The **WZ portal data** shows Mushroom Town as **one-way**:
   - 0 → 10000 → 20000 → 30000 → 40000 each have only an `out00` exit.
   - The arrival points are type-1 `in00` entries with no target (`tm` 999999999), and there is no return portal.
   - From 40000 onward, portals are two-way (`west00`/`east00` pairs).
   - The topology team should confirm this before treating it as design intent.
2. Southperry's hidden `h001` (type 1) at -1,43 has an unknown purpose. It sits next to Paul.
3. Whether Peter (or Heena: "she will take you to the next screen/map" [S11]) actively warps the player, in addition to the walkable portal, is unverified.
4. No archived era screenshots were found for 10000 through 50000. For those maps, the minimaps and WZ object lists stand in. Only 0 and 60000 have true era screenshots.
5. The `seat` nodes in 40000-40002 and 60001 were not decoded (chair or seat spots).
6. Who gives and who completes "Todd's How-To Hunt" is disputed. Hidden Street (2006) says Peter gives it and Todd completes it; StrategyWiki (2007) says Todd gives it and Peter completes it. NPC placement in v22 favours StrategyWiki.
