"""Hunting Ground Middle of the Forest II (1000006) - "sky islands over an autumn dell".

Classic (GMS v8) structure, from docs/research/maps/1000006_HuntingGroundMidForest2_1000006.md:
  a smooth V-shaped valley chain T23a-g (west plateau with orange twin birches and white
  stake fences -> slope -> lily mid shelf -> slope -> valley floor with a yellow twin
  tree -> a LONG slope -> high fenced east plateau with a yellow tree); 600 px above it
  the floating centre island T17+T18 with the exit door in an earth block T12 and an
  autumn twin tree; around it a ring of grass islands: a west stair T15 -> T13 ->
  T11/T10 -> T8, the big west islands T9 and T5, T6, the umbrella-leaf island T4 with a
  rope ladder up to T1, the daffodil summit T0, T2/T3 (daffodils) and the east descent
  T7 -> T14 -> T16 -> T18; lower islands T21/T22 (west) and T19/T20 (east) with the
  three long ground ropes. Snails, Blue Snails, Red Snails, Shrooms, Orange Mushrooms.

3D translation: the layout fixes the exit at the front at z ~7, so the hub islet floats
at the front-centre on a tapering root-ball and an earthen stalk, and the island ring
climbs BACK behind it: west stair and west islands on the left, the crown (T0, T1, T4)
at the back, the daffodil island T3 and the rope descent on the right. Every island is
a grass cap on a stepped dirt ball and a dirt stalk rising out of the dell. Islands stand
apart with open air between them; where the classic has a hop or a 12 px gap they are
joined by a narrow grass tongue (a land bridge) instead of overlapping caps. The dell
keeps its V profile across x (real slopes, no steps) under everything; its open pockets
carry the autumn colour: orange birches + picket fences in the west grove, lilies and the
yellow twin tree in the centre dip, a crest fence and the yellow twin on the high east
plateau.

Routes are declared per tier/pocket and walk the ropes between them (ground under an
island cap is invisible to the top-down raycast, so no route runs under an island). The
dell pockets are reached by the long ground ropes, as in the classic map.
"""

import math

import bpy
from mathutils import Vector

from misostory import core, geo
from misostory import materials as M
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.nature import bush

MAP_ID = 1000006
# the golden dell mid-frame, the hub + arrival portal low in the frame: the Dangerous Forest (1000002) in front of
# the hub stays a sliver along the bottom edge in the island build
GAMEPLAY_FOCUS = (17.0, 19.0)
GAMEPLAY_SCALE = 36.0

# ---------------------------------------------------------------- heights
# dell (V profile along x)
W_PLATEAU, MID_SHELF, FLOOR, E_PLATEAU = 1.4, 0.7, 0.0, 3.4
HOP = 0.44  # one classic 60 px hop (kept under the 0.45 m walk step)
HUB = 7.0                       # T17 + T18, the arrival island
T15 = T16 = HUB + HOP           # 7.44
T13 = T14 = HUB + 2 * HOP       # 7.88
T11 = T10 = T9 = HUB + 3 * HOP  # 8.32
T8 = HUB + 4 * HOP              # 8.76
T7 = HUB + 6 * HOP              # 9.64
T5 = T6 = HUB + 8 * HOP         # 10.52
T4 = HUB + 9 * HOP              # 10.96
T2 = T3 = HUB + 10 * HOP        # 11.40
T1 = HUB + 12 * HOP             # 12.28
T0 = HUB + 13 * HOP             # 12.72 summit
T19 = T20 = HUB - HOP           # 6.56
T21 = HUB - 3 * HOP             # 5.68
T22 = HUB - 4 * HOP             # 5.24
DOOR_ROOF = HUB + 2.4
LILY = 1.5  # the classic lilies of the valley tower over the player


# ---------------------------------------------------------------- local assets

