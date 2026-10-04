"""Snail Hunting Ground III (40002) - "climb the chimney, walk the ridge".

Classic (GMS v8) structure, from docs/research/maps/40002_SnailHuntingGround3_40002.md:
  ground: the same west half as SHG I (entry plateau T19 > step T21 > basin T23 > stepped
  knoll T22/T20 > hilltop T18) but the knoll ends in a SHEER east cliff over the east
  ground (T24, with a fallen hollow birch log); a low shelf (T17) with a ladder. Mid: the west
  ridge path (T12, a dead end hanging off T7), the central terrace (T15, two ladders down to
  the hilltop, two descend-only vines), stacked blocks T16/T14 to the mid-east ledge T13.
  Upper: T7 (upper-west, small ramp), stair blocks T11/T10/T9 to T8 (upper-east). A narrow
  CHIMNEY of three stacked blocks (T6/T5/T4) with short ropes and a ladder is the only way to
  the SUMMIT RIDGE (T1 > T0 > T2 > T3) that spans the top of the map; the exit east00 sits at
  the far east end of the ridge, high at the back right, with signposts. First RED SNAILS.

3D translation: higher bands step back, so the ridge is the skyline along the back edge and
the exit is literally high and far. The knoll has 1 m stepped tiers (stone stairs) on the
west and one sheer 3.5 m rock face on the east, boulders bedded at its foot. The chimney is a
slot between two rock jambs in front of a notch in the 4.9 m ridge wall: three rock ledges
stacked inside it, a 1.2 m rope pitch to each and a ladder to the crest, with banners on the
jamb tops. The crest's back edge is one rock RIM (wide grass-capped teeth joined by low rock
walls); the crest walk runs open in front of it, past two small birches at its west end and the
grove's back trees in a rim gap, to a matching rock-post gate with banners at east00. The real
through-route is painted as the pale main road on every tier (the east field stays dirt), and
the whole of it is ONE route climbing the ladders/ropes mid-route. Camera note: the camera sees
the -y and +x faces, so the 12.5 m ridge-end wall at x = 64 is dressed.
"""

import math

from misostory import core, geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.mapkit import MAIN_ROAD

MAP_ID = 40002
GAMEPLAY_FOCUS = (19.5, 35.0)
GAMEPLAY_SCALE = 44.0

PLATEAU = 0.8
EAST = 0.6  # east ground (raised so the pit notch can cut it)
KNOLL1, KNOLL2 = 1.0, 2.0
HILL = 3.0  # the hilltop (T18): its east side is one sheer 3.5 m rock face
T17 = 3.4
T15 = 5.2
T12W, T12E = 6.0, 5.6
T13 = 6.0
T7W, T7E = 8.0, 7.6
T8 = 8.0
# the chimney: three 1.2 m rope pitches, then a ladder; the ridge wall stands 4.9 m above T7
T6, T5, T4 = 9.2, 10.4, 11.6
T1, T0, T2, T3 = 12.9, 13.3, 12.9, 12.5
ROAD = {**MAIN_ROAD, "width": 2.6}  # the pale through-road (west00 -> chimney -> crest -> east00)
JAMB = T1 + 0.3  # chimney jambs: a touch taller than the ridge so their caps never coincide


@asset("X40002_Chimney_Banner", "Props", footprint=0.8, tags=("prop", "sign"))
def _banner(coll):
    """Tall pole with a red pennant banner: marks the chimney, the only gate to the ridge."""
    mb = MeshBuilder()
    mb.cyl(0.08, 3.4, mat="M_Wood", verts=8)
    mb.sphere(0.13, loc=(0, 0, 3.45), mat="M_Flat_gold", subdiv=1)
    mb.box((1.0, 0.08, 0.08), loc=(0.45, 0, 3.15), mat="M_Wood_Dark")
    mb.prism([(-0.45, 0.0), (0.45, 0.0), (0.45, -1.25), (0.0, -1.0), (-0.45, -1.25)], -0.025, 0.025,
             loc=(0.48, 0.0, 3.1), rot=(90, 0, 0), mat="M_Flat_cloth_red", bevel=0.01, segs=1)
    mb.cyl(0.2, 0.06, loc=(0.48, -0.04, 2.6), rot=(90, 0, 0), mat="M_Flat_flower_yellow", verts=10)
    mb.build("X40002_Chimney_Banner", coll, smooth=False)


