"""Amherst Department Store (1010003) - "Lucy's general store, potions first".

Classic (GMS v8) structure, from docs/research/maps/1010003_AmherstDepartmentStore_1010003.md:
  one 800 x 600 room in the same shell as the Weapon Store: plank floor, timber-frame back wall,
  lashed roof beams, a stone-and-wood pillar at the far left. Lucy sells from the WELCOME booth
  (orange arch sign, cream banner with a money-bag emblem, a pinned note) on the west side.
  Centre-left: two stacked crates, a low bench of books, a book table, a small shelf and a wall
  shelf of red and blue potions (a hop-staircase). Centre-right: a tall post with plank shelves
  and lidded jars (a 7-board climb), a parchment poster, a wall shelf with a red-and-gold
  treasure chest, and a ceiling crossbeam joining the two stacks overhead. Exit out00 at the
  right end, in front of the arched "Thank you" door.

3D translation: the shared shop shell (kit.interior) as a warm timber-framed general store. The
WELCOME booth stands against the west wall facing into the room; the left stack climbs from two
crates over the book table and a cabinet onto three stepped potion boards along the back wall;
the pole shelf becomes a solid spiral stair of seven treads wound around its post (pale treads on dark
bodies that rise from the tread below, an iron collar per tread, an outer handrail and a lit jar on every
tread tracing the climb), topping out at the chest shelf, the walkable chest lid and the crossbeam, from
which you can drop back onto the potion boards. All walkable pieces are real visible geometry (no hidden
collision proxies).
The "Thank you" door is in the back wall at the right end. Walkable pieces never overlap in plan.
"""

import math

from misostory.geo import MeshBuilder
from misostory.kit import add_outline, asset
from misostory.kit.interior import (BAND, ROOM, RUG_Z, SHOP_H, WALL_T, banded_beam, cut_room, lbox, lcyl, point_light,
                                    room_light, shop_frame, sign_text, solid)

MAP_ID = 1010003
GAMEPLAY_FOCUS = (8.0, 7.6)
GAMEPLAY_SCALE = 20.0

POLE = (11.6, 8.9)      # pole-shelf post
POLE_R = (0.24, 1.75)   # board inner / outer radius (inner end meets the post)
CHEST_SHELF_Z = 3.2
BEAM_Z = 4.0
DOOR_X = 14.3           # "Thank you" door (clear of the camera-side knee wall at x ~15.5)
TREAD = "M_Flat_wood_lt"      # pale pole-shelf treads read against their dark bodies
TREAD_BODY = "M_Wood_Dark"


# ---------------------------------------------------------------------------
# local assets
# ---------------------------------------------------------------------------

def _bottle(mb, x, y, z, mat, s=1.0):
    mb.sphere(0.11 * s, loc=(x, y, z + 0.1 * s), scale=(1, 1, 1.05), mat=mat, subdiv=2)
    mb.cyl(0.04 * s, 0.1 * s, loc=(x, y, z + 0.19 * s), mat=mat, verts=8)
    mb.cyl(0.05 * s, 0.05 * s, loc=(x, y, z + 0.28 * s), mat="M_Wood", verts=8)


POTIONS = ("M_Glow_roof_red", "M_Glow_roof_orange", "M_Glow_cloth_white", "M_Glow_roof_blue")


@asset("X1010003_PotionRow", "Props", footprint=1.1, tags=("interior",))
def _potion_row(coll):
    """A row of round potion bottles (red, orange, white, blue) along +X, about 1.0 m long."""
    mb = MeshBuilder()
    for k in range(6):
        _bottle(mb, -0.45 + k * 0.18, (k % 2) * 0.06, 0.0, POTIONS[(k * 3) % 4], s=0.9 + (k % 3) * 0.1)
    mb.build("X1010003_PotionRow", coll, smooth=True, sharp_angle=50)


@asset("X1010003_Jar", "Props", footprint=0.5, tags=("interior",))
def _jar(coll):
    """Lidded clay jar."""
    mb = MeshBuilder()
    mb.sphere(0.2, loc=(0, 0, 0.2), scale=(1, 1, 1.1), mat="M_Flat_dirt_lt", subdiv=2, flatten_bottom=0.85)
    mb.cyl(0.13, 0.08, loc=(0, 0, 0.4), mat="M_Flat_dirt_lt", verts=12)
    mb.cyl(0.16, 0.06, loc=(0, 0, 0.47), mat="M_Flat_roof_red", verts=12)
    mb.sphere(0.05, loc=(0, 0, 0.55), mat="M_Flat_roof_red", subdiv=1)
    mb.cyl(0.205, 0.05, loc=(0, 0, 0.22), mat="M_Flat_wood_dk", verts=14)
    mb.build("X1010003_Jar", coll, smooth=True, sharp_angle=50)


@asset("X1010003_JarLit", "Props", footprint=0.5, tags=("interior", "light"))
def _jar_lit(coll):
    """Open clay jar of glowing honey-drops: the lit markers that trace the pole-shelf climb."""
    mb = MeshBuilder()
    mb.sphere(0.2, loc=(0, 0, 0.2), scale=(1, 1, 1.05), mat="M_Flat_dirt_lt", subdiv=2, flatten_bottom=0.85)
    mb.cyl(0.205, 0.05, loc=(0, 0, 0.2), mat=BAND, verts=14)
    mb.cyl(0.13, 0.07, loc=(0, 0, 0.38), mat="M_Flat_dirt_lt", verts=12)
    mb.cyl(0.15, 0.04, loc=(0, 0, 0.44), mat="M_Flat_wood_dk", verts=12)
    mb.sphere(0.12, loc=(0, 0, 0.5), scale=(1, 1, 0.8), mat="M_Glow_flower_yellow", subdiv=2)
    mb.sphere(0.05, loc=(0.06, -0.04, 0.6), mat="M_Glow_flower_yellow", subdiv=1)
    mb.build("X1010003_JarLit", coll, smooth=True, sharp_angle=50)


