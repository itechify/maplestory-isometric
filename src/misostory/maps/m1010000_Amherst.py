"""Amherst (1010000) - "the cobblestone hill town".

Classic (GMS v8) structure, from docs/research/maps/1010000_Amherst_1010000.md:
  T01 west street (Rain by the gate + red postbox, yellow-capped house, red mushroom tower,
  Pio) -> T02 ramp + T03 landing + 60 px step -> T04 middle terrace / town square (lime
  Department Store in02, rainbow spring, Lucas under his tree grove) -> T05 + T06 two steps
  down to the east street (orange spotted house -> Townstreet in01, face cut-out boards,
  banner, the giant tree-house by east00). Above the west street: the T12 upper plateau with
  the two-storey capped Weapon Store (in00), Mai and two barrels, reachable ONLY by the
  paired rope + ladder (x 917 / 991) from the square onto the T11 ledge, then one step up.
  T08-T10: two floating ledges with a rope above the east steps (an optional climb).

3D translation (the camera looks straight along local +y for this map): the 2D overlap of
the plateau over the west street becomes depth - the plateau is a 7 m cobblestone bastion
BEHIND the west street, so the yellow house and red tower stand against its wall exactly as
in the 2D skyline. The middle terrace becomes a raised town square in the centre; the east
street is low again and opens toward the back: a lane climbs to a raised garden yard and a leafy
arch (in01, back edge); Townstreet's cut-away orange house (the classic house6) stands just beyond
it, seen straight up the lane, so the island has ONE orange house. The T08-T10 ledges become a
timber lookout at the square's east corner (steps, rope, roofed crow's nest with a pennant).
Streets join the square by gentle cobble slopes (T02 ramp, T03/T05 steps). Era: Mai stands on
the plateau in v8.
"""

import math

import bpy

from misostory import core, geo
from misostory import materials as M
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.architecture import door, shop_sign
from misostory.kit.art_pack import part_materials
from misostory.kit.classic import HOUSE_PACK, mushroom_house_v2
from misostory.kit.nature import _puffy_canopy
from misostory.kit.promoted import arc

MAP_ID = 1010000
GAMEPLAY_FOCUS = (30.0, 21.0)
GAMEPLAY_SCALE = 44.0

# map-local paving: the brief's pale blue-grey + tan flagstones with a light mortar, so the town square and the
# cobble street read pale (not mid-grey) from the island/region cameras. Same cobble pattern as M_Cobble_Path.
PALE = "M_X1010000_CobblePale"


def _pale_cobble():
    if bpy.data.materials.get(PALE) is None:
        M.mat_cobble(PALE, "#CAD5E9", "#DECCA6", "#B2BFD8", "#868EA0", 1.6)
    return PALE


def _retint(objs):
    """Swap the shared M_Cobble_Path on terrain pieces (cobble caps, cobble ramp tops) for the pale paving."""
    mat = bpy.data.materials.get(_pale_cobble())
    for o in (objs if isinstance(objs, (list, tuple)) else [objs]):
        if o is None or getattr(o, "data", None) is None or not hasattr(o.data, "materials"):
            continue
        for i, mt in enumerate(o.data.materials):
            if mt is not None and mt.name == "M_Cobble_Path":
                o.data.materials[i] = mat

PLAZA = 1.6      # T04 (+120 px)
STEP = 0.8       # T03 / T05 (+60 px)
LANDING = 6.4    # T11 (+390 px, compressed)
PLATEAU = 7.2    # T12 (+450 px, compressed)
LOOK1, LOOK2, LOOK3 = 2.4, 4.8, 5.6   # T08 / T09 / T10
YARD = 0.8       # raised garden yard at the top of the lane to Townstreet (in01)


# ---------------------------------------------------------------------------
# Local assets (map-prefixed; candidates for the shared kit)
# ---------------------------------------------------------------------------

@asset("X1010000_TownGate", "Architecture", footprint=6.0, tags=("landmark",))
def _town_gate(coll):
    """Amherst west gate: two cobblestone pillars with mushroom finials and a plank arch (spans X)."""
    mb = MeshBuilder()
    for sx in (-2.9, 2.9):
        mb.cyl(0.62, 0.35, loc=(sx, 0, 0), mat="M_StoneWall", verts=12)
        mb.cyl(0.48, 3.2, loc=(sx, 0, 0.3), mat="M_StoneWall", verts=12, r2=0.42)
        mb.cyl(0.55, 0.25, loc=(sx, 0, 3.45), mat="M_Wood_Dark", verts=12)
        mb.cyl(0.14, 0.45, loc=(sx, 0, 3.65), mat="M_Flat_mush_stem", verts=8)
        mb.dome(0.62, 0.55, loc=(sx, 0, 4.05), mat="M_Spot_mush_red__mush_spot", u=16, v=4, lip=0.12)
    arc(mb, 2.9, 0.32, 0.5, 3.1, "M_Plank", n=14)
    mb.box((1.7, 0.12, 0.6), loc=(0, -0.3, 5.25), mat="M_Plank", bevel=0.05, segs=1)
    mb.box((0.06, 0.06, 0.5), loc=(-0.6, -0.3, 5.75), mat="M_Rope")
    mb.box((0.06, 0.06, 0.5), loc=(0.6, -0.3, 5.75), mat="M_Rope")
    for k in range(3):
        mb.box((1.1 - k * 0.2, 0.04, 0.07), loc=(0, -0.38, 5.4 - k * 0.16), mat="M_Wood_Dark")
    mb.build("X1010000_TownGate", coll, smooth=True, sharp_angle=40)


def _cutout(coll, name, cap_mat, stem_h, cap_w, cap_h, hole_z):
    mb = MeshBuilder()
    n = 14
    # stem board
    mb.prism([(-0.36, 0.0), (0.36, 0.0), (0.4, stem_h + 0.05), (-0.4, stem_h + 0.05)], -0.06, 0.06,
             rot=(90, 0, 0), mat="M_Flat_mush_stem", bevel=0.03, segs=1)
    cap = [(cap_w * math.cos(math.pi * k / n), stem_h + cap_h * math.sin(math.pi * k / n) ** 0.8)
           for k in range(n + 1)]
    mb.prism(cap, -0.08, 0.08, rot=(90, 0, 0), mat=cap_mat, bevel=0.03, segs=1)
    # face hole (dark) + spots on the cap
    mb.cyl(0.21, 0.04, loc=(0, -0.1, hole_z), rot=(90, 0, 0), mat="M_Eye_Black", verts=16, scale=(1.0, 1.15, 1))
    for (sx, sz, r) in ((-cap_w * 0.55, 0.45, 0.13), (cap_w * 0.5, 0.35, 0.11), (cap_w * 0.05, 0.75, 0.1)):
        mb.cyl(r, 0.03, loc=(sx, -0.1, stem_h + cap_h * sz), rot=(90, 0, 0), mat="M_Flat_mush_spot", verts=12)
    # back legs
    for sx in (-0.25, 0.25):
        mb.box((0.08, 0.08, stem_h * 0.9), loc=(sx, 0.35, stem_h * 0.42), rot=(-18, 0, 0), mat="M_Wood")
    mb.build(name, coll, smooth=False)


