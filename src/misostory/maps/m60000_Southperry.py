"""Southperry (60000) - "the harbour amphitheatre".

Classic (GMS v8) structure, from docs/research/maps/60000_Southperry_60000.md:
  west town ground T29 (west00, Tia, Maple Administrator, Yoona, the blue-domed house with
  Paul on its unreachable slab T21) -> 240 px cliff (ledge T30 with two ropes down) -> sunken
  market street T34 (Armor Store door in00, Bari, a second domed house, cloth racks) that ramps
  up 120 px -> the lighthouse on its rock hump T28 -> a 7-rise grand staircase -> the quay T20
  (Shanks) -> gangplank -> the ship (deck, mast ropes up to the masthead). High above the street
  floats Biggs's terrace T12/T10 with a market canopy, reached by ladder x405 from the ledge or
  by ladder x1649 plus the slab stair T22..T13.

3D translation: the west -> east line becomes a descent into a sunken whitewashed street and a
climb to a high quay. Higher tiers step back (+y): the street is lined on its back side by the
Armor Store and the domed tower; behind them rises the sandstone belvedere (Biggs), whose walkable
front strip is backed by a row of whitewashed houses. Southperry's front edge is the island rim:
the ship <Victoria> hovers on its barrel engines off the quay's front lip, broadside to the camera,
tied to bollards, and the tall lighthouse stands on the quay's front-east corner beside its bow
(classic world map). Behind the quay a harbour quarter of stepped whitewashed houses climbs in two
terraces. The grand staircase turns toward the back (+y) from the street's front promenade so its
risers face the camera. The trail from A Split Road arrives at west00 on the square's back edge and
a paved road leads from it down to the west stair (ArrivalRoad).

NPCs follow MeowDB MS Classic (Iteration Two): Yoona, Bari, Shanks and Biggs. The v8 extras Tia, the Maple
Administrator and Paul are not placed.
"""

import math

from mathutils import Vector

from misostory import collision_tags as CT
from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.architecture import chimney, door, gable_roof, window
from misostory.mapkit import MAIN_ROAD

MAP_ID = 60000
# Gameplay view: the boarding point - quay front strip, ticket booth, Shanks at the gangplank foot, the deck and
# the foot of the grand stair
GAMEPLAY_FOCUS = (64.0, 9.0)
GAMEPLAY_SCALE = 50.0
# the moored ship's hull and bowsprit overhang the front rim: keep them in the Overview fit
OVERVIEW_EXTRA = [(60, -9, 92, 0)]

Z_SQ = 3.3      # west town square (T29), ~ trail height from A Split Road
Z_ST = 0.8      # sunken market street (T34 west part)
Z_UP = 2.2      # upper street (T34 east part)
Z_MOUND = 3.6   # lighthouse knoll (T28)
Z_QUAY = 5.6    # quay (T20)
Z_SLAB = 6.2    # slab-stair landing (T22)
Z_BW = 8.2      # belvedere west (T12)
Z_BE = 9.0      # belvedere east (T10, Biggs)
Z_QL = 8.0      # harbour quarter, lower terrace (behind the quay)
Z_QH = 9.6      # harbour quarter, upper terrace
WALL = "M_Whitewash"  # whitewash for houses, parapets and wall dressing
SHIP = (74.5, -4.3)  # ship centre, moored off the quay's front lip over the island rim; bow toward +x
# The walkable ship decks are terrain and the validator rejects terrain beyond 6 m off the footprint, so the
# deck polygons are clipped at y = SHIP_DECK_YMIN (the port strip beyond is visual hull only).
SHIP_DECK_YMIN = -5.85


# =====================================================================================
# Local assets (map-prefixed; candidates for the shared kit)
# =====================================================================================

def _star(r_out, r_in, n=5):
    pts = []
    for k in range(n * 2):
        a = math.pi / 2 + k * math.pi / n
        r = r_out if k % 2 == 0 else r_in
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


def _wall_star(mb, x, y, z, r, mat):
    """Flat starfish decoration on a wall facing -y."""
    mb.prism(_star(r, r * 0.45), 0.0, 0.06, loc=(x, y, z), rot=(90, 0, 0), mat=mat)


def _window_px(mb, loc, w=0.9, h=1.0, frame_mat="M_Wood_Dark", shutter_mat=None):
    """Window on a wall facing +x (kit window() only offers -Y / -X). At world yaw -67 the +x walls are
    the camera-facing side walls of this map."""
    x, y, z = loc
    mb.box((0.14, w + 0.22, h + 0.22), loc=(x + 0.03, y, z), mat=frame_mat, bevel=0.04, segs=1)
    mb.box((0.16, w, h), loc=(x + 0.06, y, z), mat="M_Window")
    mb.box((0.2, 0.07, h), loc=(x + 0.08, y, z), mat=frame_mat)
    mb.box((0.2, w, 0.07), loc=(x + 0.08, y, z), mat=frame_mat)
    if shutter_mat:
        for s in (-1, 1):
            mb.box((0.08, w * 0.45, h + 0.1), loc=(x + 0.08, y + s * (w * 0.75 + 0.1), z), mat=shutter_mat,
                   bevel=0.03, segs=1)


@asset("X60000_ArmorStore", "Architecture", footprint=8.0, tags=("house", "shop", "port"))
def _armor_store(coll):
    """Southperry Armor Store (housePT/house1): white plaster walls, a swooping blue tiled roof with a
    scalloped eave, a chimney topped with barrels and an arched pinkish door.
    Door centre at x=-1.0 on the front face y=-2.5 (faces -y)."""
    W, Dd, H = 7.0, 5.0, 3.6
    mb = MeshBuilder()
    mb.box((W + 0.5, Dd + 0.5, 0.5), loc=(0, 0, 0.2), mat="M_Sand_Cliff", bevel=0.08)
    mb.box((W, Dd, H), loc=(0, 0, 0.4 + H / 2), mat=WALL, bevel=0.14, segs=2)
    door(mb, (-1.0, -Dd / 2, 0.4), w=1.5, h=2.0, mat="M_Grad_door__flower_pink")
    window(mb, (-2.65, -Dd / 2, 2.85), w=0.8, h=0.7, shutter_mat="M_Flat_roof_blue")
    mb.box((1.3, 0.7, 0.1), loc=(-2.65, -Dd / 2 - 0.3, 3.38), rot=(-22, 0, 0), mat="M_Plank", bevel=0.02, segs=1)
    window(mb, (1.9, -Dd / 2, 2.0), w=1.1, h=1.0, shutter_mat="M_Flat_roof_blue", flowerbox=True)
    _window_px(mb, (W / 2, 0.6, 2.1), w=0.9, h=0.9, shutter_mat="M_Flat_roof_blue")
    # chimney topped with two barrels
    mb.box((1.1, 1.1, 3.4), loc=(2.3, 0.9, 0.4 + H + 1.7), mat=WALL, bevel=0.1)
    mb.box((1.3, 1.3, 0.22), loc=(2.3, 0.9, 0.4 + H + 3.4), mat=WALL, bevel=0.06)
    for bx, by in ((2.05, 0.75), (2.6, 1.1)):
        z0 = 0.4 + H + 3.5
        mb.cyl(0.3, 0.75, loc=(bx, by, z0), mat="M_Wood", verts=12, r2=0.33)
        for zz in (0.15, 0.55):
            mb.cyl(0.34, 0.06, loc=(bx, by, z0 + zz), mat="M_Metal", verts=12)
    # barrels by the front-right corner
    for bx, by in ((3.15, -2.95), (3.85, -2.35)):
        mb.cyl(0.36, 0.95, loc=(bx, by, 0.0), mat="M_Wood", verts=12, r2=0.4)
        for zz in (0.2, 0.7):
            mb.cyl(0.42, 0.07, loc=(bx, by, zz), mat="M_Metal", verts=12)
    mb.build("X60000_ArmorStore", coll, smooth=True, sharp_angle=35)
    roof = MeshBuilder()
    z0 = 0.4 + H
    rh, ov = 2.5, 0.65
    gable_roof(roof, W, Dd, rh, (0, 0, z0), "M_Flat_roof_blue", overhang=ov, thickness=0.34, gable_mat=WALL)
    half = Dd / 2 + ov
    ang = math.degrees(math.atan2(rh, half))
    for s in (-1, 1):
        for k in range(1, 5):  # tile ribs read as a wavy tiled roof
            t = k / 5
            roof.box((W + ov * 2 - 0.1, 0.16, 0.16), loc=(0, s * half * (1 - t), z0 + rh * t + 0.36),
                     rot=(-s * ang, 0, 0), mat="M_Flat_bsnail_shell_dk", bevel=0.04, segs=1)
        for i in range(13):  # scalloped eave
            x = -W / 2 - ov + 0.3 + i * (W + 2 * ov - 0.6) / 12
            roof.sphere(0.3, loc=(x, s * (half + 0.02), z0 - 0.02), scale=(1.0, 0.55, 0.7), mat="M_Flat_roof_blue",
                        subdiv=1)
    roof.box((W + ov * 2 + 0.1, 0.4, 0.3), loc=(0, 0, z0 + rh + 0.2), mat="M_Flat_bsnail_shell_dk", bevel=0.1)
    roof.build("X60000_ArmorStore_Roof", coll, smooth=True, sharp_angle=40)


@asset("X60000_DomeHouse", "Architecture", footprint=8.0, tags=("house", "port", "landmark"))
def _dome_house(coll):
    """housePT/house0: whitewashed house with a blue dome, a flat-roofed front wing (roof slab top at
    z=2.92 is supplied by the map as a walkable deck - Paul's terrace), blue doors and shutters,
    starfish decorations and a tall arched bell wall on its east side."""
    mb = MeshBuilder()
    mb.box((5.6, 5.0, 0.4), loc=(0, 1.0, 0.15), mat="M_Sand_Cliff", bevel=0.06)
    mb.box((5.2, 4.6, 5.0), loc=(0, 1.0, 2.5), mat=WALL, bevel=0.16, segs=2)
    mb.box((5.5, 4.9, 0.25), loc=(0, 1.0, 5.0), mat=WALL, bevel=0.06)
    # front wing (one storey); parapet around its roof terrace
    mb.box((4.0, 2.5, 2.65), loc=(-0.6, -2.45, 1.325), mat=WALL, bevel=0.1)
    for (sx, sy, lx, ly) in ((-0.6, -3.62, 4.1, 0.24), (-2.55, -2.45, 0.24, 2.5), (1.35, -2.45, 0.24, 2.5)):
        mb.box((lx, ly, 0.55), loc=(sx, sy, 3.1), mat=WALL, bevel=0.06)
    door(mb, (-0.6, -3.7, 0.0), w=1.1, h=1.85, mat="M_Flat_roof_blue")
    window(mb, (0.75, -3.7, 1.5), w=0.6, h=0.7, shutter_mat="M_Flat_roof_blue")
    door(mb, (-0.9, -1.3, 2.92), w=0.9, h=1.55, mat="M_Flat_roof_blue")
    window(mb, (1.3, -1.3, 4.0), w=0.8, h=0.9, shutter_mat="M_Flat_roof_blue")
    _window_px(mb, (2.6, 1.9, 3.6), w=0.8, h=0.9, shutter_mat="M_Flat_roof_blue")
    _window_px(mb, (2.6, 1.9, 1.5), w=0.8, h=0.9, shutter_mat="M_Flat_roof_blue")
    # blue dome on a drum
    mb.cyl(1.75, 0.5, loc=(0.3, 1.2, 5.1), mat=WALL, verts=24)
    mb.dome(1.8, 1.8, loc=(0.3, 1.2, 5.6), mat="M_Flat_roof_blue", u=24, v=6)
    mb.cyl(0.07, 0.6, loc=(0.3, 1.2, 7.35), mat="M_Gold", verts=6)
    mb.sphere(0.17, loc=(0.3, 1.2, 7.4), mat="M_Gold", subdiv=1)
    # tall arched bell wall (east wing)
    for px in (2.75, 4.25):
        mb.box((0.5, 0.7, 4.4), loc=(px, 0.2, 2.2), mat=WALL, bevel=0.08)
    mb.box((2.0, 0.7, 1.0), loc=(3.5, 0.2, 4.9), mat=WALL, bevel=0.08)
    mb.cyl(1.0, 0.7, loc=(3.5, 0.55, 5.35), rot=(90, 0, 0), mat=WALL, verts=16)
    mb.cyl(0.62, 0.72, loc=(3.5, 0.56, 4.25), rot=(90, 0, 0), mat=WALL, verts=14)
    mb.cyl(0.05, 0.3, loc=(3.5, 0.2, 3.7), mat="M_Metal", verts=6)
    mb.cyl(0.36, 0.55, loc=(3.5, 0.2, 3.15), mat="M_Gold", verts=12, r2=0.18)
    mb.box((2.1, 0.8, 0.3), loc=(3.5, 0.2, 0.15), mat="M_Sand_Cliff", bevel=0.05)
    # starfish decorations
    _wall_star(mb, -1.9, -3.75, 2.1, 0.28, "M_Flat_roof_orange")
    _wall_star(mb, 2.0, -1.35, 3.4, 0.24, "M_Flat_flower_pink")
    _wall_star(mb, 3.5, -0.18, 1.6, 0.22, "M_Flat_roof_orange")
    mb.build("X60000_DomeHouse", coll, smooth=True, sharp_angle=35)


@asset("X60000_DomeTower", "Architecture", footprint=5.0, tags=("house", "port"))
def _dome_tower(coll):
    """housePT/house2: square whitewashed tower with a blue dome and a drainpipe (faces -y)."""
    mb = MeshBuilder()
    mb.box((4.4, 4.4, 0.4), loc=(0, 0, 0.15), mat="M_Sand_Cliff", bevel=0.06)
    mb.box((4.0, 4.0, 6.6), loc=(0, 0, 3.3), mat=WALL, bevel=0.16, segs=2)
    mb.box((4.3, 4.3, 0.3), loc=(0, 0, 6.6), mat=WALL, bevel=0.08)
    door(mb, (-0.7, -2.0, 0.0), w=1.0, h=1.9, mat="M_Flat_roof_blue")
    window(mb, (0.95, -2.0, 1.9), w=0.75, h=0.85, shutter_mat="M_Flat_roof_blue")
    window(mb, (0.0, -2.0, 4.7), w=0.9, h=1.0, shutter_mat="M_Flat_roof_blue", flowerbox=True)
    _window_px(mb, (2.0, 0.3, 4.4), w=0.8, h=0.9, shutter_mat="M_Flat_roof_blue")
    _window_px(mb, (2.0, 0.3, 1.9), w=0.7, h=0.8, shutter_mat="M_Flat_roof_blue")
    mb.cyl(0.08, 6.35, loc=(1.88, -2.12, 0.1), mat="M_Metal", verts=8)
    mb.box((0.55, 0.4, 0.2), loc=(1.75, -2.02, 6.42), mat="M_Metal")
    mb.box((0.35, 0.3, 0.12), loc=(1.88, -2.25, 0.12), mat="M_Metal")
    mb.cyl(1.7, 0.45, loc=(0, 0, 6.75), mat=WALL, verts=24)
    mb.dome(1.75, 1.9, loc=(0, 0, 7.2), mat="M_Flat_roof_blue", u=24, v=6)
    mb.sphere(0.16, loc=(0, 0, 9.15), mat="M_Gold", subdiv=1)
    _wall_star(mb, -1.2, -2.05, 3.3, 0.22, "M_Flat_flower_pink")
    mb.build("X60000_DomeTower", coll, smooth=True, sharp_angle=35)


