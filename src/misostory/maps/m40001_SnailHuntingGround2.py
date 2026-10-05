"""Snail Hunting Ground II (40001) - "the Arch Rock".

Classic (GMS v8) structure, from docs/research/maps/40001_SnailHuntingGround2_40001.md:
  ground: long west meadow (birch-log picket fences, autumn grove, a plank bridge over a
  small brook pool) -> grassy ramp up onto a MESA whose east side is a sheer 180 px cliff -> east
  field (east00). Low band: a rope-hub knob (T32), stepping stones climbing east out of the
  mesa (T34 > T33 > T30 > T29) to a shelf (T31). Mid band: one long mid terrace (T23 / T26 /
  T27), a 4-block PILLAR rising from it, stacked pairs (T28/T25) to the mid-east ledge (T22).
  Upper band: upper-west (T13) and upper-east (T12) ledges. Sky: the inverted-V ARCH of
  floating blocks (T11 > T9 > T7 > T5 > T4 apex > T6 > T8 > T10), the "V" of stacked pairs
  below it (T13 > T15 > T17 > pillar top T19 < T18 < T16 < T14 < T12) and a block stair
  (T3 > T2 > T1) from the apex to the SUMMIT (T0) with its own grove. 8 ropes, no ladders.
  Snails and Blue Snails only (67 spawns, 8 of them on the summit).

3D translation: every 60 px jump-up becomes a 0.4 m step between overlapping rock stones
(walkable hops; thin caps over dark natural-rock sides, no fringe, so the stacks read as rock
columns). The pillar is one big rock column with three grass steps sunk into its flank. The arch
becomes a real stone arch turned to face the camera: two pillar legs, a round-headed ring of
rock voussoirs (local asset X40001_Arch_Body) with a 4.9 m see-through opening, and the
stepping-stone lintel walking over its crest. In front of it the V of stacked pairs dips to
the pillar top, so the classic Λ-over-V silhouette survives. From the keystone the ribbon
(T3 > T2 > T1) climbs back to the summit ridge: T3 rests on the back of the arch crown, T2 and
T1 are a rock spur rising from the hollow floor behind the arch. The brook is a meandering creek
cut into the meadow (the meadow outline wraps a notch round it) from a rock spring at the T23 cliff
foot to a spill over the front rim, crossed by the plank footbridge; the picket fence runs along the
meadow's front edge. Ground route (the pale main road) =
meadow -> bridge -> past the mesa foot -> east field; everything above is the optional climb
whose prize is the summit grove. Camera note: with this map's yaw the camera sees the +x and
-y faces, so the east edge (x = 64) walls are dressed.
"""

import math

from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.mapkit import MAIN_ROAD

MAP_ID = 40001
GAMEPLAY_FOCUS = (35.0, 28.0)
GAMEPLAY_SCALE = 40.0

MEADOW = 0.6
MESA = 2.5
MID = 5.4  # T26 / T27
STEP = 0.4  # one 60 px hop
T13 = MID + 7 * STEP  # 8.2
T12 = MID + 8 * STEP  # 8.6
APEX = MID + 12 * STEP  # 10.2
SUMMIT = APEX + 4 * STEP  # 11.8
T31 = MESA + 3 * STEP  # 3.7
T22 = MID + 2 * STEP  # 6.2

# arch line: turned so the arch faces the isometric camera of this map (yaw -103 deg)
ARCH_D = (0.55, 0.835)  # along the arch (screen right)
ARCH_N = (0.835, -0.55)  # out of the arch face (toward the camera)
ARCH_K0 = (30.43, 28.65)  # west foot, on the corner of T13
ARCH_STEP = 1.7
# sculpted arch ring (asset frame: x along the span, z above MID, centred on the opening)
ARCH_SPRING = 0.9  # springing line above the courtyard floor
ARCH_IN = (2.45, 2.45)  # soffit half-span (the inner faces of legs T9 / T8) and rise: crown at MID + 3.35
ARCH_OUT = (3.5, 3.3)  # extrados half-span and rise: crown at MID + 4.2, inside the lintel stones
PILLAR = (34.4, 24.5)  # the pillar column (T19 top)
# (name, x, y, rx, ry, rot, top): radii varied +-25 % and the ellipses turned
V_STONES = [("T15", 30.1, 26.2, 1.5, 1.15, 25, MID + 6 * STEP), ("T17", 32.0, 25.5, 1.15, 1.0, -20, MID + 5 * STEP),
            ("T18", 35.8, 26.3, 1.2, 1.05, 40, MID + 5 * STEP), ("T16", 37.4, 27.6, 1.55, 1.2, 70, MID + 6 * STEP),
            ("T14", 39.1, 29.1, 1.3, 1.15, -35, MID + 7 * STEP)]
# the creek: a meandering brook from a rock spring at the T23 cliff foot, spilling off the meadow's front rim
CREEK = [(17.2, -1.6), (16.3, 4.0), (17.8, 8.0), (16.7, 12.0), (17.3, 16.8)]
CREEK_W = [2.4, 1.6, 2.6, 1.8, 1.5]  # full widths at the control points


