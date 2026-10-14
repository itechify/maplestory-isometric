"""East Entrance to Mushroom Town (30000) - "the switchback mountain", the first real climb.

Classic (GMS v8) structure, from docs/research/maps/30000_EastEntranceMushroomTown_30000.md:
  valley (in00 bottom-west, a two-step hill carrying the yellow mushroom house with a
  dormer window, tall pale stalk mushrooms, sacks; the rainbow mushroom fountain and an
  ivy signpost at the foot of the east cliff) -> two rope pitches up the east cliff to
  E1 and E2 -> hop WEST over E3 and M1, up the M2 slope onto the long M3 high terrace
  (log bench) -> ladder up to U1 -> stepping stones U1..U4 rising EAST -> S1 (three-arrow
  signpost) -> S2 slope -> the S3 summit where Peter guards the exit out00. A dead-end
  stair of islets W1..W3 rises beside the arrival point. Every hop is exactly one 60 px
  unit; climbs of 3-4 units use ropes/ladders. No monsters in v8 (MeowDB MS Classic: 6 Tutorial Jr. Sentinels).

3D translation: the camera looks from the south-east, so the climb winds BACK (+y) as it
rises: valley in front, the mid band (E2 -> E3 -> M1 -> M3) along the middle, the
stepping stones and summit along the back. The two rope pitches dominate the east end:
E1 is a squat grassy rock shelf 2.6 m up, E2 a rock shelf 5.0 m up; each ochre knotted kit rope (dark knot
bands, ink outline, whipping knot at the lip) hangs down the east end of the south face, a pennant pole beside
its top. From E2 the climb hops WEST over separate
ledges of different shapes (E3, M1), each gap bridged by a short plank walk, then up the
M2 slope onto the long M3 high terrace (log bench). The upper stepping islets rise out of a
low back meadow behind the mid band, so they read as floating platforms while staying
grounded: U1 is a grassy rock pillar against the high terrace (ladder), U2/U3 are giant red
and orange mushrooms whose flat caps you walk across, U4 and S1 are tall pillars leading
onto the summit. A dirt trail is painted along the whole climb and arrow signs mark every
switchback. Summit at ~9.4 m (the layout hint for out00 was 7.0; kept high for the
"tall climb" identity - the inter-map trail down to 40000 is built as stair flights with
landings and a flat exit apron). A recovery ladder on M3's north face gets a player who
misses a hop back out of the meadow.
"""

import math

from misostory import collision_tags as CT
from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.classic import HOUSE_PACK, mushroom_house_v2, stem_width
from misostory.mapkit import MAIN_ROAD

MAP_ID = 30000
# the two rope pitches (identity beat) + the hop west + the summit wall. Panned ~3.8 m screen-left of (29.0, 16.5)
# and tightened from 36 so the dark trail-flank embankment under the stair flight to 40000 (world trail, east of
# the footprint) is cropped to a thin strip at the right edge (full-island ray census: 18 % -> ~7 % of the frame);
# the focus stays on the valley floor (ground z 0), clear of the 0.44 m hill lip at y 12.6.
GAMEPLAY_FOCUS = (26.8, 13.4)
GAMEPLAY_SCALE = 34.0

H = 0.44  # one 60 px hop in the valley (kept just under the 0.45 m walking step)
G2, G3 = H, 2 * H
W1, W2, W3 = 2.0, 2.0 + H, 2.0 + 2 * H
E1, E2 = 2.6, 5.0  # the two rope pitches (2.6 m and 2.4 m) dominate the low hops
HM = 0.38  # mid-band hop
E3, M1 = E2 + HM, E2 + 2 * HM
M3 = M1 + 0.44  # the M2 slope rises one more unit
MEADOW = 1.2  # low back meadow the upper stepping stones rise from
U1 = M3 + 1.4  # the 3-unit ladder
HU = 0.34  # upper-band hop (lower so cap-to-cap steps stay walkable and the summit stays ~9.4 m)
U2, U3, U4, S1 = U1 + HU, U1 + 2 * HU, U1 + 3 * HU, U1 + 4 * HU
S3 = S1 + 0.45
ROAD = MAIN_ROAD["mat"]  # the climb is the island's Main road: pale cream ribbons (narrow on the shelves)


# ---------------------------------------------------------------- local assets
# pack (#75, kit/landmark_aliases.py): House_Mushroom_Yellow fitted by its stem to this stem (r 1.8). Its cap starts
# above 3 m at the island's 1.2 scale, above any jump, so like the catalog houses it needs no overhead hull.
@asset("X30000_HouseYellowBrim", "Architecture", footprint=7.2, tags=("house", "mushroom"),
       pack=dict(HOUSE_PACK, fit_nodes=(["Plaster stem house"], stem_width(1.8))))