@asset("X60000_Gazebo", "Architecture", footprint=4.5, tags=("prop", "town"))
def _gazebo(coll):
    """Market canopy on Biggs's terrace: striped canvas pyramid on four posts, scalloped valance."""
    mb = MeshBuilder()
    mb.box((4.3, 4.3, 0.16), loc=(0, 0, 0.08), mat="M_Plank", bevel=0.03, segs=1)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.cyl(0.12, 2.6, loc=(sx * 1.9, sy * 1.9, 0.1), mat="M_Wood_Dark", verts=8)
    mb.build("X60000_Gazebo", coll, smooth=False)
    roof = MeshBuilder()
    roof.cyl(3.15, 1.55, loc=(0, 0, 2.6), rot=(0, 0, 45), verts=4, r2=0.06, mat="M_Streak_cloth_white__cloth_red")
    e = 3.15 * math.cos(math.radians(45))
    for k in range(4):
        a = k * 90
        for i in range(8):
            t = -e + (i + 0.5) * (2 * e / 8)
            x, y = (t, -e - 0.03) if k == 0 else (e + 0.03, t) if k == 1 else (t, e + 0.03) if k == 2 else (-e - 0.03, t)
            roof.box((0.5 if k % 2 == 0 else 0.06, 0.06 if k % 2 == 0 else 0.5, 0.32), loc=(x, y, 2.45),
                     mat="M_Cloth_Red" if i % 2 else "M_Cloth_White")
    roof.sphere(0.16, loc=(0, 0, 4.15), mat="M_Gold", subdiv=1)
    roof.build("X60000_Gazebo_Roof", coll, smooth=False)


@asset("X60000_Lighthouse_Tall", "Architecture", footprint=6.0, tags=("landmark", "port"))
def _lighthouse_tall(coll):
    """Southperry's lighthouse at the island rim (classic world map): a tall cream tower (~20 m) with gold
    bands, a railed gallery around a glowing lantern room, a blue dome and an orange-red cap. Door faces -y."""
    mb = MeshBuilder()
    mb.cyl(2.95, 1.0, mat="M_StoneWall", verts=22, r2=2.8)
    z0, h, r0, r1 = 1.0, 13.5, 2.35, 1.7

    def rad(z):
        return r0 + (r1 - r0) * (z - z0) / h

    mb.cyl(r0, h, loc=(0, 0, z0), mat="M_Plaster", verts=22, r2=r1)
    for zz in (4.2, 7.8, 11.4):
        mb.cyl(rad(zz) + 0.07, 0.45, loc=(0, 0, zz), mat="M_Gold", verts=22, r2=rad(zz + 0.45) + 0.07)
    door(mb, (0, -r0 + 0.02, z0), w=1.1, h=2.0, mat="M_Flat_roof_blue")
    for (zz, ang) in ((5.8, 0), (9.4, 35), (12.8, -30)):
        a = math.radians(ang - 90)
        rr = rad(zz + 0.5)
        mb.box((0.75, 0.3, 1.0), loc=(math.cos(a) * rr, math.sin(a) * rr, zz), rot=(0, 0, ang), mat="M_Window",
               bevel=0.04, segs=1)
        mb.box((0.95, 0.24, 0.12), loc=(math.cos(a) * (rr + 0.05), math.sin(a) * (rr + 0.05), zz + 1.06),
               rot=(0, 0, ang), mat="M_Flat_roof_blue")
    zg = z0 + h
    mb.cyl(2.65, 0.35, loc=(0, 0, zg), mat="M_Wood_Dark", verts=22, r2=2.55)
    for k in range(14):
        a = 2 * math.pi * k / 14
        mb.box((0.1, 0.1, 0.95), loc=(math.cos(a) * 2.45, math.sin(a) * 2.45, zg + 0.35), mat="M_Wood_Dark")
    mb.torus(2.45, 0.07, loc=(0, 0, zg + 1.3), mat="M_Gold", u=28, v=4)
    mb.cyl(1.45, 2.1, loc=(0, 0, zg + 0.35), mat="M_Glow_window", verts=16)
    for k in range(8):
        a = 2 * math.pi * k / 8 + 0.2
        mb.box((0.14, 0.14, 2.1), loc=(math.cos(a) * 1.5, math.sin(a) * 1.5, zg + 0.35), mat="M_Wood_Dark")
    mb.cyl(1.8, 0.25, loc=(0, 0, zg + 2.45), mat="M_Gold", verts=20)
    mb.dome(1.9, 1.55, loc=(0, 0, zg + 2.7), mat="M_Flat_roof_blue", u=22, v=6)
    mb.cyl(0.32, 1.1, loc=(0, 0, zg + 4.05), mat="M_Flat_roof_red", verts=12, r2=0.04)
    mb.sphere(0.42, loc=(0, 0, zg + 4.2), mat="M_Flat_roof_red", subdiv=2)
    mb.build("X60000_Lighthouse_Tall", coll, smooth=True, sharp_angle=40)


@asset("X60000_PhotoBoard_Lady", "Props", footprint=1.6, tags=("prop", "port"))
def _photo_lady(coll):
    """Face-in-the-hole board on the quay: blonde lady in a billowing white dress, dark aura (faces -y)."""
    mb = MeshBuilder()
    for x in (-0.5, 0.5):
        mb.box((0.1, 0.1, 1.2), loc=(x, 0.3, 0.55), rot=(-28, 0, 0), mat="M_Wood_Dark")
    for (x, z, r) in ((0, 1.25, 0.8), (-0.45, 0.8, 0.55), (0.45, 0.85, 0.55), (-0.3, 1.8, 0.5), (0.35, 1.75, 0.5),
                      (0, 0.45, 0.6)):
        mb.cyl(r, 0.08, loc=(x, 0.1, z), rot=(90, 0, 0), mat="M_Flat_rock_dk", verts=16)
    mb.cyl(0.75, 1.0, loc=(0, 0.0, 0.1), mat="M_Cloth_White", verts=16, r2=0.22, scale=(1.0, 0.28, 1.0))
    mb.box((0.42, 0.12, 0.45), loc=(0, -0.02, 1.25), mat="M_Cloth_White", bevel=0.04, segs=1)
    for s in (-1, 1):
        mb.box((0.1, 0.08, 0.55), loc=(s * 0.33, -0.02, 1.3), rot=(0, s * 35, 0), mat="M_Skin")
    mb.cyl(0.36, 0.1, loc=(0, 0.02, 1.85), rot=(90, 0, 0), mat="M_Flat_hair_blonde", verts=16)
    mb.cyl(0.19, 0.12, loc=(0, -0.06, 1.8), rot=(90, 0, 0), mat="M_Eye_Black", verts=14)
    for x in (-0.12, 0.12):
        mb.cyl(0.07, 0.4, loc=(x, 0.0, 0.0), mat="M_Skin", verts=6)
    mb.build("X60000_PhotoBoard_Lady", coll, smooth=False)


@asset("X60000_PhotoBoard_Ring", "Props", footprint=1.6, tags=("prop", "port"))
def _photo_ring(coll):
    """Face-in-the-hole board on the quay: an orange ring on white cloud puffs with a yellow chick."""
    mb = MeshBuilder()
    mb.box((0.1, 0.1, 1.0), loc=(0, 0.3, 0.45), rot=(-25, 0, 0), mat="M_Wood_Dark")
    for (x, z, r) in ((-0.55, 0.3, 0.38), (0.0, 0.25, 0.45), (0.55, 0.3, 0.38), (-0.85, 0.5, 0.28),
                      (0.85, 0.5, 0.28)):
        mb.sphere(r, loc=(x, 0.0, z), scale=(1.0, 0.6, 0.8), mat="M_Cloth_White", subdiv=2)
    mb.torus(0.55, 0.17, loc=(0, 0.0, 1.15), rot=(90, 0, 0), mat="M_Flat_roof_orange", u=18, v=8)
    mb.sphere(0.2, loc=(0.1, 0.0, 1.92), mat="M_Flat_flower_yellow", subdiv=2)
    mb.cyl(0.06, 0.12, loc=(0.1, -0.2, 1.92), rot=(90, 0, 0), mat="M_Flat_roof_orange", verts=6, r2=0.0)
    for x in (0.03, 0.17):
        mb.sphere(0.03, loc=(x, -0.18, 1.98), mat="M_Eye_Black", subdiv=1)
    mb.build("X60000_PhotoBoard_Ring", coll, smooth=True, sharp_angle=50)


@asset("X60000_FabricRolls", "Props", footprint=1.8, tags=("prop", "town"))
def _fabric_rolls(coll):
    """Rolled carpets / fabric bolts (red-green, purple-grey) leaning on a rail (market street)."""
    mb = MeshBuilder()
    for x in (-0.9, 0.9):
        mb.box((0.1, 0.1, 1.5), loc=(x, 0.38, 0.75), mat="M_Wood_Dark")
    mb.box((2.0, 0.1, 0.1), loc=(0, 0.38, 1.45), mat="M_Wood")
    cols = ["M_Cloth_Red", "M_Flat_roof_green", "M_Flat_roof_purple", "M_Flat_rock", "M_Flat_flower_pink"]
    for i, c in enumerate(cols):
        x = -0.72 + i * 0.36
        mb.cyl(0.15, 1.55, loc=(x, 0.0, 0.0), rot=(-15, 0, 0), mat=c, verts=10)
        mb.cyl(0.155, 0.12, loc=(x, 0.03 + 0.0, 0.7), rot=(-15, 0, 0), mat="M_Flat_flower_yellow", verts=10)
    mb.build("X60000_FabricRolls", coll, smooth=True, sharp_angle=40)


@asset("X60000_BluePots", "Props", footprint=1.2, tags=("prop", "town"))
def _blue_pots(coll):
    """Blue ceramic amphorae (the pots on Biggs's terrace)."""
    mb = MeshBuilder()
    for (x, y, s) in ((0.0, 0.0, 1.0), (0.55, 0.25, 0.75), (-0.5, 0.3, 0.62)):
        mb.cyl(0.18 * s, 0.12 * s, loc=(x, y, 0), mat="M_Flat_roof_blue", verts=12, r2=0.24 * s)
        mb.sphere(0.33 * s, loc=(x, y, 0.42 * s), scale=(1, 1, 1.15), mat="M_Flat_roof_blue", subdiv=2)
        mb.cyl(0.12 * s, 0.32 * s, loc=(x, y, 0.72 * s), mat="M_Flat_roof_blue", verts=12, r2=0.16 * s)
        mb.torus(0.16 * s, 0.045 * s, loc=(x, y, 1.03 * s), mat="M_Flat_cloth_white", u=12, v=4)
    mb.build("X60000_BluePots", coll, smooth=True, sharp_angle=50)


@asset("X60000_BlueCrate", "Props", footprint=1.0, tags=("prop", "port"))
def _blue_crate(coll):
    """Blue-painted cargo crate with white bands (the classic Southperry crates on T8/T9/T11/T6)."""
    mb = MeshBuilder()
    mb.box((0.9, 0.9, 0.9), loc=(0, 0, 0.45), mat="M_Flat_roof_blue", bevel=0.05, segs=1)
    for s in (-1, 1):
        mb.box((0.95, 0.96, 0.12), loc=(0, 0, 0.45 + s * 0.36), mat="M_Flat_cloth_white", bevel=0.02, segs=1)
    mb.box((0.12, 0.96, 0.95), loc=(0, 0, 0.45), rot=(0, 45, 0), mat="M_Flat_cloth_white")
    mb.build("X60000_BlueCrate", coll, smooth=False)


@asset("X60000_ShieldSign", "Props", footprint=1.4, tags=("prop", "sign"))
def _shield_sign(coll):
    """Armor Store sign: a board hanging from a curled post with a green shield-and-cross emblem."""
    mb = MeshBuilder()
    mb.cyl(0.25, 0.25, mat="M_StoneWall", verts=8, r2=0.2)
    mb.cyl(0.1, 2.95, loc=(0, 0, 0.2), mat="M_Wood_Dark", verts=8)
    mb.box((1.45, 0.11, 0.11), loc=(0.66, 0, 2.8), mat="M_Wood_Dark")
    mb.torus(0.2, 0.05, loc=(1.38, 0, 3.0), rot=(90, 0, 0), mat="M_Wood_Dark", u=12, v=4)
    mb.torus(0.14, 0.045, loc=(-0.05, 0, 3.22), rot=(90, 0, 0), mat="M_Wood_Dark", u=12, v=4)
    for x in (0.3, 1.0):
        mb.cyl(0.02, 0.32, loc=(x, 0, 2.45), mat="M_Rope", verts=4)
    mb.box((1.05, 0.1, 0.8), loc=(0.65, 0, 2.05), mat="M_Plank", bevel=0.05, segs=1)
    mb.box((1.15, 0.12, 0.1), loc=(0.65, 0, 2.45), mat="M_Wood_Dark")
    mb.prism([(-0.26, 0.2), (0.26, 0.2), (0.26, -0.05), (0.0, -0.3), (-0.26, -0.05)], 0.0, 0.06,
             loc=(0.65, -0.05, 2.05), rot=(90, 0, 0), mat="M_Flat_roof_green")
    mb.box((0.09, 0.05, 0.36), loc=(0.65, -0.13, 2.03), mat="M_Flat_cloth_white")
    mb.box((0.3, 0.05, 0.09), loc=(0.65, -0.13, 2.08), mat="M_Flat_cloth_white")
    mb.build("X60000_ShieldSign", coll, smooth=False)


