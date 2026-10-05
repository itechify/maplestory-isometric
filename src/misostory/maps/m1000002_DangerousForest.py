"""Dangerous Forest (1000002) - "a dark forest ravine under a great earthen shelf".

Classic (GMS v8) structure, from docs/research/maps/1000002_DangerousForest_1000002.md:
  three-band sandwich. Forest floor G1 -> G2 -> G3 rising east in two 60 px steps;
  a thick middle shelf P01a/b/c (+11/+10/+9 H) that steps DOWN eastward (so the
  ravine is a wedge, deep in the west, shallow in the east); a crenellated top row of
  alternating ledges and pillars (P03, P06, P04, P07, P05, P02). Seven long green
  leafy vines are the only way up between bands. 12 Orange Mushrooms on the floor,
  Snails on the shelf. Nothing man-made anywhere.

3D translation: the floor is the front band (camera side), the Great Shelf is a
massive terrace across the middle depth whose soil face is the ravine's back wall,
and the battlement ridge crowns the back rim with rock pillars standing in the
crenels (low rock steps in the crenels stand in for the classic hops). The layout fixes the exit
(out01) at the front-left, so the classic "arrive on top" becomes a small entry
bluff with the purple irises, from which you drop into the ravine. Vines hang in a
curtain from the shelf lip; two more climb from the shelf to the battlements. An
east glade wraps round the shelf's end. Dark pines and tall trees give the forest
its gloom, with rust/yellow/teal birches from the classic objects.

Routes are declared per tier (floor, shelf, battlements); the vines connect them.
"""

import math

import bpy

from misostory import core, geo
from misostory import materials as M
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.nature import birch, bush, puffy_canopy

MAP_ID = 1000002
GAMEPLAY_FOCUS = (19.0, 13.0)
GAMEPLAY_SCALE = 32.0

# heights (local m above base)
BLUFF = 2.0
G1, G2, G3 = 0.0, 0.9, 1.8
P01A, P01B, P01C = 7.6, 6.8, 6.0
RIDGE, PILLAR, P02 = 12.0, 12.8, 11.2
STEP = 12.4  # rock steps in the crenels
SADDLE_Y = 29.8


# ---------------------------------------------------------------------------
# local assets
# ---------------------------------------------------------------------------

@asset("X1000002_Vine_Leaves", "Foliage", footprint=0.5, tags=("vine",))
def _vine_leaves(coll):
    """1 m segment of a leafy climbing vine (stack/scale along z; origin at the bottom)."""
    mb = MeshBuilder()
    mb.cyl(0.05, 1.0, mat="M_Flat_grass_dark", verts=6)
    for k in range(3):
        z = 0.16 + k * 0.33
        s = 1 if k % 2 else -1
        mb.sphere(0.15, loc=(s * 0.15, -0.06, z), scale=(1.4, 0.45, 0.75), rot=(0, s * 25, 0), mat="M_Leaf",
                  subdiv=1)
        mb.sphere(0.09, loc=(-s * 0.08, -0.09, z + 0.13), scale=(1.2, 0.5, 0.8), mat="M_Leaf_B", subdiv=1)
    mb.build("X1000002_Vine_Leaves", coll, smooth=True, sharp_angle=60)


@asset("X1000002_Stump_Roots", "Foliage", footprint=0.8, tags=("stump",))
def _stump_roots(coll):
    """Flaring roots for a giant tree-stump pillar of radius 1 (scale x/y to the pillar radii; origin = ground)."""
    r = core.rng("x1000002_roots", 3)
    mb = MeshBuilder()
    for k in range(8):
        a = 2 * math.pi * k / 8 + r.uniform(-0.2, 0.2)
        ln = r.uniform(0.75, 1.05)
        mb.cyl(r.uniform(0.2, 0.26), ln, loc=(math.cos(a) * 0.82, math.sin(a) * 0.82, 0.62),
               rot=(0, 118, math.degrees(a)), mat="M_Bark", verts=7, r2=0.07)
    mb.build("X1000002_Stump_Roots", coll, smooth=True, sharp_angle=50)


def _gloom_mats():
    """Local gloomy materials (created once per Blender session; M.get finds them in bpy.data by name)."""
    if bpy.data.materials.get("M_X1000002_LeafGloom") is None:
        M.mat_gradient("M_X1000002_LeafGloom", "#123528", "#2F6247", 0.1, 0.95, noise_amt=0.18, random_tint=0.3)
    if bpy.data.materials.get("M_X1000002_LeafMoss") is None:
        M.mat_gradient("M_X1000002_LeafMoss", "#173F2B", "#3A6E40", 0.1, 0.95, noise_amt=0.18, random_tint=0.3)
    if bpy.data.materials.get("M_X1000002_LeafDusk") is None:
        M.mat_gradient("M_X1000002_LeafDusk", "#0F3B39", "#2A6A5E", 0.1, 0.95, noise_amt=0.18, random_tint=0.3)
    if bpy.data.materials.get("M_X1000002_BushGloom") is None:
        M.mat_gradient("M_X1000002_BushGloom", "#163824", "#3C6D3C", 0.0, 1.0, noise_amt=0.15, random_tint=0.3)
    if bpy.data.materials.get("M_X1000002_LeafRust") is None:
        M.mat_gradient("M_X1000002_LeafRust", "#4E1C10", "#9A4024", 0.1, 0.95, noise_amt=0.18, random_tint=0.3)
    if bpy.data.materials.get("M_X1000002_LeafOchre") is None:
        M.mat_gradient("M_X1000002_LeafOchre", "#5A4510", "#A07E26", 0.1, 0.95, noise_amt=0.18, random_tint=0.3)
    if bpy.data.materials.get("M_X1000002_BarkDead") is None:
        M.mat_wood("M_X1000002_BarkDead", "#4A3B30", "#2A211B", "#66574A", 2.5, axis="Z")
    if bpy.data.materials.get("M_X1000002_Thorn") is None:
        M.mat_gradient("M_X1000002_Thorn", "#24182A", "#4D3A50", 0.0, 1.0, noise_amt=0.2, random_tint=0.3)
    if bpy.data.materials.get("M_X1000002_ToadCap") is None:
        M.mat_spotted("M_X1000002_ToadCap", "#6A3C8E", "#E6D9F2")
    if bpy.data.materials.get("M_X1000002_Bone") is None:
        M.mat_flat("M_X1000002_Bone", "#EDE3C8")


