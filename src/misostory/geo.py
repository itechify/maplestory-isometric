"""Geometry primitives and terrain pieces (bmesh / curve based, no bpy.ops)."""

import math

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise

from . import core
from . import materials as M

# ---------------------------------------------------------------------------
# 2D polygon utilities (lists of (x, y) tuples)
# ---------------------------------------------------------------------------


def poly_area(poly):
    a = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        a += x1 * y2 - x2 * y1
    return a * 0.5


def ensure_ccw(poly):
    return list(poly) if poly_area(poly) >= 0 else list(reversed(poly))


def point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def poly_bbox(poly):
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    return min(xs), min(ys), max(xs), max(ys)


def resample(poly, step, closed=True):
    out = []
    n = len(poly)
    rng_ = range(n) if closed else range(n - 1)
    for i in rng_:
        a = Vector(poly[i])
        b = Vector(poly[(i + 1) % n])
        seg = (b - a).length
        k = max(1, int(math.ceil(seg / step)))
        for j in range(k):
            p = a.lerp(b, j / k)
            out.append((p.x, p.y))
    if not closed:
        out.append(tuple(poly[-1]))
    return out


def chaikin(poly, iterations=2, closed=True, ratio=0.25):
    pts = list(poly)
    for _ in range(iterations):
        new = []
        n = len(pts)
        rng_ = range(n) if closed else range(n - 1)
        if not closed:
            new.append(pts[0])
        for i in rng_:
            a = Vector(pts[i])
            b = Vector(pts[(i + 1) % n])
            q = a.lerp(b, ratio)
            r = a.lerp(b, 1 - ratio)
            new.extend([(q.x, q.y), (r.x, r.y)])
        if not closed:
            new.append(pts[-1])
        pts = new
    return pts


def wobble(poly, amount, seed=0, freq=0.35):
    """Displace vertices along their normals with smooth noise (hand-made edges)."""
    if amount <= 0:
        return list(poly)
    out = []
    n = len(poly)
    off = Vector((seed * 13.37, seed * 7.31, seed * 3.1))
    for i in range(n):
        p = Vector(poly[i])
        a = Vector(poly[i - 1])
        b = Vector(poly[(i + 1) % n])
        t = (b - a)
        if t.length < 1e-9:
            out.append(poly[i])
            continue
        t.normalize()
        nrm = Vector((t.y, -t.x))  # outward for CCW
        d = noise.noise(Vector((p.x * freq, p.y * freq, 0.0)) + off) * amount
        q = p + nrm * d
        out.append((q.x, q.y))
    return out