@asset("X1010000_FaceCutout_Red", "Props", footprint=1.4, tags=("prop",))
def _cutout_red(coll):
    """Small red mushroom face cut-out board (east-street fairground prop)."""
    _cutout(coll, "X1010000_FaceCutout_Red", "M_Flat_mush_red", 0.95, 0.75, 0.75, 1.15)


@asset("X1010000_FaceCutout_Yellow", "Props", footprint=1.6, tags=("prop",))
def _cutout_yellow(coll):
    """Tall yellow mushroom face cut-out board (east-street fairground prop)."""
    _cutout(coll, "X1010000_FaceCutout_Yellow", "M_Flat_mush_yellow", 1.9, 0.85, 0.85, 1.55)


@asset("X1010000_BannerPole", "Props", footprint=1.0, tags=("prop",))
def _banner_pole(coll):
    """White banner on a pole topped by a blue mushroom finial."""
    mb = MeshBuilder()
    mb.cyl(0.32, 0.25, mat="M_StoneWall", verts=10)
    mb.cyl(0.08, 3.9, loc=(0, 0, 0.2), mat="M_Wood_Dark", verts=8)
    mb.box((1.0, 0.08, 0.08), loc=(0.45, 0, 3.6), mat="M_Wood_Dark")
    mb.box((0.85, 0.05, 1.55), loc=(0.5, -0.02, 2.75), mat="M_Cloth_White", bevel=0.02, segs=1)
    mb.prism([(0.08, 1.98), (0.92, 1.98), (0.5, 1.7)], -0.025, 0.025, loc=(0, -0.02, 0), rot=(90, 0, 0),
             mat="M_Cloth_White")
    mb.box((0.6, 0.06, 0.18), loc=(0.5, -0.06, 3.0), mat="M_Flat_roof_blue")
    mb.cyl(0.09, 0.3, loc=(0, 0, 4.05), mat="M_MushStem", verts=8)
    mb.dome(0.36, 0.3, loc=(0, 0, 4.3), mat="M_Spot_mush_blue__mush_spot", u=14, v=4, lip=0.07)
    mb.build("X1010000_BannerPole", coll, smooth=True, sharp_angle=40)


@asset("X1010000_PotionSign", "Props", footprint=1.4, tags=("prop", "sign"))
def _potion_sign(coll):
    """Department Store sign post: hanging potion-bottle board + a lantern (faces -Y)."""
    mb = MeshBuilder()
    mb.cyl(0.26, 0.2, mat="M_StoneWall", verts=8)
    mb.box((0.16, 0.16, 2.9), loc=(0, 0, 1.45), mat="M_Wood_Dark", bevel=0.03, segs=1)
    mb.box((1.2, 0.12, 0.12), loc=(0.5, 0, 2.8), mat="M_Wood_Dark")
    shop_sign(mb, "potion", (0.65, 0.2, 2.0))
    mb.box((0.06, 0.06, 0.35), loc=(-0.0, -0.35, 2.55), mat="M_Metal")
    mb.box((0.3, 0.3, 0.38), loc=(0.0, -0.35, 2.22), mat="M_Glow_window", bevel=0.04, segs=1)
    mb.cyl(0.24, 0.14, loc=(0.0, -0.35, 2.42), mat="M_Wood_Dark", verts=4, r2=0.04, rot=(0, 0, 45))
    mb.box((0.08, 0.3, 0.06), loc=(0, -0.2, 2.62), mat="M_Wood_Dark")
    mb.build("X1010000_PotionSign", coll, smooth=False)


# pack (#75, kit/landmark_aliases.py): the pack long lime house, fitted by its stem to this stem (2.0 x 1.1 x 1.6
# wide) like the catalog houses (classic.HOUSE_PACK), so the walls stand where these did; its 2 m door spans in02.
@asset("X1010000_DeptStore", "Architecture", footprint=10.6, tags=("house", "mushroom", "shop", "landmark"),
       pack=dict(HOUSE_PACK, fit_nodes=(["Plaster stem house"], 2 * 2.0 * 1.1 * 1.6)))
def _dept_store(coll):
    """Amherst Department Store: long lime-green spotted mushroom house with a stone-oven chimney.

    A taller stem and a tighter cap than House_Mushroom_LimeLong, so that under the 40 degree
    camera the cap lip clears the door, the round windows and the wall lantern (visible facade
    ~ (stem_h - 0.65) - (cap_r - 1.96) * 0.84 = 2.2 m > door top 2.0 m).
    """
    mushroom_house_v2(coll, "X1010000_DeptStore", "M_Spot_mush_green__mush_spot", stem_h=4.0, cap_r=3.3,
                      cap_h=2.0, long_body=1.6, profile=0.6, chimney="oven")


@asset("X1010000_Birdhouse", "Props", footprint=0.8, tags=("prop",))
def _birdhouse(coll):
    """Little birdhouse on a post (by the autumn tree on the west street)."""
    mb = MeshBuilder()
    mb.box((0.14, 0.14, 2.5), loc=(0, 0, 1.25), mat="M_Wood")
    mb.box((0.55, 0.5, 0.55), loc=(0, 0, 2.75), mat="M_Plank", bevel=0.03, segs=1)
    for s in (-1, 1):
        mb.box((0.48, 0.66, 0.07), loc=(s * 0.19, 0, 3.12), rot=(0, s * 38, 0), mat="M_Flat_roof_red", bevel=0.02,
               segs=1)
    mb.cyl(0.1, 0.04, loc=(0, -0.26, 2.8), rot=(90, 0, 0), mat="M_Eye_Black", verts=10)
    mb.box((0.04, 0.16, 0.04), loc=(0, -0.32, 2.62), mat="M_Wood_Dark")
    mb.build("X1010000_Birdhouse", coll, smooth=False)


