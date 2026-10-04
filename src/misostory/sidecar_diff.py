"""Verify a fresh runtime export against the shipped one before copying it over (no bpy; any Python 3).

    PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
    "$PY" src/misostory/sidecar_diff.py --old game/assets/world --new _scratch/export_staging [--json out.json]

Checks (exit code 1 when any fails):

* files: every chunk of the old export exists in the new one (glb, collision glb when the old one had it, sidecar),
  plus index.json and _library.*; every sidecar parses as JSON; every file a sidecar lists under `files` exists
  (an empty name means "none");
* schema: additive only. For every sidecar (and index.json) the set of key paths of the old file must be contained
  in the new file's. Key paths walk dicts and lists (list items are merged: ``portals[].to_portal``), so a removed or
  renamed field anywhere is reported. A changed value type at the same path (e.g. str -> int) is reported too,
  except null <-> value (optional fields). A problem list or dict that is merely empty now (no blockers left, no
  exact fallback, no route-check offender: `EMPTIABLE`) is not a removal, as long as the container itself is still
  there; any other emptied list (a map's climbables or routes) is;
* counts: the expected Iteration Two totals: 25 map/interior chunks, 47 portals, 21 NPCs each with a MeowDB id, 25
  maps with player_spawns[0], one arrival point and one ledge (40000), spawn regions on exactly the 15 maps with
  MeowDB spawns, 20 trails (one one-way), no arrival-only portal, one one-way portal, and no portal with an empty
  to_portal (the runtime cross-checks it as Iteration One's v8 target);
* contract (per map, against the canonical MeowDB data in game/data, read-only): the NPC set by MeowDB id and name;
  the portal set by name, destination map and destination portal (one-way portals: to_spawn_index 0 and a matching
  arrival point in the destination sidecar); every portal reached by a declared route that enters its press-Up
  trigger box (portal_adaptations.json `trigger`); spawn regions present exactly where MeowDB has spawns, with species
  hints that are MeowDB species of the map and walkable ground; player_spawns[0] inside the footprint and, when the
  export measured it (`spawn_clearance`), clear of the shipped collision; every portal arrival point grounded and
  clear (the runtime would otherwise have to move the player: fix the source world instead); every route end clear
  for the controller's body (the route bot starts runs there); no route sample under a real overhang (route_check
  `overhead_by_kind.body`: wall geometry inside a walking player's body band); the one-way ledge invariant of
  MAP_ARCHITECTURE 4.4 (ledge_rules.py: jump apex at the cap + step-up + 0.30 <= height <= 2.6, face on the gate
  plane within 0.1 m, the gate plane at footprint + 1 m, blocked in reverse); World_Trails one-way flags.
  Blocked portal arrivals are also listed under `arrival_warnings` (kept for older readers of the report).

The report lists added key paths (the changelog for docs/runtime/blender_export.md).
"""

import argparse
import json
import math
import os
import sys

if __package__ in (None, ""):  # run as a script: make the misostory package importable (its __init__ has no bpy)
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from misostory import ledge_rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPECT = {"map_chunks": 25, "portals": 47, "npcs": 21, "player_spawn0": 25, "arrival_points": 1, "ledges": 1,
          "spawn_region_maps": 15, "trails": 20, "one_way_trails": 1}


def key_paths(node, prefix="", out=None):
    """{path: set(type names)} of every key path in a JSON value (list items merged under '[]')."""
    if out is None:
        out = {}
    if isinstance(node, dict):
        for k, v in node.items():
            p = f"{prefix}.{k}" if prefix else str(k)
            out.setdefault(p, set()).add(type_name(v))
            key_paths(v, p, out)
    elif isinstance(node, list):
        for v in node:
            p = f"{prefix}[]"
            out.setdefault(p, set()).add(type_name(v))
            key_paths(v, p, out)
    return out


def type_name(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, (int, float)):
        return "number"
    return type(v).__name__


# dicts whose keys are data (chunk, material, asset and object names; per-class / per-rule counts), not schema
DATA_KEYED = ("chunks", "materials", "prop_shapes", "exact_fallback", "mesh_classes", "instances_skipped",
              "mesh_class_source", "overhead_by_kind", "offenders")
