"""Nature assets: chunky whimsical trees, bushes, flowers, mushrooms, rocks."""

import math

from mathutils import Vector

from .. import core
from ..geo import MeshBuilder
from . import asset


# ---------------------------------------------------------------------------
# Trees: trunk object + canopy object (separate so gradients span each part)
# ---------------------------------------------------------------------------

def _trunk(mb, r, seed, height, base_r, bend=0.25, segs=4, roots=4, bark="M_Bark"):
    x = y = z = 0.0
    top = None
    for i in range(segs):
        h = height / segs
        r0 = base_r * (1 - 0.16 * i)
        r1 = base_r * (1 - 0.16 * (i + 1))
        mb.cyl(r0, h + 0.05, loc=(x, y, z), mat=bark, verts=10, r2=r1)
        x += r.uniform(-bend, bend)
        y += r.uniform(-bend, bend)
        z += h
        top = (x, y, z)
    # root flare
    for k in range(roots):
        a = 2 * math.pi * k / roots + r.uniform(-0.3, 0.3)
        L = base_r * r.uniform(1.4, 2.0)
        mb.cyl(base_r * 0.42, L, loc=(math.cos(a) * base_r * 0.3, math.sin(a) * base_r * 0.3, 0.32),
               rot=(0, 105, math.degrees(a)), mat=bark, verts=7, r2=base_r * 0.12)
    mb.cyl(base_r * 1.35, 0.55, loc=(0, 0, -0.05), mat=bark, verts=10, r2=base_r)
    return top


def _puffy_canopy(mb, r, seed, center, radius, lobes=6, squash=0.82, mat="M_Leaf", spread=0.78, rise=0.55):
    cx, cy, cz = center
    mb.sphere(radius, loc=(cx, cy, cz + radius * 0.35), scale=(1, 1, squash), mat=mat, subdiv=3,
              lumpy=0.10, seed=seed, flatten_bottom=0.45)
    for k in range(lobes):
        a = 2 * math.pi * k / lobes + r.uniform(-0.35, 0.35)
        rr = radius * r.uniform(0.52, 0.70)
        d = radius * spread * r.uniform(0.85, 1.05)
        z = cz + radius * r.uniform(-0.05, rise)
        mb.sphere(rr, loc=(cx + math.cos(a) * d, cy + math.sin(a) * d, z), scale=(1, 1, squash), mat=mat,
                  subdiv=2, lumpy=0.12, seed=seed + k + 1, flatten_bottom=0.4)
    # crown puff
    mb.sphere(radius * 0.62, loc=(cx + r.uniform(-0.3, 0.3), cy + r.uniform(-0.3, 0.3), cz + radius * 1.05),
              scale=(1, 1, squash), mat=mat, subdiv=2, lumpy=0.1, seed=seed + 99)


def _make_tree(coll, name, seed, height, base_r, canopy_r, lobes, leaf="M_Leaf", bend=0.25):
    r = core.rng(name, seed)
    trunk = MeshBuilder()
    top = _trunk(trunk, r, seed, height, base_r, bend=bend)
    trunk.build(name + "_Trunk", coll, smooth=True, sharp_angle=60)
    can = MeshBuilder()
    _puffy_canopy(can, r, seed, top, canopy_r, lobes=lobes, mat=leaf)
    can.build(name + "_Canopy", coll, smooth=True, sharp_angle=80)


@asset("Tree_Round_A", "Trees", footprint=3.0, tags=("tree",))
def tree_round_a(coll):
    _make_tree(coll, "Tree_Round_A", 1, height=4.2, base_r=0.42, canopy_r=2.4, lobes=6)


@asset("Tree_Round_B", "Trees", footprint=3.0, tags=("tree",))
def tree_round_b(coll):
    _make_tree(coll, "Tree_Round_B", 2, height=5.0, base_r=0.48, canopy_r=2.8, lobes=7, leaf="M_Leaf_B")


@asset("Tree_Round_C", "Trees", footprint=2.5, tags=("tree",))
def tree_round_c(coll):
    _make_tree(coll, "Tree_Round_C", 3, height=3.4, base_r=0.36, canopy_r=2.0, lobes=5)


