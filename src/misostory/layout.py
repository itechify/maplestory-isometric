"""World layout: where every classic map sits on the island.

Authoritative inputs:
  * docs/topology.json (portal connections, from raw GMS v8 WZ data),
  * the classic in-game world map WorldMap0 (relative positions / bearings),
  * per-map foothold extents (docs/research/maps/<id>.struct.json) for footprint size.

Footprint sizing rule (MapleStory px -> meters): length L ~= 0.02 * width_px, depth
D ~= 18 + 0.015 * height_px, towns enlarged so they read as towns in 3D.

Each map has a local frame (x = original left->right progression, y = depth/back,
z = height above base) and is placed with ``yaw`` (deg) and ``origin`` (world).
``anchors`` are the local positions of the edge portals: map authors MUST put the
named portal (and walkable ground) at that exact local spot. Origins are solved by
chaining anchors along ``LINKS``: the child's anchor is placed ``gap`` meters along
``bearing`` (world degrees, 0 = east, -90 = south) from the parent's anchor.
"""

import math

# World bearings used by the classic world map: Maple Road runs south-east (screen
# right in our camera), Rainbow Street east, the far fields south-south-east.
MAPS = {
    # ------------------------------------------------------------ Maple Road
    0: dict(slug="WestEntranceMushroomTown_0", name="West Entrance to Mushroom Town", street="Maple Road",
            kind="town", L=32, D=28, yaw=-20, z=14.0,
            anchors={"out00": (31.0, 10.0, 0.0)}),
    10000: dict(slug="MushroomTown_10000", name="Mushroom Town", street="Maple Road", kind="town",
                L=42, D=36, yaw=-30, z=14.0,
                anchors={"in00": (1.0, 10.0, 0.0), "out00": (41.0, 14.0, 0.0)}),
    20000: dict(slug="MushroomTown_20000", name="Mushroom Town", street="Maple Road", kind="town",
                L=42, D=36, yaw=-45, z=14.0,
                anchors={"in00": (1.0, 14.0, 0.0), "out00": (41.0, 18.0, 2.0)}),
    30000: dict(slug="EastEntranceMushroomTown_30000", name="East Entrance to Mushroom Town", street="Maple Road",
                kind="town", L=38, D=38, yaw=-55, z=15.0,
                anchors={"in00": (1.0, 12.0, 0.0), "out00": (37.0, 30.0, 7.0)}),
    40000: dict(slug="SnailHuntingGround1_40000", name="Snail Hunting Ground I", street="Maple Road", kind="hunting",
                L=64, D=40, yaw=-45, z=11.0,
                anchors={"in00": (1.0, 10.0, 0.0), "east00": (63.0, 12.0, 0.0)}),
    40001: dict(slug="SnailHuntingGround2_40001", name="Snail Hunting Ground II", street="Maple Road", kind="hunting",
                L=64, D=44, yaw=-58, z=8.0,
                anchors={"west00": (1.0, 12.0, 0.0), "east00": (63.0, 12.0, 0.0)}),
    40002: dict(slug="SnailHuntingGround3_40002", name="Snail Hunting Ground III", street="Maple Road",
                kind="hunting", L=64, D=46, yaw=-38, z=5.0,
                anchors={"west00": (1.0, 10.0, 0.0), "east00": (63.0, 36.0, 8.0)}),
    50000: dict(slug="ASplitRoad_50000", name="A Split Road", street="Maple Road", kind="field",
                L=76, D=32, yaw=-22, z=4.0,
                anchors={"west00": (1.0, 14.0, 0.0), "east00": (75.0, 25.0, 3.0), "east01": (75.0, 6.0, 0.0)}),
    60000: dict(slug="Southperry_60000", name="Southperry", street="Maple Road", kind="town",
                L=82, D=46, yaw=-22, z=1.0,
                  anchors={"west00": (4.5, 45.0, 0.0)}),  # the Split Road arrives from the north (back)
    60001: dict(slug="SouthperryArmorStore_60001", name="Southperry Armor Store", street="Maple Road",
                kind="interior", L=16, D=12, yaw=-45, z=0.0, anchors={}),
    20001: dict(slug="MushroomTownTownstreet_20001", name="Mushroom Town Townstreet", street="Maple Road",
                kind="interior", L=16, D=12, yaw=-45, z=0.0, anchors={}),
    # ------------------------------------------------------------ Rainbow Street
    1000000: dict(slug="FieldWestOfAmherst_1000000", name="The Field West of Amherst", street="Rainbow Street",
                  kind="hunting", L=80, D=48, yaw=8, z=5.0,
                  anchors={"west00": (1.0, 12.0, 0.0), "east00": (79.0, 12.0, 0.0),
                           "in00": (4.0, 47.0, 4.0), "in04": (14.0, 47.0, 6.0), "in05": (56.0, 47.0, 7.0),
                           "in01": (66.0, 47.0, 6.0), "in02": (62.0, 1.0, 0.0), "in03": (78.0, 1.0, 0.0)}),
    1000001: dict(slug="InASmallForest_1000001", name="In a Small Forest", street="Rainbow Street", kind="hunting",
                  L=38, D=34, yaw=10, z=8.0, anchors={"out00": (34.0, 1.0, 2.0)}),
    1000002: dict(slug="DangerousForest_1000002", name="Dangerous Forest", street="Rainbow Street", kind="hunting",
                  L=40, D=36, yaw=5, z=13.0, anchors={"out01": (4.0, 1.0, 0.0)}),
    1000003: dict(slug="MushroomGarden_1000003", name="Mushroom Garden", street="Rainbow Street", kind="hunting",
                  L=36, D=30, yaw=-10, z=2.0, anchors={"out00": (6.0, 29.0, 2.0)}),
    1000004: dict(slug="SnailGarden_1000004", name="Snail Garden", street="Rainbow Street", kind="hunting",
                  L=40, D=30, yaw=-10, z=2.0, anchors={"out00": (14.0, 29.0, 2.0)}),
    1000005: dict(slug="HuntingGroundMidForest1_1000005", name="Hunting Ground Middle of the Forest I",
                  street="Rainbow Street", kind="hunting", L=38, D=42, yaw=5, z=12.0,
                  anchors={"out00": (8.0, 1.0, 0.0)}),
    1000006: dict(slug="HuntingGroundMidForest2_1000006", name="Hunting Ground Middle of the Forest II",
                  street="Rainbow Street", kind="hunting", L=42, D=40, yaw=0, z=16.0,
                  anchors={"out00": (14.0, 1.0, 7.0)}),
    1010000: dict(slug="Amherst_1010000", name="Amherst", street="Rainbow Street", kind="town",
                  L=76, D=40, yaw=0, z=6.0,
                  anchors={"west00": (1.0, 12.0, 0.0), "east00": (75.0, 12.0, 0.0), "in01": (64.0, 39.0, 2.0)}),
    1010001: dict(slug="AmherstWeaponStore_1010001", name="Amherst Weapon Store", street="Rainbow Street",
                  kind="interior", L=16, D=12, yaw=-45, z=0.0, anchors={}),
    1010002: dict(slug="AmherstTownstreet_1010002", name="Amherst Townstreet", street="Rainbow Street",
                  kind="townstreet", L=24, D=22, yaw=0, z=8.0,
                  anchors={"out00": (14.0, 1.0, 0.0), "west00": (1.0, 12.0, 0.0)}),
    1010003: dict(slug="AmherstDepartmentStore_1010003", name="Amherst Department Store", street="Rainbow Street",
                  kind="interior", L=16, D=12, yaw=-45, z=0.0, anchors={}),
    1010004: dict(slug="SnailFieldOfFlowers_1010004", name="Snail Field of Flowers", street="Rainbow Street",
                  kind="hunting", L=38, D=36, yaw=0, z=9.5, anchors={"east00": (37.0, 31.5, 10.6)}),  # arrive on the rim road
    1020000: dict(slug="FieldEastOfAmherst_1020000", name="The Field East of Amherst", street="Rainbow Street",
                  kind="hunting", L=56, D=36, yaw=-62, z=4.0,
                  anchors={"west00": (1.0, 14.0, 0.0), "in00": (42.0, 35.0, 4.0)}),
    1020001: dict(slug="TomatoField_1020001", name="Tomato Field", street="Rainbow Street", kind="hunting",
                  L=60, D=30, yaw=-20, z=2.0, anchors={"out00": (1.0, 12.0, 0.0)}),
}

