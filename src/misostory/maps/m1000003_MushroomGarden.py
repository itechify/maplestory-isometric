"""Mushroom Garden (1000003) - "a walled terrace garden behind a hill door".

Classic (GMS v8) structure, from docs/research/maps/1000003_MushroomGarden_1000003.md:
  G1 long lawn (Shroom field: white birches, berry hedges, big bushes) -> three 60 px garden
  steps G2/G3 -> G4 door terrace with the round barrel door set into a grassy hill (P02,
  flower bed on top, short ladder on its face). Above, one continuous zig-zag stair of
  168 px stepping stones: from the door hill P02 -> P04 -> P06 -> central terrace P07; a
  second stair from the lawn (ladder -> P01 -> rope -> west terrace P03 -> P05 -> P07); then
  P08/P09 -> upper terrace P10 -> P11/P12 -> top terrace P14, with P13 one drop lower.
  Mobs: Shroom 28, Snail 9, Orange Mushroom 5. No NPCs.

3D translation: the layout puts the door (out00) at the back-left, so the door terrace and
its hill sit at the back-left above three stepped garden beds that run down to a front
lawn. The garden terraces climb as an amphitheatre on the right half (P01 rock pillar ->
P03 -> P07 -> P10 -> P14/P13), each tier further back. Every classic stepping stone becomes a
giant flat-topped mushroom cap (with a smaller cap between, 0.4 m per step) so the garden
earns its name: three mushroom staircases wind up the hill. There are no small decor mushrooms
(only giant ones on the edges and the back bed), so the Shroom and Orange Mushroom proxies read as
the only small mushrooms.
"""


from misostory import core, geo
from misostory.geo import MeshBuilder
from misostory.kit import asset

MAP_ID = 1000003
GAMEPLAY_FOCUS = (19.0, 15.0)
GAMEPLAY_SCALE = 36.0

# heights: one classic 60 px step = 0.8 m
G2, G3, G4 = 0.8, 1.6, 2.4
P01 = 2.8
P02 = 4.4
P03 = 5.2
P07 = 6.8
P10 = 9.2
P13 = 10.8
P14 = 11.6
BACKBED = 3.4
CAP_STEP = 0.4

CAP_MATS = {
    "red": "M_Spot_mush_red__mush_spot",
    "orange": "M_Spot_mush_orange__mush_spot",
    "blue": "M_Spot_mush_blue__mush_spot",
    "yellow": "M_Spot_mush_yellow__mush_spot",
}


# ---------------------------------------------------------------------------
# local assets (map-prefixed; candidates for the shared kit)
# ---------------------------------------------------------------------------

@asset("X1000003_Berry_Hedge", "Foliage", footprint=3.0, tags=("bush", "hedge"))
def _berry_hedge(coll):
    """3 m red-berry hedge (grassySoil nature/0) along +X, centred on the origin."""
    r = core.rng("x1000003_berry", 1)
    mb = MeshBuilder()
    mb.box((3.0, 0.9, 0.75), loc=(0, 0, 0.42), mat="M_Bush", bevel=0.3, segs=3)
    for k in range(5):
        mb.sphere(r.uniform(0.36, 0.48), loc=(-1.2 + k * 0.6, r.uniform(-0.12, 0.12), r.uniform(0.72, 0.9)),
                  scale=(1.1, 1.0, 0.8), mat="M_Bush", subdiv=2, lumpy=0.1, seed=k)
    mb.build("X1000003_Berry_Hedge", coll, smooth=True, sharp_angle=70)
    berries = MeshBuilder()
    for k in range(30):
        x = r.uniform(-1.35, 1.35)
        if k % 3 == 0:
            p = (x, r.uniform(-0.3, 0.25), r.uniform(1.0, 1.18))
        else:
            p = (x, -0.47 - r.uniform(0.0, 0.05), r.uniform(0.25, 0.8))
        berries.sphere(0.075, loc=p, mat="M_Flat_flower_red", subdiv=1)
    berries.build("X1000003_Berry_Hedge_Flowers", coll, smooth=True)


