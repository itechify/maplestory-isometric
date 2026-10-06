"""Amherst Townstreet (1010002) - "the house in Townstreet".

Classic (GMS v8) structure, from docs/research/maps/1010002_AmherstTownstreet_1010002.md:
  a big orange-capped two-storey mushroom house shown as a doll-house cutaway: T02 ground
  floor (one 29 px doorstep up; bookcase, hanging lamp), a wooden ladder (x 77) up to the T04
  upper room (bed, chest, curtained window). Out of its WEST door: T01, a short garden path
  with an orange flower bed, a bush and a DANGER sign just before west00, the back way out of
  town to the Snail Field of Flowers. T03 is a contentless strip behind/under the house. No
  NPCs, no mobs (data).

3D translation (the camera looks straight along local +y): you arrive from Amherst at the
front edge (out00) and walk up a grass lane into the big orange house through its cut-away
front. The cap is sliced like a doll's house (cream flesh, orange spotted skin), the front
walls are cut down to knee height and the wings to one storey, so both floors read at once:
the double-height west room with the bookcase and the bedroom loft on the east side, reached
only by the ladder. The house is a through-route: its broad stone-arched west door (two stone
treads down) opens onto the hedged garden path, past the orange marigold bed, under a leafy
trail-head arch with the DANGER sign, to the exit toward the Snail Field of Flowers (west00).
The cap's cut face shows apricot rim, cream flesh and a fan of gills. This is the island's one
orange house: from Amherst it is the house seen up the lane behind the in01 garden arch.
The east side is the T03 back garden (vegetable bed, washing line, woodpile).
"""

import math

import bpy

from misostory import geo
from misostory import materials as M
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.classic import barrel_chimney, wall_lantern

MAP_ID = 1010002
GAMEPLAY_FOCUS = (12.5, 11.0)
GAMEPLAY_SCALE = 27.0

# house frame (map local); the asset is built around (0, 0)
HX, HY = 14.0, 12.6
RX, RY = 6.4, 5.0          # wall centre-line ellipse
FLOOR = 0.4                # T02: 29 px doorstep
LOFT = 4.4                 # T04 bedroom loft
TOP = 7.6                  # wall top / cap base
CUT = 2.4                  # the cap is sliced this far behind the house centre
WALL_T = 0.4
FLESH = "M_X1010002_MushFlesh"   # map-local material: warm cream flesh (faintly self-lit: the slice faces away from the sun)
RIM = "M_X1010002_FleshRim"       # map-local: apricot band just under the orange skin
GROOVE = "M_X1010002_GillGroove"  # map-local: warm tan gill grooves fanning out from the stem (the house)


# ---------------------------------------------------------------------------
# Local assets
# ---------------------------------------------------------------------------

def _wall_top(deg):
    d = deg % 360.0
    if 30.0 <= d <= 150.0:
        return TOP              # back wall under the cap
    if d < 30.0 or d >= 330.0:
        return LOFT + 1.0       # east wing: loft parapet
    if 150.0 < d <= 225.0:
        return 4.6              # west wing: one storey, holds the west door
    return FLOOR + 0.9          # cut-away front: knee wall


ENTRANCE = (258.0, 282.0)       # front opening (toward out00)
# west door (toward the garden path / west00): set in the front-west curve of the wall so that it
# faces about 40 degrees toward the camera instead of edge-on (door centre ~ map (8.6, 9.9)). A broad
# double-door arch: the wall ends are 3.0 m apart, so the clear opening between the frame posts is ~2.7 m
# (a through-route, not a closet door).
WEST_DOOR = (197.0, 229.0)
DOOR_MID = math.radians(sum(WEST_DOOR) / 2)


def _in(d, rng):
    d = d % 360.0
    return rng[0] <= d <= rng[1]


def _ell(t):
    return RX * math.cos(t), RY * math.sin(t)


