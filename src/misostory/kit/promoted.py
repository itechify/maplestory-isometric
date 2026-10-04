"""Assets promoted from the map modules: one canonical version of things several maps had defined locally.

Families:
* white-trunk birches in four leaf colours (teal, green, lime, red);
* flower clumps (iris, marigold), the clover carpet and the hovering butterflies;
* berry and strawberry bushes;
* town / farm props (rainbow spring, stone planter, planter box, bed);
* DANGER signs (one builder, four styles) and ivy-wrapped signposts;
* the tomato-capped barrel gate on the hidden path between the East Field and the Tomato Field;
* the round hill door of the Field <-> garden links (Hill_Door), the leafy walk-through arches
  (Arch_Leafy garden style, Arch_Leafy_Trail rustic style with the snail-shell board) and the clipped
  Hedge_Tunnel over a secret path.

The public helpers (``flower_clump``, ``bloom``, ``butterfly_model``, ``arc``, ``danger_sign``, ``ivy_sign``,
``arch_leafy``) let maps build their own local variants in the same style.
"""

import math

from .. import core
from ..geo import MeshBuilder
from . import asset
from .nature import birch


# ---------------------------------------------------------------------------
# White-trunk birches (classic midForest / grassySoil trees)
# ---------------------------------------------------------------------------

@asset("Tree_Birch_Teal", "Trees", footprint=2.6, tags=("tree",))
def tree_birch_teal(coll):
    """White-trunk birch with teal-green foliage (the classic 'midForest' teal tree)."""
    birch(coll, "Tree_Birch_Teal", 33, 5.0, 2.3, "M_Leaf_B")


@asset("Tree_Birch_Green", "Trees", footprint=2.6, tags=("tree",))
def tree_birch_green(coll):
    """White-trunk birch with fresh green foliage (classic grassySoil lawn trees)."""
    birch(coll, "Tree_Birch_Green", 41, 4.8, 2.3, "M_Leaf")


@asset("Tree_Birch_Lime", "Trees", footprint=2.6, tags=("tree",))
def tree_birch_lime(coll):
    """White-trunk birch, same green leaf as Tree_Birch_Green but shorter (4.4 m) with a smaller crown."""
    birch(coll, "Tree_Birch_Lime", 43, 4.4, 2.1, "M_Leaf")


@asset("Tree_Birch_Red", "Trees", footprint=2.6, tags=("tree",))
def tree_birch_red(coll):
    """White-trunk birch with a red-leaf crown (the red-leaf trees of the snail hunting grounds)."""
    birch(coll, "Tree_Birch_Red", 43, 4.3, 2.1, "M_Grad_rsnail_shell_dk__rsnail_shell")


# ---------------------------------------------------------------------------
# Flowers, clover and butterflies
# ---------------------------------------------------------------------------

def bloom(mb, x, y, h, petal_mat, petal_r=0.1, n=5, center="M_Flat_flower_yellow"):
    """One flower at (x, y): stem of height h, a side leaf, n petals around a centre."""
    mb.cyl(0.025, h, loc=(x, y, 0), mat="M_Flat_grass_side", verts=4)
    mb.sphere(0.09, loc=(x + 0.08, y, h * 0.45), scale=(1.6, 0.5, 0.6), mat="M_Flat_leaf", subdiv=1)
    for k in range(n):
        a = 2 * math.pi * k / n
        mb.sphere(petal_r, loc=(x + math.cos(a) * petal_r * 1.1, y + math.sin(a) * petal_r * 1.1, h),
                  scale=(1, 1, 0.45), mat=petal_mat, subdiv=1)
    mb.sphere(petal_r * 0.7, loc=(x, y, h + 0.03), mat=center, subdiv=1)


def flower_clump(coll, name, colors, n, radius, seed, h=(0.35, 0.6), petal_r=0.1, leaves_n=5):
    """Clump of n tall blooms (cycling through colors) over a few low leaf mounds, within radius.

    Builds ``name`` (leaves) and ``name + "_Flowers"``."""
    r = core.rng(name, seed)
    leaves = MeshBuilder()
    for _k in range(leaves_n):
        a = r.uniform(0, 2 * math.pi)
        d = radius * 0.6 * math.sqrt(r.random())
        leaves.sphere(0.2, loc=(math.cos(a) * d, math.sin(a) * d, 0.08), scale=(1.3, 1.0, 0.55), mat="M_Bush",
                      subdiv=1)
    leaves.build(name, coll, smooth=True, sharp_angle=60)
    mb = MeshBuilder()
    for k in range(n):
        a = r.uniform(0, 2 * math.pi)
        d = radius * math.sqrt(r.random())
        bloom(mb, math.cos(a) * d, math.sin(a) * d, r.uniform(*h), colors[k % len(colors)], petal_r=petal_r)
    mb.build(name + "_Flowers", coll, smooth=True, sharp_angle=60)


@asset("Iris_Patch", "Foliage", footprint=1.2, tags=("flower",))
def iris_patch(coll):
    """Purple iris clump (tall purple/blue blooms over leaf mounds)."""
    flower_clump(coll, "Iris_Patch", ["M_Flat_flower_purple", "M_Flat_roof_purple", "M_Flat_flower_blue"], 9, 0.5, 5,
                 h=(0.5, 0.85), petal_r=0.11)


@asset("Marigold_Patch", "Foliage", footprint=1.4, tags=("flower",))
def marigold_patch(coll):
    """Orange marigold clump (orange/yellow blooms over leaf mounds)."""
    flower_clump(coll, "Marigold_Patch", ["M_Flat_mush_orange", "M_Flat_roof_orange", "M_Flat_flower_yellow"], 11,
                 0.6, 3, h=(0.45, 0.8), petal_r=0.12)


