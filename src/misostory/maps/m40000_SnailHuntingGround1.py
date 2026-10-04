"""Snail Hunting Ground I (40000) - "a terraced autumn hillside wrapped around a valley".

Classic (GMS v8) structure, from docs/research/maps/40000_SnailHuntingGround1_40000.md:
  ground band: raised west entry plateau (in00 + Robin) -> basin -> 3-step knoll -> east
  meadow (east00); mid band: west ridge path, long central terrace, stacked boulders to an
  east terrace; low rock shelf with a ladder; upper band: back-left high terrace with a
  trapezoid hump and a tiny islet (rope), back-right high terrace, linked by the FOUR-BLOCK
  STAIRCASE (T6 > T5 > T4 > T2, reached by rope x1530 from the central terrace).
  13 ladders/ropes; Snails + Blue Snails only.

3D translation: each higher 2D band steps BACK (+y) as it rises, so the map reads as an
amphitheatre from the camera. The front valley is the main west->east route (the pale main road),
framed by its autumn birches; the knoll is three concentric oval tiers climbed by offset stone
flights on both flanks. The terraces form an optional upper loop: knoll ladders -> central terrace
-> rope up the first rock block -> four grass-capped rock blocks stepping diagonally up the cliff
corner (2-tread stone steps between them) -> the high east terrace; the third block meets a lobe of
the high west terrace (the classic T1 overhang), which carries the hump. Above the high west
terrace the tiny islet (T0) floats free: a grass cap over a rocky inverted-cone underside, reached
by a rope hanging from its lip (no route walks under it).
"""

import math

from misostory import core, geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.mapkit import MAIN_ROAD

MAP_ID = 40000
GAMEPLAY_FOCUS = (30.0, 16.0)
GAMEPLAY_SCALE = 34.0

MID = 4.6
UPPER = 9.2  # HighWest (= block 3)
BSTEP = 0.7  # one 60 px block step
HIGH_E = UPPER + BSTEP  # HighEast (= block 4)
HUMP = UPPER + 1.4
SPIRE = UPPER + 4.8  # the islet (T0): the tallest point, 14 m
ISLET_X, ISLET_Y, ISLET_R = 5.6, 30.0, 1.9  # the floating islet over HighWest (no route walks under it)
HUMP_Y = 35.1

# knoll: three oval tiers; flights sit on staggered lanes so no landing runs into the next flight
KX = 34.0
KNOLL = [((34, 12.5), (9.5, 6.5), 1.0), ((34, 13.0), (6.4, 4.4), 2.0), ((34, 13.3), (3.6, 2.6), 3.0)]
LANES = [(9.6, 2.2), (11.9, 2.0), (14.1, 1.8)]  # (y, width) of flights 1..3

# the four-block staircase: (x0, y0, x1, y1, top); each block 0.7 m above the last, 0.2 m clefts between
BLOCKS = [(25.4, 29.0, 28.2, 31.8, UPPER - 2 * BSTEP), (28.4, 30.0, 31.2, 32.8, UPPER - BSTEP),
          (31.4, 31.0, 34.2, 33.8, UPPER), (34.4, 32.0, 37.2, 34.8, HIGH_E)]


@asset("X40000_Islet_Root", "Rocks", footprint=3.8, tags=("rock", "landmark"))
def _islet_root(coll):
    """The underside of the tiny floating islet (classic T0): a lumpy inverted cone of warm rock under a band of
    earth, a few dangling roots - the same look as the floating island's own underside. Origin = top centre;
    it hangs DOWN from z = 0 (the islet cap sits on top)."""
    r = core.rng("X40000_Islet_Root", 3)
    mb = MeshBuilder()
    R = 1.85
    mb.cyl(R, 0.55, loc=(0, 0, -0.55), mat="M_Dirt_Cliff", verts=18, r2=R * 1.02)
    mb.cyl(0.22, 2.0, loc=(0.1, -0.05, -2.55), mat="M_Rock_Cliff", verts=14, r2=R * 0.96)
    for k in range(7):  # knobbly rocks bulging out of the cone
        a = math.tau * k / 7 + r.uniform(-0.3, 0.3)
        zz = r.uniform(-1.9, -0.8)
        rad = (R * 0.96) * (1 + (zz + 0.55) / 2.0) * 0.82
        mb.sphere(r.uniform(0.38, 0.6), loc=(math.cos(a) * rad, math.sin(a) * rad, zz), scale=(1, 1, 0.8),
                  mat="M_Rock_Cliff", subdiv=2, lumpy=0.35, seed=k)
    mb.sphere(0.45, loc=(0.1, 0.0, -2.45), scale=(1, 1, 1.3), mat="M_Rock_Cliff", subdiv=2, lumpy=0.3, seed=9)
    for k in range(5):  # dangling roots
        a = math.tau * k / 5 + 0.4
        mb.cyl(0.05, r.uniform(0.6, 1.1), loc=(math.cos(a) * R * 0.9, math.sin(a) * R * 0.9, -0.5),
               rot=(180 + r.uniform(-12, 12), r.uniform(-12, 12), 0), mat="M_Wood_Dark", verts=5, r2=0.015)
    mb.build("X40000_Islet_Root", coll, smooth=True, sharp_angle=50)


