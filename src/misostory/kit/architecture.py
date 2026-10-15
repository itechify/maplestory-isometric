"""Storybook architecture: mushroom houses, cottages, shops, docks, the ship."""

import math

from mathutils import Vector

from .. import core
from ..geo import MeshBuilder
from . import asset


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

def gable_roof(mb, w, d, h, loc, mat, overhang=0.45, thickness=0.28, gable_mat="M_Plaster", ridge_mat=None):
    """Chunky gable roof, ridge along X. loc = center of the roof base (eave height)."""
    x, y, z = loc
    half = d / 2 + overhang
    slope_len = math.sqrt(half ** 2 + h ** 2)
    ang = math.degrees(math.atan2(h, half))
    for s in (-1, 1):
        cy = y + s * half / 2
        cz = z + h / 2
        mb.box((w + overhang * 2, slope_len + 0.1, thickness), loc=(x, cy, cz + thickness * 0.35),
               rot=(s * -ang, 0, 0), mat=mat, bevel=0.08, segs=2)
    # gable triangles (front/back of the ridge axis = X ends)
    for s in (-1, 1):
        xx = x + s * (w / 2 - 0.02)
        mb.tri((xx, y - d / 2, z), (xx, y + d / 2, z), (xx, y, z + h * 0.92), gable_mat)
    if ridge_mat:
        mb.box((w + overhang * 2 + 0.1, 0.32, 0.26), loc=(x, y, z + h + 0.12), mat=ridge_mat, bevel=0.08)


_FACE_YAW = {"-Y": 0.0, "+X": 90.0, "+Y": 180.0, "-X": -90.0}


def _face_frame(loc, face):
    """Transform for parts authored in a -Y-facing frame (dx along the wall, dy < 0 = outward)."""
    yaw = _FACE_YAW.get(face, 0.0)
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    x, y, z = loc

    def P(dx, dy, dz=0.0):
        return (x + dx * c - dy * s, y + dx * s + dy * c, z + dz)

    return P, yaw


def window(mb, loc, face="-Y", w=0.9, h=1.0, frame_mat="M_Wood_Dark", shutter_mat=None, flowerbox=False):
    """Framed window on a wall facing `face` (-Y, +X, +Y or -X)."""
    P, yaw = _face_frame(loc, face)
    r = (0, 0, yaw)
    mb.box((w + 0.22, 0.14, h + 0.22), loc=P(0, -0.03), rot=r, mat=frame_mat, bevel=0.04, segs=1)
    mb.box((w, 0.16, h), loc=P(0, -0.06), rot=r, mat="M_Window")
    mb.box((0.07, 0.2, h), loc=P(0, -0.08), rot=r, mat=frame_mat)
    mb.box((w, 0.2, 0.07), loc=P(0, -0.08), rot=r, mat=frame_mat)
    if shutter_mat:
        for sd in (-1, 1):
            mb.box((w * 0.45, 0.08, h + 0.1), loc=P(sd * (w * 0.75 + 0.1), -0.08), rot=r, mat=shutter_mat,
                   bevel=0.03, segs=1)
    if flowerbox:
        mb.box((w + 0.3, 0.3, 0.22), loc=P(0, -0.18, -h / 2 - 0.16), rot=r, mat="M_Wood", bevel=0.04, segs=1)
        for k in range(4):
            mb.sphere(0.11, loc=P(-w / 2 + 0.05 + k * (w / 3), -0.2, -h / 2 - 0.02),
                      mat="M_Flat_flower_pink" if k % 2 else "M_Flat_flower_red", subdiv=1)