@asset("X40002_Hollow_Log", "Foliage", footprint=4.4, tags=("log", "landmark"))
def _hollow_log(coll):
    """A fallen hollow birch trunk lying in the east field (the brief's 'flat light object with a
    dark shadow'): pale bark with black birch marks, dark hollow ends with a light ring of heartwood,
    a mossy back with a few red toadstools and a snapped branch stub."""
    r = core.rng("X40002_Hollow_Log", 7)
    mb = MeshBuilder()
    L, R, zc = 4.4, 0.62, 0.52
    mb.cyl(R, L, loc=(-L / 2, 0, zc), rot=(0, 90, 0), mat="M_Flat_cloth_white", verts=14, r2=R * 0.93)
    for s in (-1, 1):  # hollow ends: dark hole + heartwood rim
        rr = R if s < 0 else R * 0.93
        mb.cyl(rr * 0.74, 0.04, loc=(s * (L / 2 + 0.005) - 0.02, 0, zc), rot=(0, 90, 0), mat="M_Flat_hair_black",
               verts=14)
        mb.torus(rr * 0.86, 0.09, loc=(s * (L / 2 + 0.01), 0, zc), rot=(0, 90, 0), mat="M_Flat_wood_lt", u=16, v=5)
    for k in range(16):  # black birch marks on the visible upper half
        x = r.uniform(-L / 2 + 0.3, L / 2 - 0.3)
        a = r.uniform(-1.9, 1.9)
        mb.box((0.26, 0.05, 0.07), loc=(x, -math.sin(a) * R * 0.98, zc + math.cos(a) * R * 0.98),
               rot=(math.degrees(a), 0, r.uniform(-15, 15)), mat="M_Flat_hair_black")
    for k, x in enumerate((-1.3, -0.2, 0.9)):  # moss on the back
        mb.sphere(0.42, loc=(x, 0.12, zc + R * 0.86), scale=(1.5, 0.9, 0.32), mat="M_Leaf", subdiv=2, lumpy=0.2, seed=k)
    for x, y, h in ((-0.9, -0.1, 0.22), (-0.62, 0.05, 0.16), (1.25, -0.05, 0.2)):  # toadstools
        mb.cyl(0.04, h, loc=(x, y, zc + R * 0.9), mat="M_Flat_mush_stem", verts=6)
        mb.sphere(0.11, loc=(x, y, zc + R * 0.9 + h), scale=(1, 1, 0.55), mat="M_Flat_mush_red", subdiv=1)
    mb.cyl(0.12, 0.7, loc=(0.5, -0.2, zc + 0.45), rot=(-35, 20, 0), mat="M_Flat_cloth_white", verts=7, r2=0.07)
    mb.build("X40002_Hollow_Log", coll, smooth=True, sharp_angle=50)


def crag(m, name, x, y, r, h, base, seed=0, n=6, ry=None, stones=True):
    """An angular grass-capped rock tooth standing on a surface at `base` (taller ones get a second,
    narrower tier on top, offset to one side, so the crest reads craggy rather than as drums). `ry` makes it
    an ellipse (a wide, shallow tooth along the rim)."""
    rr = core.rng(name, seed)
    a0 = rr.uniform(0, math.tau) if ry is None else rr.uniform(-0.3, 0.3)
    sy = 1.0 if ry is None else ry / r

    def poly(cx, cy, rad):
        return [(cx + math.cos(a0 + math.tau * k / n) * rad * rr.uniform(0.75, 1.1),
                 cy + math.sin(a0 + math.tau * k / n) * rad * sy * rr.uniform(0.7, 1.0)) for k in range(n)]

    h1 = h if h < 1.5 else h * 0.6
    m.terrace(name, poly(x, y, r), top=base + h1, bottom=base - 0.6, style="grass_rock", fringe=False,
              smooth_iters=0, wobble_amt=0.0, resample_step=9.0, lip=0.08, cap_thickness=0.26, stones=stones)
    if h >= 1.5:
        ox, oy = rr.uniform(-0.3, 0.3) * r, rr.uniform(-0.15, 0.25) * r
        m.terrace(name + "_Top", poly(x + ox, y + oy, r * 0.62), top=base + h, bottom=base + h1 - 0.3,
                  style="grass_rock", fringe=False, smooth_iters=0, wobble_amt=0.0, resample_step=9.0, lip=0.06,
                  cap_thickness=0.24, stones=False)


def stone(m, name, cx, cy, r, top, style="grass_rock", ry=None, rot=0.0, bottom=-0.5):
    """A rock-pillar stepping stone (one 168 px floating block of the original)."""
    return m.terrace(name, geo.ellipse(cx, cy, r, ry or r * 0.9, 20, rot=rot), top=top, bottom=bottom, style=style,
                     resample_step=0.9, wobble_amt=0.15, lip=0.12, cap_thickness=0.32)


def face_x(m, y, x_out, x_in, ztop, inset=0.2):
    """x of a +x-facing cliff body at depth y: scan from x_out (outside) toward x_in until the
    ground rises to the cap, then step back in by the grass lip (so a stone embeds in the dirt)."""
    step = -0.05 if x_in < x_out else 0.05
    x = x_out
    while (x - x_in) * (1 if step < 0 else -1) > 0:
        z = m.ground_z(x, y)
        if z is not None and z > ztop - 0.3:
            return x + step * (inset / 0.05)
        x += step
    raise ValueError(f"[40002] face_x: no face at y={y} between x {x_out}..{x_in}")