def knoll_edge(i, y, side):
    """x of knoll tier i's rim at depth y on the west (side=-1) or east (+1) flank."""
    (cx, cy), (rx, ry), _ = KNOLL[i]
    t = (y - cy) / ry
    return cx + side * rx * max(0.0, 1.0 - t * t) ** 0.5


def build(m):
    L, D = m.size  # 64 x 40

    # ---------------- ground band (front) ----------------
    m.terrace("EntryPlateau", geo.rounded_rect(-1, 2, 13, 17, 2.5), top=1.2, bottom=-0.5)
    m.ramp("Steps_Plateau_Basin", (12.5, 9.0, 1.2), (16.0, 9.0, 0.0), 3.6)
    for i, ((cx, cy), (rx, ry), top) in enumerate(KNOLL):
        m.terrace(f"Knoll_T{i + 1}", geo.ellipse(cx, cy, rx, ry, 28 - 4 * i), top=top,
                  bottom=-0.5 if i == 0 else KNOLL[i - 1][2] - 0.4)
    # flights: each tops out 0.5 m inside its tier's rim; west climbs east, east climbs west
    flights = {}
    for side, sname in ((-1, "W"), (1, "E")):
        for i, (ly, w) in enumerate(LANES):
            z0 = 0.0 if i == 0 else KNOLL[i - 1][2]
            z1 = KNOLL[i][2]
            x1 = knoll_edge(i, ly, side) - side * 0.5
            run = (2.9, 2.2, 2.0)[i]
            x0 = x1 + side * run
            m.stairs(f"Knoll_{sname}_{i + 1}", (x0, ly, z0), (x1, ly, z1), w, mat="M_StoneWall", side_mat="M_Rock",
                     stringers=False)
            flights[(sname, i)] = (x0, x1, ly)
    m.path("Main_Road", [(1, 10), (12, 9), (17, 9), (20.0, 9.4), (22.2, 9.6)], **MAIN_ROAD)
    m.path("Main_Road_Meadow", [(45.8, 9.8), (52, 11.5), (63, 12)], **MAIN_ROAD)

    # ---------------- low band ----------------
    m.terrace("RockShelf", geo.rounded_rect(50, 17.5, 60, 23.5, 1.5), top=4.0, bottom=-0.5, style="grass_rock")
    m.ladder("Ladder_Shelf", 54.5, 16.8, 0.0, 4.0, facing=90)

    # ---------------- mid band ----------------
    m.terrace("WestRidge", [(-1, 17.5), (19, 18.0), (21, 22), (19, 27.5), (-1, 27.5)], top=5.6, bottom=0.6)
    m.ramp("Ridge_Down", (18.5, 22.5, 5.6), (22.5, 22.5, MID), 3.0)
    # the central terrace runs back under the block staircase (a small courtyard at its foot)
    m.terrace("CentralTerrace", [(21, 18.2), (47, 18.0), (48, 23), (47, 28.5), (37.8, 28.6), (37.8, 35.8),
                                 (24.0, 35.8), (23.4, 28.5), (21, 28.5)], top=MID, bottom=-0.5)
    m.ladder("Ladder_Plateau_Ridge", 7.0, 17.1, 1.2, 5.6, facing=90)
    m.ladder("Ladder_Knoll_A", 32.6, 17.7, KNOLL[0][2], MID, facing=90)
    m.ladder("Ladder_Knoll_B", 35.6, 17.7, KNOLL[0][2], MID, facing=90)
    m.ladder("Vine_A", 39.5, 17.7, KNOLL[0][2], MID, kind="rope")
    m.ladder("Vine_B", 42.5, 17.7, 0.0, MID, kind="rope")
    # stacked boulders (T11/T9) up to the east terrace (T8)
    m.terrace("Boulder_1", geo.ellipse(49.5, 25.5, 2.3, 2.0, 16), top=5.3, bottom=MID - 0.6, style="grass_rock")
    m.terrace("EastTerrace", geo.rounded_rect(50.5, 24.5, 63.5, 31.5, 2.0), top=6.2, bottom=-0.5)
    m.ramp("Boulder_Step_A", (46.0, 25.5, MID), (48.0, 25.5, 5.3), 2.2, extend=0.3)
    m.ramp("Boulder_Step_B", (50.8, 26.5, 5.3), (52.5, 27.2, 6.2), 2.2, extend=0.3)

    # ---------------- upper band (back) ----------------
    # HighWest, with a lobe reaching east behind the first two blocks to meet block 3 (the T1 overhang)
    m.terrace("HighWest", [(-1, 27.0), (23, 27.5), (24.8, 31.0), (25.4, 34.0), (31.0, 34.0), (31.6, 33.5),
                           (33.8, 33.5), (34.2, 35.2), (37.4, 35.2), (37.4, 40.5), (-1, 40.5)], top=UPPER,
              bottom=MID - 0.5)
    # the trapezoid hump: a raised capsule with a grass slope at each end
    m.terrace("Hump", geo.rounded_rect(8.6, 32.9, 17.0, 37.3, 0.9), top=HUMP, bottom=UPPER - 0.4)
    m.ramp("Hump_W", (5.6, HUMP_Y, UPPER), (9.1, HUMP_Y, HUMP), 4.0, extend=0.3, top_mat="M_Grass", blend=False)
    m.ramp("Hump_E", (19.8, HUMP_Y, UPPER), (16.5, HUMP_Y, HUMP), 4.0, extend=0.3, top_mat="M_Grass", blend=False)
    # the islet T0: a tiny grass-capped island FLOATING ~2.5 m over HighWest, with a rocky inverted-cone underside
    # (like the island's own), reached by a rope hanging from its camera-facing +x lip
    m.terrace("Islet", geo.ellipse(ISLET_X, ISLET_Y, ISLET_R, ISLET_R * 0.94, 18), top=SPIRE, bottom=SPIRE - 0.75,
              style="grass_rock", fringe=True, stones=False, lip=0.16, cap_thickness=0.3, wobble_amt=0.12,
              resample_step=0.9)
    m.place("X40000_Islet_Root", ISLET_X, ISLET_Y, rot=20, z=SPIRE - 0.7)
    m.ladder("Rope_Spire", ISLET_X + ISLET_R + 0.35, ISLET_Y, UPPER, SPIRE, facing=180, kind="rope")
    m.ladder("Ladder_Ridge_High", 9.0, 27.0, 5.6, UPPER, facing=90)
    m.terrace("HighEast", [(37, 31.5), (64, 31.5), (64, 40.5), (37, 40.5)], top=HIGH_E, bottom=MID - 0.5)
    m.ladder("Ladder_East_High", 57.0, 31.2, 6.2, HIGH_E, facing=90)
    # the four-block staircase: grass-capped rock blocks stepping up the cliff corner
    for i, (x0, y0, x1, y1, top) in enumerate(BLOCKS):
        m.terrace(f"StairBlock_{i + 1}", geo.rounded_rect(x0, y0, x1, y1, 0.55), top=top, bottom=MID - 0.5,
                  style="grass_rock", wobble_amt=0.08, resample_step=0.8, smooth_iters=1, lip=0.18)
    steps_y = []
    for i in range(3):
        a, b = BLOCKS[i], BLOCKS[i + 1]
        y = (max(a[1], b[1]) + min(a[3], b[3])) / 2
        m.stairs(f"BlockSteps_{i + 1}", (a[2] - 0.6, y, a[4]), (b[0] + 0.4, y, b[4]), 1.4, mat="M_StoneWall",
                 side_mat="M_Rock", overshoot=0.5, stringers=False)
        steps_y.append(y)
    # rope x1530: up the first block's front (-y) face from the central terrace
    b1 = BLOCKS[0]
    rope_x = (b1[0] + b1[2]) / 2
    m.ladder("Rope_1530", rope_x, b1[1] - 0.3, MID, b1[4], facing=90, kind="rope")

    # ---------------- dressing ----------------
    dress(m)

    # ---------------- gameplay ----------------
    m.edge_portal("in00")
    m.edge_portal("east00")
    m.npc("Robin", 5.0, 12.8, rot=-30)
    m.player(32.6, 14.5, rot=-20)  # on the knoll top, beside the Main walk (Gameplay focus)
    m.mobs("Snail", geo.rect(16, 2, 26, 16), 3, seed=1)
    m.mobs("Snail", geo.rect(44, 2, 62, 16), 3, seed=2)
    m.mobs("Blue Snail", geo.ellipse(34, 12.5, 8, 5.5), 2, seed=3)
    m.mobs("Snail", geo.rect(22, 19, 46, 28), 2, seed=4)
    m.mobs("Blue Snail", geo.rect(0, 28, 23, 40), 2, seed=5, z_band=(UPPER - 0.1, HUMP + 0.1),
           avoid=[(ISLET_X, ISLET_Y, ISLET_R + 0.6)])  # not on (or under) the islet
    m.mobs("Blue Snail", geo.rect(38, 32, 63, 40), 2, seed=6)
    m.mobs("Snail", geo.rect(51, 25, 63, 31), 1, seed=7)
    # main road: plateau -> basin -> up the knoll's west flights -> over the top -> down the east flights -> meadow
    (w1x0, w1x1, ly1), (w2x0, w2x1, ly2), (w3x0, w3x1, ly3) = (flights[("W", i)] for i in range(3))
    (e1x0, e1x1, _), (e2x0, e2x1, _), (e3x0, e3x1, _) = (flights[("E", i)] for i in range(3))
    m.route("Main", [(1, 10), (11, 9), (16.5, 9), (20.5, 9.6), (w1x0 - 0.6, ly1), (w1x1 + 0.5, ly1),
                     (w2x0 - 0.2, ly2), (w2x1 + 0.5, ly2), (w3x0 - 0.2, ly3), (w3x1 + 0.5, ly3), (KX, 13.6),
                     (e3x1 - 0.5, ly3), (e3x0 + 0.2, ly3), (e2x1 - 0.5, ly2), (e2x0 + 0.2, ly2), (e1x1 - 0.5, ly1),
                     (e1x0 + 0.6, ly1), (47.5, 10.4), (52, 11.5), (63, 12)])
    # the valley floor around the knoll's front, off Main at the basin and back onto it in the meadow
    m.route("AroundKnoll", [(20.5, 9.6), (24, 6), (34, 4), (44, 6), (47.5, 10.4)])
    # the upper loop: off Main on the knoll's middle tier -> knoll ladder -> central terrace -> rope x1530 ->
    # the four blocks -> HighEast
    m.route("KnollLadder", [(w3x0 - 0.2, ly3), (28.8, 15.3), (29.6, 15.6), (31.6, 17.2), (32.6, 19.6), (31.0, 23.8),
                            (rope_x, 26.8)])
    s1, s2, s3 = steps_y
    m.route("FourBlocks", [(rope_x, 27.4), (rope_x, 30.2), (b1[2] - 0.9, s1), (BLOCKS[1][0] + 1.0, s1),
                           (BLOCKS[1][2] - 0.9, s2), (BLOCKS[2][0] + 1.0, s2), (BLOCKS[2][2] - 0.9, s3),
                           (BLOCKS[3][0] + 1.0, s3), (39.0, 33.8), (50, 35)])
    m.route("UpperWest", [(32.8, 32.4), (32.6, 35.0), (28.0, 36.4), (20.0, 35.0)])
    m.route("Hump", [(20.0, 35.0), (18.4, HUMP_Y), (12.0, HUMP_Y), (6.4, HUMP_Y), (5.0, HUMP_Y)])
    # the west ladders: off Main on the entry plateau, up to the ridge and HighWest, round to the hump's west foot
    m.route("WestLadders", [(11, 9), (7.6, 13.4), (7.0, 15.8), (7.0, 18.6), (8.0, 22.0), (9.0, 25.8), (9.0, 28.6),
                            (9.8, 31.6), (5.0, 32.9), (5.0, HUMP_Y)])
    # the floating islet: up the rope from HighWest onto it (no route walks under it)
    m.route("Islet", [(9.8, 31.6), (9.4, ISLET_Y), (ISLET_X + 0.4, ISLET_Y), (ISLET_X - 0.3, ISLET_Y - 0.5)])