@asset("Clover_Patch", "Foliage", footprint=1.2, tags=("flower",))
def clover_patch(coll):
    """Low clover carpet with round white/pink blossoms (grassySoil clover beds; 24 trefoils, ~580 tris)."""
    from .nature import fan
    r = core.rng("Clover_Patch", 2)
    mb = MeshBuilder()
    for _k in range(24):
        a = r.uniform(0, 2 * math.pi)
        d = 0.6 * math.sqrt(r.random())
        x, y = math.cos(a) * d, math.sin(a) * d
        # one trefoil = a single domed fan whose outline traces three round leaflets (r 0.075 m, centred
        # 0.07 m out, like the old sphere leaflets) with shallow notches between them (15 tris)
        base = r.uniform(0, 2 * math.pi)
        ring = []
        for j in range(3):
            b = base + j * 2.094 + r.uniform(-0.08, 0.08)
            for db, rr, z in ((-0.82, 0.103, 0.124), (-0.27, 0.14, 0.13), (0.27, 0.14, 0.13), (0.82, 0.103, 0.124),
                              (1.047, 0.062, 0.122)):
                ring.append((x + math.cos(b + db) * rr, y + math.sin(b + db) * rr, z))
        fan(mb, (x, y, 0.138), ring, "M_Flat_leaf")
    mb.build("Clover_Patch", coll, smooth=True, sharp_angle=60, recalc_normals=False)
    fl = MeshBuilder()
    for k in range(9):
        a = r.uniform(0, 2 * math.pi)
        d = 0.55 * math.sqrt(r.random())
        x, y = math.cos(a) * d, math.sin(a) * d
        h = r.uniform(0.22, 0.38)
        for dx, dy in ((0.018, 0.0), (0.0, 0.018)):  # stem: two crossed quads
            fl.quad((x - dx, y - dy, 0.0), (x + dx, y + dy, 0.0), (x + dx, y + dy, h), (x - dx, y - dy, h),
                    "M_Flat_grass_side")
        fl.sphere(0.085, loc=(x, y, h), mat="M_Flat_flower_pink" if k % 3 == 0 else "M_Flat_flower_white", subdiv=1)
    fl.build("Clover_Patch_Flowers", coll, smooth=True, sharp_angle=60, recalc_normals=False)


def butterfly_model(coll, name, wing, spot):
    """A butterfly with visible 0.35 m wings (wing / spot materials) hovering 1.45 m up."""
    mb = MeshBuilder()
    z = 1.45
    for s in (-1, 1):
        mb.sphere(0.17, loc=(s * 0.16, 0.0, z + 0.04), scale=(1.0, 0.18, 0.85), rot=(0, s * 25, s * 10), mat=wing,
                  subdiv=2)
        mb.sphere(0.11, loc=(s * 0.13, 0.02, z - 0.13), scale=(1.0, 0.18, 0.8), rot=(0, -s * 20, 0), mat=wing,
                  subdiv=1)
        mb.sphere(0.05, loc=(s * 0.19, -0.04, z + 0.06), scale=(1, 0.3, 1), mat=spot, subdiv=1)
    mb.cyl(0.03, 0.3, loc=(0, 0, z - 0.17), mat="M_Flat_hair_black", verts=6)
    for s in (-1, 1):
        mb.cyl(0.008, 0.16, loc=(s * 0.02, 0, z + 0.12), rot=(0, s * 25, 0), mat="M_Flat_hair_black", verts=4)
    mb.build(name, coll, smooth=True)


@asset("Butterfly_Yellow", "Foliage", footprint=0.4, tags=("flower",))
def butterfly_yellow(coll):
    """A visible (0.35 m) yellow butterfly with orange spots hovering 1.45 m up."""
    butterfly_model(coll, "Butterfly_Yellow", "M_Flat_flower_yellow", "M_Flat_mush_orange")


@asset("Butterfly_Pink", "Foliage", footprint=0.4, tags=("flower",))
def butterfly_pink(coll):
    """A visible (0.35 m) pink butterfly with white spots hovering 1.45 m up."""
    butterfly_model(coll, "Butterfly_Pink", "M_Flat_flower_pink", "M_Flat_flower_white")


# ---------------------------------------------------------------------------
# Bushes
# ---------------------------------------------------------------------------

@asset("Strawberry_Bush", "Foliage", footprint=1.0, tags=("bush",))
def strawberry_bush(coll):
    """Low leafy strawberry bush with red fruit and white blossoms (grassySoil nature)."""
    r = core.rng("Strawberry_Bush", 1)
    mb = MeshBuilder()
    for k in range(4):
        a = 2 * math.pi * k / 4 + r.uniform(-0.3, 0.3)
        mb.sphere(0.32, loc=(math.cos(a) * 0.25, math.sin(a) * 0.22, 0.28), scale=(1.1, 1.0, 0.8), mat="M_Bush",
                  subdiv=2, lumpy=0.12, seed=k)
    mb.sphere(0.36, loc=(0, 0, 0.42), scale=(1, 1, 0.85), mat="M_Bush", subdiv=2, lumpy=0.1, seed=9)
    mb.build("Strawberry_Bush", coll, smooth=True, sharp_angle=70)
    fr = MeshBuilder()
    for k in range(13):
        a = r.uniform(0, 2 * math.pi)
        el = r.uniform(0.1, 1.1)
        p = (math.cos(a) * 0.55 * math.cos(el), math.sin(a) * 0.5 * math.cos(el), 0.3 + math.sin(el) * 0.42)
        if k % 4 == 0:
            fr.sphere(0.06, loc=p, mat="M_Flat_flower_white", subdiv=1)
        else:
            fr.sphere(0.075, loc=p, scale=(1, 1, 1.25), mat="M_Flat_flower_red", subdiv=1)
    fr.build("Strawberry_Bush_Flowers", coll, smooth=True)