def _inward(t):
    nx, ny = -math.cos(t) / RX, -math.sin(t) / RY
    L = math.hypot(nx, ny)
    return nx / L, ny / L


def _cut_dome(mb, rx, ry, h, zb, c, skin, flesh, u=36, v=10, p=0.75, lip=0.4):
    """Mushroom cap sliced by the plane y = c (keeps y >= c): skin, section face, underside."""
    bm = mb.bm
    phi_top = math.acos(min(1.0, (c / ry)) ** (1.0 / p))
    rings = []
    for j in range(v):
        phi = phi_top * j / v
        k = math.cos(phi) ** p
        rrx, rry = rx * k, ry * k
        t0 = math.asin(min(1.0, c / rry))
        z = zb + h * math.sin(phi)
        ring = [bm.verts.new((rrx * math.cos(t0 + (math.pi - 2 * t0) * i / u),
                              rry * math.sin(t0 + (math.pi - 2 * t0) * i / u), z)) for i in range(u + 1)]
        rings.append(ring)
    apex = bm.verts.new((0.0, c, zb + h * math.sin(phi_top)))
    lrx, lry = rx - lip * 0.4, ry - lip * 0.4
    t0 = math.asin(min(1.0, c / lry))
    lipr = [bm.verts.new((lrx * math.cos(t0 + (math.pi - 2 * t0) * i / u),
                          lry * math.sin(t0 + (math.pi - 2 * t0) * i / u), zb - lip)) for i in range(u + 1)]
    si = mb.mat(skin)
    fi = mb.mat(flesh)
    faces = []
    for a, b in ([lipr, rings[0]],) + tuple((rings[j], rings[j + 1]) for j in range(v - 1)):
        for i in range(u):
            f = bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
            f.material_index = si
            faces.append(f)
    last = rings[-1]
    for i in range(u):
        f = bm.faces.new((last[i], last[i + 1], apex))
        f.material_index = si
    # section face (the slice) and the flat underside
    sect = [lipr[0]] + [r[0] for r in rings] + [apex] + [r[u] for r in reversed(rings)] + [lipr[u]]
    f = bm.faces.new(sect)
    f.material_index = si
    f = bm.faces.new(list(reversed(lipr)))
    f.material_index = fi
    # the cut face, layered toward the camera: orange skin band (the section face itself) -> apricot rim band
    # -> warm cream flesh -> a fan of tapered gill grooves converging on the house below (reads as a sliced
    # mushroom cap, not a flat screen)
    sec = geo.ensure_ccw([(v_.co.x, v_.co.z) for v_ in sect])
    rim = geo.offset_poly(sec, -0.35)
    fl = geo.offset_poly(sec, -0.9)
    mb.prism(rim, -0.01, 0.05, loc=(0, c, 0), rot=(90, 0, 0), mat=RIM)
    mb.prism(fl, 0.05, 0.09, loc=(0, c, 0), rot=(90, 0, 0), mat=flesh)

    def inside(px, pz, poly):
        hit = False
        for (ax, az), (bx, bz) in zip(poly, poly[1:] + poly[:1]):
            if (az > pz) != (bz > pz) and px < ax + (pz - az) * (bx - ax) / (bz - az):
                hit = not hit
        return hit

    zb0 = min(q[1] for q in fl)
    fx, fz = 0.0, zb0 - 0.9                   # focal point: just below the slab, over the house centre
    n = 19
    for k in range(n):
        a = math.pi * (0.04 + 0.92 * (k + 0.5) / n)
        dx, dz = math.cos(a), math.sin(a)
        r = 1.0
        while inside(fx + dx * (r + 0.1), fz + dz * (r + 0.1), fl) or r < 1.6:
            r += 0.1
            if r > 12:
                break
        r1 = r - 0.3
        r0 = max(1.25, r1 * 0.32)
        if r1 - r0 < 0.4:
            continue
        px, pz = -dz, dx
        w0, w1 = 0.025, 0.07 if k % 2 else 0.05
        wedge = [(fx + dx * r0 + px * w0, fz + dz * r0 + pz * w0), (fx + dx * r0 - px * w0, fz + dz * r0 - pz * w0),
                 (fx + dx * r1 - px * w1, fz + dz * r1 - pz * w1), (fx + dx * r1 + px * w1, fz + dz * r1 + pz * w1)]
        mb.prism(geo.ensure_ccw(wedge), 0.09, 0.12, loc=(0, c, 0), rot=(90, 0, 0), mat=GROOVE)


