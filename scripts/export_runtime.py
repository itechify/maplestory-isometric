"""Blender -> Godot runtime export: glTF chunks, gameplay sidecars and simplified collision.

    "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b MapleIsland.blend \
        --python scripts/export_runtime.py -- --out game/assets/world

Options (after ``--``):
    --out DIR           output folder (created). Required.
    --only A,B          export only these chunks (map slugs, World_* names, _library); index.json is merged.
    --outlines shell    keep the inverted-hull ink outlines as real geometry (default) | none (drop them; each
                        node's extras carry ``outline`` = the shell thickness so the runtime can draw its own)
    --colors vertex     bake the procedural albedo into a vertex color layer (default) | flat (one base color
                        per material, the area mean of the bake)
    --grid 2.0          largest cell (m) allowed on upward faces before the bake; cap tops are boundary-only fans
    --no-library        skip _library.glb (portal visuals, player / NPC / monster proxy models)
    --check             analysis only (~1 min): collision classes, decimated collision triangle counts, prop hulls,
                        route checks and capsule clearance into <out>/check.json; writes no glb and no sidecar

Per chunk it writes ``<chunk>.glb`` (visual), ``<chunk>.collision.glb`` (Godot ``-colonly`` / ``-convcolonly``
nodes) and ``<chunk>.json`` (gameplay markers), plus ``index.json``. Chunks: one per MAPS collection (keyed by its
Iteration One slug; each map also takes its ``Plinth_<slug>_*`` ground and the plinth's cliff stones), one per
remaining WORLD collection, and ``_library``. DEBUG, CAMERAS, LIGHTING and the player / NPC / monster proxies are
not exported as geometry: they become sidecar markers.

Pipeline: (1) analyse every chunk on the untouched meshes: sidecar markers, collision classes, prop hulls (hulls
that block a declared route or cover a portal fall back to the exact mesh), route check; (2) write the collision
glbs; (3) cut flat cap tops on a grid, Cycles-bake the procedural albedo into a corner color layer 'Col' (batched
scenes), flatten cobble-type cell patterns to their mean, bake the ink shells into the meshes, rewrite every
material to a glTF-exportable Principled / unlit / blended one; (4) realize instances as linked duplicates and
write the visual glbs, patched for a Godot 4.7 importer bug (patch_glb_vertex_color_flags); (5) write the sidecars
and index.json. The .blend in memory is modified freely and never saved.

Coordinates: Godot = (x, z, -y) of Blender, exactly the glTF exporter's +Y-up conversion (see gxform). Rules,
measurements and known issues: docs/runtime/blender_export.md.
"""

import argparse
import importlib
import json
import math
import os
import pkgutil
import re
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

from misostory import kit  # noqa: E402  read-only: asset registry (category, footprint, tags)
from misostory import layout as LY  # noqa: E402  read-only: edge-portal anchor normals
from misostory.kit.creatures import MOB_ASSETS  # noqa: E402
from misostory import collision_tags as CT  # noqa: E402  the passable-tag registry (collision classes)

FORMAT_VERSION = 1

# ----------------------------------------------------------------------------------------------------------------
# Coordinates
# ----------------------------------------------------------------------------------------------------------------
# Blender is Z-up right-handed, Godot is Y-up right-handed; both in meters. The glTF exporter (export_yup) maps a
# Blender vector (x, y, z) to (x, z, -y): a -90 degree rotation about X. Object transforms are conjugated
# (B = C R C^T) because the mesh data is converted the same way. Cameras and lights look down their local -Z with
# +Y up in Blender, glTF and Godot alike, so their basis is C R (the exporter's extra correction node).
C3 = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)))
C4 = C3.to_4x4()


def rnd(v, n=4):
    return round(float(v), n)


def gpos(v):
    """Blender point -> Godot [x, y, z]."""
    return [rnd(v[0]), rnd(v[2]), rnd(-v[1])]


def gxform(mw, camera=False):
    """Blender world matrix -> Godot Transform3D as 12 floats: basis columns x, y, z, then origin.

    GDScript: Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
    Vector3(a[9], a[10], a[11])).
    """
    b = C3 @ mw.to_3x3()
    if not camera:
        b = b @ C3.transposed()
    o = C3 @ mw.to_translation()
    return [rnd(b[i][j], 5) for j in range(3) for i in range(3)] + [rnd(o.x), rnd(o.y), rnd(o.z)]


def gyaw(mw):
    """Godot rotation.y (degrees) of a yaw-only Blender matrix (= Blender rotation about Z)."""
    return rnd(math.degrees(mw.to_euler().z), 2)


def gxz(x, y):
    """Blender xy -> Godot [x, z] (ground-plane polygons)."""
    return [rnd(x), rnd(-y)]


# ----------------------------------------------------------------------------------------------------------------
# Small geometry helpers
# ----------------------------------------------------------------------------------------------------------------

def hull2d(points):
    pts = sorted(set((round(p[0], 4), round(p[1], 4)) for p in points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def poly_area(poly):
    a = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        a += x0 * y1 - x1 * y0
    return abs(a) * 0.5


def simplify_hull(poly, max_pts=12):
    """Visvalingam on a convex polygon: drop the vertex that removes the least area until <= max_pts."""
    poly = list(poly)
    while len(poly) > max_pts:
        best, bi = None, 0
        for i in range(len(poly)):
            a, b, c = poly[i - 1], poly[i], poly[(i + 1) % len(poly)]
            ar = abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]))
            if best is None or ar < best:
                best, bi = ar, i
        poly.pop(bi)
    return poly


def convex_overlap(a, b):
    """Separating-axis test for two convex 2D polygons."""
    for poly in (a, b):
        for i in range(len(poly)):
            x0, y0 = poly[i]
            x1, y1 = poly[(i + 1) % len(poly)]
            nx, ny = y0 - y1, x1 - x0
            pa = [nx * x + ny * y for x, y in a]
            pb = [nx * x + ny * y for x, y in b]
            if max(pa) < min(pb) or max(pb) < min(pa):
                return False
    return True


def point_in_convex(p, poly):
    sign = 0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        c = (x1 - x0) * (p[1] - y0) - (y1 - y0) * (p[0] - x0)
        if c != 0:
            s = 1 if c > 0 else -1
            if sign and s != sign:
                return False
            sign = s
    return True


def dist_to_poly(p, poly):
    if len(poly) >= 3 and point_in_convex(p, poly):
        return 0.0
    best = 1e18
    for i in range(len(poly)):
        a, b = Vector(poly[i]), Vector(poly[(i + 1) % len(poly)])
        ab = b - a
        t = max(0.0, min(1.0, (Vector(p) - a).dot(ab) / max(ab.length_squared, 1e-12)))
        best = min(best, (Vector(p) - (a + ab * t)).length)
    return best


