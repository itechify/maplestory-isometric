"""Validate the built island (.blend) and write docs/VALIDATION.md + docs/validation_report.json.

blender -b MapleIsland.blend --python scripts/validate.py [-- --out DIR] [--build-report FILE]

--out DIR writes VALIDATION.md + validation_report.json into DIR instead of docs/ (for test runs);
--build-report FILE reads that build report instead of docs/build_report.json.

Checks: collection hierarchy, naming, hidden objects (colliders exempt), missing materials, broken
instances, polygon budget (per map, plus the WORLD layer as its own line, plus the assets with the
largest instanced triangle totals), portal topology + reciprocity + grounding (and the MeowDB portal set; the
one-way 30000 out00 -> 40000 link is a portal plus an arrival marker), floating props (geometric:
resting on walkable ground or touching a surface; map dressing, mobs, NPCs and World_Trails instances),
m.place props crowding route centrelines (graded by body clearance), map completeness vs. MeowDB MS Classic
(fidelity: NPCs by MeowDB id and name, monster species; game/data/canonical/maps via the crosswalk), placeholders,
authored player_spawns[0] and spawn regions, and the results recorded at build time in docs/build_report.json:
traversal, route-graph connectivity (portal_split, orphan_routes), the Gameplay-camera scale proxies
(player_in_gameplay_frame), the walk between maps along every trail, both ways, against its expectation
(trail_walk), every trail's clearance from the runtime's containment rings (trail_ring_band) and the one-way ledge
invariant of MAP_ARCHITECTURE 4.4 (one_way_ledge).

Every section runs guarded: an exception inside one check is recorded in report["exceptions"] (and as a
high issue, check no_swallowed_exceptions) instead of aborting the whole validation. Exceptions that the
build swallowed and recorded in build_report (any non-empty "*exception*" / "swallowed" entry) are surfaced
there too.
"""

import importlib
import json
import math
import os
import pkgutil
import re
import sys
import traceback

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

from misostory import collision_tags as CT  # noqa: E402
from misostory import layout as LY  # noqa: E402

REQUIRED_TOP = ["MAPS", "ENVIRONMENT_ASSETS", "CHARACTER_PROXIES", "MONSTER_PROXIES", "PORTALS", "CAMERAS",
                "LIGHTING", "DEBUG", "WORLD"]
BAD_NAME = re.compile(r"^(Cube|Plane|Cylinder|Sphere|Icosphere|Cone|Torus|Circle|Empty|Mesh|Curve|Text|Suzanne)"
                      r"(\.\d+)?$|\.\d{3}$")
TRI_BUDGET_PER_MAP = 400_000     # every map is under it since the wave-3 flower trim (largest: 1000000, ~385k)
WORLD_TRI_BUDGET = 3_500_000     # WORLD layer (plinth, hull, trails, scenery forest, clouds), its own line (~2.9M)
TOP_ASSETS = 10
FLOAT_GAP = 0.35                 # an instance whose origin is <= this above walkable ground rests on it
ATTACH_TOL = 0.15                # ... or whose bounding box comes within this of a terrain/architecture surface
NEAR_ROUTE_M = 1.5               # m.place props (footprint >= NEAR_ROUTE_FOOTPRINT) closer than this to a route
NEAR_ROUTE_DZ = 1.5              #   centreline, at a height within this of the route surface, are examined
NEAR_ROUTE_FOOTPRINT = 0.9
INTERIOR_CLEAR_M = 0.8           # interiors: only solid geometry at body height within this of the centreline counts
HOP_TOP_M = 0.6                  # interiors: furniture whose top is lower than this above the walk surface is hop-able
ARCH_MIN_CLEAR_M = 0.3           # an archway the route passes through is exempt if its posts keep at least this
GRADE_MEDIUM_M = 0.45            # near-route body clearance below this is graded medium, otherwise low
ARCH_WORDS = ("arch", "gate", "trellis", "pergola", "torii", "doorway")
ROUTE_LIFT = 0.12                # DEBUG route curves float this far above the walk surface (mapkit.route)
FLOAT_SKIP_PREFIX = ("Cloud", "Mountain", "Ladder", "Vine", "Hanging", "NPC_Beacon")
EMBEDDED_ASSETS = ("Rock_Cliff_Stone",)   # set into cliff faces on purpose
NON_SOLID_TAGS = {"flower", "grass", "vine"}
TRAIL_COLL = "World_Trails"
FRAME_UV = (0.1, 0.9)            # player_in_gameplay_frame: the player must project inside this on both axes
FRAME_MOBS = 2                   #   and hunting maps need this many mob proxies inside 0..1
try:  # same rule as MapCtx.gameplay_frame_check
    from misostory.mapkit import FRAME_BAND as FRAME_UV, FRAME_MOBS_HUNTING as FRAME_MOBS  # noqa: F811
except Exception:  # noqa: BLE001
    pass

report = {"checks": {}, "issues": [], "stats": {}, "exceptions": []}
_ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = _ARGV[_ARGV.index("--out") + 1] if "--out" in _ARGV else os.path.join(ROOT, "docs")
BR_PATH = (_ARGV[_ARGV.index("--build-report") + 1] if "--build-report" in _ARGV
           else os.path.join(ROOT, "docs", "build_report.json"))


def issue(check, severity, msg, **kw):
    report["issues"].append({"check": check, "severity": severity, "msg": msg, **kw})


def check(name, ok, detail=""):
    report["checks"][name] = {"ok": bool(ok), "detail": detail}


def record_exception(section, text, severity="high", source="validate"):
    """A swallowed exception: keep the traceback in the report and raise an issue (never abort)."""
    last = [ln for ln in str(text).strip().splitlines() if ln.strip()]
    print("VALIDATE_WARN", source, section, last[-1] if last else text)
    report["exceptions"].append({"section": section, "source": source, "traceback": str(text)})
    issue("exceptions", severity, f"{source} {section}: {last[-1] if last else text}")


def run(section, fn):
    """Run one validation section; an exception is recorded and the check marked failed, not fatal."""
    try:
        fn()
    except Exception:  # noqa: BLE001
        record_exception(section, traceback.format_exc())
        if section not in report["checks"]:
            check(section, False, "validator section raised; see exceptions")


# ---------------------------------------------------------------- asset registry (kit + map-local assets)
def _load_registry():
    """Asset footprints/tags: the kit plus every map module's local X-assets (importing a map module only
    registers its assets; nothing is built)."""
    try:
        from misostory import kit
        from misostory import maps as maps_pkg
    except Exception:  # noqa: BLE001
        record_exception("registry", traceback.format_exc(), severity="medium")
        return {}
    for info in pkgutil.iter_modules(maps_pkg.__path__):
        if info.name.startswith("m"):
            try:
                importlib.import_module(f"misostory.maps.{info.name}")
            except Exception:  # noqa: BLE001
                record_exception(f"registry:{info.name}", traceback.format_exc(), severity="medium")
    return kit.REGISTRY


REGISTRY = _load_registry()

try:  # the traversal validator's constants (keep fallback copies so a framework change can't break validation)
    from misostory import traversal as TV
except Exception:  # noqa: BLE001
    TV = None
    record_exception("import traversal", traceback.format_exc(), severity="medium")
try:  # the trail builder's walk constants (trail_walk: the one-way ledge zone)
    from misostory import trails as TR
except Exception:  # noqa: BLE001
    TR = None
    record_exception("import trails", traceback.format_exc(), severity="medium")
_PLAYER_H = getattr(TV, "PLAYER_HEIGHT", None)
if _PLAYER_H is None:
    try:
        from misostory.mapkit import PLAYER_HEIGHT as _PLAYER_H
    except Exception:  # noqa: BLE001
        _PLAYER_H = 1.6
BODY_Z = tuple(getattr(TV, "BODY_Z", (0.15, _PLAYER_H)))  # body band above the walk surface (traversal.BODY_Z)
CLIMB_RADIUS = getattr(TV, "CLIMB_RADIUS", 2.2)
MAX_STEP = getattr(TV, "MAX_STEP", 0.45)

BR = {}
if os.path.exists(BR_PATH):
    try:
        BR = json.load(open(BR_PATH, encoding="utf-8"))
    except Exception:  # noqa: BLE001
        record_exception("build_report", traceback.format_exc())


def _load_meowdb():
    """{GMS v8 map id: MeowDB MS Classic map record} via game/data/misostory/map_id_crosswalk.json (read-only).

    MeowDB is the gameplay authority (docs/ITERATION_TWO_BRIEF.md): NPC sets, monster species and spawn counts, and
    player spawns come from game/data/canonical/maps/<meowdb id>.json; Iteration One's v8 research is reference."""
    out = {}
    cw_path = os.path.join(ROOT, "game", "data", "misostory", "map_id_crosswalk.json")
    if not os.path.exists(cw_path):
        return out
    for row in json.load(open(cw_path, encoding="utf-8")):
        p = os.path.join(ROOT, "game", "data", "canonical", "maps", f"{row['meowdb_id']}.json")
        if os.path.exists(p):
            out[int(row["gms_v8_id"])] = json.load(open(p, encoding="utf-8"))
    return out


MEOWDB = {}
try:
    MEOWDB = _load_meowdb()
except Exception:  # noqa: BLE001
    record_exception("meowdb", traceback.format_exc())


def asset_tags(name):
    return set(REGISTRY.get(name, {}).get("tags", ()))


def is_passable(ob, asset):
    """What the passable-tag registry calls passable never blocks a route (collision_tags.passable: climbables,
    passable flags, kit assets tagged vine, flower, grass, ...), as in traversal.obstacle_bvh. Names are not read."""
    return CT.passable(ob, asset_tags(asset))


# ---------------------------------------------------------------- organization
root = bpy.data.collections.get("MAPLE_ISLAND")
tops = [c.name for c in root.children] if root else []
missing = [t for t in REQUIRED_TOP if t not in tops]
check("hierarchy", root is not None and not missing, f"missing top collections: {missing}")
for t in missing:
    issue("hierarchy", "high", f"missing top-level collection {t}")
maps_coll = bpy.data.collections.get("MAPS")
map_colls = {c.get("map_id"): c for c in (maps_coll.children if maps_coll else []) if c.get("map_id") is not None}
expected = list(LY.MAPS)
absent = [m for m in expected if m not in map_colls]
check("all_maps_present", not absent, f"absent: {absent}")
for m in absent:
    issue("completeness", "high", f"map {m} has no MAPS collection")
placeholders = [m for m, c in map_colls.items() if c.get("placeholder")]
check("no_placeholders", not placeholders, f"placeholder maps: {placeholders}")
for m in placeholders:
    issue("completeness", "high", f"map {m} is still a placeholder")

_parents = {}
for c in bpy.data.collections:
    for ch in c.children:
        _parents[ch.name] = c.name


def _parent_chain_has(coll, names):
    n = coll.name
    while n in _parents:
        n = _parents[n]
        if n in names:
            return True
    return False


def in_debug(o):
    return any(c.name.startswith(("Debug", "DEBUG")) or _parent_chain_has(c, ("DEBUG",)) for c in o.users_collection)


