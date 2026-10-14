"""Mushroom Town (20000) - "the town terrace", the second Mushroom Town screen.

Classic (GMS v8) structure, from docs/research/maps/20000_MushroomTown_20000.md:
  T1 low west lawn (arrival in00, clover) -> T2 one broad 60 px step -> T3 the long
  raised town terrace carrying the landmark pair: the orange two-storey mushroom house
  whose stone-arched door (in01) leads into Sen's house (20001), and the stone oven
  tower whose little door stands right behind the exit out00. Nina sits on a floating
  flower islet above the lawn (talked to from below); a tall ladder rises from the step
  to an empty sky islet. No monsters (town).

3D translation: everything steps up west -> east as in the original. The camera looks
from the south-east, so west-facing risers are back-faces: the readable climb is moved
onto the long south faces. The step wraps round the terrace's south-west corner like a
porch, and ONE double flight climbs verge -> porch -> street up those camera-facing faces
(the old west flights, whose risers faced away from the camera, are gone; their corner is
clover beds now).
Nina's islet becomes a mossy giant stump; the sky islet becomes the flat grass-crowned cap
of a giant red mushroom growing from the step, with the ladder hung from its rim.

Iteration Two: classic Nina is clicked from the lawn; the game talks to NPCs in person, so a wooden stair climbs the
stump's camera-facing side to her islet.
"""

import math

from misostory import collision_tags as CT
from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.classic import barrel_chimney
from misostory.mapkit import MAIN_ROAD

MAP_ID = 20000
GAMEPLAY_FOCUS = (27.0, 17.0)
GAMEPLAY_SCALE = 32.0

U = 1.0
STEP = 1 * U  # T2
STREET = 2 * U  # T3 (layout hint for out00: z = 2.0)
NINA = 2 * U  # T4 (120 px above the lawn)
NINA_STAIR_DEG = 313.0  # the stair up Nina's stump, map-local bearing from the stump centre (toward the camera)
SKY = 5 * U  # T5 (240 px above the step)


# ---------------------------------------------------------------- local assets
@asset("X20000_OvenTower", "Architecture", footprint=3.4, tags=("landmark",))
def _oven_tower(coll):
    """Tall stone oven/chimney tower: round stone base with a small dark arched door (-Y), a log pile
    strapped to its side and a wooden barrel flue on top (house/grassySoil/chimney/3)."""
    mb = MeshBuilder()
    mb.cyl(1.55, 0.35, mat="M_Rock", verts=20, r2=1.5)
    mb.cyl(1.45, 2.7, loc=(0, 0, 0.3), mat="M_StoneWall", verts=20, r2=1.3)
    mb.cyl(1.38, 0.28, loc=(0, 0, 2.85), mat="M_Rock", verts=20)
    mb.cyl(1.0, 2.1, loc=(0, 0, 3.1), mat="M_StoneWall", verts=16, r2=0.85)
    mb.cyl(0.95, 0.22, loc=(0, 0, 5.15), mat="M_Rock", verts=16)
    # little arched door
    mb.box((0.9, 0.3, 1.15), loc=(0, -1.3, 0.85), mat="M_Wood_Dark")
    mb.cyl(0.45, 0.3, loc=(0, -1.15, 1.42), rot=(90, 0, 0), mat="M_Wood_Dark", verts=14)
    mb.box((0.7, 0.3, 1.0), loc=(0, -1.36, 0.85), mat="M_Door")
    mb.cyl(0.35, 0.3, loc=(0, -1.21, 1.35), rot=(90, 0, 0), mat="M_Door", verts=14)
    mb.sphere(0.06, loc=(0.22, -1.53, 0.95), mat="M_Gold", subdiv=1)
    # small round window above the door
    mb.cyl(0.26, 0.2, loc=(0, -0.95, 3.9), rot=(90, 0, 0), mat="M_Wood_Dark", verts=12)
    mb.cyl(0.18, 0.22, loc=(0, -0.97, 3.9), rot=(90, 0, 0), mat="M_Glow_window", verts=12)
    mb.build("X20000_OvenTower", coll, smooth=True, sharp_angle=40)
    logs = MeshBuilder()
    for row, n in ((0, 3), (1, 2), (2, 1)):
        for k in range(n):
            y = -0.55 + k * 0.4 + row * 0.2
            z = 0.25 + row * 0.36
            logs.cyl(0.19, 1.1, loc=(1.35, y, z), rot=(0, 90, 0), mat="M_Bark", verts=9)
            logs.cyl(0.16, 0.02, loc=(1.9, y, z), rot=(0, 90, 0), mat="M_Flat_wood_lt", verts=9)
    logs.box((0.06, 1.3, 0.06), loc=(1.75, -0.15, 1.15), mat="M_Rope")
    barrel_chimney(logs, (0, 0, 5.3), lid="M_Flat_roof_red")
    logs.build("X20000_OvenTower_Logs", coll, smooth=True, sharp_angle=45)