@asset("X60000_CubeHouse", "Architecture", footprint=5.0, tags=("house", "port"))
def _cube_house(coll):
    """Whitewashed flat-roofed cube house (Santorini style): blue door and shutters, roof parapet, an
    outside stair up the +x wall to the roof, a small blue dome on a corner drum (faces -y)."""
    W, Dd, H = 4.2, 3.8, 3.4
    mb = MeshBuilder()
    mb.box((W + 0.4, Dd + 0.4, 0.35), loc=(0, 0, 0.12), mat="M_Sand_Cliff", bevel=0.05)
    mb.box((W, Dd, H), loc=(0, 0, H / 2), mat=WALL, bevel=0.18, segs=2)
    for (x, y, lx, ly) in ((0, -Dd / 2 + 0.1, W, 0.2), (0, Dd / 2 - 0.1, W, 0.2), (-W / 2 + 0.1, 0, 0.2, Dd),
                           (W / 2 - 0.1, 0, 0.2, Dd)):
        mb.box((lx, ly, 0.45), loc=(x, y, H + 0.2), mat=WALL, bevel=0.06)
    door(mb, (-0.8, -Dd / 2, 0.0), w=0.95, h=1.85, mat="M_Flat_roof_blue")
    window(mb, (0.95, -Dd / 2, 1.75), w=0.7, h=0.8, shutter_mat="M_Flat_roof_blue", flowerbox=True)
    window(mb, (-W / 2, 0.5, 1.8), face="-X", w=0.7, h=0.8, shutter_mat="M_Flat_roof_blue")
    for k in range(8):
        hk = 0.42 * (k + 1)
        mb.box((0.9, 0.46, hk), loc=(W / 2 + 0.45, -Dd / 2 + 0.25 + k * 0.44, hk / 2), mat=WALL, bevel=0.03,
               segs=1)
    mb.cyl(0.75, 0.6, loc=(-W / 2 + 0.9, Dd / 2 - 0.9, H), mat=WALL, verts=16)
    mb.dome(0.8, 0.75, loc=(-W / 2 + 0.9, Dd / 2 - 0.9, H + 0.6), mat="M_Flat_roof_blue", u=16, v=5)
    mb.cyl(0.24, 0.35, loc=(W / 2 - 0.5, -Dd / 2 + 0.5, H), mat="M_Flat_roof_orange", verts=10, r2=0.3)
    mb.sphere(0.36, loc=(W / 2 - 0.5, -Dd / 2 + 0.5, H + 0.55), mat="M_Bush", subdiv=2)
    _wall_star(mb, -1.75, -Dd / 2 - 0.05, 2.7, 0.2, "M_Flat_roof_orange")
    mb.build("X60000_CubeHouse", coll, smooth=True, sharp_angle=35)


def _step_house(coll, name, vault):
    """Stepped whitewashed house (Santorini): a wide lower block whose flat roof is a terrace, and a set-back
    upper block (a blue barrel vault or a small blue dome); blue arched door and shutters, flower boxes and a
    bougainvillea spilling over the terrace parapet (faces -y)."""
    W, Dd, H = 5.6, 4.4, 3.0
    mb = MeshBuilder()
    mb.box((W + 0.4, Dd + 0.4, 0.35), loc=(0, 0, 0.12), mat="M_Sand_Cliff", bevel=0.05)
    mb.box((W, Dd, H), loc=(0, 0, H / 2), mat=WALL, bevel=0.16, segs=2)
    for (x, y, lx, ly) in ((0, -Dd / 2 + 0.1, W, 0.2), (W / 2 - 0.1, 0, 0.2, Dd)):
        mb.box((lx, ly, 0.5), loc=(x, y, H + 0.22), mat=WALL, bevel=0.06)
    UW, UD, UH = 3.2, 2.8, 2.5
    ux, uy = -W / 2 + UW / 2 + 0.15, Dd / 2 - UD / 2 - 0.15
    mb.box((UW, UD, UH), loc=(ux, uy, H + UH / 2), mat=WALL, bevel=0.14, segs=2)
    door(mb, (1.3, -Dd / 2, 0.0), w=1.0, h=1.9, mat="M_Flat_roof_blue")
    window(mb, (-1.3, -Dd / 2, 1.6), w=0.85, h=0.85, shutter_mat="M_Flat_roof_blue", flowerbox=True)
    door(mb, (ux + 0.7, uy - UD / 2, H), w=0.8, h=1.6, mat="M_Flat_roof_blue")
    window(mb, (ux - 0.8, uy - UD / 2, H + 1.3), w=0.6, h=0.7, shutter_mat="M_Flat_roof_blue")
    window(mb, (W / 2, 0.4, 1.6), face="+X", w=0.75, h=0.8, shutter_mat="M_Flat_roof_blue", flowerbox=True)
    window(mb, (ux + UW / 2, uy, H + 1.3), face="+X", w=0.6, h=0.7, shutter_mat="M_Flat_roof_blue")
    if vault:
        mb.cyl(UD / 2 + 0.05, UW + 0.12, loc=(ux - (UW + 0.12) / 2, uy, H + UH - 0.05), rot=(0, 90, 0),
               mat="M_Flat_roof_blue", verts=18)
        chimney(mb, (W / 2 - 0.6, Dd / 2 - 0.6, H), h=1.1, mat=WALL)
    else:
        mb.cyl(0.95, 0.45, loc=(ux, uy, H + UH), mat=WALL, verts=18)
        mb.dome(1.0, 0.95, loc=(ux, uy, H + UH + 0.45), mat="M_Flat_roof_blue", u=18, v=5)
        mb.sphere(0.12, loc=(ux, uy, H + UH + 1.45), mat="M_Gold", subdiv=1)
        # pergola over the terrace
        px, py = W / 2 - 1.1, -Dd / 2 + 1.0
        for sx in (-0.9, 0.9):
            mb.cyl(0.07, 2.1, loc=(px + sx, py - 0.6, H), mat="M_Wood", verts=6)
        for k in range(5):
            mb.box((0.1, 2.0, 0.08), loc=(px - 0.9 + k * 0.45, py + 0.2, H + 2.1), mat="M_Wood")
        mb.box((2.0, 0.12, 0.12), loc=(px, py - 0.6, H + 2.05), mat="M_Wood")
    # bougainvillea spilling over the front parapet
    bx = 0.4 if vault else -0.2
    for (dx, dz, r, mat) in ((0.0, 0.5, 0.55, "M_Bush"), (0.5, 0.35, 0.45, "M_Flat_flower_pink"),
                             (-0.45, 0.3, 0.4, "M_Flat_flower_pink"), (0.15, 0.85, 0.35, "M_Flat_flower_pink"),
                             (0.3, -0.25, 0.32, "M_Flat_flower_purple")):
        mb.sphere(r, loc=(bx + dx, -Dd / 2 + 0.15, H + dz), scale=(1.0, 0.8, 0.85), mat=mat, subdiv=1)
    _wall_star(mb, 2.35, -Dd / 2 - 0.05, 2.45, 0.2, "M_Flat_roof_orange")
    mb.build(name, coll, smooth=True, sharp_angle=35)


@asset("X60000_StepHouse_A", "Architecture", footprint=6.0, tags=("house", "port"))
def _step_house_a(coll):
    _step_house(coll, "X60000_StepHouse_A", vault=True)


@asset("X60000_StepHouse_B", "Architecture", footprint=6.0, tags=("house", "port"))
def _step_house_b(coll):
    _step_house(coll, "X60000_StepHouse_B", vault=False)


@asset("X60000_WallArch", "Architecture", footprint=0.8, tags=("facade", "port"))
def _wall_arch(coll):
    """Arched doorway set into a retaining wall: whitewashed surround, blue door, lamp, two blue pots.
    Thin (0.3 m) so it sits flush on a cliff face; faces -y, origin at the foot of the wall."""
    mb = MeshBuilder()
    mb.box((2.1, 0.3, 2.4), loc=(0, 0.05, 1.2), mat=WALL, bevel=0.06, segs=1)
    mb.cyl(1.05, 0.3, loc=(0, 0.2, 2.4), rot=(90, 0, 0), mat=WALL, verts=16)
    door(mb, (0, -0.1, 0.0), w=1.1, h=2.0, mat="M_Flat_roof_blue")
    mb.box((0.14, 0.3, 0.14), loc=(0.85, -0.2, 2.55), mat="M_Wood_Dark")
    mb.box((0.28, 0.28, 0.36), loc=(0.85, -0.38, 2.3), mat="M_Glow_window", bevel=0.03, segs=1)
    for sx in (-1.25, 1.25):
        mb.cyl(0.2, 0.32, loc=(sx, -0.35, 0.0), mat="M_Flat_roof_blue", verts=10, r2=0.26)
        mb.sphere(0.3, loc=(sx, -0.35, 0.5), mat="M_Bush", subdiv=1)
        mb.sphere(0.12, loc=(sx + 0.1, -0.55, 0.62), mat="M_Flat_flower_red", subdiv=1)
    mb.build("X60000_WallArch", coll, smooth=True, sharp_angle=40)


@asset("X60000_WallWindow", "Architecture", footprint=0.8, tags=("facade", "port"))
def _wall_window(coll):
    """Blue-shuttered window with a flower box and a whitewashed surround for a retaining wall (faces -y;
    origin at the window's centre)."""
    mb = MeshBuilder()
    mb.box((1.55, 0.24, 1.6), loc=(0, 0.06, 0.0), mat=WALL, bevel=0.06, segs=1)
    window(mb, (0, -0.06, 0.05), w=0.8, h=0.9, shutter_mat="M_Flat_roof_blue", flowerbox=True)
    for (dx, dz, r) in ((-0.55, -0.75, 0.2), (-0.3, -0.95, 0.16), (0.45, -0.8, 0.18)):
        mb.sphere(r, loc=(dx, -0.28, dz), scale=(1.0, 0.7, 1.2), mat="M_Bush", subdiv=1)
    mb.build("X60000_WallWindow", coll, smooth=True, sharp_angle=40)


@asset("X60000_TicketBooth", "Props", footprint=2.2, tags=("prop", "port", "sign"))
def _ticket_booth(coll):
    """Shanks' ticket booth for the ship to Victoria Island: blue-and-white plank kiosk with a striped
    awning, a counter window, a timetable board and a ship wheel sign on the roof (faces -y)."""
    mb = MeshBuilder()
    mb.box((2.0, 1.5, 0.15), loc=(0, 0, 0.075), mat="M_Plank", bevel=0.03, segs=1)
    mb.box((2.0, 1.5, 1.0), loc=(0, 0, 0.6), mat="M_Flat_roof_blue", bevel=0.04, segs=1)
    for k in range(5):
        mb.box((0.06, 1.54, 0.95), loc=(-0.8 + k * 0.4, 0, 0.6), mat="M_Flat_cloth_white")
    mb.box((2.2, 1.65, 0.1), loc=(0, 0, 1.12), mat="M_Wood", bevel=0.02, segs=1)  # counter
    for sx in (-0.95, 0.95):
        for sy in (-0.7, 0.7):
            mb.box((0.1, 0.1, 1.15), loc=(sx, sy, 1.72), mat="M_Wood_Dark")
    mb.box((2.0, 0.08, 1.1), loc=(0, 0.72, 1.72), mat="M_Flat_cloth_white")
    mb.box((2.3, 1.8, 0.14), loc=(0, 0, 2.36), mat="M_Flat_roof_blue", bevel=0.03, segs=1)
    for i in range(6):  # striped awning
        mb.box((0.39, 0.85, 0.05), loc=(-0.98 + i * 0.39, -1.15, 2.2), rot=(-22, 0, 0),
               mat="M_Cloth_White" if i % 2 else "M_Flat_roof_blue")
    # ship wheel sign
    mb.box((1.5, 0.1, 0.55), loc=(0, 0.2, 2.75), mat="M_Plank", bevel=0.03, segs=1)
    mb.torus(0.32, 0.05, loc=(0, 0.12, 3.3), rot=(90, 0, 0), mat="M_Gold", u=16, v=4)
    for k in range(4):
        mb.box((0.04, 0.04, 0.82), loc=(0, 0.12, 3.3), rot=(0, k * 45, 0), mat="M_Gold")
    for x in (-0.45, 0.0, 0.45):
        mb.box((0.3, 0.05, 0.12), loc=(x, 0.12, 2.75), mat="M_Flat_roof_blue")
    # timetable board leaning at the front
    mb.box((0.06, 0.06, 1.1), loc=(1.35, -0.55, 0.0), rot=(-8, 0, 0), mat="M_Wood_Dark")
    mb.box((0.6, 0.05, 0.75), loc=(1.35, -0.6, 0.95), rot=(-8, 0, 0), mat="M_Flat_cloth_white", bevel=0.02, segs=1)
    for z in (0.75, 0.95, 1.15):
        mb.box((0.42, 0.06, 0.05), loc=(1.35, -0.64, z), rot=(-8, 0, 0), mat="M_Flat_roof_blue")
    mb.build("X60000_TicketBooth", coll, smooth=False)


@asset("X60000_FishStall", "Props", footprint=3.0, tags=("prop", "port"))
def _fish_stall(coll):
    """Harbour fish stall: plank counter heaped with crushed ice and fish, a blue-and-white canopy, fish
    hanging from the rail, a barrel and a crate of catch (faces -y)."""
    mb = MeshBuilder()
    mb.box((2.8, 1.2, 0.9), loc=(0, 0, 0.45), mat="M_Wood", bevel=0.04, segs=1)
    mb.box((2.6, 1.0, 0.18), loc=(0, -0.05, 0.98), mat="M_Flat_cloth_white", bevel=0.05, segs=1)  # ice
    cols = ("M_Flat_roof_orange", "M_Flat_water_dk", "M_Flat_metal", "M_Flat_roof_orange", "M_Flat_water_lt",
            "M_Flat_metal", "M_Flat_flower_red")
    for i, c in enumerate(cols):
        x = -1.05 + i * 0.35
        y = -0.25 + (i % 2) * 0.35
        mb.sphere(0.13, loc=(x, y, 1.12), scale=(2.3, 1.0, 0.7), rot=(0, 0, 25 if i % 2 else -20), mat=c, subdiv=1)
        mb.cyl(0.1, 0.02, loc=(x + 0.3 * (1 if i % 2 else -1), y, 1.08), rot=(90, 0, 0), mat=c, verts=3)
    for sx in (-1.35, 1.35):
        for sy in (-0.55, 0.55):
            mb.cyl(0.06, 2.3, loc=(sx, sy, 0.0), mat="M_Wood_Dark", verts=6)
    mb.box((2.9, 0.08, 0.08), loc=(0, -0.55, 1.9), mat="M_Wood_Dark")
    for i in range(7):  # canopy stripes
        mb.box((0.42, 1.5, 0.05), loc=(-1.26 + i * 0.42, -0.1, 2.38), rot=(-14, 0, 0),
               mat="M_Flat_roof_blue" if i % 2 else "M_Cloth_White")
    for x in (-0.8, -0.3, 0.6):  # hanging fish
        mb.cyl(0.015, 0.25, loc=(x, -0.55, 1.65), mat="M_Rope", verts=4)
        mb.sphere(0.1, loc=(x, -0.55, 1.5), scale=(0.7, 0.7, 2.2), mat="M_Flat_metal", subdiv=1)
    mb.cyl(0.3, 0.75, loc=(1.75, 0.1, 0.0), mat="M_Wood", verts=12, r2=0.33)
    mb.cyl(0.34, 0.06, loc=(1.75, 0.1, 0.5), mat="M_Metal", verts=12)
    mb.box((0.7, 0.5, 0.35), loc=(-1.75, -0.2, 0.18), mat="M_Wood", bevel=0.03, segs=1)
    for i in range(3):
        mb.sphere(0.1, loc=(-1.95 + i * 0.2, -0.2, 0.4), scale=(2.0, 1.0, 0.7), mat="M_Flat_roof_orange", subdiv=1)
    mb.build("X60000_FishStall", coll, smooth=False)


