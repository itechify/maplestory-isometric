"""Inter-map trails: smoothed swept causeways with sloped grass flanks, stair flights with
landings on steep sections, and a pale 'main road' surface along the classic main route.

Each trail starts at the footprint edge of both maps (never inside a map), sits a few cm below any map or
plinth surface it meets (no coplanar z-fighting at the junction), and a draped apron ribbon in the trail's
surface material carries the road from the edge to the portal. Long trails curve through seeded lateral
waypoints. After all trails exist, `walk_trail` walks each one portal-to-portal over the combined ground.
"""

import math

from mathutils import Vector

from . import core, geo, kit

MAIN_ROAD_MAT = "M_Main_Road"
BRANCH_MAT = "M_Path_Dirt"
FLANK_MAT = "M_Grass"
MAX_RAMP_DEG = 20.0      # steeper middle sections become stair flights
HIDDEN_RAMP_DEG = 27.0   # hidden lanes stay grass ramps where they can (no stone stair look)
FLIGHT_RISE = 3.2        # rise per flight before a landing
LANDING = 2.4            # landing length (m)
SINK = 0.04              # trail top sits this far below a map/plinth surface it meets
CURVE_MIN_LEN = 28.0     # mid sections longer than this curve through lateral waypoints
RAIL_DROP = 2.0          # rails only where the side drop exceeds this
WALK_STEP = 0.3
WALK_MAX_STEP = 0.45
WALK_MAX_SLOPE = 38.0


def _profile(length_mid, rise, max_deg):
    """z offsets along the middle section: list of (s, dz, is_stair) breakpoints."""
    slope = math.degrees(math.atan2(abs(rise), max(length_mid, 0.1)))
    if slope <= max_deg or abs(rise) < 1.0:
        return [(0.0, 0.0, False), (length_mid, rise, False)], False
    k = max(1, math.ceil(abs(rise) / FLIGHT_RISE))
    land_total = LANDING * (k - 1)
    run = max((length_mid - land_total) / k, 0.6)
    pts = [(0.0, 0.0, False)]
    s = 0.0
    z = 0.0
    for i in range(k):
        s += run
        z += rise / k
        pts.append((s, z, True))
        if i < k - 1:
            s += LANDING
            pts.append((s, z, False))
    return pts, True


def _z_at(profile, s):
    if s <= profile[0][0]:
        return profile[0][1]
    for (s0, z0, _), (s1, z1, _st) in zip(profile, profile[1:]):
        if s <= s1:
            t = (s - s0) / max(s1 - s0, 1e-6)
            return z0 + (z1 - z0) * t
    return profile[-1][1]


def _catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def _middle(world, name, p0, p1, p2, p3, curve):
    """Sample the middle section p1 -> p2 (1 m spacing); curve long ones through lateral waypoints that stay
    clear of every map footprint."""
    mid_len = (p2 - p1).length
    straight = [p1.lerp(p2, k / max(2, int(mid_len))) for k in range(max(2, int(mid_len)) + 1)]
    if not curve or mid_len < CURVE_MIN_LEN:
        return straight
    u = (p2 - p1).normalized()
    side = Vector((-u.y, u.x))
    r = core.rng("trailcurve", name)
    n_way = 1 if mid_len < 45 else 2
    candidates = []
    for _ in range(10):
        offs = [r.uniform(6.0, 12.0) * r.choice((-1, 1)) for _ in range(n_way)]
        if n_way == 2 and r.random() < 0.6:
            offs[1] = -offs[0] * r.uniform(0.6, 1.0)  # gentle S-curve
        candidates.append(offs)
    for offs in candidates:
        ways = [p1.lerp(p2, (k + 1) / (n_way + 1)) + side * o for k, o in enumerate(offs)]
        ctrl = [p0, p1] + ways + [p2, p3]
        pts = []
        for i in range(1, len(ctrl) - 2):
            seg = (ctrl[i + 1] - ctrl[i]).length
            n = max(2, int(seg))
            for k in range(n):
                pts.append(_catmull(ctrl[i - 1], ctrl[i], ctrl[i + 1], ctrl[i + 2], k / n))
        pts.append(p2.copy())
        clear = True
        for q in pts[1:-1]:
            for poly, (x0, y0, x1, y1) in world.map_polys:
                if x0 <= q.x <= x1 and y0 <= q.y <= y1 and geo.point_in_poly(q.x, q.y, poly):
                    clear = False
                    break
            if not clear:
                break
        if clear:
            return pts
    return straight