@asset("X1010000_SwordSign", "Props", footprint=1.4, tags=("prop", "sign"))
def _sword_sign(coll):
    """Weapon Store sign post: hanging sword board + a lantern (faces -Y)."""
    mb = MeshBuilder()
    mb.cyl(0.26, 0.2, mat="M_StoneWall", verts=8)
    mb.box((0.16, 0.16, 2.9), loc=(0, 0, 1.45), mat="M_Wood_Dark", bevel=0.03, segs=1)
    mb.box((1.2, 0.12, 0.12), loc=(0.5, 0, 2.8), mat="M_Wood_Dark")
    shop_sign(mb, "weapon", (0.65, 0.2, 2.0))
    # a green star behind the sword (classic signboard icon/0)
    mb.cyl(0.3, 0.04, loc=(0.65, -0.11, 2.12), rot=(90, 0, 0), mat="M_Flat_roof_green", verts=5)
    mb.box((0.06, 0.06, 0.35), loc=(-0.0, -0.35, 2.55), mat="M_Metal")
    mb.box((0.3, 0.3, 0.38), loc=(0.0, -0.35, 2.22), mat="M_Glow_window", bevel=0.04, segs=1)
    mb.cyl(0.24, 0.14, loc=(0.0, -0.35, 2.42), mat="M_Wood_Dark", verts=4, r2=0.04, rot=(0, 0, 45))
    mb.box((0.08, 0.3, 0.06), loc=(0, -0.2, 2.62), mat="M_Wood_Dark")
    mb.build("X1010000_SwordSign", coll, smooth=False)


@asset("X1010000_Annex", "Architecture", footprint=3.4, tags=("house",))
def _annex(coll):
    """Low thatched lean-to (the Weapon Store's annex): high side at -X against the store, open front (-Y)."""
    mb = MeshBuilder()
    mb.box((3.0, 3.2, 0.18), loc=(0, 0, 0.09), mat="M_StoneWall", bevel=0.04, segs=1)
    mb.box((3.0, 0.16, 2.3), loc=(0, 1.52, 1.15), mat="M_Plank", bevel=0.03, segs=1)       # back wall
    mb.box((0.16, 3.2, 1.75), loc=(1.42, 0, 0.88), mat="M_Plank", bevel=0.03, segs=1)       # low side wall
    for (x, y, h) in ((1.42, -1.55, 1.9), (-1.42, -1.55, 2.75), (1.42, 1.55, 1.9), (-1.42, 1.55, 2.75)):
        mb.box((0.2, 0.2, h), loc=(x, y, h / 2), mat="M_Wood_Dark")
    mb.box((0.2, 3.3, 0.2), loc=(-1.42, 0, 2.7), mat="M_Wood_Dark")
    # thatch: a thick straw slab sloping down toward +X, with a ragged fringe of straw tufts
    ang = math.degrees(math.atan2(0.85, 2.84))
    mb.box((3.6, 3.9, 0.34), loc=(0.1, 0, 2.48), rot=(0, ang, 0), mat="M_Grad_leaf_yellow_dk__leaf_yellow",
           bevel=0.1, segs=2)
    for k in range(9):
        y = -1.8 + k * 0.45
        mb.cyl(0.2, 0.32, loc=(1.88, y, 1.72), mat="M_Flat_leaf_yellow_dk", verts=6, r2=0.05, rot=(180, 0, 0))
    mb.cyl(0.13, 3.9, loc=(-1.6, -1.95, 2.95), rot=(-90, 0, 0), mat="M_Wood_Dark", verts=8)  # ridge log
    # two crossed practice swords on the back wall
    for s in (-1, 1):
        mb.box((0.08, 0.05, 1.0), loc=(0.2, 1.42, 1.4), rot=(0, s * 30, 0), mat="M_Metal")
    mb.build("X1010000_Annex", coll, smooth=False)


@asset("X1010000_RedTower", "Architecture", footprint=6.4, tags=("house", "mushroom", "landmark"))
def _red_tower(coll):
    """The red mushroom tower on the west street (classic house10): tall stem with two rows of round
    windows, a smooth red cap with white spots and a periscope pipe chimney."""
    sr, sh = 1.75, 6.0
    mushroom_house_v2(coll, "X1010000_RedTower", "M_Spot_mush_red__mush_spot", stem_r=sr, stem_h=sh, cap_r=2.85,
                      cap_h=2.5, chimney=None, profile=0.7)
    mb = MeshBuilder()
    # upper storeys: staggered round windows with cross mullions (a stair-tower rhythm, not a face)
    for (x, z, r) in ((-0.95, 3.6, 0.34), (0.62, 4.3, 0.3)):
        t = max(0.0, (z - sh * 0.53) / (sh * 0.47))
        rr = sr * (1.1 - 0.18 * t)
        y = -math.sqrt(max(0.1, rr * rr - x * x))
        a = math.degrees(math.atan2(x, -y))          # face the window along the stem's surface normal
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        def P(d):  # point d metres outward (toward -y rotated by a) from the surface point
            return (x + sa * d, y - ca * d, z)
        mb.cyl(r + 0.1, 0.25, loc=P(-0.25), rot=(90, 0, a), mat="M_Wood_Dark", verts=14)
        mb.cyl(r, 0.3, loc=P(-0.2), rot=(90, 0, a), mat="M_Window", verts=14)
        mb.box((0.05, 0.06, r * 1.8), loc=P(0.11), rot=(0, 0, a), mat="M_Wood_Dark")
        mb.box((r * 1.8, 0.06, 0.05), loc=P(0.11), rot=(0, 0, a), mat="M_Wood_Dark")
        mb.box((r * 2.0, 0.22, 0.07), loc=P(0.06)[:2] + (z - r - 0.08,), rot=(0, 0, a), mat="M_Wood_Dark")
    # periscope pipe: up out of the cap, elbow toward the street, flared mouth
    px, py = 0.75, 0.55
    mb.cyl(0.17, 2.0, loc=(px, py, 7.8), mat="M_Metal", verts=10)
    for z in (8.55, 9.2):
        mb.cyl(0.22, 0.1, loc=(px, py, z), mat="M_Wood_Dark", verts=10)
    mb.sphere(0.2, loc=(px, py, 9.8), mat="M_Metal", subdiv=2)
    mb.cyl(0.17, 0.75, loc=(px, py, 9.8), rot=(90, 0, 0), mat="M_Metal", verts=10)
    mb.cyl(0.19, 0.28, loc=(px, py - 0.75, 9.8), rot=(90, 0, 0), mat="M_Metal", verts=12, r2=0.3)
    mb.cyl(0.24, 0.03, loc=(px, py - 1.02, 9.8), rot=(90, 0, 0), mat="M_Glow_window", verts=12)
    mb.build("X1010000_RedTower_Deco", coll, smooth=True, sharp_angle=40)