def door(mb, loc, face="-Y", w=1.1, h=2.0, mat="M_Door", frame="M_Wood_Dark", arch=True):
    """Plank door with frame, optional round arch and a stone step, on a wall facing `face`."""
    P, yaw = _face_frame(loc, face)
    r = (0, 0, yaw)
    mb.box((w + 0.3, 0.16, h + 0.2), loc=P(0, -0.02, h / 2 + 0.05), rot=r, mat=frame, bevel=0.05, segs=1)
    mb.box((w, 0.2, h), loc=P(0, -0.06, h / 2), rot=r, mat=mat, bevel=0.03, segs=1)
    if arch:
        mb.cyl(w / 2, 0.2, loc=P(0, -0.16, h), rot=(-90, 0, yaw), mat=mat, verts=12)
        mb.cyl(w / 2 + 0.15, 0.16, loc=P(0, -0.1, h), rot=(-90, 0, yaw), mat=frame, verts=12)
    mb.sphere(0.07, loc=P(w * 0.3, -0.2, h * 0.48), mat="M_Gold", subdiv=1)
    mb.box((w + 0.6, 0.6, 0.18), loc=P(0, -0.3, 0.06), rot=r, mat="M_StoneWall", bevel=0.05, segs=1)


def chimney(mb, loc, h=1.6, mat="M_StoneWall"):
    x, y, z = loc
    mb.box((0.6, 0.6, h), loc=(x, y, z + h / 2), mat=mat, bevel=0.05, segs=1)
    mb.box((0.78, 0.78, 0.2), loc=(x, y, z + h), mat=mat, bevel=0.05, segs=1)


# ---------------------------------------------------------------------------
# Mushroom houses (Maple Road / Mushroom Town identity)
# ---------------------------------------------------------------------------

def _mushroom_house(coll, name, cap_mat, stem_r=2.0, stem_h=3.2, cap_r=3.6, cap_h=2.6, seed=0):
    mb = MeshBuilder()
    mb.cyl(stem_r * 1.08, stem_h, mat="M_MushStem", verts=20, r2=stem_r * 0.94)
    mb.cyl(stem_r * 1.25, 0.35, loc=(0, 0, -0.05), mat="M_StoneWall", verts=20, r2=stem_r * 1.12)
    front = -stem_r * 0.98
    door(mb, (0, front + 0.05, 0.25), w=1.0, h=1.8)
    # round windows
    for xx, zz in ((-1.15, 2.15), (1.2, 2.25)):
        ang = math.asin(max(-1, min(1, xx / stem_r)))
        yy = -math.cos(ang) * stem_r * 0.97
        mb.cyl(0.42, 0.2, loc=(xx, yy + 0.02, zz), rot=(90, 0, -math.degrees(ang)), mat="M_Wood_Dark", verts=14)
        mb.cyl(0.32, 0.24, loc=(xx, yy + 0.0, zz), rot=(90, 0, -math.degrees(ang)), mat="M_Window", verts=14)
    side = -stem_r * 0.97
    mb.cyl(0.38, 0.2, loc=(side + 0.02, 0.4, 2.0), rot=(0, -90, 0), mat="M_Wood_Dark", verts=14)
    mb.cyl(0.28, 0.24, loc=(side, 0.4, 2.0), rot=(0, -90, 0), mat="M_Window", verts=14)
    mb.build(name + "_Stem", coll, smooth=True, sharp_angle=40)
    cap = MeshBuilder()
    cap.dome(cap_r, cap_h, loc=(0, 0, stem_h - 0.15), mat=cap_mat, u=28, v=8, lip=0.45, profile=0.75)
    # little chimney poking out of the cap
    chimney(cap, (cap_r * 0.35, cap_r * 0.25, stem_h + cap_h * 0.55), h=1.2, mat="M_StoneWall")
    cap.build(name + "_Cap", coll, smooth=True, sharp_angle=70)


@asset("House_Mushroom_Orange", "Architecture", footprint=7.5, tags=("house", "mushroom"))
def house_mush_orange(coll):
    _mushroom_house(coll, "House_Mushroom_Orange", "M_Spot_mush_orange__mush_spot")


