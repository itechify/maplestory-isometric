"""Classic Maple Island landmarks and house variants.

Derived from the WZ object notes in docs/research (wiki_maple_road.md, wiki_rainbow_street.md):
mushroom houses with spotted / streaked / plain caps, barrel chimneys with yellow lids,
stone-oven chimneys, mushroom-awning doors and iron wall lanterns; Amherst's two-storey
capped weapon store, long lime department store and giant tree-house; Rainbow Street's
barrel doors set into grassy mounds; Sera's clothesline; Southperry's lighthouse.
"""

import math

from .. import core
from ..geo import MeshBuilder
from . import asset
from .art_pack import part_materials
from .architecture import _shop_sign, door, window
from .nature import _puffy_canopy


def barrel_chimney(mb, loc, lid="M_Flat_roof_yellow"):
    x, y, z = loc
    mb.cyl(0.42, 1.1, loc=(x, y, z), mat="M_Wood", verts=12, r2=0.46)
    for zz in (0.25, 0.8):
        mb.cyl(0.47, 0.08, loc=(x, y, z + zz), mat="M_Wood_Dark", verts=12)
    mb.dome(0.55, 0.32, loc=(x, y, z + 1.1), mat=lid, u=12, v=3)


def stone_oven_chimney(mb, loc):
    x, y, z = loc
    mb.box((1.0, 1.0, 1.2), loc=(x, y, z + 0.6), mat="M_StoneWall", bevel=0.12)
    barrel_chimney(mb, (x, y, z + 1.1), lid="M_Flat_roof_red")


def mushroom_awning_door(mb, loc, cap_mat):
    """Round plank door under a little mushroom-cap awning."""
    x, y, z = loc
    door(mb, (x, y, z), w=1.25, h=2.0)
    mb.dome(0.95, 0.42, loc=(x, y - 0.5, z + 2.45), scale=(1.0, 0.7, 1.0), mat=cap_mat, u=14, v=3)
    for sx_ in (-1, 1):
        mb.sphere(0.32, loc=(x + sx_ * 1.05, y - 0.35, z + 0.25), scale=(1.2, 1.0, 0.8), mat="M_Bush", subdiv=2)
        mb.sphere(0.07, loc=(x + sx_ * 1.0, y - 0.62, z + 0.42), mat="M_Flat_flower_pink", subdiv=1)


def wall_lantern(mb, loc, face="-Y"):
    """Iron wall lantern on a wall facing `face` (-Y, +X, +Y or -X)."""
    from .architecture import _face_frame
    P, yaw = _face_frame(loc, face)
    mb.box((0.08, 0.3, 0.08), loc=P(0, -0.15, 0.35), rot=(0, 0, yaw), mat="M_Metal")
    mb.box((0.26, 0.26, 0.34), loc=P(0, -0.32, 0.15), rot=(0, 0, yaw), mat="M_Glow_window", bevel=0.03, segs=1)
    mb.cyl(0.2, 0.14, loc=P(0, -0.32, 0.32), mat="M_Eye_Black", verts=4, r2=0.03, rot=(0, 0, 45 + yaw))


# pack (#74): the pack houses have no emission, so the kit's lit windows (M_Window) and wall lantern (M_Glow_window)
# come back on purpose as their own parts; the roof (with its chimney) is <name>_Cap like the kit's. The cap is not
# tagged OVERHEAD_HULL, like the kit caps: it starts 3.6 m or more above the base, above any jump. The pack houses
# keep their own triangles (5 placed, one per town map) rather than collapsing their windows and doors.
# Size: the houses are fitted by their stem, not by their wider cap: the maps' door paths, door portals and porch
# arches line up with the kit stem's front (stem_r 2.0 x 1.06 = 2.12 m), and Sen's house fitted by its cap (1.25x)
# blocked route ToSensHouse in 20000. The pack caps come out a little smaller than the kit's.
def stem_width(stem_r=2.0, flare=1.06, long_body=1.0):
    """The width (m) a pack house's stem is fitted to (``fit_nodes``): the procedural mushroom stem's (stem_r) at
    ``flare`` times its radius (1.06: the stem front, where door paths and portals stand; 1.1: its widest band),
    across both sides, stretched by its ``long_body`` along X."""
    return 2 * stem_r * flare * long_body


