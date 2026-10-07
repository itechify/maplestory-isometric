"""Mushroom Town Townstreet (20001) - "Sen's two-storey mushroom house, cut open".

Classic (GMS v8) structure, from docs/research/maps/20001_MushroomTownTownstreet_20001.md:
  despite the name this is the inside of the orange mushroom house of 20000 (Sen and Nina's).
  Ground floor: an entry nook behind a low lintel with the round-topped orange plank exit door on
  the west wall and a little wall shelf; the main room with a cupboard of jars and books against
  the back wall, a hanging bell lamp and Sen ("I'm... so ... hungry!") between the cupboard and
  the ladder. A ladder in the east part climbs through a hatch to the upper floor: an orange bed
  with white pillows (west), a curtained window (back wall, centre), a treasure chest beside the
  ladder top and another bell lamp, all under the orange cap. Cream walls, honey timber posts.

3D translation: a dollhouse cut-away on the interior stage. The loft is a mezzanine over the
back-left of the ground floor (framed by honey posts, a railing and a top beam) so the ground
floor stays visible from the camera; the ladder stands against the loft's front beam with a
gap in the railing as the hatch. The back and left walls rise into arched gables that follow
the orange cap, whose cut edge (cream flesh, orange skin) arches over the room - the "orange
cap cross-section" of the 2D sprite (a slight swell of the skin rounds off the back-left corner where the
two cuts meet). A small stone oven echoes the house's stone-oven chimney. Cool accents keep the props from
melting into the honey room: a dark wood wainscot, blue/teal textiles (the bed quilt, braided rugs, a teal
armchair in a front-left reading corner) and blue jars; the entry nook gets a shoe bench and a coat stand.
"""

import math

from misostory import collision_tags as CT
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.interior import ROOM, RUG_Z, WALL_T, cut_room, lbox, plank_floor, point_light, room_light, solid

MAP_ID = 20001
GAMEPLAY_FOCUS = (6.6, 6.6)     # frames both storeys (loft bed + curtained window and the ground floor)
GAMEPLAY_SCALE = 25.0

WALL_H = 6.6
LOFT_Z = 3.2
LOFT = (0.3, 6.6, 10.2, 11.45)          # walkable loft footprint (x0, y0, x1, y1)
LADDER = (9.0, 6.33)
CAP = dict(cx=8.0, cy=6.0, rx=10.4, ry=8.2, base=WALL_H, h=4.2, th=0.55)
HONEY = "M_Flat_wood_lt"
CAP_SKIN = "M_Grad_mush_orange__roof_orange"
CAP_FLESH = "M_Flat_mush_stem"
CORNER_RIDGE = (0.27, 0.9)     # height, radius (m) of the skin swell that rounds off the back-left corner of the cut


def cap_z(x, y):
    """Outer height of the mushroom cap dome above local (x, y) (base height outside the rim)."""
    u2 = ((x - CAP["cx"]) / CAP["rx"]) ** 2 + ((y - CAP["cy"]) / CAP["ry"]) ** 2
    return CAP["base"] + CAP["h"] * math.sqrt(max(0.0, 1.0 - u2))


# ---------------------------------------------------------------------------
# local assets
# ---------------------------------------------------------------------------

@asset("X20001_Cupboard", "Props", footprint=1.9, tags=("interior",))
def _cupboard(coll):
    """Wooden cupboard / bookshelf with jars and books (faces -Y), 1.8 x 0.55 x 2.2."""
    mb = MeshBuilder()
    W, D, H = 1.8, 0.55, 2.2
    mb.box((W, 0.08, H), loc=(0, D / 2 - 0.04, H / 2), mat="M_Wood_Dark")
    for s in (-1, 1):
        mb.box((0.1, D, H), loc=(s * (W / 2 - 0.05), 0, H / 2), mat="M_Wood", bevel=0.02, segs=1)
    for z in (0.05, 0.75, 1.4, 2.15):
        mb.box((W, D + 0.04, 0.08), loc=(0, 0, z), mat="M_Wood", bevel=0.02, segs=1)
    mb.box((W + 0.16, D + 0.12, 0.12), loc=(0, 0, H + 0.06), mat="M_Wood_Dark", bevel=0.03, segs=1)
    cols = ("M_Flat_roof_red", "M_Flat_roof_blue", "M_Flat_roof_green", "M_Flat_roof_yellow", "M_Flat_roof_purple")
    for k in range(9):  # books on the middle shelf
        h = 0.42 + (k % 3) * 0.06
        mb.box((0.11, 0.34, h), loc=(-0.75 + k * 0.13, 0.0, 0.79 + h / 2), rot=(0, 6 if k == 8 else 0, 0),
               mat=cols[k % 5])
    for k in range(4):  # cool blue / teal / white jars on the top shelf (they read against the honey room)
        x = -0.6 + k * 0.4
        body = ("M_Flat_roof_blue", "M_Flat_cloth_white", "M_Glow_roof_teal", "M_Flat_roof_teal")[k]
        mb.cyl(0.13, 0.32, loc=(x, -0.02, 1.44), mat=body, verts=12)
        mb.cyl(0.15, 0.06, loc=(x, -0.02, 1.76), mat=("M_Flat_sea_dk", "M_Flat_roof_blue")[k % 2], verts=12)
    for k in range(2):  # lower doors
        mb.box((0.78, 0.05, 0.6), loc=(-0.42 + k * 0.84, -D / 2 - 0.01, 0.4), mat="M_Plank", bevel=0.02, segs=1)
        mb.sphere(0.04, loc=(-0.1 + k * 0.2, -D / 2 - 0.05, 0.42), mat="M_Gold", subdiv=1)
    mb.build("X20001_Cupboard", coll, smooth=False)


@asset("X20001_BellLamp", "Props", footprint=0.6, tags=("interior", "light"))
def _bell_lamp(coll):
    """Hanging bell lamp: chain, orange bell shade, glowing bulb. Origin at the top of the chain."""
    mb = MeshBuilder()
    for k in range(5):
        mb.torus(0.04, 0.012, loc=(0, 0, -0.06 - k * 0.09), rot=(90 if k % 2 else 0, 0, 0), mat="M_Metal", u=8, v=4)
    mb.dome(0.32, 0.36, loc=(0, 0, -0.95), mat="M_Flat_roof_orange", u=16, v=4, profile=1.3, lip=0.05)
    mb.cyl(0.05, 0.1, loc=(0, 0, -0.55), mat="M_Gold", verts=8)
    mb.sphere(0.16, loc=(0, 0, -0.98), mat="M_Glow_window", subdiv=2)
    mb.build("X20001_BellLamp", coll, smooth=True, sharp_angle=50)