@asset("X1010003_WelcomeBooth", "Architecture", footprint=4.6, tags=("interior", "shop"))
def _welcome_booth(coll):
    """Lucy's WELCOME booth. Counter faces -Y, back panel at +Y (against a wall).

    Width 4.4 (X), depth 2.8 (Y). Tall counter front (1.5 m) with a cream money-bag banner and a
    pinned note; an orange arch board high between the front posts (text added in-map).
    """
    mb = MeshBuilder()
    W, Dp = 4.4, 2.8
    mb.box((W, 0.2, 3.0), loc=(0, Dp / 2 - 0.1, 1.5), mat="M_Plank", bevel=0.03, segs=1)
    for z in (1.3, 2.1):  # shelves of goods behind the keeper
        mb.box((W - 0.4, 0.4, 0.07), loc=(0, Dp / 2 - 0.35, z), mat="M_Wood", bevel=0.02, segs=1)
        for k in range(8):
            _bottle(mb, -1.75 + k * 0.5, Dp / 2 - 0.35, z + 0.035, POTIONS[(k + int(z * 2)) % 4], s=1.2)
    for s in (-1, 1):
        for k in range(5):
            mb.box((0.14, 0.52, 2.0 - k * 0.05), loc=(s * (W / 2 - 0.07), -Dp / 2 + 0.3 + k * 0.53, 1.0 - k * 0.025),
                   mat="M_Plank", bevel=0.025, segs=1)
        mb.box((0.26, 0.26, 4.7), loc=(s * (W / 2 - 0.05), -Dp / 2, 2.35), mat="M_Wood", bevel=0.04, segs=1)
        mb.box((0.4, 0.4, 0.3), loc=(s * (W / 2 - 0.05), -Dp / 2, 0.15), mat="M_Flat_stone_wall", bevel=0.05)
        mb.box((0.12, Dp, 0.12), loc=(s * (W / 2 - 0.05), 0.0, 2.3), mat="M_Wood_Dark")
    # tall counter
    mb.box((W - 0.3, 0.55, 1.45), loc=(0, -Dp / 2 + 0.3, 0.72), mat="M_Wood", bevel=0.03, segs=1)
    for k in range(8):
        mb.box((0.05, 0.04, 1.35), loc=(-1.85 + k * 0.53, -Dp / 2 + 0.01, 0.72), mat="M_Wood_Dark")
    mb.box((W, 0.8, 0.14), loc=(0, -Dp / 2 + 0.3, 1.5), mat="M_Plank", bevel=0.03, segs=1)
    # cream banner with a money bag
    mb.box((1.1, 0.04, 1.0), loc=(0.2, -Dp / 2 - 0.02, 0.85), mat="M_Cloth_White")
    mb.box((1.14, 0.06, 0.08), loc=(0.2, -Dp / 2 - 0.03, 1.36), mat="M_Wood_Dark")
    mb.sphere(0.26, loc=(0.2, -Dp / 2 - 0.08, 0.75), scale=(1.0, 0.35, 0.85), mat="M_Flat_wood_dk", subdiv=2)
    mb.cyl(0.1, 0.12, loc=(0.2, -Dp / 2 - 0.08, 0.96), mat="M_Flat_wood_dk", verts=8, r2=0.14)
    mb.box((0.12, 0.05, 0.12), loc=(0.2, -Dp / 2 - 0.17, 0.75), mat="M_Gold")
    # pinned note with a red pin
    mb.box((0.36, 0.03, 0.44), loc=(-1.3, -Dp / 2 - 0.02, 1.0), rot=(0, 6, 0), mat="M_Flat_cloth_white")
    mb.sphere(0.06, loc=(-1.3, -Dp / 2 - 0.06, 1.2), mat="M_Flat_cloth_red", subdiv=1)
    # WELCOME arch board (orange planks), high so the keeper stays visible
    for k in range(9):
        t = (k - 4) / 4
        mb.box((0.52, 0.16, 0.66), loc=(t * 2.0, -Dp / 2 - 0.02, 4.2 + (1 - t * t) * 0.22), rot=(0, -t * 9, 0),
               mat="M_Flat_roof_orange", bevel=0.04, segs=1)
    for s in (-1, 1):
        mb.sphere(0.07, loc=(s * 1.9, -Dp / 2 - 0.12, 4.25), mat="M_Gold", subdiv=1)
    # goods on the counter
    _bottle(mb, -1.6, -Dp / 2 + 0.3, 1.57, "M_Glow_roof_red", s=1.3)
    _bottle(mb, -1.3, -Dp / 2 + 0.35, 1.57, "M_Glow_roof_blue", s=1.3)
    mb.box((0.4, 0.3, 0.12), loc=(1.4, -Dp / 2 + 0.3, 1.63), mat="M_Flat_gold")
    mb.build("X1010003_WelcomeBooth", coll, smooth=True, sharp_angle=40)


