# Maple Island topology: portal sources and findings (classic GMS v8)

Companion to `docs/research/portals_xml.json`. Every portal record in that file comes from the
**raw GMS v8 WZ data**. It was not reconstructed from a wiki or from an emulator dump.

Labels used below:
- **[data]**: read directly from a cited file or URL.
- **[inference]**: my reasoning from that data.
- **[memory]**: something I recall, not checked against a source here.
- **[proposal]**: a design suggestion.

All coordinates are MapleStory pixels, with y increasing downward.

---

## 1. Bottom line

- **All 25 maps are sourced from the GMS v8 WZ data. None are missing.** The per-map
  completeness check against the lossy `/api/GMS/8/map/<id>` JSON passes for **25/25** (section 6).
- **10000 is WEST of 20000.** [data] `10000 out00 (pt2 @ x=706, 88 % of the foothold width) -> 20000:in00`,
  and 20000's `in00` sits at x=-207, the far west of 20000.
- **The Maple Road chain, west to east** [data, portals]:
  `0 -> 10000 -> 20000 -> 30000 -> 40000 <-> 40001 <-> 40002 <-> 50000`. At 50000 the road forks:
  `east00` (upper, y=7) `<-> 1000000 <-> 1010000 <-> 1020000`, and `east01` (lower, y=361) `<-> 60000`.
- **The first four links are ONE-WAY.** [data] The links 0->10000, 10000->20000, 20000->30000 and
  30000->40000 have no return portal. The target `in00` in each of those maps is `pt1` with
  `tm=999999999`, so it does not lead anywhere. Two-way travel starts at 40000<->40001. Details in section 5.
- **The task brief's assumption about v62 is wrong, in two ways.** [data]
  - The restructure of Maple Island happened in **v56**, not v62. v55 still has the v8 topology, and
    v56 through v62 share the new one.
  - It is far bigger than "50000 gains a link to 50001". In v56+ the maps 1000001/1000002 lead to
    50001, the maps 1000005/1000006 lead to 1020000, 1000000 loses four side portals, and 60000's
    west exit leads to 50001.

  Separately, **map 0 changes into the Training Camp at v38**, not at v40. See section 7.
- **Before v56, 50000's `east01` led to `60000:west00`** (Southperry) [data]. This is true in v8, v22,
  v28, v32, v34, v37, v38 through v55.

---

## 2. Sources

### 2.1 Primary source: raw WZ node tree on maplestory.io (used for every record)
maplestory.io serves the raw WZ property tree, unauthenticated, at `https://maplestory.io/api/wz/<region>/<version>/<path>`.
The version list is `GET https://maplestory.io/api/wz`.

- GMS v8 is a single-`Data.wz` client. The canonical node path is
  `https://maplestory.io/api/wz/GMS/8/Data/Map/Map/Map0/<9-digit id>.img/portal/<n>/{pn,pt,tm,tn,x,y}`.
  The shorter alias `/api/wz/GMS/8/Map/Map/Map0/...` returns the same values. I checked
  `000010000.img/portal/2/tm` = 20000 through both paths.
  **Note:** the bulk fetch (`fetch_wz_portals.mjs`) went through the alias path
  `/api/wz/GMS/<v>/Map/Map/...` for every version. Only that one property was cross-checked against
  the canonical `Data/` path. The `source_url` values in `portals_xml.json` cite the canonical
  `Data/` path.
- All 25 IDs are below 100000000, so they all live in `Map0/`. For example, 1000000 is
  `Map0/001000000.img`.
- Each record carries the exact property values `pn` (name), `pt` (type), `x`, `y`, `tm` (target map)
  and `tn` (target portal name).
- I pulled the same 25 maps from **v8 (canonical), v22, v40, v55 and v62** for the version deltas. I
  also probed every other GMS version the endpoint offers between v8 and v62, looking only at maps
  0, 50000, 1000000 and 60000.