# pack (#75, kit/landmark_aliases.py): the pack stone arch, fitted by its piers to these pillars' outer span (2.26 m),
# so the opening stays as wide as this one (inner faces ~0.75 m off centre) on the walk to in01.
@asset("X20000_StoneArch", "Architecture", footprint=2.2, tags=("door",),
       pack=dict(fit_nodes=(["Stone arch pier"], 2 * (0.95 + 0.18))))
def _stone_arch(coll):
    """Freestanding stone porch arch in front of a house door (door/grassySoil/door/8): faces -Y.
    Pillars at +-0.95 m (inner faces 0.77 m off centre, so a 1.3x arch leaves 1 m either side of the
    walk), a voussoir ring, a darker keystone, a threshold slab and a little lantern on each pillar."""
    mb = MeshBuilder()
    px, ph = 0.95, 1.75
    for x in (-px, px):
        mb.box((0.36, 0.42, ph), loc=(x, 0, ph / 2), mat="M_StoneWall", bevel=0.06)
        mb.box((0.48, 0.54, 0.16), loc=(x, 0, 0.08), mat="M_Rock", bevel=0.04)
    n = 9
    for k in range(n):
        a = math.pi * (k + 0.5) / n
        mb.box((0.42, 0.44, 0.34), loc=(math.cos(a) * px, 0, ph + math.sin(a) * px),
               rot=(0, -math.degrees(a) + 90, 0), mat="M_StoneWall", bevel=0.05)
    mb.box((0.38, 0.52, 0.34), loc=(0, -0.02, ph + px + 0.05), mat="M_Rock", bevel=0.06)
    mb.box((2.5, 0.9, 0.08), loc=(0, -0.2, 0.04), mat="M_StoneWall", bevel=0.03)
    mb.build("X20000_StoneArch", coll, smooth=True, sharp_angle=40)
    lt = MeshBuilder()
    for x in (-px, px):
        lt.box((0.2, 0.2, 0.26), loc=(x, -0.24, ph - 0.35), mat="M_Glow_window", bevel=0.03)
        lt.box((0.26, 0.26, 0.06), loc=(x, -0.24, ph - 0.2), mat="M_Wood_Dark")
    lt.build("X20000_StoneArch_Lamps", coll, smooth=False)


@asset("X20000_NinaStump", "Foliage", footprint=4.6, tags=("stump", "landmark"))
def _nina_stump(coll):
    """Giant mossy tree stump that carries Nina's flower islet (top at ~1.85 m). The trunk only: it collides as a
    prism of its own 2.25 m radius. The roots are a separate asset (X20000_NinaStumpRoots): in one asset their tips
    widened the stump's collision prism to a 3.8 m circle, an invisible ledge 1.5 m outside the bark that no stair to
    Nina could meet."""
    mb = MeshBuilder()
    mb.cyl(2.25, 1.9, mat="M_Bark", verts=20, r2=2.05)
    mb.build("X20000_NinaStump", coll, smooth=True, sharp_angle=45)


NINA_ROOT_ANGLES = tuple(2 * math.pi * k / 6 + 0.4 for k in range(6))  # stump-local, radians