@asset("Tree_Tall_A", "Trees", footprint=3.0, tags=("tree",))
def tree_tall_a(coll):
    """Tall tree with two canopy tiers (forest maps)."""
    name = "Tree_Tall_A"
    r = core.rng(name, 4)
    trunk = MeshBuilder()
    top = _trunk(trunk, r, 4, 7.5, 0.55, bend=0.2, segs=5)
    trunk.build(name + "_Trunk", coll, smooth=True, sharp_angle=60)
    can = MeshBuilder()
    _puffy_canopy(can, r, 4, top, 2.6, lobes=6, mat="M_Leaf_B")
    mid = (top[0] * 0.5, top[1] * 0.5, top[2] * 0.62)
    _puffy_canopy(can, r, 14, mid, 2.1, lobes=5, mat="M_Leaf_B", rise=0.2)
    can.build(name + "_Canopy", coll, smooth=True, sharp_angle=80)


@asset("Tree_Giant_A", "Trees", footprint=6.0, tags=("tree", "landmark"))
def tree_giant_a(coll):
    """Huge landmark tree (towns / forest centers)."""
    _make_tree(coll, "Tree_Giant_A", 5, height=8.5, base_r=1.1, canopy_r=5.2, lobes=8, bend=0.35)


@asset("Tree_Pine_A", "Trees", footprint=2.2, tags=("tree",))
def tree_pine_a(coll):
    """Chunky stacked-cone fir (dark forest maps)."""
    name = "Tree_Pine_A"
    r = core.rng(name, 6)
    trunk = MeshBuilder()
    trunk.cyl(0.32, 2.2, mat="M_Bark", verts=8, r2=0.22)
    trunk.cyl(0.55, 0.4, loc=(0, 0, -0.05), mat="M_Bark", verts=8, r2=0.32)
    trunk.build(name + "_Trunk", coll, smooth=True)
    can = MeshBuilder()
    z = 1.5
    for i, (rad, h) in enumerate([(2.2, 2.4), (1.75, 2.1), (1.3, 1.9), (0.8, 1.6)]):
        can.cyl(rad, h, loc=(0, 0, z), mat="M_Leaf_B", verts=11, r2=rad * 0.18, bevel=0.0)
        z += h * 0.55
    can.build(name + "_Canopy", coll, smooth=True, sharp_angle=50)


@asset("Tree_Autumn_A", "Trees", footprint=3.0, tags=("tree",))
def tree_autumn_a(coll):
    _make_tree(coll, "Tree_Autumn_A", 7, height=4.4, base_r=0.42, canopy_r=2.5, lobes=6, leaf="M_Leaf_Autumn")


@asset("Tree_Sapling_A", "Trees", footprint=1.2, tags=("tree", "small"))
def tree_sapling(coll):
    _make_tree(coll, "Tree_Sapling_A", 8, height=1.8, base_r=0.16, canopy_r=0.95, lobes=4)


@asset("Tree_Palm_A", "Trees", footprint=2.5, tags=("tree", "coast"))
def tree_palm(coll):
    """Leaning coastal palm for Southperry."""
    name = "Tree_Palm_A"
    trunk = MeshBuilder()
    x = z = 0.0
    for i in range(7):
        h = 0.85
        trunk.cyl(0.32 - i * 0.025, h + 0.04, loc=(x, 0, z), rot=(0, 8 + i * 3, 0), mat="M_Bark", verts=8,
                  r2=0.30 - i * 0.025)
        x += math.sin(math.radians(8 + i * 3)) * h
        z += math.cos(math.radians(8 + i * 3)) * h
    trunk.build(name + "_Trunk", coll, smooth=True, sharp_angle=50)
    can = MeshBuilder()
    for k in range(7):
        a = 2 * math.pi * k / 7
        d = Vector((math.cos(a), math.sin(a), 0))
        root = Vector((x, 0, z))
        mid = root + d * 1.6 + Vector((0, 0, 0.45))
        tip = root + d * 3.0 + Vector((0, 0, -0.6))
        side = Vector((-d.y, d.x, 0)) * 0.55
        can.quad(root + side * 0.3, mid + side, mid - side, root - side * 0.3, "M_Leaf")
        can.tri(mid + side, tip, mid - side, "M_Leaf")
    can.sphere(0.45, loc=(x, 0, z - 0.1), mat="M_Bark", subdiv=1)
    can.build(name + "_Canopy", coll, smooth=False)


