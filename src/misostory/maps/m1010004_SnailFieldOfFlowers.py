"""Snail Field of Flowers (1010004) - "a sunken flower valley seen from a fenced cliff-top lane".

Classic (GMS v8) structure, from docs/research/maps/1010004_SnailFieldOfFlowers_1010004.md:
  T0 a full-width rim road at the top (arrival + exit east00, wooden rail fence alternating
  with big round bushes, no mobs) -> a 480 px sheer drop crossed only by four long green
  vines -> mid row of three flower meadows (T1 purple irises, T2 clover, T3 orange flowers)
  joined by two dip stones (T4, T5) -> low islands (T6 centre knoll covered in orange
  flowers, T7 west knoll, T8/T9/T10) on short vines -> a symmetric clover basin (T14 | T16 |
  T18 | T17 | T15). A zig-zag of 60 px stones (T15 T13 T12 T11 T10 T8 T6) climbs from the
  east basin rim to the centre knoll. 11 vines, all leafy. Butterflies everywhere.
  Snail 10, Blue Snail 16, Red Snail 17. BGM FloralLife. No NPCs.

3D translation: the rim road runs along the back of the scene, so the vine curtain hangs on
the cliff face the camera sees; the valley falls toward the camera and the clover basin is
the front. You arrive at the east end of the rim road (east00), on a little lookout over
the bowl, and walk west along the fenced lane. Each of the four long vines starts in a gap
of the rim fence under a flowering vine arch, on a pale path patch. The basin is a real
stepped bowl: a U of rim (T14/T15) and bank (T16/T17) wraps the clover floor (T18) and each
side steps down by two short stone flights. The stone stair becomes a curving flight of
round stepping stones (0.4 m per step) winding up from the wide east rim to the centre knoll.
"""

import math

from misostory import core, geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.promoted import arc, butterfly_model, flower_clump

MAP_ID = 1010004
GAMEPLAY_FOCUS = (20.0, 16.0)
GAMEPLAY_SCALE = 38.0

# heights (local, base of the map = plinth top at 0)
RIM = 10.6                    # T0 rim road (arrival)
MID, DIP = 6.9, 6.5           # T1/T2/T3 meadows, T4/T5 dip stones
T6 = 4.5                      # centre knoll
T7, T8 = 4.1, 4.1
T9, T10 = 3.7, 3.7
T11, T12, T13 = 3.3, 2.9, 2.5  # stair stones
RIMB = 2.1                    # T14/T15 bowl rim
BANK = 1.2                    # T16/T17 banks
FLOOR = 0.3                   # T18 clover floor

# rim -> mid row long vines (x), the two dead-end vines under the lip, and short curtain strands
LONG_VINES = [4.6, 15.6, 21.6, 33.4]
DEAD_VINES = [7.2, 30.6]
CURTAIN = [1.4, 10.6, 12.8, 18.6, 25.8, 36.6]  # each >= 2 m from every vine above


# ---------------------------------------------------------------------------
# local assets (map-prefixed; candidates for the shared kit)
# ---------------------------------------------------------------------------

@asset("X1010004_Marigold_Bed", "Foliage", footprint=2.0, tags=("flower",))
def _marigold_bed(coll):
    """Dense bed of tall orange marigolds/lilies (grassySoil orange flowers, centre knoll)."""
    flower_clump(coll, "X1010004_Marigold_Bed", ["M_Flat_mush_orange", "M_Flat_roof_orange", "M_Flat_flower_yellow",
                                                  "M_Flat_mush_orange"], 18, 0.95, 7, h=(0.5, 0.95),
                 petal_r=0.13, leaves_n=8)


@asset("X1010004_Butterfly_Orange", "Foliage", footprint=0.4, tags=("flower",))
def _butterfly_orange(coll):
    butterfly_model(coll, "X1010004_Butterfly_Orange", "M_Flat_mush_orange", "M_Flat_flower_yellow")