ROOT_MAP = 0
ROOT_ORIGIN = (0.0, 0.0)

# Yaws and bearings above are authored in the classic world map frame (north = up).
# The world is that frame rotated by GEO_ROT so the isometric overview (camera looking
# toward world +X+Y) shows the island oriented like the in-game world map.
GEO_ROT = -45.0


def world_yaw(mid):
    return MAPS[mid]["yaw"] + GEO_ROT

# (child, child_anchor, parent, parent_anchor, gap_m, bearing_deg)
LINKS = [
    (10000, "in00", 0, "out00", 12.0, -22),
    (20000, "in00", 10000, "out00", 16.0, -36),
    (30000, "in00", 20000, "out00", 12.0, -50),
    (40000, "in00", 30000, "out00", 30.0, -50),  # long stair-ramp down from the East Entrance summit
    (40001, "west00", 40000, "east00", 14.0, -52),
    (40002, "west00", 40001, "east00", 20.0, -45),
    (50000, "west00", 40002, "east00", 32.0, -30),  # descent from the SHG III heights to the fork
    (60000, "west00", 50000, "east01", 30.0, -125),
    (1000000, "west00", 50000, "east00", 14.0, 10),
    (1000001, "out00", 1000000, "in00", 20.0, 104),
    (1000005, "out00", 1000000, "in04", 12.0, 84),  # NNE of the field: no clash with 1000001 (was a 58 m runway)
    (1000002, "out01", 1000000, "in01", 14.0, 92),
    (1000006, "out00", 1000000, "in05", 58.0, 88),  # behind the Dangerous Forest and 1000005
    (1000003, "out00", 1000000, "in02", 26.0, -80),
    (1000004, "out00", 1000000, "in03", 38.0, -18),
    (1010000, "west00", 1000000, "east00", 14.0, 0),
    (1010002, "out00", 1010000, "in01", 5.0, 90),  # Townstreet's orange house is up the lane behind Amherst
    (1010004, "east00", 1010002, "west00", 39.0, 98),  # clear of Townstreet's west exit; 40/100 grew to 76 m
    (1020000, "west00", 1010000, "east00", 18.0, -45),
    (1020001, "out00", 1020000, "in00", 22.0, 20),
]

