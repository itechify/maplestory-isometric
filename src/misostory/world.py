"""Island-scale construction: plinths under maps, the floating island body, trails
between maps, the inland lake + waterfall, mountains, forest filler, clouds, sea.

Everything here is derived from ``layout`` so the island always wraps the maps.
"""

import math

import bmesh
import bpy
from mathutils import Vector, noise

from . import core, geo, kit
from . import layout as LY
from . import materials as M
from .scene_setup import ISO_PITCH

STEP = 3.0  # plinth terrace step height


# ---------------------------------------------------------------- helpers

def convex_hull(points):
    pts = sorted(set(points))
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


def portal_sides(mid):
    """Local outward normals (as 'left'/'right'/'front'/'back') of the footprint edges that carry an edge portal."""
    m = LY.MAPS[mid]
    names = [ca for c, ca, p, pa, _g, _b in LY.LINKS if c == mid] + [pa for c, ca, p, pa, _g, _b in LY.LINKS if p == mid]
    sides = set()
    for n in names:
        if n not in m["anchors"]:
            continue
        x, y, _z = m["anchors"][n]
        d = {"left": x, "right": m["L"] - x, "front": y, "back": m["D"] - y}
        sides.add(min(d, key=d.get))
    return sides


def rounded_footprint(mid, origins, margin, corner=6.0, seed=0, wobble_amt=1.2, front=None, sides=None):
    """front: margin on the local -y edge if different (e.g. a map whose front edge is the island cliff).
    sides: {'left'|'right'|'front'|'back': margin} overrides per edge."""
    m = LY.MAPS[mid]
    o = origins[mid]
    sm = dict(sides or {})
    if front is not None:
        sm["front"] = front
    ml, mr = sm.get("left", margin), sm.get("right", margin)
    mf, mbk = sm.get("front", margin), sm.get("back", margin)
    poly = geo.rounded_rect(-ml, -mf, m["L"] + mr, m["D"] + mbk, corner + min(ml, mr, mf, mbk) * 0.5, seg=4)
    yaw = LY.world_yaw(mid)
    wp = geo.transform_poly(poly, (o[0], o[1]), yaw)
    wp = geo.resample(wp, 3.0)
    return geo.wobble(wp, wobble_amt, seed=seed, freq=0.12)


def seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy or 1e-9
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


class Keepout:
    """2D exclusion test used by scenery scattering."""

    def __init__(self):
        self.polys = []
        self.segments = []  # (a, b, radius)
        self.circles = []

    def add_poly(self, poly):
        self.polys.append((poly, geo.poly_bbox(poly)))

    def blocked(self, x, y, pad=0.0):
        for poly, (x0, y0, x1, y1) in self.polys:
            if x0 - pad <= x <= x1 + pad and y0 - pad <= y <= y1 + pad:
                if geo.point_in_poly(x, y, poly):
                    return True
                if pad > 0 and any(math.hypot(x - px, y - py) < pad for px, py in poly[::2]):
                    return True
        for a, b, r in self.segments:
            if seg_dist((x, y), a, b) < r + pad:
                return True
        for cx, cy, r in self.circles:
            if math.hypot(x - cx, y - cy) < r + pad:
                return True
        return False


def occludes_map(x, y, height, radius, map_polys):
    """True if an object at (x, y) of this height would hide map ground from the iso camera.

    The camera looks toward world +X+Y, so an object hides ground behind it (to the
    north-east) up to ~height / tan(pitch) away.
    """
    reach = height / math.tan(math.radians(ISO_PITCH)) + radius
    d = Vector((1, 1)).normalized()
    side = Vector((-d.y, d.x))
    for t in (0.0, 0.25, 0.5, 0.75, 1.0):
        for s in (-1, 0, 1):
            q = Vector((x, y)) + d * (reach * t) + side * (radius * 0.8 * s)
            for poly, (x0, y0, x1, y1) in map_polys:
                if x0 <= q.x <= x1 and y0 <= q.y <= y1 and geo.point_in_poly(q.x, q.y, poly):
                    return True
    return False


# ---------------------------------------------------------------- builders