def _house_yellow_brim(coll):
    """Yellow-capped mushroom house with a dark brim band and a round yellow mushroom dormer
    window (houseGS/house7 + door/grassySoil/window/16), wall lantern by the door."""
    stem_h, cap_r, cap_h = 3.0, 3.4, 2.6
    _stem, cap = mushroom_house_v2(coll, "X30000_HouseYellowBrim", "M_Grad_mush_yellow__flower_yellow", stem_r=1.8,
                                   stem_h=stem_h, cap_r=cap_r, cap_h=cap_h, chimney=None, collar=False)
    # the cap (r 3.4, the dormer 3.9) overhangs the ~2 m walls and starts 2.35 m up (2.8 m at the island's 1.2 scale):
    # cap and brim collide as one overhead prism (collision_tags.OVERHEAD_HULL) that leaves the space under them open
    CT.tag(cap, CT.OVERHEAD_HULL)
    mb = MeshBuilder()
    mb.torus(cap_r - 0.12, 0.2, loc=(0, 0, stem_h - 0.3), mat="M_Wood_Dark", u=40, v=6)
    # dormer: little cream turret with a round window under a tiny yellow cap
    ang = math.radians(32)
    rr = cap_r * math.cos(ang) ** 0.75
    dz = stem_h - 0.15 + cap_h * math.sin(ang)
    y = -rr + 0.15
    mb.cyl(0.55, 0.9, loc=(0.0, y + 0.25, dz - 0.35), rot=(90, 0, 0), mat="M_MushStem", verts=16)
    mb.cyl(0.42, 0.25, loc=(0.0, y - 0.62, dz - 0.35), rot=(90, 0, 0), mat="M_Wood_Dark", verts=16)
    mb.cyl(0.32, 0.3, loc=(0.0, y - 0.66, dz - 0.35), rot=(90, 0, 0), mat="M_Window", verts=16)
    mb.box((0.06, 0.08, 0.62), loc=(0.0, y - 0.82, dz - 0.35), mat="M_Wood_Dark")
    mb.box((0.62, 0.08, 0.06), loc=(0.0, y - 0.82, dz - 0.35), mat="M_Wood_Dark")
    mb.dome(0.78, 0.5, loc=(0.0, y - 0.2, dz + 0.12), scale=(1.0, 1.1, 1.0), mat="M_Grad_mush_yellow__flower_yellow",
            u=18, v=4, lip=0.12, profile=0.8)
    CT.tag(mb.build("X30000_HouseYellowBrim_Brim", coll, smooth=True, sharp_angle=60), CT.OVERHEAD_HULL)


@asset("X30000_PaleStalks", "Foliage", footprint=1.8, tags=("mushroom", "landmark"))
def _pale_stalks(coll):
    """Cluster of tall pale stalk mushrooms (acc1/grassySoil/nature/11 + 25)."""
    stems = MeshBuilder()
    caps = MeshBuilder()
    for (x, y, h, r, tilt) in ((0.0, 0.0, 4.4, 0.6, 0), (0.7, 0.3, 3.4, 0.5, 6), (-0.55, 0.35, 2.7, 0.42, -8),
                               (0.25, -0.55, 2.1, 0.36, 10)):
        k = 1.4 * r / 0.5  # chunky stems
        stems.cyl(0.2 * k, h, loc=(x, y, 0), rot=(tilt, 0, 0), mat="M_MushStem", verts=12, r2=0.13 * k)
        stems.cyl(0.34 * k, 0.35, loc=(x, y, -0.05), mat="M_MushStem", verts=12, r2=0.2 * k)
        ty = y - math.sin(math.radians(tilt)) * h
        tz = math.cos(math.radians(tilt)) * h
        cr = r * 1.5  # big round caps
        caps.dome(cr, cr * 0.6, loc=(x, ty, tz - 0.05), rot=(tilt, 0, 0), mat="M_Grad_mush_stem_dk__flower_white",
                  u=18, v=5, lip=cr * 0.15, profile=0.8)
    stems.build("X30000_PaleStalks_Stems", coll, smooth=True, sharp_angle=60)
    caps.build("X30000_PaleStalks_Caps", coll, smooth=True, sharp_angle=70)


@asset("X30000_RainbowFountain", "Props", footprint=3.4, tags=("prop", "landmark"))
def _rainbow_fountain(coll):
    """Stone basin with a red mushroom spout and a little rainbow arching over it (artificiality/9)."""
    mb = MeshBuilder()
    mb.cyl(1.55, 0.55, mat="M_StoneWall", verts=22, r2=1.6)
    mb.torus(1.5, 0.14, loc=(0, 0, 0.55), mat="M_StoneWall", u=24, v=6)
    mb.cyl(1.38, 0.04, loc=(0, 0, 0.48), mat="M_Water", verts=22)
    mb.cyl(0.18, 0.9, loc=(0, 0, 0.45), mat="M_MushStem", verts=10, r2=0.14)
    mb.dome(0.55, 0.42, loc=(0, 0, 1.3), mat="M_Spot_mush_red__mush_spot", u=16, v=5, lip=0.08, profile=0.8)
    for k in range(6):
        a = 2 * math.pi * k / 6
        mb.sphere(0.06, loc=(math.cos(a) * 0.5, math.sin(a) * 0.5, 1.0 - 0.1 * (k % 2)), mat="M_Foam", subdiv=1)
    mb.build("X30000_RainbowFountain", coll, smooth=True, sharp_angle=40)
    rb = MeshBuilder()
    cols = ["M_Flat_roof_red", "M_Flat_roof_orange", "M_Flat_roof_yellow", "M_Flat_roof_green", "M_Flat_roof_blue",
            "M_Flat_roof_purple"]
    n = 16
    for band, c in enumerate(cols):
        R = 1.55 - band * 0.11
        for k in range(n):
            a0 = math.pi * k / n
            a1 = math.pi * (k + 1) / n
            am = (a0 + a1) / 2
            seg = 2 * R * math.sin((a1 - a0) / 2) + 0.02
            rb.box((seg, 0.08, 0.11), loc=(math.cos(am) * R, 0.15, 0.55 + math.sin(am) * R),
                   rot=(0, -math.degrees(am) + 90, 0), mat=c)
    rb.build("X30000_RainbowFountain_Rainbow", coll, smooth=False)