@asset("X60000_CargoDerrick", "Props", footprint=2.0, tags=("prop", "port"))
def _cargo_derrick(coll):
    """Wooden cargo derrick on the quay lip: a braced mast and a boom reaching out over the ship (-y), a
    rope net bulging with crates and sacks hanging from it, crates stacked at its foot."""
    mb = MeshBuilder()
    mb.box((1.2, 1.2, 0.3), loc=(0, 0, 0.15), mat="M_StoneWall", bevel=0.05, segs=1)
    mb.cyl(0.16, 4.6, loc=(0, 0, 0.3), mat="M_Wood", verts=8, r2=0.12)
    top = Vector((0, -2.6, 3.9))
    _line(mb, (0, 0, 1.2), top, 0.1, "M_Wood")
    _line(mb, (0, 0, 4.8), top, 0.03, "M_Rope")
    for sx in (-1, 1):
        _line(mb, (0, 0, 2.6), (sx * 0.9, 0.7, 0.3), 0.05, "M_Wood_Dark")
    # hanging net: rope line, bundle of crates/sacks wrapped in a rope grid
    nz = 1.7
    _line(mb, top, (0, -2.6, nz + 0.8), 0.03, "M_Rope")
    mb.box((0.6, 0.6, 0.55), loc=(-0.2, -2.6, nz + 0.05), rot=(0, 0, 20), mat="M_Wood", bevel=0.03, segs=1)
    mb.sphere(0.32, loc=(0.25, -2.5, nz + 0.1), scale=(1.0, 1.0, 0.8), mat="M_Flat_lid_tan", subdiv=1)
    mb.box((0.45, 0.45, 0.4), loc=(0.05, -2.75, nz + 0.45), rot=(0, 0, -15), mat="M_Flat_roof_blue", bevel=0.03,
           segs=1)
    for k in range(5):
        mb.torus(0.55 - abs(k - 2) * 0.12, 0.025, loc=(0, -2.6, nz - 0.15 + k * 0.22), mat="M_Rope", u=14, v=3)
    for k in range(6):
        a = k * math.pi / 3
        _line(mb, (math.cos(a) * 0.5, -2.6 + math.sin(a) * 0.5, nz + 0.1), (0, -2.6, nz + 0.8), 0.02, "M_Rope")
        _line(mb, (math.cos(a) * 0.5, -2.6 + math.sin(a) * 0.5, nz + 0.1), (0, -2.6, nz - 0.3), 0.02, "M_Rope")
    mb.box((0.7, 0.7, 0.6), loc=(0.75, 0.55, 0.3), rot=(0, 0, 10), mat="M_Wood", bevel=0.03, segs=1)
    mb.box((0.55, 0.55, 0.5), loc=(0.72, 0.5, 0.85), rot=(0, 0, -12), mat="M_Wood", bevel=0.03, segs=1)
    mb.build("X60000_CargoDerrick", coll, smooth=False)


@asset("X60000_RopeDavit", "Props", footprint=0.6, tags=("prop", "climb"))
def _rope_davit(coll):
    """Rope head on a cliff lip: a short post with an arm reaching 0.9 m over the edge (-y) and a pulley
    block the climbing rope hangs from. Origin at the post foot."""
    mb = MeshBuilder()
    mb.box((0.5, 0.5, 0.2), loc=(0, 0, 0.1), mat="M_StoneWall", bevel=0.04, segs=1)
    mb.box((0.18, 0.18, 1.5), loc=(0, 0, 0.85), mat="M_Wood_Dark", bevel=0.03, segs=1)
    mb.box((0.16, 1.25, 0.16), loc=(0, -0.5, 1.5), mat="M_Wood_Dark", bevel=0.03, segs=1)
    _line(mb, (0, 0, 1.0), (0, -0.55, 1.45), 0.05, "M_Wood_Dark")
    mb.cyl(0.17, 0.1, loc=(-0.05, -0.95, 1.25), rot=(0, 90, 0), mat="M_Metal", verts=12)
    mb.box((0.06, 0.14, 0.3), loc=(0, -0.95, 1.33), mat="M_Wood_Dark")
    # (no rope piece of its own any more: the kit rope hangs plumb off the face from its own stake, so a copy at
    # the climb position no longer lines up with it)
    mb.build("X60000_RopeDavit", coll, smooth=False)


@asset("X60000_CafeTable", "Props", footprint=1.8, tags=("prop", "town"))
def _cafe_table(coll):
    """Little cafe table under a blue-and-white parasol with two chairs."""
    mb = MeshBuilder()
    mb.cyl(0.2, 0.06, mat="M_Metal", verts=10)
    mb.cyl(0.05, 0.72, loc=(0, 0, 0.04), mat="M_Metal", verts=6)
    mb.cyl(0.42, 0.05, loc=(0, 0, 0.74), mat="M_Flat_cloth_white", verts=14)
    mb.cyl(0.03, 1.6, loc=(0, 0, 0.78), mat="M_Wood_Dark", verts=6)
    mb.cyl(1.05, 0.34, loc=(0, 0, 2.04), verts=8, r2=0.03, mat="M_Streak_cloth_white__roof_blue")
    mb.cyl(1.07, 0.08, loc=(0, 0, 1.98), verts=8, mat="M_Flat_roof_blue")
    for sx in (-0.75, 0.75):
        mb.box((0.42, 0.42, 0.06), loc=(sx, 0.05, 0.45), mat="M_Wood", bevel=0.02, segs=1)
        mb.box((0.06, 0.42, 0.5), loc=(sx + (0.19 if sx > 0 else -0.19), 0.05, 0.72), mat="M_Wood")
        for dx in (-0.17, 0.17):
            for dy in (-0.17, 0.17):
                mb.cyl(0.025, 0.45, loc=(sx + dx, 0.05 + dy, 0.0), mat="M_Wood_Dark", verts=4)
    mb.build("X60000_CafeTable", coll, smooth=False)


# ------------------------------------------------------------------ the ship <Victoria>
SHIP_HL = 11.2               # hull half-length, bow toward +x
SHIP_DECK = 2.9              # main deck above the waterline
SHIP_QD = 4.6                # quarterdeck (stern castle, T4)
SHIP_FC = 3.9                # forecastle
SHIP_QD_X = -7.3             # quarterdeck front wall
SHIP_FC_X = 7.6              # forecastle back wall
SHIP_FORE_X, SHIP_MAIN_X, SHIP_MIZ_X = 5.8, -0.6, -9.0
SHIP_TOP = SHIP_DECK + 8.0   # main fighting top floor (T2 lower yard)
# Gap in the bulwark on the quay side. The Gameplay camera looks along local (-0.375, 0.927), so a mast hides
# whatever lies 0.4 m further west per metre further back (+y): a plank in the plan-view waist (x 2.4..2.8) would
# put its quay foot (8.4 m behind the masts) and Shanks straight behind the fore mast. At 0.4 the whole plank, deck end to quay foot, projects into
# the screen gap between the main and fore mast columns (ray-probed and spot-rendered). Keep it on a 0.4 + 0.8k
# ring midpoint so ship_ztop's flat opening stays symmetric (four lowered rings).
SHIP_GANGWAY_X = 0.4
GANGWAY_SIDE = 1             # +1: starboard (+y, the quay side; the port side faces the camera and the void)


def _ss(a, b, t):
    u = min(1.0, max(0.0, (t - a) / (b - a)))
    return u * u * (3 - 2 * u)


def ship_hw(x):
    t = (x + SHIP_HL) / (2 * SHIP_HL)
    if t <= 0.4:
        hw = 3.5 - (0.4 - t) / 0.4 * 0.8
    else:
        u = min(1.0, (t - 0.4) / 0.6)
        hw = 3.5 * max(0.0, 1 - u ** 2.2) ** 0.55
    return max(0.15, hw)


def ship_ztop(x, gangway=False):
    t = (x + SHIP_HL) / (2 * SHIP_HL)
    z = 3.5 + (SHIP_QD + 0.6 - 3.5) * (1 - _ss(0.19, 0.27, t)) + (SHIP_FC + 0.6 - 3.5) * _ss(0.77, 0.83, t) \
        + 0.3 * _ss(0.9, 1.0, t)
    # hull rings are sampled every 0.8 m (-0.8, 0.0, 0.8, 1.6 around the gangway): 1.25 lowers four rings,
    # i.e. a flat 2.4 m opening for the 2.0 m gangplank
    if gangway and abs(x - SHIP_GANGWAY_X) <= 1.25:
        z = SHIP_DECK + 0.02
    return z


def ship_zbot(x):
    t = (x + SHIP_HL) / (2 * SHIP_HL)
    return -1.5 + 0.9 * _ss(0.85, 1.0, t) + 0.6 * (1 - _ss(0.0, 0.15, t))


def ship_deck_poly(x0, x1, shrink=0.93, step=0.8):
    xs = [x0]
    x = math.ceil(x0 / step) * step
    while x < x1 - 1e-6:
        if x > x0 + 1e-6:
            xs.append(x)
        x += step
    xs.append(x1)
    return [(x, -ship_hw(x) * shrink) for x in xs] + [(x, ship_hw(x) * shrink) for x in reversed(xs)]


def _line(mb, p, q, r, mat):
    p, q = Vector(p), Vector(q)
    v = q - p
    L = v.length
    th = math.degrees(math.acos(max(-1.0, min(1.0, v.z / L))))
    ph = math.degrees(math.atan2(v.y, v.x))
    mb.cyl(r, L, loc=p, rot=(0, th, ph), mat=mat, verts=5)


def _square_sail(sb, mx, z_top, z_bot, w_top, w_bot, brace=26.0, billow=0.8, cols=6, rows=4):
    """Billowing square sail braced around the mast so it faces the camera side (-y, +x)."""
    b = math.radians(brace)
    n = Vector((math.cos(b), -math.sin(b), 0.0))
    d = Vector((math.sin(b), math.cos(b), 0.0))
    bm = sb.bm
    mi = sb.mat("M_Cloth_White")
    grid = []
    for r in range(rows + 1):
        tz = r / rows
        z = z_top + (z_bot - z_top) * tz
        w = w_top + (w_bot - w_top) * tz
        row = []
        for c in range(cols + 1):
            tc = c / cols
            u = -w / 2 + w * tc
            bw = billow * math.sin(math.pi * tc) * math.sin(math.pi * min(1.0, 0.12 + tz * 0.8))
            p = Vector((mx, 0.0, z)) + d * u + n * (bw + 0.35)
            row.append(bm.verts.new(p))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            f = bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
            f.material_index = mi
    return d, n


def _swing(p, a, b, deg):
    """Rotate point p about the axis a->b by deg, in whichever sense moves it toward -y."""
    from mathutils import Matrix
    p, a, b = Vector(p), Vector(a), Vector(b)
    axis = (b - a).normalized()
    outs = [a + Matrix.Rotation(math.radians(sg * deg), 3, axis) @ (p - a) for sg in (1, -1)]
    return tuple(min(outs, key=lambda q: q.y))


def _furled_sail(sb, c, d, w, r=0.3):
    """A sail rolled up under its yard: a fat cream roll along direction d, tied with dark gaskets."""
    yaw = math.degrees(math.atan2(d.y, d.x))
    sb.cyl(r, w, loc=c - d * (w / 2), rot=(0, 90, yaw), mat="M_Cloth_White", verts=12, r2=r * 0.8)
    for t in (-0.38, -0.13, 0.13, 0.38):
        sb.cyl(r + 0.04, 0.09, loc=c + d * (t * w), rot=(0, 90, yaw), mat="M_Rope", verts=12)
    for t in (-0.3, 0.0, 0.3):  # slack bunts hanging below the roll
        sb.sphere(r * 0.9, loc=c + d * (t * w) + Vector((0, 0, -r * 0.55)), scale=(1.0, 1.0, 0.7), mat="M_Cloth_White",
                  subdiv=1)


def _flat_sail(sb, pts, bulge=(0.0, -0.35, 0.0)):
    """Fore-and-aft sail (jib / spanker) as a fan around a bulged centre vertex."""
    bm = sb.bm
    mi = sb.mat("M_Cloth_White")
    c = sum((Vector(p) for p in pts), Vector()) / len(pts) + Vector(bulge)
    vc = bm.verts.new(c)
    vs = [bm.verts.new(Vector(p)) for p in pts]
    for i in range(len(vs)):
        f = bm.faces.new((vs[i], vs[(i + 1) % len(vs)], vc))
        f.material_index = mi