HOUSE_PACK = dict(parts={"Cap": ["roof", "Roof", "chimney", "Chimney"], "Window": ["Recessed window"],
                         "Lamp": ["lamp glass"]},
                  post=part_materials({"Window": "M_Window", "Lamp": "M_Glow_window"}), max_tris=8000,
                  fit_nodes=(["Plaster stem house"], stem_width()))


def mushroom_house_v2(coll, name, cap_mat, stem_r=2.0, stem_h=4.1, cap_r=3.3, cap_h=2.5, chimney="barrel",
                      collar=True, lantern=True, barrels=False, long_body=1.0, profile=0.75, two_story=False):
    """Mushroom house: a stem (walls, door, windows, lantern) and a domed cap. Returns (stem, cap) objects."""
    mb = MeshBuilder()
    sx = long_body
    mb.cyl(stem_r * 1.04, stem_h * 0.55, mat="M_MushStem", verts=24, r2=stem_r * 1.1, scale=(sx, 1, 1))
    mb.cyl(stem_r * 1.1, stem_h * 0.47, loc=(0, 0, stem_h * 0.53), mat="M_MushStem", verts=24, r2=stem_r * 0.92,
           scale=(sx, 1, 1))
    mb.cyl(stem_r * 1.25, 0.35, loc=(0, 0, -0.05), mat="M_StoneWall", verts=24, r2=stem_r * 1.12, scale=(sx, 1, 1))
    if collar:
        mb.cyl(stem_r * 1.02, 0.35, loc=(0, 0, stem_h - 0.55), mat="M_Wood", verts=24, scale=(sx, 1, 1))
    front = -stem_r * 1.06
    mushroom_awning_door(mb, (-0.6 if sx > 1.2 else 0.0, front + 0.05, 0.25), cap_mat)
    for xx, zz in ((-1.25 * sx, 2.15), (1.3 * sx, 2.25)):
        mb.cyl(0.42, 0.25, loc=(xx, front + 0.25, zz), rot=(90, 0, 0), mat="M_Wood_Dark", verts=14)
        mb.cyl(0.31, 0.3, loc=(xx, front + 0.2, zz), rot=(90, 0, 0), mat="M_Window", verts=14)
    mb.cyl(0.36, 0.25, loc=(-stem_r * 0.96 * sx, 0.4, 2.0), rot=(0, -90, 0), mat="M_Wood_Dark", verts=14)
    mb.cyl(0.27, 0.3, loc=(-stem_r * 0.98 * sx, 0.4, 2.0), rot=(0, -90, 0), mat="M_Window", verts=14)
    if two_story:
        for xx in (-0.9 * sx, 0.9 * sx):
            mb.cyl(0.33, 0.25, loc=(xx, front + 0.3, stem_h - 1.1), rot=(90, 0, 0), mat="M_Wood_Dark", verts=12)
            mb.cyl(0.24, 0.3, loc=(xx, front + 0.25, stem_h - 1.1), rot=(90, 0, 0), mat="M_Window", verts=12)
    if lantern:
        wall_lantern(mb, (1.1, front + 0.1, 2.3))
    if barrels:
        for bx, by in ((stem_r * 0.9 * sx, front + 0.2), (stem_r * 0.9 * sx + 0.8, front + 0.6)):
            mb.cyl(0.36, 0.85, loc=(bx, by, 0.2), mat="M_Wood", verts=12, r2=0.4)
    stem = mb.build(name + "_Stem", coll, smooth=True, sharp_angle=40)
    cap = MeshBuilder()
    if profile == "cone":
        cap.cyl(cap_r, cap_h, loc=(0, 0, stem_h - 0.45), mat=cap_mat, verts=28, r2=0.18, scale=(sx, 1, 1))
        cap.cyl(cap_r * 1.02, 0.4, loc=(0, 0, stem_h - 0.75), mat=cap_mat, verts=28, r2=cap_r, scale=(sx, 1, 1))
        cap.sphere(0.32, loc=(0, 0, stem_h - 0.45 + cap_h), mat=cap_mat, subdiv=2)
    else:
        cap.dome(cap_r, cap_h, loc=(0, 0, stem_h - 0.15), scale=(sx, 1, 1), mat=cap_mat, u=32, v=8, lip=0.5,
                 profile=profile)
    if chimney == "barrel":
        barrel_chimney(cap, (cap_r * 0.45 * sx, cap_r * 0.3, stem_h + cap_h * 0.45))
    elif chimney == "oven":
        stone_oven_chimney(cap, (cap_r * 0.45 * sx, cap_r * 0.3, stem_h + cap_h * 0.35))
    return stem, cap.build(name + "_Cap", coll, smooth=True, sharp_angle=70)