@asset("X1010004_Vine_Arch", "Props", footprint=2.0, tags=("prop", "vine"))
def _vine_arch(coll):
    """Rustic arch wrapped in a flowering vine that marks the top of a climbable vine (spans X, faces -Y).

    Two thin posts 1.9 m apart carry a half-round hoop (top at 2.55 m); bright leaves and pink, white and
    yellow blossoms climb it. The walk-through opening is clear up to 1.75 m.
    """
    r = core.rng("x1010004_vine_arch", 1)
    mb = MeshBuilder()
    for x in (-0.95, 0.95):
        mb.cyl(0.07, 1.62, loc=(x, 0, 0), mat="M_Wood_Dark", verts=8)
    arc(mb, 0.95, 0.09, 0.1, 1.6, "M_Wood_Dark", n=12)
    mb.build("X1010004_Vine_Arch", coll, smooth=False)
    lv = MeshBuilder()
    pts = [(sx * 0.95, 0.25 + k * 0.3) for sx in (-1, 1) for k in range(5)]
    pts += [(0.95 * math.cos(math.pi * k / 10), 1.6 + 0.95 * math.sin(math.pi * k / 10)) for k in range(11)]
    for k, (x, z) in enumerate(pts):
        lv.sphere(r.uniform(0.15, 0.2), loc=(x + r.uniform(-0.05, 0.05), -0.04, z), scale=(1.25, 0.6, 0.9),
                  mat="M_Flat_leaf_lt" if k % 2 else "M_Leaf", subdiv=1)
    lv.build("X1010004_Vine_Arch_Leaves", coll, smooth=True, sharp_angle=60)
    fl = MeshBuilder()
    cols = ["M_Flat_flower_pink", "M_Flat_flower_white", "M_Flat_flower_yellow"]
    for k, (x, z) in enumerate(pts[1::2]):
        fl.sphere(0.075, loc=(x + r.uniform(-0.1, 0.1), -0.17, z + r.uniform(-0.08, 0.08)), mat=cols[k % 3], subdiv=1)
    fl.build("X1010004_Vine_Arch_Flowers", coll, smooth=True)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def cap_edge(m, x, y, z_top, step=0.04, max_d=6.0):
    """First y (scanning +y from y) where the ground reaches the tier at z_top: its grass-cap edge."""
    t = 0.0
    while t <= max_d:
        g = m.ground_z(x, y + t)
        if g is not None and g > z_top - 0.3:
            return y + t
        t += step
    return y + 0.3


def vine_climb(m, name, x, y, z0, z1, seed=0):
    """Climbable green leafy vine (classic connect/rope/3) hanging from z1 down to z0.

    Bright lime leaves with a blossom at every leaf pair, so the vines that go somewhere read
    apart from the short dark curtain strands."""
    r = core.rng(m.slug, name, seed)
    mb = MeshBuilder()
    p = m.w(x, y, z0)
    h = z1 - z0
    mb.cyl(0.11, h + 0.35, loc=(p.x, p.y, p.z), mat="M_Flat_leaf", verts=8)
    z = 0.25
    k = 0
    while z < h + 0.2:
        s = 1 if k % 2 else -1
        mb.sphere(0.26, loc=(p.x + s * 0.21, p.y - 0.06, p.z + z), scale=(1.3, 0.55, 0.85), mat="M_Flat_leaf_lt",
                  subdiv=1)
        mb.sphere(0.18, loc=(p.x - s * 0.17, p.y - 0.08, p.z + z + 0.14), scale=(1.2, 0.5, 0.8),
                  mat="M_Flat_grass_top_lt", subdiv=1)
        mb.sphere(0.09, loc=(p.x + s * 0.32, p.y - 0.18, p.z + z + 0.05),
                  mat=("M_Flat_flower_pink", "M_Flat_flower_white", "M_Flat_flower_yellow")[k % 3], subdiv=1)
        z += 0.32 + r.uniform(-0.04, 0.04)
        k += 1
    mb.sphere(0.26, loc=(p.x, p.y - 0.02, p.z + h + 0.25), scale=(1.4, 0.8, 0.7), mat="M_Flat_leaf_lt", subdiv=1)
    obj = mb.build(m._name(name), m.col_arch, smooth=True, sharp_angle=60)
    return m.climbable(obj, x, y, z0, z1, kind="rope")


def dark_strand(m, name, x, y, z_top, length, seed=0):
    """Decorative dark leafy strand hanging from under a lip; reaches nowhere (classic dead-end vines)."""
    r = core.rng(m.slug, name, seed)
    mb = MeshBuilder()
    p = m.w(x, y, z_top)
    mb.cyl(0.045, length, loc=(p.x, p.y, p.z - length), mat="M_Flat_leaf_dk", verts=6)
    z = 0.2
    k = 0
    while z < length:
        s = 1 if k % 2 else -1
        mb.sphere(0.17, loc=(p.x + s * 0.14, p.y - 0.05, p.z - z), scale=(1.3, 0.55, 0.85), mat="M_Leaf_B", subdiv=1)
        z += 0.34 + r.uniform(-0.04, 0.04)
        k += 1
    mb.build(m._name(name), m.col_veg, smooth=True, sharp_angle=60)


