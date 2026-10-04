"""The Field East of Amherst (1020000) - "a lattice hillside with a hidden gate to the Tomato Field".

Classic (GMS v8) structure, from docs/research/maps/1020000_FieldEastOfAmherst_1020000.md:
  ground chain: west plateau (west00 from Amherst) -> two 60 px steps down into the west
  hollow -> central mound -> east hollow -> east plateau with a log pile and the giant
  orange mushroom pair; above it a ten-row lattice of grass platforms: a low row of six
  stepping stones, mid shelves (red-berry row, pink clover bed), the DANGER-sign ledge with
  three tomato plants hiding in00 (to Tomato Field), a second row of five stepping stones,
  and a crown row of long platforms with big flowering bushes. 12 ladders/ropes.
  Mobs: Snail, Blue Snail, Red Snail (platforms only), Orange Mushroom. No NPCs.

3D translation: the lattice becomes a hillside that climbs away from the meadow, every
platform row one step higher and further back. For this map's yaw the camera looks from
the EAST-front (local look ~(-0.88, +0.47)), so the hill also climbs toward the west:
the crown and the west high shelf sit at the back-west, while the east side holds the low
DANGER-sign nook whose +x cliff faces the camera. Stepping-stone rows are chains of round
earth pillars at the foot of the next shelf. The hidden in00 is a secluded nook on the
back edge: the classic DANGER sign and tomato plants mark it, and the path slips out of the
map through a clipped hedge tunnel with only a few tomatoes in its leaves (the giant
tomato-capped barrel gate stands only at the Tomato Field end, so the two ends differ).
Classic 60 px hops are short grassy earth ramps (2.5 m wide, solid to the ground).
"""

from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.mapkit import MAIN_ROAD

MAP_ID = 1020000
GAMEPLAY_FOCUS = (37.0, 24.0)
GAMEPLAY_SCALE = 38.0

PLAT = 2.0      # west plateau / central mound / east plateau (2D y=95)
STEP = 1.0      # the 60 px steps into the hollows
STONE = 3.8     # low stepping-stone row T12..T17 (y=-145)
T11_Z = 3.2     # small stone over the east plateau (y=-85)
T18_Z = 4.6     # (y=-205)
CLOVER = 5.0    # T20 clover bed (y=-265)
T19_Z = 5.4     # (y=-265)
BERRY = 5.8     # T21/T22 red-berry shelf (y=-325)
T23_Z = 5.8     # (y=-325)
NOOK = 6.6      # T24 DANGER-sign ledge with in00 (y=-385)
WEST_HI = 7.4   # T25/T26 (y=-445)
UPSTONE = 8.8   # T27..T31 second stepping-stone row (y=-565)
T33_Z = 9.8     # T32/T33 (y=-685)
CROWN = 10.6    # T34..T37 crown (y=-745)


# ---------------------------------------------------------------------------
# local assets
# ---------------------------------------------------------------------------

@asset("X1020000_WhiteMushrooms", "Foliage", footprint=0.8, tags=("mushroom",))
def _white_mushrooms(coll):
    """Little cluster of white-capped mushrooms (seen on the top islands)."""
    stems = MeshBuilder()
    caps = MeshBuilder()
    for (x, y, h, rr) in ((0, 0, 0.55, 0.32), (0.38, 0.12, 0.35, 0.22), (-0.3, 0.2, 0.28, 0.18)):
        stems.cyl(rr * 0.35, h, loc=(x, y, 0), mat="M_MushStem", verts=10, r2=rr * 0.28)
        caps.dome(rr, rr * 0.7, loc=(x, y, h * 0.95), mat="M_Spot_cloth_white__mush_stem_dk", u=16, v=5,
                  lip=rr * 0.15, profile=0.8)
    stems.build("X1020000_WhiteMushrooms_Stems", coll, smooth=True, sharp_angle=60)
    caps.build("X1020000_WhiteMushrooms_Caps", coll, smooth=True, sharp_angle=70)