@asset("X20001_CurtainWindow", "Architecture", footprint=1.6, tags=("interior",))
def _curtain_window(coll):
    """Round-topped window with orange curtains and a little sill (flat on a wall, faces -Y). Origin = centre."""
    mb = MeshBuilder()
    w, h = 1.2, 1.1
    mb.box((w + 0.25, 0.12, h + 0.2), loc=(0, 0.02, 0), mat=HONEY, bevel=0.04, segs=1)
    mb.cyl((w + 0.25) / 2, 0.12, loc=(0, 0.08, h / 2 + 0.1), rot=(90, 0, 0), mat=HONEY, verts=16)
    mb.box((w, 0.08, h), loc=(0, -0.02, 0), mat="M_Glow_sky_horizon")
    mb.cyl(w / 2, 0.08, loc=(0, 0.02, h / 2), rot=(90, 0, 0), mat="M_Glow_sky_horizon", verts=16)
    mb.box((0.06, 0.12, h + 0.5), loc=(0, -0.05, 0.12), mat=HONEY)
    mb.box((w, 0.12, 0.06), loc=(0, -0.05, 0.0), mat=HONEY)
    for s in (-1, 1):  # curtains, gathered
        mb.box((0.36, 0.08, h + 0.35), loc=(s * (w / 2 - 0.08), -0.1, 0.08), mat="M_Flat_roof_orange", bevel=0.05,
               segs=1)
        mb.box((0.4, 0.1, 0.08), loc=(s * (w / 2 - 0.08), -0.12, -0.15), mat="M_Flat_flower_yellow")
    mb.box((w + 0.5, 0.3, 0.08), loc=(0, -0.12, h / 2 + 0.55), mat=HONEY)  # curtain rod board
    mb.box((w + 0.4, 0.3, 0.1), loc=(0, -0.12, -h / 2 - 0.12), mat=HONEY, bevel=0.03, segs=1)  # sill
    mb.sphere(0.12, loc=(-0.3, -0.18, -h / 2 + 0.0), mat="M_Flat_flower_pink", subdiv=1)
    mb.cyl(0.08, 0.12, loc=(-0.3, -0.18, -h / 2 - 0.1), mat="M_Flat_roof_red", verts=8)
    mb.build("X20001_CurtainWindow", coll, smooth=True, sharp_angle=40)


@asset("X20001_RoundWindow", "Architecture", footprint=1.1, tags=("interior",))
def _round_window(coll):
    """Round mushroom-house window (flat on a wall, faces -Y). Origin = centre."""
    mb = MeshBuilder()
    mb.cyl(0.55, 0.14, loc=(0, 0.06, 0), rot=(90, 0, 0), mat=HONEY, verts=20)
    mb.cyl(0.44, 0.1, loc=(0, 0.0, 0), rot=(90, 0, 0), mat="M_Glow_sky_horizon", verts=20)
    mb.box((0.06, 0.08, 0.9), loc=(0, -0.08, 0), mat=HONEY)
    mb.box((0.9, 0.08, 0.06), loc=(0, -0.08, 0), mat=HONEY)
    mb.build("X20001_RoundWindow", coll, smooth=True, sharp_angle=40)


@asset("X20001_Door", "Architecture", footprint=1.8, tags=("interior", "door"))
def _house_door(coll):
    """Round-topped orange plank door with iron hinges in a stone arch (closed, flat on a wall, faces -Y)."""
    mb = MeshBuilder()
    w, h = 1.25, 1.85
    for k in range(9):  # stone arch voussoirs
        a = math.radians(180 * k / 8)
        mb.box((0.34, 0.2, 0.3), loc=(math.cos(a) * (w / 2 + 0.2), 0.03, h + math.sin(a) * (w / 2 + 0.2)),
               rot=(0, -math.degrees(a) + 90, 0), mat="M_Flat_stone_wall", bevel=0.04, segs=1)
    for s in (-1, 1):
        for k in range(4):
            mb.box((0.34, 0.2, 0.42), loc=(s * (w / 2 + 0.2), 0.03, 0.22 + k * 0.45), mat="M_Flat_stone_wall",
                   bevel=0.04, segs=1)
    mb.box((w, 0.14, h), loc=(0, -0.02, h / 2), mat="M_Flat_roof_orange", bevel=0.03, segs=1)
    mb.cyl(w / 2, 0.14, loc=(0, 0.05, h), rot=(90, 0, 0), mat="M_Flat_roof_orange", verts=16)
    for k in range(4):
        mb.box((0.03, 0.16, h + w / 2 - abs(k - 1.5) * 0.12), loc=(-0.47 + k * 0.31, -0.03, (h + w / 2) / 2 - 0.1),
               mat="M_Flat_wood_dk")
    for z in (0.4, 1.5):
        mb.box((0.75, 0.18, 0.09), loc=(-0.2, -0.05, z), mat="M_Flat_rock_dk")
        mb.sphere(0.05, loc=(-0.55, -0.12, z), mat="M_Flat_rock_dk", subdiv=1)
    mb.torus(0.09, 0.025, loc=(0.42, -0.13, 1.0), rot=(90, 0, 0), mat="M_Metal", u=10, v=4)
    mb.box((w + 1.0, 0.7, 0.12), loc=(0, -0.3, 0.06), mat="M_Flat_stone_wall", bevel=0.04, segs=1)
    mb.build("X20001_Door", coll, smooth=True, sharp_angle=40)


@asset("X20001_WallShelf", "Architecture", footprint=1.2, tags=("interior",))
def _wall_shelf(coll):
    """Small honey-wood wall shelf with jars and a plant (faces -Y). Origin at the board."""
    mb = MeshBuilder()
    mb.box((1.2, 0.36, 0.07), loc=(0, -0.12, 0), mat=HONEY, bevel=0.02, segs=1)
    for s in (-1, 1):
        mb.box((0.06, 0.3, 0.26), loc=(s * 0.48, -0.1, -0.15), rot=(-30, 0, 0), mat=HONEY)
    mb.cyl(0.1, 0.24, loc=(-0.35, -0.12, 0.035), mat="M_Flat_roof_blue", verts=10)
    mb.cyl(0.11, 0.05, loc=(-0.35, -0.12, 0.27), mat="M_Flat_cloth_white", verts=10)
    mb.cyl(0.08, 0.18, loc=(0.0, -0.12, 0.035), mat="M_Glow_roof_teal", verts=10)
    mb.cyl(0.1, 0.12, loc=(0.35, -0.12, 0.035), mat="M_Flat_dirt_lt", verts=10)
    mb.sphere(0.16, loc=(0.35, -0.12, 0.25), mat="M_Bush", subdiv=1, lumpy=0.2, seed=2)
    mb.build("X20001_WallShelf", coll, smooth=True, sharp_angle=40)