@asset("X30000_ClimbFlag", "Props", footprint=0.6, tags=("prop", "sign"))
def _climb_flag(coll):
    """Rope-pitch marker: a slim wooden pole with a red-and-white pennant (along +X) and a spare coil of
    hemp rope (the kit M_Rope, matching the climbing strand) hung on a peg, planted on the cap beside the top of
    a climbing rope."""
    mb = MeshBuilder()
    mb.cyl(0.055, 2.1, mat="M_Wood", verts=8)
    mb.cyl(0.1, 0.12, loc=(0, 0, -0.02), mat="M_Wood_Dark", verts=8, r2=0.06)
    mb.sphere(0.085, loc=(0, 0, 2.12), mat="M_Gold", subdiv=1)
    mb.cyl(0.03, 0.24, loc=(0, 0.0, 1.0), rot=(90, 0, 0), mat="M_Wood_Dark", verts=6)
    mb.build("X30000_ClimbFlag", coll, smooth=True, sharp_angle=45)
    fl = MeshBuilder()
    fl.box((0.7, 0.03, 0.42), loc=(0.4, 0, 1.82), mat="M_Flat_cloth_red", bevel=0.01, segs=1)
    fl.box((0.7, 0.036, 0.1), loc=(0.4, 0, 1.82), mat="M_Flat_cloth_white")
    fl.build("X30000_ClimbFlag_Pennant", coll, smooth=False)
    co = MeshBuilder()
    for k, (r, z) in enumerate(((0.17, 0.92), (0.15, 0.86), (0.13, 0.8))):
        co.torus(r, 0.045, loc=(0, -0.2, z), rot=(90, 0, 0), mat="M_Rope", u=14, v=5)
    co.build("X30000_ClimbFlag_Coil", coll, smooth=True)


@asset("X30000_LogBench", "Props", footprint=2.2, tags=("prop",))
def _log_bench(coll):
    """Split-log bench on two stumps, a few tiny mushrooms at its foot (artificiality/6 + 7)."""
    mb = MeshBuilder()
    for x in (-0.75, 0.75):
        mb.cyl(0.26, 0.38, loc=(x, 0, 0), mat="M_Bark", verts=10, r2=0.24)
    mb.cyl(0.3, 2.1, loc=(-1.05, 0, 0.55), rot=(0, 90, 0), mat="M_Bark", verts=12)
    mb.box((2.0, 0.5, 0.06), loc=(0, 0, 0.83), mat="M_Flat_wood_lt")
    for x in (-1.06, 1.06):
        mb.cyl(0.27, 0.02, loc=(x, 0, 0.55), rot=(0, 90, 0), mat="M_Flat_wood_lt", verts=12)
    mb.build("X30000_LogBench", coll, smooth=True, sharp_angle=45)
    sh = MeshBuilder()
    for (x, y, h, r) in ((1.25, -0.2, 0.28, 0.14), (1.4, 0.1, 0.2, 0.1), (1.15, 0.25, 0.16, 0.08)):
        sh.cyl(r * 0.35, h, loc=(x, y, 0), mat="M_MushStem", verts=8)
        sh.dome(r, r * 0.7, loc=(x, y, h), mat="M_Grad_mush_stem_dk__flower_white", u=10, v=3)
    sh.build("X30000_LogBench_Mushrooms", coll, smooth=True)




# ---------------------------------------------------------------- helpers
def _giant_mushroom(m, tag, cx, cy, base_z, top_z, cap_r, cap_mat):
    """Giant mushroom growing from the back meadow; its flat-topped cap is a walkable stepping islet."""
    cap_h = 0.7
    stalk = MeshBuilder()
    h = top_z - cap_h - base_z + 0.25
    stalk.cyl(0.85, h, loc=m.w(cx, cy, base_z - 0.25), mat="M_MushStem", verts=16, r2=0.62)
    stalk.cyl(1.2, 0.5, loc=m.w(cx, cy, base_z - 0.2), mat="M_MushStem", verts=16, r2=0.85)
    stalk.cyl(0.7, 0.16, loc=m.w(cx, cy, top_z - cap_h - 1.0), mat="M_MushStem", verts=16, r2=1.0)
    CT.tag(stalk.build(f"{m.slug}_Mushroom_{tag}_Stalk", m.col_arch, smooth=True, sharp_angle=50), CT.WALL)
    cap = MeshBuilder()
    cap.dome(cap_r, cap_h, loc=m.w(cx, cy, top_z - cap_h), mat=cap_mat, u=32, v=8, lip=0.4, profile=0.2)
    obj = cap.build(f"{m.slug}_Mushroom_{tag}_Cap", m.col_terrain, smooth=True, sharp_angle=70)
    m.add_ground(obj)
    return obj


