"""West Entrance to Mushroom Town (0) - "the hamlet on the hill", the very first map.

Classic (GMS v8) structure, from docs/research/maps/0_WestEntranceMushroomTown_0.md:
  T1 high west plateau (spawn, the orange yellow-spotted mushroom house, barrels,
  Heena standing on top of a big bush) -> T2 / T3 two 60 px grass steps down ->
  T4 sunken lane running east to out00; T5 the laundry bluff behind the lane, reached
  by one ladder, where Sera hangs her neverending laundry. No monsters (town).

3D translation: the plateau fills the back-west of the map; the two steps curl around
its south-east corner (east, then south, then east again) so the descent reads as a
terraced slope instead of a straight staircase. The lane runs along the front-east,
the laundry bluff rises behind it with its ladder face toward the camera.
"""

import math

from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.mapkit import MAIN_ROAD

MAP_ID = 0
GAMEPLAY_FOCUS = (14.0, 14.5)
GAMEPLAY_SCALE = 30.0

U = 0.8  # one 60 px MapleStory step
PLATEAU = 3 * U  # T1
STEP2 = 2 * U  # T2
STEP3 = 1 * U  # T3
BLUFF = 4 * U  # T5


# ---------------------------------------------------------------- local assets
@asset("X0_HeenaBush", "Foliage", footprint=3.4, tags=("bush", "landmark"))
def _heena_bush(coll):
    """Big round bush whose flattened crown carries Heena's little grass clump."""
    mb = MeshBuilder()
    mb.sphere(1.45, loc=(0, 0, 0.75), scale=(1.15, 1.05, 0.62), mat="M_Bush", subdiv=3, lumpy=0.12, seed=3,
              flatten_bottom=0.5)
    for k in range(7):
        a = 2 * math.pi * k / 7 + 0.3
        rr = 0.62 + 0.12 * (k % 3)
        mb.sphere(rr, loc=(math.cos(a) * 1.25, math.sin(a) * 1.1, 0.45 + 0.15 * (k % 2)), scale=(1, 1, 0.85),
                  mat="M_Bush", subdiv=2, lumpy=0.15, seed=10 + k, flatten_bottom=0.5)
    for k in range(5):
        a = 2 * math.pi * k / 5 + 1.0
        mb.sphere(0.5, loc=(math.cos(a) * 0.7, math.sin(a) * 0.6, 1.05), scale=(1, 1, 0.7), mat="M_Bush",
                  subdiv=2, lumpy=0.12, seed=30 + k)
    mb.build("X0_HeenaBush", coll, smooth=True, sharp_angle=80)


@asset("X0_BerryBush", "Foliage", footprint=1.8, tags=("bush",))
def _berry_bush(coll):
    """Low red-berry shrub row (the bush at the east end of Sera's bluff)."""
    mb = MeshBuilder()
    for k, (x, y, r) in enumerate(((-0.7, 0.0, 0.55), (0.0, 0.1, 0.68), (0.72, -0.05, 0.52))):
        mb.sphere(r, loc=(x, y, r * 0.6), scale=(1.1, 1.0, 0.85), mat="M_Leaf_B", subdiv=2, lumpy=0.15, seed=k,
                  flatten_bottom=0.5)
    mb.build("X0_BerryBush", coll, smooth=True, sharp_angle=80)
    be = MeshBuilder()
    pts = [(-0.9, -0.35, 0.55), (-0.5, -0.45, 0.75), (-0.2, -0.5, 0.4), (0.15, -0.55, 0.85), (0.4, -0.45, 0.55),
           (0.8, -0.4, 0.7), (1.0, -0.2, 0.4), (-0.3, -0.3, 1.05), (0.3, -0.2, 1.1), (-0.75, 0.0, 0.85),
           (0.6, 0.0, 0.95), (0.05, -0.05, 1.25)]
    for p in pts:
        be.sphere(0.09, loc=p, mat="M_Flat_cloth_red", subdiv=1)
    be.build("X0_BerryBush_Berries", coll, smooth=True)