- Raw fetches and scripts are in `docs/research/raw/wz_portals/`:
  - `fetch_wz_portals.mjs <ver>` writes `gms_v<ver>.json`. These files hold the full portal lists and
    the `info` fields returnMap, town, mapMark and bgm.
  - `probe_versions.mjs` does the version bisection described above.
  - `build_portals_xml.js` regenerates `docs/research/portals_xml.json`.
  - `worldmap.mjs` writes `worldmap0_gms_v8.json` (section 4.2).

### 2.2 Corroboration: TitanMS per-map XML (independent v62-era dump)
- Repo: `koolkdev/TitanMS` ("Archive of TitanMS (C++ MapleStory private server)"). It has per-map
  XML at `TitanMS/Maps/<id>.xml`, for example
  `https://raw.githubusercontent.com/koolkdev/TitanMS/master/TitanMS/Maps/10000.xml`.
  Each `<Portal>` has `from`, `to`, `toid`, `type`, `x`, `y` and `script` elements.
- Result [data]:
  - For **24 of the 25 IDs** (every ID except 0), the TitanMS portal lists match the maplestory.io
    **v62** tree exactly: names, types, coordinates, targets and sp counts.
  - Map 0 matches too, except for one extra `tele_01` portal (pt2 at 390,463, leading to map 7) that is
    not in the GMS v62 tree. [inference] That portal is probably an emulator-side addition.
- This shows that the maplestory.io WZ tree reproduces real client data faithfully. TitanMS is
  v62-era, so I used it **only to corroborate**. It was never used as a topology source for v8. I
  did not copy any TitanMS files into the project.

### 2.3 Search for WZ XML dumps (task step 1)
- WebSearch for `"000010000.img.xml"` and `"001000000.img.xml"` with OdinMS/WZ terms found nothing
  relevant. GitHub code is not indexed by that engine.
- The GitHub repo-search API (unauthenticated) for `odinms v55`, `odinms v62`, `titanms` and
  `maplestory v62 server` returned:
  - `v3921358/OdinMS-v55-R988`, `s884812/odinms` (v62), `BiosSystem/OriginalMS` (v62),
    `hugogrochau/VoidMS` (v62) and `platymeta-debug/titanms`. I scanned their recursive git trees: **none
    contains `Map.wz` XML** (no `*.img.xml` and no 9-digit map files). These repos ship code and SQL only.
  - `koolkdev/TitanMS` has converted per-map XML. It is used above as corroboration only.
- I did not use any v83+ dump. HeavenMS-style data reuses the IDs, so it is explicitly excluded.
- Conclusion: an XML dump from v62 or earlier would have been a *derivative* of the WZ files. The
  maplestory.io tree is the WZ data itself, for the exact target version (v8), so it supersedes any
  emulator dump. **No wiki fallback was needed.**

### 2.4 Secondary local data
- `docs/research/raw/gms_v8/<id>.json` (maplestory.io `/api/GMS/8/map/<id>`) is lossy: unparsed
  portals come back as `null` and some targets are `999999999`. I used it only for the completeness
  check, the foothold extents, and the NPC positions.

---

## 3. Canonical v8 exits (summary)

pt values come from the data. What each pt *means* is covered in section 8.
"Arrival-only" means a portal with `tm=999999999` that is the target of another map's portal.

