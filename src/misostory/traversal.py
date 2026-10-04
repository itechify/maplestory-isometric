"""Traversal validation: walk each declared route over the real geometry.

For every route polyline (local xy) we sample the ground every 0.4 m and classify
height changes between samples:
  * walk   - |dz| <= MAX_STEP (stairs/ramps/terrain)
  * climb  - larger rise/fall within CLIMB_RADIUS of a ladder/rope spanning it
  * drop   - a fall of <= MAX_DROP (allowed, one-way)
  * error  - unclimbable step, missing ground, slope steeper than MAX_SLOPE_DEG, or a
             prop blocking the way (an upward ray from the walk surface hits geometry
             inside the body band BODY_Z; not on the approach to a ladder/rope climb)
It also checks that every ladder/rope has walkable ground at its foot and top, that
portals stand on ground, that terrain stays near the map footprint, and that the declared
routes form one connected graph that joins every portal (route_graph).
"""

import math

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import core, geo, kit, ledge_rules

MAX_STEP = 0.45
MAX_DROP = 2.6
MAX_SLOPE_DEG = 38.0
CLIMB_RADIUS = 2.2
SAMPLE = 0.4
PLAYER_HEIGHT = core.PLAYER_HEIGHT
BODY_Z = (0.15, PLAYER_HEIGHT)  # body band above the walk surface: geometry inside it blocks a route
HEAD = BODY_Z[1] - BODY_Z[0]    # length of the upward 'blocked' ray (kept for older callers)
SMALL_FOOTPRINT = 0.9  # props smaller than this (flowers, tufts) never block
CLIMB_EXEMPT_SAMPLES = 2  # 'blocked' hits this many samples (0.8 m) from a climb, beside a ladder/rope, are exempt
# route graph (route_graph): two routes join where a vertex of one lies within JOIN_XY (xy) and JOIN_Z (ground
# height) of a segment of the other, or where their segments cross at the same height
JOIN_XY = 0.75
JOIN_Z = 0.45
PORTAL_REACH = 1.5    # a route reaches a portal when one of its samples is this close ...
PORTAL_REACH_Z = 0.45  # ... on ground within this of the portal's height
# One-way ledge invariant (docs/runtime/MAP_ARCHITECTURE.md 4.4): a one-way trail's drop-down ledge must be higher
# than anything the player can climb back up (jump apex at the Jump cap + one walking step + this margin) and no
# higher than a one-way drop (MAX_DROP). Its face must lie on the arrival gate plane within LEDGE_FACE_TOL_M. The
# rule itself lives in ledge_rules.py (no bpy) so the staging check (sidecar_diff.py) applies the same bounds.
LEDGE_MARGIN_M = ledge_rules.LEDGE_MARGIN_M
LEDGE_FACE_TOL_M = ledge_rules.LEDGE_FACE_TOL_M


def ledge_bounds(root):
    """(min_height, max_height, detail) of the one-way ledge invariant, from the game data under root
    (ledge_rules.ledge_bounds with this module's MAX_DROP and MAX_STEP)."""
    return ledge_rules.ledge_bounds(root, max_drop=MAX_DROP, max_step=MAX_STEP)


def climbables(ctx):
    out = []
    for o in ctx.col_arch.objects:
        if "climbable" in o.keys():
            cs = [o.matrix_world @ Vector(c) for c in o.bound_box]
            cx = sum(c.x for c in cs) / 8
            cy = sum(c.y for c in cs) / 8
            out.append((cx, cy, o["climb_z0"], o["climb_z1"], o.name, bool(o.get("descend_only"))))
    return out


_PASSABLE_WORDS = ("rope", "vine", "ladder", "sign", "portal", "banner", "flag", "lantern", "butterfly")


def _passable(ob):
    """Climbables, ropes/vines, signs and anything tagged passable never block a route."""
    if "climbable" in ob.keys() or ob.get("passable"):
        return True
    n = ob.name.lower()
    return any(w in n for w in _PASSABLE_WORDS)