coll_map = {}
for _mid, _c in map_colls.items():
    for _sub in [_c] + list(_c.children_recursive):
        coll_map[_sub.name] = _mid


# ---------------------------------------------------------------- naming / hidden / materials / instances
def sec_scene_hygiene():
    bad_names = [o.name for o in bpy.data.objects if BAD_NAME.search(o.name)]
    check("naming", not bad_names, f"{len(bad_names)} generic names: {bad_names[:15]}")
    for n in bad_names[:50]:
        issue("naming", "low", f"generic object name {n}")
    hidden = []
    for o in bpy.data.objects:
        if o.get("collider"):
            continue  # m.collider: invisible walkable proxies are hidden on purpose
        if o.hide_render or o.hide_viewport or o.hide_get():
            if not any(c.name == "DEBUG" or _parent_chain_has(c, ("DEBUG",)) for c in o.users_collection):
                hidden.append(o.name)
    check("no_hidden_objects", not hidden, f"{len(hidden)} hidden (colliders exempt): {hidden[:10]}")
    for n in hidden[:30]:
        issue("hidden", "medium", f"object hidden outside DEBUG: {n}")
    no_mat = []
    for o in bpy.data.objects:
        if o.type == "MESH":
            mats = [s.material for s in o.material_slots]
            if not mats or any(m is None for m in mats):
                no_mat.append(o.name)
    check("materials", not no_mat, f"{len(no_mat)} meshes missing materials: {no_mat[:10]}")
    for n in no_mat[:30]:
        issue("materials", "medium", f"mesh without material: {n}")
    broken = [o.name for o in bpy.data.objects if o.instance_type == "COLLECTION" and o.instance_collection is None]
    check("instances", not broken, f"{len(broken)} broken instances")
    for n in broken:
        issue("instances", "high", f"broken collection instance {n}")


run("scene_hygiene", sec_scene_hygiene)

# ---------------------------------------------------------------- polygon budget
tri_by_map = {}
total_tris = 0
world_tris = 0
top_assets = []


def sec_polygon_budget():
    global total_tris, world_tris, top_assets
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    world_coll = bpy.data.collections.get("WORLD")
    world_names = {c.name for c in ([world_coll] + list(world_coll.children_recursive))} if world_coll else set()
    tri_by_asset = {}
    unit_by_asset = {}
    tri_cache = {}
    failed = []
    for inst in dg.object_instances:
        ob = inst.instance_object if inst.is_instance else inst.object
        if ob.type != "MESH":
            continue
        key = (ob.original.name, inst.is_instance)
        tris = tri_cache.get(key)
        if tris is None:
            me = ob.data if inst.is_instance else ob.evaluated_get(dg).data
            try:
                tris = sum(len(p.vertices) - 2 for p in me.polygons)
            except Exception:  # noqa: BLE001
                tris = 0
                failed.append((ob.original.name, traceback.format_exc()))
            tri_cache[key] = tris
        total_tris += tris
        owner = inst.parent if inst.is_instance else inst.object
        owner = owner.original if owner else None
        mid = None
        in_world = False
        if owner is not None:
            for c in owner.users_collection:
                mid = coll_map.get(c.name)
                if mid is not None:
                    break
                if c.name in world_names:
                    in_world = True
        if mid is not None:
            tri_by_map[mid] = tri_by_map.get(mid, 0) + tris
        elif in_world:
            world_tris += tris
        if inst.is_instance:
            asset = ob.original.get("asset")
            if asset:
                tri_by_asset[asset] = tri_by_asset.get(asset, 0) + tris
                unit_by_asset.setdefault(asset, {})[ob.original.name] = tris
    if failed:
        record_exception("polygon_budget", f"{len(failed)} meshes could not be triangle-counted (counted as 0), "
                         f"first {failed[0][0]}:\n{failed[0][1]}", severity="medium")
    inst_count = {}
    for o in bpy.data.objects:
        if o.instance_type == "COLLECTION" and o.instance_collection is not None:
            inst_count[o.instance_collection.name] = inst_count.get(o.instance_collection.name, 0) + 1
    top_assets[:] = [{"asset": a, "instances": inst_count.get(a, 0),
                      "tris_per_instance": sum(unit_by_asset[a].values()), "total": t}
                     for a, t in sorted(tri_by_asset.items(), key=lambda kv: -kv[1])[:TOP_ASSETS]]
    report["stats"]["total_triangles"] = total_tris
    report["stats"]["world_triangles"] = world_tris
    report["stats"]["triangles_by_map"] = tri_by_map
    report["stats"]["top_assets_by_instanced_triangles"] = top_assets
    heavy = {m: t for m, t in tri_by_map.items() if t > TRI_BUDGET_PER_MAP}
    biggest = max(tri_by_map.items(), key=lambda kv: kv[1]) if tri_by_map else (None, 0)
    check("polygon_budget", not heavy, f"maps over {TRI_BUDGET_PER_MAP:,}: {heavy}; largest {biggest[0]} "
          f"({biggest[1]:,})")
    for m, t in heavy.items():
        issue("performance", "medium", f"map {m} has {t:,} triangles (budget {TRI_BUDGET_PER_MAP:,})")
    check("world_polygon_budget", world_tris <= WORLD_TRI_BUDGET,
          f"WORLD layer {world_tris:,} triangles (budget {WORLD_TRI_BUDGET:,})")
    if world_tris > WORLD_TRI_BUDGET:
        issue("performance", "medium", f"WORLD layer has {world_tris:,} triangles (budget {WORLD_TRI_BUDGET:,})")


run("polygon_budget", sec_polygon_budget)


# ---------------------------------------------------------------- portals
def sec_portals():
    """Every link has its two portal objects, reciprocal; a one-way link (layout.ONE_WAY) has a portal at the
    source (one_way, to_portal and to_arrival naming the arrival marker) and an arrival marker (no portal object)
    at the destination. The portal set is checked against MeowDB's portal list per map."""
    portals = {}
    arrivals = {}
    for o in bpy.data.objects:
        if "portal_name" in o.keys():
            portals[(int(o["map_id"]), o["portal_name"])] = o
        if "arrival_name" in o.keys():
            arrivals[(int(o["map_id"]), o["arrival_name"])] = o
    expected_links = [(c, ca, p, pa, "edge") for c, ca, p, pa, _g, _b in LY.LINKS] + \
                     [(it, ipn, mm, pn, "door") for mm, pn, it, ipn in LY.DOOR_LINKS]
    plinks = []
    for a_map, a_pn, b_map, b_pn, kind in expected_links:
        if LY.is_arrival_only(a_map, a_pn):  # one-way: b (source portal) -> a (arrival marker)
            src, arr = portals.get((b_map, b_pn)), arrivals.get((a_map, a_pn))
            if src is None or arr is None or (a_map, a_pn) in portals:
                issue("portals", "high", f"one-way link {b_map}:{b_pn} -> {a_map}:{a_pn}: needs a portal at the "
                      f"source and an arrival marker (no portal object) at the destination",
                      source=src is not None, arrival=arr is not None, portal_at_arrival=(a_map, a_pn) in portals)
                continue
            ok = (int(src["to_map"]) == a_map and src["to_portal"] == a_pn and src.get("to_arrival") == a_pn
                  and bool(src.get("one_way")) and int(arr["from_map"]) == b_map and arr["from_portal"] == b_pn)
            if not ok:
                issue("portals", "high", f"one-way link {b_map}:{b_pn} -> {a_map}:{a_pn}: portal/arrival marker "
                      f"fields disagree (to_portal and to_arrival must be '{a_pn}', one_way True)")
            d = (src.location - arr.location).length
            plinks.append({"a": f"{b_map}:{b_pn}", "b": f"{a_map}:{a_pn} (arrival)", "kind": kind,
                           "distance_m": round(d, 1), "reciprocal": False, "one_way": True, "fields_ok": ok})
            continue
        a = portals.get((a_map, a_pn))
        b = portals.get((b_map, b_pn))
        if a is None or b is None:
            issue("portals", "high", f"missing portal object(s) for link {a_map}:{a_pn} <-> {b_map}:{b_pn}",
                  missing=[f"{m}:{p}" for (m, p), ob in (((a_map, a_pn), a), ((b_map, b_pn), b)) if ob is None])
            continue
        recip = (int(a["to_map"]) == b_map and a["to_portal"] == b_pn and int(b["to_map"]) == a_map
                 and b["to_portal"] == a_pn)
        if not recip:
            issue("portals", "high", f"non-reciprocal portal pair {a_map}:{a_pn} <-> {b_map}:{b_pn}")
        d = (a.location - b.location).length
        if kind == "edge" and d > 90:
            issue("portals", "medium", f"edge link {a_map}:{a_pn} <-> {b_map}:{b_pn} is {d:.0f} m apart")
        plinks.append({"a": f"{a_map}:{a_pn}", "b": f"{b_map}:{b_pn}", "kind": kind, "distance_m": round(d, 1),
                       "reciprocal": recip})
    report["stats"]["portal_links"] = plinks
    extra = [f"{m}:{p}" for (m, p) in portals
             if not any((m, p) in ((l[0], l[1]), (l[2], l[3])) for l in expected_links)]
    # MeowDB portal parity: the built portal names per map equal MeowDB's (47 portals on the 25 maps)
    meow_missing, meow_extra = [], []
    for mid, rec in MEOWDB.items():
        want = {p["name"] for p in rec.get("portals", [])}
        have = {pn for (m, pn) in portals if m == mid}
        meow_missing += [f"{mid}:{p}" for p in sorted(want - have)]
        meow_extra += [f"{mid}:{p}" for p in sorted(have - want)]
    for e in meow_missing:
        issue("portals", "high", f"MeowDB portal {e} has no portal object")
    for e in meow_extra:
        issue("portals", "high", f"portal object {e} is not a MeowDB portal")
    report["stats"]["portal_count"] = len(portals)
    report["stats"]["arrival_markers"] = sorted(f"{m}:{n}" for (m, n) in arrivals)
    check("portal_topology", not [i for i in report["issues"] if i["check"] == "portals"],
          f"{len(plinks)} links ok-checked ({sum(1 for p in plinks if p.get('one_way'))} one-way); {len(portals)} "
          f"portal objects vs MeowDB {sum(len(r.get('portals', [])) for r in MEOWDB.values())} (missing "
          f"{meow_missing}, extra {meow_extra}); arrival markers {sorted(f'{m}:{n}' for (m, n) in arrivals)}; "
          f"extra portals: {extra}")
    for e in extra:
        issue("portals", "low", f"portal {e} not part of the classic topology")


run("portal_topology", sec_portals)


# ---------------------------------------------------------------- geometry helpers
def _mesh_into(verts, polys, me, mw):
    off = len(verts)
    verts.extend(mw @ v.co for v in me.vertices)
    polys.extend([off + i for i in p.vertices] for p in me.polygons)