@asset("X60000_Ship_Victoria", "Architecture", footprint=26.0, tags=("ship", "landmark"))
def _ship_victoria(coll):
    """The ship <Victoria> moored at Southperry (classic vehicle/ship/victoria): brown hull with a green
    upper strake and gold stripe, raised stern castle and forecastle, golden winged figurehead, three
    masts with cream square sails braced toward the viewer, jibs and spanker, rigging, a fighting top
    on the main mast, pennants, and the twin barrel engines with propellers of the classic sprite.
    Waterline at z=0, bow toward +x. Walkable heights: SHIP_DECK / SHIP_QD / SHIP_FC / SHIP_TOP
    (the map adds its own walkable decks at those heights)."""
    hull = MeshBuilder()
    bm = hull.bm
    band = ["M_Flat_roof_green", "M_Gold", "M_Wood", "M_Wood_Dark", "M_Wood_Dark", "M_Wood_Dark", "M_Wood_Dark",
            "M_Wood", "M_Gold", "M_Flat_roof_green"]
    mids = [hull.mat(mn) for mn in band]
    xs = [-SHIP_HL + i * 0.8 for i in range(int(2 * SHIP_HL / 0.8) + 1)]
    rings = []
    for x in xs:
        hw = ship_hw(x)
        zb = ship_zbot(x)
        side = []
        for sgn in (-1, 1):
            zt = ship_ztop(x, gangway=(sgn == GANGWAY_SIDE))
            zt_s = ship_ztop(x)
            z1 = min(zt_s - 0.55, zt - 0.05)
            z2 = min(zt_s - 0.8, z1 - 0.15)
            pts = [(hw, zt), (hw * 1.03, z1), (hw * 1.03, z2), (hw * 0.97, 0.4),
                   (hw * 0.72, (0.4 + zb) / 2 - 0.15)]
            side.append([(x, sgn * a, z) for a, z in pts])
        ring = side[0] + [(x, 0.0, zb)] + list(reversed(side[1]))
        rings.append([bm.verts.new(p) for p in ring])
    for i in range(len(rings) - 1):
        for j in range(len(rings[i]) - 1):
            f = bm.faces.new((rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1]))
            f.material_index = mids[j]
    for ring in (rings[0], rings[-1]):
        f = bm.faces.new(ring)
        f.material_index = hull.mat("M_Wood")
    # decks: main deck, stern castle block (cabin) and forecastle block
    hull.prism(ship_deck_poly(SHIP_QD_X, SHIP_FC_X), SHIP_DECK - 0.2, SHIP_DECK, mat="M_Plank")
    hull.prism(ship_deck_poly(-SHIP_HL + 0.05, SHIP_QD_X, 0.96), SHIP_DECK - 0.2, SHIP_QD, mat="M_Wood",
               cap_mat="M_Plank")
    hull.prism(ship_deck_poly(SHIP_FC_X, SHIP_HL - 1.2, 0.96), SHIP_DECK - 0.2, SHIP_FC, mat="M_Wood",
               cap_mat="M_Plank")
    # gold cap rail along the bulwark top
    for sgn in (-1, 1):
        for i in range(len(xs) - 1):
            a = Vector((xs[i], sgn * ship_hw(xs[i]), ship_ztop(xs[i], gangway=sgn == GANGWAY_SIDE) + 0.04))
            b = Vector((xs[i + 1], sgn * ship_hw(xs[i + 1]), ship_ztop(xs[i + 1], gangway=sgn == GANGWAY_SIDE) + 0.04))
            if a.z < SHIP_DECK + 0.3 and b.z < SHIP_DECK + 0.3:
                continue
            mid = (a + b) / 2
            v = b - a
            yaw = math.degrees(math.atan2(v.y, v.x))
            pitch = math.degrees(math.atan2(v.z, Vector((v.x, v.y)).length))
            hull.box((v.length + 0.06, 0.2, 0.12), loc=mid, rot=(0, -pitch, yaw), mat="M_Gold")
    # cabin front (under the quarterdeck) facing +x: door, windows, lantern
    qx = SHIP_QD_X + 0.02
    hull.box((0.12, 1.0, 1.45), loc=(qx + 0.06, 0.9, SHIP_DECK + 0.72), mat="M_Door")
    hull.box((0.1, 1.2, 0.12), loc=(qx + 0.08, 0.9, SHIP_DECK + 1.5), mat="M_Gold")
    for yy in (-1.3, -2.3):
        hull.box((0.1, 0.6, 0.5), loc=(qx + 0.07, yy, SHIP_DECK + 1.0), mat="M_Window")
        hull.box((0.12, 0.75, 0.08), loc=(qx + 0.08, yy, SHIP_DECK + 0.7), mat="M_Gold")
    hull.box((0.12, 0.6, 0.6), loc=(SHIP_FC_X - 0.04, 1.4, SHIP_DECK + 0.45), mat="M_Door")
    # portholes along both sides
    for xx in (-6.0, -3.6, -1.2, 1.2, 3.6, 6.0):
        hw = ship_hw(xx)
        for sgn in (-1, 1):
            yy = sgn * (hw * 1.01 + 0.03)
            hull.torus(0.24, 0.06, loc=(xx, yy, 1.55), rot=(90, 0, 0), mat="M_Gold", u=12, v=4)
            hull.cyl(0.19, 0.06, loc=(xx, yy + sgn * 0.0, 1.55), rot=(90, 0, 0), mat="M_Window", verts=12)
    # stern windows (transom) and lanterns
    for yy in (-1.2, 0.0, 1.2):
        hull.box((0.12, 0.7, 0.8), loc=(-SHIP_HL - 0.02, yy, SHIP_DECK + 0.9), mat="M_Window")
        hull.box((0.14, 0.85, 0.1), loc=(-SHIP_HL - 0.03, yy, SHIP_DECK + 1.35), mat="M_Gold")
    for yy in (-2.0, 2.0):
        hull.box((0.12, 0.12, 1.2), loc=(-SHIP_HL + 0.6, yy, SHIP_QD + 0.6), mat="M_Wood_Dark")
        hull.box((0.36, 0.36, 0.46), loc=(-SHIP_HL + 0.6, yy, SHIP_QD + 1.35), mat="M_Glow_window", bevel=0.04, segs=1)
        hull.cyl(0.3, 0.2, loc=(-SHIP_HL + 0.6, yy, SHIP_QD + 1.58), rot=(0, 0, 45), verts=4, r2=0.04,
                 mat="M_Wood_Dark")
    # golden winged figurehead under the bowsprit
    fx, fz = SHIP_HL + 0.1, SHIP_FC - 0.5
    hull.sphere(0.34, loc=(fx, 0, fz), scale=(0.9, 0.75, 1.5), mat="M_Gold", subdiv=2)
    hull.sphere(0.22, loc=(fx + 0.2, 0, fz + 0.62), mat="M_Gold", subdiv=2)
    for sgn in (-1, 1):
        hull.box((1.3, 0.08, 0.55), loc=(fx - 0.45, sgn * 0.4, fz + 0.35), rot=(sgn * 12, -28, sgn * 18),
                 mat="M_Gold", bevel=0.03, segs=1)
    # twin barrel engines with propellers (sail/airship hybrid of the classic sprite)
    for sgn in (-1, 1):
        ey = sgn * (ship_hw(-9.1) + 0.85)
        hull.cyl(0.8, 3.0, loc=(-10.6, ey, 2.0), rot=(0, 90, 0), mat="M_Wood", verts=16, r2=0.85)
        for xx in (-10.4, -9.1, -7.8):
            hull.cyl(0.88, 0.12, loc=(xx, ey, 2.0), rot=(0, 90, 0), mat="M_Metal", verts=16)
        hull.box((1.4, abs(ey) - ship_hw(-9.1) + 0.2, 0.3), loc=(-9.1, (ey + sgn * ship_hw(-9.1)) / 2, 2.0),
                 mat="M_Wood_Dark")
        hull.sphere(0.24, loc=(-10.75, ey, 2.0), mat="M_Metal", subdiv=1)
        for k in range(3):
            a = k * 120 + 20
            hull.box((0.08, 0.34, 1.15), loc=(-10.8, ey + math.sin(math.radians(a)) * 0.6,
                                               2.0 + math.cos(math.radians(a)) * 0.6), rot=(-a, 0, 0),
                     mat="M_Wood", bevel=0.02, segs=1)
    # a smaller pair of barrel engines forward under the bow quarters, so the hovering read carries along the
    # whole hull (the port pods face the camera over the void)
    for sgn in (-1, 1):
        fxp, fl, fr, fz = 3.4, 2.5, 0.62, 1.55
        hwf = ship_hw(fxp + fl / 2)
        ey = sgn * (hwf + 0.78)
        hull.cyl(fr, fl, loc=(fxp, ey, fz), rot=(0, 90, 0), mat="M_Wood", verts=14, r2=fr * 1.08)
        for xx in (fxp + 0.18, fxp + fl / 2, fxp + fl - 0.18):
            hull.cyl(fr * 1.1 + 0.02, 0.1, loc=(xx, ey, fz), rot=(0, 90, 0), mat="M_Metal", verts=14)
        hull.box((1.1, 0.9, 0.24), loc=(fxp + fl / 2, (ey + sgn * hwf) / 2, fz), mat="M_Wood_Dark")
        hull.sphere(0.2, loc=(fxp - 0.12, ey, fz), mat="M_Metal", subdiv=1)
        for k in range(3):
            a = k * 120 + 50
            hull.box((0.07, 0.28, 0.9), loc=(fxp - 0.18, ey + math.sin(math.radians(a)) * 0.46,
                                              fz + math.cos(math.radians(a)) * 0.46), rot=(-a, 0, 0),
                     mat="M_Wood", bevel=0.02, segs=1)
    hull.build("X60000_Ship_Victoria_Hull", coll, smooth=True, sharp_angle=40)

    rig = MeshBuilder()
    masts = ((SHIP_FORE_X, SHIP_DECK, 15.5), (SHIP_MAIN_X, SHIP_DECK, 18.5), (SHIP_MIZ_X, SHIP_QD, 11.5))
    for mx, base, h in masts:
        rig.cyl(0.3, h, loc=(mx, 0, base - 0.1), mat="M_Wood", verts=10, r2=0.17)
        rig.cyl(0.28, 0.28, loc=(mx, 0, base + h - 0.05), mat="M_Gold", verts=10)
    # bowsprit
    bx0 = Vector((SHIP_HL - 0.6, 0, SHIP_FC + 0.5))
    btip = bx0 + Vector((math.cos(math.radians(18)), 0, math.sin(math.radians(18)))) * 4.4
    _line(rig, bx0, btip, 0.17, "M_Wood")
    # fighting top on the main mast (floor supplied by the map deck; rail + trestles here)
    tz = SHIP_TOP
    rig.cyl(1.22, 0.12, loc=(SHIP_MAIN_X, 0, tz - 0.2), mat="M_Plank", verts=14)
    for k in range(8):
        a = 2 * math.pi * k / 8
        rig.box((0.08, 0.08, 0.85), loc=(SHIP_MAIN_X + math.cos(a) * 1.15, math.sin(a) * 1.15, tz + 0.42),
                mat="M_Wood_Dark")
    rig.torus(1.15, 0.06, loc=(SHIP_MAIN_X, 0, tz + 0.85), mat="M_Wood_Dark", u=18, v=4)
    for sgn in (-1, 1):
        rig.box((0.16, 2.6, 0.16), loc=(SHIP_MAIN_X + sgn * 0.45, 0, tz - 0.32), mat="M_Wood_Dark")
    rig.build("X60000_Ship_Victoria_Masts", coll, smooth=True, sharp_angle=45)

    sails = MeshBuilder()
    # (z_lo, z_hi, w_foot, w_head) above each mast's base
    spec = {SHIP_FORE_X: [(3.4, 7.0, 6.4, 6.0), (7.6, 11.0, 5.2, 4.4), (11.5, 14.4, 3.8, 3.0)],
            SHIP_MAIN_X: [(3.6, 7.5, 7.0, 6.4), (8.9, 12.8, 5.6, 4.6), (13.3, 16.8, 4.2, 3.0)],
            SHIP_MIZ_X: [(6.6, 9.6, 4.0, 3.2)]}
    # Moored: the courses and topsails of the fore and main masts are furled on their yards (set, they would hide
    # the gangplank and Shanks on the quay behind the ship); the topgallants and the mizzen stay set.
    for mx, base, h in masts:
        for k, (z_lo, z_hi, w_foot, w_head) in enumerate(spec[mx]):
            if k <= 1 and mx != SHIP_MIZ_X:
                b = math.radians(26.0)
                n = Vector((math.cos(b), -math.sin(b), 0.0))
                d = Vector((math.sin(b), math.cos(b), 0.0))
                _furled_sail(sails, Vector((mx, 0, base + z_hi - 0.3)) + n * 0.32, d, w_head + 0.2)
            else:
                d, n = _square_sail(sails, mx, base + z_hi, base + z_lo, w_head, w_foot)
            yard_c = Vector((mx, 0, base + z_hi + 0.05)) + n * 0.25
            _line(sails, yard_c - d * (w_head / 2 + 0.35), yard_c + d * (w_head / 2 + 0.35), 0.1, "M_Wood_Dark")
    # one jib from the bowsprit to the fore topmast (the lower jib is struck so the quay strip stays clear),
    # spanker aft of the mizzen. Fore-and-aft sails in the ship's x-z plane show the camera their unlit side (the
    # key light comes from local +x+y), so the clew is swung off the centreline toward -y: the camera-facing side
    # then also faces the sun and reads cream.
    fd = SHIP_DECK
    head, tack, clew = (SHIP_FORE_X + 0.4, 0, fd + 13.8), (btip.x - 0.2, 0, btip.z + 0.1), (9.6, 0, SHIP_FC + 1.3)
    _flat_sail(sails, [head, tack, _swing(clew, head, tack, 50.0)], bulge=(0.0, -0.25, 0.1))
    # spanker + boom kept above head height on the walkable quarterdeck, swung 60 deg out toward -y
    mz0, mz1 = (SHIP_MIZ_X - 0.3, 0, 0), (SHIP_MIZ_X - 0.3, 0, 1)
    _flat_sail(sails, [(SHIP_MIZ_X - 0.3, 0, SHIP_QD + 2.2), (SHIP_MIZ_X - 0.3, 0, SHIP_QD + 6.0),
                       _swing((SHIP_MIZ_X - 2.5, 0, SHIP_QD + 5.0), mz0, mz1, 60.0),
                       _swing((SHIP_MIZ_X - 2.7, 0, SHIP_QD + 2.3), mz0, mz1, 60.0)], bulge=(0.15, -0.2, 0.0))
    _line(sails, (SHIP_MIZ_X, 0, SHIP_QD + 2.2), _swing((SHIP_MIZ_X - 3.0, 0, SHIP_QD + 2.3), mz0, mz1, 60.0), 0.08,
          "M_Wood_Dark")
    # standing rigging: shrouds to the rails, stays between mast heads and the bowsprit
    for mx, base, h in masts:
        head = Vector((mx, 0, base + h * 0.72))
        for sgn in (-1, 1):
            if sgn == GANGWAY_SIDE and abs(mx - SHIP_GANGWAY_X) < 2.0:
                # a mast beside the gangway opening: its quay-side shrouds all anchor aft of the opening (default
                # anchors would float over the lowered rail, and a forward pair would cross the plank in Gameplay)
                xs_sh = (SHIP_GANGWAY_X - 3.2, SHIP_GANGWAY_X - 2.6, SHIP_GANGWAY_X - 2.0)
            else:
                xs_sh = (mx - 0.8, mx, mx + 0.8)
            for xx in xs_sh:
                _line(sails, (xx, sgn * ship_hw(xx) * 0.98, ship_ztop(xx) + 0.05), head, 0.035, "M_Rope")
    tops = [Vector((mx, 0, base + h - 0.3)) for mx, base, h in masts]
    _line(sails, tops[0], btip, 0.035, "M_Rope")
    _line(sails, tops[1], tops[0] + Vector((0, 0, -1.5)), 0.035, "M_Rope")
    _line(sails, tops[2], tops[1] + Vector((0, 0, -2.5)), 0.035, "M_Rope")
    # pennants
    for (mx, base, h), mat in zip(masts, ("M_Flat_roof_blue", "M_Cloth_Red", "M_Flat_roof_blue")):
        zt = base + h + 0.15
        sails.quad((mx, 0, zt), (mx, 0, zt - 0.7), (mx - 1.6, 0.0, zt - 0.45), (mx - 1.6, 0.0, zt - 0.25), mat)
        sails.tri((mx - 1.6, 0.0, zt - 0.45), (mx - 2.6, 0.0, zt - 0.36), (mx - 1.6, 0.0, zt - 0.25), mat)
    sails.build("X60000_Ship_Victoria_Sails", coll, smooth=True, sharp_angle=60, recalc_normals=False)


# =====================================================================================
# helpers
# =====================================================================================

def solid_stairs(m, name, p0, p1, width, step_h=0.28, top="M_Plaster", side="M_Sand_Cliff", base=-0.5,
                 parapet=0.0, parapet_sides=(-1, 1), overshoot=0.6):
    """Solid masonry stairs from p0 (bottom) to p1 (top): stacked blocks with whitewashed treads (walkable)."""
    (x0, y0, z0), (x1, y1, z1) = p0, p1
    dz = z1 - z0
    n = max(2, int(round(abs(dz) / step_h)))
    run = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / run, (y1 - y0) / run
    nx, ny = -uy, ux

    def P(s, w):
        return m.wxy(x0 + ux * s + nx * w, y0 + uy * s + ny * w)

    oz = m.origin.z
    mb = MeshBuilder()
    for i in range(n):
        s0 = run * i / n - (0.0 if i == 0 else 0.02)
        s1 = run * (i + 1) / n if i < n - 1 else run + overshoot
        z = z0 + dz * (i + 1) / n
        if i == n - 1:  # the landing block runs under the upper terrace's cap: keep it 3 cm low (no z-fight)
            z -= 0.03
        poly = [P(s0, -width / 2), P(s1, -width / 2), P(s1, width / 2), P(s0, width / 2)]
        mb.prism(poly, oz + base, oz + z, mat=side, cap_mat=top)
        if parapet > 0:
            for sd in parapet_sides:
                wa, wb = (width / 2 - 0.45, width / 2) if sd > 0 else (-width / 2, -width / 2 + 0.45)
                pp = [P(s0, wa), P(s1, wa), P(s1, wb), P(s0, wb)]
                mb.prism(pp, oz + z - 0.1, oz + z + parapet, mat=WALL)
    # geo.MeshBuilder.prism(cap_mat=...) tests f.normal before bmesh normals exist, so the cap material is
    # silently dropped: recompute normals here and paint every up-facing face (treads + parapet tops).
    mb.bm.normal_update()
    ti = mb.mat(top)
    for f in mb.bm.faces:
        if f.normal.z > 0.7:
            f.material_index = ti
    obj = mb.build(f"{m.slug}_{name}", m.col_terrain, smooth=False)
    m.add_ground(obj)
    return obj