@asset("House_Mushroom_OrangeSpotted", "Architecture", footprint=7.5, tags=("house", "mushroom"), pack=HOUSE_PACK)
def hm_orange_spotted(coll):
    """Orange cap with yellow spots, barrels and a wall lantern (West Entrance, map 0)."""
    mushroom_house_v2(coll, "House_Mushroom_OrangeSpotted", "M_Spot_mush_orange__flower_yellow", barrels=True)


@asset("House_Mushroom_YellowStreaked", "Architecture", footprint=7.5, tags=("house", "mushroom"), pack=HOUSE_PACK)
def hm_yellow_streaked(coll):
    """Yellow cap with dark streaks, wooden collar, barrel chimney with a yellow lid (Mushroom Town 10000)."""
    mushroom_house_v2(coll, "House_Mushroom_YellowStreaked", "M_Streak_mush_yellow__wood", chimney="barrel")


@asset("House_Mushroom_OrangeOven", "Architecture", footprint=8.0, tags=("house", "mushroom"), pack=HOUSE_PACK)
def hm_orange_oven(coll):
    """Plain orange cap, stone-oven chimney, two storeys (Mushroom Town 20000, Sen and Nina's house)."""
    mushroom_house_v2(coll, "House_Mushroom_OrangeOven", "M_Grad_mush_orange__roof_orange", chimney="oven",
                      cap_r=3.9, stem_h=3.6, two_story=True)


@asset("House_Mushroom_RedStriped", "Architecture", footprint=7.0, tags=("house", "mushroom"), pack=HOUSE_PACK)
def hm_red_striped(coll):
    """Red cap with white stripes and a chimney (Amherst)."""
    mushroom_house_v2(coll, "House_Mushroom_RedStriped", "M_Streak_mush_red__cloth_white", chimney="barrel",
                      cap_r=3.3, stem_h=3.0)


@asset("House_Mushroom_LimeLong", "Architecture", footprint=10.0, tags=("house", "mushroom", "shop"),
       pack=HOUSE_PACK)
def hm_lime_long(coll):
    """Long low lime-yellow capped mushroom house with a chimney (Amherst Department Store)."""
    mushroom_house_v2(coll, "House_Mushroom_LimeLong", "M_Spot_mush_green__flower_yellow", chimney="oven",
                      long_body=1.6, stem_h=4.0, cap_r=3.3, cap_h=2.0, profile=0.6)


@asset("House_Mushroom_BlueCone", "Architecture", footprint=7.0, tags=("house", "mushroom"), pack=HOUSE_PACK)
def hm_blue_cone(coll):
    """Blue pointed-cone cap (classic world map, Mushroom Town pocket)."""
    mushroom_house_v2(coll, "House_Mushroom_BlueCone", "M_Spot_mush_blue__cloth_white", cap_r=3.1, cap_h=4.6,
                      profile="cone", chimney=None)


# pack: the kit store is a wide box under a 9.8 m cap with its door at (-1.2, -2.4), where Amherst's in00 portal
# stands; the pack store is a round stem under a smaller cap with its door in the middle. Fitted by its cap it
# would be 12.6 m tall with its door 1.2 m off the portal, so its stem front stands on the kit wall (y -2.4) and it
# moves 1.2 m along -X onto the kit door.
KIT_STORE_WALL_Y = 2.4  # the kit store's front wall stands this far in front of its origin (y -2.4)


@asset("House_Wood_TwoStory_Capped", "Architecture", footprint=9.0, tags=("house", "shop"),
       pack=dict(HOUSE_PACK, fit_nodes=(["Plaster stem house"], 2 * KIT_STORE_WALL_Y), shift=(-1.2, 0.0, 0.0)))