@asset("House_Mushroom_Red", "Architecture", footprint=7.5, tags=("house", "mushroom"))
def house_mush_red(coll):
    _mushroom_house(coll, "House_Mushroom_Red", "M_Spot_mush_red__mush_spot", stem_r=1.8, stem_h=2.9, cap_r=3.3,
                    cap_h=2.9)


@asset("House_Mushroom_Blue", "Architecture", footprint=7.5, tags=("house", "mushroom"))
def house_mush_blue(coll):
    _mushroom_house(coll, "House_Mushroom_Blue", "M_Spot_mush_blue__mush_spot", stem_r=2.1, stem_h=3.4, cap_r=3.8,
                    cap_h=2.3)


@asset("House_Mushroom_Yellow", "Architecture", footprint=7.0, tags=("house", "mushroom"))
def house_mush_yellow(coll):
    _mushroom_house(coll, "House_Mushroom_Yellow", "M_Spot_mush_yellow__mush_spot", stem_r=1.7, stem_h=2.8,
                    cap_r=3.0, cap_h=2.4)


# ---------------------------------------------------------------------------
# Cottages / shops (Amherst & Southperry)
# ---------------------------------------------------------------------------

def _cottage(coll, name, w=6.0, d=4.8, wall_h=3.0, roof_mat="M_Flat_roof_red", wall_mat="M_Plaster",
             base_mat="M_StoneWall", shutter="M_Flat_roof_green", roof_h=2.4, two_story=False, sign=None):
    mb = MeshBuilder()
    mb.box((w + 0.4, d + 0.4, 0.7), loc=(0, 0, 0.3), mat=base_mat, bevel=0.1)
    total_h = wall_h * (2 if two_story else 1)
    mb.box((w, d, total_h), loc=(0, 0, 0.6 + total_h / 2), mat=wall_mat, bevel=0.06)
    # timber framing
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.28, 0.28, total_h + 0.1), loc=(sx * (w / 2 - 0.05), sy * (d / 2 - 0.05), 0.6 + total_h / 2),
                   mat="M_Wood_Dark", bevel=0.04, segs=1)
    mb.box((w + 0.1, 0.22, 0.24), loc=(0, -d / 2 - 0.02, 0.6 + total_h - 0.1), mat="M_Wood_Dark", bevel=0.03)
    if two_story:
        mb.box((w + 0.1, 0.22, 0.22), loc=(0, -d / 2 - 0.02, 0.6 + wall_h), mat="M_Wood_Dark", bevel=0.03)
    front = -d / 2
    door(mb, (-w * 0.18, front, 0.6), w=1.15, h=2.0)
    window(mb, (w * 0.22, front, 0.6 + 1.55), w=1.0, h=0.95, shutter_mat=shutter, flowerbox=True)
    window(mb, (-w / 2, d * 0.1, 0.6 + 1.6), face="-X", w=0.95, h=0.95, shutter_mat=shutter)
    if two_story:
        for xx in (-w * 0.22, w * 0.22):
            window(mb, (xx, front, 0.6 + wall_h + 1.4), w=0.9, h=0.9, shutter_mat=shutter)
    roof_z = 0.6 + total_h
    gable_roof(mb, w, d, roof_h, (0, 0, roof_z), roof_mat, gable_mat=wall_mat)
    chimney(mb, (w * 0.28, d * 0.18, roof_z + roof_h * 0.35), h=1.5)
    if sign:
        _shop_sign(mb, sign, (w * 0.05, front - 0.25, 0.6 + 2.45))
    mb.build(name, coll, smooth=True, sharp_angle=35)


