"""Export the built island's topology / map manifest.

Runs with Blender's bundled Python (no bpy needed; scripts/build_island.py also runs it after every build):
"/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" scripts/export_manifest.py

Inputs (all read-only):
  * src/misostory/layout.py: placement, links, arrival-only anchors (layout.is_arrival_only);
  * docs/build_report.json: what was built (NPC and monster proxies, routes, traversal);
  * the canonical MeowDB MS Classic maps: game/data/canonical/maps/<meowdb id>.json, found through the id crosswalk
    game/data/misostory/map_id_crosswalk.json (GMS v8 id -> MeowDB id). They give `classic_npcs` (MeowDB's NPC
    list) and `classic_mobs` (species -> MeowDB spawn points, monsters[].count). Iteration One's v8 research
    (docs/research/entities.json) is no longer used: MeowDB is the gameplay authority.
Outputs: docs/manifest.json and docs/MAPLE_ISLAND_MANIFEST.md (map -> exits -> destination, arrival points).

`built_mobs` sums the representative proxies per species over every m.mobs area of the map (each area reports its
own count). `exits` lists portals only: an arrival-only anchor (layout.ONE_WAY, today 40000 in00) is not a portal in
MeowDB, so it is listed under `arrival_points` of its map, and the portal leading to it is an exit with
`one_way: true` and `to_arrival` naming it.
"""

import importlib.util
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("layout", os.path.join(ROOT, "src", "misostory", "layout.py"))
LY = importlib.util.module_from_spec(spec)
spec.loader.exec_module(LY)

origins = LY.resolve()
report = {}
built_trails = {}
rp = os.path.join(ROOT, "docs", "build_report.json")
if os.path.exists(rp):
    with open(rp, encoding="utf-8") as f:
        full = json.load(f)
    report = full.get("maps", {})
    built_trails = {t["trail"]: t for t in full.get("trails", [])}

# MeowDB canonical maps through the crosswalk (gms v8 id -> meowdb id)
DATA = os.path.join(ROOT, "game", "data")
crosswalk = {}
cw_path = os.path.join(DATA, "misostory", "map_id_crosswalk.json")
if os.path.exists(cw_path):
    with open(cw_path, encoding="utf-8") as f:
        crosswalk = {int(r["gms_v8_id"]): str(r["meowdb_id"]) for r in json.load(f)}
canon = {}
for v8, mid in crosswalk.items():
    p = os.path.join(DATA, "canonical", "maps", f"{mid}.json")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            canon[v8] = json.load(f)
missing = sorted(set(LY.MAPS) - set(canon))
if missing:
    # RuntimeError, not SystemExit: scripts/build_island.py runs this file after saving the .blend and reports a
    # failure as MANIFEST_WARN (`except Exception`); a SystemExit escaped that handler and ended the build script
    # before its NON_AUTHORED_MAPS line and the --render step. Run standalone, it still exits non-zero.
    raise RuntimeError(f"export_manifest: no MeowDB canonical map for GMS ids {missing} "
                       f"(game/data/misostory/map_id_crosswalk.json + game/data/canonical/maps)")


def trail_m(child, ca, parent, pa, gap):
    t = built_trails.get(f"Trail_{LY.MAPS[parent]['slug']}_{pa}_to_{LY.MAPS[child]['slug']}")
    return round(t["length_m"], 1) if t else round(LY.GAPS.get((child, ca), gap), 1)


exits = {m: [] for m in LY.MAPS}
arrivals = {m: [] for m in LY.MAPS}
for child, ca, parent, pa, gap, _bearing in LY.LINKS:
    tm = trail_m(child, ca, parent, pa, gap)
    if LY.is_arrival_only(child, ca):
        # MeowDB: the parent's portal leads one way to a player spawn of the child; the child's anchor is an arrival
        # point (a marker, not a portal), reached down the one-way ledge trail
        exits[parent].append({"portal": pa, "to_map": child, "to_portal": ca, "to_arrival": ca, "kind": "edge",
                              "one_way": True, "trail_m": tm})
        arrivals[child].append({"name": ca, "from_map": parent, "from_portal": pa, "trail_m": tm,
                                "ledge_m": LY.ONE_WAY_LEDGE.get((parent, pa, child, ca))})
        continue
    exits[parent].append({"portal": pa, "to_map": child, "to_portal": ca, "kind": "edge", "one_way": False,
                          "trail_m": tm})
    exits[child].append({"portal": ca, "to_map": parent, "to_portal": pa, "kind": "edge", "one_way": False,
                         "trail_m": tm})
for mm, pn, it, ipn in LY.DOOR_LINKS:
    exits[mm].append({"portal": pn, "to_map": it, "to_portal": ipn, "kind": "door", "one_way": False})
    exits[it].append({"portal": ipn, "to_map": mm, "to_portal": pn, "kind": "door", "one_way": False})


def summed_mobs(spawns):
    """{species: proxies} over every m.mobs area (build_report lists one entry per area)."""
    out = {}
    for s in spawns:
        out[s["mob"]] = out.get(s["mob"], 0) + int(s.get("count", 0))
    return out


def canonical_mobs(monsters):
    """{species: MeowDB spawn points} (monsters[].count), summed should a species ever be listed twice."""
    out = {}
    for x in monsters or []:
        out[x["name"]] = out.get(x["name"], 0) + int(x.get("count", 0))
    return out