@asset("X1020000_LogPile", "Props", footprint=2.6, tags=("prop",))
def _log_pile(coll):
    """Stacked log pile (3-2-1) on the east plateau (grassySoil artificiality/6+7)."""
    mb = MeshBuilder()
    r = 0.34
    rows = [(-2 * r, 0), (0, 0), (2 * r, 0), (-r, 1), (r, 1), (0, 2)]
    for k, (y, row) in enumerate(rows):
        z = r + row * r * 1.72
        ln = 2.4 - 0.15 * (k % 2)
        mb.cyl(r, ln, loc=(-ln / 2, y, z), rot=(0, 90, 0), mat="M_Bark", verts=12, r2=r * 0.95)
        mb.cyl(r * 0.86, 0.04, loc=(ln / 2 + 0.01, y, z), rot=(0, 90, 0), mat="M_Flat_wood_lt", verts=12)
        mb.cyl(r * 0.86, 0.04, loc=(-ln / 2 - 0.05, y, z), rot=(0, 90, 0), mat="M_Flat_wood_lt", verts=12)
    for s in (-1, 1):
        mb.box((0.12, 0.12, 1.2), loc=(s * 0.9, -3 * r - 0.06, 0.6), mat="M_Wood_Dark")
        mb.box((0.12, 0.12, 1.2), loc=(s * 0.9, 3 * r + 0.06, 0.6), mat="M_Wood_Dark")
    mb.build("X1020000_LogPile", coll, smooth=True, sharp_angle=45)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _hop(m, name, p0, p1, width):
    """A classic 60 px hop between two platforms as a short grassy earth ramp (solid to the ground,
    no dirt top): reads as the land itself rising rather than a loose plank step. p0 low, p1 high.
    p1 sits just 0.1 m inside the upper outline so the slope has (almost) topped out before it runs
    under the upper cap's overhanging lip; p0 sits >= 2.3 m back, well inside the lower platform."""
    m.ramp(name, p0, p1, width, top_mat=None, bottom=-0.5, extend=0.2)  # short flat ends: no big mats on the caps


def _stone(m, x, y, z, rot=0.0, scale=1.0):
    """Embed a mossy stone in a cliff face (explicit height, no raycast)."""
    m.place("Rock_Cliff_Stone", x, y, z=z, rot=rot, scale=scale)


# ---------------------------------------------------------------------------
# the map
# ---------------------------------------------------------------------------