@asset("X1010000_YellowHouse", "Architecture", footprint=7.0, tags=("house", "mushroom"), pack=HOUSE_PACK)  # #75
def _yellow_house(coll):
    """The yellow-capped house by the west gate (classic house1): smooth yellow cap, green bamboo door."""
    mushroom_house_v2(coll, "X1010000_YellowHouse", "M_Grad_leaf_yellow_dk__mush_yellow", chimney="barrel")
    mb = MeshBuilder()
    front = -2.0 * 1.06
    # bamboo door: vertical green poles with darker node rings, following the round door arch
    for k in range(5):
        x = -0.44 + k * 0.22
        top = 0.25 + 2.0 + math.sqrt(max(0.0, 0.62 ** 2 - x * x)) * 0.85 - 0.12
        mb.cyl(0.1, top - 0.3, loc=(x, front - 0.24, 0.3), mat="M_Flat_roof_green", verts=8)
        for z in (0.95, 1.65):
            mb.cyl(0.115, 0.05, loc=(x, front - 0.24, z + (k % 2) * 0.12), mat="M_Flat_leaf_dk", verts=8)
    mb.box((1.1, 0.05, 0.08), loc=(0, front - 0.36, 1.3), mat="M_Flat_leaf_dk")
    mb.build("X1010000_YellowHouse_Door", coll, smooth=False)


def _rect_posts(mb, pts, z0, z1, w=0.26, mat="M_Wood_Dark"):
    for (x, y) in pts:
        mb.box((w, w, z1 - z0), loc=(x, y, (z0 + z1) / 2), mat=mat, bevel=0.03, segs=1)