def instance_parts(o):
    """(mesh, world matrix) of every source mesh of a collection instance."""
    coll = o.instance_collection
    base = o.matrix_world.copy()
    off = coll.instance_offset
    if off.length > 0:
        from mathutils import Matrix
        base = base @ Matrix.Translation(-off)
    return [(src.data, base @ src.matrix_basis) for src in coll.all_objects if src.type == "MESH"]


_mesh_bounds = {}


def mesh_bounds(me):
    """Local (min, max) per axis of a mesh, cached by mesh name."""
    b = _mesh_bounds.get(me.name)
    if b is None:
        cos = [v.co for v in me.vertices]
        b = [(min(c[i] for c in cos), max(c[i] for c in cos)) for i in range(3)] if cos else None
        _mesh_bounds[me.name] = b
    return b


def instance_bbox(o):
    pts = []
    for me, mw in instance_parts(o):
        b = mesh_bounds(me)
        if b:
            pts += [mw @ Vector((x, y, z)) for x in b[0] for y in b[1] for z in b[2]]
    if not pts:
        p = o.matrix_world.translation
        return p.copy(), p.copy()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def box_bvh(lo, hi):
    vs = [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return BVHTree.FromPolygons(vs, quads)


def aabb_overlap(alo, ahi, blo, bhi):
    return all(alo[i] <= bhi[i] and blo[i] <= ahi[i] for i in range(3))


def aabb_inside(lo, hi, blo, bhi):
    return all(blo[i] >= lo[i] and bhi[i] <= hi[i] for i in range(3))


_inst_bbox_cache = {}
_inst_bvh_cache = {}


def cached_bbox(o):
    bb = _inst_bbox_cache.get(o.name)
    if bb is None:
        bb = _inst_bbox_cache[o.name] = instance_bbox(o)
    return bb


def cached_inst_bvh(o):
    t = _inst_bvh_cache.get(o.name)
    if t is None:
        vs, ps = [], []
        for me, mw in instance_parts(o):
            _mesh_into(vs, ps, me, mw)
        t = _inst_bvh_cache[o.name] = BVHTree.FromPolygons(vs, ps) if ps else None
    return t


def map_of(o):
    """Map id of an object via its collections (MAPS subcollections, or Mobs_/NPCs_ <slug> collections)."""
    mid = next((coll_map.get(c.name) for c in o.users_collection if c.name in coll_map), None)
    if mid is None:
        mid = next((m for c in o.users_collection for m, mc in map_colls.items() if c.name.endswith("_" + mc.name)),
                   None)
    return mid


def to_local_exact(mc, v):
    ox, oy, _oz = mc.get("origin", (0, 0, 0))
    yaw = math.radians(mc.get("yaw", 0.0))
    dx, dy = v.x - ox, v.y - oy
    return dx * math.cos(yaw) + dy * math.sin(yaw), -dx * math.sin(yaw) + dy * math.cos(yaw)


def to_local(mc, v):
    x, y = to_local_exact(mc, v)
    return round(x, 1), round(y, 1)


# ---------------------------------------------------------------- floating props
# An instance passes when (1) its origin rests on walkable ground (<= FLOAT_GAP above it), or (2) its bounding
# box comes within ATTACH_TOL of any terrain/architecture surface: a plain map/world mesh (library sources at the
# origin are excluded) or another solid instance of the same map (walls, houses, posts, crates, trees), or (3) it
# is tagged wall_mounted / vine, embedded on purpose (Rock_Cliff_Stone), or a deliberate hoverer (butterflies).
# Checked: map dressing (_Vegetation/_Props/_Architecture), mobs, NPCs and the trail dressing in World_Trails.
FLOAT_COLLS = ("_Vegetation", "_Props", "_Architecture")


def sec_floating():
    ground_objs = [o for o in bpy.data.objects if o.type == "MESH" and (o.get("walkable") or any(
        k in o.name for k in ("_Cap", "Ramp", "Stair", "Deck", "Bridge", "Room_Floor", "Trail_", "Island_Ground",
                              "Lake_Shore", "Path", "Dock", "Pier")))]
    gv, gp = [], []
    for o in ground_objs:
        _mesh_into(gv, gp, o.data, o.matrix_world)
    bvh = BVHTree.FromPolygons(gv, gp) if gp else None
    av, ap = [], []
    for o in bpy.data.objects:
        if o.type != "MESH" or not o.users_collection or "asset" in o.keys():
            continue  # library sources all sit at the origin
        if in_debug(o):
            continue
        _mesh_into(av, ap, o.data, o.matrix_world)
    attach_bvh = BVHTree.FromPolygons(av, ap) if ap else None
    solid_by_group = {}  # map id (or TRAIL_COLL) -> solid instances that props may rest against
    for o in bpy.data.objects:
        if o.instance_type != "COLLECTION" or o.instance_collection is None:
            continue
        if any(c.name == TRAIL_COLL for c in o.users_collection):
            grp = TRAIL_COLL
        else:
            grp = next((coll_map.get(c.name) for c in o.users_collection if c.name in coll_map), None)
            if grp is None or not any(c.name.endswith(FLOAT_COLLS) for c in o.users_collection):
                continue
        if asset_tags(o.instance_collection.name) & NON_SOLID_TAGS:
            continue
        solid_by_group.setdefault(grp, []).append(o)

    def float_exempt(o, name):
        if name.startswith(FLOAT_SKIP_PREFIX) or "butterfly" in name.lower():
            return True
        tags = asset_tags(name)
        return (name in EMBEDDED_ASSETS or "vine" in tags or "wall_mounted" in tags or bool(o.get("wall_mounted"))
                or bool(o.instance_collection.get("wall_mounted")))

    def attached(o, grp):
        lo, hi = cached_bbox(o)
        t = Vector((ATTACH_TOL,) * 3)
        elo, ehi = lo - t, hi + t
        box = box_bvh(elo, ehi)
        if attach_bvh is not None:
            if attach_bvh.overlap(box):
                return "surface"
            centre = (lo + hi) * 0.5
            hit = attach_bvh.find_nearest(centre, (hi - lo).length * 0.5 + ATTACH_TOL)
            if hit[0] is not None and aabb_inside(elo, ehi, hit[0], hit[0]):
                return "surface"
        for other in solid_by_group.get(grp, ()):
            if other is o:
                continue
            olo, ohi = cached_bbox(other)
            if not aabb_overlap(elo, ehi, olo, ohi):
                continue
            if aabb_inside(elo, ehi, olo, ohi):
                return other.name
            ob = cached_inst_bvh(other)
            if ob is not None and ob.overlap(box):
                return other.name
        return None

    floating = []
    n_checked = 0
    n_attached = 0
    n_trail = 0
    if bvh is not None:
        for o in bpy.data.objects:
            if o.instance_type != "COLLECTION" or o.instance_collection is None:
                continue
            on_trail = any(c.name == TRAIL_COLL for c in o.users_collection)
            if not on_trail and not any(c.name.endswith(FLOAT_COLLS) or c.name.startswith(("Mobs_", "NPCs_"))
                                        for c in o.users_collection):
                continue
            name = o.instance_collection.name
            if float_exempt(o, name):
                continue
            n_checked += 1
            n_trail += on_trail
            p = o.matrix_world.translation
            hit = bvh.ray_cast(p + Vector((0, 0, 0.6)), Vector((0, 0, -1)), 50.0)
            if hit[0] is not None and (p.z - hit[0].z) <= FLOAT_GAP:
                continue
            # mobs and NPCs stand on the ground: only terrain/architecture meshes count for them, never a
            # neighbouring tree or prop (a snail touching a pine canopy is floating)
            grp = TRAIL_COLL if on_trail else next((coll_map.get(c.name) for c in o.users_collection
                                                    if c.name in coll_map), None)
            if attached(o, grp):
                n_attached += 1
                continue
            gap = None if hit[0] is None else round(p.z - hit[0].z, 2)
            where = TRAIL_COLL if on_trail else map_of(o)
            floating.append({"object": o.name, "asset": name, "map": where, "gap": gap})
    check("floating_props", len(floating) == 0,
          f"{len(floating)} of {n_checked} instances ({n_trail} trail dressing) neither on walkable ground nor "
          f"within {ATTACH_TOL} m of a surface ({n_attached} rest against walls/props)")
    for f in floating[:80]:
        where = "trail" if f["map"] == TRAIL_COLL else f"map {f['map']}"
        issue("floating", "medium", f"{where}: {f['object']} ({f['asset']}) floats (gap {f['gap']})")
    report["stats"]["floating"] = floating


run("floating_props", sec_floating)


# ---------------------------------------------------------------- props near route centrelines
def map_routes(mid, mc):
    """World-space route polylines of a map: its DEBUG Route_* curves (3D, on the ground); falls back to
    routes_json (2D local) with no height."""
    slug = mc.name
    dbg = bpy.data.collections.get(f"Debug_{slug}")
    out = []
    if dbg is not None:
        for ob in dbg.all_objects:
            if ob.type == "CURVE" and "Route_" in ob.name:
                rname = ob.name.split("Route_", 1)[1]
                for sp in ob.data.splines:
                    pts = [ob.matrix_world @ Vector(p.co[:3]) for p in sp.points]
                    if len(pts) >= 2:
                        out.append((rname, pts, True))
    if not out and mc.get("routes_json"):
        ox, oy, oz = mc.get("origin", (0, 0, 0))
        yaw = math.radians(mc.get("yaw", 0.0))
        c, s = math.cos(yaw), math.sin(yaw)
        for r in json.loads(mc["routes_json"]):
            pts = [Vector((ox + x * c - y * s, oy + x * s + y * c, oz)) for x, y in r["pts"]]
            if len(pts) >= 2:
                out.append((r["name"], pts, False))
    return out


def _seg_closest(p, a, b):
    dx, dy = b.x - a.x, b.y - a.y
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / L2))
    return t, math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))


def route_samples(ob, rsegs, pad):
    """Route centreline samples (every 0.4 m) within pad of the prop's xy bounding box."""
    lo, hi = cached_bbox(ob)
    samples = []
    for rname, a, b in rsegs:
        L = math.hypot(b.x - a.x, b.y - a.y)
        n = max(1, int(L / 0.4))
        for k in range(n + 1):
            s = a.lerp(b, k / n)
            if lo.x - pad <= s.x <= hi.x + pad and lo.y - pad <= s.y <= hi.y + pad:
                samples.append((rname, s))
    return samples


def walked_over(ob, samples):
    """A perch the route walks on (crate lids, shelves, tank tops): the route passes over the prop's top."""
    lo, hi = cached_bbox(ob)
    return any(lo.x <= s.x <= hi.x and lo.y <= s.y <= hi.y and s.z - ROUTE_LIFT >= hi.z - 0.35 for _r, s in samples)