@asset("Berry_Bush", "Foliage", footprint=1.4, tags=("bush",))
def berry_bush(coll):
    """Round shrub hung with big red berries, most of them on its front-right (+X/-Y) side."""
    r = core.rng("Berry_Bush", 1)
    lobes = ((0, 0, 0.62), (-0.45, 0.1, 0.45), (0.45, 0.05, 0.48), (0.05, 0.25, 0.42))
    mb = MeshBuilder()
    for k, (x, y, rr) in enumerate(lobes):
        mb.sphere(rr, loc=(x, y, rr * 0.9), scale=(1, 1, 0.85), mat="M_Bush", subdiv=2, lumpy=0.12, seed=k)
    mb.build("Berry_Bush", coll, smooth=True, sharp_angle=70)

    def inside(px, py, pz):
        return any(((px - x) / rr) ** 2 + ((py - y) / rr) ** 2 + ((pz - rr * 0.9) / (rr * 0.85)) ** 2 < 1.0
                   for (x, y, rr) in lobes)

    # berries sit on the outer surface; 19 of 24 are on the +X/-Y side (turn that side to the camera)
    bb = MeshBuilder()
    for k in range(24):
        a = math.radians(r.uniform(-110, 40)) if k < 19 else r.uniform(0, 2 * math.pi)
        e = r.uniform(-0.25, 0.95)
        dx, dy, dz = math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)
        t = 0.1
        while inside(dx * t, 0.08 + dy * t, 0.5 + dz * t) and t < 1.5:
            t += 0.02
        bb.sphere(0.13, loc=(dx * (t - 0.04), 0.08 + dy * (t - 0.04), 0.5 + dz * (t - 0.04)),
                  mat="M_Flat_flower_red", subdiv=2)
    bb.build("Berry_Bush_Berries", coll, smooth=True)


# ---------------------------------------------------------------------------
# Town and farm props
# ---------------------------------------------------------------------------

def arc(mb, R, thick, depth, z0, mat, n=18, x0=0.0):
    """Half-circle band of radius R in the XZ plane (rainbow / arch), standing on z0, centred on x0."""
    for k in range(n):
        a0 = math.pi * k / n
        a1 = math.pi * (k + 1) / n
        am = (a0 + a1) / 2
        seg = 2 * R * math.sin((a1 - a0) / 2) + 0.03
        x = x0 + R * math.cos(am)
        z = z0 + R * math.sin(am)
        mb.box((seg, depth, thick), loc=(x, 0, z), rot=(0, -math.degrees(am) + 90, 0), mat=mat)


@asset("Rainbow_Spring", "Props", footprint=3.2, tags=("prop", "landmark"))
def rainbow_spring(coll):
    """Little rainbow arching over mushrooms and pebbles, cloud puffs at its feet (spans X, faces -Y)."""
    mb = MeshBuilder()
    cols = ["M_Flat_flower_red", "M_Flat_roof_orange", "M_Flat_flower_yellow", "M_Flat_roof_green",
            "M_Flat_flower_blue", "M_Flat_flower_purple"]
    for i, c in enumerate(cols):
        arc(mb, 1.45 - i * 0.13, 0.13, 0.22, 0.15, c, n=20)
    for x, s in ((-1.25, 1.0), (1.25, 0.9)):
        mb.sphere(0.42 * s, loc=(x, 0, 0.2), scale=(1.3, 1.1, 0.7), mat="M_Cloud", subdiv=2, lumpy=0.1, seed=3)
    for k, (x, y, r) in enumerate(((-0.5, 0.25, 0.22), (0.15, 0.35, 0.18), (0.6, 0.1, 0.25), (-0.1, -0.2, 0.16),
                                   (0.95, 0.45, 0.14), (-0.95, 0.45, 0.17))):
        mb.sphere(r, loc=(x, y, r * 0.5), scale=(1.2, 1.0, 0.7), mat="M_Rock", subdiv=1, lumpy=0.15, seed=k)
    for (x, y, h, cap) in ((-0.25, 0.0, 0.35, "M_Spot_mush_red__mush_spot"),
                           (0.3, -0.05, 0.28, "M_Spot_mush_orange__flower_yellow"),
                           (0.05, 0.3, 0.45, "M_Spot_mush_blue__mush_spot")):
        mb.cyl(0.07, h, loc=(x, y, 0), mat="M_MushStem", verts=8)
        mb.dome(0.2, 0.16, loc=(x, y, h), mat=cap, u=12, v=3, lip=0.04)
    mb.build("Rainbow_Spring", coll, smooth=True, sharp_angle=45)


@asset("Planter", "Props", footprint=2.2, tags=("prop", "town"))
def planter(coll):
    """Round cobblestone planter (2 m) with a flowering shrub (town squares)."""
    mb = MeshBuilder()
    mb.cyl(1.0, 0.5, mat="M_StoneWall", verts=20, r2=0.95)
    mb.cyl(1.06, 0.12, loc=(0, 0, 0.48), mat="M_StoneWall", verts=20)
    mb.cyl(0.86, 0.04, loc=(0, 0, 0.58), mat="M_Dirt_Cliff", verts=20)
    mb.sphere(0.62, loc=(0, 0.05, 0.82), scale=(1.25, 1.2, 0.85), mat="M_Bush", subdiv=2, lumpy=0.14, seed=4)
    cols = ["M_Flat_flower_pink", "M_Flat_flower_yellow", "M_Flat_flower_white", "M_Flat_flower_red",
            "M_Flat_flower_purple"]
    for k in range(11):
        a = 2 * math.pi * k / 11 + 0.4
        rr = 0.55 if k % 2 else 0.35
        z = 0.82 + 0.5 * math.sqrt(max(0.0, 1 - (rr / 0.78) ** 2))
        mb.sphere(0.1, loc=(math.cos(a) * rr * 1.2, math.sin(a) * rr * 1.15, z), mat=cols[k % len(cols)],
                  subdiv=1)
    mb.build("Planter", coll, smooth=True, sharp_angle=50)