@asset("X1000002_Pine_Gloom", "Trees", footprint=2.2, tags=("tree",))
def _pine_gloom(coll):
    """Tall, narrow, almost black-green fir with a dark trunk (the gloom of the Dangerous Forest)."""
    _gloom_mats()
    trunk = MeshBuilder()
    trunk.cyl(0.3, 2.4, mat="M_X1000002_BarkDead", verts=8, r2=0.2)
    trunk.cyl(0.52, 0.4, loc=(0, 0, -0.05), mat="M_X1000002_BarkDead", verts=8, r2=0.3)
    trunk.build("X1000002_Pine_Gloom_Trunk", coll, smooth=True)
    can = MeshBuilder()
    z = 1.6
    for rad, h in ((1.9, 2.3), (1.6, 2.1), (1.25, 1.9), (0.9, 1.7), (0.55, 1.4)):
        can.cyl(rad, h, loc=(0, 0, z), mat="M_X1000002_LeafGloom", verts=9, r2=rad * 0.15)
        z += h * 0.55
    can.build("X1000002_Pine_Gloom_Canopy", coll, smooth=True, sharp_angle=50)


@asset("X1000002_Tall_Gloom", "Trees", footprint=3.0, tags=("tree",))
def _tall_gloom(coll):
    """Tall dark-barked forest tree with two tiers of deep moss-green canopy."""
    _gloom_mats()
    r = core.rng("x1000002_tall", 4)
    trunk = MeshBuilder()
    x = y = z = 0.0
    for i in range(5):
        h = 1.5
        trunk.cyl(0.5 * (1 - 0.15 * i), h + 0.05, loc=(x, y, z), mat="M_X1000002_BarkDead", verts=9,
                  r2=0.5 * (1 - 0.15 * (i + 1)))
        x += r.uniform(-0.2, 0.2)
        y += r.uniform(-0.2, 0.2)
        z += h
    trunk.cyl(0.7, 0.5, loc=(0, 0, -0.05), mat="M_X1000002_BarkDead", verts=9, r2=0.5)
    trunk.build("X1000002_Tall_Gloom_Trunk", coll, smooth=True, sharp_angle=60)
    can = MeshBuilder()
    puffy_canopy(can, r, 4, (x, y, z), 2.3, lobes=6, mat="M_X1000002_LeafMoss")
    puffy_canopy(can, r, 14, (x * 0.5, y * 0.5, z * 0.62), 1.9, lobes=5, mat="M_X1000002_LeafGloom", rise=0.2)
    can.build("X1000002_Tall_Gloom_Canopy", coll, smooth=True, sharp_angle=80)


@asset("X1000002_Birch_Dusk", "Trees", footprint=2.6, tags=("tree",))
def _birch_dusk(coll):
    """White-trunk birch with a deep teal crown (the classic midForest teal tree, in the forest's shade)."""
    _gloom_mats()
    birch(coll, "X1000002_Birch_Dusk", 43, 5.0, 2.3, "M_X1000002_LeafDusk")


def _gloom_bush(coll, name, seed, radius, lobes):
    _gloom_mats()
    bush(coll, name, seed, radius, lobes, mat="M_X1000002_BushGloom")


@asset("X1000002_Bush_A", "Foliage", footprint=1.4, tags=("bush",))
def _bush_a(coll):
    _gloom_bush(coll, "X1000002_Bush_A", 11, 0.8, 4)


@asset("X1000002_Bush_B", "Foliage", footprint=2.0, tags=("bush",))
def _bush_b(coll):
    _gloom_bush(coll, "X1000002_Bush_B", 12, 1.1, 5)


@asset("X1000002_Bush_C", "Foliage", footprint=0.9, tags=("bush",))
def _bush_c(coll):
    _gloom_bush(coll, "X1000002_Bush_C", 13, 0.55, 3)


@asset("X1000002_Birch_Rust", "Trees", footprint=2.6, tags=("tree", "autumn"))
def _birch_rust(coll):
    """White-trunk birch with a dark rust crown (the classic orange/rust trees, dimmed)."""
    _gloom_mats()
    birch(coll, "X1000002_Birch_Rust", 41, 4.8, 2.2, "M_X1000002_LeafRust")


@asset("X1000002_Birch_Ochre", "Trees", footprint=2.6, tags=("tree", "autumn"))
def _birch_ochre(coll):
    """White-trunk birch with a dull ochre crown (the classic yellow twins, in shadow)."""
    _gloom_mats()
    birch(coll, "X1000002_Birch_Ochre", 42, 5.2, 2.3, "M_X1000002_LeafOchre")


