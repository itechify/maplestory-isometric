"""Snail Garden (1000004) - "a terraced kitchen garden in a hollow, behind a hill door".

Classic (GMS v8) structure, from docs/research/maps/1000004_SnailGarden_1000004.md:
  ground band: entrance shelf T21 (+3 steps) with the door block T13 (ladder to a
  strawberry roof) -> two 60 px risers T22/T23 -> fenced sunken basin T25 -> east bank T24.
  Low arch of eight 168 px stones over the basin (T18 T14 T19 T15 T16 T12 T17 T20, ladder
  down to T24). Mid row: west stone stair T11 -> T8 -> T6, central T9, stone T7, east T10.
  Upper: T4/T5 (ladder from T10). Top row of garden beds: T1 carrots + fruit bushes, T0
  sunflower summit (longest rope from T9), T2 purple flowers, T3 carrots. 11 ladders/ropes.
  Snail 17, Blue Snail 19, Red Snail 11. No NPCs.

3D translation: the layout puts the arrival (out00) at the back edge, where the island trail
from the Field comes in, so the courtyard between the carrot-bed wall and the central terrace is
the entrance; the round barrel door is set into the camera-facing front of a grassy door hill
at the foot of the carrot-bed column, beside the swirl, with strawberries on its crown.
The shelf runs forward to the front-left; one straight line of stone stair flights drops east
over the two risers into the fenced vegetable basin at the front; the east bank rises at the
front-right. The low arch becomes a row of separate giant tree-stump posts linked by short
plank tongues, bowing forward over the back of the basin (0.4 m steps, ladder down to the
east bank). Behind it the mid row, upper ledges and top beds step back and up; the west
column (door-block roof -> stone stair -> carrot bed) climbs the back-left wall. Both map
ends are closed by hedges.
"""

import math

from misostory import core, geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.promoted import butterfly_model

MAP_ID = 1000004
GAMEPLAY_FOCUS = (22.0, 14.0)
GAMEPLAY_SCALE = 38.0

# heights (one classic 60 px step = 0.75 m)
T25 = 0.0
T23, T22, T21 = 0.75, 1.5, 2.25
T24 = 0.75
T13 = 4.1
T11, T8, T6 = 6.75, 7.5, 8.25
T9, T7, T10 = 7.5, 8.25, 7.5
T5, T4 = 9.0, 9.75
T3, T1, T2, T0 = 10.5, 11.25, 11.25, 12.0
DOOR_HILL = 4.4  # the grassy hill carrying the barrel door (2.15 m above the shelf)
# the low arch of stump posts: classic up/down rhythm compressed to 0.4 m steps.
# (name, x, y, top, radius, variant). The row bows forward over the back of the basin in the
# middle; T14 and T17 stay back against the cliff for their ropes. Neighbours stand apart
# (air between the posts) and are joined by short plank tongues.
ARCH = [("T18", 18.4, 15.6, 2.65, 1.0, 0), ("T14", 20.4, 17.0, 3.05, 1.0, 1), ("T19", 22.0, 14.6, 2.65, 0.95, 2),
        ("T15", 24.0, 12.8, 3.05, 1.0, 3), ("T16", 26.4, 12.3, 3.45, 1.0, 0), ("T12", 29.1, 14.0, 3.85, 1.0, 2),
        ("T17", 30.4, 16.8, 3.45, 1.05, 1), ("T20", 32.3, 15.4, 3.05, 0.95, 3)]
FENCE_Y = 10.9
STUMP_BARK = ["M_Bark", "M_Flat_bark_dk", "M_Flat_stump", "M_Bark"]


# ---------------------------------------------------------------------------
# local assets (map-prefixed; candidates for the shared kit)
# ---------------------------------------------------------------------------

@asset("X1000004_Carrot_Row", "Foliage", footprint=2.2, tags=("farm",))
def _carrots(coll):
    """A dug row of carrots: orange shoulders and feathery leaf tufts (grassySoil nature/8)."""
    r = core.rng("x1000004_carrot", 1)
    soil = MeshBuilder()
    soil.box((2.2, 0.7, 0.14), loc=(0, 0, 0.05), mat="M_Path_Dirt", bevel=0.06, segs=1)
    soil.build("X1000004_Carrot_Row", coll, smooth=True, sharp_angle=50)
    mb = MeshBuilder()
    for k in range(6):
        x = -0.9 + k * 0.36 + r.uniform(-0.04, 0.04)
        y = r.uniform(-0.1, 0.1)
        mb.cyl(0.1, 0.16, loc=(x, y, 0.08), mat="M_Flat_mush_orange", verts=8, r2=0.075)
        for j in range(4):
            a = j * 1.57 + r.uniform(-0.3, 0.3)
            mb.cyl(0.035, 0.42, loc=(x, y, 0.22), rot=(math.cos(a) * 22, math.sin(a) * 22, 0), mat="M_Flat_leaf",
                   verts=4, r2=0.06)
    mb.build("X1000004_Carrot_Row_Flowers", coll, smooth=True, sharp_angle=50)