@asset("Planter_Box", "Props", footprint=0.8, tags=("prop", "farm"))
def planter_box(coll):
    """Small square wooden planter box with a soil top, 0.42 m tall (stand a plant on it at z + 0.42)."""
    mb = MeshBuilder()
    mb.box((0.72, 0.72, 0.4), loc=(0, 0, 0.2), mat="M_Plank", bevel=0.03, segs=1)
    for s in (-1, 1):
        mb.box((0.78, 0.08, 0.08), loc=(0, s * 0.36, 0.4), mat="M_Wood_Dark")
        mb.box((0.08, 0.78, 0.08), loc=(s * 0.36, 0, 0.4), mat="M_Wood_Dark")
        mb.box((0.06, 0.74, 0.06), loc=(s * 0.33, 0, 0.12), mat="M_Wood_Dark")
    mb.box((0.62, 0.62, 0.04), loc=(0, 0, 0.41), mat="M_Flat_dirt_dk")
    mb.build("Planter_Box", coll, smooth=False)


@asset("Bed", "Props", footprint=2.6, tags=("interior",))
def bed(coll):
    """Orange wooden bed, two white pillows and a patchwork quilt; 2.5 x 1.4 m, length along +X, headboard at -X."""
    mb = MeshBuilder()
    L, W = 2.5, 1.4
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.14, 0.14, 0.45), loc=(sx * (L / 2 - 0.07), sy * (W / 2 - 0.07), 0.22), mat="M_Flat_roof_orange")
    mb.box((L, W, 0.22), loc=(0, 0, 0.42), mat="M_Flat_roof_orange", bevel=0.04, segs=1)
    mb.box((0.16, W + 0.08, 1.15), loc=(-L / 2, 0, 0.58), mat="M_Flat_roof_orange", bevel=0.05, segs=1)
    mb.cyl((W + 0.08) / 2, 0.16, loc=(-L / 2 - 0.08, 0, 1.15), rot=(0, 90, 0), mat="M_Flat_roof_orange", verts=16,
           scale=(0.55, 1, 1))
    mb.box((0.14, W + 0.06, 0.75), loc=(L / 2, 0, 0.42), mat="M_Flat_roof_orange", bevel=0.05, segs=1)
    mb.box((L - 0.2, W - 0.1, 0.22), loc=(0.02, 0, 0.62), mat="M_Cloth_White", bevel=0.08, segs=2)
    for k, x in enumerate((-0.25, 0.25, 0.75)):  # quilt patches
        for j, y in enumerate((-0.35, 0.0, 0.35)):
            mat = ("M_Flat_flower_yellow", "M_Flat_roof_red", "M_Flat_flower_pink")[(k + j) % 3]
            mb.box((0.5, 0.36, 0.06), loc=(x + 0.05, y, 0.75), mat=mat, bevel=0.02, segs=1)
    mb.box((0.25, W - 0.06, 0.08), loc=(-0.38, 0, 0.77), mat="M_Cloth_White", bevel=0.03, segs=1)
    for y in (-0.33, 0.33):
        mb.sphere(0.3, loc=(-0.85, y, 0.82), scale=(0.75, 1.0, 0.45), mat="M_Cloth_White", subdiv=2)
    mb.build("Bed", coll, smooth=True, sharp_angle=40)


# ---------------------------------------------------------------------------
# Signs: DANGER family and ivy-wrapped signposts
# ---------------------------------------------------------------------------

def _tri_sign_base(mb, h=1.15):
    mb.box((0.13, 0.13, h + 0.35), loc=(0, 0.02, (h + 0.35) / 2), mat="M_Wood", bevel=0.03, segs=1)
    mb.prism([(-0.62, 0.0), (0.62, 0.0), (0.0, 1.08)], -0.04, 0.04, loc=(0, -0.08, h), rot=(90, 0, 0),
             mat="M_Flat_cloth_red", bevel=0.03, segs=1)
    mb.prism([(-0.46, 0.1), (0.46, 0.1), (0.0, 0.9)], -0.03, 0.03, loc=(0, -0.13, h), rot=(90, 0, 0),
             mat="M_Flat_flower_yellow")


DANGER_STYLES = ("excl", "skull", "board", "diamond")


