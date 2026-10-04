"""Mushroom Town (10000) - "the village green".

Classic (GMS v8) structure, from docs/research/maps/10000_MushroomTown_10000.md:
  T1 low west meadow (sunflowers, arrival in00) -> T2 short ramp -> T3 main street
  (exit out00 near the east end); T4 Roger's raised hedge-walled vegetable garden
  (display only) beside the yellow mushroom house with a barrel chimney.

3D translation: the meadow is a sunken lawn at the west, planted as a dense sunflower bed
either side of the arrival path (the map's colour signature). An earthen ramp turns the
player slightly north-east onto a raised village street running west->east. The north
(back) side of the street carries the landmarks: Roger's garden terrace (hedge face to the
street, the blue-rope vegetable fence along its top edge, crop rows behind) and, right
beside it, the big yellow brown-streaked mushroom house with its barrel chimney, its cap
overhanging the garden's east corner as in 2D. Behind the meadow, Roger's tool shed and the
village well stand on the back lawn. No other houses: the town distinction comes from each
map's own landmark.
"""

import math

from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.mapkit import MAIN_ROAD

MAP_ID = 10000
GAMEPLAY_FOCUS = (27.0, 21.5)
GAMEPLAY_SCALE = 30.0

STREET_Z = 1.2
GARDEN_Z = STREET_Z + 3.0


# ---------------------------------------------------------------- local assets
@asset("X10000_VegFence", "Props", footprint=1.0, tags=("prop", "farm"))
def _veg_fence(coll):
    """Roger's vegetable-garden fence (v8 object at (327,44)): a 9.6 m run of stout posts with
    two strands of blue rope, a row of leafy crops right behind it. Gap behind the middle where
    Roger stands. Runs along local X, crops on the +Y side."""
    mb = MeshBuilder()
    n = 9
    for k in range(n):
        x = -4.8 + k * 1.2
        mb.box((0.14, 0.14, 0.95), loc=(x, 0, 0.42), mat="M_Wood", bevel=0.03, segs=1)
        mb.cyl(0.1, 0.08, loc=(x, 0, 0.9), mat="M_Wood_Dark", verts=8)
    for z in (0.42, 0.74):
        mb.box((9.7, 0.05, 0.06), loc=(0, 0, z), mat="M_Flat_roof_blue")
    mb.build("X10000_VegFence", coll, smooth=False)
    crops = MeshBuilder()
    k = 0
    x = -4.4
    while x < 4.5:
        if not (-1.0 < x < 2.0):  # Roger's gap
            crops.sphere(0.27, loc=(x, 0.55, 0.22), scale=(1.15, 1.1, 0.75), mat="M_Leaf_B", subdiv=2, lumpy=0.18,
                         seed=k)
            if k % 2:
                crops.sphere(0.11, loc=(x + 0.1, 0.4, 0.36), mat="M_Tomato", subdiv=1)
            else:
                crops.cyl(0.07, 0.24, loc=(x - 0.08, 0.42, 0.3), rot=(180, 0, 0), mat="M_Flat_roof_orange",
                          verts=6, r2=0.0)
            k += 1
        x += 0.72
    crops.box((9.4, 0.8, 0.12), loc=(0, 0.55, 0.04), mat="M_Path_Dirt", bevel=0.05, segs=1)
    crops.build("X10000_VegFence_Crops", coll, smooth=True, sharp_angle=50)


@asset("X10000_CropRow", "Foliage", footprint=1.0, tags=("farm",))
def _crop_row(coll):
    """A 4 m tilled row along X: a dirt ridge with cabbages and carrot tops alternating."""
    mb = MeshBuilder()
    mb.box((4.0, 0.75, 0.16), loc=(0, 0, 0.06), mat="M_Path_Dirt", bevel=0.07, segs=1)
    for k in range(7):
        x = -1.7 + k * 0.57
        if k % 2 == 0:
            mb.sphere(0.24, loc=(x, 0, 0.3), scale=(1.1, 1.1, 0.8), mat="M_Leaf_B", subdiv=2, lumpy=0.2, seed=k)
            mb.sphere(0.14, loc=(x, 0, 0.36), mat="M_Flat_leaf_lt", subdiv=1)
        else:
            for s in (-1, 0, 1):
                mb.cyl(0.03, 0.34, loc=(x + s * 0.07, 0, 0.14), rot=(s * 18, 0, 0), mat="M_Flat_leaf", verts=4)
            mb.cyl(0.08, 0.12, loc=(x, 0, 0.12), mat="M_Flat_roof_orange", verts=8)
    mb.build("X10000_CropRow", coll, smooth=True, sharp_angle=50)