# ---------------------------------------------------------------------------
# Bushes, grass, flowers
# ---------------------------------------------------------------------------

def _bush(coll, name, seed, radius, lobes, mat="M_Bush"):
    r = core.rng(name, seed)
    mb = MeshBuilder()
    mb.sphere(radius, loc=(0, 0, radius * 0.55), scale=(1.15, 1.0, 0.8), mat=mat, subdiv=2, lumpy=0.14,
              seed=seed, flatten_bottom=0.5)
    for k in range(lobes):
        a = 2 * math.pi * k / lobes + r.uniform(-0.4, 0.4)
        rr = radius * r.uniform(0.5, 0.7)
        mb.sphere(rr, loc=(math.cos(a) * radius * 0.75, math.sin(a) * radius * 0.65, rr * 0.6), scale=(1, 1, 0.85),
                  mat=mat, subdiv=2, lumpy=0.14, seed=seed + k, flatten_bottom=0.5)
    mb.build(name, coll, smooth=True, sharp_angle=80)


@asset("Bush_A", "Foliage", footprint=1.4, tags=("bush",))
def bush_a(coll):
    _bush(coll, "Bush_A", 11, 0.8, 4)


@asset("Bush_B", "Foliage", footprint=2.0, tags=("bush",))
def bush_b(coll):
    _bush(coll, "Bush_B", 12, 1.1, 5)


@asset("Bush_C", "Foliage", footprint=0.9, tags=("bush",))
def bush_c(coll):
    _bush(coll, "Bush_C", 13, 0.55, 3)


@asset("Bush_Flowering_A", "Foliage", footprint=1.6, tags=("bush",))
def bush_flowering(coll):
    _bush(coll, "Bush_Flowering_A", 14, 0.9, 4)
    r = core.rng("bf", 1)
    mb = MeshBuilder()
    for k in range(14):
        a = r.uniform(0, 2 * math.pi)
        el = r.uniform(0.15, 1.2)
        p = Vector((math.cos(a) * 0.95 * math.cos(el * 0.8), math.sin(a) * 0.85 * math.cos(el * 0.8),
                    0.5 + math.sin(el) * 0.62))
        mb.sphere(0.13, loc=p, mat="M_Flat_flower_pink" if k % 3 else "M_Flat_flower_white", subdiv=1)
    mb.build("Bush_Flowering_A_Flowers", coll, smooth=True)


@asset("Grass_Tuft_A", "Foliage", footprint=0.5, tags=("grass",))
def grass_tuft_a(coll):
    r = core.rng("gta", 1)
    mb = MeshBuilder()
    for k in range(9):
        a = 2 * math.pi * k / 9 + r.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0)) * 0.06
        base = d * 0.06
        tip = d * r.uniform(0.18, 0.32) + Vector((0, 0, r.uniform(0.35, 0.6)))
        mb.tri(base + side, base - side, tip, "M_Grass")
    mb.build("Grass_Tuft_A", coll, smooth=False, recalc_normals=False)


def _fan(mb, center, ring, mat):
    """Triangle fan from ``center`` to a closed ``ring`` of points (shared verts, so it shades smoothly).

    Wound counter-clockwise seen from above (normal +Z for a ring ordered by increasing angle); build the
    MeshBuilder with ``recalc_normals=False`` so open fans keep that orientation."""
    bm = mb.bm
    c = bm.verts.new(center)
    vs = [bm.verts.new(p) for p in ring]
    mi = mb.mat(mat)
    n = len(vs)
    for i in range(n):
        bm.faces.new((c, vs[i], vs[(i + 1) % n])).material_index = mi
    return c, vs