def danger_sign(coll, name, style):
    """Classic DANGER guide sign facing -Y, in one of DANGER_STYLES:

    excl: yellow triangle with a red rim and a black '!' on a post; skull: the same triangle with a skull
    and crossbones; board: two-post plank notice board with a red band and a big '!'; diamond: post with a
    yellow warning diamond, red '!' and a red plank."""
    mb = MeshBuilder()
    h = 1.15
    if style == "excl":
        _tri_sign_base(mb, h)
        mb.box((0.1, 0.04, 0.34), loc=(0, -0.17, h + 0.56), mat="M_Eye_Black", bevel=0.02, segs=1)
        mb.sphere(0.06, loc=(0, -0.17, h + 0.27), mat="M_Eye_Black", subdiv=1)
    elif style == "skull":
        _tri_sign_base(mb, h)
        for s in (-1, 1):
            mb.box((0.5, 0.03, 0.06), loc=(0, -0.17, h + 0.3), rot=(0, s * 35, 0), mat="M_Flat_cloth_white")
        mb.sphere(0.15, loc=(0, -0.18, h + 0.48), scale=(1.0, 0.45, 0.95), mat="M_Flat_cloth_white", subdiv=2)
        mb.box((0.16, 0.04, 0.08), loc=(0, -0.18, h + 0.34), mat="M_Flat_cloth_white")
        for s in (-1, 1):
            mb.sphere(0.04, loc=(s * 0.06, -0.24, h + 0.49), mat="M_Eye_Black", subdiv=1)
    elif style == "board":
        for x in (-0.7, 0.7):
            mb.box((0.16, 0.16, 1.8), loc=(x, 0, 0.9), mat="M_Wood", bevel=0.04, segs=1)
        mb.box((1.75, 0.12, 0.95), loc=(0, -0.1, 1.25), rot=(0, 3, 0), mat="M_Plank", bevel=0.05, segs=1)
        mb.box((1.6, 0.04, 0.22), loc=(0, -0.18, 1.56), rot=(0, 3, 0), mat="M_Flat_cloth_red")
        for k in range(4):
            mb.box((0.22, 0.03, 0.08), loc=(-0.55 + k * 0.37, -0.21, 1.56), rot=(0, 3, 0), mat="M_Flat_cloth_white")
        mb.box((0.11, 0.04, 0.32), loc=(0, -0.18, 1.2), mat="M_Eye_Black")
        mb.sphere(0.06, loc=(0, -0.18, 0.95), mat="M_Eye_Black", subdiv=1)
        mb.box((1.95, 0.24, 0.1), loc=(0, -0.05, 1.78), mat="M_Wood_Dark", bevel=0.03, segs=1)
    elif style == "diamond":
        mb.box((0.14, 0.14, 2.0), loc=(0, 0, 1.0), mat="M_Wood", bevel=0.03, segs=1)
        mb.box((1.05, 0.06, 1.05), loc=(0, 0.02, 1.62), rot=(0, 45, 0), mat="M_Wood_Dark", bevel=0.03, segs=1)
        mb.box((0.9, 0.08, 0.9), loc=(0, -0.03, 1.62), rot=(0, 45, 0), mat="M_Flat_roof_yellow", bevel=0.03, segs=1)
        mb.box((0.13, 0.05, 0.4), loc=(0, -0.09, 1.7), mat="M_Flat_cloth_red")
        mb.box((0.13, 0.05, 0.13), loc=(0, -0.09, 1.38), mat="M_Flat_cloth_red")
        mb.box((1.0, 0.08, 0.3), loc=(0, -0.05, 0.85), mat="M_Flat_cloth_red", bevel=0.03, segs=1)
        mb.box((0.8, 0.09, 0.07), loc=(0, -0.08, 0.85), mat="M_Flat_cloth_white")
    else:
        raise ValueError(f"danger_sign style must be one of {DANGER_STYLES}, got {style!r}")
    mb.build(name, coll, smooth=False)


@asset("Sign_Danger_Excl", "Architecture", footprint=1.2, tags=("sign",))
def sign_danger_excl(coll):
    """DANGER sign: yellow triangle with a red rim and a black '!' on a post (faces -Y)."""
    danger_sign(coll, "Sign_Danger_Excl", "excl")


@asset("Sign_Danger_Skull", "Architecture", footprint=1.2, tags=("sign",))
def sign_danger_skull(coll):
    """DANGER sign: yellow triangle with a red rim, skull and crossbones, on a post (faces -Y)."""
    danger_sign(coll, "Sign_Danger_Skull", "skull")


@asset("Sign_Danger_Board", "Architecture", footprint=1.8, tags=("sign",))
def sign_danger_board(coll):
    """DANGER notice board: two posts, plank board, red band and a big '!' (faces -Y)."""
    danger_sign(coll, "Sign_Danger_Board", "board")


@asset("Sign_Danger_Diamond", "Architecture", footprint=1.0, tags=("sign",))
def sign_danger_diamond(coll):
    """DANGER guide sign: post, yellow warning diamond with a red '!' and a red plank (faces -Y)."""
    danger_sign(coll, "Sign_Danger_Diamond", "diamond")


def _ivy_post(mb, h, seed):
    mb.box((0.18, 0.18, h), loc=(0, 0, h / 2), mat="M_Wood", bevel=0.04, segs=1)
    mb.cyl(0.3, 0.25, loc=(0, 0, -0.05), mat="M_Wood_Dark", verts=8, r2=0.2)
    for k in range(9):
        a = k * 1.9 + seed
        z = 0.2 + k * (h - 0.4) / 9
        mb.sphere(0.13, loc=(math.cos(a) * 0.13, math.sin(a) * 0.13, z), scale=(1.2, 0.7, 0.8), mat="M_Leaf",
                  subdiv=1)


def _arrow_board(mb, z, yaw, flip=False):
    pts = [(-0.55, -0.22), (0.4, -0.22), (0.72, 0.0), (0.4, 0.22), (-0.55, 0.22)]
    if flip:
        pts = [(-x, y) for x, y in pts]
    mb.prism(pts, -0.06, 0.06, loc=(0.0, -0.13, z), rot=(90, 0, yaw), mat="M_Plank", bevel=0.03, segs=1)


def ivy_sign(coll, name, post_h, boards, seed=1):
    """Wooden signpost of height post_h wrapped in ivy, with arrow boards [(z, yaw_deg, points_minus_x), ...]
    on its -Y face (an unflipped board points +X)."""
    mb = MeshBuilder()
    _ivy_post(mb, post_h, seed)
    for z, yaw, flip in boards:
        _arrow_board(mb, z, yaw, flip=flip)
    mb.build(name, coll, smooth=False)


@asset("Ivy_Sign", "Architecture", footprint=1.0, tags=("sign",))
def ivy_sign_1(coll):
    """Wooden signpost wrapped in ivy with one arrow board pointing +X (guide/midForest/wood)."""
    ivy_sign(coll, "Ivy_Sign", 2.1, [(1.65, 0, False)], seed=1)


@asset("Ivy_Sign_3Way", "Architecture", footprint=1.2, tags=("sign",))
def ivy_sign_3way(coll):
    """Taller ivy signpost with three arrow boards (+X, -X, +X)."""
    ivy_sign(coll, "Ivy_Sign_3Way", 2.5, [(2.1, 8, False), (1.62, -6, True), (1.15, 4, False)], seed=2)


# ---------------------------------------------------------------------------
# Landmarks
# ---------------------------------------------------------------------------

