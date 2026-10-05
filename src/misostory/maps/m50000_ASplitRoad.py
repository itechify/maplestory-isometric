"""A Split Road (50000) - "the fork".

Classic (GMS v8) structure, from docs/research/maps/50000_ASplitRoad_50000.md:
  a wide, low two-level road map. West entry ground (T11, west00) steps down twice onto the
  LOWER ROAD (T13) that runs the whole width to east01 -> Southperry. Behind it rise a MESA
  (T8 > T6 > T3 stepped west terraces, big yellow tree, ropes up its face via the block T9)
  and the EMBANKMENT / UPPER ROAD (T4: a lower run, a 270 px ramp, a crest) that ends at
  east00 -> The Field West of Amherst. A trio of blocks (T1/T2/T0) sits on the mesa's east
  shoulder; the shoulder steps down twice onto the upper road. Maria waits on a small
  flowered platform (T5) near the start, up a short ladder, beside a red mailbox. Two
  signboards mark the fork: "Amherst" on the upper path, "Southperry" on the lower path.
  Blue Snails, Red Snails and the first Shrooms.

3D translation: the camera sees this map almost from the front, so the fork is told in
depth AND height: the lower road hugs the front edge and runs out to Southperry, bending
toward the front-right after the junction, while the upper road peels off behind the mesa,
climbs its ramp toward the back and leaves for Amherst at the back-right corner. The junction
itself is a small plaza at the foot of the embankment (x 49-60): a tall two-armed signpost,
a lamp and a bench, and a wooden stair beside ladder x2095 that carries the upper branch up
the 2.2 m embankment. The mesa doubles as the high route between them: one 3 m cliff along
the road, then terraces that step back in depth (T8 > T6 > T3W, 0.4 m hops), a broad grass
slope up to the 5 m east top (T3E) with its big yellow tree and stepped rock-trio outcrop, and two short stone
stairs down the shoulder (T3E > T7 > T4) onto the upper road.
"""

import math

import bpy

from misostory import core, geo
from misostory import materials as M
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.mapkit import MAIN_ROAD

MAP_ID = 50000
GAMEPLAY_FOCUS = (48.0, 14.0)
GAMEPLAY_SCALE = 44.0

T11 = 0.8  # west entry ground
T12 = 0.4  # step down
T5 = 2.8  # Maria's platform
# mesa: the west terraces are 60 px jump-ups (kept as 0.4 m walkable hops), then the 90 px slope
# lifts the east top to 5.0 m so the mesa clearly tops the 2.2 m embankment
T8, T6, T3W, T3E = 3.0, 3.4, 3.8, 5.0
T7 = 3.8  # mesa east step (T3E -1.2 -> T7 -1.6 -> T4W)
T4W, T4C = 2.2, 4.0  # upper road: lower run and crest
T9 = 2.4  # block in front of the mesa face
T10 = 2.0  # block in front of the upper-road ramp
TRIO, TRIO_TOP = 5.4, 5.8
SHOULDER_Y = 18.7  # both shoulder flights run along this line, with the T7 landing between them