def body_clearance(ob, samples, radius):
    """(distance, route, sample) of the prop's solid geometry closest to the route centreline at body height
    (BODY_Z above the walk surface), or None when nothing of it is within radius there: rugs and deck frames
    under the walk surface, eaves and arch tops overhead, and posts beyond the corridor don't count."""
    tree = cached_inst_bvh(ob)
    if tree is None:
        return None
    best = None
    query = max(radius, NEAR_ROUTE_M)  # 3D search radius; the xy distance is filtered against radius below
    for rname, s in samples:
        for h in (0.35, 0.8, 1.3):
            hit = tree.find_nearest(s + Vector((0, 0, h)), query)
            if hit[0] is None:
                continue
            zr = hit[0].z - (s.z - ROUTE_LIFT)
            d = math.hypot(hit[0].x - s.x, hit[0].y - s.y)
            if BODY_Z[0] <= zr <= BODY_Z[1] and d < radius and (best is None or d < best[0]):
                best = (d, rname, s)
    return best


def archway(ob, samples, asset):
    """The route passes through the prop: at least two centreline samples inside its xy box, every one of them
    with a clear body column (nothing from BODY_Z[0] to BODY_Z[1] above the walk surface), and the prop spans
    the route overhead there (a lintel / canopy) or is arch-like by name (arch, gate, trellis, ...)."""
    tree = cached_inst_bvh(ob)
    if tree is None:
        return False
    lo, hi = cached_bbox(ob)
    inside = [s for _r, s in samples if lo.x <= s.x <= hi.x and lo.y <= s.y <= hi.y]
    if len(inside) < 2:
        return False
    up = Vector((0, 0, 1))
    overhead = False
    for s in inside:
        surf = s.z - ROUTE_LIFT
        if tree.ray_cast(Vector((s.x, s.y, surf + BODY_Z[0])), up, BODY_Z[1] - BODY_Z[0])[0] is not None:
            return False
        if not overhead:
            overhead = tree.ray_cast(Vector((s.x, s.y, surf + BODY_Z[1])), up, 8.0)[0] is not None
    return overhead or any(w in asset.lower() for w in ARCH_WORDS)


def climbable_points():
    """(x, y) of every ladder / rope / vine (traversal uses the bounding-box centre as the climb position)."""
    out = []
    for o in bpy.data.objects:
        if "climbable" in o.keys():
            cs = [o.matrix_world @ Vector(c) for c in o.bound_box]
            out.append((sum(c.x for c in cs) / 8, sum(c.y for c in cs) / 8))
    return out


def sec_props_near_routes():
    climbs = climbable_points()
    near_routes = []
    exempt = []
    for mid, mc in sorted(map_colls.items()):
        routes = map_routes(mid, mc)
        if not routes:
            continue
        interior = LY.MAPS.get(mid, {}).get("kind") == "interior"
        radius = INTERIOR_CLEAR_M if interior else NEAR_ROUTE_M
        segs = [(rname, a, b, has_z) for rname, pts, has_z in routes for a, b in zip(pts, pts[1:])]
        for sub in [mc] + list(mc.children_recursive):
            if not sub.name.endswith(FLOAT_COLLS):
                continue
            for ob in sub.objects:
                if ob.instance_type != "COLLECTION" or ob.instance_collection is None or ob.get("scattered"):
                    continue  # scattered clutter on a route is auto-cleared at build time
                asset = ob.instance_collection.name
                info = REGISTRY.get(asset, {})
                if info.get("footprint", 1.0) < NEAR_ROUTE_FOOTPRINT or is_passable(ob, asset):
                    continue
                if info.get("category") in ("Markers", "Monsters", "Characters"):
                    continue
                if "portal_door" in asset_tags(asset) or "door" in asset.lower():
                    continue  # the door / gate a route leads to
                p = ob.matrix_world.translation
                best, near, flat = None, [], False
                for rname, a, b, has_z in segs:
                    t, d = _seg_closest(p, a, b)
                    if has_z and abs(p.z - (a.z + t * (b.z - a.z))) > NEAR_ROUTE_DZ:
                        continue  # on another tier
                    if d < NEAR_ROUTE_M:
                        near.append((rname, a, b))
                        flat = flat or not has_z
                        if best is None or d < best[0]:
                            best = (d, rname, a, b, t)
                if best is None:
                    continue
                row = {"map": mid, "object": ob.name, "asset": asset, "route": best[1],
                       "origin_distance_m": round(best[0], 2), "footprint": info.get("footprint"),
                       "local_xy": to_local(mc, p)}
                if flat:  # no route heights (routes_json fallback): cannot grade by body clearance
                    near_routes.append({**row, "body_clearance_m": None, "grade": "low"})
                    continue
                # a climb: the nearest route segment jumps more than a step, beside a ladder / rope
                _d, _r, a, b, t = best
                cx, cy = a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)
                if abs(b.z - a.z) > MAX_STEP and any(math.hypot(lx - cx, ly - cy) < CLIMB_RADIUS for lx, ly in climbs):
                    exempt.append({**row, "reason": "climb"})
                    continue
                samples = route_samples(ob, near, radius)
                if walked_over(ob, samples):
                    exempt.append({**row, "reason": "perch the route walks over"})
                    continue
                clear = body_clearance(ob, samples, radius)
                if clear is None:
                    continue
                row["route"] = clear[1]
                row["body_clearance_m"] = round(clear[0], 2)
                if interior:
                    top = cached_bbox(ob)[1].z - (clear[2].z - ROUTE_LIFT)
                    if top < HOP_TOP_M:
                        exempt.append({**row, "reason": f"hop-able (top {top:.2f} m above the floor)"})
                        continue
                if clear[0] >= ARCH_MIN_CLEAR_M and archway(ob, samples, asset):
                    exempt.append({**row, "reason": "archway spanning the route"})
                    continue
                row["grade"] = "medium" if clear[0] < GRADE_MEDIUM_M else "low"
                near_routes.append(row)
    med = [n for n in near_routes if n["grade"] == "medium"]
    low = [n for n in near_routes if n["grade"] == "low"]
    reasons = {}
    for e in exempt:
        k = e["reason"].split(" (")[0]
        reasons[k] = reasons.get(k, 0) + 1
    check("props_near_routes", not med,
          f"{len(med)} medium (solid at body height < {GRADE_MEDIUM_M} m from a route centreline), {len(low)} low; "
          f"exempt {reasons or 'none'}; interiors use {INTERIOR_CLEAR_M} m")
    for n in sorted(near_routes, key=lambda n: (n["grade"] != "medium", n["map"])):
        body = "" if n["body_clearance_m"] is None else f", solid at body height {n['body_clearance_m']} m from it"
        issue("props_near_routes", n["grade"], f"map {n['map']}: {n['asset']} at {n['local_xy']} stands "
              f"{n['origin_distance_m']} m from route {n['route']}{body} (keep m.place props >= {NEAR_ROUTE_M} m from "
              f"route centrelines; medium below {GRADE_MEDIUM_M} m body clearance)")
    report["stats"]["props_near_routes"] = near_routes
    report["stats"]["props_near_routes_exempt"] = exempt


run("props_near_routes", sec_props_near_routes)


# ---------------------------------------------------------------- classic data fidelity
def sec_fidelity():
    """NPC and monster parity against MeowDB MS Classic (game/data/canonical/maps, via the crosswalk).

    NPCs: every MeowDB NPC of a map has exactly one proxy there, carrying its MeowDB id (meowdb_npc_id, a string)
    and name; no proxy without a MeowDB entry. Monsters: the representative proxies show only MeowDB species of the
    map, every MeowDB species with a kit proxy is represented, and every spawn region's species hints are MeowDB
    species of the map. (Iteration One checked docs/research/entities.json, the GMS v8 data, instead.)"""
    if not MEOWDB:
        check("fidelity", False, "no MeowDB canonical map data (game/data/canonical/maps + crosswalk)")
        issue("fidelity", "high", "MeowDB canonical map data missing: NPC/monster parity not checked")
        return
    npc_objs = {}
    mob_objs = {}
    for o in bpy.data.objects:
        if "npc_name" in o.keys():
            for c in o.users_collection:
                if c.name.startswith("NPCs_"):
                    npc_objs.setdefault(c.name[5:], []).append(o)
        if o.instance_type == "COLLECTION" and o.instance_collection and o.instance_collection.name.startswith("Mob_"):
            for c in o.users_collection:
                if c.name.startswith("Mobs_"):
                    mob_objs.setdefault(c.name[5:], set()).add(o.instance_collection.name)
    from misostory.kit.creatures import MOB_ASSETS
    n_npcs = 0
    for mid, m in LY.MAPS.items():
        slug = m["slug"]
        rec = MEOWDB.get(mid)
        if rec is None:
            issue("fidelity", "high", f"map {mid}: no MeowDB record via the crosswalk")
            continue
        want = {str(n["id"]): n["name"] for n in rec.get("npcs", [])}
        have = {}
        for o in npc_objs.get(slug, []):
            nid = str(o.get("meowdb_npc_id", ""))
            n_npcs += 1
            if not nid:
                issue("fidelity", "high", f"map {mid}: NPC proxy {o.name} ('{o['npc_name']}') has no meowdb_npc_id")
                continue
            if nid in have:
                issue("fidelity", "high", f"map {mid}: MeowDB NPC {nid} has two proxies")
            have[nid] = o
            if nid not in want:
                issue("fidelity", "high", f"map {mid}: NPC '{o['npc_name']}' (MeowDB id {nid}) is not a MeowDB NPC of "
                      f"this map")
            elif want[nid] != o["npc_name"]:
                issue("fidelity", "high", f"map {mid}: NPC proxy '{o['npc_name']}' carries MeowDB id {nid}, which "
                      f"MeowDB names '{want[nid]}'")
        for nid in sorted(set(want) - set(have), key=int):
            issue("fidelity", "high", f"map {mid}: MeowDB NPC {nid} '{want[nid]}' has no proxy")
        species = {mo["name"] for mo in rec.get("monsters", [])}
        want_mobs = {MOB_ASSETS[k] for k in species if k in MOB_ASSETS}
        have_m = mob_objs.get(slug, set())
        for k in sorted(want_mobs - have_m):
            issue("fidelity", "medium", f"map {mid}: MeowDB monster {k} has no representative proxy")
        for k in sorted(have_m - want_mobs):
            issue("fidelity", "high", f"map {mid}: monster proxy {k} is NOT a MeowDB species of this map")
        mc = map_colls.get(mid)
        for reg in json.loads(mc.get("spawn_regions_json", "[]")) if mc is not None else []:
            bad = [s for s in reg.get("species", []) if s not in species]
            if bad:
                issue("fidelity", "high", f"map {mid}: spawn region {reg['name']} names species {bad}, not MeowDB "
                      f"species of this map")
    report["stats"]["npc_proxies"] = n_npcs
    check("fidelity", not [i for i in report["issues"] if i["check"] == "fidelity"],
          f"{n_npcs} NPC proxies vs MeowDB {sum(len(r.get('npcs', [])) for r in MEOWDB.values())} NPCs (by MeowDB id "
          f"and name); monster proxies and spawn-region species vs MeowDB species")


run("fidelity", sec_fidelity)


# ---------------------------------------------------------------- traversal (from build report)
_ROUTE_FAIL_KEYS = ("portal_issues", "portal_unreachable", "climbable_issues", "out_of_bounds_terrain")