# containers that may legitimately become empty when the source world gets better: problem lists (blockers, the
# exact-mesh fallbacks, the route-check offenders and overhead samples) and the tag list of exact-mesh instances.
# Any other list or dict that empties (a map's climbables, routes, cameras, ...) is reported as removed fields, so an
# exporter that silently drops a marker kind cannot pass the schema gate.
EMPTIABLE = ("blockers", "exact_fallback", "exact_by_tag", "offenders", "overhead", "instances_skipped")


def emptied_container(path, present):
    """True when `path` is gone only because an EMPTIABLE list or data-keyed dict that still exists is now empty (a
    list's items '[]' or a data dict's '<*>' children, at any depth below that container): no field was removed.
    Example: 'spawn_clearance.portal_arrivals[].blockers[]' once every arrival is clear;
    'collision.exact_fallback.<*>[]' once nothing falls back to an exact mesh. Not 'climbables[]' or 'routes[]'."""
    p = path
    while True:
        if p.endswith("[]"):
            p = p[:-2]
        elif "." in p and p.rsplit(".", 1)[1].startswith("<*>"):
            p = p.rsplit(".", 1)[0]
        else:
            return False
        if p in present:
            return p.rsplit(".", 1)[-1] in EMPTIABLE


def normalise(paths):
    """Collapse data-keyed dict children (index.json chunks.<name>, materials.<name>, ...) to '<*>'."""
    out = {}
    for p, t in paths.items():
        parts = p.split(".")
        norm = []
        skip = False
        for part in parts:
            if skip:
                norm.append("<*>" + ("[]" if part.endswith("[]") else ""))
                skip = False
                continue
            norm.append(part)
            base = part[:-2] if part.endswith("[]") else part
            if base in DATA_KEYED and not part.endswith("[]"):
                skip = True
        out.setdefault(".".join(norm), set()).update(t)
    return out


def _point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1:
            inside = not inside
    return inside


def _dist_to_outline(x, y, poly):
    """Distance from (x, y) to the polygon's boundary."""
    best = math.inf
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy + 1e-12)))
        best = min(best, math.hypot(x - (ax + t * dx), y - (ay + t * dy)))
    return best


def _misostory_value(data_dir, fname, section, key):
    """game/data/misostory/<fname>.json section.key as a float, or None when absent (read-only)."""
    try:
        with open(os.path.join(data_dir, "misostory", f"{fname}.json"), encoding="utf-8") as f:
            v = json.load(f).get(section, {}).get(key)
        return None if v is None else float(v)
    except (OSError, ValueError, AttributeError):
        return None


def load_canonical(data_dir):
    """({meowdb map id: canonical map record}, {gms v8 id: meowdb id}) from game/data (read-only); ({}, {}) when the
    data is absent (the contract checks then report that instead of passing silently)."""
    maps, v8 = {}, {}
    cw = os.path.join(data_dir, "misostory", "map_id_crosswalk.json")
    if not os.path.exists(cw):
        return maps, v8
    with open(cw, encoding="utf-8") as f:
        for row in json.load(f):
            v8[int(row["gms_v8_id"])] = str(row["meowdb_id"])
            p = os.path.join(data_dir, "canonical", "maps", f"{row['meowdb_id']}.json")
            if os.path.exists(p):
                with open(p, encoding="utf-8") as g:
                    maps[str(row["meowdb_id"])] = json.load(g)
    return maps, v8


def _portal_inward_xz(p):
    """Unit Godot (x, z) direction into the map at a portal marker: minus anchor_normal_xz (edges), else the door's
    facing (the xform's basis z column), as MapDefinitions does."""
    n = p.get("anchor_normal_xz")
    if n and math.hypot(n[0], n[1]) > 1e-3:
        d = (-n[0], -n[1])
    else:
        x = p.get("xform") or [0.0] * 12
        d = (x[6], x[8])
    ln = math.hypot(d[0], d[1]) or 1.0
    return d[0] / ln, d[1] / ln


def route_reach(s, portal, half_depth, half_width, height, step=0.25):
    """Smallest |distance along the inward normal| of a route sample inside the portal's press-Up trigger box
    (centred on the anchor: half_depth along the normal, half_width across, 0.5 m below to `height` above), or None
    when no declared route enters the box."""
    o = portal.get("position") or [0.0, 0.0, 0.0]
    ix, iz = _portal_inward_xz(portal)
    best = None
    for r in s.get("routes") or []:
        pts = r.get("points") or []
        for a, b in zip(pts, pts[1:]):
            n = max(1, int(math.dist(a, b) / step))
            for k in range(n + 1):
                t = k / n
                x, y, z = (a[i] + (b[i] - a[i]) * t for i in range(3))
                if not -0.5 <= y - o[1] <= height:
                    continue
                dx, dz = x - o[0], z - o[2]
                along, across = dx * ix + dz * iz, -dx * iz + dz * ix
                if abs(along) <= half_depth and abs(across) <= half_width and (best is None or abs(along) < best):
                    best = abs(along)
    return best