def stone(m, name, cx, cy, rx, ry, top, bottom=-0.5, style="grass_dirt", **kw):
    """Round knoll / stepping stone (grass cap, little wobble so overlaps hold)."""
    return m.terrace(name, geo.ellipse(cx, cy, rx, ry, 20), top=top, bottom=bottom, wobble_amt=0.05, style=style,
                     **kw)


def stair_stone(m, name, cx, cy, r, top):
    """Stepping stone of the east stair: a boulder-shaped warm rock drum with a grass rim and fringe, topped by a
    flagstone slab whose (walkable) top is at `top` (the grass rim sits 5 cm lower, so 0.4 m steps stay 0.4)."""
    m.terrace(name, geo.ellipse(cx, cy, r, r, 20), top=top - 0.05, bottom=-0.5, wobble_amt=0.05, style="grass_rock",
              stones=False, cap_thickness=0.22, lip=0.18)
    w = m.w(cx, cy, top)
    mb = MeshBuilder()
    mb.cyl(r * 0.74, 0.12, loc=(w.x, w.y, w.z - 0.12), mat="M_StoneWall", verts=14, bevel=0.03, segs=1)
    m.add_ground(mb.build(m._name(name + "_Slab"), m.col_terrain, smooth=True, sharp_angle=40))


# the bowl trail and the east stair walk (routes; the basin flower scatter keeps 1.5 m off them)
BASIN_BOWL = [(2.4, 10.6), (4.4, 10.6), (7.2, 10.6), (8.2, 10.6), (11.0, 10.6), (14, 10.0), (19, 9.0), (22.2, 8.6),
              (25.0, 8.6), (25.5, 8.6), (28.3, 8.6), (31.0, 8.6)]
EAST_STAIR = [(31.0, 8.6), (33.0, 10.2), (34.0, 12.0), (35.2, 14.6), (33.8, 17.2), (31.6, 18.4), (28.0, 19.2),
              (25.6, 18.6), (23.6, 17.6), (19.0, 17.0)]


# ---------------------------------------------------------------------------