@asset("X20000_NinaStumpRoots", "Foliage", footprint=4.6, tags=("stump", "collide_exact"))
def _nina_stump_roots(coll):
    """The six buttress roots spreading from Nina's stump (same frame as X20000_NinaStump), 1.1 m high at the bark
    and sloping into the lawn. They collide with their exact mesh (collide_exact): the player walks over a root, up its
    sloping side and along its ridge (about 0.65 m high mid-root), and is stopped by it only near the bark, where it
    rises higher, so the body never passes through one. (Passable, as a plain Foliage stump is, the body walked
    through them; as prisms, each root's flat top stood at the root's full 1.1 m over its low tip, and a player walking
    off Nina's stair sideways crossed a root on that invisible top.)"""
    mb = MeshBuilder()
    for a in NINA_ROOT_ANGLES:
        mb.cyl(0.75, 2.2, loc=(math.cos(a) * 1.6, math.sin(a) * 1.6, 0.35), rot=(0, 100, math.degrees(a)),
               mat="M_Bark", verts=8, r2=0.2)
    mb.build("X20000_NinaStumpRoots", coll, smooth=True, sharp_angle=45)


@asset("X20000_Tulips", "Foliage", footprint=1.2, tags=("flower",))
def _tulips(coll):
    """Little bed of orange tulip-like flowers (acc1/grassySoil/nature/5,6)."""
    mb = MeshBuilder()
    for k, (x, y, h) in enumerate(((-0.4, 0.0, 0.55), (-0.1, 0.2, 0.7), (0.2, -0.1, 0.6), (0.45, 0.15, 0.5),
                                   (0.05, -0.3, 0.45))):
        mb.cyl(0.025, h, loc=(x, y, 0), mat="M_Flat_grass_side", verts=5)
        mb.sphere(0.1, loc=(x + 0.07, y, h * 0.4), scale=(1.4, 0.4, 0.7), mat="M_Flat_leaf", subdiv=1)
        mb.cyl(0.08, 0.17, loc=(x, y, h), mat="M_Flat_roof_orange" if k % 2 == 0 else "M_Flat_flower_yellow",
               verts=8, r2=0.12)
    mb.build("X20000_Tulips", coll, smooth=True, sharp_angle=50)


# ---------------------------------------------------------------- helpers
def _sky_mushroom(m, cx, cy, base_z, cap_z, cap_r):
    """Giant red mushroom growing from the step; its cap is the walkable sky islet."""
    stalk = MeshBuilder()
    stalk.cyl(0.95, cap_z - 0.5 - base_z + 0.2, loc=m.w(cx, cy, base_z - 0.2), mat="M_MushStem", verts=16, r2=0.7)
    stalk.cyl(1.25, 0.4, loc=m.w(cx, cy, base_z - 0.15), mat="M_MushStem", verts=16, r2=0.95)
    stalk.cyl(0.95, 0.18, loc=m.w(cx, cy, cap_z - 1.5), mat="M_MushStem", verts=16, r2=1.1)
    CT.tag(stalk.build(f"{m.slug}_SkyMushroom_Stalk", m.col_arch, smooth=True, sharp_angle=50), CT.WALL)
    cap = MeshBuilder()
    cap.dome(cap_r, 0.75, loc=m.w(cx, cy, cap_z - 0.75), mat="M_Spot_mush_red__mush_spot", u=32, v=8, lip=0.45,
             profile=0.2)
    obj = cap.build(f"{m.slug}_SkyMushroom_Cap", m.col_terrain, smooth=True, sharp_angle=70)
    m.add_ground(obj)
    # a grassy crown on the flat cap, so it reads as the classic grass islet (not another house roof)
    m.terrace("SkyIslet_Grass", geo.ellipse(cx, cy, cap_r - 0.7, cap_r - 0.7, 18), top=cap_z + 0.05,
              bottom=cap_z - 0.35, wobble_amt=0.1)
    return obj


def _door_xy(cx, cy, rot, dist):
    a = math.radians(rot)
    return cx + math.sin(a) * dist, cy - math.cos(a) * dist