@asset("X10000_WateringCan", "Props", footprint=0.5, tags=("prop", "farm"))
def _watering_can(coll):
    """Green tin watering can with a long spout and a rose."""
    mb = MeshBuilder()
    mb.cyl(0.2, 0.36, mat="M_Flat_roof_green", verts=14, r2=0.17)
    mb.cyl(0.18, 0.03, loc=(0, 0, 0.36), mat="M_Metal", verts=14)
    mb.cyl(0.035, 0.5, loc=(0.16, 0, 0.1), rot=(0, 55, 0), mat="M_Flat_roof_green", verts=6)
    mb.cyl(0.07, 0.05, loc=(0.56, 0, 0.38), rot=(0, 55, 0), mat="M_Metal", verts=8)
    mb.torus(0.14, 0.025, loc=(-0.05, 0, 0.5), rot=(90, 0, 0), mat="M_Flat_roof_green", u=12, v=4)
    mb.build("X10000_WateringCan", coll, smooth=True, sharp_angle=45)


@asset("X10000_ToolShed", "Architecture", footprint=3.4, tags=("shed",))
def _tool_shed(coll):
    """Roger's little plank tool shed: lean-to red roof, plank door (-Y), a round window, a rake
    and a shovel leaning by the door, a sack of seed and a wheelbarrow of turnips."""
    mb = MeshBuilder()
    mb.box((3.0, 2.2, 0.2), loc=(0, 0, 0.1), mat="M_StoneWall", bevel=0.05, segs=1)
    mb.box((2.8, 2.0, 2.3), loc=(0, 0, 1.35), mat="M_Plank", bevel=0.04, segs=1)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((0.18, 0.18, 2.5), loc=(sx * 1.4, sy * 1.0, 1.35), mat="M_Wood_Dark")
    mb.box((3.0, 0.16, 0.16), loc=(0, -1.02, 2.45), mat="M_Wood_Dark")
    # lean-to roof, high at the back
    mb.box((3.5, 2.8, 0.16), loc=(0, -0.05, 2.85), rot=(-14, 0, 0), mat="M_Flat_roof_red", bevel=0.04, segs=1)
    mb.box((3.6, 0.2, 0.22), loc=(0, -1.38, 2.55), rot=(-14, 0, 0), mat="M_Wood_Dark")
    # door + window
    mb.box((0.95, 0.08, 1.75), loc=(-0.45, -1.04, 1.08), mat="M_Door")
    mb.box((1.1, 0.06, 0.1), loc=(-0.45, -1.07, 1.98), mat="M_Wood_Dark")
    mb.box((0.08, 0.06, 1.2), loc=(-0.45, -1.09, 1.1), rot=(0, 38, 0), mat="M_Wood_Dark")
    mb.sphere(0.05, loc=(-0.12, -1.1, 1.05), mat="M_Gold", subdiv=1)
    mb.cyl(0.3, 0.12, loc=(0.75, -1.0, 1.55), rot=(90, 0, 0), mat="M_Wood_Dark", verts=12)
    mb.cyl(0.22, 0.14, loc=(0.75, -1.02, 1.55), rot=(90, 0, 0), mat="M_Window", verts=12)
    mb.build("X10000_ToolShed", coll, smooth=False)
    t = MeshBuilder()
    # rake
    t.cyl(0.03, 1.7, loc=(0.55, -1.25, 0.05), rot=(-12, 8, 0), mat="M_Wood", verts=6)
    t.box((0.5, 0.05, 0.05), loc=(0.67, -1.6, 1.7), rot=(-12, 8, 0), mat="M_Metal")
    for k in range(5):
        t.box((0.02, 0.02, 0.12), loc=(0.47 + k * 0.1, -1.62, 1.64), mat="M_Metal")
    # shovel
    t.cyl(0.03, 1.4, loc=(1.15, -1.2, 0.25), rot=(-10, -6, 0), mat="M_Wood", verts=6)
    t.box((0.24, 0.04, 0.32), loc=(1.15, -1.2, 0.18), mat="M_Metal", bevel=0.02, segs=1)
    # seed sack
    t.sphere(0.32, loc=(-1.35, -1.25, 0.3), scale=(1.0, 0.9, 1.1), mat="M_Flat_wood_lt", subdiv=2, lumpy=0.1, seed=3)
    t.torus(0.12, 0.04, loc=(-1.35, -1.25, 0.62), mat="M_Rope", u=10, v=4)
    # wheelbarrow with turnips on the east side
    t.box((0.9, 0.6, 0.3), loc=(1.95, 0.2, 0.55), rot=(0, -8, 0), mat="M_Plank", bevel=0.04, segs=1)
    t.cyl(0.18, 0.08, loc=(2.45, 0.24, 0.2), rot=(90, 0, 0), mat="M_Wood_Dark", verts=10)
    for k in range(4):
        t.sphere(0.13, loc=(1.75 + (k % 2) * 0.3, 0.05 + (k // 2) * 0.28, 0.76), mat="M_Flat_flower_white", subdiv=1)
        t.cyl(0.03, 0.18, loc=(1.75 + (k % 2) * 0.3, 0.05 + (k // 2) * 0.28, 0.84), mat="M_Flat_leaf", verts=4)
    for s in (-1, 1):
        t.box((0.7, 0.05, 0.05), loc=(1.25, 0.2 + s * 0.25, 0.52), rot=(0, -12, 0), mat="M_Wood")
        t.box((0.05, 0.05, 0.4), loc=(1.6, 0.2 + s * 0.25, 0.2), mat="M_Wood")
    t.build("X10000_ToolShed_Tools", coll, smooth=True, sharp_angle=45)


@asset("X10000_Firewood", "Props", footprint=1.4, tags=("prop",))
def _firewood(coll):
    """Stacked split firewood between two stakes, a chopping block with an axe."""
    mb = MeshBuilder()
    for row, n in ((0, 4), (1, 4), (2, 3)):
        for k in range(n):
            x = -0.48 + k * 0.32 + row * 0.16 * (row == 2)
            mb.cyl(0.14, 0.9, loc=(x, -0.45, 0.14 + row * 0.26), rot=(-90, 0, 0), mat="M_Bark", verts=7)
            mb.cyl(0.12, 0.02, loc=(x, -0.46, 0.14 + row * 0.26), rot=(90, 0, 0), mat="M_Flat_wood_lt", verts=7)
    for x in (-0.72, 0.72):
        mb.box((0.08, 0.08, 1.0), loc=(x, 0, 0.5), mat="M_Wood_Dark")
    mb.cyl(0.3, 0.42, loc=(1.15, -0.2, 0), mat="M_Bark", verts=12)
    mb.cyl(0.27, 0.02, loc=(1.15, -0.2, 0.42), mat="M_Flat_wood_lt", verts=12)
    mb.cyl(0.025, 0.6, loc=(1.15, -0.2, 0.42), rot=(0, 35, 0), mat="M_Wood", verts=6)
    mb.box((0.18, 0.04, 0.14), loc=(1.33, -0.2, 0.86), rot=(0, 35, 0), mat="M_Metal")
    mb.build("X10000_Firewood", coll, smooth=True, sharp_angle=45)


@asset("X10000_PicnicTable", "Props", footprint=2.0, tags=("prop", "town"))
def _picnic_table(coll):
    """Village-common picnic table: plank top on splayed A-frame legs, a bench either side (along X),
    a little basket of apples and a jug on the table."""
    mb = MeshBuilder()
    for k in range(4):  # top slats
        mb.box((1.9, 0.2, 0.06), loc=(0, -0.33 + k * 0.22, 0.72), mat="M_Plank", bevel=0.015, segs=1)
    for x in (-0.72, 0.72):
        for s in (-1, 1):
            mb.box((0.09, 0.09, 0.98), loc=(x, s * 0.36, 0.36), rot=(s * 30, 0, 0), mat="M_Wood")
        mb.box((0.08, 1.75, 0.07), loc=(x, 0, 0.36), mat="M_Wood_Dark")
        mb.box((0.08, 0.7, 0.06), loc=(x, 0, 0.66), mat="M_Wood_Dark")
    for s in (-1, 1):  # benches
        mb.box((1.9, 0.32, 0.06), loc=(0, s * 0.74, 0.42), mat="M_Plank", bevel=0.015, segs=1)
    mb.build("X10000_PicnicTable", coll, smooth=False)
    t = MeshBuilder()
    t.cyl(0.2, 0.16, loc=(-0.35, 0.02, 0.75), mat="M_Flat_wood_lt", verts=12, r2=0.24)
    t.torus(0.16, 0.025, loc=(-0.35, 0.02, 0.98), rot=(90, 0, 0), mat="M_Flat_wood", u=12, v=4)
    for k, (dx, dy) in enumerate(((-0.08, -0.05), (0.07, 0.06), (0.0, -0.1), (0.1, -0.06))):
        t.sphere(0.075, loc=(-0.35 + dx, 0.02 + dy, 0.93 + 0.03 * (k % 2)), mat="M_Tomato", subdiv=1)
    t.cyl(0.09, 0.22, loc=(0.4, -0.08, 0.75), mat="M_Flat_cloth_white", verts=10, r2=0.07)
    t.box((1.0, 0.5, 0.012), loc=(0.15, 0.0, 0.755), mat="M_Flat_cloth_red")
    t.build("X10000_PicnicTable_Picnic", coll, smooth=True, sharp_angle=45)


# ---------------------------------------------------------------- helpers
def _door_xy(cx, cy, rot, dist):
    a = math.radians(rot)
    return cx + math.sin(a) * dist, cy - math.cos(a) * dist


# ---------------------------------------------------------------- the map
def build(m):
    L, D = m.size  # 42 x 36

    # --- terrain -----------------------------------------------------------------
    # main street terrace (T3): raised 1.2 m above the meadow, wide and gently curving
    # the street's west lip is notched where the T2 ramp arrives, so the ramp runs up a shallow cut and
    # lands flush on the street (no grass lip across the trail)
    street = [(12, 3), (26, 2.5), (42.5, 4), (42.5, 25), (30, 26), (24, 24), (14, 24), (11.07, 15.2), (12.35, 15.53),
              (13.67, 10.29), (11.44, 9.72)]
    m.terrace("Street", street, top=STREET_Z, bottom=-0.5)
    # Roger's garden (T4): +3 m above the street, behind (north of) it
    m.terrace("RogerGarden", geo.rounded_rect(15, 24, 27, 34.5, 2.0), top=GARDEN_Z, bottom=STREET_Z - 0.2)
    # house lot behind the street, east of the garden (street level)
    m.terrace("HouseLot", [(26, 22), (40, 22), (41, 35), (27, 35)], top=STREET_Z, bottom=-0.5)
    # back lawn, a little higher: Roger's tool shed and the village well
    m.terrace("BackLawn", geo.rounded_rect(1, 22, 13, 34, 2.5), top=0.6, bottom=-0.5)
    # T2 ramp from the meadow up to the street: a grassy slope (cap lip + fringe) carrying the road
    m.ramp("Ramp_Meadow_Street", (5.5, 11.0, 0.0), (13.3, 12.98, STREET_Z), 5.0, top_mat=None)
    # the island's Main road (pale cream): in00 -> meadow -> up the ramp's axis -> village street -> out00
    m.path("Main_Road", [(1, 10), (3.5, 10.4), (5.5, 11.0), (9.4, 11.99), (13.3, 12.98), (16.5, 13.9), (20, 14.4),
                         (30, 14.5), (42, 14)], **MAIN_ROAD)

    # --- landmarks -----------------------------------------------------------------
    # the yellow brown-streaked mushroom house with the barrel chimney (houseGS/house8): right beside
    # Roger's garden, its cap overhanging the garden's east corner, the arched door facing the street
    hx, hy, hrot = 30.5, 27.5, -8.0
    m.place("House_Mushroom_YellowStreaked", hx, hy, rot=hrot, scale=1.3)
    dx, dy = _door_xy(hx, hy, hrot, 2.76)  # door plane of the scaled stem
    m.path("Door_Path", [(31.2, 15.0), (30.9, 19.0), (dx + 0.05, dy - 0.7), (dx, dy - 0.25)], width=1.9)
    # the vegetable patch between the street and the house front (v8 fence at (547,190)), east of the door
    m.place("Veg_Garden_Bed", 36.6, 20.4, rot=-4)
    m.place("Barrel", 32.5, 24.0, rot=10)
    m.place("Crate", 33.3, 24.9, rot=20)
    m.place("X10000_Firewood", 35.4, 28.4, rot=-70)
    m.place("Flower_Bed_Large", 36.4, 24.6, rot=20, scale=0.8)
    m.place("Mailbox_Red", 32.6, 19.2, rot=-10)
    m.place("Bush_A", 38.6, 27.0, rot=40)  # bushes east of the house (v8 (599,167), (645,164))
    m.place("Bush_B", 40.2, 24.2, rot=10)

    # Roger's terrace: hedge face toward the street, the blue-rope vegetable fence along its top edge,
    # crop rows behind it, a watering can and the scarecrow
    m.place("Hedge_Wall_4m", 15.2, 23.6, rot=0)
    m.place("Hedge_Wall_4m", 19.2, 23.4, rot=0)
    m.place("Hedge_Wall_4m", 23.2, 23.6, rot=0, scale=(0.95, 1, 1))
    m.place("X10000_VegFence", 21.0, 24.9, rot=0)
    m.npc("Roger", 21.5, 26.1, rot=-10)
    for i, (x, y) in enumerate([(18.8, 28.0), (23.4, 28.0), (18.8, 29.8), (23.4, 29.8), (18.8, 31.6),
                                (23.4, 31.6)]):
        m.place("X10000_CropRow", x, y, rot=0 if i % 2 == 0 else 180)
    m.place("Scarecrow", 25.6, 30.6, rot=-25)
    m.place("X10000_WateringCan", 21.0, 27.2, rot=40)
    m.place("Sack", 16.6, 26.4, rot=20, scale=0.9)
    m.place("Bush_B", 16.4, 33.0, rot=30, scale=0.8)

    # back lawn: Roger's tool shed and the village well
    m.place("X10000_ToolShed", 5.6, 29.2, rot=12)
    m.place("Well", 10.0, 26.0, rot=-20)
    m.place("Bush_C", 2.4, 32.6, rot=0)
    m.place("Bush_A", 9.6, 32.6, rot=40, scale=0.9)

    # --- the sunflower arrival meadow: a dense bed either side of the in00 path ----------------
    def path_y(x):  # centreline of the Main road across the meadow
        return 10.0 + 0.16 * (x - 1) if x < 3.5 else (10.4 + 0.3 * (x - 3.5) if x < 5.5 else 11.0 + 0.254 * (x - 5.5))

    k = 0
    for gx in (1.6, 3.2, 4.8, 6.4, 8.0):
        for side, ys in ((-1, (5.2, 6.7, 8.0)), (1, (12.9, 14.3, 15.6))):
            for yy in ys:
                y = yy + 0.25 * ((k * 7) % 3 - 1)
                x = gx + 0.3 * ((k * 5) % 3 - 1)
                if abs(y - path_y(x)) < 2.6 or (side > 0 and gx > 7.5):  # clear of the 3.6 m road and the ramp
                    k += 1
                    continue
                m.place("Sunflower_Patch", x, y, rot=k * 47, scale=1.3 + 0.08 * (k % 4))
                k += 1
    # low shrubs along the ramp's camera-facing flank (softens the sloped earth side into the meadow)
    m.place("Bush_Flowering_A", 10.6, 8.9, rot=20, scale=0.75)
    m.place("Bush_B", 8.6, 8.5, rot=60, scale=0.6)
    m.place("Butterfly_Yellow", 3.8, 7.6)
    m.place("Butterfly", 6.6, 13.8)
    m.place("Butterfly_Pink", 2.4, 14.2)

    # --- street furniture (north side) ------------------------------------------------------
    m.place("Lamp_Post", 17.0, 17.6, rot=180)
    m.place("Planter", 20.4, 18.6, rot=0, scale=0.8)
    m.place("Bench", 24.0, 18.6, rot=180)
    m.place("Lamp_Post", 28.6, 17.4, rot=180)
    m.place("Bench", 34.2, 17.6, rot=180)
    m.place("Lamp_Post", 40.2, 17.9, rot=180)
    m.place("Planter", 13.6, 18.4, rot=0, scale=0.75)
    m.place("Sign_Board", 39.0, 9.0, rot=-30)

    # --- dressing ------------------------------------------------------------------
    # the south verge is the village common (all solids >= 1.5 m from the Main road at y ~13.2-14.5):
    # a second sunflower bed echoing the arrival meadow, a picnic table in the shade of a tree, a notice
    # board at the street edge, flower beds and low shrubs along the fence, round trees on the flanks
    for k, (x, y) in enumerate(((17.3, 6.5), (18.7, 5.4), (20.3, 5.0), (21.9, 5.5), (23.1, 6.6), (22.3, 8.1),
                                (20.7, 8.6), (19.1, 8.3), (20.3, 6.8))):
        m.place("Sunflower_Patch", x, y, rot=k * 53, scale=1.25 + 0.08 * (k % 3))
    m.place("Butterfly_Yellow", 19.6, 9.6)
    m.place("Butterfly", 22.8, 4.4)
    m.place("X10000_PicnicTable", 28.4, 8.4, rot=12)
    m.place("Tree_Round_C", 34.4, 5.2, rot=40, scale=0.8)  # beside (not in front of) the picnic table
    m.place("Tree_Round_C", 14.0, 5.6, rot=110, scale=0.75)
    m.place("Tree_Round_C", 40.4, 6.8, rot=200, scale=0.75)
    m.place("Signpost_Notice", 25.2, 11.4, rot=25)
    for (x, y, r, s) in ((31.2, 5.6, -20, 0.7), (37.6, 8.2, 20, 0.65)):
        m.place("Flower_Bed_Large", x, y, rot=r, scale=s)
    for (x, y) in ((25.4, 8.0), (34.6, 9.6), (37.8, 10.4), (13.6, 9.0), (16.4, 9.8)):
        m.place("Clover_Patch", x, y, rot=x * 13)
    m.place("Bush_C", 23.8, 3.6, rot=10, scale=0.8)
    # east of the house: a second crop bed, a flowering bush and a small tree frame the lot
    m.place("Veg_Garden_Bed", 37.6, 31.0, rot=8, scale=0.9)
    m.place("Bush_Flowering_A", 34.6, 33.2, rot=0, scale=0.9)
    m.place("Tree_Round_C", 40.4, 29.4, rot=40, scale=0.75)
    m.place("Bush_B", 9.0, 2.0)
    m.place("Bush_A", 41.0, 32.0)
    m.place("Bush_Flowering_A", 26.0, 3.8, scale=0.85)
    m.place("Bush_C", 16.4, 3.8)
    m.place("Mushroom_Cluster_A", 12.0, 20.0, rot=20)
    m.place("Tree_Round_B", 2.5, 19.0)
    m.place("Tree_Round_A", 1.0, 3.0, rot=60)
    m.place("Tree_Round_C", 12.0, 34.6, rot=10)
    m.place("Tree_Round_A", 28.0, 34.6, rot=200, scale=0.9)
    m.place("Tree_Round_B", 40.6, 34.8, rot=120, scale=0.85)
    m.fence([(13.5, 3.2), (26, 2.8), (41.5, 4.2)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(12, 3, 42, 23), 16, seed=4,
              min_dist=1.6, avoid=[geo.rect(12, 11, 42, 16.5), geo.rect(29, 15, 33, 25)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A"], geo.rect(0, 0, 11, 22), 6, seed=6, min_dist=1.4,
              avoid=[geo.rect(0, 4.4, 9.2, 16.4), geo.rect(5, 8.5, 13.5, 15.5)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_B"], geo.rect(1, 22, 13, 34), 5, seed=7, min_dist=1.4,
              avoid=[(5.6, 29.2, 2.6), (10.0, 26.0, 1.6)])

    # --- gameplay ------------------------------------------------------------------
    m.edge_portal("in00")
    m.edge_portal("out00")
    m.player(26.2, 13.7, rot=30)  # on the street, just off the road centreline, facing the camera
    m.player_spawn(4.5, 10.5, rot=90, note="sp x -91: ~3 m east of in00 on the arrival meadow")
    m.route("Main", [(1, 10), (5.5, 11.0), (9.4, 11.99), (13.3, 12.98), (16.5, 13.9), (20, 14.4), (30, 14.5),
                     (41, 14)])
    # ends on the door path 1.35 m in front of the door plane: a run can start there clear of the house's
    # collision (at 1.1 m the 0.3 m body touched its prism)
    m.route("ToYellowHouse", [(31.2, 14.6), (30.9, 19.0), (dx + 0.05, dy - 1.35)])