| Map | Name | Exits: `pn (pt @ x,y) -> tm:tn` | Other non-sp portals | sp |
|---|---|---|---|---|
| 0 | West Entrance to Mushroom Town | out00 (2 @ 1052,365) -> 10000:in00 **one-way** | none | 4 |
| 10000 | Mushroom Town | out00 (2 @ 706,216) -> 20000:in00 **one-way** | in00 (1 @ -195,278), arrival-only | 1 |
| 20000 | Mushroom Town | in01 (2 @ 557,94) -> 20001:out00; out00 (2 @ 795,96) -> 30000:in00 **one-way** | in00 (1 @ -207,218), arrival-only | 3 |
| 20001 | Mushroom Town Townstreet | out00 (2 @ -167,244) -> 20000:in01 | none | 1 |
| 30000 | East Entrance to Mushroom Town | out00 (2 @ 1433,-924) -> 40000:in00 **one-way** | in00 (1 @ -218,217), arrival-only | 1 |
| 40000 | Snail Hunting Ground I | east00 (2 @ 2692,392) -> 40001:west00 | in00 (1 @ -172,278), arrival-only | 5 |
| 40001 | Snail Hunting Ground II | west00 (2 @ -219,393) -> 40000:east00; east00 (2 @ 2792,395) -> 40002:west00 | none | 5 |
| 40002 | Snail Hunting Ground III | west00 (2 @ -19,274) -> 40001:east00; east00 (2 @ 2822,-1164) -> 50000:west00 | none | 5 |
| 50000 | A Split Road | west00 (2 @ -505,246) -> 40002:east00; east00 (2 @ 3041,7) -> 1000000:west00; east01 (2 @ 3046,361) -> 60000:west00 | none | 1 |
| 60000 | Southperry | west00 (2 @ -547,286) -> 50000:east01; in00 (2 @ 699,527) -> 60001:out00 | h001 (1 @ -1,43), no target; 6x tp (6 @ x=870,955,1058,1147,1239,1327; y=523-526) | 1 |
| 60001 | Southperry Armor Store | out00 (2 @ -48,181) -> 60000:in00 | none | 1 |
| 1000000 | The Field West of Amherst | west00 (2 @ -391,276) -> 50000:east00; east00 (2 @ 3338,456) -> 1010000:west00; in00 (2 @ -60,-385) -> 1000001:out00; in01 (2 @ 2987,-508) -> 1000002:out01; in02 (2 @ 1740,455) -> 1000003:out00; in03 (2 @ 1908,456) -> 1000004:out00; in04 (2 @ 389,-688) -> 1000005:out00; in05 (2 @ 757,-747) -> 1000006:out00 | none | 1 |
| 1000001 | In a Small Forest | out00 (2 @ 1153,-56) -> 1000000:in00 | none | 5 |
| 1000002 | Dangerous Forest | out01 (2 @ -310,-864) -> 1000000:in01 | none | 8 |
| 1000003 | Mushroom Garden | out00 (2 @ 2695,329) -> 1000000:in02 | none | 6 |
| 1000004 | Snail Garden | out00 (2 @ 980,329) -> 1000000:in03 | none | 6 |
| 1000005 | Hunting Ground Middle of the Forest I | out00 (2 @ 132,155) -> 1000000:in04 | none | 6 |
| 1000006 | Hunting Ground Middle of the Forest II | out00 (2 @ 133,-1346) -> 1000000:in05 | none | 7 |
| 1010000 | Amherst | west00 (2 @ -291,276) -> 1000000:east00; in00 (2 @ 227,-175) -> 1010001:out00; in02 (2 @ 1516,156) -> 1010003:out00; in01 (2 @ 2276,275) -> 1010002:out00; east00 (2 @ 3055,274) -> 1020000:west00 | 6x tp (6 @ x=169,250,335,421,492,621; y=273-276) | 1 |
| 1010001 | Amherst Weapon Store | out00 (2 @ -48,181) -> 1010000:in00 | none | 1 |
| 1010002 | Amherst Townstreet | out00 (2 @ -167,244) -> 1010000:in01; west00 (2 @ -492,275) -> 1010004:east00 | none | 1 |
| 1010003 | Amherst Department Store | out00 (2 @ 300,182) -> 1010000:in02 | none | 1 |
| 1010004 | Snail Field of Flowers | east00 (2 @ 559,-623) -> 1010002:west00 | none | 11 |
| 1020000 | The Field East of Amherst | west00 (2 @ -332,90) -> 1010000:east00; in00 (**pt1** @ 1792,-384) -> 1020001:out00 | none | 10 |
| 1020001 | Tomato Field | out00 (2 @ -275,214) -> 1020000:in00 | none | 9 |