@asset("X20001_Stove", "Props", footprint=1.6, tags=("interior",))
def _stove(coll):
    """Little stone oven with a glowing fire, a soup pot and a pipe up into the cap (faces -Y)."""
    mb = MeshBuilder()
    mb.box((1.5, 0.95, 1.0), loc=(0, 0, 0.5), mat="M_StoneWall", bevel=0.1, segs=2)
    mb.box((1.6, 1.05, 0.12), loc=(0, 0, 1.04), mat="M_Flat_rock_dk", bevel=0.03, segs=1)
    mb.box((0.7, 0.1, 0.5), loc=(0, -0.47, 0.42), mat="M_Flat_rock_dk")
    mb.cyl(0.35, 0.1, loc=(0, -0.47, 0.67), rot=(90, 0, 0), mat="M_Flat_rock_dk", verts=12)
    mb.box((0.56, 0.08, 0.38), loc=(0, -0.52, 0.4), mat="M_Glow_roof_orange")
    mb.sphere(0.13, loc=(-0.1, -0.5, 0.3), mat="M_Glow_flower_yellow", subdiv=1)
    mb.sphere(0.1, loc=(0.12, -0.52, 0.28), mat="M_Glow_flower_yellow", subdiv=1)
    mb.cyl(0.32, 0.36, loc=(-0.3, -0.05, 1.1), mat="M_Flat_rock_dk", verts=14, r2=0.36)
    mb.cyl(0.3, 0.03, loc=(-0.3, -0.05, 1.44), mat="M_Flat_roof_orange", verts=14)
    mb.box((0.05, 0.05, 0.5), loc=(-0.2, -0.05, 1.6), rot=(0, 20, 0), mat="M_Wood")
    mb.cyl(0.2, 5.3, loc=(0.45, 0.2, 1.1), mat="M_Metal", verts=10)
    for z in (2.2, 3.6):
        mb.cyl(0.24, 0.1, loc=(0.45, 0.2, z), mat="M_Flat_rock_dk", verts=10)
    mb.build("X20001_Stove", coll, smooth=True, sharp_angle=40)


@asset("X20001_DiningSet", "Props", footprint=2.2, tags=("interior",))
def _dining_set(coll):
    """Small round table with an empty plate, a cup and two mushroom stools (poor hungry Sen)."""
    mb = MeshBuilder()
    mb.cyl(0.62, 0.08, loc=(0, 0, 0.72), mat="M_Plank", verts=16)
    mb.cyl(0.07, 0.72, mat="M_Wood_Dark", verts=8)
    mb.cyl(0.3, 0.05, mat="M_Wood_Dark", verts=10)
    mb.cyl(0.6, 0.012, loc=(0, 0, 0.8), mat="M_Flat_cloth_red", verts=16)
    mb.cyl(0.2, 0.03, loc=(0.1, -0.15, 0.81), mat="M_Flat_cloth_white", verts=14)
    mb.cyl(0.07, 0.12, loc=(-0.25, 0.15, 0.81), mat="M_Flat_roof_blue", verts=10)
    mb.box((0.03, 0.22, 0.02), loc=(0.36, -0.1, 0.82), mat="M_Metal")
    for (x, y) in ((-0.95, 0.15), (0.9, 0.25)):
        mb.cyl(0.13, 0.36, loc=(x, y, 0.0), mat="M_MushStem", verts=10)
        mb.dome(0.3, 0.18, loc=(x, y, 0.34), mat="M_Spot_mush_red__mush_spot", u=14, v=3)
    mb.build("X20001_DiningSet", coll, smooth=True, sharp_angle=40)


@asset("X20001_Nightstand", "Props", footprint=0.7, tags=("interior",))
def _nightstand(coll):
    """Bedside table with a candle and a little plush mushroom."""
    mb = MeshBuilder()
    mb.box((0.6, 0.5, 0.6), loc=(0, 0, 0.3), mat=HONEY, bevel=0.03, segs=1)
    mb.box((0.5, 0.04, 0.2), loc=(0, -0.26, 0.42), mat="M_Wood")
    mb.cyl(0.08, 0.04, loc=(-0.12, 0, 0.6), mat="M_Gold", verts=10)
    mb.cyl(0.04, 0.16, loc=(-0.12, 0, 0.64), mat="M_Flat_cloth_white", verts=8)
    mb.sphere(0.04, loc=(-0.12, 0, 0.84), scale=(1, 1, 1.6), mat="M_Glow_flower_yellow", subdiv=1)
    mb.cyl(0.07, 0.12, loc=(0.13, 0.02, 0.6), mat="M_Flat_mush_stem", verts=8)
    mb.dome(0.13, 0.1, loc=(0.13, 0.02, 0.71), mat="M_Spot_mush_orange__mush_spot", u=12, v=3)
    mb.build("X20001_Nightstand", coll, smooth=True, sharp_angle=40)


def _braided(name, coll, rings):
    """Oval braided rag rug (rings outermost first)."""
    mb = MeshBuilder()
    for k, (r, mat) in enumerate(rings):
        mb.cyl(r, 0.03 + k * 0.004, mat=mat, verts=28, scale=(1.0, 0.75, 1.0))
    mb.build(name, coll, smooth=False)


@asset("X20001_RugBraided", "Props", footprint=3.0, tags=("interior",))
def _rug_braided(coll):
    """Oval braided rag rug in orange, cream and brown rings."""
    _braided("X20001_RugBraided", coll, ((1.5, "M_Flat_wood_dk"), (1.3, "M_Flat_roof_orange"),
                                         (1.05, "M_Flat_mush_stem"), (0.82, "M_Flat_flower_yellow"),
                                         (0.6, "M_Flat_roof_orange"), (0.35, "M_Flat_mush_stem")))


@asset("X20001_RugBlue", "Props", footprint=3.0, tags=("interior",))
def _rug_blue(coll):
    """Oval braided rag rug in denim blue, teal and cream rings (a cool accent on the honey floor)."""
    _braided("X20001_RugBlue", coll, ((1.5, "M_Flat_sea_dk"), (1.3, "M_Flat_roof_blue"), (1.05, "M_Flat_cloth_white"),
                                      (0.82, "M_Flat_roof_teal"), (0.6, "M_Flat_roof_blue"),
                                      (0.35, "M_Flat_cloth_white")))


@asset("X20001_RugGreen", "Props", footprint=3.0, tags=("interior",))
def _rug_green(coll):
    """Oval braided rag rug in leaf green, teal and cream rings."""
    _braided("X20001_RugGreen", coll, ((1.5, "M_Flat_leaf_b_dk"), (1.3, "M_Flat_leaf_b"), (1.05, "M_Flat_cloth_white"),
                                       (0.82, "M_Flat_roof_teal"), (0.6, "M_Flat_leaf_b"),
                                       (0.35, "M_Flat_flower_yellow")))