# Interiors live on a remote "interior stage" (outside every island camera frame).
INTERIOR_STAGE = {  # 200 m apart so no room shows up in another room's camera frame
    20001: (2400.0, 0.0),
    60001: (2600.0, 0.0),
    1010001: (2800.0, 0.0),
    1010003: (3000.0, 0.0),
}

# Door portals (map -> portal -> interior) whose position the map author chooses.
DOOR_LINKS = [
    (20000, "in01", 20001, "out00"),
    (60000, "in00", 60001, "out00"),
    (1010000, "in00", 1010001, "out00"),
    (1010000, "in02", 1010003, "out00"),
]


def _rot(yaw, x, y):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return (x * c - y * s, x * s + y * c)


AUTO_GAP_MARGIN = 1.5
GAPS = {}
LAYOUT_WARN = {}  # (child, portal) -> {"authored", "resolved", "clashed_with"} for links resolve() had to lengthen


def resolve():
    """Compute world origins for every map (dict id -> (ox, oy, oz))."""
    origins = {ROOT_MAP: (ROOT_ORIGIN[0], ROOT_ORIGIN[1], MAPS[ROOT_MAP]["z"])}
    pending = list(LINKS)
    guard = 0
    while pending and guard < 100:
        guard += 1
        for link in list(pending):
            child, ca, parent, pa, gap, bearing = link
            if parent not in origins:
                continue
            pm = MAPS[parent]
            cm = MAPS[child]
            po = origins[parent]
            px, py, _pz = pm["anchors"][pa]
            wx, wy = _rot(world_yaw(parent), px, py)
            pwx, pwy = po[0] + wx, po[1] + wy
            wb = math.radians(bearing + GEO_ROT)
            cx, cy, _cz = cm["anchors"][ca]
            rx, ry = _rot(world_yaw(child), cx, cy)
            # lengthen the connecting trail until the child clears every placed map
            g = gap
            clashed = set()
            while True:
                tx = pwx + g * math.cos(wb)
                ty = pwy + g * math.sin(wb)
                origins[child] = (tx - rx, ty - ry, cm["z"])
                fp = footprint_world(child, origins, AUTO_GAP_MARGIN)
                clash = [m for m in origins if m != child and MAPS[m]["kind"] != "interior" and
                         _sat_overlap(fp, footprint_world(m, origins, AUTO_GAP_MARGIN))]
                if not clash or g > gap + 60:
                    break
                clashed.update(clash)
                g += 2.0
            GAPS[(child, ca)] = g
            if g > gap * 1.5 or g > gap + 10:
                LAYOUT_WARN[(child, ca)] = {"authored": gap, "resolved": g, "clashed_with": sorted(clashed)}
            pending.remove(link)
    for mid, (sx, sy) in INTERIOR_STAGE.items():
        origins[mid] = (sx, sy, MAPS[mid]["z"])
    missing = [m for m in MAPS if m not in origins]
    if missing:
        raise RuntimeError(f"Layout could not place maps: {missing}")
    return origins