@asset("X1000004_Trellis", "Props", footprint=1.6, tags=("prop",))
def _trellis(coll):
    """Wooden garden trellis panel, 1.5 m wide x 4.5 m tall, with a leafy creeper (front -Y)."""
    r = core.rng("x1000004_trellis", 1)
    mb = MeshBuilder()
    for x in (-0.72, 0.72):
        mb.box((0.12, 0.12, 4.6), loc=(x, 0, 2.3), mat="M_Wood")
    z = 0.4
    while z < 4.5:
        mb.box((1.5, 0.06, 0.07), loc=(0, -0.02, z), mat="M_Wood_Dark")
        z += 0.55
    for k in range(-2, 3):
        mb.box((0.06, 0.06, 4.4), loc=(k * 0.3, -0.05, 2.25), rot=(0, 14 if k % 2 else -14, 0), mat="M_Wood_Dark")
    mb.build("X1000004_Trellis", coll, smooth=False)
    lv = MeshBuilder()
    for k in range(26):
        x = r.uniform(-0.65, 0.65)
        zz = r.uniform(0.2, 4.3)
        lv.sphere(r.uniform(0.12, 0.2), loc=(x, -0.1, zz), scale=(1.2, 0.5, 0.9), mat="M_Leaf", subdiv=1)
    lv.build("X1000004_Trellis_Flowers", coll, smooth=True)


@asset("X1000004_Butterfly_White", "Foliage", footprint=0.4, tags=("flower",))
def _butterfly_white(coll):
    """A visible (0.35 m) cabbage-white butterfly hovering 1.45 m up (kitchen garden)."""
    butterfly_model(coll, "X1000004_Butterfly_White", "M_Flat_flower_white", "M_Flat_flower_yellow")


# ---------------------------------------------------------------------------
# helpers
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


def face_y(m, x, y, z0, z1, reach=3.0):
    """y of the cliff body face (its most protruding point between z0 and z1) scanning +y from (x, y), the same
    probe the kit rope hangs from; None if the probe finds nothing (then callers fall back to cap_edge)."""
    try:
        bvh = m._face_bvh(x, y, reach, z0, z1)
        hs = [z0 + 0.3 + 0.3 * k for k in range(max(1, int((z1 - z0 - 0.85) / 0.3)))]
        ts = [m._hit(bvh, x, y, h, (0.0, 1.0), reach) for h in hs]
        ts = [t for t in ts if t is not None]
        return y + min(ts) if ts else None
    except Exception:  # noqa: BLE001  (private kit helpers: keep the map building if they change)
        return None


def turf_step(m, name, x0, x1, yc, width, top, base):
    """Chunky turf step for one half-riser: a separate rounded grass-capped rock block on the lower tier, its
    higher end tucked under the upper cap. Its stone body shows on the camera side, so a descent of these blocks
    reads as steps from this view (stone flights climbing along x showed their risers edge-on as paving)."""
    return m.terrace(name, geo.rounded_rect(x0, yc - width / 2, x1, yc + width / 2, 0.45), top=top,
                     bottom=base - 0.4, style="grass_rock", stones=False, cap_thickness=0.2, lip=0.15,
                     wobble_amt=0.08)


def stump_post(m, name, x, y, top, r, bottom, variant=0):
    """Walkable giant tree-stump post: bark sides, pale ring top at local height `top`.

    variant 0: plain with a big root flare; 1: moss draped over the rim; 2: orange bracket
    fungi on the bark; 3: dark bark, moss collar and a tiny mushroom tuft at the foot.
    """
    wv = m.w(x, y, top)
    wb = m.w(x, y, bottom)
    bark = STUMP_BARK[variant % len(STUMP_BARK)]
    mb = MeshBuilder()
    mb.cyl(r, (top - 0.1) - (bottom - 0.1), loc=(wb.x, wb.y, wb.z - 0.1), mat=bark, verts=22, r2=r * 0.94)
    mb.cyl(r * 1.04, 0.22, loc=(wv.x, wv.y, wv.z - 0.3), mat="M_Wood_Dark", verts=22)
    mb.cyl(r * 0.98, 0.16, loc=(wv.x, wv.y, wv.z - 0.16), mat="M_Flat_wood_lt", verts=22, bevel=0.04, segs=1)
    flare = 1.35 if variant == 0 else 1.1
    for k in range(5):
        a = 2 * math.pi * k / 5 + 0.4 + variant
        mb.cyl(r * 0.32, r * flare, loc=(wb.x + math.cos(a) * r * 0.75, wb.y + math.sin(a) * r * 0.75, wb.z + 0.15),
               rot=(0, 112, math.degrees(a)), mat=bark, verts=7, r2=r * 0.08)
    obj = mb.build(m._name(name), m.col_terrain, smooth=True, sharp_angle=40)
    m.add_ground(obj)
    ring = MeshBuilder()
    for rr in (0.62, 0.32):
        ring.cyl(r * rr, 0.012, loc=(wv.x, wv.y, wv.z - 0.004), mat="M_Flat_wood", verts=18)
        ring.cyl(r * rr - 0.06, 0.016, loc=(wv.x, wv.y, wv.z - 0.004), mat="M_Flat_wood_lt", verts=18)
    ring.build(m._name(name + "_Rings"), m.col_props, smooth=True)
    deco = MeshBuilder()
    used = False
    if variant in (1, 3):  # moss hanging over the camera-side rim
        for k in range(7):
            a = math.radians(200 + k * 22)
            q = m.w(x + math.cos(a) * r, y + math.sin(a) * r, top - 0.22 - (k % 2) * 0.12)
            deco.sphere(0.22, loc=(q.x, q.y, q.z), scale=(1.3, 1.3, 0.75), mat="M_Flat_rock_moss", subdiv=1)
        used = True
    if variant == 2:  # bracket fungi stepping up the front of the bark
        for k, (a, dz) in enumerate([(250, 0.9), (275, 1.35), (300, 0.75), (230, 1.6)]):
            q = m.w(x + math.cos(math.radians(a)) * r * 0.98, y + math.sin(math.radians(a)) * r * 0.98, top - dz)
            deco.cyl(0.26 - k * 0.03, 0.09, loc=(q.x, q.y, q.z), mat="M_Flat_mush_orange", verts=12,
                     scale=(1.0, 0.7, 1.0), rot=(0, 0, m.wyaw(a)))
        used = True
    if variant == 3:  # a tiny mushroom tuft at the foot
        for dx, dy, s in [(-0.3, -1.15, 1.0), (0.05, -1.25, 0.75), (0.32, -1.1, 0.6)]:
            q = m.w(x + dx * r, y + dy * r, bottom)
            deco.cyl(0.05 * s, 0.22 * s, loc=(q.x, q.y, q.z), mat="M_MushStem", verts=6)
            deco.dome(0.13 * s, 0.1 * s, loc=(q.x, q.y, q.z + 0.2 * s), mat="M_Spot_mush_red__mush_spot", u=10, v=3)
    if used:
        deco.build(m._name(name + "_Deco"), m.col_props, smooth=True, sharp_angle=60)
    return obj