@asset("X20001_Bed", "Props", footprint=2.6, tags=("interior",))
def _bed_blue(coll):
    """Sen's orange wooden bed (as in the 2D sprite) made up with a cool blue-and-teal patchwork quilt so it
    stands out from the honey floor; 2.5 x 1.4 m, length along +X, headboard at -X (the kit Bed's shape)."""
    mb = MeshBuilder()
    L, W = 2.5, 1.4
    frame = "M_Flat_roof_orange"
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.14, 0.14, 0.45), loc=(sx * (L / 2 - 0.07), sy * (W / 2 - 0.07), 0.22), mat=frame)
    mb.box((L, W, 0.22), loc=(0, 0, 0.42), mat=frame, bevel=0.04, segs=1)
    mb.box((0.16, W + 0.08, 1.15), loc=(-L / 2, 0, 0.58), mat=frame, bevel=0.05, segs=1)
    mb.cyl((W + 0.08) / 2, 0.16, loc=(-L / 2 - 0.08, 0, 1.15), rot=(0, 90, 0), mat=frame, verts=16, scale=(0.55, 1, 1))
    mb.box((0.14, W + 0.06, 0.75), loc=(L / 2, 0, 0.42), mat=frame, bevel=0.05, segs=1)
    mb.box((L - 0.2, W - 0.1, 0.22), loc=(0.02, 0, 0.62), mat="M_Cloth_White", bevel=0.08, segs=2)
    # quilt: a blue cover draped over both sides, with teal / white / navy patches
    mb.box((1.6, W + 0.06, 0.08), loc=(0.4, 0, 0.74), mat="M_Flat_roof_blue", bevel=0.03, segs=1)
    for s in (-1, 1):
        mb.box((1.6, 0.05, 0.3), loc=(0.4, s * (W / 2 + 0.01), 0.6), mat="M_Flat_roof_blue", bevel=0.015, segs=1)
    for k, x in enumerate((-0.1, 0.4, 0.9)):
        for j, y in enumerate((-0.38, 0.0, 0.38)):
            mat = ("M_Flat_roof_teal", "M_Flat_cloth_white", "M_Flat_sea_dk")[(k + j) % 3]
            mb.box((0.44, 0.32, 0.03), loc=(x, y, 0.785), mat=mat, bevel=0.01, segs=1)
    mb.box((0.25, W - 0.06, 0.08), loc=(-0.5, 0, 0.77), mat="M_Cloth_White", bevel=0.03, segs=1)   # sheet fold
    for y in (-0.33, 0.33):
        mb.sphere(0.3, loc=(-0.85, y, 0.82), scale=(0.75, 1.0, 0.45), mat="M_Cloth_White", subdiv=2)
    mb.build("X20001_Bed", coll, smooth=True, sharp_angle=40)


@asset("X20001_CoatRack", "Props", footprint=0.8, tags=("interior",))
def _coat_rack(coll):
    """Honey-wood coat stand for the entry nook: a green hooded cloak, a striped blue scarf and a straw hat."""
    mb = MeshBuilder()
    for k in range(3):  # three splayed feet
        a = math.radians(30 + k * 120)
        mb.box((0.42, 0.08, 0.07), loc=(math.cos(a) * 0.18, math.sin(a) * 0.18, 0.04), rot=(0, 0, math.degrees(a)),
               mat=HONEY, bevel=0.02, segs=1)
    mb.cyl(0.05, 1.78, mat=HONEY, verts=10)
    mb.sphere(0.075, loc=(0, 0, 1.8), mat=HONEY, subdiv=1)
    for k in range(4):  # pegs
        a = math.radians(45 + k * 90)
        mb.cyl(0.025, 0.2, loc=(math.cos(a) * 0.03, math.sin(a) * 0.03, 1.55),
               rot=(0, 60, math.degrees(a)), mat="M_Wood_Dark", verts=6)
    # green hooded cloak on the camera side
    mb.box((0.44, 0.14, 0.78), loc=(0.0, -0.13, 1.1), mat="M_Flat_leaf_b", bevel=0.06, segs=1)
    mb.sphere(0.17, loc=(0.0, -0.12, 1.52), scale=(1.1, 0.8, 0.9), mat="M_Flat_leaf_b", subdiv=2)
    mb.box((0.46, 0.15, 0.06), loc=(0.0, -0.14, 0.74), mat="M_Flat_leaf_b_dk")
    # blue scarf with white stripes over the +X peg
    for (y, h) in ((-0.03, 0.7), (0.08, 0.55)):
        mb.box((0.11, 0.08, h), loc=(0.17, y, 1.55 - h / 2), mat="M_Flat_roof_blue")
        for z in (1.55 - h + 0.12, 1.55 - h + 0.26):
            mb.box((0.115, 0.085, 0.04), loc=(0.17, y, z), mat="M_Flat_cloth_white")
    # straw hat with a red band on top
    mb.cyl(0.27, 0.03, loc=(0, 0, 1.86), mat="M_Flat_sand_a", verts=16)
    mb.cyl(0.14, 0.15, loc=(0, 0, 1.88), mat="M_Flat_sand_a", verts=12, r2=0.12)
    mb.cyl(0.145, 0.04, loc=(0, 0, 1.9), mat="M_Flat_roof_red", verts=12)
    mb.build("X20001_CoatRack", coll, smooth=True, sharp_angle=40)


@asset("X20001_ShoeBench", "Props", footprint=1.2, tags=("interior",))
def _shoe_bench(coll):
    """Low honey-wood entry bench (faces -Y, 1.1 m long): blue seat cushion, two pairs of boots on the shelf."""
    mb = MeshBuilder()
    W, D = 1.1, 0.42
    mb.box((W, D, 0.06), loc=(0, 0, 0.42), mat=HONEY, bevel=0.02, segs=1)
    for sx in (-1, 1):
        mb.box((0.06, D, 0.42), loc=(sx * (W / 2 - 0.04), 0, 0.21), mat=HONEY)
    mb.box((W - 0.1, D - 0.04, 0.04), loc=(0, 0, 0.1), mat=HONEY)
    mb.box((W - 0.16, D - 0.08, 0.08), loc=(0, 0, 0.49), mat="M_Flat_roof_blue", bevel=0.035, segs=1)
    for (x0, mat) in ((-0.28, "M_Flat_wood_dk"), (0.2, "M_Flat_leaf_b_dk")):
        for dx in (0.0, 0.13):
            mb.box((0.1, 0.24, 0.09), loc=(x0 + dx, -0.04, 0.165), mat=mat, bevel=0.03, segs=1)
            mb.box((0.1, 0.11, 0.17), loc=(x0 + dx, 0.03, 0.29), mat=mat, bevel=0.03, segs=1)
    mb.build("X20001_ShoeBench", coll, smooth=True, sharp_angle=40)


@asset("X20001_Armchair", "Props", footprint=1.1, tags=("interior",))
def _armchair(coll):
    """Chunky stuffed armchair in teal-blue upholstery on honey legs, with a cream cushion and a knitted
    throw (faces -Y)."""
    mb = MeshBuilder()
    up = "M_Flat_roof_teal"
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.cyl(0.05, 0.14, loc=(sx * 0.36, sy * 0.3, 0.0), mat=HONEY, verts=8)
    mb.box((0.9, 0.8, 0.3), loc=(0, 0, 0.28), mat=up, bevel=0.08, segs=2)            # base
    mb.box((0.62, 0.62, 0.14), loc=(0, -0.05, 0.48), mat="M_Flat_cloth_white", bevel=0.06, segs=2)   # seat
    mb.box((0.9, 0.22, 0.75), loc=(0, 0.3, 0.68), mat=up, bevel=0.09, segs=2)        # back
    for sx in (-1, 1):                                                                  # rolled arms
        mb.box((0.18, 0.78, 0.26), loc=(sx * 0.38, 0, 0.5), mat=up, bevel=0.07, segs=2)
        mb.cyl(0.11, 0.78, loc=(sx * 0.38, -0.39, 0.62), rot=(-90, 0, 0), mat=up, verts=12)
    mb.box((0.5, 0.06, 0.55), loc=(0.08, 0.17, 0.78), rot=(-12, 0, 8), mat="M_Flat_flower_yellow", bevel=0.03, segs=1)
    mb.build("X20001_Armchair", coll, smooth=True, sharp_angle=40)