def anchor_normal_world(mid, name):
    """Outward unit normal (world xy) of the footprint edge an anchor sits on."""
    m = MAPS[mid]
    x, y, _z = m["anchors"][name]
    L, D = m["L"], m["D"]
    d = {(-1.0, 0.0): x, (1.0, 0.0): L - x, (0.0, -1.0): y, (0.0, 1.0): D - y}
    nx, ny = min(d, key=d.get)
    return _rot(world_yaw(mid), nx, ny)


def anchor_world(mid, name, origins=None):
    origins = origins or resolve()
    m = MAPS[mid]
    o = origins[mid]
    x, y, z = m["anchors"][name]
    wx, wy = _rot(world_yaw(mid), x, y)
    return (o[0] + wx, o[1] + wy, o[2] + z)


def footprint_world(mid, origins=None, margin=0.0):
    origins = origins or resolve()
    m = MAPS[mid]
    o = origins[mid]
    pts = [(-margin, -margin), (m["L"] + margin, -margin), (m["L"] + margin, m["D"] + margin),
           (-margin, m["D"] + margin)]
    out = []
    for x, y in pts:
        wx, wy = _rot(world_yaw(mid), x, y)
        out.append((o[0] + wx, o[1] + wy))
    return out


def _sat_overlap(a, b):
    for poly in (a, b):
        n = len(poly)
        for i in range(n):
            x1, y1 = poly[i]
            x2, y2 = poly[(i + 1) % n]
            ax, ay = -(y2 - y1), x2 - x1
            pa = [ax * x + ay * y for x, y in a]
            pb = [ax * x + ay * y for x, y in b]
            if max(pa) < min(pb) or max(pb) < min(pa):
                return False
    return True


def overlaps(margin=1.5):
    origins = resolve()
    ids = [m for m in MAPS if MAPS[m]["kind"] != "interior"]
    out = []
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            if _sat_overlap(footprint_world(a, origins, margin), footprint_world(b, origins, margin)):
                out.append((a, b))
    return out


def exterior_ids():
    return [m for m in MAPS if MAPS[m]["kind"] != "interior"]


if __name__ == "__main__":
    o = resolve()
    for k, v in o.items():
        print(k, MAPS[k]["slug"], [round(c, 1) for c in v])
    print("OVERLAPS:", overlaps())