@asset("X1010002_CutawayHouse", "Architecture", footprint=16.0, tags=("house", "landmark", "mushroom"))
def _cutaway_house(coll):
    """Two-storey orange mushroom house cut open toward -Y (Amherst Townstreet). Origin = ground."""
    walls = MeshBuilder()
    n = 128

    def strip(ts, thick, z0, z1, mat):
        """One closed wall strip along the ellipse (continuous, so the ink outline only rims its ends)."""
        bm = walls.bm
        rows = []
        for t in ts:
            x, y = _ell(t)
            nx, ny = _inward(t)
            ox, oy, ix, iy = x - nx * thick / 2, y - ny * thick / 2, x + nx * thick / 2, y + ny * thick / 2
            rows.append((bm.verts.new((ox, oy, z0)), bm.verts.new((ox, oy, z1)), bm.verts.new((ix, iy, z1)),
                         bm.verts.new((ix, iy, z0))))
        faces = [bm.faces.new(rows[0]), bm.faces.new(list(reversed(rows[-1])))]
        for a, b in zip(rows, rows[1:]):
            for q in range(4):
                faces.append(bm.faces.new((a[q], b[q], b[(q + 1) % 4], a[(q + 1) % 4])))
        mi = walls.mat(mat)
        for f in faces:
            f.material_index = mi

    def runs(keyfn):
        """Group consecutive segments by key (None = no wall); yields (key, [angles])."""
        cur, start = None, 0
        keys = [keyfn(math.degrees(2 * math.pi * (k + 0.5) / n)) for k in range(n)] + [None]
        for k, key in enumerate(keys):
            if key != cur:
                if cur is not None:
                    yield cur, [2 * math.pi * j / n for j in range(start, k + 1)]
                cur, start = key, k

    def wall_key(d):
        if _in(d, ENTRANCE):
            return None
        return (FLOOR + 2.4 if _in(d, WEST_DOOR) else FLOOR + 0.05, _wall_top(d))

    for (z0, top), ts in runs(wall_key):
        strip(ts, WALL_T, z0, top - 0.2, "M_Plaster")
        strip(ts, WALL_T + 0.1, top - 0.2, top, "M_Wood_Dark")
    # stone foundation ring (cut at both openings: the west doorstep is real walkable stairs, see build())
    for _k, ts in runs(lambda d: None if (_in(d, ENTRANCE) or _in(d, WEST_DOOR)) else 1):
        strip(ts, WALL_T + 0.2, 0.0, FLOOR + 0.05, "M_StoneWall")
    # floor-slab beam on the two-storey parts, half-timber rail round the ground floor
    for _k, ts in runs(lambda d: 1 if _wall_top(d) >= LOFT + 0.9 else None):
        strip(ts, WALL_T + 0.08, LOFT - 0.23, LOFT, "M_Wood_Dark")
    for _k, ts in runs(lambda d: 1 if _wall_top(d) >= 4.5 and not _in(d, WEST_DOOR) else None):
        strip(ts, WALL_T + 0.06, FLOOR + 0.97, FLOOR + 1.13, "M_Wood")
    # timber posts
    for deg in range(0, 360, 30):
        if _in(deg, ENTRANCE) or _in(deg, WEST_DOOR):
            continue
        t = math.radians(deg)
        x, y = _ell(t)
        top = max(_wall_top(deg - 1), _wall_top(deg + 1))
        nx, ny = _inward(t)
        yaw = math.degrees(math.atan2(nx, -ny))
        walls.box((0.3, WALL_T + 0.14, top - FLOOR), loc=(x, y, (top + FLOOR) / 2), rot=(0, 0, yaw),
                  mat="M_Wood_Dark")
    # west door: a broad frame at the two wall ends, two open plank leaves folded back against the outer wall,
    # a mushroom awning over the lintel. The stone doorstep is walkable stairs placed by build().
    tw = DOOR_MID
    xw, yw = _ell(tw)
    nx, ny = _inward(tw)
    yaw = math.degrees(math.atan2(nx, -ny))
    tx, ty = -ny, nx                         # wall tangent (toward the back of the house here)
    ox, oy = -nx, -ny                        # outward normal
    ends = [_ell(math.radians(a)) for a in WEST_DOOR]
    half = math.hypot(ends[1][0] - ends[0][0], ends[1][1] - ends[0][1]) / 2   # ~1.5 m
    for s in (-1, 1):
        px, py = xw + tx * s * (half - 0.08), yw + ty * s * (half - 0.08)
        walls.box((0.26, WALL_T + 0.24, 2.6), loc=(px, py, FLOOR + 1.3), rot=(0, 0, yaw), mat="M_Wood_Dark")
    walls.box((2 * half + 0.3, WALL_T + 0.28, 0.28), loc=(xw, yw, FLOOR + 2.5), rot=(0, 0, yaw), mat="M_Wood_Dark")
    # two plank leaves, hinged at the posts and swung out flat against the wall (155 deg open): they frame the
    # opening from the camera and keep the 2.7 m doorway clear
    leaf = half - 0.1
    for s in (-1, 1):
        sw = math.radians(25.0)
        ct = half + leaf / 2 * math.cos(sw)
        co = WALL_T / 2 + 0.06 + leaf / 2 * math.sin(sw)
        walls.box((leaf, 0.1, 2.35), loc=(xw + tx * s * ct + ox * co, yw + ty * s * ct + oy * co, FLOOR + 1.2),
                  rot=(0, 0, yaw - s * 25), mat="M_Door", bevel=0.03, segs=1)
        for zz in (0.55, 1.85):  # iron straps
            walls.box((leaf * 0.9, 0.13, 0.08), loc=(xw + tx * s * ct + ox * (co + 0.02),
                                                     yw + ty * s * ct + oy * (co + 0.02), FLOOR + zz),
                      rot=(0, 0, yaw - s * 25), mat="M_Metal")
    # stone-arched doorway (classic house6 "stone-arched door"): a flattened arch of stone voussoirs with an
    # orange keystone over the lintel, and a warm glowing fanlight between them
    zl = FLOOR + 2.64
    face = WALL_T / 2 + 0.06
    ra, rz = half + 0.12, 1.05
    n_v = 9
    for k in range(n_v):
        a0, a1 = math.pi * k / n_v, math.pi * (k + 1) / n_v
        am = (a0 + a1) / 2
        u, z = ra * math.cos(am), zl + rz * math.sin(am)
        seg = math.hypot(ra * (math.cos(a1) - math.cos(a0)), rz * (math.sin(a1) - math.sin(a0))) + 0.03
        tilt = math.degrees(math.atan2(rz * math.cos(am), -ra * math.sin(am)))
        walls.box((seg, 0.32, 0.34), loc=(xw + tx * u + ox * face, yw + ty * u + oy * face, z),
                  rot=(0, -tilt, yaw), mat="M_Spot_mush_orange__flower_yellow" if k == n_v // 2 else "M_StoneWall",
                  bevel=0.03, segs=1)
    fan = [((ra - 0.2) * math.cos(math.pi * k / 12), (rz - 0.2) * math.sin(math.pi * k / 12)) for k in range(13)]
    fx_, fy_ = xw + ox * (face - 0.04), yw + oy * (face - 0.04)
    walls.prism([(u, zl + z) for (u, z) in fan], -0.03, 0.03, loc=(fx_, fy_, 0), rot=(90, 0, yaw),
                mat="M_Glow_window")
    for k in (3, 6, 9):  # fanlight glazing bars
        a = math.pi * k / 12
        L_ = 0.5 * ((ra - 0.2) + (rz - 0.2))
        walls.box((0.05, 0.08, L_), loc=(fx_ + ox * 0.03 + tx * math.cos(a) * L_ / 2,
                                          fy_ + oy * 0.03 + ty * math.cos(a) * L_ / 2, zl + math.sin(a) * L_ / 2),
                  rot=(0, 90 - math.degrees(a), yaw), mat="M_Wood_Dark")
    # red runner on the floor from the front entrance to the west door (lifted 2 cm)
    ex, ey = 0.0, -RY + 0.9
    dx, dy = xw + nx * 0.5, yw + ny * 0.5
    run = math.hypot(dx - ex, dy - ey)
    walls.box((run, 1.0, 0.04), loc=((ex + dx) / 2, (ey + dy) / 2, FLOOR + 0.02),
              rot=(0, 0, math.degrees(math.atan2(dy - ey, dx - ex))), mat="M_Cloth_Red", bevel=0.01, segs=1)
    # round windows on the inner face of the back wall (seen through the cut)
    for deg, z in ((122.0, FLOOR + 2.3), (96.0, FLOOR + 2.3), (42.0, LOFT + 1.45)):
        t = math.radians(deg)
        x, y = _ell(t)
        nx, ny = _inward(t)
        rz = math.degrees(math.atan2(nx, -ny))
        bx, by = x + nx * (WALL_T / 2 - 0.03), y + ny * (WALL_T / 2 - 0.03)
        walls.cyl(0.6, 0.12, loc=(bx, by, z), rot=(90, 0, rz), mat="M_Wood_Dark", verts=18)
        walls.cyl(0.46, 0.16, loc=(bx, by, z), rot=(90, 0, rz), mat="M_Window", verts=18)
        walls.box((0.95, 0.06, 0.07), loc=(bx + nx * 0.17, by + ny * 0.17, z), rot=(0, 0, rz), mat="M_Wood_Dark")
        walls.box((0.07, 0.06, 0.95), loc=(bx + nx * 0.17, by + ny * 0.17, z), rot=(0, 0, rz), mat="M_Wood_Dark")
        if deg == 42.0:  # curtains in the bedroom
            for s in (-1, 1):
                walls.box((0.32, 0.05, 1.15), loc=(bx + nx * 0.22 + (-ny) * s * 0.5, by + ny * 0.22 + nx * s * 0.5,
                                                   z - 0.05), rot=(0, 0, rz), mat="M_Flat_flower_pink")
    # iron wall lantern on the bedroom's back wall, beside the curtained window (wall faces ~ -y there)
    t = math.radians(62.0)
    x, y = _ell(t)
    nx, ny = _inward(t)
    wall_lantern(walls, (x + nx * (WALL_T / 2 + 0.02), y + ny * (WALL_T / 2 + 0.02), LOFT + 1.6))
    # loft: front corner posts and an underside beam
    for (x, y) in ((0.6, -3.1), (4.7, -3.1)):
        walls.box((0.26, 0.26, LOFT - FLOOR), loc=(x, y, (LOFT + FLOOR) / 2), mat="M_Wood_Dark")
    walls.box((4.4, 0.3, 0.3), loc=(2.65, -3.1, LOFT - 0.35), mat="M_Wood_Dark")
    walls.build("X1010002_CutawayHouse_Walls", coll, smooth=True, sharp_angle=40)
    # the cap, sliced like a doll's house
    cap = MeshBuilder()
    if bpy.data.materials.get(FLESH) is None:
        # the slice faces away from the sun: a faint self-glow keeps it reading as cream mushroom flesh;
        # darker toward the gills so the slab has some structure
        M.mat_gradient(FLESH, "#EDB878", "#FBDFB2", 0.0, 0.9, noise_amt=0.06, emission=0.55)
    if bpy.data.materials.get(RIM) is None:
        M.mat_flat(RIM, "#F09A4A", emission=0.45)
        M.mat_flat(GROOVE, "#D49A5E", emission=0.35)
    _cut_dome(cap, 9.0, 7.2, 5.0, TOP, CUT, "M_Spot_mush_orange__flower_yellow", FLESH, p=0.72, lip=0.55)
    barrel_chimney(cap, (4.2, 4.6, TOP + 3.1))
    barrel_chimney(cap, (4.9, 5.2, TOP + 2.1))
    cap.build("X1010002_CutawayHouse_Cap", coll, smooth=True, sharp_angle=55)


