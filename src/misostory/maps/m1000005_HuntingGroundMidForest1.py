"""Hunting Ground Middle of the Forest I (1000005) - "the spiral of stones round the rock, under the giant tree".

Classic (GMS v8) structure, from docs/research/maps/1000005_HuntingGroundMidForest1_1000005.md:
  an undulating forest floor (west hollow T36, central mound T34 with the exit door in
  an earth block T29, east hollow T37 with the rainbow fountain, a two-step east rise
  T35/T33 with a log pile); the signature zig-zag JUMP TOWER of tiny grass stones
  (T27 -> T8, 11 hops of 60 px) climbing straight up from the door block; a west stack
  of stones + rope to T22; an east branch T24 -> ladder -> T19 -> T16 (log piles) ->
  rope -> T8; an upper ring T8 -> ladder -> T6 -> ladder -> T4 -> rope -> summit T0,
  then a stair of stones T1 -> T2 -> T3 -> T5 down the west and ropes T5 -> T7 -> T10.
  Snails, Blue Snails, Red Snails and Shrooms (Shrooms only low).

3D translation: the 2D "up" becomes up AND back, and the jump tower becomes a real
tower: the 11 hops wind clockwise round a mossy rock spire (radius 2.5 m) as mossy
stone brackets, 30 deg and one hop (0.42 m) apart, with slivers of air between them.
The rope from the door-block roof reaches the tower base stone T27; T25 hands over to
the west shelf T22, the side stone T26 to the east ledge T24, and the top bracket T9
steps onto T8. East of the tower the "middle of the forest" stands: a giant dark-bark
tree rising from the forest floor, its crown above the summit. T8 is a branch-shaped
shelf that leaves the tower top and wraps round the back of the trunk; the east branch
(T24 -> ladder -> T19 -> root bridge -> T16 -> rope -> T8) steps up in front of it with
the ground showing between the shelves. T10 (west, behind the tower) is reached from the
west ropes and rejoins the tower by a drop, as in the classic. The upper ring (T6, T4,
summit T0) and the stair of stones (T1 -> T2 -> T3 -> T5) run along the back rim. The
palette is fresh green and teal with clover, marigolds, irises and strawberries.

Routes are declared per tier/pocket (ladders and ropes connect them); every climbable is
self-checked at build time.
"""

import math

import bpy
from mathutils import Vector

from misostory import core, geo
from misostory import materials as M
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.nature import puffy_canopy

MAP_ID = 1000005
GAMEPLAY_FOCUS = (14.0, 13.0)
GAMEPLAY_SCALE = 32.0

# ---------------------------------------------------------------- heights
MOUND = 0.9      # T34 / T35
EAST = 1.8       # T33
ROOF = 3.3       # T29 door block
HOP = 0.42       # one classic 60 px hop
T27 = 4.5        # jump-tower base
T8 = T27 + 11 * HOP          # 9.12  top of the tower / the branch shelf round the giant tree
T22 = T24 = T27 + 2 * HOP    # 5.34
T19 = T27 + 5 * HOP          # 6.60
T16 = T27 + 6 * HOP          # 7.02
T10 = T27 + 9 * HOP          # 8.28
T7 = T8 + 2 * HOP            # 9.96
T6 = T8 + 4 * HOP            # 10.80
T5 = T8 + 6 * HOP            # 11.64
T3 = T4 = T8 + 7 * HOP       # 12.06
T2 = T8 + 8 * HOP            # 12.48
T1 = T8 + 9 * HOP            # 12.90
T0 = T8 + 10 * HOP           # 13.32  summit
STACK = (1.3, 1.72, 2.14)    # west stack T32, T30, T28

# ---------------------------------------------------------------- the spiral tower
SPIRE = (9.2, 15.6)   # centre of the rock spire
SPIRE_R = 2.5
RING_R = 4.0          # bracket centres
SPIRE_TOP = 9.6
# ring brackets, clockwise from the front, 30 deg and one hop apart: (classic id, angle deg, top)
RING = [("T25", -90, T27 + HOP), ("T23", -120, T27 + 2 * HOP), ("T21", -150, T27 + 3 * HOP),
        ("T20", 180, T27 + 4 * HOP), ("T18", 150, T27 + 5 * HOP), ("T15", 120, T27 + 6 * HOP),
        ("T13", 90, T27 + 7 * HOP), ("T12", 60, T27 + 8 * HOP), ("T11", 30, T27 + 9 * HOP),
        ("T9", 0, T27 + 10 * HOP)]
BRACKET_RADIAL, BRACKET_TANGENT = 1.35, 0.9
T27_XY = (11.31, 11.07)   # tower base stone (free-standing, in the open sector of the spiral)
T26_XY = (13.6, 11.4)     # side stone toward the east ledge T24
GIANT = (21.5, 24.0)      # the giant tree of the middle of the forest


def _ring_xy(ang):
    a = math.radians(ang)
    return SPIRE[0] + RING_R * math.cos(a), SPIRE[1] + RING_R * math.sin(a)


# ---------------------------------------------------------------- local materials + assets

def _mats():
    if bpy.data.materials.get("M_X1000005_BarkDark") is None:
        M.mat_wood("M_X1000005_BarkDark", "#5A3B26", "#352217", "#77502F", 2.0, axis="Z")
    if bpy.data.materials.get("M_X1000005_Fungus") is None:
        M.mat_gradient("M_X1000005_Fungus", "#B4652A", "#F2C27A", 0.0, 1.0, noise_amt=0.12)


def _spire_rock():
    """Blue-grey rock strata for the spire and its stones (darker than the pale kit rock, so it reads as stone)."""
    name = "M_X1000005_SpireRock"
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    return M.mat_cliff(name, "#7C8290", "#4E5462", "#A2A8B4", band_scale=0.5)


def _moss_cap():
    """Deep mossy green for the tower stones and the spire top (reads apart from the shelves' fresh grass)."""
    name = "M_X1000005_Moss"
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    b = M._MatBuilder(name)
    nz = b.noise(scale=0.25, detail=2.0, roughness=0.6, coord_kind="Object")
    patches = b.ramp(nz, [(0.38, M.col("#3E8A3A")), (0.66, M.col("#69A845"))])
    side_fac = b.ramp(b.normal_z(), [(0.55, (1, 1, 1, 1)), (0.85, (0, 0, 0, 1))])
    return b.finish(b.mix(patches, M.col("#2F6B2F"), M._bw(b, side_fac)))