def _chunky_bloom(mb, x, y, h, petal_mat, r, R=0.13, n=5, center="M_Flat_flower_yellow", tilt=14.0, cup=0.035,
                  stem_w=0.036):
    """Low-poly stylised flower (28 tris): a cupped disc of n rounded petals (3 verts per petal tip and a notch,
    one smooth-shaded fan), a low yellow button, and a stem of two crossed quads. The bloom faces up with a
    random spin and a tilt of up to ``tilt`` degrees, so a patch never looks stamped."""
    from mathutils import Matrix
    spin = r.uniform(0, 2 * math.pi)
    tm = (Matrix.Translation((x, y, h)) @ Matrix.Rotation(r.uniform(0, 2 * math.pi), 4, "Z")
          @ Matrix.Rotation(math.radians(r.uniform(0, tilt)), 4, "X"))
    half = math.pi / n
    w = 0.72 * half
    ring = []
    for k in range(n):
        a = spin + 2 * math.pi * k / n
        for b, d, z in ((a - w, 0.93 * R, cup * 0.85), (a, R, cup), (a + w, 0.93 * R, cup * 0.85),
                        (a + half, 0.58 * R, cup * 0.45)):
            ring.append(tm @ Vector((math.cos(b) * d, math.sin(b) * d, z)))
    _fan(mb, tm @ Vector((0, 0, 0)), ring, petal_mat)
    rc = 0.38 * R
    button = [tm @ Vector((math.cos(spin + 0.5 * math.pi * k) * rc, math.sin(spin + 0.5 * math.pi * k) * rc,
                           cup * 0.6)) for k in range(4)]
    _fan(mb, tm @ Vector((0, 0, cup * 0.6 + 0.025)), button, center)
    top = tm @ Vector((0, 0, -0.01))
    s = stem_w / 2
    for dx, dy in ((s, 0.0), (0.0, s)):
        mb.quad((x - dx, y - dy, 0.0), (x + dx, y + dy, 0.0), (top.x + dx, top.y + dy, top.z),
                (top.x - dx, top.y - dy, top.z), "M_Flat_grass_side")


def _flower_patch(coll, name, colors, n, radius, seed, leaves=2, h=(0.22, 0.42)):
    """n chunky low-poly blooms (cycling through colors) within radius over a few low leaf mounds.

    About 28 tris per bloom + 20 per leaf mound (9 blooms + 2 mounds = 292 tris)."""
    r = core.rng(name, seed)
    mb = MeshBuilder()
    for k in range(n):
        a = r.uniform(0, 2 * math.pi)
        d = radius * math.sqrt(r.random())
        _chunky_bloom(mb, math.cos(a) * d, math.sin(a) * d, r.uniform(*h), colors[k % len(colors)], r)
    for k in range(leaves):
        a = 2 * math.pi * k / leaves + r.uniform(-0.6, 0.6)
        d = radius * r.uniform(0.35, 0.65)
        mb.sphere(0.13, loc=(math.cos(a) * d, math.sin(a) * d, 0.06), scale=(1.3, 1, 0.6), mat="M_Bush", subdiv=1)
    mb.build(name, coll, smooth=True, sharp_angle=60, recalc_normals=False)


@asset("Flower_Patch_A", "Foliage", footprint=1.0, tags=("flower",))
def flower_patch_a(coll):
    """Patch of 9 chunky pink/white/yellow blooms on stems over two leaf mounds (292 tris)."""
    _flower_patch(coll, "Flower_Patch_A", ["M_Flat_flower_pink", "M_Flat_flower_white", "M_Flat_flower_yellow"], 9,
                  0.55, 1)


@asset("Flower_Patch_B", "Foliage", footprint=1.0, tags=("flower",))
def flower_patch_b(coll):
    """Patch of 9 chunky red/purple/blue blooms on stems over two leaf mounds (292 tris)."""
    _flower_patch(coll, "Flower_Patch_B", ["M_Flat_flower_red", "M_Flat_flower_purple", "M_Flat_flower_blue"], 9,
                  0.55, 2)


@asset("Flower_Bed_Large", "Foliage", footprint=2.5, tags=("flower",))
def flower_bed_large(coll):
    """Large mixed flower bed: 34 chunky blooms in five colours over six leaf mounds (~1.07k tris)."""
    _flower_patch(coll, "Flower_Bed_Large", ["M_Flat_flower_pink", "M_Flat_flower_yellow", "M_Flat_flower_red",
                                             "M_Flat_flower_white", "M_Flat_flower_purple"], 34, 1.3, 3, leaves=6)