def obstacle_bvh(ctx):
    """BVH of solid props/architecture of this map (instances + meshes), excluding small foliage."""
    from .core import GroundIndex
    verts, polys = [], []
    owners = []  # (first face index, owner name)

    def add_mesh(ob, mw, owner=None):
        me = ob.data
        owners.append((len(polys), owner or ob.name))
        off = len(verts)
        verts.extend(mw @ v.co for v in me.vertices)
        polys.extend([off + i for i in p.vertices] for p in me.polygons)

    for coll in (ctx.col_arch, ctx.col_props, ctx.col_veg):
        for ob in coll.objects:
            if ob.instance_type == "COLLECTION" and ob.instance_collection is not None:
                asset = ob.get("asset", "")
                info = kit.REGISTRY.get(asset, {})
                if info.get("footprint", 1.0) < SMALL_FOOTPRINT or set(info.get("tags", ())) & {"portal_door"}:
                    continue
                if _passable(ob) or any(w in asset.lower() for w in _PASSABLE_WORDS):
                    continue
                if set(info.get("tags", ())) & {"flower", "grass"} or "flower" in asset.lower() or "clover" in asset.lower():
                    continue
                me_w = GroundIndex.object_world_matrix(ob)
                for src in ob.instance_collection.all_objects:
                    if src.type == "MESH":
                        add_mesh(src, me_w @ src.matrix_basis, owner=ob.name)
            elif ob.type == "MESH" and not _passable(ob):
                add_mesh(ob, GroundIndex.object_world_matrix(ob))
    if not polys:
        return None
    bvh = BVHTree.FromPolygons(verts, polys)
    bvh_owners[id(bvh)] = owners
    return bvh


bvh_owners = {}


def owner_of(bvh, face_index):
    import bisect
    owners = bvh_owners.get(id(bvh), [])
    i = bisect.bisect_right([o[0] for o in owners], face_index) - 1
    return owners[i][1] if i >= 0 else "?"


def _near_climb(ctx, ladders, x, y, za, zb, allow_down_only=False):
    """The nearest ladder/rope within CLIMB_RADIUS whose z-span covers za..zb (local heights): its object name,
    or None (truthy/falsy, so callers may use it as a bool)."""
    w = ctx.w(x, y)
    zlo, zhi = min(za, zb) + ctx.origin.z, max(za, zb) + ctx.origin.z
    best = None
    for l in ladders:
        if l[5] and not allow_down_only:
            continue  # descend-only vines cannot be climbed up
        d = math.hypot(l[0] - w.x, l[1] - w.y)
        if d < CLIMB_RADIUS and l[2] <= zlo + 0.6 and l[3] >= zhi - 0.6 and (best is None or d < best[0]):
            best = (d, l[4])
    return None if best is None else best[1]


def _resample_indexed(pts, step):
    """geo.resample(pts, step, closed=False) plus, per sample, the index of the authored segment it lies on."""
    out, seg = [], []
    n = len(pts)
    for i in range(n - 1):
        a = Vector(pts[i])
        b = Vector(pts[i + 1])
        k = max(1, int(math.ceil((b - a).length / step)))
        for j in range(k):
            p = a.lerp(b, j / k)
            out.append((p.x, p.y))
            seg.append(i)
    out.append(tuple(pts[-1]))
    seg.append(max(0, n - 2))
    return out, seg


def _near_ladder_xy(ctx, ladders, x, y):
    w = ctx.w(x, y)
    return any(math.hypot(l[0] - w.x, l[1] - w.y) < CLIMB_RADIUS for l in ladders)