def offset_poly(poly, d):
    """Miter offset of a CCW polygon (d > 0 grows). Fine for smooth outlines."""
    out = []
    n = len(poly)
    for i in range(n):
        p = Vector(poly[i])
        a = Vector(poly[i - 1])
        b = Vector(poly[(i + 1) % n])
        t1 = (p - a)
        t2 = (b - p)
        if t1.length < 1e-9 or t2.length < 1e-9:
            out.append(poly[i])
            continue
        t1.normalize()
        t2.normalize()
        n1 = Vector((t1.y, -t1.x))
        n2 = Vector((t2.y, -t2.x))
        m = (n1 + n2)
        if m.length < 1e-6:
            m = n1
        m.normalize()
        cosang = max(0.55, m.dot(n1))
        q = p + m * (d / cosang)
        out.append((q.x, q.y))
    return out


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def rounded_rect(x0, y0, x1, y1, r, seg=4):
    r = min(r, (x1 - x0) / 2 - 1e-3, (y1 - y0) / 2 - 1e-3)
    pts = []
    corners = [(x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)]
    for cx, cy, start in corners:
        for k in range(seg + 1):
            a = math.radians(start + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def ellipse(cx, cy, rx, ry, n=24, rot=0.0):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        c, s = math.cos(rot), math.sin(rot)
        pts.append((cx + x * c - y * s, cy + x * s + y * c))
    return pts


def transform_poly(poly, origin, rot_deg):
    c, s = math.cos(math.radians(rot_deg)), math.sin(math.radians(rot_deg))
    ox, oy = origin
    return [(ox + x * c - y * s, oy + x * s + y * c) for x, y in poly]


# ---------------------------------------------------------------------------
# MeshBuilder: compose multi-material meshes from primitives
# ---------------------------------------------------------------------------


def _mat4(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    if isinstance(scale, (int, float)):
        scale = (scale, scale, scale)
    return (Matrix.Translation(Vector(loc)) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
            @ Matrix.Diagonal(Vector((*scale, 1.0))))


class MeshBuilder:
    def __init__(self):
        self.bm = bmesh.new()
        self.mat_names = []

    def mat(self, name):
        if name not in self.mat_names:
            self.mat_names.append(name)
        return self.mat_names.index(name)

    def _faces_of(self, verts):
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
        return list(faces)

    def _finish_part(self, verts, mat, bevel=0.0, segs=2, smooth_part=None):
        faces = self._faces_of(verts)
        mi = self.mat(mat)
        for f in faces:
            f.material_index = mi
        if bevel > 0:
            edges = set()
            for f in faces:
                edges.update(f.edges)
            bmesh.ops.bevel(self.bm, geom=list(edges), offset=bevel, segments=segs, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
        return faces

    def box(self, size, loc=(0, 0, 0), rot=(0, 0, 0), mat="M_Wood", bevel=0.0, segs=2):
        sx, sy, sz = size
        m = _mat4(loc, rot, (sx, sy, sz))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        return self._finish_part(res["verts"], mat, bevel, segs)

    def cyl(self, r, h, loc=(0, 0, 0), rot=(0, 0, 0), mat="M_Wood", verts=12, r2=None, bevel=0.0,
            segs=2, cap=True, scale=(1, 1, 1)):
        """Cylinder/cone standing on loc (base at loc, top at loc+h along local Z)."""
        r2 = r if r2 is None else r2
        m = _mat4(loc, rot, scale) @ Matrix.Translation((0, 0, h / 2))
        res = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=verts,
                                    radius1=r, radius2=r2, depth=h, matrix=m)
        return self._finish_part(res["verts"], mat, bevel, segs)

    def sphere(self, r, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), mat="M_Leaf", subdiv=2,
               lumpy=0.0, seed=0, flatten_bottom=None):
        m = _mat4(loc, rot, scale)
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=r, matrix=Matrix.Identity(4))
        vs = res["verts"]
        off = Vector((seed * 3.7, seed * 1.3, seed * 5.1))
        for v in vs:
            p = v.co.copy()
            if lumpy:
                d = noise.noise(p * (1.6 / max(r, 0.01)) + off) * lumpy * r
                p = p + p.normalized() * d
            if flatten_bottom is not None and p.z < -r * flatten_bottom:
                p.z = -r * flatten_bottom + (p.z + r * flatten_bottom) * 0.15
            v.co = m @ p
        return self._finish_part(vs, mat)

    def uvsphere(self, r, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), mat="M_Leaf", u=16, v=8):
        m = _mat4(loc, rot, scale)
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=r, matrix=m)
        return self._finish_part(res["verts"], mat)

    def dome(self, r, h, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), mat="M_Leaf", u=20, v=6,
             lip=0.0, underside=True, profile=1.0):
        """Mushroom-cap style dome: base ring radius r at z=0, apex at z=h.

        profile < 1 gives a puffier cap, > 1 a pointier one. lip curls the rim down.
        """
        m = _mat4(loc, rot, scale)
        bm = self.bm
        rings = []
        for j in range(v + 1):
            t = j / v  # 0 = rim, 1 = apex
            ang = t * math.pi / 2
            rr = r * math.cos(ang) ** profile
            zz = h * math.sin(ang)
            ring = []
            if j == v:
                ring = [bm.verts.new(m @ Vector((0, 0, h)))]
            else:
                for i in range(u):
                    a = 2 * math.pi * i / u
                    ring.append(bm.verts.new(m @ Vector((rr * math.cos(a), rr * math.sin(a), zz))))
            rings.append(ring)
        newv = [vv for ring in rings for vv in ring]
        if lip > 0:
            lip_ring = []
            for i in range(u):
                a = 2 * math.pi * i / u
                lip_ring.append(bm.verts.new(m @ Vector(((r - lip * 0.4) * math.cos(a), (r - lip * 0.4) * math.sin(a), -lip))))
            newv += lip_ring
            for i in range(u):
                bm.faces.new((lip_ring[i], lip_ring[(i + 1) % u], rings[0][(i + 1) % u], rings[0][i]))
            bottom_ring = lip_ring
        else:
            bottom_ring = rings[0]
        for j in range(v - 1):
            a, b = rings[j], rings[j + 1]
            for i in range(u):
                bm.faces.new((a[i], a[(i + 1) % u], b[(i + 1) % u], b[i]))
        apex = rings[v][0]
        last = rings[v - 1]
        for i in range(u):
            bm.faces.new((last[i], last[(i + 1) % u], apex))
        if underside:
            c = bm.verts.new(m @ Vector((0, 0, (-lip if lip else 0) + h * 0.12)))
            newv.append(c)
            for i in range(u):
                bm.faces.new((bottom_ring[(i + 1) % u], bottom_ring[i], c))
        return self._finish_part(newv, mat)

    def torus(self, R, r, loc=(0, 0, 0), rot=(0, 0, 0), mat="M_Rope", u=16, v=6, scale=(1, 1, 1)):
        m = _mat4(loc, rot, scale)
        bm = self.bm
        grid = []
        for i in range(u):
            a = 2 * math.pi * i / u
            row = []
            for j in range(v):
                b = 2 * math.pi * j / v
                x = (R + r * math.cos(b)) * math.cos(a)
                y = (R + r * math.cos(b)) * math.sin(a)
                z = r * math.sin(b)
                row.append(bm.verts.new(m @ Vector((x, y, z))))
            grid.append(row)
        for i in range(u):
            for j in range(v):
                bm.faces.new((grid[i][j], grid[(i + 1) % u][j], grid[(i + 1) % u][(j + 1) % v], grid[i][(j + 1) % v]))
        return self._finish_part([vv for row in grid for vv in row], mat)

    def prism(self, poly, z0, z1, loc=(0, 0, 0), rot=(0, 0, 0), mat="M_Wood", bevel=0.0, segs=2,
              cap_mat=None):
        """Extrude a 2D polygon between z0 and z1."""
        poly = ensure_ccw(poly)
        m = _mat4(loc, rot)
        bm = self.bm
        bot = [bm.verts.new(m @ Vector((x, y, z0))) for x, y in poly]
        top = [bm.verts.new(m @ Vector((x, y, z1))) for x, y in poly]
        n = len(poly)
        faces = []
        faces.append(bm.faces.new(list(reversed(bot))))
        ftop = bm.faces.new(top)
        faces.append(ftop)
        for i in range(n):
            faces.append(bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i])))
        mi = self.mat(mat)
        for f in faces:
            f.material_index = mi
        if cap_mat:
            # the top face is known explicitly (fresh bmesh faces have no normals yet)
            ftop.material_index = self.mat(cap_mat if z1 >= z0 else mat)
        if bevel > 0:
            edges = set()
            for f in faces:
                edges.update(f.edges)
            bmesh.ops.bevel(self.bm, geom=list(edges), offset=bevel, segments=segs, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
        return faces

    def tube(self, pts, r, mat="M_Rope", sides=8, caps=True, radii=None):
        """Sweep a circle (radius r, or per-point radii) along a 3D polyline with parallel-transport frames
        (ropes, vines, cables, bent pipes). Points are world/builder coordinates."""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        if n < 2:
            return []
        bm = self.bm
        tans = []
        for i in range(n):
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
            tans.append(t.normalized() if t.length > 1e-9 else Vector((0.0, 0.0, 1.0)))
        ref = Vector((0.0, 0.0, 1.0)) if abs(tans[0].z) < 0.9 else Vector((1.0, 0.0, 0.0))
        nrm = tans[0].cross(ref).normalized()
        rings = []
        for i in range(n):
            if i > 0:
                nrm = tans[i - 1].rotation_difference(tans[i]) @ nrm
                nrm = (nrm - tans[i] * nrm.dot(tans[i])).normalized()
            bi = tans[i].cross(nrm)
            rr = radii[i] if radii else r
            rings.append([bm.verts.new(pts[i] + (nrm * math.cos(a) + bi * math.sin(a)) * rr)
                          for a in (2 * math.pi * k / sides for k in range(sides))])
        faces = []
        for i in range(n - 1):
            a, b = rings[i], rings[i + 1]
            for k in range(sides):
                faces.append(bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k])))
        if caps:
            faces.append(bm.faces.new(list(reversed(rings[0]))))
            faces.append(bm.faces.new(rings[-1]))
        mi = self.mat(mat)
        for f in faces:
            f.material_index = mi
        return faces

    def tri(self, a, b, c, mat):
        bm = self.bm
        vs = [bm.verts.new(Vector(p)) for p in (a, b, c)]
        f = bm.faces.new(vs)
        f.material_index = self.mat(mat)
        return f

    def quad(self, a, b, c, d, mat):
        bm = self.bm
        vs = [bm.verts.new(Vector(p)) for p in (a, b, c, d)]
        f = bm.faces.new(vs)
        f.material_index = self.mat(mat)
        return f

    def build(self, name, collection, smooth=True, sharp_angle=35, recalc_normals=True):
        if recalc_normals:
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mats = [M.get(n) for n in self.mat_names]
        return core.mesh_object(name, self.bm, collection, mats, smooth=smooth, sharp_angle=sharp_angle)