def _shop_sign(mb, kind, loc):
    """Hanging shop sign with a simple icon (sword / shield / potion / bag)."""
    x, y, z = loc
    mb.box((0.08, 0.9, 0.08), loc=(x, y + 0.2, z + 0.6), mat="M_Wood_Dark")
    mb.box((1.3, 0.12, 0.85), loc=(x, y - 0.25, z + 0.1), mat="M_Plank", bevel=0.05, segs=1)
    yy = y - 0.33
    if kind == "weapon":
        mb.box((0.12, 0.06, 0.6), loc=(x, yy, z + 0.18), mat="M_Metal")
        mb.box((0.4, 0.07, 0.08), loc=(x, yy, z - 0.12), mat="M_Gold")
        mb.box((0.08, 0.07, 0.18), loc=(x, yy, z - 0.24), mat="M_Wood_Dark")
    elif kind == "armor":
        mb.cyl(0.32, 0.06, loc=(x, yy + 0.03, z + 0.1), rot=(90, 0, 0), mat="M_Flat_roof_blue", verts=6)
        mb.cyl(0.12, 0.08, loc=(x, yy, z + 0.1), rot=(90, 0, 0), mat="M_Gold", verts=8)
    elif kind == "potion":
        mb.sphere(0.24, loc=(x, yy, z + 0.02), mat="M_Glow_roof_red", subdiv=2)
        mb.cyl(0.08, 0.2, loc=(x, yy, z + 0.2), mat="M_Cloth_White", verts=8)
    elif kind == "general":
        mb.sphere(0.26, loc=(x, yy, z + 0.05), scale=(1, 0.5, 0.9), mat="M_Flat_wood_lt", subdiv=2)
        mb.torus(0.12, 0.03, loc=(x, yy, z + 0.3), rot=(90, 0, 0), mat="M_Rope")


shop_sign = _shop_sign  # public name for map modules


@asset("House_Cottage_Red", "Architecture", footprint=7.0, tags=("house",))
def cottage_red(coll):
    _cottage(coll, "House_Cottage_Red", roof_mat="M_Flat_roof_red")


@asset("House_Cottage_Blue", "Architecture", footprint=7.0, tags=("house",))
def cottage_blue(coll):
    _cottage(coll, "House_Cottage_Blue", w=5.4, d=4.6, roof_mat="M_Flat_roof_blue", shutter="M_Flat_roof_yellow")


@asset("House_Cottage_Green", "Architecture", footprint=7.0, tags=("house",))
def cottage_green(coll):
    _cottage(coll, "House_Cottage_Green", w=6.4, d=5.0, roof_mat="M_Flat_roof_green", shutter="M_Flat_roof_red",
             roof_h=2.8)


@asset("House_Cottage_Purple_2F", "Architecture", footprint=8.0, tags=("house",))
def cottage_purple(coll):
    _cottage(coll, "House_Cottage_Purple_2F", w=6.0, d=5.2, roof_mat="M_Flat_roof_purple", two_story=True,
             shutter="M_Flat_roof_teal", roof_h=2.6)


@asset("Shop_Weapon", "Architecture", footprint=8.0, tags=("house", "shop"))
def shop_weapon(coll):
    _cottage(coll, "Shop_Weapon", w=7.0, d=5.4, roof_mat="M_Flat_roof_blue", shutter="M_Flat_wood_dk",
             sign="weapon", roof_h=2.7)


@asset("Shop_Department", "Architecture", footprint=9.0, tags=("house", "shop"))
def shop_department(coll):
    _cottage(coll, "Shop_Department", w=8.4, d=6.0, roof_mat="M_Flat_roof_orange", two_story=True,
             shutter="M_Flat_roof_green", sign="general", roof_h=3.0)


@asset("Shop_Armor", "Architecture", footprint=8.0, tags=("house", "shop"))
def shop_armor(coll):
    _cottage(coll, "Shop_Armor", w=7.0, d=5.4, roof_mat="M_Flat_roof_teal", wall_mat="M_StoneWall",
             base_mat="M_Sand_Cliff", shutter="M_Flat_roof_blue", sign="armor", roof_h=2.6)