@asset("X1010002_Bookcase", "Props", footprint=1.8, tags=("interior",))
def _bookcase(coll):
    """Tall bookcase full of coloured books (faces -Y)."""
    from misostory import core
    r = core.rng("x1010002_books", 1)
    mb = MeshBuilder()
    mb.box((1.8, 0.45, 2.4), loc=(0, 0.05, 1.2), mat="M_Wood_Dark", bevel=0.03, segs=1)
    cols = ["M_Flat_roof_red", "M_Flat_roof_blue", "M_Flat_roof_green", "M_Flat_roof_yellow", "M_Flat_cloth_white",
            "M_Flat_flower_purple", "M_Flat_roof_orange"]
    for k in range(4):
        z = 0.12 + k * 0.58
        mb.box((1.66, 0.4, 0.05), loc=(0, -0.08, z), mat="M_Plank")
        x = -0.76
        while x < 0.7:
            w = r.uniform(0.07, 0.13)
            hgt = r.uniform(0.3, 0.46)
            mb.box((w, 0.3, hgt), loc=(x + w / 2, -0.1, z + 0.03 + hgt / 2), rot=(0, r.uniform(-4, 4), 0),
                   mat=r.choice(cols))
            x += w + 0.015
    mb.build("X1010002_Bookcase", coll, smooth=False)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _door_point(out, side=0.0):
    """Map point on the west door's axis, `out` metres outside the wall centre-line (negative = inside),
    `side` metres along the wall tangent (positive = toward the back of the house)."""
    x, y = _ell(DOOR_MID)
    nx, ny = _inward(DOOR_MID)
    return (round(HX + x - nx * out - ny * side, 3), round(HY + y - ny * out + nx * side, 3))