# ---------------------------------------------------------------------------
# Terrain pieces
# ---------------------------------------------------------------------------

TERRAIN_STYLES = {
    # cap material, side material, fringe?, lip, cap thickness
    "grass_dirt": ("M_Grass", "M_Dirt_Cliff", True, 0.28, 0.42),
    "grass_stone": ("M_Grass", "M_Stone_Cliff", True, 0.28, 0.42),
    "grass_sand": ("M_Grass", "M_Sand_Cliff", True, 0.28, 0.42),
    "grass_rock": ("M_Grass", "M_Rock_Cliff", True, 0.28, 0.42),
    "cobble": ("M_Cobble_Path", "M_Stone_Cliff", False, 0.12, 0.30),
    "sandstone": ("M_Sand_Path", "M_Sand_Cliff", False, 0.12, 0.30),
    "beach": ("M_Beach", "M_Sand_Cliff", False, 0.30, 0.30),
    "dirt": ("M_Path_Dirt", "M_Dirt_Cliff", False, 0.15, 0.30),
    "wood_floor": ("M_Plank", "M_Wood_Dark", False, 0.05, 0.25),
}


def _curve_slab(name, poly, z_center, half_extrude, bevel, offset, collection, bevel_res=3, holes=()):
    cu = bpy.data.curves.new(name + "_crv", "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    for ring in [poly] + [list(reversed(h)) for h in holes]:
        sp = cu.splines.new("POLY")
        sp.points.add(len(ring) - 1)
        for p, (x, y) in zip(sp.points, ring):
            p.co = (x, y, 0, 1)
        sp.use_cyclic_u = True
    cu.extrude = max(0.0, half_extrude)
    cu.bevel_depth = bevel
    cu.bevel_resolution = bevel_res
    cu.offset = offset
    ob = bpy.data.objects.new(name + "_crvobj", cu)
    collection.objects.link(ob)
    ob.location = (0, 0, z_center)
    return ob


def terrace(name, outline, top, bottom, collection, style="grass_dirt", smooth_iters=2, wobble_amt=0.25,
            seed=0, fringe=None, lip=None, cap_thickness=None, ground_index=None, resample_step=2.0,
            stones=True, holes=()):
    """A MapleStory-style platform: rounded grass cap overhanging an earthen body.

    outline: 2D polygon in world XY (meters). top/bottom: world Z.
    Returns list of created objects (body, cap, fringe).

    style "grass_rock" shapes the rock body instead of a straight drum (rock_profile): small rocks (effective
    radius < ROCK_SMALL_R) get a boulder profile in the visible band under the cap - bulging at mid-band, tucked
    in below it - so stacked drums read as separate stones; larger ones taper in toward the foot. stones=True
    also sets 1-3 Rock_Cliff_Stone instances into the faces that face the isometric camera.
    """
    cap_mat, side_mat, fringe_default, lip_default, cap_t_default = TERRAIN_STYLES[style]
    fringe = fringe_default if fringe is None else fringe
    lip = lip_default if lip is None else lip
    cap_t = cap_t_default if cap_thickness is None else cap_thickness
    poly = ensure_ccw(outline)
    poly = resample(poly, resample_step)
    poly = wobble(poly, wobble_amt, seed=seed)
    poly = chaikin(poly, smooth_iters)
    objs = []
    body_top = top - cap_t * 0.6
    if body_top - bottom > 0.05:
        bev = min(0.12, (body_top - bottom) / 4)
        body = _curve_slab(name + "_Body", poly, (body_top + bottom) / 2, (body_top - bottom) / 2 - bev,
                           bev, -bev, collection, bevel_res=1, holes=holes)
        body = core.curve_to_mesh_object(body, name + "_Body", collection, [M.get(side_mat)], smooth=True,
                                         sharp_angle=50)
        objs.append(body)
        if style == "grass_rock" and not holes:
            profile = rock_profile(poly, bottom, body_top)
            _shape_rock_body(body, poly, profile)
            if stones:
                _rock_face_stones(name, poly, collection, seed, profile)
    if stones and style in ("grass_dirt", "dirt") and body_top - bottom > 1.1:
        _cliff_stones(name, poly, bottom, body_top, collection, seed)
    bevel = min(cap_t * 0.5, 0.2)
    cap = _curve_slab(name + "_Cap", poly, top - cap_t / 2, cap_t / 2 - bevel, bevel, lip - bevel, collection,
                      holes=holes)
    cap = core.curve_to_mesh_object(cap, name + "_Cap", collection, [M.get(cap_mat)], smooth=True, sharp_angle=60)
    objs.append(cap)
    if ground_index is not None:
        ground_index.add(cap)
    if fringe:
        objs.append(grass_fringe(name + "_Fringe", offset_poly(poly, lip * 0.75), top - cap_t * 0.35,
                                 collection, seed=seed))
    return objs


ROCK_SMALL_R = 2.5      # grass_rock: effective radius (2 * area / perimeter) below this -> boulder profile
ROCK_BULGE = 0.11       #   swell at mid-band (fraction of the radius, at most ROCK_BULGE_MAX: stays under the lip)
ROCK_BULGE_MAX = 0.2
ROCK_TUCK = 0.18        #   inset below the swell, down to the foot (fraction of the radius, <= ROCK_TUCK_MAX)
ROCK_TUCK_MAX = 0.4
ROCK_TAPER = 0.15       # larger grass_rock bodies: inset at the foot (fraction of the radius), tapering to 0 at
ROCK_TAPER_MAX = 0.55   #   the top; at most this many meters and a quarter of the body height
ROCK_SMALL_STONE_P = 0.4  # chance that a small grass_rock drum gets its one camera-facing stone
ISO_VIEW_XY = (0.70710678, 0.70710678)  # world xy direction the isometric camera looks along (scene_setup.ISO_YAW)


def rock_profile(poly, bottom, body_top):
    """Shape of a grass_rock body: {"offset": f(z) -> horizontal offset in m (+ outward), "levels": z values where
    the body gets extra vertex rings, "band": (z_lo, z_hi) the visible face band (stones go there)}."""
    per = sum(math.dist(poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly))) or 1.0
    r_eff = 2.0 * abs(poly_area(poly)) / per
    h = max(0.01, body_top - bottom)
    if r_eff < ROCK_SMALL_R:
        hb = min(h, max(1.2, 1.15 * r_eff))      # the band under the cap that reads as one stone
        bulge = min(ROCK_BULGE * r_eff, ROCK_BULGE_MAX)
        tuck = min(ROCK_TUCK * r_eff, ROCK_TUCK_MAX, 0.35 * hb)

        def offset(z):
            g = 1.0 - min(1.0, max(0.0, (body_top - z) / hb))  # 1 at the top of the band, 0 at its foot
            return bulge * math.sin(math.pi * g) - tuck * (1.0 - g) ** 2.2
        levels = [body_top - hb * k / 6 for k in range(1, 7)]
        if h > hb + 0.3:
            levels.append(body_top - hb - 0.25)
        return {"offset": offset, "levels": [z for z in levels if bottom + 0.05 < z < body_top - 0.05],
                "band": (body_top - hb, body_top)}
    inset = min(ROCK_TAPER * r_eff, ROCK_TAPER_MAX, 0.25 * h)

    def offset(z):
        f = min(1.0, max(0.0, (z - bottom) / h))
        return -inset * (1.0 - f) ** 1.6
    return {"offset": offset, "levels": [bottom + h * k / 4 for k in (1, 2, 3)], "band": (bottom, body_top)}