@asset("House_Stone_Port", "Architecture", footprint=7.0, tags=("house", "port"))
def house_stone_port(coll):
    _cottage(coll, "House_Stone_Port", w=5.8, d=4.6, roof_mat="M_Flat_roof_teal", wall_mat="M_Sand_Cliff",
             base_mat="M_StoneWall", shutter="M_Flat_roof_blue", roof_h=2.2)


@asset("House_Stone_Port_2F", "Architecture", footprint=8.0, tags=("house", "port"))
def house_stone_port_2f(coll):
    _cottage(coll, "House_Stone_Port_2F", w=6.4, d=5.0, roof_mat="M_Flat_roof_blue", wall_mat="M_Plaster",
             base_mat="M_Sand_Cliff", shutter="M_Flat_roof_teal", two_story=True, roof_h=2.4)


# ---------------------------------------------------------------------------
# Fences, signs, walkways
# ---------------------------------------------------------------------------

# pack (#74): the pack fence is centred on its origin; m.fence and the trails scale a segment (L/n/2, 1, 1) from
# its origin, so it keeps the kit frame (0..2 m along +X)
@asset("Fence_Wood_Seg", "Architecture", footprint=2.0, tags=("fence",), pack=dict(align_xy="kit"))
def fence_seg(coll):
    """2 m fence segment along +X starting at origin."""
    mb = MeshBuilder()
    for x in (0.0, 2.0):
        mb.box((0.2, 0.2, 1.1), loc=(x, 0, 0.55), mat="M_Wood", bevel=0.04, segs=1)
        mb.cyl(0.14, 0.14, loc=(x, 0, 1.08), mat="M_Wood", verts=4, r2=0.02)
    for z in (0.45, 0.85):
        mb.box((2.1, 0.1, 0.16), loc=(1.0, 0, z), mat="M_Plank", bevel=0.03, segs=1)
    mb.build("Fence_Wood_Seg", coll, smooth=False)


@asset("Fence_Picket_Seg", "Architecture", footprint=2.0, tags=("fence",), pack=dict(align_xy="kit"))
def fence_picket(coll):
    mb = MeshBuilder()
    for i in range(7):
        x = i * 2.0 / 6
        mb.box((0.16, 0.08, 0.9), loc=(x, 0, 0.45), mat="M_Flat_cloth_white", bevel=0.03, segs=1)
        mb.cyl(0.11, 0.18, loc=(x, 0, 0.9), mat="M_Flat_cloth_white", verts=4, r2=0.01, rot=(0, 0, 45))
    mb.box((2.1, 0.06, 0.1), loc=(1.0, 0.06, 0.6), mat="M_Flat_cloth_white")
    mb.box((2.1, 0.06, 0.1), loc=(1.0, 0.06, 0.25), mat="M_Flat_cloth_white")
    mb.build("Fence_Picket_Seg", coll, smooth=False)


@asset("Sign_Arrow", "Architecture", footprint=0.8, tags=("sign",))
def sign_arrow(coll):
    """Wooden direction sign; arrow points +X."""
    mb = MeshBuilder()
    mb.box((0.18, 0.18, 2.0), loc=(0, 0, 1.0), mat="M_Wood", bevel=0.04, segs=1)
    mb.prism([(-0.6, -0.28), (0.45, -0.28), (0.8, 0.0), (0.45, 0.28), (-0.6, 0.28)], -0.07, 0.07,
             loc=(0.25, -0.12, 1.55), rot=(90, 0, 0), mat="M_Plank", bevel=0.03, segs=1)
    mb.build("Sign_Arrow", coll, smooth=False)