def build(m):
    L, D = m.size  # 64 x 46

    # ================= ground band =================
    m.terrace("T19_Plateau", [(-1, -1), (11.4, -1), (12.2, 8), (11.6, 20.2), (-1, 20.2)], top=PLATEAU, bottom=-0.5)
    m.terrace("T21_Step", [(10.8, 0.0), (14.6, 0.6), (15.0, 9.0), (14.4, 17.6), (10.8, 18.2)], top=PLATEAU / 2,
              bottom=-0.5)
    # the knoll: 1 m tiers stepped on the west, one sheer rock face on the east
    m.terrace("Knoll_T22", [(25.4, 8), (27.0, 3.6), (32, 2.4), (40.2, 2.6), (40.4, 20.2), (29.0, 20.2), (25.8, 15.0)],
              top=KNOLL1, bottom=-0.5)
    m.terrace("Knoll_T20", [(28.2, 9), (29.6, 5.0), (34, 4.0), (40.2, 4.2), (40.3, 20.2), (31.0, 20.2), (28.6, 15.0)],
              top=KNOLL2, bottom=0.3)
    m.terrace("Knoll_T18_Hilltop", [(31.2, 10), (32.4, 6.2), (36, 5.6), (40.0, 5.8), (40.1, 20.2), (32.6, 20.2),
                                    (31.4, 15.0)], top=HILL, bottom=1.0)
    # the sheer east face: one rock wall (big boulders are bedded in its foot, see dress())
    m.terrace("Knoll_EastFace", [(37.8, 5.9), (40.7, 5.6), (41.0, 12.0), (40.8, 20.2), (37.6, 20.2)], top=HILL,
              bottom=-0.5, style="grass_rock", fringe=False)
    stone_steps = dict(mat="M_StoneWall", side_mat="M_Rock", stringers=False)
    m.stairs("Knoll_Stair1", (23.2, 10.6, 0.0), (26.0, 10.6, KNOLL1), 2.4, **stone_steps)
    m.stairs("Knoll_Stair2", (26.3, 11.6, KNOLL1), (28.9, 11.6, KNOLL2), 2.2, **stone_steps)
    m.stairs("Knoll_Stair3", (29.3, 12.4, KNOLL2), (31.8, 12.4, HILL), 2.0, **stone_steps)
    # east ground: an open field (no pit here - its 'flat light object' is a fallen hollow birch log)
    m.terrace("T24_East", [(40.6, -1), (64.6, -1), (64.6, 20.0), (40.6, 20.0)], top=EAST, bottom=-0.5)
    m.ramp("Knoll_Front_Ramp", (36.6, 0.6, 0.0), (41.4, 0.6, EAST), 2.8)
    m.path("Main_Road", [(1, 10), (6, 10.4), (12.5, 10.6), (19, 10.6), (22.6, 10.6)], **ROAD)
    m.path("Main_Road_Hilltop", [(32.2, 12.4), (33.4, 13.4), (34.2, 15.0), (34.2, 18.5)], **ROAD)
    m.path("Around_Knoll", [(20, 6), (26, 1.2), (36.0, 0.6)], width=2.6)
    m.path("East_Path", [(42.0, 1.0), (43.6, 4.6), (46.4, 7.6), (50.4, 8.2), (53.6, 10.0), (55.4, 12.4)], width=2.4)

    # ================= low band =================
    m.terrace("T17_Shelf", [(49.0, 14.0), (57.6, 14.2), (57.4, 20.6), (54.4, 21.0), (54.2, 27.0), (48.6, 27.0),
                            (48.4, 20.4)], top=T17, bottom=-0.5)
    m.ladder("Ladder_2496", 55.6, 13.6, EAST, T17, facing=90)

    # ================= mid band =================
    m.terrace("T12_MidWest_W", [(-1, 20.4), (2.6, 19.0), (6.4, 19.6), (6.6, 28.8), (-1, 28.8)], top=T12W, bottom=-0.5)
    m.terrace("T12_MidWest_E", [(6.0, 19.4), (9.4, 18.4), (13.0, 19.2), (16.4, 18.8), (17.8, 20.4), (17.6, 28.8), (6.0, 28.8)], top=T12E,
              bottom=-0.5)
    # (the 192 px gap between T12 and T15 stays a chasm down to the basin)
    m.terrace("T15_Central", [(21.4, 19.6), (30, 19.9), (40, 19.7), (46.4, 19.9), (46.6, 38.4), (21.4, 38.4)],
              top=T15, bottom=-0.5)
    m.ladder("Ladder_1335", 34.2, 19.25, HILL, T15, facing=90)
    m.path("Main_Road_T15", [(34.2, 20.4), (34.2, 23.0), (28.0, 24.0), (23.2, 25.2), (23.2, 26.4)], **ROAD)
    m.ladder("Ladder_1418", 36.4, 19.25, HILL, T15, facing=90)
    # descend-only vines (x1867 / x1913): they hang short of the east ground (drop the last bit)
    m.ladder("Vine_1867", 43.0, 19.5, 2.2, T15, facing=90, kind="rope", descend_only=True)
    m.ladder("Vine_1913", 44.8, 19.5, 3.0, T15, facing=90, kind="rope", descend_only=True)
    stone(m, "T16", 50.8, 22.4, 1.9, T15, style="grass_dirt")
    stone(m, "T14", 52.8, 24.4, 1.9, T15 + 0.4, style="grass_dirt")
    m.ladder("Rope_2270", 51.0, 20.2, T17, T15, facing=90, kind="rope")
    m.terrace("T13_MidEast", [(53.6, 18.8), (64.6, 18.6), (64.6, 38.0), (54.0, 38.0), (53.2, 25.0), (53.6, 22.0)],
              top=T13, bottom=-0.5)

    # ================= upper band =================
    m.terrace("T7_UpperWest_W", [(-1, 29.4), (3.0, 27.0), (7.4, 26.6), (10.0, 28.0), (14, 27.2), (19.0, 27.4), (20.8, 29.0), (20.8, 42.4), (-1, 42.4)],
              top=T7W, bottom=-0.5)
    m.terrace("T7_UpperWest_E", [(20.2, 27.6), (28, 27.4), (35.6, 27.8), (35.8, 38.4), (20.2, 38.4)], top=T7E,
              bottom=-0.5)
    m.ladder("Ladder_395", 14.0, 26.8, T12E, T7W, facing=90)
    m.ladder("Rope_873", 23.2, 27.0, T15, T7E, facing=90, kind="rope")
    m.path("Main_Road_T7", [(23.2, 28.0), (23.2, 31.0), (18.0, 32.0), (15.2, 33.6), (15.2, 34.8)], **ROAD)
    # stair blocks T11 > T10 > T9 up to the upper-east ledge T8
    stone(m, "T11", 37.6, 25.8, 1.8, T7E - 0.8)
    m.ladder("Rope_1530", 37.6, 23.7, T15, T7E - 0.8, facing=90, kind="rope")
    stone(m, "T10", 37.6, 28.4, 1.8, T7E - 0.4)
    stone(m, "T9", 40.2, 29.4, 1.8, T7E)
    m.terrace("T8_UpperEast", [(42.4, 27.4), (52, 27.6), (58.8, 27.8), (59.0, 38.0), (42.0, 38.0), (41.6, 31.0)],
              top=T8, bottom=-0.5)
    m.ladder("Ladder_2585", 57.4, 27.35, T13, T8, facing=90)
    m.ladder("Rope_2520", 56.0, 27.3, T13, T8, facing=90, kind="rope")

    # ================= summit ridge + the chimney =================
    m.terrace("T1_RidgeWest", [(-1, 39.2), (4.0, 37.4), (10.0, 38.0), (10.4, 41.6), (16.4, 41.6), (16.6, 38.0), (30.4, 37.6),
                               (30.4, 46.6), (-1, 46.6)], top=T1, bottom=-0.5)
    m.terrace("T0_RidgeCentre", [(30.0, 37.6), (36.0, 38.2), (40.0, 36.8), (44.0, 37.0), (49.8, 37.4), (49.8, 46.6), (30.0, 46.6)], top=T0, bottom=-0.5)
    m.terrace("T2_RidgeStep", [(49.4, 37.4), (52.2, 37.4), (52.2, 46.6), (49.4, 46.6)], top=T2, bottom=-0.5)
    # (its east end juts forward into a small bastion so the exit gate has room on both sides)
    m.terrace("T3_RidgeEast", [(51.8, 34.0), (58.4, 33.8), (59.6, 31.6), (64.6, 31.2), (64.4, 45.4), (63.6, 46.4),
                               (51.8, 46.6)], top=T3, bottom=-0.5)
    # the crest skyline: a continuous rock RIM along the ridge's back edge - wide, shallow grass-capped teeth
    # every 6-8 m (tops <= 14.5 m) joined by low rim walls 0.8-1.1 m tall. A gap at x 39.6-44.8 holds the
    # grove's back trees. The crest walk (Main, y ~42.5) stays >= 1.5 m in front of the rim.
    teeth = [(5.4, 1.5, 1.5, T1), (12.2, 1.9, 1.6, T1), (18.6, 1.6, 1.2, T1), (25.6, 2.0, 1.5, T1),
             (32.0, 1.6, 1.1, T0), (37.6, 2.0, 1.2, T0), (46.8, 2.0, 1.2, T0), (54.0, 1.8, 1.6, T3),
             (60.4, 2.2, 2.0, T3)]
    for i, (x, rx, h, base) in enumerate(teeth):
        crag(m, f"Crest_Tooth{i}", x, 45.75, rx, h, base, seed=i, n=7, ry=1.05)
    for i, (x0, x1, top) in enumerate([(-0.8, 4.4, T1 + 0.9), (6.3, 10.8, T1 + 0.8), (13.6, 17.4, T1 + 1.0),
                                       (19.6, 24.1, T1 + 0.85), (27.0, 30.9, T0 + 0.85), (33.0, 36.1, T0 + 0.8),
                                       (48.2, 52.7, T0 + 0.8), (55.2, 58.7, T3 + 1.1)]):
        m.terrace(f"Crest_Rim{i}", geo.rounded_rect(x0, 45.15, x1, 46.4, 0.55), top=top, bottom=T3 - 0.6,
                  style="grass_rock", fringe=False, stones=False, lip=0.08, cap_thickness=0.24, wobble_amt=0.12,
                  resample_step=0.9)
    # the exit gate: two tall rock posts flanking east00 (they echo the chimney jambs; trail corridor kept clear)
    for i, (x, y) in enumerate([(62.0, 32.6), (62.0, 39.4)]):
        crag(m, f"Exit_GatePost{i}", x, y, 0.75, 2.0, T3, seed=20 + i, n=5)
    # the chimney: a slot between two rock jambs, with three rock ledges stacked inside it
    for n, x0, x1 in [("Chimney_JambW", 9.0, 10.8), ("Chimney_JambE", 16.4, 18.2)]:
        m.terrace(n, geo.rounded_rect(x0, 34.6, x1, 38.6, 0.5), top=JAMB, bottom=-0.5, style="grass_rock",
                  fringe=False, lip=0.08, wobble_amt=0.12, resample_step=0.9)
    stone(m, "T6_Chimney1", 14.4, 37.0, 1.8, T6, ry=1.3)
    stone(m, "T5_Chimney2", 12.4, 38.7, 1.6, T5, ry=1.3)
    stone(m, "T4_Chimney3", 14.3, 40.3, 1.7, T4, ry=1.2)
    m.ladder("Rope_453", 15.2, 35.3, T7W, T6, facing=90, kind="rope")
    m.ladder("Rope_355", 13.4, 37.25, T6, T5, facing=90, kind="rope")
    m.ladder("Rope_296", 13.0, 39.1, T5, T4, facing=90, kind="rope")
    m.ladder("Ladder_361", 14.0, 41.0, T4, T1, facing=90)
    m.path("Main_Road_Crest", [(14.0, 42.0), (14.0, 42.6), (24.0, 42.8), (31.0, 42.6), (40.0, 42.4), (48.4, 42.4),
                               (50.8, 41.4), (52.6, 39.6), (58.0, 37.4), (63.0, 36.0)], **ROAD)

    # ================= gameplay: portals + routes =================
    m.edge_portal("west00")
    m.edge_portal("east00")
    # ONE through-route (the validator climbs ladders/ropes mid-route): plateau -> basin -> knoll stairs ->
    # ladder x1335 -> T15 -> rope x873 -> T7 -> the chimney (ropes x453/x355/x296, ladder x361) -> crest -> exit
    m.route("Main", [(1, 10), (6, 10.4), (11.0, 10.6), (13.0, 10.6), (19, 10.6), (20.0, 10.6), (23.2, 10.6),
                     (26.0, 10.6), (26.3, 11.6), (28.9, 11.6), (29.3, 12.4), (31.8, 12.4), (33.4, 13.4), (34.2, 15.0),
                     (34.2, 18.0), (34.2, 23.0),  # ladder x1335 up to T15
                     (28.0, 24.0), (23.2, 25.2), (23.2, 26.2), (23.2, 31.0),  # rope x873 up to T7
                     (18.0, 32.0), (16.6, 32.8), (15.2, 33.6), (15.2, 34.4), (15.2, 37.0),  # rope x453 to T6
                     (14.6, 37.0), (13.4, 36.6), (13.4, 38.8),  # rope x355 to T5
                     (12.6, 38.8), (13.0, 38.5), (13.0, 40.4),  # rope x296 to T4
                     (14.0, 40.4), (14.0, 40.2), (14.0, 42.6),  # ladder x361 to the crest (T1)
                     (24.0, 42.8), (31.0, 42.6), (40.0, 42.4), (48.4, 42.4), (50.8, 41.4), (52.6, 39.6),
                     (58.0, 37.4), (63.0, 36.0)])
    # east loop: off Main at the basin, around the knoll, ladder x2496 -> T17, rope x2270 -> T16/T14 -> T13,
    # ladder x2585 -> T8, west over the stair blocks T9/T10 to T7, back onto Main at the rope x873 head
    m.route("East_Loop", [(20.0, 10.6), (20, 6), (26, 1.2), (36.6, 0.6), (41.4, 0.8), (44, 5.5), (45.8, 8.0),
                          (50.4, 8.0), (54.0, 10.5), (55.6, 12.4), (55.6, 16.0),  # ladder x2496
                          (55.0, 17.4), (51.0, 18.6), (51.0, 19.6), (51.0, 22.8),  # rope x2270
                          (52.8, 24.4), (56.0, 24.8), (57.4, 25.6), (57.4, 26.4), (57.4, 31.0),  # ladder x2585
                          (50.0, 31.0), (44.0, 30.6), (40.2, 29.4), (37.6, 28.4), (34.0, 30.0), (30.0, 31.0),
                          (23.2, 31.0)])
    # rope x1530: from the Main walk on T15 up the stair blocks T11/T10 onto the east loop on T8
    m.route("Rope_1530", [(34.2, 23.0), (37.6, 22.6), (37.6, 26.0), (37.6, 28.4), (40.2, 29.4), (43.0, 30.4),
                          (47.0, 30.9)])
    # rope x2520: the second way from T13 up to T8
    m.route("Rope_2520", [(56.0, 24.8), (56.0, 26.4), (56.0, 31.4), (53.0, 32.0)])
    # the T12 dead end: off Main on T7, down ladder x395, along T12 to the west edge; and T7's west lobe
    m.route("T12_Walk", [(16.6, 32.8), (14.0, 30.5), (14.0, 25.8), (16.0, 24.0), (8.0, 24.0), (6.0, 24.0),
                         (1.0, 24.0)])
    m.route("T7_West", [(14.0, 30.5), (8.0, 31.0), (2.0, 32.0)])

    # ================= dressing =================
    dress(m)

    # ================= monsters (Snail 36 / Blue 26 / Red 13 spawns -> 18 proxies) =================
    m.mobs("Snail", geo.rect(15, 1, 25, 16), 1, seed=1, z_band=(-0.1, 0.1))
    m.mobs("Snail", geo.rect(51, 1, 63, 12), 1, seed=2, z_band=(EAST - 0.1, EAST + 0.1))
    m.mobs("Snail", geo.rect(31, 39, 49, 46), 1, seed=3, z_band=(T0 - 0.1, T0 + 0.1))
    m.mobs("Snail", geo.rect(22, 29, 35, 37), 1, seed=4, z_band=(T7E - 0.1, T7E + 0.1))
    m.mobs("Snail", geo.rect(0, 20, 17, 28), 1, seed=5, z_band=(T12E - 0.1, T12W + 0.1))
    m.mobs("Snail", geo.rect(0, 39, 10, 46), 1, seed=6, z_band=(T1 - 0.1, T1 + 0.1))
    m.mobs("Snail", geo.rect(53, 35, 60, 40), 1, seed=7, z_band=(T3 - 0.1, T3 + 0.1))
    m.mobs("Snail", geo.rect(22, 21, 33, 27), 1, seed=8, z_band=(T15 - 0.1, T15 + 0.1))
    m.mobs("Blue Snail", geo.rect(39, 21, 46, 27), 1, seed=11, z_band=(T15 - 0.1, T15 + 0.1))
    m.mobs("Blue Snail", geo.rect(41, 1, 46, 14), 1, seed=12, z_band=(EAST - 0.1, EAST + 0.1))
    m.mobs("Blue Snail", geo.rect(1, 29, 9, 37), 1, seed=13, z_band=(T7W - 0.1, T7W + 0.1))
    m.mobs("Blue Snail", geo.rect(15, 1, 25, 16), 1, seed=14, z_band=(-0.1, 0.1))
    m.mobs("Blue Snail", geo.rect(1, 1, 10, 18), 1, seed=15, z_band=(PLATEAU - 0.1, PLATEAU + 0.1))
    m.mobs("Blue Snail", geo.rect(43, 29, 58, 36), 1, seed=16, z_band=(T8 - 0.1, T8 + 0.1))
    m.mobs("Red Snail", geo.rect(31, 39, 49, 46), 1, seed=21, z_band=(T0 - 0.1, T0 + 0.1))
    m.mobs("Red Snail", geo.rect(53, 41, 63, 46), 1, seed=22, z_band=(T3 - 0.1, T3 + 0.1))
    m.mobs("Red Snail", geo.rect(0, 20, 17, 28), 1, seed=23, z_band=(T12E - 0.1, T12W + 0.1))
    m.mobs("Red Snail", geo.rect(22, 29, 35, 37), 1, seed=24, z_band=(T7E - 0.1, T7E + 0.1))
    m.player(17.1, 33.0, rot=-30)  # on T7 by the chimney foot (Gameplay focus)
    m.player_spawn(4.0, 10.0, rot=90, note="sp x 1: just east of west00 on the entry plateau")


