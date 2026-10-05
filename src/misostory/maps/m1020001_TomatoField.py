"""Tomato Field (1020001) - "a hidden farm with a trellis boardwalk over the tomato beds".

Classic (GMS v8) structure, from docs/research/maps/1020001_TomatoField_1020001.md:
  one continuous ground chain of gentle slopes (no steps): west bank (out00, autumn tree
  pair) -> slope down into the long west furrow (32 tomato plants) -> slope up to the central
  hump (yellow tree) -> slope down into the east furrow -> long 120 px rise to the east bank
  (tree pair). High above, 17 small platforms form one zig-zag canopy walk (rows -145..-325,
  apex T26) reached only by five long leafy vines, one per ground zone. 72 tomato plants,
  quiet RestNPeace mood, a dead end reached through the hidden portal on the East Field.
  Mobs on the ground only: Snail, Blue Snail, Red Snail, Orange Mushroom. No NPCs.

3D translation: a walled-off farm. The two furrows are sunken planted beds whose ridged
tomato rows run INTO depth so the monsters wander between them; the hump and the east bank
are grassy rises joined by full-width grass slopes (so the field's front edge still shows
the classic rolling profile). The canopy becomes a wooden trellis boardwalk on posts along
the back of the field: 17 decks, each row 0.4 m higher and 1.5 m further back than the one
below, so the zig-zag reads in depth as well as height. Five vine-wrapped ropes climb to it
from the farm track. The arrival (out00) is a hedge gap under the tomato-capped barrel gate;
the East Field end of the secret path is a plain clipped hedge tunnel, so the giant tomato
is only revealed here. The full-width slopes stop 0.6 m short of the front edge, where
clipped hedgerows screen their side wedges.
"""

import math

from misostory import core, geo
from misostory.geo import MeshBuilder
from misostory.kit import asset

MAP_ID = 1020001
GAMEPLAY_FOCUS = (27.0, 13.0)
GAMEPLAY_SCALE = 36.0

BANK = 1.2       # west bank and central hump (2D y=215)
EAST = 2.4       # east bank (2D y=155)
RIDGE = 0.28     # planted ridge height above its furrow
ROW_Z = (4.6, 5.0, 5.4, 5.8)      # canopy rows y=-145, -205, -265, -325
ROW_Y = (18.5, 20.0, 21.5, 23.0)  # each higher row sits 1.5 m further back
DECK_D = 3.0
SLOPE_Y0 = 0.6   # the full-width slopes start here (the strip in front holds the field-edge hedgerows)

# canopy decks west -> east in walking order: (name, x0, x1, row), 2D x mapped at 0.0203 m/px
DECKS = [("T10", 3.65, 7.06, 0), ("T11", 7.3, 10.7, 0), ("T12", 9.1, 12.5, 1), ("T18", 12.8, 16.2, 2),
         ("T13", 14.6, 18.0, 1), ("T19", 18.3, 21.7, 2), ("T14", 20.1, 23.5, 1), ("T20", 23.7, 27.1, 2),
         ("T21", 27.4, 30.8, 2), ("T15", 29.2, 32.6, 1), ("T22", 32.9, 36.3, 2), ("T26", 34.7, 38.1, 3),
         ("T23", 36.5, 39.9, 2), ("T16", 40.1, 43.6, 1), ("T17", 43.8, 47.2, 1), ("T24", 47.5, 50.9, 2),
         ("T25", 51.1, 54.6, 2)]


# ---------------------------------------------------------------------------
# local assets
# ---------------------------------------------------------------------------