@asset("Sign_Board", "Architecture", footprint=1.6, tags=("sign",))
def sign_board(coll):
    """Two-post notice / map-name board facing -Y."""
    mb = MeshBuilder()
    for x in (-0.75, 0.75):
        mb.box((0.18, 0.18, 1.9), loc=(x, 0, 0.95), mat="M_Wood", bevel=0.04, segs=1)
    mb.box((1.9, 0.14, 0.9), loc=(0, -0.1, 1.35), mat="M_Plank", bevel=0.06, segs=2)
    mb.box((2.1, 0.3, 0.12), loc=(0, -0.05, 1.86), mat="M_Wood_Dark", bevel=0.04, segs=1)
    for k in range(3):
        mb.box((1.3 - k * 0.25, 0.04, 0.08), loc=(-0.05, -0.18, 1.55 - k * 0.2), mat="M_Wood_Dark")
    mb.build("Sign_Board", coll, smooth=False)


@asset("Ladder_2m", "Architecture", footprint=0.8, tags=("ladder",))
def ladder_2m(coll):
    """2 m modular ladder unit (stack along Z). Rails along Z, rungs along X, leans on +Y wall."""
    mb = MeshBuilder()
    for x in (-0.38, 0.38):
        mb.box((0.12, 0.12, 2.02), loc=(x, 0, 1.0), mat="M_Wood", bevel=0.03, segs=1)
    for k in range(5):
        mb.cyl(0.05, 0.76, loc=(-0.38, 0, 0.2 + k * 0.4), rot=(0, 90, 0), mat="M_Wood_Dark", verts=6)
    mb.build("Ladder_2m", coll, smooth=False)


@asset("Dock_Pier_4m", "Architecture", footprint=4.0, tags=("dock",))
def dock_pier(coll):
    """4 m x 3 m pier section along +X; deck top at z=0, posts down to -3."""
    mb = MeshBuilder()
    for i in range(9):
        x = i * 4.0 / 9 + 0.22
        mb.box((0.42, 3.1, 0.18), loc=(x, 0, -0.09), mat="M_Plank", bevel=0.03, segs=1)
    for x in (0.2, 3.8):
        for y in (-1.45, 1.45):
            mb.cyl(0.2, 4.0, loc=(x, y, -3.4), mat="M_Wood_Dark", verts=8)
    mb.box((4.0, 0.2, 0.25), loc=(2.0, -1.5, -0.3), mat="M_Wood_Dark")
    mb.box((4.0, 0.2, 0.25), loc=(2.0, 1.5, -0.3), mat="M_Wood_Dark")
    mb.build("Dock_Pier_4m", coll, smooth=False)


@asset("Dock_Bollard", "Architecture", footprint=0.6, tags=("dock",))
def dock_bollard(coll):
    mb = MeshBuilder()
    mb.cyl(0.22, 0.7, mat="M_Wood_Dark", verts=10)
    mb.torus(0.22, 0.06, loc=(0, 0, 0.45), mat="M_Rope", u=12, v=5)
    mb.build("Dock_Bollard", coll, smooth=True)