@asset("X1010003_Poster", "Architecture", footprint=1.2, tags=("interior",))
def _poster(coll):
    """Parchment map of Maple Island pinned to the wall (faces -Y)."""
    mb = MeshBuilder()
    mb.box((1.2, 0.04, 0.95), loc=(0, 0, 0), rot=(0, 2, 0), mat="M_Flat_sand_a")
    mb.sphere(0.32, loc=(-0.15, -0.03, 0.05), scale=(1.2, 0.05, 0.75), mat="M_Flat_grass_top", subdiv=2)
    mb.sphere(0.18, loc=(0.32, -0.03, -0.18), scale=(1.2, 0.05, 0.7), mat="M_Flat_grass_top", subdiv=2)
    for (x, z) in ((-0.3, 0.1), (0.05, -0.05), (0.35, -0.15)):
        mb.sphere(0.04, loc=(x, -0.06, z), mat="M_Flat_cloth_red", subdiv=1)
    for (x, z) in ((-0.55, 0.42), (0.55, 0.42), (-0.55, -0.42), (0.55, -0.42)):
        mb.sphere(0.04, loc=(x, -0.04, z), mat="M_Gold", subdiv=1)
    mb.build("X1010003_Poster", coll, smooth=True, sharp_angle=40)


@asset("X1010003_BookStacks", "Props", footprint=1.4, tags=("interior",))
def _book_stacks(coll):
    """Two stacks of colourful books and an open book, for a table top (along +X, ~1.3 m)."""
    mb = MeshBuilder()
    cols = ("M_Flat_roof_red", "M_Flat_roof_blue", "M_Flat_roof_green", "M_Flat_roof_yellow", "M_Flat_roof_purple")
    for sx, n in ((-0.45, 4), (0.45, 3)):
        for k in range(n):
            mb.box((0.42, 0.3, 0.09), loc=(sx, 0, 0.045 + k * 0.09), rot=(0, 0, (k * 37) % 20 - 10),
                   mat=cols[(k + n) % 5], bevel=0.01, segs=1)
    mb.box((0.36, 0.26, 0.03), loc=(0.0, -0.05, 0.02), rot=(0, 0, 8), mat="M_Flat_cloth_white")
    mb.build("X1010003_BookStacks", coll, smooth=False)


@asset("X1010003_AppleBarrel", "Props", footprint=0.9, tags=("interior",))
def _apple_barrel(coll):
    mb = MeshBuilder()
    mb.cyl(0.38, 0.7, mat="M_Wood", verts=14, r2=0.42)
    for z in (0.1, 0.55):
        mb.cyl(0.43, 0.06, loc=(0, 0, z), mat="M_Metal", verts=14)
    for k in range(9):
        a = k * 2.4
        rr = 0.22 if k < 6 else 0.07
        mb.sphere(0.11, loc=(math.cos(a) * rr, math.sin(a) * rr, 0.74 + (0.06 if k >= 6 else 0.0)),
                  mat="M_Tomato" if k % 3 else "M_Flat_roof_green", subdiv=1)
    mb.build("X1010003_AppleBarrel", coll, smooth=True, sharp_angle=40)