@asset("X1000005_Rainbow_Fountain", "Props", footprint=4.5, tags=("prop", "landmark"))
def _rainbow_fountain(coll):
    """Rainbow Street fountain: a ring of stones, an orange-mushroom spout and a rainbow arc (faces -Y)."""
    mb = MeshBuilder()
    for k in range(13):
        a = 2 * math.pi * k / 13
        mb.sphere(0.42, loc=(math.cos(a) * 1.6, math.sin(a) * 1.6, 0.2), scale=(1.2, 1.0, 0.75), mat="M_Rock",
                  subdiv=1, lumpy=0.25, seed=k, flatten_bottom=0.5)
    mb.cyl(1.55, 0.32, loc=(0, 0, -0.05), mat="M_Water", verts=24)
    mb.cyl(0.2, 0.95, loc=(0, 0, 0.2), mat="M_MushStem", verts=10, r2=0.16)
    mb.dome(0.58, 0.44, loc=(0, 0, 1.1), mat="M_Spot_mush_orange__mush_spot", u=18, v=5, lip=0.08, profile=0.8)
    for k in range(6):  # water drops falling from the cap rim
        a = 2 * math.pi * k / 6 + 0.3
        mb.sphere(0.07, loc=(math.cos(a) * 0.62, math.sin(a) * 0.62, 0.75), scale=(1, 1, 1.8), mat="M_Water",
                  subdiv=1)
    bands = ["M_Flat_flower_red", "M_Flat_roof_orange", "M_Flat_flower_yellow", "M_Flat_leaf_lt",
             "M_Flat_flower_blue", "M_Flat_flower_purple"]
    for i, mat in enumerate(bands):  # lower half sinks into the ground
        mb.torus(2.3 - i * 0.13, 0.072, loc=(0, 0.35, 0.15), rot=(90, 0, 0), mat=mat, u=40, v=6)
    mb.build("X1000005_Rainbow_Fountain", coll, smooth=True, sharp_angle=50)


@asset("X1000005_Log_Pile", "Props", footprint=2.2, tags=("prop",))
def _log_pile(coll):
    """Stacked logs with tiny mushrooms and a ladybug (classic grassySoil artificiality/6+7)."""
    mb = MeshBuilder()
    for (y, z) in ((-0.37, 0.36), (0.37, 0.36), (0.0, 0.96)):
        mb.cyl(0.36, 2.0, loc=(-1.0, y, z), rot=(0, 90, 0), mat="M_Bark", verts=12, r2=0.34)
        mb.cyl(0.3, 0.04, loc=(1.0, y, z), rot=(0, 90, 0), mat="M_Flat_wood_lt", verts=12)
    for x, c in ((-0.55, "M_Spot_mush_yellow__mush_spot"), (-0.32, "M_Spot_mush_blue__mush_spot"),
                 (0.15, "M_Spot_mush_yellow__mush_spot")):
        mb.cyl(0.045, 0.16, loc=(x, 0.06, 1.28), mat="M_MushStem", verts=6)
        mb.dome(0.12, 0.09, loc=(x, 0.06, 1.43), mat=c, u=10, v=3)
    mb.sphere(0.09, loc=(0.55, -0.18, 1.33), scale=(1.0, 1.25, 0.6), mat="M_Flat_flower_red", subdiv=1)
    mb.sphere(0.05, loc=(0.55, -0.3, 1.32), mat="M_Eye_Black", subdiv=1)
    mb.build("X1000005_Log_Pile", coll, smooth=True, sharp_angle=45)


@asset("X1000005_Tree_Mixed", "Trees", footprint=3.0, tags=("tree",))
def _tree_mixed(coll):
    """White-trunk tree whose crown mixes green, teal and an orange clump (classic T33 tree)."""
    name = "X1000005_Tree_Mixed"
    r = core.rng(name, 5)
    trunk = MeshBuilder()
    x = y = z = 0.0
    for i in range(4):
        h = 1.2
        trunk.cyl(0.32 - i * 0.04, h + 0.04, loc=(x, y, z), mat="M_Flat_cloth_white", verts=9, r2=0.28 - i * 0.04)
        trunk.box((0.22, 0.05, 0.06), loc=(x + 0.05, y - 0.29 + i * 0.03, z + h * 0.5), mat="M_Flat_hair_black")
        x += r.uniform(-0.15, 0.15)
        y += r.uniform(-0.1, 0.1)
        z += h
    trunk.cyl(0.46, 0.35, loc=(0, 0, -0.05), mat="M_Flat_cloth_white", verts=9, r2=0.3)
    trunk.build(name + "_Trunk", coll, smooth=True, sharp_angle=60)
    can = MeshBuilder()
    puffy_canopy(can, r, 51, (x, y, z), 2.0, lobes=4, mat="M_Leaf_B", squash=0.9)
    puffy_canopy(can, r, 52, (x - 1.5, y + 0.3, z - 0.6), 1.3, lobes=3, mat="M_Leaf", squash=0.9)
    puffy_canopy(can, r, 53, (x + 1.5, y - 0.2, z - 0.4), 1.15, lobes=3, mat="M_Leaf_Autumn", squash=0.9)
    can.build(name + "_Canopy", coll, smooth=True, sharp_angle=80)