@asset("X40001_Arch_Body", "Rocks", footprint=7.4, tags=("rock", "landmark"))
def _arch_body(coll):
    """The Arch Rock's sculpted body: a round-headed ring of nine beveled rock voussoirs (a deeper, proud
    keystone at the crown) springing from two impost shelves. It carries no walk surface: it sits
    under the lintel stones and turns the gap between the two pillar legs into a real opening."""
    mb = MeshBuilder()
    n = 9
    gap = math.radians(1.4)
    (ai, hi), (ao, ho) = ARCH_IN, ARCH_OUT
    for k in range(n):
        t0 = math.pi * k / n + gap
        t1 = math.pi * (k + 1) / n - gap
        key = k == n // 2
        oo = 0.14 if key else 0.0
        ts = (t0, (t0 + t1) / 2, t1)
        poly = [(-ai * math.cos(t), ARCH_SPRING + hi * math.sin(t)) for t in ts]
        poly += [(-(ao + oo) * math.cos(t), ARCH_SPRING + (ho + oo) * math.sin(t)) for t in reversed(ts)]
        d = 2.8 if key else (2.6 if k % 2 == 0 else 2.48)  # face stands proud of the lintel drums (ry 1.15)
        mb.prism(poly, -d / 2, d / 2, rot=(90, 0, 0), mat="M_Rock", bevel=0.07, segs=1)
    for s in (-1, 1):  # impost shelves where the ring springs from each leg
        mb.box((1.4, 2.8, 0.34), loc=(s * 3.0, 0.0, ARCH_SPRING - 0.13), mat="M_Rock", bevel=0.06, segs=1)
    mb.build("X40001_Arch_Body", coll, smooth=False)


def stone(m, name, cx, cy, r, top, style="grass_rock", ry=None, rot=0.0, bottom=-0.5, lip=0.03, fringe=False,
          wobble=0.15):
    """A round rock stepping stone (one 168 px floating block of the original): a thin grass cap with no
    hanging fringe over dark natural-rock sides, so the stacked heights read as rock columns."""
    return m.terrace(name, geo.ellipse(cx, cy, r, ry or r * 0.9, 20, rot=rot), top=top, bottom=bottom, style=style,
                     resample_step=0.9, wobble_amt=wobble, lip=lip, fringe=fringe, cap_thickness=0.32)


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


def face_x(m, y, x_out, x_in, ztop, inset=0.2):
    """x of a cliff body seen along x at depth y: scan from x_out (outside) toward x_in until the
    ground reaches the cap, then step in by `inset` (stones embed in the dirt)."""
    step = -0.05 if x_in < x_out else 0.05
    x = x_out
    while (x - x_in) * (1 if step < 0 else -1) > 0:
        z = m.ground_z(x, y)
        if z is not None and z > ztop - 0.3:
            return x + step * (inset / 0.05)
        x += step
    raise ValueError(f"[40001] face_x: no face at y={y} between x {x_out}..{x_in}")


def face_y(m, x, y_out, y_in, ztop, inset=0.2):
    """y of a -y-facing cliff body at x (scan from y_out in front toward y_in)."""
    y = y_out
    while y < y_in:
        z = m.ground_z(x, y)
        if z is not None and z > ztop - 0.3:
            return y + inset
        y += 0.05
    raise ValueError(f"[40001] face_y: no face at x={x} between y {y_out}..{y_in}")


def arch_pt(i, off=0.0):
    """Point i steps along the arch line, offset `off` m toward the camera."""
    return (ARCH_K0[0] + ARCH_D[0] * ARCH_STEP * i + ARCH_N[0] * off,
            ARCH_K0[1] + ARCH_D[1] * ARCH_STEP * i + ARCH_N[1] * off)