def contract(sidecars, data_dir, root):
    """(failures, arrival_warnings) of the per-map export contract against the canonical data (see module doc)."""
    fails, warns = [], []
    canon, v8 = load_canonical(data_dir)
    if not canon:
        return [f"contract: no canonical map data under {data_dir} (map_id_crosswalk.json + canonical/maps)"], warns
    trig = {k: _misostory_value(data_dir, "portal_adaptations", "trigger", k) for k in ("width_m", "depth_m", "height_m")}
    if None in trig.values():
        fails.append(f"contract: no press-Up trigger size in {data_dir}/misostory/portal_adaptations.json (trigger)")
    maps = {s.get("meowdb_map_id"): (f, s) for f, s in sidecars.items() if s.get("kind") in ("map", "interior")}
    for mid in sorted(set(canon) - set(maps)):
        fails.append(f"{mid}: no map sidecar with this meowdb_map_id")
    lo, hi, _detail = ledge_rules.ledge_bounds(root)
    for mid, (f, s) in sorted((k, v) for k, v in maps.items() if k is not None):
        rec = canon.get(mid)
        if rec is None:
            fails.append(f"{f}: meowdb_map_id {mid} is not a canonical Maple Island map")
            continue
        if v8.get(s.get("map_id")) != mid:
            fails.append(f"{f}: map_id {s.get('map_id')} and meowdb_map_id {mid} disagree with the crosswalk")
        # NPCs: exactly MeowDB's, by id and name
        want = {(str(n["id"]), n["name"]) for n in rec.get("npcs") or []}
        have = {(str(n.get("meowdb_npc_id")), n.get("name")) for n in s.get("npcs") or []}
        if want != have:
            fails.append(f"{mid} npcs: missing {sorted(want - have)}, not MeowDB {sorted(have - want)}")
        # portals: MeowDB's names, destinations and destination portals
        cports = {p["name"]: p for p in rec.get("portals") or []}
        sports = {p["name"]: p for p in s.get("portals") or []}
        if set(cports) != set(sports):
            fails.append(f"{mid} portals: missing {sorted(set(cports) - set(sports))}, "
                         f"not MeowDB {sorted(set(sports) - set(cports))}")
        for name in sorted(set(cports) & set(sports)):
            c, p = cports[name], sports[name]
            if p.get("to_meowdb_map_id") != c.get("to_map_id") or v8.get(p.get("to_map")) != c.get("to_map_id"):
                fails.append(f"{mid}.{name}: leads to {p.get('to_meowdb_map_id')} (v8 {p.get('to_map')}), MeowDB "
                             f"{c.get('to_map_id')}")
            if c.get("to_portal"):  # two-way: the reciprocal portal MeowDB derives
                if p.get("one_way") or p.get("to_portal") != c["to_portal"]:
                    fails.append(f"{mid}.{name}: to_portal {p.get('to_portal')!r} one_way {p.get('one_way')}, MeowDB "
                                 f"{c['to_portal']!r} (two-way)")
                continue
            # one-way: no reciprocal; the export names the destination's arrival point and spawn index 0
            if not p.get("one_way") or p.get("to_spawn_index") != 0 or not p.get("to_arrival"):
                fails.append(f"{mid}.{name}: MeowDB has no portal back, but the export says one_way "
                             f"{p.get('one_way')}, to_spawn_index {p.get('to_spawn_index')}, to_arrival "
                             f"{p.get('to_arrival')!r}")
                continue
            dest = maps.get(c.get("to_map_id"), (None, {}))[1]
            arr = [a for a in dest.get("arrival_points") or [] if a.get("name") == p["to_arrival"]]
            if len(arr) != 1 or arr[0].get("from_meowdb_map_id") != mid or arr[0].get("from_portal") != name or \
                    arr[0].get("spawn_index") != 0:
                fails.append(f"{mid}.{name}: destination {c.get('to_map_id')} has no matching arrival point "
                             f"{p['to_arrival']!r} (from {mid}.{name}, spawn_index 0)")
        # every portal is reached by a declared route that enters its press-Up trigger (routes were walked over the
        # real geometry; a route that stops short of the trigger no longer proves the portal is reachable)
        if None not in trig.values():
            for p in s.get("portals") or []:
                if route_reach(s, p, trig["depth_m"] / 2, trig["width_m"] / 2, trig["height_m"]) is None:
                    fails.append(f"{mid}.{p.get('name')}: no declared route enters its press-Up trigger "
                                 f"({trig['width_m']} x {trig['depth_m']} m around the anchor)")
        for a in s.get("arrival_points") or []:
            src = maps.get(a.get("from_meowdb_map_id"), (None, {}))[1]
            if not any(p.get("one_way") and p.get("to_arrival") == a.get("name") and p.get("name") == a.get("from_portal")
                       for p in src.get("portals") or []):
                fails.append(f"{mid} arrival point {a.get('name')}: no one-way portal "
                             f"{a.get('from_meowdb_map_id')}.{a.get('from_portal')} leads to it")
        # spawn regions: exactly where MeowDB spawns monsters; species hints are MeowDB species of the map
        species = {m["name"] for m in rec.get("monsters") or []}
        regs = s.get("spawn_regions") or []
        if bool(rec.get("spawns")) != bool(regs):
            fails.append(f"{mid}: {len(rec.get('spawns') or [])} MeowDB spawn points but {len(regs)} spawn regions")
        for r in regs:
            bad = sorted(set(r.get("species") or []) - species)
            if bad:
                fails.append(f"{mid} spawn region {r.get('name')}: species {bad} are not MeowDB species of the map")
            if len(r.get("polygon_xz") or []) < 3 or r.get("surface_y") is None or not r.get("walkable_fraction"):
                fails.append(f"{mid} spawn region {r.get('name')}: no polygon or no walkable ground")
        # player spawns: [0] authored, inside the footprint, clear of the shipped collision
        fp = (s.get("footprint") or {}).get("outline_xz") or []
        sp = {p.get("index"): p for p in s.get("player_spawns") or []}
        if 0 not in sp:
            fails.append(f"{mid}: no player_spawns[0]")
        elif len(fp) >= 3 and not _point_in_poly(sp[0]["position"][0], sp[0]["position"][2], fp):
            fails.append(f"{mid}: player_spawns[0] {sp[0]['position']} is outside the footprint")
        n_canon = max(len(rec.get("player_spawns") or []), 1)
        for i in sp:
            if not isinstance(i, int) or not 0 <= i < n_canon:
                fails.append(f"{mid}: player_spawns index {i} is not a MeowDB playerSpawns index (0..{n_canon - 1})")
        clr = s.get("spawn_clearance")
        if isinstance(clr, dict):
            for row in clr.get("player_spawns") or []:
                if not row.get("clear"):
                    fails.append(f"{mid}: player_spawns[{row.get('index')}] is blocked by {row.get('blockers')} "
                                 f"(the runtime would have to move it)")
            for row in clr.get("portal_arrivals") or []:
                if not row.get("clear"):
                    msg = (f"{mid}.{row.get('portal')} arrival blocked by {row.get('blockers')}"
                           f"{'' if row.get('grounded', True) else ' (not grounded)'}")
                    warns.append(msg)
                    fails.append(msg + " (the runtime would have to move arriving players)")
            for row in clr.get("route_ends") or []:
                if not row.get("clear"):
                    fails.append(f"{mid} route {row.get('route')} {row.get('end')} {row.get('position')}: a standing "
                                 f"body touches {row.get('blockers')} (a route run cannot start there)")
        rc = (((s.get("collision") or {}).get("summary") or {}).get("route_check") or {})
        body = (rc.get("overhead_by_kind") or {}).get("body", 0)
        if body:
            where = sorted({o.get("route") for o in rc.get("overhead") or [] if o.get("kind") == "body"})
            fails.append(f"{mid}: {body} route sample(s) under wall geometry inside a walking player's body "
                         f"(routes {where})")
        # the one-way ledge (MAP_ARCHITECTURE 4.4)
        for led in s.get("ledges") or []:
            h = led.get("height_m")
            tag = f"{mid} ledge {led.get('from_map')}:{led.get('from_portal')} -> {led.get('arrival_point')}"
            if h is None or not lo <= h <= hi:
                fails.append(f"{tag}: height {h} m outside [{lo:.3f}, {hi}] m")
            off = led.get("face_offset_from_gate_m")
            if off is None or off > ledge_rules.LEDGE_FACE_TOL_M:
                fails.append(f"{tag}: face {off} m off the gate plane (tolerance {ledge_rules.LEDGE_FACE_TOL_M} m)")
            if not led.get("reverse_blocked_at_face"):
                fails.append(f"{tag}: not blocked at the face when walked back")
            gp = led.get("gate_plane") or {}
            pt = gp.get("point")
            ring = _misostory_value(data_dir, "presentation", "containment", "ring_offset_m")
            if ring is not None and gp.get("offset_from_footprint_m") != ring:
                # MAP_ARCHITECTURE 4.4: gate plane = RegionIndex boundary = containment-ring gap; they must coincide
                fails.append(f"{tag}: gate plane at footprint + {gp.get('offset_from_footprint_m')} m, but the "
                             f"runtime's containment ring (presentation.json ring_offset_m) is at + {ring} m")
            if pt and len(fp) >= 3:
                d = _dist_to_outline(pt[0], pt[2], fp)
                outside = not _point_in_poly(pt[0], pt[2], fp)
                want_off = gp.get("offset_from_footprint_m")
                if not outside or want_off is None or abs(d - want_off) > ledge_rules.LEDGE_FACE_TOL_M:
                    fails.append(f"{tag}: gate plane point {pt} is {d:.3f} m {'outside' if outside else 'inside'} "
                                 f"the footprint, expected {want_off} m outside")
    # trails: the one-way flag matches the one-way portals
    trails = (sidecars.get("World_Trails.json") or {}).get("trails") or []
    one_way_portals = {(p.get("map"), p.get("name")) for _f, s in maps.values() for p in s.get("portals") or []
                       if p.get("one_way")}
    for t in trails:
        key = (t.get("from_map"), t.get("from_portal"))
        if bool(t.get("one_way")) != (key in one_way_portals):
            fails.append(f"trail {t.get('mesh')}: one_way {t.get('one_way')} but portal {key} one_way "
                         f"{key in one_way_portals}")
        if t.get("one_way") and not t.get("ledge"):
            fails.append(f"trail {t.get('mesh')}: one-way trail without a ledge")
    return fails, warns