def house_wood_two_story(coll):
    """Two-storey wooden house under a big yellow/orange mushroom cap (Amherst Weapon Store)."""
    mb = MeshBuilder()
    mb.box((6.4, 5.2, 0.6), loc=(0, 0, 0.3), mat="M_StoneWall", bevel=0.1)
    mb.box((6.0, 4.8, 5.6), loc=(0, 0, 3.4), mat="M_Plank", bevel=0.08)
    for zz in (0.6, 3.4, 6.1):
        mb.box((6.2, 5.0, 0.25), loc=(0, 0, zz), mat="M_Wood_Dark", bevel=0.04)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.3, 0.3, 5.8), loc=(sx * 3.0, sy * 2.4, 3.4), mat="M_Wood_Dark")
    door(mb, (-1.2, -2.4, 0.6), w=1.2, h=2.1)
    window(mb, (1.3, -2.4, 2.2), w=1.1, h=1.0, shutter_mat="M_Flat_roof_blue", flowerbox=True)
    window(mb, (-1.3, -2.4, 4.6), w=1.0, h=0.9, shutter_mat="M_Flat_roof_blue")
    window(mb, (1.3, -2.4, 4.6), w=1.0, h=0.9, shutter_mat="M_Flat_roof_blue")
    window(mb, (-3.0, 0.5, 4.2), face="-X", w=1.0, h=0.9, shutter_mat="M_Flat_roof_blue")
    _shop_sign(mb, "weapon", (0.3, -2.75, 2.9))
    mb.build("House_Wood_TwoStory_Capped", coll, smooth=True, sharp_angle=35)
    cap = MeshBuilder()
    cap.dome(4.9, 3.0, loc=(0, 0, 6.0), scale=(1.0, 0.92, 1.0), mat="M_Spot_roof_yellow__roof_orange", u=32, v=8,
             lip=0.5, profile=0.72)
    barrel_chimney(cap, (1.8, 1.2, 7.9))
    cap.build("House_Wood_TwoStory_Capped_Cap", coll, smooth=True, sharp_angle=70)


@asset("TreeHouse_Giant", "Architecture", footprint=12.0, tags=("house", "landmark", "tree"))
def tree_house_giant(coll):
    """Amherst landmark: a huge leafy tree with a house built into its trunk (door faces -Y)."""
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
    mb.build("TreeHouse_Giant_Trunk", coll, smooth=True, sharp_angle=50)
    can = MeshBuilder()
    _puffy_canopy(can, r, 7, (0, 0, 9.5), 5.8, lobes=9, mat="M_Leaf")
    can.build("TreeHouse_Giant_Canopy", coll, smooth=True, sharp_angle=80)


@asset("Barrel_Door_Mound", "Architecture", footprint=5.0, tags=("portal_door", "landmark"),
       pack=dict(max_tris=1212))
def barrel_door_mound(coll):
    """Rainbow Street side-map entrance: round plank barrel-door in a grass-capped mound (door faces -Y).

    Place the portal about 1.8 m in front (-Y) of the asset origin.
    """
    mb = MeshBuilder()
    mb.sphere(2.4, loc=(0, 0.8, 0.2), scale=(1.15, 1.0, 0.85), mat="M_Dirt_Cliff", subdiv=3, lumpy=0.08, seed=4,
              flatten_bottom=0.1)
    mb.cyl(1.05, 0.5, loc=(0, -1.0, 1.1), rot=(90, 0, 0), mat="M_Wood_Dark", verts=20)
    mb.cyl(0.92, 0.6, loc=(0, -1.05, 1.1), rot=(90, 0, 0), mat="M_Door", verts=20)
    for zz in (0.6, 1.1, 1.6):
        mb.box((1.9, 0.12, 0.1), loc=(0, -1.38, zz), mat="M_Metal")
    mb.sphere(0.08, loc=(0.55, -1.42, 1.0), mat="M_Gold", subdiv=1)
    mb.build("Barrel_Door_Mound_Body", coll, smooth=True, sharp_angle=50)
    top = MeshBuilder()
    top.sphere(2.5, loc=(0, 0.8, 0.45), scale=(1.12, 0.98, 0.78), mat="M_Grass", subdiv=3, lumpy=0.06, seed=5,
               flatten_bottom=-0.25)
    top.build("Barrel_Door_Mound_Grass", coll, smooth=True, sharp_angle=60)