def sec_traversal():
    if not BR:
        check("traversal", False, f"{BR_PATH} missing")
        return
    bad = []
    for mid, info in BR.get("maps", {}).items():
        t = info.get("traversal") or {}
        if info.get("status") != "authored":
            issue("build", "high", f"map {mid} build status {info.get('status')}")
        if not t.get("ok"):
            bad.append(mid)
            n0 = len(report["issues"])
            if t.get("error"):
                last = [ln for ln in str(t["error"]).strip().splitlines() if ln.strip()]
                issue("traversal", "high", f"map {mid} traversal check raised: {last[-1] if last else t['error']}")
            for r in t.get("routes", []):
                if not r.get("ok"):
                    issue("traversal", "high", f"map {mid} route {r['route']} fails",
                          issues=r.get("issues", [])[:5])
            for p in t.get("portal_issues", []):
                issue("traversal", "high", f"map {mid} portal {p.get('portal')} not grounded")
            for p in t.get("portal_unreachable", []):
                issue("traversal", "high", f"map {mid} portal {p.get('portal')} is not reached by any route "
                      f"(nearest route point {p.get('nearest_route_point_m')} m)")
            for c in t.get("climbable_issues", []):
                issue("traversal", "high", f"map {mid} climbable {c.get('climbable')} lacks ground at "
                      f"{'foot' if not c.get('foot_ok') else 'top'}")
            for o in t.get("out_of_bounds_terrain", []):
                issue("traversal", "medium", f"map {mid} terrain {o} extends beyond the footprint")
            if len(report["issues"]) == n0 and t.get("route_groups") is None:
                issue("traversal", "high", f"map {mid} traversal not ok (no route/portal issue recorded; see "
                      f"docs/build_report.json maps.{mid}.traversal)")
        if not info.get("routes"):
            issue("traversal", "high", f"map {mid} declares no routes")
    check("traversal", not bad, f"maps failing traversal: {bad}")


run("traversal", sec_traversal)


# ---------------------------------------------------------------- route graph (traversal.check_map route_groups)
def _portal_split(t, groups, orphans):
    """Portals not all in one connected route group. Prefer explicit keys from traversal.check_map; else infer:
    the map is not ok for no other recorded reason and more than one group touches a portal."""
    for key in ("portal_split", "portals_split", "split_portals"):
        if key in t:
            return bool(t[key]), t[key]
    pg = t.get("portal_groups")
    if isinstance(pg, (list, dict)):
        n = len(pg)
        return n > 1, pg
    if t.get("ok"):
        return False, None
    if any(not r.get("ok", True) for r in t.get("routes", [])) or any(t.get(k) for k in _ROUTE_FAIL_KEYS) \
            or t.get("error"):
        return False, None
    live = [g for g in groups if g and not set(g) <= orphans]
    return len(live) > 1, live if len(live) > 1 else None


def sec_route_graph():
    have = 0
    split_maps, orphan_maps = [], []
    graph = {}
    for mid, info in (BR.get("maps", {}) if BR else {}).items():
        t = info.get("traversal") or {}
        groups = t.get("route_groups")
        if groups is None:
            continue
        have += 1
        orphans = set(t.get("orphan_routes") or [])
        graph[mid] = {"route_groups": groups, "orphan_routes": sorted(orphans)}
        orphan_groups = [g for g in groups if g and set(g) <= orphans]
        loose = orphans - {r for g in orphan_groups for r in g}
        if orphan_groups or loose:
            orphan_maps.append(mid)
        for g in orphan_groups:
            issue("orphan_routes", "medium", f"map {mid}: route group {sorted(g)} touches no portal (orphan; "
                  f"stitch it to a portal-connected route within 0.75 m xy / 0.45 m z, or via a ladder it walks)")
        if loose:
            issue("orphan_routes", "medium", f"map {mid}: orphan routes {sorted(loose)}")
        split, detail = _portal_split(t, groups, orphans)
        if split:
            split_maps.append(mid)
            issue("portal_split", "high", f"map {mid}: its portals are not all in one connected route group "
                  f"({detail if detail is not None else groups})")
    report["stats"]["route_graph"] = graph
    if not have:
        check("portal_split", True, "no route graph data in build_report (traversal.check_map route_groups); skipped")
        check("orphan_routes", True, "no route graph data in build_report; skipped")
        return
    check("portal_split", not split_maps, f"{have} maps with route groups; portals split in: {split_maps}")
    check("orphan_routes", not orphan_maps, f"maps with route groups that reach no portal: {orphan_maps}")


run("portal_split", sec_route_graph)


# ---------------------------------------------------------------- gameplay-frame scale proxies
def _project(cam, co):
    from bpy_extras.object_utils import world_to_camera_view
    v = world_to_camera_view(bpy.context.scene, cam, co)
    return v.x, v.y, v.z


def recompute_gameplay_frame(mid):
    """Same rule as MapCtx.gameplay_frame_check, from the saved scene (instance origins projected through
    CAM_<slug>_Gameplay): exterior maps need a Player_Proxy at 0.1 <= u, v <= 0.9 with z > 0; hunting maps need
    >= 2 mob proxies inside 0..1; interiors report the player only."""
    meta = LY.MAPS[mid]
    slug = meta["slug"]
    kind = meta.get("kind")
    # "player" is True when the Player_Proxy projects inside the band (as in MapCtx.gameplay_frame_check);
    # "player_uv" is None when there is no Player_Proxy at all
    out = {"ok": True, "player": False, "player_uv": None, "mobs_in_frame": 0,
           "mobs_required": FRAME_MOBS if kind == "hunting" else 0, "issues": [], "source": "recomputed"}
    cam = bpy.data.objects.get(f"CAM_{slug}_Gameplay")
    if cam is None:
        out["ok"] = False
        out["issues"].append(f"no camera CAM_{slug}_Gameplay")
        return out
    mc = map_colls.get(mid)
    L, D = meta.get("L", 0), meta.get("D", 0)
    if mc is not None and mc.get("size"):
        L, D = mc["size"][0], mc["size"][1]
    best = None
    for o in bpy.data.objects:
        src = o.instance_collection.name if o.instance_collection else o.get("asset")
        if src != "Player_Proxy" or mc is None:
            continue
        x, y = to_local_exact(mc, o.matrix_world.translation)
        if not o.name.startswith(f"{slug}_") and not (-2 <= x <= L + 2 and -2 <= y <= D + 2):
            continue
        u, v, z = _project(cam, o.matrix_world.translation)
        score = max(abs(u - 0.5), abs(v - 0.5)) if z > 0 else 9
        if best is None or score < best[0]:
            best = (score, u, v, z)
    lo, hi = FRAME_UV
    player_in = best is not None and lo <= best[1] <= hi and lo <= best[2] <= hi and best[3] > 0
    if best is not None:
        out["player"] = player_in
        out["player_uv"] = [round(best[1], 3), round(best[2], 3)]
    if kind != "interior":
        if best is None:
            out["ok"] = False
            out["issues"].append("no Player_Proxy (call m.player(x, y, rot) inside the Gameplay frame)")
        elif not player_in:
            out["ok"] = False
            out["issues"].append(f"Player_Proxy projects to uv {out['player_uv']}, outside {lo}..{hi}")
    mobs = bpy.data.collections.get(f"Mobs_{slug}")
    n_in = 0
    for o in (mobs.all_objects if mobs else ()):
        if o.instance_collection is None or not o.instance_collection.name.startswith("Mob_"):
            continue
        u, v, z = _project(cam, o.matrix_world.translation)
        n_in += 0 <= u <= 1 and 0 <= v <= 1 and z > 0
    out["mobs_in_frame"] = n_in
    if kind == "hunting" and n_in < FRAME_MOBS:
        out["ok"] = False
        out["issues"].append(f"{n_in} mob proxies inside the Gameplay frame (need {FRAME_MOBS})")
    return out


def sec_gameplay_frame():
    maps_br = BR.get("maps", {}) if BR else {}
    rows = {}
    bad = []
    n_recomputed = 0
    for mid, meta in LY.MAPS.items():
        info = maps_br.get(str(mid), {})
        gf = info.get("gameplay_frame")
        if not isinstance(gf, dict):
            if mid not in map_colls:
                continue
            gf = recompute_gameplay_frame(mid)
            n_recomputed += 1
        rows[mid] = gf
        if gf.get("ok"):
            continue
        bad.append(mid)
        kind = meta.get("kind")
        if gf.get("error"):
            last = [ln for ln in str(gf["error"]).strip().splitlines() if ln.strip()]
            issue("player_in_gameplay_frame", "high", f"map {mid}: gameplay_frame_check raised: "
                  f"{last[-1] if last else gf['error']}")
            continue
        said = False
        uv = gf.get("player_uv")
        lo, hi = FRAME_UV
        if kind != "interior" and not uv:
            issue("player_in_gameplay_frame", "high", f"map {mid}: no Player_Proxy (m.player) for the Gameplay "
                  f"scale reference")
            said = True
        elif kind != "interior" and not gf.get("player"):
            issue("player_in_gameplay_frame", "high", f"map {mid}: Player_Proxy outside the Gameplay frame "
                  f"(uv {uv}, needs {lo}..{hi} with z > 0; local {gf.get('player_local')})")
            said = True
        need = gf.get("mobs_required") or (FRAME_MOBS if kind == "hunting" else 0)
        if need and (gf.get("mobs_in_frame") or 0) < need:
            issue("player_in_gameplay_frame", "medium", f"map {mid}: {gf.get('mobs_in_frame')} mob proxies in the "
                  f"Gameplay frame (hunting maps need {need})")
            said = True
        if not said:
            issue("player_in_gameplay_frame", "high", f"map {mid}: gameplay frame not ok: "
                  f"{'; '.join(map(str, gf.get('issues') or [])) or 'no reason given'}")
    report["stats"]["gameplay_frame"] = rows
    src = f"{len(rows) - n_recomputed} from build_report, {n_recomputed} recomputed from the scene"
    check("player_in_gameplay_frame", not bad, f"maps failing: {bad} ({src}; player at {FRAME_UV[0]}..{FRAME_UV[1]}"
          f" of CAM_<slug>_Gameplay, hunting maps >= {FRAME_MOBS} mobs in frame)")


run("player_in_gameplay_frame", sec_gameplay_frame)


def _misostory_value(fname, section, key, default):
    """A value of game/data/misostory/<fname>.json (section.key), read-only; `default` when the file or key is absent.
    The runtime reads the same adaptation tables, so the validator checks what the game will do."""
    try:
        with open(os.path.join(ROOT, "game", "data", "misostory", f"{fname}.json"), encoding="utf-8") as f:
            v = json.load(f).get(section, {}).get(key)
        return default if v is None else float(v)
    except (OSError, ValueError, AttributeError):
        return default