@asset("X0_LaundryBasket", "Props", footprint=0.8, tags=("prop",))
def _laundry_basket(coll):
    """Wicker basket heaped with washing (Sera's neverending pile)."""
    mb = MeshBuilder()
    mb.cyl(0.38, 0.42, mat="M_Flat_wood_lt", verts=14, r2=0.46)
    for z in (0.12, 0.28):
        mb.torus(0.43 + z * 0.15, 0.03, loc=(0, 0, z), mat="M_Flat_wood", u=16, v=4)
    mb.torus(0.47, 0.05, loc=(0, 0, 0.42), mat="M_Flat_wood", u=16, v=4)
    mb.sphere(0.3, loc=(-0.1, 0.05, 0.45), scale=(1.2, 1.0, 0.6), mat="M_Cloth_White", subdiv=2, lumpy=0.2, seed=2)
    mb.sphere(0.22, loc=(0.18, -0.08, 0.5), scale=(1.1, 1.0, 0.6), mat="M_Flat_flower_pink", subdiv=2, lumpy=0.2,
              seed=4)
    mb.sphere(0.18, loc=(0.05, 0.2, 0.55), scale=(1.1, 1.0, 0.6), mat="M_Flat_roof_blue", subdiv=2, lumpy=0.2, seed=5)
    mb.build("X0_LaundryBasket", coll, smooth=True, sharp_angle=50)


@asset("X0_Washtub", "Props", footprint=1.0, tags=("prop",))
def _washtub(coll):
    """Wooden washtub with soapy water and a washboard leaning in it."""
    mb = MeshBuilder()
    mb.cyl(0.42, 0.45, mat="M_Wood", verts=16, r2=0.5)
    for z in (0.1, 0.36):
        mb.cyl(0.47 + z * 0.15, 0.05, loc=(0, 0, z), mat="M_Metal", verts=16)
    mb.cyl(0.44, 0.03, loc=(0, 0, 0.4), mat="M_Water", verts=16)
    for k in range(5):
        a = 2 * math.pi * k / 5
        mb.sphere(0.07, loc=(math.cos(a) * 0.25, math.sin(a) * 0.2, 0.45), mat="M_Foam", subdiv=1)
    mb.box((0.36, 0.05, 0.62), loc=(0.15, 0.22, 0.5), rot=(-18, 0, 0), mat="M_Plank")
    for k in range(5):
        mb.box((0.3, 0.03, 0.03), loc=(0.15, 0.19 - k * 0.0, 0.32 + k * 0.08), rot=(-18, 0, 0), mat="M_Wood_Dark")
    mb.build("X0_Washtub", coll, smooth=True, sharp_angle=45)


# ---------------------------------------------------------------- helpers
def _flight_ends(m, inside, climb, z_lo, z_hi, width, n=5, depth=0.42):
    """Ends (p0, p1) of a stone flight of n steps climbing along `climb` onto the terrace that contains
    `inside`. The top step sits just inside the upper cap's real (wobbled) edge, so every lower step stands
    clear of the cap lip and the flight reads as steps, not as a slab under a grass band."""
    cx, cy = climb
    best = None
    for off in (-0.5 * width, 0.0, 0.5 * width):
        sx, sy = inside[0] - cy * off, inside[1] + cx * off
        e = m.face_point(sx, sy, -cx, -cy)
        if e is None:
            continue
        proj = e[0] * cx + e[1] * cy  # the most-protruding edge sample wins (lower steps clear the lip)
        if best is None or proj < best:
            best = proj
    ix, iy = inside
    t = (best - (ix * cx + iy * cy)) if best is not None else -2.0
    ex, ey = ix + cx * t, iy + cy * t  # edge point on the flight's centreline
    p1 = (ex + cx * (depth - 0.1), ey + cy * (depth - 0.1), z_hi)
    p0 = (p1[0] - cx * n * depth, p1[1] - cy * n * depth, z_lo)
    return p0, p1