# ---------------------------------------------------------------------------
# climbables and cliff dressing
# ---------------------------------------------------------------------------

def cap_edge(m, x, y, z_top, step=0.04, max_d=3.0):
    """First y (scanning +y from y) where the ground reaches the tier at z_top: its grass-cap edge."""
    t = 0.0
    while t <= max_d:
        g = m.ground_z(x, y + t)
        if g is not None and g > z_top - 0.3:
            return y + t
        t += step
    return y + 0.3


def leafy_strand(m, name, x, y, z_top, length, seed=0):
    """Decorative leafy strand hanging down a cliff face from under a grass lip."""
    r = core.rng(m.slug, name, seed)
    mb = MeshBuilder()
    p = m.w(x, y, z_top)
    mb.cyl(0.05, length, loc=(p.x, p.y, p.z - length), mat="M_Flat_grass_dark", verts=6)
    z = 0.2
    k = 0
    while z < length:
        s = 1 if k % 2 else -1
        mb.sphere(0.2, loc=(p.x + s * 0.16, p.y - 0.05, p.z - z), scale=(1.3, 0.55, 0.85), mat="M_Leaf", subdiv=1)
        if k % 2 == 0:
            mb.sphere(0.14, loc=(p.x - s * 0.13, p.y - 0.07, p.z - z - 0.12), scale=(1.2, 0.5, 0.8), mat="M_Leaf_B",
                      subdiv=1)
        z += 0.36 + r.uniform(-0.04, 0.04)
        k += 1
    mb.build(m._name(name), m.col_veg, smooth=True, sharp_angle=60)


# ---------------------------------------------------------------------------
# walkable giant mushrooms (built as terrain so they can be walked on)
# ---------------------------------------------------------------------------

def shroom_cap(m, name, x, y, top, r, mat, bottom, thick=0.55):
    """A giant flat-topped mushroom: walkable cap disc at local height `top`, stem to `bottom`."""
    wv = m.w(x, y, top)
    cap = MeshBuilder()
    cap.cyl(r, thick, loc=(wv.x, wv.y, wv.z - thick), mat=mat, verts=28, bevel=0.17, segs=2)
    cap.cyl(r * 0.86, 0.1, loc=(wv.x, wv.y, wv.z - thick - 0.06), mat="M_Flat_mush_stem_dk", verts=24)
    cap_obj = cap.build(m._name(name + "_Cap"), m.col_terrain, smooth=True, sharp_angle=50)
    m.add_ground(cap_obj)
    h = (top - thick) - bottom
    if h > 0.15:
        sr = 0.3 + r * 0.2
        st = MeshBuilder()
        wb = m.w(x, y, bottom)
        st.cyl(sr * 1.35, 0.45, loc=(wb.x, wb.y, wb.z - 0.1), mat="M_MushStem", verts=16, r2=sr)
        st.cyl(sr, h + 0.05, loc=(wb.x, wb.y, wb.z), mat="M_MushStem", verts=16, r2=sr * 0.82)
        st.build(m._name(name + "_Stem"), m.col_veg, smooth=True, sharp_angle=50)
    return cap_obj


def shroom_chain(m, name, z0, caps):
    """Staircase of giant mushroom caps rising CAP_STEP each, starting CAP_STEP above z0.

    caps: list of (x, y, r, color). Stem bottoms are found before any cap of the chain is
    added to the ground index, so stems reach the terrain, not the neighbouring caps.
    """
    specs = []
    for i, (x, y, r, color) in enumerate(caps):
        top = z0 + CAP_STEP * (i + 1)
        b = m.ground_z(x, y, z_from=top - 0.8)
        specs.append((x, y, top, r, color, 0.0 if b is None else b))
    for i, (x, y, top, r, color, b) in enumerate(specs):
        shroom_cap(m, f"{name}_{i}", x, y, top, r, CAP_MATS[color], b)
    return [(x, y) for (x, y, _t, _r, _c, _b) in specs]