def _seg(mb, a, b, r, mat, r2=None, verts=8):
    """Tapered cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = d.to_track_quat("Z", "Y").to_euler()
    mb.cyl(r, d.length, loc=a, rot=tuple(math.degrees(v) for v in rot), mat=mat, verts=verts, r2=r2)


@asset("X1000005_Giant_Tree", "Trees", footprint=5.0, tags=("tree", "landmark"))
def _giant_tree(coll):
    """The giant tree of the middle of the forest: a dark-bark trunk tapering from r 2.0 at the forest floor to r 1.4
    under the crown, a root flare ~1.5 m round, three thick limbs that carry the branch shelves of this map (under
    T19, under T16 out of T8's face, and along T8's east lip) and a broad crown widened toward the camera and the
    sides (not back, so the summit row stays visible). Origin = trunk base; place it with rot=0 (the limbs aim at
    the shelves in map coordinates)."""
    _mats()
    bark = "M_X1000005_BarkDark"
    r = core.rng("x1000005_giant", 9)
    tr = MeshBuilder()
    rings = [(0.0, 2.0), (2.5, 1.92), (5.0, 1.83), (7.5, 1.72), (10.0, 1.58), (12.4, 1.4), (14.6, 1.15)]
    for (z0, r0), (z1, r1) in zip(rings, rings[1:]):
        tr.cyl(r0, z1 - z0 + 0.06, loc=(0, 0, z0), mat=bark, verts=18, r2=r1)
    for k in range(9):  # bark ridges, following the taper
        a = 2 * math.pi * k / 9 + r.uniform(-0.15, 0.15)
        _seg(tr, (math.cos(a) * 1.86, math.sin(a) * 1.86, 0.3), (math.cos(a) * 1.3, math.sin(a) * 1.3, 13.4), 0.3,
             bark, r2=0.16, verts=6)
    tr.cyl(3.5, 1.3, loc=(0, 0, -0.1), mat=bark, verts=18, r2=2.0)  # root flare skirt
    for k in range(8):  # buttress roots spreading ~1.5 m onto the floor
        a = 2 * math.pi * k / 8 + r.uniform(-0.2, 0.2)
        _seg(tr, (math.cos(a) * 1.5, math.sin(a) * 1.5, 2.4), (math.cos(a) * 3.8, math.sin(a) * 3.8, 0.0), 0.62,
             bark, r2=0.22)
    # thick limbs carrying the shelves (tree at (21.5, 24)): under T19, under T16 (out of T8's front face),
    # and one along the front lip of T8's east arm
    for p0, p1, r0, r1 in (((0.6, -1.5, 4.5), (1.6, -7.5, 5.15), 0.78, 0.4),
                           ((1.2, -1.2, 5.4), (8.0, -8.3, 6.0), 0.82, 0.42),
                           ((8.0, -8.3, 6.0), (9.5, -11.1, 5.45), 0.42, 0.26),  # its tip shows under T16's front lip
                           ((1.3, -1.1, 7.4), (2.6, -4.85, 8.2), 0.6, 0.46),
                           ((2.6, -4.85, 8.2), (6.4, -4.95, 8.32), 0.46, 0.24)):
        _seg(tr, p0, p1, r0, bark, r2=r1, verts=10)
        tr.sphere(r1 * 1.05, loc=p1, mat=bark, subdiv=1)
    for side in (-1, 1):  # two limbs reaching into the crown
        tr.cyl(0.75, 4.6, loc=(side * 0.5, -0.3, 12.0), rot=(-12, side * 52, 0), mat=bark, verts=10, r2=0.38)
    tr.cyl(0.6, 3.6, loc=(0.0, -0.6, 12.4), rot=(-48, 0, 0), mat=bark, verts=10, r2=0.32)
    tr.build("X1000005_Giant_Tree_Trunk", coll, smooth=True, sharp_angle=50)
    can = MeshBuilder()
    for seed, centre, rad, mat in ((91, (0.0, -0.9, 14.4), 3.3, "M_Leaf_B"), (92, (-5.3, -0.8, 14.2), 2.5, "M_Leaf"),
                                   (93, (5.3, -0.6, 14.3), 2.5, "M_Leaf_B"), (94, (0.4, -4.7, 13.8), 2.4, "M_Leaf"),
                                   (95, (-3.5, -3.7, 13.8), 2.0, "M_Leaf_B"), (96, (3.7, -3.5, 13.9), 2.0, "M_Leaf"),
                                   (97, (0.0, 1.7, 14.9), 2.2, "M_Leaf_B")):
        puffy_canopy(can, r, seed, centre, rad, lobes=5, mat=mat, squash=0.72)
    can.build("X1000005_Giant_Tree_Canopy", coll, smooth=True, sharp_angle=80)


@asset("X1000005_Shelf_Fungus", "Foliage", footprint=0.5, tags=("vine",))
def _shelf_fungus(coll):
    """Three stacked tan-orange bracket fungi growing out of a rock face toward -y (origin = wall contact)."""
    _mats()
    mb = MeshBuilder()
    for (x, z, rr) in ((0.0, 0.0, 0.42), (0.32, -0.32, 0.3), (-0.26, -0.5, 0.24)):
        mb.dome(rr, rr * 0.35, loc=(x, -rr * 0.45, z), scale=(1.0, 0.75, 1.0), mat="M_X1000005_Fungus", u=14, v=3)
    mb.build("X1000005_Shelf_Fungus", coll, smooth=True, sharp_angle=50)


@asset("X1000005_Fern", "Foliage", footprint=0.8, tags=("grass",))
def _fern(coll):
    """A fern of seven arching fronds (forest-floor undergrowth)."""
    r = core.rng("x1000005_fern", 3)
    mb = MeshBuilder()
    for k in range(7):
        a = 2 * math.pi * k / 7 + r.uniform(-0.2, 0.2)
        ln = r.uniform(0.55, 0.8)
        mb.sphere(ln, loc=(math.cos(a) * ln * 0.55, math.sin(a) * ln * 0.55, 0.32), scale=(1.0, 0.22, 0.12),
                  rot=(0, -38, math.degrees(a)), mat="M_Leaf_B" if k % 2 else "M_Leaf", subdiv=2)
    mb.build("X1000005_Fern", coll, smooth=True, sharp_angle=60)


# ---------------------------------------------------------------- helpers

_CLIMBS = []


def _climb(m, name, x, y, z0, z1, kind="ladder", facing=90):
    """Queue a ladder/rope; _flush_climbs builds it once all terrain exists."""
    _CLIMBS.append((name, x, y, z0, z1, kind, facing))


def _flush_climbs(m):
    """Build the queued climbables once all terrain exists (a kit rope finds the face and the lip to hang from)."""
    for name, x, y, z0, z1, kind, facing in _CLIMBS:
        m.ladder(name, x, y, z0, z1, facing=facing, kind=kind)
    _CLIMBS.clear()


def _cliff_stones(m, pts):
    for i, (x, y, z) in enumerate(pts):
        m.place("Rock_Cliff_Stone", x, y, z=z, rot=(i * 23) % 30 - 15, scale=0.85 + (i % 3) * 0.15)


def _strip(p0, p1, width):
    """Rectangle of the given width along the segment p0 -> p1."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln * width / 2, dx / ln * width / 2
    return [(p0[0] + nx, p0[1] + ny), (p0[0] - nx, p0[1] - ny), (p1[0] - nx, p1[1] - ny), (p1[0] + nx, p1[1] + ny)]