# ---------------------------------------------------------------- the map
def build(m):
    L, D = m.size  # 32 x 28

    # ---------------- terrain ----------------
    # T1: the spawn plateau (back-west), the house sits on its north edge
    plateau = [(-0.6, 8.6), (6.0, 7.8), (11.5, 8.3), (13.8, 10.5), (14.2, 16.0), (13.6, 22.5), (12.8, 28.6),
               (-0.6, 28.6)]
    m.terrace("Plateau_T1", plateau, top=PLATEAU, bottom=-0.5)
    # T2: first step, curls around the plateau's east side and runs under the bluff
    # (runs all the way to the back edge so there is no pit between the plateau, T2 and the bluff)
    m.terrace("Step_T2", [(12.4, 9.8), (17.6, 9.4), (19.6, 12.6), (21.6, 15.4), (22.0, 24.5), (21.0, 28.6),
                          (13.0, 28.6), (12.4, 23.0)], top=STEP2, bottom=-0.5)
    # T3: second step, south of T2 (in front of the plateau's corner)
    m.terrace("Step_T3", [(10.6, 3.2), (17.0, 2.4), (20.6, 3.6), (21.6, 7.0), (20.6, 11.6), (16.0, 11.8),
                          (11.0, 10.0)], top=STEP3, bottom=-0.5)
    # T5: the laundry bluff behind the lane (its south face carries the ladder)
    m.terrace("Bluff_T5", [(20.2, 15.4), (23.0, 14.7), (29.0, 14.6), (32.6, 15.0), (32.6, 28.6), (20.6, 28.6),
                           (19.8, 22.0)], top=BLUFF, bottom=-0.5)

    # the three-step descent: narrow flights of five shallow stone steps, each set just inside the real
    # cap edge of the tier above. Paths and flights are interleaved bottom-up so each ribbon runs UNDER
    # the foot of the flight below it (laid before that flight exists) and drapes OVER the top landing of
    # the flight above it (laid after): one continuous dirt trail from the spawn down to out00
    # the trail is the island's Main road (pale cream, MAIN_ROAD material); the stone flights stay as they are
    stone = dict(mat="M_StoneWall", side_mat="M_Rock", step_h=0.16)
    road = MAIN_ROAD["mat"]
    a0, a1 = _flight_ends(m, (12.2, 14.2), (-1, 0), STEP2, PLATEAU, 2.4)  # T2 -> T1, climbing west
    b0, b1 = _flight_ends(m, (16.4, 11.6), (0, 1), STEP3, STEP2, 2.4)  # T3 -> T2, climbing north
    c0, c1 = _flight_ends(m, (19.4, 6.4), (-1, 0), 0.0, STEP3, 2.4)  # lane -> T3, climbing west
    m.path("Main_Road", [(c0[0] - 0.3, 6.4), (c0[0] + 0.9, 6.5), (26.0, 7.4), (28.5, 9.2), (31.5, 10.0)],
           mat=road, width=3.4)
    m.stairs("Steps_T3_T4", c0, c1, 2.4, **stone)
    m.path("Main_Road_T3", [(b0[0], b0[1] + 0.25), (17.4, b0[1] - 1.0), (19.4, 6.4), (c1[0], 6.4)], mat=road,
           width=2.6)
    m.stairs("Steps_T2_T3", b0, b1, 2.4, **stone)
    m.path("Main_Road_T2", [(a0[0] - 0.3, 14.2), (a0[0] + 0.7, 13.5), (16.7, 12.0), (b1[0], b1[1])], mat=road,
           width=2.6)
    m.stairs("Steps_T1_T2", a0, a1, 2.4, **stone)
    m.path("Main_Road_Plateau", [(2.5, 12.6), (6.5, 13.4), (10.0, 13.8), (12.0, 14.2), (a1[0], 14.2)], mat=road,
           width=3.0)
    m.path("Door_Path", [(7.5, 13.3), (8.3, 16.2), (8.9, 18.9)], width=1.8)
    m.path("Ladder_Path", [(25.4, 8.0), (26.0, 11.0), (26.0, 13.4)], width=1.8)
    m.ladder("Ladder_Bluff", 26.0, 14.0, 0.0, BLUFF, facing=90)
    # stair cheeks: a rock at the cliff foot and a tuft of flowers beside each flight
    for (a, x, y, r, sc) in (("Rock_A", 14.7, 12.2, 30, 0.7), ("Flower_Patch_A", 15.2, 16.0, 0, 1.0),
                             ("Rock_B", 14.7, 8.7, 60, 0.75), ("Flower_Patch_B", 18.0, 8.9, 20, 1.0),
                             ("Rock_C", 22.4, 8.1, 10, 0.8), ("Flower_Patch_A", 22.2, 4.7, 40, 1.0)):
        m.place(a, x, y, rot=r, scale=sc)

    # ---------------- landmarks ----------------
    # the orange mushroom house with yellow spots (barrels + lantern built in), door toward the spawn
    # scaled 1.2 so it reads from the island cameras; set 0.4 m back so the door stays where the door path ends
    m.place("House_Mushroom_OrangeSpotted", 8.0, 22.0, rot=20, scale=1.2)
    m.place("Barrel", 11.6, 19.0, rot=30)
    # Heena's big bush, right above the spawn; a little grass clump crowns it and she stands there
    hx, hy = 2.8, 16.2
    m.place("X0_HeenaBush", hx, hy, rot=10)
    m.terrace("HeenaClump", geo.ellipse(hx, hy, 0.95, 0.85, 14), top=PLATEAU + 2 * U, bottom=PLATEAU + 1.35,
              wobble_amt=0.1)
    m.npc("Heena", hx, hy, rot=25)
    # the laundry bluff: clothesline, basket, Sera, red-berry shrubs, a butterfly on the post
    m.place("Clothesline_Laundry", 27.6, 17.4, rot=0)
    # the basket stands on Sera's west side: at (24.6, 16.5) it sat on the BluffLadder walk to her (the route
    # brushed its rim, so the export had to collide it as an exact mesh the player clipped through)
    m.place("X0_LaundryBasket", 22.6, 16.4, rot=20)
    m.npc("Sera", 23.6, 17.6, rot=15)
    m.place("X0_BerryBush", 31.0, 18.8, rot=-10)
    m.place("X0_BerryBush", 30.6, 25.5, rot=40, scale=0.9)
    m.place("Butterfly_Yellow", 29.75, 17.4, z=BLUFF + 0.72, rot=-20)  # perched on the east post top
    m.place("X0_Washtub", 22.4, 19.2, rot=10)
    m.place("Clothesline_Laundry", 26.4, 22.6, rot=8, scale=(0.85, 1, 1))
    m.place("X0_LaundryBasket", 29.4, 22.0, rot=-30, scale=0.9)
    m.place("Tree_Sapling_A", 21.6, 24.6, rot=30)
    m.place("Bush_Flowering_A", 31.4, 21.6, rot=0, scale=0.9)
    m.place("Mushroom_Orange_S", 23.0, 25.8, rot=0)
    m.place("Mushroom_Blue_S", 23.6, 26.3, rot=40, scale=0.9)
    # the long first step under the bluff: a little orchard corner
    m.place("Tree_Round_C", 15.6, 22.6, rot=70, scale=0.85)
    m.place("Bush_A", 18.4, 23.6, rot=10)
    m.place("Mushroom_Cluster_A", 14.4, 19.6, rot=-30, scale=0.9)
    m.place("Stump_A", 18.2, 18.6, rot=30, scale=0.8)
    m.place("Butterfly", 17.0, 20.2)
    m.place("Lamp_Post", 29.6, 13.0, rot=200)
    m.place("Sign_Arrow", 28.2, 5.0, rot=10)  # "to Mushroom Town"
    # row of four colored mushrooms at the cliff foot, "climb here"
    m.place("Mushroom_Cluster_A", 23.6, 13.2, rot=0)
    # amanitas, tiny mushrooms and bushes at the foot of the steps
    m.place("Mushroom_Red_S", 22.3, 3.4, rot=10)
    m.place("Mushroom_Red_S", 22.9, 2.6, rot=60, scale=1.2)
    m.place("Mushroom_Red_S", 21.7, 2.3, rot=-30, scale=0.85)
    m.place("Mushroom_Yellow_S", 23.6, 3.2, rot=0, scale=0.7)
    m.place("Bush_B", 19.6, 13.2, rot=20)
    m.place("Bush_A", 24.2, 2.2, rot=50)

    # ---------------- dressing ----------------
    # back + west frame (no west exit: this is where new characters appear)
    m.place("Tree_Giant_A", 0.8, 27.2, rot=40, scale=0.62)
    m.place("Tree_Round_B", 13.0, 27.0, rot=120, scale=0.9)
    m.place("Tree_Round_A", 22.0, 27.6, rot=200, scale=0.85)
    m.place("Tree_Round_C", 31.4, 27.6, rot=10, scale=0.9)
    m.place("Tree_Round_C", 0.4, 10.0, rot=80, scale=0.8)
    for i, (x, y) in enumerate([(0.3, 13.5), (0.4, 20.5), (0.6, 23.5), (4.0, 27.6), (17.0, 26.0), (26.5, 27.8)]):
        m.place(["Bush_A", "Bush_B", "Bush_C"][i % 3], x, y, rot=i * 47)
    m.place("Lamp_Post", 11.3, 17.4, rot=200)
    m.place("Sign_Board", 12.0, 10.2, rot=15)
    m.place("Bench", 3.6, 22.8, rot=40)
    m.place("Flower_Bed_Large", 11.5, 24.6, rot=20, scale=0.8)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 9, 13.5, 27), 12, seed=1,
              min_dist=1.6, avoid=[geo.rect(1.5, 11.2, 14, 15.4), (8.0, 22.0, 4.8), (hx, hy, 2.0),
                                   geo.rect(7, 15, 9.8, 19)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A"], geo.rect(21, 15.5, 32, 28), 8, seed=2, min_dist=1.6,
              avoid=[geo.rect(23, 16, 32, 18.6), (26.0, 16.0, 1.4), geo.rect(22, 21.4, 31, 23.8), (22.4, 19.2, 1.0)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_B"], geo.rect(13, 10, 21, 28), 5, seed=3, min_dist=1.5,
              avoid=[geo.rect(14, 10, 18.5, 15.5), (15.6, 22.6, 1.6), (17.0, 26.0, 1.4), (18.4, 23.6, 1.2)])
    # front meadow below the plateau: rocks at the cliff foot, flowers, a low picket fence
    m.place("Rock_B", 2.6, 6.8, rot=30)
    m.place("Rock_A", 8.4, 6.6, rot=70)
    m.place("Stump_A", 5.6, 4.0, rot=20)
    m.place("Bush_Flowering_A", 1.0, 2.6, rot=0)
    m.place("Butterfly", 3.6, 3.2)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A"], geo.rect(0.5, 0.5, 10.5, 7.0), 9, seed=4,
              min_dist=1.4)
    m.scatter(["Flower_Patch_A", "Grass_Tuft_A", "Flower_Patch_B"], geo.rect(18, 0.5, 31.5, 13.5), 9, seed=5,
              min_dist=1.6, avoid=[geo.rect(21, 5, 32, 11.2), geo.rect(24.5, 8, 27.5, 14.5), geo.rect(18, 0, 32, 1.7)])
    m.fence([(0.4, 0.6), (10.0, 0.6), (16.5, 0.8)], asset_name="Fence_Picket_Seg")
    # the lane's south side: a low hedge bank so the lane reads as a hollow at the bluff's foot
    for hx0 in (19.6, 23.6, 27.6):
        m.place("Hedge_Wall_4m", hx0, 0.8, rot=0)
    m.place("Bush_B", 18.0, 0.8, rot=10)
    m.place("Rock_C", 30.4, 13.6, rot=0)
    m.place("Rock_A", 32.0, 13.2, rot=40, scale=0.8)
    # grey stones set into the visible dirt faces (classic grassySoil tiles)
    for (x, y, z) in [(3.0, 8.15, 1.2), (9.0, 7.75, 0.7), (18.2, 2.25, 0.35), (24.0, 14.45, 1.4),
                      (30.0, 14.45, 2.2), (28.0, 14.4, 0.6)]:
        m.place("Rock_Cliff_Stone", x, y, z=z, rot=0, scale=0.9)

    # ---------------- gameplay ----------------
    m.edge_portal("out00")
    m.player(4.0, 12.6, rot=20)  # new characters appear here, under Heena's bush
    m.player_spawn(4.0, 12.6, rot=20,
                   note="sp x -189: the west end below Heena (MeowDB's west half differs from v8; the tier and side "
                        "are kept)")
    m.route("Main", [(2.5, 12.6), (8.0, 13.6), (12.0, 14.2), (a1[0] - 0.4, 14.2), (a0[0] + 0.4, 14.2),
                     (a0[0] + 0.7, 13.5), (16.7, 12.0), (16.4, b1[1] + 0.4), (16.4, b0[1] - 0.4), (17.4, b0[1] - 1.0),
                     (19.4, 6.4), (c1[0] - 0.4, 6.4), (c0[0] + 0.4, 6.4), (26.5, 7.6), (31.0, 10.0)])
    m.route("ToHouseDoor", [(7.5, 13.4), (8.4, 17.0), (9.0, 18.5)])
    # lane -> up the bluff ladder -> Sera -> along the laundry lines (one route through the climb)
    m.route("BluffLadder", [(26.3, 7.5), (25.8, 8.5), (26.0, 11.0), (26.0, 13.3), (26.0, 15.6), (25.0, 16.8), (24.4, 17.8),
                            (27.6, 19.2), (30.0, 21.5)])