maps = []
for mid, m in LY.MAPS.items():
    o = origins[mid]
    gx, gy = LY.world_to_geo(o[0], o[1])
    built = report.get(str(mid), {})
    c = canon[mid]
    maps.append({
        "id": mid, "meowdb_map_id": crosswalk[mid], "name": m["name"], "meowdb_name": c.get("name"),
        "slug": m["slug"], "street": m["street"], "kind": m["kind"],
        "footprint_m": [m["L"], m["D"]], "base_height_m": m["z"], "world_origin": [round(o[0], 2), round(o[1], 2)],
        "world_yaw_deg": LY.world_yaw(mid), "worldmap_frame_origin": [round(gx, 1), round(gy, 1)],
        "exits": exits[mid],
        "arrival_points": arrivals[mid],
        "classic_npcs": [n.get("name") for n in c.get("npcs") or []],
        "classic_mobs": canonical_mobs(c.get("monsters")),
        "classic_source": f"MeowDB MS Classic, game/data/canonical/maps/{crosswalk[mid]}.json",
        "built_status": built.get("status", "not built"),
        "built_npcs": [n.get("name") for n in built.get("npcs", [])],
        "built_mobs": summed_mobs(built.get("spawns", [])),
        "routes": [r["name"] for r in built.get("routes", [])],
        "traversal_ok": built.get("traversal", {}).get("ok"),
    })
manifest = {"island": "Maple Island (MeowDB MS Classic; the 3D layout follows Iteration One's GMS v8 research)",
            "classic_source": "MeowDB MS Classic (game/data/canonical/maps, via game/data/misostory/map_id_crosswalk.json)",
            "start_map": 0, "start_map_meowdb": crosswalk.get(0),
            "primary_route": [0, 10000, 20000, 30000, 40000, 40001, 40002, 50000, 60000],
            "rainbow_street_route": [50000, 1000000, 1010000, 1020000, 1020001],
            "maps": maps}
with open(os.path.join(ROOT, "docs", "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
    json.dump(manifest, f, indent=1)

name = {m["id"]: m["name"] for m in maps}


def fmt_counts(d):
    return ", ".join(f"{k}×{v}" for k, v in d.items())


L = ["# Maple Island manifest (built world)", "",
     "Generated by `scripts/export_manifest.py` from `src/misostory/layout.py`, `docs/build_report.json` and the MeowDB "
     "MS Classic maps (`game/data/canonical/maps`, found through `game/data/misostory/map_id_crosswalk.json`). "
     "Positions are meters in Blender world space. The world-map frame is the same space rotated so north is up, "
     "which is how the classic in-game world map is drawn.", "",
     "NPCs and monsters (MeowDB) are MeowDB's lists: NPC names and, per species, the number of spawn points. The "
     "built columns are what the Blender world holds: NPC proxies, and the representative monster proxies (a visual "
     "placeholder per spawn area, not the spawn count; the runtime spawns MeowDB's monsters in the authored spawn "
     "regions).", "",
     "## Maps", "",
     "| ID | MeowDB id | Name | Region | Kind | Footprint (m) | Base z | Built | Traversal | NPCs (MeowDB) | "
     "NPCs (built) | Monsters (MeowDB spawn points) | Monster proxies (built) |",
     "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
for m in maps:
    L.append(f"| {m['id']} | {m['meowdb_map_id']} | {m['name']} | {m['street']} | {m['kind']} | "
             f"{m['footprint_m'][0]}×{m['footprint_m'][1]} | {m['base_height_m']} | {m['built_status']} | "
             f"{m['traversal_ok']} | {', '.join(m['classic_npcs'])} | {', '.join(m['built_npcs'])} | "
             f"{fmt_counts(m['classic_mobs'])} | {fmt_counts(m['built_mobs'])} |")
L += ["", "## Topology: map → exit → destination", "",
      "Every exit is a MeowDB portal. An arrival point is not a portal: it is where a one-way portal of another map "
      "lands (MeowDB: a player spawn of this map), reached in 3D down a one-way trail ledge.", ""]
for m in maps:
    L.append(f"### {m['id']} {m['name']} (`{m['slug']}`, MeowDB {m['meowdb_map_id']})")
    for e in m["exits"]:
        trail = f", {e['trail_m']} m trail" if e.get("trail_m") else ""
        if e.get("one_way"):
            L.append(f"- `{e['portal']}` → **{e['to_map']} {name[e['to_map']]}** arrival point `{e['to_arrival']}` "
                     f"[{e['kind']}{trail}] (one-way: no portal back)")
        else:
            L.append(f"- `{e['portal']}` → **{e['to_map']} {name[e['to_map']]}** `{e['to_portal']}` [{e['kind']}{trail}]")
    for a in m["arrival_points"]:
        ledge = f", ending in a {a['ledge_m']} m drop-down ledge" if a.get("ledge_m") else ""
        L.append(f"- arrival point `{a['name']}` ← **{a['from_map']} {name[a['from_map']]}** `{a['from_portal']}` "
                 f"[one-way, {a['trail_m']} m trail{ledge}] (not a portal: no exit back)")
    L.append("")
L += ["## Routes", "",
      "- Primary route: " + " → ".join(f"{i} {name[i]}" for i in manifest["primary_route"]),
      "- Rainbow Street: " + " → ".join(f"{i} {name[i]}" for i in manifest["rainbow_street_route"]),
      "- Side maps of the Field West of Amherst: 1000001, 1000002, 1000003, 1000004, 1000005, 1000006",
      "- Amherst side maps: 1010002 Amherst Townstreet → 1010004 Snail Field of Flowers; interiors 1010001, 1010003",
      "- Interiors: 20001 (from 20000), 60001 (from 60000), 1010001 and 1010003 (from 1010000)", ""]
with open(os.path.join(ROOT, "docs", "MAPLE_ISLAND_MANIFEST.md"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(L) + "\n")
print("MANIFEST_DONE", len(maps))