# ---------------------------------------------------------------- the walk between maps (build_report trails)
def sec_trail_walk():
    """Every trail walked portal-to-portal both ways, against its expectation, which comes from the layout (not from
    the build report): a two-way trail must walk ok forward and reverse; a one-way trail (layout.ONE_WAY_LEDGE, the
    link whose destination anchor is arrival-only) must walk ok forward with its only drop at the ledge, and be
    blocked in reverse by an unclimbable step at the ledge face and by nothing else (a defect elsewhere on the trail
    must not hide behind the expected block). Every layout trail link must have been walked."""
    trails = BR.get("trails") if BR else None
    walks = [t for t in (trails or []) if isinstance(t, dict) and isinstance(t.get("walk"), dict)]
    if not walks:
        check("trail_walk", True, "no trail walk data in build_report (trails[i].walk); skipped")
        return

    def fmt(x):
        if not isinstance(x, dict):
            return str(x)
        rest = ", ".join(f"{k} {v}" for k, v in x.items() if k != "type")
        return f"{x.get('type', 'issue')} ({rest})"

    zone = getattr(TR, "LEDGE_ZONE_M", 1.5) if TR is not None else 1.5
    lo = TV.ledge_bounds(ROOT)[0] if TV is not None else 2.0
    bad = []
    n_two = n_one = 0
    walked_links = set()
    for i, t in enumerate(walks):
        name = t.get("trail", f"trail {i}")
        link = t.get("link") or {}
        key = (link.get("from_map"), link.get("from_portal"), link.get("to_map"), link.get("to_portal"))
        walked_links.add(key)
        # the expectation from the layout; the build report's own `expect` must agree with it
        one_way = key in LY.ONE_WAY_LEDGE or (key[2] is not None and LY.is_arrival_only(key[2], key[3]))
        want = {"forward": "ok", "reverse": "blocked" if one_way else "ok"}
        if t.get("expect") != want:
            bad.append(name)
            issue("trail_walk", "high", f"{name}: build_report expectation {t.get('expect')} disagrees with the layout "
                  f"({want}; link {key})")
            continue
        fwd, rev = t["walk"], t.get("walk_reverse")
        n_one += one_way
        n_two += not one_way
        if not fwd.get("ok"):
            bad.append(name)
            its = list(fwd.get("issues") or [])
            issue("trail_walk", "high", f"{name}: the walk between the two maps fails: "
                  f"{'; '.join(fmt(x) for x in its[:3]) or 'no detail'}{' ...' if len(its) > 3 else ''}",
                  issues=its[:10])
            continue
        if rev is None:
            bad.append(name)
            issue("trail_walk", "high", f"{name}: no reverse walk recorded (build_report trails[i].walk_reverse)")
            continue
        if one_way:
            led = t.get("ledge") or {}
            gp = (led.get("gate_plane") or {}).get("point")
            if not gp:
                bad.append(name)
                issue("trail_walk", "high", f"{name}: one-way trail without a ledge record (build_report ledge)")
                continue

            def near(it):
                return math.hypot(it["at"][0] - gp[0], it["at"][1] - gp[1]) <= zone

            drops = list(fwd.get("drops") or [])
            stray = [d for d in drops if not near(d)]
            if not drops or stray:
                bad.append(name)
                issue("trail_walk", "high", f"{name}: the forward walk must drop exactly at the ledge (within {zone} m "
                      f"of its gate-plane point): drops {drops or 'none'}")
            its = list(rev.get("issues") or [])
            face = [it for it in its if it.get("type") == "step" and it.get("dz", 0) >= lo and near(it)]
            other = [it for it in its if it not in face]
            if rev.get("ok") or not face or not led.get("reverse_blocked_at_face"):
                bad.append(name)
                issue("trail_walk", "high", f"{name}: one-way trail is NOT blocked at its ledge when walked back "
                      f"(reverse ok {rev.get('ok')}, an unclimbable step >= {lo:.2f} m within {zone} m of the face: "
                      f"{bool(face)})")
            elif other:
                bad.append(name)
                issue("trail_walk", "high", f"{name}: the walk back has issues away from the ledge face: "
                      f"{'; '.join(fmt(x) for x in other[:3])}{' ...' if len(other) > 3 else ''}", issues=other[:10])
        elif not rev.get("ok"):
            bad.append(name)
            its = list(rev.get("issues") or [])
            issue("trail_walk", "high", f"{name}: the walk back fails: "
                  f"{'; '.join(fmt(x) for x in its[:3]) or 'no detail'}{' ...' if len(its) > 3 else ''}",
                  issues=its[:10])
    # world.trails walks every layout link parent -> child (LINKS rows are (child, anchor, parent, anchor, ...))
    layout_links = {(p, pa, c, ca) for c, ca, p, pa, _g, _b in LY.LINKS}
    unwalked = sorted(layout_links - walked_links)
    for k in unwalked:
        bad.append(f"{k[0]}:{k[1]}-{k[2]}:{k[3]}")
        issue("trail_walk", "high", f"layout link {k[0]}:{k[1]} <-> {k[2]}:{k[3]} has no trail walk in build_report")
    check("trail_walk", not bad, f"{len(walks) - len(bad)}/{len(walks)} trails meet their expectation ({n_two} "
          f"two-way: ok both ways; {n_one} one-way: forward ok with its only drop at the ledge, reverse blocked at "
          f"the face and nowhere else); failing: {bad[:8]}{' ...' if len(bad) > 8 else ''}")


run("trail_walk", sec_trail_walk)


# ---------------------------------------------------------------- trails vs the runtime's containment rings
def sec_trail_ring_band():
    """Every trail stays clear of the maps' containment rings (MAP_ARCHITECTURE 4.6; the runtime's ContainmentBuilder
    walls each map at footprint + ring_offset_m, wall_thickness_m thick, open only at its gate gaps). The build
    measures it (trails.ring_clearance, build_report trails[i].ring_clearance) with the numbers of
    game/data/misostory (layout.containment_params); this check recomputes those numbers, so a stale build report
    fails, and grades the result:

    * high: a ring wall within the controller's capsule radius of a trail's centreline away from its own gaps (it
      stands across the walkable top: a walk along the trail stalls, as on 000001012 -> 000001014 before it was
      re-routed), or the centreline inside another map's ring line (that map's region);
    * low (listed): a wall on the ribbon's edge (closer than the half-width), or a gate jamb closer than the gap's
      half-width (the trail turns before it has left its gap): the trail is narrower there but walkable."""
    trails = [t for t in (BR.get("trails") or []) if isinstance(t, dict)]
    if not trails:
        check("trail_ring_band", True, "no trails in build_report; skipped")
        return
    cp = LY.containment_params(ROOT)
    radius = _misostory_value("presentation", "grounding", "capsule_radius_m", 0.3)
    rows, bad, n_low = [], [], 0
    for t in trails:
        name = t.get("trail", "?")
        rc = t.get("ring_clearance")
        if not isinstance(rc, dict):
            bad.append(name)
            issue("trail_ring_band", "high", f"{name}: no ring clearance in build_report (trails[i].ring_clearance)")
            continue
        if abs(rc.get("ring_offset_m", -1) - cp["ring_offset_m"]) > 1e-6 or \
                abs(rc.get("wall_thickness_m", -1) - cp["wall_thickness_m"]) > 1e-6:
            bad.append(name)
            issue("trail_ring_band", "high", f"{name}: measured against ring offset {rc.get('ring_offset_m')} m / wall "
                  f"{rc.get('wall_thickness_m')} m, the game data says {cp['ring_offset_m']} / "
                  f"{cp['wall_thickness_m']}: rebuild")
            continue
        half, gap = rc.get("half_width_m", 0.0), rc.get("gap_half_width_m", 0.0)
        for ins in rc.get("centre_inside") or []:
            bad.append(name)
            issue("trail_ring_band", "high", f"{name}: its centreline runs inside map {ins['map']}'s ring line at "
                  f"{ins['at']} (outside its own gate corridors)")
            break
        for r in rc.get("near_rings") or []:
            d, j = r.get("wall_to_centre_m"), r.get("jamb_to_centre_m")
            if d is not None and d < radius:
                bad.append(name)
                issue("trail_ring_band", "high", f"{name}: map {r['map']}'s ring wall stands across the trail, {d} m "
                      f"from its centreline at {r['at']} (a body on the centreline is {radius} m wide)")
            elif d is not None and d < half:
                n_low += 1
                issue("trail_ring_band", "low", f"{name}: map {r['map']}'s ring wall stands on the trail's edge, {d} m "
                      f"from its centreline at {r['at']} (half-width {half} m)")
            if j is not None and j < min(gap, half) - 0.05:
                n_low += 1
                issue("trail_ring_band", "low", f"{name}: map {r['map']}'s gate jamb is {j} m from the centreline at "
                      f"{r['jamb_at']} (the gap is {gap} m either side: the trail turns before leaving it)")
        rows.append({"trail": name, "half_width_m": half, "min_wall_to_centre_m": rc.get("min_wall_to_centre_m"),
                     "min_jamb_to_centre_m": rc.get("min_jamb_to_centre_m")})
    report["stats"]["trail_ring_band"] = rows
    check("trail_ring_band", not bad, f"{len(trails) - len(set(bad))}/{len(trails)} trails clear of every containment "
          f"ring wall (ring at footprint + {cp['ring_offset_m']} m, {cp['wall_thickness_m']} m thick); {n_low} "
          f"narrowings listed as low; failing: {sorted(set(bad))[:6]}")


run("trail_ring_band", sec_trail_ring_band)


# ---------------------------------------------------------------- the one-way ledge invariant (MAP_ARCHITECTURE 4.4)
def sec_one_way_ledge():
    """Every one-way link has a trail ending in a measured ledge: face on the arrival gate plane (footprint +
    GATE_OFFSET_M) within traversal.LEDGE_FACE_TOL_M across the gate width, and jump_apex_m_at_cap + step_up_m +
    LEDGE_MARGIN_M <= height <= MAX_DROP."""
    if TV is None:
        check("one_way_ledge", False, "traversal module missing")
        issue("one_way_ledge", "high", "traversal module missing: ledge invariant not checked")
        return
    lo, hi, detail = TV.ledge_bounds(ROOT)
    rows = []
    want = sorted(LY.ONE_WAY)
    for mid, name in want:
        t = next((t for t in (BR.get("trails") or []) if (t.get("ledge") or {}).get("arrival_map") == mid and
                  (t.get("ledge") or {}).get("arrival_point") == name), None)
        if t is None:
            issue("one_way_ledge", "high", f"arrival {mid}:{name}: no one-way trail with a measured ledge")
            continue
        led = t["ledge"]
        meas = led.get("measured") or {}
        h, h_max = meas.get("height_m"), meas.get("height_max_m")
        off = meas.get("face_offset_max_abs_m")
        row = {"trail": t["trail"], "height_m": h, "height_max_m": h_max, "face_offset_max_abs_m": off,
               "bounds_m": [round(lo, 3), hi], "found_all": meas.get("found")}
        rows.append(row)
        if not meas.get("found") or h is None:
            issue("one_way_ledge", "high", f"{t['trail']}: ledge face not found at every lateral sample")
            continue
        if not (lo <= h and h_max <= hi):
            issue("one_way_ledge", "high", f"{t['trail']}: ledge height {h}..{h_max} m outside [{lo:.3f}, {hi}] m")
        if off is None or off > TV.LEDGE_FACE_TOL_M:
            issue("one_way_ledge", "high", f"{t['trail']}: ledge face {off} m off the arrival gate plane "
                  f"(tolerance {TV.LEDGE_FACE_TOL_M} m)")
    report["stats"]["one_way_ledges"] = rows
    check("one_way_ledge", not [i for i in report["issues"] if i["check"] == "one_way_ledge"],
          f"{len(rows)}/{len(want)} ledges: {rows}; bounds from {detail}")