@asset("X20001_Firewood", "Props", footprint=1.0, tags=("interior",))
def _firewood(coll):
    """Stack of split firewood logs (along X) on two sleepers, for the stove."""
    mb = MeshBuilder()
    for s in (-1, 1):
        mb.box((0.08, 0.66, 0.08), loc=(s * 0.3, 0, 0.04), mat="M_Wood_Dark")
    r = 0.1
    for n, z in ((3, 0.08 + r), (2, 0.08 + r * 2.75), (1, 0.08 + r * 4.5)):
        for i in range(n):
            y = (i - (n - 1) / 2) * (2 * r + 0.015)
            mb.cyl(r, 0.84 - n * 0.02, loc=(-0.42 + n * 0.01, y, z), rot=(0, 90, 0), mat="M_Bark", verts=8)
            mb.cyl(r * 0.78, 0.02, loc=(0.41 - n * 0.01, y, z), rot=(0, 90, 0), mat="M_Flat_wood_lt", verts=8)
    mb.box((0.05, 0.42, 0.05), loc=(0.05, 0.0, 0.08 + r * 5.6), rot=(0, 0, 25), mat="M_Wood")
    mb.box((0.16, 0.05, 0.13), loc=(0.14, -0.19, 0.08 + r * 5.6), rot=(0, 0, 25), mat="M_Metal")
    mb.build("X20001_Firewood", coll, smooth=True, sharp_angle=40)


@asset("X20001_WashTub", "Props", footprint=1.1, tags=("interior",))
def _wash_tub(coll):
    """Wooden wash tub with soap suds, a washboard leaning in it and a towel over the rim."""
    mb = MeshBuilder()
    mb.cyl(0.42, 0.45, mat="M_Wood", verts=16, r2=0.5)
    for z in (0.06, 0.34):
        mb.cyl(0.445 + z * 0.18, 0.05, loc=(0, 0, z), mat="M_Metal", verts=16)
    mb.cyl(0.47, 0.03, loc=(0, 0, 0.39), mat="M_Water", verts=16)
    for k in range(7):
        a = k * 0.9
        rr = 0.12 + (k % 3) * 0.1
        mb.sphere(0.07 + (k % 2) * 0.03, loc=(math.cos(a) * rr, math.sin(a) * rr, 0.43), mat="M_Flat_cloth_white",
                  subdiv=1)
    mb.box((0.38, 0.04, 0.62), loc=(0.05, 0.22, 0.6), rot=(-18, 0, 0), mat="M_Wood", bevel=0.02, segs=1)
    for k in range(5):
        mb.box((0.3, 0.05, 0.03), loc=(0.05, 0.2 - (k - 2) * 0.03 * 0.31, 0.5 + (k - 2) * 0.09), rot=(-18, 0, 0),
               mat="M_Metal")
    mb.box((0.14, 0.34, 0.03), loc=(-0.5, -0.05, 0.47), mat="M_Flat_flower_pink", bevel=0.01, segs=1)
    mb.box((0.03, 0.34, 0.22), loc=(-0.57, -0.05, 0.37), mat="M_Flat_flower_pink")
    mb.build("X20001_WashTub", coll, smooth=True, sharp_angle=40)


@asset("X20001_MushroomCrate", "Props", footprint=0.9, tags=("interior",))
def _mushroom_crate(coll):
    """Open pantry crate heaped with orange and red mushrooms (and poor Sen is SO hungry)."""
    mb = MeshBuilder()
    mb.box((0.8, 0.6, 0.06), loc=(0, 0, 0.03), mat="M_Wood_Dark")
    for s in (-1, 1):
        mb.box((0.8, 0.06, 0.38), loc=(0, s * 0.27, 0.19), mat="M_Plank", bevel=0.02, segs=1)
        mb.box((0.06, 0.6, 0.38), loc=(s * 0.37, 0, 0.19), mat="M_Plank", bevel=0.02, segs=1)
    mb.box((0.84, 0.03, 0.07), loc=(0, -0.3, 0.27), mat="M_Flat_roof_orange")
    orange, red = "M_Spot_mush_orange__mush_spot", "M_Spot_mush_red__mush_spot"
    for (x, y, z, mat) in ((-0.22, -0.1, 0.36, orange), (0.04, -0.13, 0.38, red), (0.24, -0.06, 0.36, orange),
                           (-0.15, 0.12, 0.38, red), (0.13, 0.12, 0.4, orange), (-0.02, 0.0, 0.5, orange)):
        mb.cyl(0.05, 0.12, loc=(x, y, z - 0.1), mat="M_MushStem", verts=8)
        mb.dome(0.13, 0.1, loc=(x, y, z), mat=mat, u=12, v=3)
    mb.cyl(0.05, 0.1, loc=(0.52, -0.34, 0.05), rot=(80, 0, 30), mat="M_MushStem", verts=8)   # one rolled out
    mb.dome(0.12, 0.09, loc=(0.47, -0.42, 0.12), rot=(80, 0, 30), mat=orange, u=12, v=3)
    mb.build("X20001_MushroomCrate", coll, smooth=True, sharp_angle=40)


@asset("X20001_PottedPlant", "Props", footprint=0.7, tags=("interior",))
def _potted_plant(coll):
    """Terracotta pot with a round leafy bush and a few yellow flowers."""
    mb = MeshBuilder()
    mb.cyl(0.22, 0.4, mat="M_Flat_roof_orange", verts=14, r2=0.28)
    mb.cyl(0.31, 0.08, loc=(0, 0, 0.38), mat="M_Flat_roof_orange", verts=14)
    mb.cyl(0.25, 0.05, loc=(0, 0, 0.12), mat="M_Flat_wood_dk", verts=14)
    mb.cyl(0.27, 0.03, loc=(0, 0, 0.45), mat="M_Flat_dirt_dk", verts=14)
    mb.sphere(0.34, loc=(0, 0, 0.75), mat="M_Bush", subdiv=2, lumpy=0.22, seed=4)
    mb.sphere(0.2, loc=(0.14, -0.1, 0.98), mat="M_Bush", subdiv=1, lumpy=0.2, seed=6)
    for k in range(5):
        a = k * 1.3
        mb.sphere(0.06, loc=(math.cos(a) * 0.27, math.sin(a) * 0.27 - 0.05, 0.8 + (k % 2) * 0.12),
                  mat="M_Flat_flower_yellow", subdiv=1)
    mb.build("X20001_PottedPlant", coll, smooth=True, sharp_angle=40)


# ---------------------------------------------------------------------------
# house pieces built in-map
# ---------------------------------------------------------------------------