def _loft_outline():
    """East-side bedroom loft: the house interior with x >= HX + 0.6 and y >= HY - 3.1."""
    ix, iy = RX - 0.22, RY - 0.22
    xw, yf = HX + 0.6, HY - 3.1
    ta = math.asin((yf - HY) / iy)
    tb = math.acos((xw - HX) / ix)
    pts = [(xw, yf)]
    n = 16
    for k in range(n + 1):
        t = ta + (tb - ta) * k / n
        pts.append((HX + ix * math.cos(t), HY + iy * math.sin(t)))
    return pts


# ---------------------------------------------------------------------------
# Map
# ---------------------------------------------------------------------------

def build(m):
    L, D = m.size  # 24 x 22

    # ================= terrain =================
    m.terrace("GroundFloor", geo.ellipse(HX, HY, RX - 0.05, RY - 0.05, 56), top=FLOOR, bottom=-0.3,
              style="wood_floor", wobble_amt=0.0, smooth_iters=1)
    m.deck("Loft", _loft_outline(), top=LOFT, posts=False)
    m.ladder("Ladder_Loft", 16.0, HY - 3.4, FLOOR, LOFT, facing=90)
    m.rail("Loft_Rail_FrontW", [(HX + 0.6, HY - 3.1), (15.45, HY - 3.1)], LOFT, closed=False)
    m.rail("Loft_Rail_FrontE", [(16.55, HY - 3.1), (HX + 4.6, HY - 3.1)], LOFT, closed=False)
    m.rail("Loft_Rail_West", [(HX + 0.6, HY - 3.1), (HX + 0.6, 17.1)], LOFT, closed=False)
    m.stairs("EntranceSteps", (HX, 6.5, 0.0), (HX, 7.9, FLOOR + 0.05), 2.6, mat="M_Plank", side_mat="M_Wood_Dark")
    # west doorstep: two stone treads through the cut foundation, straight out along the door normal
    (dxi, dyi), (dxo, dyo) = _door_point(-0.7), _door_point(1.7)
    m.stairs("WestDoorStep", (dxo, dyo, 0.0), (dxi, dyi, FLOOR), 2.7, mat="M_StoneWall", side_mat="M_Rock",
             stringers=False, overshoot=0.5)
    # lanes: Amherst side (front) and the garden path to the Snail Field of Flowers (west)
    m.path("FrontLane", [(14.0, 0.0), (14.0, 3.5), (14.0, 6.4)], width=2.8)
    # the path runs across the foot of the doorstep (the tread front is at out 1.7, 2.7 m wide), its near edge
    # 0.15 m clear of the tread so the ribbon never drapes up onto a step, then turns through the trail arch
    m.path("GardenPath", [_door_point(3.15, -1.2), _door_point(3.15, 1.5), (4.0, 11.35), (2.5, 11.7), (0.0, 12.0)],
           width=2.6)
    # starts 0.65 m east of the entrance steps' side face (x 15.3) so the ribbon never drapes up onto a tread
    m.path("GardenLane", [(15.95, 6.15), (17.2, 6.9), (19.2, 6.6)], width=2.4)

    # ================= the house =================
    m.place("X1010002_CutawayHouse", HX, HY, z=0.0)
    # ground floor (double-height west room): bookcase, table, rug, the Pio-quest wooden boxes
    m.place("X1010002_Bookcase", 11.4, 16.5, rot=18, z=FLOOR)
    m.place("Rug_Round", 11.2, 11.6, scale=0.9, z=FLOOR)
    m.place("Table_Round", 11.2, 11.8, rot=10)
    m.place("Crate", 9.7, 13.9, rot=20, z=FLOOR)
    m.place("Barrel", 10.3, 15.1, z=FLOOR)
    m.place("Crate", 17.9, 10.0, rot=-10, z=FLOOR)
    m.place("Sack", 19.0, 10.4, z=FLOOR)
    m.place("Hanging_Lantern", 17.8, 9.5, z=LOFT - 0.5, scale=1.6)   # hangs from the loft front beam
    # bedroom loft: bed under the window, chest, little rug
    # (kit bed has its headboard at -x: rot = -12 - 90 keeps the head at the back wall; 0.85 keeps it 2.25 m long)
    m.place("Bed", 17.6, 15.4, rot=-102, z=LOFT, scale=0.85)
    m.place("Treasure_Chest", 19.0, 12.0, rot=-15, z=LOFT)
    m.place("Rug_Round", 16.9, 12.2, scale=0.55, z=LOFT)

    # ================= garden dressing =================
    # T01 garden path: a leafy trail-head arch at west00 with the DANGER sign beside it, low hedges along the
    # path, the orange flower bed and a bush cluster north of it (classic acc1 nature/5,6,13,21)
    m.place("Arch_Leafy_Trail", 4.0, 11.35, rot=40, scale=1.05)
    m.place("Sign_Danger_Skull", 1.4, 8.7, rot=8)
    m.place("Hedge_Wall_4m", 7.3, 11.2, rot=139, scale=(0.46, 0.8, 0.7))
    m.place("Hedge_Wall_4m", 4.64, 6.86, rot=139, scale=(0.6, 0.8, 0.7))   # across the doorstep, beyond the path
    m.place("Flower_Bed_Large", 4.4, 15.6, rot=20)
    for (x, y, rr) in ((2.8, 15.4, 10), (6.4, 14.6, 70), (5.9, 16.6, 140), (3.4, 17.2, 200)):
        m.place("Marigold_Patch", x, y, rot=rr)
    m.place("Bush_A", 4.8, 18.8, rot=40)
    m.place("Bush_Flowering_A", 6.6, 18.0, rot=10)
    m.place("Bush_B", 2.6, 19.2, rot=80, scale=0.9)
    m.place("Flower_Bed_Large", 3.2, 4.5, rot=-30)
    m.place("Lamp_Post", 11.9, 4.8)
    m.place("Lamp_Post", 16.1, 4.8)
    m.place("Mailbox_Red", 12.0, 6.6, rot=8)
    m.place("Sign_Board", 9.4, 4.2, rot=-6)
    m.fence([(1.6, 1.8), (6.0, 1.6), (11.6, 1.8)], asset_name="Fence_Picket_Seg")
    m.fence([(16.4, 1.8), (20.0, 1.6), (23.4, 1.9)], asset_name="Fence_Picket_Seg")
    # T03 back garden on the east side: vegetable bed, washing line, a woodpile against the house wall
    m.place("Veg_Garden_Bed", 21.4, 4.4, rot=0, scale=0.9)
    m.place("Clothesline_Laundry", 20.9, 8.2, rot=-4)
    m.place("Log_A", 21.95, 12.6, rot=90)
    m.place("Log_A", 22.72, 12.5, rot=88)
    m.place("Log_A", 22.33, 12.7, rot=93, z=0.62)
    m.place("Stump_A", 22.5, 15.0, rot=30, scale=0.8)
    m.place("Barrel", 22.6, 16.6)
    m.place("Crate_Stack", 22.6, 18.6, rot=-15)
    for i, (x, y) in enumerate([(5.4, 20.9), (9.0, 21.4), (21.6, 20.6), (0.8, 4.6)]):
        m.place(["Tree_Round_A", "Tree_Birch_Orange", "Tree_Round_C", "Bush_B"][i], x, y, rot=i * 61)
    m.place("Butterfly", 5.0, 13.6)
    m.place("Stump_A", 10.4, 12.9, rot=20, scale=0.55, z=FLOOR)
    m.place("Mushroom_Red_S", 8.0, 5.6, rot=30, scale=1.3)
    m.place("Mushroom_Orange_S", 7.2, 6.2, rot=-20)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A"], geo.rect(0.4, 0.4, 23.6, 21.6), 30, seed=3,
              min_dist=1.4, avoid=[geo.ellipse(HX, HY, RX + 0.8, RY + 0.8), geo.rect(12, 0, 16, 7),
                                   geo.rect(0, 8.0, 9, 13.6), geo.rect(4.0, 5.6, 9.2, 8.6), geo.rect(15, 3.0, 24, 19),
                                   geo.rect(1, 14, 8, 20)])

    # ================= gameplay =================
    m.edge_portal("out00")
    m.edge_portal("west00")
    m.player(14.6, 4.0, rot=-20)
    m.player_spawn(6.0, 10.0, rot=90, note="sp x -329: on the street between west00 and out00")
    # through-route: Amherst lane -> into the house -> out of the west door -> garden path -> west00
    m.route("Main", [(14.0, 1.0), (14.0, 5.6), (14.0, 8.6), (12.0, 9.6), _door_point(-1.2), _door_point(0.0),
                     _door_point(1.8), (5.0, 10.6), (1.0, 12.0)])
    # up the ladder (x 77) onto the bedroom loft: the validator classifies the 4 m rise at the loft edge as a climb
    m.route("Loft", [(14.0, 8.4), (16.0, 8.3), (16.0, 11.0), (17.2, 13.2)])
    m.route("BackGarden", [(14.0, 6.0), (16.8, 6.9), (19.0, 6.5)])