def build(m):
    L, D = m.size  # 38 x 36

    # ---------------- the rim road (back) ----------------
    m.terrace("RimRoad_T0", [(-0.8, 28.3), (4.6, 28.0), (9.0, 27.5), (12.4, 27.9), (15.6, 28.0), (18.6, 27.5),
                             (21.6, 28.0), (26.0, 28.4), (30.6, 28.0), (34.0, 27.6), (38.8, 27.4), (38.8, 36.8),
                             (-0.8, 36.8)], top=RIM, bottom=-0.5)

    # ---------------- mid row: three meadows joined by two dips ----------------
    m.terrace("WestMeadow_T1", [(-0.8, 21.2), (2.0, 20.9), (4.2, 21.0), (6.6, 20.6), (8.4, 21.2), (8.4, 28.6),
                                (-0.8, 28.6)], top=MID, bottom=-0.5)
    m.terrace("Dip_T4", [(8.0, 21.8), (10.0, 21.7), (12.0, 21.9), (12.0, 28.6), (8.0, 28.6)], top=DIP, bottom=-0.5)
    m.terrace("CentreMeadow_T2", [(11.6, 21.2), (14.0, 20.6), (17.5, 20.9), (21.0, 20.5), (24.6, 21.2),
                                  (24.6, 28.6), (11.6, 28.6)], top=MID, bottom=-0.5)
    m.terrace("Dip_T5", [(24.2, 21.9), (26.4, 21.7), (28.2, 21.9), (28.2, 28.6), (24.2, 28.6)], top=DIP,
              bottom=-0.5)
    m.terrace("EastMeadow_T3", [(27.8, 21.2), (29.6, 21.0), (31.6, 20.8), (34.0, 21.3), (36.4, 21.0), (38.8, 21.4),
                                (38.8, 28.6), (27.8, 28.6)], top=MID, bottom=-0.5)

    # ---------------- low islands: flower knolls ----------------
    m.terrace("CentreKnoll_T6", [(13.0, 15.0), (16.0, 13.4), (21.0, 13.4), (24.6, 15.0), (25.4, 17.6),
                                 (24.8, 20.4), (21.0, 20.8), (15.5, 20.6), (12.8, 18.6)], top=T6, bottom=-0.5)
    m.terrace("WestKnoll_T7", geo.ellipse(8.9, 18.7, 3.8, 2.8, 22), top=T7, bottom=-0.5, wobble_amt=0.1)
    m.terrace("FarWestKnoll_T9", geo.ellipse(3.0, 19.4, 2.7, 2.0, 18), top=T9, bottom=-0.5, wobble_amt=0.1)
    # Plinth-level slivers walled in between the knolls, the bowl rim and the meadows' front edges were pits a
    # player fell into off a meadow or a knoll (Iteration Three stuck-region scan, docs/runtime/STUCK_SCAN.md).
    # Each is filled 0.2 m below the low neighbour it joins.
    m.terrace("Knoll_T7_T6_Fill", [(10.4, 18.8), (14.4, 18.8), (14.4, 21.9), (10.4, 21.9)], top=T7 - 0.2,
              bottom=-0.5)
    m.terrace("Rim_T9_Fill", [(-0.8, 18.2), (1.2, 18.2), (1.2, 21.4), (-0.8, 21.4)], top=RIMB - 0.2, bottom=-0.5)
    m.terrace("Knoll_T8_Fill", [(24.2, 19.8), (26.0, 19.8), (26.0, 22.2), (24.2, 22.2)], top=T8 - 0.2, bottom=-0.5)
    stone(m, "EastKnoll_T8", 26.9, 19.2, 2.4, 2.2, T8)
    stone(m, "EastKnoll_T10", 31.2, 18.6, 2.4, 2.4, T10)
    # the curving stone stair from the wide east rim up to T10: rock drums with flagstone tops and a grass rim
    stair_stone(m, "Stair_T13", 34.0, 12.0, 1.7, T13)
    stair_stone(m, "Stair_T12", 35.2, 14.6, 1.7, T12)
    stair_stone(m, "Stair_T11", 33.8, 17.2, 1.7, T11)

    # ---------------- the clover bowl: a U of rim and bank around the floor ----------------
    # T14 (west) and T15 (east) rims are joined by a low front lip; the east rim fills the freed
    # east strip back to the T3 cliff, so the stone stair rises out of it
    m.terrace("BowlRim_T14_T15", [(-0.8, -0.8), (38.8, -0.8), (38.8, 21.6), (33.0, 21.4), (30.4, 15.8),
                                  (28.2, 12.6), (27.6, 8.0), (26.6, 3.8), (23.4, 2.4), (16.0, 2.0), (8.6, 2.4),
                                  (5.8, 3.8), (5.0, 8.0), (5.0, 13.5), (5.4, 18.6), (-0.8, 18.6)],
              top=RIMB, bottom=-0.5)
    m.terrace("Bank_T16_T17", [(4.6, 17.4), (4.3, 13.5), (4.3, 8.0), (5.1, 3.2), (8.4, 1.7), (16.0, 1.3),
                               (23.6, 1.7), (27.3, 3.2), (28.3, 8.0), (28.9, 12.4), (29.6, 13.8), (25.8, 13.4),
                               (24.6, 9.0), (23.8, 6.8), (21.8, 5.6), (16.0, 5.4), (10.6, 5.6), (9.2, 6.8),
                               (8.8, 9.0), (8.8, 16.6)], top=BANK, bottom=-0.5)
    m.terrace("BasinFloor_T18", [(7.6, 4.4), (24.6, 4.4), (26.6, 10.0), (29.0, 16.6), (12.6, 17.0), (7.6, 17.0)],
              top=FLOOR, bottom=-0.5)
    # each side of the bowl steps down by two short turf slopes (rim -> bank -> floor); a dirt trail
    # runs over them and across the floor (grass-topped so they read as part of the bowl wall)
    turf = dict(top_mat=None, extend=0.25, blend=False)
    m.ramp("Slope_W_RimBank", (7.2, 10.6, BANK), (4.4, 10.6, RIMB), 2.6, **turf)
    m.ramp("Slope_W_BankFloor", (11.0, 10.6, FLOOR), (8.2, 10.6, BANK), 2.6, **turf)
    m.ramp("Slope_E_FloorBank", (22.2, 8.6, FLOOR), (25.0, 8.6, BANK), 2.6, **turf)
    m.ramp("Slope_E_BankRim", (25.5, 8.6, BANK), (28.3, 8.6, RIMB), 2.6, **turf)

    # ---------------- vines ----------------
    # the four long climbable vines hang from the rim lip; bright, flowering and full length
    vine_top = {}
    for i, x in enumerate(LONG_VINES):
        ye = cap_edge(m, x, 24.0, RIM)
        vine_top[x] = ye
        vine_climb(m, f"Vine_Rim_{i}", x, ye - 0.15, MID, RIM, seed=i)
    for i, x in enumerate(DEAD_VINES):  # classic dead-end vines: dark, hang from the lip and stop mid-face
        dark_strand(m, f"Vine_DeadEnd_{i}", x, cap_edge(m, x, 24.0, RIM) - 0.12, RIM - 0.15, 1.5 + i * 0.3, seed=i)
    for i, x in enumerate(CURTAIN):  # a few short dark strands keep the face lush without competing
        dark_strand(m, f"Vine_Curtain_{i}", x, cap_edge(m, x, 24.0, RIM) - 0.12, RIM - 0.15, 0.7 + (i % 3) * 0.15,
                    seed=20 + i)
    # short climbable vines from the meadow edges down to the knolls, and from T9 to the west rim
    short = [("Vine_T9_T1", 2.6, MID, T9, 18.0), ("Vine_T7_T4", 10.0, DIP, T7, 18.0),
             ("Vine_T8_T5", 26.4, DIP, T8, 18.0), ("Vine_T10_T3", 31.6, MID, T10, 18.0)]
    short_y = {}
    for name, x, ztop, zfoot, y0 in short:
        ye = cap_edge(m, x, y0, ztop)
        short_y[name] = ye
        vine_climb(m, name, x, ye - 0.15, zfoot, ztop, seed=len(name) + int(x))
    ye9 = cap_edge(m, 2.6, 14.0, T9)
    vine_climb(m, "Vine_T14_T9", 2.6, ye9 - 0.15, RIMB, T9, seed=9)
    for i, x in enumerate([14.0, 19.6]):  # two tiny strands on the centre meadow face
        dark_strand(m, f"Vine_MidFace_{i}", x, cap_edge(m, x, 18.0, MID) - 0.12, MID - 0.15, 0.6, seed=60 + i)

    # ---------------- paths ----------------
    m.path("Path_RimRoad", [(37.6, 31.5), (33.0, 31.5), (20, 31.6), (8, 31.4), (1.0, 31.6)], width=3.2)
    for i, x in enumerate(LONG_VINES):  # pale patches lead from the road to each vine top
        m.path(f"Path_VineTop_{i}", [(x, 30.4), (x, vine_top[x] + 0.2)], width=1.5, mat="M_Sand_Path")
    m.path("Path_Bowl", [(2.6, 10.6), (7.8, 10.6), (11.6, 10.6), (14, 10.2), (19, 9.0), (21.6, 8.6), (25.2, 8.6),
                         (29.2, 8.6), (32.0, 9.4), (33.2, 10.6)], width=2.3)
    # the dirt resumes off the top stone: across the T10 and T8 knolls onto the centre knoll (the exit climb)
    m.path("Path_StairTop", [(32.5, 17.9), (31.0, 18.5), (28.0, 19.2), (25.6, 18.6), (24.0, 17.8)], width=1.8)

    # ---------------- rim road dressing ----------------
    # rail fence alternating with big bushes; every long vine starts in a fence gap under a vine arch
    for a, b in [(0.2, 3.2), (6.0, 9.0), (11.8, 14.2), (17.0, 20.2), (23.0, 26.0), (28.8, 32.0), (34.8, 38.0)]:
        m.fence([(a, 28.95), (b, 28.95)])
    for (x, s) in [(10.4, 1.0), (27.4, 1.0)]:
        m.place("Bush_B", x, 29.1, rot=x * 17, scale=s)
    for x in LONG_VINES:
        m.place("X1010004_Vine_Arch", x, vine_top[x] + 0.75, rot=0)
    # the arrival lookout at the east end: a bench facing the bowl and a welcome board
    m.place("Bench", 36.2, 29.95, rot=0)
    m.place("Sign_Board", 33.4, 34.0, rot=-10)
    m.place("Flower_Bed_Large", 35.4, 34.6, rot=20, scale=0.8)
    # backdrop behind the road: a hedge-and-tree edge to the field (clear of the trail corridor)
    for i, x in enumerate([1.5, 6.5, 12.0, 17.5, 23.0, 28.5, 33.0]):
        m.place(["Tree_Round_B", "Tree_Birch_Yellow", "Tree_Round_C", "Tree_Round_A"][i % 4], x + (i % 2) * 0.9,
                34.9 + (i * 3 % 4) * 0.5, rot=i * 53, scale=0.8 + (i * 5 % 3) * 0.1)
    for i, x in enumerate([4.0, 9.2, 14.8, 20.2, 25.8, 30.6]):
        m.place(["Bush_B", "Bush_A", "Bush_Flowering_A"][i % 3], x, 33.8, rot=i * 41)
    for (x, y) in [(2.6, 29.6), (13.0, 29.7), (24.6, 29.6), (30.2, 33.4)]:
        m.place("Clover_Patch", x, y, rot=x * 11)

    # ---------------- mid row meadows ----------------
    # T1 west meadow: purple irises, a big bush, a pink butterfly
    for (x, y) in [(1.2, 23.0), (3.0, 25.6), (6.4, 23.6), (7.0, 27.0), (7.6, 25.4)]:
        m.place("Iris_Patch", x, y, rot=x * 29)
    m.place("Bush_B", 0.8, 26.6, rot=40)
    m.place("Flower_Bed_Large", 5.4, 22.6, rot=15, scale=0.8)
    m.place("Butterfly_Pink", 3.0, 24.4, rot=30, scale=1.4)
    # T2 centre meadow: clover patch, bushes, a pink butterfly
    for (x, y) in [(13.2, 22.6), (17.6, 23.4), (18.8, 26.0), (22.8, 23.0), (23.6, 26.4), (12.6, 25.6),
                   (20.4, 22.0)]:
        m.place("Clover_Patch", x, y, rot=x * 13)
    m.place("Bush_B", 12.4, 27.6, rot=20, scale=0.9)
    m.place("Bush_A", 24.0, 27.6, rot=60)
    m.place("Flower_Bed_Large", 18.4, 22.6, rot=10, scale=0.9)
    m.place("Butterfly_Pink", 16.4, 24.0, rot=-40, scale=1.4)
    m.place("Bush_Flowering_A", 13.9, 26.4, rot=30)
    m.place("Bush_Flowering_A", 19.0, 27.4, rot=-20, scale=0.9)
    # T3 east meadow (now running to the east edge): orange flowers, bushes, a yellow butterfly
    for (x, y, s) in [(29.0, 22.8, 0.75), (35.8, 23.2, 0.8), (29.6, 25.6, 0.7), (37.4, 26.2, 0.7), (31.6, 27.2, 0.6)]:
        m.place("X1010004_Marigold_Bed", x, y, rot=x * 7, scale=s)
    m.place("Bush_B", 38.2, 26.6, rot=10, scale=0.85)
    m.place("Butterfly_Yellow", 35.0, 24.6, rot=15, scale=1.4)
    # dips: little grass tufts
    for (x, y) in [(10.0, 25.0), (26.2, 25.4)]:
        m.place("Grass_Tuft_A", x, y)

    # ---------------- knolls ----------------
    # T6 centre knoll: dense orange flower bed + 4 bushes + orange butterflies
    for (x, y, s) in [(16.0, 16.2, 1.0), (18.6, 15.2, 1.05), (21.2, 16.0, 0.95), (17.2, 18.4, 0.9),
                      (20.2, 18.6, 1.0), (22.8, 18.6, 0.8), (14.6, 18.2, 0.8)]:
        m.place("X1010004_Marigold_Bed", x, y, rot=x * 31, scale=s)
    for (x, y) in [(13.8, 15.4), (23.8, 15.2), (15.6, 20.0), (22.0, 20.2)]:
        m.place("Bush_A", x, y, rot=x * 9, scale=0.85)
    m.place("X1010004_Butterfly_Orange", 18.8, 17.0, rot=20, scale=1.4)
    m.place("X1010004_Butterfly_Orange", 21.4, 14.4, rot=-50, scale=1.4)
    # T7 west knoll: a big bush (kept off the T9 -> T7 walk) + orange flowers + yellow butterfly
    m.place("Bush_B", 12.0, 18.2, rot=30, scale=0.9)
    m.place("X1010004_Marigold_Bed", 8.8, 17.4, rot=10, scale=0.7)
    m.place("X1010004_Marigold_Bed", 7.0, 20.2, rot=70, scale=0.6)
    m.place("Butterfly_Yellow", 9.0, 19.0, rot=-20, scale=1.4)
    m.place("Flower_Patch_A", 2.0, 20.4)
    m.place("Flower_Patch_A", 31.0, 20.2, rot=40)
    m.place("Flower_Patch_B", 26.6, 20.6, rot=80)

    # ---------------- basin ----------------
    # T18: a white-pink clover carpet (kept off the bowl trail), big bushes at the west end, pink butterflies
    route_av = [(x, y, 1.5) for x, y in geo.resample(BASIN_BOWL, 1.0, closed=False)]
    route_av += [(x, y, 1.5) for x, y in geo.resample(EAST_STAIR, 1.0, closed=False)]
    m.scatter(["Clover_Patch"], geo.rect(9.0, 5.6, 25.0, 15.6), 24, seed=2, min_dist=1.5,
              scale=(1.0, 1.4), z_band=(FLOOR - 0.2, FLOOR + 0.3), avoid=[(x, y, 1.15) for x, y, _r in route_av])
    for (x, y, s) in [(9.6, 14.6, 1.1), (11.4, 15.6, 0.9)]:
        m.place("Bush_B", x, y, rot=x * 23, scale=s)
    m.place("Bush_Flowering_A", 21.6, 14.4, rot=60)
    # denser clover and pink-white flowers over the floor and the banks of the U, 1.5 m off the trail and stair
    m.scatter(["Clover_Patch", "Flower_Patch_A"], [(7.6, 4.4), (24.6, 4.4), (26.6, 10.0), (29.0, 16.6),
                                                   (12.6, 17.0), (7.6, 17.0)], 22, seed=31, min_dist=1.2,
              scale=(0.9, 1.3), avoid=route_av, z_band=(FLOOR - 0.2, FLOOR + 0.3))
    m.scatter(["Clover_Patch", "Flower_Patch_A"], [(4.0, 18.0), (3.8, 2.6), (8.0, 0.8), (24.0, 0.8), (28.8, 2.8),
                                                   (30.2, 14.4), (25.0, 14.0), (24.0, 6.4), (9.6, 6.4),
                                                   (9.4, 17.2)], 16, seed=32, min_dist=1.2, scale=(0.9, 1.2),
              avoid=route_av, z_band=(BANK - 0.2, BANK + 0.3))
    m.place("Flower_Bed_Large", 15.4, 13.0, rot=0)
    m.place("Flower_Bed_Large", 13.0, 7.0, rot=40, scale=0.85)
    m.place("Flower_Bed_Large", 19.4, 6.6, rot=-20, scale=0.85)
    m.place("Butterfly_Pink", 14.6, 11.6, z=1.9, required=False, scale=1.4)
    m.place("X1010004_Butterfly_Orange", 17.6, 8.4, rot=-10, scale=1.4)
    # rocks and a log at the knoll feet
    for (x, y, a, s) in [(12.6, 13.8, "Rock_A", 0.9), (25.6, 14.2, "Rock_C", 1.0), (7.2, 15.2, "Rock_B", 0.7),
                         (0.4, 17.8, "Rock_A", 0.7)]:
        m.place(a, x, y, rot=x * 37, scale=s)
    m.place("Log_A", 18.6, 13.0, rot=8, scale=0.8)
    # banks: clover tufts and small flowering bushes around the U
    for (x, y) in [(6.0, 6.4), (6.4, 14.4), (12.0, 3.4), (19.6, 3.2), (25.8, 5.0), (26.8, 11.6)]:
        m.place("Clover_Patch", x, y, rot=x * 19)
    for (x, y) in [(5.6, 4.2), (24.8, 3.0)]:
        m.place("Bush_Flowering_A", x, y, rot=x * 13, scale=0.8)
    # rims: clover, bushes and pink butterflies (front lip kept low)
    for (x, y) in [(1.4, 3.0), (2.8, 13.4), (1.0, 15.8), (2.4, 6.8), (16.0, 0.6), (9.0, 0.8)]:
        m.place("Clover_Patch", x, y, rot=y * 19)
    m.place("Bush_A", 0.6, 9.6)
    m.place("Bush_Flowering_A", 0.8, 0.6, rot=20)
    for (x, y) in [(30.4, 3.0), (35.6, 6.8), (30.8, 12.6), (37.6, 1.6), (37.4, 18.8), (23.0, 0.6)]:
        m.place("Clover_Patch", x, y, rot=x * 19)
    for (x, y, s) in [(37.6, 10.0, 0.9), (31.6, 6.2, 0.8)]:
        m.place("Bush_B", x, y, rot=x * 29, scale=s)
    m.place("Bush_Flowering_A", 29.0, 0.8, rot=50)
    m.place("Bush_Flowering_A", 37.8, 15.2, rot=10, scale=0.8)
    m.place("Flower_Bed_Large", 34.4, 3.4, rot=30, scale=0.9)
    m.place("Tree_Birch_Yellow", 37.6, 19.4, rot=40, scale=0.9)
    m.place("Tree_Birch_Teal", 0.4, 15.0, rot=200, scale=0.8)
    for (x, y, a) in [(36.4, 12.6, "Flower_Patch_A"), (31.8, 1.6, "Flower_Patch_B"), (2.0, 1.4, "Flower_Patch_A")]:
        m.place(a, x, y, rot=x * 7)
    m.place("Butterfly_Pink", 2.0, 11.6, rot=60, scale=1.4)
    m.place("Butterfly_Pink", 33.0, 5.4, rot=-30, scale=1.4)

    # ---------------- gameplay ----------------
    m.edge_portal("east00")
    # the player stands on the centre knoll among the orange flowers, beside the EastStair walk, facing the camera
    PLAYER = (22.4, 16.9)
    m.player(*PLAYER, rot=-15)
    m.player_spawn(4.6, 31.5, rot=90, note="sp x -794: the west end of the top tier (rim road)")
    m.mobs("Blue Snail", geo.rect(0.5, 22, 8, 27.5), 1, seed=1, z_band=(MID - 0.2, MID + 0.3))
    m.mobs("Red Snail", geo.rect(12.5, 22, 24, 27.5), 1, seed=2, z_band=(MID - 0.2, MID + 0.3))
    m.mobs("Blue Snail", geo.rect(12.5, 22, 24, 27.5), 1, seed=3, z_band=(MID - 0.2, MID + 0.3), min_dist=3.0)
    m.mobs("Red Snail", geo.rect(28.4, 22, 38, 27.0), 1, seed=4, z_band=(MID - 0.2, MID + 0.3))
    m.mobs("Blue Snail", geo.rect(14, 14, 24, 20), 1, seed=5, z_band=(T6 - 0.2, T6 + 0.3),
           avoid=[(*PLAYER, 1.8)])
    m.mobs("Snail", geo.rect(14, 14, 24, 20), 1, seed=6, z_band=(T6 - 0.2, T6 + 0.3), min_dist=3.0,
           avoid=[(*PLAYER, 1.8)])
    m.mobs("Blue Snail", geo.ellipse(8.9, 18.7, 3.0, 2.0), 1, seed=7, z_band=(T7 - 0.2, T7 + 0.3))
    m.mobs("Red Snail", geo.rect(0, 1, 4, 16), 1, seed=8, z_band=(RIMB - 0.2, RIMB + 0.3))
    m.mobs("Red Snail", geo.rect(29, 1, 37, 9.5), 1, seed=9, z_band=(RIMB - 0.2, RIMB + 0.3))
    m.mobs("Snail", geo.rect(9, 6, 24, 13), 1, seed=10, z_band=(FLOOR - 0.2, FLOOR + 0.3))
    m.mobs("Blue Snail", geo.rect(9, 6, 24, 13), 1, seed=11, z_band=(FLOOR - 0.2, FLOOR + 0.3), min_dist=3.0)
    m.mobs("Red Snail", geo.rect(9, 6, 24, 13), 1, seed=12, z_band=(FLOOR - 0.2, FLOOR + 0.3), min_dist=3.0)
    # MeowDB MS Classic adds 6 Orange Mushrooms here (v8 had none): a representative proxy on the west meadow
    m.mobs("Orange Mushroom", geo.rect(0.5, 22, 8, 27.5), 1, seed=13, z_band=(MID - 0.2, MID + 0.3), min_dist=3.0)

    # routes (each is validated in both directions; vines count as climbs)
    m.route("RimRoad", [(37.0, 31.5), (33.0, 31.5), (20, 31.6), (8, 31.4), (1.0, 31.6)])
    for i, x in enumerate(LONG_VINES):
        m.route(f"VineDown_{i}", [(x, 31.4), (x, vine_top[x] - 1.6), (x, 24.0)])
    m.route("MidRow", [(1.0, 24.6), (8.2, 24.6), (10.0, 24.8), (12.2, 24.6), (18.0, 24.6), (24.4, 24.6),
                       (26.2, 24.8), (28.2, 24.6), (36.4, 24.6)])
    for name, x, _zt, _zf, _y0 in short:
        ye = short_y[name]
        # from MidRow (y 24.8) down the short vine onto the knoll below (both ways: the vines climb)
        m.route(name.replace("Vine_", "Vine"), [(x, 24.8), (x, ye - 1.4), (x, ye - 2.2)])
    m.route("WestKnolls", [(3.0, 19.4), (5.4, 19.3), (8.6, 18.6)])
    m.route("VineT9_T14", [(2.6, ye9 + 1.2), (2.6, ye9 - 1.6), (2.6, 14.0), (2.4, 10.6)])
    m.route("BasinBowl", BASIN_BOWL)
    m.route("EastStair", EAST_STAIR)