def _shelf_on_stalk(m, name, outline, top, cap=1.1, inset=0.8, ball_h=0.9, stalk=0.34):
    """A branch shelf: walkable grass cap, one non-walkable root-ball tier (the outline shrunk about its bbox centre)
    and a narrow earthen stalk down to the forest floor, so the ground shows under it."""
    m.terrace(name, outline, top=top, bottom=top - cap)
    x0, y0, x1, y1 = geo.poly_bbox(outline)
    bx, by = (x0 + x1) / 2, (y0 + y1) / 2
    sx = (x1 - x0 - 2 * inset) / (x1 - x0)
    sy = (y1 - y0 - 2 * inset) / (y1 - y0)
    z = top - cap + 0.1
    m.terrace(name + "_Ball", [(bx + (x - bx) * sx, by + (y - by) * sy) for x, y in outline], top=z, bottom=z - ball_h,
              style="dirt", fringe=False, walkable=False)
    cx = sum(p[0] for p in outline) / len(outline)
    cy = sum(p[1] for p in outline) / len(outline)
    m.terrace(name + "_Stalk", geo.ellipse(cx, cy, (x1 - x0) * stalk / 2, (y1 - y0) * stalk / 2, 14),
              top=z - ball_h + 0.05, bottom=-0.5, style="dirt", fringe=False, walkable=False)
    return cx, cy


def _wall_point(m, part, x, y, z, dx, dy, reach=4.0):
    """Local (x, y) where a horizontal ray from (x, y) - reach * (dx, dy) toward (dx, dy) at local height z first
    meets a terrain body whose name contains `part` (non-walkable root-balls and stalks), or None."""
    from mathutils.bvhtree import BVHTree
    vs, ps = [], []
    for ob in m.col_terrain.objects:
        if ob.type != "MESH" or part not in ob.name or ob.data is None:
            continue
        mw = ob.matrix_basis
        off = len(vs)
        vs.extend(mw @ v.co for v in ob.data.vertices)
        ps.extend([off + i for i in pl.vertices] for pl in ob.data.polygons)
    if not ps:
        return None
    tree = BVHTree.FromPolygons(vs, ps)
    o = m.w(x - dx * reach, y - dy * reach, z)
    d = m.w(x + dx, y + dy, z) - m.w(x, y, z)
    hit = tree.ray_cast(o, d.normalized(), reach * 2)
    if hit[0] is None:
        return None
    lx, ly, _lz = m._local(hit[0])
    return lx, ly


def _swap_grass(m, words, mat):
    for ob in m.col_terrain.objects:
        if ob.type != "MESH" or ob.data is None or not any(w in ob.name for w in words):
            continue
        mats = ob.data.materials
        for i, mt in enumerate(mats):
            if mt is not None and mt.name == "M_Grass":
                mats[i] = mat


def _spiral_tower(m):
    """The rock spire and the clockwise ring of mossy brackets (each attached to the spire, air beneath)."""
    sx, sy = SPIRE
    m.terrace("Tower_Spire", geo.ellipse(sx, sy, SPIRE_R, SPIRE_R * 0.97, 20), top=SPIRE_TOP, bottom=-0.3,
              style="grass_rock", walkable=False)
    for nm, ang, top in RING:
        cx, cy = _ring_xy(ang)
        m.terrace(f"Tower_{nm}", geo.ellipse(cx, cy, BRACKET_RADIAL, BRACKET_TANGENT, 16, rot=math.radians(ang)),
                  top=top, bottom=top - 0.75, style="grass_rock", fringe=False, stones=False)
    # the tower base T27 and the side stone T26 stand free in the open sector of the spiral
    m.terrace("Tower_T27", geo.ellipse(T27_XY[0], T27_XY[1], 1.3, 1.25, 16), top=T27, bottom=-0.3,
              style="grass_rock", stones=False)
    m.terrace("Tower_T26", geo.ellipse(T26_XY[0], T26_XY[1], 1.2, 1.15, 16), top=T27 + HOP, bottom=-0.3,
              style="grass_rock", stones=False)