def _poly_dist(p, poly):
    """(distance to the polygon boundary, nearest boundary point, inside?) for a 2D point."""
    best, near = 1e9, None
    n = len(poly)
    for i in range(n):
        a, b = Vector(poly[i]), Vector(poly[(i + 1) % n])
        d = b - a
        t = 0.0 if d.length_squared < 1e-9 else max(0.0, min(1.0, (p - a).dot(d) / d.length_squared))
        q = a + d * t
        if (p - q).length < best:
            best, near = (p - q).length, q
    return best, near, geo.point_in_poly(p.x, p.y, poly)


def _relax(points, polys, clear, iters=40, exempt=None):
    """Push the interior points of a polyline out of (and `clear` m away from) the given footprints, smoothing
    as it goes; the end points stay put. exempt: radius around the first/last point inside which a point
    ignores polys[0]/polys[1] (the map that end of the trail leaves from)."""
    pts = [p.copy() for p in points]
    if len(pts) < 3 or not polys:
        return pts
    cents = [Vector((sum(x for x, _ in pl) / len(pl), sum(y for _, y in pl) / len(pl))) for pl in polys]
    for _ in range(iters):
        for i in range(1, len(pts) - 1):
            for k, (poly, c) in enumerate(zip(polys, cents)):
                if exempt and ((k == 0 and (pts[i] - pts[0]).length < exempt) or
                               (k == 1 and (pts[i] - pts[-1]).length < exempt)):
                    continue
                d, near, inside = _poly_dist(pts[i], poly)
                if inside or d < clear:
                    out = (pts[i] - near) if not inside else (near - pts[i])
                    if out.length < 1e-6:
                        out = pts[i] - c
                    out.normalize()
                    pts[i] = pts[i] + out * ((clear + d if inside else clear - d) * 0.6)
        for i in range(1, len(pts) - 1):
            pts[i] = pts[i] * 0.5 + (pts[i - 1] + pts[i + 1]) * 0.25
    flat = geo.resample([(p.x, p.y) for p in pts], 1.0, closed=False)
    return [Vector(q) for q in flat]


def _polyline_at(pts, s_cum, s):
    """Position and unit direction at arc length s."""
    for i in range(1, len(pts)):
        if s <= s_cum[i] or i == len(pts) - 1:
            seg = max(s_cum[i] - s_cum[i - 1], 1e-6)
            t = min(1.0, max(0.0, (s - s_cum[i - 1]) / seg))
            d = pts[i] - pts[i - 1]
            return pts[i - 1].lerp(pts[i], t), (d.normalized() if d.length > 1e-6 else Vector((1, 0)))
    return pts[-1], Vector((1, 0))