def gables(m):
    """Arched wall tops on the back and left walls that rise to meet the cap's cut edge."""
    x0, y0, x1, y1 = ROOM
    T = WALL_T
    yb = y1 - T / 2          # back wall inner plane (the cap is cut here)
    xl = x0 + T / 2          # left wall inner plane
    mb = MeshBuilder()
    # back gable: profile along x, extruded through the wall thickness
    xs = [x0 - T / 2 + i * (x1 - x0 + T) / 40 for i in range(41)]
    prof = [(xs[0] - (x0 - T / 2), WALL_H - 0.1), (xs[-1] - (x0 - T / 2), WALL_H - 0.1)]
    prof += [(x - (x0 - T / 2), max(WALL_H - 0.05, cap_z(x, yb) - CAP["th"] - 0.06)) for x in reversed(xs)]
    mb.prism(prof, -T / 2, T / 2, loc=m.w(x0 - T / 2, y1, 0.0), rot=(90, 0, m.wyaw(0)), mat="M_Flat_mush_stem")
    # left gable: profile along y
    ys = [y0 + i * (y1 - T / 2 - y0) / 30 for i in range(31)]
    prof = [(ys[0] - y0, WALL_H - 0.1), (ys[-1] - y0, WALL_H - 0.1)]
    prof += [(y - y0, max(WALL_H - 0.05, cap_z(xl, y) - CAP["th"] - 0.06)) for y in reversed(ys)]
    mb.prism(prof, -T / 2, T / 2, loc=m.w(x0, y0, 0.0), rot=(90, 0, m.wyaw(90)), mat="M_Flat_mush_stem")
    obj = CT.tag(mb.build(f"{m.slug}_Gables", m.col_arch, smooth=False), CT.WALL)
    obj.visible_shadow = False
    return obj


def mushroom_cap(m):
    """The orange cap, kept only behind the back/left wall planes; its cut faces show the cream flesh."""
    x0, y0, x1, y1 = ROOM
    T = WALL_T
    yb, xl = y1 - T / 2, x0 + T / 2
    cx, cy, rx, ry, th = CAP["cx"], CAP["cy"], CAP["rx"], CAP["ry"], CAP["th"]
    mb = MeshBuilder()

    def ridge(x, y):
        """Corner ridge: the two cut lines both fall toward the back-left corner (it sits right at the rim), so
        their top edges met in a sharp V-notch. A swell of the skin layer around the corner rounds the V into a
        soft U (the inner flesh surface and the gables under it are unchanged)."""
        d = math.hypot(x - xl, y - yb) / CORNER_RIDGE[1]
        return CORNER_RIDGE[0] * (1.0 - d) ** 2 if d < 1.0 else 0.0   # (its slope cancels the cut lines' fall)

    def P(x, y, inner=False, depth=None):
        d = (th if inner else 0.0) if depth is None else depth
        lift = ridge(x, y) if d < th - 1e-6 else 0.0   # outer skin + skin line lifted; the inner surface stays put
        return m.w(x, y, cap_z(x, y) + lift - d)

    def shell(grid, cut_edge, rim_edge):
        """grid[i][j]: i runs toward +x, j toward +y (top quads wind CCW seen from above)."""
        n, k = len(grid), len(grid[0])
        for i in range(n - 1):
            for j in range(k - 1):
                a, b, c, d = grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]
                mb.quad(P(*a), P(*b), P(*c), P(*d), CAP_SKIN)
                mb.quad(P(*d, True), P(*c, True), P(*b, True), P(*a, True), CAP_FLESH)
        skin = 0.36
        for (a, b) in cut_edge:      # (a, a_in, b_in, b): outward = (-z) x (b - a); orange skin over cream flesh
            mb.quad(P(*a), P(*a, depth=skin), P(*b, depth=skin), P(*b), CAP_SKIN)
            mb.quad(P(*a, depth=skin), P(*a, True), P(*b, True), P(*b, depth=skin), CAP_FLESH)
        for (a, b) in rim_edge:
            mb.quad(P(*a), P(*a, True), P(*b, True), P(*b), CAP_SKIN)

    # back region: x columns from the rim's west to east crossing of the cut line, y from the cut to the rim
    half = rx * math.sqrt(max(0.0, 1 - ((yb - cy) / ry) ** 2))
    xa, xb = cx - half + 0.02, cx + half - 0.02
    # (one column sits exactly on the left cut plane x = xl, so the back cut face starts precisely where
    #  the left region's cut face ends - no V-notch at the corner apex)
    xs = sorted({xa + (xb - xa) * i / 48 for i in range(49)} | {xl})
    xs = [x for k, x in enumerate(xs) if k == 0 or x - xs[k - 1] > 0.05 or x == xl]
    xs = [x for k, x in enumerate(xs) if not (k > 0 and xs[k - 1] == xl and x - xl < 0.05)]
    cols = []
    for x in xs:
        yr = cy + ry * math.sqrt(max(0.0, 1 - ((x - cx) / rx) ** 2)) - 0.01
        cols.append([(x, yb + (yr - yb) * j / 8) for j in range(9)])
    nc = len(cols) - 1
    cut = [(cols[i][0], cols[i + 1][0]) for i in range(nc) if cols[i][0][0] >= xl - 1e-6]   # faces -y
    rim = [(cols[i + 1][-1], cols[i][-1]) for i in range(nc)]                                 # faces +y
    rim += [(cols[0][j + 1], cols[0][j]) for j in range(8)] + [(cols[-1][j], cols[-1][j + 1]) for j in range(8)]
    shell(cols, cut, rim)
    # left region: columns from the rim (west) to the cut line x = xl, rows from the rim's south crossing to yb
    halfy = ry * math.sqrt(max(0.0, 1 - ((xl - cx) / rx) ** 2))
    ya = cy - halfy + 0.02
    rows = []
    for i in range(37):
        y = ya + (yb - ya) * i / 36
        xr = cx - rx * math.sqrt(max(0.0, 1 - ((y - cy) / ry) ** 2)) + 0.01
        rows.append([(xr + (xl - xr) * j / 6, y) for j in range(7)])
    grid = [[rows[i][j] for i in range(37)] for j in range(7)]
    cut = [(grid[-1][i], grid[-1][i + 1]) for i in range(36)]                                 # faces +x
    rim = [(grid[0][i + 1], grid[0][i]) for i in range(36)] + [(grid[j][0], grid[j + 1][0]) for j in range(6)]
    shell(grid, cut, rim)
    cap = CT.tag(mb.build(f"{m.slug}_Mushroom_Cap", m.col_arch, smooth=True, sharp_angle=50, recalc_normals=False),
                 CT.WALL)
    cap.visible_shadow = False
    # little cream spots on the visible crest (the 20000 house cap is plain, so keep them few and soft)
    return cap