def build(m):
    L, D = m.size  # 38 x 42
    _CLIMBS.clear()
    _mats()
    grass = dict(top_mat=None)

    # ================= forest floor (front band) =================
    # T34 central mound (+1 H) carrying the door block; T36 west / T37 east hollows are plinth level
    m.terrace("Mound_T34", [(3.4, -0.8), (10.0, -1.0), (16.6, -0.8), (17.3, 2.5), (17.0, 7.0), (16.6, 9.6),
                            (14.0, 10.8), (8.0, 11.2), (4.4, 10.4), (3.2, 6.5), (3.0, 3.0)], top=MOUND, bottom=-0.5)
    # T35 riser step and T33 east high corner (they stop short of the east branch columns)
    m.terrace("Rise_T35", [(25.4, -0.8), (32.0, -1.0), (38.8, -0.8), (38.8, 11.6), (30.0, 11.8), (25.8, 11.6),
                           (25.6, 9.0), (25.2, 6.0), (25.6, 3.0)], top=MOUND, bottom=-0.5)
    m.terrace("Corner_T33", [(28.4, -0.8), (33.0, -1.0), (38.8, -0.8), (38.8, 11.6), (33.0, 11.8), (28.8, 11.6),
                             (28.4, 10.4), (28.2, 8.0), (28.6, 5.0), (28.2, 2.0)], top=EAST, bottom=-0.5)
    m.ramp("Mound_To_T36", (3.8, 1.4, MOUND), (0.8, 1.4, 0.0), 2.8, **grass)
    # the floor path is painted only on flat ground; the dirt-topped ramps carry it over the steps
    m.ramp("Mound_To_T37", (16.8, 4.2, MOUND), (19.9, 4.2, 0.0), 3.0, **grass)
    m.ramp("T37_To_T35", (22.4, 5.4, 0.0), (25.9, 5.4, MOUND), 3.0, **grass)
    m.ramp("T35_To_T33", (26.0, 9.4, MOUND), (29.0, 9.4, EAST), 2.8, **grass)
    # one continuous floor trail from the door, draped over the three grassy ramps
    m.path("FloorPath", [(8.0, 0.4), (12.5, 1.6), (16.8, 4.2), (19.9, 4.2), (22.4, 5.4), (25.2, 5.6), (26.0, 7.0),
                         (26.0, 9.4), (29.0, 9.4), (37.5, 8.6)], width=2.6)

    # door block T29: an earth block on the mound, the barrel door set into its front face
    # (its face stands 2.4 m behind the out00 anchor, so the 1.5 m arrival and the press-Up trigger in front of the
    # door are clear: Iteration Two playtest finding arrival-1005-inside-mound)
    m.terrace("DoorBlock_T29", [(4.6, 3.5), (8.0, 3.4), (12.4, 3.6), (12.6, 9.4), (4.6, 9.4)], top=ROOF,
              bottom=0.4)
    # the barrel door sits east of the out00 swirl so the camera sees it beside the portal
    m.place("Barrel_Door_Mound", 10.4, 3.85, rot=0, scale=0.75, z=MOUND - 0.04)  # bulges from the block face
    # the ladder stands east of the door, 1.55 m outside out00's press-Up trigger (x 5.75-10.25) plus the 0.8 m grab
    # radius, so Up at the portal never grabs it (playtest finding ladder-portal-up-conflict-1005)
    _climb(m, "Ladder_T34_T29", 11.8, 3.3, MOUND, ROOF)
    _climb(m, "Rope_T29_T27", T27_XY[0], 9.5, ROOF, T27, kind="rope")

    # west stack (T32 -> T30 -> T28) and the rope up to T22
    for (nm, x, y), top in zip((("T32", 3.4, 4.6), ("T30", 2.2, 6.6), ("T28", 3.0, 8.6)), STACK):
        m.terrace(f"Stack_{nm}", geo.ellipse(x, y, 1.5, 1.4, 16), top=top, bottom=-0.3, style="grass_stone")
    _climb(m, "Rope_T28_T22", 3.0, 9.85, STACK[2], T22, kind="rope")

    # ================= the spiral jump tower =================
    _spiral_tower(m)

    # ================= low shelves: west T22, east ledge T24, the branch shelves T19 and T16 =================
    # T22: a front strip with a tongue to T23 (the classic hop to the tower) and a back part along the west rim
    m.terrace("Shelf_T22", [(-0.8, 10.1), (2.0, 9.9), (5.4, 10.2), (5.4, 11.6), (3.2, 11.8), (3.2, 16.4),
                            (1.6, 16.6), (-0.8, 16.4)], top=T22, bottom=-0.5)
    m.terrace("Tongue_T22_T23", _strip((5.0, 10.75), (7.0, 11.15), 1.3), top=T22, bottom=T22 - 0.8, fringe=False,
              stones=False)
    m.terrace("Ledge_T24", [(14.8, 10.2), (17.0, 9.9), (19.2, 10.4), (21.8, 11.4), (22.4, 13.2), (15.0, 13.3)],
              top=T24, bottom=-0.5)
    _climb(m, "Ladder_T24_T19", 21.6, 13.3, T24, T19)
    _shelf_on_stalk(m, "Branch_T19", [(20.4, 13.9), (23.0, 13.6), (26.0, 13.9), (26.2, 16.4), (25.8, 18.3),
                                      (20.6, 18.3)], T19)
    m.terrace("RootBridge_T19_T16", _strip((25.4, 16.0), (27.4, 16.0), 1.8), top=T19, bottom=T19 - 0.8,
              fringe=False, stones=False)
    # T16's back edge abuts T8's front face, where Rope_T16_T8 hangs (no gap to fall through at the rope foot)
    _shelf_on_stalk(m, "Branch_T16", [(26.8, 13.2), (29.5, 12.9), (32.0, 13.3), (32.2, 16.0), (31.8, 19.3),
                                      (29.0, 19.4), (26.8, 19.1)], T16)

    # ================= mid shelves: T10 + T7 (west), T8 round the giant tree, T6 + T4 (east) =================
    m.terrace("Shelf_T10", [(-0.8, 17.4), (2.0, 17.1), (4.4, 17.6), (4.7, 19.4), (5.6, 21.4), (8.0, 21.9),
                            (10.0, 21.8), (11.0, 22.6), (11.2, 31.0), (-0.8, 31.0)], top=T10, bottom=-0.5)
    m.terrace("Stone_T7", geo.ellipse(3.8, 28.6, 2.2, 1.9, 18), top=T7, bottom=T10 - 0.5, style="grass_stone")
    _climb(m, "Rope_T10_T7", 3.8, 26.25, T10, T7, kind="rope")
    # T8: a branch-shaped shelf from the tower top round the back of the giant trunk to the east branch; a bay
    # in front of the trunk lets the tree rise from the forest floor
    m.terrace("Branch_T8", [(14.2, 14.4), (16.0, 14.8), (17.6, 16.6), (18.6, 19.4), (18.9, 21.8), (19.0, 24.0),
                            (19.7, 25.8), (21.5, 26.6), (23.3, 25.8), (24.0, 24.0), (24.1, 21.8), (24.3, 19.6),
                            (26.5, 19.4), (29.0, 19.5), (31.2, 19.8), (31.4, 22.5), (31.0, 24.6), (27.0, 24.6),
                            (25.8, 27.0), (23.8, 29.4), (21.5, 29.8), (19.0, 29.4), (17.4, 27.6), (16.4, 24.8),
                            (15.6, 21.6), (14.8, 19.6), (14.4, 17.6), (14.0, 15.8)], top=T8, bottom=-0.5)
    _climb(m, "Rope_T16_T8", 29.0, 18.9, T16, T8, kind="rope")
    m.terrace("Canopy_T6", [(26.6, 25.6), (29.5, 25.2), (32.5, 25.6), (35.5, 25.2), (38.8, 25.5), (38.8, 37.0),
                            (26.0, 37.0)], top=T6, bottom=-0.5)
    _climb(m, "Ladder_T8_T6", 28.4, 24.9, T8, T6)
    m.terrace("Ledge_T4", [(30.4, 32.6), (33.4, 32.4), (36.4, 32.6), (36.4, 36.8), (30.4, 36.8)], top=T4,
              bottom=T6 - 0.5, style="grass_stone")
    _climb(m, "Ladder_T6_T4", 33.4, 32.0, T6, T4)

    # ================= top row along the back rim (T5 <- T3 <- T2 <- T1 <- T0 summit) =================
    m.terrace("Top_T5", [(-0.8, 30.6), (4.0, 30.2), (8.0, 30.5), (11.6, 30.8), (11.6, 41.8), (-0.8, 41.8)], top=T5,
              bottom=-0.5)
    _climb(m, "Rope_T7_T5", 3.6, 30.1, T7, T5, kind="rope")
    m.terrace("Top_T3", [(11.0, 34.4), (15.0, 34.1), (20.6, 34.5), (20.6, 41.8), (11.0, 41.8)], top=T3, bottom=-0.5)
    m.terrace("Top_T2", [(20.0, 35.2), (23.6, 35.0), (23.6, 41.8), (20.0, 41.8)], top=T2, bottom=-0.5,
              style="grass_stone")
    m.terrace("Top_T1", [(23.0, 36.0), (26.8, 35.8), (26.8, 41.8), (23.0, 41.8)], top=T1, bottom=-0.5,
              style="grass_stone")
    m.terrace("Summit_T0", [(26.2, 36.4), (30.0, 36.1), (34.0, 36.5), (38.8, 36.3), (38.8, 41.8), (26.2, 41.8)],
              top=T0, bottom=-0.5)
    _climb(m, "Rope_T4_T0", 33.4, 35.95, T4, T0, kind="rope")

    _flush_climbs(m)
    _swap_grass(m, ("Tower_",), _moss_cap())
    rock = _spire_rock()
    for ob in m.col_terrain.objects:
        if "Tower_" in ob.name and ob.type == "MESH" and ob.data is not None:
            mats = ob.data.materials
            for i, mt in enumerate(mats):
                if mt is not None and mt.name == "M_Rock_Cliff":
                    mats[i] = rock

    # ================= the giant tree of the middle of the forest =================
    m.place("X1000005_Giant_Tree", GIANT[0], GIANT[1], z=-0.15, rot=0)
    # undergrowth at its feet and in the hollow behind the shelves (ferns, logs, small mushrooms, bushes)
    for i, (x, y) in enumerate([(19.6, 20.2), (23.6, 20.4), (21.0, 19.9), (16.8, 30.6), (13.2, 32.0), (22.8, 31.4),
                                (26.4, 30.0), (12.6, 25.0)]):
        m.place("X1000005_Fern", x, y, rot=i * 47, scale=1.1 + (i % 3) * 0.2, required=False, z_from=7.0)
    for i, (x, y, a) in enumerate([(14.8, 33.0, "Log_A"), (19.6, 32.4, "Mushroom_Cluster_A"),
                                   (25.0, 32.6, "Bush_B"), (12.4, 28.6, "Bush_A"), (23.0, 20.6, "Mushroom_Blue_S"),
                                   (21.0, 33.2, "Mushroom_Yellow_S"), (17.6, 31.6, "Bush_C")]):
        m.place(a, x, y, rot=i * 61, required=False, z_from=7.0)

    # ================= dressing =================
    # --- floor: door hump shrubs, the rainbow fountain, log pile + mixed tree in the east corner
    for i, (x, y, s) in enumerate([(4.2, -0.5, 0.65), (13.8, -0.4, 0.6)]):  # clear of the out00 corridor
        m.place("Bush_C", x, y, rot=i * 70, scale=s)
    # the door-block roof (T29): a shrub and clover
    m.place("Bush_C", 5.6, 7.6, rot=30, scale=0.85)
    m.place("Clover_Patch", 7.6, 8.4, rot=10)
    m.place("Tree_Sapling_A", 0.2, -0.4, rot=20)
    m.place("Tree_Autumn_A", 14.8, 7.6, rot=30, scale=0.55)
    m.place("Bush_A", 15.6, 1.2, rot=10)
    m.place("X1000005_Rainbow_Fountain", 21.4, 8.8, rot=0)
    m.place("Bush_B", 24.6, 11.6, rot=80, scale=0.8)
    m.place("X1000005_Log_Pile", 34.6, 5.4, rot=12)
    m.place("X1000005_Tree_Mixed", 37.6, 10.8, rot=200)
    m.place("Bush_B", 31.6, 11.0, rot=0, scale=0.8)
    m.place("Bush_A", 37.8, 1.6, rot=50)
    m.place("Tree_Round_C", 38.2, 6.4, rot=0, scale=0.7)
    m.place("Butterfly", 22.6, 6.6, rot=40)

    # --- the tower: shelf fungus on the spire between the brackets, vines and stones in its face
    for i, ang in enumerate((-105, -135, -75, -165, -45)):
        a = math.radians(ang)
        top = T27 + HOP * (1 + (-90 - ang) / 30.0) if ang <= -90 else T27
        m.place("X1000005_Shelf_Fungus", SPIRE[0] + math.cos(a) * (SPIRE_R + 0.15),
                SPIRE[1] + math.sin(a) * (SPIRE_R + 0.15), z=max(1.6, top - 1.4), rot=ang + 90,
                scale=1.2 + (i % 2) * 0.3)
    for i, (ang, zt, sz) in enumerate(((-100, 9.5, 1.3), (-60, 9.4, 1.6), (-140, 9.4, 1.1), (-20, 9.5, 1.5))):
        a = math.radians(ang)
        m.place("Vine_Hanging_A", SPIRE[0] + math.cos(a) * (SPIRE_R + 0.2), SPIRE[1] + math.sin(a) * (SPIRE_R + 0.2),
                z=zt, rot=ang + 90, scale=(1.0, 1.0, sz))
    m.place("Bush_C", SPIRE[0] - 0.6, SPIRE[1] + 0.4, z=SPIRE_TOP - 0.1, rot=20, scale=1.1)
    m.place("Tree_Sapling_A", SPIRE[0] + 0.7, SPIRE[1] + 0.8, z=SPIRE_TOP - 0.1, rot=60, scale=0.9)

    # --- shelf fungus on the root-balls and stalks of the branch shelves (their camera-facing -y and -x sides)
    for i, (part, x, y, z, dx, dy, sc) in enumerate([("Branch_T16_Ball", 29.4, 15.7, 5.45, 0, 1, 1.3),
                                                     ("Branch_T16_Stalk", 29.1, 15.4, 3.4, 0, 1, 1.15),
                                                     ("Branch_T16_Stalk", 30.3, 15.4, 1.9, 0, 1, 1.0),
                                                     ("Branch_T16_Ball", 29.5, 15.7, 5.3, 1, 0, 1.1),
                                                     ("Branch_T19_Ball", 23.3, 15.9, 5.0, 1, 0, 1.25),
                                                     ("Branch_T19_Stalk", 23.7, 15.4, 3.2, 1, 0, 1.05),
                                                     ("Branch_T19_Ball", 22.6, 15.9, 5.1, 0, 1, 1.1)]):
        hit = _wall_point(m, part, x, y, z, dx, dy)
        if hit is not None:
            rot = 0.0 if dy else -90.0
            m.place("X1000005_Shelf_Fungus", hit[0] - dx * 0.04, hit[1] - dy * 0.04, z=z, rot=rot + (i * 17) % 20 - 10,
                    scale=sc, name="ShelfFungus_Branch")

    # --- T22 (young autumn tree), T24, T19 (log pile, irises), T16 (log pile, marigolds)
    m.place("Tree_Autumn_A", 0.9, 15.6, rot=60, scale=0.7)
    m.place("Bush_C", 0.6, 11.0, rot=20)
    m.place("X1000005_Log_Pile", 23.6, 17.4, rot=-8)
    m.place("Iris_Patch", 21.2, 17.2, rot=10)
    m.place("Butterfly_Pink", 23.0, 15.0, rot=10)
    m.place("X1000005_Log_Pile", 30.6, 14.8, rot=8)
    m.place("Marigold_Patch", 31.4, 17.4, rot=0)
    m.place("Butterfly_Yellow", 29.6, 14.4, rot=60)
    # --- the hollow east of the branches (ground between the shelves): trees and undergrowth
    m.place("Tree_Birch_Teal", 36.8, 18.4, rot=150, scale=0.9)
    m.place("Tree_Round_A", 35.6, 22.8, rot=100, scale=0.8)
    m.place("Tree_Round_C", 33.4, 15.0, rot=30, scale=0.8)
    for i, (x, y) in enumerate([(34.6, 19.6), (37.6, 14.0), (33.2, 23.6)]):
        m.place("X1000005_Fern", x, y, rot=i * 80, scale=1.3)
    m.place("Bush_A", 37.8, 24.0, rot=40, scale=0.9)
    m.place("Log_A", 36.0, 12.6, rot=20, scale=0.8)

    # --- T10 (teal tree), T8 round the trunk (bushes, clover), T6 (bushes, clover)
    m.place("Tree_Birch_Teal", 1.0, 24.0, rot=30, scale=0.9)
    m.place("Bush_A", 0.4, 28.0, rot=40, scale=0.9)
    m.place("Bush_C", 9.2, 29.0, rot=10)
    m.place("Tree_Round_B", 9.6, 25.2, rot=10, scale=0.7)
    m.place("Clover_Patch", 15.2, 15.6, rot=20)
    m.place("Clover_Patch", 30.2, 23.6, rot=60)
    m.place("Bush_C", 16.4, 25.6, rot=30, scale=0.9)
    m.place("Bush_A", 30.8, 22.6, rot=70, scale=0.8)
    m.place("Bush_C", 19.6, 29.2, rot=10, scale=0.8)
    m.place("Tree_Round_C", 25.2, 28.4, rot=40, scale=0.65)
    m.place("Bush_B", 27.4, 31.6, rot=0, scale=0.9)
    m.place("Bush_A", 37.6, 33.6, rot=90)
    m.place("Clover_Patch", 35.2, 29.8, rot=20)
    m.place("Tree_Round_A", 37.4, 27.6, rot=100, scale=0.7)
    m.place("Tree_Birch_Teal", 29.0, 30.8, rot=20, scale=0.85)
    m.place("Tree_Round_C", 35.6, 26.6, rot=80, scale=0.7)

    # --- top row: T5 (young tree), T3 (strawberries, irises), T0 summit (clover, marigolds, butterfly)
    m.place("Tree_Round_C", 2.0, 38.6, rot=10, scale=0.85)
    m.place("Tree_Birch_Teal", 1.8, 35.0, rot=40, scale=0.85)
    m.place("Tree_Round_B", 9.8, 39.8, rot=70, scale=0.7)
    m.place("Bush_A", 8.0, 33.0, rot=20)
    m.place("Bush_B", 12.4, 35.0, rot=0, scale=0.9)
    m.place("Strawberry_Bush", 16.2, 36.0, rot=10)
    m.place("Strawberry_Bush", 18.8, 35.6, rot=70)
    m.place("Iris_Patch", 14.6, 38.8, rot=20)
    m.place("Butterfly_Pink", 17.2, 36.6, rot=0)
    m.place("Clover_Patch", 28.6, 38.0, rot=0)
    m.place("Marigold_Patch", 31.0, 39.6, rot=40)
    m.place("Marigold_Patch", 35.6, 38.4, rot=0)
    m.place("Butterfly", 32.2, 38.2, rot=30)
    # a fresh-green back fringe
    for i, (a, x, y, s) in enumerate([("Tree_Round_A", 4.4, 41.0, 0.9), ("Tree_Round_B", 9.0, 41.2, 0.85),
                                      ("Tree_Round_B", 16.6, 41.2, 0.8), ("Tree_Birch_Teal", 24.6, 41.0, 0.9),
                                      ("Tree_Round_A", 29.6, 41.4, 0.85), ("Tree_Round_B", 37.2, 40.8, 0.9),
                                      ("Tree_Birch_Teal", 0.4, 34.6, 0.85)]):
        m.place(a, x, y, rot=i * 47, scale=s)

    _cliff_stones(m, [(1.6, 10.0, 3.0), (4.6, 10.0, 2.0),
                      (3.0, 17.0, 6.6), (8.0, 30.2, 10.2), (15.4, 34.0, 10.6), (35.0, 25.0, 9.2),
                      (17.0, 14.6, 6.8), (30.8, 19.7, 7.8)])

    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Grass_Tuft_A"], geo.rect(16, 0, 38, 12), 14, seed=21,
              min_dist=1.8, avoid=[(21.4, 8.8, 3.0), geo.rect(15, 3.0, 30, 6.8), geo.rect(25, 7.5, 38, 10.6)])
    m.scatter(["Grass_Tuft_A", "Clover_Patch"], geo.rect(12, 12, 38, 37), 18, seed=22, min_dist=2.2,
              avoid=[(29.0, 18.9, 1.5), (28.4, 24.9, 1.5), (33.4, 32.0, 1.5), (21.6, 13.3, 1.5)])

    # ================= gameplay =================
    m.edge_portal("out00")
    m.player(15.4, 3.9, rot=-50)  # on the mound beside the floor trail, the door, tower and branches behind
    m.player_spawn(4.0, 3.6, rot=180, note="sp x -214: west of out00, a little higher, on the forest floor")
    m.mobs("Shroom", geo.rect(0, 2, 3, 10), 1, seed=1, z_band=(-0.2, 0.3))
    m.mobs("Shroom", geo.rect(18, 1, 25, 12), 1, seed=2, z_band=(-0.2, 0.3), avoid=[(21.4, 8.8, 3.0)])
    m.mobs("Shroom", geo.rect(29, 1, 38, 11), 1, seed=3, z_band=(1.6, 2.0))
    m.mobs("Shroom", geo.rect(0, 12, 3.2, 16.4), 1, seed=4, z_band=(T22 - 0.2, T22 + 0.2))
    m.mobs("Snail", geo.rect(5, 3.5, 12, 8.6), 1, seed=13, z_band=(ROOF - 0.2, ROOF + 0.2),
           avoid=[(10.4, 3.85, 2.2), (11.8, 3.6, 1.2), (5.6, 7.6, 1.2), (7.6, 8.4, 1.0), (T27_XY[0], 9.5, 1.0)])
    m.mobs("Blue Snail", geo.rect(20.6, 14, 26, 18.2), 1, seed=5, z_band=(T19 - 0.2, T19 + 0.2))
    m.mobs("Red Snail", geo.rect(27, 13.4, 32, 18.4), 1, seed=6, z_band=(T16 - 0.2, T16 + 0.2))
    m.mobs("Snail", geo.rect(0, 19, 10, 26), 1, seed=7, z_band=(T10 - 0.2, T10 + 0.2))
    m.mobs("Snail", geo.rect(24.5, 19.6, 31, 24.4), 1, seed=8, z_band=(T8 - 0.2, T8 + 0.2))
    m.mobs("Snail", geo.rect(30, 26, 38, 32), 1, seed=9, z_band=(T6 - 0.2, T6 + 0.2))
    m.mobs("Red Snail", geo.rect(1, 32, 10, 40), 1, seed=10, z_band=(T5 - 0.2, T5 + 0.2))
    m.mobs("Snail", geo.rect(12, 36, 20, 40), 1, seed=11, z_band=(T3 - 0.2, T3 + 0.2))
    m.mobs("Blue Snail", geo.rect(28, 37, 37, 41), 1, seed=12, z_band=(T0 - 0.2, T0 + 0.2))

    # --- floor (the door, the hollows, the east rise), the west stack and the door-block roof
    m.route("Floor", [(6.0, 1.0), (8.0, 1.0), (12.5, 1.2), (16.8, 4.2), (19.9, 4.2), (22.4, 5.4), (25.9, 5.4),
                      (26.0, 7.6), (26.0, 9.4), (29.0, 9.4), (37.0, 8.6)])
    m.route("WestHollow", [(6.0, 1.0), (3.8, 1.4), (0.8, 1.4), (0.6, 3.4)])
    # up the west stack and Rope_T28_T22 onto the west shelf T22
    m.route("WestStack", [(3.8, 1.2), (3.4, 4.6), (2.2, 6.6), (3.0, 8.6), (3.0, 9.3), (3.0, 10.8)])
    # up Ladder_T34_T29 onto the door-block roof, across it and up Rope_T29_T27 to the tower base
    m.route("DoorRoof", [(11.8, 1.6), (11.8, 4.2), (10.0, 6.0), (T27_XY[0], 8.9), (T27_XY[0], 10.4)])
    # --- the spiral (T27 -> T25 ... T9 -> T8), its hand-overs to T22 and T24, and the drop from T10
    m.route("JumpTower", [(T27_XY[0], 10.4), T27_XY] + [_ring_xy(a) for _n, a, _t in RING] + [(15.2, 16.2)])
    m.route("TowerToT22", [_ring_xy(-120), (6.4, 11.0), (4.6, 10.85), (2.4, 11.4), (1.8, 13.4)])
    # the side stone to the east ledge T24, then up Ladder_T24_T19 onto the first branch shelf
    m.route("TowerToT24", [T27_XY, T26_XY, (16.4, 11.8), (21.6, 12.6), (21.6, 14.4)])
    # along T19, over the root bridge to T16 and up Rope_T16_T8 onto the branch round the giant tree
    m.route("EastBranch", [(21.6, 14.4), (23.0, 14.8), (25.0, 15.4), (27.6, 16.0), (29.0, 16.6), (29.0, 18.2),
                           (29.0, 20.0)])
    m.route("T10", [(3.8, 25.6), (2.2, 22.0), (1.8, 19.2)])
    m.route("T10DropToTower", [(1.8, 19.2), (3.6, 18.5), _ring_xy(150)], one_way=True)
    # --- T8 round the giant trunk, and the upper ring
    m.route("BranchT8", [(15.2, 16.2), (16.6, 19.6), (17.4, 23.4), (18.6, 26.8), (21.5, 28.2), (24.4, 26.8),
                         (25.8, 23.4), (27.4, 21.4), (29.0, 20.0)])
    m.route("T8ToT6Ladder", [(27.4, 21.4), (28.4, 24.2), (28.4, 25.8)])
    m.route("CanopyT6", [(28.4, 25.8), (33.4, 30.8), (37.0, 30.0)])
    # up Ladder_T6_T4 onto the stone ledge, then Rope_T4_T0 to the summit
    m.route("LedgeT4", [(33.4, 30.8), (33.4, 33.4), (33.4, 35.4), (33.4, 37.6)])
    m.route("SummitStair", [(33.4, 37.6), (30.0, 39.0), (24.9, 39.0), (21.8, 38.6), (16.0, 38.0), (8.0, 36.0),
                            (3.6, 31.4)])
    # the west ropes: T10 -> Rope_T10_T7 -> the stone T7 -> Rope_T7_T5 -> the top row
    m.route("StoneT7", [(3.8, 25.6), (3.8, 27.4), (3.6, 29.6), (3.6, 31.4)])