Reciprocity check [data, computed by `build_portals_xml.js`]:
- Every portal with a real `tm` points at a portal name (`tn`) that exists in the target map.
- Every link is two-way (A.pn -> B.tn and B.tn -> A.pn), except the four one-way Maple Road links.

Other facts [data] from the v8 `info` nodes (in `raw/wz_portals/gms_v8.json`):
- `town=1` for 0, 10000, 20000, 20001, 30000, 60000, 60001, 1010000, 1010001, 1010002 and 1010003.
- `returnMap=60000` for 40000, 40001, 40002 and 50000.
- `returnMap=1010000` for every 10xxxxx map.
- 0 through 30000 return to themselves.

---

## 4. Geography (west to east) and the graph

### 4.1 From portals
These are relative portal positions inside each map's foothold x-extent, computed from
`raw/gms_v8/<id>.json` footholds. They confirm that `in`/`west` portals sit at the west edge and
`out`/`east` portals at the east edge along the main road:

- 0: fhX [-264, 1254]; out00 at 87 %.
- 10000: fhX [-309, 849]; in00 at 10 %, out00 at 88 %.
- 20000: fhX [-309, 939]; in00 at 8 %, in01 (the Townstreet door) at 69 %, out00 at 88 %.
- 30000: fhX [-309, 1569]; in00 at 5 %, out00 at 93 %, but at y=-924 (high up; the climb is at the east end).
- 40000, 40001 and 40002: fhX [-309, 2919] each. The west portals are at 3-9 % and the east portals
  at 93-97 %. 40002's east00 is at y=-1164 (high up).
- 50000: fhX [-624, 3234]; west00 at 3 %. **east00 and east01 are both at 95 % of x**, stacked
  vertically: east00 at y=7 (upper, toward Amherst) and east01 at y=361 (lower, toward Southperry).
- 60000: fhX [-662, 4082]; west00 at 2 %. **There is no east portal.** The east end holds NPC 22000
  "Shanks" at x=3223 (from `raw/gms_v8/60000.json` npcs; the name comes from `/api/GMS/8/npc/22000`).
- 1000000: fhX [-489, 3459]; west00 at 2 %, east00 at 97 %. The six side doors sit in between.
- 1010000: fhX [-398, 3278]; west00 at 3 %, east00 at 94 %.
- 1020000: fhX [-489, 2199]; west00 at 6 %. The Tomato Field portal in00 is at 85 %, with y=-384.

The resulting graph (W = west portal, E = east portal):

```
[0] --out00--> [10000] --out00--> [20000] --out00--> [30000] --out00--> [40000]      (one-way chain)
                                   |in01<->out00
                                [20001]
[40000]E <-> W[40001]E <-> W[40002]E <-> W[50000]
[50000] east00 (upper) <-> W[1000000]E <-> W[1010000]E <-> W[1020000]
[50000] east01 (lower) <-> W[60000]   (dead end; Shanks NPC at east end)
[60000] in00 <-> [60001]
[1000000] in00..in05 <-> 1000001, 1000002, 1000003, 1000004, 1000005, 1000006 (each has a single exit back)
[1010000] in00 <-> 1010001, in01 <-> 1010002, in02 <-> 1010003;  [1010002] west00 <-> east00 [1010004]
[1020000] in00 (pt1) <-> [1020001]
```

### 4.2 From the v8 world map
Source: `https://maplestory.io/api/wz/GMS/8/Data/Map/WorldMap/WorldMap0.img/MapList/<n>/{mapNo,type,x,y}`,
saved as `raw/wz_portals/worldmap0_gms_v8.json`.

[data] Each world-map spot is shown as (x, y), y down, followed by the map IDs grouped under it:

| Spot (x, y) | Maps |
|---|---|
| (104, 38) | 0 |
| (132, 48) | 10000, 20000, 20001 (type 0) |
| (141, 67) | 30000 |
| (160, 86) | 40000 |
| (180, 118) | 40001 |
| (213, 144) | 40002 |
| (249, 170) | 50000 |
| (273, 164) | 1000000-1000006 |
| (312, 165) | 1010000-1010004 (type 0) |
| (321, 189) | 1020000, 1020001 |
| (262, 187) | 60000, 60001 (type 0) |

[inference]:
- Maple Road runs diagonally from the north-west to the south-east of the island.
- At the split (249,170), Amherst's branch heads east (273 -> 312 -> 321).
- Southperry (262,187) lies south and slightly east of the split. This agrees with the portal data:
  east01 is the *lower* of the two east exits of 50000.
- The world map groups 10000, 20000 and 20001 under one spot, so it cannot order 10000 against
  20000. The portals settle that: 10000 is west.

---

## 5. One-way links and "arrival-only" portals

Data:
- In 10000, 20000, 30000 and 40000, `in00` is `pt1`, `tm=999999999`, `tn=""`. It is the arrival point of
  the previous map's `out00`.
- No portal in 10000, 20000, 30000 or 40000 targets the previous map.
- Map 0 has no `in00` at all. Players start at its `sp` points.

[inference]:
- In classic v8 the opening sequence 0 -> 10000 -> 20000 -> 30000 -> 40000 is walkable **forward
  only**.
- Once on 40000, the player can move freely between 40000 and Amherst/Southperry, but cannot walk
  back into the Mushroom Town maps.
- Caveat: portal data does not capture NPC-scripted warps. An NPC in those maps could still offer a
  return trip (NPCs: 0 has 2101/2100, 10000 has 2000, 20000 has 2102). I did not verify whether any of
  them warp the player. [memory] As far as I recall, they were tutorial/advice NPCs.

[proposal]: The 3D game should keep this one-way funnel, or decide explicitly to add return paths.
Either way, it should be recorded as a design decision rather than an accident of conversion.

---

## 6. Completeness check (task step 4)

Check: `count(API-parsed non-sp) + count(API null)` must equal the WZ non-sp count, and the API sp count
must equal the WZ sp count.
- API data: `raw/gms_v8/<id>.json`.
- WZ data: `raw/wz_portals/gms_v8.json`.

**Result: ok for all 25 maps.** The per-map strings are in `portals_xml.json` under `api_completeness`.

| Map | API non-sp + null | WZ non-sp | sp (API / WZ) |
|---|---|---|---|
| 0 | 0 + 1 | 1 | 4 / 4 |
| 10000 | 1 + 1 | 2 | 1 / 1 |
| 20000 | 1 + 2 | 3 | 3 / 3 |
| 20001 | 0 + 1 | 1 | 1 / 1 |
| 30000 | 2 + 0 | 2 | 1 / 1 |
| 40000 | 1 + 1 | 2 | 5 / 5 |
| 40001 | 0 + 2 | 2 | 5 / 5 |
| 40002 | 0 + 2 | 2 | 5 / 5 |
| 50000 | 0 + 3 | 3 | 1 / 1 |
| 60000 | 7 + 2 | 9 | 1 / 1 |
| 60001 | 0 + 1 | 1 | 1 / 1 |
| 1000000 | 0 + 8 | 8 | 1 / 1 |
| 1000001-1000005 | 0 + 1 each | 1 each | 5/5, 8/8, 6/6, 6/6, 6/6 |
| 1000006 | 1 + 0 | 1 | 7 / 7 |
| 1010000 | 6 + 5 | 11 | 1 / 1 |
| 1010001, 1010003 | 0 + 1 | 1 | 1 / 1 |
| 1010002 | 0 + 2 | 2 | 1 / 1 |
| 1010004 | 0 + 1 | 1 | 11 / 11 |
| 1020000 | 1 + 1 | 2 | 10 / 10 |
| 1020001 | 1 + 0 | 1 | 9 / 9 |