def mesh_arrays(me, mtx=None):
    """(verts Nx3 float64 in mtx space, triangles Mx3 int) of a mesh, via loop triangles."""
    n = len(me.vertices)
    co = np.empty(n * 3, np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    if mtx is not None:
        m = np.array(mtx, dtype=np.float64)
        co = co @ m[:3, :3].T + m[:3, 3]
    me.calc_loop_triangles()
    tri = np.empty(len(me.loop_triangles) * 3, np.int64)
    me.loop_triangles.foreach_get("vertices", tri)
    return co, tri.reshape(-1, 3)


def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


# ----------------------------------------------------------------------------------------------------------------
# Scene inventory
# ----------------------------------------------------------------------------------------------------------------

def load_registry():
    """Import the kit and every map module read-only so map-local X* assets have their category/tags/footprint."""
    import misostory.maps as maps_pkg
    failed = []
    for info in pkgutil.iter_modules(maps_pkg.__path__):
        if info.name.startswith("m"):
            try:
                importlib.import_module(f"misostory.maps.{info.name}")
            except Exception as e:  # noqa: BLE001 - a broken module only loses tags; the bbox rules still apply
                failed.append(f"{info.name}: {e!r}")
    return failed


def asset_categories():
    """Asset collection name -> library category (Trees, Foliage, ..., Monsters, Characters)."""
    out = {}
    env = bpy.data.collections.get("ENVIRONMENT_ASSETS")
    for cat in (env.children if env else []):
        for a in cat.children:
            out[a.name] = cat.name
    for lib, cat in (("_MonsterLibrary", "Monsters"), ("_CharacterLibrary", "Characters")):
        c = bpy.data.collections.get(lib)
        for a in (c.children if c else []):
            out[a.name] = cat
    return out


def asset_info(name, cats):
    reg = kit.REGISTRY.get(name, {})
    return {"category": cats.get(name, reg.get("category", "Props")), "tags": set(reg.get("tags", ())),
            "footprint": reg.get("footprint")}


def source_parts(o):
    """[(mesh object, matrix relative to o)] that make up a visual item: itself, or its instanced collection."""
    if o.type == "MESH":
        return [(o, Matrix.Identity(4))]
    if o.instance_type == "COLLECTION" and o.instance_collection is not None:
        coll = o.instance_collection
        off = Matrix.Translation(-coll.instance_offset)
        return [(s, off @ s.matrix_world) for s in coll.all_objects if s.type == "MESH" and not s.hide_render]
    return []


def is_visual(o):
    if o.hide_render or o.get("collider") or not o.visible_camera:
        return False
    if any(c.hide_render for c in o.users_collection):
        return False
    return o.type == "MESH" or (o.instance_type == "COLLECTION" and o.instance_collection is not None)


def plan_chunks():
    """name -> {name, kind, coll, items: [(object, group)]}."""
    chunks = {}
    wp = bpy.data.collections.get("World_Plinths")
    plinth_objs = list(wp.objects) if wp else []
    taken = set()
    caps = {}
    for mc in bpy.data.collections["MAPS"].children:
        slug = mc.name
        items = [(o, "Misc") for o in mc.objects]
        for sub in mc.children:
            grp = sub.name[len(slug) + 1:] if sub.name.startswith(slug + "_") else sub.name
            items += [(o, grp) for o in sub.all_objects]
        for o in plinth_objs:
            if o.name.startswith(f"Plinth_{slug}_"):
                items.append((o, "Plinth"))
                taken.add(o.name)
                if o.get("terrace_part") == "cap" and o.type == "MESH":  # geo.terrace's role mark
                    caps[slug] = o
        kind = "interior" if mc.get("kind") == "interior" else "map"
        chunks[slug] = {"name": slug, "kind": kind, "coll": mc, "items": items}
    # the plinth's cliff stones are anonymous instances: give each to the nearest plinth cap (xy hull distance)
    hulls = {}
    for slug, cap in caps.items():
        co, _t = mesh_arrays(cap.data, cap.matrix_world)
        hulls[slug] = hull2d(co[:, :2].tolist())
    for o in plinth_objs:
        if o.name in taken or o.type == "MESH":
            continue
        p = o.matrix_world.translation
        best = min(((dist_to_poly((p.x, p.y), h), s) for s, h in hulls.items()), default=None)
        if best is not None and best[0] < 3.0:
            chunks[best[1]]["items"].append((o, "Plinth"))
            taken.add(o.name)
    for wc in bpy.data.collections["WORLD"].children:
        items = [(o, wc.name) for o in wc.all_objects if o.name not in taken]
        if items:
            chunks[wc.name] = {"name": wc.name, "kind": "world", "coll": wc, "items": items}
    return chunks


LIBRARY_PREFIXES = ("Portal_", "Player_", "NPC_", "Mob_")


def library_assets():
    """Asset collections of the runtime-replaced objects: portal visuals and the character / monster proxies."""
    out = []
    for path in ("Markers", "_CharacterLibrary", "_MonsterLibrary"):
        c = bpy.data.collections.get(path)
        for a in (c.children if c else []):
            if a.name.startswith(LIBRARY_PREFIXES) and a.name != "NPC_Beacon":
                out.append(a)
    return out


# ----------------------------------------------------------------------------------------------------------------
# Collision classification
# ----------------------------------------------------------------------------------------------------------------
WATER_MATS = {"M_Water"}
NO_COLLIDE_MATS = {"M_Waterfall", "M_Sea", "M_Foam"}
# Legacy name rules (before the collision-tag registry): used only by --legacy-names, to prove a rule change keeps
# the collision output identical (check.json of both runs on one .blend). The export itself never reads names.
DECOR_NAME = re.compile(r"(_Fringe|_Foam|_Splash|_Apron[AB]|_BlendTop|_BlendFoot|LilyPad|Underside|_TextMesh)"
                        r"(_\d+)?$")
SOLID_TERRAIN_NAME = re.compile(r"(_Body|_Cap|_BridgeRails|Rail[A-Z]?)(_\d+)?$")
STEP_HEIGHT = 0.45          # anything lower is stepped over (traversal.py walks 0.45 m steps)
BLOCK_TOP = 3.0             # collision prisms stop here above the asset base: tall enough that no jump clears them
BAND = (0.15, 1.6)          # the body band of the 1.5 m player: what a prop's collision is sliced from
TRUNK_BAND = (0.1, 1.0)     # trees: the trunk, never the canopy
HULL_SINK = 0.3             # prisms reach this far below the base so slopes leave no gap


def classify_mesh(o, grp, chunk_kind, legacy_names=False):
    """Non-instanced mesh -> (class, source): class 'ground' | 'wall' | 'hull' | 'veg_hull' | 'water' | None (no
    collision); source names the rule that decided it (see collision_tags).

    The class comes from data on the object, never from words in its name (MAP_ARCHITECTURE section 5 item 6):
    the authored flags (collider, climbable / passable, walkable), then the builder's tag obj["collision"]
    (misostory.collision_tags), then the materials (water / falls / foam), then the collection group's default
    (Architecture: wall; Props: hull; Vegetation: trunk hull; Terrain, Plinth and WORLD: none, i.e. the painted
    ribbons draped 2-3 cm over real ground). legacy_names=True applies the pre-registry name rules instead of the
    tag (suffixes like _Body / _Cap / _Fringe), for before / after comparisons with --check --legacy-names."""
    if o.get("collider"):
        return "ground", "collider"
    if o.get("climbable") or o.get("passable"):
        return None, "climbable/passable"
    if o.get("walkable"):
        return "ground", "walkable"
    tagged = None if legacy_names else CT.of(o)
    if tagged is not None:
        cls = {CT.NONE: None, CT.EXACT: "wall"}.get(tagged, tagged)  # a mesh's exact mesh is its wall geometry
        return cls, "tag"
    mats = {m.name for m in o.data.materials if m}
    if mats and mats <= WATER_MATS:
        return "water", "material"
    if mats and mats <= (NO_COLLIDE_MATS | WATER_MATS):
        return None, "material"
    if legacy_names:
        if DECOR_NAME.search(o.name):
            return None, "name"
        if grp in ("Terrain", "Plinth") or chunk_kind == "world":
            return ("wall" if SOLID_TERRAIN_NAME.search(o.name) else None), "name"
    if grp in ("Terrain", "Plinth") or chunk_kind == "world":
        return None, "group"
    cls = CT.GROUP_DEFAULT.get(grp)
    return cls, "group"


def instance_rule(info):
    """Collision rule of an instanced asset, or None. Thresholds are in world meters (scaled asset)."""
    cat, tags = info["category"], info["tags"]
    if cat in ("Markers", "Monsters", "Characters"):
        return None
    if tags & CT.PASSABLE_TAGS:
        return None
    if tags & CT.EXACT_TAGS:  # thin overhead dressing: the exact mesh joins the Walls trimesh, never a prism
        return {"kind": "exact"}
    if "rock" in tags and "cliff" in tags:  # stones set into terrace faces: the body wall already blocks
        return None
    if cat == "Foliage" and not (tags & {"hedge", "landmark"}):  # bushes, flowers, grass, mushrooms, stumps, logs
        return None
    if cat == "Trees":
        return {"band": TRUNK_BAND, "min_h": 1.0, "min_area": 0.02, "kind": "trunk"}
    if cat in ("Rocks", "Terrain"):
        return {"band": BAND, "min_h": 0.9, "min_area": 0.05, "kind": "rock"}
    return {"band": BAND, "min_h": STEP_HEIGHT, "min_area": 0.02, "kind": "prop"}


def band_hulls(parts, z0, z1, min_area, max_pts=12):
    """Convex 2D hulls of the geometry inside the height band [z0, z1], one per connected piece of the slice,
    overlapping pieces merged (so a house is one hull but an arch's two posts stay two). parts: [(mesh, matrix)]
    in one frame. Returns [[(x, y), ...], ...]."""
    pieces = []
    for me, mtx in parts:
        co, tri = mesh_arrays(me, mtx)
        if not len(tri):
            continue
        tz = co[tri][:, :, 2]
        tri = tri[(tz.max(1) >= z0) & (tz.min(1) <= z1)]
        if not len(tri):
            continue
        # connected components of the sliced triangles (union-find on vertex ids)
        parent = {}

        def find(a):
            while parent.setdefault(a, a) != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a

        for a, b, c in tri.tolist():
            ra, rb, rc = find(a), find(b), find(c)
            parent[rb] = ra
            parent[find(rc)] = ra
        comp = {}
        for t in tri.tolist():
            comp.setdefault(find(t[0]), []).append(t)
        for ts in comp.values():
            ts = np.array(ts)
            pts = []
            v = co[np.unique(ts)]
            inside = v[(v[:, 2] >= z0) & (v[:, 2] <= z1)]
            pts += inside[:, :2].tolist()
            for i, j in ((0, 1), (1, 2), (2, 0)):
                a, b = co[ts[:, i]], co[ts[:, j]]
                for zc in (z0, z1):
                    da, db = a[:, 2] - zc, b[:, 2] - zc
                    cr = da * db < 0
                    if cr.any():
                        t = (da[cr] / (da[cr] - db[cr]))[:, None]
                        pts += (a[cr][:, :2] + (b[cr][:, :2] - a[cr][:, :2]) * t).tolist()
            h = hull2d(pts)
            if len(h) >= 3:
                pieces.append(h)
    merged = True
    while merged and len(pieces) > 1:
        merged = False
        for i in range(len(pieces)):
            for j in range(i + 1, len(pieces)):
                if convex_overlap(pieces[i], pieces[j]):
                    pieces[i] = hull2d(pieces[i] + pieces[j])
                    pieces.pop(j)
                    merged = True
                    break
            if merged:
                break
    return [simplify_hull(h, max_pts) for h in pieces if poly_area(h) >= min_area]


# ----------------------------------------------------------------------------------------------------------------
# Per-chunk analysis: markers + collision (runs on the untouched meshes, before the bake edits them)
# ----------------------------------------------------------------------------------------------------------------

class Ctx:
    def __init__(self, args):
        self.args = args
        self.cats = asset_categories()
        self.asset_hull_cache = {}
        self.timings = {}
        self.warnings = []


def asset_extent(coll):
    """(zmin, zmax) of an asset collection in its own frame (instance offset applied)."""
    off = Matrix.Translation(-coll.instance_offset)
    zs = []
    for s in coll.all_objects:
        if s.type == "MESH" and not s.hide_render:
            m = off @ s.matrix_world
            zs += [(m @ Vector(c)).z for c in s.bound_box]
    return (min(zs), max(zs)) if zs else (0.0, 0.0)


def asset_hulls(ctx, coll, rule):
    key = (coll.name, rule["band"])
    if key not in ctx.asset_hull_cache:
        zmin, zmax = asset_extent(coll)
        off = Matrix.Translation(-coll.instance_offset)
        parts = [(s.data, off @ s.matrix_world) for s in coll.all_objects if s.type == "MESH" and not s.hide_render]
        hulls = band_hulls(parts, rule["band"][0], rule["band"][1], rule["min_area"])
        ctx.asset_hull_cache[key] = {"hulls": hulls, "z0": -HULL_SINK, "z1": min(zmax, BLOCK_TOP), "top": zmax}
    return ctx.asset_hull_cache[key]


def merge_arrays(parts, owners=None):
    """Concatenate parts into one (verts, tris). owners (list) receives (first triangle, part index) per part."""
    vs, ts, off, nt = [], [], 0, 0
    for k, (me, mw) in enumerate(parts):
        co, tri = mesh_arrays(me, mw)
        if not len(tri):
            continue
        if owners is not None:
            owners.append((nt, k))
        vs.append(co)
        ts.append(tri + off)
        off += len(co)
        nt += len(tri)
    if not vs:
        return np.zeros((0, 3)), np.zeros((0, 3), np.int64)
    return np.concatenate(vs), np.concatenate(ts)


def analyse_chunk(ctx, ch):
    """Collision geometry (Blender world space) and gameplay markers (Godot space) of one chunk."""
    kind = ch["kind"]
    classes = []  # (object, class) for non-instanced meshes
    hull_items = []  # dicts: {name, asset, hulls (2D, own frame), z0, z1, matrix, kind}
    stats = {"instances": 0, "instances_colliding": 0, "skipped_by_rule": {}}
    exact_items = []  # (name, parts) of instances whose asset is tagged collide_exact (collision_tags.EXACT_TAGS)
    class_source = {}  # mesh name -> the rule that decided its class (classify_mesh)
    lights = []
    for o, grp in ch["items"]:
        if o.type == "LIGHT":
            lights.append(o)
            continue
        if o.type == "MESH":
            c, src = classify_mesh(o, grp, kind, legacy_names=ctx.args.legacy_names)
            classes.append((o, c))
            class_source[o.name] = src
            if c in ("hull", "veg_hull"):
                zs = [(o.matrix_world @ Vector(b)).z for b in o.bound_box]
                zmin, zmax = min(zs), max(zs)
                if zmax - zmin < STEP_HEIGHT or (c == "veg_hull" and zmax - zmin < 1.0):
                    continue
                band = TRUNK_BAND if c == "veg_hull" else BAND
                hulls = band_hulls([(o.data, o.matrix_world)], zmin + band[0], zmin + band[1],
                                   0.3 if c == "veg_hull" else 0.02)
                if hulls:
                    hull_items.append({"name": o.name, "asset": None, "hulls": hulls, "z0": zmin - HULL_SINK,
                                       "z1": min(zmax, zmin + BLOCK_TOP), "matrix": Matrix.Identity(4),
                                       "kind": "mesh", "parts": [(o.data, o.matrix_world.copy())]})
            continue
        if o.instance_type != "COLLECTION" or o.instance_collection is None or not is_visual(o):
            continue
        stats["instances"] += 1
        coll = o.instance_collection
        info = asset_info(coll.name, ctx.cats)
        rule = instance_rule(info)
        if rule is None:
            k = info["category"]
            stats["skipped_by_rule"][k] = stats["skipped_by_rule"].get(k, 0) + 1
            continue
        if rule["kind"] == "exact":
            stats["instances_colliding"] += 1
            exact_items.append((o.name, [(sp.data, o.matrix_world @ rel) for sp, rel in source_parts(o)]))
            continue
        ah = asset_hulls(ctx, coll, rule)
        sz = o.matrix_world.to_scale().z
        if ah["top"] * sz < rule["min_h"] or not ah["hulls"]:
            stats["skipped_by_rule"]["low_or_thin"] = stats["skipped_by_rule"].get("low_or_thin", 0) + 1
            continue
        stats["instances_colliding"] += 1
        hull_items.append({"name": o.name, "asset": coll.name, "hulls": ah["hulls"], "z0": ah["z0"], "z1": ah["z1"],
                           "matrix": o.matrix_world.copy(), "kind": rule["kind"],
                           "parts": [(sp.data, o.matrix_world @ rel) for sp, rel in source_parts(o)]})
    for it in hull_items:  # world-space prisms: (xy polygon, z0, z1)
        it["world"] = []
        for h in it["hulls"]:
            pts = [it["matrix"] @ Vector((x, y, z)) for x, y in h for z in (it["z0"], it["z1"])]
            zs = [p.z for p in pts]
            it["world"].append(([(p.x, p.y) for p in pts[::2]], min(zs), max(zs)))
    ground_objs = [o for o, c in classes if c == "ground"]
    ground_parts = [(o.data, o.matrix_world.copy()) for o in ground_objs]
    wall_parts = [(o.data, o.matrix_world.copy()) for o, c in classes if c == "wall"]
    wall_names = [o.name for o, c in classes if c == "wall"]
    for name, parts in exact_items:
        wall_parts += parts
        wall_names += [name] * len(parts)
    owners = []
    gv, gt = merge_arrays(ground_parts, owners)
    out = {"ground": (gv, gt), "wall_parts": wall_parts, "wall_names": wall_names, "hull_items": hull_items,
           "exact_by_tag": sorted(name for name, _p in exact_items), "stats": stats, "class_source": class_source,
           "classes": {o.name: c for o, c in classes}, "water": [], "lights": lights,
           "ground_owner": ([s for s, _k in owners], [ground_objs[k] for _s, k in owners])}
    for o, c in classes:
        if c == "water":
            co, _t = mesh_arrays(o.data, o.matrix_world)
            h = hull2d(co[:, :2].tolist())
            out["water"].append({"name": o.name, "surface_y": rnd(float(co[:, 2].mean())),
                                 "outline_xz": [gxz(x, y) for x, y in h],
                                 "aabb": aabb_g(co)})
    out["authored_colliders"] = [{"name": o.name, "aabb": aabb_g(mesh_arrays(o.data, o.matrix_world)[0]),
                                  "tris": tri_count(o.data)} for o, c in classes if o.get("collider")]
    out["ground_bvh"] = BVHTree.FromPolygons(gv.tolist(), gt.tolist()) if len(gt) else None
    return out


def aabb_g(co):
    """Godot AABB {position, size} of Blender points."""
    lo, hi = co.min(0), co.max(0)
    p = [lo[0], lo[2], -hi[1]]
    s = [hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]]
    return {"position": [rnd(v) for v in p], "size": [rnd(v) for v in s]}