@asset("Tomato_Gate", "Architecture", footprint=6.0, tags=("landmark", "portal_door"))
def tomato_gate(coll):
    """Barrel gate capped with a giant ripe tomato (hidden path East Field <-> Tomato Field); opening faces -Y.

    Two barrel-banded posts (4.4 m apart, trails pass between them), a round barrel-door arch, open plank door
    leaves, a hanging tomato sign and a wide tomato cap with a leafy calyx."""
    mb = MeshBuilder()
    for s in (-1, 1):
        x = s * 2.65
        mb.cyl(0.56, 0.4, loc=(x, 0, -0.1), mat="M_StoneWall", verts=14, r2=0.5)
        mb.cyl(0.44, 3.2, loc=(x, 0, 0.25), mat="M_Wood", verts=14, r2=0.4)
        for zz in (0.75, 1.75, 2.75):
            mb.cyl(0.47, 0.13, loc=(x, 0, zz), mat="M_Wood_Dark", verts=14)
        # barrel-door leaf swung open against the post (plank disc segment)
        mb.box((0.12, 1.3, 2.0), loc=(x - s * 0.15, 0.95, 1.25), rot=(0, 0, s * 12), mat="M_Door", bevel=0.04,
               segs=1)
        for zz in (0.65, 1.25, 1.85):
            mb.box((0.15, 1.34, 0.08), loc=(x - s * 0.15, 0.95, zz), rot=(0, 0, s * 12), mat="M_Metal")
    # round barrel-door arch (lower half hidden in the ground)
    mb.torus(2.3, 0.2, loc=(0, -0.3, 1.1), rot=(90, 0, 0), mat="M_Wood_Dark", u=32, v=8)
    mb.torus(2.3, 0.09, loc=(0, -0.52, 1.1), rot=(90, 0, 0), mat="M_Metal", u=32, v=6)
    mb.box((6.0, 0.55, 0.42), loc=(0, 0, 3.5), mat="M_Wood_Dark", bevel=0.06, segs=1)
    # hanging sign with a tomato emblem
    for s in (-1, 1):
        mb.box((0.04, 0.04, 0.4), loc=(s * 0.55, -0.32, 3.15), mat="M_Rope")
    mb.box((1.5, 0.12, 0.62), loc=(0, -0.32, 2.75), mat="M_Plank", bevel=0.05, segs=1)
    mb.sphere(0.22, loc=(0, -0.43, 2.74), scale=(1.1, 0.6, 0.95), mat="M_Tomato", subdiv=2)
    mb.box((0.3, 0.04, 0.06), loc=(0, -0.5, 2.97), mat="M_Flat_tomato_leaf")
    mb.build("Tomato_Gate", coll, smooth=True, sharp_angle=40)
    # ripe-tomato cap (ties the gate to its destination; keeps it from reading as a giant mushroom)
    cap = MeshBuilder()
    cap.dome(3.15, 1.6, loc=(0, 0.1, 3.66), scale=(1.0, 0.56, 1.0), mat="M_Tomato", u=30, v=7, lip=0.35,
             profile=0.75)
    cap.build("Tomato_Gate_Cap", coll, smooth=True, sharp_angle=70)
    # calyx: a star of pointed leaves lying on the (nearly flat) crown of the cap, plus a stem
    leaf = MeshBuilder()
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        d = 0.62 if k % 2 else 0.55
        leaf.sphere(1.0, loc=(math.cos(a) * d, 0.1 + math.sin(a) * d * 0.7, 5.3),
                    scale=(0.68 if k % 2 else 0.58, 0.2, 0.06),
                    rot=(0, 0, math.degrees(math.atan2(math.sin(a) * 0.7, math.cos(a)))), mat="M_Flat_tomato_leaf",
                    subdiv=2)
    leaf.cyl(0.4, 0.1, loc=(0, 0.1, 5.24), mat="M_Flat_tomato_leaf", verts=10, r2=0.3)
    leaf.cyl(0.13, 0.6, loc=(0, 0.1, 5.25), mat="M_Flat_tomato_leaf", verts=8, r2=0.08)
    leaf.build("Tomato_Gate_Leaves", coll, smooth=True, sharp_angle=60)


# ---------------------------------------------------------------------------
# Garden doors, leafy arches and the hedge tunnel (promoted from 1000003/1000004, 1010000/1010002, 1020000)
# ---------------------------------------------------------------------------

@asset("Hill_Door", "Architecture", footprint=2.4, tags=("landmark", "portal_door"))
def hill_door(coll):
    """Round banded plank door set into a grassy hill face (grassySoil door/0). Faces -Y.

    The garden end of both Field <-> garden links (Mushroom Garden, Snail Garden) is drawn as this door.
    The origin sits on the ground at the face plane; the stone surround, dark frame and plank door are
    cylinders running from y=+0.5 (inside the hill) toward -y, the smaller ring protruding further, so the
    door seats into an uneven cliff face. The surround tops out at 1.84 m, under a 2 m hill's turf lip.
    """
    mb = MeshBuilder()
    zc, r = 0.84, 0.8
    mb.cyl(r + 0.2, 0.78, loc=(0, 0.5, zc), rot=(90, 0, 0), mat="M_StoneWall", verts=22)
    mb.cyl(r + 0.1, 0.84, loc=(0, 0.5, zc), rot=(90, 0, 0), mat="M_Wood_Dark", verts=22)
    mb.cyl(r, 0.88, loc=(0, 0.5, zc), rot=(90, 0, 0), mat="M_Door", verts=22)
    for k in range(-2, 3):  # plank seams
        h = 2 * math.sqrt(max(0.02, r * r - (k * 0.3) ** 2)) - 0.1
        mb.box((0.035, 0.04, h), loc=(k * 0.3, -0.395, zc), mat="M_Wood_Dark")
    for zz in (zc - 0.42, zc + 0.42):  # iron bands
        w = 2 * math.sqrt(max(0.05, r * r - (zz - zc) ** 2))
        mb.box((w, 0.06, 0.09), loc=(0, -0.41, zz), mat="M_Metal")
    mb.sphere(0.075, loc=(0.5, -0.45, zc - 0.05), mat="M_Gold", subdiv=1)
    mb.box((2.0, 0.8, 0.12), loc=(0, -0.42, 0.02), mat="M_StoneWall", bevel=0.04, segs=1)  # threshold slab
    mb.build("Hill_Door", coll, smooth=True, sharp_angle=40)