def _shape_rock_body(obj, poly, profile):
    """Add vertex rings at profile["levels"], then push every body vertex along the outward normal of the nearest
    outline point by profile["offset"](z)."""
    from mathutils import kdtree
    me = obj.data
    mw = core.GroundIndex.object_world_matrix(obj)
    inv = mw.inverted()
    bm = bmesh.new()
    bm.from_mesh(me)
    for zw in profile["levels"]:
        co = inv @ Vector((0.0, 0.0, zw))
        nz = (inv.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-4, plane_co=co, plane_no=nz)
    bm.to_mesh(me)
    bm.free()
    pts = resample(poly, 0.1)
    n = len(pts)
    if n < 3:
        return
    kd = kdtree.KDTree(n)
    nrms = []
    for i in range(n):
        a = Vector(pts[i - 1])
        b = Vector(pts[(i + 1) % n])
        t = b - a
        nrms.append(Vector((t.y, -t.x)).normalized() if t.length > 1e-9 else Vector((0.0, 0.0)))  # outward (CCW)
        kd.insert((pts[i][0], pts[i][1], 0.0), i)
    kd.balance()
    off_fn = profile["offset"]
    for v in me.vertices:
        w = mw @ v.co
        off = off_fn(w.z)
        if abs(off) < 1e-4:
            continue
        _co, i, _d = kd.find((w.x, w.y, 0.0))
        nv = nrms[i]
        v.co = inv @ Vector((w.x + nv.x * off, w.y + nv.y * off, w.z))
    me.update()
    me.set_sharp_from_angle(angle=math.radians(50))