class World:
    def __init__(self, origins=None):
        self.origins = origins or LY.resolve()
        self.coll_base = core.get_collection("WORLD/World_IslandBody")
        self.coll_plinth = core.get_collection("WORLD/World_Plinths")
        self.coll_trails = core.get_collection("WORLD/World_Trails")
        self.coll_scenery = core.get_collection("WORLD/World_Scenery")
        self.coll_forest = core.get_collection("WORLD/World_Forest")
        self.coll_sky = core.get_collection("WORLD/World_SkyAndSea")
        self.ground = core.GroundIndex()
        self.trail_report = []
        self.keep = Keepout()
        self.map_polys = []
        self.island_outline = None
        for mid in LY.exterior_ids():
            fp = LY.footprint_world(mid, self.origins, margin=1.0)
            self.map_polys.append((fp, geo.poly_bbox(fp)))

    # -- plinths: stepped grassy terraces that lift each map to its base height
    def plinth(self, mid):
        """The top ring a map stands on (grass cap + cliff), and below it a sloped grassy hill skirt."""
        m = LY.MAPS[mid]
        top = m["z"]
        style = "grass_stone" if m["street"] == "Rainbow Street" and m["kind"] == "town" else "grass_dirt"
        if mid == 60000:
            style = "grass_sand"
        front = 0.3 if LY.RIM_EDGE.get(mid) == "front" else None
        thin = {s: 0.8 for s in portal_sides(mid)}  # trails leave over a thin ring, not a 4 m shelf
        poly0 = rounded_footprint(mid, self.origins, 4.0, seed=mid % 997, wobble_amt=0.0 if (front or thin) else 1.0,
                                  front=front, sides=thin)
        bottom0 = top - 2.6 if top > 2.6 else -1.5
        objs = geo.terrace(f"Plinth_{m['slug']}_Top", poly0, top, bottom0, self.coll_plinth, style=style, seed=mid,
                           wobble_amt=0.0, ground_index=self.ground)
        if top > 2.6:
            objs.append(self._hill_skirt(mid, poly0, bottom0 + 0.35))
        self.keep.add_poly(rounded_footprint(mid, self.origins, 6.0, seed=1, wobble_amt=0.0,
                                             front=0.5 if front else None))
        return objs

    def _hill_skirt(self, mid, poly0, z_top):
        """Sloped grass hill from under the top ring down to the island ground, with rock outcrops."""
        r = core.rng("skirt", mid)
        inner = geo.resample(geo.ensure_ccw(poly0), 2.5)
        run = (z_top + 1.0) * 1.35 + 2.0
        rings = [(0.15, z_top), (0.42 * run, z_top * 0.42), (run, -1.0)]
        mb = geo.MeshBuilder()
        bm = mb.bm
        gi = mb.mat("M_Hill")
        rows = []
        n = len(inner)
        for k, (off, z) in enumerate(rings):
            poly = geo.offset_poly(inner, off) if off > 0 else inner
            if k == 2:
                poly = geo.wobble(poly, run * 0.22, seed=mid % 97, freq=0.06)
            rows.append([bm.verts.new((x, y, z + (noise.noise(Vector((x * 0.05, y * 0.05, k))) * 0.8 if k == 1 else 0)))
                         for x, y in poly])
        for k in range(len(rows) - 1):
            for i in range(n):
                f = bm.faces.new((rows[k][i], rows[k + 1][i], rows[k + 1][(i + 1) % n], rows[k][(i + 1) % n]))
                f.material_index = gi
        mid_ring = [v.co.copy() for v in rows[1]]  # capture before the bmesh is freed by build()
        obj = mb.build(f"Plinth_{LY.MAPS[mid]['slug']}_Skirt", self.coll_plinth, smooth=True, sharp_angle=55)
        self.ground.add(obj)
        for i in range(0, n, max(1, n // 7)):
            if r.random() < 0.6:
                v = mid_ring[i]
                kit.instance(r.choice(["Rock_B", "Rock_A", "Rock_Boulder"]), self.coll_plinth, (v.x, v.y, v.z - 0.3),
                             rot_z=r.uniform(0, 360), scale=r.uniform(0.7, 1.4), obj_name="Plinth_Outcrop")
        return obj

    # -- island body
    def island(self):
        pts = []
        for mid in LY.exterior_ids():
            pts += LY.footprint_world(mid, self.origins, margin=LY.RIM_MARGIN.get(mid, LY.ISLAND_MARGIN))
        lake = self.lake_poly(extra=30.0)
        pts += lake
        for ridge in LY.RIDGES:  # ridges that wrap behind maps need ground under their peaks
            if ridge.get("pocket"):
                for gx, gy in ridge["pts"]:
                    wx, wy = LY.geo_to_world(gx, gy)
                    pts += geo.ellipse(wx, wy, ridge["radius"][1] + 8.0, ridge["radius"][1] + 8.0, 12)
        hull = convex_hull(pts)
        outline = geo.resample(geo.ensure_ccw(hull), 6.0)
        # keep the rim tight where a map uses it as its own edge (no wobble eating into the quay)
        tight = [LY.footprint_world(mid, self.origins, margin=LY.RIM_MARGIN[mid] + 6.0) for mid in LY.RIM_MARGIN]

        def near_tight(p):
            return any(geo.point_in_poly(p[0], p[1], poly) for poly in tight)
        wob = geo.wobble(outline, 9.0, seed=7, freq=0.02)
        wob = geo.wobble(wob, 3.0, seed=9, freq=0.08)
        outline = [p if near_tight(p) else q for p, q in zip(outline, wob)]
        outline = geo.chaikin(outline, 2)
        self.island_outline = outline
        self.lake_outline = self.natural_lake_poly()
        geo.terrace("Island_Ground", outline, 0.0, -18.0, self.coll_base, style="grass_dirt", wobble_amt=0.0,
                    smooth_iters=0, resample_step=4.0, ground_index=self.ground, holes=[self.lake_outline],
                    stones=False)
        self.underside(outline)
        return outline

    def underside(self, outline):
        """Tapered rocky underbelly: the island floats, like the classic world map."""
        cx = sum(p[0] for p in outline) / len(outline)
        cy = sum(p[1] for p in outline) / len(outline)
        ring_src = geo.resample(outline, 8.0)
        mb = geo.MeshBuilder()
        bm = mb.bm
        mi = mb.mat("M_Rock_Under")
        stal = []
        rings = []
        levels = [(-17.5, 1.0), (-40, 1.0), (-62, 0.98), (-88, 0.9), (-118, 0.72), (-150, 0.5), (-185, 0.27),
                  (-215, 0.1)]
        for k, (z, f) in enumerate(levels):
            ring = []
            for i, (x, y) in enumerate(ring_src):
                px = cx + (x - cx) * f
                py = cy + (y - cy) * f
                amp = (0.0, 0.35, 0.75)[k] if k < 3 else 1.0  # sheer under the rim, rugged further down
                n = (noise.noise(Vector((px * 0.012, py * 0.012, k * 0.7))) * 26.0 * (1 - f * 0.5) +
                     noise.noise(Vector((px * 0.05, py * 0.05, k * 1.3))) * 6.0) * amp
                dx, dy = px - cx, py - cy
                L = math.hypot(dx, dy) or 1
                ring.append(bm.verts.new((px + dx / L * n, py + dy / L * n, z + noise.noise(
                    Vector((px * 0.05, py * 0.05, 3.0))) * 4.0 * (k > 0))))
            rings.append(ring)
        n = len(ring_src)
        for k in range(len(rings) - 1):
            for i in range(n):
                f = bm.faces.new((rings[k][i], rings[k + 1][i], rings[k + 1][(i + 1) % n], rings[k][(i + 1) % n]))
                f.material_index = mi
        tip = bm.verts.new((cx + 20, cy - 10, -250))
        for i in range(n):
            f = bm.faces.new((rings[-1][i], tip, rings[-1][(i + 1) % n]))
            f.material_index = mi
        mb.build("Island_Underside", self.coll_base, smooth=True, sharp_angle=60)

    # -- lake + waterfall
    def lake_poly(self, extra=0.0):
        L = LY.LAKE
        cx, cy = LY.geo_to_world(*L["center"])
        rot = math.radians(L["rot"] + LY.GEO_ROT)
        return geo.ellipse(cx, cy, L["rx"] + extra, L["ry"] + extra, 40, rot=rot)

    def natural_lake_poly(self):
        """Lobed lake outline (world xy) around the layout lake center."""
        L = LY.LAKE
        cx, cy = LY.geo_to_world(*L["center"])
        rot = math.radians(L["rot"] + LY.GEO_ROT)
        pts = []
        for i in range(72):
            a = 2 * math.pi * i / 72
            k = 1 + 0.16 * math.sin(2 * a + 0.7) + 0.1 * math.sin(3 * a + 2.1) + 0.05 * math.sin(5 * a)
            x, y = L["rx"] * k * math.cos(a), L["ry"] * k * math.sin(a)
            c, s_ = math.cos(rot), math.sin(rot)
            pts.append((cx + x * c - y * s_, cy + x * s_ + y * c))
        return geo.wobble(geo.ensure_ccw(pts), 2.5, seed=11, freq=0.05)

    def lake(self):
        """Natural lake sunk below the island ground, sloped sandy banks, cliff waterfall in two tiers."""
        poly = getattr(self, "lake_outline", None) or self.natural_lake_poly()
        water_z = -1.1
        bed_z = -3.2
        # banks: hole edge (z 0) -> beach shelf -> bed
        inner1 = geo.offset_poly(poly, -3.0)
        inner2 = geo.offset_poly(poly, -6.5)
        mb = geo.MeshBuilder()
        bm = mb.bm
        bi = mb.mat("M_Beach")
        di = mb.mat("M_Path_Dirt")
        rings = [[bm.verts.new((x, y, 0.05)) for x, y in poly],
                 [bm.verts.new((x, y, water_z + 0.15)) for x, y in inner1],
                 [bm.verts.new((x, y, bed_z)) for x, y in inner2]]
        n = len(poly)
        for k in range(2):
            for i in range(n):
                f = bm.faces.new((rings[k][i], rings[k][(i + 1) % n], rings[k + 1][(i + 1) % n], rings[k + 1][i]))
                f.material_index = bi if k == 0 else di
        centre = bm.verts.new((sum(p[0] for p in inner2) / n, sum(p[1] for p in inner2) / n, bed_z - 0.4))
        for i in range(n):
            bm.faces.new((rings[2][i], rings[2][(i + 1) % n], centre)).material_index = di
        bank = mb.build("Lake_Banks", self.coll_scenery, smooth=True, sharp_angle=50)
        self.ground.add(bank)
        geo.flat_poly("Lake_Water", geo.offset_poly(poly, -1.2), water_z, self.coll_scenery, "M_Water")
        geo.foam_ring("Lake_Foam", geo.offset_poly(poly, -1.25), water_z + 0.03, -0.7, self.coll_scenery, seed=3)
        self.keep.add_poly(geo.offset_poly(poly, 7.0))
        # waterfall: a crescent rock cliff north of the lake, falling in two tiers onto a splash ledge
        W = LY.WATERFALL
        L = LY.LAKE
        tx, ty = LY.geo_to_world(*W["top"])
        cxl, cyl = LY.geo_to_world(*L["center"])
        d = Vector((cxl - tx, cyl - ty)).normalized()
        side = Vector((-d.y, d.x))
        h = W["height"] + 6.0
        rw = core.rng("waterfall", 9)

        def crest(t):  # the crescent's front line (t = -1 west .. 1 east); t = 0 is the falls' lip
            return Vector((tx, ty)) - d * (4 + 12 * t * t) + side * (34 * t)

        # the cliff as three overlapping lobes of different heights (no uniform cake top); the centre lobe carries
        # the lip at full height h for the upper sheet, the wings sit lower and wobble more
        dress = []
        for tag, t0, t1, hf, wob, seed in (("W", -1.0, -0.25, 0.80, 2.8, 31), ("C", -0.35, 0.35, 1.0, 0.8, 21),
                                           ("E", 0.25, 1.0, 0.88, 2.6, 41)):
            band_f, band_b = [], []
            for i in range(10):
                t = t0 + (t1 - t0) * i / 9
                p = crest(t)
                band_f.append(p)
                band_b.append(p - d * (16 + 4 * abs(t) + rw.uniform(-1.5, 1.5)))
            lobe = [(p.x, p.y) for p in band_f] + [(p.x, p.y) for p in reversed(band_b)]
            geo.terrace(f"Waterfall_Cliff_{tag}", lobe, h * hf, -1.0, self.coll_scenery, style="grass_rock",
                        wobble_amt=wob, seed=seed, ground_index=self.ground)
            dress += [(p, h * hf) for p in band_f[1:-1:2]]
        # irregular, non-concentric front tiers (different depths, jittered fronts) and a low shoulder
        for tag, t0, t1, hf, fwd, depth, seed in (("W", -1.0, -0.3, 0.58, 7.0, 3.0, 23),
                                                  ("E", 0.32, 1.0, 0.5, 9.5, 4.5, 24),
                                                  ("WS", -0.95, -0.55, 0.3, 13.0, 3.5, 25)):
            band_f, band_b = [], []
            for i in range(9):
                t = t0 + (t1 - t0) * i / 8
                jf = fwd + 2.5 * math.sin(2.7 * math.pi * t + seed) + rw.uniform(-1.0, 1.0)
                p = crest(t) + d * jf
                band_f.append(p)
                band_b.append(p - d * (depth + jf * 0.5))
            tier = [(p.x, p.y) for p in band_f] + [(p.x, p.y) for p in reversed(band_b)]
            geo.terrace(f"Waterfall_Tier_{tag}", tier, h * hf, -1.0, self.coll_scenery, style="grass_rock",
                        wobble_amt=1.8, seed=seed, ground_index=self.ground)
            dress += [(p, h * hf) for p in band_f[1:-1:2]]
        # break the flat lobe tops: low rocky crags, boulders and a few trees along each lobe's back half
        for k in range(14):
            t = -1.0 + 2.0 * (k + 0.5) / 14
            if abs(t) < 0.18:
                continue  # keep the river and the falls' lip clear
            q = crest(t) - d * rw.uniform(6.0, 14.0) + side * rw.uniform(-2.0, 2.0)
            gz = self.ground.raycast_down(q.x, q.y, z_from=h + 20.0)[0]
            if gz is None or gz < h * 0.45:
                continue
            pick = k % 3
            if pick == 0:
                cr = rw.uniform(3.5, 5.5)
                kit.instance("Mountain_Peak_Rocky", self.coll_scenery, (q.x, q.y, gz - 1.0), rot_z=rw.uniform(0, 360),
                             scale=(cr, cr, cr * rw.uniform(1.1, 1.6) / 2.1), obj_name="Waterfall_Crag")
            elif pick == 1:
                kit.instance("Rock_Boulder", self.coll_scenery, (q.x, q.y, gz - 0.3), rot_z=rw.uniform(0, 360),
                             scale=rw.uniform(1.4, 2.4), obj_name="Waterfall_TopBoulder")
            else:
                kit.instance(rw.choice(["Tree_Pine_A", "Tree_Round_B", "Tree_Tall_A"]), self.coll_scenery,
                             (q.x, q.y, gz - 0.1), rot_z=rw.uniform(0, 360), scale=rw.uniform(0.9, 1.3),
                             obj_name="Waterfall_TopTree")
        # boulders in the faces and bush clumps on the lips
        dyaw = math.degrees(math.atan2(d.y, d.x))
        for k, (p, top) in enumerate(dress):
            if abs((p - Vector((tx, ty))).dot(side)) < W["width"] * 0.9:
                continue  # keep the falls themselves clear
            q = p + d * 0.4
            kit.instance("Rock_Cliff_Stone", self.coll_scenery, (q.x, q.y, top * rw.uniform(0.35, 0.65)),
                         rot_z=dyaw + rw.uniform(-30, 30), scale=rw.uniform(1.5, 3.2), obj_name="Waterfall_FaceStone")
            if k % 2 == 0:
                b = p - d * 1.2
                gz = self.ground.raycast_down(b.x, b.y, z_from=top + 3.0)[0]
                if gz is not None:
                    kit.instance(rw.choice(["Bush_A", "Bush_B", "Bush_C"]), self.coll_scenery, (b.x, b.y, gz - 0.05),
                                 rot_z=rw.uniform(0, 360), scale=rw.uniform(1.1, 1.8), obj_name="Waterfall_LipBush")
        # rocky peaks flanking and behind the crescent: the falls read as a gap in the ridge
        for k, (back_m, side_m, rad) in enumerate(((26.0, -40.0, 17.0), (30.0, 41.0, 18.0), (44.0, 4.0, 21.0))):
            q = Vector((tx, ty)) - d * back_m + side * side_m
            hk = rad * 2.2
            if occludes_map(q.x, q.y, hk, rad, self.map_polys):
                continue
            kit.instance("Mountain_Peak_Rocky", self.coll_scenery, (q.x, q.y, -1.0), rot_z=37.0 * k,
                         scale=(rad, rad, hk / 2.1), obj_name="Waterfall_Peak")
            self.keep.circles.append((q.x, q.y, rad * 0.8))
        lip = Vector((tx, ty)) - d * 4.0
        ledge_z = h * 0.48
        ledge_c = lip + d * 3.2
        geo.terrace("Waterfall_Ledge", geo.ellipse(ledge_c.x, ledge_c.y, 7.5, 4.2, 18,
                                                    rot=math.atan2(side.y, side.x)), ledge_z, -1.0,
                    self.coll_scenery, style="grass_rock", wobble_amt=0.6, seed=22, ground_index=self.ground)
        width = W["width"] + 5.0

        def sheet(name, start, z0, z1, fwd, w0, w1):
            m2 = geo.MeshBuilder()
            b2 = m2.bm
            mi = m2.mat("M_Waterfall")
            rows = []
            for k in range(9):
                t = k / 8
                z = z0 + (z1 - z0) * (t ** 1.6)
                p = start + d * (fwd * t)
                w = (w0 + (w1 - w0) * t) / 2
                rows.append([b2.verts.new((p.x + side.x * w * sd, p.y + side.y * w * sd, z)) for sd in (-1, 1)])
            for k in range(8):
                b2.faces.new((rows[k][0], rows[k][1], rows[k + 1][1], rows[k + 1][0])).material_index = mi
            m2.build(name, self.coll_scenery, smooth=True, recalc_normals=False)

        sheet("Waterfall_Upper", lip, h + 0.1, ledge_z + 0.2, 1.6, width, width * 1.1)
        foot = ledge_c + d * 6.6
        foot_z = self.ground.raycast_down(foot.x, foot.y)[0]
        foot_z = 0.0 if foot_z is None else foot_z
        sheet("Waterfall_Lower", ledge_c + d * 3.6, ledge_z + 0.1, foot_z + 0.05, 3.0, width * 0.9, width * 1.25)
        reach_lake = 4.0
        while reach_lake < 60.0 and not geo.point_in_poly((foot + d * reach_lake).x, (foot + d * reach_lake).y,
                                                          geo.offset_poly(poly, -2.5)):
            reach_lake += 1.0
        stream = [foot + d * (reach_lake * k / 6) for k in range(7)]
        geo.path_ribbon("Waterfall_Stream", [(p.x, p.y) for p in stream], width * 1.05, self.coll_scenery,
                        self.ground, mat="M_Water", lift=0.04, edge_wobble=0.3, end_taper=0.9)
        geo.path_ribbon("Waterfall_Splash", [(p.x, p.y) for p in stream[:3]], width * 0.7, self.coll_scenery,
                        self.ground, mat="M_Foam", lift=0.07, edge_wobble=0.4, end_taper=0.3)
        geo.flat_poly("Waterfall_River", [(p.x, p.y) for p in (
            lip - side * width * 0.5, lip + side * width * 0.5, lip + side * 4 - d * 14, lip - side * 4 - d * 14)],
            h + 0.12, self.coll_scenery, "M_Water", smooth_iters=0)
        for c0, zc, sc in ((ledge_c, ledge_z + 0.3, 1.6), (foot + d * 1.0, foot_z + 0.3, 2.2)):
            for k in range(7):
                a = k / 7 * 2 * math.pi
                kit.instance("Cloud_Puff_A", self.coll_scenery, (c0.x + math.cos(a) * 3.5, c0.y + math.sin(a) * 2.5, zc),
                             scale=sc + 0.4 * (k % 2), obj_name="Waterfall_Mist")
        self.keep.circles.append((tx, ty, 40.0))
        self._dress_lake(poly, geo.offset_poly(poly, 2.0), (tx, ty), h)

    def _dress_lake(self, water, shore, mesa_xy, mesa_h):
        """Rocks, reeds and lily pads around the lake; trees on top of the waterfall mesa."""
        r = core.rng("lake", 5)
        L = LY.LAKE
        ring = geo.resample(geo.ensure_ccw(shore), 5.0)
        for i, (x, y) in enumerate(ring):
            if r.random() < 0.55:
                a = r.choice(["Rock_A", "Rock_C", "Bush_C", "Grass_Tuft_A", "Rock_B", "Bush_A"])
                kit.instance(a, self.coll_scenery, (x, y, 0.0), rot_z=r.uniform(0, 360),
                             scale=r.uniform(0.8, 1.5), obj_name="Lake_Shore_Dressing")
        cx = sum(p[0] for p in water) / len(water)
        cy = sum(p[1] for p in water) / len(water)
        for k in range(22):
            a = r.uniform(0, 2 * math.pi)
            d = r.uniform(0.35, 0.85)
            px = cx + (water[0][0] - cx) * 0 + math.cos(a) * LY.LAKE["rx"] * d
            py = cy + math.sin(a) * LY.LAKE["ry"] * d
            if not geo.point_in_poly(px, py, water):
                continue
            mb = geo.MeshBuilder()
            mb.cyl(r.uniform(0.6, 1.2), 0.05, mat="M_Flat_leaf", verts=10)
            if r.random() < 0.4:
                mb.sphere(0.18, loc=(0.2, 0.1, 0.12), scale=(1, 1, 0.6), mat="M_Flat_flower_pink", subdiv=1)
            ob = mb.build("Lake_LilyPad", self.coll_scenery, smooth=False)
            ob.location = (px, py, -1.07)
        mx, my = mesa_xy
        for k in range(16):
            a = 2 * math.pi * k / 16
            px, py = mx + math.cos(a) * r.uniform(8, 26), my + math.sin(a) * r.uniform(8, 20)
            z, _n = self.ground.raycast_down(px, py)
            if z is None or z < mesa_h - 1.5:
                continue  # only on top of the waterfall cliff
            kit.instance(r.choice(["Tree_Round_A", "Tree_Round_B", "Tree_Pine_A", "Tree_Tall_A"]), self.coll_scenery,
                         (px, py, z - 0.1), rot_z=r.uniform(0, 360), scale=r.uniform(0.9, 1.3),
                         obj_name="Waterfall_Cliff_Tree")

    # -- trails between maps (raised dirt embankments with signposts)
    def _edge_point(self, mid, p, mapground):
        """Outward normal of the footprint edge nearest a (built) portal, and the edge point in front of it
        with z = the map ground just inside that edge."""
        o = self.origins[mid]
        yaw = LY.world_yaw(mid)
        lx, ly = LY._rot(-yaw, p.x - o[0], p.y - o[1])
        m = LY.MAPS[mid]
        d = {(-1.0, 0.0): lx, (1.0, 0.0): m["L"] - lx, (0.0, -1.0): ly, (0.0, 1.0): m["D"] - ly}
        n_loc = min(d, key=d.get)
        dist = max(0.0, d[n_loc])
        n = Vector(LY._rot(yaw, *n_loc))
        e = Vector((p.x, p.y)) + n * dist
        probe = e - n * 0.35
        zg = mapground.raycast_down(probe.x, probe.y, z_from=p.z + 3.0)[0] if mapground else None
        if zg is None or abs(zg - p.z) > 0.3:  # a lip or step at the edge: keep the portal height
            zg = p.z
        return n, Vector((e.x, e.y, zg))

    def _trail_neighbours(self, parent, child, a, b, reach=25.0):
        """Footprints (inflated by their plinth ring) of other maps near the straight line a-b, for trail routing."""
        out = []
        for mid in LY.exterior_ids():
            if mid in (parent, child):
                continue
            fp = LY.footprint_world(mid, self.origins, margin=2.5)
            if min(seg_dist(q, (a.x, a.y), (b.x, b.y)) for q in fp) < reach:
                out.append(fp)
        return out

    def trails(self, built_portals=None, ctxs=None):
        """Causeway trails between linked edge portals (see trails.py), then junction aprons and a
        portal-to-portal walk of every trail (results in self.trail_report[i]["walk"]).

        built_portals: {(map_id, portal_name): (x, y, z)} from the built maps (preferred over layout anchors).
        ctxs: {map_id: MapCtx} for the map ground at the junctions.
        """
        from . import trails as TR
        objs = []
        infos = []
        built_portals = built_portals or {}
        mapground = core.GroundIndex()
        for ctx in (ctxs or {}).values():
            for o in ctx.ground.objects:
                mapground.add(o)
        for child, ca, parent, pa, _gap, _b in LY.LINKS:
            a = Vector(built_portals.get((parent, pa)) or LY.anchor_world(parent, pa, self.origins))
            b = Vector(built_portals.get((child, ca)) or LY.anchor_world(child, ca, self.origins))
            if (Vector((b.x - a.x, b.y - a.y))).length < 0.5:
                continue
            name = f"Trail_{LY.MAPS[parent]['slug']}_{pa}_to_{LY.MAPS[child]['slug']}"
            na, ea = self._edge_point(parent, a, mapground)
            nb, eb = self._edge_point(child, b, mapground)
            main = (parent, pa, child, ca) in LY.MAIN_ROAD
            hidden = (parent, pa, child, ca) in LY.HIDDEN_TRAILS
            bridge = LY.BRIDGE_END.get((child, ca), 0.0)
            o, info = TR.build_trail(self, name, a, b, ea, eb, na, nb, mapground=mapground, main=main,
                                     hidden=hidden, bridge_b=bridge,
                                     avoid=[LY.footprint_world(parent, self.origins),
                                            LY.footprint_world(child, self.origins)] + self._trail_neighbours(
                                                parent, child, a, b))
            objs += o
            info["ids"] = (parent, child)
            infos.append(info)
        combined = core.GroundIndex()
        for ob in self.ground.objects + mapground.objects:
            combined.add(ob)
        for info in infos:
            objs += TR.apron(self, info, combined)
        village = {0, 10000, 20000, 30000}
        for info in infos:  # lamp-lit village lanes between the Mushroom Town maps
            if not set(info["ids"]) <= village:
                continue
            pts = info["pts"]
            for k in range(2, len(pts) - 2, 5):
                p = pts[k]
                u = (pts[k + 1] - pts[k - 1]).normalized()
                sd = 1 if (k // 5) % 2 else -1
                q = p + Vector((-u.y, u.x)) * (info["width"] / 2 + 0.7) * sd
                z = combined.raycast_down(q.x, q.y)[0]
                if z is not None:
                    kit.instance("Lamp_Post", self.coll_trails, (q.x, q.y, z - 0.03), obj_name="Trail_VillageLamp")
        for info in infos:
            info["entry"]["walk"] = TR.walk_trail(info, combined)
        return objs

    # -- mountains + forest + clouds
    def scenery(self, seed=3):
        r = core.rng("scenery", seed)
        outline = self.island_outline
        x0, y0, x1, y1 = geo.poly_bbox(outline)
        inner = geo.offset_poly(geo.ensure_ccw(outline), -6.0)
        peaks = []
        for ridge_i, ridge in enumerate(LY.RIDGES):
            wpts = [LY.geo_to_world(*p) for p in ridge["pts"]]
            if ridge.get("asset") == "Mountain_Hill":
                self._rim_hills(r, ridge, wpts, inner, peaks)
                continue
            for (x, y) in geo.resample(wpts, ridge["spacing"], closed=False):
                x += r.uniform(-4, 4)
                y += r.uniform(-4, 4)
                rad = r.uniform(*ridge["radius"])
                h = rad * r.uniform(*ridge["height"])
                if not geo.point_in_poly(x, y, inner):
                    print(f"RIDGE_REJECT {ridge_i} ({x:.0f},{y:.0f}) off the island")
                    continue
                if self.keep.blocked(x, y, pad=rad * 0.7):
                    print(f"RIDGE_REJECT {ridge_i} ({x:.0f},{y:.0f}) keepout (map, trail, lake or peak)")
                    continue
                for _ in range(4):
                    if not occludes_map(x, y, h, rad, self.map_polys):
                        break
                    h *= 0.6
                    rad *= 0.85
                else:
                    print(f"RIDGE_REJECT {ridge_i} ({x:.0f},{y:.0f}) would hide a map")
                    continue
                if h < 6:
                    print(f"RIDGE_REJECT {ridge_i} ({x:.0f},{y:.0f}) too low after occlusion shrink")
                    continue
                an = ridge.get("asset") or ("Mountain_Peak_Rocky" if h > 36 else r.choice(["Mountain_Peak_A",
                                                                                          "Mountain_Peak_B"]))
                if h < 14:
                    an = "Mountain_Hill"
                hs = h / {"Mountain_Peak_A": 1.6, "Mountain_Peak_B": 2.1, "Mountain_Peak_C": 1.2,
                          "Mountain_Peak_Rocky": 2.1, "Mountain_Hill": 0.8}[an]
                kit.instance(an, self.coll_scenery, (x, y, -1.0), rot_z=r.uniform(0, 360), scale=(rad, rad, hs),
                             obj_name="Mountain_Ridge")
                peaks.append((x, y, rad))
        tries = 0
        while len(peaks) < 55 and tries < 9000:
            tries += 1
            x = r.uniform(x0, x1)
            y = r.uniform(y0, y1)
            if not geo.point_in_poly(x, y, inner):
                continue
            big = r.random() < 0.35
            rad = r.uniform(20, 32) if big else r.uniform(9, 20)
            h = rad * (r.uniform(1.5, 2.3) if big else r.uniform(0.9, 1.8))
            if self.keep.blocked(x, y, pad=rad * 0.9):
                continue
            if any(math.hypot(x - px, y - py) < (rad + pr) * 0.75 for px, py, pr in peaks):
                continue
            # shrink peaks that would hide a map from the camera; skip if they can't fit
            ok = False
            for _ in range(4):
                if not occludes_map(x, y, h, rad, self.map_polys):
                    ok = True
                    break
                h *= 0.6
                rad *= 0.85
            if not ok or h < 6:
                continue
            if h > 38:
                asset_name = r.choice(["Mountain_Peak_B", "Mountain_Peak_Rocky"])
            elif h < 16:
                asset_name = r.choice(["Mountain_Peak_C", "Mountain_Hill"])
            else:
                asset_name = r.choice(["Mountain_Peak_A", "Mountain_Peak_B", "Mountain_Peak_C"])
            hscale = h / {"Mountain_Peak_A": 1.6, "Mountain_Peak_B": 2.1, "Mountain_Peak_C": 1.2,
                          "Mountain_Peak_Rocky": 2.1, "Mountain_Hill": 0.8}[asset_name]
            kit.instance(asset_name, self.coll_scenery, (x, y, -1.0), rot_z=r.uniform(0, 360),
                         scale=(rad, rad, hscale), obj_name="Mountain")
            peaks.append((x, y, rad))
        for px, py, pr in peaks:
            self.keep.circles.append((px, py, pr * 0.8))
        # forest filler, with a tree palette per region so each part of the island has its own colour
        palettes = {
            "mushroom": ["Tree_Round_A", "Tree_Round_B", "Tree_Round_C", "Tree_Round_B"],
            "valley": ["Tree_Birch_Orange", "Tree_Birch_Yellow", "Tree_Autumn_A", "Tree_Round_A", "Tree_Round_B"],
            "port": ["Tree_Palm_A", "Tree_Round_A", "Tree_Round_C", "Tree_Palm_A"],
            "forest": ["Tree_Tall_A", "Tree_Pine_A", "Tree_Round_B", "Tree_Tall_A", "Tree_Round_A"],
            "amherst": ["Tree_Round_A", "Tree_Round_B", "Tree_Birch_Yellow", "Tree_Round_C"],
            "east": ["Tree_Birch_Orange", "Tree_Birch_Yellow", "Tree_Round_A", "Tree_Autumn_A"],
            "gloom": ["Tree_Pine_A", "Tree_Tall_A", "Tree_Pine_A", "Tree_Tall_A", "Tree_Pine_A"],
        }
        region_of = {0: "mushroom", 10000: "mushroom", 20000: "mushroom", 30000: "mushroom", 40000: "valley",
                     40001: "valley", 40002: "valley", 50000: "valley", 60000: "port", 1000000: "forest",
                     1000001: "forest", 1000002: "gloom", 1000003: "amherst", 1000004: "amherst",
                     1000005: "forest", 1000006: "forest", 1010000: "amherst", 1010002: "amherst",
                     1010004: "amherst", 1020000: "east", 1020001: "east"}
        centers = []
        for mid in LY.exterior_ids():
            fp = LY.footprint_world(mid, self.origins)
            centers.append((sum(p[0] for p in fp) / 4, sum(p[1] for p in fp) / 4, region_of.get(mid, "mushroom")))

        rim_strip = geo.offset_poly(geo.ensure_ccw(outline), -9.0)
        # a low shrub ring around every map, so hand-made groves at map edges don't merge into the filler forest
        shrub_bb = []
        for mid in LY.exterior_ids():
            poly = rounded_footprint(mid, self.origins, 14.0, wobble_amt=0.0)
            shrub_bb.append((poly, geo.poly_bbox(poly)))

        mt_ids = (0, 10000, 20000, 30000)
        mt_zone = [(p, geo.poly_bbox(p)) for p in (LY.footprint_world(m, self.origins, margin=60.0) for m in mt_ids)]
        mt_lanes = []  # the gaps between neighbouring Mushroom Town plinths stay open (village lanes)
        for m1, m2 in ((0, 10000), (10000, 20000), (20000, 30000)):
            hull = convex_hull(LY.footprint_world(m1, self.origins, margin=8.0) +
                               LY.footprint_world(m2, self.origins, margin=8.0))
            mt_lanes.append((hull, geo.poly_bbox(hull)))
        mt_trees = []

        def in_polys(px, py, polys):
            return any(bx0 <= px <= bx1 and by0 <= py <= by1 and geo.point_in_poly(px, py, poly)
                       for poly, (bx0, by0, bx1, by1) in polys)

        def in_shrub_ring(px, py):
            return any(bx0 <= px <= bx1 and by0 <= py <= by1 and geo.point_in_poly(px, py, poly)
                       for poly, (bx0, by0, bx1, by1) in shrub_bb)
        clearings = [LY.footprint_world(mid, self.origins, margin=15.0) for mid in (0, 10000, 20000, 30000)]

        def palette_at(px, py):
            best = min(centers, key=lambda c: (c[0] - px) ** 2 + (c[1] - py) ** 2)
            return palettes[best[2]]
        count = 0
        tries = 0
        placed = []
        cell = 5.5
        grid = {}
        while count < 2600 and tries < 60000:
            tries += 1
            x = r.uniform(x0, x1)
            y = r.uniform(y0, y1)
            if not geo.point_in_poly(x, y, inner):
                continue
            if self.keep.blocked(x, y, pad=2.5):
                continue
            key = (int(x // cell), int(y // cell))
            near = False
            for i in (-1, 0, 1):
                for j in (-1, 0, 1):
                    for (qx, qy) in grid.get((key[0] + i, key[1] + j), ()):
                        if (x - qx) ** 2 + (y - qy) ** 2 < cell * cell:
                            near = True
            if near:
                continue
            if occludes_map(x, y, 8.5, 2.5, self.map_polys):
                continue
            # density mask: open meadows (no trees) and darker groves; a tree-free strip along the rim
            dens = noise.noise(Vector((x * 0.011, y * 0.011, 4.2)))
            if dens < -0.18:
                continue
            if not geo.point_in_poly(x, y, rim_strip):
                continue
            if any(geo.point_in_poly(x, y, c) for c in clearings):
                continue
            z, _n = self.ground.raycast_down(x, y)
            if z is None:
                continue
            if in_polys(x, y, mt_zone):
                if in_polys(x, y, mt_lanes):
                    continue
                grove = noise.noise(Vector((x * 0.02, y * 0.02, 7.7)))
                if grove > 0.18 and all(math.hypot(x - qx, y - qy) >= 14.0 for qx, qy in mt_trees):
                    kit.instance(r.choice(["Tree_Round_A", "Tree_Round_B"]), self.coll_forest, (x, y, z - 0.1),
                                 rot_z=r.uniform(0, 360), scale=r.uniform(1.6, 2.2), obj_name="MeadowOak")
                    mt_trees.append((x, y))
                elif r.random() < 0.3:
                    kit.instance(r.choice(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A", "Flower_Patch_A"]),
                                 self.coll_forest, (x, y, z - 0.02), rot_z=r.uniform(0, 360),
                                 scale=r.uniform(1.2, 1.9), obj_name="MeadowFlowers")
                grid.setdefault(key, []).append((x, y))
                count += 1
                continue
            if in_shrub_ring(x, y):
                kit.instance(r.choice(["Bush_A", "Bush_B", "Bush_C"]), self.coll_forest, (x, y, z - 0.05),
                             rot_z=r.uniform(0, 360), scale=r.uniform(1.1, 1.7), obj_name="ForestShrub")
            else:
                t = r.choice(palette_at(x, y))
                kit.instance(t, self.coll_forest, (x, y, z - 0.1), rot_z=r.uniform(0, 360),
                             scale=r.uniform(0.8, 1.35), obj_name="ForestTree")
            grid.setdefault(key, []).append((x, y))
            count += 1
        # giant toadstools and stalk-mushroom clusters on the Mushroom Town hill skirts
        for mid in mt_ids:
            ring = geo.resample(geo.ensure_ccw(LY.footprint_world(mid, self.origins, margin=9.0)), 7.0)
            for k, (px, py) in enumerate(ring):
                if r.random() < 0.55:
                    continue
                px += r.uniform(-2.5, 2.5)
                py += r.uniform(-2.5, 2.5)
                if any(seg_dist((px, py), a, b) < rr + 1.0 for a, b, rr in self.keep.segments):
                    continue
                z, _n = self.ground.raycast_down(px, py)
                if z is None:
                    continue
                big = r.random() < 0.45
                kit.instance(r.choice(["Mushroom_Giant_Red", "Mushroom_Giant_Orange", "Mushroom_Giant_Blue"]) if big
                             else "Mushroom_Cluster_A", self.coll_forest, (px, py, z - 0.1), rot_z=r.uniform(0, 360),
                             scale=r.uniform(0.9, 1.5) if big else r.uniform(1.4, 2.2), obj_name="SkirtToadstool")
        # clouds hugging the cliff base (classic world map) and a cloud sea far below
        ring = geo.resample(geo.ensure_ccw(outline), 34.0)
        for k, (px, py) in enumerate(ring):
            if r.random() < 0.6:
                continue
            cxm, cym = (x0 + x1) / 2, (y0 + y1) / 2
            dx, dy = px - cxm, py - cym
            L = math.hypot(dx, dy) or 1
            out = r.uniform(6, 34)
            sxy = r.uniform(9, 16)
            kit.instance(r.choice(["Cloud_Puff_A", "Cloud_Puff_B"]), self.coll_sky,
                         (px + dx / L * out, py + dy / L * out, r.uniform(-170, -110)), rot_z=r.uniform(0, 360),
                         scale=(sxy, sxy * r.uniform(0.7, 0.9), r.uniform(2.5, 4.5)), obj_name="Cloud_CliffBase")
        for k in range(36):
            cx = r.uniform(x0 - 250, x1 + 250)
            cy = r.uniform(y0 - 250, y1 + 250)
            sxy = r.uniform(16, 30)
            kit.instance(r.choice(["Cloud_Puff_A", "Cloud_Puff_B"]), self.coll_sky,
                         (cx, cy, r.uniform(-215, -180)), rot_z=r.uniform(0, 360),
                         scale=(sxy, sxy * r.uniform(0.75, 0.95), sxy * r.uniform(0.5, 0.65)), obj_name="Cloud_SeaLayer")
        for k in range(14):
            a = 2 * math.pi * k / 14 + r.uniform(-0.2, 0.2)
            cx = (x0 + x1) / 2 + math.cos(a) * (x1 - x0) * r.uniform(0.62, 0.8)
            cy = (y0 + y1) / 2 + math.sin(a) * (y1 - y0) * r.uniform(0.62, 0.8)
            kit.instance(r.choice(["Cloud_Puff_A", "Cloud_Puff_B"]), self.coll_sky,
                         (cx, cy, r.uniform(25, 70)), rot_z=r.uniform(0, 360), scale=r.uniform(6, 11),
                         obj_name="Cloud_High")
        return count

    def _rim_hills(self, r, ridge, wpts, inner, peaks):
        """Low rounded rim hills: clusters of 2-3 with gaps, jittered off the line, sunk into the ground, about
        half of them topped with a tree or a boulder (instead of a uniform row of olive domes)."""
        line = geo.resample(wpts, ridge["spacing"], closed=False)
        for i, (x, y) in enumerate(line):
            if r.random() < 0.35:
                continue
            a = Vector(line[max(i - 1, 0)])
            b = Vector(line[min(i + 1, len(line) - 1)])
            along = (b - a).normalized() if (b - a).length > 1e-6 else Vector((1, 0))
            perp = Vector((-along.y, along.x))
            for _k in range(r.choice((2, 2, 3))):
                q = Vector((x, y)) + along * r.uniform(-7, 7) + perp * r.uniform(-12, 12)
                rad = r.uniform(6, 16)
                h = rad * r.uniform(0.7, 1.0)
                if not geo.point_in_poly(q.x, q.y, inner) or self.keep.blocked(q.x, q.y, pad=rad * 0.6):
                    continue
                if any(math.hypot(q.x - px, q.y - py) < (rad + pr) * 0.55 for px, py, pr in peaks):
                    continue
                if occludes_map(q.x, q.y, h, rad, self.map_polys):
                    continue
                sink = h * r.uniform(0.3, 0.5)
                kit.instance("Mountain_Hill", self.coll_scenery, (q.x, q.y, -1.0 - sink), rot_z=r.uniform(0, 360),
                             scale=(rad, rad, h / 0.8), obj_name="Rim_Hill")
                peaks.append((q.x, q.y, rad))
                if r.random() < 0.5:
                    top = -1.0 - sink + h - 0.35
                    an = r.choice(["Tree_Round_A", "Tree_Round_B", "Rock_Boulder", "Tree_Round_C"])
                    kit.instance(an, self.coll_scenery, (q.x, q.y, top), rot_z=r.uniform(0, 360),
                                 scale=r.uniform(1.0, 1.4), obj_name="Rim_Hill_Top")

    def sea(self):
        x0, y0, x1, y1 = geo.poly_bbox(self.island_outline)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        S = max(x1 - x0, y1 - y0) * 6
        geo.flat_poly("Sea_Far_Below", geo.rect(cx - S, cy - S, cx + S, cy + S), LY.SEA_Z, self.coll_sky, "M_Sea",
                      smooth_iters=0)