# ---------------------------------------------------------------- scenery (geo frame)
# Inland lake fed by a waterfall (world map: lake NE of the valley road, walled off
# from the road by ridges). Coordinates in the world-map (geo) frame, meters.
LAKE = dict(center=(330.0, -128.0), rx=48.0, ry=26.0, rot=-25.0, z=4.0)
WATERFALL = dict(top=(318.0, -88.0), height=26.0, width=10.0)
# Authored mountain ridges (world-map frame). Peaks are placed along these first.
RIDGES = [
    # the cloud-ringed peaks behind the Mushroom Town pocket (north-west rim)
    # (30-45 m beyond the back edges of 0/10000/20000 and wrapping round the west of map 0: a peak "pocket")
    dict(pts=[(-46, -6), (-40, 28), (-8, 60), (36, 66), (92, 46), (148, 6), (188, -38)], spacing=20,
         radius=(14, 22), height=(1.7, 2.3), halo=True, pocket=True),
    # north-east massif beyond the lake and waterfall
    dict(pts=[(352, -78), (392, -86), (430, -96), (452, -76)], spacing=20, radius=(16, 26), height=(1.6, 2.3),
         halo=True),
    # low ridge between the snail valley and the lake (kept low so it never hides the valley)
    dict(pts=[(268, -112), (286, -150), (306, -182)], spacing=16, radius=(9, 13), height=(0.8, 1.1)),
    # peaks north and north-east of Amherst's plaza (world map)
    dict(pts=[(600, -140), (636, -170), (664, -205), (690, -236)], spacing=19, radius=(14, 22), height=(1.6, 2.2),
         halo=True),
    # south-west rim: only low rounded hills
    dict(pts=[(150, -150), (215, -212), (285, -268), (350, -330)], spacing=26, radius=(9, 13), height=(0.7, 1.0),
         asset="Mountain_Hill"),
]
ISLAND_MARGIN = 34.0
# Maps that sit on the island rim use a smaller margin so their outer edge IS the cliff
# (Southperry's quay drops straight into the sky, West Entrance sits on the NW tip).
RIM_MARGIN = {60000: 1.0, 0: 9.0, 1020000: 12.0, 1020001: 9.0, 1000003: 16.0, 1000004: 16.0}
SEA_Z = -260.0
# Trails on the classic main roads get the pale 'main road' surface (Maple Road and Rainbow Street).
MAIN_ROAD = {
    (0, "out00", 10000, "in00"), (10000, "out00", 20000, "in00"), (20000, "out00", 30000, "in00"),
    (30000, "out00", 40000, "in00"), (40000, "east00", 40001, "west00"), (40001, "east00", 40002, "west00"),
    (40002, "east00", 50000, "west00"), (50000, "east01", 60000, "west00"), (50000, "east00", 1000000, "west00"),
    (1000000, "east00", 1010000, "west00"), (1010000, "east00", 1020000, "west00"),
}
ONE_WAY = {(10000, "in00"), (20000, "in00"), (30000, "in00"), (40000, "in00")}
# Maps whose front (local -y) edge IS the island cliff: no plinth ring and no rim wobble there.
RIM_EDGE = {60000: "front"}
# Classic hidden portals: the trail is a hedge-screened grass lane (no road, rails or signposts).
HIDDEN_TRAILS = {(1020000, "in00", 1020001, "out00")}
# Arrivals onto a floating hub: the causeway stops this many m short and a plank bridge spans the rest.
BRIDGE_END = {(1000006, "out00"): 8.0}


def geo_to_world(x, y):
    c, s = math.cos(math.radians(GEO_ROT)), math.sin(math.radians(GEO_ROT))
    return (x * c - y * s, x * s + y * c)


def world_to_geo(x, y):
    c, s = math.cos(math.radians(-GEO_ROT)), math.sin(math.radians(-GEO_ROT))
    return (x * c - y * s, x * s + y * c)