# ---------------------------------------------------------------------------
# Decorative mushrooms (iconic for Maple Island)
# ---------------------------------------------------------------------------

def _mushroom(coll, name, cap_mat, h, cap_r, stem_r, seed, spots=True, tilt=0.0):
    mb = MeshBuilder()
    mb.cyl(stem_r * 1.15, h, mat="M_MushStem", verts=12, r2=stem_r * 0.85, rot=(tilt, 0, 0))
    mb.build(name + "_Stem", coll, smooth=True, sharp_angle=60)
    cap = MeshBuilder()
    cap.dome(cap_r, cap_r * 0.75, loc=(0, -math.sin(math.radians(tilt)) * h, h * 0.97), mat=cap_mat, u=20, v=6,
             lip=cap_r * 0.12, profile=0.8, rot=(tilt, 0, 0))
    cap.build(name + "_Cap", coll, smooth=True, sharp_angle=70)


@asset("Mushroom_Orange_S", "Foliage", footprint=0.6, tags=("mushroom",))
def mush_orange_s(coll):
    _mushroom(coll, "Mushroom_Orange_S", "M_Spot_mush_orange__mush_spot", 0.45, 0.38, 0.11, 1)


@asset("Mushroom_Red_S", "Foliage", footprint=0.6, tags=("mushroom",))
def mush_red_s(coll):
    _mushroom(coll, "Mushroom_Red_S", "M_Spot_mush_red__mush_spot", 0.5, 0.34, 0.1, 2, tilt=8)


@asset("Mushroom_Yellow_S", "Foliage", footprint=0.6, tags=("mushroom",))
def mush_yellow_s(coll):
    _mushroom(coll, "Mushroom_Yellow_S", "M_Spot_mush_yellow__mush_spot", 0.38, 0.3, 0.09, 3)


@asset("Mushroom_Blue_S", "Foliage", footprint=0.6, tags=("mushroom",))
def mush_blue_s(coll):
    _mushroom(coll, "Mushroom_Blue_S", "M_Spot_mush_blue__mush_spot", 0.42, 0.33, 0.1, 4, tilt=-6)


@asset("Mushroom_Cluster_A", "Foliage", footprint=1.2, tags=("mushroom",))
def mush_cluster(coll):
    """Little group of 4 colored mushrooms (as seen at the West Entrance)."""
    specs = [((-0.45, 0.05), "M_Spot_mush_yellow__mush_spot", 0.35, 0.25),
             ((-0.1, 0.1), "M_Spot_mush_orange__mush_spot", 0.5, 0.33),
             ((0.32, -0.05), "M_Spot_mush_red__mush_spot", 0.7, 0.42),
             ((0.72, 0.12), "M_Spot_mush_green__mush_spot", 0.42, 0.3)]
    stems = MeshBuilder()
    caps = MeshBuilder()
    for (x, y), m, h, rr in specs:
        stems.cyl(rr * 0.33, h, loc=(x, y, 0), mat="M_MushStem", verts=10, r2=rr * 0.26)
        caps.dome(rr, rr * 0.75, loc=(x, y, h * 0.96), mat=m, u=16, v=5, lip=rr * 0.12, profile=0.8)
    stems.build("Mushroom_Cluster_A_Stems", coll, smooth=True, sharp_angle=60)
    caps.build("Mushroom_Cluster_A_Caps", coll, smooth=True, sharp_angle=70)


@asset("Mushroom_Giant_Orange", "Foliage", footprint=3.0, tags=("mushroom", "landmark"))
def mush_giant_orange(coll):
    _mushroom(coll, "Mushroom_Giant_Orange", "M_Spot_mush_orange__mush_spot", 3.2, 2.4, 0.55, 5)


@asset("Mushroom_Giant_Red", "Foliage", footprint=3.0, tags=("mushroom", "landmark"))
def mush_giant_red(coll):
    _mushroom(coll, "Mushroom_Giant_Red", "M_Spot_mush_red__mush_spot", 2.6, 2.0, 0.45, 6, tilt=6)