def _seg(mb, a, b, r, mat, r2=None, verts=6):
    """Cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = d.to_track_quat("Z", "Y").to_euler()
    mb.cyl(r, d.length, loc=a, rot=tuple(math.degrees(v) for v in rot), mat=mat, verts=verts, r2=r2)


@asset("X1000006_Lily_Of_The_Valley", "Foliage", footprint=1.4, tags=("flower",))
def _lily(coll):
    """Big lily-of-the-valley (classic midForest/9): two broad upright leaf blades and one tall stem that arches
    over at the top, hung with a vertical row of small white bells on the camera side."""
    mb = MeshBuilder()
    for sx, lean, h in ((-0.16, -10, 1.05), (0.17, 12, 0.85)):  # two upright blades, slightly apart
        mb.sphere(0.5, loc=(sx, 0.06, h * 0.5), scale=(0.34, 0.14, h), rot=(0, lean, 0), mat="M_Leaf", subdiv=2)
    bells = MeshBuilder()
    p0 = Vector((0.0, -0.06, 0.0))
    p1 = Vector((0.02, -0.1, 1.75))
    p2 = Vector((0.42, -0.16, 1.35))
    prev = p0
    n = 18
    for i in range(1, n + 1):
        t = i / n
        q = p0 * (1 - t) ** 2 + p1 * 2 * t * (1 - t) + p2 * t * t
        _seg(mb, prev - (q - prev) * 0.15, q, 0.03, "M_Flat_grass_side", verts=8)
        if i >= 8 and i % 2 == 0 and i < n:  # 5 bells in a row down the arching stem, on short pedicels
            bells.cyl(0.012, 0.09, loc=(q.x, q.y - 0.05, q.z - 0.09), mat="M_Flat_grass_side", verts=5)
            bells.dome(0.085, 0.11, loc=(q.x, q.y - 0.06, q.z - 0.06), rot=(180, 0, 0), mat="M_Flat_flower_white",
                       u=12, v=4, lip=0.025, underside=True)
        prev = q
    for dz, dx in ((0.07, 0.0), (0.24, -0.05)):  # the last bells hang off the drooping tip
        bells.dome(0.075, 0.1, loc=(p2.x + dx, p2.y - 0.04, p2.z - dz), rot=(180, 0, 0), mat="M_Flat_flower_white",
                   u=12, v=4, lip=0.02, underside=True)
    mb.build("X1000006_Lily_Of_The_Valley", coll, smooth=True, sharp_angle=60)
    bells.build("X1000006_Lily_Of_The_Valley_Flowers", coll, smooth=True, sharp_angle=60)


@asset("X1000006_Daffodils", "Foliage", footprint=1.4, tags=("flower",))
def _daffodils(coll):
    """Clump of tall yellow daffodils among long blades (classic midForest/10)."""
    r = core.rng("x1000006_daff", 2)
    mb = MeshBuilder()
    for k in range(12):
        a = 2 * math.pi * k / 12 + r.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0)) * 0.05
        base = d * r.uniform(0.05, 0.35)
        tip = base + d * r.uniform(0.15, 0.3) + Vector((0, 0, r.uniform(0.8, 1.15)))
        mb.tri(base + side, base - side, tip, "M_Flat_grass_side")
    fl = MeshBuilder()
    for k in range(6):
        a = 2 * math.pi * k / 6 + r.uniform(-0.3, 0.3)
        rr = r.uniform(0.1, 0.4)
        x, y = math.cos(a) * rr, math.sin(a) * rr
        h = r.uniform(0.85, 1.15)
        mb.cyl(0.025, h, loc=(x, y, 0), mat="M_Flat_grass_side", verts=5)
        ax = Vector((0.0, -math.sin(math.radians(50)), math.cos(math.radians(50))))  # the head faces the camera
        u = Vector((1.0, 0.0, 0.0))
        v = ax.cross(u)
        c = Vector((x, y - 0.02, h))
        for j in range(6):
            b = 2 * math.pi * j / 6
            pp = c + (u * math.cos(b) + v * math.sin(b)) * 0.12
            fl.sphere(0.1, loc=tuple(pp), scale=(1, 1, 0.32), rot=(50, 0, 0), mat="M_Flat_flower_yellow", subdiv=1)
        fl.cyl(0.075, 0.16, loc=tuple(c), rot=(50, 0, 0), mat="M_Flat_leaf_yellow_dk", verts=10, r2=0.1)
    mb.build("X1000006_Daffodils", coll, smooth=False, recalc_normals=False)
    fl.build("X1000006_Daffodils_Flowers", coll, smooth=True)


@asset("X1000006_Umbrella_Leaf", "Foliage", footprint=2.4, tags=("bush", "landmark"))
def _umbrella_leaf(coll):
    """Giant umbrella-leaf plant: round lily-pad leaves on tall stalks (classic midForest/8, island T4)."""
    mb = MeshBuilder()
    for (lx, ly, h, rr) in ((0.0, 0.0, 2.3, 0.95), (-0.85, 0.15, 1.45, 0.7), (0.8, -0.1, 1.0, 0.62)):
        _seg(mb, (0.0, 0.0, 0.0), (lx * 0.85, ly, h), 0.07, "M_Flat_leaf", r2=0.05)
        mb.dome(rr, rr * 0.22, loc=(lx, ly, h), mat="M_Leaf", u=18, v=3, profile=1.2, underside=True)
        for j in range(5):  # radial veins
            b = 2 * math.pi * j / 5
            mb.box((rr * 0.9, 0.03, 0.03), loc=(lx + math.cos(b) * rr * 0.45, ly + math.sin(b) * rr * 0.45,
                                               h + rr * 0.2), rot=(0, 0, math.degrees(b)), mat="M_Flat_leaf_dk")
    mb.build("X1000006_Umbrella_Leaf", coll, smooth=True, sharp_angle=50)


@asset("X1000006_Olive_Bush", "Foliage", footprint=1.6, tags=("bush",))
def _olive_bush(coll):
    """Olive-green round bush (classic darkWood/nature/9)."""
    bush(coll, "X1000006_Olive_Bush", 71, 0.75, 4, mat="M_Grad_mountain_dk__mountain_lt")


@asset("X1000006_Leaf_Litter", "Foliage", footprint=1.0, tags=("grass",))
def _leaf_litter(coll):
    """A drift of fallen orange, gold and rust leaves (the autumn floor of the dell)."""
    r = core.rng("x1000006_litter", 4)
    mb = MeshBuilder()
    mats = ("M_Flat_leaf_autumn", "M_Flat_leaf_yellow", "M_Flat_leaf_autumn_dk", "M_Flat_leaf_yellow_dk")
    for k in range(22):
        a = r.uniform(0, 2 * math.pi)
        rr = r.uniform(0.0, 1.0)
        mb.sphere(0.17, loc=(math.cos(a) * rr, math.sin(a) * rr, 0.02), scale=(1.0, 0.6, 0.12),
                  rot=(0, 0, r.uniform(0, 180)), mat=mats[k % 4], subdiv=1)
    mb.build("X1000006_Leaf_Litter", coll, smooth=True, sharp_angle=60)


@asset("X1000006_Hanging_Roots", "Foliage", footprint=0.5, tags=("vine",))
def _hanging_roots(coll):
    """A tuft of thin roots dangling from an island's underside (origin = top)."""
    r = core.rng("x1000006_roots", 6)
    mb = MeshBuilder()
    for k in range(7):
        x = r.uniform(-0.45, 0.45)
        y = r.uniform(-0.15, 0.15)
        ln = r.uniform(1.0, 2.1)
        mid = (x + r.uniform(-0.2, 0.2), y, -ln * 0.5)
        _seg(mb, (x, y, 0.1), mid, r.uniform(0.07, 0.09), "M_Bark", r2=0.05, verts=6)
        _seg(mb, mid, (mid[0] + r.uniform(-0.2, 0.2), y, -ln), 0.05, "M_Bark", r2=0.012, verts=6)
    mb.build("X1000006_Hanging_Roots", coll, smooth=True, sharp_angle=60)