# ---------------------------------------------------------------- the map
def build(m):
    L, D = m.size  # 42 x 36

    # ---------------- terrain ----------------
    # T3: the town terrace (east, raised 2 m) - its long south face shows from the camera
    street = [(18.6, 9.6), (25.0, 9.0), (33.0, 8.4), (42.6, 8.8), (42.6, 36.6), (19.2, 36.6), (18.4, 24.0)]
    m.terrace("Street_T3", street, top=STREET, bottom=-0.5)
    # T2: the single broad step - west bench under the ladder + a porch round the terrace's SW corner
    step = [(13.4, 4.6), (21.0, 4.2), (26.6, 5.0), (27.4, 7.8), (25.6, 10.4), (20.0, 11.4), (20.2, 31.6),
            (16.8, 33.0), (13.4, 30.6)]
    m.terrace("Step_T2", step, top=STEP, bottom=-0.5)
    # the one climb: a double flight up the camera-facing south faces, verge -> porch -> street.
    # Paths and flights are interleaved bottom-up: each dirt ribbon runs UNDER the foot of the flight
    # above it (laid before that flight exists) and drapes OVER the landing of the flight below it
    # (laid after), so the trail flows unbroken from in00 up both flights onto the street.
    # in00 -> straight down the lawn round the step's corner to (under) the foot of the verge flight
    # (the trail is the island's Main road: pale cream MAIN_ROAD ribbons; the flights stay plank)
    road = MAIN_ROAD["mat"]
    m.path("Main_Road_Lawn", [(1.0, 14.0), (5.6, 12.8), (9.4, 9.6), (11.6, 5.8), (14.2, 3.0), (18.0, 1.7),
                              (21.4, 1.3), (23.0, 1.5), (23.0, 2.0)], mat=road, width=3.4)
    m.stairs("Steps_Verge_T2", (23.0, 1.6, 0.0), (23.0, 4.9, STEP), 2.6, step_h=0.2, fit_edge=True)
    # (fit_edge slides each flight so its top tread meets the real cap edge: the porch ribbon starts square
    # at the step edge and runs under the upper flight foot, the street ribbon starts square at the top)
    m.path("Main_Road_Porch", [(23.0, 4.4), (23.0, 5.4), (23.0, 6.4)], mat=road, width=2.6, smooth_iters=0,
           end_taper=1.0)
    m.stairs("Steps_Porch_T3", (23.0, 6.6, STEP), (23.0, 9.9, STREET), 2.6, step_h=0.2, fit_edge=True)
    m.path("Main_Road_Up", [(23.0, 9.1), (23.0, 11.2), (23.3, 13.6), (24.0, 16.6)], mat=road, width=2.8,
           end_taper=1.0)
    # T4: Nina's flower islet - a giant mossy stump above the north-west lawn
    nx, ny = 8.2, 25.2
    m.place("X20000_NinaStump", nx, ny, rot=20, z=-0.05)
    m.place("X20000_NinaStumpRoots", nx, ny, rot=20, z=-0.05)
    m.terrace("NinaIslet_T4", geo.ellipse(nx, ny, 2.15, 2.05, 18), top=NINA, bottom=1.45, wobble_amt=0.12)
    # Iteration Two talks to NPCs in person (the interact key, no click from the lawn), so a wooden stair climbs the
    # stump to Nina: 10 risers of 0.2 m (walked, never jumped), on the camera-facing side between two roots
    # (NINA_STAIR_DEG lies halfway between the roots at 283 and 343 degrees: root angles + the stump's 20 degree yaw)
    sa = math.radians(NINA_STAIR_DEG)
    sux, suy = math.cos(sa), math.sin(sa)
    m.stairs("Steps_NinaStump", (nx + sux * 4.8, ny + suy * 4.8, 0.0), (nx + sux * 2.0, ny + suy * 2.0, NINA), 1.2,
             step_h=0.2, fit_edge=True)
    # T5: the sky islet - cap of a giant red mushroom on the step, ladder hung from its rim
    sx, sy, sr = 17.0, 27.4, 3.0
    _sky_mushroom(m, sx, sy, STEP, SKY, sr)
    m.ladder("Ladder_Sky", sx, sy - sr - 0.25, STEP, SKY + 0.05, facing=90)
    m.place("Grass_Tuft_A", sx + 0.8, sy + 0.6)

    # paths
    m.path("Main_Road", [(22.8, 16.4), (24.0, 16.6), (30.0, 17.4), (36.0, 18.0), (41.6, 18.0)], **MAIN_ROAD)
    # Sen's house, scaled 1.3 for the island read: stem front ~2.76 m, cap lip ring ~4.8 m from its centre.
    # The door walk runs straight up the door axis from the street, through a freestanding stone porch arch
    # standing at the cap rim (5.0 m: its keystone stays below the lip line seen from the 40 deg camera), to
    # the in01 threshold just outside the stone base ring (3.6 m)
    hx, hy, hrot = 29.6, 26.8, 22.0
    dx, dy = _door_xy(hx, hy, hrot, 3.6)
    ax, ay = _door_xy(hx, hy, hrot, 5.0)
    sx0, sy0 = _door_xy(hx, hy, hrot, 9.5)  # on the street (Main)
    mx, my = _door_xy(hx, hy, hrot, 7.6)
    ex, ey = _door_xy(hx, hy, hrot, 3.1)  # tucks under the stone base ring at the door
    m.path("Door_Path", [(sx0, sy0), (mx, my), (ax, ay), (ex, ey)], width=1.8)

    # ---------------- landmarks ----------------
    # the orange two-storey mushroom house (Sen's house) with a stone-arched door: in01 -> 20001
    m.place("House_Mushroom_OrangeOven", hx, hy, rot=hrot, scale=1.3)
    m.place("X20000_StoneArch", ax, ay, rot=hrot, scale=1.3)
    m.door_portal("in01", dx, dy, rot=hrot)
    m.place("Mushroom_Red_S", 34.4, 23.6, rot=0, scale=1.3)
    m.place("Mushroom_Red_S", 35.2, 24.4, rot=50, scale=1.0)
    m.place("Mushroom_Orange_S", 33.8, 24.6, rot=10)
    # the stone oven tower beside the house; its little door stands right behind out00
    # (scaled up so it stands as tall as the house: the classic landmark pair)
    m.place("X20000_OvenTower", 39.6, 21.8, rot=18, scale=1.25)
    m.place("Bush_B", 41.0, 26.6, rot=30)  # olive bush at the east end
    m.place("Bush_A", 41.6, 13.0, rot=10)
    # Nina on her flower islet, a dark bush, tulips and a butterfly
    m.npc("Nina", nx + 0.3, ny - 0.4, rot=40)
    m.place("Bush_B", nx - 1.0, ny + 0.7, rot=0, scale=0.8)
    m.place("X20000_Tulips", nx + 1.0, ny + 0.6, rot=20)
    m.place("X20000_Tulips", nx - 0.9, ny - 0.8, rot=-40, scale=0.85)
    m.place("Butterfly", nx + 1.4, ny - 1.0)
    m.place("Vine_Hanging_A", nx + 0.2, ny - 2.15, z=NINA - 0.2, rot=0)
    m.place("Vine_Hanging_A", nx - 1.6, ny - 1.4, z=NINA - 0.2, rot=-40)  # (was over the stair head)

    # neighbours at the back of the pocket (classic world map shows several mushroom roofs)
    m.place("House_Mushroom_BlueCone", 38.0, 31.6, rot=30, scale=1.35)
    m.place("Tree_Round_B", 24.0, 34.8, rot=150, scale=0.9)

    # ---------------- dressing ----------------
    # street furniture
    for x, y in ((22.6, 19.6), (29.6, 19.2)):  # (clear of the porch arch: the door walk runs between them)
        m.place("Lamp_Post", x, y, rot=200)
    m.place("Bench", 25.0, 21.0, rot=200)
    m.place("Sign_Board", 19.6, 3.1, rot=8)  # at the foot of the climb, under the step face
    m.place("Barrel", 36.2, 22.4, rot=10)
    m.place("Crate", 37.2, 23.0, rot=25)
    m.place("Sack", 36.8, 21.6, rot=0)
    m.place("Flower_Bed_Large", 26.6, 22.6, rot=20, scale=0.8)
    m.place("X20000_Tulips", 21.4, 29.2, rot=0)
    m.place("Bush_A", 20.8, 31.2, rot=40)
    m.place("Butterfly", 22.0, 28.4)
    m.fence([(26.8, 10.4), (33.0, 9.8), (41.8, 10.0)], )
    # the freed west corner (where the hidden-riser flights were): clover beds and flowers on lawn and step
    for (x, y, r) in ((10.6, 13.4, 20), (12.0, 16.6, 70), (9.4, 16.0, 0), (14.2, 14.6, 40), (17.6, 15.8, 10),
                      (14.2, 17.6, 80), (18.0, 12.4, 30)):
        m.place("Clover_Patch", x, y, rot=r)
    m.place("X20000_Tulips", 17.6, 13.9, rot=10)
    m.place("X20000_Tulips", 11.4, 15.0, rot=60, scale=0.9)
    m.place("Bush_Flowering_A", 19.0, 14.6, rot=20, scale=0.8)
    m.place("Butterfly_Pink", 13.0, 15.0)
    # the v8 object list just west of the house: orange flowers, a green bush and a butterfly
    for (x, y, r) in ((23.2, 22.6, 0), (24.4, 24.6, 40), (22.6, 25.4, -30)):
        m.place("X20000_Tulips", x, y, rot=r)
    m.place("Bush_A", 21.6, 23.6, rot=20)
    m.place("Butterfly", 23.8, 23.8)
    m.place("Bush_C", 31.6, 31.8, rot=10)
    m.place("X20000_Tulips", 34.2, 27.6, rot=0)
    m.place("Clover_Patch", 35.4, 29.2, rot=40)
    # firewood for the oven, stacked by the tower
    m.place("Log_A", 36.2, 25.9, rot=15)
    m.place("Crate_Stack", 42.0, 24.2, rot=10, scale=0.8)
    # shrubs and mushrooms at the foot of the terrace face, sunflowers round the arrival lawn
    for i, (x, y) in enumerate([(28.4, 7.4), (35.0, 7.2), (39.6, 7.6), (17.6, 3.9)]):
        m.place(["Bush_A", "Bush_C", "Bush_B", "Bush_C"][i], x, y, rot=i * 50)
    m.place("Mushroom_Cluster_A", 31.8, 7.4, rot=10)
    m.place("Mushroom_Red_S", 26.0, 3.2, rot=0)
    # the front verge under the terrace face: low flower beds, tulips and a sunflower clump (front band: low)
    for (x, y, r, s) in ((30.4, 3.6, 10, 0.8), (37.6, 3.2, -20, 0.75)):
        m.place("Flower_Bed_Large", x, y, rot=r, scale=s)
    for (x, y) in ((27.4, 5.0), (33.6, 4.8), (40.8, 5.0)):
        m.place("X20000_Tulips", x, y, rot=x * 17)
    m.place("Sunflower_Patch", 34.8, 3.2, rot=40)
    m.place("Butterfly_Pink", 31.4, 4.6)
    for (x, y) in ((2.4, 22.4), (2.6, 6.2)):
        m.place("Sunflower_Patch", x, y, rot=x * 20)
    m.place("Butterfly", 3.4, 22.8)
    # trees framing the back and the east edge
    for i, (x, y, s) in enumerate([(30.2, 34.8, 0.95), (17.8, 35.2, 0.9), (9.0, 34.8, 1.0),
                                   (0.8, 27.0, 0.9), (13.0, 35.6, 0.8)]):
        m.place(["Tree_Round_A", "Tree_Round_B", "Tree_Round_C"][i % 3], x, y, rot=i * 61, scale=s)
    for i, (x, y) in enumerate([(26.0, 35.2), (34.6, 35.6), (20.6, 34.6), (0.6, 33.0), (1.0, 20.5), (6.0, 35.4),
                                (42.0, 32.0)]):
        m.place(["Bush_A", "Bush_B", "Bush_C"][i % 3], x, y, rot=i * 37)
    # lawn: clover beds, flowers, the arrival meadow
    for (x, y, r) in ((5.2, 18.0, 10), (10.0, 19.6, 70), (3.6, 9.0, 40), (7.6, 3.6, 20),
                      (4.6, 24.2, 30), (11.8, 30.4, 60), (9.6, 3.0, 10)):
        m.place("Clover_Patch", x, y, rot=r)
    m.place("Tree_Round_B", 1.2, 3.0, rot=200, scale=0.9)
    # the inside of the lawn bend: a round flower bed ringed with tulips, and a bench in the shade of the
    # corner tree (all >= 2 m from the Main road)
    fx, fy = 7.0, 6.6
    m.place("Flower_Bed_Large", fx, fy, rot=15, scale=0.95)
    for k in range(7):
        a = 2 * math.pi * k / 7 + 0.3
        m.place("X20000_Tulips", fx + math.cos(a) * 1.75, fy + math.sin(a) * 1.6, rot=k * 51, scale=0.9)
    m.place("Bench", 3.0, 4.2, rot=35)
    m.place("Butterfly_Yellow", fx + 0.4, fy + 0.9)
    m.place("Bush_Flowering_A", 9.0, 1.4, rot=0)
    m.place("Rock_B", 12.0, 1.0, rot=20, scale=0.8)
    m.place("Stump_A", 4.0, 27.6, rot=0)
    verge_path = [(5.6, 12.8, 1.7), (8.0, 11.0, 1.7), (9.4, 9.6, 1.7), (10.6, 7.6, 1.7), (11.6, 5.8, 1.7),
                  (12.8, 4.2, 1.7), (14.2, 3.0, 1.7), (16.2, 2.2, 1.7), (18.0, 1.7, 1.7), (20.4, 1.4, 1.7)]
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 13, 34), 16, seed=1,
              min_dist=1.6, avoid=[geo.rect(0, 12.0, 4, 16.0), (nx, ny, 3.0),
                                   (nx + sux * 3.6, ny + suy * 3.6, 1.8)] + verge_path)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(13, 0, 42, 8), 12, seed=2,
              min_dist=1.6, avoid=[geo.rect(21, 0, 25, 11), geo.rect(19, -1, 26, 1.8)] + verge_path)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A"], geo.rect(19, 10, 42, 36), 14, seed=3, min_dist=1.8,
              avoid=[geo.rect(19, 13.6, 42, 19.6), (hx, hy, 5.6), geo.rect(29, 17, 34, 25), (39.6, 21.8, 2.9),
                     geo.rect(39, 15, 42.5, 21), (sx, sy, sr + 0.6), geo.rect(20.5, 20.5, 26, 28.5),
                     geo.rect(21.5, 10, 25.5, 14), geo.rect(18.4, 10, 19.6, 24)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_B"], geo.rect(13.5, 5, 20, 31), 6, seed=4, min_dist=1.6,
              avoid=[geo.rect(13.5, 11.5, 20, 18), (sx, sy - sr, 1.6), (sx, sy, sr + 0.6), geo.rect(15, 6, 20, 13.4)])
    # grey stones in the visible terrace faces
    for (x, y, z) in [(30.0, 8.2, 1.1), (37.0, 8.4, 0.6), (16.0, 4.35, 0.45), (40.0, 8.5, 1.5)]:
        m.place("Rock_Cliff_Stone", x, y, z=z, rot=0, scale=0.9)

    # ---------------- gameplay ----------------
    m.edge_portal("in00")
    m.edge_portal("out00")
    m.player(25.9, 16.4, rot=45)  # on the street at the top of the porch flight, facing the camera
    m.player_spawn(4.0, 13.5, rot=90, note="sp x -256: beside in00 on the west lawn")
    # main climb: lawn -> verge -> the double flight up the south faces -> street -> out00
    m.route("Main", [(1.0, 14.0), (5.6, 12.8), (9.4, 9.6), (11.6, 5.8), (14.2, 3.0), (18.0, 1.7), (21.4, 1.3),
                     (23.0, 1.2), (23.0, 5.4), (23.0, 10.8), (24.0, 16.6), (30.0, 17.4), (36.0, 18.0), (41.0, 18.0)])
    # street (on Main) -> up the door axis -> through the porch arch -> in01
    # (ends 0.4 m in front of the in01 threshold: on it, the 0.3 m body touched the house's collision prism)
    m.route("ToSensHouse", [(sx0, sy0), (mx, my), (ax, ay), _door_xy(hx, hy, hrot, 4.0)])
    # Main -> across the lawn -> up the stump stair onto Nina's islet (ends 1.1 m from her: inside her talk zone)
    m.route("ToNina", [(5.6, 12.8), (9.6, 17.2), (nx + sux * 5.4, ny + suy * 5.4), (nx + sux * 1.6, ny + suy * 1.6)])
    # verge flight -> along the step's porch to its west bench -> up the sky-islet ladder -> the grass crown
    m.route("SkyIslet", [(23.0, 1.0), (23.0, 5.6), (18.0, 7.2), (16.0, 12.6), (15.6, 16.4), (16.6, 20.0), (sx, sy - sr - 0.9), (sx, sy - sr + 0.15), (sx, sy - 1.2),
                         (sx, sy + 0.8)])