# ---------------------------------------------------------------------------

def build(m):
    L, D = m.size  # 36 x 30
    av = []  # prop footprints that mob proxies must avoid

    def put(asset_name, x, y, rad, **kw):
        obj = m.place(asset_name, x, y, **kw)
        av.append((x, y, rad))
        return obj

    # ---------------- terrain: left half (door complex + garden steps) ----------------
    door_terrace = [(-0.8, 18.5), (5, 17.8), (10, 18.2), (14, 19.0), (18.6, 19.5), (18.8, 25.0), (17.8, 31.0),
                    (-0.8, 31.0)]
    m.terrace("DoorTerrace_G4", door_terrace, top=G4, bottom=-0.5)
    # the door hill: a west arm reaches toward the arrival swirl (out00 at (6, 29)) and carries the
    # barrel door in its camera-facing front; the trail strip x 3.75-8.25 stays open ground
    m.terrace("DoorHill_P02", [(8.9, 31.0), (8.9, 28.3), (9.6, 27.5), (12.5, 27.4), (13.1, 26.6), (13.3, 24.6),
                               (14.4, 23.5), (17.2, 23.5), (18.3, 24.6), (18.3, 31.0)], top=P02, bottom=G4 - 0.4)
    m.terrace("GardenStep_G3", [(-0.8, 14.5), (6, 13.8), (11, 14.2), (15, 15.2), (18.5, 15.5), (18.6, 20.0),
                                (-0.8, 20.0)], top=G3, bottom=-0.5)
    m.terrace("GardenStep_G2", [(-0.8, 10.6), (5, 10.0), (10, 10.4), (13.5, 11.5), (15.5, 14.5), (15, 16.0),
                                (-0.8, 16.0)], top=G2, bottom=-0.5)
    stone = dict(mat="M_StoneWall", side_mat="M_Rock")
    m.stairs("Steps_Lawn_G2", (4.0, 8.2, 0.0), (4.0, 10.8, G2 + 0.03), 2.8, **stone)
    m.stairs("Steps_G2_G3", (8.0, 11.8, G2), (8.0, 14.6, G3 + 0.03), 2.8, **stone)
    m.stairs("Steps_G3_G4", (5.0, 15.6, G3), (5.0, 18.5, G4 + 0.03), 2.8, **stone)
    # back garden bed filling the hollow between the door hill and the top terrace (it runs in
    # under P07's notched back edge so the notch shows bed, not a pit)
    m.terrace("BackBed", [(17.6, 21.4), (25.8, 21.4), (26.0, 31.0), (17.6, 31.0)], top=BACKBED, bottom=G4 - 0.4,
              fringe=False)

    # ---------------- terrain: right half (the terraced garden hill) ----------------
    m.terrace("WestTerrace_P03", [(26.5, 11.5), (30, 10.5), (36.8, 10.5), (36.8, 18.6), (27, 18.6), (26, 15)],
              top=P03, bottom=-0.5)
    m.terrace("RockPillar_P01", geo.ellipse(32.5, 9.4, 1.9, 1.7, 18), top=P01, bottom=-0.5, style="grass_stone")
    m.ladder("Ladder_Lawn_P01", 32.5, 7.2, 0.0, P01, facing=90)
    # kit knotted rope: hung plumb off the P03 face, climb position 0.3 m in front of the cap edge
    m.ladder("Rope_P01_P03", 33.3, cap_edge(m, 33.3, 9.2, P03) - 0.3, P01, P03, facing=90, kind="rope")
    # P07's back edge is notched to y ~22 at x 20-25 so the east mushroom stair behind it shows its caps
    m.terrace("Central_P07", [(17.5, 14.5), (21, 13.2), (25.6, 12.8), (26.5, 17), (26, 21), (25.3, 22.0),
                              (23.0, 21.9), (20.4, 22.1), (18.9, 21.7), (17.8, 20.5)], top=P07, bottom=-0.5)
    m.terrace("Upper_P10", [(27.2, 18.0), (36.8, 18.0), (36.8, 24.6), (30, 24.6), (27.5, 23.5)], top=P10,
              bottom=P03 - 0.4)
    m.terrace("Top_P14", [(25.8, 24.2), (31.5, 23.8), (32.5, 26), (32.2, 31.0), (25.8, 31.0)], top=P14,
              bottom=BACKBED - 0.4)
    m.terrace("TopRight_P13", [(32.0, 25.2), (36.8, 25.0), (36.8, 31.0), (32.0, 31.0)], top=P13, bottom=P10 - 0.4)
    # classic: a 60 px hop between P14 and P13; three stone treads keep it walkable both ways
    m.stairs("Steps_P13_P14", (34.0, 28.2, P13), (31.9, 28.2, P14), 2.2, **stone)

    # ---------------- the three mushroom staircases ----------------
    # east stair (the classic main stair): door hill P02 -> (P04) -> (P06) -> central terrace P07.
    # Caps overlap ~0.4-0.5 m and curl forward into P07's notch; each cap's front edge sits far
    # enough behind P07's back edge (>= 1.2 x the height difference) for its top to show.
    east = shroom_chain(m, "Shroom_East", P02, [(19.0, 27.9, 1.3, "yellow"), (21.4, 27.8, 1.5, "red"),
                                                (23.4, 26.8, 1.3, "blue"), (24.0, 24.6, 1.4, "orange"),
                                                (22.6, 23.2, 1.35, "yellow")])
    # west stair: P03 -> (P05) -> P07
    west = shroom_chain(m, "Shroom_West", P03, [(27.8, 11.4, 1.3, "yellow"), (26.4, 10.6, 1.5, "red"),
                                                (25.4, 12.3, 1.4, "blue")])
    # P07 -> (P08) -> (P09) -> P10, climbing along the back of P03
    mid = shroom_chain(m, "Shroom_Mid", P07, [(26.9, 16.8, 1.3, "yellow"), (28.6, 16.3, 1.5, "orange"),
                                              (30.3, 16.4, 1.3, "blue"), (32.0, 16.6, 1.5, "red"),
                                              (33.6, 17.4, 1.3, "yellow")])
    # P10 -> (P11) -> (P12) -> top terrace P14
    top = shroom_chain(m, "Shroom_Top", P10, [(35.2, 22.6, 1.3, "blue"), (33.6, 23.1, 1.5, "red"),
                                              (31.9, 23.0, 1.3, "yellow"), (30.2, 22.6, 1.5, "orange"),
                                              (28.8, 23.4, 1.3, "blue")])

    # ---------------- paths ----------------
    m.path("Path_Door", [(6, 29.8), (6, 28.0), (5.6, 23.5), (5.0, 19.4)], width=2.6)
    m.path("Path_DoorStep", [(5.9, 25.2), (8.4, 25.9), (10.3, 26.5)], width=1.8)
    m.path("Path_Lawn", [(4.0, 7.4), (9, 6.2), (18, 6.0), (26, 6.4), (32.5, 5.6)], width=2.8)

    # ---------------- landmark: the barrel door in its hill ----------------
    # the classic wooden door sits in the door hill's face beside the arrival swirl, with the short
    # ladder fixed to the same face just to its right (classic ladder x 2598 beside the door)
    fp = m.face_point(10.3, 29.5, 0, -1, drop=1.0)
    door_y = (fp[1] if fp else 27.4) + 0.02
    m.place("Hill_Door", 10.3, door_y, z=G4 - 0.02)
    fpl = m.face_point(12.0, 29.5, 0, -1, drop=1.0)
    lad_y = (fpl[1] if fpl else 27.4) - 0.3
    m.ladder("Ladder_DoorHill", 12.0, lad_y, G4, P02, facing=90)
    for (x, y) in [(3.0, 27.0), (2.2, 25.0), (8.6, 23.4)]:
        m.place("Clover_Patch", x, y, rot=x * 20)
    m.place("Flower_Bed_Large", 3.4, 23.6, rot=30, scale=0.8)
    m.place("Sign_Board", 10.8, 19.2, rot=-15)
    m.place("Mushroom_Giant_Orange", 1.2, 22.5, rot=30, scale=1.25)
    m.place("Clover_Patch", 2.6, 20.0, rot=-20)
    m.place("Iris_Patch", 3.3, 20.5, rot=40)
    # door hill crown: marigolds + clover (classic orange flowers and clover on P02)
    for i, (x, y) in enumerate([(10.2, 29.9), (14.4, 25.4), (15.6, 26.6), (16.4, 24.6), (15.2, 29.9), (12.6, 30.2)]):
        put("Marigold_Patch" if i % 2 == 0 else "Clover_Patch", x, y, 0.7, rot=i * 47)
    put("Mushroom_Giant_Orange", 17.0, 30.4, 1.5, rot=60, scale=0.9)

    # ---------------- lawn dressing: white birches among berry hedges ----------------
    put("Tree_Birch_Teal", 1.0, 8.6, 0.9, rot=20, scale=0.95)
    m.place("Tree_Birch_Green", 0.8, 16.8, rot=110, scale=0.85)
    m.place("Tree_Birch_Green", 0.9, 28.2, rot=200, scale=0.9)
    m.place("Tree_Birch_Teal", 36.0, 12.8, rot=60, scale=0.8)
    put("Tree_Birch_Green", 12.2, 9.9, 0.9, rot=150, scale=0.9)
    put("Tree_Birch_Teal", 22.4, 11.6, 0.9, rot=80)
    put("Tree_Birch_Green", 35.8, 7.4, 0.9, rot=250, scale=0.75)
    for i, (x, y, rr) in enumerate([(9.4, 8.9, 0), (17.6, 11.2, 4), (26.4, 8.4, -8)]):
        put("X1000003_Berry_Hedge", x, y, 1.6, rot=rr)
    put("Bush_B", 15.4, 9.6, 1.0, rot=80, scale=0.9)
    put("Flower_Bed_Large", 20.0, 9.6, 1.1, rot=10)
    put("Flower_Bed_Large", 2.2, 4.6, 1.0, rot=40, scale=0.9)
    put("Bush_A", 19.0, 12.0, 0.8, rot=50)
    put("Flower_Patch_A", 28.2, 9.4, 0.6, rot=-30)
    put("Mushroom_Giant_Red", 0.9, 1.2, 1.5, rot=-20, scale=1.0)
    put("Mushroom_Giant_Orange", 36.2, 1.8, 1.3, rot=40, scale=0.85)
    # the spawn lawn carries only flowers and clover, so the Shroom proxies read as the mushrooms here
    for (x, y, a, s) in [(7.6, 2.0, "Flower_Patch_A", 1.0), (13.0, 3.0, "Clover_Patch", 1.0),
                         (20.5, 2.5, "Flower_Patch_B", 1.0), (30.0, 2.2, "Clover_Patch", 1.0),
                         (27.4, 1.0, "Marigold_Patch", 1.0), (11.4, 1.4, "Iris_Patch", 1.0)]:
        put(a, x, y, 0.6, rot=x * 23, scale=s)
    put("Stump_A", 16.4, 3.6, 0.7, rot=10)
    m.scatter(["Clover_Patch", "Grass_Tuft_A", "Flower_Patch_A"], geo.rect(0.5, 0.5, 31, 9.5), 22, seed=4,
              min_dist=1.5, avoid=[geo.rect(2.4, 4.6, 33.5, 7.6), geo.rect(2.0, 7.0, 6.0, 11.0)] + av,
              z_band=(-0.2, 0.3))
    for (x, y, a) in [(6.0, 3.6, "Butterfly_Pink"), (23.4, 3.2, "Butterfly_Yellow"),
                      (33.4, 2.8, "Butterfly_Pink")]:
        m.place(a, x, y, rot=x * 13, scale=1.4)

    # garden steps: little beds along their fronts
    for (x, y) in [(1.5, 12.0), (11.6, 12.4), (1.2, 16.5), (12.5, 17.0), (15.6, 18.2)]:
        m.place("Clover_Patch", x, y, rot=x * 31)
    m.place("X1000003_Berry_Hedge", 11.2, 15.8, rot=8, scale=0.8)
    m.place("Marigold_Patch", 14.6, 13.6, rot=70)
    m.place("Clover_Patch", 14.0, 12.9, rot=20)
    for (x, y, a, s) in [(2.4, 13.0, "Flower_Patch_B", 1.0), (10.2, 13.2, "Flower_Patch_A", 1.0),
                         (3.0, 17.4, "Iris_Patch", 1.0), (13.6, 18.6, "Marigold_Patch", 1.0),
                         (7.2, 21.2, "Flower_Patch_B", 1.0)]:
        m.place(a, x, y, rot=x * 29, scale=s)
    # rocks and a log at the cliff feet; the tall P07 face gets half-buried boulders and leafy strands
    for (x, y, a, s) in [(16.6, 12.6, "Rock_A", 0.8), (24.2, 8.0, "Rock_C", 1.0), (29.2, 9.4, "Rock_B", 0.6),
                         (16.8, 22.4, "Rock_C", 0.9)]:
        put(a, x, y, 0.6, rot=x * 41, scale=s)
    for (x, y, a, s) in [(19.6, 13.4, "Rock_A", 1.1), (21.2, 12.9, "Rock_C", 1.3), (23.9, 12.5, "Rock_A", 0.9)]:
        put(a, x, y, 0.8, rot=x * 53, scale=s, sink=0.25 * s)
    for i, (x, ln) in enumerate([(17.9, 2.4), (18.8, 1.6), (19.7, 2.9), (24.9, 2.0)]):
        ye = cap_edge(m, x, 11.0, P07)
        leafy_strand(m, f"Strand_P07_{i}", x, ye + 0.12, P07 - 0.2, ln, seed=i)
    put("Log_A", 7.2, 9.3, 0.9, rot=-6, scale=0.75)

    # ---------------- terraces dressing ----------------
    # P07 central terrace: clover bed
    for (x, y) in [(19.0, 15.2), (21.0, 20.9), (18.8, 19.6), (22.4, 14.6), (19.4, 20.8)]:
        put("Clover_Patch", x, y, 0.6, rot=y * 17)
    put("Bush_C", 25.2, 20.4, 0.5)
    put("Flower_Bed_Large", 20.6, 17.6, 1.1, rot=20)
    put("Flower_Bed_Large", 23.6, 19.0, 1.0, rot=-30, scale=0.85)
    put("Marigold_Patch", 24.6, 14.2, 0.6, rot=50)
    # P03 west terrace: red-berry hedge
    put("X1000003_Berry_Hedge", 31.4, 14.6, 1.6, rot=0)
    put("Bush_A", 36.0, 11.6, 0.8)
    put("Clover_Patch", 35.6, 14.4, 0.6)
    # P10 upper terrace: clover bed and a berry bush
    for (x, y) in [(29.0, 19.6), (36.0, 19.4), (31.0, 20.6)]:
        put("Clover_Patch", x, y, 0.6, rot=x * 9)
    put("Bush_Flowering_A", 36.0, 21.2, 0.9, rot=20)
    m.place("Mushroom_Giant_Blue", 36.2, 24.0, rot=-30, scale=0.85)
    # P14 top terrace: berry hedges and clover
    put("X1000003_Berry_Hedge", 27.6, 30.0, 1.6, rot=0)
    put("X1000003_Berry_Hedge", 30.7, 30.2, 1.6, rot=-6)
    for (x, y) in [(26.6, 26.4), (31.2, 26.8), (29.8, 29.6), (26.4, 28.8)]:
        put("Clover_Patch", x, y, 0.6, rot=y * 23)
    put("Flower_Bed_Large", 30.8, 25.4, 1.0, rot=15, scale=0.8)
    m.place("Butterfly_Yellow", 30.4, 26.4, rot=40, scale=1.4)
    # P13 top-right: big bush, dark bush and purple irises
    put("Bush_B", 35.6, 30.0, 1.2, rot=30, scale=1.2)
    put("Bush_A", 33.6, 30.4, 0.8, rot=-20)
    for (x, y) in [(33.4, 26.6), (35.0, 26.8), (36.0, 28.2)]:
        put("Iris_Patch", x, y, 0.6, rot=x * 41)
    m.place("Mushroom_Giant_Red", 36.2, 30.8, rot=200, scale=1.4, required=False)
    # back bed behind the stairs: a giant mushroom grove
    m.place("Mushroom_Giant_Blue", 25.0, 30.4, rot=-10, scale=1.0)

    # ---------------- gameplay ----------------
    m.edge_portal("out00")
    m.player(7.4, 26.2, rot=-160)
    m.mobs("Shroom", geo.rect(1, 1, 30, 9.5), 3, seed=1, z_band=(-0.2, 0.3), avoid=av)
    m.mobs("Orange Mushroom", geo.rect(10, 1.5, 28, 9.5), 1, seed=2, z_band=(-0.2, 0.3), min_dist=3.0, avoid=av)
    m.mobs("Shroom", geo.rect(12.8, 24.2, 17.6, 30.5), 1, seed=3, z_band=(P02 - 0.2, P02 + 0.3), avoid=av)
    m.mobs("Shroom", geo.rect(18, 14, 25.5, 22.5), 1, seed=4, z_band=(P07 - 0.2, P07 + 0.3), avoid=av)
    m.mobs("Snail", geo.rect(28, 11, 36.5, 14.5), 1, seed=5, z_band=(P03 - 0.2, P03 + 0.3), avoid=av)
    m.mobs("Shroom", geo.rect(28, 18.5, 36.5, 21.5), 1, seed=6, z_band=(P10 - 0.2, P10 + 0.3), avoid=av)
    p14 = m.mobs("Shroom", geo.rect(26, 25, 32, 30.5), 1, seed=7, z_band=(P14 - 0.2, P14 + 0.3), avoid=av)
    m.mobs("Orange Mushroom", geo.rect(26, 25, 32, 30.5), 1, seed=8, z_band=(P14 - 0.2, P14 + 0.3), min_dist=3.0,
           avoid=av + [(x, y, 2.2) for x, y in p14])
    m.mobs("Snail", geo.rect(32.5, 25.5, 36.5, 30.5), 1, seed=9, z_band=(P13 - 0.2, P13 + 0.3), avoid=av)

    # routes walk straight through ladder/rope climbs (the validator treats steps beside a climbable
    # as climbs); every route is checked in both directions
    m.route("Main", [(6.0, 29.4), (6.0, 28.0), (5.6, 23.5), (5.0, 19.6), (5.0, 15.3), (8.0, 15.3), (8.0, 11.5),
                     (4.0, 11.5), (4.0, 7.6), (12, 6), (24, 6.5), (32.5, 5.0)])
    m.route("DoorHillStair", [(5.6, 24.4), (8.4, 25.6), (12.0, lad_y - 0.9), (12.0, lad_y + 1.5), (13.8, 28.8),
                              (16.8, 27.8)] + east + [(22.6, 20.6), (22.0, 18.0)])
    m.route("LawnToCentral", [(32.5, 5.0), (32.5, 9.6), (33.3, 9.6), (33.3, 12.8), (29.6, 12.4)] + west +
            [(24.0, 15.5)])
    m.route("ToTop", [(24.0, 16.0)] + mid + [(33.8, 20.0)] + top + [(28.6, 25.4), (28.4, 27.6), (30.2, 28.2),
                                                                     (35.0, 27.8)])