@asset("Mushroom_Giant_Blue", "Foliage", footprint=3.0, tags=("mushroom", "landmark"))
def mush_giant_blue(coll):
    _mushroom(coll, "Mushroom_Giant_Blue", "M_Spot_mush_blue__mush_spot", 2.9, 2.2, 0.5, 7, tilt=-5)


# ---------------------------------------------------------------------------
# Rocks, stumps, logs
# ---------------------------------------------------------------------------

def _rock(coll, name, seed, size, squash=0.65, mat="M_Rock"):
    mb = MeshBuilder()
    mb.sphere(size, loc=(0, 0, size * squash * 0.55), scale=(1.15, 0.95, squash), mat=mat, subdiv=1, lumpy=0.32,
              seed=seed, flatten_bottom=0.55)
    mb.build(name, coll, smooth=True, sharp_angle=38)


@asset("Rock_A", "Rocks", footprint=1.2, tags=("rock",))
def rock_a(coll):
    _rock(coll, "Rock_A", 21, 0.6)


@asset("Rock_B", "Rocks", footprint=1.8, tags=("rock",))
def rock_b(coll):
    _rock(coll, "Rock_B", 22, 0.95, 0.55, mat="M_Rock_Moss")


@asset("Rock_C", "Rocks", footprint=0.6, tags=("rock",))
def rock_c(coll):
    _rock(coll, "Rock_C", 23, 0.32, 0.7)


@asset("Rock_Boulder", "Rocks", footprint=3.0, tags=("rock", "landmark"))
def rock_boulder(coll):
    mb = MeshBuilder()
    mb.sphere(1.6, loc=(0, 0, 1.0), scale=(1.2, 1.0, 0.8), mat="M_Rock_Moss", subdiv=2, lumpy=0.25, seed=24,
              flatten_bottom=0.6)
    mb.sphere(0.9, loc=(1.4, -0.6, 0.5), scale=(1.1, 1.0, 0.75), mat="M_Rock", subdiv=1, lumpy=0.3, seed=25,
              flatten_bottom=0.5)
    mb.build("Rock_Boulder", coll, smooth=True, sharp_angle=40)


@asset("Rock_Cliff_Stone", "Rocks", footprint=0.8, tags=("rock", "cliff"))
def rock_cliff_stone(coll):
    """Flat stone to embed in cliff faces (Maple dirt walls have stones in them)."""
    mb = MeshBuilder()
    mb.sphere(0.45, scale=(1.2, 0.55, 0.8), mat="M_Rock", subdiv=1, lumpy=0.25, seed=26)
    tuft_r = core.rng("rcs", 1)
    for k in range(5):
        x = tuft_r.uniform(-0.4, 0.4)
        mb.tri((x - 0.06, -0.05, 0.3), (x + 0.06, -0.05, 0.3), (x + tuft_r.uniform(-0.1, 0.1), -0.12, 0.55), "M_Grass")
    mb.build("Rock_Cliff_Stone", coll, smooth=True, sharp_angle=40)


@asset("Stump_A", "Foliage", footprint=1.0, tags=("stump",))
def stump_a(coll):
    mb = MeshBuilder()
    mb.cyl(0.55, 0.7, mat="M_Bark", verts=12, r2=0.48)
    mb.cyl(0.47, 0.06, loc=(0, 0, 0.68), mat="M_Flat_wood_lt", verts=12)
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.4
        mb.cyl(0.22, 0.8, loc=(math.cos(a) * 0.25, math.sin(a) * 0.25, 0.18), rot=(0, 100, math.degrees(a)),
               mat="M_Bark", verts=6, r2=0.06)
    mb.build("Stump_A", coll, smooth=True, sharp_angle=45)


@asset("Log_A", "Foliage", footprint=2.2, tags=("log",))
def log_a(coll):
    mb = MeshBuilder()
    mb.cyl(0.38, 2.4, loc=(-1.2, 0, 0.36), rot=(0, 90, 0), mat="M_Bark", verts=12, r2=0.34)
    mb.cyl(0.33, 0.04, loc=(1.21, 0, 0.36), rot=(0, 90, 0), mat="M_Flat_wood_lt", verts=12)
    mb.build("Log_A", coll, smooth=True, sharp_angle=45)