@asset("Ship_Southperry", "Architecture", footprint=26.0, tags=("ship", "landmark"))
def ship_southperry(coll):
    """Chunky three-masted ship moored at Southperry (bow toward +X). Waterline at z=0."""
    hull = MeshBuilder()
    L, W = 22.0, 6.4
    # hull as stacked tapered slices
    prof = []
    for i in range(13):
        t = i / 12
        x = -L / 2 + t * L
        wf = math.sin(math.pi * min(1.0, t * 1.15 + 0.08)) ** 0.6
        prof.append((x, max(0.25, W / 2 * wf)))
    bm = hull.bm
    rings = []
    for x, hw in prof:
        ring = []
        for (yy, zz) in ((-hw, 3.0), (-hw * 0.92, 1.0), (-hw * 0.55, -1.2), (0, -1.8), (hw * 0.55, -1.2),
                         (hw * 0.92, 1.0), (hw, 3.0)):
            ring.append(bm.verts.new((x, yy, zz + (0.9 if x > L * 0.3 else 0) + (0.7 if x < -L * 0.32 else 0))))
        rings.append(ring)
    hi = hull.mat("M_Wood_Dark")
    for i in range(len(rings) - 1):
        for j in range(len(rings[i]) - 1):
            f = bm.faces.new((rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1]))
            f.material_index = hi
    for ring, rev in ((rings[0], True), (rings[-1], False)):
        f = bm.faces.new(list(reversed(ring)) if rev else ring)
        f.material_index = hi
    # deck
    deck_pts = [(x, -hw * 0.95) for x, hw in prof] + [(x, hw * 0.95) for x, hw in reversed(prof)]
    hull.prism(deck_pts, 2.55, 2.75, mat="M_Plank")
    # stripe & rails
    for s in (-1, 1):
        hull.box((L * 0.86, 0.2, 0.35), loc=(0, s * (W / 2 - 0.05), 2.2), mat="M_Gold", bevel=0.05)
    # cabin at stern
    hull.box((4.2, W * 0.7, 2.2), loc=(-L / 2 + 3.2, 0, 3.6 + 0.7), mat="M_Wood", bevel=0.12)
    hull.box((4.6, W * 0.78, 0.3), loc=(-L / 2 + 3.2, 0, 4.85 + 0.7), mat="M_Wood_Dark", bevel=0.08)
    for yy in (-W * 0.36,):
        for xx in (-L / 2 + 2.4, -L / 2 + 4.0):
            hull.box((0.7, 0.12, 0.6), loc=(xx, yy, 4.0 + 0.7), mat="M_Window")
    # bowsprit
    hull.cyl(0.2, 6.0, loc=(L / 2 - 0.5, 0, 3.6), rot=(0, 72, 0), mat="M_Wood", verts=8, r2=0.1)
    hull.build("Ship_Southperry_Hull", coll, smooth=True, sharp_angle=40)
    rig = MeshBuilder()
    for mx, mh in ((-3.5, 15.0), (2.5, 17.5), (7.5, 13.0)):
        rig.cyl(0.28, mh, loc=(mx, 0, 2.6), mat="M_Wood", verts=10, r2=0.18)
        for k, (yz, yw) in enumerate(((0.45, 6.2), (0.72, 4.8))):
            z = 2.6 + mh * yz
            rig.cyl(0.12, yw, loc=(mx, -yw / 2, z), rot=(-90, 0, 0), mat="M_Wood", verts=6)
        rig.cyl(0.4, 0.4, loc=(mx, 0, 2.6 + mh * 0.82), mat="M_Wood_Dark", verts=10)
    rig.build("Ship_Southperry_Masts", coll, smooth=True, sharp_angle=45)
    sails = MeshBuilder()
    for mx, mh in ((-3.5, 15.0), (2.5, 17.5), (7.5, 13.0)):
        for (z0, z1, w0, w1) in ((0.47, 0.70, 5.6, 4.6), (0.74, 0.92, 4.2, 3.0)):
            za, zb = 2.6 + mh * z0, 2.6 + mh * z1
            bm2 = sails.bm
            cols = 6
            rows = 4
            grid = []
            for rr in range(rows + 1):
                tz = rr / rows
                z = za + (zb - za) * tz
                w = w0 + (w1 - w0) * tz
                row = []
                for c in range(cols + 1):
                    ty = c / cols
                    y = -w / 2 + w * ty
                    billow = math.sin(math.pi * ty) * math.sin(math.pi * tz) * 0.9
                    row.append(bm2.verts.new((mx + 0.45 + billow, y, z)))
                grid.append(row)
            si = sails.mat("M_Cloth_White")
            for rr in range(rows):
                for c in range(cols):
                    f = bm2.faces.new((grid[rr][c], grid[rr][c + 1], grid[rr + 1][c + 1], grid[rr + 1][c]))
                    f.material_index = si
    # flag
    sails.quad((2.5, 0, 20.0), (2.5, 0, 21.0), (4.3, 0, 20.7), (4.3, 0, 20.1), "M_Cloth_Red")
    sails.build("Ship_Southperry_Sails", coll, smooth=True, sharp_angle=60, recalc_normals=False)