@asset("X1000006_Gate_Posts", "Architecture", footprint=0.6, tags=("fence",))
def _gate_posts(coll):
    """The open gate of the high meadow: two tall white stake posts with ball tops under a crossbar
    (posts at x = +-1.6; the opening between them faces -y/+y)."""
    mb = MeshBuilder()
    for sx in (-1.6, 1.6):
        mb.box((0.22, 0.22, 2.2), loc=(sx, 0, 1.1), mat="M_Flat_cloth_white", bevel=0.03)
        mb.sphere(0.16, loc=(sx, 0, 2.28), mat="M_Flat_cloth_white", subdiv=1)
    mb.box((3.6, 0.12, 0.2), loc=(0, 0, 2.05), mat="M_Flat_cloth_white", bevel=0.02)
    mb.box((1.2, 0.08, 0.32), loc=(0, -0.06, 2.35), mat="M_Flat_leaf_yellow", bevel=0.03)
    mb.build("X1000006_Gate_Posts", coll, smooth=False)


def _autumn_grass():
    """Golden-olive grass for the dell floor (the islands keep the fresh kit grass)."""
    name = "M_X1000006_GrassAutumn"
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    b = M._MatBuilder(name)
    nz = b.noise(scale=0.08, detail=2.0, roughness=0.5, coord_kind="Object")
    patches = b.ramp(nz, [(0.40, M.col("#A39A36")), (0.62, M.col("#C2B04C"))])
    small = b.noise(scale=0.7, detail=1.0, coord_kind="Object")
    spots = M._bw(b, b.ramp(small, [(0.66, (0, 0, 0, 1)), (0.86, (0.5, 0.5, 0.5, 1))]))
    top = b.mix(patches, M.col("#C47A2C"), spots)
    side_fac = b.ramp(b.normal_z(), [(0.55, (1, 1, 1, 1)), (0.85, (0, 0, 0, 1))])
    return b.finish(b.mix(top, M.col("#7D7A2E"), M._bw(b, side_fac)))


def _autumn_dell(m):
    """Swap the grass of every dell piece (terraces, slopes, blend ribbons) for the golden autumn grass."""
    gold = _autumn_grass()
    for ob in m.col_terrain.objects:
        if "Dell_" not in ob.name or ob.type != "MESH" or ob.data is None:
            continue
        mats = ob.data.materials
        for i, mt in enumerate(mats):
            if mt is not None and mt.name == "M_Grass":
                mats[i] = gold


# ---------------------------------------------------------------- helpers

def _centroid(poly):
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    return sum(xs) / len(xs), sum(ys) / len(ys)


def _island(m, name, outline, top, cap=1.4, tiers=((0.8, 0.9), (1.8, 0.8), (2.7, 0.7)), stalk=0.22,
            ground=-0.5, **cap_kw):
    """A sky island: walkable grass cap, a root-ball of non-walkable dirt tiers that taper toward an earthen stalk.

    tiers: (inset, height) per dirt tier, top to bottom; a tier too big for the outline is skipped. Each tier is
    the outline shrunk about its bbox centre (no miter spikes on deep insets).
    """
    m.terrace(name, outline, top=top, bottom=top - cap, **cap_kw)
    x0, y0, x1, y1 = geo.poly_bbox(outline)
    bx, by = (x0 + x1) / 2, (y0 + y1) / 2
    z = top - cap + 0.1
    for i, (inset, h) in enumerate(tiers):
        if min(x1 - x0, y1 - y0) < 2 * inset + 1.2:
            break
        sx = (x1 - x0 - 2 * inset) / (x1 - x0)
        sy = (y1 - y0 - 2 * inset) / (y1 - y0)
        inner = [(bx + (x - bx) * sx, by + (y - by) * sy) for x, y in outline]
        m.terrace(f"{name}_Ball{i}", inner, top=z, bottom=z - h, style="dirt", fringe=False, walkable=False)
        z -= h - 0.1
    cx, cy = _centroid(outline)
    rx = max(0.75, (x1 - x0) * stalk / 2)
    ry = max(0.75, (y1 - y0) * stalk / 2)
    m.terrace(name + "_Stalk", geo.ellipse(cx, cy, rx, ry, 14), top=z + 0.05, bottom=ground,
              style="dirt", fringe=False, walkable=False)
    _ISLANDS.append((name, outline, top, cap))


_ISLANDS = []


def _hang_under_islands(m):
    """Roots and leafy vines dangling from the camera side (-y) and the flanks of every island cap."""
    k = 0
    for name, outline, top, cap in _ISLANDS:
        x0, y0, x1, y1 = geo.poly_bbox(outline)
        cx, cy = _centroid(outline)
        w = x1 - x0
        n = max(1, min(4, int(w / 2.2)))
        starts = [(x0 + w * (i + 0.5) / n, cy, 0.0, -1.0) for i in range(n)]
        if w > 3.5:
            starts += [(cx, cy, -1.0, 0.0), (cx, cy, 1.0, 0.0)]
        for sx, sy, dx, dy in starts:
            fp = m.face_point(sx, sy, dx, dy, drop=1.0)
            if fp is None:
                continue
            ex, ey, zt, zb = fp
            if abs(zt - top) > 0.3 or (zb is not None and zt - zb < 3.0):
                continue  # not this island's own lip, or too little air beneath
            hx, hy = ex - dx * 0.35, ey - dy * 0.35
            if k % 3 == 2:
                m.place("Vine_Hanging_A", hx, hy, z=top - cap * 0.75, rot=k * 37 % 40 - 20,
                        scale=(1.0, 1.0, 0.8 + (k % 2) * 0.3), name=f"{name}_UnderVine")
            else:
                m.place("X1000006_Hanging_Roots", hx, hy, z=top - cap + 0.1, rot=k * 53 % 360,
                        scale=(1.0, 1.0, 0.9 + (k % 3) * 0.25), name=f"{name}_Roots")
            k += 1