def build(m):
    L, D = m.size  # 56 x 36

    # ================= terrain: ground chain (front band) =================
    m.terrace("WestPlateau", [(-0.8, -0.8), (10.6, -0.8), (11.2, 6), (10.8, 13), (11.4, 17.5), (6, 20.0),
                              (-0.8, 21.0)], top=PLAT, bottom=-0.5)
    m.terrace("WestStep_A", geo.rounded_rect(10.0, -0.8, 13.4, 5.4, 0.8), top=STEP, bottom=-0.5)
    m.terrace("WestStep_B", geo.rounded_rect(10.0, 9.6, 13.2, 15.6, 0.8), top=STEP, bottom=-0.5)
    # The pale Rainbow Street road (MAIN_ROAD) arrives at west00 from Amherst and runs the whole
    # ground chain to the east plateau. The ramps carry it themselves (cream top, a little wider than
    # the 3.6 m ribbon, no dirt blend collars); ramp tops end 0.1 m inside the plateau/mound outlines,
    # so the road tops out at the cap lip.
    road = dict(top_mat=MAIN_ROAD["mat"], blend=False)
    m.ramp("Ramp_West", (11.0, 7.5, PLAT), (15.6, 7.5, 0.0), 3.9, **road)

    m.terrace("Mound", [(28.0, -0.8), (31.6, -0.8), (31.8, 8), (31.4, 16.8), (28.2, 16.8), (27.8, 8)],
              top=PLAT, bottom=-0.5)
    m.terrace("MoundStep_WA", geo.rounded_rect(25.8, -0.8, 28.6, 6.4, 0.8), top=STEP, bottom=-0.5)
    m.terrace("MoundStep_WB", geo.rounded_rect(25.8, 10.6, 28.6, 16.0, 0.8), top=STEP, bottom=-0.5)
    m.terrace("MoundStep_EA", geo.rounded_rect(31.2, -0.8, 34.0, 5.0, 0.8), top=STEP, bottom=-0.5)
    m.terrace("MoundStep_EB", geo.rounded_rect(31.2, 9.2, 34.0, 16.0, 0.8), top=STEP, bottom=-0.5)
    m.ramp("Ramp_Mound_W", (23.0, 8.5, 0.0), (27.9, 8.5, PLAT), 3.9, **road)
    m.ramp("Ramp_Mound_E", (31.7, 7.1, PLAT), (36.8, 7.1, 0.0), 3.9, **road)

    m.terrace("EastPlateau", [(44.0, -0.8), (56.8, -0.8), (56.8, 36.8), (50.5, 36.8), (48.5, 22.0), (44.4, 17.0),
                              (43.6, 8)], top=PLAT, bottom=-0.5)
    m.terrace("EastStep_A", geo.rounded_rect(41.4, -0.8, 44.4, 4.6, 0.8), top=STEP, bottom=-0.5)
    m.terrace("EastStep_B", geo.rounded_rect(41.4, 8.4, 44.4, 15.6, 0.8), top=STEP, bottom=-0.5)
    m.ramp("Ramp_East", (38.6, 6.5, 0.0), (43.8, 6.5, PLAT), 3.9, **road)

    # the road ribbon, one per flat: each runs 1.2 m onto the cream ramp tops at both ends (same
    # material, so the overlap is invisible and the cap lip over each ramp end stays covered). It starts
    # just outside west00 to meet the trail's apron and stops at the ladder foot on the east plateau:
    # the hidden in00 nook gets no road.
    m.path("Main_Road", [(-0.4, 14.3), (1.6, 13.6), (4.0, 10.9), (7.0, 8.3), (10.2, 7.5), (12.2, 7.5)],
           **MAIN_ROAD)
    m.path("Main_Road_WestHollow", [(14.4, 7.5), (16.6, 7.5), (19.0, 7.8), (22.2, 8.4), (24.2, 8.5)], **MAIN_ROAD)
    m.path("Main_Road_Mound", [(26.7, 8.5), (29.0, 8.5), (30.5, 7.6), (32.9, 7.1)], **MAIN_ROAD)
    m.path("Main_Road_EastHollow", [(35.6, 7.1), (37.6, 6.8), (39.8, 6.5)], **MAIN_ROAD)
    m.path("Main_Road_East", [(42.6, 6.5), (45.2, 6.8), (46.6, 8.6), (46.6, 10.0), (46.2, 13.0), (45.5, 15.6)],
           **MAIN_ROAD)

    # ================= low stepping-stone row T12..T17 + west column =================
    stones = [(10.6, 17.6), (14.4, 18.0), (18.1, 18.3), (21.8, 18.4), (25.5, 18.2), (29.4, 18.0)]
    for i, (x, y) in enumerate(stones):
        m.terrace(f"Stone_T{i + 12}", geo.ellipse(x, y, 2.0, 1.8, 18), top=STONE + 0.08 * (i % 2), bottom=-0.5)
    m.terrace("T18", geo.ellipse(11.0, 22.0, 1.75, 1.6, 16), top=T18_Z, bottom=-0.5)
    _hop(m, "Hop_T12_T18", (11.0, 18.2, STONE), (11.0, 20.5, T18_Z), 2.5)
    m.terrace("T19", geo.ellipse(13.4, 25.2, 2.3, 1.8, 16), top=T19_Z, bottom=-0.5)
    _hop(m, "Hop_T18_T19", (10.9, 21.9, T18_Z), (12.3, 23.75, T19_Z), 2.5)

    # ================= mid band =================
    m.terrace("BerryShelf", [(15.2, 20.2), (23, 19.8), (31.2, 19.9), (31.6, 23.5), (31.2, 27.2), (15.2, 27.0)],
              top=BERRY, bottom=-0.5)
    m.terrace("CloverShelf", [(31.0, 19.6), (39.2, 19.4), (39.4, 26.6), (35.2, 27.0), (35.0, 30.8), (31.0, 30.8)],
              top=CLOVER, bottom=-0.5)
    _hop(m, "Hop_Berry_Clover", (33.8, 24.2, CLOVER), (31.42, 24.2, BERRY), 2.5)
    m.terrace("T23", geo.ellipse(41.2, 21.4, 2.1, 2.1, 18), top=T23_Z, bottom=-0.5)
    _hop(m, "Hop_Clover_T23", (36.9, 21.8, CLOVER), (39.25, 21.8, T23_Z), 2.5)
    m.terrace("T11", geo.ellipse(45.4, 19.6, 2.3, 2.1, 18), top=T11_Z, bottom=-0.5)
    m.terrace("Nook", [(39.2, 24.2), (46.5, 24.0), (50.2, 26.0), (50.6, 36.6), (39.2, 36.6), (39.0, 30)],
              top=NOOK, bottom=-0.5)
    _hop(m, "Hop_T23_Nook", (41.6, 21.9, T23_Z), (41.6, 24.25, NOOK), 2.5)

    # ================= upper band =================
    m.terrace("WestHigh", [(-0.8, 27.0), (16.6, 26.8), (17.2, 31), (16.4, 36.8), (-0.8, 36.8)],
              top=WEST_HI, bottom=-0.5)
    m.terrace("T32", geo.ellipse(14.4, 31.6, 2.0, 1.9, 16), top=T33_Z, bottom=WEST_HI - 0.3)
    m.terrace("Crown", [(16.0, 30.6), (24, 30.3), (35.4, 30.6), (35.6, 36.8), (16.0, 36.8)], top=CROWN,
              bottom=-0.5)
    _hop(m, "Hop_T32_Crown", (13.8, 31.8, T33_Z), (16.1, 31.8, CROWN), 2.5)
    up = [(19.6, 28.8), (23.1, 28.9), (26.6, 28.8), (30.1, 28.9), (33.4, 28.6)]
    for i, (x, y) in enumerate(up):
        m.terrace(f"UpStone_T{i + 27}", geo.ellipse(x, y, 1.85, 1.6, 16), top=UPSTONE + 0.08 * (i % 2),
                  bottom=-0.5)
    m.terrace("T33", [(35.0, 27.2), (39.2, 27.2), (39.4, 32.0), (38.6, 36.8), (35.0, 36.8)], top=T33_Z,
              bottom=-0.5)
    _hop(m, "Hop_T33_Crown", (37.7, 33.6, T33_Z), (35.4, 33.6, CROWN), 2.5)

    # ================= climbables (5 ladders + 6 knotted ropes on pegs) =================
    m.ladder("Ladder_Plateau_T12", 9.9, 15.5, PLAT, STONE, facing=90)
    m.ladder("Rope_Mound_T17", 29.6, 15.8, PLAT, STONE, facing=90, kind="rope")
    m.ladder("Rope_T17_Berry", 30.0, 19.4, STONE, BERRY, facing=90, kind="rope")
    m.ladder("Ladder_Plateau_T11", 45.4, 17.1, PLAT, T11_Z, facing=90)
    m.ladder("Rope_T11_T23", 43.7, 20.8, T11_Z, T23_Z, facing=180, kind="rope")
    m.ladder("Ladder_T19_WestHigh", 13.6, 26.4, T19_Z, WEST_HI, facing=90)
    m.ladder("Rope_WestHigh_T32", 14.4, 29.3, WEST_HI, T33_Z, facing=90, kind="rope")
    m.ladder("Rope_Berry_UpStone", 23.1, 26.8, BERRY, UPSTONE, facing=90, kind="rope")
    m.ladder("Ladder_UpStone_Crown", 20.4, 30.1, UPSTONE, CROWN, facing=90)
    m.ladder("Rope_Clover_UpStone", 33.4, 26.6, CLOVER, UPSTONE, facing=90, kind="rope")
    m.ladder("Ladder_Nook_T33", 39.95, 30.6, NOOK, T33_Z, facing=180)

    # ================= landmarks =================
    # the secret way to the Tomato Field (in00, classic pt=1 hidden portal) on the back edge of the
    # DANGER-sign nook: the path slips into a clipped hedge tunnel in the nook's back hedge. Only a
    # few tomatoes in the leaves hint at it; the giant tomato gate is kept for the Tomato Field side.
    # The mouth sits just behind in00 so the swirl stays visible; walls keep a 4.6 m corridor.
    m.place("Hedge_Tunnel", 42.0, 35.3, rot=0)
    m.place("Hedge_Wall_4m", 45.7, 36.0, rot=0, scale=(1.0, 1.0, 1.15))
    m.place("Bush_A", 45.6, 34.4, rot=30, scale=0.8)
    m.place("Sign_Danger_Diamond", 44.4, 26.6, rot=45, scale=1.25)
    for (x, y, r) in ((45.8, 27.6, 0), (47.0, 26.6, 70), (47.4, 28.6, 140)):
        m.place("Tomato_Plant", x, y, rot=r, scale=1.15)
    # the secluded nook: low growth only (taller things here would hide it from the camera)
    for (a, x, y, r, s) in (("Bush_A", 49.6, 30.0, 0, 0.9), ("Bush_C", 49.2, 34.6, 40, 1.0),
                            ("Flower_Patch_A", 46.4, 32.6, 0, 1.0), ("Flower_Patch_B", 44.6, 30.2, 30, 1.0),
                            ("Stump_A", 48.2, 25.6, 10, 0.8), ("Mushroom_Red_S", 40.0, 33.4, 0, 1.0),
                            ("Mushroom_Orange_S", 40.2, 28.2, 40, 0.9), ("Grass_Tuft_A", 45.0, 34.8, 0, 1.2)):
        m.place(a, x, y, rot=r, scale=s, required=False)
    # east plateau: log pile (set screen-sideways of the mushrooms so the camera sees it) and the
    # giant orange mushroom pair closing the east end
    m.place("X1020000_LogPile", 50.4, 16.6, rot=-20)
    # (scaled up to read as a landmark; caps (~2.7 m radius per unit scale) stay within 1 m of the
    # footprint edge and clear of each other)
    # (sized so their caps do not hide the Main route's turn at the Ramp_East top behind them)
    m.place("Mushroom_Giant_Orange", 53.0, 3.6, rot=20, scale=1.3)
    m.place("Mushroom_Giant_Orange", 53.6, 10.9, rot=-30, scale=1.05)
    m.place("Mushroom_Orange_S", 50.6, 6.4, rot=10)
    m.place("Mushroom_Orange_S", 51.0, 12.8, rot=80, scale=0.8)
    # rainbow springs (two at the west arrival, one on the east plateau); the kit spring is ~1.5x
    # the size of this map's old local one, hence the smaller scales
    m.place("Rainbow_Spring", 4.2, 4.6, rot=-20, scale=0.65)
    m.place("Rainbow_Spring", 7.4, 17.2, rot=10, scale=0.55)
    m.place("Rainbow_Spring", 46.6, 2.8, rot=15, scale=0.6)
    m.place("Sign_Board", 5.6, 12.9, rot=55)  # beside the road where the ladder path forks off
    # mid shelves: red-berry shrub row and the pink clover bed
    # (rot stays near 0: the berries are biased to the asset's camera-facing side)
    for i, (x, y) in enumerate(((17.6, 25.4), (19.4, 25.9), (21.1, 25.4), (25.6, 25.7), (27.3, 25.3),
                                (18.8, 21.0), (22.2, 20.9), (27.9, 21.1))):
        m.place("Berry_Bush", x, y, rot=(-12, 8, -4, 14, -8, 4, -14, 10)[i], scale=0.95 + 0.05 * (i % 2))
    for (a, x, y, r, s) in (("Flower_Patch_A", 21.0, 26.5, 0, 1.0), ("Flower_Patch_A", 24.8, 26.6, 40, 1.1),
                            ("Flower_Patch_A", 28.6, 26.5, 80, 1.0), ("Flower_Patch_A", 18.4, 26.6, 20, 0.9),
                            ("Rock_A", 29.8, 26.7, 30, 0.8)):
        m.place(a, x, y, rot=r, scale=s, required=False)
    m.scatter(["Clover_Patch"], [(34.2, 19.9), (38.6, 19.8), (38.4, 23.2), (34.8, 23.0)], 7, seed=11,
              min_dist=1.0, avoid=[(37.6, 21.8, 1.4)])
    # crown: the two big flowering bushes (one with a butterfly), along the back edge so the crown
    # walk (y ~32) stays open
    m.place("Bush_B", 21.0, 35.1, rot=20, scale=1.3)
    m.place("Flower_Bed_Large", 22.6, 33.9, rot=0, scale=0.85)
    m.place("Bush_Flowering_A", 23.4, 35.6, rot=40, scale=1.1)
    m.place("Bush_B", 29.6, 35.3, rot=-30, scale=1.3)
    m.place("Bush_Flowering_A", 31.6, 35.0, rot=10, scale=1.15)
    m.place("Butterfly", 30.4, 33.7, rot=30)
    # T33: small bushes and white mushrooms
    m.place("Bush_C", 35.9, 35.9, rot=10)
    m.place("Bush_C", 37.6, 29.0, rot=60, scale=0.9)
    m.place("X1020000_WhiteMushrooms", 36.0, 30.0, rot=20)
    m.place("X1020000_WhiteMushrooms", 37.8, 35.6, rot=-40, scale=0.8)
    # west high shelf: two big bushes
    m.place("Bush_B", 4.6, 30.0, rot=10, scale=1.3)
    m.place("Bush_B", 9.0, 31.4, rot=80, scale=1.2)
    m.place("X1020000_WhiteMushrooms", 6.8, 31.2, rot=0, scale=0.9)

    # ================= trees: autumn birch groves =================
    trees = [
        ("Tree_Autumn_A", 3.0, 18.6, 1.15), ("Tree_Birch_Yellow", 0.8, 6.0, 1.0),          # west plateau
        ("Tree_Birch_Orange", 16.4, 2.2, 0.95), ("Tree_Birch_Yellow", 22.4, 3.0, 0.9),     # west hollow
        ("Tree_Birch_Yellow", 37.2, 2.4, 0.85),                                            # east hollow
        # back edge, staggered in depth and spacing (crown trees stay at y >= 34.6, off the crown route)
        ("Tree_Birch_Orange", 1.6, 34.6, 1.05), ("Tree_Birch_Yellow", 6.2, 35.9, 0.9),     # west high
        ("Tree_Autumn_A", 11.2, 33.6, 1.05),
        ("Tree_Birch_Orange", 17.4, 35.6, 0.85), ("Tree_Birch_Yellow", 26.4, 35.3, 1.15),  # crown back edge
        ("Tree_Autumn_A", 34.0, 36.0, 0.9),
        ("Tree_Birch_Orange", 47.2, 1.0, 0.9),                                             # east plateau front
        ("Tree_Birch_Orange", 55.2, 34.6, 0.8), ("Tree_Sapling_A", 54.2, 24.6, 1.1),      # east plateau back
    ]
    for i, (a, x, y, s) in enumerate(trees):
        m.place(a, x, y, rot=i * 47, scale=s)

    # ================= bushes, rocks, flowers =================
    bushes = [(1.2, 1.2), (12.2, 1.0), (14.2, 14.8), (26.4, 1.0), (34.6, 14.8), (40.6, 1.0), (55.4, 1.2),
              (55.6, 17.0), (52.6, 23.6), (54.8, 30.4), (51.6, 35.2), (48.8, 34.4), (49.4, 27.6), (16.4, 22.0),
              None, (38.2, 25.6), (2.2, 22.8)]  # (None: was on the T17 -> berry rope top)
    for i, xy in enumerate(bushes):
        if xy is None:
            continue
        x, y = xy
        m.place(["Bush_A", "Bush_C", "Bush_B", "Bush_Flowering_A"][i % 4], x, y, rot=i * 37,
                scale=0.85 + 0.1 * (i % 3), required=False)
    for (a, x, y, r, s) in (("Rock_B", 14.0, 1.6, 30, 0.9), ("Rock_A", 25.2, 15.0, 0, 1.0),
                            ("Rock_A", 34.6, 1.8, 60, 0.8), ("Rock_C", 40.6, 15.4, 0, 1.2),
                            ("Rock_B", 13.8, 12.0, 120, 0.8), ("Stump_A", 19.0, 1.4, 0, 1.0),
                            ("Stump_A", 29.0, 4.0, 40, 0.8), ("Log_A", 52.0, 18.6, 70, 0.9),
                            ("Rock_A", 54.0, 26.0, 20, 0.9), ("Rock_C", 50.8, 30.6, 0, 1.0),
                            ("Mushroom_Cluster_A", 36.0, 13.6, 30, 1.0), ("Mushroom_Cluster_A", 9.6, 1.8, -20, 1.0),
                            ("Rock_C", 44.2, 31.6, 0, 0.9), ("Stump_A", 4.0, 33.2, 0, 0.9)):
        m.place(a, x, y, rot=r, scale=s, required=False)
    # keep the road, the west ladder approach and the mound rope approach clear of tufts and flowers
    route_band = [geo.rect(0, 5.6, 56, 10.0), (1.0, 14.0, 2.6), (2.8, 12.3, 2.3), (4.6, 10.4, 2.3),
                  geo.rect(43.8, 9, 47.5, 17.5), (6.8, 11.5, 1.5), (8.4, 12.8, 1.5), (9.3, 14.2, 1.5),
                  geo.rect(28.6, 8.0, 30.8, 16.6)]
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 56, 16.5), 34, seed=5,
              min_dist=1.6, avoid=route_band)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B", "Mushroom_Orange_S"], geo.rect(44, 13, 56, 36),
              18, seed=6, min_dist=1.6, z_band=(1.5, 2.5), avoid=[geo.rect(43.8, 9, 47.5, 17.5), (50.4, 16.6, 1.8)])
    for (a, x, y, r, s) in (("Bush_B", 55.4, 21.0, 30, 1.0), ("Flower_Bed_Large", 52.4, 28.8, 0, 0.9)):
        m.place(a, x, y, rot=r, scale=s, required=False)
    # corner dressing where the ramps meet their plateaus (hides the bare ramp-end notch)
    for (a, x, y, r, s) in (("Rock_B", 44.1, 4.6, 20, 0.75), ("Bush_C", 43.8, 9.1, 0, 1.0),
                            ("Rock_A", 28.2, 6.4, 40, 0.9), ("Rock_A", 28.2, 10.6, 110, 0.9)):
        m.place(a, x, y, rot=r, scale=s, required=False)
    stair_feet = [(11.0, 19.9, 1.4), (12.2, 23.7, 1.5), (32.2, 24.2, 1.6), (38.2, 21.8, 1.5), (14.4, 31.8, 1.5),
                  (35.8, 33.6, 1.6)]
    m.scatter(["Grass_Tuft_A", "Flower_Patch_B"], geo.rect(0, 16, 40, 36), 26, seed=7, min_dist=1.8,
              z_band=(3.5, 11.0), avoid=stair_feet)
    m.scatter(["Grass_Tuft_A"], geo.rect(39, 24, 50.5, 36.6), 6, seed=8, min_dist=1.6, z_band=(6.0, 7.0),
              avoid=[geo.rect(39.6, 31, 45.6, 36.6), (41.6, 24.8, 1.4)])

    # embedded stones in the visible cliff faces (+x and -y faces)
    for (x, y, z) in ((17.6, 19.95, 4.7), (23.8, 19.75, 5.0), (28.0, 19.85, 4.6), (32.8, 19.5, 2.4),
                      (35.6, 19.35, 3.8), (37.9, 19.35, 1.4), (3.2, 26.9, 4.8), (7.6, 26.85, 3.0),
                      (11.0, 26.85, 5.8), (14.3, 16.25, 2.0), (21.8, 16.6, 1.4), (25.6, 16.4, 2.8),
                      (45.0, 17.5, 1.9), (26.0, 30.4, 9.6)):
        _stone(m, x, y, z, rot=0)
    for (x, y, z) in ((50.5, 28.6, 3.6), (50.65, 33.2, 4.9), (50.4, 30.8, 5.6), (56.85, 6.0, 0.8),
                      (56.85, 21.0, 1.0), (56.85, 31.0, 0.7), (39.45, 33.6, 8.4), (39.25, 28.2, 8.0),
                      (31.95, 12.0, 1.0), (11.35, 3.0, 0.9), (43.25, 21.0, 4.0)):
        _stone(m, x, y, z, rot=90)
    for (x, y, z, r) in ((50.6, 31.5, 6.5, 90), (50.5, 26.8, 6.5, 90), (24.0, 19.75, 5.75, 0),
                         (36.2, 19.35, 4.95, 0), (39.4, 35.0, 9.7, 90), (9.0, 26.9, 7.35, 0),
                         (43.28, 21.7, 5.75, 90), (29.1, 19.86, 5.75, 0)):  # beside the key-route rope tops
        m.place("Vine_Hanging_A", x, y, z=z, rot=r)

    # ================= gameplay =================
    m.edge_portal("west00")
    m.edge_portal("in00")
    # on the clover bed beside the shelf walk, near GAMEPLAY_FOCUS, ~0.5 m camera-side of the route
    # and turned toward the camera (local look ~(-0.88, +0.47))
    m.player(36.6, 22.6, rot=60)

    # monsters (52 classic spawns: Blue Snail 19, Red Snail 13, Orange Mushroom 12, Snail 8)
    # 14 proxies, one per ~4 spawns, spread over the tiers that have spawns (Red Snails on platforms only)
    m.mobs("Snail", geo.rect(2, 1, 10, 13), 1, seed=2, z_band=(1.5, 2.5))
    m.mobs("Blue Snail", geo.rect(2, 1, 10, 13), 1, seed=21, z_band=(1.5, 2.5))
    m.mobs("Orange Mushroom", geo.rect(15, 1, 25, 15), 1, seed=3, z_band=(-0.2, 0.3))
    m.mobs("Blue Snail", geo.rect(15, 1, 25, 15), 1, seed=4, z_band=(-0.2, 0.3))
    m.mobs("Orange Mushroom", geo.rect(35, 1, 41, 15), 1, seed=5, z_band=(-0.2, 0.3))
    m.mobs("Blue Snail", geo.rect(35, 9, 41, 15), 1, seed=6, z_band=(-0.2, 0.3))
    m.mobs("Orange Mushroom", geo.rect(47, 12, 55, 21), 1, seed=7, z_band=(1.5, 2.5))
    m.mobs("Red Snail", geo.rect(34, 20, 38.5, 26), 1, seed=9, z_band=(4.8, 5.2))
    m.mobs("Orange Mushroom", geo.rect(17, 21, 30, 24.5), 1, seed=11, z_band=(5.6, 6.0))
    m.mobs("Red Snail", geo.rect(43, 28, 50, 33), 1, seed=13, z_band=(6.4, 6.8))
    m.mobs("Snail", geo.rect(1, 28, 12, 35), 1, seed=15, z_band=(7.2, 7.6))
    m.mobs("Blue Snail", geo.rect(1, 28, 12, 35), 1, seed=14, z_band=(7.2, 7.6))
    m.mobs("Orange Mushroom", geo.rect(17, 31, 34, 35), 1, seed=16, z_band=(10.4, 10.8))
    m.mobs("Blue Snail", geo.rect(24, 31, 34, 35), 1, seed=18, z_band=(10.4, 10.8))
    m.mobs("Red Snail", geo.rect(35.5, 28, 38.6, 35), 1, seed=17, z_band=(9.6, 10.0))

    # routes: one connected graph. Routes walk straight through their ladder/rope climbs; the vertex
    # just before each climb is the probed cliff-lip point of the earlier route legs, so each climb is
    # sampled exactly as before (no sample lands in the sliver between two caps).
    # Main: west00 along the ground chain (the road), up the T11 ladder and the T23 rope, over the
    # T23 -> nook hop to the hidden in00.
    m.route("Main", [(1, 14), (5, 10), (9, 7.5), (16, 7.5), (22, 8.5), (29, 8.5), (30.5, 7.6), (37, 7.1),
                     (44.5, 6.5), (46.4, 9.5), (46.0, 13.5), (45.4, 16.4), (45.4, 19.6), (44.6, 20.8),
                     (43.68, 20.97), (42.4, 21.2), (41.6, 21.8), (41.6, 26.2), (42.0, 30.0), (42.0, 35.0)])
    # west plateau ladder onto the low stepping-stone row (leaves the road at a Main vertex)
    m.route("West_LadderStones", [(5, 10), (8.4, 12.8), (9.9, 15.0), (10.2, 17.6), (14.4, 18.0), (18.1, 18.3),
                                  (21.8, 18.4), (25.5, 18.2), (29.4, 18.0)])
    m.route("West_StairsToShelves", [(10.8, 17.4), (11.0, 18.4), (11.0, 21.4), (12.4, 23.8), (13.0, 24.6),
                                     (13.6, 25.0), (16.5, 24.0), (24.0, 23.4), (30.0, 24.2), (33.6, 24.2),
                                     (36.0, 22.4), (37.0, 21.8), (39.4, 21.8), (41.2, 21.6)])
    # mound rope onto T17, then the T17 rope up to the berry shelf walk
    m.route("Mound_RopeT17_Berry", [(29.0, 8.5), (30.0, 10.4), (29.8, 15.0), (29.6, 18.0), (30.0, 19.42),
                                    (30.0, 22.0), (30.0, 24.2)])
    # T19 ladder up to the west high shelf
    m.route("T19_LadderWestHigh", [(13.6, 25.0), (13.6, 26.38), (13.6, 28.2), (7.0, 28.5)])
    # west high rope to T32, the crown walk, T33 and its ladder down into the nook (ends at in00)
    m.route("WestHigh_Crown_Nook", [(13.6, 28.2), (14.4, 28.6), (14.4, 30.5), (13.4, 31.8), (16.6, 31.8),
                                    (20.0, 32.0), (31.0, 32.2), (33.6, 33.4), (34.7, 33.6), (37.0, 33.6),
                                    (37.4, 31.0), (39.5, 30.6), (41.4, 30.6), (42.0, 34.0)])
    # berry shelf rope onto the upper stepping stones, then the ladder onto the crown walk
    m.route("Berry_UpStones_Crown", [(22.83, 23.49), (23.1, 25.0), (23.1, 26.86), (23.1, 28.9), (20.4, 28.8),
                                     (20.4, 30.02), (20.4, 32.0)])
    # clover bed rope onto the upper stepping stones, along the row to the berry rope top
    m.route("Clover_RopeUpStones", [(33.6, 24.2), (33.4, 25.2), (33.4, 26.58), (33.4, 28.6), (30.1, 28.9),
                                    (26.6, 28.8), (23.1, 28.9)])