@asset("X1000002_Tree_Dead", "Trees", footprint=1.6, tags=("tree",))
def _tree_dead(coll):
    """Bare, crooked dead tree with clawing branches and a few strands of hanging moss."""
    _gloom_mats()
    r = core.rng("x1000002_dead", 7)
    mb = MeshBuilder()
    x = y = z = 0.0
    pts = []
    for i in range(5):
        h = 1.05
        mb.cyl(0.36 - i * 0.06, h + 0.06, loc=(x, y, z), mat="M_X1000002_BarkDead", verts=8, r2=0.3 - i * 0.06)
        x += r.uniform(-0.22, 0.22)
        y += r.uniform(-0.18, 0.18)
        z += h
        pts.append((x, y, z))
    for k in range(4):  # root claws
        a = 2 * math.pi * k / 4 + r.uniform(-0.3, 0.3)
        mb.cyl(0.16, 0.9, loc=(math.cos(a) * 0.12, math.sin(a) * 0.12, 0.25), rot=(0, 108, math.degrees(a)),
               mat="M_X1000002_BarkDead", verts=6, r2=0.04)
    moss = MeshBuilder()
    for k in range(6):  # crooked branches, each with a twig
        bx, by, bz = pts[min(4, 1 + k * 4 // 6)]
        a = 2 * math.pi * k / 6 + r.uniform(-0.4, 0.4)
        tilt = r.uniform(45, 70)
        ln = r.uniform(1.1, 1.7)
        mb.cyl(0.11, ln, loc=(bx, by, bz - 0.2), rot=(0, tilt, math.degrees(a)), mat="M_X1000002_BarkDead",
               verts=6, r2=0.035)
        s = math.sin(math.radians(tilt))
        ex = bx + math.cos(a) * s * ln * 0.75
        ey = by + math.sin(a) * s * ln * 0.75
        ez = bz - 0.2 + math.cos(math.radians(tilt)) * ln * 0.75
        mb.cyl(0.05, 0.6, loc=(ex, ey, ez), rot=(0, r.uniform(-35, 35), math.degrees(a) + 40),
               mat="M_X1000002_BarkDead", verts=5, r2=0.015)
        if k % 2 == 0:  # a hanging strand of grey-green moss
            moss.cyl(0.04, 0.7, loc=(ex, ey, ez - 0.7), mat="M_Flat_mountain_dk", verts=4, r2=0.015)
    mb.build("X1000002_Tree_Dead", coll, smooth=True, sharp_angle=50)
    moss.build("X1000002_Tree_Dead_Moss", coll, smooth=True)


@asset("X1000002_Bramble", "Foliage", footprint=1.3, tags=("bush",))
def _bramble(coll):
    """Low tangle of dark thorny canes (danger at the cliff feet)."""
    _gloom_mats()
    r = core.rng("x1000002_bramble", 5)
    mb = MeshBuilder()
    for k in range(7):
        a = r.uniform(0, 360)
        R = r.uniform(0.35, 0.6)
        mb.torus(R, 0.045, loc=(r.uniform(-0.25, 0.25), r.uniform(-0.25, 0.25), r.uniform(0.0, 0.25)),
                 rot=(r.uniform(60, 110), 0, a), mat="M_X1000002_Thorn", u=14, v=5)
    for k in range(22):  # thorns
        a = r.uniform(0, 2 * math.pi)
        rr = r.uniform(0.2, 0.7)
        mb.cyl(0.04, 0.16, loc=(math.cos(a) * rr, math.sin(a) * rr, r.uniform(0.15, 0.8)),
               rot=(r.uniform(-70, 70), r.uniform(-70, 70), 0), mat="M_Flat_cloth_white", verts=4, r2=0.0)
    mb.sphere(0.45, loc=(0, 0, 0.12), scale=(1.3, 1.1, 0.55), mat="M_X1000002_LeafGloom", subdiv=2, lumpy=0.2,
              seed=3, flatten_bottom=0.3)
    mb.build("X1000002_Bramble", coll, smooth=True, sharp_angle=50)


@asset("X1000002_Toadstool_Dark", "Foliage", footprint=1.0, tags=("mushroom",))
def _toadstool_dark(coll):
    """Three purple spotted toadstools (gloomy mushrooms instead of flowers)."""
    _gloom_mats()
    mb = MeshBuilder()
    for (x, y, h, cr) in ((0.0, 0.0, 0.85, 0.42), (0.38, -0.22, 0.5, 0.27), (-0.32, -0.18, 0.36, 0.2)):
        mb.cyl(cr * 0.32, h, loc=(x, y, 0), mat="M_MushStem", verts=8, r2=cr * 0.26)
        mb.dome(cr, cr * 0.75, loc=(x, y, h - 0.04), mat="M_X1000002_ToadCap", u=14, v=4, lip=0.05, profile=0.8)
    mb.build("X1000002_Toadstool_Dark", coll, smooth=True, sharp_angle=50)


@asset("X1000002_Bones", "Props", footprint=0.8, tags=("prop",))
def _bones(coll):
    """A little cartoon skull and two crossed bones lying in the grass."""
    _gloom_mats()
    mb = MeshBuilder()
    mb.sphere(0.2, loc=(0, 0, 0.18), scale=(1.0, 1.05, 0.95), mat="M_X1000002_Bone", subdiv=2)
    mb.box((0.22, 0.14, 0.1), loc=(0, -0.12, 0.07), mat="M_X1000002_Bone")
    for s in (-1, 1):
        mb.sphere(0.055, loc=(s * 0.08, -0.17, 0.2), mat="M_Eye_Black", subdiv=1)
    for a in (30, -30):
        mb.cyl(0.035, 0.75, loc=(-0.38 * math.cos(math.radians(a)), 0.25 - 0.38 * math.sin(math.radians(a)), 0.05),
               rot=(0, 90, a), mat="M_X1000002_Bone", verts=6)
        for t in (-0.38, 0.38):
            for o in (-0.035, 0.035):
                mb.sphere(0.05, loc=(t * math.cos(math.radians(a)) - o * math.sin(math.radians(a)),
                                     0.25 + t * math.sin(math.radians(a)) + o * math.cos(math.radians(a)), 0.05),
                          mat="M_X1000002_Bone", subdiv=1)
    mb.build("X1000002_Bones", coll, smooth=True, sharp_angle=50)


@asset("X1000002_Thorn_Vine", "Foliage", footprint=0.5, tags=("vine",))
def _thorn_vine(coll):
    """Dark thorny strand hanging down a soil face (origin = top), the gloomy cousin of Vine_Hanging_A."""
    _gloom_mats()
    r = core.rng("x1000002_thornvine", 2)
    mb = MeshBuilder()
    z = x = 0.0
    for k in range(9):
        mb.cyl(0.04, 0.34, loc=(x, 0, z - 0.33), mat="M_X1000002_Thorn", verts=5)
        s = 1 if k % 2 else -1
        mb.cyl(0.03, 0.14, loc=(x, -0.02, z - 0.16), rot=(0, s * 75, 0), mat="M_Flat_cloth_white", verts=4, r2=0.0)
        if k % 3 == 1:
            mb.sphere(0.1, loc=(x - s * 0.08, -0.04, z - 0.22), scale=(1.2, 0.5, 0.8), mat="M_X1000002_LeafGloom",
                      subdiv=1)
        z -= 0.32
        x += r.uniform(-0.06, 0.06)
    mb.build("X1000002_Thorn_Vine", coll, smooth=True, sharp_angle=60)


def _moss_grass():
    """Dark blue-green mossy grass for this forest's caps (a local copy of the kit grass-cap recipe)."""
    name = "M_X1000002_GrassMoss2"
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    b = M._MatBuilder(name)
    nz = b.noise(scale=0.08, detail=2.0, roughness=0.5, coord_kind="Object")
    patches = b.ramp(nz, [(0.40, M.col("#2F6232")), (0.62, M.col("#3E7637"))])
    small = b.noise(scale=0.9, detail=1.0, coord_kind="Object")
    top = b.mix(patches, M.col("#1F4527"),
                M._bw(b, b.ramp(small, [(0.62, (0, 0, 0, 1)), (0.86, (0.45, 0.45, 0.45, 1))])))
    side_fac = b.ramp(b.normal_z(), [(0.55, (1, 1, 1, 1)), (0.85, (0, 0, 0, 1))])
    return b.finish(b.mix(top, M.col("#1B3D24"), M._bw(b, side_fac)))


def _dark_soil():
    """Darker, wetter soil for the cliff faces of the ravine."""
    name = "M_X1000002_SoilDark"
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    return M.mat_cliff(name, "#5E4630", "#33261A", "#76593C")


def _deer_trail():
    """Dark, mossy trodden earth for the deer tracks (darker than the kit dirt path: nothing man-made here)."""
    name = "M_X1000002_DeerTrail"
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    b = M._MatBuilder(name)
    nz = b.noise(scale=0.6, detail=1.5, roughness=0.45, coord_kind="Object")
    earth = b.ramp(nz, [(0.35, M.col("#7A5E3E")), (0.65, M.col("#977A52"))])
    moss = b.noise(scale=0.45, detail=1.5, coord_kind="Object")
    return b.finish(b.mix(earth, M.col("#5B7438"), M._bw(b, b.ramp(moss, [(0.5, (0, 0, 0, 1)),
                                                                           (0.72, (0.75, 0.75, 0.75, 1))]))))


def _swap_mat(ob, old, new):
    mats = ob.data.materials if ob.type == "MESH" and ob.data is not None else ()
    for i, mt in enumerate(mats):
        if mt is not None and mt.name == old:
            mats[i] = new


def _darken_terrain(m):
    """Every grass surface of this map (caps, fringes, grassy ramps) gets the mossy dark grass, every soil
    face the dark wet soil."""
    moss = _moss_grass()
    soil = _dark_soil()
    for ob in m.col_terrain.objects:
        _swap_mat(ob, "M_Grass", moss)
        _swap_mat(ob, "M_Dirt_Cliff", soil)


def _stump_pillar(m, name, cx, cy, rx, ry, top, bottom, foot_z):
    """A battlement pillar as a giant mossy tree stump: bark body, grass (moss) top, flaring roots."""
    objs = m.terrace(name, geo.ellipse(cx, cy, rx, ry, 18), top=top, bottom=bottom, stones=False)
    for ob in objs:
        if "_Body" in ob.name:
            _swap_mat(ob, "M_Dirt_Cliff", M.get("M_Bark"))
    m.place("X1000002_Stump_Roots", cx, cy, z=foot_z - 0.05, scale=(rx, ry, 1.1), name=name + "_Roots")


def _hang_vines(m, pts, dy=-1.0):
    """Leafy vines hanging over the lip of the soil face found from each (x, y) toward dy."""
    for i, (x, y) in enumerate(pts):
        fp = m.face_point(x, y, 0.0, dy)
        if fp is None:
            continue
        ex, ey, zt, zb = fp
        drop = zt - (zb if zb is not None else 0.0)
        sz = min(0.75 + (i * 0.37) % 0.85, (drop - 0.6) / 2.9)
        if sz < 0.4:
            continue
        m.place("X1000002_Thorn_Vine" if i % 2 else "Vine_Hanging_A", ex, ey + dy * 0.04, z=zt - 0.1,
                rot=(i * 29) % 30 - 15, scale=(1.0, 1.0, sz), name="FaceVine")


def _vine(m, name, x, y, z0, z1, facing=90):
    """A climbable leafy green vine: the kit vine (hung plumb against the face from a leaf clump on the lip),
    thickened with this forest's chunky leaf segments along the strand where the kit actually hung it."""
    obj = m.ladder(name, x, y, z0, z1, facing=facing, kind="vine")
    lo, hi = m.origin.z + z0 + 0.6, m.origin.z + z1 - 0.6
    mid = [v.co for v in obj.data.vertices if lo < v.co.z < hi]
    sx, sy = x, y
    if mid:
        xs = sorted(v.x for v in mid)
        ys = sorted(v.y for v in mid)
        sx, sy, _sz = m._local(type(mid[0])((xs[len(xs) // 2], ys[len(ys) // 2], 0.0)))
    h = z1 - z0
    n = max(1, int(round(h / 1.0)))
    for k in range(n):
        m.place("X1000002_Vine_Leaves", sx, sy - 0.03, z=z0 + k * h / n, rot=(k * 37) % 50 - 25,
                scale=(1.0, 1.0, h / n), name=f"{name}_Leaves")
    return obj


def _cliff_stones(m, pts):
    """Grey stones set into the soil faces (classic grassySoil cliffs)."""
    for i, (x, y, z) in enumerate(pts):
        m.place("Rock_Cliff_Stone", x, y, z=z, rot=(i * 23) % 30 - 15, scale=0.9 + (i % 3) * 0.15)


def build(m):
    L, D = m.size  # 40 x 36
    grass = dict(top_mat=None)  # grassy slopes, nothing man-made in this forest

    # ================= forest floor (front band) =================
    # entry bluff around the exit (the classic top-left arrival platform P03, with its irises)
    m.terrace("EntryBluff", [(-0.8, -0.8), (4.0, -0.9), (7.0, -0.4), (9.0, 1.6), (9.2, 4.4), (8.4, 6.6),
                             (6.0, 7.8), (2.5, 7.9), (-0.8, 6.9)], top=BLUFF, bottom=-0.5)
    # G2: middle floor (+1 H); G1 is the sunken west hollow (plinth level) behind the bluff
    m.terrace("Floor_G2", [(8.4, -0.8), (15.0, -1.0), (23.2, -0.8), (23.6, 2.0), (24.0, 4.0), (24.6, 8.0),
                           (24.8, 11.5), (25.4, 16.5), (10.2, 16.5), (9.6, 11.0), (10.0, 8.6), (8.4, 7.4)],
              top=G2, bottom=-0.5)
    # G3: east floor (+2 H) wrapping round the shelf's end into a back glade
    m.terrace("Floor_G3", [(23.0, -0.8), (32.0, -1.0), (40.8, -0.8), (40.8, 36.8), (35.0, 36.8), (34.8, 26.0),
                           (34.6, 17.0), (25.2, 16.8), (24.6, 13.0), (24.3, 9.5), (23.9, 6.0), (23.5, 3.0)],
              top=G3, bottom=-0.5)
    m.ramp("Bluff_To_G2", (8.6, 3.8, BLUFF), (12.0, 3.8, G2), 3.2, **grass)
    m.ramp("Bluff_To_G1", (5.0, 7.2, BLUFF), (5.0, 12.4, G1), 3.0, **grass)
    m.ramp("G1_To_G2", (6.8, 12.6, G1), (10.3, 12.6, G2), 3.0, **grass)
    m.ramp("G2_To_G3", (20.0, 6.0, G2), (24.4, 6.0, G3), 3.4, **grass)
    # one continuous trail from the exit through the ravine, draped over both grassy ramps (no seams); it fades
    # out in a trampled clearing on G3, from which worn deer tracks (dark mossy earth: nothing man-made here)
    # lead on to the foot of the east vine (Vine_1410) and round the shelf's end into the east glade
    deer = _deer_trail().name

    def ragged(t):  # deer tracks narrow and widen as they go
        return 0.8 + 0.2 * math.sin(t * math.pi * 3.0) ** 2

    m.path("Trail_Clearing", [(28.6, 6.3), (30.2, 6.9), (31.4, 7.0), (32.4, 7.8)], width=3.6, mat=deer,
           end_taper=0.45, edge_wobble=0.3)
    m.path("Trail_EastTail", [(31.6, 7.4), (32.5, 9.0), (33.0, 11.0), (33.6, 13.5)], width=1.6, mat=deer,
           end_taper=0.35, edge_wobble=0.18, width_fn=ragged)
    m.path("Trail_GladeSpur", [(32.6, 8.4), (34.6, 10.2), (36.3, 12.6), (36.9, 16.0), (36.9, 21.6)], width=1.2,
           mat=deer, end_taper=0.3, edge_wobble=0.15, width_fn=ragged)
    # a worn track from the trail north to the foot of the vine curtain, beside the jump-grab stump
    m.path("Trail_VineSpur", [(17.0, 4.2), (17.5, 6.4), (17.4, 8.4), (17.8, 10.6), (18.6, 12.7)], width=1.5,
           mat=deer, end_taper=0.3, edge_wobble=0.18, width_fn=ragged)
    # the main trail last, so it lies over the ends of the tracks (later ribbons layer on top)
    m.path("Trail", [(4.2, 1.6), (6.0, 3.1), (8.6, 3.8), (12.0, 3.8), (17.0, 4.6), (20.0, 6.0), (24.4, 6.0),
                     (28.4, 6.3), (30.8, 6.6)], width=2.6, end_taper=0.35)

    # ================= the Great Shelf (middle band) =================
    m.terrace("Shelf_P01a", [(-0.8, 15.6), (2.5, 15.2), (5.0, 15.5), (7.5, 15.1), (10.0, 15.7), (12.6, 15.3),
                             (14.9, 15.6), (14.9, 36.8), (-0.8, 36.8)], top=P01A, bottom=-0.5)
    m.terrace("Shelf_P01b", [(14.5, 15.5), (16.5, 15.2), (18.5, 15.1), (20.5, 15.1), (22.5, 15.3), (25.0, 15.7),
                             (27.4, 15.4), (27.4, 36.8), (14.5, 36.8)], top=P01B, bottom=-0.5)
    m.terrace("Shelf_P01c", [(27.1, 15.6), (29.5, 15.8), (31.5, 15.4), (33.6, 15.4), (35.8, 15.9), (35.6, 26.0),
                             (35.4, 36.8), (27.1, 36.8)], top=P01C, bottom=-0.5)
    m.ramp("Shelf_a_b", (17.0, 21.5, P01B), (14.4, 21.5, P01A), 3.0, **grass)
    m.ramp("Shelf_b_c", (29.5, 21.5, P01C), (26.9, 21.5, P01B), 3.0, **grass)

    # ================= battlement ridge (back band) =================
    m.terrace("Ridge_P03", [(-0.8, 27.6), (2.0, 27.0), (4.6, 27.5), (7.0, 27.9), (7.0, 36.8), (-0.8, 36.8)],
              top=RIDGE, bottom=P01A - 0.6)
    # the battlement pillars are giant mossy tree stumps rising out of the shelf (nothing man-made here)
    _stump_pillar(m, "Pillar_P06", 9.6, SADDLE_Y, 1.5, 2.1, PILLAR, P01A - 0.6, P01A)
    m.terrace("Ridge_P04", [(12.2, 26.5), (13.8, 26.2), (15.2, 26.7), (15.2, 34.8), (12.2, 34.8)], top=RIDGE,
              bottom=P01A - 0.6)
    _stump_pillar(m, "Pillar_P07", 17.8, SADDLE_Y, 1.5, 2.1, PILLAR, P01B - 0.6, P01B)
    m.terrace("Ridge_P05", [(20.4, 27.3), (23.0, 26.9), (26.0, 27.4), (28.5, 26.9), (30.6, 27.2), (30.8, 31.6),
                            (35.3, 31.8), (35.3, 36.8), (20.4, 36.8)], top=RIDGE, bottom=P01C - 0.6)
    m.terrace("Ridge_P02", [(30.2, 26.1), (32.4, 25.8), (34.5, 26.3), (34.6, 32.2), (30.2, 32.2)], top=P02,
              bottom=P01C - 0.6)
    # low earth steps in the crenels between ledges and stumps (the classic 60 px hops)
    for i, cx in enumerate((7.55, 11.65, 15.75, 19.85)):
        m.terrace(f"CrenelStep_{i}", geo.ellipse(cx, SADDLE_Y + 0.1, 0.85, 1.0, 14), top=STEP,
                  bottom=P01B - 0.6, fringe=False)
    m.ramp("Ramp_P02_P05", (32.4, 29.6, P02), (32.4, 32.2, RIDGE), 2.8, bottom=P01C - 0.4, **grass)

    # ================= vines (the only links between bands) =================
    _vine(m, "Vine_410", 15.6, 15.0, G2, P01B)
    _vine(m, "Vine_504", 17.3, 14.75, G2, P01B)
    _vine(m, "Vine_664", 19.8, 14.7, G2 + 0.5, P01B)  # the jump-grab vine, over a stump
    _vine(m, "Vine_756", 21.7, 14.8, G2, P01B)
    _vine(m, "Vine_1410", 33.6, 15.0, G3, P01C)
    _vine(m, "Vine_286", 13.6, 26.0, P01A, RIDGE)
    _vine(m, "Vine_1349", 32.4, 25.4, P01C, P02)
    # the back yard behind the battlements (the shelf behind the ridge, x 7-20, y 31-37) was walled in by the
    # ridge, the stumps and the containment ring: a player who dropped into it from the crenels could not climb out
    # (Iteration Three stuck-region scan, docs/runtime/STUCK_SCAN.md). A vine up P04's back face is its way out.
    _vine(m, "Vine_BackYard", 13.7, 35.4, P01A, RIDGE, facing=-90)

    # ================= dressing =================
    # --- entry bluff: irises by the exit, kept low so the ravine opens up behind it
    for i, (x, y) in enumerate([(1.6, 2.6), (6.4, 1.2), (2.2, 5.6), (6.6, 5.7)]):
        m.place("Iris_Patch", x, y, rot=i * 70, scale=1.0 + (i % 2) * 0.2)
    m.place("X1000002_Bush_B", 0.4, 4.0, rot=20, scale=0.9)
    m.place("X1000002_Bush_C", 8.4, 0.6, rot=60)
    m.place("Rock_A", 0.6, 0.2, rot=40)
    m.place("Rock_Boulder", 8.0, 6.4, rot=35, scale=0.55)   # lookout rock on the brink of the ravine
    m.player(7.6, 3.2, rot=-40)  # at the head of the trail, beside the exit
    m.player_spawn(6.4, 3.4, rot=180, note="sp x -204: just east of out01 at the head of the trail")

    # --- G1 west hollow: a tight rust twin on the west edge, mossy rocks, a stump (P01a face kept open)
    m.place("X1000002_Birch_Rust", 0.6, 9.4, rot=30, scale=0.8)
    m.place("X1000002_Birch_Rust", 1.4, 11.2, rot=200, scale=0.7)
    m.place("Rock_B", 3.0, 14.0, rot=40)
    m.place("X1000002_Pine_Gloom", 0.6, 13.6, rot=10, scale=0.8)
    m.place("X1000002_Bush_B", 8.0, 14.6, rot=80)
    m.place("Rock_B", 6.0, 14.3, rot=15)
    m.place("Stump_A", 7.0, 10.2, rot=40)
    m.place("Mushroom_Yellow_S", 2.6, 9.2, rot=10)
    m.place("Mushroom_Yellow_S", 3.0, 8.8, rot=60, scale=0.7)

    # --- G2: trees only clear of the vine curtain (x 15-22)
    m.place("X1000002_Birch_Dusk", 11.6, 14.3, rot=60, scale=0.95)
    m.place("X1000002_Bush_A", 12.6, 10.4, rot=0)
    m.place("X1000002_Birch_Rust", 24.8, 14.0, rot=140, scale=0.95)
    m.place("Stump_A", 19.8, 13.9, rot=20, scale=1.1)  # launch point under the jump-grab vine
    m.place("X1000002_Bush_A", 13.8, 1.0, rot=10)
    m.place("X1000002_Bush_C", 18.8, 0.4, rot=50)
    m.place("X1000002_Bush_B", 23.4, 10.4, rot=100, scale=0.85)
    m.place("Rock_B", 16.0, 8.8, rot=70, scale=0.8)
    m.place("Log_A", 11.6, 8.4, rot=-25)
    m.place("Mushroom_Blue_S", 12.4, 12.4, rot=30)
    m.place("Mushroom_Red_S", 24.0, 12.8, rot=0, scale=0.9)
    m.place("Mushroom_Cluster_A", 15.2, 11.2, rot=70)
    m.place("Rock_A", 17.2, 0.2, rot=15, scale=0.9)

    # --- G3 and the east glade
    m.place("X1000002_Birch_Dusk", 27.0, 14.4, rot=10)
    m.place("X1000002_Birch_Ochre", 30.4, 13.4, rot=90, scale=0.9)
    m.place("X1000002_Birch_Dusk", 38.8, 13.0, rot=200, scale=1.05)
    m.place("X1000002_Tree_Dead", 38.2, 9.0, rot=310)
    for i, (x, y, s) in enumerate([(39.6, 17.5, 0.9), (39.4, 26.6, 0.85), (38.8, 35.4, 0.9)]):
        m.place("X1000002_Pine_Gloom", x, y, rot=i * 50, scale=s)
    m.place("X1000002_Tall_Gloom", 40.2, 28.8, rot=40, scale=0.8)
    for i, (x, y) in enumerate([(26.2, 2.6), (31.4, 1.0), (35.4, 4.2), (39.6, 1.6), (28.6, 10.0)]):
        m.place(["X1000002_Bush_A", "X1000002_Bush_B", "X1000002_Bush_C"][i % 3], x, y, rot=i * 40)
    m.place("X1000002_Pine_Gloom", 40.0, 9.2, rot=0, scale=0.9)
    m.place("X1000002_Pine_Gloom", 40.3, 4.0, rot=30, scale=0.75)
    m.place("Rock_B", 30.4, 11.8, rot=20, scale=0.8)
    m.place("Log_A", 34.6, 2.4, rot=70)
    m.place("Rock_C", 21.6, 2.4)
    m.place("Rock_C", 29.0, 4.4, rot=50)
    m.place("Log_A", 28.6, 14.1, rot=8)
    m.place("Rock_A", 24.8, 14.4, rot=0)
    m.place("Rock_Boulder", 39.2, 20.0, rot=-60, scale=0.6)
    m.place("Mushroom_Cluster_A", 38.4, 15.6, rot=-20)
    # east glade: a small reward pocket (berry bushes, a stump and a log) behind the shelf's end
    m.place("Berry_Bush", 38.7, 22.6, rot=30)
    m.place("Berry_Bush", 38.7, 28.8, rot=140)
    m.place("Stump_A", 38.6, 24.6, rot=10)
    m.place("Mushroom_Cluster_A", 38.5, 30.6, rot=0)
    m.place("Log_A", 39.2, 32.6, rot=80)

    # --- the Great Shelf: twin birches (yellow / yellow / rust) toward the ridge, kept off vines & pillars
    m.place("X1000002_Birch_Ochre", 2.8, 24.2, rot=20)
    m.place("X1000002_Birch_Ochre", 5.4, 23.0, rot=140, scale=0.9)
    m.place("X1000002_Pine_Gloom", 1.0, 17.8, rot=0, scale=0.9)
    m.place("X1000002_Tall_Gloom", 23.2, 24.2, rot=60, scale=0.75)
    m.place("X1000002_Birch_Ochre", 25.6, 22.6, rot=250, scale=0.85)
    m.place("X1000002_Tall_Gloom", 28.4, 24.0, rot=30, scale=0.8)
    m.place("X1000002_Tall_Gloom", 29.6, 18.6, rot=120, scale=0.75)
    for i, (x, y) in enumerate([(14.0, 18.0), (9.8, 17.4), (27.8, 17.4), (31.2, 18.2), (19.6, 22.6),
                                (11.2, 24.4), (34.6, 22.4)]):
        m.place(["X1000002_Bush_B", "X1000002_Bush_A", "X1000002_Bush_C"][i % 3], x, y, rot=i * 55)
    m.place("Rock_B", 6.6, 18.0, rot=30, scale=0.8)
    m.place("Log_A", 21.2, 21.6, rot=-12)
    m.place("Stump_A", 8.4, 23.4, rot=0)
    m.place("Mushroom_Cluster_A", 26.4, 18.4, rot=40)
    m.place("Mushroom_Red_S", 3.6, 21.0, rot=0)
    m.place("X1000002_Tall_Gloom", 0.4, 21.6, rot=100, scale=0.8)
    # gloom: a darker fringe of pines and rust birches along the shelf lip and the foot of the ridge
    # (kept off the vine curtain x 14-23 and low enough not to hide the battlements)
    pine, tall, dead = "X1000002_Pine_Gloom", "X1000002_Tall_Gloom", "X1000002_Tree_Dead"
    for i, (a, x, y, sc) in enumerate([(pine, 4.4, 17.0, 0.85), (pine, 11.4, 17.0, 0.9), (pine, 25.2, 17.2, 0.8),
                                       (dead, 35.0, 19.8, 1.0), (dead, 9.8, 25.6, 1.0),
                                       ("X1000002_Birch_Rust", 17.0, 25.0, 0.85), (pine, 20.2, 25.8, 0.8),
                                       (pine, 29.8, 26.0, 0.8)]):
        m.place(a, x, y, rot=i * 67, scale=sc)

    # --- the battlements: P03 (old arrival ledge), P05 ridge meadow with berry bushes, dark back fringe
    m.place("Iris_Patch", 2.4, 29.4, rot=10)
    m.place("Iris_Patch", 4.6, 30.8, rot=80, scale=0.9)
    for i, (x, y) in enumerate([(0.8, 31.6), (5.8, 32.6), (3.0, 28.4)]):
        m.place(["X1000002_Bush_A", "X1000002_Bush_C", "X1000002_Bush_B"][i], x, y, rot=i * 60)
    m.place("Berry_Bush", 22.6, 28.0, rot=20)   # classic P05 berry bushes, on the camera side of the trail
    m.place("Berry_Bush", 27.0, 28.2, rot=100)
    m.place("X1000002_Birch_Dusk", 22.6, 34.2, rot=30, scale=0.95)
    m.place("X1000002_Birch_Rust", 27.4, 34.6, rot=200)
    m.place("X1000002_Tree_Dead", 21.0, 33.0, rot=120, scale=0.7)
    # (the dead tree at (6.2, 34.2) and the back-row trees at x <= 21 are gone or lowered: they rose into the
    # bottom of 1000006's Gameplay frame, which looks over this back edge)
    m.place("X1000002_Bush_C", 29.2, 34.4, rot=40)
    # (no tree at the west end (1.4, 35.4): in 1000006's Gameplay frame it hid that map's arrival portal)
    for i, (x, y, a, s) in enumerate([(5.2, 35.8, pine, 0.65), (13.6, 34.6, pine, 0.65),
                                      (10.0, 34.8, pine, 0.8), (17.6, 35.0, tall, 0.75), (24.8, 36.0, pine, 0.9),
                                      (31.4, 35.4, pine, 1.0), (34.4, 35.0, tall, 0.7)], start=1):
        m.place(a, x, y, rot=i * 41, scale=s)
    m.place(tall, 28.6, 36.3, rot=3 * 59 + 20, scale=0.75)
    m.place("Mushroom_Red_S", 9.4, 29.2, rot=0, scale=0.8)   # a toadstool on the mossy stump top
    m.place("Mushroom_Yellow_S", 18.2, 30.6, rot=40)
    m.place("Grass_Tuft_A", 17.6, 30.4)

    for i, (x, y) in enumerate([(12.9, 14.7), (23.0, 14.5), (31.8, 14.6), (6.0, 26.4), (22.0, 25.9),
                                (27.0, 25.9)]):
        m.place("X1000002_Bramble", x, y, rot=i * 73, scale=1.0 + (i % 3) * 0.15)
    for i, (x, y) in enumerate([(10.6, 10.2), (27.4, 11.4), (4.0, 22.6), (19.9, 19.9), (25.8, 33.0)]):
        m.place("X1000002_Toadstool_Dark", x, y, rot=i * 61, scale=1.0 + (i % 2) * 0.25)
    m.place("X1000002_Bones", 2.2, 12.4, rot=20)
    m.place("X1000002_Bones", 23.6, 32.6, rot=-40, scale=0.9)
    m.place("X1000002_Pine_Gloom", 26.4, 25.4, rot=15, scale=0.85)
    m.place("X1000002_Pine_Gloom", 7.0, 25.8, rot=75, scale=0.8)

    # --- leafy vines hanging down every soil face the camera sees (besides the climbing vines)
    _hang_vines(m, [(x, 17.4) for x in (0.8, 3.0, 5.6, 8.4, 10.6, 13.0, 23.6, 25.8, 28.2, 30.4, 31.6, 35.0)])
    _hang_vines(m, [(x, 30.6) for x in (0.6, 2.8, 5.0, 21.2, 23.6, 25.8, 28.0, 29.8)] +
                [(31.0, 29.0), (33.8, 29.0), (9.0, SADDLE_Y), (10.3, SADDLE_Y), (17.2, SADDLE_Y), (18.4, SADDLE_Y)])

    # --- stones in the soil faces
    _cliff_stones(m, [(3.0, 15.0, 3.6), (8.0, 14.9, 5.6), (11.0, 15.2, 2.4), (24.0, 14.9, 4.2), (29.0, 15.4, 3.4),
                      (31.0, 15.0, 5.0), (1.8, 27.0, 9.4), (5.6, 27.2, 10.6), (14.6, 26.2, 9.2),
                      (24.4, 26.6, 9.8), (28.0, 26.6, 8.6), (33.6, 25.8, 8.2), (20.0, 15.0, 2.2)])

    # --- ground cover (kept off the trail)
    trail = [(4.5, 2.2), (8.6, 3.8), (13.0, 4.2), (19.0, 5.2), (24.4, 6.0), (31.0, 6.6), (32.6, 7.2)]  # incl. ramps
    trail_zone = geo.offset_poly(geo.ensure_ccw([(x, y - 1.7) for x, y in trail] +
                                                [(x, y + 1.7) for x, y in reversed(trail)]), 0.0)
    tracks = [(31.6, 8.0, 1.4), (32.8, 9.9, 1.3), (33.4, 12.4, 1.3), (17.2, 6.0, 1.2), (17.6, 8.4, 1.2),
              (17.9, 10.4, 1.2), (18.3, 12.0, 1.2), (34.2, 10.0, 1.1), (36.0, 11.8, 1.1), (36.8, 14.6, 1.1),
              (36.9, 17.4, 1.1), (36.9, 20.2, 1.1)]
    # no flower meadows in this forest: grass tufts and little mushrooms instead
    m.scatter(["Grass_Tuft_A", "X1000002_Toadstool_Dark", "Grass_Tuft_A", "Mushroom_Blue_S"],
              geo.rect(9, 0, 40, 15), 26, seed=11, min_dist=1.8, avoid=[trail_zone, (19.8, 14.0, 1.5)] + tracks)
    m.scatter(["Grass_Tuft_A", "Grass_Tuft_A", "X1000002_Toadstool_Dark", "Mushroom_Blue_S"],
              geo.rect(0, 16, 35, 26), 14, seed=12, min_dist=2.0, avoid=[(17.0, 21.5, 2.0), (28.2, 21.5, 2.0)])
    m.scatter(["Grass_Tuft_A", "Mushroom_Blue_S"], geo.rect(0, 27, 35, 36), 10, seed=13, min_dist=2.0,
              avoid=[geo.rect(6, SADDLE_Y - 1.4, 21.5, SADDLE_Y + 1.4)], z_band=(11.0, 12.5))

    # ================= gameplay =================
    m.edge_portal("out01")
    m.mobs("Orange Mushroom", geo.rect(11, 1, 23, 12), 2, seed=1, z_band=(0.6, 1.2), avoid=tracks)
    m.mobs("Orange Mushroom", geo.rect(25, 1, 40, 13), 2, seed=2, z_band=(1.5, 2.1), avoid=tracks)
    glade_clear = [(38.7, 22.6, 1.4), (38.7, 28.8, 1.4), (38.6, 24.6, 1.0), (38.5, 30.6, 1.0), (39.2, 32.6, 1.4),
                   (39.2, 20.0, 1.3)]
    m.mobs("Orange Mushroom", geo.rect(35.8, 17, 38.0, 33), 1, seed=8, z_band=(1.5, 2.1), avoid=glade_clear)
    g1_clear = [(0.6, 9.4, 1.6), (1.4, 11.2, 1.5), (1.0, 13.6, 1.0), (3.0, 14.0, 1.1), (7.0, 10.2, 0.9),
                (2.8, 9.0, 1.0), (8.4, 14.0, 1.3), (6.0, 14.3, 1.1)]
    m.mobs("Red Snail", geo.rect(0, 8.5, 9, 14.5), 1, seed=3, z_band=(-0.2, 0.4), avoid=g1_clear)
    m.mobs("Orange Mushroom", geo.rect(0, 8.5, 9, 14.5), 1, seed=16, z_band=(-0.2, 0.4), avoid=g1_clear)
    m.mobs("Blue Snail", geo.rect(25, 1, 40, 13), 1, seed=9, z_band=(1.5, 2.1), avoid=tracks)
    m.mobs("Snail", geo.rect(1, 17, 14, 26), 1, seed=4, z_band=(7.3, 7.9))
    m.mobs("Red Snail", geo.rect(2, 17, 14, 26), 1, seed=10, z_band=(7.3, 7.9))
    m.mobs("Snail", geo.rect(15, 17, 35, 26), 2, seed=5, z_band=(5.8, 7.0))
    m.mobs("Orange Mushroom", geo.rect(16, 17, 27, 26), 1, seed=6, z_band=(6.6, 7.0))
    m.mobs("Snail", geo.rect(21, 30, 30, 35), 1, seed=7, z_band=(11.8, 12.2))
    m.mobs("Orange Mushroom", geo.rect(21, 30, 30, 35), 1, seed=14, z_band=(11.8, 12.2))
    m.mobs("Snail", geo.rect(0, 30, 7, 35), 1, seed=15, z_band=(11.8, 12.2))
    m.mobs("Blue Snail", geo.rect(21, 30, 30, 35), 1, seed=17, z_band=(11.8, 12.2))

    # floor (exit -> ravine -> east end), the west hollow, and the feet of every vine
    m.route("Descent", [(4.0, 1.0), (4.5, 3.8), (8.6, 3.8), (12.0, 3.8), (17.0, 4.5), (20.0, 6.0), (24.4, 6.0),
                        (31.0, 6.6), (39.2, 7.0)])
    m.route("WestHollow", [(5.0, 4.5), (5.0, 7.2), (5.0, 12.4), (6.8, 12.6), (10.3, 12.6), (13.0, 12.2)])
    # past the vine feet; the jump-grab stump under Vine_664 stays clear of the walk line
    m.route("VineCurtainFeet", [(13.0, 12.2), (15.6, 13.5), (17.3, 13.5), (18.4, 12.3), (21.0, 12.3), (21.7, 13.5),
                                (20.6, 9.0), (20.0, 6.0)])
    m.route("VineSpur", [(17.0, 4.5), (17.4, 7.0), (17.9, 9.8), (18.4, 12.3)])  # the deer track
    m.route("VineEastFoot", [(31.0, 6.6), (32.4, 8.6), (33.2, 11.2), (33.6, 13.8)])
    m.route("EastGlade", [(31.0, 6.6), (36.6, 12.0), (36.9, 22.0), (36.9, 33.0)])
    # the Great Shelf: up Vine_504 from the curtain feet, then west and east along the shelf
    m.route("ShelfWest", [(17.3, 13.5), (17.3, 16.6), (17.0, 21.5), (14.4, 21.5), (8.0, 21.0), (3.0, 19.5)])
    # ... east along the shelf and up Vine_1349 onto P02
    m.route("ShelfEast", [(17.3, 16.6), (22.0, 19.0), (26.9, 21.5), (29.5, 21.5), (32.4, 23.0), (32.4, 24.9),
                          (32.4, 26.9)])
    # up Vine_1410 from the east floor onto P01c
    m.route("ShelfToVines", [(33.6, 13.8), (33.6, 16.8), (32.4, 23.0)])
    # up Vine_286 from the shelf onto the P04 ledge of the battlements
    m.route("ShelfToRidgeVine", [(14.4, 21.5), (13.6, 25.2), (13.6, 27.4)])
    # the battlements, from the vine 286 top across pillars and saddles to P02 (vine 1349 top)
    m.route("BattlementsWest", [(13.6, 27.4), (13.6, SADDLE_Y), (12.7, SADDLE_Y), (10.6, SADDLE_Y),
                                (8.6, SADDLE_Y), (6.5, SADDLE_Y), (3.0, 31.0)])
    m.route("BattlementsEast", [(13.6, SADDLE_Y), (14.7, SADDLE_Y), (16.8, SADDLE_Y), (18.8, SADDLE_Y),
                                (20.9, SADDLE_Y), (26.0, 30.0), (29.4, 31.6), (31.4, 33.0), (32.4, 32.6), (32.4, 29.6),
                                (32.4, 26.9)])

    # the dark, mossy grass of the Dangerous Forest (after all terrain exists)
    _darken_terrain(m)