def house_frame(m):
    """Honey timber posts, storey beams, the roof truss on the gables, and the loft's frame + railing."""
    x0, y0, x1, y1 = ROOM
    fb = y1 - WALL_T / 2 - 0.1
    fl = x0 + WALL_T / 2 + 0.1
    mb = MeshBuilder()
    for x in (3.4, 10.2, 13.0):  # wall posts (back)
        lbox(mb, m, (0.32, 0.22, WALL_H), (x, fb, WALL_H / 2), 0, HONEY, bevel=0.03)
    for y in (0.75, 3.4 + 1.35):  # wall posts (left)
        lbox(mb, m, (0.32, 0.22, WALL_H), (fl, y, WALL_H / 2), 90, HONEY, bevel=0.03)
    # storey line on the walls + top plates
    lbox(mb, m, (x1 - LOFT[2], 0.24, 0.3), ((LOFT[2] + x1) / 2, fb, LOFT_Z - 0.15), 0, HONEY, bevel=0.03)
    lbox(mb, m, (LOFT[1] - y0, 0.24, 0.3), (fl, (y0 + LOFT[1]) / 2, LOFT_Z - 0.15), 90, HONEY, bevel=0.03)
    lbox(mb, m, (x1 - x0, 0.26, 0.32), ((x0 + x1) / 2, fb, WALL_H - 0.16), 0, HONEY, bevel=0.03)
    lbox(mb, m, (y1 - y0, 0.26, 0.32), (fl, (y0 + y1) / 2, WALL_H - 0.16), 90, HONEY, bevel=0.03)
    # roof truss on the back gable: king post + rafters under the cap edge
    top = cap_z(CAP["cx"], fb) - CAP["th"] - 0.25
    lbox(mb, m, (0.3, 0.22, top - WALL_H), (CAP["cx"], fb, (top + WALL_H) / 2), 0, HONEY, bevel=0.03)
    for xa in (x0 + 0.6, x1 - 0.6):
        za = cap_z(xa, fb) - CAP["th"] - 0.25
        L = math.hypot(CAP["cx"] - xa, top - za)
        ang = math.degrees(math.atan2(top - za, CAP["cx"] - xa))
        lbox(mb, m, (L, 0.22, 0.26), ((xa + CAP["cx"]) / 2, fb, (za + top) / 2), 0, HONEY, tilt=(0, -ang, 0))
    # left gable: a centre post
    ymid = CAP["cy"]
    topl = cap_z(fl, ymid) - CAP["th"] - 0.25
    lbox(mb, m, (0.3, 0.22, topl - WALL_H), (fl, ymid, (topl + WALL_H) / 2), 90, HONEY, bevel=0.03)
    # loft frame: posts from the floor to the roof plate, front + side beams under the slab
    lx0, ly0, lx1, ly1 = LOFT
    for (px, py) in ((3.4, ly0 + 0.15), (6.8, ly0 + 0.15), (lx1 - 0.15, ly0 + 0.15)):
        lbox(mb, m, (0.3, 0.3, WALL_H), (px, py, WALL_H / 2), 0, HONEY, bevel=0.03)
    lbox(mb, m, (0.3, 0.3, LOFT_Z - 0.3), (lx1 - 0.15, 9.3, (LOFT_Z - 0.3) / 2), 0, HONEY, bevel=0.03)
    lbox(mb, m, (lx1 - lx0, 0.32, 0.45), ((lx0 + lx1) / 2, ly0 + 0.15, LOFT_Z - 0.4), 0, HONEY, bevel=0.03)
    lbox(mb, m, (0.32, ly1 - ly0, 0.45), (lx1 - 0.15, (ly0 + ly1) / 2, LOFT_Z - 0.4), 0, HONEY, bevel=0.03)
    lbox(mb, m, (lx1 - x0, 0.3, 0.32), ((x0 + lx1) / 2, ly0 + 0.15, WALL_H - 0.16), 0, HONEY, bevel=0.03)
    lbox(mb, m, (0.26, ly1 - ly0, 0.28), (7.6, (ly0 + ly1) / 2, WALL_H - 0.18), 0, HONEY, bevel=0.03)  # tie beam
    # loft railing (gap = the hatch over the ladder)
    hx0, hx1 = LADDER[0] - 0.65, LADDER[0] + 0.65
    for (a, b) in ((lx0 + 0.25, hx0), (hx1, lx1 - 0.2)):
        lbox(mb, m, (b - a, 0.12, 0.12), ((a + b) / 2, ly0 + 0.15, LOFT_Z + 0.9), 0, HONEY)
        n = max(1, int((b - a) / 0.45))
        for k in range(n + 1):
            lbox(mb, m, (0.08, 0.08, 0.9), (a + (b - a) * k / n, ly0 + 0.15, LOFT_Z + 0.45), 0, HONEY)
    lbox(mb, m, (0.12, ly1 - ly0, 0.12), (lx1 - 0.15, (ly0 + ly1) / 2, LOFT_Z + 0.9), 0, HONEY)
    for k in range(10):
        lbox(mb, m, (0.08, 0.08, 0.9), (lx1 - 0.15, ly0 + 0.15 + k * (ly1 - ly0 - 0.2) / 9, LOFT_Z + 0.45), 0, HONEY)
    # entry-nook lintel (the low beam between the nook and the main room): two posts framing the
    # nook opening and a short beam between them (the open front band stays clear)
    na, nb = 1.5, 5.2
    for py in (na, nb):
        lbox(mb, m, (0.3, 0.3, 2.3), (3.4, py, 1.15), 0, HONEY, bevel=0.03)
    lbox(mb, m, (0.3, nb - na + 0.3, 0.32), (3.4, (na + nb) / 2, 2.15), 0, HONEY, bevel=0.03)
    for (py, t) in ((na + 0.3, 40), (nb - 0.3, -40)):  # knee brackets from each post up to the beam
        lbox(mb, m, (0.12, 0.6, 0.12), (3.4, py, 1.85), 0, HONEY, tilt=(t, 0))
    obj = CT.tag(mb.build(f"{m.slug}_House_Frame", m.col_arch, smooth=False), CT.WALL)
    obj.visible_shadow = False   # posts + railings only striped the floor; the loft slab still casts its shadow
    return obj


WAINSCOT_H = 0.9


def wainscot_rail(m):
    """Honey cap rail along the top of the dark wainscot on the back and left walls (broken where the
    cupboard, the stove and the door stand against the wall)."""
    x0, y0, x1, y1 = ROOM
    T = WALL_T
    yb, xl = y1 - T / 2 - 0.06, x0 + T / 2 + 0.06
    mb = MeshBuilder()
    for (a, b) in ((x0 + T / 2, 10.72), (12.68, 13.55), (15.25, x1 - 0.05)):           # back wall
        lbox(mb, m, (b - a, 0.12, 0.07), ((a + b) / 2, yb, WAINSCOT_H + 0.02), 0, HONEY, bevel=0.015)
    for (a, b) in ((y0 + 0.05, 2.2), (4.4, y1 - T / 2)):                              # left wall
        lbox(mb, m, (b - a, 0.12, 0.07), (xl, (a + b) / 2, WAINSCOT_H + 0.02), 90, HONEY, bevel=0.015)
    obj = CT.tag(mb.build(f"{m.slug}_Wainscot_Rail", m.col_arch, smooth=False), CT.WALL)
    obj.visible_shadow = False
    return obj


# ---------------------------------------------------------------------------
# map
# ---------------------------------------------------------------------------