# Arch_Leafy styles. "garden": square timber posts on stone footings, a round wooden arc, 15 leaf lumps and a
# hanging board with a cut-out orange mushroom (the Amherst garden lane). "trail": log posts on rock footings,
# a flattened bent-branch arch, 13 lumps, vines twining down the posts and a board with a snail shell (the
# Townstreet trail-head toward the Snail Field of Flowers). The rng keys keep each style identical to the
# map-local arch it replaces.
ARCH_LEAFY_STYLES = {
    "garden": {"rng": ("x1010000_arch", 2), "posts": "timber", "arch": "round", "board": "mushroom",
               "vines": False, "lumps": 15, "lump_r": (0.3, 0.42), "lump_dy": 0.12, "lump_scale": (1.1, 0.9, 0.9),
               "lump_lumpy": 0.15, "lump_seed": 0, "lump_dz": 0.0, "z0": 2.1, "rise": 2.55,
               "flowers": ("M_Flat_flower_pink", "M_Flat_flower_yellow", "M_Flat_flower_white",
                           "M_Flat_roof_orange"),
               "flower_odd": 0, "flower_r": 0.1, "flower_out": (1.04, -0.36, 0.1)},
    "trail": {"rng": ("x1010002_arch", 3), "posts": "log", "arch": "branch", "board": "snail",
              "vines": True, "lumps": 13, "lump_r": (0.24, 0.34), "lump_dy": 0.1, "lump_scale": (1.15, 0.85, 0.85),
              "lump_lumpy": 0.18, "lump_seed": 20, "lump_dz": 0.05, "z0": 2.3, "rise": 1.6,
              "flowers": ("M_Flat_flower_pink", "M_Flat_flower_white", "M_Flat_flower_yellow",
                          "M_Flat_flower_purple"),
              "flower_odd": 1, "flower_r": 0.09, "flower_out": (1.03, -0.3, 0.12)},
}