def _tongue(m, name, poly, top):
    """Narrow grass land bridge between two islands (the classic hop / 12 px gap)."""
    m.terrace(name, poly, top=top, bottom=top - 0.9)


def _strip(p0, p1, width):
    """Rectangle of the given width along the segment p0 -> p1."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln * width / 2, dx / ln * width / 2
    return [(p0[0] + nx, p0[1] + ny), (p0[0] - nx, p0[1] - ny), (p1[0] - nx, p1[1] - ny), (p1[0] + nx, p1[1] + ny)]


def _rope(m, name, x, y, z0, z1):
    return m.ladder(name, x, y, z0, z1, facing=90, kind="rope")


def _dell_rope(m, name, x, y, z1, z_from=3.6):
    """Long ground rope from the dell up to an island (its foot found by raycast below the island caps)."""
    z0 = m.ground_z(x, y, z_from=z_from)
    if z0 is None:
        raise ValueError(f"[{name}] no dell ground under the rope foot at ({x}, {y})")
    return _rope(m, name, x, y, z0, z1)


def _rope_ladder(m, name, x, y, z0, z1):
    """Rope ladder (classic connect/ladder/0): wooden rungs on rope rails."""
    obj = m.ladder(name, x, y, z0, z1, facing=90, kind="ladder")
    obj.data = obj.data.copy()  # never recolour a shared ladder mesh
    mats = obj.data.materials
    for i, mt in enumerate(mats):
        if mt is not None and mt.name == "M_Wood":
            mats[i] = M.get("M_Rope")
    return obj


def build(m):
    L, D = m.size  # 42 x 40
    soft = dict(top_mat=None)
    _ISLANDS.clear()

    # ================= the dell: V profile across x, full depth =================
    m.terrace("Dell_T23a_WestPlateau", [(-0.8, -0.8), (5.0, -1.0), (10.6, -0.8), (10.8, 14.0), (10.6, 26.0),
                                        (10.6, 40.8), (-0.8, 40.8)], top=W_PLATEAU, bottom=-0.5)
    m.terrace("Dell_T23c_MidShelf", [(12.0, -0.8), (18.8, -0.8), (18.8, 40.8), (12.0, 40.8)], top=MID_SHELF,
              bottom=-0.5)
    m.terrace("Dell_T23g_EastPlateau", [(32.0, -0.8), (42.8, -0.8), (42.8, 40.8), (32.0, 40.8)], top=E_PLATEAU,
              bottom=-0.5)
    # T23e valley floor between the two slopes' flat feet (5 cm proud of the plinth, so it can carry the autumn grass)
    m.terrace("Dell_T23e_Floor", [(20.9, -0.8), (25.3, -0.8), (25.3, 40.8), (20.9, 40.8)], top=FLOOR + 0.05,
              bottom=-0.5, fringe=False)
    m.ramp("Dell_T23b_Slope", (10.1, 20.0, W_PLATEAU), (12.6, 20.0, MID_SHELF), 41.6, bottom=-0.5, **soft)
    m.ramp("Dell_T23d_Slope", (18.3, 20.0, MID_SHELF), (20.6, 20.0, FLOOR), 41.6, bottom=-0.5, **soft)
    m.ramp("Dell_T23f_LongSlope", (25.6, 20.0, FLOOR), (32.5, 20.0, E_PLATEAU), 41.6, bottom=-0.5, **soft)

    # ================= the hub islet (T17 + T18) with the door block =================
    # the front lip sits just behind the footprint edge (cap lip ~0.28 m + a low wobble): the world's 8 m plank
    # bridge from the in05 causeway ends at local y 0 and tucks under it, with open air and the dell beneath
    hub = [(7.8, 0.4), (10.5, 0.15), (13.0, 0.12), (15.5, 0.12), (19.0, 0.2), (22.8, 0.4), (24.3, 1.8), (24.4, 5.4),
           (23.2, 7.8), (19.0, 8.4), (13.0, 8.4), (8.6, 8.2), (7.4, 5.0), (7.2, 2.0)]
    _island(m, "Hub_T17", hub, HUB, cap=2.0, tiers=((1.2, 0.9), (2.2, 0.9), (3.4, 0.9), (4.4, 0.8)), stalk=0.24,
            wobble_amt=0.1)
    m.terrace("DoorBlock_T12", [(12.0, 2.6), (15.0, 2.4), (18.4, 2.7), (18.4, 6.8), (12.0, 6.8)], top=DOOR_ROOF,
              bottom=HUB - 0.4)
    # the barrel door bulges from the block face east of the out00 swirl, so the camera sees both
    m.place("Barrel_Door_Mound", 16.4, 2.9, rot=0, scale=0.7, z=HUB - 0.04)

    # ================= west: lower island T21, the stair T15 -> T13 -> T11 -> T8, T10 + T9 =================
    small = dict(cap=1.1, tiers=((0.55, 1.1),), stalk=0.45)
    _island(m, "T21", [(-0.8, 7.6), (1.6, 7.1), (4.2, 7.4), (6.8, 7.6), (7.0, 9.8), (6.4, 11.8), (3.0, 12.0),
                       (-0.8, 11.6)], T21)
    for nm, (x, y), r, top in (("T15", (9.6, 9.3), 1.55, T15), ("T13", (7.6, 11.3), 1.75, T13),
                               ("T11", (8.7, 13.6), 1.55, T11), ("T8", (10.2, 15.9), 1.55, T8)):
        _island(m, nm, geo.ellipse(x, y, r, r * 0.97, 18), top, **small)
    _island(m, "T10", geo.ellipse(6.5, 15.0, 1.45, 1.4, 16), T10, **small)
    _island(m, "T9", [(-0.8, 12.8), (2.0, 12.3), (4.6, 12.6), (5.6, 13.6), (5.6, 16.6), (4.8, 18.6), (2.5, 18.9),
                      (-0.8, 18.4)], T9)

    # ================= upper west + crown: T6, T5, T0 summit, T1, T4 (umbrella leaf), T2, T22 =================
    _island(m, "T6", [(7.4, 18.6), (8.8, 17.7), (11.4, 17.7), (12.4, 18.6), (12.6, 21.0), (12.2, 23.2),
                      (9.6, 23.6), (7.4, 23.0)], T6)
    _island(m, "T5", [(-0.8, 19.0), (2.6, 18.7), (5.0, 19.0), (5.8, 20.6), (5.8, 25.0), (5.6, 29.4), (3.0, 29.6),
                      (-0.8, 29.4)], T5)
    _island(m, "T0_Summit", [(2.4, 29.4), (3.8, 28.8), (6.0, 28.7), (9.6, 29.0), (12.0, 29.4), (12.2, 32.6),
                             (11.8, 36.0), (8.0, 36.4), (2.6, 35.8)], T0)
    _island(m, "T1", [(14.2, 29.4), (15.0, 29.0), (16.4, 29.0), (17.6, 29.4), (17.8, 32.0), (17.4, 34.2),
                      (14.2, 34.0)], T1)
    _island(m, "T4", [(14.2, 23.8), (15.6, 23.0), (18.6, 22.8), (20.2, 22.9), (20.4, 26.0), (20.0, 28.6),
                      (17.6, 29.4), (14.2, 29.4)], T4)
    _island(m, "T2", [(22.0, 24.6), (23.4, 23.9), (25.0, 24.2), (25.2, 26.6), (24.8, 28.8), (22.0, 28.9)], T2)
    _island(m, "T22", geo.ellipse(19.4, 21.2, 1.7, 1.5, 16), T22, **small)
    # land bridges (classic hops / 12 px gaps): each starts on the lower island and ends 0.3+ m inside the next
    _tongue(m, "Tongue_T5_T6", _strip((5.2, 22.0), (7.9, 22.0), 1.2), T5)
    _tongue(m, "Tongue_T6_T4", _strip((12.0, 21.0), (14.75, 24.2), 1.2), T6)
    _tongue(m, "Tongue_T4_T2", _strip((19.8, 25.6), (22.4, 25.6), 1.2), T4)
    _tongue(m, "Tongue_T2_T3", _strip((24.7, 25.0), (27.0, 25.0), 1.2), T2)
    _tongue(m, "Tongue_T1_T0", _strip((14.6, 31.4), (11.7, 31.4), 1.2), T1)

    # ================= east: T3 (daffodils), the rope descent T7 -> T14 -> T16, lower T19/T20 =================
    _island(m, "T3", [(26.6, 19.0), (28.4, 18.5), (31.0, 18.7), (33.0, 19.2), (33.0, 22.6), (32.6, 26.4),
                      (28.6, 26.8), (26.6, 26.2)], T3)
    _island(m, "T7", [(27.0, 14.9), (28.0, 14.6), (29.0, 14.6), (30.0, 14.9), (30.2, 17.0), (30.0, 18.9),
                      (27.0, 18.9)], T7, tiers=((0.7, 1.0),))
    _island(m, "T14", [(24.6, 9.6), (26.6, 9.9), (29.0, 10.0), (31.0, 10.4), (31.2, 12.6), (31.0, 14.6),
                       (24.6, 14.6)], T14)
    _island(m, "T16", geo.ellipse(22.4, 9.2, 1.6, 1.5, 18), T16, **small)
    _tongue(m, "Tongue_T16_T14", _strip((22.6, 10.0), (25.0, 10.0), 1.2), T16)
    _island(m, "T19", [(23.6, 3.6), (25.6, 3.2), (27.8, 3.4), (27.9, 5.6), (27.6, 7.4), (23.6, 7.2)], T19)
    _island(m, "T20", [(27.2, 3.5), (29.6, 3.1), (32.2, 3.4), (32.4, 5.6), (32.0, 7.4), (27.2, 7.4)], T20)

    # ================= ropes (hemp, wooden pegs) and the rope ladder (all self-checked) =================
    _dell_rope(m, "Rope_597_Dell_T21", 2.6, 6.85, T21)     # west grove -> T21
    _rope(m, "Rope_272_T21_T13", 6.4, 9.6, T21, T13)       # T21 -> the stair
    _rope(m, "Rope_200_T8_T6", 10.2, 17.3, T8, T6)
    _rope(m, "Rope_696_T9_T5", 2.6, 18.35, T9, T5)
    _rope(m, "Rope_407_T5_T0", 5.0, 28.4, T5, T0)
    _rope_ladder(m, "RopeLadder_29_T4_T1", 15.4, 28.65, T4, T1)
    _rope(m, "Rope_627_T7_T3", 28.4, 18.2, T7, T3)
    _rope(m, "Rope_714_T14_T7", 28.4, 14.3, T14, T7)
    _dell_rope(m, "Rope_643_Dell_T20", 30.4, 2.75, T20)    # long slope -> T20
    _dell_rope(m, "Rope_167_Dell_T22", 19.4, 19.3, T22)    # centre dip -> T22
    _rope(m, "Rope_T22_T4", 19.4, 22.5, T22, T4)

    # ================= dressing =================
    # --- west grove: the orange twin birches and white stake fences of the west plateau
    m.place("Tree_Birch_Orange", 0.6, 3.2, rot=20, scale=0.95)
    m.place("Tree_Birch_Orange", 4.8, 3.6, rot=160, scale=0.8)
    m.fence([(-0.6, 5.9), (1.0, 6.0)], asset_name="Fence_Picket_Seg")   # a gap in the fence at the rope foot
    m.fence([(4.2, 6.1), (6.2, 5.9)], asset_name="Fence_Picket_Seg")
    m.fence([(6.0, 1.0), (6.5, 4.6)], asset_name="Fence_Wood_Seg")
    m.place("Bush_C", 4.6, 0.0, rot=10)
    m.place("X1000006_Olive_Bush", 5.0, 6.0, rot=40, scale=0.8)
    # --- centre dip (behind the hub's sight line): lilies on the mid shelf, the yellow twin tree, a fence
    for i, (x, y, s) in enumerate([(13.6, 18.0, 1.0), (16.0, 18.4, 1.15), (15.2, 21.2, 0.9), (17.0, 19.8, 0.8)]):
        m.place("X1000006_Lily_Of_The_Valley", x, y, rot=i * 65 - 20, scale=s * LILY)
    m.place("Tree_Birch_Yellow", 21.0, 15.0, rot=40, scale=0.8)
    m.place("Tree_Birch_Yellow", 22.4, 16.8, rot=200, scale=0.62)
    m.fence([(19.8, 16.8), (21.4, 16.4)], asset_name="Fence_Picket_Seg")
    m.fence([(21.8, 20.6), (23.2, 19.8)], asset_name="Fence_Picket_Seg")
    m.place("X1000006_Olive_Bush", 24.4, 17.6, rot=10, scale=0.8)
    # --- the long slope and the high east plateau: one stake fence along the crest, the yellow twin beside it
    # the fenced high meadow: the crest fence + a second fence line across the plateau, with an open gate where
    # the dell path passes; the yellow twin tree stands big inside the paddock
    m.fence([(33.6, 4.0), (33.8, 10.0), (34.0, 16.0), (34.2, 21.0), (34.4, 22.0)], asset_name="Fence_Wood_Seg")
    m.fence([(34.4, 22.0), (36.3, 22.0)], asset_name="Fence_Picket_Seg")
    m.fence([(39.7, 22.0), (41.7, 22.0)], asset_name="Fence_Picket_Seg")
    m.place("X1000006_Gate_Posts", 38.0, 22.0, rot=0)
    m.place("Tree_Birch_Yellow", 35.6, 9.0, rot=10, scale=1.25)
    m.place("Tree_Birch_Yellow", 35.5, 11.9, rot=130, scale=1.1)
    for i, (x, y) in enumerate([(35.4, 0.3), (41.0, 3.2), (35.4, 13.0), (40.8, 19.0), (35.6, 17.0), (39.4, 28.4)]):
        m.place(["Bush_B", "X1000006_Olive_Bush", "Bush_C"][i % 3], x, y, rot=i * 50)
    m.place("X1000006_Lily_Of_The_Valley", 36.6, 20.6, rot=-30, scale=0.9 * LILY)
    m.place("Tree_Birch_Orange", 41.2, 24.0, rot=70, scale=0.85)
    m.place("Bush_B", 39.4, 25.6, rot=20)
    m.place("X1000006_Olive_Bush", 40.4, 30.4, rot=80)
    m.place("Flower_Patch_B", 36.6, 32.8, rot=0)
    m.place("Flower_Patch_B", 39.6, 21.6, rot=60)
    # --- back of the dell: autumn trees framing the crown
    for i, (a, x, y, s) in enumerate([("Tree_Birch_Orange", 2.6, 39.4, 0.95), ("Tree_Birch_Yellow", 8.8, 39.4, 0.9),
                                      ("Tree_Autumn_A", 15.4, 39.6, 0.8), ("Tree_Birch_Orange", 22.0, 37.2, 0.9),
                                      ("Tree_Birch_Yellow", 28.6, 33.8, 0.95), ("Tree_Birch_Orange", 35.2, 32.8, 0.9),
                                      ("Tree_Birch_Yellow", 40.2, 35.6, 1.0), ("Tree_Autumn_A", 35.2, 38.8, 0.85)]):
        m.place(a, x, y, rot=i * 53, scale=s)
    for i, (x, y) in enumerate([(21.6, 33.4), (26.0, 33.0), (11.0, 40.2), (31.6, 36.8)]):
        m.place(["X1000006_Olive_Bush", "Bush_C"][i % 2], x, y, rot=i * 40)

    # --- the hub: a small autumn twin tree + stake fence on the front-west corner (the west stair stays open)
    m.place("Tree_Birch_Orange", 8.3, 1.8, rot=60, scale=0.6)
    m.place("Tree_Birch_Orange", 9.5, 1.0, rot=210, scale=0.5)
    m.fence([(7.9, 3.0), (8.1, 4.9)], asset_name="Fence_Wood_Seg")
    m.place("Bush_C", 18.8, 8.0, rot=20)
    m.place("X1000006_Olive_Bush", 22.6, 6.0, rot=70, scale=0.8)
    m.place("Bush_C", 22.8, 1.0, rot=0, scale=0.8)
    m.place("Bush_A", 14.6, 5.0, rot=30, scale=0.8)  # on the door-block roof
    m.place("Butterfly", 21.4, 2.6, rot=40)
    # --- island flowers: lilies (T21, T9, T5, T14), daffodils (T0, T3), the umbrella leaf on T4
    m.place("X1000006_Lily_Of_The_Valley", 1.2, 10.0, rot=10, scale=LILY)
    m.place("Bush_C", 5.0, 11.4, rot=0)
    m.place("X1000006_Lily_Of_The_Valley", 0.8, 14.8, rot=-20, scale=LILY)
    m.place("X1000006_Lily_Of_The_Valley", 4.4, 17.6, rot=40, scale=0.85 * LILY)
    m.place("X1000006_Lily_Of_The_Valley", 1.6, 24.4, rot=20, scale=1.1 * LILY)
    m.place("Bush_B", 1.0, 27.8, rot=30, scale=0.8)
    m.place("X1000006_Lily_Of_The_Valley", 30.2, 12.2, rot=-40, scale=LILY)
    m.place("Bush_C", 25.6, 13.6, rot=20)
    m.place("Bush_A", 9.6, 23.0, rot=60, scale=0.85)
    for i, (x, y) in enumerate([(4.6, 31.8), (8.0, 34.0), (10.4, 33.4), (5.8, 34.8)]):
        m.place("X1000006_Daffodils", x, y, rot=i * 70, scale=1.35)
    m.place("Bush_B", 10.8, 35.0, rot=0, scale=0.75)
    for i, (x, y) in enumerate([(30.4, 21.6), (32.0, 24.4), (29.2, 25.6)]):
        m.place("X1000006_Daffodils", x, y, rot=i * 80, scale=1.35)
    m.place("Bush_A", 23.6, 27.8, rot=20, scale=0.8)
    m.place("X1000006_Umbrella_Leaf", 18.6, 27.6, rot=-10, scale=1.6)  # island centrepiece, clear of the walk lines
    m.place("X1000006_Olive_Bush", 17.2, 29.0, rot=50, scale=0.85)
    m.place("Bush_C", 30.6, 6.2, rot=0, scale=0.8)
    m.place("Bush_C", 16.4, 33.2, rot=0, scale=0.7)

    m.scatter(["Grass_Tuft_A", "Flower_Patch_A"], geo.rect(33.5, 0, 42, 40), 12, seed=31, min_dist=2.0,
              z_band=(E_PLATEAU - 0.2, E_PLATEAU + 0.2), avoid=[geo.rect(35, 0, 42, 22), geo.rect(33, 3.5, 35, 21.5)])
    m.scatter(["Grass_Tuft_A"], geo.rect(0, 0, 42, 40), 22, seed=32, min_dist=2.0, z_band=(-0.2, E_PLATEAU + 0.2),
              avoid=[geo.rect(33, 3.5, 35, 21.5)])
    m.scatter(["X1000006_Leaf_Litter"], geo.rect(0, 0, 42, 40), 52, seed=33, min_dist=1.8,
              z_band=(-0.2, E_PLATEAU + 0.2),
              scale=(1.2, 1.7), avoid=[geo.rect(33, 3.5, 35, 22.5)])
    # --- the dell's V profile made legible: a worn path in the west grove to the foot of Rope_597, and one from
    # the valley floor in front of the islands up the long slope (T23f) and along the high meadow to its gate;
    # a row of rocks marks the slope's crest. (Under the islands no ribbon can be draped: it would land on the
    # island caps, so the two pockets are painted apart.)
    m.path("DellPath_West", [(0.9, 0.5), (2.4, 1.2), (2.9, 3.2), (2.6, 5.6)], width=1.8, end_taper=0.35)
    m.path("DellPath_East", [(25.6, 1.0), (27.6, 1.1), (30.4, 1.4), (33.2, 2.4), (35.8, 3.0), (37.4, 5.2),
                             (38.0, 9.0), (38.0, 15.0), (38.0, 23.2)], width=2.0, end_taper=0.35)
    for i, (x, y) in enumerate([(33.1, 4.8), (33.0, 8.2), (32.9, 12.0), (33.2, 27.6), (33.4, 33.0), (33.2, 36.4),
                                (33.0, 39.4)]):
        m.place(["Rock_A", "Rock_C", "Rock_B"][i % 3], x, y, rot=i * 47, scale=0.7 + (i % 2) * 0.15)
    _hang_under_islands(m)
    _autumn_dell(m)

    # ================= gameplay =================
    m.edge_portal("out00")
    # dell (Orange Mushrooms on the west plateau, the dip and the east plateau)
    m.mobs("Snail", geo.rect(0, 0, 6.5, 6.5), 1, seed=1, z_band=(1.2, 1.6))
    m.mobs("Orange Mushroom", geo.rect(0, 0, 6.5, 6.5), 1, seed=2, z_band=(1.2, 1.6))
    dip_clear = [(13.6, 18.0, 1.2), (16.0, 18.4, 1.3), (15.2, 21.2, 1.2), (17.0, 19.8, 1.1), (19.4, 19.3, 0.8),
                 (20.4, 17.2, 1.0), (21.0, 16.6, 2.8)]
    m.mobs("Blue Snail", geo.rect(14.5, 17, 18.2, 22), 1, seed=3, z_band=(-0.2, 0.9),
           avoid=dip_clear + [(13.3, 19.8, 1.4)])
    m.mobs("Orange Mushroom", geo.rect(13, 17, 22, 21.5), 1, seed=4, z_band=(-0.2, 0.9), avoid=dip_clear)
    m.mobs("Blue Snail", geo.rect(35, 0, 42, 18), 1, seed=5, z_band=(E_PLATEAU - 0.2, E_PLATEAU + 0.2),
           avoid=[(36.2, 8.6, 1.6), (35.8, 10.6, 1.4), (35.4, 13.0, 1.1), (35.6, 17.0, 1.1), (35.6, 1.0, 1.1),
                  (36.6, 20.6, 1.0)])
    m.mobs("Snail", geo.rect(25, 0, 32, 2.6), 1, seed=6, z_band=(0.0, E_PLATEAU), avoid=[(30.4, 2.3, 1.2)])
    m.mobs("Orange Mushroom", geo.rect(34, 26, 42, 40), 1, seed=7, z_band=(E_PLATEAU - 0.2, E_PLATEAU + 0.2),
           avoid=[(38.2, 26.4, 1.2), (40.4, 30.4, 1.2), (36.6, 32.8, 1.0), (39.4, 28.4, 1.1)])
    # islands (the hub and the stair islets stay mob-free)
    m.mobs("Blue Snail", geo.rect(0, 8, 6.5, 11.5), 1, seed=8, z_band=(T21 - 0.2, T21 + 0.2))
    m.mobs("Snail", geo.rect(24.6, 10.5, 31, 14.5), 1, seed=9, z_band=(T14 - 0.2, T14 + 0.2))
    m.mobs("Red Snail", geo.rect(0, 13, 5.5, 18.5), 1, seed=10, z_band=(T9 - 0.2, T9 + 0.2))
    m.mobs("Shroom", geo.rect(0, 20, 5.5, 27.5), 1, seed=11, z_band=(T5 - 0.2, T5 + 0.2))
    m.mobs("Orange Mushroom", geo.rect(14.5, 23.5, 20.2, 29), 1, seed=12, z_band=(T4 - 0.2, T4 + 0.2),
           avoid=[(18.6, 27.6, 2.4), (17.2, 29.0, 1.0), (15.4, 28.65, 1.0)])
    m.mobs("Blue Snail", geo.rect(27, 19.5, 32.6, 26), 1, seed=13, z_band=(T3 - 0.2, T3 + 0.2),
           avoid=[(30.4, 21.6, 1.1), (32.0, 24.4, 1.1), (29.2, 25.6, 1.1)])
    t0_clear = [(4.6, 31.8, 1.1), (8.0, 34.0, 1.1), (10.4, 33.4, 1.1), (5.8, 34.8, 1.1), (10.8, 35.0, 1.0)]
    m.mobs("Shroom", geo.rect(3, 30, 11.5, 35.5), 1, seed=14, z_band=(T0 - 0.2, T0 + 0.2), avoid=t0_clear)
    m.mobs("Orange Mushroom", geo.rect(3, 30, 11.5, 35.5), 1, seed=15, z_band=(T0 - 0.2, T0 + 0.2),
           avoid=t0_clear)

    m.player(21.0, 6.0, rot=-45)  # on the hub, clear of the door block (screen right of it), facing the camera

    # --- islands: every route walks its ropes (the validator links routes that climb the same rope)
    # hub -> T18 -> T19 -> T20 and down the long Rope_643 to the long slope of the dell
    m.route("HubEast", [(14.0, 1.0), (19.0, 1.4), (22.6, 4.4), (25.6, 5.4), (30.4, 4.4), (30.4, 2.3)])
    m.route("HubToT14", [(14.0, 1.0), (18.4, 1.4), (20.0, 1.8), (20.4, 7.0), (22.0, 7.9), (22.4, 9.6), (23.4, 10.0),
                         (25.4, 10.0), (27.2, 12.4), (28.4, 13.7)])
    # the west stair T15 -> T13 -> T11 -> T8, then up Rope_200 onto T6
    m.route("WestStair", [(14.0, 1.0), (11.0, 1.6), (10.6, 7.2), (9.6, 9.3), (7.6, 11.3), (8.7, 13.6),
                          (10.2, 15.9), (10.2, 16.7), (10.2, 18.5)])
    # T11 -> T10 -> T9, up Rope_696 onto T5 (meets UpperWest)
    m.route("StairToT9", [(8.7, 13.6), (6.5, 15.0), (3.0, 15.6), (2.6, 17.75), (2.6, 19.8), (4.0, 22.6)])
    # T21, and up Rope_272 onto the stair island T13
    m.route("T21", [(2.6, 8.0), (4.4, 9.6), (6.4, 9.0), (7.6, 11.3)])
    # T6 -> T5 and up Rope_407 to the summit T0
    m.route("UpperWest", [(10.2, 18.5), (8.6, 21.0), (7.6, 22.0), (5.4, 22.0), (4.0, 22.6), (5.0, 27.8), (5.0, 29.6)])
    # along T4's front edge, so the umbrella leaf stands clear as the island centrepiece
    m.route("UpperRing", [(10.2, 18.5), (11.6, 20.6), (12.2, 21.2), (14.6, 24.0), (17.5, 24.2), (19.6, 24.8),
                          (20.6, 25.6), (22.6, 25.6), (24.4, 25.0), (27.2, 25.0), (28.0, 22.0), (28.4, 19.4)])
    # T4 -> the rope ladder -> T1 (meets the summit route)
    m.route("RopeLadderFoot", [(17.5, 24.2), (15.4, 27.6), (15.4, 30.0)])
    m.route("Summit", [(5.0, 29.6), (9.0, 31.4), (12.0, 31.4), (14.6, 31.4), (15.4, 30.0)])
    # T14 -> Rope_714 -> T7 -> Rope_627 -> T3 (the east rope descent)
    m.route("T7", [(28.4, 13.7), (28.4, 15.4), (28.4, 18.0), (28.4, 19.4)])
    # centre dip -> Rope_167 -> T22 -> Rope_T22_T4 -> T4
    m.route("T22", [(19.4, 18.7), (19.4, 20.2), (19.4, 22.0), (19.5, 24.6)])
    # --- dell pockets: the west grove (up Rope_597 to T21), the east plateau + back of the dell, the centre dip
    m.route("WestGrove", [(0.8, 0.6), (2.6, 1.0), (2.8, 3.2), (2.6, 6.4), (2.6, 8.0)])
    m.route("EastAndBackDell", [(25.0, 0.6), (30.4, 2.3), (36.0, 2.0), (38.0, 10.0), (38.0, 22.0), (36.0, 29.6),
                                (26.0, 30.6), (19.4, 31.6), (16.0, 37.2), (4.0, 37.4)])
    m.route("CentreDell", [(14.6, 17.0), (17.0, 16.4), (18.6, 19.2), (19.4, 18.7), (22.4, 19.0)])