def _plank_walk(m, tag, p0, p1, width=2.0):
    """A short, solid plank walk bridging the gap between two ledges (p0 -> p1, local x, y, z of the
    walking surface). Boards overlap so there is no slot to fall through; two dark stringers below."""
    a = m.w(*p0)
    b = m.w(*p1)
    dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    run = math.hypot(dx, dy)
    yaw = math.degrees(math.atan2(dy, dx))
    pitch = math.degrees(math.atan2(dz, run))
    n = max(3, math.ceil(run / 0.42))
    mb = MeshBuilder()
    for i in range(n + 1):
        t = i / n
        p = a.lerp(b, t)
        mb.box((0.5, width - 0.1 * (i % 2), 0.12), loc=(p.x, p.y, p.z - 0.06), rot=(0, -pitch, yaw), mat="M_Plank",
               bevel=0.02, segs=1)
    nx, ny = -dy / run, dx / run
    mid = a.lerp(b, 0.5)
    for s in (-1, 1):
        off = s * (width / 2 - 0.2)
        mb.box((run + 0.8, 0.14, 0.2), loc=(mid.x + nx * off, mid.y + ny * off, mid.z - 0.2), rot=(0, -pitch, yaw),
               mat="M_Wood_Dark", bevel=0.02, segs=1)
    obj = mb.build(f"{m.slug}_PlankWalk_{tag}", m.col_terrain, smooth=False)
    m.add_ground(obj)
    return obj


def _face_x(m, y, top, x_out=39.8, x_in=35.0):
    """Local x of the (wobbled) east body face of a terrace at depth y: walk inward until the
    ground reaches the terrace top (that is the cap edge), then step back by the cap lip."""
    x = x_out
    while x > x_in:
        z = m.ground_z(x, y)
        if z is not None and z > top - 0.3:
            return x - 0.28
        x -= 0.05
    return None


def _edge(m, x, y, dx, dy, drop=0.5):
    """Cliff edge marching from inside (x, y) along (dx, dy): (ex, ey, z_top, z_below) or None."""
    return m.face_point(x, y, dx, dy, drop=drop)


def _vine(m, x, y, dx, dy, rot):
    e = _edge(m, x, y, dx, dy)
    if e:
        m.place("Vine_Hanging_A", e[0] + dx * 0.1, e[1] + dy * 0.1, z=e[2] - 0.14, rot=rot)


def _stone(m, x, y, dx, dy, frac, rot, scale=0.9):
    """A grey stone set into a dirt face, `frac` of the way up the face."""
    e = _edge(m, x, y, dx, dy)
    if e and e[3] is not None:
        z = e[3] + (e[2] - e[3]) * frac
        m.place("Rock_Cliff_Stone", e[0] - dx * 0.22, e[1] - dy * 0.22, z=z, rot=rot, scale=scale)