def _brace(mb, a, b, w=0.14, mat="M_Wood"):
    """Diagonal timber between two 3D points."""
    ax, ay, az = a
    bx, by, bz = b
    dx, dy, dz = bx - ax, by - ay, bz - az
    L = math.sqrt(dx * dx + dy * dy + dz * dz)
    yaw = math.degrees(math.atan2(dy, dx))
    pitch = math.degrees(math.atan2(dz, math.hypot(dx, dy)))
    mb.box((L, w, w), loc=((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), rot=(0, -pitch, yaw), mat=mat)


# lookout tower (T08-T10) in MAP coordinates; the asset is placed at LOOK_ORIGIN with z = 0
LOOK_ORIGIN = (54.6, 27.0)
LOOK_T08 = (50.6, 20.8, 55.8, 26.4)
LOOK_T09 = (52.2, 25.4, 57.0, 30.4)
LOOK_T10 = (53.8, 29.0, 57.6, 33.0)


@asset("X1010000_Lookout", "Architecture", footprint=6.0, tags=("landmark",))
def _lookout(coll):
    """Timber frame of the plaza lookout: tower posts, braces, a red spotted mushroom roof and a pennant.

    The walkable decks are terrain (m.deck); this is only the frame, built in map coordinates around
    LOOK_ORIGIN so it lines up with the decks.
    """
    ox, oy = LOOK_ORIGIN
    mb = MeshBuilder()

    def L(x, y):
        return (x - ox, y - oy)

    t9 = [L(52.4, 25.6), L(56.8, 25.6), L(52.4, 30.2), L(56.8, 30.2)]
    _rect_posts(mb, t9, -0.3, LOOK2 - 0.2, w=0.3)
    t10 = [L(54.0, 29.2), L(57.4, 29.2), L(54.0, 32.8), L(57.4, 32.8)]
    _rect_posts(mb, t10, -0.3, 7.75, w=0.28)
    # X braces on the east faces and the back, between the lower deck and the upper decks
    for (ya, yb, x) in ((25.6, 30.2, 56.8), (29.2, 32.8, 57.4)):
        _brace(mb, (*L(x, ya), 0.4), (*L(x, yb), LOOK2 - 0.45))
        _brace(mb, (*L(x, yb), 0.4), (*L(x, ya), LOOK2 - 0.45))
    _brace(mb, (*L(54.0, 32.8), 0.4), (*L(57.4, 32.8), LOOK3 - 0.45))
    _brace(mb, (*L(57.4, 32.8), 0.4), (*L(54.0, 32.8), LOOK3 - 0.45))
    _brace(mb, (*L(52.4, 30.2), LOOK1 + 0.3), (*L(52.4, 25.9), LOOK2 - 0.4))
    # roof plate + a red spotted mushroom roof with a pennant on top
    cx, cy = L(55.7, 31.0)
    for (ya, yb) in ((29.2, 32.8),):
        for x in (54.0, 57.4):
            mb.box((0.22, yb - ya + 0.3, 0.22), loc=(*L(x, (ya + yb) / 2), 7.75), mat="M_Wood_Dark")
    for y in (29.2, 32.8):
        mb.box((3.7, 0.22, 0.22), loc=(*L(55.7, y), 7.75), mat="M_Wood_Dark")
    mb.dome(2.75, 1.55, loc=(cx, cy, 7.85), scale=(1.0, 0.95, 1.0), mat="M_Spot_mush_red__mush_spot", u=24, v=6,
            lip=0.35, profile=0.75)
    mb.cyl(0.06, 1.7, loc=(cx, cy, 9.25), mat="M_Wood_Dark", verts=8)
    mb.sphere(0.1, loc=(cx, cy, 10.98), mat="M_Gold", subdiv=1)
    mb.prism([(0.0, 10.88), (1.25, 10.62), (0.0, 10.34)], -0.025, 0.025, loc=(cx + 0.05, cy, 0), rot=(90, 0, 0),
             mat="M_Flat_roof_yellow")
    mb.prism([(0.0, 10.88), (0.7, 10.73), (0.0, 10.58)], -0.03, 0.03, loc=(cx + 0.05, cy - 0.01, 0), rot=(90, 0, 0),
             mat="M_Flat_roof_red")
    # a lantern hanging under the roof
    mb.box((0.04, 0.04, 0.4), loc=(cx, cy, 7.25), mat="M_Metal")
    mb.box((0.28, 0.28, 0.34), loc=(cx, cy, 6.95), mat="M_Glow_window", bevel=0.03, segs=1)
    mb.build("X1010000_Lookout", coll, smooth=True, sharp_angle=40)


@asset("X1010000_MysticStone", "Props", footprint=0.6, tags=("prop", "passable"))
def _mystic_stone(coll):
    """Flat rune flagstone set into the west street: one of the six classic Mystic Door landing points (tp).
    Top ~0.1 m above its base, so it never blocks a walk."""
    mb = MeshBuilder()
    mb.cyl(0.36, 0.08, mat="M_Flat_cobble_c", verts=18)
    mb.cyl(0.27, 0.012, loc=(0, 0, 0.08), mat="M_Glow_water_lt", verts=18)
    mb.cyl(0.21, 0.016, loc=(0, 0, 0.08), mat="M_Flat_cobble_a", verts=18)
    star = [(0.0, 0.17), (0.04, 0.04), (0.17, 0.0), (0.04, -0.04), (0.0, -0.17), (-0.04, -0.04), (-0.17, 0.0),
            (-0.04, 0.04)]
    mb.prism(star, 0.08, 0.1, mat="M_Glow_water_lt")
    mb.build("X1010000_MysticStone", coll, smooth=False)


# pack (#75): TreeHouse_Giant fitted by its trunk to this trunk (r 2.6), so X1010000_TreePods (kit art) still grow out
# of it and the door stays at the trunk's front; the windows get the kit's lit M_Window back.
@asset("X1010000_GiantTree", "Architecture", footprint=12.0, tags=("house", "landmark", "tree"),
       pack=dict(parts={"Window": ["Recessed window"]}, post=part_materials({"Window": "M_Window"}),
                 fit_nodes=(["Hollow treehouse trunk"], 2 * 2.6)))
def _giant_tree(coll):
    """Amherst's giant tree-house (the kit TreeHouse_Giant trunk) under a trimmed canopy: radius 5.0 m instead of
    5.8, leaned 0.3 m east (+X), so the garden yard and the in01 arch behind it show from the island cameras."""
    r = core.rng("treehouse", 1)
    mb = MeshBuilder()
    mb.cyl(2.6, 9.0, mat="M_Bark", verts=18, r2=1.9)
    mb.cyl(3.6, 1.2, loc=(0, 0, -0.1), mat="M_Bark", verts=18, r2=2.6)
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        mb.cyl(0.9, 3.6, loc=(math.cos(a) * 2.0, math.sin(a) * 2.0, 0.6), rot=(0, 100, math.degrees(a)),
               mat="M_Bark", verts=8, r2=0.2)
    door(mb, (0, -2.45, 0.3), w=1.3, h=2.3)
    for (xx, zz) in ((-1.2, 4.0), (1.0, 5.6), (-0.3, 7.6)):
        yy = -math.sqrt(max(0.1, (2.35 - zz * 0.07) ** 2 - xx * xx))
        mb.cyl(0.5, 0.35, loc=(xx, yy + 0.1, zz), rot=(90, 0, 0), mat="M_Wood_Dark", verts=14)
        mb.cyl(0.38, 0.4, loc=(xx, yy + 0.05, zz), rot=(90, 0, 0), mat="M_Window", verts=14)
    for (xx, yy, zz, rr) in ((2.0, -1.2, 6.2, 1.4), (-2.2, -0.6, 3.6, 1.2)):
        mb.box((1.8, 1.6, 1.6), loc=(xx, yy, zz), mat="M_Plank", bevel=0.1)
        mb.dome(rr, 1.0, loc=(xx, yy, zz + 0.8), mat="M_Flat_roof_orange", u=14, v=4)
    mb.build("X1010000_GiantTree_Trunk", coll, smooth=True, sharp_angle=50)
    can = MeshBuilder()
    _puffy_canopy(can, r, 7, (0.3, 0.0, 9.4), 5.0, lobes=9, mat="M_Leaf")
    can.build("X1010000_GiantTree_Canopy", coll, smooth=True, sharp_angle=80)


@asset("X1010000_TreePods", "Architecture", footprint=3.0, tags=("house",))
def _tree_pods(coll):
    """Two orange, yellow-spotted cap pods with round windows grown into TreeHouse_Giant's trunk
    (place at the tree's origin with the tree's rotation)."""
    mb = MeshBuilder()
    for (ang, rad, z) in ((-150.0, 2.75, 2.3), (-35.0, 2.55, 4.9)):
        a = math.radians(ang)
        x, y = rad * math.cos(a), rad * math.sin(a)
        mb.cyl(0.92, 1.3, loc=(x, y, z), mat="M_Plaster", verts=16, r2=0.86)
        mb.cyl(0.98, 0.14, loc=(x, y, z + 1.2), mat="M_Wood_Dark", verts=16)
        mb.dome(1.32, 0.85, loc=(x, y, z + 1.3), mat="M_Spot_mush_orange__flower_yellow", u=18, v=5, lip=0.18,
                profile=0.8)
        # bracket under the pod (a stubby branch) and a round window facing out (toward -y)
        mb.cyl(0.75, 0.6, loc=(x * 0.86, y * 0.86, z - 0.55), mat="M_Bark", verts=10, r2=0.95)
        wa = math.atan2(y - 0.9, x)
        wx, wy = x + math.cos(wa) * 0.82, y + math.sin(wa) * 0.82
        rz = math.degrees(wa) + 90
        mb.cyl(0.36, 0.16, loc=(wx, wy, z + 0.62), rot=(90, 0, rz), mat="M_Wood_Dark", verts=14)
        mb.cyl(0.27, 0.2, loc=(wx, wy, z + 0.62), rot=(90, 0, rz), mat="M_Glow_window", verts=14)
    mb.build("X1010000_TreePods", coll, smooth=True, sharp_angle=40)


# ---------------------------------------------------------------------------
# Map
# ---------------------------------------------------------------------------

def build(m):
    L, D = m.size  # 76 x 40

    # ================= terrain =================
    # T04 town square: the raised middle terrace (notched at the back-left for the T11 ledge)
    plaza = [(25.5, 4.6), (33, 3.8), (42, 3.6), (50.6, 4.4), (51.4, 10), (51.2, 18), (52.2, 24), (52.0, 31),
             (50.4, 37.8), (40, 38.2), (31.0, 37.8), (31.0, 22.0), (25.5, 20.5)]
    m.terrace("Plaza", plaza, top=PLAZA, bottom=-0.5, style="grass_stone")
    # paved square in front of the Department Store (a 15 cm curb), in the pale town paving
    _retint(m.terrace("Square", geo.rounded_rect(31.5, 8.6, 47.5, 22.5, 3.0), top=PLAZA + 0.15, bottom=PLAZA - 0.3,
                      style="cobble"))

    # T02 slope + T03 landing + the 60 px step (west street -> square): two gentle cobble slopes
    m.terrace("WestLanding", geo.rounded_rect(20.6, 5.6, 26.8, 16.8, 1.2), top=STEP, bottom=-0.5,
              style="grass_stone")
    _retint(m.ramp("WestRamp", (16.6, 11.0, 0.0), (21.6, 11.0, STEP), 4.2, style="cobble", extend=0.4))
    _retint(m.ramp("WestStep", (22.6, 11.0, STEP), (26.1, 11.0, PLAZA), 4.0, style="cobble", extend=0.4))

    # T05 + T06: two cobble slopes down from the square to the east street
    _retint(m.terrace("EastStep", geo.rounded_rect(50.0, 6.0, 56.0, 15.6, 1.0), top=STEP, bottom=-0.5,
                      style="cobble"))
    _retint(m.ramp("EastSlope_Upper", (54.0, 11.0, STEP), (50.8, 11.0, PLAZA), 4.0, style="cobble", extend=0.45))
    _retint(m.ramp("EastSlope_Lower", (59.0, 11.0, 0.0), (55.4, 11.0, STEP), 4.0, style="cobble", extend=0.45))

    # T12 upper plateau (behind the west street) and the T11 ledge at the top of the rope + ladder
    plateau = [(1.0, 25.6), (7, 25.0), (13, 24.4), (19, 24.9), (24.5, 25.3), (31.8, 25.1), (32.4, 31),
               (31.8, 39.6), (16, 39.8), (0.8, 39.6), (0.6, 32)]
    m.terrace("Plateau", plateau, top=PLATEAU, bottom=-0.5, style="grass_stone")
    m.terrace("Ledge_T11", geo.rounded_rect(25.0, 19.6, 31.8, 27.0, 1.4), top=LANDING, bottom=-0.5,
              style="grass_stone")
    # the only way up: rope (x 917) + ladder (x 991), 74 px apart on the same face
    m.ladder("Rope_Plateau", 26.9, 19.1, PLAZA, LANDING, kind="rope")
    m.ladder("Ladder_Plateau", 28.9, 19.1, PLAZA, LANDING, facing=90)
    # the 60 px step from the ledge onto the plateau: a short grassy slope toward the back; the pale cobble
    # PlateauWalk ribbon is draped over it from the ladder top (no cobble block / flap of its own)
    m.ramp("LedgeSlope", (29.6, 21.5, LANDING), (29.6, 25.9, PLATEAU), 3.4, style="grass_stone", top_mat=None,
           extend=0.2)

    # T08 / T09 / T10: a timber lookout at the square's east corner (classic: two floating ledges and a
    # rope above the east steps). Steps from the square onto T08, the rope up to T09, three steps to the
    # roofed crow's nest T10.
    m.deck("Look_T08", geo.rect(*LOOK_T08), top=LOOK1, post_bottom=-0.3)
    m.deck("Look_T09", geo.rect(*LOOK_T09), top=LOOK2, posts=False)
    m.deck("Look_T10", geo.rect(*LOOK_T10), top=LOOK3, posts=False)
    m.stairs("Look_Steps", (47.6, 23.0, PLAZA), (51.0, 23.0, LOOK1), 2.2)
    m.ladder("Rope_Look", 54.0, 25.1, LOOK1, LOOK2, kind="rope")
    m.stairs("Look_TopSteps", (55.6, 27.0, LOOK2), (55.6, 29.5, LOOK3), 1.6)
    m.place("X1010000_Lookout", *LOOK_ORIGIN, z=0.0)
    m.rail("Look_T08_Rail", [(51.6, 20.8), (55.8, 20.8), (55.8, 25.3)], LOOK1, closed=False)
    m.rail("Look_T09_RailW", [(53.2, 25.4), (52.2, 25.4), (52.2, 30.4), (53.8, 30.4)], LOOK2, closed=False)
    m.rail("Look_T09_RailE", [(54.8, 25.4), (57.0, 25.4), (57.0, 28.8)], LOOK2, closed=False)
    m.rail("Look_T10_Rail", [(54.7, 29.0), (53.8, 29.0), (53.8, 33.0), (57.6, 33.0), (57.6, 29.0), (56.5, 29.0)],
           LOOK3, closed=False)

    # raised garden yard at the back: in01 -> Townstreet, whose cutaway orange house stands just behind
    # the back edge, seen straight up this lane
    m.terrace("GardenYard", geo.rounded_rect(58.4, 31.6, 70.6, 40.8, 1.6), top=YARD, bottom=-0.5,
              style="grass_stone")
    m.stairs("YardSteps", (64.0, 29.6, 0.0), (64.0, 32.2, YARD), 4.0, mat="M_StoneWall", side_mat="M_Rock")

    # cobble streets
    # one continuous cobble street draped over both slope pairs, so no grass shows where a slope tucks
    # under a terrace lip
    pale = _pale_cobble()
    m.path("MainStreet", [(0.0, 12.0), (8, 11.8), (15.5, 11.25), (19.0, 11.0), (36, 11.3), (44, 11.3), (50.2, 11.0),
                          (60.0, 11.0), (66, 11.6), (76.0, 12.0)], width=3.8, mat=pale,
           step=0.3)
    m.path("YardLane", [(62.0, 12.5), (63.2, 20), (64.0, 29.4)], width=3.0, mat=pale)
    m.path("YardWalk", [(64.0, 33.0), (64.0, 40.4)], width=3.0, mat=pale)
    # from the ladder/rope top, up the grassy LedgeSlope and along the vista to the Weapon Store door
    m.path("PlateauWalk", [(28.9, 20.5), (29.3, 21.7), (29.6, 23.4), (29.6, 26.4), (22, 28.2), (14.0, 28.4),
                           (11.1, 29.6)], width=2.6, mat=pale, step=0.3)
    m.path("StoreDoor", [(38.6, 21.8), (38.65, 25.4)], width=2.6, mat=pale)

    # ================= landmarks =================
    # west street: the yellow-capped house + the red mushroom tower against the plateau wall
    m.place("X1010000_YellowHouse", 9.6, 20.6, rot=-6)
    # 1.2x so the red spotted tower carries from the island/region cameras (cap back edge stays ~0.8 m off the
    # plateau face)
    m.place("X1010000_RedTower", 18.4, 20.7, rot=6, scale=1.2)
    m.place("X1010000_TownGate", 3.4, 12.0, rot=68)
    m.place("Mailbox_Red", 5.4, 16.2, rot=-10)
    m.place("Tree_Birch_Orange", 23.0, 18.4, rot=40, scale=0.85)
    m.place("X1010000_Birdhouse", 24.4, 17.2, rot=-15)
    # Pio's farm plot (with his sacks) in front of the tower, leaving the tower door clear
    m.place("Veg_Garden_Bed", 15.0, 16.6, rot=-4)
    m.place("Sack", 21.4, 16.9, rot=20)
    m.place("Sack", 22.0, 17.6, rot=-30, scale=0.9)
    m.place("Crate_Stack", 12.6, 18.8, rot=10)
    m.place("Barrel", 6.6, 17.8)
    # plateau: the Weapon Store (in00) with its sword sign and a thatched lean-to annex, Mai's barrels,
    # the two framing trees
    # 1.2x (island-scale read), set 0.8 m further back so the door and its in00 threshold stay where they were
    m.place("House_Wood_TwoStory_Capped", 12.5, 33.4, rot=0, scale=1.2)
    m.place("X1010000_Annex", 18.0, 33.0, rot=0)
    m.place("X1010000_SwordSign", 16.75, 30.0, rot=0)
    m.place("Weapon_Rack", 19.6, 30.6, rot=0)
    m.place("Barrel", 25.4, 30.6)
    m.place("Barrel", 26.5, 31.3, rot=40)
    m.place("Tree_Round_B", 3.6, 31.6, rot=20)
    m.place("Tree_Birch_Yellow", 21.4, 35.2, rot=70)
    # town square: the lime Department Store (in02), the rainbow spring centre-stage, planters, benches,
    # Lucas's grove
    m.place("X1010000_DeptStore", 39.3, 28.3, rot=0, scale=1.1)
    m.place("X1010000_PotionSign", 43.0, 24.7, rot=-6)
    m.place("Rainbow_Spring", 41.0, 16.0, rot=0, scale=2.0)
    m.place("Planter", 32.6, 14.2, rot=10)
    m.place("Planter", 32.6, 21.0, rot=-40)
    m.place("Planter", 46.4, 13.8, rot=25)
    m.place("Bench", 32.4, 17.6, rot=90)
    m.place("Bench", 46.4, 18.4, rot=-90)
    m.place("Tree_Round_B", 47.4, 29.4, rot=110)
    m.place("Tree_Round_C", 49.0, 33.6, rot=30)
    # east street: fairground cut-outs, banner, the giant tree-house (with its cap pods) at the exit
    m.place("X1010000_FaceCutout_Red", 56.9, 16.3, rot=6, scale=1.3)
    m.place("X1010000_FaceCutout_Yellow", 58.8, 16.6, rot=-4, scale=1.3)
    m.place("X1010000_BannerPole", 60.0, 17.2, rot=0, scale=1.15)
    for (x, y, a) in ((8.0, 17.4, "Mushroom_Yellow_S"), (35.0, 24.0, "Mushroom_Orange_S"),
                      (59.2, 35.6, "Mushroom_Orange_S"), (4.2, 29.0, "Mushroom_Blue_S")):
        m.place(a, x, y, rot=x * 13, scale=1.3)
    m.place("X1010000_GiantTree", 71.5, 19.0, rot=-12)
    m.place("X1010000_TreePods", 71.5, 19.0, rot=-12)
    m.place("Mushroom_Cluster_A", 74.3, 15.4, rot=20)
    m.place("Mushroom_Red_S", 73.2, 15.0, rot=0, scale=1.4)
    # the garden yard: a leafy arch over the lane marks the way to Townstreet (in01), hedges either side
    m.place("Arch_Leafy", 64.0, 39.2, rot=0)
    m.place("Hedge_Wall_4m", 58.9, 32.5, rot=0, scale=(0.8, 1.0, 0.85))
    m.place("Hedge_Wall_4m", 66.0, 32.5, rot=0, scale=(0.95, 1.0, 0.85))
    m.place("Flower_Bed_Large", 60.2, 39.0, rot=40)
    m.place("Flower_Bed_Large", 67.8, 39.0, rot=-20)
    m.place("Ivy_Sign", 66.0, 33.0, rot=90)
    m.place("Crate", 69.2, 33.2, rot=30)
    m.place("Barrel", 69.6, 34.3)
    for x in (59.8, 61.2, 66.9, 68.6):
        m.place("Vine_Hanging_A", x, 31.5, z=YARD - 0.15, rot=0, scale=1.1)

    # ================= dressing =================
    # lamps + benches along the streets and on the square
    for (x, y) in ((7.0, 9.0), (16.0, 9.0), (30.6, 15.0), (47.8, 15.2), (30.8, 7.0), (48.4, 7.2), (58.6, 8.4),
                   (69.0, 8.6), (61.4, 29.4), (66.6, 29.4)):
        m.place("Lamp_Post", x, y)
    m.place("Bench", 11.4, 15.4, rot=0)
    m.place("Bench", 66.4, 16.0, rot=-6)
    # low white pickets along the street front (broken at the lamps)
    for seg in (((3.6, 8.7), (6.3, 8.7)), ((7.7, 8.7), (15.3, 8.7)), ((60.0, 8.7), (68.0, 8.7)),
                ((70.0, 8.7), (74.0, 8.7))):
        m.fence(list(seg), asset_name="Fence_Picket_Seg")
    m.place("Crate", 33.4, 24.6, rot=15)
    m.place("Signpost_Notice", 49.4, 19.4, rot=-20)
    m.place("Sign_Board", 27.6, 7.6, rot=-8)
    # T11 ledge at the top of the rope + ladder: a lamp, a crate and an arrow toward the Weapon Store (the lip
    # stays open: the rope and ladder tops are the ledge's front)
    m.place("Lamp_Post", 26.0, 24.6)
    m.place("Crate", 25.9, 22.6, rot=12)
    m.place("Sign_Arrow", 31.3, 21.0, rot=165)
    # lookout: a barrel on T09
    m.place("Barrel", 53.3, 28.8, rot=30)
    # flower beds
    for (x, y) in ((11.5, 5.0), (29.0, 6.0), (45.0, 6.2), (73.0, 6.0)):
        m.place("Flower_Bed_Large", x, y, rot=(x * 37) % 360)
    # plateau edge fence (the vista over the west street) and vines down the bastion wall
    m.fence([(2.0, 26.9), (7.0, 26.3), (13.0, 25.7), (19.0, 26.2), (24.2, 26.6)])
    for x in (2.6, 6.2, 16.4, 23.6, 30.9):
        y = 24.9 if x < 25 else 19.4
        z = PLATEAU - 0.15 if x < 25 else LANDING - 0.15
        m.place("Vine_Hanging_A", x, y - 0.1, z=z, rot=0, scale=1.3)
    # trees framing the back and the sides
    for i, (x, y) in enumerate([(7.6, 38.2), (17.6, 38.8), (28.4, 37.6), (33.2, 35.4), (38.4, 36.8), (44.2, 35.8),
                                (53.0, 37.6), (74.6, 28.0), (74.0, 37.0), (57.0, 38.6)]):
        m.place(["Tree_Round_A", "Tree_Birch_Orange", "Tree_Round_C", "Tree_Birch_Yellow"][i % 4], x, y,
                rot=i * 53, scale=0.9 + (i % 3) * 0.08)
    for i, (x, y) in enumerate([(4.8, 23.6), (13.9, 23.9), (25.6, 18.0), (31.5, 33.0), (57.8, 20.4), (59.0, 24.4),
                                (70.0, 30.8), (75.0, 22.0), (53.4, 3.2), (66.0, 3.4), (20.0, 3.0), (36.0, 2.6),
                                (6.0, 35.0), (28.6, 33.4), (44.6, 32.6), (71.6, 39.0)]):
        m.place(["Bush_A", "Bush_B", "Bush_C", "Bush_Flowering_A"][i % 4], x, y, rot=i * 41)
    m.place("Rock_A", 24.6, 19.3, rot=10)
    m.place("Rock_B", 52.6, 19.6, rot=50, scale=0.8)
    m.place("Rock_C", 0.8, 24.4)
    m.place("Butterfly", 30.0, 9.0)
    m.place("Butterfly", 62.0, 6.0)
    # the six classic Mystic Door landing points (tp, x 169..621 px on the west street): glowing rune flagstones
    # set flush into the cobbles along the street's south half (flat: nothing to trip on)
    for i, x in enumerate((8.0, 9.6, 11.2, 12.8, 14.4, 15.9)):
        yc = 11.8 + (11.25 - 11.8) * (x - 8.0) / 7.5
        m.place("X1010000_MysticStone", x, yc - 1.2 - (0.15 if i % 2 else 0.0), rot=i * 23)
    # a small market green in the low front band (stalls <= 2.5 m, well in front of the street): Amherst reads as a
    # town from the region cameras, and the street (y 9.4-14) stays clear
    m.place("Market_Stall", 17.6, 5.4, rot=0)
    m.place("Sack", 19.4, 5.9, rot=25)
    m.place("Market_Stall", 63.4, 5.2, rot=4)
    m.place("Barrel", 65.2, 5.8)
    m.place("Cart", 70.2, 4.4, rot=200)
    routes_avoid = [geo.rect(0, 9.4, 76, 14.0), geo.rect(61, 12, 66.5, 40.6), geo.rect(33.4, 12, 45, 26),
                    geo.rect(26.5, 13, 31.5, 23), geo.rect(10, 26.4, 31, 29.6), geo.rect(42, 20, 58.4, 34),
                    geo.rect(49.6, 5.6, 56.4, 16.0)]
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0.5, 0.5, 75.5, 39.5), 70, seed=7,
              min_dist=1.8, avoid=routes_avoid)
    # the low front band: flower meadow, sunflowers, a few rocks at the foot of the square's wall
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A", "Sunflower_Patch"], geo.rect(0.5, 0.3, 75.5, 8.2),
              46, seed=11, min_dist=1.4, avoid=routes_avoid + [geo.rect(25, 3.2, 52, 9)])
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A"], geo.rect(25.5, 4.4, 51, 8.4), 14, seed=12,
              min_dist=1.3, z_band=(1.4, 1.9))
    # low clumps (marigold, clover, iris, little bushes) so the meadow reads as a cared-for town green
    m.scatter(["Marigold_Patch", "Clover_Patch", "Iris_Patch", "Bush_C"], geo.rect(0.5, 0.4, 75.5, 8.0), 24, seed=21,
              min_dist=2.4, avoid=routes_avoid + [geo.rect(24.5, 3.0, 52.5, 9)])
    for i, x in enumerate((27.0, 33.5, 41.0, 47.5)):
        m.place(["Rock_A", "Rock_C", "Rock_B", "Rock_C"][i], x, 3.0, rot=i * 70, scale=0.7)
    # plateau garden: flowers, a bench at the vista, bushes round the store
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A", "Flower_Patch_A"], geo.rect(1.5, 26.8, 31, 39),
              22, seed=13, min_dist=1.6, z_band=(6.9, 7.6), avoid=[geo.rect(10, 26.0, 31, 30.2),
                                                                   geo.rect(6.6, 28.5, 20.0, 38.6)])
    m.place("Bench", 5.6, 27.6, rot=0)
    m.place("Bush_Flowering_A", 21.0, 33.6, rot=30)
    m.place("Bush_A", 7.4, 34.6, rot=80)
    m.place("Flower_Bed_Large", 26.0, 35.0, rot=20)

    # ================= gameplay =================
    m.edge_portal("west00")
    m.edge_portal("east00")
    m.edge_portal("in01")
    m.door_portal("in00", 11.06, 29.75)
    m.door_portal("in02", 38.65, 25.3)
    m.npc("Rain", 9.8, 15.0, rot=10)
    m.npc("Pio", 19.9, 15.6, rot=-30)
    m.npc("Lucas", 47.3, 25.2, rot=-25)
    # (Mai is not an Amherst NPC in MeowDB MS Classic: she stands on A Split Road, 000000050)
    # on the square at the foot of the plateau ladder, 0.6 m off the Plateau route, facing the camera
    m.player(28.3, 16.4, rot=-20)
    m.player_spawn(13.6, 11.8, rot=90, note="sp x 282: on the west street between Rain and Pio")

    m.route("Main", [(1, 12), (8, 11.8), (15.5, 11.3), (21.8, 11.0), (24.3, 11.0), (27.2, 11.0), (36, 11.4),
                     (44, 11.4), (49.8, 11.0), (53.0, 11.0), (56.8, 11.0), (66, 11.6), (75, 12)])
    # plateau: square -> up the ladder onto T11 -> the cobble slope -> along the vista to the Weapon Store
    m.route("Plateau", [(29.0, 11.1), (29.0, 12.0), (28.9, 16.0), (28.9, 18.6), (28.9, 20.4), (28.9, 21.2), (29.6, 22.0),
                        (29.6, 26.4), (22.0, 28.2), (14.0, 28.4), (11.2, 29.0)])
    m.route("ToDeptStore", [(36.4, 11.6), (35.4, 15.0), (35.6, 19.6), (38.0, 22.4), (38.65, 24.6)])
    # lookout: steps onto T08, rope up to T09, steps up to the roofed T10
    m.route("Lookout", [(38.23, 23.4), (43.6, 22.2), (47.0, 23.0), (51.6, 23.0), (53.0, 23.4), (54.0, 24.0), (54.0, 26.2),
                        (55.6, 26.6), (55.6, 30.4)])
    m.route("ToTownstreet", [(62.0, 12.0), (63.2, 20.0), (64.0, 28.6), (64.0, 33.4), (64.0, 38.8)])