# ---------------------------------------------------------------- local assets
def _text_mesh(coll, name, body, size, loc, mat, yaw=0.0):
    """Flat text standing up and facing -Y (turned by `yaw` deg about Z; font curve evaluated, then moved)."""
    cu = bpy.data.curves.new(name + "_crv", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = 0.015
    ob = bpy.data.objects.new(name + "_crvobj", cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (math.radians(90), 0.0, math.radians(yaw))
    bpy.context.view_layer.update()
    return core.curve_to_mesh_object(ob, name, coll, [M.get(mat)], smooth=False)


def _signboard(coll, name, text, paint):
    """Two-post wooden direction board shaped like an arrow pointing +X, with its town name."""
    mb = MeshBuilder()
    for x in (-0.95, 0.75):
        mb.box((0.17, 0.17, 2.35), loc=(x, 0.0, 1.17), mat="M_Wood", bevel=0.04, segs=1)
        mb.cyl(0.13, 0.16, loc=(x, 0.0, 2.33), mat="M_Wood_Dark", verts=6, r2=0.03)
    mb.prism([(-1.35, -0.45), (0.95, -0.45), (1.55, 0.0), (0.95, 0.45), (-1.35, 0.45)], -0.06, 0.06,
             loc=(0.0, -0.13, 1.72), rot=(90, 0, 0), mat="M_Plank", bevel=0.03, segs=1)
    mb.prism([(-1.25, -0.36), (0.9, -0.36), (1.42, 0.0), (0.9, 0.36), (-1.25, 0.36)], -0.01, 0.01,
             loc=(0.0, -0.195, 1.72), rot=(90, 0, 0), mat=paint, bevel=0.0, segs=1)
    mb.prism([(0.95, -0.22), (1.3, 0.0), (0.95, 0.22)], -0.012, 0.012, loc=(0.0, -0.21, 1.72), rot=(90, 0, 0),
             mat="M_Flat_cloth_white", bevel=0.0, segs=1)
    mb.build(name + "_Board", coll, smooth=False)
    try:
        _text_mesh(coll, name + "_Text", text, 0.36, (-0.22, -0.215, 1.72), "M_Flat_wood_dk")
    except Exception as e:  # text is a nicety; the painted arrow still reads
        print(f"[50000] signboard text failed: {e}")


@asset("X50000_Signboard_Amherst", "Architecture", footprint=3.0, tags=("sign", "landmark"))
def _sign_amherst(coll):
    """Fork signboard on the upper road: 'Amherst' with a green arrow (to the Amherst fields)."""
    _signboard(coll, "X50000_Signboard_Amherst", "Amherst", "M_Flat_roof_green")


@asset("X50000_Signboard_Southperry", "Architecture", footprint=3.0, tags=("sign", "landmark"))
def _sign_southperry(coll):
    """Fork signboard on the lower road: 'Southperry' with a blue arrow (to the port)."""
    _signboard(coll, "X50000_Signboard_Southperry", "Southperry", "M_Flat_roof_blue")


@asset("X50000_Fork_Signpost", "Architecture", footprint=1.4, tags=("sign", "landmark"))
def _fork_signpost(coll):
    """The fork's tall two-armed signpost (4.7 m) on a rock-pile base: a green 'Amherst' arm angled up and
    back toward the upper road, a blue 'Southperry' arm pointing on along the lower road, and a small
    'A Split Road' plaque below. Boards face -Y; arrows point +X (both destinations lie east)."""
    name = "X50000_Fork_Signpost"
    mb = MeshBuilder()
    mb.cyl(0.62, 0.32, mat="M_Rock", verts=9, r2=0.46, bevel=0.03)
    for x, y, r in [(0.45, -0.3, 0.3), (-0.42, -0.22, 0.26), (0.05, 0.45, 0.28), (-0.3, 0.38, 0.22)]:
        mb.sphere(r, loc=(x, y, 0.12), scale=(1.1, 1.0, 0.75), mat="M_Rock", subdiv=1)
    mb.box((0.22, 0.22, 4.45), loc=(0.0, 0.0, 2.42), mat="M_Wood", bevel=0.05, segs=1)
    mb.box((0.3, 0.3, 0.12), loc=(0.0, 0.0, 4.68), mat="M_Wood_Dark", bevel=0.03, segs=1)
    mb.cyl(0.24, 0.34, loc=(0.0, 0.0, 4.74), mat="M_Flat_roof_red", verts=8, r2=0.02)
    mb.sphere(0.07, loc=(0.0, 0.0, 5.1), mat="M_Flat_gold", subdiv=1)
    arms = [(3.95, 26.0, "Amherst", "M_Flat_roof_green", 2.7), (3.1, -10.0, "Southperry", "M_Flat_roof_blue", 3.0)]
    for z, yaw, _t, paint, L in arms:
        board = [(0.05, -0.38), (L - 0.55, -0.38), (L, 0.0), (L - 0.55, 0.38), (0.05, 0.38)]
        inlay = [(0.16, -0.3), (L - 0.6, -0.3), (L - 0.12, 0.0), (L - 0.6, 0.3), (0.16, 0.3)]
        mb.prism(board, -0.065, 0.065, loc=(0.0, 0.0, z), rot=(90, 0, yaw), mat="M_Plank", bevel=0.03, segs=1)
        mb.prism(inlay, 0.06, 0.08, loc=(0.0, 0.0, z), rot=(90, 0, yaw), mat=paint, bevel=0.0, segs=1)
        mb.prism([(L - 0.55, -0.18), (L - 0.2, 0.0), (L - 0.55, 0.18)], 0.075, 0.095, loc=(0.0, 0.0, z),
                 rot=(90, 0, yaw), mat="M_Flat_cloth_white", bevel=0.0, segs=1)
    mb.prism([(-0.6, -0.24), (0.6, -0.24), (0.6, 0.24), (-0.6, 0.24)], 0.11, 0.2, loc=(0.0, 0.0, 2.35),
             rot=(90, 0, 0), mat="M_Plank", bevel=0.03, segs=1)
    mb.build(name + "_Post", coll, smooth=False)
    for z, yaw, text, _p, L in arms:
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        xm, ym = (L - 0.5) / 2 + 0.05, -0.1
        try:
            _text_mesh(coll, f"{name}_{text}", text, 0.36, (xm * c - ym * s, xm * s + ym * c, z), "M_Flat_wood_dk",
                       yaw=yaw)
        except Exception as e:
            print(f"[50000] signpost text failed: {e}")
    try:
        _text_mesh(coll, f"{name}_Plaque", "Split Road", 0.2, (0.0, -0.215, 2.35), "M_Flat_wood_dk")
    except Exception as e:
        print(f"[50000] signpost plaque failed: {e}")


@asset("X50000_Mailbox_Post", "Props", footprint=0.7, tags=("prop", "landmark"))
def _mailbox_post(coll):
    """Maria's red mailbox on a post, with a heart and an envelope slot."""
    mb = MeshBuilder()
    mb.cyl(0.07, 1.05, mat="M_Wood", verts=8)
    mb.box((0.42, 0.32, 0.12), loc=(0, 0, 1.02), mat="M_Wood_Dark")
    mb.box((0.5, 0.42, 0.42), loc=(0, 0, 1.28), mat="M_Flat_roof_red", bevel=0.05, segs=2)
    mb.cyl(0.21, 0.5, loc=(-0.25, 0, 1.49), rot=(0, 90, 0), mat="M_Flat_roof_red", verts=14)
    mb.box((0.3, 0.04, 0.05), loc=(0, -0.22, 1.36), mat="M_Eye_Black")
    for s in (-1, 1):
        mb.sphere(0.055, loc=(s * 0.045, -0.225, 1.2), mat="M_Flat_flower_pink", subdiv=1)
    mb.cyl(0.075, 0.06, loc=(0, -0.225, 1.155), rot=(90, 0, 0), mat="M_Flat_flower_pink", verts=4, r2=0.0)
    mb.box((0.04, 0.04, 0.22), loc=(0.27, 0.0, 1.5), mat="M_Flat_flower_yellow")
    mb.box((0.14, 0.03, 0.1), loc=(0.33, 0.0, 1.58), mat="M_Flat_flower_yellow")
    mb.build("X50000_Mailbox_Post", coll, smooth=False)


def stone(m, name, cx, cy, r, top, style="grass_rock", ry=None, rot=0.0, bottom=-0.5, wobble=0.15):
    """A rock-pillar block (one 168 px floating block of the original)."""
    return m.terrace(name, geo.ellipse(cx, cy, r, ry or r * 0.9, 20, rot=rot), top=top, bottom=bottom, style=style,
                     resample_step=0.9, wobble_amt=wobble, lip=0.12, cap_thickness=0.32)


def road_ramp(m, name, p0, p1, width, **kw):
    """A ramp carrying the main road: the ramp top in M_Main_Road plus blend ribbons onto both caps in the same
    material (the same shape as mapkit's ramp blends, which always paint M_Path_Dirt)."""
    kw.setdefault("extend", 0.6)
    m.ramp(name, p0, p1, width, top_mat="M_Main_Road", blend=False, **kw)
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy) or 1.0
    ux, uy = dx / L, dy / L
    run_in, out = min(1.2, 0.35 * L), kw["extend"] + 1.1
    full = (run_in + kw["extend"]) / (run_in + out)

    def narrowing(t):
        if t <= full:
            return 1.0
        v = min(1.0, (t - full) / max(1e-6, 1.0 - full))
        return 1.0 - 0.15 * v * v * (3 - 2 * v)

    for tag, a, sgn in (("_BlendTop", p1, -1), ("_BlendFoot", p0, 1)):
        m.path(name + tag, [(a[0] + sgn * ux * run_in, a[1] + sgn * uy * run_in),
                            (a[0] - sgn * ux * out, a[1] - sgn * uy * out)],
               width=max(0.6, width - 0.08), mat="M_Main_Road", smooth_iters=0, edge_wobble=0.03,
               width_fn=narrowing, end_taper=0.75)


def face_y(m, x, y_out, y_in, ztop, inset=0.2):
    """y of a -y-facing cliff body at x: scan from y_out (in front) toward y_in until the ground
    rises to the cap, then step in by `inset` (stones embed in the dirt; ropes stand off it)."""
    y = y_out
    while y < y_in:
        z = m.ground_z(x, y)
        if z is not None and z > ztop - 0.3:
            return y + inset
        y += 0.05
    raise ValueError(f"[50000] face_y: no face at x={x} between y {y_out}..{y_in}")


def edge_x(m, y, x_from, x_to, ztop):
    """x where the ground at depth y first rises to `ztop` - 0.3, scanning from x_from toward x_to."""
    step = 0.05 if x_to > x_from else -0.05
    x = x_from
    while (x_to - x) * step > 0:
        z = m.ground_z(x, y)
        if z is not None and z > ztop - 0.3:
            return x
        x += step
    raise ValueError(f"[50000] edge_x: no edge at y={y} between x {x_from}..{x_to}")


# ---------------------------------------------------------------- the map
def build(m):
    L, D = m.size  # 76 x 32

    # ================= the trunk (west) =================
    m.terrace("T11_EntryGround", [(-1, 5.0), (8, 4.4), (13.6, 5.2), (15.6, 8.0), (15.4, 19.6), (20.8, 20.6),
                                  (20.8, 32.6), (-1, 32.6)], top=T11, bottom=-0.5)
    m.terrace("T12_StepDown", [(14.6, 3.6), (18.2, 4.2), (18.6, 9.0), (18.2, 19.6), (14.6, 19.6)], top=T12,
              bottom=-0.5)
    # Maria's little flowered platform: a grass-capped rock outcrop up a short ladder beside the trunk
    m.terrace("T5_MariaPlatform", [(10.4, 17.0), (17.2, 16.8), (17.6, 23.4), (10.6, 23.8)], top=T5, bottom=-0.5,
              style="grass_rock")
    m.ladder("Ladder_77", 13.8, 16.4, T11, T5, facing=90)

    # ================= the mesa (middle back) =================
    # a stepped plateau. The original's west steps T8 > T6 > T3 climb eastward; seen from this camera an
    # eastward step shows only its hidden west face, so the steps are turned into depth: T8 is the mesa's
    # front shelf (one 3 m face along the road, rounded west nose), and T6 and T3W are bowed bands that
    # each step 4-5 m further back, their 0.4 m faces turned toward the camera. T3E is the high east top.
    m.terrace("T8_MesaWest", [(20.6, 12.6), (21.4, 11.3), (23.6, 10.8), (29.0, 10.9), (34.0, 11.4), (37.0, 11.8),
                              (38.2, 13.0), (38.4, 32.6), (20.6, 32.6)], top=T8, bottom=-0.5)
    rope502_y = face_y(m, 22.4, 8.0, 14.0, T8, inset=-0.3)
    m.ladder("Rope_502", 22.4, rope502_y, 0.0, T8, facing=90, kind="rope")
    m.terrace("T6_MesaStep", [(22.0, 18.0), (23.2, 16.2), (26.4, 15.3), (31.0, 15.0), (35.0, 15.6), (38.2, 16.0),
                              (38.4, 32.6), (22.0, 32.6)], top=T6, bottom=-0.5)
    # (T3W's front runs straight along y 20.7 where the slope rises, so the slope's front face continues it)
    m.terrace("T3_MesaTopWest", [(23.6, 22.6), (25.0, 20.7), (29.0, 19.8), (31.6, 20.5), (32.4, 20.7), (38.4, 20.7),
                                 (38.4, 32.6), (23.6, 32.6)], top=T3W, bottom=-0.5)
    m.terrace("T3_MesaTopEast", [(37.8, 14.6), (42, 14.2), (47.8, 14.8), (48.0, 32.6), (37.8, 32.6)], top=T3E,
              bottom=-0.5)
    # the 90 px slope up to the east top: one broad grass slope spanning the whole back of the mesa (y 21-32.4),
    # so its front edge continues T3W's 0.4 m face and no loose panel or side wall shows on the cap
    m.ramp("T3_Slope", (32.6, 26.6, T3W), (38.3, 26.6, T3E), 11.8, segments=12, top_mat="M_Grass", blend=False,
           extend=0.2, bottom=T6 - 0.3)
    # T9: block standing in front of the mesa face, with a rope below and above it
    stone(m, "T9_FaceBlock", 40.6, 13.0, 1.8, T9, ry=1.7)
    m.ladder("Rope_1397", 39.8, 11.0, 0.0, T9, facing=90, kind="rope")
    m.ladder("Rope_1503", 41.6, 14.0, T9, T3E, facing=90, kind="rope")
    # the east shoulder steps down twice (T3 > T7 > T4) on two stone flights along one line
    m.terrace("T7_MesaEastStep", [(47.4, 14.2), (52.4, 14.0), (52.6, 22.4), (47.4, 22.6)], top=T7, bottom=-0.5)

    # the trio of blocks on the shoulder (T1 / T0 / T2): a rock outcrop vantage point
    stone(m, "T2_Trio", 50.6, 26.8, 2.2, TRIO, ry=1.98, rot=0.25, wobble=0.35)
    stone(m, "T1_Trio", 47.2, 27.0, 1.6, TRIO, ry=1.44, rot=-0.4, wobble=0.35)
    stone(m, "T0_TrioTop", 49.2, 29.5, 1.35, TRIO_TOP, ry=1.2, rot=0.6, wobble=0.35)
    m.ladder("Rope_2010", 50.6, 24.4, T4W, TRIO, facing=90, kind="rope")

    # ================= the upper road (embankment, back right) =================
    # Its east edge follows T4_Ramp's north edge to the crest: the ground-level pocket that used to lie between the
    # ramp, this cap and the crest (walls 2.2-4.0 m against a 1.35 m jump reach) trapped players who stepped off the
    # ramp (Iteration Two playtest finding split-road-pit-trap). The cap now fills it, so a fall off the ramp's north
    # side lands on this cap and walks back to the road.
    m.terrace("T4_UpperRoad_Low", [(49.6, 13.0), (55, 12.6), (59.6, 13.4), (60.0, 21.85), (64.3, 23.05), (64.8, 25.0),
                                   (64.8, 32.6), (47.6, 32.6), (47.6, 22.0)], top=T4W, bottom=-0.5)
    m.ladder("Ladder_2095", 53.6, 12.4, 0.0, T4W, facing=90)
    m.terrace("T4_UpperRoad_Crest", [(64.4, 18.0), (70, 17.6), (77.0, 18.0), (77.0, 32.6), (64.4, 32.6),
                                     (64.0, 25.0)], top=T4C, bottom=-0.5)
    # (the ramp carries the main-road surface itself and blends into both caps; the Upper_Road ribbons stop at
    # its foot and resume 0.3 m inside the crest, so no ribbon drapes over the ramp's lip)
    road_ramp(m, "T4_Ramp", (58.4, 19.55, T4W), (64.6, 21.3, T4C), 3.6, segments=12)
    stone(m, "T10_RampBlock", 66.0, 16.6, 1.8, T10, ry=1.6)
    m.ladder("Rope_2665", 64.8, 15.0, 0.0, T10, facing=90, kind="rope")
    m.ladder("Rope_2757", 66.6, 17.4, T10, T4C, facing=90, kind="rope")

    # shoulder flights: each ends 0.5 m inside the cap it climbs onto (cap edges probed on the real geometry)
    e3 = edge_x(m, SHOULDER_Y, 50.0, 44.0, T3E)  # T3E's east lip, seen from T7
    e7 = edge_x(m, SHOULDER_Y, 56.0, 49.0, T7)  # T7's east lip, seen from the upper road
    s1_top = e3 - 0.5
    stone_steps = dict(mat="M_StoneWall", side_mat="M_Rock", stringers=False)
    m.stairs("Shoulder_Stair1", (s1_top + 2.4, SHOULDER_Y, T7), (s1_top, SHOULDER_Y, T3E), 2.4, **stone_steps)
    s2_top = e7 - 0.5
    m.stairs("Shoulder_Stair2", (s2_top + 2.5, SHOULDER_Y, T4W), (s2_top, SHOULDER_Y, T7), 2.4, **stone_steps)

    # ================= the junction plaza (the fork) =================
    # (the plaza is painted before the stair is built, so the ribbon stays on the ground under it)
    m.path("Fork_Plaza", [(49.4, 9.2), (54.0, 9.5), (59.4, 9.4)], width=5.2)
    # a wooden stair beside ladder x2095 carries the upper branch up the 2.2 m embankment
    eF = face_y(m, 56.8, 8.0, 15.0, T4W, inset=0.0)
    m.stairs("Fork_Stair", (56.8, eF + 0.5 - 4.2, 0.0), (56.8, eF + 0.5, T4W), 2.6)

    # ================= paths =================
    # the island's main road (pale cream): west00 down the trunk, then BOTH branches of the fork
    m.path("Main_Road", [(1, 14), (6, 13.2), (11, 11.4), (15.0, 9.6), (17.4, 8.2)], **MAIN_ROAD)
    # the lower road runs along the front and bends toward the front-right after the junction (to Southperry)
    m.path("Main_Road_Lower", [(17.4, 8.2), (24, 7.0), (36, 6.3), (46, 6.6), (52, 6.9), (58, 5.6), (64, 4.6),
                               (70, 4.8), (75, 6.0)], **MAIN_ROAD)
    # the upper road (to Amherst): from the ladder head and stair top to the ramp foot, then from just inside the
    # crest to east00 (the ramp's own top carries the road between them)
    m.path("Main_Road_Upper", [(53.6, 14.8), (56.8, 14.6), (58.0, 17.2), (58.9, 19.4)], **{**MAIN_ROAD, "width": 3.4})
    m.path("Main_Road_Crest", [(64.95, 21.45), (66.6, 22.0), (70.0, 23.6), (75, 25)], **{**MAIN_ROAD, "width": 3.4})
    # (no painted trail on the mesa: a path decal draped over its 0.4 m tier steps breaks up)

    # ================= gameplay =================
    m.edge_portal("west00")
    m.edge_portal("east00")
    m.edge_portal("east01")
    m.npc("Maria", 14.6, 20.8, rot=-15)
    # Mai (MeowDB 000000050 at x 1891, y -182: the floating trio's top block T0) on the top stone, beside the trio
    # walk; Maria (x 159) stays west of her, as in MeowDB
    m.npc("Mai", 48.6, 30.0, rot=-15)
    # player_spawns[0] (MeowDB sp x -183, y 120: the west entry ground T11, ~6 m east of west00), on the trunk road
    m.player_spawn(7.0, 13.0, rot=70, note="west entry ground, on the road")
    m.route("Main_Lower_Southperry", [(1, 14), (6, 13.2), (11, 11.4), (15.0, 9.6), (17.4, 8.2), (24, 7.0), (36, 6.3),
                                      (46, 6.6), (52, 6.9), (58, 5.6), (64, 4.6), (70, 4.8), (75, 6.0)])
    # the upper branch: up the fork stair, along the embankment and over the ramp to Amherst
    m.route("Main_Upper_Amherst", [(1, 14), (11, 11.4), (17.4, 8.2), (30, 6.6), (46, 6.8), (52, 7.6), (56.8, 8.6),
                                   (56.8, eF + 1.0), (57.6, 15.6), (58.4, 17.6), (59.6, 19.6), (64.6, 21.3),
                                   (66.6, 22.0), (70.0, 23.6), (75, 25)])
    m.route("Ladder_2095", [(53.6, 7.9), (53.6, 9.6), (53.6, 14.8), (56.4, 14.8), (57.2, 14.5)])
    m.route("Maria_Ladder77", [(12.1, 10.9), (13.8, 14.6), (13.8, 19.4), (16.0, 20.4)])
    # the high route: rope x502 up the mesa face, over the stepped terraces and the slope, down the shoulder
    m.route("Mesa_HighRoute", [(22.4, 9.2), (22.4, 13.6), (23.6, 16.8), (26.4, 21.6), (30.0, 24.6), (34.0, 26.7),
                               (38.8, 26.7), (42.4, 21.4), (s1_top - 0.4, SHOULDER_Y), (s1_top + 2.4, SHOULDER_Y),
                               (s2_top - 0.2, SHOULDER_Y), (s2_top + 2.5, SHOULDER_Y), (56.6, SHOULDER_Y),
                               (58.4, 17.6)])
    m.route("Rope_1397_1503", [(39.8, 6.4), (39.8, 9.4), (39.8, 12.6), (41.6, 13.0), (41.6, 17.6), (43.0, 20.0),
                               (43.5, 20.8)])
    m.route("Rope_2665_2757", [(64.8, 13.4), (65.2, 16.2), (66.6, 16.4), (66.6, 19.4), (66.6, 20.6), (70.0, 23.6)])
    # the trio: off the shoulder's foot on the upper road, up rope x2010 onto the big base, the top stone, the small
    # base and over onto the mesa top
    m.route("Rope_2010_Trio", [(56.6, SHOULDER_Y), (56.0, 23.3), (50.6, 23.3), (50.6, 26.2), (49.4, 29.3),
                               (50.0, 27.4), (47.4, 27.0), (44.0, 26.0), (41.0, 25.0), (40.3, 24.5)])

    # ================= dressing =================
    dress(m)

    # ================= monsters (Blue Snail 25 / Shroom 18 / Red Snail 13 -> 16 proxies) =================
    road = geo.rect(19, 2.5, 74, 9.5)
    plaza = geo.rect(48, 7.4, 61, 14)
    m.mobs("Blue Snail", road, 2, seed=1, z_band=(-0.1, 0.1), avoid=[plaza])
    m.mobs("Shroom", road, 3, seed=2, z_band=(-0.1, 0.1), avoid=[plaza])
    m.mobs("Red Snail", road, 2, seed=3, z_band=(-0.1, 0.1), avoid=[plaza])
    m.mobs("Blue Snail", geo.rect(50, 14, 60, 24), 1, seed=4, z_band=(T4W - 0.1, T4W + 0.1))
    m.mobs("Red Snail", geo.rect(66, 19, 75, 31), 1, seed=5, z_band=(T4C - 0.1, T4C + 0.1))
    m.mobs("Blue Snail", geo.rect(38, 16, 47, 31), 1, seed=6, z_band=(T3E - 0.1, T3E + 0.1))
    m.mobs("Shroom", geo.rect(24, 22, 37, 31), 1, seed=7, z_band=(T3W - 0.1, T3W + 0.1))
    m.mobs("Red Snail", geo.rect(38, 16, 47, 31), 1, seed=8, z_band=(T3E - 0.1, T3E + 0.1))
    m.mobs("Blue Snail", geo.rect(1, 6, 13, 16), 1, seed=9, z_band=(T11 - 0.1, T11 + 0.1))
    m.mobs("Shroom", geo.rect(1, 24, 20, 31), 1, seed=10, z_band=(T11 - 0.1, T11 + 0.1))
    m.mobs("Shroom", geo.rect(21, 11.8, 37, 15), 1, seed=11, z_band=(T8 - 0.1, T8 + 0.1))
    m.mobs("Red Snail", geo.rect(23, 16.5, 37, 19.6), 1, seed=12, z_band=(T6 - 0.1, T6 + 0.1))
    m.player(54.2, 10.6, rot=-20)  # at the fork, by the signpost (Gameplay focus)


def dress(m):
    yb, ob, ta = "Tree_Birch_Yellow", "Tree_Birch_Orange", "Tree_Birch_Teal"
    # --- west entry ground: orange, white-trunked and teal trees around the arrival
    for a, x, y, r, s in [(ob, 2.6, 22.0, 10, 1.1), (ta, 6.4, 26.4, 80, 1.0), (yb, 2.0, 29.6, 160, 1.0),
                          (ob, 9.6, 29.8, 220, 0.95), (ta, 17.6, 28.0, 300, 0.9), (yb, 1.4, 6.6, 40, 0.85)]:
        m.place(a, x, y, rot=r, scale=s)
    for a, x, y, r in [("Bush_B", 5.0, 18.6, 20), ("Bush_A", 9.0, 7.4, 60), ("Bush_C", 18.8, 24.0, 0)]:
        m.place(a, x, y, rot=r)
    m.place("Sign_Board", 4.0, 9.4, rot=-10)
    m.place("Sign_Arrow", 19.4, 10.8, rot=0)
    m.place("Signpost_Notice", 16.6, 11.6, rot=-20)
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Grass_Tuft_A"], geo.rect(0, 5, 15, 32), 10, seed=41,
              min_dist=1.6, avoid=[geo.rect(0, 10, 18, 15.5), geo.rect(10, 16.5, 18, 24)])
    # --- Maria's platform: red flowers, a sapling and her red mailbox
    m.place("X50000_Mailbox_Post", 16.0, 21.4, rot=-10)
    m.place("Flower_Bed_Large", 11.8, 21.6)
    m.place("Tree_Sapling_A", 16.4, 22.8, rot=30, scale=0.9)
    m.place("Flower_Patch_A", 12.0, 18.2)
    for x, y, z in [(11.2, 16.9, 1.6), (16.6, 16.7, 1.9)]:  # Maria's outcrop: stones in its rock face
        m.place("Rock_Cliff_Stone", x, y - 0.25, z=z)
    # --- mesa: the big yellow tree on the crown of the east top, the little red object beside it, bushes,
    # rocks in the faces
    m.place(yb, 41.0, 29.4, rot=20, scale=1.35)
    m.place("Mushroom_Red_S", 42.6, 28.2, rot=30, scale=1.7)
    m.place("Flower_Patch_A", 43.4, 29.6)
    m.place("Flower_Bed_Large", 45.4, 23.2, rot=15)
    m.place("Bush_A", 30.6, 28.6, rot=40)
    m.place("Bush_B", 32.4, 30.4, rot=10)
    m.place("Bush_A", 26.2, 29.0, rot=70)
    m.place(ob, 24.0, 24.6, rot=120, scale=0.85)
    for x, z, ztop in [(23.0, 1.2, T8), (26.6, 2.0, T8), (25.0, 0.6, T8), (29.6, 2.0, T8), (32.2, 2.2, T8),
                       (35.6, 1.4, T8), (33.8, 0.6, T8), (28.2, 0.8, T8), (44.0, 3.6, T3E), (46.6, 1.8, T3E),
                       (39.0, 4.2, T3E), (45.2, 0.8, T3E)]:
        m.place("Rock_Cliff_Stone", x, face_y(m, x, 8.0, 18.0, ztop), z=z)
    # the row of low birches standing in front of the mesa face, kept below the mesa top so face and ropes show
    m.place("Tree_Sapling_A", 19.4, 12.0, rot=10)
    m.place(yb, 26.8, 10.0, rot=40, scale=0.74)
    m.place(ta, 31.2, 9.6, rot=60, scale=0.7)
    m.place(ob, 35.8, 10.0, rot=200, scale=0.72)
    m.place(ta, 44.2, 10.6, rot=150, scale=0.7)
    m.place(ob, 47.0, 12.4, rot=100, scale=0.66)
    # --- the trio: a stepped rock outcrop - boulders round its foot, stones in its camera faces
    m.place("Flower_Patch_B", 48.8, 29.9)
    for x, y, r, sc in [(53.6, 26.6, 30, 0.75), (53.2, 29.0, 120, 0.65), (48.2, 24.6, 200, 0.7), (48.0, 31.4, 300, 0.6)]:
        m.place("Rock_Boulder", x, y, rot=r, scale=sc)
    for x, z in [(51.8, 3.6), (49.4, 3.0)]:
        m.place("Rock_Cliff_Stone", x, face_y(m, x, 22.8, 28.0, TRIO), z=z)
    # --- the junction plaza: tall two-armed signpost at the ladder foot, a lamp and a bench by the stair
    m.place("X50000_Fork_Signpost", 51.4, 10.4, rot=16)
    m.place("Lamp_Post", 49.4, 11.6)
    m.place("Bench", 59.8, 11.4, rot=0)
    m.place("Lamp_Post", 59.0, 13.9)
    m.place("Rock_A", 48.4, 12.4, rot=20, scale=0.8)
    m.place("Flower_Patch_B", 60.8, 12.2)
    # --- upper road: bushes on the embankment foot, trees along its back, the Amherst board
    m.place("Bush_Flowering_A", 62.2, 12.6, rot=40)
    m.place("Bush_A", 61.4, 15.2, rot=80)
    for a, x, y, r, s in [(yb, 56.0, 29.6, 30, 1.0), (ob, 61.6, 30.2, 90, 0.95), (yb, 68.4, 30.4, 150, 1.05),
                          (ob, 73.6, 30.0, 210, 1.0), (ta, 52.2, 30.6, 270, 0.9)]:
        m.place(a, x, y, rot=r, scale=s)
    m.place("X50000_Signboard_Amherst", 70.4, 27.8, rot=-8)
    m.place("Bush_C", 72.2, 27.6)
    m.place("Rock_Boulder", 65.6, 28.8, rot=40, scale=0.5)
    for x, y, z in [(52.0, 12.6, 1.2), (58.9, 13.3, 0.9), (68.0, 17.5, 2.6), (72.0, 17.7, 1.8), (75.0, 17.8, 3.0),
                    (70.0, 17.6, 1.0), (62.6, 19.6, 1.6)]:
        m.place("Rock_Cliff_Stone", x, y - 0.25, z=z)
    # --- lower road: the Southperry board at the east end, rock clusters and flowered verges along it
    m.place("X50000_Signboard_Southperry", 68.4, 1.8, rot=-4)
    m.place(ta, 72.0, 13.4, rot=20, scale=0.95)
    # low wooden fence runs along the road's front verge
    m.fence([(21.0, 1.6), (29.0, 1.0), (33.0, 0.8)])
    m.fence([(45.0, 0.8), (53.0, 1.2), (56.0, 0.8)])
    m.place("Log_A", 39.0, 1.4, rot=10, scale=0.8)
    m.place("Stump_A", 63.0, 1.6, rot=40)
    for a, x, y, r, s in [("Rock_A", 27.0, 2.2, 30, 1.0), ("Rock_C", 28.2, 2.9, 0, 1.0), ("Rock_C", 44.0, 2.0, 0, 1.1),
                          ("Rock_A", 42.8, 3.0, 80, 0.7), ("Rock_B", 58.6, 2.0, 70, 0.7), ("Rock_C", 59.8, 2.6, 0, 0.9),
                          ("Rock_A", 37.0, 9.6, 10, 0.8), ("Rock_C", 29.0, 9.2, 0, 0.9), ("Rock_A", 64.4, 7.6, 50, 0.8)]:
        m.place(a, x, y, rot=r, scale=s)
    for a, x, y in [("Bush_A", 34.0, 1.6), ("Bush_C", 50.0, 1.6), ("Mushroom_Cluster_A", 61.8, 1.4),
                    ("Flower_Patch_A", 23.4, 3.6), ("Flower_Patch_B", 31.0, 3.4), ("Sunflower_Patch", 36.0, 3.0),
                    ("Flower_Patch_A", 47.6, 3.4), ("Flower_Patch_B", 53.6, 3.4), ("Flower_Patch_A", 66.4, 7.8),
                    ("Sunflower_Patch", 24.2, 9.6), ("Flower_Patch_B", 41.6, 9.4)]:
        m.place(a, x, y, rot=0)
    keep = [geo.rect(16, 2.4, 76, 9.6), geo.rect(0, 10, 18, 15.5), geo.rect(48, 7, 61, 16),
            geo.rect(53, 13, 76, 26), geo.rect(63, 13.4, 68, 16), geo.rect(38, 9.4, 43, 11.6), geo.rect(21, 9.4, 24, 11)]
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 76, 32), 45, seed=5,
              min_dist=1.8, avoid=keep)