def plank_link(m, name, a, b, width=0.96):
    """Short plank tongue between two stump posts a, b = (x, y, top, r); walkable, three boards."""
    (ax, ay, at, ar), (bx, by, bt, br) = a, b
    dx, dy = bx - ax, by - ay
    d = math.hypot(dx, dy)
    ux, uy = dx / d, dy / d
    p0 = (ax + ux * (ar - 0.35), ay + uy * (ar - 0.35), at + 0.02)
    p1 = (bx - ux * (br - 0.35), by - uy * (br - 0.35), bt + 0.02)
    run = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    pitch = math.degrees(math.atan2(p1[2] - p0[2], run))
    length = math.hypot(run, p1[2] - p0[2])
    yaw = m.wyaw(math.degrees(math.atan2(uy, ux)))
    nx, ny = -uy, ux
    mb = MeshBuilder()
    for k in (-1, 0, 1):
        o = k * width / 3
        c = m.w((p0[0] + p1[0]) / 2 + nx * o, (p0[1] + p1[1]) / 2 + ny * o, (p0[2] + p1[2]) / 2 - 0.05)
        mb.box((length + (0.04 if k else 0.12), width / 3 - 0.03, 0.1), loc=(c.x, c.y, c.z), rot=(0, -pitch, yaw),
               mat="M_Plank", bevel=0.02, segs=1)
    for t in (0.3, 0.7):  # cross battens under the boards
        c = m.w(p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, p0[2] + (p1[2] - p0[2]) * t - 0.14)
        mb.box((0.12, width + 0.1, 0.08), loc=(c.x, c.y, c.z), rot=(0, 0, yaw), mat="M_Wood_Dark")
    obj = mb.build(m._name(name), m.col_terrain, smooth=False)
    m.add_ground(obj)
    return obj


# ---------------------------------------------------------------------------