run("one_way_ledge", sec_one_way_ledge)


# ---------------------------------------------------------------- authored player spawns and spawn regions
def _local_to_world(mc, x, y):
    ox, oy, _oz = mc.get("origin", (0, 0, 0))
    yaw = math.radians(mc.get("yaw", 0.0))
    return ox + x * math.cos(yaw) - y * math.sin(yaw), oy + x * math.sin(yaw) + y * math.cos(yaw)


_GROUND_BVH = []


def _ground_bvh():
    """BVH of every walkable mesh (obj['walkable'], set by core.GroundIndex.add) in world space."""
    if not _GROUND_BVH:
        vs, ps = [], []
        for o in bpy.data.objects:
            if o.type == "MESH" and o.get("walkable"):
                _mesh_into(vs, ps, o.data, o.matrix_world)
        _GROUND_BVH.append(BVHTree.FromPolygons(vs, ps) if ps else None)
    return _GROUND_BVH[0]


def _portal_frames(mid):
    """[(name, centre Vector, inward unit 2D (x, y))] of every portal object of a map: edges use the layout anchor's
    outward normal (inward = its negative), doors their facing (the kit front, local -Y), as the runtime does."""
    out = []
    for q in bpy.data.objects:
        if "portal_name" not in q.keys() or int(q["map_id"]) != mid:
            continue
        c = q.matrix_world.translation.copy()
        if q.get("portal_kind") == "edge":
            try:
                nx, ny = LY.anchor_normal_world(mid, q["portal_name"])
                out.append((q["portal_name"], c, (-nx, -ny)))
                continue
            except (KeyError, ValueError):
                pass
        f = q.matrix_world.to_3x3() @ Vector((0.0, -1.0, 0.0))
        fl = math.hypot(f.x, f.y) or 1.0
        out.append((q["portal_name"], c, (f.x / fl, f.y / fl)))
    return out


def sec_player_spawns():
    """Every map has player_spawns[0] (m.player_spawn): one marker, grounded on walkable ground (within 0.1 m), inside
    its footprint, and with its body (the grounding capsule radius) outside every portal's press-Up trigger box (the
    runtime's box: portal_adaptations.json trigger width x depth, centred on the portal, along its inward normal). On
    an arrival-only map it stands at least GATE_OFFSET_M + the arrival inset inside the gate plane, where the arrival
    gate's spawn_transform is (MAP_ARCHITECTURE 4.4)."""
    bvh = _ground_bvh()
    half_w = _misostory_value("portal_adaptations", "trigger", "width_m", 4.5) / 2
    half_d = _misostory_value("portal_adaptations", "trigger", "depth_m", 1.6) / 2
    radius = _misostory_value("presentation", "grounding", "capsule_radius_m", 0.3)
    inset = _misostory_value("portal_adaptations", "arrival", "inset_m", 1.5)
    gate_depth = LY.GATE_OFFSET_M + inset
    markers = {}
    for o in bpy.data.objects:
        if "player_spawn_index" in o.keys():
            markers.setdefault(int(o["map_id"]), []).append(o)
    rows = {}
    for mid, m in LY.MAPS.items():
        mc = map_colls.get(mid)
        obs = markers.get(mid, [])
        idx0 = [o for o in obs if int(o["player_spawn_index"]) == 0]
        if len(idx0) != 1 or mc is None:
            issue("player_spawns", "high", f"map {mid}: {len(idx0)} player_spawns[0] markers (need exactly 1)"
                  + ("" if mc is not None else "; no map collection"))
            continue
        o = idx0[0]
        p = o.matrix_world.translation
        hit = bvh.ray_cast(p + Vector((0, 0, 0.5)), Vector((0, 0, -1)), 2.0) if bvh else (None,)
        gap = None if hit[0] is None else round(p.z - hit[0].z, 3)
        lx, ly = to_local_exact(mc, p)
        L, D = m["L"], m["D"]
        # body vs trigger box: the spawn's distance outside the box (negative = the body overlaps it)
        clear = []
        for name, c, (ix, iy) in _portal_frames(mid):
            dx, dy = p.x - c.x, p.y - c.y
            along, lat = abs(dx * ix + dy * iy), abs(-dx * iy + dy * ix)
            out_d = max(along - half_d, lat - half_w)
            clear.append((round(out_d - radius, 2), name))
        clear.sort()
        row = {"local": [round(lx, 2), round(ly, 2)], "ground_gap_m": gap,
               "trigger_clearance_m": clear[0][0] if clear else None, "nearest_trigger": clear[0][1] if clear else None}
        if gap is None or abs(gap) > 0.1:
            issue("player_spawns", "high", f"map {mid}: player_spawns[0] not on walkable ground (gap {gap})")
        if not (0.0 <= lx <= L and 0.0 <= ly <= D):
            issue("player_spawns", "high", f"map {mid}: player_spawns[0] at local ({lx:.1f}, {ly:.1f}) is outside "
                  f"the {L} x {D} m footprint")
        if clear and clear[0][0] < 0.0:
            issue("player_spawns", "high", f"map {mid}: player_spawns[0] overlaps the press-Up trigger of portal "
                  f"{clear[0][1]} by {-clear[0][0]:.2f} m (body radius {radius} m)")
        for (amid, aname) in LY.ONE_WAY:
            if amid != mid:
                continue
            ax, ay, _az = LY.MAPS[mid]["anchors"][aname]
            # the anchor's footprint edge: local outward normal n and dot(edge point, n)
            edges = {(-1, 0): (ax, 0.0), (1, 0): (L - ax, L), (0, -1): (ay, 0.0), (0, 1): (D - ay, D)}
            n = min(edges, key=lambda k: edges[k][0])
            depth = edges[n][1] - (lx * n[0] + ly * n[1]) + LY.GATE_OFFSET_M  # inward distance from the gate plane
            row["inside_gate_plane_m"] = round(depth, 2)
            if depth < gate_depth - 0.05:
                issue("player_spawns", "high", f"map {mid}: player_spawns[0] is only {depth:.2f} m inside the "
                      f"arrival gate plane of {aname} (needs >= {gate_depth} m: gate offset + arrival inset)")
        rows[mid] = row
    report["stats"]["player_spawns"] = rows
    check("player_spawns", not [i for i in report["issues"] if i["check"] == "player_spawns"],
          f"{len(rows)}/{len(LY.MAPS)} maps have a grounded player_spawns[0] inside the footprint whose body ({radius} m) "
          f"clears every press-Up trigger box ({2 * half_w} x {2 * half_d} m); arrival map spawn >= {gate_depth} m "
          f"inside its gate plane")


run("player_spawns", sec_player_spawns)


def sec_spawn_regions():
    """Every map with MeowDB monster spawns has authored spawn regions (spawn_regions_json) whose polygons hold
    walkable ground inside their z band; maps without MeowDB spawns have none."""
    bvh = _ground_bvh()
    rows = {}
    for mid, m in LY.MAPS.items():
        mc = map_colls.get(mid)
        regs = json.loads(mc.get("spawn_regions_json", "[]")) if mc is not None else []
        n_spawn = len((MEOWDB.get(mid) or {}).get("spawns", []))
        if n_spawn and not regs:
            issue("spawn_regions", "high", f"map {mid}: {n_spawn} MeowDB spawn points but no authored spawn region")
        if regs and not n_spawn:
            issue("spawn_regions", "medium", f"map {mid}: {len(regs)} spawn regions but MeowDB lists no spawns")
        oz = mc.get("origin", (0, 0, 0))[2] if mc is not None else 0.0
        out = []
        for reg in regs:
            poly = reg["polygon"]
            xs, ys = [p[0] for p in poly], [p[1] for p in poly]
            hits = total = 0
            step = 0.75
            yv = min(ys) + step / 2
            while yv < max(ys):
                xv = min(xs) + step / 2
                while xv < max(xs):
                    if _point_in_poly(xv, yv, poly):
                        total += 1
                        wx, wy = _local_to_world(mc, xv, yv)
                        zb = reg.get("z_band")
                        top = oz + (zb[1] if zb else 60.0)
                        h = bvh.ray_cast(Vector((wx, wy, top + 0.05)), Vector((0, 0, -1)), 200.0) if bvh else (None,)
                        if h[0] is not None and h[1].z > 0.5 and (not zb or zb[0] - 0.05 <= h[0].z - oz):
                            hits += 1
                    xv += step
                yv += step
            frac = hits / total if total else 0.0
            out.append({"name": reg["name"], "species": reg.get("species"), "walkable_fraction": round(frac, 2)})
            if hits == 0:
                issue("spawn_regions", "high", f"map {mid}: spawn region {reg['name']} has no walkable ground in its "
                      f"polygon / z band")
        rows[mid] = {"meowdb_spawn_points": n_spawn, "regions": out}
    report["stats"]["spawn_regions"] = rows
    n_maps = sum(1 for r in rows.values() if r["regions"])
    check("spawn_regions", not [i for i in report["issues"] if i["check"] == "spawn_regions"],
          f"{n_maps} maps with spawn regions ({sum(len(r['regions']) for r in rows.values())} regions) vs "
          f"{sum(1 for r in rows.values() if r['meowdb_spawn_points'])} maps with MeowDB spawns")


def _point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1:
            inside = not inside
    return inside


run("spawn_regions", sec_spawn_regions)


# ---------------------------------------------------------------- the band inside the containment ring (stuck slots)
RING_BAND_STEP_M = 0.5           # sample spacing along the inset ring line
RING_BAND_GATE_CLEAR_M = 1.5     # gate corridors are skipped for GATE_HALF_WIDTH_M + this either side of the anchor


def _movement_value(key, default):
    """A top-level value of game/data/misostory/movement.json (the controller's body numbers)."""
    try:
        with open(os.path.join(ROOT, "game", "data", "misostory", "movement.json"), encoding="utf-8") as f:
            v = json.load(f).get(key)
        return default if v is None else float(v)
    except (OSError, ValueError, AttributeError):
        return default