def build_trail(world, name, a, b, ea, eb, na, nb, mapground=None, main=False, hidden=False, bridge_b=0.0,
                avoid=()):
    """One trail between two edge portals.

    a, b: portal world positions (Vector xyz). ea, eb: the footprint-edge points in front of them (Vector xyz,
    z = map ground just inside that edge). na, nb: outward edge normals (2D). mapground: GroundIndex of the map
    and plinth surfaces (junction sinking). bridge_b: the last bridge_b m before eb are a plank bridge.
    Returns (objects, info) where info feeds the apron and walk passes.
    """
    width = 5.2 if main else (3.4 if hidden else 3.8)
    za, zb = ea.z - SINK, eb.z - SINK
    d = (Vector((eb.x, eb.y)) - Vector((ea.x, ea.y))).length
    max_deg = HIDDEN_RAMP_DEG if hidden else MAX_RAMP_DEG
    reach = min(5.0, max(1.5, d / 3.2))
    if d < 2 * reach + 1.0:  # very short link: tiny exits, the rest is the climb
        reach = max(0.4, (d - 1.0) / 2)
    elif abs(zb - za) >= 1.0 and math.degrees(math.atan2(abs(zb - za), d - 2 * reach)) > max_deg and             math.degrees(math.atan2(abs(zb - za), d - 3.0)) <= max_deg:
        reach = 1.5  # shorter flat exits let the whole climb be a ramp instead of stairs
    est, est_st = _profile(max(d - 2 * reach, 0.1), zb - za, max_deg)
    if est_st and reach > 1.5:  # stairs: keep the flights near 35 deg by giving them the exit length
        k_f = sum(1 for (_s, _z, st) in est[1:] if st)
        run_f = (max(d - 2 * reach, 0.1) - LANDING * (k_f - 1)) / k_f
        if math.degrees(math.atan2(abs(zb - za) / k_f, max(run_f, 0.1))) > 36.0:
            reach = 1.5
    p0 = Vector((ea.x, ea.y))
    p3 = Vector((eb.x, eb.y))
    p1 = p0 + na * reach
    p2 = p3 + nb * reach
    middle = _middle(world, name, p0, p1, p2, p3, curve=not hidden)
    if avoid and (p2 - p1).length > 12.0:  # keep the trail body off the two maps it joins (offset exits)
        middle = _relax(middle, avoid, width / 2 + 2.0, exempt=width / 2 + 4.0)
    ne = max(1, int(round(reach / 0.5)))  # rows every ~0.5 m across the junction exits
    pts = [p0.lerp(p1, k / ne) for k in range(ne)] + middle + [p2.lerp(p3, k / ne) for k in range(1, ne + 1)]
    s_cum = [0.0]
    for i in range(1, len(pts)):
        s_cum.append(s_cum[-1] + (pts[i] - pts[i - 1]).length)
    s1 = reach
    s_end = s_cum[-1]
    s2 = s_end - reach
    mid_len = max(s2 - s1, 0.1)
    profile, stairs = _profile(mid_len, zb - za, max_deg)
    flights = [(s1 + s0, s1 + sb) for (s0, _z0, _), (sb, _zb, st) in zip(profile, profile[1:]) if st]

    def under_flight(s):  # inside a flight the solid ducks just under the treads (their masonry fills the rest)
        return any(f0 - 0.05 <= s <= f1 + 0.05 for f0, f1 in flights)

    def z_of(s):
        if s <= s1:
            return za
        if s >= s2:
            return zb
        return za + _z_at(profile, s - s1)

    top_mat = MAIN_ROAD_MAT if main else ("M_Grass" if hidden else BRANCH_MAT)
    s_cut = s_end - bridge_b if bridge_b > 0 else s_end + 1.0
    if bridge_b > 0:  # an exact row where the causeway ends and the bridge begins (no gap between them)
        p_cut, _u = _polyline_at(pts, s_cum, s_cut)
        k = next(i for i in range(1, len(s_cum)) if s_cum[i] > s_cut)
        pts.insert(k, p_cut)
        s_cum.insert(k, s_cut)
    mb = geo.MeshBuilder()
    bm = mb.bm
    ti = mb.mat(top_mat)
    fi = mb.mat(FLANK_MAT)
    di = mb.mat("M_Dirt_Cliff")
    rows = []
    row_drop = []
    for i, p in enumerate(pts):
        if s_cum[i] > s_cut + 0.01:
            break
        q = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        if q.length < 1e-6:
            q = Vector((1, 0))
        q.normalize()
        nrm = Vector((-q.y, q.x))
        s = s_cum[i]
        z = z_of(s) - (0.06 if under_flight(s) else 0.0)
        half = width / 2
        if mapground is not None and (s <= s1 + 0.5 or s >= s2 - 0.5):
            # junction: never coplanar with (or poking through) a map or plinth surface
            for off in (-half, 0.0, half):
                e = p + nrm * off
                zm = mapground.raycast_down(e.x, e.y, z_from=z + 1.0)[0]
                if zm is not None and -0.6 < zm - z < 0.6 and zm < z + SINK + 0.01:
                    z = min(z, zm - SINK)
        row = []
        drops = []
        for sd in (1, -1):
            edge = p + nrm * half * sd
            gz = world.ground.raycast_down(edge.x + nrm.x * sd * 3.0, edge.y + nrm.y * sd * 3.0)[0]
            drop = max(1.2, min(14.0, z - (gz if gz is not None else z - 3.0) + 0.4))
            drops.append(drop)
            foot = edge + nrm * sd * min(drop * 0.85, 9.0)
            row.append((bm.verts.new((edge.x, edge.y, z)), bm.verts.new((foot.x, foot.y, z - drop))))
        rows.append(row)
        row_drop.append((s, p, nrm, z, drops))
    for i in range(len(rows) - 1):
        (lt, lf), (rt, rf) = rows[i]
        (lt2, lf2), (rt2, rf2) = rows[i + 1]
        bm.faces.new((rt, rt2, lt2, lt)).material_index = ti
        bm.faces.new((lt, lt2, lf2, lf)).material_index = fi
        bm.faces.new((rf, rf2, rt2, rt)).material_index = fi
    for row, flip in ((rows[0], True), (rows[-1], False)):
        (lt, lf), (rt, rf) = row
        f = bm.faces.new((lf, lt, rt, rf) if flip else (rf, rt, lt, lf))
        f.material_index = di
    obj = mb.build(name, world.coll_trails, smooth=True, sharp_angle=40)
    world.ground.add(obj)
    objs = [obj]
    stair_chords = []
    # stair flights with landings on steep sections (solid); main road treads are the cream road surface
    if stairs:
        tread, cheek = ("M_Main_Road", "M_Rock") if main else (("M_Grass", "M_Dirt_Cliff") if hidden else
                                                               ("M_StoneWall", "M_Rock"))
        for (s0, z0, _), (sb, zb_, st) in zip(profile, profile[1:]):
            if not st:
                continue
            q0, _u0 = _polyline_at(pts, s_cum, s1 + s0)
            q1, _u1 = _polyline_at(pts, s_cum, s1 + sb)
            lo, hi = Vector((q0.x, q0.y, za + z0)), Vector((q1.x, q1.y, za + zb_))
            if lo.z > hi.z:
                lo, hi = hi, lo
            objs.append(geo.stairs(f"{name}_Flight", lo, hi, width - 0.6, world.coll_trails, mat=tread,
                                   side_mat=cheek, ground_index=world.ground, overshoot=0.3))
            stair_chords.append(((q0.x, q0.y), (q1.x, q1.y)))
        for (s0, z0, st0), (sb, zb_, st) in zip(profile, profile[1:]):
            if st or sb - s0 < 0.5:
                continue
            q0, _ = _polyline_at(pts, s_cum, s1 + s0)
            q1, _ = _polyline_at(pts, s_cum, s1 + sb)
            u = (q1 - q0)
            if u.length < 1e-6:
                continue
            m = geo.MeshBuilder()
            c = (q0 + q1) / 2
            m.box((u.length + 0.2, width - 0.6, 0.3), loc=(c.x, c.y, za + z0 - 0.12 + 0.03),
                  rot=(0, 0, math.degrees(math.atan2(u.y, u.x))), mat=tread, bevel=0.04, segs=1)
            lob = m.build(f"{name}_Landing", world.coll_trails, smooth=False)
            world.ground.add(lob)
            objs.append(lob)
    # plank bridge over the last bridge_b m (e.g. onto a floating arrival hub)
    if bridge_b > 0:
        objs += _plank_bridge(world, name, pts, s_cum, s_cut, s_end, z_of, 3.0)
    # edge dressing: hedges for hidden lanes; rails only over real drops; shrub clumps along long trails
    r = core.rng("traildress", name)
    if hidden:
        for k in range(0, len(row_drop) - 1, 4):
            s, p, nrm, z, _dr = row_drop[k]
            _q, u = _polyline_at(pts, s_cum, s)
            for sd in (-1, 1):
                q = p + nrm * ((width / 2 + 0.5) * sd)
                kit.instance("Hedge_Wall_4m", world.coll_trails, (q.x, q.y, z - 0.1),
                             rot_z=math.degrees(math.atan2(u.y, u.x)), scale=(1.05, 1.0, 1.15), obj_name="Trail_Hedge")
    else:
        for k, (s, p, nrm, z, drops) in enumerate(row_drop):
            if not (s1 + 1.0 < s < s2 - 1.0) or k % 4:
                continue
            _q, u = _polyline_at(pts, s_cum, s)
            for sd, drop in zip((1, -1), drops):
                if drop < RAIL_DROP:
                    continue
                q = p + nrm * ((width / 2 - 0.3) * sd)
                kit.instance("Fence_Wood_Seg", world.coll_trails, (q.x, q.y, z - 0.05),
                             rot_z=math.degrees(math.atan2(u.y, u.x)), scale=(0.9, 1, 0.8), obj_name="Trail_Rail")
        if mid_len > 20:
            for k, (s, p, nrm, z, drops) in enumerate(row_drop):
                if not (s1 + 2.0 < s < s2 - 2.0) or k % 6:
                    continue
                sd = 1 if (k // 6) % 2 else -1
                off = width / 2 + min(drops[0 if sd == 1 else 1] * 0.85, 9.0) + r.uniform(0.8, 2.5)
                q = p + nrm * off * sd
                gz = world.ground.raycast_down(q.x, q.y)[0]
                if gz is None or world.keep.blocked(q.x, q.y, pad=0.0):
                    continue
                for j in range(r.randint(1, 3)):
                    jx, jy = q.x + r.uniform(-1.2, 1.2), q.y + r.uniform(-1.2, 1.2)
                    jz = world.ground.raycast_down(jx, jy)[0]
                    if jz is None:
                        continue
                    kit.instance(r.choice(["Bush_A", "Bush_B", "Bush_C"]), world.coll_trails, (jx, jy, jz - 0.05),
                                 rot_z=r.uniform(0, 360), scale=r.uniform(0.9, 1.4), obj_name="Trail_Shrub")
        for end, sdir, z in ((p1, (p1 - p0).normalized(), za), (p2, (p2 - p3).normalized(), zb)):
            q = end + Vector((-sdir.y, sdir.x)) * (width / 2 + 0.9)
            gz = world.ground.raycast_down(q.x, q.y, z_from=z + 2.0)[0]  # stand on the flank, not in the air
            z = gz + 0.05 if gz is not None else z
            kit.instance("Sign_Arrow", world.coll_trails, (q.x, q.y, z - 0.05),
                         rot_z=math.degrees(math.atan2(sdir.y, sdir.x)), obj_name=f"TrailSign_{name}")
    for i in range(len(pts) - 1):
        world.keep.segments.append(((pts[i].x, pts[i].y), (pts[i + 1].x, pts[i + 1].y), width / 2 + 4.0))
    slope = math.degrees(math.atan2(abs(zb - za), max(mid_len, 0.1)))
    entry = {"trail": name, "length_m": round(s_end, 1), "rise_m": round(zb - za, 2), "slope_deg": round(slope, 1),
             "kind": "stairs+landings" if stairs else "ramp", "main_road": main, "hidden": hidden,
             "curved": _max_offset(middle, p1, p2) > 2.0,
             "bridge_m": bridge_b}
    world.trail_report.append(entry)
    info = {"name": name, "entry": entry, "a": a, "b": b, "ea": ea, "eb": eb, "na": na, "nb": nb,
            "pts": pts, "width": width, "top_mat": top_mat, "reach": reach, "hidden": hidden,
            "stair_chords": stair_chords}
    return objs, info


def _max_offset(pts, a, b):
    """Largest lateral distance of pts from the straight line a-b."""
    d = b - a
    L = max(d.length, 1e-6)
    return max((abs((q.x - a.x) * d.y - (q.y - a.y) * d.x) / L for q in pts), default=0.0)


def _plank_bridge(world, name, pts, s_cum, s0, s1, z_of, width):
    """Plank deck on rope rails from arc length s0 to s1 (nothing underneath)."""
    mb = geo.MeshBuilder()
    s = s0
    k = 0
    while s < s1 - 0.05:
        p, u = _polyline_at(pts, s_cum, s + 0.2)
        z = z_of(s)
        mb.box((0.47, width, 0.12), loc=(p.x, p.y, z - 0.06), rot=(0, 0, math.degrees(math.atan2(u.y, u.x))),
               mat="M_Wood_Dark" if k % 3 else "M_Wood", bevel=0.02, segs=1)  # 0.47 every 0.42: planks overlap
        s += 0.42
        k += 1
    deck = mb.build(f"{name}_BridgeDeck", world.coll_trails, smooth=False)
    world.ground.add(deck)
    rails = geo.MeshBuilder()
    for sd in (-1, 1):
        ring = []
        s = s0
        while s <= s1 + 1e-6:
            p, u = _polyline_at(pts, s_cum, s)
            side = Vector((-u.y, u.x)) * (width / 2 - 0.1) * sd
            ring.append(Vector((p.x + side.x, p.y + side.y, z_of(s) + 1.0)))
            rails.cyl(0.09, 1.2, loc=(p.x + side.x, p.y + side.y, z_of(s) - 0.08), mat="M_Wood", verts=8)
            s += 1.6
        if len(ring) >= 2:  # two rope rails, so the span reads as a bridge from the island cameras
            rails.tube(ring, 0.05, mat="M_Rope", sides=6)
            rails.tube([q - Vector((0.0, 0.0, 0.45)) for q in ring], 0.04, mat="M_Rope", sides=6)
    objs = [deck, rails.build(f"{name}_BridgeRails", world.coll_trails, smooth=True)]
    for s_end_, sgn in ((s0 + 0.5, -1), (s1 - 0.5, 1)):  # a lamp on the deck at each end of the span
        p, u = _polyline_at(pts, s_cum, s_end_)
        q = p + Vector((-u.y, u.x)) * (width / 2 - 0.35) * sgn
        kit.instance("Lamp_Post", world.coll_trails, (q.x, q.y, z_of(s_end_) - 0.03), obj_name=f"{name}_BridgeLamp")
    return objs


def apron(world, info, ground):
    """Draped road ribbons from each portal out over the junction, in the trail's surface material."""
    if info["hidden"]:
        return []
    objs = []
    for tag, portal, edge, n in (("A", info["a"], info["ea"], info["na"]), ("B", info["b"], info["eb"], info["nb"])):
        if tag == "B" and info["entry"].get("bridge_m"):
            continue  # a plank bridge arrives here: no sand apron over the planks
        pv = Vector((portal.x, portal.y))
        ev = Vector((edge.x, edge.y))
        start = pv - n * 0.6
        end = ev + n * (info["reach"] + 0.8)
        if (end - start).length < 0.8:
            continue
        objs.append(geo.path_ribbon(f"{info['name']}_Apron{tag}", [start, (start + end) / 2, end],
                                    info["width"] * 0.82, world.coll_trails, ground, mat=info["top_mat"],
                                    lift=0.03, edge_wobble=0.05, end_taper=0.6))
    return objs


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy))