def dress(m):
    autumn = ["Tree_Birch_Orange", "Tree_Birch_Yellow", "Tree_Autumn_A"]
    # back row thinned to the two back corners (the high terraces must read), plus the side frames
    for i, (x, y, s) in enumerate([(2.0, 39.0, 0.8), (61.5, 38.6, 0.8), (62.5, 29.5, 0.95), (1.0, 25.5, 1.0),
                                   (46, 27.5, 0.95), (24, 19.5, 1.03)]):
        m.place(autumn[i % 3], x, y, rot=i * 47, scale=s)
    for i, (x, y) in enumerate([(14, 15.5), (16.8, 2.4), (47, 3), (58, 4), (62, 18), (28.5, 21.5), (44.5, 22.5),
                                (6, 21.5), (15, 21.5)]):
        if (x, y) == (28.5, 21.5):
            continue  # (the red birch stands there now)
        m.place(["Bush_A", "Bush_B", "Bush_C"][i % 3], x, y, rot=i * 33)
    m.place("Rock_B", 23.0, 3.0, rot=30)
    m.place("Rock_A", 46.0, 6.0)
    m.place("Rock_Boulder", 56.0, 4.5, rot=80, scale=0.7)
    # the front valley's autumn trees (classic minimap): a yellow birch cluster on the west plateau behind Robin,
    # a yellow birch in the basin, a sapling at the knoll's east foot, a big orange tree framing east00
    for a, x, y, sc in [("Tree_Birch_Yellow", 1.8, 15.2, 1.0), ("Tree_Birch_Yellow", 4.2, 16.3, 0.85),
                        ("Tree_Birch_Yellow", 9.6, 15.6, 0.95), ("Tree_Sapling_A", 1.6, 6.4, 1.0),
                        ("Tree_Birch_Yellow", 19.5, 3.8, 1.05), ("Tree_Sapling_A", 45.0, 3.2, 1.0),
                        ("Tree_Birch_Orange", 59.0, 7.2, 1.3)]:
        m.place(a, x, y, rot=x * 37 % 360, scale=sc)
    m.place("Bush_B", 61.6, 8.4, rot=30)
    # the islet: a sapling and a flower tuft on top
    m.place("Tree_Sapling_A", ISLET_X - 0.9, ISLET_Y + 1.15, rot=40, scale=0.65)
    m.place("Flower_Patch_A", ISLET_X + 0.7, ISLET_Y + 0.8, rot=10)
    m.place("Stump_A", 19.0, 14.0)
    m.place("Log_A", 54.0, 28.0, rot=15)
    m.place("Sign_Board", 3.0, 4.5, rot=-25)
    m.place("Sign_Arrow", 60.0, 15.5, rot=0)
    # central terrace (T10): the red-leaf birch and a bush pair, flowers, off the upper-loop walk
    m.place("Tree_Birch_Red", 28.4, 21.0, rot=40, scale=0.95)
    m.place("Bush_B", 32.2, 26.6, rot=20)
    m.place("Bush_A", 33.4, 25.4, rot=80, scale=0.85)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Sunflower_Patch"], geo.rect(22, 19, 46, 28), 7, seed=11,
              min_dist=1.8, z_band=(MID - 0.1, MID + 0.1),
              avoid=[geo.rect(30, 16, 35, 25), geo.rect(24, 22, 32, 28.5), geo.rect(37, 17, 44, 21)])
    # the high terraces: hump flowers, a mushroom cluster on the lobe, bushes, a stump
    m.place("Mushroom_Cluster_A", 30.4, 38.4, rot=-30)
    m.place("Bush_A", 22.6, 38.8, rot=10)
    m.place("Bush_C", 12.0, 38.6, rot=60)
    m.place("Bush_B", 44.0, 38.8, rot=30)
    m.place("Bush_A", 52.0, 38.4, rot=70)
    m.place("Stump_A", 26.4, 38.6, rot=15, scale=0.8)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B"], geo.rect(9.0, 33.0, 16.5, 37.0), 3, seed=12, min_dist=1.6,
              z_band=(HUMP - 0.1, HUMP + 0.1), avoid=[geo.rect(7, HUMP_Y - 0.9, 18, HUMP_Y + 0.9)])
    # stones bedded in the blocks' camera-facing faces and at their feet
    for i, (x0, y0, x1, y1, top) in enumerate(BLOCKS):
        m.place("Rock_Cliff_Stone", x0 + 0.9 + (i % 2) * 0.8, y0 + 0.06, z=MID + 1.0 + (i % 3) * 0.5)
    m.place("Rock_C", 29.6, 29.4, rot=20)
    m.place("Rock_A", 35.4, 31.2, rot=60, scale=0.8)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 64, 40), 40, seed=5, min_dist=2.0,
              avoid=[geo.rect(0, 7.5, 64, 15.5), geo.rect(22, 18, 40, 36), geo.rect(4, 29, 20, 37),
                     (ISLET_X, ISLET_Y, ISLET_R + 0.8)])