def check_route(ctx, route, ladders, obstacles, reverse=False):
    rpts = route["pts"][::-1] if reverse else route["pts"]
    if len(rpts) < 2:
        rpts = list(rpts) * 2
    pts, seg_of = _resample_indexed(rpts, SAMPLE)
    samples = []
    events = []  # (sample index, issue, counts as error) in walking order
    stats = {"walk": 0, "climb": 0, "drop": 0, "error": 0}
    climb_pairs = []
    climbed = set()  # ladders/ropes this walk climbs (route_graph links the routes that walk the same one)
    for x, y in pts:
        samples.append((x, y, ctx.ground_z(x, y)))
    n = len(samples)
    for i in range(n - 1):
        x0, y0, z0 = samples[i]
        x1, y1, z1 = samples[i + 1]
        if z0 is None or z1 is None:
            events.append((i, {"type": "no_ground", "at": [round(x1 if z1 is None else x0, 1),
                                                          round(y1 if z1 is None else y0, 1)]}, True))
            continue
        dz = z1 - z0
        if abs(dz) <= MAX_STEP:
            # slope over a ~1.2 m window of consecutive *walkable* pairs (stops at climbs/drops),
            # so stair risers and the approach to a ladder are not mistaken for steep ramps
            j = i + 1
            while j < min(n - 1, i + 3):
                za, zb = samples[j][2], samples[j + 1][2]
                if za is None or zb is None or abs(zb - za) > MAX_STEP:
                    break
                j += 1
            zj = samples[j][2]
            run = math.hypot(samples[j][0] - x0, samples[j][1] - y0)
            slope = math.degrees(math.atan2(abs(zj - z0), run)) if run >= 0.75 else 0.0
            lad = _near_climb(ctx, ladders, x0, y0, z0, zj) if slope > MAX_SLOPE_DEG else None
            if lad:
                stats["climb"] += 1
                climb_pairs.append(i)
                climbed.add(lad)
            elif slope > MAX_SLOPE_DEG:
                events.append((i, {"type": "steep", "at": [round(x0, 1), round(y0, 1)], "deg": round(slope)}, True))
            else:
                stats["walk"] += 1
            if obstacles is not None:
                w = ctx.w(x1, y1, z1)
                hit = obstacles.ray_cast(Vector((w.x, w.y, w.z + BODY_Z[0])), Vector((0, 0, 1)), BODY_Z[1] - BODY_Z[0])
                if hit[0] is not None:
                    events.append((i + 1, {"type": "blocked", "at": [round(x1, 1), round(y1, 1)],
                                           "height": round(hit[0].z - w.z, 2), "by": owner_of(obstacles, hit[2])},
                                   True))
            continue
        near = _near_climb(ctx, ladders, (x0 + x1) / 2, (y0 + y1) / 2, z0, z1, allow_down_only=dz < 0)
        if near:
            stats["climb"] += 1
            climb_pairs.append(i)
            climbed.add(near)
        elif dz < 0 and -dz <= MAX_DROP:
            stats["drop"] += 1
            events.append((i, {"type": "drop", "at": [round(x0, 1), round(y0, 1)], "dz": round(dz, 2)}, False))
        else:
            events.append((i, {"type": "step", "at": [round(x0, 1), round(y0, 1)], "dz": round(dz, 2)}, True))
    # a prop beside the climb of a ladder/rope (a trellis behind the rope, the upper lip's dressing over the
    # foot) is not 'blocked': skip hits on an authored segment that contains a climb, or within
    # CLIMB_EXEMPT_SAMPLES samples of one, when a ladder/rope stands within CLIMB_RADIUS
    climb_segs = {seg_of[i] for i in climb_pairs} | {seg_of[min(i + 1, n - 1)] for i in climb_pairs}
    exempt = []
    issues = []
    for k, it, is_err in events:
        if it["type"] == "blocked" and climb_pairs:
            close = seg_of[k] in climb_segs or any(abs(k - c) <= CLIMB_EXEMPT_SAMPLES or abs(k - (c + 1)) <=
                                                   CLIMB_EXEMPT_SAMPLES for c in climb_pairs)
            if close and _near_ladder_xy(ctx, ladders, samples[k][0], samples[k][1]):
                exempt.append(it)
                continue
        if is_err:
            stats["error"] += 1
        issues.append(it)
    merged = []
    for it in issues:
        if merged and merged[-1]["type"] == it["type"] and math.dist(merged[-1]["at"], it["at"]) < 1.5:
            continue
        merged.append(it)
    label = route["name"] + (" (reverse)" if reverse else "")
    out = {"route": label, "ok": stats["error"] == 0, "stats": stats, "issues": merged[:20]}
    if exempt:
        out["climb_exempt"] = [{"at": e["at"], "by": e["by"]} for e in exempt[:10]]
    if climbed:
        out["climbed"] = sorted(climbed)
    if not reverse and climb_pairs:
        segs = sorted(climb_segs & set(range(len(rpts) - 1)))
        out["climb_segments"] = [[round(rpts[i][0], 2), round(rpts[i][1], 2), round(rpts[i + 1][0], 2),
                                  round(rpts[i + 1][1], 2)] for i in segs]
    return out