@asset("X1010003_ScrollRack", "Props", footprint=1.0, tags=("interior",))
def _scroll_rack(coll):
    """Small rack of rolled scrolls and a quiver of arrows."""
    mb = MeshBuilder()
    mb.box((0.9, 0.4, 0.9), loc=(0, 0, 0.45), mat="M_Wood_Dark", bevel=0.03, segs=1)
    for r_ in range(2):
        for c in range(4):
            mb.cyl(0.07, 0.42, loc=(-0.3 + c * 0.2, -0.22, 0.3 + r_ * 0.35), rot=(90, 0, 0),
                   mat="M_Flat_sand_a" if (r_ + c) % 2 else "M_Flat_cloth_white", verts=8)
    mb.cyl(0.12, 0.55, loc=(0.6, 0.0, 0.0), mat="M_Flat_wood_dk", verts=10)
    for k in range(5):
        mb.box((0.02, 0.02, 0.5), loc=(0.56 + (k % 3) * 0.04, -0.03 + (k // 3) * 0.06, 0.75), mat="M_Wood")
        mb.box((0.06, 0.02, 0.1), loc=(0.56 + (k % 3) * 0.04, -0.03 + (k // 3) * 0.06, 1.0), mat="M_Flat_cloth_white")
    mb.build("X1010003_ScrollRack", coll, smooth=True, sharp_angle=40)


@asset("X1010003_DisplayTable", "Props", footprint=1.4, tags=("interior", "shop"))
def _display_table(coll):
    """Low plank display table (1.3 x 0.7 x 0.55, long side along X, front -Y) with a green runner, a tray of
    potion bottles, a basket of apples and a little price card."""
    mb = MeshBuilder()
    W, D, H = 1.3, 0.7, 0.55
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.09, 0.09, H - 0.06), loc=(sx * (W / 2 - 0.08), sy * (D / 2 - 0.08), (H - 0.06) / 2),
                   mat="M_Wood_Dark")
    mb.box((W - 0.16, D - 0.16, 0.04), loc=(0, 0, 0.14), mat="M_Wood")                       # low shelf
    mb.box((W, D, 0.07), loc=(0, 0, H - 0.035), mat="M_Plank", bevel=0.02, segs=1)
    mb.box((0.42, D + 0.02, 0.012), loc=(-0.3, 0, H + 0.006), mat="M_Flat_roof_green")       # runner
    mb.box((0.42, 0.012, 0.16), loc=(-0.3, -D / 2 - 0.006, H - 0.08), mat="M_Flat_roof_green")
    mb.box((0.5, 0.36, 0.03), loc=(-0.3, 0.02, H + 0.027), mat="M_Wood_Dark", bevel=0.01, segs=1)   # tray
    for k, (x, y) in enumerate(((-0.45, -0.06), (-0.3, -0.08), (-0.15, -0.05), (-0.38, 0.1), (-0.22, 0.11))):
        _bottle(mb, x, y, H + 0.04, POTIONS[k % 4], s=0.95)
    mb.cyl(0.2, 0.14, loc=(0.32, 0.02, H), mat="M_Flat_wood_lt", verts=14, r2=0.24)          # apple basket
    mb.cyl(0.245, 0.03, loc=(0.32, 0.02, H + 0.13), mat="M_Wood", verts=14)
    for k in range(7):
        a = k * 2.2
        rr = 0.13 if k < 5 else 0.04
        mb.sphere(0.075, loc=(0.32 + math.cos(a) * rr, 0.02 + math.sin(a) * rr, H + 0.17 + (0.05 if k >= 5 else 0.0)),
                  mat="M_Tomato" if k % 3 else "M_Flat_roof_green", subdiv=1)
    mb.box((0.16, 0.02, 0.11), loc=(0.05, -0.25, H + 0.06), rot=(-15, 0, 0), mat="M_Flat_cloth_white")  # price card
    for x in (-0.3, 0.32):                                                                    # spare goods below
        mb.box((0.3, 0.26, 0.18), loc=(x, 0.0, 0.25), mat="M_Flat_dirt_lt", bevel=0.02, segs=1)
    mb.build("X1010003_DisplayTable", coll, smooth=True, sharp_angle=40)


@asset("X1010003_RugSquare", "Props", footprint=3.4, tags=("interior",))
def _rug_square(coll):
    """Rectangular green-and-cream shop rug with a diamond border."""
    mb = MeshBuilder()
    mb.box((3.6, 2.6, 0.03), loc=(0, 0, 0.015), mat="M_Flat_roof_green")
    mb.box((3.1, 2.1, 0.035), loc=(0, 0, 0.018), mat="M_Flat_cloth_white")
    mb.box((2.6, 1.6, 0.04), loc=(0, 0, 0.02), mat="M_Flat_leaf_b_dk")
    for k in range(7):
        for sy in (-1, 1):
            mb.box((0.18, 0.18, 0.045), loc=(-1.35 + k * 0.45, sy * 1.05, 0.02), rot=(0, 0, 45), mat="M_Flat_roof_yellow")
    mb.cyl(0.45, 0.05, loc=(0, 0, 0.0), mat="M_Flat_roof_yellow", verts=4, rot=(0, 0, 45))
    mb.build("X1010003_RugSquare", coll, smooth=False)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def timber_frame(m, height=SHOP_H):
    """Decorative timber framing on the plaster back/left walls (verticals + two rails)."""
    x0, y0, x1, y1 = ROOM
    fb = y1 - WALL_T / 2 - 0.035
    fl = x0 + WALL_T / 2 + 0.035
    mb = MeshBuilder()
    for x in (2.0, 5.2, 9.4, 12.9):   # (12.9 keeps this vertical out of the door frame's wall plane)
        lbox(mb, m, (0.24, 0.07, height - 1.0), (x, fb, 1.0 + (height - 1.0) / 2), 0, "M_Wood")
    for y in (3.6, 8.2):
        lbox(mb, m, (0.24, 0.07, height - 1.0), (fl, y, 1.0 + (height - 1.0) / 2), 90, "M_Wood")
    for z in (1.0, 4.4):
        lbox(mb, m, (x1 - x0 - WALL_T / 2, 0.08, 0.2), ((x0 + x1) / 2 + WALL_T / 4, fb - 0.01, z), 0, "M_Wood_Dark")
        lbox(mb, m, (y1 - y0 - WALL_T / 2, 0.08, 0.2), (fl - 0.01, (y0 + y1 - WALL_T / 2) / 2, z), 90, "M_Wood_Dark")
    for (xa, xb) in ((5.2, 9.4), (9.4, 12.9)):  # diagonal braces in the upper panels
        L = math.hypot(xb - xa, 1.8)
        ang = math.degrees(math.atan2(1.8, xb - xa))
        lbox(mb, m, (L, 0.06, 0.18), ((xa + xb) / 2, fb, 5.4), 0, "M_Wood", tilt=(0, -ang, 0))
    obj = mb.build(f"{m.slug}_Timber_Frame", m.col_arch, smooth=False)
    obj.visible_shadow = False
    return obj


def _wedge(r0, r1, a_center, half, n=7):
    """Annular wedge outline around the pole (local xy), outer arc first."""
    cx, cy = POLE
    pts = []
    for i in range(n):
        a = math.radians(a_center - half + 2 * half * i / (n - 1))
        pts.append((cx + r1 * math.cos(a), cy + r1 * math.sin(a)))
    for i in range(3):
        a = math.radians(a_center + half - 2 * half * i / 2)
        pts.append((cx + r0 * math.cos(a), cy + r0 * math.sin(a)))
    return pts


def _spoke(mb, m, a_deg, r_a, z_a, r_b, z_b, size, mat):
    """Straight member from (radius r_a, height z_a) to (r_b, z_b) along the pole's radial at angle a_deg."""
    cx, cy = POLE
    ca, sa = math.cos(math.radians(a_deg)), math.sin(math.radians(a_deg))
    L = math.hypot(r_b - r_a, z_b - z_a)
    pitch = math.degrees(math.atan2(z_b - z_a, r_b - r_a))
    rm, zm = (r_a + r_b) / 2, (z_a + z_b) / 2
    lbox(mb, m, (L, size, size), (cx + ca * rm, cy + sa * rm, zm), a_deg, mat, tilt=(0, -pitch, 0))


def spiral_board(m, k, a_center, z_top, half=26.0, rise=0.4):
    """One walkable tread of the pole shelf. A pale plank tread with an iron nosing sits on a dark solid
    body that reaches down to the level of the tread below, so the seven boards read as one continuous
    spiral stair (each body is the riser above the previous tread), not as loose floating wedges. An iron
    collar clamps every tread to the post and a strut carries it."""
    cx, cy = POLE
    r0, r1 = POLE_R
    oz = m.origin.z
    mb = MeshBuilder()
    mb.prism(m.wpoly(_wedge(r0, r1, a_center, half)), oz + z_top - 0.1, oz + z_top, mat=TREAD, bevel=0.02, segs=1)
    # body: 25 deg half-angle so neighbouring bodies meet edge to edge; 3 mm above the tread below (no z-fight)
    zb = 0.0 if k == 0 else z_top - rise + 0.003
    mb.prism(m.wpoly(_wedge(r0, r1 - 0.05, a_center, min(half, 25.0))), oz + zb, oz + z_top - 0.1, mat=TREAD_BODY,
             bevel=0.01, segs=1)
    # iron nosing along the outer arc
    n = 6
    for i in range(n):
        a = a_center - half + 2 * half * (i + 0.5) / n
        ar = math.radians(a)
        seg = 2 * r1 * math.sin(math.radians(half / n)) + 0.01
        lbox(mb, m, (0.05, seg, 0.08), (cx + (r1 - 0.01) * math.cos(ar), cy + (r1 - 0.01) * math.sin(ar), z_top - 0.07),
             a, BAND)
    if k > 0:
        for i in range(6):   # iron collar clamping the tread's inner end to the post (only under its own tread)
            a = a_center - 33.0 + 66.0 * (i + 0.5) / 6
            ar = math.radians(a)
            lbox(mb, m, (0.07, 0.085, 0.2), (cx + 0.235 * math.cos(ar), cy + 0.235 * math.sin(ar), z_top - 0.19), a, BAND)
        _spoke(mb, m, a_center, 0.2, zb - 0.55, 1.15, zb + 0.02, 0.09, TREAD_BODY)          # strut
    obj = mb.build(f"{m.slug}_PoleBoard_{k}", m.col_terrain, smooth=False)
    m.add_ground(obj)
    return obj


def spiral_z(a_deg):
    """Tread height of the pole-shelf spiral as a continuous function of the angle (board k sits at
    60 + 50 (6 - k) degrees, top 0.4 (k + 1))."""
    return 0.4 * (7.0 - (a_deg - 60.0) / 50.0)


def spiral_rail(m, a_from, a_to, r=1.62, h=0.85):
    """Helical handrail on dark posts along the outer edge of the spiral (open where the climb is entered
    and left). a_from > a_to (the spiral rises clockwise)."""
    cx, cy = POLE
    mb = MeshBuilder()
    pts = []
    steps = max(2, int((a_from - a_to) / 7.0))
    for i in range(steps + 1):
        a = a_from + (a_to - a_from) * i / steps
        ar = math.radians(a)
        pts.append((cx + r * math.cos(ar), cy + r * math.sin(ar), spiral_z(a) + h))
    for (ax, ay, az), (bx, by, bz) in zip(pts, pts[1:]):
        L = math.hypot(bx - ax, by - ay)
        yaw = math.degrees(math.atan2(by - ay, bx - ax))
        pitch = math.degrees(math.atan2(bz - az, L))
        lbox(mb, m, (math.hypot(L, bz - az) + 0.02, 0.07, 0.07), ((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), yaw,
             BAND, tilt=(0, -pitch, 0))
    # posts: two per board, standing on the tread (board k spans a_k +- 26 deg)
    a = a_from
    while a >= a_to - 1e-6:
        k = max(0, min(6, round(6 - (a - 60.0) / 50.0)))
        ar = math.radians(a)
        z0 = 0.4 * (k + 1)
        top = spiral_z(a) + h
        lbox(mb, m, (0.07, 0.07, top - z0 + 0.1), (cx + r * math.cos(ar), cy + r * math.sin(ar), (z0 - 0.1 + top) / 2),
             a, TREAD_BODY)
        a -= 25.0
    obj = mb.build(f"{m.slug}_PoleShelf_Rail", m.col_arch, smooth=False)
    obj.visible_shadow = True
    return obj


def _crate_faces(mb, m, cx, cy, w, d, z0, h, kind):
    """Visual body of one walkable crate (framed planks with a cross brace) or wares box (iron-banded),
    trim on the two camera-facing faces (-Y and +X)."""
    body = {"crate": "M_Wood", "box": "M_Plank"}[kind]
    trim = {"crate": "M_Wood_Dark", "box": "M_Metal"}[kind]
    lbox(mb, m, (w, d, h), (cx, cy, z0 + h / 2), 0, body, bevel=0.02)
    t = 0.02
    for face in ("-Y", "+X"):
        if face == "-Y":
            fy, span, ax = cy - d / 2 - t / 2, w, "x"
        else:
            fy, span, ax = cx + w / 2 + t / 2, d, "y"

        def strip(sx, sz, off, zc, tilt=(0.0, 0.0)):
            if ax == "x":
                lbox(mb, m, (sx, t + 0.005, sz), (cx + off, fy, zc), 0, trim, tilt=tilt)
            else:
                lbox(mb, m, (sx, t + 0.005, sz), (fy, cy + off, zc), 90, trim, tilt=tilt)

        if kind == "crate":
            strip(span, 0.09, 0, z0 + 0.06)
            strip(span, 0.09, 0, z0 + h - 0.06)
            for sg in (-1, 1):
                strip(0.09, h, sg * (span / 2 - 0.045), z0 + h / 2)
            dl = math.hypot(span - 0.18, h - 0.18)
            strip(dl, 0.07, 0, z0 + h / 2, tilt=(0, math.degrees(math.atan2(h - 0.18, span - 0.18))))
        else:
            strip(span + 0.01, 0.07, 0, z0 + h * 0.5)
            for sg in (-1, 1):
                strip(0.07, h, sg * (span / 2 - 0.035), z0 + h / 2)


def crate_stack(m, name, x0, y0, x1, y1, top, kind="crate"):
    """A walkable crate on the floor as REAL geometry: a framed visible body plus a plank lid that is the
    walkable top (no hidden collision proxy)."""
    mb = MeshBuilder()
    _crate_faces(mb, m, (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0 - 0.06, y1 - y0 - 0.06, 0.0, top - 0.07, kind)
    body = mb.build(f"{m.slug}_{name}_Body", m.col_props, smooth=False)
    add_outline(body, 0.022)
    return solid(m, name, [(x0, y0, x1, y1, top - 0.07, top)], mat="M_Plank" if kind == "crate" else "M_Wood",
                 bevel=0.015)


def treasure_chest(m, cx, cy, z0, name="Chest"):
    """Red-and-gold treasure chest built in-map: its low vaulted lid (top z0 + 0.41) is real walkable ground,
    as the classic chest is a foothold. 0.9 x 0.62 m, lock facing -Y."""
    W, D, H = 0.9, 0.62, 0.26
    mb = MeshBuilder()
    lbox(mb, m, (W, D, H), (cx, cy, z0 + H / 2), 0, "M_Flat_roof_red", bevel=0.03)
    mb.cyl(D / 2, W, loc=m.w(cx - W / 2, cy, z0 + H), rot=(0, 90, m.wyaw(0)), mat="M_Flat_roof_red", verts=16,
           scale=(0.5, 1, 1))
    for x in (-0.33, 0.0, 0.33):
        lbox(mb, m, (0.08, D + 0.04, H + 0.02), (cx + x, cy, z0 + H / 2 + 0.01), 0, "M_Gold")
        mb.cyl(D / 2 + 0.01, 0.08, loc=m.w(cx + x - 0.04, cy, z0 + H), rot=(0, 90, m.wyaw(0)), mat="M_Gold", verts=16,
               scale=(0.5, 1, 1))
    lbox(mb, m, (0.16, 0.06, 0.18), (cx, cy - D / 2 - 0.02, z0 + H - 0.02), 0, "M_Gold")
    obj = mb.build(f"{m.slug}_{name}", m.col_terrain, smooth=True, sharp_angle=40)
    m.add_ground(obj)   # (no ink outline: its flipped shell would read as an underside to the ground raycast)
    return obj


# ---------------------------------------------------------------------------
# map
# ---------------------------------------------------------------------------

def build(m):
    x0, y0, x1, y1 = ROOM
    # ---------------- shell: warm plaster in a timber frame ----------------
    cut_room(m, SHOP_H, wall_mat="M_Flat_plaster", knee_mat="M_Plank", base_mat="M_Plank", base_h=1.0,
             trim_mat="M_Wood_Dark")
    timber_frame(m)
    shop_frame(m, posts_back=(3.1,), posts_left=(6.0, 0.75))
    room_light(m, energy=2300, color=(1.0, 0.9, 0.75))

    # ---------------- Lucy's WELCOME booth (west wall) ----------------
    solid(m, "Booth_Stand", [(0.6, 6.9, 2.7, 10.3, -0.1, 0.8)], mat="M_Plank")
    m.npc("Lucy", 2.0, 9.1, rot=50)
    m.place("X1010003_WelcomeBooth", 1.95, 8.6, rot=90, z=0.0)
    sign_text(m, "WELCOME", 3.55, 8.6, 4.37, rot=90, size=0.46, mat="M_Flat_cloth_white", name="Welcome")

    # ---------------- "Thank you" exit door (back wall, right end) ----------------
    m.place("Door_Plank", DOOR_X, y1 - WALL_T / 2 - 0.02, rot=0, z=0.0)
    m.door_portal("out00", DOOR_X, 10.75, rot=0)
    plaque = MeshBuilder()   # dark board above the arch, cream lettering (readable at gameplay zoom)
    lbox(plaque, m, (2.0, 0.1, 0.56), (DOOR_X, y1 - WALL_T / 2 - 0.06, 3.8), 0, "M_Wood_Dark", bevel=0.04)
    plaque.build(f"{m.slug}_ThankYou_Plaque", m.col_arch, smooth=False)
    sign_text(m, "Thank you", DOOR_X, y1 - WALL_T / 2 - 0.13, 3.8, rot=0, size=0.36, mat="M_Flat_cloth_white",
              name="ThankYou")

    # ---------------- left stack: crates -> book table -> cabinet -> potion boards ----------------
    crate_stack(m, "Crate_Low", 5.0, 9.5, 6.1, 10.6, 0.42, kind="box")
    crate_stack(m, "Crate_High", 6.1, 9.5, 7.2, 10.6, 0.84, kind="crate")
    solid(m, "Book_Table", [(7.2, 9.4, 8.8, 10.6, 1.12, 1.26)], mat="M_Plank")
    legs = MeshBuilder()
    for (lx, ly) in ((7.32, 9.52), (8.68, 9.52), (7.32, 10.48), (8.68, 10.48)):
        lbox(legs, m, (0.12, 0.12, 1.12), (lx, ly, 0.56), 0, "M_Wood_Dark")
    lbox(legs, m, (1.5, 1.1, 0.06), (8.0, 10.0, 0.35), 0, "M_Wood")
    legs.build(f"{m.slug}_Book_Table_Legs", m.col_arch, smooth=False)
    m.place("X1010003_BookStacks", 8.05, 10.45, z=1.26, rot=0, scale=0.75)   # back lip, clear of LeftStack
    m.place("X1010003_BookStacks", 8.0, 10.0, z=0.41, rot=180, scale=0.9)
    solid(m, "Cabinet", [(8.8, 9.6, 10.0, 10.6, 0.0, 1.68, "M_Wood"), (8.75, 9.55, 10.05, 10.65, 1.58, 1.68, "M_Plank")])
    fronts = MeshBuilder()
    for k in range(3):
        lbox(fronts, m, (1.0, 0.05, 0.42), (9.4, 9.57, 0.3 + k * 0.5), 0, "M_Plank", bevel=0.02)
        lbox(fronts, m, (0.16, 0.06, 0.06), (9.4, 9.53, 0.38 + k * 0.5), 0, "M_Gold")
    fronts.build(f"{m.slug}_Cabinet_Fronts", m.col_arch, smooth=False)
    boards = [(8.7, 10.1, 2.1), (7.5, 8.7, 2.5), (6.3, 7.5, 2.9)]
    for i, (bx0, bx1, bz) in enumerate(boards):
        solid(m, f"Potion_Board_{i}", [(bx0, 10.65, bx1, 11.45, bz - 0.12, bz)], mat="M_Plank")
        # (pushed to the back lip and slimmed in depth so the LeftStack walk along y 10.9 clears the bottles)
        m.place("X1010003_PotionRow", (bx0 + bx1) / 2, 11.32, z=bz, rot=0, scale=(1.0, 0.7, 1.0))
    brackets = MeshBuilder()
    for (bx0, bx1, bz) in boards:
        for bx in (bx0 + 0.15, bx1 - 0.15):
            lbox(brackets, m, (0.08, 0.6, 0.08), (bx, 11.1, bz - 0.4), 0, "M_Wood_Dark", tilt=(-40, 0, 0))
    lbox(brackets, m, (3.7, 0.08, 0.52), (8.2, 11.42, 3.65), 0, "M_Wood_Dark", bevel=0.03)   # "POTIONS" header
    brackets.build(f"{m.slug}_Potion_Brackets", m.col_arch, smooth=False)
    sign_text(m, "POTIONS", 8.2, 11.33, 3.65, rot=0, size=0.36, mat="M_Flat_cloth_white", name="Potions")
    m.place("Shelf_Goods", 5.6, 11.1, rot=0, z=0.0, scale=(0.55, 0.9, 0.85))   # against the back wall, west of the boards

    # ---------------- pole shelf: seven boards spiralling up the post ----------------
    for k in range(7):
        a = 60 + 50 * (6 - k)
        # (the top board is a little narrower so less of it tucks under the chest shelf)
        spiral_board(m, k, a, 0.4 * (k + 1), half=22.0 if k == 6 else 26.0)
        # a lit jar on every tread traces the climb order (kept by the post, off the walking line at r 1.25)
        aj = math.radians(a + 14)
        m.place("X1010003_JarLit", POLE[0] + math.cos(aj) * 0.58, POLE[1] + math.sin(aj) * 0.58, z=0.4 * (k + 1),
                rot=a, scale=0.75)
    spiral_rail(m, 325.0, 95.0)   # boards 1-5; open at the board-0 entry (east) and the board-6 exit (chest shelf)
    post = MeshBuilder()
    lcyl(post, m, 0.2, 4.6, (POLE[0], POLE[1], 0.0), mat="M_Wood", verts=12)
    lcyl(post, m, 0.34, 0.3, (POLE[0], POLE[1], 0.0), mat="M_Flat_stone_wall", verts=12)
    lcyl(post, m, 0.3, 0.25, (POLE[0], POLE[1], 4.6), mat="M_Flat_stone_wall", verts=12)
    lcyl(post, m, 0.14, 0.25, (POLE[0], POLE[1], 4.85), mat="M_Gold", verts=10, r2=0.02)
    post.build(f"{m.slug}_Pole_Post", m.col_arch, smooth=True)

    # ---------------- chest shelf, chest lid, crossbeam ----------------
    # (y0 10.45 keeps the top spiral board's corner out from under it; x1 13.3 clears the door frame)
    solid(m, "Chest_Shelf", [(11.8, 10.45, 13.3, 11.45, CHEST_SHELF_Z - 0.14, CHEST_SHELF_Z)], mat="M_Plank")
    cb = MeshBuilder()
    for bx in (12.0, 13.1):
        lbox(cb, m, (0.08, 0.9, 0.08), (bx, 10.95, CHEST_SHELF_Z - 0.45), 0, "M_Wood_Dark", tilt=(-35, 0, 0))
    # the crossbeam (T20) is carried by knee braces from the wall and iron straps hung from the frame rail
    for bx in (10.3, 11.6):
        lbox(cb, m, (0.08, 0.9, 0.08), (bx, 11.05, BEAM_Z - 0.7), 0, "M_Wood_Dark", tilt=(-35, 0, 0))
    for bx in (10.25, 11.65):
        lbox(cb, m, (0.12, 0.05, 0.5), (bx, 11.42, BEAM_Z + 0.22), 0, BAND)
        lbox(cb, m, (0.12, 0.84, 0.04), (bx, 11.04, BEAM_Z + 0.015), 0, BAND)
        lbox(cb, m, (0.12, 0.04, 0.47), (bx, 10.63, BEAM_Z - 0.22), 0, BAND)
    cb.build(f"{m.slug}_Chest_Shelf_Brackets", m.col_arch, smooth=False)
    treasure_chest(m, 12.25, 11.02, CHEST_SHELF_Z)   # walkable lid (real geometry, no hidden proxy)
    m.place("X1010003_Jar", 12.95, 11.3, z=CHEST_SHELF_Z, scale=0.75)
    banded_beam(m, "Crossbeam", (10.1, 11.05), (11.8, 11.05), 0.8, 0.45, BEAM_Z, walkable=True)
    m.place("X1010003_Poster", x0 + WALL_T / 2 + 0.03, 4.8, rot=90, z=2.5)
    m.place("Hanging_Lantern", 11.0, 11.0, z=BEAM_Z - 0.45)   # under the crossbeam, between its braces
    point_light(m, 8.0, 7.0, 4.0, energy=110, color=(1.0, 0.82, 0.55), radius=0.5, name="Lantern")

    # ---------------- shop floor dressing ----------------
    m.place("X1010003_RugSquare", 8.2, 5.4, rot=0, z=RUG_Z)
    m.place("X1010003_AppleBarrel", 3.6, 5.2, rot=0)
    m.place("X1010003_AppleBarrel", 4.3, 4.6, rot=40, scale=0.85)
    m.place("X1010003_ScrollRack", 1.0, 4.6, rot=90)
    m.place("Sack", 1.3, 1.6, rot=20)
    m.place("Sack", 2.0, 1.1, rot=-30, scale=0.9)
    m.place("Crate", 2.8, 1.6, rot=10)
    m.place("Table_Round", 9.0, 2.6)
    m.place("X1010003_PotionRow", 9.0, 2.6, z=0.88, rot=-20, scale=0.8)
    m.place("Barrel", 15.1, 6.3, scale=0.9)          # (>= 0.8 m body clearance from Main)
    m.place("X1010003_AppleBarrel", 15.05, 5.45, rot=10)
    m.place("Crate_Stack", 14.4, 1.4, rot=-15, scale=0.85)
    m.place("Sack", 13.2, 1.0, rot=50)
    # front-right: a small rug with a low display table of potions and apples, and a barrel of goods
    # (all >= 2.3 m off Main)
    m.place("Rug_Round", 11.8, 2.5, rot=0, z=RUG_Z, scale=0.65)
    m.place("X1010003_DisplayTable", 11.75, 2.5, rot=-8, scale=1.2)
    m.place("Barrel", 13.15, 3.0, rot=20, scale=0.9)

    # ---------------- gameplay ----------------
    m.player(6.8, 3.6, rot=-40)
    m.player_spawn(14.3, 9.0, rot=0, note="interior: just inside the door (out00)")
    m.route("Main", [(DOOR_X, 10.75), (14.4, 7.5), (13.0, 5.6), (8.0, 4.6), (4.9, 6.2), (4.3, 8.6)])
    # crates -> book table -> cabinet along y 9.95 (the book stacks sit on the table's back lip), then the potion
    # boards along y 10.9 (the bottle rows stand at the back)
    m.route("LeftStack", [(4.4, 9.4), (4.5, 9.95), (6.65, 9.95), (8.0, 9.9), (9.6, 9.95), (9.6, 10.9),
                          (8.2, 10.9), (6.9, 10.9)])
    ring = []
    for k in range(7):
        a = math.radians(60 + 50 * (6 - k))
        ring.append((POLE[0] + math.cos(a) * 1.25, POLE[1] + math.sin(a) * 1.25))
    # on the chest shelf the route loops out to its east end before stepping onto the chest lid, so the
    # validator's 1.2 m slope window never spans board -> shelf -> lid in a short straight distance
    m.route("PoleShelf", [(14.4, 8.0), (13.9, 8.9)] + ring + [(12.45, 10.1), (12.45, 10.55), (13.15, 10.6),
                                                             (13.15, 11.1), (12.25, 11.1), (11.3, 11.1),
                                                             (10.4, 11.0)])  # (a body at y 11.1 touches the wall)
    m.route("BeamDrop", [(10.4, 11.05), (9.7, 10.9)], one_way=True)   # 1.9 m jump down onto the potion board