def parapet(m, name, pts, z, h=0.5, w=0.32, gaps=()):
    """Whitewashed low wall along a local polyline on top of a tier edge (decor, not ground).

    gaps: (x, y, r) circles where wall pieces are left out (ladder heads, stair tops)."""
    mb = MeshBuilder()
    for i in range(len(pts) - 1):
        (xa0, ya0), (xb0, yb0) = pts[i], pts[i + 1]
        seg = math.hypot(xb0 - xa0, yb0 - ya0)
        n = max(1, int(round(seg / 1.0)))
        yaw = math.degrees(math.atan2(yb0 - ya0, xb0 - xa0)) + m.yaw
        for k in range(n):
            cx = xa0 + (xb0 - xa0) * (k + 0.5) / n
            cy = ya0 + (yb0 - ya0) * (k + 0.5) / n
            if any(math.hypot(cx - gx, cy - gy) < gr for gx, gy, gr in gaps):
                continue
            mb.box((seg / n + 0.03, w, h), loc=m.w(cx, cy, z + h / 2 - 0.05), rot=(0, 0, yaw), mat=WALL,
                   bevel=0.05, segs=1)
    if mb.bm.verts:
        CT.tag(mb.build(f"{m.slug}_{name}", m.col_arch, smooth=False), CT.WALL)


def face_y(m, x, y_top, y_dir=-1.0):
    """Local y of the -y facing cliff edge reached by marching from (x, y_top) on a terrace top."""
    fp = m.face_point(x, y_top, 0.0, y_dir)
    if fp is None:
        raise ValueError(f"[{m.slug}] face_y: no edge from ({x}, {y_top})")
    return fp[1]


def plaster_band(m, name, xs, y_top, z0, z1, t=0.2):
    """Whitewashed band along a -y facing retaining wall, just under its cap: one slab per 1 m, each set on
    the edge found by face_point (the outlines wobble)."""
    mb = MeshBuilder()
    x0, x1 = xs
    n = max(1, int(round((x1 - x0) / 1.0)))
    for k in range(n):
        cx = x0 + (x1 - x0) * (k + 0.5) / n
        ey = face_y(m, cx, y_top)
        mb.box(((x1 - x0) / n + 0.04, t, z1 - z0), loc=m.w(cx, ey + 0.06, (z0 + z1) / 2), rot=(0, 0, m.yaw),
               mat=WALL, bevel=0.04, segs=1)
    CT.tag(mb.build(f"{m.slug}_{name}", m.col_arch, smooth=False), CT.WALL)


def mooring_rope(m, name, p, q, sag=0.4, r=0.05):
    """Sagging rope between two local points (x, y, z); the name contains 'Rope' so routes may pass under it."""
    mb = MeshBuilder()
    pts = []
    for i in range(11):
        t = i / 10
        pts.append(m.w(p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t,
                       p[2] + (q[2] - p[2]) * t - math.sin(math.pi * t) * sag))
    for a, b in zip(pts, pts[1:]):
        _line(mb, a, b, r, "M_Rope")
    CT.tag(mb.build(f"{m.slug}_{name}", m.col_arch, smooth=False), CT.WALL)


def planter(m, name, outline, base, h=0.5):
    """Raised Mediterranean planter bed: green top over a beige masonry rim."""
    m.terrace(name, outline, top=base + h, bottom=base - 0.3, style="grass_sand")


def layered_path(m, name, pts, lift, **kw):
    """m.path at a fixed height above the ground. geo.path_ribbon adds 0.006 * (ribbon count % 6) to its lift so
    successive ribbons layer, but the count wraps, so a road laid after its kerb can land under it; this cancels
    that term (cream road over cobble kerb over the ramp blend ribbons, whatever the count)."""
    n = getattr(geo, "_RIBBON_COUNT", None)
    base = lift - 0.006 * ((n + 1) % 6) if isinstance(n, int) else lift
    return m.path(name, pts, lift=base, **kw)


def vines(m, pts, z, seed=0, scale=1.0):
    for i, (x, y) in enumerate(pts):
        m.place("Vine_Hanging_A", x, y, z=z, rot=(i * 37 + seed) % 360, scale=(0.9 + (i % 3) * 0.12) * scale)


# =====================================================================================
# build
# =====================================================================================