def dress(m):
    yb, ob, ta, rb = "Tree_Birch_Yellow", "Tree_Birch_Orange", "Tree_Birch_Teal", "Tree_Birch_Red"
    # --- entry plateau: the big orange tree + arrival signs
    m.place(ob, 3.0, 16.4, rot=20, scale=1.25)
    m.place(yb, 7.6, 18.2, rot=80, scale=0.9)
    m.place("Bush_B", 9.6, 15.0, rot=10)
    m.place("Bush_A", 1.6, 3.0, rot=40)
    m.place("Sign_Board", 3.4, 6.0, rot=-20)
    m.place("Sign_Arrow", 9.0, 7.4, rot=0)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A"], geo.rect(0, 0, 11, 19), 9, seed=31,
              min_dist=1.6, avoid=[geo.rect(0, 8.5, 12, 12.5)])
    # --- basin and knoll
    m.place(yb, 14.8, 15.4, rot=150)
    m.place("Bush_A", 24.4, 17.0, rot=20)
    m.place("Stump_A", 18.0, 3.4, rot=50)
    m.place("Rock_B", 24.0, 17.6, rot=120, scale=0.8)
    m.scatter(["Sunflower_Patch", "Flower_Patch_A"], geo.rect(34, 7, 39.5, 18), 5, seed=32, min_dist=1.6,
              z_band=(HILL - 0.1, HILL + 0.1), avoid=[geo.rect(33, 13, 37.5, 20.5)])
    m.place("Butterfly", 36.5, 9.0)
    m.place("Mushroom_Cluster_A", 29.0, 6.4, rot=30)
    # the sheer east face (+x, camera side): big boulders bedded in its foot, stones high in the rock,
    # a scree fan below
    for x, y, r, sc in [(41.5, 8.6, 30, 0.8), (41.7, 13.2, 110, 0.95), (41.3, 17.2, 200, 0.7)]:
        m.place("Rock_Boulder", x, y, rot=r, scale=sc, z=EAST - 0.25)
    for y, z in [(6.6, 2.2), (10.7, 2.5), (11.6, 1.2), (15.3, 2.4), (19.0, 1.9)]:
        m.place("Rock_Cliff_Stone", face_x(m, y, 44.0, 38.0, HILL), y, rot=90, z=z, scale=1.3)
    for a, x, y, r, sc in [("Rock_A", 42.6, 10.6, 10, 0.9), ("Rock_C", 42.3, 11.6, 0, 1.2), ("Rock_C", 43.0, 9.6, 40, 0.9),
                           ("Rock_A", 42.5, 15.0, 70, 0.8), ("Rock_C", 43.1, 14.2, 20, 1.0), ("Rock_C", 42.1, 6.6, 60, 1.1),
                           ("Rock_C", 43.4, 12.6, 80, 0.7), ("Rock_B", 42.4, 18.6, 30, 0.6)]:
        m.place(a, x, y, rot=r, scale=sc)
    # --- east ground: sapling + bush at the cliff foot, the hollow log, the teal tree by the east edge
    m.place("Tree_Sapling_A", 44.0, 16.8, rot=10)
    m.place("Bush_A", 45.6, 18.2, rot=50)
    m.place("X40002_Hollow_Log", 50.2, 3.4, rot=14)
    m.place("Stump_A", 53.6, 4.6, rot=40, scale=0.8)
    m.place("Mushroom_Cluster_A", 47.4, 2.2, rot=-30)
    m.place("Rock_A", 52.8, 1.4, rot=20, scale=0.8)
    m.place("Tree_Sapling_A", 50.4, 16.2, rot=40, scale=0.8)
    m.place(ta, 62.2, 16.6, rot=20, scale=0.95)
    m.place("Bush_B", 60.4, 17.8, rot=80)
    m.place("Bush_C", 61.0, 2.4)
    m.place("Rock_Cliff_Stone", 51.5, 13.8, z=2.0)
    # --- mid band
    m.place("Tree_Sapling_A", 3.0, 26.6, rot=0, scale=0.9)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B"], geo.rect(1, 20, 12, 28), 5, seed=33, min_dist=1.6,
              z_band=(T12E - 0.1, T12W + 0.1))
    m.place("Bush_A", 16.4, 27.0, rot=30)
    m.place(ob, 26.0, 21.6, rot=60)  # T15's orange tree, clear of the Main_2 walk to rope x873
    m.place(rb, 30.6, 26.6, rot=10)
    m.place("Bush_B", 28.6, 21.6, rot=30)
    m.place("Bush_A", 44.6, 22.2, rot=70)
    m.place("Bush_C", 62.0, 25.4)
    m.place("Bush_B", 63.2, 21.4, rot=40)
    for x, z in [(4.0, 3.4), (10.0, 2.6), (15.0, 4.0)]:
        m.place("Rock_Cliff_Stone", x, 18.9, z=z)
    for x, z in [(24.0, 3.2), (44.0, 4.4)]:
        m.place("Rock_Cliff_Stone", x, 19.4, z=z)
    m.place("Rock_Cliff_Stone", 17.95, 24.0, rot=90, z=3.0)  # in the chasm wall
    m.place("Rock_C", 19.6, 22.0)
    m.place("Rock_A", 19.4, 26.0, rot=30)
    # --- upper band
    m.place(ob, 26.0, 34.6, rot=20)
    m.place("Bush_A", 24.0, 33.0, rot=10)
    m.place("Bush_B", 28.6, 35.8, rot=90)
    m.place(yb, 3.0, 35.6, rot=30, scale=0.95)
    m.place("Bush_A", 7.0, 39.6, rot=0)
    m.place("Bush_A", 47.0, 33.6, rot=20)
    m.place("Bush_B", 51.6, 35.6, rot=60)
    m.place("Bush_A", 56.4, 34.6, rot=10)
    m.place("Rock_Boulder", 44.2, 36.0, rot=200, scale=0.5)
    for x, y, z in [(6.0, 27.9, 7.0), (26.0, 27.2, 6.4), (32.0, 27.4, 6.2), (48.0, 27.3, 7.0)]:
        m.place("Rock_Cliff_Stone", x, y, z=z)
    # --- the chimney gate: banners on top of the two jambs (on the skyline) and on the crest
    m.place("X40002_Chimney_Banner", 17.3, 36.4, rot=-10)
    m.place("X40002_Chimney_Banner", 9.9, 36.4, rot=10)
    m.place("X40002_Chimney_Banner", 17.2, 43.4, rot=-10)
    m.place("Sign_Board", 19.6, 34.4, rot=38)
    m.place("Vine_Hanging_A", 16.7, 34.45, z=JAMB - 0.05)
    m.place("Vine_Hanging_A", 10.95, 35.8, rot=90, z=JAMB - 0.05, scale=(1, 1, 1.2))
    # --- summit ridge: plants on T1, the birch grove on T0, the yellow tree on T3, exit signposts
    for a, x, y, r, s in [(ta, 2.2, 43.4, 0, 0.95), (ob, 8.4, 43.6, 60, 0.9), ("Tree_Sapling_A", 21.8, 44.4, 0, 0.9)]:
        m.place(a, x, y, rot=r, scale=s)
    m.scatter(["Flower_Patch_A", "Bush_C", "Grass_Tuft_A"], geo.rect(17, 39, 30, 46), 7, seed=34, min_dist=1.6,
              z_band=(T1 - 0.1, T1 + 0.1), avoid=[geo.rect(12, 41, 30, 44)])
    # the crest stays OPEN to the camera from x 37 to the exit: only two small teal birches on T0's front half
    # (x 31-36), the rest of the grove stands in the rim gap at the back edge (x 40-44)
    for a, x, y, r, s in [(ta, 32.4, 40.4, 10, 0.85), (ta, 35.6, 40.0, 70, 0.85),
                          ("Tree_Birch_Green", 42.2, 45.2, 130, 0.78), ("Tree_Sapling_A", 40.6, 45.5, 200, 0.85),
                          ("Tree_Sapling_A", 43.8, 45.6, 260, 0.75)]:
        m.place(a, x, y, rot=r, scale=s)
    m.place("Bush_A", 34.6, 44.3)
    m.place(yb, 56.8, 43.4, rot=30, scale=1.0)
    m.place("Bush_Flowering_A", 59.4, 43.6)
    # boulders at the rim's foot (in front of the low walls, clear of the walk)
    for a, x, y, r, sc in [("Rock_Boulder", 29.0, 44.6, 20, 0.55), ("Rock_B", 50.6, 44.5, 200, 0.9),
                           ("Rock_Boulder", 16.0, 44.7, 140, 0.45), ("Rock_B", 63.2, 44.4, 320, 0.8)]:
        m.place(a, x, y, rot=r, scale=sc)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A"], geo.rect(37, 38, 49, 40.8), 5, seed=36,
              min_dist=1.6, z_band=(T0 - 0.1, T0 + 0.1))
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Sunflower_Patch"], geo.rect(53, 40, 62, 46), 6, seed=35,
              min_dist=1.6, z_band=(T3 - 0.1, T3 + 0.1))
    m.place("Butterfly", 58.0, 41.0)
    m.place("Sign_Arrow", 53.4, 35.4, rot=0)
    # way-finding: the east field is a dead end (arrow back west / up), and from the T15 ladder head on to the chimney
    m.place("Sign_Arrow", 53.2, 12.7, rot=160)
    m.place("Sign_Arrow", 32.6, 21.0, rot=150)
    # exit gate: banners on the two rock posts, like the chimney gate at the start of the ridge
    m.place("X40002_Chimney_Banner", 62.0, 32.6, rot=-10, z=T3 + 2.0)
    m.place("X40002_Chimney_Banner", 62.0, 39.4, rot=10, z=T3 + 2.0)
    # the ridge's front wall (4.9 m over T7, 8 m over T15): bedded stones and vines along it
    for x, z0, z1 in [(2.0, 9.4, 11.2), (6.0, 10.2, 11.8), (21.0, 9.0, 11.6), (25.5, 9.8, 12.0), (29.0, 8.8, 11.0),
                      (33.0, 9.4, 11.8), (37.6, 6.8, 9.8), (39.6, 11.2, 8.4), (43.4, 9.6, 11.6), (47.0, 9.0, 12.0)]:
        fp = m.face_point(x, 41.0, 0, -1)
        if fp:
            for z in (z0, z1):
                m.place("Rock_Cliff_Stone", x + (z - z0) * 0.35, fp[1] + 0.12, z=z, scale=1.1 if z == z0 else 0.85)
    for x in (55.0, 57.4):  # T3's front wall over T8
        fp = m.face_point(x, 38.0, 0, -1)
        if fp:
            m.place("Rock_Cliff_Stone", x, fp[1] + 0.12, z=10.6 if x < 56 else 9.2)
    for x, z in [(60.6, 10.4), (63.0, 8.6), (61.8, 6.4)]:  # the exit bastion's front wall over T13
        fp = m.face_point(x, 34.0, 0, -1)
        if fp:
            m.place("Rock_Cliff_Stone", x, fp[1] + 0.12, z=z)
    # --- the camera-facing east edge (+x faces): the 12.5 m ridge-end wall and the T13 wall
    for y, z, ztop in [(40.0, 3.5, T3), (43.5, 6.5, T3), (41.5, 9.8, T3), (45.0, 11.0, T3), (36.0, 8.8, T3),
                       (22.0, 2.5, T13), (27.0, 4.6, T13), (29.0, 3.2, T13), (30.0, 1.4, T13)]:
        m.place("Rock_Cliff_Stone", face_x(m, y, 66.0, 60.0, ztop), y, rot=90, z=z)
    for y, ztop, s in [(36.5, T3, 1.0), (42.0, T3, 1.15), (24.0, T13, 1.0), (28.6, T13, 0.85)]:
        m.place("Vine_Hanging_A", face_x(m, y, 66.0, 60.0, ztop, inset=0.05), y, rot=90, z=ztop - 0.05,
                scale=(1, 1, s))
    m.place("Rock_Boulder", 65.6, 44.2, rot=30, scale=0.6, required=False)
    m.place("Rock_B", 65.4, 40.6, rot=80, scale=0.8, required=False)
    # --- hanging vines on the tall faces
    for x, y, z in [(9.0, 27.5, T7W), (30.0, 27.3, T7E), (3.0, 19.4, T12W), (12.0, 18.7, T12E), (60.0, 18.5, T13)]:
        m.place("Vine_Hanging_A", x, y - 0.25, z=z - 0.05)
    for x, sc in [(4.0, 1.2), (19.6, 1.0), (23.6, 1.4), (31.0, 1.1), (35.2, 1.5), (38.6, 1.8), (41.0, 1.3), (45.6, 1.5),
                  (49.0, 1.1), (56.2, 1.3), (61.4, 1.6)]:
        fp = m.face_point(x, 41.0 if x < 52 else 37.0, 0, -1)
        if fp:
            m.place("Vine_Hanging_A", x, fp[1] - 0.05, z=fp[2] - 0.05, scale=(1, 1, sc))
    keep = [geo.rect(0, 8.5, 28, 12.6), geo.rect(18, 0, 42, 3.4), geo.rect(40, 4, 58, 13.6), (63.0, 36.0, 2.2),
            geo.rect(31.5, 11.5, 35.6, 19.2), geo.rect(22, 22.4, 35.6, 26.8), geo.rect(14, 27.6, 24.6, 35.6)]
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(12, 0, 64, 38), 40, seed=5,
              min_dist=1.8, avoid=keep)