def sec_ring_band():
    """No pit inside a map's containment ring (docs/runtime/STUCK_SCAN.md). The runtime walls every map at footprint +
    ring_offset_m (ContainmentBuilder), so a player who walks off the terrain into the band between the terrain edge
    and that wall can only leave the way they came. Iteration Three's stuck-region scan found such slots at map corners
    2.3-2.6 m deep (the plinth's rounded top did not reach the ring's square corners), deeper than any jump. Every
    exterior map's ring line, inset by the body radius (the farthest a body's centre gets), is sampled every
    RING_BAND_STEP_M; gate corridors (trail ends) and RIM_EDGE sides are skipped. At each sample the highest walkable
    surface (the walkable BVH, cast from above the map) must lie no more than the controller's step_up_m below the
    map's base height: deeper (or no surface at all) is high."""
    bvh = _ground_bvh()
    cp = LY.containment_params(ROOT)
    radius = _misostory_value("presentation", "grounding", "capsule_radius_m", 0.3)
    step_up = _movement_value("step_up_m", 0.45)
    inset = cp["ring_offset_m"] - radius
    origins = LY.resolve()
    rows, n_bad = {}, 0
    for mid in LY.exterior_ids():
        m = LY.MAPS[mid]
        base = m["z"]
        gates = []
        for c, ca, p, pa, _g, _b in LY.LINKS:
            for side_map, name in ((c, ca), (p, pa)):
                if side_map == mid and name in m["anchors"]:
                    gates.append(LY.anchor_world(mid, name, origins))
        rim = LY.RIM_EDGE.get(mid)
        poly = LY.footprint_world(mid, origins, margin=inset)  # local corners (0,0) (L,0) (L,D) (0,D) grown by inset
        names = ["front", "right", "back", "left"]  # edge i runs from poly[i] to poly[i + 1]
        o = origins[mid]
        yaw = math.radians(LY.world_yaw(mid))
        beyond = {"front": lambda lx, ly: ly < 0.0, "back": lambda lx, ly: ly > m["D"],
                  "left": lambda lx, ly: lx < 0.0, "right": lambda lx, ly: lx > m["L"]}
        worst, pits = None, []
        for i in range(4):
            if rim == names[i]:
                continue
            ax, ay = poly[i]
            bx, by = poly[(i + 1) % 4]
            length = math.hypot(bx - ax, by - ay)
            n = max(1, int(math.ceil(length / RING_BAND_STEP_M)))
            for k in range(n + 1):
                t = k / n
                x, y = ax + (bx - ax) * t, ay + (by - ay) * t
                if any(math.hypot(x - g[0], y - g[1]) < LY.GATE_HALF_WIDTH_M + RING_BAND_GATE_CLEAR_M for g in gates):
                    continue
                if rim:  # the rim edge's own band (past the quay, over the island's rim) belongs to the rim
                    dx, dy = x - o[0], y - o[1]
                    lx, ly = dx * math.cos(-yaw) - dy * math.sin(-yaw), dx * math.sin(-yaw) + dy * math.cos(-yaw)
                    if beyond[rim](lx, ly):
                        continue
                h = bvh.ray_cast(Vector((x, y, base + 40.0)), Vector((0, 0, -1)), 200.0) if bvh else (None,)
                depth = None if h[0] is None else round(base - h[0].z, 2)
                if depth is not None and depth <= step_up + 0.02:
                    continue
                pits.append((x, y, depth))
                if worst is None or depth is None or (worst[2] is not None and depth > worst[2]):
                    worst = (x, y, depth)
        if pits:
            n_bad += 1
            # Report each pit run once (the samples cluster at corners), in map-local Blender coordinates.
            runs = []
            for x, y, depth in pits:
                dx, dy = x - o[0], y - o[1]
                lx, ly = dx * math.cos(-yaw) - dy * math.sin(-yaw), dx * math.sin(-yaw) + dy * math.cos(-yaw)
                if runs and math.hypot(lx - runs[-1]["last"][0], ly - runs[-1]["last"][1]) <= RING_BAND_STEP_M * 1.5:
                    runs[-1]["last"] = (lx, ly)
                    runs[-1]["n"] += 1
                    runs[-1]["depth"] = None if depth is None or runs[-1]["depth"] is None else max(depth, runs[-1]["depth"])
                    continue
                runs.append({"first": (lx, ly), "last": (lx, ly), "n": 1, "depth": depth})
            rows[mid] = [{"local_from": [round(r["first"][0], 2), round(r["first"][1], 2)],
                          "local_to": [round(r["last"][0], 2), round(r["last"][1], 2)], "samples": r["n"],
                          "depth_m": r["depth"]} for r in runs]
            for r in rows[mid]:
                issue("ring_band", "high", f"map {mid}: {r['samples']} samples of the band inside the containment ring "
                      f"from local {r['local_from']} to {r['local_to']} lie "
                      f"{'over no walkable surface' if r['depth_m'] is None else str(r['depth_m']) + ' m'} below the "
                      f"map's base (more than step_up {step_up} m): a player who drops in cannot climb out")
    report["stats"]["ring_band"] = rows
    check("ring_band", n_bad == 0, f"{len(LY.exterior_ids()) - n_bad}/{len(LY.exterior_ids())} exterior maps have "
          f"walkable ground within step_up ({step_up} m) of their base all along the ring line inset by the body "
          f"radius (footprint + {inset:.2f} m; gate corridors and rim edges skipped)")


run("ring_band", sec_ring_band)


# ---------------------------------------------------------------- exceptions the build swallowed
def _find_exceptions(node, path, out):
    if isinstance(node, dict):
        for k, v in node.items():
            low = str(k).lower()
            if ("exception" in low or "swallowed" in low) and v:
                out.append((f"{path}.{k}", v))
            elif isinstance(v, (dict, list)):
                _find_exceptions(v, f"{path}.{k}", out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            if isinstance(v, (dict, list)):
                _find_exceptions(v, f"{path}[{i}]", out)


def sec_collision_tags():
    """Every mesh of a map's Terrain, the plinths and the WORLD layer must say how it collides, by data: a walkable,
    collider, climbable or passable flag, or a collision tag (misostory.collision_tags, set by the builder that made
    it). The runtime export never reads object names; an untagged mesh there would fall back to "none" and could
    silently lose its collision (a terrace body, a rail)."""
    colls = [c for mc in map_colls.values() for c in mc.children if c.name.endswith("_Terrain")]
    for name in ("World_Plinths",):
        if bpy.data.collections.get(name) is not None:
            colls.append(bpy.data.collections[name])
    world = bpy.data.collections.get("WORLD")
    colls += list(world.children) if world else []
    seen, untagged, tagged, bad = set(), [], 0, []
    for c in colls:
        for o in c.all_objects:
            if o.type != "MESH" or o.name in seen or o.hide_render or in_debug(o):
                continue
            seen.add(o.name)
            if o.get("walkable") or o.get("collider") or "climbable" in o.keys() or o.get("passable"):
                continue
            v = o.get(CT.KEY)
            if v is None:
                untagged.append(o.name)
            elif v not in CT.CLASSES:
                bad.append(f"{o.name}={v!r}")
            else:
                tagged += 1
    for n in untagged[:40]:
        issue("collision_tags", "medium", f"{n} has no collision tag (misostory.collision_tags.tag at its builder)")
    for n in bad[:40]:
        issue("collision_tags", "medium", f"{n}: unknown collision class (expected one of {CT.CLASSES})")
    check("collision_tags", not untagged and not bad,
          f"{len(seen)} Terrain / Plinth / WORLD meshes: {tagged} tagged, the rest walkable / collider / climbable / "
          f"passable; untagged: {len(untagged)} {untagged[:6]}; unknown class: {bad[:6]}")


run("collision_tags", sec_collision_tags)


def sec_build_exceptions():
    found = []
    if BR:
        _find_exceptions(BR, "build_report", found)
    for path, v in found:
        items = v if isinstance(v, list) else [v]
        for it in items[:10]:
            record_exception(path, json.dumps(it, default=str) if not isinstance(it, str) else it,
                             severity="medium", source="build")


run("build_exceptions", sec_build_exceptions)
check("no_swallowed_exceptions", not report["exceptions"],
      f"{len(report['exceptions'])} recorded: "
      f"{sorted({e['source'] + ' ' + e['section'] for e in report['exceptions']})[:8]}")

# ---------------------------------------------------------------- write
report["stats"]["objects"] = len(bpy.data.objects)
report["stats"]["meshes"] = len(bpy.data.meshes)
report["stats"]["materials"] = len(bpy.data.materials)
sev = {"high": 0, "medium": 0, "low": 0}
for i in report["issues"]:
    sev[i["severity"]] = sev.get(i["severity"], 0) + 1
report["summary"] = sev
os.makedirs(OUT_DIR, exist_ok=True)
with open(os.path.join(OUT_DIR, "validation_report.json"), "w", encoding="utf-8", newline="\n") as f:
    json.dump(report, f, indent=1, default=str)
lines = ["# Validation report", "", f"Objects: {report['stats']['objects']}, triangles (evaluated, incl. instances): "
         f"{total_tris:,}", "", "| check | ok | detail |", "|---|---|---|"]
for k, v in report["checks"].items():
    lines.append(f"| {k} | {'yes' if v['ok'] else '**NO**'} | {v['detail'][:200]} |")
lines += ["", "## Triangle budget", "",
          f"Per map: budget {TRI_BUDGET_PER_MAP:,} (evaluated, instances included). The WORLD layer is its own line.",
          "", "| layer | triangles | budget | ok |", "|---|---|---|---|"]
slug_of = {mid: LY.MAPS[mid]["slug"] for mid in LY.MAPS}
for mid, t in sorted(tri_by_map.items(), key=lambda kv: -kv[1]):
    lines.append(f"| {mid} {slug_of.get(mid, '')} | {t:,} | {TRI_BUDGET_PER_MAP:,} | "
                 f"{'yes' if t <= TRI_BUDGET_PER_MAP else '**NO**'} |")
lines.append(f"| WORLD (plinth, hull, trails, scenery, clouds) | {world_tris:,} | {WORLD_TRI_BUDGET:,} | "
             f"{'yes' if world_tris <= WORLD_TRI_BUDGET else '**NO**'} |")
lines.append(f"| total | {total_tris:,} | | |")
lines += ["", f"## Top {TOP_ASSETS} assets by instanced triangles", "",
          "| asset | instances | tris / instance (with outline) | total |", "|---|---|---|---|"]
for a in top_assets:
    lines.append(f"| `{a['asset']}` | {a['instances']} | {a['tris_per_instance']:,} | {a['total']:,} |")
order = {"high": 0, "medium": 1, "low": 2}
issues_sorted = sorted(report["issues"], key=lambda i: order.get(i["severity"], 3))
lines += ["", f"Issues: {sev['high']} high, {sev['medium']} medium, {sev['low']} low", ""]
for i in issues_sorted[:300]:
    lines.append(f"- [{i['severity']}] {i['check']}: {i['msg']}")
if len(issues_sorted) > 300:
    lines.append(f"- ... {len(issues_sorted) - 300} more in docs/validation_report.json")
if report["exceptions"]:
    lines += ["", "## Swallowed exceptions", ""]
    for e in report["exceptions"][:30]:
        last = [ln for ln in e["traceback"].strip().splitlines() if ln.strip()]
        lines.append(f"- {e['source']} `{e['section']}`: {last[-1] if last else ''}")
with open(os.path.join(OUT_DIR, "VALIDATION.md"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("VALIDATION_SUMMARY", json.dumps(sev), json.dumps({k: v["ok"] for k, v in report["checks"].items()}))