# ---------------------------------------------------------------- the map
def build(m):
    L, D = m.size  # 38 x 38

    # ================= terrain =================
    # ---- valley (front band): the two-step house hill ----
    m.terrace("Hill_G2G4", geo.rounded_rect(10.6, 1.2, 29.2, 12.6, 2.5), top=G2, bottom=-0.5)
    m.terrace("Hill_G3", geo.rounded_rect(12.6, 2.2, 25.4, 11.8, 2.0), top=G3, bottom=-0.3)

    # dead-end islet stair beside the arrival point (W1..W3): grassy rock pillars
    for i, (x, y, top) in enumerate(((3.4, 15.2, W1), (5.4, 15.6, W2), (7.4, 16.0, W3))):
        m.terrace(f"WestIslet_W{i + 1}", geo.ellipse(x, y, 1.9, 1.8, 18), top=top, bottom=-0.5,
                  style="grass_dirt")
    m.ladder("Ladder_W1", 3.4, 13.05, 0.0, W1, facing=90)

    # ---- east cliff: E1 and E2 are grassy ROCK shelves; each rope hangs down the lit east end of the
    # camera-facing south face (no notch: the kit rope hangs plumb against the real face) ----
    m.terrace("Shelf_E1", [(32.4, 13.6), (33.0, 12.4), (34.4, 11.9), (36.4, 11.8), (37.8, 12.1), (38.5, 13.4),
                           (38.3, 15.8), (37.2, 16.9), (33.6, 16.9), (32.5, 15.6)],
              top=E1, bottom=-0.5, style="grass_rock")
    m.terrace("Shelf_E2", [(32.3, 17.4), (32.9, 16.4), (35.0, 16.3), (37.3, 16.1), (38.5, 16.9), (38.6, 21.6),
                           (37.4, 23.4), (33.6, 23.6), (32.6, 22.4), (32.3, 20.6)],
              top=E2, bottom=-0.5, style="grass_rock")

    # ---- mid band: hop west over separate ledges, slope up, the long M3 terrace ----
    m.terrace("Ledge_E3", [(24.5, 17.6), (27.4, 16.7), (30.4, 17.3), (31.0, 19.2), (30.8, 23.0), (29.4, 24.9),
                           (25.8, 25.4), (24.4, 23.2)], top=E3, bottom=-0.5)
    # M1 reaches a tongue under M3; M3's east lip is notched there so the M2 slope runs up a shallow
    # cut and lands flush on the high terrace (no grass lip across the trail)
    m.terrace("Ledge_M1", [(18.4, 17.6), (21.4, 17.1), (23.3, 18.0), (23.4, 21.0), (22.9, 25.0), (20.6, 26.2),
                           (18.6, 25.9), (18.5, 24.1), (16.5, 24.1), (16.5, 18.7), (18.45, 18.7)], top=M1, bottom=-0.5)
    m.terrace("HighTerrace_M3", [(-0.6, 17.4), (8.0, 17.0), (18.6, 17.4), (18.65, 19.3), (17.2, 19.3), (17.2, 23.5),
                                 (18.7, 23.5), (18.8, 26.2), (12.0, 27.0), (-0.6, 27.4)], top=M3, bottom=-0.5)
    m.ramp("Slope_M2", (21.2, 21.4, M1), (16.9, 21.4, M3), 3.2, top_mat=ROAD)
    # low back meadow behind the mid band: the stepping stones rise out of it like islets
    m.terrace("BackMeadow", [(-0.6, 26.4), (30.0, 25.8), (30.0, 38.6), (-0.6, 38.6)], top=MEADOW, bottom=-0.5)

    # ---- upper band: stepping stones rising east, the summit ----
    m.terrace("Stone_U1", geo.ellipse(8.8, 27.8, 2.3, 2.3, 20), top=U1, bottom=MEADOW - 0.3)
    _giant_mushroom(m, "U2", 11.8, 29.6, MEADOW, U2, 2.4, "M_Spot_mush_red__mush_spot")
    _giant_mushroom(m, "U3", 14.8, 31.2, MEADOW, U3, 2.4, "M_Spot_mush_orange__mush_spot")
    m.terrace("Stone_U4", geo.rounded_rect(16.3, 28.6, 22.8, 35.0, 1.6), top=U4, bottom=MEADOW - 0.3)
    # S1 reaches a tongue under the summit; the summit's west lip is notched for the S2 slope
    m.terrace("Ridge_S1", [(22.4, 29.2), (24.0, 27.6), (27.2, 27.6), (28.8, 28.4), (31.4, 28.4), (31.4, 33.6),
                           (28.8, 33.6), (27.2, 34.6), (24.0, 34.6), (22.4, 33.0)], top=S1, bottom=MEADOW - 0.3)
    m.ramp("Slope_S2", (27.6, 31.0, S1), (31.0, 31.0, S3), 3.0, top_mat=ROAD)
    m.terrace("Summit_S3", [(29.6, 24.4), (32.0, 23.2), (36.0, 22.8), (38.8, 23.4), (38.8, 38.6), (29.6, 38.6),
                            (29.6, 33.1), (30.7, 33.1), (30.7, 28.9), (29.6, 28.9)],
              top=S3, bottom=-0.5)

    # ================= climbables (located on the real, wobbled faces) =================
    R1X, R2X = 36.6, 36.0  # rope pitches near the east end of the E1 / E2 south faces (staggered on screen)
    e = _edge(m, R1X, 14.4, 0, -1)
    r1y = (e[1] - 0.3) if e else 11.5
    m.ladder("Rope_G5_E1", R1X, r1y, 0.0, E1, facing=90, kind="rope")
    e = _edge(m, R2X, 19.0, 0, -1)
    r2y = (e[1] - 0.3) if e else 15.9
    m.ladder("Rope_E1_E2", R2X, r2y, E1, E2, facing=90, kind="rope")
    # a pennant pole with a spare coil beside each rope top, so the two pitches read from afar
    m.place("X30000_ClimbFlag", R1X + 1.0, r1y + 1.6, rot=55)
    m.place("X30000_ClimbFlag", R2X + 1.0, r2y + 1.3, rot=55)
    e = _edge(m, 8.8, 27.8, 0, -1)
    l1y = (e[1] - 0.15) if e else 25.2
    m.ladder("Ladder_M3_U1", 8.8, l1y, M3, U1, facing=90)
    e = _edge(m, 3.6, 24.0, 0, 1)
    lry = (e[1] + 0.25) if e else 27.8
    # recovery ladder: a misstep off the stepping stones lands in the meadow; climb back up to M3
    m.ladder("Ladder_Meadow_M3", 3.6, lry, MEADOW, M3, facing=270)

    # the plank walks over the gaps between the hop ledges (E2 -> E3 -> M1)
    _plank_walk(m, "E2_E3", (33.1, 19.9, E2 + 0.04), (30.3, 19.9, E3 + 0.04))
    _plank_walk(m, "E3_M1", (25.2, 21.3, E3 + 0.04), (22.6, 21.3, M1 + 0.04))

    # ================= the painted climb trail =================
    # (Main road material all the way; 3.6 m on the valley floor and the summit, narrow on the shelves)
    m.path("Main_Road", [(1.0, 12.0), (5.0, 9.0), (9.0, 5.6), (12.0, 4.4), (18.0, 4.0), (24.0, 4.2), (27.0, 5.2),
                         (31.0, 8.0), (34.6, 9.6), (R1X, r1y - 0.4)], **MAIN_ROAD)
    m.path("Trail_E1", [(R1X, r1y + 0.9), (36.5, 14.0), (R2X, r2y - 0.35)], mat=ROAD, width=2.0)
    m.path("Trail_E2", [(R2X, r2y + 0.9), (35.4, 18.8), (34.2, 19.6), (33.0, 19.9)], mat=ROAD, width=2.2)
    m.path("Trail_E3", [(30.6, 19.9), (28.6, 20.4), (26.4, 21.0), (25.0, 21.3)], mat=ROAD, width=2.2)
    # (the slopes' own blend ribbons carry the trail across M1 and onto M3 / the summit: the painted
    # trail picks up where they end instead of overlapping them, so the edges stay clean)
    m.path("Trail_M3", [(15.4, 21.5), (14.0, 21.8), (11.6, 22.8), (9.4, 23.8), (8.8, l1y - 0.4)], mat=ROAD,
           width=2.4)
    m.path("Trail_U4", [(17.6, 31.4), (19.5, 31.4), (22.0, 31.2)], mat=ROAD, width=2.2)
    m.path("Trail_S1", [(22.8, 31.2), (25.5, 31.0), (26.5, 31.0)], mat=ROAD, width=2.2)
    m.path("Summit_Path", [(32.5, 30.9), (34.0, 30.6), (36.6, 30.0)], mat=ROAD, width=3.2)
    m.path("WestLadder_Path", [(1.4, 11.8), (3.4, 12.6)], width=1.8)

    # ================= landmarks =================
    # the yellow mushroom house on the hill (decorative door: no portal in the data)
    m.place("X30000_HouseYellowBrim", 20.6, 9.0, rot=40, scale=1.2)  # 1.2 for the island read
    m.place("X30000_PaleStalks", 14.4, 8.8, rot=0, scale=1.4)
    m.place("Sack", 16.9, 6.4, rot=20)
    m.place("Sack", 16.2, 5.7, rot=-30, scale=0.9)
    m.place("Bush_B", 24.8, 10.8, rot=30)
    m.place("Bush_C", 27.6, 11.6, rot=0)  # olive bush on the east shoulder
    # the rainbow mushroom fountain at the foot of the east cliff + ivy signposts
    m.place("X30000_RainbowFountain", 32.6, 4.8, rot=55)
    m.place("Ivy_Sign", 7.4, 10.6, rot=0)
    m.place("Ivy_Sign", 34.0, 11.3, rot=20)  # beside (not in front of) the first rope: "up"
    m.place("X30000_LogBench", 12.6, 19.6, rot=0)
    m.place("Ivy_Sign_3Way", 25.4, 33.0, rot=0)
    # arrow signs at every switchback: E2 -> west, M3 west end -> the U1 ladder, U4 -> east
    m.place("Sign_Arrow", 36.2, 19.6, rot=180)
    m.place("Sign_Arrow", 10.8, 25.4, rot=118)
    m.place("Sign_Arrow", 19.4, 33.4, rot=0)
    # the summit: Peter guards the exit; a big bush behind him, pale stalks between him and out00
    m.npc("Peter", 33.0, 30.6, rot=40)
    m.place("Bush_B", 32.0, 33.8, rot=20, scale=1.25)
    m.place("X30000_PaleStalks", 35.4, 33.2, rot=180, scale=1.4)
    m.place("Bush_C", 37.8, 33.8, rot=10, scale=1.2)

    # ================= dressing =================
    # valley floor
    for (x, y, r) in ((2.8, 7.2, 0), (6.2, 3.4, 40), (9.6, 1.8, 10), (29.8, 2.2, 0), (36.4, 2.0, 60)):
        m.place("Flower_Bed_Large", x, y, rot=r, scale=0.7)
    for i, (x, y) in enumerate([(0.6, 4.0), (0.6, 8.6), (37.6, 6.8), (30.4, 11.4), (11.4, 14.4), (26.0, 14.6)]):
        m.place(["Bush_A", "Bush_C", "Bush_B"][i % 3], x, y, rot=i * 40)
    m.place("Rock_B", 9.6, 14.6, rot=20, scale=0.9)
    m.place("Rock_A", 22.0, 14.8, rot=60)
    m.place("Rock_A", 38.0, 11.6, rot=10, scale=0.8)
    m.place("Rock_B", 32.4, 11.6, rot=40, scale=0.7)
    m.place("Mushroom_Cluster_A", 18.4, 14.6, rot=-10)
    m.place("Mushroom_Cluster_A", 32.9, 11.5, rot=20)  # "climb here" at the sign foot, clear of the rope
    m.place("Mushroom_Red_S", 29.6, 13.8, rot=0)
    m.place("Butterfly", 31.0, 6.0)
    m.place("Butterfly", 4.0, 6.0)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 38, 15.5), 22, seed=1,
              min_dist=1.8, avoid=[geo.rect(0, 10, 4, 14), (20.6, 8.6, 3.8), (32.6, 4.8, 2.0),
                                   geo.rect(9, 3, 28, 5.2), geo.rect(28, 6, 37, 12.6)])
    # the rock shelves and hop ledges: tufts, flowers, little mushrooms so each landing reads as a place
    for (a, x, y, r) in (("Flower_Patch_A", 34.6, r2y - 0.5, 0), ("Grass_Tuft_A", 37.4, 14.2, 0),
                         ("Rock_A", 37.8, 15.4, 0), ("Flower_Patch_B", 33.2, 13.4, 0),
                         ("Mushroom_Orange_S", 37.4, 21.6, 0), ("Bush_A", 37.6, 18.2, 20),
                         ("Grass_Tuft_A", 33.4, 22.2, 0), ("Flower_Patch_A", 36.8, 17.2, 0),
                         ("Flower_Patch_B", 27.4, 18.2, 30), ("Mushroom_Red_S", 25.8, 24.0, 0),
                         ("Rock_C", 28.4, 23.8, 0), ("Grass_Tuft_A", 29.8, 22.4, 0), ("Bush_C", 26.0, 23.6, 0),
                         ("Flower_Patch_A", 21.8, 23.6, 60), ("Rock_C", 19.4, 25.0, 0), ("Bush_A", 22.0, 18.4, 50),
                         ("Mushroom_Yellow_S", 19.8, 18.4, 0), ("Mushroom_Yellow_S", 19.4, 19.0, 40),
                         ("Flower_Patch_B", 6.0, 19.6, 0), ("Mushroom_Cluster_A", 1.8, 25.8, 40),
                         ("Grass_Tuft_A", 14.0, 26.0, 0), ("Bush_B", 13.8, 24.2, 0), ("Bush_C", 16.6, 18.4, 0),
                         ("Butterfly", 22.0, 20.0, 0), ("Butterfly", 34.0, 27.0, 0), ("Butterfly_Yellow", 35.6, 15.0, 0)):
        m.place(a, x, y, rot=r)
    # vines and stones on the camera-facing faces (south -y, east +x)
    for (x, y) in ((34.4, 14.8), (33.2, 14.8), (37.6, 18.0), (34.0, 19.0), (27.0, 20.0), (29.6, 20.0), (20.4, 20.0),
                   (11.0, 20.0), (5.0, 20.0), (1.8, 20.0), (8.2, 20.0), (13.4, 20.0), (16.6, 20.0)):
        _vine(m, x, y, 0, -1, 0)
    for (x, y) in ((36.0, 14.0), (36.0, 19.0), (28.0, 21.0), (22.0, 22.0)):
        _vine(m, x, y, 1, 0, 90)
    for (x, y, f, s) in ((10.0, 20.0, 0.62, 0.9), (14.6, 20.0, 0.3, 0.9), (2.6, 20.0, 0.5, 1.0), (21.0, 20.0, 0.45, 0.9),
                         (19.0, 20.0, 0.75, 0.8), (26.6, 20.0, 0.3, 0.9), (29.0, 20.0, 0.65, 0.8)):
        _stone(m, x, y, 0, -1, f, 0, s)
    for (x, y, f) in ((26.0, 21.0, 0.5), (22.0, 23.0, 0.35)):
        _stone(m, x, y, 1, 0, f, 90)
    # the summit's south face above E2 (seen behind the E2 shelf)
    for (x, f, s) in ((33.6, 0.45, 1.0), (36.6, 0.7, 0.9)):
        e = _edge(m, x, 27.0, 0, -1, drop=1.5)
        if e and e[3] is not None:
            m.place("Rock_Cliff_Stone", e[0], e[1] + 0.22, z=e[3] + (e[2] - e[3]) * f, rot=0, scale=s)
    # the summit's east face (the most camera-facing surface): stones and vines, kept clear of
    # the band y ~28.5-35.5 where the stairway trail to 40000 leaves out00 eastward
    for (y, frac, s) in ((24.6, 0.72, 1.1), (25.9, 0.3, 1.3), (27.4, 0.55, 1.0), (28.0, 0.18, 0.9), (36.4, 0.37, 1.2),
                         (37.2, 0.78, 1.0), (38.1, 0.55, 0.9)):
        fx = _face_x(m, y, S3)
        if fx is not None:
            m.place("Rock_Cliff_Stone", fx + 0.1, y, z=S3 * frac, rot=90, scale=s)
    for y in (24.4, 25.6, 27.0, 36.2, 37.6):
        fx = _face_x(m, y, S3)
        if fx is not None:
            m.place("Vine_Hanging_A", fx + 0.3, y, z=S3 - 0.15, rot=90)
    # the dead-end islet stair: a small reward on W3 and a dressed wall above it
    m.place("Mushroom_Cluster_A", 8.7, 16.9, rot=30)  # on the W3 rim, clear of the route end
    m.place("Butterfly", 7.0, 15.4)
    _stone(m, 6.0, 19.0, 0, -1, 0.8, 0, 1.0)
    _vine(m, 8.6, 19.0, 0, -1, 0)
    # back of the high terrace and massif: trees frame the sky line
    for i, (x, y, s) in enumerate([(1.6, 23.6, 0.9), (2.2, 32.6, 1.0), (6.4, 36.8, 0.85), (11.0, 35.6, 0.9),
                                   (19.4, 36.6, 0.9), (26.6, 37.0, 0.95), (31.8, 37.2, 0.85), (37.4, 37.4, 0.8)]):
        m.place(["Tree_Round_A", "Tree_Round_B", "Tree_Round_C"][i % 3], x, y, rot=i * 53, scale=s)
    for i, (x, y) in enumerate([(0.8, 19.6), (4.6, 21.0), (14.6, 34.6), (23.0, 36.2), (29.0, 27.2), (38.0, 27.6)]):
        m.place(["Bush_A", "Bush_B", "Bush_C"][i % 3], x, y, rot=i * 41)
    m.place("Bush_C", 21.4, 33.6, rot=0)  # dark bush on U4
    m.place("Grass_Tuft_A", 18.6, 29.0)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A"], geo.rect(0, 17.5, 30, 38), 16, seed=2, min_dist=1.8,
              avoid=[geo.rect(15, 19.4, 23, 23.4), geo.rect(6, 21, 11, 26), (8.8, 27.8, 2.5), (11.8, 29.6, 2.8),
                     (14.8, 31.2, 2.8), geo.rect(16, 28, 29.5, 35.2), (12.6, 19.6, 1.6),
                     geo.rect(23, 18.6, 34, 22.6), (3.6, 28.8, 1.8), (3.6, 26.2, 1.4)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_B"], geo.rect(30, 24, 38, 38), 6, seed=3, min_dist=1.8,
              avoid=[geo.rect(30, 28.6, 38, 32.4)])

    # ================= gameplay =================
    m.edge_portal("in00")  # a two-way portal back to 20000 out00 in MeowDB (v8 had an arrival point only)
    m.edge_portal("out00")  # one-way to 40000: the trail ends in a drop-down ledge (no portal back)
    m.player(27.5, 20.2, rot=55)  # on the E3 ledge just off the trail, facing the camera
    # Todd (MeowDB 000000030 at x -21, y 202: the west valley floor G1, just east of the arrival) by the ivy signpost,
    # 1.6 m off the Main road
    m.npc("Todd", 6.8, 9.6, rot=30)
    # player_spawns[0] (MeowDB sp x -77, y 122: on G1 between in00 and Todd), on the Main road facing down it
    m.player_spawn(5.0, 10.2, rot=50, note="west valley floor between in00 and Todd")
    # MeowDB: 6 Tutorial Jr. Sentinel spawn points (x 1360 on the east valley floor G5; x 475 / 690 on the house
    # hilltop G3; x 192 / 425 on the M3 high terrace, x 763 on M1). No kit proxy exists for the species, so these are
    # bare regions (no representative proxies)
    sentinel = ("Tutorial Jr. Sentinel",)
    m.spawn_region("ValleyEast_G5", geo.rect(29.5, 1.0, 37.5, 11.0), species=sentinel, z_band=(-0.2, 0.3),
                   tiers=("G5",))
    m.spawn_region("Hilltop_G3", geo.rect(12.8, 2.4, 25.2, 6.0), species=sentinel, z_band=(G3 - 0.2, G3 + 0.2),
                   tiers=("G3",))
    m.spawn_region("HighTerrace_M3", geo.rect(1.0, 17.6, 16.8, 26.0), species=sentinel, z_band=(M3 - 0.2, M3 + 0.2),
                   tiers=("M3",))
    m.spawn_region("Ledge_M1", geo.rect(18.6, 17.6, 23.0, 25.6), species=sentinel, z_band=(M1 - 0.2, M1 + 0.2),
                   tiers=("M1",))
    # the whole climb as ONE route: valley -> rope -> E1 -> rope -> E2 -> planks -> E3 -> planks -> M1 ->
    # M2 slope -> M3 -> ladder -> U1 -> mushroom caps -> U4 -> S1 -> S2 slope -> summit -> out00
    m.route("Main", [(1.0, 12.0), (5.0, 9.0), (9.0, 5.6), (12.0, 4.4), (18.0, 4.0), (24.0, 4.2), (27.0, 5.2),
                     (31.0, 8.0), (34.6, 9.6), (R1X, r1y - 0.5),
                     (R1X, r1y + 1.2), (36.5, 14.0), (R2X, r2y - 0.5),
                     (R2X, r2y + 1.2), (35.4, 18.8), (34.2, 19.6), (33.4, 19.9), (30.0, 19.9), (28.6, 20.4), (26.4, 21.0),
                     (25.4, 21.3), (22.4, 21.3), (21.6, 21.4), (17.2, 21.4), (14.0, 21.8), (11.6, 22.8),
                     (9.4, 23.8), (8.8, l1y - 0.6),
                     (8.8, l1y + 1.2), (9.6, 27.8), (11.8, 29.6), (13.4, 30.4), (14.8, 31.2), (16.8, 31.4),
                     (19.5, 31.4), (22.0, 31.2), (25.5, 31.0), (27.8, 31.0), (30.8, 31.0), (33.0, 30.6),
                     (37.0, 30.0)])
    # the dead-end islet stair: valley -> ladder -> W1 -> W2 -> W3
    m.route("WestIslets", [(1.6, 11.6), (3.4, 12.4), (3.4, 14.6), (3.6, 15.4), (5.4, 15.6), (7.0, 16.0)])
    # back-meadow recovery: meadow -> ladder -> M3
    m.route("MeadowRecovery", [(3.6, 31.0), (3.6, lry + 0.6), (3.6, lry - 1.2), (5.0, 23.0), (8.8, l1y - 0.6)])