The four "known-good" API connections in the brief all appear unchanged in the WZ data:
- 30000 out00 -> 40000:in00
- 1000006 out00 -> 1000000:in05
- 1020000 west00 -> 1010000:east00
- 1020001 out00 -> 1020000:in00

---

## 7. Version deltas (v8 -> v22 -> v37 -> v38 -> v49 -> v56 -> v62)

### Bisection over available versions
Method: `probe_versions.mjs`, run over every GMS version the WZ endpoint serves between v8 and v62.
- Available: 8, 22, 28, 32, 34, 37-62.
- 23, 29, 30 and 35 return no Map tree. v12 is listed, but its parser folds `Map0` into a single node,
  `/api/wz/GMS/12/Data/Map/Map/Map0.img`, which is map 0 only: its portals are 4 sp and out00 pt2
  (1052,365) -> 10000:in00, identical to v8. The other 24 maps cannot be read at v12. (Corrected in the
  verification pass.)

| Change | Last old version | First new version |
|---|---|---|
| Map 0 becomes the Training Camp entrance: the portal set changes to `st00` + sp and `out00 -> 10000` is gone; the name changes too | v37 | **v38** |

Name evidence [data]: `https://maplestory.io/api/wz/GMS/37/String/Map.img/maple/0/mapName` = "West Entrance to Mushroom Town", and
`.../GMS/38/String/Map.img/maple/0/mapName` = "Entrance - Mushroom Town Training Camp". `/api/GMS/<v>/map/0/name` agrees for v37, v38, v39 and v40.
| Maple Island restructure (50001 inserted, side maps rerouted) | v55 | **v56** (v56-v62 have the same links for the probed maps 0/50000/1000000/60000; only pn->tm was probed per version) |

### v8 -> v22: links identical, minor geometry changes [data]
- 0 out00 x 1052 -> 1116.
- 20000 out00 (795,96) -> (1109,97).
- 40002 east00 (2822,-1164) -> (2753,-685).
- 60000 `h001` (pt1 @ -1,43) is renamed `gm00` (pt1 @ -65,43).
- Everything else is identical. **v8 values are canonical in `portals_xml.json`.**

### v22 -> v40/v55: links identical except map 0 [data]

Correction from the verification pass: the dates in this subsection are the versions the team
sampled (v40, v55), not the first changed ones. Bisection with the parsed API and WZ portal nodes
shows:
- **Extra climbables are first present at v37** (v34 is the last served version without them) in
  11 maps: 40000, 40001, 40002, 50000, 1000000, 1000001, 1000002, 1000003, 1000004, 1000005, 1020001.
- **The geometry and spawn rework is first present at v49** (v48 equals v40 for every map checked):
  40000, 40001, 50000, 60000, 1000000-1000006, 1010000, 1020000 and 1020001 change. v49 also adds
  Stump, Slime and Pig to 1000000 and Slime and Pig to 1020000. Foothold, climbable and mob counts at v49
  equal those at v55 for every map checked, so the v55 portal values below most likely hold from v49
  (verified for 1000000 west00/in00 and 1020000 in00).
- **1020000 is reworked again at v56**, with the restructure. Yoona appears in 1000000 at v56.

- 20000 out00 -> (1046,94).
- 40000 east00 -> (2812,397) in v40 and (1750,213) in v55.
- 40001 east00 -> (1964,392) in v55.
- 50000 east00 -> (3033,2).

v49 (first changed version; the values below were read at v55) reworks the geometry of several maps while keeping the same links:
- 1000000: west00 moves to (830,272), in00 to (843,-507), in04 to (1208,-445), in05 to (1565,-385).
- 1000002 out01 -> (-266,-867).
- 1020000 in00 becomes **pt2** at (1874,-266), and the sp count drops from 10 to 8. WZ: pt1 at (1792,-384)
  at v48 (`/api/wz/GMS/48/Map/Map/Map0/001020000.img/portal/10`), pt2 at v49 (`.../GMS/49/.../portal/9`).
- 1020001 sp count drops from 9 to 6.