def ground_at(bvh, x, y, z_from, z_max_drop=50.0):
    if bvh is None:
        return None
    hit = bvh.ray_cast(Vector((x, y, z_from)), Vector((0.0, 0.0, -1.0)), z_max_drop)
    if hit[0] is None or hit[1].z < 0.2:
        return None
    return hit[0].z


def climb_marker(o, bvh):
    """Ladder / rope / vine: bottom and top points (the validator's climb position = bbox centre xy), plus the
    standing point where the climber steps off at the top (probed on the ground mesh)."""
    cs = [o.matrix_world @ Vector(c) for c in o.bound_box]
    cx = sum(c.x for c in cs) / 8
    cy = sum(c.y for c in cs) / 8
    z0, z1 = float(o["climb_z0"]), float(o["climb_z1"])
    exit_pt, best = None, None
    for rad in (0.5, 0.8, 1.1, 1.5, 2.0):
        hits = []
        for k in range(16):
            a = 2 * math.pi * k / 16
            x, y = cx + math.cos(a) * rad, cy + math.sin(a) * rad
            g = ground_at(bvh, x, y, z1 + 0.6, 1.2)
            if g is not None and abs(g - z1) < 0.35:
                hits.append((x, y, g))
        if hits:
            hx = sum(h[0] for h in hits) / len(hits)
            hy = sum(h[1] for h in hits) / len(hits)
            d = Vector((hx - cx, hy - cy))
            if d.length > 1e-3:
                d.normalize()
            best = (cx + d.x * rad, cy + d.y * rad)
            g = ground_at(bvh, best[0], best[1], z1 + 0.6, 1.2)
            exit_pt = (best[0], best[1], g if g is not None else z1)
            break
    foot = ground_at(bvh, cx, cy, z0 + 0.5, 1.5)
    return {"name": o.name, "kind": str(o["climbable"]), "descend_only": bool(o.get("descend_only", False)),
            "bottom": gpos((cx, cy, z0)), "top": gpos((cx, cy, z1)),
            "foot_ground": None if foot is None else gpos((cx, cy, foot)),
            "top_exit": None if exit_pt is None else gpos(exit_pt),
            "facing_xz": None if best is None else [rnd(best[0] - cx), rnd(-(best[1] - cy))]}


def ground_object_at(an, x, y, z):
    """The walkable mesh object right under (x, y) near height z, via the chunk ground BVH."""
    bvh = an["ground_bvh"]
    if bvh is None:
        return None
    hit = bvh.ray_cast(Vector((x, y, z + 0.5)), Vector((0.0, 0.0, -1.0)), 2.0)
    if hit[0] is None:
        return None
    import bisect
    starts, objs = an["ground_owner"]
    i = bisect.bisect_right(starts, hit[2]) - 1
    return objs[i] if i >= 0 else None


def douglas_peucker(pts, tol):
    if len(pts) < 3:
        return pts
    a, b = Vector(pts[0]), Vector(pts[-1])
    ab = b - a
    best, bi = -1.0, 0
    for i in range(1, len(pts) - 1):
        p = Vector(pts[i])
        d = abs(ab.x * (p.y - a.y) - ab.y * (p.x - a.x)) / max(ab.length, 1e-9) if ab.length > 1e-9 else (p - a).length
        if d > best:
            best, bi = d, i
    if best <= tol:
        return [pts[0], pts[-1]]
    return douglas_peucker(pts[:bi + 1], tol)[:-1] + douglas_peucker(pts[bi:], tol)


_TIER_CACHE = {}


def tier_outline(o, tol=0.3):
    """(outline [(x, y)], surface z) of a walkable mesh's upward faces: the longest boundary loop, simplified."""
    if o.name in _TIER_CACHE:
        return _TIER_CACHE[o.name]
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    bm.normal_update()
    top = {f for f in bm.faces if f.normal.z > 0.9}
    adj = {}
    for e in bm.edges:
        if sum(1 for f in e.link_faces if f in top) == 1:
            a, b = e.verts
            adj.setdefault(a, []).append(b)
            adj.setdefault(b, []).append(a)
    zs = [v.co.z for f in top for v in f.verts]
    loops, seen = [], set()
    for start in list(adj):
        if start in seen:
            continue
        loop, prev, cur = [], None, start
        while cur is not None and cur not in seen:
            seen.add(cur)
            loop.append((cur.co.x, cur.co.y))
            nxt = [v for v in adj[cur] if v is not prev and v not in seen]
            prev, cur = cur, (nxt[0] if nxt else None)
        if len(loop) >= 3:
            loops.append(loop)
    bm.free()
    if not loops:
        res = (None, None)
    else:
        loop = max(loops, key=lambda L: poly_area(L))
        res = (douglas_peucker(loop + [loop[0]], tol)[:-1], sum(zs) / len(zs) if zs else None)
    _TIER_CACHE[o.name] = res
    return res


def spawn_areas(an, by_species):
    """One area per (species, walkable tier): the outline of the ground mesh each representative proxy stands on.
    Iteration One's m.mobs() area polygons are not stored in the .blend, so the tier is the best available bound."""
    out = []
    for sp, pts in sorted(by_species.items()):
        groups = {}
        for p in pts:
            o = ground_object_at(an, *p)
            groups.setdefault(o.name if o else None, (o, []))[1].append(p)
        for name, (o, ps) in groups.items():
            outline, z = tier_outline(o) if o is not None else (None, None)
            if not outline:
                continue
            out.append({"species": sp, "ground": name, "points": len(ps), "surface_y": rnd(z),
                        "area_m2": rnd(poly_area(outline), 1), "outline_xz": [gxz(x, y) for x, y in outline]})
    return out


def camera_marker(cam, res):
    d = cam.data
    aspect = res[0] / res[1]
    fit_w = d.sensor_fit == "HORIZONTAL" or (d.sensor_fit == "AUTO" and res[0] >= res[1])
    width = d.ortho_scale if fit_w else d.ortho_scale * aspect
    fwd = cam.matrix_world.to_3x3() @ Vector((0, 0, -1))
    return {"name": cam.name, "projection": "orthogonal" if d.type == "ORTHO" else "perspective",
            "xform": gxform(cam.matrix_world, camera=True),
            "blender_ortho_scale": rnd(d.ortho_scale), "reference_aspect": rnd(aspect, 5),
            "godot_size_keep_width": rnd(width), "godot_size_keep_height": rnd(width / aspect),
            "pitch_down_deg": rnd(math.degrees(math.asin(max(-1.0, min(1.0, -fwd.z)))), 2),
            "forward": [rnd(v, 5) for v in gpos(fwd)],
            "near": rnd(d.clip_start), "far": rnd(d.clip_end)}


def load_crosswalk():
    """GMS v8 map id -> MeowDB map id string, from game/data/misostory/map_id_crosswalk.json (read-only)."""
    try:
        with open(os.path.join(ROOT, "game", "data", "misostory", "map_id_crosswalk.json"), encoding="utf-8") as f:
            return {int(r["gms_v8_id"]): str(r["meowdb_id"]) for r in json.load(f)}
    except (OSError, ValueError, KeyError):
        return {}


CROSSWALK = load_crosswalk()


def local_to_world_xy(mc, x, y):
    """Map-local (x, y) -> Blender world (x, y) through the map collection's origin and yaw."""
    org = mc.get("origin", (0, 0, 0))
    yaw = math.radians(float(mc.get("yaw", 0.0)))
    return org[0] + x * math.cos(yaw) - y * math.sin(yaw), org[1] + x * math.sin(yaw) + y * math.cos(yaw)