@asset("Vine_Hanging_A", "Foliage", footprint=0.5, tags=("vine",))
def vine_hanging(coll):
    """Leafy vine strand to hang down cliff faces (origin = top)."""
    r = core.rng("vine", 1)
    mb = MeshBuilder()
    z = 0.0
    x = 0.0
    for k in range(9):
        mb.cyl(0.035, 0.32, loc=(x, 0, z - 0.32), mat="M_Flat_grass_dark", verts=4)
        for s in (-1, 1):
            mb.sphere(0.11, loc=(x + s * 0.09, -0.04, z - 0.18), scale=(1.2, 0.5, 0.8), mat="M_Leaf", subdiv=1)
        z -= 0.32
        x += r.uniform(-0.05, 0.05)
    mb.build("Vine_Hanging_A", coll, smooth=True, sharp_angle=60)


# ---------------------------------------------------------------------------
# Additional foliage (from the map briefs)
# ---------------------------------------------------------------------------

def _birch(coll, name, seed, height, canopy_r, leaf):
    """White-trunked autumn tree (Snail Hunting Ground minimap colors)."""
    r = core.rng(name, seed)
    trunk = MeshBuilder()
    x = y = z = 0.0
    for i in range(4):
        h = height / 4
        trunk.cyl(0.3 - i * 0.04, h + 0.04, loc=(x, y, z), mat="M_Flat_cloth_white", verts=9, r2=0.26 - i * 0.04)
        for k in range(2):
            trunk.box((0.22, 0.05, 0.06), loc=(x + 0.05, y - 0.27 + i * 0.03, z + h * (0.3 + 0.4 * k)),
                      rot=(0, 0, r.uniform(-20, 20)), mat="M_Flat_hair_black")
        x += r.uniform(-0.15, 0.15)
        y += r.uniform(-0.15, 0.15)
        z += h
    trunk.cyl(0.45, 0.35, loc=(0, 0, -0.05), mat="M_Flat_cloth_white", verts=9, r2=0.3)
    trunk.build(name + "_Trunk", coll, smooth=True, sharp_angle=60)
    can = MeshBuilder()
    _puffy_canopy(can, r, seed, (x, y, z), canopy_r, lobes=5, mat=leaf, squash=0.9)
    can.build(name + "_Canopy", coll, smooth=True, sharp_angle=80)


@asset("Tree_Birch_Orange", "Trees", footprint=2.6, tags=("tree", "autumn"))
def birch_orange(coll):
    _birch(coll, "Tree_Birch_Orange", 31, 4.6, 2.2, "M_Leaf_Autumn")


@asset("Tree_Birch_Yellow", "Trees", footprint=2.6, tags=("tree", "autumn"))
def birch_yellow(coll):
    _birch(coll, "Tree_Birch_Yellow", 32, 5.2, 2.4, "M_Leaf_Yellow")


@asset("Sunflower_Patch", "Foliage", footprint=1.4, tags=("flower",))
def sunflower_patch(coll):
    r = core.rng("sunflower", 1)
    mb = MeshBuilder()
    for k in range(5):
        a = 2 * math.pi * k / 5 + r.uniform(-0.3, 0.3)
        d = r.uniform(0.15, 0.6)
        x, y = math.cos(a) * d, math.sin(a) * d
        h = r.uniform(1.0, 1.5)
        mb.cyl(0.035, h, loc=(x, y, 0), mat="M_Flat_grass_side", verts=5)
        for s in (-1, 1):
            mb.sphere(0.12, loc=(x + s * 0.12, y, h * 0.5), scale=(1.4, 0.4, 0.7), mat="M_Flat_leaf", subdiv=1)
        mb.cyl(0.24, 0.06, loc=(x, y - 0.04, h), rot=(70, 0, 0), mat="M_Flat_flower_yellow", verts=12)
        mb.cyl(0.12, 0.08, loc=(x, y - 0.06, h), rot=(70, 0, 0), mat="M_Flat_wood_dk", verts=10)
    mb.build("Sunflower_Patch", coll, smooth=True, sharp_angle=50)