@asset("X1020001_CratesTomatoes", "Props", footprint=1.4, tags=("prop", "farm"))
def _crate_tomatoes(coll):
    """Open harvest crate heaped with ripe tomatoes."""
    mb = MeshBuilder()
    mb.box((1.1, 0.8, 0.5), loc=(0, 0, 0.25), mat="M_Plank", bevel=0.04, segs=1)
    for x in (-0.56, 0.56):
        mb.box((0.06, 0.84, 0.54), loc=(x, 0, 0.27), mat="M_Wood_Dark")
    mb.build("X1020001_CratesTomatoes", coll, smooth=False)
    r = core.rng("x1020001_crate", 1)
    tm = MeshBuilder()
    for k in range(9):
        x = -0.36 + (k % 3) * 0.36 + r.uniform(-0.05, 0.05)
        y = -0.22 + (k // 3) * 0.22 + r.uniform(-0.04, 0.04)
        tm.sphere(0.15, loc=(x, y, 0.55 + r.uniform(0, 0.06)), scale=(1, 1, 0.85), mat="M_Tomato", subdiv=2)
    tm.build("X1020001_CratesTomatoes_Fruit", coll, smooth=True)


@asset("X1020001_TrellisArch", "Architecture", footprint=2.6, tags=("farm",))
def _trellis_arch(coll):
    """Garden trellis arch over the farm track, wound with tomato vines (front faces -Y)."""
    r = core.rng("x1020001_trellis", 3)
    mb = MeshBuilder()
    hw = 1.7  # half width: posts stand just outside a 3 m farm track
    for x in (-hw, hw):
        for y in (-0.35, 0.35):
            mb.box((0.12, 0.12, 2.6), loc=(x, y, 1.3), mat="M_Wood", bevel=0.02, segs=1)
        for z in (0.8, 1.6):
            mb.box((0.06, 0.8, 0.06), loc=(x, 0, z), mat="M_Wood_Dark")
    for k in range(9):
        a = math.pi * (k + 0.5) / 9
        ang = math.degrees(math.atan2(math.cos(a) * 0.6, math.sin(a) * hw))
        mb.box((0.62, 0.86, 0.08), loc=(-math.cos(a) * hw, 0, 2.6 + math.sin(a) * 0.6), rot=(0, -ang, 0),
               mat="M_Plank")
    mb.build("X1020001_TrellisArch", coll, smooth=False)
    lv = MeshBuilder()
    for k in range(18):
        side = -hw if k % 2 else hw
        z = r.uniform(0.4, 2.7)
        lv.sphere(0.2, loc=(side + r.uniform(-0.12, 0.12), r.uniform(-0.4, 0.4), z), scale=(1.1, 1.1, 0.8),
                  mat="M_Bush", subdiv=1, lumpy=0.2, seed=k)
    for k in range(6):
        side = -hw if k % 2 else hw
        lv.sphere(0.11, loc=(side + r.uniform(-0.15, 0.15), -0.42, r.uniform(0.6, 2.3)), mat="M_Tomato", subdiv=1)
    lv.build("X1020001_TrellisArch_Vines", coll, smooth=True, sharp_angle=60)


@asset("X1020001_DeckFrame", "Architecture", footprint=3.8, tags=("farm",))
def _deck_frame(coll):
    """Under-structure of one 3.8 x 3.0 m trellis deck: rim beams, corner brackets and a
    criss-cross trellis lattice on the front face. Origin = deck underside center."""
    mb = MeshBuilder()
    w, d = 3.8, 3.0
    for y in (-d / 2 + 0.06, d / 2 - 0.06):
        mb.box((w - 0.1, 0.14, 0.3), loc=(0, y, -0.15), mat="M_Wood_Dark", bevel=0.03, segs=1)
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        mb.box((0.14, d - 0.1, 0.3), loc=(x, 0, -0.15), mat="M_Wood_Dark", bevel=0.03, segs=1)
    # front trellis lattice between the front legs
    span = w - 0.8
    for s in (-1, 1):
        for k in range(3):
            x = -span / 2 + span * (k + 0.5) / 3
            mb.box((0.06, 0.05, 1.45), loc=(x, -d / 2 + 0.22, -0.95), rot=(0, s * 35, 0), mat="M_Wood")
    mb.box((span, 0.06, 0.08), loc=(0, -d / 2 + 0.22, -1.55), mat="M_Wood")
    # corner brackets
    for x in (-w / 2 + 0.3, w / 2 - 0.3):
        for y in (-d / 2 + 0.3, d / 2 - 0.3):
            sx = 1 if x < 0 else -1
            mb.box((0.08, 0.08, 0.8), loc=(x + sx * 0.25, y, -0.45), rot=(0, sx * 40, 0), mat="M_Wood")
    mb.build("X1020001_DeckFrame", coll, smooth=False)


@asset("X1020001_TrellisLeg", "Architecture", footprint=0.3, tags=("farm",))
def _trellis_leg(coll):
    """Square trellis post, 1 m tall (scale z to length), origin at its foot."""
    mb = MeshBuilder()
    mb.box((0.24, 0.24, 1.0), loc=(0, 0, 0.5), mat="M_Wood", bevel=0.03, segs=1)
    mb.build("X1020001_TrellisLeg", coll, smooth=False)


@asset("X1020001_PoleVine", "Foliage", footprint=0.5, tags=("vine",))
def _pole_vine(coll):
    """Tomato vine climbing a trellis post: leaf clusters and fruit, 4 m tall (scale z)."""
    r = core.rng("x1020001_polevine", 5)
    mb = MeshBuilder()
    for k in range(14):
        a = k * 1.9
        z = 0.25 + k * 0.27
        mb.sphere(0.17, loc=(math.cos(a) * 0.16, math.sin(a) * 0.12, z), scale=(1.2, 1.0, 0.45), mat="M_Bush",
                  subdiv=1, lumpy=0.15, seed=k)
    mb.build("X1020001_PoleVine", coll, smooth=True, sharp_angle=60)
    fr = MeshBuilder()
    for k in range(5):
        a = r.uniform(0, 2 * math.pi)
        fr.sphere(0.1, loc=(math.cos(a) * 0.2, -0.12 + math.sin(a) * 0.05, 0.6 + k * 0.62), scale=(1, 1, 0.8),
                  mat="M_Tomato", subdiv=1)
    fr.build("X1020001_PoleVine_Fruit", coll, smooth=True)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _deck_rect(x0, x1, row):
    yc = ROW_Y[row]
    return (x0 - 0.2, yc - DECK_D / 2, x1 + 0.2, yc + DECK_D / 2)


def _ridge(m, name, x, y0, y1, base, plants=True, seed=0):
    """A planted furrow ridge running into depth, with staked tomato plants."""
    m.terrace(name, geo.rounded_rect(x - 0.5, y0, x + 0.5, y1, 0.45), top=base + RIDGE, bottom=base - 0.3,
              style="dirt", fringe=False, wobble_amt=0.04)
    if plants:
        n = max(2, int((y1 - y0 - 0.6) / 1.35) + 1)
        for k in range(n):
            y = y0 + 0.5 + k * (y1 - y0 - 1.0) / max(1, n - 1)
            m.place("Tomato_Plant", x + (0.06 if k % 2 else -0.06), y, rot=(seed * 37 + k * 71) % 360,
                    scale=0.95 + 0.1 * ((k + seed) % 3) / 2)


# ---------------------------------------------------------------------------
# the map
# ---------------------------------------------------------------------------

def build(m):
    L, D = m.size  # 60 x 30

    # ================= ground chain: gentle near-full-width slopes =================
    # The slopes stop SLOPE_Y0 short of the front edge: a hedgerow on the flat strip in front of
    # each one screens its dirt side wedge (the banks and hump keep their terrace fronts).
    m.terrace("WestBank", geo.rounded_rect(-0.8, -1.0, 8.6, 31.0, 0.3), top=BANK, bottom=-0.5)
    sy, sw = (SLOPE_Y0 + 31.1) / 2, 31.1 - SLOPE_Y0
    m.ramp("Slope_Bank_Furrow", (8.3, sy, BANK + 0.02), (11.4, sy, 0.0), sw, extend=0.3, top_mat=None)
    m.terrace("Hump", geo.rounded_rect(29.8, -1.0, 35.7, 31.0, 0.3), top=BANK, bottom=-0.5)
    m.ramp("Slope_Furrow_Hump", (27.0, sy, 0.0), (30.1, sy, BANK + 0.02), sw, extend=0.3, top_mat=None)
    m.ramp("Slope_Hump_Furrow", (35.4, sy, BANK + 0.02), (38.5, sy, 0.0), sw, extend=0.3, top_mat=None)
    m.terrace("EastBank", geo.rounded_rect(51.0, -1.0, 60.8, 31.0, 0.3), top=EAST, bottom=-0.5)
    m.ramp("Slope_Furrow_EastBank", (45.0, sy, 0.0), (51.3, sy, EAST + 0.02), sw, extend=0.3, top_mat=None)

    # farm track along the front of the canopy, from the hedge gap to the east bank
    m.path("Farm_Track", [(1.0, 12.0), (4.0, 14.6), (9.0, 15.4), (30.0, 15.4), (46.0, 15.4), (58.5, 15.2)],
           width=2.8)
    m.path("Track_Spur_East", [(55.0, 15.2), (56.0, 12.6), (56.4, 11.2)], width=2.4)  # ends before Soil_Bank

    # ================= planted beds (rows run into depth) =================
    # tilled soil first (draped on the bare ground), ridges on top
    for name, cx, y0, y1, wd in (("Soil_West", 19.0, 1.3, 13.9, 14.4), ("Soil_East", 42.0, 1.3, 13.9, 6.6),
                                 ("Soil_Hump", 32.8, 1.9, 7.7, 2.4), ("Soil_Bank", 54.1, 2.4, 10.6, 4.4)):
        m.path(name, [(cx, y0), (cx, (y0 + y1) / 2), (cx, y1)], width=wd, mat="M_Flat_dirt", edge_wobble=0.25)
    for i, x in enumerate((13.0, 15.4, 17.8, 20.2, 22.6, 25.0)):
        _ridge(m, f"WestRow_{i}", x, 2.0, 13.2, 0.0, seed=i)
    for i, x in enumerate((39.9, 42.1)):
        _ridge(m, f"EastRow_{i}", x, 2.0, 13.2, 0.0, seed=10 + i)
    _ridge(m, "EastRow_2", 44.2, 3.0, 12.4, 0.0, seed=12)
    _ridge(m, "HumpRow", 32.8, 2.4, 7.2, BANK, seed=20)
    for i, x in enumerate((53.2, 55.0)):
        _ridge(m, f"BankRow_{i}", x, 3.0, 10.0, EAST, seed=30 + i)

    # ================= trellis canopy (17 decks) =================
    for name, x0, x1, row in DECKS:
        rx0, ry0, rx1, ry1 = _deck_rect(x0, x1, row)
        m.deck(f"Deck_{name}", geo.rect(rx0, ry0, rx1, ry1), top=ROW_Z[row], posts=False)
    # supports go in after every deck exists so a leg can stand on a lower deck it overlaps
    for i, (name, x0, x1, row) in enumerate(DECKS):
        rx0, ry0, rx1, ry1 = _deck_rect(x0, x1, row)
        cx, cy = (rx0 + rx1) / 2, (ry0 + ry1) / 2
        under = ROW_Z[row] - 0.25
        m.place("X1020001_DeckFrame", cx, cy, z=under, rot=0)
        for k, (lx, ly) in enumerate(((rx0 + 0.3, ry0 + 0.3), (rx1 - 0.3, ry0 + 0.3), (rx1 - 0.3, ry1 - 0.3),
                                      (rx0 + 0.3, ry1 - 0.3))):
            gz = m.ground_z(lx, ly, z_from=under - 0.05)
            gz = 0.0 if gz is None else gz
            if under - gz < 0.3:
                continue
            m.place("X1020001_TrellisLeg", lx, ly, z=gz - 0.05, scale=(1.0, 1.0, under - gz + 0.05))
            # decorative vines on BACK legs only: the five climbs stay the only leafy columns up front
            if k >= 2 and (i + k) % 2 == 0 and under - gz > 2.5:
                m.place("X1020001_PoleVine", lx, ly - 0.16, z=gz, rot=0, scale=(1.0, 1.0, (under - gz) / 4.0))

    # five leafy vines (knotted ropes wound thick with tomato vine), one per ground zone
    vines = [("Vine_Bank", 5.9, 16.75, BANK, ROW_Z[0]), ("Vine_WestFurrow", 16.8, 18.25, 0.0, ROW_Z[1]),
             ("Vine_Hump", 31.3, 18.25, BANK, ROW_Z[1]), ("Vine_EastFurrow", 41.4, 18.25, 0.0, ROW_Z[1]),
             ("Vine_EastBank", 52.0, 19.75, EAST, ROW_Z[2])]
    for k, (name, x, y, z0, z1) in enumerate(vines):
        m.ladder(name, x, y, z0, z1, facing=90, kind="rope")
        m.place("X1020001_PoleVine", x, y + 0.05, z=z0, rot=0, scale=(1.5, 1.5, (z1 - z0) / 4.0))
        m.place("Vine_Hanging_A", x + 0.08, y - 0.05, z=z1 - 0.05, rot=0)
        m.place("Vine_Hanging_A", x - 0.1, y - 0.05, z=z1 - 1.3, rot=90)
        m.place("Vine_Hanging_A", x - 0.08, y - 0.05, z=z1 - 2.6, rot=180)
        # foot marker beside the base, off the climb line and behind the farm track
        m.place(("Flower_Patch_A", "Stump_A", "Flower_Patch_A", "Stump_A", "Flower_Patch_A")[k], x + 0.85, y + 0.15,
                rot=k * 70, scale=0.8, z_from=z0 + 1.0)
    # tomato vines draping the trellis and potted plants on the decks (2D: T10 x2, T15 x1, T25 x3)
    for i, (name, x0, x1, row) in enumerate(DECKS):
        rx0, ry0, rx1, ry1 = _deck_rect(x0, x1, row)
        if i % 2 == 0:
            m.place("Vine_Hanging_A", rx0 + 0.6, ry0 - 0.02, z=ROW_Z[row] - 0.1, rot=0, scale=0.9)
        if i % 3 == 1:
            m.place("Vine_Hanging_A", rx1 - 0.7, ry0 - 0.02, z=ROW_Z[row] - 0.1, rot=0, scale=0.8)
    # potted tomatoes, kept to deck edges away from the Canopy route's junctions
    for (x, y, row) in ((4.4, 19.55, 0), (6.5, 19.55, 0), (29.6, 19.0, 1), (52.2, 22.55, 2), (53.3, 22.55, 2),
                        (54.3, 22.3, 2)):
        m.place("Planter_Box", x, y, z=ROW_Z[row], rot=x * 13)
        m.place("Tomato_Plant", x, y, z=ROW_Z[row] + 0.42, rot=x * 40, scale=0.8)
    # a few harvest props on free deck corners
    m.place("Crate", 46.9, 18.95, z=ROW_Z[1], rot=12, scale=0.85)
    m.place("X1020001_CratesTomatoes", 24.1, 22.35, z=ROW_Z[2], rot=-8, scale=0.8)
    m.place("Sack", 9.4, 21.0, z=ROW_Z[1], rot=30)

    # ================= arrival: the hedge gap under the tomato-cap gate =================
    # The portal stays on the gate's axis, 1.5 m in front of it. This map's camera looks along
    # local (-0.34, 0.94) (world yaw -65), so rot=+20 would face it squarely, but out00 is only
    # 1 m from the west edge: -25 is as far as the gate can turn before its west post leaves the
    # bank (post at x ~ -0.77). It is seen about 45 deg off-axis (it was 70 deg at the old -50).
    ox, oy, _oz = m.anchor("out00")
    m.place("Tomato_Gate", ox + 1.5 * 0.42, oy + 1.5 * 0.91, rot=-25)
    for (x, y) in ((0.3, 15.6), (0.3, 19.6), (0.3, 23.6)):
        m.place("Hedge_Wall_4m", x, y, rot=90, scale=(1.0, 1.0, 1.05))
    m.place("Hedge_Wall_4m", 0.3, 1.0, rot=90, scale=(1.0, 1.0, 1.05))
    m.place("Hedge_Wall_4m", 0.3, 5.0, rot=90, scale=(0.9, 1.0, 1.05))
    m.place("Sign_Board", 6.0, 9.4, rot=30)
    m.place("Tree_Birch_Orange", 2.6, 25.6, rot=20, scale=1.05)
    m.place("Tree_Autumn_A", 6.4, 27.4, rot=100, scale=1.0)
    m.place("Tree_Birch_Orange", 5.6, 2.0, rot=200, scale=0.8)
    m.place("Haystack", 3.4, 4.4, rot=0, scale=1.0)
    m.place("Barrel", 7.2, 6.2, rot=0)
    m.place("Crate", 7.6, 4.8, rot=20)
    m.place("Sack", 6.4, 5.2, rot=40)

    # ================= farm dressing =================
    # back boundary: hedge wall + fence, the yellow tree on the hump, tree pair on the east bank
    for k in range(15):
        m.place("Hedge_Wall_4m", 0.4 + k * 4.0, 29.4, rot=0, scale=(1.0, 1.0, 1.0 + 0.08 * (k % 2)), required=False)
    m.place("Tree_Birch_Yellow", 32.8, 27.2, rot=40, scale=1.1)
    m.place("Tree_Birch_Yellow", 54.4, 26.8, rot=120, scale=1.05)
    m.place("Tree_Autumn_A", 58.6, 25.0, rot=10, scale=1.0)
    m.place("Tree_Birch_Orange", 20.0, 27.4, rot=70, scale=0.95)
    m.place("Tree_Birch_Yellow", 44.0, 27.6, rot=10, scale=0.9)
    # front edge: low rail fence on the flat ground, clipped hedgerows in front of the slopes (they
    # hide the slopes' dirt side wedges); the east-bank slope rises 2.4 m so its upper hedge is taller
    for (a, b) in ((1.2, 7.6), (12.2, 26.4), (30.8, 34.8), (38.8, 44.6), (51.8, 58.6)):
        m.fence([(a, 0.3), (b, 0.3)])
    for (x0, x1, zs) in ((8.7, 11.9, 1.0), (26.6, 29.75, 1.0), (35.75, 38.9, 1.0), (44.6, 47.9, 0.95),
                         (47.9, 50.95, 1.75)):
        m.place("Hedge_Wall_4m", x0, -0.15, rot=0, scale=((x1 - x0) / 4.0, 1.0, zs))
    m.fence([(59.6, 1.2), (59.6, 15.0), (59.6, 28.6)])
    # scarecrows guarding the beds, a giant prize tomato on the hump
    m.place("Scarecrow", 16.6, 8.0, rot=20)
    m.place("Scarecrow", 41.0, 9.2, rot=-25, scale=0.95)
    m.place("Tomato_Giant", 32.6, 10.6, rot=30, scale=1.1)
    m.place("Haystack", 31.2, 3.0, rot=0, scale=1.1)
    m.place("Haystack", 34.4, 4.4, rot=30, scale=0.9)
    m.place("X1020001_CratesTomatoes", 34.2, 12.2, rot=10)
    # east bank: the harvest yard (cart, giant tomatoes, haystacks, crates)
    m.place("Cart", 58.1, 8.4, rot=-80)  # handles turned away from the spur arch
    m.place("Tomato_Giant", 52.6, 12.6, rot=0, scale=1.2)
    m.place("Tomato_Giant", 57.4, 18.8, rot=60, scale=0.9)
    m.place("Haystack", 58.4, 3.6, rot=0, scale=1.15)
    m.place("Haystack", 57.0, 2.0, rot=30, scale=0.9)
    m.place("X1020001_CratesTomatoes", 58.6, 13.4, rot=-10)
    m.place("X1020001_CratesTomatoes", 57.6, 6.0, rot=15, scale=0.9)
    m.place("Crate_Stack", 51.8, 1.8, rot=0)
    m.place("Barrel", 52.8, 1.4, rot=0)
    # trellis arches where a path runs into depth, so they face the camera: at the head of the
    # west bed (between the 17.8 and 20.2 ridges) and over the east-yard spur into the bank bed
    m.place("X1020001_TrellisArch", 19.0, 13.9, rot=10)
    m.place("X1020001_TrellisArch", 55.9, 12.4, rot=20)
    # baskets and tools along the track
    m.place("X1020001_CratesTomatoes", 11.95, 10.8, rot=95, scale=0.9)
    m.place("Sack", 11.6, 11.95, rot=20)
    m.place("X1020001_CratesTomatoes", 37.4, 13.4, rot=-12, scale=0.9)
    m.place("Barrel", 46.0, 13.4, rot=0)
    for (a, x, y, r, s) in (("Rock_A", 10.2, 1.4, 0, 0.8), ("Rock_C", 27.6, 1.2, 30, 1.0),
                            ("Rock_B", 36.8, 1.0, 60, 0.7), ("Stump_A", 26.8, 24.6, 0, 0.9),
                            ("Rock_A", 9.8, 25.6, 40, 0.9), ("Log_A", 40.6, 25.6, 10, 0.9),
                            ("Mushroom_Cluster_A", 14.0, 26.6, 0, 1.0), ("Stump_A", 48.6, 24.6, 30, 0.8)):
        m.place(a, x, y, rot=r, scale=s, required=False)
    bushes = [(2.6, 28.4), (11.6, 27.6), (17.2, 28.0), (24.4, 27.8), (29.2, 28.2), (37.6, 28.0), (47.6, 28.2),
              (51.4, 28.0), (8.2, 21.6), (35.8, 24.6), (0.9, 9.2), (0.9, 15.0)]
    for i, (x, y) in enumerate(bushes):
        m.place(["Bush_A", "Bush_B", "Bush_C", "Bush_Flowering_A"][i % 4], x, y, rot=i * 41,
                scale=0.9 + 0.1 * (i % 3), required=False)
    track = geo.rect(0, 13.8, 60, 17.2)
    beds = [geo.rect(12.2, 1.6, 25.8, 13.6), geo.rect(39.2, 1.6, 44.9, 13.6), geo.rect(52.4, 2.6, 55.8, 10.4)]
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 60, 13.6), 26, seed=3,
              min_dist=1.5, avoid=beds + [(1.6, 12.5, 3.0), track, (19.0, 13.9, 2.0), (55.9, 12.4, 2.0)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_B"], geo.rect(0, 23.6, 60, 28.8), 18, seed=4, min_dist=1.6,
              z_band=(-0.2, 2.8))

    # ================= gameplay =================
    m.edge_portal("out00")
    # on the farm track at the head of the west bed, near GAMEPLAY_FOCUS, ~0.5 m camera-side of the
    # Main route and turned toward the camera (local look ~(-0.34, +0.94))
    m.player(26.0, 14.9, rot=20)
    # player_spawns[0] (MeowDB sp x -195, y 111: just east of and above out00 at x -275, y 214): on the Main route
    # just through the barrel gate, on the west bank. Not at (4.0, 12.0): that stood inside the gate's south post
    # (its collision hull), and the runtime had to move the spawn 1 m to stand clear.
    m.player_spawn(4.8, 14.7, rot=90, note="sp x -195: just east of out00, through the barrel gate, on the west bank")

    # monsters (25 classic spawns, all on the ground: Snail 9, Blue Snail 8, Red Snail 4, Orange Mushroom 4)
    m.mobs("Snail", geo.rect(2, 1, 7.5, 9), 1, seed=1, z_band=(1.0, 1.5))
    m.mobs("Orange Mushroom", geo.rect(18.3, 2.5, 19.7, 12.5), 1, seed=3, z_band=(-0.2, 0.15))
    m.mobs("Snail", geo.rect(13.7, 2.5, 14.7, 12.5), 1, seed=4, z_band=(-0.2, 0.15))
    m.mobs("Blue Snail", geo.rect(23.3, 2.5, 24.3, 12.5), 1, seed=5, z_band=(-0.2, 0.15))
    m.mobs("Blue Snail", geo.rect(30.5, 12.8, 35.0, 16.4), 1, seed=7, z_band=(1.0, 1.5))
    m.mobs("Orange Mushroom", geo.rect(40.5, 2.5, 41.5, 12.5), 1, seed=8, z_band=(-0.2, 0.15))
    m.mobs("Red Snail", geo.rect(38.6, 13.8, 44.0, 16.4), 1, seed=9, z_band=(-0.2, 0.15))
    m.mobs("Snail", geo.rect(52.0, 13.8, 58.5, 16.4), 1, seed=11, z_band=(2.2, 2.6))

    # routes
    m.route("Main", [(1.0, 12.0), (4.0, 14.6), (9.0, 15.4), (20.0, 15.4), (30.0, 15.4), (40.0, 15.4),
                     (48.0, 15.4), (57.9, 15.2)])  # stops 1.7 m short of the east fence
    # The bed walks keep 0.7 m between their centreline and every planted ridge's tomato plants (each plant collides
    # as a ~0.42 m prism, the player is 0.3 m wide): WestBed enters the 13.0 | 15.4 furrow past the north tip of the
    # 13.0 ridge, crosses to the 17.8 | 20.2 furrow on the open strip in front of the ridge ends (y 1.3; the ridges
    # start at y 2.0, their first plants at 2.5) and walks up it. It used to cut over the 13.0 ridge's last plant and
    # through the first plants of the 15.4 and 17.8 ridges (6 route samples under leaves, Godot route bot stalls).
    m.route("WestBed", [(10.0, 15.2), (12.6, 14.0), (14.2, 13.0), (14.2, 3.0), (14.6, 1.3), (18.6, 1.3),
                        (19.0, 3.0), (19.0, 12.5)])
    # EastYard runs down the east side of the 55.0 bank ridge and round its south tip; the 53.2 | 55.0 furrow is
    # only 0.8 m between plant prisms, too narrow for a walk (the old route ended in it through the ridge's plants)
    m.route("EastYard", [(55.0, 15.2), (56.0, 11.0), (56.3, 6.4), (56.1, 3.2), (55.0, 2.3)])
    # the canopy walk: leaves the farm track on Main, up the bank vine, then deck to deck through every
    # overlap to the far east deck (routes walk straight through their climbs; (5.9, 16.9) is the probed
    # point just before the bank vine's climb)
    pts = [(5.9, 14.9), (5.9, 16.9), (5.9, 18.6)]
    for (n0, a0, a1, r0), (n1, b0, b1, r1) in zip(DECKS, DECKS[1:]):
        ra = _deck_rect(a0, a1, r0)
        rb = _deck_rect(b0, b1, r1)
        jx = (max(ra[0], rb[0]) + min(ra[2], rb[2])) / 2
        jy = (max(ra[1], rb[1]) + min(ra[3], rb[3])) / 2
        pts.append((jx, jy))
        pts.append(((rb[0] + rb[2]) / 2, ROW_Y[r1]))
    m.route("Canopy", pts)
    # the other four vines: each leaves the farm track on Main and climbs onto its deck
    for name, x, y, z0, z1 in vines[1:]:
        ty = 15.4 if x < 48.0 else 15.4 - 0.2 * (x - 48.0) / 9.9  # Main's centreline at x
        m.route(f"Climb_{name}", [(x, ty), (x, y + 1.2)])