def spawn_region_marker(mc, reg, bvh):
    """Sidecar entry of one authored spawn region (MapCtx.spawn_region / m.mobs areas, spawn_regions_json).

    polygon_xz: the authored polygon in Godot xz; y_band: the authored local z band as Godot y (null when the
    region has none); surface_y: median walkable height inside the polygon (and band), sampled on a 0.5 m grid on
    the chunk's ground; walkable_fraction: the share of grid samples that found ground in the band."""
    base = float(mc.get("origin", (0, 0, 0))[2])
    poly = [tuple(p) for p in reg["polygon"]]
    wpoly = [local_to_world_xy(mc, x, y) for x, y in poly]
    zb = reg.get("z_band")
    top = base + (zb[1] if zb else 60.0) + 0.05
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    zs, total = [], 0
    step = 0.5
    yv = min(ys) + step / 2
    while yv < max(ys):
        xv = min(xs) + step / 2
        while xv < max(xs):
            if point_in_poly_xy(xv, yv, poly):
                total += 1
                wx, wy = local_to_world_xy(mc, xv, yv)
                hit = bvh.ray_cast(Vector((wx, wy, top)), Vector((0.0, 0.0, -1.0)), 200.0) if bvh else (None,)
                if hit[0] is not None and hit[1].z > 0.5 and (not zb or hit[0].z >= base + zb[0] - 0.05):
                    zs.append(hit[0].z)
            xv += step
        yv += step
    zs.sort()
    return {"name": reg["name"], "species": list(reg.get("species") or []), "tiers": list(reg.get("tiers") or []),
            "source": reg.get("source", ""), "proxies": int(reg.get("proxies", 0)),
            "polygon_xz": [gxz(x, y) for x, y in wpoly], "polygon_local": [[rnd(x, 3), rnd(y, 3)] for x, y in poly],
            "y_band": None if not zb else [rnd(base + zb[0]), rnd(base + zb[1])],
            "surface_y": rnd(zs[len(zs) // 2]) if zs else None, "area_m2": rnd(poly_area(poly), 1),
            "walkable_fraction": rnd(len(zs) / total, 3) if total else 0.0}


def point_in_poly_xy(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1:
            inside = not inside
    return inside


def ledge_marker(led):
    """A one-way ledge (build_report trails[i].ledge, stored on the trail mesh as trail_ledge) in Godot space."""
    gp = led["gate_plane"]
    n = gp["outward_normal"]
    meas = led.get("measured") or {}
    return {"arrival_point": led["arrival_point"], "from_map": led["from_map"], "from_portal": led["from_portal"],
            "height_m": meas.get("height_m"), "authored_height_m": led.get("authored_height_m"),
            "top_y": led.get("top_z"), "landing_y": led.get("landing_z"),
            "face_offset_from_gate_m": meas.get("face_offset_max_abs_m"),
            "gate_plane": {"point": gpos(gp["point"]), "outward_normal_xz": [rnd(n[0], 5), rnd(-n[1], 5)],
                           "offset_from_footprint_m": gp.get("offset_from_footprint_m"),
                           "half_width_m": gp.get("half_width_m")},
            "reverse_blocked_at_face": bool(led.get("reverse_blocked_at_face"))}


def trail_ledges():
    """[(trail mesh object, ledge dict)] of every one-way trail (trail_ledge on the World_Trails trail meshes)."""
    out = []
    for o in bpy.data.objects:
        if o.type == "MESH" and o.get("trail_ledge"):
            out.append((o, json.loads(o["trail_ledge"])))
    return out


def map_markers(ctx, ch, an):
    """Sidecar content for a map / interior chunk."""
    mc = ch["coll"]
    slug = ch["name"]
    res = (bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y)
    out = {"map_id": int(mc.get("map_id", -1)), "map_name": mc.get("map_name", ""), "street": mc.get("street", ""),
           "map_kind": mc.get("kind", ""), "meowdb_map_id": CROSSWALK.get(int(mc.get("map_id", -1)))}
    # footprint: the layout rectangle (local 0..L x 0..D at origin/yaw) on the map's base height
    org = Vector(mc.get("origin", (0, 0, 0)))
    yaw = math.radians(float(mc.get("yaw", 0.0)))
    L, D = mc.get("size", (0, 0))
    cyaw, syaw = math.cos(yaw), math.sin(yaw)
    rect = [(org.x + x * cyaw - y * syaw, org.y + x * syaw + y * cyaw) for x, y in ((0, 0), (L, 0), (L, D), (0, D))]
    out["footprint"] = {"outline_xz": [gxz(x, y) for x, y in rect], "base_y": rnd(org.z),
                        "local_frame": {"origin": gpos(org), "yaw_deg": rnd(math.degrees(yaw), 2),
                                        "size": [L, D]}}
    # portals
    portals = []
    pc = bpy.data.collections.get(f"Portals_{slug}")
    for o in (pc.objects if pc else []):
        if "portal_name" not in o.keys():
            continue
        normal = None
        try:
            if o.get("portal_kind") == "edge":
                nx, ny = LY.anchor_normal_world(int(o["map_id"]), o["portal_name"])
                normal = [rnd(nx, 5), rnd(-ny, 5)]
        except (KeyError, ValueError):
            pass
        one_way = bool(o.get("one_way", False))
        portals.append({"name": o["portal_name"], "map": int(o["map_id"]), "to_map": int(o["to_map"]),
                        "to_portal": o["to_portal"], "kind": o.get("portal_kind", "edge"),
                        "one_way_arrival": bool(o.get("one_way_arrival", False)),
                        "visual": o.get("asset", ""), "position": gpos(o.matrix_world.translation),
                        "yaw_deg": gyaw(o.matrix_world), "xform": gxform(o.matrix_world),
                        "anchor_normal_xz": normal,
                        # additive (Iteration Two): one-way links (to_portal "" -> arrive at player_spawns[index])
                        "one_way": one_way, "to_arrival": (o.get("to_arrival") or None) if one_way else None,
                        "to_spawn_index": 0 if one_way else None,
                        "to_meowdb_map_id": CROSSWALK.get(int(o["to_map"]))})
    out["portals"] = sorted(portals, key=lambda p: p["name"])
    # arrival-only anchors (layout.ONE_WAY): markers, not portals
    arrivals = []
    for o in (pc.objects if pc else []):
        if "arrival_name" not in o.keys():
            continue
        nx, ny = LY.anchor_normal_world(int(o["map_id"]), o["arrival_name"])
        arrivals.append({"name": o["arrival_name"], "from_map": int(o["from_map"]), "from_portal": o["from_portal"],
                         "from_meowdb_map_id": CROSSWALK.get(int(o["from_map"])),
                         "position": gpos(o.matrix_world.translation), "yaw_deg": gyaw(o.matrix_world),
                         "xform": gxform(o.matrix_world), "anchor_normal_xz": [rnd(nx, 5), rnd(-ny, 5)],
                         "spawn_index": 0})
    out["arrival_points"] = sorted(arrivals, key=lambda a: a["name"])
    out["ledges"] = [ledge_marker(led) for _o, led in trail_ledges() if int(led["arrival_map"]) == out["map_id"]]
    # NPCs
    npcs = []
    nc = bpy.data.collections.get(f"NPCs_{slug}")
    for o in (nc.objects if nc else []):
        if "npc_name" in o.keys():
            npcs.append({"name": o["npc_name"], "npc_id": int(o.get("npc_id", 0)), "role": o.get("role", ""),
                         "proxy": o.get("asset", ""), "position": gpos(o.matrix_world.translation),
                         "yaw_deg": gyaw(o.matrix_world), "xform": gxform(o.matrix_world),
                         "meowdb_npc_id": str(o.get("meowdb_npc_id", "")) or None})
    out["npcs"] = sorted(npcs, key=lambda n: (int(n["meowdb_npc_id"]) if n["meowdb_npc_id"] else 9999, n["name"]))
    # monster spawn points (the representative proxies) and derived areas
    inv = {}
    for species, asset in MOB_ASSETS.items():
        inv.setdefault(asset, species)
    spawns, by_species = [], {}
    mobc = bpy.data.collections.get(f"Mobs_{slug}")
    for o in (mobc.objects if mobc else []):
        a = o.get("asset", o.instance_collection.name if o.instance_collection else "")
        sp = inv.get(a, a)
        p = o.matrix_world.translation
        spawns.append({"species": sp, "proxy": a, "position": gpos(p), "yaw_deg": gyaw(o.matrix_world)})
        by_species.setdefault(sp, []).append((p.x, p.y, p.z))
    out["spawn_points"] = spawns
    out["spawn_areas"] = spawn_areas(an, by_species)
    out["spawn_counts_authored"] = json.loads(mc.get("spawns_json", "[]"))
    # player start (the Iteration One scale reference: one per map, inside the Gameplay frame)
    pl = bpy.data.objects.get(f"{slug}_Player_Proxy")
    out["player_start"] = None if pl is None else {"position": gpos(pl.matrix_world.translation),
                                                    "yaw_deg": gyaw(pl.matrix_world),
                                                    "xform": gxform(pl.matrix_world)}
    # authored player spawns (m.player_spawn): index == MeowDB playerSpawns[] index; [0] on every map
    sps = []
    sc_ = bpy.data.collections.get(f"PlayerSpawns_{slug}")
    for o in (sc_.objects if sc_ else []):
        if "player_spawn_index" in o.keys():
            sps.append({"index": int(o["player_spawn_index"]), "position": gpos(o.matrix_world.translation),
                        "yaw_deg": gyaw(o.matrix_world), "xform": gxform(o.matrix_world),
                        "note": o.get("note", ""), "source": "authored"})
    out["player_spawns"] = sorted(sps, key=lambda s: s["index"])
    # authored monster spawn regions (MapCtx.spawn_region and the m.mobs areas; spawn_areas above stays derived)
    out["spawn_regions"] = [spawn_region_marker(mc, reg, an["ground_bvh"])
                            for reg in json.loads(mc.get("spawn_regions_json", "[]"))]
    # climbables
    out["climbables"] = [climb_marker(o, an["ground_bvh"]) for o, _g in ch["items"]
                         if o.type == "MESH" and "climbable" in o.keys()]
    # traversal routes: the DEBUG ribbons are the declared routes draped on the real ground (+0.12 m)
    routes = []
    meta = {r["name"]: r for r in json.loads(mc.get("routes_json", "[]"))}
    dc = bpy.data.collections.get(f"Debug_{slug}")
    for o in (dc.objects if dc else []):
        if o.type != "CURVE" or "_Route_" not in o.name:
            continue
        name = re.sub(r"(_\d\d)?$", "", o.name.split("_Route_", 1)[1])
        pts = []
        for sp in o.data.splines:
            for p in sp.points:
                w = o.matrix_world @ Vector(p.co[:3])
                pts.append(gpos((w.x, w.y, w.z - 0.12)))
        m = meta.get(name, {})
        routes.append({"name": name, "one_way": bool(m.get("one_way", False)), "points": pts})
    out["routes"] = sorted(routes, key=lambda r: r["name"])
    # cameras
    cams = {}
    cc = bpy.data.collections.get(f"Cams_{slug}")
    for o in (cc.objects if cc else []):
        if o.type == "CAMERA":
            key = "gameplay" if o.name.endswith("_Gameplay") else ("overview" if o.name.endswith("_Overview")
                                                                    else o.name)
            cams[key] = camera_marker(o, res)
    frame = BUILD_FRAMES.get(str(out["map_id"]), {})
    if "gameplay" in cams and frame:
        cams["gameplay"]["focus_local"] = frame.get("focus")
        cams["gameplay"]["gameplay_scale"] = frame.get("scale")
    out["cameras"] = cams
    return out


def trail_entries(ch):
    """World_Trails `trails[]`: one entry per inter-map trail, from the trail mesh's trail_link tag (world.py).

    Fields: mesh, from_chunk, from_portal, to_chunk (as before), plus to_portal, one_way, parts (every mesh of the
    trail: causeway, stair flights, landings, the ledge face) and ledge (one-way trails, Godot space). Before the
    tag existed the entries were parsed from mesh names, which also listed stair flights and landings as trails."""
    slugs = {int(c.get("map_id")): c.name for c in bpy.data.collections["MAPS"].children if c.get("map_id") is not None}
    out = []
    for o, _g in ch["items"]:
        if o.type != "MESH" or not o.get("trail_link"):
            continue
        link = json.loads(o["trail_link"])
        led = json.loads(o["trail_ledge"]) if o.get("trail_ledge") else None
        out.append({"mesh": o.name, "from_chunk": slugs.get(int(link["from_map"])), "from_portal": link["from_portal"],
                    "to_chunk": slugs.get(int(link["to_map"])), "to_portal": link["to_portal"],
                    "from_map": int(link["from_map"]), "to_map": int(link["to_map"]),
                    "one_way": bool(o.get("trail_one_way", False)),
                    "parts": json.loads(o.get("trail_parts", "[]")), "ledge": ledge_marker(led) if led else None})
    return sorted(out, key=lambda t: t["mesh"])


def load_build_frames():
    """Per-map gameplay framing (GAMEPLAY_FOCUS local xy, GAMEPLAY_SCALE) from Iteration One's build report."""
    try:
        with open(os.path.join(ROOT, "docs", "build_report.json"), encoding="utf-8") as f:
            return {k: v.get("gameplay_frame") or {} for k, v in json.load(f)["maps"].items()}
    except (OSError, ValueError, KeyError):
        return {}


BUILD_FRAMES = load_build_frames()


def light_marker(o):
    d = o.data
    m = {"name": o.name, "type": d.type, "color": [rnd(c, 3) for c in d.color], "blender_energy_w": rnd(d.energy, 2),
         "xform": gxform(o.matrix_world, camera=True), "position": gpos(o.matrix_world.translation),
         "shadow": bool(getattr(d, "use_shadow", True))}
    if d.type == "SPOT":
        m["spot_angle_deg"] = rnd(math.degrees(d.spot_size), 2)
        m["spot_blend"] = rnd(d.spot_blend, 3)
    if d.type in ("POINT", "SPOT"):
        m["radius"] = rnd(getattr(d, "shadow_soft_size", 0.0), 3)
    return m


def linear_to_hex(c):
    def enc(v):
        v = max(0.0, min(1.0, float(v)))
        return v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return "#" + "".join(f"{round(enc(v) * 255):02X}" for v in c[:3])


def environment_block(scene):
    """The island's one sun and sky (LIGHTING + world), for the runtime's DirectionalLight3D / Environment."""
    env = {}
    lc = bpy.data.collections.get("LIGHTING")
    for o in (lc.objects if lc else []):
        if o.type == "LIGHT" and o.data.type == "SUN":
            fwd = o.matrix_world.to_3x3() @ Vector((0, 0, -1))
            env["sun"] = {"name": o.name, "xform": gxform(o.matrix_world, camera=True),
                          "direction": [rnd(v, 5) for v in gpos(fwd)], "color_srgb": linear_to_hex(o.data.color),
                          "blender_strength_w_m2": rnd(o.data.energy, 3),
                          "angle_deg": rnd(math.degrees(o.data.angle), 3)}
    w = scene.world
    if w and w.use_nodes:
        bgs = []
        for n in w.node_tree.nodes:
            if n.bl_idname == "ShaderNodeBackground":
                bgs.append({"node": n.name, "color_srgb": linear_to_hex(n.inputs["Color"].default_value),
                            "strength": rnd(n.inputs["Strength"].default_value, 3),
                            "color_linked": n.inputs["Color"].is_linked})
            if n.bl_idname == "ShaderNodeValToRGB":
                env["sky_gradient_srgb"] = [linear_to_hex(e.color) for e in n.color_ramp.elements]
        env["world_backgrounds"] = bgs
    env["view_transform"] = scene.view_settings.view_transform
    return env


def route_samples(markers, step=0.25, walk_flags=False):
    """Blender-space samples of every declared route: [(route name, Vector)]. With walk_flags, each sample also
    says whether its route segment is walked (no steeper than movement.json floor_max_angle_deg and no rise above
    step_up_m in one step) rather than climbed or dropped: [(route name, Vector, walked)]."""
    tan_max = math.tan(math.radians(misostory_value("movement", "", "floor_max_angle_deg", 38.0)))
    step_up = misostory_value("movement", "", "step_up_m", 0.45)
    out = []
    for r in markers.get("routes", []):
        pts = [Vector((p[0], -p[2], p[1])) for p in r["points"]]
        for a, b in zip(pts, pts[1:]):
            n = max(1, int((b - a).length / step))
            if walk_flags:
                dz, run = abs(b.z - a.z), math.hypot(b.x - a.x, b.y - a.y)
                walked = dz <= step_up or dz <= run * tan_max
                out += [(r["name"], a.lerp(b, k / n), walked) for k in range(n)]
            else:
                out += [(r["name"], a.lerp(b, k / n)) for k in range(n)]
    return out


def hull_grid(items):
    grid = {}
    for i, it in enumerate(items):
        for poly, _z0, _z1 in it["world"]:
            xs = [p[0] for p in poly]
            ys = [p[1] for p in poly]
            for gx in range(int(math.floor(min(xs) / 4)), int(math.floor(max(xs) / 4)) + 1):
                for gy in range(int(math.floor(min(ys) / 4)), int(math.floor(max(ys) / 4)) + 1):
                    grid.setdefault((gx, gy), set()).add(i)
    return grid


def hull_hit(items, grid, p, lo, hi):
    """Index of the first hull item whose prism covers point p (xy) within heights [lo, hi], or None."""
    for i in grid.get((int(math.floor(p.x / 4)), int(math.floor(p.y / 4))), ()):
        for poly, z0, z1 in items[i]["world"]:
            if z1 >= lo and z0 <= hi and point_in_convex((p.x, p.y), poly):
                return i
    return None


def climb_points(markers):
    return [(c["bottom"][0], -c["bottom"][2]) for c in markers.get("climbables", [])]


def resolve_blockers(an, markers):
    """Declared routes and portals are authoritative (Iteration One walked them over the real geometry). A prop
    hull that covers a route sample inside the body band (0.15-1.5 m above the walk surface), or a portal, is an
    over-approximation: that item collides with its exact mesh instead (it joins the Walls trimesh)."""
    items = an["hull_items"]
    grid = hull_grid(items)
    climbs = climb_points(markers)
    bad = {}
    for rname, sp in route_samples(markers):
        if any(math.hypot(sp.x - cx, sp.y - cy) < 0.8 for cx, cy in climbs):
            continue
        i = hull_hit(items, grid, sp, sp.z + 0.15, sp.z + 1.5)
        if i is not None:
            bad.setdefault(i, set()).add("route:" + rname)
    for pt in markers.get("portals", []):
        pp = Vector((pt["position"][0], -pt["position"][2], pt["position"][1]))
        i = hull_hit(items, grid, pp, pp.z + 0.15, pp.z + 1.5)
        if i is not None:
            bad.setdefault(i, set()).add("portal:" + pt["name"])
    an["exact_fallback"] = {items[i]["name"]: sorted(v) for i, v in bad.items()}
    for i in bad:
        an["wall_parts"] += items[i]["parts"]
        an["wall_names"] += [items[i]["name"]] * len(items[i]["parts"])
    an["hull_items"] = [it for i, it in enumerate(items) if i not in bad]


def finish_walls(an):
    owners = []
    wv, wt = merge_arrays(an["wall_parts"], owners)
    an["walls"] = (wv, wt)
    an["walls_bvh"] = BVHTree.FromPolygons(wv.tolist(), wt.tolist()) if len(wt) else None
    names = an.get("wall_names") or []
    an["wall_owner"] = ([s for s, _k in owners], [names[k] if k < len(names) else "?" for _s, k in owners])


def wall_name_of(an, tri_index):
    """The object whose geometry is triangle tri_index of the chunk's Walls trimesh (diagnostics)."""
    import bisect
    starts, names = an.get("wall_owner") or ([], [])
    i = bisect.bisect_right(starts, tri_index) - 1
    return names[i] if 0 <= i < len(names) else "?"


def route_block_check(an, markers):
    """Final check of the shipped collision: route samples blocked by a prop hull, or by wall geometry overhead in
    the body band (an upward ray from 0.15 m to 1.5 m). Samples within 0.8 m (xy) of a climbable are exempt.

    `offenders` counts per (route, cause); `overhead` lists every wall-overhead sample with its Godot position, the
    height of the hit above the sample, the wall object hit and the distance to the nearest climbable, so a reader
    can tell a terrace lip beside a ladder from a real overhang."""
    items = an["hull_items"]
    grid = hull_grid(items)
    climbs = climb_points(markers)
    total = blocked_hull = blocked_wall = 0
    kinds = {"step": 0, "climb_or_drop": 0, "body": 0}
    offenders = {}
    overhead = []
    bvh = an.get("walls_bvh")
    up = Vector((0.0, 0.0, 1.0))
    step_up = misostory_value("movement", "", "step_up_m", 0.45)
    for rname, sp, walked in route_samples(markers, walk_flags=True):
        total += 1
        near = min((math.hypot(sp.x - cx, sp.y - cy) for cx, cy in climbs), default=math.inf)
        if near < 0.8:
            continue
        i = hull_hit(items, grid, sp, sp.z + 0.15, sp.z + 1.5)
        if i is not None:
            blocked_hull += 1
            key = rname + " <- " + (items[i]["asset"] or items[i]["name"])
            offenders[key] = offenders.get(key, 0) + 1
            continue
        if bvh is not None:
            hit = bvh.ray_cast(sp + Vector((0, 0, 0.15)), up, 1.35)
            if hit[0] is not None:
                blocked_wall += 1
                key = rname + " <- wall overhead"
                offenders[key] = offenders.get(key, 0) + 1
                above = hit[0].z - sp.z
                # step: below the controller's floating capsule (PLAYER_AND_CAMERA "Body model": it covers
                # step_up_m .. body height), a lip the feet step onto; climb_or_drop: the sample is on a climbed or
                # dropped segment, not walked; body: a real overhang inside a walking player's body
                kind = "step" if above < step_up else ("body" if walked else "climb_or_drop")
                kinds[kind] += 1
                overhead.append({"route": rname, "at": gpos(sp), "hit_above_m": rnd(above, 3), "kind": kind,
                                 "wall": wall_name_of(an, hit[2]),
                                 "nearest_climb_m": None if near == math.inf else rnd(near, 2)})
    return {"samples": total, "blocked_by_hulls": blocked_hull, "blocked_by_walls_overhead": blocked_wall,
            "overhead_by_kind": kinds,
            "offenders": dict(sorted(offenders.items(), key=lambda kv: -kv[1])[:20]), "overhead": overhead[:40]}


def misostory_value(fname, section, key, default):
    """game/data/misostory/<fname>.json section.key (read-only; section "" = a top-level key), or default. The runtime
    reads the same tables."""
    try:
        with open(os.path.join(ROOT, "game", "data", "misostory", f"{fname}.json"), encoding="utf-8") as f:
            d = json.load(f)
            v = (d if not section else d.get(section, {})).get(key)
        return default if v is None else float(v)
    except (OSError, ValueError, AttributeError):
        return default


def capsule_checker(analysis):
    """(blockers, ground, dims) over the SHIPPED collision of every chunk in `analysis` (prop hulls after the exact
    fallback, and the Walls trimeshes).

    blockers(p, band=None): sorted names of what a vertical capsule of grounding.capsule_radius_m at Blender point p
    touches; band = (lo, hi) above p.z, by default the settle capsule (capsule_lift_m .. + capsule_height_m,
    presentation.json). ground(x, y, z): the highest walkable surface from 1 m above z to 3 m below, or None.
    dims: the capsule numbers and movement.json's body band (step_up_m .. body_height_m)."""
    r = misostory_value("presentation", "grounding", "capsule_radius_m", 0.3)
    h = misostory_value("presentation", "grounding", "capsule_height_m", 1.5)
    lift = misostory_value("presentation", "grounding", "capsule_lift_m", 0.05)
    inset = misostory_value("portal_adaptations", "arrival", "inset_m", 1.5)
    # route ends: the controller's own body (movement.json): a floating capsule from step_up_m to body_height_m
    # above the feet; anything lower is stepped onto, so only this band can trap a run that starts there
    body = (misostory_value("movement", "", "step_up_m", 0.45), misostory_value("movement", "", "body_height_m", 1.5))
    items = [it for an in analysis.values() for it in an["hull_items"]]
    grid = hull_grid(items)
    walls = [(name, an.get("walls_bvh")) for name, an in analysis.items() if an.get("walls_bvh") is not None]
    grounds = [an.get("ground_bvh") for an in analysis.values() if an.get("ground_bvh") is not None]
    dirs = [Vector((math.cos(k * math.pi / 4), math.sin(k * math.pi / 4), 0.0)) for k in range(8)]
    up = Vector((0.0, 0.0, 1.0))

    def ground(x, y, z):
        best = None
        for bvh in grounds:
            hit = bvh.ray_cast(Vector((x, y, z + 1.0)), Vector((0.0, 0.0, -1.0)), 4.0)
            if hit[0] is not None and hit[1].z > 0.2 and (best is None or hit[0].z > best):
                best = hit[0].z
        return best

    def blockers(p, band=None):
        """Names of the shipped collision a vertical capsule of radius r at p touches. band = (lo, hi) above p.z;
        default: the settle capsule (lift .. lift + h)."""
        lo, hi = (p.z + lift, p.z + lift + h) if band is None else (p.z + band[0], p.z + band[1])
        out = set()
        cells = {(int(math.floor((p.x + dx) / 4)), int(math.floor((p.y + dy) / 4)))
                 for dx in (-r, 0.0, r) for dy in (-r, 0.0, r)}
        for cell in cells:
            for i in grid.get(cell, ()):
                for poly, z0, z1 in items[i]["world"]:
                    if z1 >= lo and z0 <= hi and dist_to_poly((p.x, p.y), poly) < r:
                        out.add(items[i]["name"])
        for name, bvh in walls:
            hit = bvh.ray_cast(Vector((p.x, p.y, lo)), up, hi - lo)  # overhead / inside a solid
            if hit[0] is None:
                for zz in (lo + r, (lo + hi) / 2, hi - r):
                    if any(bvh.ray_cast(Vector((p.x, p.y, zz)), d, r)[0] is not None for d in dirs):
                        hit = (True,)
                        break
            if hit[0] is not None:
                out.add(f"{name} walls")
        return sorted(out)

    dims = {"radius_m": r, "height_m": h, "lift_m": lift, "inset_m": inset, "body_band": body}
    return blockers, ground, dims


def spawn_clearance(analysis, sidecars, partial=False):
    """Capsule clearance of every authored player spawn, every portal arrival point and every route end against the
    SHIPPED collision of every chunk in this run (prop hulls after the exact fallback, and the Walls trimeshes).

    This mirrors the runtime's static check (MapDefinitions.settle, MAP_ARCHITECTURE 4.13 L1): a capsule of
    grounding.capsule_radius_m x capsule_height_m (presentation.json), lifted capsule_lift_m above the ground, must
    be clear of blocking collision; a portal's arrival point is its anchor + arrival.inset_m (portal_adaptations.json)
    along the inward normal (edges: minus anchor_normal_xz; doors: the door's facing), grounded from 1 m above to
    3 m below. The runtime moves a blocked point to the nearest clear one and logs a warning; the source world should
    not need that. Route ends are where the runtime's route bot starts a run (both directions), so a capsule must
    stand there too. Writes `spawn_clearance` into each map / interior sidecar (additive). With --only the hulls of
    chunks outside the run are not seen (`partial` is recorded)."""
    blockers, ground, dims = capsule_checker(analysis)
    r, h, lift, inset, body = dims["radius_m"], dims["height_m"], dims["lift_m"], dims["inset_m"], dims["body_band"]

    for name, sc in sidecars.items():
        if sc.get("kind") not in ("map", "interior"):
            continue
        rows_s, rows_a = [], []
        for s in sc.get("player_spawns") or []:
            p = Vector((s["position"][0], -s["position"][2], s["position"][1]))
            b = blockers(p)
            rows_s.append({"index": s["index"], "clear": not b, "blockers": b})
        for pt in sc.get("portals") or []:
            pos = pt["position"]
            n = pt.get("anchor_normal_xz")
            if n:
                ix, iy = -n[0], n[1]  # Godot xz outward -> Blender xy inward
            else:
                x = pt["xform"]  # doors: the facing is the Godot basis z column = Blender local -Y
                ix, iy = x[6], -x[8]
            ln = math.hypot(ix, iy) or 1.0
            ax, ay = pos[0] + inset * ix / ln, -pos[2] + inset * iy / ln
            gz = ground(ax, ay, pos[1])
            if gz is None:
                rows_a.append({"portal": pt["name"], "clear": False, "grounded": False, "blockers": []})
                continue
            b = blockers(Vector((ax, ay, gz)))
            rows_a.append({"portal": pt["name"], "clear": not b, "grounded": True, "blockers": b})
        rows_r = []
        for rt in sc.get("routes") or []:
            pts = rt.get("points") or []
            for end, q in (("start", pts[0] if pts else None), ("end", pts[-1] if pts else None)):
                if q is None:
                    continue
                b = blockers(Vector((q[0], -q[2], q[1])), body)
                rows_r.append({"route": rt["name"], "end": end, "position": q, "clear": not b, "blockers": b})
        sc["spawn_clearance"] = {"capsule": {"radius_m": r, "height_m": h, "lift_m": lift}, "arrival_inset_m": inset,
                                 "partial": bool(partial), "player_spawns": rows_s, "portal_arrivals": rows_a,
                                 "route_end_body_m": [body[0], body[1]], "route_ends": rows_r}


# ----------------------------------------------------------------------------------------------------------------
# Bake: procedural albedo -> corner color attribute "Col"
# ----------------------------------------------------------------------------------------------------------------

def read_material_params(mats):
    """Emission / gloss constants that every MS_Shading material feeds its group (read before any rewiring)."""
    out = {}
    for m in mats:
        p = {"emission": 0.0, "gloss": 0.0, "shading_group": False, "cell_pattern": False}
        if m.use_nodes and m.node_tree:
            for n in m.node_tree.nodes:
                if n.bl_idname == "ShaderNodeTexVoronoi" and n.feature == "DISTANCE_TO_EDGE":
                    p["cell_pattern"] = True  # cobbles / flagstones: mortar lines a few cm wide
                if n.bl_idname == "ShaderNodeGroup" and n.node_tree and n.node_tree.name == "MS_Shading":
                    p["shading_group"] = True
                    for k in ("Emission", "Gloss"):
                        s = n.inputs.get(k)
                        if s is not None and not s.is_linked:
                            p[k.lower()] = float(s.default_value)
        out[m.name] = p
    return out


def densify_tops(me, grid, nz_min=0.6):
    """Cut upward faces on a grid (bisect planes along x and y) so a per-vertex bake can carry the large-scale
    paint across cap tops, which _curve_slab fills with boundary-only fans. Returns faces added."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    top = [f for f in bm.faces if f.normal.z > nz_min]
    if not top:
        bm.free()
        return 0
    longest = max(e.calc_length() for f in top for e in f.edges)
    area = sum(f.calc_area() for f in top)
    g = max(grid, math.sqrt(area / 6000.0))  # huge surfaces (island ground) get a coarser grid
    if longest <= g * 1.6:
        bm.free()
        return 0
    n0 = len(bm.faces)
    # merge each flat top (boundary-only fan) into n-gons first, so the grid cuts ~one piece per cell instead of
    # slicing every long fan triangle into slivers
    flat = {f for f in bm.faces if f.normal.z > 0.995}
    inner = [e for e in bm.edges if len(e.link_faces) == 2 and all(f in flat for f in e.link_faces)]
    if inner:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=[], edges=inner, delimit={"MATERIAL"})
        bm.normal_update()
        top = [f for f in bm.faces if f.normal.z > nz_min]
    for axis in (0, 1):
        # bucket each face under the grid planes it spans; a cut leaves pieces that only span later planes
        buckets = {}

        def add(f):
            cs = [v.co[axis] for v in f.verts]
            lo, hi = min(cs), max(cs)
            for k in range(int(math.floor(lo / g)) + 1, int(math.ceil(hi / g))):
                if lo < k * g - 1e-4 and hi > k * g + 1e-4:
                    buckets.setdefault(k, set()).add(f)

        for f in top:
            add(f)
        for k in sorted(buckets):
            faces = [f for f in buckets[k] if f.is_valid]
            if not faces:
                continue
            edges = list({e for f in faces for e in f.edges})
            verts = list({v for f in faces for v in f.verts})
            c = k * g
            co = Vector((c, 0, 0)) if axis == 0 else Vector((0, c, 0))
            no = Vector((1, 0, 0)) if axis == 0 else Vector((0, 1, 0))
            res = bmesh.ops.bisect_plane(bm, geom=verts + edges + faces, plane_co=co, plane_no=no, dist=1e-5)
            for el in res["geom"]:
                if isinstance(el, bmesh.types.BMFace) and el.is_valid:
                    add(el)
        bm.normal_update()
        top = [f for f in bm.faces if f.normal.z > nz_min]
    added = len(bm.faces) - n0
    bm.to_mesh(me)
    bm.free()
    return added


BAKE_BATCH = 30  # objects per Cycles bake call: each call re-syncs its whole scene per object (quadratic in
#                  the scene size) and costs ~0.5 s of session start-up, so small private scenes win (measured:
#                  141 objects take 11.7 s in one scene, 6.5 s in batches of 20, 74 s one by one)


def bake_albedo(objs, win, batch=BAKE_BATCH):
    """Cycles EMIT bake of the albedo into each mesh's 'Col' corner attribute. objs: one object per mesh."""
    ng = bpy.data.node_groups.get("MS_Shading")
    if ng is not None:  # the shared group now just emits its Albedo input
        ng.nodes.clear()
        gi = ng.nodes.new("NodeGroupInput")
        go = ng.nodes.new("NodeGroupOutput")
        em = ng.nodes.new("ShaderNodeEmission")
        ng.links.new(gi.outputs["Albedo"], em.inputs["Color"])
        ng.links.new(em.outputs[0], go.inputs["Shader"])
    home = win.scene
    for o in objs:
        o.hide_viewport = False
        for md in o.modifiers:
            md.show_render = md.show_viewport = False
        me = o.data
        ca = me.color_attributes.get("Col") or me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
    for i in range(0, len(objs), batch):
        part = objs[i:i + batch]
        sc = bpy.data.scenes.new("_RUNTIME_BAKE")
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 1
        sc.render.bake.target = "VERTEX_COLORS"
        sc.render.bake.margin = 0
        for o in part:
            sc.collection.objects.link(o)
        vl = sc.view_layers[0]
        win.scene = sc
        with bpy.context.temp_override(window=win, scene=sc, view_layer=vl, active_object=part[0], object=part[0],
                                       selected_objects=part, selected_editable_objects=part):
            for o in part:
                o.select_set(True, view_layer=vl)
            vl.objects.active = part[0]
            bpy.ops.object.bake(type="EMIT", target="VERTEX_COLORS")
        win.scene = home
        bpy.data.scenes.remove(sc)
    for o in objs:
        for md in o.modifiers:
            md.show_render = md.show_viewport = True


def flatten_cell_patterns(objs, means, names):
    """Cobble / flagstone materials (a Voronoi edge-distance mortar pattern) cannot be sampled per vertex: the
    2 m bake grid turns their mortar lines into grey speckle. Give those faces their material's mean color
    instead (a clean low-pass). Returns corners changed."""
    names = set(names)
    n = 0
    for o in objs:
        me = o.data
        ca = me.color_attributes.get("Col")
        slots = [m.name if m else "" for m in me.materials]
        if ca is None or not (names & set(slots)) or not len(me.polygons):
            continue
        col = np.empty(len(ca.data) * 4, np.float32)
        ca.data.foreach_get("color", col)
        col = col.reshape(-1, 4)
        lt = np.empty(len(me.polygons), np.int64)
        mi = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("loop_total", lt)
        me.polygons.foreach_get("material_index", mi)
        per_loop = np.repeat(mi, lt)
        for idx, name in enumerate(slots):
            if name in names and name in means:
                sel = per_loop == idx
                col[sel, :3] = means[name]
                n += int(sel.sum())
        ca.data.foreach_set("color", col.ravel())
    return n


def material_means(objs):
    """Area-ish (corner-count) mean linear albedo per material over the baked meshes."""
    acc = {}
    for o in objs:
        me = o.data
        ca = me.color_attributes.get("Col")
        if ca is None or not len(me.polygons):
            continue
        col = np.empty(len(ca.data) * 4, np.float32)
        ca.data.foreach_get("color", col)
        col = col.reshape(-1, 4)[:, :3]
        ls = np.empty(len(me.polygons), np.int64)
        lt = np.empty(len(me.polygons), np.int64)
        mi = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("loop_start", ls)
        me.polygons.foreach_get("loop_total", lt)
        me.polygons.foreach_get("material_index", mi)
        per_loop = np.repeat(mi, lt)
        for idx in np.unique(per_loop):
            if idx >= len(me.materials) or me.materials[idx] is None:
                continue
            sel = per_loop == idx
            s = col[sel].sum(0)
            a = acc.setdefault(me.materials[idx].name, [np.zeros(3), 0])
            a[0] += s
            a[1] += int(sel.sum())
    return {k: (v[0] / max(v[1], 1)).tolist() for k, v in acc.items()}


def apply_outlines(export_objs, win, mode):
    """shell: bake the SOLIDIFY ink shells into the mesh data (shared by every realized copy); none: drop them."""
    shells = {}
    n = 0
    users = [o for o in export_objs if any(md.type == "SOLIDIFY" for md in o.modifiers)]
    if not users:
        return 0
    if mode == "none":
        for o in users:
            md = next(md for md in o.modifiers if md.type == "SOLIDIFY")
            o["outline"] = rnd(md.thickness, 4)
            o.modifiers.remove(md)
        return len(users)
    home = win.scene
    ev = bpy.data.scenes.new("_RUNTIME_EVAL")
    for o in users:
        ev.collection.objects.link(o)
    vl = ev.view_layers[0]
    win.scene = ev
    with bpy.context.temp_override(window=win, scene=ev, view_layer=vl):
        dg = bpy.context.evaluated_depsgraph_get()
        for o in users:
            md = next(md for md in o.modifiers if md.type == "SOLIDIFY")
            key = (o.data.name, round(md.thickness, 5))
            if key not in shells:
                me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
                me.name = o.data.name + "_inked"
                shells[key] = me
                n += 1
            o.modifiers.clear()
            o.data = shells[key]
    win.scene = home
    bpy.data.scenes.remove(ev)
    return n


def rewrite_materials(mats, params, means, colors_mode):
    """Replace every node tree by a glTF-exportable one. Lit materials: Principled BSDF, base color = the baked
    'Col' attribute (or the material's mean albedo), roughness 0.85, emission = mean albedo x the old strength.
    Ink: unlit (Background shader -> KHR_materials_unlit). Glows / light shafts: emissive and alpha-blended."""
    out = {}
    for m in mats:
        p = params.get(m.name, {})
        mean = means.get(m.name)
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        rec = {"emission": p.get("emission", 0.0), "gloss": p.get("gloss", 0.0)}
        if m.name == "M_Outline":
            bg = nt.nodes.new("ShaderNodeBackground")
            bg.inputs["Color"].default_value = (0.024, 0.0123, 0.0070, 1.0)  # #2B1D14 linear
            nt.links.new(bg.outputs[0], o.inputs["Surface"])
            rec["kind"] = "ink_unlit"
            out[m.name] = rec
            continue
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(b.outputs[0], o.inputs["Surface"])
        b.inputs["Roughness"].default_value = max(0.35, 0.85 - 2.0 * rec["gloss"])
        c = list(mean) if mean else [0.8, 0.8, 0.8]
        blended = getattr(m, "surface_render_method", "") == "BLENDED"
        if blended or m.name.startswith("M_Portal_Glow"):
            # pure emission + transparency in Blender: a soft emissive, alpha-blended surface
            base = c if mean else [1.0, 0.85, 0.5]
            b.inputs["Base Color"].default_value = (*base, 1.0)
            b.inputs["Alpha"].default_value = 0.35
            b.inputs["Emission Color"].default_value = (*base, 1.0)
            b.inputs["Emission Strength"].default_value = 1.5
            m.surface_render_method = "BLENDED"
            rec["kind"] = "glow_blend"
            out[m.name] = rec
            continue
        if colors_mode == "vertex" and mean is not None:
            # the exporter writes the (unlinked) socket default as baseColorFactor, which multiplies COLOR_0
            b.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
            ca = nt.nodes.new("ShaderNodeVertexColor")
            ca.layer_name = "Col"
            nt.links.new(ca.outputs["Color"], b.inputs["Base Color"])
            rec["kind"] = "vertex_color"
        else:
            b.inputs["Base Color"].default_value = (*c, 1.0)
            rec["kind"] = "flat"
        if rec["emission"] > 0:
            b.inputs["Emission Color"].default_value = (*c, 1.0)
            b.inputs["Emission Strength"].default_value = rec["emission"]
        rec["mean_linear"] = [rnd(v, 4) for v in c]
        out[m.name] = rec
    return out


# ----------------------------------------------------------------------------------------------------------------
# Export
# ----------------------------------------------------------------------------------------------------------------

def export_scene_ctx(win, sc):
    win.scene = sc
    return bpy.context.temp_override(window=win, scene=sc, view_layer=sc.view_layers[0])


def gltf_export(win, sc, objs, path, visual=True, colors="vertex"):
    vl = sc.view_layers[0]
    vl.update()
    for o in list(vl.objects):
        if o is not None:
            o.select_set(False, view_layer=vl)
    for o in objs:
        o.select_set(True, view_layer=vl)
    kw = dict(filepath=path, export_format="GLB", use_selection=True, use_active_scene=True, export_apply=False,
              export_yup=True, export_cameras=False, export_lights=False, export_animations=False,
              export_skins=False, export_morph=False, export_texcoords=False, export_tangents=False)
    if visual:
        # COLOR_0 = the baked 'Col' layer, by name: the exporter's MATERIAL mode does not see the Color Attribute
        # node, and "all vertex colors" writes the layer a second time as COLOR_1
        kw.update(export_extras=True, export_normals=True, export_materials="EXPORT",
                  export_vertex_color="NAME" if colors == "vertex" else "NONE", export_vertex_color_name="Col",
                  export_all_vertex_colors=False, export_active_vertex_color_when_no_material=False,
                  export_image_format="NONE")
    else:
        kw.update(export_extras=False, export_normals=False, export_materials="NONE", export_vertex_color="NONE")
    with export_scene_ctx(win, sc):
        bpy.ops.export_scene.gltf(**kw)


def patch_glb_vertex_color_flags(path):
    """Work around Godot 4.7.2's glTF importer: gltf_document.cpp tracks ``has_vertex_color`` per mesh and tests it
    before decoding the current primitive's COLOR_0, so the first primitive of every mesh never sets
    vertex_color_use_as_albedo on its material. A material used only as some mesh's primitive 0 would import
    white. Append one unreferenced mesh whose primitives 1..n use exactly those materials (one 1 mm triangle each,
    sharing three tiny accessors): Godot parses every mesh, sets the flag on the shared materials, and never
    instances the dummy (no node points at it). Returns the number of materials fixed."""
    import struct
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    j = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen = struct.unpack_from("<I", data, off)[0]
    binc = bytearray(data[off + 8:off + 8 + blen])
    first, later = set(), set()
    for m in j.get("meshes", []):
        seen_color = False
        for p in m["primitives"]:
            if "material" in p and "COLOR_0" in p["attributes"]:
                (later if seen_color else first).add(p["material"])
            seen_color = seen_color or "COLOR_0" in p["attributes"]
    need = sorted(first - later)
    if not need:
        return 0
    while len(binc) % 4:
        binc.append(0)
    views = j.setdefault("bufferViews", [])
    accs = j.setdefault("accessors", [])

    def add(payload, acc):
        while len(binc) % 4:
            binc.append(0)
        views.append({"buffer": 0, "byteOffset": len(binc), "byteLength": len(payload)})
        binc.extend(payload)
        acc["bufferView"] = len(views) - 1
        accs.append(acc)
        return len(accs) - 1

    pos = add(struct.pack("<9f", 0, 0, 0, 0.001, 0, 0, 0, 0, 0.001),
              {"componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [0.001, 0, 0.001]})
    nrm = add(struct.pack("<9f", *([0.0, 1.0, 0.0] * 3)), {"componentType": 5126, "count": 3, "type": "VEC3"})
    col = add(struct.pack("<12f", *([1.0] * 12)), {"componentType": 5126, "count": 3, "type": "VEC4"})
    idx = add(struct.pack("<3H", 0, 2, 1), {"componentType": 5123, "count": 3, "type": "SCALAR"})
    attrs = {"POSITION": pos, "NORMAL": nrm, "COLOR_0": col}
    prims = [{"attributes": dict(attrs), "indices": idx}]  # primitive 0: sets nothing (that is the bug)
    prims += [{"attributes": dict(attrs), "indices": idx, "material": mi} for mi in need]
    j["meshes"].append({"name": "_godot_vertex_color_flags", "primitives": prims,
                        "extras": {"note": "unreferenced: works around a Godot 4.7 glTF importer bug"}})
    j["buffers"][0]["byteLength"] = len(binc)
    js = json.dumps(j, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    while len(binc) % 4:
        binc.append(0)
    total = 12 + 8 + len(js) + 8 + len(binc)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(binc), 0x004E4942))
        f.write(binc)
    return len(need)


def realize_chunk(ch, coll, cats):
    """Linked-duplicate objects for the chunk's visual items under one empty per group; returns (objects, stats)."""
    made = []
    groups = {}
    tris = shell_tris = 0
    nodes = 0
    meshes = set()

    def group_empty(grp):
        if grp not in groups:
            e = bpy.data.objects.new(f"{ch['name']}__{grp}", None)
            coll.objects.link(e)
            groups[grp] = e
            made.append(e)
        return groups[grp]

    for o, grp in ch["items"]:
        if not is_visual(o):
            continue
        parent = group_empty(grp)
        parts = source_parts(o)
        base_name = o.name
        o.name = o.name + ("__src" if o.type == "MESH" else "__inst")  # free the name for the realized copy
        for k, (s, rel) in enumerate(parts):
            name = base_name if len(parts) == 1 else f"{base_name}__{s.name.split('.')[0]}"
            dup = bpy.data.objects.new(name, s.data)
            coll.objects.link(dup)
            dup.parent = parent
            dup.matrix_world = o.matrix_world @ rel if o.type != "MESH" else o.matrix_world.copy()
            for key in ("walkable", "climbable", "climb_z0", "climb_z1", "descend_only", "passable", "outline",
                        "collision"):
                src = o if key in o.keys() else s
                if key in src.keys():
                    dup[key] = src[key]
            if o.type != "MESH":
                a = o.instance_collection.name
                dup["asset"] = a
                dup["category"] = cats.get(a, "")
                if o.get("scattered"):
                    dup["scattered"] = True
            dup["group"] = grp
            made.append(dup)
            nodes += 1
            meshes.add(s.data.name)
            tris += tri_count(s.data)
            shell_tris += outline_tris(s.data)
    return made, {"nodes": nodes, "unique_meshes": len(meshes), "tris": tris, "outline_tris": shell_tris}


_OUTLINE_TRIS = {}


def outline_tris(me):
    if me.name not in _OUTLINE_TRIS:
        idx = {i for i, m in enumerate(me.materials) if m and m.name == "M_Outline"}
        _OUTLINE_TRIS[me.name] = sum(len(p.vertices) - 2 for p in me.polygons if p.material_index in idx)
    return _OUTLINE_TRIS[me.name]


def realize_library(assets, coll, cats):
    made, info = [], []
    for a in assets:
        root = bpy.data.objects.new(a.name, None)
        coll.objects.link(root)
        made.append(root)
        off = Matrix.Translation(-a.instance_offset)
        zs = []
        for s in a.all_objects:
            if s.type != "MESH" or s.hide_render:
                continue
            dup = bpy.data.objects.new(f"{a.name}__{s.name.split('.')[0]}", s.data)
            coll.objects.link(dup)
            dup.parent = root
            dup.matrix_world = off @ s.matrix_world
            made.append(dup)
            zs += [(dup.matrix_world @ Vector(c)).z for c in s.bound_box]
        info.append({"asset": a.name, "category": cats.get(a.name, ""), "height": rnd(max(zs) - min(zs)) if zs else 0})
    return made, info


def build_collision_objects(an, coll, name):
    """Collision glb content: Ground-colonly / Walls-colonly trimeshes (planar-decimated) and one
    <item>-convcolonly prism per prop hull (world space baked in, so no scaled shapes)."""
    made, st = [], {}
    for cls, label in (("ground", "Ground"), ("walls", "Walls")):
        v, t = an[cls]
        st[f"{cls}_tris_raw"] = int(len(t))
        if not len(t):
            st[f"{cls}_tris"] = 0
            continue
        me = bpy.data.meshes.new(f"{name}_{label}")
        me.from_pydata(v.tolist(), [], t.tolist())
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.01)
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(5.0), verts=bm.verts, edges=bm.edges)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(f"{label}-colonly", me)
        coll.objects.link(ob)
        made.append(ob)
        st[f"{cls}_tris"] = tri_count(me)
    n = 0
    for it in an["hull_items"]:
        mw = it["matrix"]
        for k, h in enumerate(it["hulls"]):
            pts = [mw @ Vector((x, y, z)) for x, y in h for z in (it["z0"], it["z1"])]
            bm = bmesh.new()
            for p in pts:
                bm.verts.new(p)
            try:
                bmesh.ops.convex_hull(bm, input=bm.verts)
            except Exception:  # noqa: BLE001
                bm.free()
                continue
            me = bpy.data.meshes.new(f"{it['name']}_hull{k}")
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new(f"{it['name']}_hull{k}-convcolonly", me)
            coll.objects.link(ob)
            made.append(ob)
            n += 1
    st["prop_hulls"] = n
    return made, st


def collision_json(an, ctx):
    """Prop collision as data: a shape library (asset-local convex prisms, Godot axes) and per-instance xforms."""
    shapes, inst = {}, []
    for it in an["hull_items"]:
        if it["asset"]:
            key = it["asset"]
            if key not in shapes:
                shapes[key] = [[gpos((x, y, z)) for x, y in h for z in (it["z0"], it["z1"])] for h in it["hulls"]]
            inst.append({"shape": key, "kind": it["kind"], "xform": gxform(it["matrix"])})
        else:
            key = "mesh:" + it["name"]
            shapes[key] = [[gpos((x, y, z)) for x, y in h for z in (it["z0"], it["z1"])] for h in it["hulls"]]
            inst.append({"shape": key, "kind": it["kind"], "xform": gxform(Matrix.Identity(4))})
    return {"prop_shapes": shapes, "prop_instances": inst}


def bounds_of(objs):
    lo = Vector((1e18,) * 3)
    hi = Vector((-1e18,) * 3)
    any_ = False
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
            any_ = True
    if not any_:
        return None
    return aabb_g(np.array([lo[:], hi[:]]))


def file_size(path):
    return os.path.getsize(path) if os.path.exists(path) else 0


def file_hash(path):
    import hashlib
    if not os.path.exists(path):
        return None
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()[:16]


# ----------------------------------------------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------------------------------------------

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(prog="export_runtime.py")
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--outlines", choices=("shell", "none"), default="shell")
    ap.add_argument("--colors", choices=("vertex", "flat"), default="vertex")
    ap.add_argument("--grid", type=float, default=2.0)
    ap.add_argument("--no-library", action="store_true")
    ap.add_argument("--legacy-names", action="store_true",
                    help="classify meshes by the pre-registry name rules (_Body, _Cap, _Fringe, ...) instead of "
                         "their collision tags; for before / after comparisons")
    ap.add_argument("--check", action="store_true",
                    help="analysis only: collision classes, decimated collision triangle counts, prop hulls, route "
                         "checks and capsule clearance into <out>/check.json; no glbs, no sidecars (~1 min)")
    return ap.parse_args(argv)


def check_report(analysis, sidecars, chunks, out_dir, T, t_all):
    """--check: everything the export decides about collision and clearance, without the bake or any glb.

    Writes <out>/check.json: per chunk the mesh classes (and, per object, the class each mesh got), the collision
    stats exactly as the export computes them (raw and decimated Ground / Walls triangles, prop hulls), the exact
    fallbacks, the route check and the spawn clearance (player spawns, portal arrivals, route ends). Two check.json
    files diffed object by object prove a collision-rule change keeps the output identical."""
    exp = bpy.data.scenes.new("_RUNTIME_CHECK")
    rep = {"generated": time.strftime("%Y-%m-%d %H:%M:%S"), "blend": bpy.data.filepath, "chunks": {}}
    for name, ch in chunks.items():
        an, sc = analysis[name], sidecars[name]
        coll = bpy.data.collections.new(f"CHKCOL_{name}")
        exp.collection.children.link(coll)
        made, st = build_collision_objects(an, coll, name)
        for o in made:
            me = o.data
            bpy.data.objects.remove(o)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)
        bpy.data.collections.remove(coll)
        rep["chunks"][name] = {
            "kind": ch["kind"], "collision": st, "mesh_classes": _count(an["classes"].values()),
            "classes": dict(sorted(an["classes"].items())),
            "class_source": _count(an.get("class_source", {}).values()),
            "class_source_by_object": dict(sorted(an.get("class_source", {}).items())),
            "hull_items": sorted(it["name"] for it in an["hull_items"]),
            "exact_fallback": an["exact_fallback"], "exact_by_tag": an["exact_by_tag"],
            "route_check": route_block_check(an, sc) if sc.get("routes") else None,
            "spawn_clearance": sc.get("spawn_clearance")}
    bpy.data.scenes.remove(exp)
    T["total_s"] = rnd(time.time() - t_all, 2)
    rep["timings"] = T
    path = os.path.join(out_dir, "check.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=1)
    tot = {"ground_tris": 0, "walls_tris": 0, "prop_hulls": 0, "route_samples": 0, "blocked_by_hulls": 0,
           "blocked_by_walls_overhead": 0, "overhead_body": 0, "blocked_spawns": 0, "blocked_arrivals": 0,
           "blocked_route_ends": 0}
    for c in rep["chunks"].values():
        tot["ground_tris"] += c["collision"].get("ground_tris", 0)
        tot["walls_tris"] += c["collision"].get("walls_tris", 0)
        tot["prop_hulls"] += c["collision"].get("prop_hulls", 0)
        rc = c["route_check"] or {}
        for k, k2 in (("route_samples", "samples"), ("blocked_by_hulls", "blocked_by_hulls"),
                      ("blocked_by_walls_overhead", "blocked_by_walls_overhead")):
            tot[k] += rc.get(k2, 0)
        tot["overhead_body"] += (rc.get("overhead_by_kind") or {}).get("body", 0)
        clr = c["spawn_clearance"] or {}
        tot["blocked_spawns"] += sum(1 for r in clr.get("player_spawns", []) if not r["clear"])
        tot["blocked_arrivals"] += sum(1 for r in clr.get("portal_arrivals", []) if not r["clear"])
        tot["blocked_route_ends"] += sum(1 for r in clr.get("route_ends", []) if not r["clear"])
    print("CHECK_TOTALS", json.dumps(tot))
    print("CHECK_DONE", path, json.dumps(T))


def main():
    args = parse_args()
    t_all = time.time()
    out_dir = args.out if os.path.isabs(args.out) else os.path.join(ROOT, args.out)
    os.makedirs(out_dir, exist_ok=True)
    win = bpy.context.window_manager.windows[0]
    main_scene = bpy.context.scene
    res = (main_scene.render.resolution_x, main_scene.render.resolution_y)
    ctx = Ctx(args)
    T = ctx.timings

    t = time.time()
    failed = load_registry()
    ctx.warnings += [f"map module import failed (tags lost): {f}" for f in failed]
    chunks = plan_chunks()
    only = {s for s in args.only.split(",") if s}
    if only:
        unknown = only - set(chunks) - {"_library"}
        if unknown:
            raise SystemExit(f"unknown chunk(s): {sorted(unknown)}; known: {sorted(chunks)}")
        chunks = {k: v for k, v in chunks.items() if k in only}
    do_library = not args.no_library and (not only or "_library" in only)
    T["plan_s"] = rnd(time.time() - t, 2)
    print("PHASE", "plan_s", T["plan_s"], flush=True)

    # ---- 1. analysis on the untouched meshes: collision + markers
    t = time.time()
    analysis, sidecars = {}, {}
    for name, ch in chunks.items():
        an = analyse_chunk(ctx, ch)
        analysis[name] = an
        sc = {"format": FORMAT_VERSION, "chunk": name, "kind": ch["kind"], "units": "meters",
              "coordinates": "godot: (x, y, z) = blender (x, z, -y); xform = [basis.x, basis.y, basis.z, origin]",
              "files": {"visual": f"{name}.glb", "collision": f"{name}.collision.glb"}}
        if ch["kind"] in ("map", "interior"):
            sc.update(map_markers(ctx, ch, an))
        if name == "World_SkyAndSea":
            sea = bpy.data.objects.get("Sea_Far_Below")
            if sea is not None:
                sc["sea_level_y"] = rnd(sum((sea.matrix_world @ Vector(c)).z for c in sea.bound_box) / 8)
        if name == "World_Trails":
            sc["trails"] = trail_entries(ch)
        an["exact_fallback"] = {}
        if sc.get("routes") or sc.get("portals"):
            resolve_blockers(an, sc)
        finish_walls(an)
        sc["lights"] = [light_marker(o) for o in an["lights"]]
        sc["water"] = an["water"]
        sc["collision"] = {"authored_colliders": an["authored_colliders"], **collision_json(an, ctx),
                           "exact_fallback": an["exact_fallback"], "exact_by_tag": an["exact_by_tag"],
                           "instances_seen": an["stats"]["instances"],
                           "instances_colliding": an["stats"]["instances_colliding"],
                           "instances_skipped": an["stats"]["skipped_by_rule"],
                           "mesh_classes": _count(an["classes"].values()),
                           "mesh_class_source": _count(an["class_source"].values())}
        sidecars[name] = sc
    # player spawns and portal arrivals vs the shipped collision of every chunk (hulls are final after the loop)
    spawn_clearance(analysis, sidecars, partial=bool(only))
    T["analyse_s"] = rnd(time.time() - t, 2)
    print("PHASE", "analyse_s", T["analyse_s"], flush=True)
    if args.check:
        check_report(analysis, sidecars, chunks, out_dir, T, t_all)
        return

    # ---- 2. collision glbs (before any mesh edits)
    t = time.time()
    exp = bpy.data.scenes.new("_RUNTIME_EXPORT")
    coll_stats = {}
    for name, ch in chunks.items():
        coll = bpy.data.collections.new(f"EXPCOL_{name}")
        exp.collection.children.link(coll)
        made, st = build_collision_objects(analysis[name], coll, name)
        path = os.path.join(out_dir, f"{name}.collision.glb")
        if made:
            gltf_export(win, exp, made, path, visual=False)
        else:
            if os.path.exists(path):
                os.remove(path)
            # no collision geometry (World_SkyAndSea): do not name a file that is not written (empty = none)
            sidecars[name]["files"]["collision"] = ""
        st["exact_fallback"] = len(analysis[name]["exact_fallback"])
        st["route_check"] = route_block_check(analysis[name], sidecars[name]) if sidecars[name].get("routes") \
            else None
        coll_stats[name] = st
        sidecars[name]["collision"]["summary"] = st
        for o in made:
            me = o.data
            bpy.data.objects.remove(o)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)
        bpy.data.collections.remove(coll)
    T["collision_s"] = rnd(time.time() - t, 2)
    print("PHASE", "collision_s", T["collision_s"], flush=True)

    # ---- 3. visual export set: map/world objects + instance sources + library sources
    export_objs = {}
    for name, ch in chunks.items():
        for o, _g in ch["items"]:
            if is_visual(o):
                for s, _rel in source_parts(o):
                    export_objs[s.name] = s
    lib_assets = library_assets() if do_library else []
    for a in lib_assets:
        for s in a.all_objects:
            if s.type == "MESH" and not s.hide_render:
                export_objs[s.name] = s
    export_objs = list(export_objs.values())
    reps = {}
    for o in export_objs:
        if len(o.data.polygons) and len(o.data.materials):
            reps.setdefault(o.data.name, o)
    reps = list(reps.values())

    # ---- 4. densify cap tops, bake albedo, outlines, materials
    t = time.time()
    added = 0
    for o in reps:
        added += densify_tops(o.data, args.grid)
    T["densify_s"] = rnd(time.time() - t, 2)
    print("PHASE", "densify_s", T["densify_s"], flush=True)
    mats = sorted({m for o in export_objs for m in o.data.materials if m}, key=lambda m: m.name)
    params = read_material_params(mats)
    t = time.time()
    corners = sum(len(o.data.loops) for o in reps)
    bake_albedo(reps, win)
    T["bake_s"] = rnd(time.time() - t, 2)
    print("PHASE", "bake_s", T["bake_s"], flush=True)
    means = material_means(reps)
    cells = sorted(k for k, v in params.items() if v.get("cell_pattern"))
    flattened = flatten_cell_patterns(reps, means, cells) if args.colors == "vertex" else 0
    t = time.time()
    n_shells = apply_outlines(export_objs, win, args.outlines)
    T["outlines_s"] = rnd(time.time() - t, 2)
    print("PHASE", "outlines_s", T["outlines_s"], flush=True)
    mat_info = rewrite_materials(mats, params, means, args.colors)

    # ---- 5. visual glbs + sidecars
    t = time.time()
    index_path = os.path.join(out_dir, "index.json")
    index = {}
    if os.path.exists(index_path) and only:
        with open(index_path, encoding="utf-8") as f:
            index = json.load(f)
    index.setdefault("chunks", {})
    for name, ch in chunks.items():
        coll = bpy.data.collections.new(f"EXP_{name}")
        exp.collection.children.link(coll)
        made, vst = realize_chunk(ch, coll, ctx.cats)
        path = os.path.join(out_dir, f"{name}.glb")
        tv = time.time()
        gltf_export(win, exp, made, path, visual=True, colors=args.colors)
        vst["godot_vc_flag_fix_materials"] = patch_glb_vertex_color_flags(path) if args.colors == "vertex" else 0
        vst["export_s"] = rnd(time.time() - tv, 2)
        sidecars[name]["bounds"] = bounds_of(made)
        sidecars[name]["visual"] = vst
        for o in made:
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(coll)
        sc = sidecars[name]
        jpath = os.path.join(out_dir, f"{name}.json")
        with open(jpath, "w", encoding="utf-8") as f:
            json.dump(sc, f, indent=1)
        cs = coll_stats[name]
        index["chunks"][name] = {
            "kind": ch["kind"], "map_id": sc.get("map_id"), "visual_tris": vst["tris"],
            "outline_tris": vst["outline_tris"], "nodes": vst["nodes"], "unique_meshes": vst["unique_meshes"],
            "glb_bytes": file_size(path), "collision_bytes": file_size(os.path.join(out_dir, f"{name}.collision.glb")),
            "json_bytes": file_size(jpath), "collision": {k: v for k, v in cs.items() if k != "route_check"},
            "route_check": None if cs.get("route_check") is None else
            {k: cs["route_check"][k] for k in ("samples", "blocked_by_hulls", "blocked_by_walls_overhead")},
            "markers": {k: len(sc.get(k) or []) for k in ("portals", "npcs", "spawn_points", "spawn_areas",
                                                            "climbables", "routes", "water", "lights",
                                                            "arrival_points", "ledges", "player_spawns",
                                                            "spawn_regions", "trails")},
            "has_player_start": bool(sc.get("player_start")), "cameras": len(sc.get("cameras", {})),
            "authored_colliders": len(sc["collision"]["authored_colliders"]),
            "prop_collision_instances": len(sc["collision"]["prop_instances"]), "export_s": vst["export_s"],
            "content_hash": {k: file_hash(os.path.join(out_dir, f)) for k, f in
                             (("visual", f"{name}.glb"), ("collision", f"{name}.collision.glb"),
                              ("sidecar", f"{name}.json"))}}
    if do_library:
        coll = bpy.data.collections.new("EXP__library")
        exp.collection.children.link(coll)
        made, info = realize_library(lib_assets, coll, ctx.cats)
        path = os.path.join(out_dir, "_library.glb")
        gltf_export(win, exp, made, path, visual=True, colors=args.colors)
        if args.colors == "vertex":
            patch_glb_vertex_color_flags(path)
        with open(os.path.join(out_dir, "_library.json"), "w", encoding="utf-8") as f:
            json.dump({"format": FORMAT_VERSION, "chunk": "_library", "kind": "library",
                       "note": "one root node per asset at the origin; feet at y = 0, front = +Z (Godot MODEL_FRONT)",
                       "assets": info}, f, indent=1)
        index["chunks"]["_library"] = {"kind": "library", "glb_bytes": file_size(path), "assets": len(info),
                                       "visual_tris": sum(tri_count(o.data) for o in made if o.type == "MESH")}
        for o in made:
            bpy.data.objects.remove(o)
    T["export_s"] = rnd(time.time() - t, 2)
    print("PHASE", "export_s", T["export_s"], flush=True)
    T["total_s"] = rnd(time.time() - t_all, 2)

    index.update({
        "format": FORMAT_VERSION, "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "blend": bpy.data.filepath, "blender": bpy.app.version_string,
        "settings": {"outlines": args.outlines, "colors": args.colors, "grid_m": args.grid},
        "coordinates": "godot (x, y, z) = blender (x, z, -y); markers' xform = [basis.x, basis.y, basis.z, origin]",
        "sea_level_y": sidecars.get("World_SkyAndSea", {}).get("sea_level_y", index.get("sea_level_y")),
        "bake": {"meshes": len(reps), "corners": corners, "faces_added_by_densify": added, "outline_meshes": n_shells,
                 "cell_pattern_materials_flattened": cells, "cell_pattern_corners": flattened},
        "environment": environment_block(main_scene), "materials": mat_info, "timings": T, "warnings": ctx.warnings,
    })
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1)
    main_scene_restore(win, main_scene)
    print("EXPORT_DONE", out_dir, json.dumps(T))


def _count(vals):
    out = {}
    for v in vals:
        k = str(v)
        out[k] = out.get(k, 0) + 1
    return out


def main_scene_restore(win, sc):
    try:
        win.scene = sc
    except Exception:  # noqa: BLE001
        pass


if __name__ == "__main__":
    main()