def build(m):
    L, D = m.size  # 82 x 46
    shx, shy = SHIP

    # ------------------------------------------------------------------ terrain
    # Zone A: west town square (T29) and the cliff-top ledge (T30)
    m.terrace("WestSquare", [(-0.8, 2.4), (8.5, 1.9), (16.9, 2.6), (17.1, 13.0), (16.8, 24.4), (16.9, 31.0),
                             (16.7, 46.6), (-0.8, 46.6)], top=Z_SQ, bottom=-0.5, style="sandstone")
    m.terrace("Ledge_T30", [(15.8, 24.2), (20.9, 23.9), (21.4, 27.4), (21.0, 31.0), (15.8, 31.0)], top=Z_SQ,
              bottom=-0.5, style="sandstone")
    # (west00 sits at (4.5, 45) on the back edge: the 4.5 m corridor x 2.25..6.75 behind it stays paving only)
    planter(m, "Garden_NW", [(-0.8, 43.4), (1.2, 43.4), (1.6, 46.6), (-0.8, 46.6)], Z_SQ, 0.5)
    planter(m, "Garden_HouseBack", geo.rounded_rect(10.6, 43.4, 16.4, 46.6, 1.0), Z_SQ, 0.45)
    planter(m, "Garden_HouseFront", geo.rounded_rect(13.2, 34.2, 16.2, 38.6, 0.9), Z_SQ, 0.45)
    planter(m, "Planter_SquareSW", geo.rounded_rect(-0.6, 2.6, 2.8, 6.8, 1.0), Z_SQ, 0.5)
    planter(m, "Planter_SquareFront", geo.rounded_rect(6.2, 2.3, 13.4, 4.3, 0.8), Z_SQ, 0.45)
    planter(m, "Planter_SquareTree", geo.ellipse(11.2, 26.8, 2.0, 1.7, 16), Z_SQ, 0.5)

    # Zone B: sunken market street (T34) and its ramp up to the east part
    m.terrace("StreetLow", [(16.2, 1.6), (37.4, 1.3), (37.6, 15.6), (40.2, 16.0), (40.2, 31.2), (16.2, 31.2)],
              top=Z_ST, bottom=-0.5, style="sandstone")
    m.ramp("Street_Ramp", (36.4, 8.8, Z_ST), (41.0, 8.8, Z_UP), 13.6, style="sandstone", bottom=-0.5)
    m.terrace("UpperStreet", [(40.8, 1.3), (61.8, 1.3), (61.8, 6.4), (52.4, 6.4), (52.4, 13.6), (53.4, 14.0),
                              (53.6, 23.2), (44.6, 23.4), (44.4, 31.2), (39.4, 31.2), (39.4, 16.2), (40.8, 15.8)],
              top=Z_UP, bottom=-0.5, style="sandstone")
    planter(m, "Planter_StreetFront_A", geo.rounded_rect(17.2, 1.7, 23.0, 3.4, 0.7), Z_ST, 0.5)
    planter(m, "Planter_StreetFront_B", geo.rounded_rect(25.4, 1.6, 31.4, 3.3, 0.7), Z_ST, 0.5)
    planter(m, "Planter_StreetFront_C", geo.rounded_rect(33.0, 1.5, 36.2, 3.2, 0.7), Z_ST, 0.5)
    planter(m, "Planter_StreetTree", geo.ellipse(30.2, 5.8, 1.8, 1.5, 16), Z_ST, 0.5)
    planter(m, "Planter_UpperFront", geo.rounded_rect(42.4, 1.5, 50.6, 3.2, 0.7), Z_UP, 0.5)
    planter(m, "Planter_UpperPalm", geo.ellipse(45.2, 15.2, 1.5, 1.3, 14), Z_UP, 0.5)
    # stepped planter boxes flanking the wide street ramp: their stepping tops make the 1.4 m rise read
    for i, (xa, xb, top) in enumerate(((36.5, 38.0, 1.6), (38.1, 39.7, 2.1), (39.8, 41.7, 2.55))):
        m.terrace(f"RampPlanter_Front{i}", geo.rounded_rect(xa, 1.6, xb, 3.8, 0.6), top=top, bottom=-0.5,
                  style="grass_sand")
    for i, (xa, xb, top) in enumerate(((36.5, 38.0, 1.6), (38.1, 39.6, 2.1))):
        m.terrace(f"RampPlanter_Back{i}", geo.rounded_rect(xa, 13.7, xb, 15.6, 0.6), top=top, bottom=0.3,
                  style="grass_sand")
    # the classic cliff: two ropes down from the ledge, plus a carved stair for the main route
    m.ladder("Rope_Street_Ledge_A", 17.8, 23.75, Z_ST, Z_SQ, kind="rope")
    m.ladder("Rope_Street_Ledge_B", 19.9, 23.6, Z_ST, Z_SQ, kind="rope")
    solid_stairs(m, "WestStair", (21.6, 10.8, Z_ST), (16.6, 10.8, Z_SQ), 3.6)

    # Zone C: Biggs's belvedere (T12 west, T10 east) high behind the street
    m.terrace("Belvedere_W", [(16.3, 30.5), (27.8, 30.3), (27.9, 46.6), (16.3, 46.6)], top=Z_BW, bottom=-0.5,
              style="sandstone")
    m.terrace("Belvedere_E", [(27.0, 30.6), (38.9, 30.6), (39.1, 39.0), (44.6, 39.0), (44.6, 46.6), (27.0, 46.6)],
              top=Z_BE, bottom=-0.5, style="sandstone")
    # (the walkable belvedere is its front strip y 30.5..~39: the back half is lined with whitewashed houses)
    solid_stairs(m, "Belvedere_Step", (26.0, 35.0, Z_BW), (28.4, 35.0, Z_BE), 2.6)
    m.ladder("Ladder_Ledge_Belvedere", 18.8, 30.1, Z_SQ, Z_BW, facing=90)
    planter(m, "Garden_BelvW", geo.rounded_rect(22.6, 41.0, 26.6, 46.4, 1.0), Z_BW, 0.5)
    planter(m, "Garden_BelvE", geo.rounded_rect(38.8, 41.6, 44.2, 46.4, 1.2), Z_BE, 0.5)
    planter(m, "Planter_BelvFront", geo.rounded_rect(22.0, 31.2, 25.6, 32.8, 0.6), Z_BW, 0.45)
    # east access: ladder x1649 to the slab landing (T22), then the slab stair up to T10
    m.terrace("SlabTower", [(38.9, 30.0), (44.4, 30.0), (44.4, 39.3), (38.9, 39.3)], top=Z_SLAB, bottom=-0.5,
              style="sandstone")
    m.ladder("Ladder_Street_Slab", 41.0, 29.7, Z_UP, Z_SLAB, facing=90)
    solid_stairs(m, "SlabStair", (42.8, 32.8, Z_SLAB), (42.8, 39.4, Z_BE), 2.6)

    # Zone D: the knoll (T28, the classic lighthouse hump: its annex and chapel stay) and the grand staircase
    m.terrace("LighthouseKnoll", [(44.6, 22.6), (52.8, 22.4), (54.6, 26.0), (54.8, 33.5), (54.0, 39.6), (44.6, 39.8),
                                  (43.9, 33.0), (44.2, 27.0)], top=Z_MOUND, bottom=-0.5, style="grass_sand")
    solid_stairs(m, "Knoll_Steps", (48.0, 19.0, Z_UP), (48.0, 21.9, Z_MOUND), 2.8)
    # The grand staircase (classic 7 rises from the hump to the quay) climbs toward the back (+y) from the
    # street's front promenade onto the quay, so its risers face the camera (risers facing +-x are edge-on
    # or back-facing at this map's yaw). It overlaps the upper street (x<=52.4) and the quay's east block
    # (x>=61.3) so no gap opens between them; parapet on the open west side.
    solid_stairs(m, "GrandStair", (56.95, 6.4, Z_UP), (56.95, 13.6, Z_QUAY), 9.2, parapet=0.7, parapet_sides=(1,))

    # Zone E: quay (T20), gangplank and the ship. Southperry's front edge is the island rim: the ship <Victoria>
    # hovers on its barrel engines off the quay's front lip (over the rim), broadside to the camera, tied to
    # bollards on the lip. Its deck sits 0.9 m above the quay, so the gangplank climbs as in the classic map.
    m.terrace("Quay", [(61.3, 3.4), (82.6, 3.0), (82.6, 26.4), (52.9, 26.4), (52.9, 13.5), (61.3, 13.5)],
              top=Z_QUAY, bottom=-0.5, style="sandstone")
    # the harbour quarter: whitewashed houses stepping up behind the quay in two terraces (where the walled
    # basin used to be), reached by a stair from the quay; a garden terrace fills the corner behind the knoll
    # (both reach the back-right corner + 0.9 m: at 82.6 / 46.6 their rounded corner left a body-sized plinth-level
    # pocket inside the containment ring's corner, 9.6 m under the quarter; Iteration Three stuck-region scan)
    m.terrace("Quarter_Low", [(54.2, 26.0), (82.9, 25.8), (82.9, 46.9), (54.2, 46.9)], top=Z_QL, bottom=-0.5,
              style="sandstone")
    m.terrace("Quarter_High", [(57.6, 36.2), (82.9, 36.0), (82.9, 46.9), (57.6, 46.9)], top=Z_QH, bottom=Z_QL - 0.5,
              style="sandstone")
    m.terrace("KnollBack", [(44.4, 39.4), (54.4, 39.4), (54.4, 46.6), (44.4, 46.6)], top=5.4, bottom=-0.5,
              style="grass_sand")
    solid_stairs(m, "QuarterStair", (64.4, 22.0, Z_QUAY), (64.4, 26.0, Z_QL), 3.6, parapet=0.6)
    solid_stairs(m, "QuarterStair_Up", (63.2, 33.0, Z_QL), (63.2, 36.2, Z_QH), 2.8)
    planter(m, "Planter_QuayPalm_A", geo.rounded_rect(68.4, 10.0, 70.8, 12.4, 0.7), Z_QUAY, 0.5)
    planter(m, "Planter_QuayPalm_B", geo.rounded_rect(73.2, 8.4, 75.8, 11.0, 0.7), Z_QUAY, 0.5)
    gx = shx + SHIP_GANGWAY_X
    ship_z = Z_QUAY + 0.9 - SHIP_DECK          # the ship's waterline (its keel floats ~2 m above the plinth)
    deck_z = ship_z + SHIP_DECK
    deck_edge = shy + ship_hw(SHIP_GANGWAY_X) * 0.93
    m.ramp("Gangway_Base", (gx, 4.2, Z_QUAY - 0.08), (gx, deck_edge - 0.8, deck_z + 0.05), 2.0, style="wood_floor",
           bottom=Z_QUAY - 0.6, extend=0.3, segments=1)
    m.bridge("Gangplank", (gx, 4.1, Z_QUAY), (gx, deck_edge - 0.8, deck_z + 0.14), width=2.0, sag=0.0)
    m.place("X60000_Ship_Victoria", shx, shy, rot=0, z=ship_z)
    # small cloud puffs drifting under the keel, peeking out under the port (camera-side) bilge: the ship floats
    # off the rim, it does not rest on the cliff
    for (cxo, cyo, czo, a, s, r) in ((-7.4, -2.3, -1.75, "Cloud_Puff_A", 0.7, 20),
                                     (0.4, -2.5, -1.95, "Cloud_Puff_B", 0.75, 160),
                                     (7.2, -2.1, -1.6, "Cloud_Puff_A", 0.6, 250)):
        m.place(a, shx + cxo, shy + cyo, z=ship_z + czo, rot=r, scale=s)

    def ship_poly(x0, x1, shrink=0.93):
        return [(shx + x, max(SHIP_DECK_YMIN, shy + y)) for x, y in ship_deck_poly(x0, x1, shrink)]

    m.deck("ShipDeck", ship_poly(SHIP_QD_X, SHIP_FC_X), top=deck_z + 0.02, posts=False)
    m.deck("ShipQuarterdeck", ship_poly(-SHIP_HL + 0.3, SHIP_QD_X, 0.94), top=ship_z + SHIP_QD + 0.02, posts=False)
    m.deck("ShipForecastle", ship_poly(SHIP_FC_X, SHIP_HL - 1.3, 0.94), top=ship_z + SHIP_FC + 0.02, posts=False)
    m.stairs("Ship_QD_Stairs", (shx + SHIP_QD_X + 2.7, shy + 2.0, deck_z),
             (shx + SHIP_QD_X + 0.05, shy + 2.0, ship_z + SHIP_QD + 0.02), 1.2)
    m.stairs("Ship_FC_Stairs", (shx + SHIP_FC_X - 1.9, shy + 1.6, deck_z),
             (shx + SHIP_FC_X + 0.05, shy + 1.6, ship_z + SHIP_FC + 0.02), 1.2)
    top_z = ship_z + SHIP_TOP
    mast_x = shx + SHIP_MAIN_X
    m.deck("MastTop", geo.ellipse(mast_x, shy, 1.2, 1.2, 14), top=top_z, posts=False)
    m.ladder("MastRope", mast_x - 0.7, shy - 0.4, deck_z, top_z, kind="rope")
    # mooring lines from the starboard bulwark to bollards on the quay lip
    for i, (xr, bx) in enumerate(((-8.2, 66.2), (-3.2, 70.8), (4.6, 77.5))):
        by = 3.75 - (bx - 61.3) * 0.019
        m.place("Dock_Bollard", bx, by)
        mooring_rope(m, f"MooringRope_{i}", (shx + xr, shy + ship_hw(xr) * 0.98, ship_z + ship_ztop(xr) + 0.05),
                     (bx, by, Z_QUAY + 0.55), sag=0.35)

    # ------------------------------------------------------------------ whitewashed parapets on the tier edges
    parapet(m, "Parapet_SquareCliff_S", [(16.35, 3.2), (16.55, 8.7)], Z_SQ)
    parapet(m, "Parapet_SquareCliff_N", [(16.55, 12.9), (16.45, 23.7)], Z_SQ)
    parapet(m, "Parapet_BelvW", [(16.9, 30.95), (27.2, 30.8)], Z_BW, gaps=[(18.8, 30.9, 0.9)])
    parapet(m, "Parapet_BelvE", [(27.7, 31.05), (38.4, 31.05)], Z_BE)
    parapet(m, "Parapet_SlabTower", [(39.4, 30.45), (44.0, 30.45)], Z_SLAB, gaps=[(41.0, 30.4, 0.9)])
    parapet(m, "Parapet_QuayWest", [(53.35, 14.0), (53.35, 26.0)], Z_QUAY)
    parapet(m, "Parapet_QuayFrontWest", [(61.75, 3.9), (61.75, 6.3)], Z_QUAY)
    parapet(m, "Parapet_QuarterLow", [(54.6, 26.35), (62.4, 26.3), (66.4, 26.3), (82.2, 26.15)], Z_QL,
            gaps=[(64.4, 26.3, 1.9)])
    parapet(m, "Parapet_QuarterHigh", [(58.0, 36.55), (61.4, 36.5), (65.0, 36.5), (82.2, 36.35)], Z_QH,
            gaps=[(63.2, 36.5, 1.6)])

    # ------------------------------------------------------------------ retaining-wall dressing
    # The belvedere wall over the street: a whitewash band under the cap, an arched doorway at street level,
    # blue-shuttered windows with flower boxes where the wall shows above the shop roofs.
    plaster_band(m, "Band_BelvW", (16.4, 27.4), 33.0, Z_BW - 1.05, Z_BW - 0.15)
    plaster_band(m, "Band_BelvE", (27.4, 38.8), 33.0, Z_BE - 1.05, Z_BE - 0.15)
    plaster_band(m, "Band_SlabTower", (39.0, 44.3), 32.0, Z_SLAB - 0.95, Z_SLAB - 0.15)
    plaster_band(m, "Band_QuarterLow", (54.4, 82.4), 29.0, Z_QL - 0.85, Z_QL - 0.15)
    for (x, z, yt) in ((20.7, 5.9, 33.0), (24.2, 6.4, 33.0), (29.6, 6.9, 33.0), (37.6, 6.2, 33.0),
                       (43.2, 4.3, 32.0)):
        m.place("X60000_WallWindow", x, face_y(m, x, yt) + 0.1, z=z, rot=0)
    m.place("X60000_WallArch", 37.3, face_y(m, 37.3, 33.0) + 0.1, z=Z_ST, rot=0)

    # ------------------------------------------------------------------ landmarks
    # west square: the blue-domed house (Paul on its front-wing roof terrace, the unreachable T21)
    hx, hy, HS = 11.0, 39.5, 1.0
    m.place("X60000_DomeHouse", hx, hy, rot=0, scale=HS)
    wing_top = Z_SQ - 0.04 + 2.92 * HS
    m.deck("PaulTerrace", geo.rect(hx - 2.6 * HS, hy - 3.7 * HS, hx + 1.4 * HS, hy - 1.2 * HS), top=wing_top,
           posts=False, mat=WALL)
    m.place("X60000_CubeHouse", 1.0, 40.0, rot=90, scale=0.85)
    m.place("Clothesline_Laundry", 12.4, 31.6, rot=0)
    # street: Armor Store (door in00; moved east so the ledge ropes have a clear lane), the domed tower, racks
    sx, sy = 26.5, 24.6
    m.place("X60000_ArmorStore", sx, sy, rot=0)
    m.place("X60000_ShieldSign", 22.0, 20.4, rot=0)
    m.place("X60000_DomeTower", 33.6, 25.2, rot=0)
    m.place("Market_Stall", 35.4, 19.8, rot=0)
    m.place("X60000_FabricRolls", 38.2, 22.4, rot=-25)
    m.place("X60000_FabricRolls", 31.8, 19.0, rot=10, scale=0.9)
    # the ledge ropes: a davit with a pulley on the T30 lip over each rope, a coil at each foot
    for (x, y) in ((18.0, 23.75), (19.9, 23.6)):  # pulleys over the kit ropes' lip points
        m.place("X60000_RopeDavit", x, y + 0.95, rot=0)
    m.place("Rope_Coil", 16.9, 22.6)
    m.place("Rope_Coil", 21.0, 22.7, rot=60)
    # belvedere: the walkable front strip has Biggs's market canopy, cafe tables, blue crates and pots; the back
    # half is lined with whitewashed houses and garden trees (no more empty flagstone mesa)
    m.place("X60000_Gazebo", 33.0, 35.4, rot=0)
    m.place("X60000_CafeTable", 21.2, 37.6, rot=10)
    m.place("X60000_CafeTable", 24.8, 37.8, rot=-15)
    m.place("X60000_BluePots", 26.2, 39.6, rot=10)
    m.place("X60000_BlueCrate", 17.4, 38.0, rot=15)
    m.place("X60000_BlueCrate", 17.6, 39.1, rot=-10)
    m.place("X60000_BlueCrate", 17.5, 38.55, rot=30, z=Z_BW + 0.86)
    m.place("X60000_BlueCrate", 28.8, 39.0, rot=-12)
    m.place("X60000_BlueCrate", 28.85, 39.0, rot=8, z=Z_BE + 0.86)
    m.place("Sack", 29.8, 39.4)
    m.place("Bench", 29.4, 32.0, rot=180)
    m.place("Bench", 36.4, 32.0, rot=180)
    m.place("X60000_CubeHouse", 19.6, 43.6, rot=0)
    m.place("X60000_StepHouse_B", 30.8, 43.6, rot=0)
    m.place("X60000_DomeTower", 36.2, 43.8, rot=0)
    # the knoll (T28): the classic blue-roofed whitewashed annex and a small domed chapel
    m.place("X60000_CubeHouse", 51.3, 28.6, rot=0, scale=0.85)
    m.place("X60000_DomeTower", 48.6, 35.0, rot=0, scale=0.9)
    # harbour quarter
    m.place("X60000_StepHouse_A", 57.6, 31.4, rot=0)
    m.place("X60000_DomeTower", 69.0, 31.2, rot=0)
    m.place("X60000_CubeHouse", 76.2, 30.9, rot=0)
    m.place("X60000_CubeHouse", 59.6, 43.0, rot=0, scale=0.95)
    m.place("X60000_StepHouse_B", 67.6, 43.2, rot=0)
    m.place("X60000_DomeTower", 74.2, 43.2, rot=0, scale=1.08)
    m.place("X60000_StepHouse_A", 79.4, 43.2, rot=0)
    # the lighthouse stands on the quay's front-east corner at the island rim, beside the ship's bow (classic
    # world map): ~19-20 m at a uniform 1.15 (round dome), taller than the masts and the tallest thing in the
    # south of the island; its footprint is pinned by the quay edge and the gangplank route. Door turned toward
    # the gangplank.
    LH = (79.6, 6.6, 1.15)
    m.place("X60000_Lighthouse_Tall", LH[0], LH[1], rot=-35, scale=(LH[2], LH[2], LH[2]))
    # quay east end: the two photo boards (kept out of the lighthouse's sight shadow toward -x,+y)
    m.place("X60000_PhotoBoard_Lady", 80.3, 15.2, rot=-8)
    m.place("X60000_PhotoBoard_Ring", 81.1, 18.6, rot=-4)
    # quay: Shanks's ticket booth, the cargo derrick swinging a net over the gap, a fish stall
    m.place("X60000_TicketBooth", 68.4, 6.2, rot=0)
    m.place("X60000_CargoDerrick", 65.2, 5.2, rot=0)
    m.place("X60000_FishStall", 68.2, 15.8, rot=0)

    # ------------------------------------------------------------------ dressing
    # west square
    # The island trail from A Split Road (50000:east01) arrives at west00 (4.5, 45) on the back edge on the
    # island's cream main road, which carries on through the town to the ship: the arrival road down the square's
    # west side to the west stair (the town's main axis), across the sunken street and up its ramp to the grand
    # stair, then over the quay to the gangplank (it breaks over the stairs: ribbons on 0.28 m risers smear).
    road = [(4.5, 46.6), (4.6, 41.0), (5.2, 33.0), (6.8, 24.0), (10.0, 16.6), (13.4, 12.4), (16.8, 10.8)]
    street = [(21.8, 10.8), (24.0, 10.4), (30.0, 9.6), (36.4, 8.8), (41.0, 8.8), (46.0, 7.0), (50.4, 5.6),
              (54.6, 5.4), (56.95, 6.3)]
    # (the quay road keeps 2 m off the grand stair's top treads - a ribbon over 0.28 m risers tears - and swings
    # round its head before running down to the gangplank)
    quay = [(56.95, 15.0), (59.6, 15.3), (62.6, 15.0), (64.6, 13.0), (66.6, 10.6), (70.2, 7.8), (gx - 0.9, 6.6),
            (gx, 5.6), (gx, 4.2)]
    # each cream band sits on a cobble kerb like the arrival road's, so it reads as a paved road, not drifted sand
    for (nm, pts, w) in (("", road, 3.6), ("_Street", street, 3.2), ("_Quay", quay, 3.0)):
        layered_path(m, f"Main_Road{nm}_Border", pts, 0.086, width=w + 1.2, mat="M_Cobble_Path")
        layered_path(m, f"Main_Road{nm}", pts, 0.11, **{**MAIN_ROAD, "width": w})
    for (x, y, r) in ((0.8, 4.6, 20), (15.6, 4.4, 160), (1.0, 45.2, 200), (11.2, 26.8, 40)):
        m.place("Tree_Palm_A", x, y, rot=r)
    m.place("Tree_Round_C", 14.4, 45.2, rot=40)
    m.place("Tree_Round_A", 11.9, 45.3, rot=200, scale=0.85)
    m.place("Crate_Stack", 3.6, 8.4, rot=12)
    m.place("Barrel", 5.6, 7.8)
    m.place("Barrel", 2.6, 10.2, rot=40)
    m.place("Lamp_Post", 1.4, 11.6, rot=0)
    m.place("Lamp_Post", 15.4, 15.0, rot=180)
    m.place("Lamp_Post", 15.4, 6.6, rot=180)
    m.place("Bench", 14.6, 22.0, rot=90)
    m.place("Bench", 9.8, 5.4, rot=180)
    m.place("Bench", 13.9, 27.4, rot=90)
    m.place("Sign_Board", 11.0, 21.4, rot=-20)
    for (x, y) in ((7.2, 3.3), (9.6, 3.3), (12.0, 3.3)):
        m.place("Flower_Bed_Large", x, y, scale=0.8)
    m.place("Flower_Patch_A", 1.6, 3.6)
    # low flowers in the planter so the domed house's bell wall reads from the camera
    m.place("Flower_Patch_A", 14.0, 35.4)
    m.place("Flower_Patch_B", 15.2, 36.6)
    m.place("Flower_Patch_A", 14.2, 37.6, rot=90)
    m.place("Bush_Flowering_A", 8.9, 33.4)
    m.place("Bush_B", 16.0, 28.0)
    m.place("X60000_BluePots", 12.0, 34.6, rot=30, scale=0.8)
    m.place("Butterfly", 10.0, 6.0)
    m.place("Flower_Patch_B", 10.2, 25.0)
    m.place("Cart", 9.0, 31.0, rot=-60)
    m.place("Sack", 8.8, 29.2)
    m.place("Barrel", 11.0, 32.9)
    m.place("X60000_BluePots", 13.6, 8.6, rot=200, scale=0.7)
    m.place("Flower_Patch_A", 14.0, 15.6)
    m.place("Flower_Patch_B", 4.8, 11.4)
    m.place("Fountain_Small", 8.0, 9.0)
    # street
    m.place("Bush_A", 22.2, 28.4)
    m.place("Bush_C", 30.9, 28.6, rot=30)
    m.place("X60000_BluePots", 31.3, 21.6, rot=-20, scale=0.8)
    m.place("Lamp_Post", 21.4, 15.6, rot=0)
    m.place("Lamp_Post", 33.4, 15.4, rot=0)
    m.place("Signpost_Notice", 18.0, 17.0, rot=15)
    m.place("Crate_Stack", 36.4, 16.6, rot=-8)
    m.place("Sack", 34.2, 17.6)
    # low dressing in the front street planter (a tall tree here hid the street from the gameplay camera)
    m.place("Sunflower_Patch", 30.0, 5.9)
    m.place("Bush_C", 31.0, 5.3)
    m.place("Flower_Patch_B", 29.0, 5.4)
    m.place("Bench", 27.8, 5.8, rot=270)
    m.place("Bench", 32.6, 5.8, rot=90)
    m.place("Tree_Palm_A", 18.6, 2.6, rot=100)
    for (x, y) in ((21.0, 2.6), (26.6, 2.5), (29.2, 2.5)):
        m.place("Flower_Bed_Large", x, y, scale=0.75)
    m.place("Bush_C", 23.8, 2.0)
    m.place("Bush_Flowering_A", 35.4, 2.6)
    # ramp planters
    m.place("Flower_Patch_A", 37.2, 2.7)
    m.place("Bush_C", 38.9, 2.6)
    m.place("Flower_Patch_B", 40.7, 2.7)
    m.place("Flower_Patch_B", 37.2, 14.6)
    m.place("Bush_C", 38.8, 14.7)
    # back of the street, in front of the slab tower (where the extra cube house used to stand)
    m.place("Barrel", 35.4, 28.6, rot=40)
    m.place("Bush_Flowering_A", 38.8, 27.6)
    # upper street + knoll (the corridor x 39.4..44.4 to the slab ladder stays clear)
    m.place("Treasure_Chest", 43.0, 24.6, rot=-15)
    m.place("Lamp_Post", 42.9, 15.6, rot=0)
    m.place("Lamp_Post", 51.8, 7.2, rot=180)  # flanking the grand stair's foot (the other is on the quay)
    m.place("Lamp_Post", 51.4, 14.4, rot=180)
    m.place("Barrel", 45.8, 18.4)
    m.place("Sack", 46.1, 19.5)
    m.place("Bench", 43.4, 12.2, rot=90)
    m.place("Market_Stall", 43.6, 20.0, rot=0)
    m.place("X60000_FabricRolls", 45.8, 21.4, rot=-10, scale=0.9)
    m.place("Crate", 38.6, 18.6, rot=20)
    m.place("Crate_Stack", 51.0, 18.4, rot=5)
    m.place("Tree_Palm_A", 45.2, 15.2, rot=300)
    for (x, y) in ((43.6, 2.4), (46.4, 2.4), (49.2, 2.3)):
        m.place("Flower_Bed_Large", x, y, scale=0.75)
    # rocks: on the knoll and at its front foot (rocky outcrop under the lighthouse)
    for (x, y, a, s) in ((45.4, 23.4, "Rock_B", 0.55), (53.8, 24.6, "Rock_A", 1.0), (45.6, 36.0, "Rock_B", 0.6),
                         (52.0, 23.4, "Rock_C", 1.2), (50.6, 21.5, "Rock_A", 0.75), (52.1, 21.7, "Rock_C", 1.3),
                         (44.0, 22.0, "Rock_C", 1.0)):
        m.place(a, x, y, rot=x * 13, scale=s)
    # (no tree on the knoll: a palm canopy here reached over the slab stair; the domed chapel is the vertical)
    m.place("Bush_A", 45.6, 29.4)
    m.place("Bush_B", 52.6, 37.6)
    m.place("Bush_A", 45.7, 38.4)
    m.place("Bench", 52.4, 33.0, rot=90)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A"], geo.rect(45.4, 23.6, 53.6, 38.3), 8, seed=4,
              min_dist=1.4, z_band=(3.2, 4.2),
              avoid=[(48.6, 35.0, 2.8), geo.rect(49.0, 26.4, 54.4, 31.0), geo.rect(46.0, 22.0, 49.0, 31.4)])
    # belvedere gardens between the back-row houses
    for (x, y, a, r) in ((23.6, 43.4, "Tree_Palm_A", 70), (25.4, 45.4, "Tree_Round_C", 0),
                         (40.4, 44.0, "Tree_Palm_A", 250), (43.0, 45.0, "Tree_Round_C", 0)):
        m.place(a, x, y, rot=r)
    for (x, y) in ((16.8, 41.6), (42.4, 42.4), (27.2, 41.2)):
        m.place("Bush_Flowering_A", x, y)
    m.place("X60000_BluePots", 22.2, 40.4, rot=-20, scale=0.8)
    m.place("X60000_BluePots", 33.6, 40.6, rot=40, scale=0.75)
    m.place("Flower_Bed_Large", 23.8, 32.0, scale=0.8)
    m.place("Bush_C", 26.2, 32.0)
    # grand stair + quay
    m.place("Lamp_Post", 62.4, 5.9, rot=0)
    m.place("Lamp_Post", 61.9, 13.0, rot=0)  # at the stair head, on the main road's kerb
    # Shanks beside the gangplank foot on the quay front strip, facing the camera, in the screen gap between the
    # main and fore masts (ray-probed clear from the Gameplay camera); 1.1 m off the gangplank centreline, 1.4 m off
    # Main. Red captain's coat and hat here (npcs.py has him in roof_blue): blue read as part of the blue-and-white
    # ticket booth and the green-and-gold hull behind him; red stands out on the sandstone quay.
    m.npc("Shanks", gx - 1.1, 5.0, rot=22, top="cloth_red", coat="cloth_red", hat_color="cloth_red")
    m.place("Lifebuoy", 63.4, 3.9, rot=0)
    m.place("Lifebuoy", 69.6, 3.8, rot=0)
    m.place("Rope_Coil", 66.9, 4.1)
    m.place("Crate_Stack", 69.0, 20.4, rot=10)
    m.place("Crate", 70.6, 21.6, rot=30)
    m.place("Sack", 67.6, 19.6)
    m.place("Barrel", 70.8, 19.4)
    m.place("Rope_Coil", 71.2, 23.0)
    m.place("Crate_Stack", 57.0, 18.2, rot=-12)
    m.place("Barrel", 55.4, 17.0)
    m.place("Barrel", 55.0, 18.2)
    m.place("Sack", 59.6, 18.0)
    m.place("Rope_Coil", 59.0, 20.6)
    m.place("Anchor", 63.8, 8.4, rot=-20)
    m.place("Bench", 60.2, 24.8, rot=0)
    m.place("Lamp_Post", 67.0, 22.4, rot=0)
    # harbour quarter: lower terrace
    m.place("Tree_Palm_A", 66.2, 27.6, rot=40)
    m.place("Bush_Flowering_A", 55.2, 27.6)
    m.place("X60000_BluePots", 61.8, 27.6, rot=10, scale=0.8)
    m.place("X60000_CafeTable", 80.8, 28.6, rot=0)
    m.place("Clothesline_Laundry", 72.8, 34.2, rot=0)
    m.place("Bush_B", 72.6, 27.6)
    m.place("Tree_Round_C", 81.0, 33.8, rot=20)
    m.place("Barrel", 65.6, 30.0)
    # harbour quarter: upper terrace
    m.place("Tree_Palm_A", 63.6, 44.6, rot=200)
    m.place("Bush_Flowering_A", 71.0, 39.6)
    m.place("X60000_BluePots", 81.0, 39.0, rot=-30, scale=0.8)
    m.place("Bench", 56.2, 39.4, rot=90)
    # garden terrace behind the knoll
    for (x, y, a, r) in ((46.6, 43.6, "Tree_Round_A", 0), (50.4, 42.4, "Tree_Palm_A", 130), (53.2, 45.4, "Tree_Round_C", 0)):
        m.place(a, x, y, rot=r)
    m.place("Bush_Flowering_A", 48.6, 41.0)
    m.place("Bush_B", 45.4, 40.6)
    m.place("Lamp_Post", 72.0, 12.0, rot=0)
    m.place("Lamp_Post", 80.4, 21.2, rot=180)
    m.place("Tree_Palm_A", 69.6, 11.2, rot=130)
    m.place("Tree_Palm_A", 74.5, 9.7, rot=200)
    for (x, y, a) in ((81.6, 12.6, "Bush_B"), (79.6, 17.0, "Bush_A"), (81.8, 21.6, "Bush_Flowering_A")):
        m.place(a, x, y)
    # vines down the big masonry faces
    vines(m, [(63.6 + i * 2.6, 3.35 - i * 0.05 - 0.25) for i in range(7)], Z_QUAY - 0.1, seed=1)
    vines(m, [(19.6 + i * 3.1, face_y(m, 19.6 + i * 3.1, 33.0) + 0.15) for i in range(6)], Z_BW - 0.1, seed=2,
          scale=1.25)
    vines(m, [(31.6 + i * 2.4, face_y(m, 31.6 + i * 2.4, 33.0) + 0.15) for i in range(3)], Z_BE - 0.1, seed=5,
          scale=1.25)
    vines(m, [(56.0 + i * 3.4, face_y(m, 56.0 + i * 3.4, 29.0) + 0.15) for i in range(8) if abs(56.0 + i * 3.4 - 64.4) > 2.4],
          Z_QL - 0.1, seed=6)
    vines(m, [(4.0 + i * 3.3, 2.1) for i in range(3)], Z_SQ - 0.1, seed=3)
    # the east edge (+x faces show at this yaw): vines and shuttered windows break the tall quarter/quay wall
    def east_x(y, x_in):
        fp = m.face_point(x_in, y, 1.0, 0.0)
        return fp[0] if fp else None
    for i, y in enumerate((8.0, 12.6, 16.4, 23.4, 28.6, 32.4, 39.0, 44.6)):
        ex = east_x(y, 80.0)
        if ex is not None:
            m.place("Vine_Hanging_A", ex + 0.12, y, z=m.ground_z(ex - 0.3, y) - 0.1, rot=(i * 41) % 360,
                    scale=1.1 + (i % 2) * 0.2, required=False)
    for (y, z) in ((30.8, Z_QL - 2.4), (41.0, Z_QH - 2.6), (18.0, Z_QUAY - 2.4)):
        ex = east_x(y, 80.0)
        if ex is not None:
            m.place("X60000_WallWindow", ex - 0.1, y, z=z, rot=90)

    # ------------------------------------------------------------------ NPCs and portals
    m.edge_portal("west00")
    m.door_portal("in00", sx - 1.0, sy - 3.25, rot=0)
    # NPCs: MeowDB's Southperry set (Yoona, Bari, Shanks, Biggs). Iteration One's v8 extras Tia, the Maple
    # Administrator and Paul are not Maple Island NPCs in MeowDB MS Classic, so they are not placed (Paul's roof
    # terrace stays as scenery).
    m.npc("Yoona", 11.6, 18.0, rot=10)
    m.npc("Bari", 28.9, 16.6, rot=-15)
    m.npc("Biggs", 29.9, 33.8, rot=-10)
    # the player on the quay just off the Main route, near the Gameplay focus, facing the camera
    m.player(65.0, 11.0, rot=22)
    m.player_spawn(10.4, 16.2, rot=10, note="sp x -37: on the west town ground beside Yoona")

    # ------------------------------------------------------------------ routes
    m.route("Main", [(4.5, 45.0), (4.6, 41.0), (5.2, 33.0), (6.8, 24.0), (10.0, 16.6), (13.4, 12.4), (16.0, 10.8),
                     (21.6, 10.8), (24.0, 10.4), (30.0, 9.6),
                     (36.4, 8.8), (41.0, 8.8), (46.0, 7.0), (50.6, 4.8), (56.6, 4.8), (56.6, 14.8), (62.0, 12.0),
                     (70.0, 8.0), (gx, 6.0), (gx, 4.1), (gx, deck_edge - 1.0), (gx + 1.2, shy + 1.5)])
    m.route("SquareFront", [(10.0, 16.6), (5.0, 13.6), (3.0, 12.6)])
    m.route("ArmorStore", [(25.4, 10.2), (25.5, 11.0), (25.5, 20.95)])  # ends 0.4 m short of in00, off the shop
    # the classic west climb: from the street (off Main past the west stair's foot) up a ledge rope to T30, then the
    # long ladder x405 up to Biggs's belvedere and along it to the market canopy
    m.route("LedgeRopes_Belvedere", [(23.0, 10.6), (22.4, 13.2), (19.4, 14.4), (19.0, 22.8), (19.0, 25.2),
                                     (19.0, 27.0), (18.9, 29.4), (18.9, 31.4), (18.9, 33.0), (22.0, 35.0),
                                     (26.0, 35.0), (28.4, 35.0), (31.6, 35.3), (33.0, 35.4)])
    # the east access: from the ramp head up the slab ladder x1649, the slab stair to T10 and back west to the canopy
    m.route("SlabLadder_Belvedere", [(41.0, 8.8), (41.0, 18.0), (41.0, 29.2), (41.0, 31.2), (41.6, 31.6),
                                     (42.8, 32.4), (42.8, 39.6), (40.6, 39.9), (38.2, 38.8), (36.6, 37.4),
                                     (35.2, 35.8), (33.6, 35.4)])
    m.route("Knoll", [(46.0, 7.0), (48.0, 12.0), (48.0, 19.0), (48.0, 22.4), (47.6, 26.0), (47.0, 30.4)])
    m.route("HarbourQuarter", [(62.0, 12.0), (64.6, 15.0), (64.4, 20.6), (64.4, 27.4), (63.6, 30.0), (63.2, 32.4),
                               (63.2, 37.4), (66.0, 38.0), (72.0, 37.9), (78.0, 37.8)])
    # (deck routes keep clear of the fighting top's footprint: the validator raycasts from above)
    m.route("ShipDecks", [(gx + 1.2, shy + 1.5), (shx + 0.4, shy + 2.1), (shx + SHIP_QD_X + 3.4, shy + 2.0),
                          (shx + SHIP_QD_X - 0.8, shy + 2.0), (shx - 9.6, shy + 0.4)])
    m.route("ShipForecastle", [(gx + 1.2, shy + 1.5), (shx + SHIP_FC_X - 2.6, shy + 1.6),
                               (shx + SHIP_FC_X + 0.9, shy + 1.6)])
    # from the starboard deck walk across under the mast rope and up onto the fighting top (the deck leg keeps
    # 1.4 m off the top's 1.2 m radius: the ground index reads anything under the top as its floor)
    m.route("ClimbMast", [(mast_x - 1.9, shy + 2.03), (mast_x - 1.9, shy - 1.2), (mast_x - 0.9, shy - 0.3),
                          (mast_x, shy + 0.8)])