def creek_banks(pad=0.0, step=0.45):
    """(left, right, head centre, head radius) of the creek (left = -x side), offset pad m outward, from the
    mouth to the spring, along a Catmull-Rom curve through CREEK with linearly varying width."""
    pts, ws = CREEK, CREEK_W
    cen, wid = [], []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(0, i - 1)], pts[i], pts[i + 1], pts[min(len(pts) - 1, i + 2)]
        n = max(2, int(math.dist(p1, p2) / step))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            cen.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 +
                                    (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
            wid.append(ws[i] + (ws[i + 1] - ws[i]) * t)
    cen.append(pts[-1])
    wid.append(ws[-1])
    left, right = [], []
    for i, (cx, cy) in enumerate(cen):
        a, b = cen[max(0, i - 1)], cen[min(len(cen) - 1, i + 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        tl = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / tl, tx / tl
        h = wid[i] / 2 + pad
        left.append((cx + nx * h, cy + ny * h))
        right.append((cx - nx * h, cy - ny * h))
    return left, right, cen[-1], wid[-1] / 2 + pad


def creek_poly(pad=0.0, ymin=-1.25):
    """Closed creek outline (mouth -> left bank -> round spring head -> right bank), cut off straight at y = ymin
    (just past the meadow's front rim, so the bed and water stay within ~1 m of the footprint)."""
    left, right, (hx, hy), hr = creek_banks(pad)
    a0 = math.atan2(left[-1][1] - hy, left[-1][0] - hx)
    head = [(hx + math.cos(a0 - math.pi * k / 6) * hr, hy + math.sin(a0 - math.pi * k / 6) * hr) for k in range(1, 6)]
    body = [q for q in left + head + list(reversed(right)) if q[1] > ymin]
    return [(_cut_at(left, ymin), ymin)] + body + [(_cut_at(right, ymin), ymin)]


def _cut_at(line, y):
    """x where a bank polyline (running +y) crosses depth y."""
    for (x0, y0), (x1, y1) in zip(line, line[1:]):
        if y0 <= y <= y1 and y1 > y0:
            return x0 + (x1 - x0) * (y - y0) / (y1 - y0)
    return line[0][0]


def build(m):
    L, D = m.size  # 64 x 44

    # ================= ground band (front) =================
    # the creek: a meandering brook cut into the meadow (the meadow outline wraps a notch round it), from a rock
    # spring at the T23 cliff foot to a spill over the meadow's front rim; water 0.3 m below the grass
    left, right, _h, _r = creek_banks(0.0)
    notch = [p for p in creek_poly(0.0, ymin=-1.0) if p[1] > -1.0]
    # (its west edge, the west00 trail end, overhangs 1.5 m: past the plinth's thin rim, which is 0.6 m lower; a rim
    # sticking out beyond the meadow sank the trail's junction to its height, a 0.6 m step at the gate)
    m.terrace("Meadow", [(-1.5, -1), (_cut_at(left, -1.0), -1.0)] + notch +
              [(_cut_at(right, -1.0), -1.0), (26.5, -1), (29.6, 2.5), (29.2, 8.5), (28.8, 18.9), (-1.5, 18.9)],
              top=MEADOW, bottom=-0.5, smooth_iters=1, resample_step=1.2, wobble_amt=0.15)
    m.terrace("Creek_Bed", creek_poly(0.7), top=MEADOW - 0.45, bottom=-0.5, style="dirt", fringe=False,
              stones=False, smooth_iters=1, resample_step=1.0, wobble_amt=0.1, walkable=False)
    m.water("Brook", creek_poly(0.22), MEADOW - 0.3)
    BR = MEADOW + 0.06
    m.deck("Pit_Bridge", geo.rect(15.0, 8.6, 19.6, 11.8), top=BR, post_bottom=-0.3)
    m.rail("Pit_Bridge_RailS", [(15.2, 8.7), (19.4, 8.7)], top=BR, closed=False, height=0.75)
    m.rail("Pit_Bridge_RailN", [(15.2, 11.7), (19.4, 11.7)], top=BR, closed=False, height=0.75)
    # down to the low trail that passes the mesa foot
    road_ramp(m, "Meadow_Down", (28.9, 5.0, MEADOW), (32.6, 5.0, 0.0), 3.6)  # tops out 0.5 m inside the meadow edge
    # the mesa: grassy ramp on its west side, sheer cliff on its east side
    m.terrace("Mesa", [(32.4, 8.6), (36.0, 8.2), (39.8, 8.6), (40.0, 15.0), (40.2, 22.6), (32.2, 22.6), (31.9, 16.0)],
              top=MESA, bottom=-0.5)
    m.ramp("Ramp_Mesa", (27.4, 14.2, MEADOW), (32.6, 14.2, MESA), 3.6)
    m.path("Main_Road", [(1, 12), (7, 11), (14.8, 10.2)], **MAIN_ROAD)
    m.path("Main_Road_E", [(19.8, 10.2), (24.5, 8.4), (27.4, 5.2)], **MAIN_ROAD)
    m.path("Main_Road_Field", [(31.4, 5.0), (38, 4.8), (46, 6.4), (55, 9.4), (63, 12)], **MAIN_ROAD)
    m.path("Mesa_Path", [(33.2, 14.4), (36.5, 17.0), (39.2, 18.6)], width=2.2)

    # ================= low band =================
    # T32: rock knob between the meadow and the mid terrace, a rope hub
    stone(m, "T32_Knob", 24.6, 19.8, 2.3, 2.8, ry=2.1)
    m.ladder("Rope_918", 24.3, 17.1, MEADOW, 2.8, facing=90, kind="rope")
    # stepping stones out of the mesa's back-east corner (T34 > T33 > T30 > T29)
    for i, (n, x, y) in enumerate([("T34", 41.2, 19.4), ("T33", 43.6, 20.2), ("T30", 46.0, 19.6),
                                   ("T29", 48.3, 19.0)]):
        stone(m, n, x, y, 2.0, MESA + (i + 1) * STEP)
    # the crevice between T30, T29, the T31 shelf and the mid terrace was a body-wide hole 3.7 m deep at plinth
    # level (Iteration Three stuck-region scan, docs/runtime/STUCK_SCAN.md): a rock fill 0.2 m below T30
    stone(m, "T29_T30_Crevice_Fill", 47.7, 21.0, 1.3, MESA + 3 * STEP - 0.2, ry=0.9)
    # T31 shelf (L-shaped: a front shelf plus a back bay under the stacked pair)
    m.terrace("T31_Shelf", [(49.6, 14.4), (57.2, 14.6), (57.0, 21.2), (54.2, 21.6), (54.0, 30.6), (47.4, 30.6),
                            (47.2, 21.8), (49.4, 21.0)], top=T31, bottom=-0.5)
    m.ladder("Rope_2383", 53.4, 13.8, 0.0, T31, facing=90, kind="rope")

    # ================= mid band =================
    m.terrace("T23_MidWest", [(-1, 19.4), (5, 18.4), (12, 19.0), (20.2, 18.6), (21.8, 20.4), (21.8, 31.0),
                              (-1, 31.0)], top=MID + STEP, bottom=-0.5)
    m.terrace("T26_T27_Mid", [(21.2, 21.6), (30, 22.0), (40, 21.6), (47.2, 21.6), (47.4, 30.8), (46.5, 44.6),
                              (21.2, 44.6)], top=MID, bottom=-0.5)
    m.ladder("Rope_997", 25.9, 21.0, 2.8, MID, facing=90, kind="rope")
    m.ladder("Rope_1867", 43.4, 21.0, MESA + 2 * STEP, MID, facing=90, kind="rope")
    # mid-east: stacked pair T28 > T25 out of the T31 bay, then the mid-east ledge T22
    stone(m, "T28", 50.6, 24.2, 2.0, MID)
    stone(m, "T25", 52.6, 26.2, 2.0, MID + STEP)
    m.ladder("Rope_2270", 50.6, 21.8, T31, MID, facing=90, kind="rope")
    m.terrace("T22_MidEast", [(54.2, 21.4), (64.6, 21.0), (64.6, 31.2), (54.6, 31.2), (53.4, 27.5), (53.6, 24.0)],
              top=T22, bottom=-0.5)

    # ================= upper band =================
    m.terrace("T13_UpperWest", [(-1, 32.6), (6, 31.4), (14, 30.8), (22, 30.6), (26.5, 29.4), (28.8, 26.4),
                                (30.9, 27.8), (30.4, 33.0), (29.8, 40.2), (27.0, 44.6), (-1, 44.6)], top=T13,
              bottom=-0.5)
    m.ladder("Rope_412", 14.3, 30.2, MID + STEP, T13, facing=90, kind="rope")
    # (its back is trimmed to y 38.6 east of x 41 so the summit can come forward; the corner behind the
    # arch's east foot stays, where the arch walk lands)
    m.terrace("T12_UpperEast", [(38.6, 29.8), (48, 30.8), (60.0, 31.4), (60.4, 38.6), (41.2, 38.8), (39.6, 41.0),
                                (38.4, 41.2), (37.6, 39.4), (38.0, 35.6)], top=T12, bottom=-0.5)
    m.ladder("Rope_2520", 56.1, 30.6, T22, T12, facing=90, kind="rope")
    # (its east end is pulled back and rounded so it no longer stacks flush above T22's east wall; its
    # front comes forward to y ~38.5 east of the arch so the grove and the walk both fit)
    # (its east end reaches the edge + 0.9 m: at x 64.4 it left a body-wide plinth-level strip beside it, walled
    # by the containment ring, that a player fell into off the summit and could not leave)
    m.terrace("T0_Summit", [(27.2, 40.8), (28.6, 39.0), (34.4, 39.0), (37.2, 41.1), (39.4, 41.2), (41.0, 38.7),
                            (62.0, 38.4), (63.6, 39.1), (64.9, 40.9), (64.9, 44.6), (27.2, 44.6)], top=SUMMIT,
              bottom=-0.5)
    # Pockets the Iteration Three stuck-region scan found walled in between these bands (docs/runtime/STUCK_SCAN.md):
    # the plinth-level slot behind T22 under T12 and the summit (the camera-facing east slot) gets a rope up T22's
    # back face; the crack between T23 and T13, the notch between the summit, T12 and the arch's east leg, and the
    # gap between T31, T22 and T12 are filled 0.2 m below the neighbour they join.
    m.ladder("Rope_Slot_T22", 62.6, 31.8, 0.0, T22, facing=-90, kind="rope")
    m.terrace("T23_T13_Fill", [(-0.8, 30.7), (10.0, 30.7), (10.0, 31.2), (6.0, 31.8), (-0.8, 33.0)],
              top=MID + STEP - 0.2, bottom=-0.5)
    m.terrace("T12_Notch_Fill", [(36.4, 38.4), (38.4, 38.4), (38.8, 41.6), (36.6, 41.6)], top=T12 - 0.2, bottom=-0.5)
    m.terrace("T31_Corner_Fill", [(53.4, 29.9), (55.0, 29.9), (55.0, 31.6), (53.4, 31.6)], top=T31 - 0.2,
              bottom=-0.5)

    # ================= the V: pillar + stacked pairs (in front of the arch) =================
    # the pillar (T24 > T21 > T20 > T19) is ONE rock column rising from the mid terrace; its lower three
    # blocks are shelf ledges cut into its east and front flanks, spiralling up to the column top (T19)
    stone(m, "T19_PillarColumn", PILLAR[0], PILLAR[1], 1.9, MID + 4 * STEP, ry=1.6, bottom=MID - 0.5, wobble=0.2)
    for n, (x, y, r, ry, k) in [("T24_Ledge", (35.89, 23.57, 1.05, 0.9, 1)), ("T21_Ledge", (34.95, 23.02, 1.05, 0.9, 2)),
                                ("T20_Ledge", (33.65, 23.09, 1.0, 0.9, 3))]:
        # each step is sunk into the column so only a ~1 m crescent of grass ledge stands out of it
        stone(m, n, x, y, r, MID + k * STEP, ry=ry, bottom=MID - 0.5, wobble=0.1)
    # the V of stacked stones dips from the upper ledges to the column top; smaller stones spaced so each
    # cap shows a crescent of rock wall below the next
    for n, x, y, r, ry, rt, z in V_STONES:
        stone(m, n, x, y, r, z, ry=ry, rot=math.radians(rt), wobble=0.22)
    # rope x1530: from the courtyard behind the V up the back of T18
    m.ladder("Rope_1530", 35.8, 27.8, MID, MID + 5 * STEP, facing=-90, kind="rope")

    # ================= the arch (sky band) =================
    rot = math.atan2(ARCH_D[1], ARCH_D[0])
    names = ["T11_ArchW1", "T9_ArchW2", "T7_Lintel1", "T5_Lintel2", "T4_Keystone", "T6_Lintel3", "T8_ArchE2",
             "T10_ArchE3"]
    tops = [T12, T12 + STEP, T12 + 2 * STEP, T12 + 3 * STEP, APEX, APEX - STEP, APEX - 2 * STEP, APEX - 3 * STEP]
    bottoms = [-0.5, -0.5, 8.4, 8.8, 9.0, 8.8, -0.5, -0.5]  # lintel stones float: the arch opening
    for i, (n, t, b) in enumerate(zip(names, tops, bottoms)):
        x, y = arch_pt(i)
        leg = b < 0  # chunky, rough pillar legs; slimmer, smoother lintel keystones
        stone(m, n, x, y, 1.8 if leg else 1.6, t, ry=1.9 if leg else 1.15, rot=rot, bottom=b,
              wobble=0.3 if leg else 0.1)
    # the sculpted rock ring under the lintel stones: a round-headed opening 4.9 m wide between the
    # legs (not walkable and not in the ground index; the walk surface stays the stone caps above it)
    m.place("X40001_Arch_Body", *arch_pt(3.5), rot=math.degrees(rot), z=MID)
    # summit ribbon (T3 > T2 > T1) climbing back from the keystone over the hollow to the ridge.
    # T3 is fused to the back of the arch crown (it rests on the ring); T2 and T1 are a stepped rock
    # spur rising from the hollow floor. The spur is aimed deep behind the arch (>= 2 m behind its
    # plane) so it does not wall up the opening as seen from the camera.
    kx, ky = arch_pt(4)
    sx, sy = kx - ARCH_N[0] * 1.9, ky - ARCH_N[1] * 1.9
    sdx, sdy = ARCH_D[0] * 0.9 - ARCH_N[0] * 1.75, ARCH_D[1] * 0.9 - ARCH_N[1] * 1.75  # (u +0.9, N -1.75) a step
    ribbon = []
    for j, n in enumerate(["T3_Ribbon1", "T2_Ribbon2", "T1_Ribbon3"]):
        x, y = sx + sdx * j, sy + sdy * j
        top = APEX + (j + 1) * STEP
        stone(m, n, x, y, 1.5, top, ry=1.35, bottom=8.3 if j == 0 else MID - 0.5)
        ribbon.append((x, y))

    # four ivy strands hang off the ring's haunches (the opening itself stays clear); boulders at the leg feet
    vine_rot = math.degrees(math.atan2(ARCH_N[1], ARCH_N[0])) + 90.0
    (ao, ho) = ARCH_OUT
    for u, s in [(-3.25, 0.8), (-2.75, 1.0), (2.75, 0.9), (3.25, 0.75)]:
        x, y = arch_pt(3.5 + u / ARCH_STEP, off=1.36)
        ztop = MID + ARCH_SPRING + ho * math.sqrt(max(0.0, 1.0 - (u / ao) ** 2))
        m.place("Vine_Hanging_A", x, y, rot=vine_rot, z=ztop - 0.05, scale=(1, 1, s))
    for i, a, s in [(0, "Rock_A", 1.0), (1, "Rock_C", 1.2), (6, "Rock_B", 0.7), (7, "Rock_C", 1.0)]:
        x, y = arch_pt(i, off=2.1)
        m.place(a, x, y, rot=i * 50, scale=s, required=False)

    # ================= gameplay: portals + routes =================
    m.edge_portal("west00")
    m.edge_portal("east00")
    m.route("Main", [(1, 12), (7, 11), (13.0, 10.2), (17.1, 10.2), (21.0, 10.2), (24.5, 8.4), (27.6, 5.0),
                     (31.4, 5.0), (38, 4.8), (46, 6.4), (55, 9.4), (63, 12)])
    # off Main up the mesa ramp, over the stepping stones to the T31 shelf
    m.route("MesaAndStones", [(22.5, 9.4), (23.0, 10.5), (25.5, 13.6), (27.6, 14.2), (32.6, 14.2), (36.5, 17.0),
                              (41.2, 19.4), (43.6, 20.2), (46.0, 19.6), (48.3, 19.0), (51.5, 18.0), (53.0, 17.0)])
    # the west rope chain: rope x918 onto the knob, x997 to the mid terrace, along T23, x412 to T13, onto the arch
    m.route("West_Ropes", [(25.5, 13.6), (24.3, 16.0), (24.3, 18.6), (24.8, 19.6), (25.9, 20.2), (25.9, 25.0),
                           (22.0, 25.5), (18.0, 25.5), (14.3, 28.0), (14.3, 32.5), (14.3, 34.0), (24.0, 35.0),
                           (27.0, 34.0), (27.0, 33.0)])
    # the east rope chain: off Main in the field, rope x2383 to T31, x2270 to the stacked pair and T22, x2520 to T12
    m.route("East_Ropes", [(53.4, 8.9), (53.4, 12.8), (53.4, 16.0), (53.4, 17.5), (51.0, 19.5), (50.6, 20.8),
                           (50.6, 24.0), (50.6, 24.6), (52.6, 26.2), (55.6, 26.6), (56.1, 28.0), (56.1, 29.5),
                           (56.1, 33.0), (56.1, 34.5), (50.0, 35.0), (44.0, 35.5)])
    # rope x1867 from the stepping stone T33 to the mid terrace in front of the pillar
    m.route("Rope_1867", [(43.6, 20.2), (43.4, 23.5), (43.4, 25.0), (41.0, 25.6), (40.6, 24.6)])
    # rope x1530: out of the courtyard behind the V onto T18 and up the V's east arm to T12
    m.route("Rope_1530", [(35.8, 29.4), (35.8, 26.3), (37.4, 27.6), (39.1, 29.1), (40.4, 31.2), (44.0, 33.0)])
    m.route("Pillar", [(40.6, 24.6), (36.7, 23.9), (35.2, 22.35), (33.1, 22.5), (33.6, 23.9), (34.4, 24.8),
                       (32.0, 25.5), (30.1, 26.2), (29.0, 26.9), (28.3, 27.6), (26.0, 30.4), (22.0, 33.0)])
    m.route("V_East", [(34.4, 24.8), (35.8, 26.3), (37.4, 27.6), (39.1, 29.1), (40.4, 31.2), (44.0, 33.0),
                       (44.0, 35.5)])
    arch = [arch_pt(i) for i in range(8)]
    m.route("Arch", [(27.0, 33.0), (28.8, 30.4)] + arch + [(39.0, 39.4), (42.0, 38.0), (46.0, 36.0)])
    m.route("Summit", [arch_pt(4)] + ribbon + [(31.0, 40.6), (34.6, 41.6), (38.0, 42.4), (41.8, 40.4), (50.0, 40.0),
                                               (61.0, 40.0)])

    # ================= dressing =================
    dress(m)

    # ================= monsters (Snail 43 / Blue Snail 24 spawns -> 18 proxies) =================
    m.mobs("Snail", geo.rect(2, 2, 14.5, 17), 1, seed=1, z_band=(0.5, 0.7))
    m.mobs("Snail", geo.rect(19.5, 1, 28, 17), 1, seed=2, z_band=(0.5, 0.7))
    m.mobs("Snail", geo.rect(41, 1, 62, 13), 2, seed=3, z_band=(-0.2, 0.3))
    m.mobs("Snail", geo.rect(1, 20, 20, 30), 1, seed=4, z_band=(5.7, 5.9))
    m.mobs("Snail", geo.rect(21.5, 22, 30, 28), 1, seed=5, z_band=(5.3, 5.5))
    m.mobs("Snail", geo.rect(1, 33, 27, 43), 2, seed=6, z_band=(8.1, 8.3))
    m.mobs("Snail", geo.rect(44, 32, 60, 38), 1, seed=7, z_band=(8.5, 8.7))
    m.mobs("Snail", geo.rect(55, 22, 64, 30), 1, seed=8, z_band=(6.1, 6.3))
    m.mobs("Snail", geo.rect(30, 39.2, 63, 44.2), 1, seed=9, z_band=(11.7, 11.9))
    m.mobs("Blue Snail", geo.rect(2, 2, 14.5, 17), 1, seed=11, z_band=(0.5, 0.7))
    m.mobs("Blue Snail", geo.rect(41, 1, 62, 13), 1, seed=12, z_band=(-0.2, 0.3))
    m.mobs("Blue Snail", geo.rect(40, 22, 47, 30), 1, seed=13, z_band=(5.3, 5.5))
    m.mobs("Blue Snail", geo.rect(50, 15, 57, 21), 1, seed=14, z_band=(3.6, 3.8))
    m.mobs("Blue Snail", geo.rect(1, 33, 27, 43), 1, seed=15, z_band=(8.1, 8.3))
    m.mobs("Blue Snail", geo.rect(30, 39.2, 63, 44.2), 2, seed=16, z_band=(11.7, 11.9))
    m.player(38.8, 23.6, rot=-30)  # on the mid terrace at the pillar's foot (Gameplay focus)
    m.player_spawn(5.3, 12.0, rot=90, note="sp x -4: ~4 m east of west00 on the entry ground")


def dress(m):
    yb, ob, ta, rb = "Tree_Birch_Yellow", "Tree_Birch_Orange", "Tree_Birch_Teal", "Tree_Birch_Red"
    # --- west meadow: the dense autumn grove by the entrance, kept to the back and west edge
    for a, x, y, r, s in [(yb, 2.6, 16.6, 10, 1.0), (ob, 6.2, 15.6, 70, 0.95), (yb, 9.6, 16.9, 140, 1.05),
                          ("Tree_Autumn_A", 13.0, 15.6, 200, 0.9), (ob, 1.8, 3.2, 30, 0.9), (yb, 5.2, 1.4, 250, 0.8),
                          (yb, 21.0, 16.4, 90, 0.95), (ob, 25.6, 0.8, 300, 0.8)]:
        m.place(a, x, y, rot=r, scale=s)
    for a, x, y, r in [("Bush_B", 11.2, 14.0, 20), ("Bush_A", 4.0, 13.6, 70), ("Bush_C", 8.0, 2.6, 0),
                       ("Bush_Flowering_A", 23.0, 1.8, 40), ("Bush_A", 19.8, 14.8, 10)]:
        m.place(a, x, y, rot=r)
    m.place("Stump_A", 9.0, 6.4, rot=30)
    m.place("Sign_Board", 3.2, 15.0, rot=-15)
    m.place("Sign_Arrow", 4.6, 8.6, rot=0)
    # the classic white birch-log picket fence runs along the meadow's outer front edge (open at the creek mouth)
    m.fence([(1.0, -0.45), (15.0, -0.45)], asset_name="Fence_Picket_Seg")
    m.fence([(19.6, -0.45), (25.4, -0.45)], asset_name="Fence_Picket_Seg")
    # the creek: stones in the water, stones and reeds along the banks (clear of the bridge), a rock spring at the
    # T23 cliff foot (stones set in the face, a vine), rocks at the mouth where it spills over the rim
    m.place("Rock_C", 16.4, 2.6, rot=20, scale=0.7)
    m.place("Rock_C", 17.6, 6.4, rot=50, scale=0.6)
    left, right, _h, _r = creek_banks(0.45)
    for side, line in ((0, left), (1, right)):
        for k in range(2 + side, len(line) - 2, 5):
            x, y = line[k]
            if 7.6 < y < 12.8 or y < 0.4:
                continue
            if (k // 5 + side) % 2:
                m.place("Rock_C", x, y, rot=k * 37, scale=0.45 + 0.1 * (k % 3))
            else:
                m.place("Grass_Tuft_A", x, y, rot=k * 23, scale=1.2)
    for x, y, z in [(17.3, 18.35, 1.4), (16.1, 18.4, 2.5), (18.4, 18.3, 3.3)]:
        m.place("Rock_Cliff_Stone", x, y, z=z)
    m.place("Vine_Hanging_A", 16.6, 18.15, z=MID + STEP - 0.05, scale=(1, 1, 1.3))
    m.place("Rock_A", 15.9, 17.4, rot=30, scale=0.8)
    m.place("Rock_C", 18.6, 17.2, rot=80, scale=0.9)
    m.place("Rock_C", 15.6, -0.75, rot=10, scale=0.7)
    m.place("Rock_A", 18.9, -0.8, rot=60, scale=0.75)
    # --- mesa top and its sheer east face
    m.place(yb, 37.6, 10.6, rot=40, scale=0.9)
    m.place("Bush_C", 33.4, 19.0)
    m.place("Rock_B", 41.6, 10.2, rot=60)
    m.place("Rock_A", 40.9, 13.6, rot=10)
    m.place("Rock_C", 41.6, 15.0)
    for y, z in [(10.5, 1.2), (13.0, 1.7), (16.5, 1.0)]:
        m.place("Rock_Cliff_Stone", 40.25, y, rot=90, z=z)
    for x, z in [(34.0, 1.3), (37.6, 0.9)]:
        m.place("Rock_Cliff_Stone", x, 8.0, z=z)
    # --- east field: sapling + bush under the cliff, a yellow tree, the teal tree by the exit
    m.place("Tree_Sapling_A", 42.2, 7.9, rot=10)
    m.place("Bush_A", 44.2, 9.6, rot=50)
    m.place("Tree_Sapling_A", 46.4, 12.4, rot=120)
    m.place(yb, 63.0, 6.0, rot=200, scale=0.85)
    m.place(ta, 62.4, 17.8, rot=20, scale=0.9)
    m.place("Bush_B", 62.6, 15.0, rot=80)
    m.place("Bush_C", 59.8, 3.0)
    m.place("Rock_A", 50.5, 2.2, rot=40)
    m.place("Sign_Arrow", 60.6, 8.8, rot=0)
    m.place("Rock_Cliff_Stone", 51.5, 14.2, z=1.8)
    m.place("Rock_Cliff_Stone", 56.0, 14.4, z=1.2)
    # --- mid band
    m.scatter(["Flower_Patch_A", "Flower_Patch_B", "Sunflower_Patch"], geo.rect(1, 20.5, 9, 29), 7, seed=21,
              min_dist=1.6, z_band=(5.7, 5.9))
    m.place(ob, 3.0, 28.6, rot=100)
    m.place("Bush_A", 9.6, 29.4, rot=30)
    m.place(ob, 22.6, 29.6, rot=60)
    m.place(rb, 24.2, 27.0, rot=10)
    m.place("Bush_B", 22.6, 22.8, rot=10)
    m.place("Bush_A", 45.6, 28.0, rot=70)
    m.place("Bush_B", 62.4, 25.0, rot=40)
    m.place(yb, 63.0, 29.6, rot=300, scale=0.9)
    for x, y, z in [(7.0, 18.5, 3.0), (15.0, 18.6, 2.2), (2.0, 19.0, 4.2)]:
        m.place("Rock_Cliff_Stone", x, y - 0.3, z=z)
    for x, z in [(29.0, 4.0), (45.6, 4.4)]:
        m.place("Rock_Cliff_Stone", x, 21.4, z=z)
    # the V / pillar read as grouped rock masses: boulders at their feet (off the routes), moss on the stones
    for a, x, y, r, sc in [("Rock_Boulder", 31.4, 23.6, 30, 0.7), ("Rock_A", 38.8, 26.4, 70, 1.2),
                           ("Rock_Boulder", 29.0, 24.2, 150, 0.6)]:
        m.place(a, x, y, rot=r, scale=sc)
    for n, (x, y), (dx, dy), sc in [("T15", (30.1, 26.2), (0, -1), 1.0), ("T17", (32.0, 25.5), (0, -1), 0.8),
                                    ("T18", (35.8, 26.3), (0, -1), 0.9), ("T14", (39.1, 29.1), (1, 0), 1.1)]:
        fp = m.face_point(x, y, dx, dy)
        if fp:
            m.place("Vine_Hanging_A", fp[0] + dx * 0.05, fp[1] + dy * 0.05, rot=90 if dx else 0, z=fp[2] - 0.05,
                    scale=(1, 1, sc))
    # the courtyard between the V and the arch, and the hollow behind the arch
    m.place("Mushroom_Cluster_A", 37.8, 31.4, rot=-20)
    m.place("Flower_Patch_B", 36.6, 30.6)
    # (the hollow floor around the foot of the T2/T1 rock spur)
    m.place("Stump_A", 35.2, 38.7, rot=40)
    m.place("Mushroom_Cluster_A", 33.9, 38.3, rot=60)
    m.place("Flower_Patch_A", 33.6, 36.9)
    m.place("Bush_C", 35.2, 39.9)
    m.place("Rock_C", 32.9, 39.2, rot=30, scale=0.9)
    # --- upper band
    m.place(ob, 18.2, 36.4, rot=20)
    m.place("Bush_A", 15.4, 37.2, rot=10)
    m.place("Bush_B", 20.4, 37.6, rot=90)
    for a, x, y, r, s in [(yb, 2.4, 41.8, 0, 1.05), (ob, 6.8, 43.0, 80, 1.0), (ta, 11.0, 41.6, 160, 0.95),
                          (yb, 22.4, 42.4, 240, 1.0), (rb, 4.6, 36.0, 30, 0.9)]:
        m.place(a, x, y, rot=r, scale=s)
    m.place("Bush_A", 49.6, 37.2, rot=20)
    m.place("Bush_B", 53.0, 36.4, rot=60)
    m.place("Bush_A", 58.6, 36.0, rot=10)
    m.place("Rock_Boulder", 58.4, 33.2, rot=200, scale=0.55)
    for x, y, z in [(20.0, 30.5, 6.8), (24.0, 30.0, 7.2), (9.0, 31.0, 6.6)]:
        m.place("Rock_Cliff_Stone", x, y, z=z)
    for x, z in [(48.6, 7.4), (52.4, 7.1)]:
        m.place("Rock_Cliff_Stone", x, 30.7, z=z)
    # --- the summit ridge and its grove (the top prize): the walk runs along its front (y ~40), the
    # grove of yellow, orange and teal birches stands behind it (y 42.4-43.8)
    for a, x, y, r, s in [(yb, 44.6, 43.0, 10, 1.0), (ob, 48.4, 43.6, 70, 1.0), (ta, 52.2, 42.8, 130, 1.08),
                          (yb, 56.0, 43.7, 200, 1.05), (ob, 60.0, 42.9, 260, 0.95), (ta, 40.4, 43.8, 320, 0.88),
                          (rb, 28.8, 43.6, 30, 0.85)]:
        m.place(a, x, y, rot=r, scale=s)
    for a, x, y in [("Bush_Flowering_A", 46.6, 42.0), ("Bush_A", 54.2, 42.0), ("Bush_C", 58.0, 42.1),
                    ("Bush_A", 62.6, 41.9)]:
        m.place(a, x, y)
    # the top of the ribbon stair: a flower bed and a sign welcoming the climber onto the summit
    m.place("Flower_Bed_Large", 28.8, 41.4, rot=20)
    m.place("Sign_Board", 33.2, 39.6, rot=58)
    # --- hanging vines on the big faces
    for x, y, z in [(9.0, 31.0, T13), (26.0, 29.6, T13), (3.0, 19.2, MID + STEP), (18.0, 18.4, MID + STEP),
                    (58.0, 31.3, T12), (62.0, 20.9, T22), (55.5, 14.4, T31)]:
        m.place("Vine_Hanging_A", x, y - 0.25, z=z - 0.05)
    for x, sc in [(43.0, 1.2), (46.4, 0.9), (51.0, 1.3), (55.6, 1.0), (59.4, 1.25)]:  # the summit's new front wall
        fp = m.face_point(x, 40.5, 0, -1)
        if fp:
            m.place("Vine_Hanging_A", x, fp[1] - 0.05, z=fp[2] - 0.05, scale=(1, 1, sc))
    for x, z in [(44.6, 10.4), (49.0, 9.8), (53.4, 10.6), (57.6, 10.0)]:
        fp = m.face_point(x, 40.5, 0, -1)
        if fp:
            m.place("Rock_Cliff_Stone", x, fp[1] + 0.12, z=z)
    # --- the camera-facing east edge (+x faces): T22's wall, the slot under T12, the summit's end wall
    for y, z, ztop in [(23.0, 3.0, T22), (26.5, 4.6, T22), (29.5, 2.2, T22), (24.8, 1.0, T22),
                       (42.0, 4.0, SUMMIT), (43.4, 7.5, SUMMIT), (42.6, 10.2, SUMMIT), (44.0, 1.6, SUMMIT)]:
        m.place("Rock_Cliff_Stone", face_x(m, y, 66.0, 61.0, ztop), y, rot=90, z=z)
    for y, z in [(33.5, 3.0), (36.6, 5.8), (37.8, 2.4)]:  # T12's +x wall over the slot
        m.place("Rock_Cliff_Stone", face_x(m, y, 63.5, 57.0, T12), y, rot=90, z=z)
    for x, z in [(61.4, 4.8), (63.0, 8.6), (62.2, 1.8)]:  # the summit's front wall over the slot
        m.place("Rock_Cliff_Stone", x, face_y(m, x, 33.0, 43.0, SUMMIT), z=z)
    for y, ztop, s in [(25.0, T22, 1.0), (28.5, T22, 1.15), (42.8, SUMMIT, 1.2)]:
        m.place("Vine_Hanging_A", face_x(m, y, 66.0, 61.0, ztop, inset=0.05), y, rot=90, z=ztop - 0.05,
                scale=(1, 1, s))
    m.place("Vine_Hanging_A", face_x(m, 35.2, 63.5, 57.0, T12, inset=0.05), 35.2, rot=90, z=T12 - 0.05)
    m.place("Rock_Boulder", 62.8, 36.4, rot=120, scale=0.5)
    m.place("Bush_B", 63.4, 39.6, rot=30)
    m.place("Rock_B", 65.4, 43.6, rot=60, scale=0.8, required=False)
    # --- grass + flowers on open ground (routes kept clear)
    keep = [geo.rect(0, 8.4, 28, 12.6), geo.rect(30, 3, 64, 8), geo.rect(48, 7, 64, 13), geo.rect(26, 12, 34, 16.5),
            geo.rect(22, 2.8, 33, 9.0),
            creek_poly(0.5)]
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 64, 44), 70, seed=5,
              min_dist=1.8, avoid=keep)