def check_climbables(ctx, ladders):
    """Every ladder/rope needs walkable ground at its foot and at its top (within ~1.3 m)."""
    out = []
    for (cx, cy, z0, z1, name, descend_only) in ladders:
        def ground_near(zt):
            for r in (0.0, 0.5, 0.9, 1.3):
                for k in range(12 if r else 1):
                    a = 2 * math.pi * k / 12
                    z, _n = ctx.ground.raycast_down(cx + math.cos(a) * r, cy + math.sin(a) * r, z_from=zt + 0.8)
                    if z is not None and abs(z - zt) < 0.6:
                        return True
            return False
        top_ok = ground_near(z1)
        foot_ok = True if descend_only else ground_near(z0)
        if not (top_ok and foot_ok):
            out.append({"climbable": name, "top_ok": top_ok, "foot_ok": foot_ok})
    return out


def _seg_closest_t(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
    return t, math.hypot(px - (ax + t * dx), py - (ay + t * dy)), math.sqrt(L2)


def _seg_cross(a, b, c, d):
    """Parameter (t on ab) where segments ab and cd properly cross in xy, or None."""
    r = (b[0] - a[0], b[1] - a[1])
    q = (d[0] - c[0], d[1] - c[1])
    den = r[0] * q[1] - r[1] * q[0]
    if abs(den) < 1e-12:
        return None
    t = ((c[0] - a[0]) * q[1] - (c[1] - a[1]) * q[0]) / den
    u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
    return t if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0 else None


def route_reach(ctx):
    """Per portal name: (set of route indices reaching it, nearest z-matching route sample distance or None).

    A route reaches a portal when one of its samples (every SAMPLE m) lies within PORTAL_REACH m of it, on ground
    within PORTAL_REACH_Z of the portal's height."""
    dense = [geo.resample(r["pts"], SAMPLE, closed=False) if len(r["pts"]) >= 2 else [tuple(r["pts"][0])]
             for r in ctx.routes]
    out = {}
    for p in ctx.portals:
        best, reached = None, set()
        for ri, pts in enumerate(dense):
            for (x, y) in pts:
                d = math.hypot(x - p["x"], y - p["y"])
                if d <= PORTAL_REACH or best is None or d < best:
                    z = ctx.ground_z(x, y)
                    if z is not None and abs(z - p["z"]) <= PORTAL_REACH_Z:
                        if best is None or d < best:
                            best = d
                        if d <= PORTAL_REACH:
                            reached.add(ri)
        out[p["name"]] = (reached, best)
    return out


def route_graph(ctx, reach=None, climbed=None):
    """Connectivity of the declared routes (the walkable graph the validator has actually proven).

    Two routes join where a vertex of one lies within JOIN_XY m (xy) of a segment of the other and the ground
    there is within JOIN_Z m of the vertex's ground height, or where two segments cross at the same height. A
    ladder or rope links only the routes that walk it: routes whose walks climb the same ladder/rope join
    (climbed: route index -> set of climbable names, from check_route); passing near its foot or top joins
    nothing. A portal joins every route that reaches it (route_reach). Returns
    {"route_groups": [[names]], "orphan_routes": [names in groups that reach no portal],
     "portal_groups": [[portal names] per group that reaches portals], "portal_split": [] or portal_groups,
     "group_gaps": [nearest gap from every group that is not the main portal group to any other route]}.
    """
    routes = ctx.routes
    names = []
    for r in routes:  # route names are the key fixers read; keep them unique
        nm, k = r["name"], 2
        while nm in names:
            nm, k = f"{r['name']}#{k}", k + 1
        names.append(nm)
    nr = len(routes)
    parent = list(range(nr + len(ctx.portals)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i, j):
        a, b = find(i), find(j)
        if a != b:
            parent[b] = a

    zcache = {}

    def gz(x, y):
        key = (round(x, 3), round(y, 3))
        if key not in zcache:
            zcache[key] = ctx.ground_z(x, y)
        return zcache[key]

    verts = [[(float(p[0]), float(p[1]), gz(p[0], p[1])) for p in r["pts"]] for r in routes]

    def vertex_joins(v, rb):
        vx, vy, vz = v
        if vz is None:
            return False
        pts = routes[rb]["pts"]
        for a, b in zip(pts, pts[1:]):
            t, d, L = _seg_closest_t(vx, vy, a[0], a[1], b[0], b[1])
            if d > JOIN_XY:
                continue
            # sample the part of the segment inside the join circle: the ground jumps at a lip, so a vertex at a
            # ladder foot joins the climbing route's lower part, not its upper end
            half = math.sqrt(max(0.0, JOIN_XY * JOIN_XY - d * d)) / max(L, 1e-9)
            k = max(1, int(math.ceil(2 * half * L / 0.2)))
            for j in range(k + 1):
                tt = min(1.0, max(0.0, t - half + 2 * half * j / k))
                qx, qy = a[0] + (b[0] - a[0]) * tt, a[1] + (b[1] - a[1]) * tt
                if math.hypot(qx - vx, qy - vy) > JOIN_XY + 1e-6:
                    continue
                zq = gz(qx, qy)
                if zq is not None and abs(zq - vz) <= JOIN_Z:
                    return True
        return False

    def crossing_joins(ra, rb):
        pa, pb = routes[ra]["pts"], routes[rb]["pts"]
        for a, b in zip(pa, pa[1:]):
            for c, d in zip(pb, pb[1:]):
                t = _seg_cross(a, b, c, d)
                if t is None:
                    continue
                qx, qy = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                if gz(qx, qy) is not None:
                    return True  # one ground height at one xy: both routes stand on it there
        return False

    for ra in range(nr):
        for rb in range(ra + 1, nr):
            if find(ra) == find(rb):
                continue
            if any(vertex_joins(v, rb) for v in verts[ra]) or any(vertex_joins(v, ra) for v in verts[rb]) \
                    or crossing_joins(ra, rb):
                union(ra, rb)
    by_ladder = {}
    for ri, names_ in (climbed or {}).items():
        for lad in names_:
            by_ladder.setdefault(lad, []).append(ri)
    for rs in by_ladder.values():
        for ri in rs[1:]:
            union(rs[0], ri)
    reach = reach if reach is not None else route_reach(ctx)
    for pi, p in enumerate(ctx.portals):
        for ri in reach.get(p["name"], (set(), None))[0]:
            union(nr + pi, ri)
    groups, gportals = {}, {}
    for ri in range(nr):
        groups.setdefault(find(ri), []).append(names[ri])
    for pi, p in enumerate(ctx.portals):
        if reach.get(p["name"], (set(), None))[0]:
            gportals.setdefault(find(nr + pi), []).append(p["name"])
    route_groups = list(groups.values())
    orphans = [nm for root, g in groups.items() if root not in gportals for nm in g]
    portal_groups = list(gportals.values())
    # where to stitch: for every group other than the main one (the group joining most portals), the nearest gap
    # to the main group and to any other group - vertex to segment in xy like the join rule, preferring gaps at
    # the same height (|dz| <= JOIN_Z) over nearer ones on another tier
    gaps = []
    roots = list(groups)

    def nearest(in_r, out_ok):
        best_same = best_any = None
        for ri in range(nr):
            if find(ri) != in_r:
                continue
            for rj in range(nr):
                if find(rj) == in_r or not out_ok(find(rj)):
                    continue
                for vr, sr in ((ri, rj), (rj, ri)):
                    pts = routes[sr]["pts"]
                    for (vx, vy, vz) in verts[vr]:
                        for a_, b_ in zip(pts, pts[1:]):
                            t, d, _L = _seg_closest_t(vx, vy, a_[0], a_[1], b_[0], b_[1])
                            if not ((best_any is None or d < best_any["gap_xy_m"]) or
                                    (best_same is None or d < best_same["gap_xy_m"])):
                                continue
                            qx, qy = a_[0] + (b_[0] - a_[0]) * t, a_[1] + (b_[1] - a_[1]) * t
                            zq = gz(qx, qy)
                            dz = None if (vz is None or zq is None) else zq - vz
                            g = {"vertex_route": names[vr], "segment_route": names[sr],
                                 "from": [round(vx, 2), round(vy, 2)], "to": [round(qx, 2), round(qy, 2)],
                                 "gap_xy_m": round(d, 2), "dz_m": None if dz is None else round(dz, 2)}
                            if best_any is None or d < best_any["gap_xy_m"]:
                                best_any = g
                            if dz is not None and abs(dz) <= JOIN_Z and (best_same is None or
                                                                       d < best_same["gap_xy_m"]):
                                best_same = g
        return best_same or best_any

    if len(roots) > 1:
        main = max(roots, key=lambda r: (len(gportals.get(r, [])), len(groups[r])))
        for r in roots:
            if r == main:
                continue
            to_main = nearest(r, lambda q: q == main)
            to_any = nearest(r, lambda q: True)
            gap = {"group": groups[r], "portals": gportals.get(r, []), "to_main": to_main}
            if to_any and to_main and to_any["gap_xy_m"] < to_main["gap_xy_m"] - 1e-6:
                gap["to_other"] = to_any
            gaps.append(gap)
    return {"route_groups": route_groups, "orphan_routes": orphans, "portal_groups": portal_groups,
            "portal_split": portal_groups if len(portal_groups) > 1 else [], "group_gaps": gaps}


def check_map(ctx):
    ladders = climbables(ctx)
    exceptions = list(getattr(ctx, "warnings", []))
    try:
        obstacles = obstacle_bvh(ctx)
    except Exception as e:  # noqa: BLE001 - routes are still walked, without the 'blocked' test
        obstacles = None
        exceptions.append(f"obstacle_bvh failed (no 'blocked' test on this map): {e!r}")
    results = []
    climbed = {}
    for ri, r in enumerate(ctx.routes):
        fwd = check_route(ctx, r, ladders, obstacles)
        climbed[ri] = set(fwd.get("climbed", ()))
        results.append(fwd)
        if not r.get("one_way"):
            rev = check_route(ctx, r, ladders, obstacles, reverse=True)
            climbed[ri] |= set(rev.get("climbed", ()))
            # drops become unclimbable steps when walked back: only report if the forward walk was clean
            if fwd["ok"]:
                results.append(rev)
    # every portal must actually be reached by a declared route (within 1.5 m, same height +-0.45 m)
    reach_map = route_reach(ctx)
    reach = []
    for p in ctx.portals:
        reached, best = reach_map[p["name"]]
        if not reached:
            reach.append({"portal": p["name"], "nearest_route_point_m": None if best is None else round(best, 2)})
    portal_issues = []
    for p in ctx.portals:
        z = ctx.ground_z(p["x"], p["y"])
        if z is None or abs(z - p["z"]) > 0.35:
            portal_issues.append({"portal": p["name"], "ground": z, "portal_z": p["z"]})
    climb_issues = check_climbables(ctx, ladders)
    L, D = ctx.size
    bounds = []
    for o in list(ctx.col_terrain.objects):
        if o.type != "MESH":
            continue
        vs = o.data.vertices
        step = max(1, len(vs) // 400)
        cs = [ctx_local(ctx, o.matrix_world @ vs[i].co) for i in range(0, len(vs), step)]
        if not cs:
            continue
        xs = [c[0] for c in cs]
        ys = [c[1] for c in cs]
        if min(xs) < -6 or max(xs) > L + 6 or min(ys) < -6 or max(ys) > D + 6:
            bounds.append(o.name)
    try:
        graph = route_graph(ctx, reach_map, climbed)
    except Exception as e:  # noqa: BLE001
        graph = {"route_groups": None, "orphan_routes": [], "portal_groups": None, "portal_split": [],
                 "group_gaps": []}
        exceptions.append(f"route_graph failed: {e!r}")
    ok = (all(r["ok"] for r in results) and not portal_issues and not bounds and not climb_issues and not reach
          and not graph["portal_split"])
    out = {"routes": results, "portal_issues": portal_issues, "portal_unreachable": reach,
           "climbable_issues": climb_issues, "out_of_bounds_terrain": bounds, **graph, "ok": ok}
    if exceptions:
        out["exceptions"] = exceptions
    return out


def ctx_local(ctx, v):
    dx, dy = v.x - ctx.origin.x, v.y - ctx.origin.y
    c, s = math.cos(math.radians(-ctx.yaw)), math.sin(math.radians(-ctx.yaw))
    return (dx * c - dy * s, dx * s + dy * c)


CLEARABLE_CATEGORIES = ("Trees", "Foliage", "Rocks")


def clear_routes(ctx, half_width=0.9):
    """Remove scattered natural clutter (trees, bushes, flowers, rocks, logs...) standing on a route.

    Scatter calls run before routes are declared, so they cannot avoid them. Authored
    architecture and props are never touched; those are reported as 'blocked' instead.
    """
    removed = []
    for _ in range(3):
        bvh = obstacle_bvh(ctx)
        if bvh is None:
            break
        doomed = set()
        for route in ctx.routes:
            pts = geo.resample(route["pts"], SAMPLE, closed=False)
            for i, (x, y) in enumerate(pts):
                if i + 1 < len(pts):
                    dx, dy = pts[i + 1][0] - x, pts[i + 1][1] - y
                else:
                    dx, dy = x - pts[i - 1][0], y - pts[i - 1][1]
                L = math.hypot(dx, dy) or 1.0
                nx, ny = -dy / L, dx / L
                for off in (0.0, -half_width, half_width):
                    px, py = x + nx * off, y + ny * off
                    z = ctx.ground_z(px, py)
                    if z is None:
                        continue
                    w = ctx.w(px, py, z)
                    hit = bvh.ray_cast(Vector((w.x, w.y, w.z + BODY_Z[0])), Vector((0, 0, 1)), BODY_Z[1] - BODY_Z[0])
                    if hit[0] is None:
                        continue
                    name = owner_of(bvh, hit[2])
                    ob = bpy.data.objects.get(name)
                    if ob is None or ob.instance_type != "COLLECTION" or not ob.get("scattered"):
                        continue  # authored props (m.place) are reported as 'blocked', never deleted
                    info = kit.REGISTRY.get(ob.get("asset", ""), {})
                    if info.get("category") in CLEARABLE_CATEGORIES and "landmark" not in info.get("tags", ()):
                        doomed.add(name)
        if not doomed:
            break
        for name in doomed:
            ob = bpy.data.objects.get(name)
            if ob is not None:
                lx, ly = ctx_local(ctx, ob.location)
                removed.append(f"{ob.get('asset', name)}@{lx:.1f},{ly:.1f}")
                bpy.data.objects.remove(ob)
    return removed