def compare(old_dir, new_dir, data_dir=None, root=None):
    root = root or ROOT
    data_dir = data_dir or os.path.join(root, "game", "data")
    rep = {"missing_files": [], "unparsable": [], "removed_paths": {}, "type_changes": {}, "added_paths": {},
           "counts": {}, "count_failures": [], "listed_files_missing": [], "contract_failures": [],
           "arrival_warnings": []}
    old_files = sorted(f for f in os.listdir(old_dir) if f.endswith((".json", ".glb")))
    new_files = set(os.listdir(new_dir))
    for f in old_files:
        if f not in new_files:
            rep["missing_files"].append(f)
    sidecars = {}
    for f in sorted(new_files):
        if not f.endswith(".json"):
            continue
        try:
            with open(os.path.join(new_dir, f), encoding="utf-8") as fh:
                sidecars[f] = json.load(fh)
        except (OSError, ValueError) as e:
            rep["unparsable"].append(f"{f}: {e}")
    old_sidecars = {}
    for f in old_files:
        if not f.endswith(".json"):
            continue
        try:
            with open(os.path.join(old_dir, f), encoding="utf-8") as fh:
                old_sidecars[f] = json.load(fh)
        except (OSError, ValueError):
            continue
        if f not in sidecars:
            continue
        po, pn = normalise(key_paths(old_sidecars[f])), normalise(key_paths(sidecars[f]))
        removed = sorted(p for p in set(po) - set(pn) if not emptied_container(p, pn))
        if removed:
            rep["removed_paths"][f] = removed
        changed = {}
        for p in set(po) & set(pn):
            to, tn = po[p] - {"null"}, pn[p] - {"null"}
            if to and tn and not to <= tn:
                changed[p] = [sorted(po[p]), sorted(pn[p])]
        if changed:
            rep["type_changes"][f] = changed
        added = sorted(set(pn) - set(po))
        if added:
            rep["added_paths"][f] = added
    for f, s in sidecars.items():
        for which, name in (s.get("files") or {}).items() if isinstance(s.get("files"), dict) else ():
            if name and name not in new_files:
                rep["listed_files_missing"].append(f"{f}: files.{which} = {name}")
    # counts
    maps = [s for f, s in sidecars.items() if s.get("kind") in ("map", "interior")]
    c = rep["counts"]
    c["map_chunks"] = len(maps)
    c["portals"] = sum(len(s.get("portals") or []) for s in maps)
    c["npcs"] = sum(len(s.get("npcs") or []) for s in maps)
    c["npcs_with_meowdb_id"] = sum(1 for s in maps for n in s.get("npcs") or [] if n.get("meowdb_npc_id"))
    c["player_spawn0"] = sum(1 for s in maps if any(p.get("index") == 0 for p in s.get("player_spawns") or []))
    c["arrival_points"] = sum(len(s.get("arrival_points") or []) for s in maps)
    c["ledges"] = sum(len(s.get("ledges") or []) for s in maps)
    c["spawn_region_maps"] = sum(1 for s in maps if s.get("spawn_regions"))
    c["spawn_regions"] = sum(len(s.get("spawn_regions") or []) for s in maps)
    c["arrival_only_portals"] = sum(1 for s in maps for p in s.get("portals") or [] if p.get("one_way_arrival"))
    c["empty_to_portal"] = sum(1 for s in maps for p in s.get("portals") or [] if not p.get("to_portal"))
    c["one_way_portals"] = sum(1 for s in maps for p in s.get("portals") or [] if p.get("one_way"))
    c["meowdb_map_ids"] = sum(1 for s in maps if s.get("meowdb_map_id"))
    trails = (sidecars.get("World_Trails.json") or {}).get("trails") or []
    c["trails"] = len(trails)
    c["one_way_trails"] = sum(1 for t in trails if t.get("one_way"))
    for k, v in EXPECT.items():
        if c.get(k) != v:
            rep["count_failures"].append(f"{k}: {c.get(k)} (expected {v})")
    if c["npcs_with_meowdb_id"] != c["npcs"]:
        rep["count_failures"].append(f"npcs_with_meowdb_id: {c['npcs_with_meowdb_id']} of {c['npcs']}")
    if c["arrival_only_portals"]:
        rep["count_failures"].append(f"arrival_only_portals: {c['arrival_only_portals']} (expected 0)")
    if c["empty_to_portal"]:  # MapDefinitions cross-checks to_portal (the v8 target) on every portal
        rep["count_failures"].append(f"empty_to_portal: {c['empty_to_portal']} (expected 0)")
    if c["one_way_portals"] != 1:
        rep["count_failures"].append(f"one_way_portals: {c['one_way_portals']} (expected 1)")
    if c["meowdb_map_ids"] != c["map_chunks"]:
        rep["count_failures"].append(f"meowdb_map_ids: {c['meowdb_map_ids']} of {c['map_chunks']}")
    # the per-map contract against the canonical data (blocked portal arrivals are contract failures)
    rep["contract_failures"], rep["arrival_warnings"] = contract(sidecars, data_dir, root)
    c["blocked_portal_arrivals"] = len(rep["arrival_warnings"])
    rep["ok"] = not (rep["missing_files"] or rep["unparsable"] or rep["removed_paths"] or rep["type_changes"] or
                     rep["count_failures"] or rep["listed_files_missing"] or rep["contract_failures"])
    return rep


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--old", required=True)
    ap.add_argument("--new", required=True)
    ap.add_argument("--data", help="game/data (canonical + misostory); default: the repo's")
    ap.add_argument("--json")
    a = ap.parse_args(argv)
    rep = compare(a.old, a.new, data_dir=a.data)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(rep, f, indent=1)
    print("SIDECAR_DIFF counts", json.dumps(rep["counts"]))
    for k in ("missing_files", "unparsable", "count_failures", "listed_files_missing", "contract_failures",
              "arrival_warnings"):
        if rep[k]:
            print("SIDECAR_DIFF", k, json.dumps(rep[k]))
    for k in ("removed_paths", "type_changes"):
        for f, v in rep[k].items():
            print("SIDECAR_DIFF", k, f, json.dumps(v))
    added = sorted({p for v in rep["added_paths"].values() for p in v})
    print("SIDECAR_DIFF added_paths", json.dumps(added))
    print("SIDECAR_DIFF_OK", rep["ok"])
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