@asset("Clothesline_Laundry", "Props", footprint=4.0, tags=("prop",))
def clothesline(coll):
    """Y-fork posts, a sagging line, shirts, trousers and a sheet lifted by the wind (Sera, West Entrance)."""
    mb = MeshBuilder()
    for x in (-2.1, 2.1):
        mb.cyl(0.08, 2.0, loc=(x, 0, 0), mat="M_Wood", verts=8, r2=0.07)
        for sd in (-1, 1):
            mb.cyl(0.05, 0.42, loc=(x, 0, 1.95), rot=(0, sd * 28, 0), mat="M_Wood", verts=6, r2=0.035)
    # sagging line (catenary-ish polyline of thin boxes)
    prev = None
    line = []
    for k in range(11):
        t = k / 10
        x = -2.05 + 4.1 * t
        z = 2.15 - 0.22 * math.sin(math.pi * t)
        line.append((x, z))
        if prev is not None:
            mx, mz = (x + prev[0]) / 2, (z + prev[1]) / 2
            ang = math.degrees(math.atan2(z - prev[1], x - prev[0]))
            mb.box((math.hypot(x - prev[0], z - prev[1]) + 0.01, 0.03, 0.03), loc=(mx, 0, mz), rot=(0, -ang, 0),
                   mat="M_Rope")
        prev = (x, z)

    def z_line(x):
        t = (x + 2.05) / 4.1
        return 2.15 - 0.22 * math.sin(math.pi * max(0.0, min(1.0, t)))

    # shirt (body + sleeves)
    for x0, c in ((-1.45, "M_Cloth_White"), (0.35, "M_Flat_roof_blue")):
        z = z_line(x0)
        mb.box((0.46, 0.04, 0.5), loc=(x0, 0, z - 0.29), mat=c, bevel=0.015)
        for sd in (-1, 1):
            mb.box((0.22, 0.04, 0.16), loc=(x0 + sd * 0.31, 0, z - 0.12), rot=(0, sd * -25, 0), mat=c, bevel=0.01)
    # trousers (two legs)
    x0 = -0.55
    z = z_line(x0)
    for sd in (-1, 1):
        mb.box((0.17, 0.04, 0.62), loc=(x0 + sd * 0.1, 0, z - 0.33), rot=(0, sd * 4, 0), mat="M_Flat_wood_dk",
               bevel=0.01)
    mb.box((0.38, 0.04, 0.1), loc=(x0, 0, z - 0.05), mat="M_Flat_wood_dk")
    # a long white/cream sheet lifted by the wind
    x0 = 1.35
    z = z_line(x0)
    mb.box((0.95, 0.03, 0.8), loc=(x0, -0.14, z - 0.36), rot=(18, 0, 0), mat="M_Cloth_White", bevel=0.01)
    for x in (-1.45, -0.55, 0.35, 1.0, 1.75):
        mb.box((0.04, 0.06, 0.08), loc=(x, 0, z_line(x) - 0.02), mat="M_Wood_Dark")
    mb.build("Clothesline_Laundry", coll, smooth=False)


@asset("Lighthouse_Southperry", "Architecture", footprint=7.0, tags=("landmark", "port"))
def lighthouse(coll):
    """Cream lighthouse with gold bands, blue dome and an orange-red cap (classic world map, Southperry)."""
    mb = MeshBuilder()
    mb.cyl(3.2, 1.2, mat="M_StoneWall", verts=20, r2=3.0)
    mb.cyl(2.6, 11.0, loc=(0, 0, 1.2), mat="M_Plaster", verts=20, r2=1.9)
    for zz in (3.5, 7.0, 10.4):
        mb.cyl(2.65 - zz * 0.065, 0.45, loc=(0, 0, zz), mat="M_Gold", verts=20)
    door(mb, (0, -2.55, 1.2), w=1.1, h=2.0)
    for zz in (4.8, 8.4):
        mb.box((0.7, 0.3, 1.0), loc=(0, -2.5 + zz * 0.06, zz), mat="M_Window")
    mb.cyl(2.4, 0.4, loc=(0, 0, 12.2), mat="M_Wood_Dark", verts=20)
    mb.cyl(1.5, 2.2, loc=(0, 0, 12.6), mat="M_Glow_window", verts=16)
    for k in range(8):
        a = 2 * math.pi * k / 8
        mb.box((0.14, 0.14, 2.2), loc=(math.cos(a) * 1.55, math.sin(a) * 1.55, 13.7), mat="M_Wood_Dark")
    mb.dome(1.9, 1.4, loc=(0, 0, 14.8), mat="M_Flat_roof_blue", u=20, v=5)
    mb.cyl(0.25, 1.0, loc=(0, 0, 16.1), mat="M_Flat_roof_red", verts=10, r2=0.05)
    mb.sphere(0.35, loc=(0, 0, 16.0), mat="M_Flat_roof_red", subdiv=2)
    mb.build("Lighthouse_Southperry", coll, smooth=True, sharp_angle=40)