def _rock_face_stones(name, poly, collection, seed, profile):
    """1-3 Rock_Cliff_Stone instances set into the camera-facing faces of a grass_rock body's visible band."""
    from . import kit
    z_lo, z_hi = profile["band"]
    hb = z_hi - z_lo
    if hb < 0.9:
        return
    r = core.rng(name, seed, "rockstones")
    pts = resample(poly, 0.5)
    n = len(pts)
    cand = []
    for i in range(n):
        p = Vector(pts[i])
        t = Vector(pts[(i + 1) % n]) - p
        if t.length < 1e-6:
            continue
        t.normalize()
        nrm = Vector((t.y, -t.x))
        if nrm.x * ISO_VIEW_XY[0] + nrm.y * ISO_VIEW_XY[1] < -0.35:  # faces the camera
            cand.append((p + t * 0.25, nrm))
    face_len = 0.5 * len(cand)
    if face_len < 2.0:
        return
    small = face_len < 4.0
    count = max(1, min(3, int(face_len * hb / 6.0)))
    if small and r.random() > ROCK_SMALL_STONE_P:
        return  # a stone on every small drum lines up into a belt across a stack
    picked = []
    order = list(range(len(cand)))
    r.shuffle(order)
    gap = max(2, len(cand) // (count + 1))
    for i in order:
        if len(picked) >= count:
            break
        if all(abs(i - j) >= gap for j in picked):
            picked.append(i)
    for i in picked:
        p, nrm = cand[i]
        z = z_lo + hb * r.uniform(0.22, 0.78)
        loc = p + nrm * (0.03 + profile["offset"](z))
        yaw = math.degrees(math.atan2(nrm.y, nrm.x)) + 90.0
        sc = r.uniform(0.45, 0.7) if small else r.uniform(0.75, 1.15)
        kit.instance("Rock_Cliff_Stone", collection, (loc.x, loc.y, z), rot_z=yaw, scale=sc, obj_name=f"{name}_Stone")


def _cliff_stones(name, poly, bottom, top, collection, seed):
    """Half-buried stones studding an earthen cliff face (instances of Rock_Cliff_Stone)."""
    from . import kit
    r = core.rng(name, seed, "stones")
    pts = resample(poly, 1.0)
    n = len(pts)
    i = r.randrange(0, 4)
    h = top - bottom
    while i < n:
        p = Vector(pts[i])
        q = Vector(pts[(i + 1) % n])
        t = q - p
        if t.length > 1e-6:
            t.normalize()
            nrm = Vector((t.y, -t.x))
            z = bottom + h * r.uniform(0.25, 0.8)
            loc = p + nrm * 0.04
            yaw = math.degrees(math.atan2(nrm.y, nrm.x)) + 90.0
            kit.instance("Rock_Cliff_Stone", collection, (loc.x, loc.y, z), rot_z=yaw,
                         scale=r.uniform(0.75, 1.35), obj_name=f"{name}_Stone")
        i += r.randrange(3, 7)


def grass_fringe(name, poly, z, collection, seed=0, spacing=0.32, length=(0.25, 0.55), out=0.18):
    """Jagged hanging grass blades along an outline - the classic Maple platform edge."""
    r = core.rng(name, seed)
    mb = MeshBuilder()
    pts = resample(poly, spacing)
    n = len(pts)
    for i in range(n):
        p = Vector(pts[i])
        q = Vector(pts[(i + 1) % n])
        t = q - p
        if t.length < 1e-6:
            continue
        t.normalize()
        nrm = Vector((t.y, -t.x, 0.0))
        w = spacing * r.uniform(0.55, 0.85)
        L = r.uniform(*length)
        base = Vector((p.x, p.y, z))
        a = base - Vector((t.x, t.y, 0)) * w * 0.5
        b = base + Vector((t.x, t.y, 0)) * w * 0.5
        tip = base + nrm * (out + r.uniform(-0.05, 0.08)) + Vector((0, 0, -L))
        tip += Vector((t.x, t.y, 0)) * r.uniform(-0.08, 0.08)
        mb.tri(a, b, tip, "M_Grass")
        # slight inner second layer for density
        if r.random() < 0.5:
            a2 = a + nrm * -0.05 + Vector((0, 0, 0.02))
            b2 = b + nrm * -0.05 + Vector((0, 0, 0.02))
            tip2 = base + nrm * (out * 0.6) + Vector((0, 0, -L * 0.6))
            mb.tri(a2, b2, tip2, "M_Grass")
    return mb.build(name, collection, smooth=False, recalc_normals=False)


def ramp(name, p0, p1, width, collection, style="grass_dirt", bottom=None, extend=0.6, ground_index=None,
         segments=10, bulge=0.0, top_mat="M_Path_Dirt"):
    """Sloped embankment from p0=(x,y,z0) to p1=(x,y,z1), solid down to `bottom`."""
    cap_mat, side_mat = TERRAIN_STYLES[style][0], TERRAIN_STYLES[style][1]
    if top_mat and style.startswith("grass"):
        cap_mat = top_mat  # trails read as routes
    a = Vector(p0)
    b = Vector(p1)
    d2 = Vector((b.x - a.x, b.y - a.y, 0))
    L = d2.length
    d2.normalize()
    nrm = Vector((-d2.y, d2.x, 0))
    a_ext = a - d2 * extend
    b_ext = b + d2 * extend
    zbot = (min(a.z, b.z) - 1.5) if bottom is None else bottom
    mb = MeshBuilder()
    bm = mb.bm
    ci = mb.mat(cap_mat)
    si = mb.mat(side_mat)
    rows = []
    n = segments
    for k in range(n + 1):
        t = k / n
        c = a_ext.lerp(b_ext, t)
        # smoothstep height so the ends meet terraces tangentially
        raw = (t * (L + 2 * extend) - extend) / max(L, 1e-3)
        tt = min(1.0, max(0.0, raw))
        s = 0.5 * tt + 0.5 * tt * tt * (3 - 2 * tt)
        z = a.z + (b.z - a.z) * s + math.sin(math.pi * t) * bulge
        if raw < 0.0 or raw > 1.0:
            z += 0.02  # flat extensions sit just proud of the terrace they rest on
        left = c + nrm * (width / 2)
        right = c - nrm * (width / 2)
        rows.append((bm.verts.new((left.x, left.y, z)), bm.verts.new((right.x, right.y, z)),
                     bm.verts.new((left.x, left.y, zbot)), bm.verts.new((right.x, right.y, zbot))))
    for k in range(n):
        lt, rt, lb, rb = rows[k]
        lt2, rt2, lb2, rb2 = rows[k + 1]
        f = bm.faces.new((rt, rt2, lt2, lt))
        f.material_index = ci
        f = bm.faces.new((lb, lb2, lt2, lt))
        f.material_index = si
        f = bm.faces.new((rt, rt2, rb2, rb))
        f.material_index = si
        f = bm.faces.new((lb, rb, rb2, lb2))
        f.material_index = si
    grassy = style.startswith("grass") and (not top_mat or top_mat == "M_Grass")
    # end faces sit buried in the terraces except for the 2 cm proud strip; on a grassy ramp keep that
    # strip green so it does not draw a dark seam line across the lower cap
    ei = ci if grassy else si
    lt, rt, lb, rb = rows[0]
    bm.faces.new((lt, rt, rb, lb)).material_index = ei
    lt, rt, lb, rb = rows[-1]
    bm.faces.new((lt, lb, rb, rt)).material_index = ei
    if grassy:
        # grass-topped ramp: the same rounded grass lip + hanging fringe as a terrace cap along both sides
        # (visual only; built before the ramp joins the ground index so the fringe can test what lies below)
        left = [Vector(rw[0].co) for rw in rows]
        right = [Vector(rw[1].co) for rw in rows]
        ramp_lip(name + "_Fringe", [(left, nrm), (right, -nrm)], collection, ground_index=ground_index,
                 seed=core.stable_hash(name))
    obj = mb.build(name, collection, smooth=True, sharp_angle=40)
    if grassy:
        bend_normals_up(obj, ci, 0.7)  # light the slope like the flat caps around it (no pale/dark sheet)
    if ground_index is not None:
        ground_index.add(obj)
    return obj


def bend_normals_up(obj, mat_index, k):
    """Tilt the shading normals of faces using material slot mat_index toward +Z by k (0..1).

    Geometry is untouched; only lighting changes, so a sloped grass surface shades like the flat grass
    caps beside it instead of reading as a brighter (sun-facing) or darker sheet."""
    me = obj.data
    try:
        cn = [Vector(c.vector) for c in me.corner_normals]
    except AttributeError:
        return
    up = Vector((0.0, 0.0, 1.0))
    for p in me.polygons:
        if p.material_index != mat_index:
            continue
        for li in p.loop_indices:
            cn[li] = (cn[li] * (1.0 - k) + up * k).normalized()
    try:
        me.normals_split_custom_set([tuple(v) for v in cn])
    except Exception:
        pass


# rounded cap lip cross-section (outward offset, drop) - matches a terrace cap's bevelled overhang
LIP_PROFILE = ((0.0, 0.0), (0.09, -0.012), (0.16, -0.045), (0.21, -0.10), (0.23, -0.17), (0.21, -0.24),
               (0.14, -0.29), (0.0, -0.31))


def ramp_lip(name, edges, collection, ground_index=None, seed=0, spacing=0.32, length=(0.25, 0.55)):
    """Rounded grass lip + hanging grass fringe along open 3D edges (grass-topped ramps).

    edges: list of (points, outward) - points are the top-edge Vectors (world), outward the horizontal
    direction the lip overhangs. Fringe blades that would end inside terrain (an upper cap the ramp tucks
    under, the lower cap at the foot) are skipped. Not walkable: the caller keeps it out of the ground.
    """
    r = core.rng(name, seed)
    mb = MeshBuilder()
    bm = mb.bm
    mi = mb.mat("M_Grass")
    np_ = len(LIP_PROFILE)
    for pts, out in edges:
        out = Vector((out.x, out.y, 0.0))
        if out.length < 1e-9 or len(pts) < 2:
            continue
        out.normalize()
        rings = [[bm.verts.new((p.x + out.x * o, p.y + out.y * o, p.z + dz)) for o, dz in LIP_PROFILE]
                 for p in pts]
        for k in range(len(rings) - 1):
            for j in range(np_ - 1):
                f = bm.faces.new((rings[k][j], rings[k + 1][j], rings[k + 1][j + 1], rings[k][j + 1]))
                f.material_index = mi
                (o1, z1), (o2, z2) = LIP_PROFILE[j], LIP_PROFILE[j + 1]
                expect = out * (z1 - z2) + Vector((0.0, 0.0, o2 - o1))  # profile normal, pointing outward
                f.normal_update()
                if f.normal.dot(expect) < 0:
                    f.normal_flip()
        # hanging blades along the lip, resampled by 3D arc length
        samples = []
        carry = r.uniform(0.0, spacing)
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            seg = (b - a).length
            t = carry
            while t < seg:
                samples.append((a.lerp(b, t / seg), (b - a) / seg))
                t += spacing
            carry = t - seg
        for p, tan in samples:
            base = p + out * 0.19 + Vector((0.0, 0.0, -0.15))
            L = r.uniform(*length)
            w = spacing * r.uniform(0.55, 0.85)
            tip = base + out * (0.18 + r.uniform(-0.05, 0.08)) + Vector((0.0, 0.0, -L)) + tan * r.uniform(-0.08, 0.08)
            if ground_index is not None:
                g = ground_index.raycast_down(tip.x, tip.y, z_from=base.z + 0.45)[0]
                if g is not None and g > base.z - 0.12:
                    continue  # this stretch of the side is buried in (or tucked under) a terrace
            a = base - tan * w * 0.5
            b = base + tan * w * 0.5
            mb.tri(a, b, tip, "M_Grass")
            if r.random() < 0.5:
                a2 = a - out * 0.05 + Vector((0.0, 0.0, 0.02))
                b2 = b - out * 0.05 + Vector((0.0, 0.0, 0.02))
                mb.tri(a2, b2, base + out * 0.11 + Vector((0.0, 0.0, -L * 0.6)), "M_Grass")
    if not bm.faces:
        bm.free()
        return None
    return mb.build(name, collection, smooth=True, sharp_angle=70, recalc_normals=False)


STAIR_LIFT = 0.03  # treads sit just proud of the cap they land on (no z-fighting)
LANDING_GAP_PROBE = 0.08  # stairs: the cap must also be there right past the top tread's end (no gap) ...
LANDING_PROBE = 0.3      # stairs: look for the upper cap this far past p1 along the flight ...
LANDING_SKIP_TOL = 0.05  # ... and skip the top landing when it is within this of p1's height
LANDING_THICK = 0.03     # otherwise the landing is a flush slab this thick, in the material of what it reaches


def stairs(name, p0, p1, width, collection, mat="M_Plank", side_mat="M_Wood_Dark", step_h=0.28,
           ground_index=None, stringers=True, overshoot=0.6):
    """Straight stairs from p0 (bottom) to p1 (top).

    A top landing extends `overshoot` meters past p1 at the top height so the stairs always reach onto the
    upper terrace even when its edge is curved - unless the ground index already reports the upper cap at the top
    height (within LANDING_SKIP_TOL) 0.3 m past p1, in which case no landing is built (no plank pad lying on the
    grass). When a landing is needed it is a flush 3 cm slab in the material of the surface it reaches onto (the
    cap's grass, cobble...), falling back to the tread material.
    """
    a = Vector(p0)
    b = Vector(p1)
    dz = b.z - a.z
    n = max(2, int(round(abs(dz) / step_h)))
    d2 = Vector((b.x - a.x, b.y - a.y, 0))
    run = d2.length
    d2.normalize()
    yaw = math.degrees(math.atan2(d2.y, d2.x))
    mb = MeshBuilder()
    for i in range(n):
        t0 = i / n
        t1 = (i + 1) / n
        c = a.lerp(b, (t0 + t1) / 2)
        z_top = a.z + dz * t1 + STAIR_LIFT
        depth = run / n + 0.04
        mb.box((depth, width, 0.16), loc=(c.x, c.y, z_top - 0.08), rot=(0, 0, yaw), mat=mat, bevel=0.03, segs=1)
        base = min(a.z, b.z) - 0.35
        body_h = z_top - 0.16 - base
        if body_h > 0.05:  # solid riser block under the tread (reads as masonry/timber, not floating tiles)
            mb.box((depth - 0.02, width - 0.06, body_h), loc=(c.x, c.y, base + body_h / 2), rot=(0, 0, yaw),
                   mat=side_mat, bevel=0.02, segs=1)
    if overshoot > 0:
        land_mat, skip = mat, False
        if ground_index is not None:
            fwd = Vector((d2.x, d2.y, 0))
            side = Vector((-d2.y, d2.x, 0))
            q = b + fwd * LANDING_PROBE
            gz, _gn, gob, gmat = ground_index.raycast_down_hit(q.x, q.y, z_from=b.z + 0.6)
            # skip only when the cap is at the top height 0.3 m past p1 AND right past the top tread's end, across
            # the flight (a gap between the last tread and the cap edge still needs the landing to bridge it)
            skip = True
            for t in (LANDING_GAP_PROBE, LANDING_PROBE):
                for lat in (-0.35 * width, 0.0, 0.35 * width):
                    p = b + fwd * t + side * lat
                    z = ground_index.raycast_down(p.x, p.y, z_from=b.z + 0.6)[0]
                    if z is None or abs(z - b.z) > LANDING_SKIP_TOL:
                        skip = False
            if not skip and gz is not None and gmat and abs(gz - b.z) <= 0.3 and \
                    not (gob is not None and gob.get("collider")):
                land_mat = gmat
        if not skip:
            land = b + Vector((d2.x, d2.y, 0)) * (overshoot / 2)
            top = b.z + STAIR_LIFT * 0.4  # flush: just proud of a cap at the top height
            mb.box((overshoot + 0.1, width, LANDING_THICK), loc=(land.x, land.y, top - LANDING_THICK / 2),
                   rot=(0, 0, yaw), mat=land_mat, bevel=0.008, segs=1)
    if stringers:
        nrm = Vector((-d2.y, d2.x, 0))
        for side in (-1, 1):
            off = nrm * side * (width / 2 + 0.06)
            mid = a.lerp(b, 0.5) + off
            length = math.sqrt(run ** 2 + dz ** 2)
            pitch = math.degrees(math.atan2(dz, run))
            mb.box((length - 0.2, 0.12, 0.3), loc=(mid.x, mid.y, mid.z - 0.12), rot=(0, -pitch, yaw),
                   mat=side_mat, bevel=0.03, segs=1)
    obj = mb.build(name, collection, smooth=False)
    if ground_index is not None:
        ground_index.add(obj)
    return obj


_RIBBON_COUNT = 0


RIBBON_LIP = 0.28      # a height jump this big between ribbon samples is a lip/cliff, not a slope
RIBBON_LAT_STEP = 0.15  # lateral probe spacing when looking for the edge of the ground under a ribbon
RIBBON_SPLIT = 0.5      # a centre-line jump bigger than a walkable step (0.45) splits the ribbon at the lip


def path_ribbon(name, pts, width, collection, ground, mat="M_Path_Dirt", lift=0.05, step=0.3,
                smooth_iters=2, edge_wobble=0.12, seed=0, width_fn=None, lip=RIBBON_LIP, end_taper=0.55,
                split=RIBBON_SPLIT):
    """A flat painted path draped over the ground (raycast), with softly rounded ends.

    Rows every `step` m carry several vertices across the width, each raycast, so the ribbon hugs
    cambered ground and cap bevels instead of being cut through by them. Where the ground across a row
    jumps by >= `lip` (a terrace lip, a ramp side, a cliff edge) the row is clipped back to the edge (no
    flat overhanging flap); where the centre line itself jumps by more than a walkable step (`split`)
    between rows the ribbon is split there, the upper piece ending right at the lip (smaller steps, such as
    a cap lip overhanging a ramp top, stay draped). width_fn(t), t = 0..1 along the ribbon, scales
    the width (used by ramp blend ribbons); end_taper is the width factor at both tips.
    """
    global _RIBBON_COUNT
    _RIBBON_COUNT += 1
    lift = lift + 0.006 * (_RIBBON_COUNT % 6)  # successive ribbons layer instead of z-fighting
    pts = chaikin(pts, smooth_iters, closed=False) if len(pts) > 2 else pts
    pts = resample(pts, step, closed=False)
    mb = MeshBuilder()
    bm = mb.bm
    mi = mb.mat(mat)
    n = len(pts)
    P = [Vector(p) for p in pts]
    S = [0.0]
    for i in range(1, n):
        S.append(S[-1] + (P[i] - P[i - 1]).length)
    total = S[-1] or 1.0
    n_lat = max(3, int(math.ceil(width / 0.6)) + 1)  # vertices across the ribbon

    def ray(v):
        return ground.raycast_down(v.x, v.y)[0]

    def extent(p, d, hw, zc):
        """How far from p along d (<= hw) the ground stays continuous with the centre (no lip, has ground)."""
        z_prev, t_ok = zc, 0.0
        t = min(RIBBON_LAT_STEP, hw)
        while True:
            z = ray(p + d * t)
            if z is None or abs(z - z_prev) > lip:
                lo, hi = t_ok, t  # the edge lies between the last good probe and this one
                for _ in range(4):
                    mid = (lo + hi) * 0.5
                    zm = ray(p + d * mid)
                    if zm is not None and abs(zm - z_prev) < lip * 0.5:
                        lo = mid
                    else:
                        hi = mid
                return lo
            t_ok, z_prev = t, z
            if t >= hw - 1e-6:
                return hw
            t = min(t + RIBBON_LAT_STEP, hw)

    def make_row(p, nrm, hl, hr, zc, prev=None):
        el, er = extent(p, nrm, hl, zc), extent(p, -nrm, hr, zc)
        fwd = Vector((nrm.y, -nrm.x))
        verts, pos = [], []
        for k in range(n_lat):
            s = p + nrm * (el - (el + er) * k / (n_lat - 1))
            if prev is not None:  # inside of a tight turn: never let a vertex fall behind its predecessor
                d = (s - prev[k]).dot(fwd)
                if d < 0.01:
                    s = s + fwd * (0.01 - d)
            z = ray(s)
            if z is None or abs(z - zc) > lip * 3:
                z = zc
            verts.append(bm.verts.new((s.x, s.y, z + lift)))
            pos.append(s)
        return verts, el, er, pos

    rows = []  # per sample: None (no ground under the centre) or (zc, verts, p, nrm, el, er)
    prev = None
    for i in range(n):
        p = P[i]
        q = P[min(i + 2, n - 1)] - P[max(i - 2, 0)]  # a wide window keeps row directions smooth in turns
        if q.length < 1e-6:
            q = Vector((1, 0))
        q.normalize()
        nrm = Vector((-q.y, q.x))
        zc = ray(p)
        if zc is None:
            rows.append(None)
            prev = None
            continue
        u = min(1.0, min(S[i], total - S[i]) / 0.6)
        taper = end_taper + (1.0 - end_taper) * (u * u * (3 - 2 * u))  # soft rounded ends (old 0.55 footprint)
        fw = width_fn(S[i] / total) if width_fn else 1.0
        hw = width / 2 * taper * fw * (1 + noise.noise(Vector((p.x * 0.4, p.y * 0.4, seed))) * edge_wobble)
        hw = max(hw, 0.05)
        verts, el, er, prev = make_row(p, nrm, hw, hw, zc, prev)
        rows.append((zc, verts, p, nrm, el, er))

    def quads(ra, rb):
        for k in range(n_lat - 1):
            fc = bm.faces.new((ra[k], ra[k + 1], rb[k + 1], rb[k]))
            fc.material_index = mi

    for i in range(n - 1):
        a, b = rows[i], rows[i + 1]
        if a is None or b is None:
            continue
        if abs(a[0] - b[0]) < split:
            quads(a[1], b[1])
            continue
        # the centre line crosses a lip: close the upper piece right at the edge, leave a gap to the lower
        upper, lower = (a, b) if a[0] >= b[0] else (b, a)
        lo, hi = upper[2], lower[2]
        for _ in range(5):
            mid = (lo + hi) * 0.5
            zm = ray(mid)
            if zm is not None and abs(zm - upper[0]) < split * 0.5:
                lo = mid
            else:
                hi = mid
        if (lo - upper[2]).length < 0.03:
            continue
        zl = ray(lo)
        verts, _el, _er, _pos = make_row(lo, upper[3], upper[4], upper[5], upper[0] if zl is None else zl)
        if upper is a:
            quads(a[1], verts)
        else:
            quads(verts, b[1])
    return mb.build(name, collection, smooth=True)


def flat_poly(name, poly, z, collection, mat, smooth_iters=1):
    poly = chaikin(ensure_ccw(poly), smooth_iters)
    mb = MeshBuilder()
    bm = mb.bm
    vs = [bm.verts.new((x, y, z)) for x, y in poly]
    f = bm.faces.new(vs)
    f.material_index = mb.mat(mat)
    bmesh.ops.triangulate(bm, faces=[f])
    return mb.build(name, collection, smooth=True, recalc_normals=False)


def foam_ring(name, poly, z, width, collection, seed=0):
    """Shoreline foam band hugging an outline."""
    inner = ensure_ccw(chaikin(resample(poly, 1.0), 1))
    outer = offset_poly(inner, width)
    outer = wobble(outer, width * 0.35, seed=seed, freq=0.5)
    mb = MeshBuilder()
    bm = mb.bm
    mi = mb.mat("M_Foam")
    a = [bm.verts.new((x, y, z)) for x, y in inner]
    b = [bm.verts.new((x, y, z)) for x, y in outer]
    n = len(a)
    for i in range(n):
        f = bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
        f.material_index = mi
    return mb.build(name, collection, smooth=False, recalc_normals=False)