def walk_trail(info, ground):
    """Walk portal A -> portal B over the combined ground (both maps, plinths, trails). Steps above
    WALK_MAX_STEP, slopes above WALK_MAX_SLOPE off stair flights, and missing ground are issues."""
    a, b = info["a"], info["b"]
    poly = [Vector((a.x, a.y))] + [p.copy() for p in info["pts"]] + [Vector((b.x, b.y))]
    samples = geo.resample([(p.x, p.y) for p in poly], WALK_STEP, closed=False)
    issues = []
    zs = []
    z_prev = a.z
    for (x, y) in samples:
        z = ground.height_below(x, y, z_prev + 1.6)
        if z is None:
            z = ground.height_below(x, y, z_prev + 6.0)
        if z is None:
            z = ground.raycast_down(x, y)[0]
        zs.append(z)
        if z is not None:
            z_prev = z
    for i in range(len(samples) - 1):
        z0, z1 = zs[i], zs[i + 1]
        x1, y1 = samples[i + 1]
        if z0 is None or z1 is None:
            issues.append({"type": "no_ground", "at": [round(x1, 1), round(y1, 1)]})
            continue
        if abs(z1 - z0) > WALK_MAX_STEP:
            issues.append({"type": "step", "at": [round(x1, 1), round(y1, 1)], "dz": round(z1 - z0, 2)})
            continue
        j = min(len(samples) - 1, i + 4)
        if zs[j] is None:
            continue
        run = math.hypot(samples[j][0] - samples[i][0], samples[j][1] - samples[i][1])
        if run < 0.75:
            continue
        slope = math.degrees(math.atan2(abs(zs[j] - z0), run))
        on_stair = any(_seg_dist(samples[i], c0, c1) < 1.2 for c0, c1 in info["stair_chords"])
        if slope > WALK_MAX_SLOPE and not on_stair:
            issues.append({"type": "steep", "at": [round(x1, 1), round(y1, 1)], "deg": round(slope, 1)})
    # one issue per metre is plenty
    dedup = []
    for it in issues:
        if not dedup or math.hypot(it["at"][0] - dedup[-1]["at"][0], it["at"][1] - dedup[-1]["at"][1]) > 1.0 or \
                it["type"] != dedup[-1]["type"]:
            dedup.append(it)
    return {"ok": not dedup, "issues": dedup[:20]}