def build(m):
    x0, y0, x1, y1 = ROOM
    # ---------------- shell ----------------
    # (dark wood wainscot: a value break between the cream walls and the honey floor; a flat tint with no
    #  grain, so the bits seen between the furniture read as one panel band, capped by a honey rail)
    cut_room(m, WALL_H, wall_mat="M_Flat_mush_stem", knee_mat="M_StoneWall", base_mat="M_Flat_wood_dk",
             base_h=0.9, trim_mat="M_Flat_wood_dk", top_trim=False)
    wainscot_rail(m)
    gables(m)
    mushroom_cap(m)
    room_light(m, energy=2300, color=(1.0, 0.9, 0.74))

    # ---------------- NPC + door first (nothing walkable may sit above them) ----------------
    m.npc("Sen", 11.0, 4.7, rot=40)
    m.place("X20001_Door", x0 + WALL_T / 2 + 0.02, 3.3, rot=90, z=0.0)
    m.door_portal("out00", 1.2, 3.3, rot=90)

    # ---------------- ground floor ----------------
    m.place("X20001_WallShelf", x0 + WALL_T / 2 + 0.02, 1.55, rot=90, z=1.55)
    m.place("X20001_Cupboard", 11.7, y1 - WALL_T / 2 - 0.3, rot=0, z=0.0)
    m.place("X20001_Stove", 14.4, y1 - WALL_T / 2 - 0.5, rot=0, z=0.0)
    point_light(m, 14.4, 10.2, 0.6, energy=60, color=(1.0, 0.55, 0.2), radius=0.3, name="StoveGlow")
    m.place("X20001_RoundWindow", 11.6, y1 - WALL_T / 2 - 0.02, rot=0, z=4.7)
    m.place("X20001_RoundWindow", 14.1, y1 - WALL_T / 2 - 0.02, rot=0, z=4.7)
    m.place("X20001_RoundWindow", x0 + WALL_T / 2 + 0.02, 3.3, rot=90, z=4.6)
    m.place("X20001_DiningSet", 12.9, 5.4, rot=15)
    m.place("X20001_RugBraided", 12.9, 5.4, rot=15, z=RUG_Z, scale=0.8)
    m.place("X20001_RugBlue", 6.8, 3.6, rot=0, z=RUG_Z)
    # the front-right quadrant: Sen's pantry crate, laundry tub, a pot plant and a bench on the near wall
    m.place("X20001_MushroomCrate", 11.8, 3.1, rot=20)
    m.place("X20001_WashTub", 14.5, 2.9, rot=-30)
    m.place("X20001_PottedPlant", 15.0, 4.3, rot=0)
    m.place("Bench", 15.15, 6.8, rot=-90)
    m.place("X20001_Firewood", 13.12, 10.92, rot=0)
    m.place("X20001_BellLamp", 6.5, LOFT[1] - 0.15, z=LOFT_Z - 0.45)
    point_light(m, 6.5, 6.0, 1.8, energy=70, color=(1.0, 0.8, 0.5), radius=0.3, name="LampLow")
    # storage under the loft (explicit z: the loft would catch the raycast)
    # (the crates stand well west of the ladder foot so, from the camera, the ladder reads on its own)
    for (a, x, y, r, s) in (("Barrel", 1.6, 7.6, 0, 1.0), ("Barrel", 2.4, 8.2, 30, 0.9), ("Sack", 4.6, 7.3, 20, 1.0),
                            ("Crate", 6.3, 7.2, 12, 1.0), ("Crate", 5.8, 8.3, -8, 0.8), ("Sack", 4.9, 8.5, -40, 0.9)):
        m.place(a, x, y, rot=r, z=0.0, scale=s)
    m.place("Sack", 2.3, 1.0, rot=30)
    # entry nook: a shoe bench under the little wall shelf and a coat stand by the lintel post
    m.place("X20001_ShoeBench", x0 + WALL_T / 2 + 0.23, 1.55, rot=90)
    m.place("X20001_CoatRack", 1.15, 5.5, rot=20)
    # centre-left reading corner (front band, kept low and >1.5 m off the Main route)
    m.place("X20001_RugGreen", 5.2, 1.35, rot=0, z=RUG_Z, scale=0.62)
    m.place("X20001_Armchair", 4.7, 1.3, rot=30)
    m.place("X20001_Nightstand", 5.8, 0.95, rot=10)
    m.place("Barrel", 15.0, 1.2, rot=0, scale=0.9)
    m.place("Sack", 14.2, 0.9, rot=-30)

    # ---------------- loft (upper floor) ----------------
    m.ladder("Ladder_Loft", LADDER[0], LADDER[1], 0.0, LOFT_Z, facing=90)
    loft = solid(m, "Loft_Floor", [(LOFT[0], LOFT[1], LOFT[2], LOFT[3], LOFT_Z - 0.3, LOFT_Z)], mat="M_Flat_wood_dk")
    loft.visible_shadow = True
    plank_floor(m, LOFT[0] + 0.2, LOFT[1] + 0.05, LOFT[2] - 0.05, LOFT[3] - 0.1, z=LOFT_Z, name="Loft_Planks")
    house_frame(m)
    m.place("X20001_Bed", 2.2, 10.5, rot=0, z=LOFT_Z)
    m.place("X20001_Nightstand", 3.95, 11.05, rot=0, z=LOFT_Z)
    m.place("X20001_CurtainWindow", 5.9, y1 - WALL_T / 2 - 0.02, rot=0, z=LOFT_Z + 1.75)
    # treasure chest near the ladder top, front (lock) turned to the camera; on screen (x + y ~17.9) it is
    # clear of the loft's full-height corner post (10.05, 6.75) and above both railings
    m.place("Treasure_Chest", 8.7, 9.2, rot=25, z=LOFT_Z, scale=0.9)   # (25: lock + the lid's round end show)
    m.place("X20001_RugGreen", 6.2, 9.1, rot=0, z=LOFT_Z + RUG_Z, scale=0.7)
    m.place("X20001_BellLamp", 7.6, 9.1, z=WALL_H - 0.32)
    point_light(m, 7.6, 9.1, 4.9, energy=70, color=(1.0, 0.8, 0.5), radius=0.3, name="LampHigh")
    m.place("Crate", 8.6, 10.9, rot=10, z=LOFT_Z, scale=0.7)
    m.place("X20001_WallShelf", 8.0, y1 - WALL_T / 2 - 0.02, rot=0, z=LOFT_Z + 1.6)

    # ---------------- gameplay ----------------
    m.player(5.6, 2.6, rot=-50)
    m.player_spawn(3.0, 3.3, rot=90, note="interior: just inside the door (out00)")
    m.route("Main", [(1.2, 3.3), (4.6, 3.4), (8.0, 4.4), (10.4, 4.7)])
    # one route from the main room up the ladder (climbed mid-route) and across the loft to the bed
    m.route("Loft", [(10.4, 4.7), (9.0, 5.4), (9.0, 6.0), (9.0, 6.75), (9.0, 7.2), (7.0, 7.8), (4.6, 8.6),
                     (4.0, 9.4)])
    # to the stove: round the north side of the dining set (between it and the loft's corner post), clear of
    # the stools, and stop in front of the oven
    m.route("ToStove", [(10.4, 4.7), (11.3, 6.9), (13.3, 8.5), (14.3, 9.5)])