def arch_leafy(coll, name, style="garden", **override):
    """Leafy walk-through arch spanning X (posts at +-2.55 m, about 4.4 m tall), facing -Y.

    ``style`` picks a preset from ARCH_LEAFY_STYLES; keyword overrides change single features, e.g.
    ``board="snail"`` puts the snail-shell board on the garden arch, ``vines=True`` adds post vines."""
    st = dict(ARCH_LEAFY_STYLES[style], **override)
    r = core.rng(*st["rng"])
    mb = MeshBuilder()
    for sx in (-2.55, 2.55):
        if st["posts"] == "timber":
            mb.cyl(0.36, 0.3, loc=(sx, 0, 0), mat="M_StoneWall", verts=10)
            mb.box((0.26, 0.26, 2.6), loc=(sx, 0, 1.55), mat="M_Wood_Dark", bevel=0.03, segs=1)
            mb.dome(0.42, 0.36, loc=(sx, 0, 2.86), mat="M_Spot_mush_orange__flower_yellow", u=12, v=3, lip=0.08)
        else:
            mb.cyl(0.42, 0.32, loc=(sx, 0, 0), mat="M_Rock", verts=9, r2=0.34)
            mb.cyl(0.2, 2.9, loc=(sx, 0, 0.2), mat="M_Bark", verts=9, r2=0.16)
            mb.dome(0.3, 0.26, loc=(sx, 0, 3.05), mat="M_Spot_mush_orange__flower_yellow", u=10, v=3, lip=0.06)
    z0, rise = st["z0"], st["rise"]
    if st["arch"] == "round":
        arc(mb, 2.55, 0.24, 0.3, z0, "M_Wood", n=16)
    else:  # a slightly flattened arch of bark (the bent branch)
        for k in range(14):
            a0, a1 = math.pi * k / 14, math.pi * (k + 1) / 14
            am = (a0 + a1) / 2
            seg = 2 * 2.55 * math.sin((a1 - a0) / 2) + 0.04
            x, z = 2.55 * math.cos(am), z0 + rise * math.sin(am)
            tang = math.degrees(math.atan2(rise * math.cos(am), -2.55 * math.sin(am)))
            mb.box((seg * (0.75 + 0.25 * abs(math.cos(am))), 0.2, 0.2), loc=(x, 0, z), rot=(0, -tang, 0),
                   mat="M_Bark")
    n = st["lumps"]
    cols = st["flowers"]
    fx, fy, fz = st["flower_out"]
    for k in range(n):
        a = math.pi * (k + 0.5) / n
        x, z = 2.55 * math.cos(a), z0 + rise * math.sin(a)
        mb.sphere(r.uniform(*st["lump_r"]), loc=(x, r.uniform(-st["lump_dy"], st["lump_dy"]), z + st["lump_dz"]),
                  scale=st["lump_scale"], mat="M_Bush", subdiv=2, lumpy=st["lump_lumpy"], seed=k + st["lump_seed"])
        if k % 2 == st["flower_odd"]:
            mb.sphere(st["flower_r"], loc=(x * fx, fy, z + fz), mat=cols[(k // 2) % len(cols)], subdiv=1)
    if st["vines"]:  # vines twining down the posts
        for sx in (-2.55, 2.55):
            for k in range(4):
                mb.sphere(0.2, loc=(sx + (0.12 if k % 2 else -0.1), -0.1, 2.6 - k * 0.55), scale=(1.0, 0.8, 1.1),
                          mat="M_Bush", subdiv=1, lumpy=0.15, seed=k + 40)
    if st["board"] == "mushroom":  # small hanging board under the apex (a cut-out orange mushroom)
        mb.box((0.04, 0.04, 0.45), loc=(-0.35, -0.05, 4.3), mat="M_Rope")
        mb.box((0.04, 0.04, 0.45), loc=(0.35, -0.05, 4.3), mat="M_Rope")
        mb.box((1.2, 0.1, 0.5), loc=(0, -0.05, 3.85), mat="M_Plank", bevel=0.04, segs=1)
        mb.dome(0.3, 0.2, loc=(0, -0.12, 3.85), rot=(90, 0, 0), mat="M_Flat_mush_orange", u=12, v=3)
    elif st["board"] == "snail":  # hanging board with a snail shell (the way to the Snail Field of Flowers)
        for sx in (-0.4, 0.4):
            mb.box((0.04, 0.04, 0.55), loc=(sx, -0.02, 3.55), mat="M_Rope")
        mb.box((1.3, 0.1, 0.52), loc=(0, -0.04, 3.1), mat="M_Plank", bevel=0.04, segs=1)
        mb.cyl(0.19, 0.08, loc=(-0.12, -0.1, 3.1), rot=(90, 0, 0), mat="M_Flat_snail_teal", verts=16)
        mb.cyl(0.1, 0.1, loc=(-0.12, -0.12, 3.1), rot=(90, 0, 0), mat="M_Flat_snail_teal_dk", verts=12)
        mb.box((0.42, 0.06, 0.1), loc=(0.2, -0.11, 2.97), mat="M_Flat_snail_slug")
    mb.build(name, coll, smooth=True, sharp_angle=40)


@asset("Arch_Leafy", "Architecture", footprint=5.6, tags=("landmark",))
def arch_leafy_garden(coll):
    """Leafy garden arch: timber posts, a round arc of leaf lumps and blossoms, orange-mushroom board (5.1 m span)."""
    arch_leafy(coll, "Arch_Leafy", "garden")


@asset("Arch_Leafy_Trail", "Architecture", footprint=5.8, tags=("landmark",))
def arch_leafy_trail(coll):
    """Rustic leafy trail-head arch: log posts, bent-branch arch with vines and blossoms, snail-shell board."""
    arch_leafy(coll, "Arch_Leafy_Trail", "trail")


@asset("Hedge_Tunnel", "Foliage", footprint=6.0, tags=("hedge", "landmark"))
def hedge_tunnel(coll):
    """Clipped hedge tunnel over a secret path (4.6 m clear corridor, >= 3 m clear at the centre, 1.7 m deep).

    Origin = mouth centre on the ground; the passage runs +Y and the mouth faces -Y. Two thick hedge walls under
    a leafy roof of three staggered rows of hedge lumps (round lumps in offset rows read as a hedge, not a ringed
    hoop, and the full-depth roof keeps the passage shaded so it reads as a tunnel). A few ripe tomatoes peep out
    of the mouth (the hidden path from the East Field to the Tomato Field). Set its back against a map edge.
    """
    r = core.rng("x1020000_tunnel", 2)
    hw, depth = 2.3, 1.7  # inner half width (4.6 m clear corridor), tunnel length
    mb = MeshBuilder()
    for s in (-1, 1):
        x = s * (hw + 0.6)
        mb.box((1.2, depth, 2.5), loc=(x, depth / 2, 1.25), mat="M_Bush", bevel=0.4, segs=3)
        for k in range(3):
            mb.sphere(r.uniform(0.5, 0.62), loc=(x + r.uniform(-0.12, 0.12), 0.3 + k * 0.55, 2.35 + r.uniform(0, 0.15)),
                      scale=(1.0, 1.0, 0.8), mat="M_Bush", subdiv=2, lumpy=0.12, seed=k + 4 * (s + 1))
    front = []
    # (the back row is smaller and sits at y ~1.0 so no lump reaches more than ~1.7 m behind the mouth)
    for row, (yy, n, rmax) in enumerate(((0.32, 9, 0.82), (0.72, 10, 0.82), (1.0, 9, 0.65))):
        for k in range(n):
            a = math.pi * min(1.0, max(0.0, (k + 0.5 * (row % 2) + r.uniform(-0.18, 0.18)) / (n - 1 + 0.5 * (row % 2))))
            rad = r.uniform(0.52 if row == 2 else 0.58, rmax)
            loc = (-math.cos(a) * (hw + 0.5 + r.uniform(-0.08, 0.14)), yy + r.uniform(-0.1, 0.1),
                   2.45 + math.sin(a) * 1.25 + r.uniform(-0.04, 0.12))
            mb.sphere(rad, loc=loc, scale=(1.0, 0.92, 0.82), mat="M_Bush", subdiv=2, lumpy=0.14,
                      seed=20 + row * 13 + k)
            if row == 0:
                front.append((loc, rad))
    mb.build("Hedge_Tunnel", coll, smooth=True, sharp_angle=70)
    # ripe tomatoes on the wall fronts and on the front faces of three roof lumps
    tm = MeshBuilder()
    for (x, z) in ((-2.75, 1.5), (2.55, 2.0)):
        tm.sphere(0.16, loc=(x, -0.08, z), scale=(1, 1, 0.85), mat="M_Tomato", subdiv=2)
    for idx, dz in ((1, 0.1), (5, 0.18), (7, -0.05)):
        (lx, ly, lz), rad = front[idx]
        tm.sphere(0.16, loc=(lx, ly - rad * 0.92 + 0.06, lz + dz), scale=(1, 1, 0.85), mat="M_Tomato", subdiv=2)
    tm.build("Hedge_Tunnel_Tomatoes", coll, smooth=True)