[inference] v49+ geometry must not be used for the v8 layout. The 40000 east exit moves from x=2812 to
x=1750, which means the map was shortened.

### v56-v62: restructured topology [data, v62 tree, corroborated by TitanMS]

**Maple Road / Southperry:**
- 50000 east01 -> **50001**:west00.
- 60000 west00 -> **50001**:east00.
- 60000 also gains event portals: ev00-ev06 (pt3) and ev99 (pt1).

**Amherst field and its side maps:**
- 1000000 keeps only west00, east00, in00 (-> **1000003**) and in01 (-> **1000004**).
- 1000001 out00 -> **50001**:in00, and 1000002 now has out00 -> **50001**:in01.
- 1000003 -> 1000000:in00, and 1000004 -> 1000000:in01.
- 1000005 out00 -> **1020000**:in01, and 1000006 out00 -> **1020000**:in02.
- 1020000 gains in01 (-> 1000005) and in02 (-> 1000006).

**Tutorial portals:** pt9 `tutorialN` portals appear in 0, 10000, 40000 and 50000.

**Correction to the brief:** "v62 added 50001 and only 50000's link must be dropped" is wrong.
- The change came in v56.
- It rewired 1000001, 1000002, 1000005, 1000006 and 60000 as well.
- **No v56+ link should be used for the classic map set.**

### Map 0
In v38 and later, ID 0 is a different map. Its classic exits come only from v8-v37 data:
- `out00 -> 10000:in00` (one-way).
- No other exits.
- 10000's arrival point `in00` is the reverse end.

---

## 8. Portal type semantics

- [memory] Standard WZ portal types:
  - 0 = `sp` start/spawn point.
  - 1 = `pi`, invisible portal.
  - 2 = `pv`, visible portal.
  - 3 = `pc`, collision portal.
  - 6 = `tp`, town-portal (Mystic Door) landing point.
  - 9 = scripted collision portal.

  I have not verified this mapping against a source in this task.
- [data] In v8, `pt1` appears in two forms:
  - With no target: the `in00` arrival points, and `h001` in 60000.
  - With a target: 1020000 `in00 -> 1020001`.
- [inference] If the [memory] mapping holds, the Tomato Field entrance was a **hidden/invisible
  portal** in v8-v48 (pt1), and became visible (pt2) at v49 (verified at v48 and v49).
- [data] `tp` (pt6) points exist only in the towns 60000 and 1010000, six in each.

---

## 9. Unresolved gaps

1. **NPC-scripted travel is not in the portal data.** This covers Shanks in 60000 (off-island ship)
   and any NPC warps in the Mushroom Town maps. These need a separate NPC-script source.
2. **pt semantics** (section 8) are [memory]. The raw integers are recorded verbatim, so nothing
   downstream depends on the interpretation.
3. **v12 is checkable through the WZ tree endpoint for map 0 only.** `/api/wz/GMS/12/Data/Map/Map/Map0.img`
   is map 0 and its portals match v8 exactly; the other 24 maps cannot be read at v12. The 25-map
   claim for v12 rests on the `/api/GMS/12` map list. v8 and v22 bracket it and agree on topology.
4. **v8 build provenance.** maplestory.io labels the client "GMS 8". I cannot independently confirm
   which exact patch date of v0.08 it was taken from. [data, verification pass] Its `Etc/QuestInfo.img`
   also lists Ludibrium (Eos Tower, 1002100/1002101) and Zakum Dungeon (7000000-7000002) quests.
   [memory] Those areas are usually remembered as later GMS additions, so the v8 Etc data may include
   content that was not yet live, or the build may be later than assumed. Unresolved; it does not
   affect the Maple Island map data.
5. `h001` (v8) vs `gm00` (v22+) in 60000 is a targetless pt1 point. [inference] It is likely a GM/hidden
   arrival spot, not a player exit.
6. World-map `x`/`y` (section 4.2) are spot positions on the world-map UI image. They are only good
   for relative direction, not for real distances.