def build(m):
    L, D = m.size  # 40 x 30
    av = []  # prop footprints that mob proxies must avoid

    def rope(name, x, y_edge, z0, z1):
        """Kit knotted rope (hung plumb off the real face by m.ladder), climb position 0.3 m in front of the
        upper cap's edge."""
        return m.ladder(name, x, y_edge - 0.3, z0, z1, facing=90, kind="rope")

    def put(asset_name, x, y, rad, **kw):
        obj = m.place(asset_name, x, y, **kw)
        av.append((x, y, rad))
        return obj

    # ---------------- ground band ----------------
    # the entrance shelf also runs behind the west column as a back lane at shelf height
    m.terrace("EntranceShelf_T21", [(-0.8, 4.0), (8, 3.4), (12.6, 3.8), (14.0, 6.0), (14.2, 12.6), (17.8, 13.4),
                                    (17.8, 17.5), (18.5, 25), (19.8, 26.5), (19.8, 31.0), (-0.8, 31.0)],
              top=T21, bottom=-0.5)
    # the two 60 px risers are ~3.5 m wide bands; one straight line of stone flights at y 7.6
    # carries the trail from the shelf down into the basin (each flight ends 0.5 m inside its cap)
    m.terrace("Riser_T22", [(13.4, 2.8), (17.6, 2.6), (17.8, 12.8), (13.6, 13.0)], top=T22, bottom=-0.5)
    m.terrace("Riser_T23", [(17.2, 2.2), (21.0, 2.0), (21.2, 12.6), (17.4, 12.8)], top=T23, bottom=-0.5)
    # the stepped drop into the basin: one chunky turf step (half a riser, 0.375 m) in front of each riser
    turf_step(m, "Step_Basin_T23", 21.0, 22.4, 7.6, 2.8, (T25 + T23) / 2, T25)
    turf_step(m, "Step_T23_T22", 17.6, 19.0, 7.6, 2.8, (T23 + T22) / 2, T23)
    turf_step(m, "Step_T22_T21", 13.95, 15.35, 7.6, 2.8, (T22 + T21) / 2, T22)
    m.terrace("EastBank_T24", [(32.2, -0.8), (40.8, -0.8), (40.8, 17.8), (31.2, 17.6), (31.0, 9)], top=T24,
              bottom=-0.5)
    turf_step(m, "Step_Basin_T24", 30.1, 31.9, 5.0, 2.6, (T25 + T24) / 2, T25)

    # ---------------- west column: door block -> stone stair -> carrot bed ----------------
    m.terrace("DoorBlock_T13", geo.rounded_rect(-0.8, 9.6, 8.6, 17.4, 1.5), top=T13, bottom=T21 - 0.4)
    m.ladder("Ladder_T21_T13", 4.2, 9.05, T21, T13, facing=90)
    m.terrace("Stone_T11", [(4.4, 16.8), (9.6, 16.8), (9.6, 24.4), (5.6, 24.4), (4.4, 21.4)], top=T11,
              bottom=T21 - 0.4)
    rope("Rope_T13_T11", 7.0, cap_edge(m, 7.0, 15.6, T11), T13, T11)
    m.terrace("Stone_T8", geo.rounded_rect(1.0, 18.4, 5.8, 22.6, 1.0), top=T8, bottom=T21 - 0.4)
    # the classic stone stair T11 -> T8 -> T6: one chunky rock step between each pair of stones
    turf_step(m, "Step_T11_T8", 5.5, 6.9, 19.8, 2.4, (T11 + T8) / 2, T11)
    m.terrace("Stone_T6", geo.rounded_rect(-0.8, 19.8, 3.0, 24.4, 0.9), top=T6, bottom=T21 - 0.4)
    turf_step(m, "Step_T8_T6", 2.7, 4.1, 21.4, 2.2, (T8 + T6) / 2, T8)
    # the carrot bed is kept shallow so more of the back-left corner shows behind it
    m.terrace("CarrotBed_T1", [(-0.8, 24.0), (9.4, 24.2), (9.4, 26.6), (-0.8, 27.0)], top=T1, bottom=T21 - 0.4,
              wobble_amt=0.1)
    rope("Rope_T6_T1", 1.2, cap_edge(m, 1.2, 22.8, T1), T6, T1)
    # Two pockets of the back lane walled in by the column (Iteration Three stuck-region scan): behind the door
    # block (between it, T6, T8 and the ring) a turf step halfway up to the door block's top; between T8, T11, T6
    # and the carrot bed a rock fill 0.2 m below T11.
    turf_step(m, "Step_Lane_T13", -0.8, 1.2, 17.6, 1.6, (T21 + T13) / 2, T21)
    m.terrace("Stone_T8_T11_Fill", [(2.8, 22.4), (5.8, 22.4), (5.8, 24.2), (2.8, 24.2)], top=T11 - 0.2,
              bottom=T21 - 0.4, style="grass_rock", stones=False, wobble_amt=0.05)
    # the door hill at the foot of the column, its front face toward the courtyard and the camera
    m.terrace("DoorHill", [(-0.8, 31.0), (-0.8, 26.4), (9.0, 26.0), (9.6, 25.6), (12.2, 25.6), (12.6, 26.4),
                           (11.4, 27.4), (11.3, 31.0)], top=DOOR_HILL, bottom=T21 - 0.4, stones=False)

    # ---------------- mid row ----------------
    m.terrace("Central_T9", [(17.4, 18.0), (27.2, 18.0), (27.4, 25.2), (18.4, 25.2), (17.4, 21)], top=T9,
              bottom=-0.5)
    m.terrace("Stone_T7", geo.rounded_rect(27.0, 19.0, 30.2, 31.0, 0.8), top=T7, bottom=-0.5)
    m.terrace("East_T10", [(29.6, 18.0), (40.8, 18.0), (40.8, 24.2), (29.8, 24.2)], top=T10, bottom=-0.5)
    # the classic hops up onto stone T7 from both terraces: one turf step each
    turf_step(m, "Step_T9_T7", 25.6, 27.1, 21.5, 2.4, (T9 + T7) / 2, T9)
    turf_step(m, "Step_T10_T7", 30.1, 31.6, 21.5, 2.4, (T10 + T7) / 2, T10)

    # ---------------- upper ledges + top beds ----------------
    # The upper ledges and top beds reach down to the ground: floating at T10 - 0.4 over the back of the map they
    # roofed a 61 m2 room at plinth level (x 30-40.8, y 24-31, 7 m high), open through the slot between stone T7 and
    # this ledge (Iteration Three stuck-region scan, docs/runtime/STUCK_SCAN.md: the real controller did not get in,
    # but nothing could have got out).
    m.terrace("Ledge_T4", geo.rounded_rect(31.0, 23.6, 35.0, 27.6, 0.8), top=T4, bottom=-0.5)
    m.ladder("Ladder_T10_T4", 33.0, 23.05, T10, T4, facing=90)
    # (the slot between stone T7 and this ledge, 0.8 m wide and now 8 m deep, is filled 0.2 m below T7)
    m.terrace("T7_T4_Slot_Fill", [(29.8, 24.0), (31.6, 24.0), (31.6, 27.6), (29.8, 27.6)], top=T7 - 0.2, bottom=-0.5)
    m.terrace("Ledge_T5", geo.rounded_rect(35.0, 23.6, 40.8, 27.8, 0.8), top=T5, bottom=-0.5)
    # (kept forward of the T2 lip so the T5 -> T2 rope stands on flat ground beside it)
    turf_step(m, "Step_T5_T4", 34.7, 36.1, 25.15, 2.0, (T5 + T4) / 2, T5)
    # (down to the ground: floating at T21 - 0.4 it left a 1.85 m high cavern under itself, entered off the back
    # lane's edge and with no way out; Iteration Three stuck-region scan, docs/runtime/STUCK_SCAN.md)
    m.terrace("Summit_T0", [(19.8, 25.0), (28.6, 25.0), (28.6, 31.0), (20.0, 31.0)], top=T0, bottom=-0.5)
    ye_t0a = cap_edge(m, 23.5, 23.6, T0)
    ye_t0b = cap_edge(m, 27.9, 23.6, T0)
    rope("Rope_T9_T0", 23.5, ye_t0a, T9, T0)
    rope("Rope_T7_T0", 27.9, ye_t0b, T7, T0)
    m.terrace("PurpleBed_T2", [(29.8, 27.4), (36.6, 27.4), (36.6, 31.0), (29.8, 31.0)], top=T2, bottom=-0.5)
    ye_t2 = cap_edge(m, 35.8, 25.8, T2)
    rope("Rope_T5_T2", 35.8, ye_t2, T5, T2)
    # the real body faces behind those three ropes (the kit rope hangs ~0.12 m in front of them): the trellises
    # stand flush against them, and the routes leave the flat ground >= 0.7 m before them
    fy_t0a = face_y(m, 23.5, ye_t0a - 1.0, T9, T0) or ye_t0a + 0.25
    fy_t0b = face_y(m, 27.9, ye_t0b - 1.0, T7, T0) or ye_t0b + 0.25
    fy_t2 = face_y(m, 35.8, ye_t2 - 1.0, T5, T2) or ye_t2 + 0.25
    m.terrace("CarrotBed_T3", [(36.4, 27.8), (40.8, 27.8), (40.8, 31.0), (36.4, 31.0)], top=T3, bottom=-0.5)
    # classic: a 60 px hop between T3 and T2; one turf step keeps it walkable both ways
    turf_step(m, "Step_T3_T2", 36.4, 37.8, 30.0, 1.8, (T3 + T2) / 2, T3)

    # ---------------- the low arch of stump posts ----------------
    specs = []
    for name, x, y, top, r, var in ARCH:
        # stand each stump on the lowest ground under its footprint so no edge floats
        zs = [m.ground_z(x + dx * r * 0.9, y + dy * r * 0.9, z_from=top - 0.5)
              for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))]
        zs = [z for z in zs if z is not None]
        specs.append((name, x, y, top, r, var, min(zs) if zs else 0.0))
    for name, x, y, top, r, var, b in specs:
        stump_post(m, f"Stump_{name}", x, y, top, r, b, variant=var)
    for (na, xa, ya, ta, ra, _va), (nb, xb, yb, tb, rb, _vb) in zip(ARCH, ARCH[1:]):
        plank_link(m, f"Plank_{na}_{nb}", (xa, ya, ta, ra), (xb, yb, tb, rb))
    arch_pts = [(x, y) for _n, x, y, _t, _r, _v in ARCH]
    st = {name: (x, y, top, r) for name, x, y, top, r, _v in ARCH}
    t20x, t20y, t20top, t20r = st["T20"]
    lad_y = t20y - t20r - 0.25
    m.ladder("Ladder_T24_T20", t20x, lad_y, T24, t20top, facing=90)
    rope9_x, rope10_x = st["T14"][0] + 0.1, st["T17"][0] + 0.3
    rope("Rope_T14_T9", rope9_x, cap_edge(m, rope9_x, st["T14"][1], T9), st["T14"][2], T9)
    rope("Rope_T17_T10", rope10_x, cap_edge(m, rope10_x, st["T17"][1], T10), st["T17"][2], T10)
    # the plinth-level nook behind the west posts (between the shelf's east edge, T9 and the posts T18 / T14) and the
    # sliver between the shelf, T9 and the summit were pits a player fell into from the shelf (Iteration Three
    # stuck-region scan): filled 0.2 m below the shelf
    m.terrace("Shelf_Summit_Fill", [(18.4, 24.8), (20.4, 24.8), (20.4, 27.0), (18.4, 27.0)], top=T21 - 0.2,
              bottom=-0.5, style="grass_rock", stones=False, wobble_amt=0.05)
    m.terrace("Shelf_Nook_Fill", [(17.6, 16.4), (20.2, 16.4), (20.2, 18.4), (17.6, 18.4)], top=T21 - 0.2,
              bottom=-0.5, style="grass_rock", stones=False, wobble_amt=0.05)

    # ---------------- paths ----------------
    m.path("Path_Courtyard", [(14.0, 29.8), (14.0, 28.0), (13.6, 22.0), (13.0, 15.0), (12.6, 10.4), (12.9, 7.6),
                              (13.3, 7.6)], width=2.8)
    m.path("Path_Descent", [(13.3, 7.6), (18.0, 7.6), (23.0, 7.6)], width=2.2, end_taper=1.0)
    m.path("Path_Basin", [(23.0, 7.6), (25.0, 6.6), (27.0, 6.0), (30.0, 5.0), (33.2, 5.0), (36.5, 6.0)], width=2.4)

    # ---------------- landmark: the barrel door in its hill, beside the swirl ----------------
    # the door hill is the foot of the carrot-bed column (it fills the back-left corner behind T1);
    # its camera-facing front carries the round door, its crown a strawberry patch. The trail strip
    # x 11.75-16.25 behind the swirl stays open ground.
    fp = m.face_point(11.0, 28.6, 0, -1, drop=1.0)
    door_y = (fp[1] if fp else 25.4) + 0.02
    m.place("Hill_Door", 11.0, door_y, z=T21 - 0.02)
    for (x, y, rr, s) in [(9.9, 27.4, 0, 1.0), (10.5, 28.6, 60, 0.9), (10.0, 29.8, 120, 0.85), (8.6, 28.4, 30, 0.8)]:
        m.place("Strawberry_Bush", x, y, rot=rr, scale=s)
    put("Clover_Patch", 10.4, 21.0, 0.6, rot=40)
    put("Sign_Board", 16.8, 20.6, 0.7, rot=-20)

    # ---------------- entrance shelf + door block ----------------
    put("Tree_Birch_Yellow", 10.6, 13.6, 1.0, rot=30, scale=0.85)
    m.place("Bush_B", 9.8, 4.8, rot=40)
    m.place("Bush_A", 1.4, 7.6, rot=-30)
    for (x, y) in [(2.6, 8.4), (11.6, 17.6), (16.4, 16.4)]:
        put("Clover_Patch", x, y, 0.6, rot=y * 29)
    # a small fenced kitchen bed on the shelf, hedged at the west end
    m.place("Veg_Garden_Bed", 4.6, 6.2, rot=0, scale=0.9)
    m.place("X1000004_Carrot_Row", 8.0, 6.8, rot=90)
    m.place("Sunflower_Patch", 1.6, 4.9, rot=30)
    m.place("Sunflower_Patch", 8.6, 4.4, rot=80)
    m.fence([(-0.4, 4.3), (4.0, 3.9), (8.0, 3.7), (12.2, 4.1)])
    m.place("Hedge_Wall_4m", -0.15, 4.7, rot=90, scale=(1.0, 0.9, 1.0))
    put("Strawberry_Bush", 2.4, 14.6, 0.7)
    put("Strawberry_Bush", 7.0, 11.2, 0.7, rot=60)
    put("Flower_Patch_A", 4.0, 16.2, 0.6)
    # the risers: clover along the bands either side of the stair flights
    for (x, y) in [(15.4, 4.0), (19.0, 3.6), (15.6, 11.4), (19.2, 11.6)]:
        m.place("Clover_Patch", x, y, rot=x * 17)
    m.place("Bush_B", 19.4, 4.4, rot=30, scale=0.85)

    # ---------------- the sunken vegetable basin ----------------
    for (x, y) in [(23.4, 2.6), (27.6, 2.6)]:
        m.place("Veg_Garden_Bed", x, y, rot=0)
    m.place("X1000004_Carrot_Row", 30.2, 2.2, rot=90)
    # back row behind the path, in front of the low fence and the stump arch
    for i, x in enumerate([22.2, 22.9, 23.6, 24.3]):
        m.place("Tomato_Plant", x, 9.9, rot=i * 40)
    put("Scarecrow", 25.6, 9.6, 0.8, rot=-20)
    m.place("Veg_Garden_Bed", 28.0, 9.7, rot=0, scale=0.75)
    m.place("X1000004_Carrot_Row", 30.3, 9.6, rot=90)
    m.fence([(21.6, FENCE_Y), (25.0, FENCE_Y)])
    m.fence([(25.8, FENCE_Y), (29.4, FENCE_Y)])
    m.fence([(30.0, FENCE_Y), (31.0, FENCE_Y)])
    m.fence([(21.4, 0.4), (31.4, 0.4)])
    put("Tree_Sapling_A", 31.0, 8.4, 0.8, rot=10)
    put("Haystack", 29.4, 7.6, 1.0, rot=20, scale=0.8)
    m.scatter(["Grass_Tuft_A", "Clover_Patch"], geo.rect(21.4, 1, 31, 10.6), 8, seed=3, min_dist=1.4,
              avoid=[geo.rect(21.2, 1.2, 31.6, 3.8), geo.rect(21.4, 9.0, 31.4, 11.0), geo.rect(21.4, 4.4, 31, 8.8)])

    # ---------------- east bank: hedged at the east end, a strawberry patch ----------------
    put("Tree_Birch_Yellow", 37.4, 14.2, 1.0, rot=-20, scale=1.15)
    put("Tree_Birch_Orange", 38.2, 10.6, 1.0, rot=70, scale=0.9)
    m.place("Bush_B", 38.4, 0.9, rot=10, scale=0.85)
    put("Bush_A", 34.8, 15.8, 0.8, rot=50)
    for y0 in (1.6, 5.6, 9.6):
        m.place("Hedge_Wall_4m", 40.25, y0, rot=90, scale=(1.0, 0.9, 1.0))
    for (x, y, rr) in [(36.0, 2.5, 0), (37.2, 3.1, 50), (36.3, 3.8, 100), (37.6, 2.0, 160)]:
        put("Strawberry_Bush", x, y, 0.7, rot=rr)
    for (x, y) in [(34.6, 2.0), (38.0, 5.6), (34.4, 11.0)]:
        put("Clover_Patch", x, y, 0.6, rot=x * 7)

    # ---------------- terrace beds ----------------
    # door-block roof: strawberry patch
    put("Strawberry_Bush", 2.0, 11.6, 0.7)
    put("Strawberry_Bush", 4.2, 15.6, 0.7, rot=40)
    # T1 carrot bed: veg bed, carrot rows, red-fruit bushes (kept clear of the rope landing at x 1.2)
    put("Veg_Garden_Bed", 6.4, 25.5, 1.7, rot=0, scale=0.7)
    put("X1000004_Carrot_Row", 1.8, 26.3, 1.1, rot=0, scale=(0.9, 0.8, 1.0))
    put("X1000004_Carrot_Row", 8.6, 25.3, 1.1, rot=90, scale=(0.9, 1.0, 1.0))
    put("Strawberry_Bush", -0.2, 26.1, 0.7)
    put("Strawberry_Bush", 4.0, 26.3, 0.7, rot=30)
    # T9 central: big bush + orange flowers
    put("Bush_B", 19.0, 23.8, 1.0, rot=20)
    put("Marigold_Patch", 22.0, 19.4, 0.7, rot=10)
    put("Marigold_Patch", 25.0, 23.2, 0.7, rot=80)
    put("Clover_Patch", 20.6, 21.6, 0.6)
    # T10 east: strawberries + orange flowers
    put("Strawberry_Bush", 35.4, 19.4, 0.7)
    put("Strawberry_Bush", 38.8, 22.6, 0.7, rot=50)
    put("Marigold_Patch", 37.0, 19.6, 0.7, rot=30)
    put("Bush_A", 40.2, 19.0, 0.8)
    # T0 sunflower summit
    for (x, y) in [(25.4, 29.4), (26.6, 30.2), (24.2, 30.4), (27.6, 29.0)]:
        put("Sunflower_Patch", x, y, 0.8, rot=x * 33)
    put("Bush_C", 21.0, 30.0, 0.6)
    put("Clover_Patch", 22.0, 27.0, 0.6)
    # the tall trellises stand flush against the cliff face, behind each rope (posts half sunk in the face)
    m.place("X1000004_Trellis", 23.5, fy_t0a + 0.08, z=T9 - 0.02, rot=0, scale=(1.0, 1.0, (T0 - T9 - 0.1) / 4.6))
    m.place("X1000004_Trellis", 27.9, fy_t0b + 0.08, z=T7 - 0.02, rot=0, scale=(0.9, 1.0, (T0 - T7 - 0.1) / 4.6))
    m.place("X1000004_Trellis", 35.8, fy_t2 + 0.08, z=T5 - 0.02, rot=0, scale=(0.9, 1.0, (T2 - T5 - 0.1) / 4.6))
    # T2 purple bed, T3 carrots
    for (x, y) in [(31.2, 30.4), (33.2, 30.6), (34.4, 27.9)]:
        put("Iris_Patch", x, y, 0.6, rot=x * 19)
    put("Bush_C", 30.0, 30.6, 0.6)
    put("X1000004_Carrot_Row", 38.6, 28.4, 1.1, rot=0, scale=(0.8, 1.0, 1.0))
    put("Strawberry_Bush", 40.3, 28.5, 0.7)
    # upper ledges + stones
    m.place("Bush_C", 39.8, 26.6)
    m.place("Grass_Tuft_A", 32.0, 26.6)
    m.place("Grass_Tuft_A", 8.6, 18.0)
    # rocks and a log at the cliff feet
    for (x, y, a, s) in [(10.2, 23.0, "Rock_A", 0.8), (18.4, 26.0, "Rock_C", 0.8), (33.8, 17.0, "Rock_B", 0.6),
                         (13.2, 2.0, "Rock_C", 0.9), (36.6, 23.0, "Rock_C", 0.8)]:
        put(a, x, y, 0.7 * s + 0.2, rot=x * 37, scale=s)
    put("Log_A", 11.6, 19.2, 0.9, rot=80, scale=0.75)
    # visible butterflies over the beds
    for (x, y, a) in [(24.0, 28.0, "X1000004_Butterfly_White"), (26.4, 4.4, "X1000004_Butterfly_White"),
                      (36.6, 3.6, "Butterfly_Yellow"), (5.0, 25.6, "Butterfly_Yellow")]:
        m.place(a, x, y, rot=x * 11, scale=1.4)

    # ---------------- gameplay ----------------
    m.edge_portal("out00")
    m.player(14.6, 25.6, rot=-170)
    m.player_spawn(13.8, 25.5, rot=0, note="sp x 827: in front of out00 on the arrival shelf")
    bed_avoid = [geo.rect(21.2, 1.2, 29.8, 3.8), geo.rect(21.4, 9.0, 31.0, 11.4)] + av
    m.mobs("Snail", geo.rect(22.5, 4, 30.5, 9.0), 1, seed=1, z_band=(-0.2, 0.3), avoid=bed_avoid)
    m.mobs("Blue Snail", geo.rect(22.5, 4, 30.5, 9.0), 1, seed=2, z_band=(-0.2, 0.3), avoid=bed_avoid)
    m.mobs("Red Snail", geo.rect(22.5, 4, 30.5, 9.0), 1, seed=3, z_band=(-0.2, 0.3), avoid=bed_avoid)
    p24 = m.mobs("Red Snail", geo.rect(33, 4.4, 39.2, 12.5), 1, seed=4, z_band=(T24 - 0.2, T24 + 0.3), avoid=av)
    m.mobs("Snail", geo.rect(33, 4.4, 39.2, 12.5), 1, seed=13, z_band=(T24 - 0.2, T24 + 0.3),
           avoid=av + [(x, y, 2.6) for x, y in p24])
    m.mobs("Blue Snail", geo.rect(10, 12, 17, 22), 1, seed=5, z_band=(T21 - 0.2, T21 + 0.3), avoid=av)
    m.mobs("Snail", geo.rounded_rect(0, 10.5, 7.8, 16.6, 1.0), 1, seed=6, z_band=(T13 - 0.2, T13 + 0.3), avoid=av)
    m.mobs("Snail", geo.rect(18.5, 19, 26.5, 24.5), 1, seed=7, z_band=(T9 - 0.2, T9 + 0.3), avoid=av)
    m.mobs("Red Snail", geo.rect(32.5, 18.6, 40, 23.8), 1, seed=8, z_band=(T10 - 0.2, T10 + 0.3), avoid=av)
    m.mobs("Blue Snail", geo.rect(20.5, 25.6, 28, 30.6), 1, seed=9, z_band=(T0 - 0.2, T0 + 0.3), avoid=av)
    m.mobs("Snail", geo.rect(0, 24.4, 9.0, 26.6), 1, seed=10, z_band=(T1 - 0.2, T1 + 0.3), avoid=av)
    m.mobs("Blue Snail", geo.rect(30.4, 28, 36, 30.6), 1, seed=11, z_band=(T2 - 0.2, T2 + 0.3), avoid=av)
    m.mobs("Red Snail", geo.rect(37, 28.4, 40.4, 30.6), 1, seed=12, z_band=(T3 - 0.2, T3 + 0.3), avoid=av)

    # routes walk straight through ladder/rope climbs (the validator treats steps beside a climbable
    # as climbs); every route is checked in both directions
    m.route("Main", [(14.0, 29.4), (14.0, 28.0), (13.6, 22.0), (13.0, 15.0), (12.6, 10.4), (12.8, 7.6), (23.0, 7.6),
                     (25.0, 6.6), (30.0, 5.0), (33.2, 5.0), (36.5, 6.0), (34.0, 9.0), (t20x, lad_y - 1.4)])
    m.route("StumpArch", [(t20x, lad_y - 1.4)] + arch_pts[::-1] + [(16.4, 15.0), (14.0, 15.0)])
    m.route("WestColumn", [(12.6, 12.0), (8.6, 9.0), (4.2, 8.4), (4.2, 10.8), (4.6, 12.6), (7.0, 14.4), (7.0, 18.0),
                           (7.4, 18.6), (8.2, 19.8), (6.2, 19.8), (4.8, 20.4), (4.2, 21.4), (3.4, 21.4), (2.0, 21.9), (1.2, 22.6),
                           (1.2, 24.8), (3.6, 24.8)])
    m.route("ArchToCentral", [st["T14"][:2], (rope9_x, 19.4), (21.0, 20.6), (24.6, 21.5), (28.2, 21.5),
                              (32.4, 21.5), (34.0, 21.0), (33.0, 22.0)])
    # Summit: from T9 (on ArchToCentral) up the T9 -> T0 rope, across the sunflower summit and down the T7 rope
    # onto T7 (on ArchToCentral again); the flat ends stop 0.75 m short of the trellised faces
    m.route("Summit", [(23.5, 21.3), (23.5, fy_t0a - 0.75), (23.5, 26.6), (25.0, 27.6), (27.9, 26.8),
                       (27.9, fy_t0b - 0.75), (27.9, 21.5)])
    m.route("ArchToEast", [st["T17"][:2], (rope10_x, 19.4), (31.0, 20.0), (34.0, 20.6)])
    m.route("EastLedges", [(33.0, 22.0), (33.0, 25.15), (37.6, 25.15), (37.6, 26.6), (35.8, min(26.6, fy_t2 - 0.75)), (35.8, 28.8),
                           (33.0, 29.0), (31.0, 29.0)])
    m.route("ToCarrots", [(34.6, 29.4), (35.6, 30.0), (39.6, 30.1)])