@asset("Hedge_Wall_4m", "Foliage", footprint=4.0, tags=("bush", "hedge"))
def hedge_wall(coll):
    """4 m long clipped hedge along +X from the origin (stack/scale for longer walls); reads as one wall from any yaw.

    A tall well-rounded body with a crest of seven overlapping, slightly elongated lumps that stay inside the
    wall's width: side-on the top still undulates, end-on (running along the camera's view) it is one
    continuous rounded strip instead of a column of separate blobs."""
    r = core.rng("hedge", 1)
    mb = MeshBuilder()
    mb.box((4.0, 1.1, 1.36), loc=(2.0, 0, 0.68), mat="M_Bush", bevel=0.46, segs=4)
    n = 7
    for k in range(n):
        x = 0.4 + k * (3.2 / (n - 1))
        mb.sphere(r.uniform(0.46, 0.52), loc=(x, r.uniform(-0.03, 0.03), r.uniform(1.1, 1.2)), scale=(1.3, 1.06, 0.7),
                  mat="M_Bush", subdiv=2, lumpy=0.12, seed=k)
    mb.build("Hedge_Wall_4m", coll, smooth=True, sharp_angle=70)


@asset("Veg_Garden_Bed", "Foliage", footprint=4.0, tags=("farm",))
def veg_garden(coll):
    """Fenced vegetable bed (posts + blue rope + leafy crops), 4 x 2 m, centered."""
    r = core.rng("veg", 1)
    mb = MeshBuilder()
    mb.box((4.0, 2.0, 0.25), loc=(0, 0, 0.1), mat="M_Path_Dirt", bevel=0.08, segs=1)
    for i in range(4):
        for j in range(2):
            x = -1.4 + i * 0.93
            y = -0.5 + j * 1.0
            mb.sphere(0.28, loc=(x, y, 0.42), scale=(1.1, 1.1, 0.7), mat="M_Bush", subdiv=1, lumpy=0.2, seed=i + j)
            if (i + j) % 2:
                mb.sphere(0.12, loc=(x + 0.1, y - 0.1, 0.55), mat="M_Tomato", subdiv=1)
            else:
                mb.cyl(0.07, 0.3, loc=(x, y - 0.1, 0.3), mat="M_Flat_roof_orange", verts=6, r2=0.0, rot=(180, 0, 0))
    for (x, y) in ((-2.1, -1.1), (2.1, -1.1), (-2.1, 1.1), (2.1, 1.1), (0, -1.1), (0, 1.1)):
        mb.box((0.12, 0.12, 0.9), loc=(x, y, 0.45), mat="M_Wood")
    for y in (-1.1, 1.1):
        mb.box((4.2, 0.04, 0.05), loc=(0, y, 0.7), mat="M_Flat_roof_blue")
    for x in (-2.1, 2.1):
        mb.box((0.04, 2.2, 0.05), loc=(x, 0, 0.7), mat="M_Flat_roof_blue")
    mb.build("Veg_Garden_Bed", coll, smooth=True, sharp_angle=50)


@asset("Butterfly", "Foliage", footprint=0.2, tags=("flower",))
def butterfly(coll):
    """Hovering butterfly, big enough to read at map scale (0.35 m wings, 1.45 m up)."""
    mb = MeshBuilder()
    for s in (-1, 1):
        mb.sphere(0.17, loc=(s * 0.15, 0, 1.47), scale=(1.0, 0.18, 0.75), rot=(0, s * 25, 0),
                  mat="M_Flat_flower_yellow", subdiv=2)
        mb.sphere(0.11, loc=(s * 0.11, 0, 1.33), scale=(1.0, 0.18, 0.7), rot=(0, s * 35, 0),
                  mat="M_Flat_roof_orange", subdiv=1)
    mb.cyl(0.025, 0.24, loc=(0, 0, 1.3), mat="M_Eye_Black", verts=5)
    mb.build("Butterfly", coll, smooth=True)


# ---------------------------------------------------------------------------
# Public names for the shape helpers (for kit modules and maps that build their own variants)
# ---------------------------------------------------------------------------

birch = _birch
bush = _bush
flower_patch = _flower_patch
chunky_bloom = _chunky_bloom
fan = _fan
puffy_canopy = _puffy_canopy
