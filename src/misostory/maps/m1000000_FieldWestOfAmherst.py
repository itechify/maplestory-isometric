"""The Field West of Amherst (1000000) - "the six-door hillside hub".

Classic (GMS v8) structure, from docs/research/maps/1000000_FieldWestOfAmherst_1000000.md:
  ground road W->E: west-gate plateau G1 (west00), shallow swale G2, the rope yard G3 (4 ropes
  up to stepping floaters P05/P07/P10), two steps down into the sunken Hollow G6, a sheer 3-step
  cliff up to G7 (ladder to P08), three steps down to the East Gate G10 ("Amherst ->" sign,
  sunflowers, east00). Above it: the long central plateau P11a/P11b (barrels, red toadstools),
  the V-fork of stepping stones rising off its back, the west terraces (P17/P20-P25, doors in00
  and in04 with danger signs), the summit grove P36 (Orange Mushrooms), the east shelf P26a-c
  climbing to the Dangerous Forest door in01 and the east balcony P12 with giant pale
  stalk-mushrooms. Six side doors in total; no NPCs in v8.

3D translation: one 60 px tier = 0.4 m, so every classic single step is a walkable 0.4 m ledge
and the road keeps its exact undulation (1.2 / 0.8 / 1.2 / 0.8 / 0.4 / 0 / cliff / 1.2 / 0.8 /
0.4 / 0). Bands climb away from the camera: road in front, the plateau behind the Hollow, the
west terraces and the V-fork above it, then a summit "skirt" ledge and the summit at the back.
Every side-map entrance is a barrel door with the classic danger-sign variant beside it: the two
front-edge doors (in02, in03) are closed barrel doors in grassy mounds; the four back-edge doors
are open barrel gates between two mounds, so the world trail to the side map runs straight through
the door (in02 sits in a pocket notched into the G7 cliff block). Classic ropes and
ladders are kept as climbing shortcuts; every door also has a walkable stair/step route.
The layout moved some doors relative to the classic x positions: in05 now sits on the summit's
east shoulder, in02 (Mushroom Garden) in the Hollow's south-east corner at the foot of the G7
cliff, and in03 (Snail Garden) at the East Gate.
"""

import math

from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset, nature
from misostory.kit.interior import sign_text
from misostory.mapkit import MAIN_ROAD

MAP_ID = 1000000
GAMEPLAY_FOCUS = (47.0, 18.0)
GAMEPLAY_SCALE = 46.0

# heights (local m). 1 classic 60 px tier = 0.4 m
Z_ROAD = 1.2        # G1 / G3 / G7
Z_LOW1 = 0.8        # G2 / G4 / G8
Z_LOW2 = 0.4        # G5 / G9
Z_P11A = 4.4
Z_P11B = 4.0
Z_P08 = 3.6
Z_P12 = 4.4
Z_ARM = 6.4         # P20 / P21 / P22 / P26a
Z_P17 = 6.0
Z_P24 = 6.8         # P23 / P24 / P26b
Z_P25 = 7.2         # P25 / P26c (in01)
Z_P29 = 8.4         # in04 knoll
Z_SKIRT = 8.8       # P30/P31 summit skirt + in05 shoulder
Z_SUMMIT = 11.6


# ---------------------------------------------------------------------------
# local assets (map-prefixed; candidates for the shared kit)
# ---------------------------------------------------------------------------

@asset("X1000000_StalkMushroom_Cluster", "Foliage", footprint=4.0, tags=("mushroom", "landmark"))
def _stalk_mushrooms(coll):
    """Cluster of tall pale beige stalk-mushrooms (east balcony P12 landmark, ~5 m tall, chunky stems)."""
    mb = MeshBuilder()
    stalks = [(0.0, 0.0, 5.0, 0.48), (1.25, 0.55, 3.9, 0.4), (-1.1, 0.5, 4.3, 0.42), (0.5, -1.0, 2.9, 0.34),
              (-0.6, -0.95, 2.2, 0.3), (1.55, -0.6, 1.6, 0.26)]
    for i, (x, y, h, r) in enumerate(stalks):
        lean = (i % 3 - 1) * 4.0
        mb.cyl(r * 1.25, h, loc=(x, y, 0), rot=(lean, -lean * 0.6, 0), mat="M_MushStem", verts=10, r2=r * 0.8)
        cx = x - math.sin(math.radians(lean * 0.6)) * h
        cy = y - math.sin(math.radians(lean)) * h
        mb.dome(r * 2.6, r * 2.2, loc=(cx, cy, h - 0.1), mat="M_Grad_mush_stem_dk__plaster", u=14, v=4, profile=1.2)
        mb.sphere(r * 0.9, loc=(cx, cy, h - 0.12), scale=(1.4, 1.4, 0.35), mat="M_Flat_lid_tan", subdiv=1)
    mb.sphere(1.5, loc=(0, 0, 0.0), scale=(1.5, 1.2, 0.35), mat="M_Bush", subdiv=2, lumpy=0.15, seed=3)
    mb.build("X1000000_StalkMushroom_Cluster", coll, smooth=True, sharp_angle=50)


GATE_R = 2.6       # barrel-arch radius: ~5 m clear opening at the ground (trails are 4.2 m wide)
GATE_CZ = 0.5      # arch centre height
GATE_HD = 1.0      # half depth (along the passage, local y)


def _arc_boxes(mb, r, t0, t1, n, sy, sz, mat, y=0.0, alt_mat=None):
    """Boxes laid tangentially along an arc in the local x-z plane (angles in degrees, 0 = +x, 90 = up)."""
    for i in range(n):
        ta = math.radians(t0 + (t1 - t0) * i / n)
        tb = math.radians(t0 + (t1 - t0) * (i + 1) / n)
        tm = 0.5 * (ta + tb)
        chord = 2 * r * math.sin(abs(tb - ta) / 2) * 1.04
        mb.box((chord, sy, sz), loc=(r * math.cos(tm), y, GATE_CZ + r * math.sin(tm)),
               rot=(0, -(math.degrees(tm) + 90), 0), mat=(alt_mat if (alt_mat and i % 2) else mat))


def _plaque(mb, style, y, z, accent):
    """Keystone emblem on the arch front (faces -y): a round wooden boss with a coloured rim and the gate's
    classic danger motif ('excl' / 'skull' / 'skull_tilt' triangle, or the 'board' DANGER notice)."""
    mb.cyl(0.78, 0.14, loc=(0, y + 0.02, z), rot=(90, 0, 0), mat=accent, verts=20)
    mb.cyl(0.66, 0.16, loc=(0, y - 0.02, z), rot=(90, 0, 0), mat="M_Wood_Dark", verts=20)
    if style == "board":
        mb.box((1.7, 0.12, 0.78), loc=(0, y - 0.16, z - 0.05), rot=(0, 3, 0), mat="M_Plank", bevel=0.05, segs=1)
        mb.box((1.56, 0.04, 0.2), loc=(0, y - 0.24, z + 0.2), rot=(0, 3, 0), mat="M_Flat_cloth_red")
        for k in range(4):
            mb.box((0.2, 0.03, 0.07), loc=(-0.54 + k * 0.36, y - 0.27, z + 0.2), rot=(0, 3, 0),
                   mat="M_Flat_cloth_white")
        mb.box((0.11, 0.04, 0.3), loc=(0, y - 0.24, z - 0.1), mat="M_Eye_Black")
        mb.sphere(0.06, loc=(0, y - 0.24, z - 0.34), mat="M_Eye_Black", subdiv=1)
        return
    tilt = 14.0 if style == "skull_tilt" else 0.0
    zb = z - 0.42
    mb.prism([(-0.6, 0.0), (0.6, 0.0), (0.0, 1.04)], -0.04, 0.04, loc=(0, y - 0.18, zb), rot=(90, tilt, 0),
             mat="M_Flat_cloth_red", bevel=0.03, segs=1)
    mb.prism([(-0.45, 0.1), (0.45, 0.1), (0.0, 0.87)], -0.03, 0.03, loc=(0, y - 0.23, zb), rot=(90, tilt, 0),
             mat="M_Flat_flower_yellow")
    t = math.radians(tilt)

    def at(u, v):  # point on the (tilted) triangle face: u right, v up from its base centre
        return (u * math.cos(t) + v * math.sin(t), y - 0.28, zb - u * math.sin(t) + v * math.cos(t))
    if style == "excl":
        mb.box((0.1, 0.04, 0.32), loc=at(0, 0.54), mat="M_Eye_Black", bevel=0.02, segs=1)
        mb.sphere(0.06, loc=at(0, 0.27), mat="M_Eye_Black", subdiv=1)
    else:
        for s in (-1, 1):
            mb.box((0.46, 0.03, 0.06), loc=at(0, 0.3), rot=(0, s * 35 + tilt, 0), mat="M_Flat_cloth_white")
        mb.sphere(0.14, loc=at(0, 0.47), scale=(1.0, 0.45, 0.95), mat="M_Flat_cloth_white", subdiv=2)
        for s in (-1, 1):
            p = at(s * 0.055, 0.48)
            mb.sphere(0.035, loc=(p[0], p[1] - 0.05, p[2]), mat="M_Eye_Black", subdiv=1)


def _gate_mesh(coll, name, west_mound=True, staves=("M_Wood", "M_Plank"), rim="M_Wood_Dark", ivy=False,
               plaque=None, accent="M_Flat_roof_yellow"):
    """Open barrel-door gate: a short open-ended barrel tunnel (round plank arch with iron hoops) set between
    grassy earth half-mounds, its round barrel door swung open on the east side. The passage runs along local y
    so the world trail to the side map passes straight through; the origin is the centre of the passage floor.
    Each gate carries its destination's danger emblem on the keystone (plaque) and may be dressed with ivy."""
    R, HD = GATE_R, GATE_HD
    body = MeshBuilder()
    for s in ((-1, 1) if west_mound else (1,)):
        body.sphere(1.7, loc=(s * 3.75, 0.0, 0.15), scale=(0.78, 0.62, 1.2), mat="M_Dirt_Cliff", subdiv=3,
                    lumpy=0.08, seed=6 + s, flatten_bottom=0.1)
    # barrel staves (two wood tones), front rim and two iron hoops
    _arc_boxes(body, R, -7, 187, 15, 2 * HD, 0.18, staves[0], alt_mat=staves[1])
    _arc_boxes(body, R + 0.02, -7, 187, 18, 0.16, 0.3, rim, y=-HD)
    if plaque:
        _plaque(body, plaque, -HD - 0.1, GATE_CZ + R + 0.12, accent)
    if ivy:
        # ivy strands hanging off the front rim (Dangerous Forest: the arch is half swallowed by the forest)
        for k, t in enumerate((24, 40, 58, 122, 140, 156)):
            a = math.radians(t)
            x0, z0 = (R + 0.12) * math.cos(a), GATE_CZ + (R + 0.12) * math.sin(a)
            n = 4 + (k * 3) % 4
            for j in range(n):
                body.sphere(0.15 - j * 0.01, loc=(x0 + 0.05 * math.sin(j * 1.7), -HD - 0.16, z0 - j * 0.24),
                            scale=(1.2, 0.7, 0.9), mat=("M_Leaf" if (j + k) % 3 else "M_Leaf_B"), subdiv=1)
    for yy in (-HD + 0.3, HD - 0.3):
        _arc_boxes(body, R + 0.1, -7, 187, 18, 0.14, 0.08, "M_Metal", y=yy)
    # the round barrel door, swung open forward on its east hinge (face turned toward -x / the camera)
    hx, hy = R - 0.05, -HD - 0.05
    dang = math.radians(28.0)
    d = (math.sin(dang), -math.cos(dang))          # from the hinge along the door leaf
    n = (-math.cos(dang), -math.sin(dang))         # door face normal
    gam = math.degrees(math.atan2(n[0], -n[1]))    # yaw that turns a -y-facing disc to face n
    cx, cy, cz = hx + d[0] * 0.98, hy + d[1] * 0.98, 1.05
    body.cyl(1.0, 0.12, loc=(cx - n[0] * 0.06, cy - n[1] * 0.06, cz), rot=(90, 0, gam), mat="M_Wood_Dark", verts=20)
    body.cyl(0.9, 0.18, loc=(cx - n[0] * 0.04, cy - n[1] * 0.04, cz), rot=(90, 0, gam), mat="M_Door", verts=20)
    band_yaw = math.degrees(math.atan2(d[1], d[0]))
    for dz in (-0.45, 0.0, 0.45):
        body.box((1.7, 0.04, 0.09), loc=(cx + n[0] * 0.15, cy + n[1] * 0.15, cz + dz), rot=(0, 0, band_yaw),
                 mat="M_Metal")
    body.sphere(0.08, loc=(cx + d[0] * 0.55 + n[0] * 0.2, cy + d[1] * 0.55 + n[1] * 0.2, cz), mat="M_Gold",
                subdiv=1)
    body.build(name + "_Body", coll, smooth=True, sharp_angle=50)
    grass = MeshBuilder()
    for s in ((-1, 1) if west_mound else (1,)):
        grass.sphere(1.78, loc=(s * 3.75, 0.0, 0.42), scale=(0.77, 0.61, 1.08), mat="M_Grass", subdiv=3,
                     lumpy=0.06, seed=9 + s, flatten_bottom=-0.25)
    # turf saddle over the back of the barrel (the front rim and hoop stay visible)
    _arc_boxes(grass, R + 0.22, 22, 158, 9, 1.3, 0.34, "M_Grass", y=0.3)
    for k, t in enumerate((50, 90, 130)):
        a = math.radians(t)
        grass.sphere(0.55, loc=((R + 0.3) * math.cos(a), 0.35, GATE_CZ + (R + 0.3) * math.sin(a)),
                     scale=(1.3, 1.25, 0.6), mat="M_Grass", subdiv=2, lumpy=0.1, seed=20 + k)
    if not west_mound:
        for k, (x, y) in enumerate(((-R - 0.3, 0.4), (-R - 0.1, -0.5))):
            grass.sphere(0.45, loc=(x, y, 0.2), scale=(1.1, 1.0, 0.7), mat="M_Bush", subdiv=2, lumpy=0.12,
                         seed=30 + k)
    grass.build(name + "_Grass", coll, smooth=True, sharp_angle=60)


@asset("X1000000_Barrel_Door_Gate_Excl", "Architecture", footprint=7.0, tags=("portal_door", "landmark"))
def _barrel_door_gate_excl(coll):
    """In a Small Forest gate (in00): east mound only (map edge on the west), '!' triangle on the keystone."""
    _gate_mesh(coll, "X1000000_Barrel_Door_Gate_Excl", west_mound=False, plaque="excl", accent="M_Flat_roof_green")


@asset("X1000000_Barrel_Door_Gate_Skull", "Architecture", footprint=9.0, tags=("portal_door", "landmark"))
def _barrel_door_gate_skull(coll):
    """Hunting Ground I gate (in04): two mounds, skull-and-crossbones triangle on the keystone."""
    _gate_mesh(coll, "X1000000_Barrel_Door_Gate_Skull", west_mound=True, plaque="skull", accent="M_Flat_roof_blue")


@asset("X1000000_Barrel_Door_Gate_SkullTilt", "Architecture", footprint=9.0, tags=("portal_door", "landmark"))
def _barrel_door_gate_skull_tilt(coll):
    """Hunting Ground II gate (in05): two mounds, the classic tilted skull triangle on the keystone."""
    _gate_mesh(coll, "X1000000_Barrel_Door_Gate_SkullTilt", west_mound=True, plaque="skull_tilt",
               accent="M_Flat_roof_purple")


@asset("X1000000_Barrel_Door_Gate_Dark", "Architecture", footprint=7.0, tags=("portal_door", "landmark"))
def _barrel_door_gate_dark(coll):
    """Dangerous Forest gate (in01): dark weathered staves, hanging ivy and the DANGER board on the keystone;
    east mound only (its west side leans on the higher summit-skirt face)."""
    _gate_mesh(coll, "X1000000_Barrel_Door_Gate_Dark", west_mound=False, staves=("M_Wood_Dark", "M_Bark"),
               rim="M_Flat_bark_dk", ivy=True, plaque="board", accent="M_Flat_roof_red")


@asset("X1000000_Bush_Autumn", "Foliage", footprint=1.4, tags=("bush",))
def _bush_autumn(coll):
    """Round orange autumn bush (In a Small Forest gate dressing)."""
    nature.bush(coll, "X1000000_Bush_Autumn", 21, 0.8, 4, mat="M_Leaf_Autumn")


@asset("X1000000_Bush_Mustard", "Foliage", footprint=1.4, tags=("bush",))
def _bush_mustard(coll):
    """Round mustard-yellow autumn bush."""
    nature.bush(coll, "X1000000_Bush_Mustard", 22, 0.7, 4, mat="M_Leaf_Yellow")


@asset("X1000000_Sign_Amherst", "Architecture", footprint=2.4, tags=("sign", "landmark"))
def _sign_amherst(coll):
    """The East Gate's big orange arrow signboard pointing east (+X) toward Amherst, on two posts (faces -Y).
    The 'Amherst' lettering is added by the map as 3D text."""
    mb = MeshBuilder()
    for x in (-0.75, 0.55):
        mb.box((0.18, 0.18, 2.3), loc=(x, 0.06, 1.15), mat="M_Wood", bevel=0.04, segs=1)
    # arrow-shaped board: plank body + pointed head toward +x, dark trim behind
    body = [(-1.35, -0.42), (0.85, -0.42), (0.85, -0.7), (1.65, 0.0), (0.85, 0.7), (0.85, 0.42), (-1.35, 0.42)]
    trim = [(x * 1.07 + (0.04 if x > 0 else -0.04), y * 1.16) for (x, y) in body]
    mb.prism(trim, -0.02, 0.1, loc=(0, 0, 1.75), rot=(90, 0, 0), mat="M_Wood_Dark", bevel=0.03, segs=1)
    mb.prism(body, 0.1, 0.2, loc=(0, 0, 1.75), rot=(90, 0, 0), mat="M_Flat_mush_orange", bevel=0.04, segs=1)
    for z in (1.6, 1.9):  # plank seams
        mb.box((2.1, 0.03, 0.03), loc=(-0.25, -0.205, z), mat="M_Flat_wood_dk")
    mb.box((0.5, 0.25, 0.08), loc=(-0.1, 0.02, 2.36), mat="M_Wood_Dark", bevel=0.02, segs=1)
    mb.build("X1000000_Sign_Amherst", coll, smooth=False)


@asset("X1000000_Signpost_Vined", "Props", footprint=1.4, tags=("prop",))
def _signpost_vined(coll):
    """Blank wooden signpost wrapped in ivy, with two loose planks at its foot (G7)."""
    mb = MeshBuilder()
    mb.box((0.16, 0.16, 1.9), loc=(0, 0, 0.95), mat="M_Wood", bevel=0.03, segs=1)
    mb.box((1.1, 0.1, 0.55), loc=(0.1, -0.1, 1.5), rot=(0, -4, 0), mat="M_Plank", bevel=0.04, segs=1)
    for k in range(9):
        a = k * 1.3
        mb.sphere(0.12, loc=(math.cos(a) * 0.13, math.sin(a) * 0.13 - 0.02, 0.15 + k * 0.19), scale=(1.2, 0.8, 0.8),
                  mat="M_Leaf", subdiv=1)
    for k in range(5):
        mb.sphere(0.11, loc=(-0.35 + k * 0.2, -0.17, 1.28 + (k % 2) * 0.1), scale=(1.2, 0.6, 0.9), mat="M_Leaf_B",
                  subdiv=1)
    mb.box((1.2, 0.28, 0.07), loc=(0.6, -0.55, 0.04), rot=(0, 0, 25), mat="M_Plank", bevel=0.02, segs=1)
    mb.box((1.0, 0.26, 0.07), loc=(0.7, -0.35, 0.11), rot=(0, 6, -10), mat="M_Plank", bevel=0.02, segs=1)
    mb.build("X1000000_Signpost_Vined", coll, smooth=False)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _door(m, portal, px, py, z_top, rot=0.0, scale=1.0, sign=None, sign_off=(2.6, 0.4), sign_rot=0.0,
          back=1.8, portal_rot=None):
    """Barrel-door mound behind an anchored portal; the door faces the portal (and the camera).

    `back` must leave the portal's arrival point clear: the runtime puts arriving players 1.5 m inward of the anchor
    (portal_adaptations.json arrival.inset_m, along the footprint edge's inward normal) in a 0.3 m capsule, and the
    mound's collision prism reaches 1.65 m in front of its origin (Barrel_Door_Mound, scale 1). For a front-edge door
    at yaw `rot` the arrival sits 1.5 * cos(rot) - back in front of the origin along the door axis, so back must be at
    least 1.5 * cos(rot) + 1.65 + 0.3 plus a margin. The export's spawn_clearance re-checks it on the real hulls."""
    r = math.radians(rot)
    # door normal at rot=0 is -y; the mound origin sits `back` m behind the portal
    nx, ny = math.sin(r), -math.cos(r)
    ox, oy = px - nx * back * scale, py - ny * back * scale
    m.place("Barrel_Door_Mound", ox, oy, rot=rot, scale=scale, z=z_top - 0.05, name=f"DoorMound_{portal}")
    m.edge_portal(portal, rot=rot if portal_rot is None else portal_rot)
    if sign:
        sx = px + sign_off[0] * math.cos(r) - sign_off[1] * math.sin(r)
        sy = py + sign_off[0] * math.sin(r) + sign_off[1] * math.cos(r)
        m.place(sign, sx, sy, rot=rot + sign_rot)


def _gate(m, portal, child_dir, variant, sign=None, sign_local=(3.8, -1.9), sign_rot=0.0, sign_scale=1.75):
    """Open barrel-door gate on a back-edge portal, aligned with the world trail that leaves through it.

    child_dir is the (dx, dy) local direction from the anchor toward the linked map (layout trail bearing);
    the trail is a 4.2 m solid embankment, so the gate's 5 m opening is centred on that line. The big danger
    sign stands right beside the arch opening (sign_local is in the gate frame: +x east, -y toward the camera),
    facing the camera. Returns a function mapping gate-local (x, y) to map-local (x, y) for more dressing."""
    ax, ay, _az = m.anchor(portal)
    rot = math.degrees(math.atan2(-child_dir[0], child_dir[1]))
    r = math.radians(rot)
    gx, gy = ax - math.sin(r) * 0.8, ay + math.cos(r) * 0.8
    m.place(variant, gx, gy, rot=rot, name=f"Gate_{portal}")
    m.edge_portal(portal, rot=rot)

    def to_map(lx, ly):
        return gx + lx * math.cos(r) - ly * math.sin(r), gy + lx * math.sin(r) + ly * math.cos(r)
    if sign:
        sx, sy = to_map(*sign_local)
        m.place(sign, sx, sy, rot=sign_rot, scale=sign_scale, name=f"Sign_{portal}")
    return to_map


def _pillar(m, name, cx, cy, rx, ry, top, bottom, style="grass_dirt"):
    m.terrace(name, geo.ellipse(cx, cy, rx, ry, 18), top=top, bottom=bottom, style=style)


def build(m):
    L, D = m.size  # 80 x 48

    # =====================================================================
    # GROUND ROAD (front band)
    # =====================================================================
    m.terrace("G1_WestGate", [(-1, -0.6), (14.3, -0.6), (14.3, 27.5), (6, 28.3), (-1, 27.8)], top=Z_ROAD,
              bottom=-0.5)
    m.terrace("G2_Swale", geo.rounded_rect(13.9, -0.6, 21.3, 26.0, 1.2), top=Z_LOW1, bottom=-0.5)
    m.terrace("G3_RopeYard", [(20.9, -0.6), (36.7, -0.6), (36.7, 21.5), (30, 24.5), (20.9, 24.8)], top=Z_ROAD,
              bottom=-0.5)
    m.terrace("G4_Step", geo.rect(36.3, -0.6, 39.0, 17.6), top=Z_LOW1, bottom=-0.5)
    m.terrace("G5_Step", geo.rect(38.6, -0.6, 41.3, 17.6), top=Z_LOW2, bottom=-0.5)
    # (the Hollow G6 is the plinth itself, z = 0, x ~41..63)
    # the raised Hollow block P01 (classic twin-door mound): a door-less 1 m knoll you only reach by a drop
    # or a knock-back, like the islanders' remembered "pillar" ledge above the Mushroom Garden door
    m.terrace("P01_Knoll", geo.rounded_rect(43.5, 1.6, 51.0, 7.6, 1.6), top=1.0, bottom=-0.5)
    # G7 cliff block with a pocket notched into its front-west corner for the Mushroom Garden barrel door
    m.terrace("G7_CliffTop", [(67.6, -0.6), (69.3, -0.6), (69.3, 17.4), (63.0, 17.4), (63.0, 8.6), (65.2, 7.6),
                              (67.6, 5.4)], top=Z_ROAD, bottom=-0.5)
    m.terrace("G8_Step", geo.rect(68.9, -0.6, 71.6, 17.2), top=Z_LOW1, bottom=-0.5)
    m.terrace("G9_Step", geo.rect(71.2, -0.6, 73.9, 17.2), top=Z_LOW2, bottom=-0.5)
    # (the East Gate G10 is the plinth, x ~74..80)
    # walkable bypass of the Hollow's sheer east cliff, tucked along the back wall
    m.ramp("Ramp_Hollow_G7", (53.5, 14.0, 0.0), (63.8, 14.0, Z_ROAD), 3.8, top_mat="M_Main_Road", blend=False)
    # ...but the classic climb up the sheer cliff is still offered right at the road
    m.ladder("Rope_Cliff_G7", 62.7, 10.4, 0.0, Z_ROAD, facing=0, kind="rope")

    # the island's through-road (Split Road -> Amherst): one cream ribbon from west00 to east00, over the
    # Hollow and up the bypass ramp (its top is road too); every side path stays dirt
    m.path("Main_Road", [(0.3, 12), (8, 11), (14, 10.5), (21, 10.5), (30, 10.8), (36, 11), (41, 11),
                         (46.5, 12.6), (50.2, 14.0), (53.5, 14.0), (58.6, 14.0), (63.8, 14.0), (65.2, 13.6),
                         (67, 12.5), (72, 12), (79.7, 12)], **MAIN_ROAD)
    m.path("Path_MushroomGarden", [(48, 12), (55, 6), (60.5, 2.2), (62, 1.6)], width=2.6)
    m.path("Path_SnailGarden", [(73.2, 11.4), (73.8, 8.2), (74.4, 4.4), (75.5, 1.6), (78, 1.4)], width=2.6)

    # =====================================================================
    # MID BAND: central plateau, rope-yard stumps, P08, east balcony, lookout
    # =====================================================================
    m.terrace("P11a_Plateau", [(34.4, 17.4), (50.4, 16.9), (50.6, 28.8), (52.6, 29.4), (52.4, 38.6),
                                (39.6, 38.6), (39.4, 29.6), (34.4, 29.2)], top=Z_P11A, bottom=-0.5)
    m.terrace("P11b_Plateau", [(50.0, 16.8), (63.2, 16.8), (63.4, 28.8), (50.0, 29.2)], top=Z_P11B, bottom=-0.5)
    # rope-yard stepping stumps P05 -> P07 -> P10 up to the plateau's west end, joined by solid earthen
    # ramps (grassy saddles between the stumps, never floating boards)
    m.terrace("P05_Stump", geo.rounded_rect(21.6, 17.6, 25.8, 22.0, 1.6), top=2.0, bottom=0.6)
    m.terrace("P07_Stump", geo.rounded_rect(27.6, 18.6, 31.6, 23.0, 1.6), top=2.8, bottom=0.6)
    m.terrace("P10_Stump", geo.rounded_rect(28.0, 24.8, 33.0, 28.0, 1.6), top=3.6, bottom=0.6)
    # grassy saddles; one continuous worn trail is draped over the whole climb below
    grass = dict(top_mat=None)
    m.ramp("R_G3_P05", (23.6, 13.8, Z_ROAD), (23.6, 18.2, 2.0), 2.6, **grass)
    m.ramp("R_P05_P07", (24.9, 20.4, 2.0), (28.2, 20.4, 2.8), 2.6, bottom=0.6, **grass)
    m.ramp("R_P07_P10", (29.6, 21.8, 2.8), (29.6, 25.4, 3.6), 2.6, bottom=0.6, **grass)
    m.ramp("R_P10_P11a", (31.8, 26.3, 3.6), (35.0, 26.3, Z_P11A), 2.6, bottom=0.6, **grass)
    # classic ropes 898 / 1085 / 1167 hanging off the stumps and the plateau into the rope yard
    m.ladder("Rope_P07", 30.4, 18.3, Z_ROAD, 2.8, facing=90, kind="rope")
    m.ladder("Rope_P10", 32.3, 24.5, Z_ROAD, 3.6, facing=90, kind="rope")
    m.ladder("Rope_P11a", 35.8, 17.1, Z_ROAD, Z_P11A, facing=90, kind="rope")
    # the long rope 2197 from the Hollow floor up the plateau face
    m.ladder("Rope_Hollow_P11b", 52.0, 16.5, 0.0, Z_P11B, facing=90, kind="rope")
    # P08 above the cliff top, ladder 2528 from G7
    m.terrace("P08_Ledge", geo.rounded_rect(62.0, 16.0, 66.6, 21.4, 1.4), top=Z_P08, bottom=0.6)
    m.ladder("Ladder_G7_P08", 64.4, 15.7, Z_ROAD, Z_P08, facing=90)

    # east balcony P12 over the East Gate (stalk mushrooms), ropes 3001 / 3064 down to the gate
    m.terrace("P12_Balcony", [(67.6, 17.2), (80.6, 17.0), (80.6, 31.6), (67.8, 31.2)], top=Z_P12, bottom=-0.5)
    m.ladder("Rope_P12_G9", 72.2, 16.7, Z_LOW2, Z_P12, facing=90, kind="rope")
    m.ladder("Rope_P12_G10", 76.0, 16.7, 0.0, Z_P12, facing=90, kind="rope")

    # west lookout: the stacked floaters P02-P09 as a zig-zag of grassy stump pillars (dead end)
    lookout = [(9.6, 16.4, 1.6), (12.2, 18.4, 2.0), (10.0, 20.8, 2.4), (12.6, 22.9, 2.8), (15.4, 24.0, 3.2)]
    for i, (x, y, z) in enumerate(lookout):
        _pillar(m, f"Lookout_{i}", x, y, 1.65, 1.5, z, Z_ROAD - 0.4)

    # =====================================================================
    # UPPER-MID BAND: V-fork, west terraces (in00), east shelf
    # =====================================================================
    vfork = [("P13", 46.0, 30.4, 4.8), ("P14", 46.0, 32.8, 5.2), ("P15", 43.7, 34.6, 5.6),
             ("P16", 48.3, 34.6, 5.6), ("P18", 41.5, 36.1, 6.0), ("P19", 50.5, 36.1, 6.0)]
    for name, x, y, z in vfork:
        _pillar(m, f"VFork_{name}", x, y, 1.7, 1.45, z, Z_P11A - 0.3)

    m.terrace("P22_WestArm", geo.rounded_rect(28.2, 28.2, 41.6, 38.8, 1.6), top=Z_ARM, bottom=-0.5)
    m.terrace("P24_Hump", geo.rounded_rect(21.2, 29.6, 29.2, 38.6, 1.8), top=Z_P24, bottom=-0.5)
    m.terrace("P21_Hub", geo.rounded_rect(13.0, 27.0, 22.0, 36.2, 1.8), top=Z_ARM, bottom=-0.5)
    m.terrace("P17_Dip", geo.rounded_rect(7.6, 26.4, 16.0, 32.6, 1.6), top=Z_P17, bottom=-0.5)
    m.terrace("P20_DoorTerrace", [(-1.0, 27.6), (9.6, 27.2), (9.8, 40.0), (8.6, 49.6), (-1.0, 49.6)], top=Z_ARM,
              bottom=-0.5)
    # (the knoll stays east of the in00 gate opening, so the gate, the portal and the trail all sit on P20;
    # the gate's east mound backs into the knoll's face)
    m.terrace("P27_Knoll", geo.rounded_rect(7.6, 46.8, 10.2, 49.8, 1.0), top=Z_ARM + 1.8, bottom=Z_ARM - 0.3)
    m.terrace("P23_Step", geo.ellipse(19.6, 37.6, 2.4, 1.9, 18), top=Z_P24, bottom=Z_ARM - 0.3)
    m.terrace("P25_Ledge", geo.rounded_rect(10.2, 35.2, 17.6, 40.8, 1.6), top=Z_P25, bottom=-0.5)
    # Fill the ground-level gap enclosed by P17 (south), P20 (west), P21 (east) and P25's rounded corner (north): a
    # player who dropped into it faced 6-7 m walls on every side (Iteration Two Test C replay, trap_probe at local
    # (12.6, 0, -33.6)). 0.2 m below the 6.4 m caps on either side, so every neighbour is a walkable step and no cap is
    # coplanar with another; it tucks under P20, P21 and P25 where they overlap.
    m.terrace("P17_P25_Fill", [(9.5, 32.4), (13.3, 32.4), (13.3, 37.4), (9.5, 37.4)], top=Z_ARM - 0.2, bottom=-0.5)
    m.terrace("P29_In04Knoll", [(8.8, 40.4), (24.0, 40.0), (29.8, 41.0), (29.8, 49.6), (8.8, 49.6)], top=Z_P29,
              bottom=-0.5)
    m.ramp("R_P25_P29", (13.6, 37.0, Z_P25), (13.6, 41.4, Z_P29), 2.6)
    # The plinth-level gap behind P21 and P24 and in front of P29 (x 17-30, y 36-41) was a pit 6-8 m deep that a
    # player fell into from any of them (Iteration Three stuck-region scan): filled 0.2 m below P21.
    m.terrace("P21_P29_Gap_Fill", [(16.8, 35.6), (30.0, 35.6), (30.0, 41.2), (16.8, 41.2)], top=Z_ARM - 0.2,
              bottom=-0.5)

    # east shelf P26a -> P26b -> P26c (in01) and the stairs down to the balcony
    m.terrace("P26a_EastArm", geo.rounded_rect(51.2, 28.4, 61.2, 37.6, 1.6), top=Z_ARM, bottom=-0.5)
    m.terrace("P26b_Step", geo.rounded_rect(59.8, 30.2, 65.4, 37.2, 1.4), top=Z_P24, bottom=-0.5)
    # (its west edge tucks under the higher in05 shoulder so no slot opens between them)
    m.terrace("P26c_In01Shelf", [(64.2, 33.0), (77.4, 32.8), (77.6, 49.6), (61.6, 49.6), (61.6, 38.6),
                                 (64.2, 38.2)], top=Z_P25, bottom=-0.5)
    m.stairs("St_P12_P26c", (71.6, 26.0, Z_P12), (71.6, 33.1, Z_P25), 2.8, step_h=0.2)
    m.ladder("Rope_P26c_P12", 75.6, 32.5, Z_P12, Z_P25, facing=90, kind="rope")
    # Plinth-level gaps between these shelves trapped a player who fell into them (Iteration Three stuck-region
    # scan, docs/runtime/STUCK_SCAN.md): the slot between P12 and P26c with the strip behind P26c's east edge (walled
    # by P12, P26c and the containment ring), the gap between P08, P11b, P26b and P12, and the notch between P26b,
    # P26c and the summit skirt. Each is filled 0.2 m below the shelf it joins, so a fall lands on a walkable step.
    m.terrace("P12_P26c_Slot_Fill", [(64.0, 30.4), (80.6, 30.4), (80.6, 48.6), (77.2, 48.6), (77.2, 33.4),
                                     (64.0, 33.4)], top=Z_P12 - 0.2, bottom=-0.5)
    m.terrace("P08_P12_Gap_Fill", [(63.0, 21.0), (68.0, 21.0), (68.0, 30.6), (61.0, 30.6), (61.0, 28.6),
                                   (63.0, 28.6)], top=Z_P11B - 0.2, bottom=-0.5)
    m.terrace("P26b_Notch_Fill", [(60.8, 36.8), (65.8, 36.8), (65.8, 39.0), (60.8, 39.0)], top=Z_P24 - 0.2,
              bottom=-0.5)

    # =====================================================================
    # TOP BAND: summit skirt (in05 shoulder) and the summit grove
    # =====================================================================
    m.terrace("P31_SummitSkirt", [(29.2, 38.8), (51.0, 38.0), (62.4, 37.8), (62.6, 49.6), (29.2, 49.6)],
              top=Z_SKIRT, bottom=-0.5)
    # the wooded summit: a broad crown pulled forward over the skirt (a 3 m strip stays free in front of it
    # for the in05 trail along the skirt)
    m.terrace("P36_Summit", geo.rounded_rect(36.6, 41.6, 51.0, 49.4, 2.0), top=Z_SUMMIT, bottom=Z_SKIRT - 0.3)
    m.stairs("St_P22_Skirt", (33.4, 31.4, Z_ARM), (33.4, 38.9, Z_SKIRT), 2.8, step_h=0.2)
    # the summit is climbed from the west landing (where classic ladder 1554 + stones P34/P35 were): an
    # earthen trail ramp along the landing
    m.ramp("R_Skirt_Summit", (30.8, 45.6, Z_SKIRT), (37.3, 45.6, Z_SUMMIT), 2.8)
    # classic ropes 1537/1598 and ladder 1554 survive as climbing shortcuts
    m.ladder("Rope_P22_Skirt", 30.6, 38.5, Z_ARM, Z_SKIRT, facing=90, kind="rope")
    m.ladder("Ladder_Skirt_Summit", 43.0, 41.3, Z_SKIRT, Z_SUMMIT, facing=90)

    # =====================================================================
    # SIDE-MAP DOORS (classic barrel doors + danger-sign variants)
    # The four back-edge doors are open barrel gates: the world trail to each side map leaves the anchor
    # along local +y as a 4.2 m solid embankment, so it must pass through the door, not into a mound.
    # child_dir = layout bearing from the anchor toward the linked map's anchor (parent-local).
    # =====================================================================
    # Each gate is dressed for its destination: In a Small Forest = '!' triangle + autumn bushes; the two
    # Hunting Grounds = skull triangles (in05's tilted, with flowers); Dangerous Forest = dark ivy-hung staves
    # and the DANGER notice board.
    # (each sign stands on the outer side of its own gate, so neighbouring gates never share a sign)
    g00 = _gate(m, "in00", (-2.5, 23.9), "X1000000_Barrel_Door_Gate_Excl", sign="Sign_Danger_Excl",
                sign_local=(-3.3, -1.9), sign_rot=6)
    for k, (lx, ly, a) in enumerate([(4.9, -1.3, "X1000000_Bush_Autumn"), (3.6, -2.6, "X1000000_Bush_Mustard"),
                                     (-3.6, -4.0, "X1000000_Bush_Autumn")]):
        bx, by = g00(lx, ly)
        m.place(a, bx, by, rot=k * 70, scale=1.0 - 0.1 * (k % 2))
    g04 = _gate(m, "in04", (-0.4, 12.0), "X1000000_Barrel_Door_Gate_Skull", sign="Sign_Danger_Skull",
                sign_local=(3.7, -1.9), sign_rot=-6)
    for k, (lx, ly, a) in enumerate([(5.6, -0.6, "Bush_B")]):
        bx, by = g04(lx, ly)
        m.place(a, bx, by, rot=k * 90)
    g05 = _gate(m, "in05", (6.7, 63.6), "X1000000_Barrel_Door_Gate_SkullTilt")
    sx, sy = g05(3.7, -2.0)
    m.place("Sign_Danger_Skull", sx, sy, rot=-10, scale=1.75, tilt=(0, -11), name="Sign_in05")
    for k, (lx, ly) in enumerate([(5.2, -1.0), (-4.6, -1.7), (-3.2, -2.4)]):
        bx, by = g05(lx, ly)
        m.place("Flower_Patch_A" if k % 2 else "Flower_Patch_B", bx, by, rot=k * 60, scale=1.2)
    # in01's west side leans on the higher summit-skirt face, so it only has the east mound
    g01 = _gate(m, "in01", (1.5, 13.9), "X1000000_Barrel_Door_Gate_Dark", sign="Sign_Danger_Board",
                sign_local=(4.0, -2.1), sign_rot=-8, sign_scale=1.35)
    for k, lx in enumerate((-1.9, 1.7)):
        vx, vy = g01(lx, -1.2)
        m.place("Vine_Hanging_A", vx, vy, z=Z_P25 + 2.6, scale=(1, 1, 1.3), rot=k * 30)
    # the two front-edge doors keep the closed barrel-door mound (their trails leave toward -y, away from it). The
    # mounds stand far enough back that a player arriving through in02 / in03 lands on the grass between the swirl
    # and the closed door (back=2.4 put the arrival inside the mound and the runtime had to move it 1.0-1.5 m). in03
    # faces straight at the camera: at -15 its mound already reached 1.6 m past the east edge (0.7 m now).
    _door(m, "in02", 62.0, 1.0, 0.0, rot=-30, back=3.6, portal_rot=65)
    m.place("Sign_Danger_Board", 58.0, 1.2, rot=-20)
    _door(m, "in03", 78.0, 1.0, 0.0, rot=0, back=3.8, portal_rot=65)
    m.edge_portal("west00")
    m.edge_portal("east00")
    # worn trails along the upper routes, from the V-fork tops out to every back gate
    m.path("Path_in00", [(4.0, 46.4), (3.6, 44.0), (3.0, 40.0), (4.2, 34.6), (7.6, 30.6), (11.4, 29.8),
                         (14.6, 30.4), (19.0, 32.2), (24.0, 33.0), (27.4, 33.0), (30.6, 31.8), (33.4, 29.8),
                         (36.0, 30.6), (38.6, 33.4)], width=2.0)
    # in04: P21 -> P23 -> P25, then the dirt ramp itself carries the trail up to P29 and on to the gate
    m.path("Path_in04_Low", [(18.6, 31.6), (19.4, 34.4), (19.4, 37.4), (16.6, 37.6), (14.6, 37.4)], width=2.0)
    m.path("Path_in04", [(14.0, 46.2), (13.8, 44.4), (13.6, 43.0)], width=2.0)
    m.path("Path_SkirtWest", [(14.2, 45.6), (14.6, 44.6), (16.6, 43.4), (20.0, 43.6), (27.0, 43.6), (30.4, 41.8),
                              (33.4, 39.6)], width=1.8)
    m.path("Path_Plateau", [(35.6, 26.3), (38.0, 25.0), (42.0, 24.6), (45.4, 26.2), (46.0, 28.8)], width=1.8)
    m.path("Path_in05", [(56.0, 46.2), (56.0, 44.2), (54.6, 41.4), (51.0, 39.9), (44.0, 39.8), (37.0, 40.0),
                         (33.4, 40.0)], width=2.0)
    # the summit trail: from the skirt fork round to the ramp foot, and from the ramp head into the grove
    m.path("Path_SummitFoot", [(31.8, 41.4), (31.2, 43.2), (31.2, 44.6)], width=1.8)
    m.path("Path_Summit", [(38.6, 45.6), (41.6, 45.3), (44.6, 44.7)], width=1.8)
    m.path("Path_in01", [(66.0, 46.2), (66.2, 41.0), (65.4, 36.4), (62.6, 34.0), (58.0, 33.4), (53.6, 34.0)],
           width=2.0)
    m.path("Path_RopeYard", [(23.6, 12.0), (23.6, 18.8), (24.6, 20.4), (28.2, 20.4), (29.6, 21.8), (29.6, 25.6),
                             (30.8, 26.3), (35.6, 26.3), (38.0, 25.0)], width=1.8)

    # =====================================================================
    # LANDMARKS
    # =====================================================================
    # East Gate: the big orange "Amherst ->" arrow board beside east00, and the sunflower patch
    # (turned 28 deg so the arrow points at the gate and the board catches the east sun instead of standing
    # in its own shade; 1.3x so it reads beside the sunflowers)
    SIGN_S, SIGN_R = 1.3, 28.0
    m.place("X1000000_Sign_Amherst", 76.4, 9.0, rot=SIGN_R, scale=SIGN_S, name="Sign_Amherst")
    sz = m.ground_z(76.4, 9.0)
    cr, sr = math.cos(math.radians(SIGN_R)), math.sin(math.radians(SIGN_R))
    tx, ty = -0.15 * SIGN_S, -0.24 * SIGN_S
    sign_text(m, "Amherst", 76.4 + tx * cr - ty * sr, 9.0 + tx * sr + ty * cr, sz + 1.74 * SIGN_S,
              rot=SIGN_R, size=0.5 * SIGN_S, mat="M_Flat_bark_dk", name="Sign_Amherst")
    # sunflowers flank the gate road and the Snail Garden path without standing on them
    for i, (x, y) in enumerate([(78.6, 7.8), (79.2, 9.2), (77.4, 6.6), (73.4, 15.0), (78.8, 14.6)]):
        m.place("Sunflower_Patch", x, y, rot=i * 50, scale=0.9 + (i % 3) * 0.08)
    # G7: the vine-wrapped blank signpost with loose planks
    m.place("X1000000_Signpost_Vined", 66.6, 9.8, rot=-10)
    # central plateau: barrels on P11b (3 upright, 1 on its side), red toadstools on P11a's front-west lawn
    for (x, y) in [(53.4, 22.2), (54.4, 22.9), (55.3, 22.0)]:
        m.place("Barrel", x, y, rot=x * 20)
    m.place("Barrel", 56.7, 22.6, rot=70, tilt=(90, 0), z=Z_P11B + 0.38)
    m.place("Mushroom_Giant_Red", 38.6, 21.4, rot=-20, scale=0.75)
    m.place("Mushroom_Cluster_A", 40.4, 20.6, rot=30, scale=1.3)
    # east balcony: the two giant pale stalk-mushroom clusters on its front lip, towering over the East Gate,
    # + a red toadstool cluster
    m.place("X1000000_StalkMushroom_Cluster", 70.0, 19.6, rot=10, scale=1.4)
    m.place("X1000000_StalkMushroom_Cluster", 74.4, 19.8, rot=-35, scale=1.2)
    m.place("Mushroom_Cluster_A", 74.6, 25.8, rot=-20, scale=1.4)
    m.place("Mushroom_Red_S", 74.0, 22.6)
    # ivy hanging off the Dangerous Forest shelf
    for x in (66.5, 68.8, 73.4):
        m.place("Vine_Hanging_A", x, 32.55, z=Z_P25 - 0.1, rot=0, scale=(1, 1, 1.4))
    for x in (55.0, 58.6):
        m.place("Vine_Hanging_A", x, 37.6, z=Z_SKIRT - 0.1, scale=(1, 1, 1.2))

    # =====================================================================
    # TREES (white-trunk midForest set: green, teal, orange, yellow)
    # =====================================================================
    trees = [
        # west gate (autumn trees by the Split Road exit), swale tree
        ("Tree_Birch_Orange", 1.2, 23.5, 1.0), ("Tree_Birch_Yellow", 4.8, 25.6, 0.95),
        ("Tree_Birch_Orange", 18.6, 23.6, 0.9),
        # Hollow: white-trunk tree by the road and the squat tree on the P01 knoll
        ("Tree_Birch_Lime", 44.0, 14.6, 0.85), ("Tree_Birch_Teal", 50.0, 6.4, 0.7),
        # P27 knoll (between the in00 and in04 gates), in00's autumn tree, door terraces (clear of the gates
        # and their trail corridors)
        ("Tree_Birch_Yellow", 9.0, 49.0, 0.9), ("Tree_Birch_Orange", 0.8, 37.4, 0.9),
        ("Tree_Birch_Teal", 20.2, 48.4, 0.95), ("Tree_Birch_Orange", 22.2, 48.9, 0.9),
        ("Tree_Birch_Lime", 24.4, 47.8, 0.9),
        # summit grove: a ring of autumn birches round the back and east side of the summit (it reads against
        # the green world forest), and a teal one on the west landing
        ("Tree_Birch_Teal", 32.0, 48.6, 1.0), ("Tree_Birch_Orange", 38.0, 48.3, 1.0),
        ("Tree_Birch_Yellow", 41.6, 48.7, 1.1), ("Tree_Birch_Orange", 45.2, 48.5, 1.1),
        ("Tree_Birch_Yellow", 48.8, 48.2, 1.0), ("Tree_Birch_Orange", 50.0, 44.8, 0.9),
        # in05 shoulder, east shelf (P26a trees), Dangerous Forest shelf
        ("Tree_Birch_Orange", 62.0, 49.0, 0.9), ("Tree_Birch_Teal", 56.2, 35.8, 0.85),
        ("Tree_Birch_Yellow", 59.4, 36.6, 0.85), ("Tree_Birch_Orange", 72.6, 48.2, 1.0),
        ("Tree_Birch_Yellow", 76.4, 45.4, 0.95), ("Tree_Birch_Teal", 76.6, 38.4, 0.9),
        # west terraces back
        ("Tree_Birch_Yellow", 25.4, 37.6, 0.9),
        ("Tree_Birch_Teal", 0.2, 28.8, 0.9),
        # side framing: east edge of the balcony and the shelf, west edge of the gate
        ("Tree_Birch_Lime", 79.6, 30.0, 0.9), ("Tree_Birch_Orange", 79.4, 20.4, 0.8),
        ("Tree_Birch_Yellow", 0.2, 19.4, 0.85), ("Tree_Birch_Teal", 77.2, 34.6, 0.85),
        # plateau corners
        ("Tree_Birch_Teal", 62.2, 27.6, 0.8),
    ]
    for i, (a, x, y, s) in enumerate(trees):
        m.place(a, x, y, rot=i * 41, scale=s)

    # =====================================================================
    # BUSHES / FLOWERS / ROCKS
    # =====================================================================
    bushes = [("Bush_A", 5.4, 40.4), ("X1000000_Bush_Autumn", 7.4, 42.6), ("Bush_C", 4.4, 30.6), ("Bush_B", 9.6, 43.0),
              ("Bush_A", 18.6, 41.2), ("Bush_Flowering_A", 51.6, 45.0), ("Bush_C", 59.6, 43.6),
              ("Bush_B", 47.0, 47.4), ("Bush_Flowering_A", 43.4, 47.6), ("Bush_A", 72.0, 44.8),
              ("Bush_Flowering_A", 74.8, 41.6), ("Bush_B", 70.0, 21.0), ("Bush_C", 61.4, 26.8),
              ("Bush_C", 47.6, 19.6), ("Bush_B", 25.6, 34.6), ("Bush_A", 18.6, 29.0),
              ("Bush_Flowering_A", 2.6, 19.6), ("Bush_C", 16.4, 2.0), ("Bush_A", 34.0, 1.6),
              ("Bush_B", 61.6, 30.6), ("Bush_C", 79.2, 18.8)]
    for i, (a, x, y) in enumerate(bushes):
        m.place(a, x, y, rot=i * 37)
    for (a, x, y, r) in [("Rock_A", 41.8, 15.8, 20), ("Rock_C", 46.4, 2.2, 0),
                         ("Rock_A", 22.0, 23.4, 40), ("Stump_A", 26.0, 13.8, 0), ("Log_A", 29.8, 15.6, 15),
                         ("Rock_C", 70.2, 2.0, 0), ("Rock_A", 51.0, 31.0, 0), ("Stump_A", 19.6, 15.4, 30),
                         ("Rock_B", 8.0, 27.0, 10)]:
        m.place(a, x, y, rot=r)
    m.place("Butterfly", 70.4, 41.0)
    m.place("Butterfly", 74.2, 44.0)
    m.place("Butterfly", 76.0, 9.4)
    m.place("Butterfly", 6.0, 5.0)
    m.place("Butterfly", 47.0, 5.6)
    # front lawns: low dressing only (keeps the road band readable)
    for (a, x, y, r, s) in [("Bush_B", 1.6, 2.2, 0, 1.0), ("Flower_Bed_Large", 6.4, 4.0, 20, 0.9),
                            ("Rock_A", 11.4, 2.6, 30, 1.0), ("Mushroom_Orange_S", 15.6, 4.6, 0, 1.0),
                            ("Mushroom_Yellow_S", 16.4, 5.2, 0, 1.0), ("Bush_Flowering_A", 27.6, 3.2, 10, 1.0),
                            ("Flower_Bed_Large", 31.6, 5.0, -15, 0.85), ("Rock_C", 25.4, 6.4, 0, 1.0),
                            ("Flower_Bed_Large", 49.6, 4.0, 5, 0.9), ("Bush_A", 42.4, 1.2, 0, 1.0),
                            ("Mushroom_Cluster_A", 55.6, 9.2, 40, 1.0), ("Grass_Tuft_A", 64.6, 6.6, 0, 1.0),
                            ("Flower_Patch_A", 68.4, 3.0, 0, 1.0), ("Bush_C", 72.0, 2.4, 0, 1.0),
                            ("Stump_A", 2.4, 16.0, 0, 1.1), ("Mushroom_Red_S", 3.2, 15.5, 0, 1.0),
                            # plateau props
                            ("Log_A", 41.4, 26.6, 10, 1.0), ("Stump_A", 59.6, 19.4, 0, 1.0),
                            ("Bush_B", 50.8, 27.4, 0, 0.9), ("Rock_B", 42.6, 18.4, 40, 0.8),
                            ("Mushroom_Cluster_A", 60.4, 24.6, 0, 1.0),
                            # door terraces / shelves
                            ("Bush_Flowering_A", 6.6, 36.4, 0, 1.0), ("Rock_A", 2.0, 31.6, 0, 1.0),
                            ("Mushroom_Cluster_A", 8.0, 39.0, 0, 1.0), ("Log_A", 70.6, 41.6, 15, 1.0),
                            ("Bush_C", 74.0, 37.2, 0, 1.0),
                            ("Rock_C", 58.0, 39.6, 0, 1.0),
                            ("Stump_A", 23.4, 41.2, 0, 1.0)]:
        m.place(a, x, y, rot=r, scale=s)
    # stones embedded in the big soil faces (Maple dirt walls carry mossy rocks)
    for (x, y, z) in [(37.8, 17.1, 2.6), (44.2, 16.6, 2.2), (48.6, 16.6, 3.2), (56.0, 16.5, 1.6), (60.4, 16.5, 2.8),
                      (3.0, 27.3, 3.4), (6.6, 27.0, 4.6), (10.8, 26.1, 2.6), (16.8, 26.7, 4.0), (19.6, 26.7, 2.6),
                      (24.0, 29.3, 3.2), (70.6, 16.9, 2.0), (74.4, 16.7, 3.2), (78.6, 16.7, 1.6),
                      (44.0, 38.3, 6.6), (48.6, 38.0, 7.6), (66.8, 32.7, 5.6), (70.2, 32.6, 6.0), (13.0, 39.9, 7.9),
                      (21.0, 39.7, 7.6)]:
        m.place("Rock_Cliff_Stone", x, y, z=z, rot=0, scale=1.2)
    road_band = geo.rect(0, 8.4, 80, 15.6)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 80, 17), 30, seed=11,
              min_dist=1.7, avoid=[road_band, (63.4, 3.6, 3.6), (78.6, 3.4, 3.4), geo.rect(52, 12, 65, 16.5)])
    m.scatter(["Grass_Tuft_A", "Flower_Patch_B", "Flower_Patch_A", "Mushroom_Blue_S"],
              geo.rect(34.5, 17.5, 63, 29), 12, seed=13, min_dist=1.8,
              avoid=[geo.rect(52.5, 21, 58, 24), geo.rect(36.5, 19.5, 42, 23.2), (46, 30, 2.0)])
    gates = [geo.rect(-1.5, 42.0, 6.6, 50), geo.rect(8.6, 45.8, 19.4, 50), geo.rect(50.6, 45.8, 61.4, 50),
             geo.rect(62.6, 45.8, 71.4, 50)]
    m.scatter(["Flower_Patch_B", "Grass_Tuft_A", "Flower_Patch_A"], geo.rect(0, 17, 80, 49), 30, seed=12,
              min_dist=2.0, avoid=gates + [geo.rect(34.5, 17.5, 63, 29)])

    # =====================================================================
    # GAMEPLAY
    # =====================================================================
    m.player(46.2, 13.1, rot=-15)
    m.player_spawn(7.0, 12.0, rot=90, note="sp x -91: ~6 m east of west00 on the entry ground")
    # road and Hollow: Snails, Shrooms and Red Snails
    m.mobs("Snail", geo.rect(2, 2, 13, 8), 1, seed=1, z_band=(1.0, 1.4))
    m.mobs("Shroom", geo.rect(14, 2, 34, 8), 2, seed=2, z_band=(0.6, 1.4))
    m.mobs("Red Snail", geo.rect(42, 3, 56, 11), 2, seed=3, z_band=(-0.1, 0.2))
    m.mobs("Red Snail", geo.rect(65, 9.5, 69, 16), 1, seed=4, z_band=(1.0, 1.4))
    # plateau: Blue Snails, a Red Snail and the one Orange Mushroom of P11b
    m.mobs("Blue Snail", geo.rect(35, 19, 48, 27.5), 2, seed=5, z_band=(4.2, 4.6))
    m.mobs("Orange Mushroom", geo.rect(57, 19, 62.5, 27.5), 1, seed=6, z_band=(3.8, 4.2))
    # west terraces
    m.mobs("Red Snail", geo.rect(29, 29, 39, 35), 1, seed=7, z_band=(6.2, 6.6))
    m.mobs("Blue Snail", geo.rect(13.5, 28, 21.5, 34.5), 1, seed=8, z_band=(6.2, 6.6))
    m.mobs("Shroom", geo.rect(0, 29, 8, 40), 1, seed=9, z_band=(6.2, 6.6))
    m.mobs("Snail", geo.rect(9.5, 41.5, 25, 45.5), 2, seed=10, z_band=(8.2, 8.6))
    # summit skirt by the in05 door: the classic Shroom pocket
    m.mobs("Shroom", geo.rect(52, 39, 61.5, 45), 2, seed=11, z_band=(8.6, 9.0))
    # summit grove: Orange Mushrooms + a Snail
    m.mobs("Orange Mushroom", geo.rect(38.5, 42.3, 50, 44.4), 2, seed=12, z_band=(Z_SUMMIT - 0.2, Z_SUMMIT + 0.2))
    m.mobs("Snail", geo.rect(38.5, 42.3, 50, 47.8), 1, seed=13, z_band=(Z_SUMMIT - 0.2, Z_SUMMIT + 0.2))
    # east shelf: Red/Blue Snails, Orange Mushrooms guarding the Dangerous Forest door
    m.mobs("Blue Snail", geo.rect(52, 29.5, 60, 36), 1, seed=14, z_band=(6.2, 6.6))
    m.mobs("Orange Mushroom", geo.rect(67, 35, 76, 43), 1, seed=15, z_band=(7.0, 7.4))
    # east balcony
    m.mobs("Red Snail", geo.rect(68.5, 19, 75, 30), 1, seed=16, z_band=(4.2, 4.6))

    # --- routes (walkable only; ropes/ladders are shortcuts) ---
    m.route("Main", [(1, 12), (8, 11), (13, 10.8), (17.5, 10.6), (22, 10.6), (30, 10.8), (35.5, 11),
                     (37.6, 11), (39.8, 11), (43, 11.6), (48, 13.0), (53.0, 14.0), (58, 14.0), (63.6, 14.0),
                     (66.2, 12.6), (70.2, 12.2), (72.5, 12.0), (76, 12), (79, 12)])
    m.route("ToMushroomGarden_in02", [(48, 12.5), (54, 7), (60, 2.6), (62, 1.4)])
    m.route("ToSnailGarden_in03", [(72.5, 12.0), (73.8, 8.4), (74.6, 3.4), (76, 1.4), (78, 1.4)])
    m.route("WestLookout", [(7.2, 11.1), (7.5, 13.5), (9.6, 16.4), (12.2, 18.4), (10.0, 20.8), (12.6, 22.9), (15.4, 24.0)])
    m.route("ToPlateau_RopeYard", [(23.6, 10.65), (23.6, 11.5), (23.6, 14.0), (23.6, 18.4), (23.6, 20.4), (24.6, 20.4),
                                   (28.2, 20.4), (29.6, 20.6), (29.6, 21.6), (29.6, 25.6), (30.2, 26.3),
                                   (31.6, 26.3), (35.2, 26.3), (38, 25), (42, 23), (50.5, 24.6), (57, 25.6),
                                   (61.2, 21.2), (62.6, 19.0), (64.6, 18.8)])
    m.route("VFork_West_to_in00", [(46.7, 23.9), (46, 27.4), (46, 30.4), (46, 32.8), (43.7, 34.6), (41.5, 36.1), (38.6, 33.6),
                                   (36.0, 30.4), (33.4, 29.9), (30.6, 31.8), (27.4, 33.0), (24, 33.0),
                                   (19.0, 32.2), (14.6, 30.2), (11.4, 29.6), (7.6, 30.4), (4.2, 34.6), (3.0, 40.0), (3.6, 44.0),
                                   (4.0, 46.6)])
    m.route("To_in04", [(18.6, 31.8), (19.4, 34.4), (19.4, 37.4), (16.6, 37.6), (13.6, 37.4), (13.6, 41.8),
                        (14.0, 46.6)])
    m.route("ToSummit", [(33.4, 30.0), (33.4, 39.6), (31.8, 41.4), (31.2, 43.2), (31.2, 44.8), (31.6, 45.6),
                         (38.6, 45.6), (41.6, 45.3), (46, 45.0)])
    m.route("To_in05", [(33.6, 40.0), (40, 39.9), (46, 39.8), (51, 39.9), (54.6, 41.4), (56, 44.2), (56.0, 46.6)])
    m.route("Skirt_to_in04", [(31.0, 41.2), (27.0, 43.6), (20.0, 43.6), (16.6, 43.4), (14.4, 44.6), (14.0, 46.6)])
    m.route("VFork_East_to_in01", [(46.7, 23.9), (46, 27.4), (46, 30.4), (46, 32.8), (48.3, 34.6), (50.5, 36.1), (53.4, 34.0),
                                   (58, 33.4), (62.6, 33.8), (66.0, 35.6), (66, 40), (66.0, 46.6)])
    m.route("ToBalcony", [(66.0, 40.0), (68.6, 40), (71.6, 36.0), (71.6, 33.4), (71.6, 28.6), (72.6, 24), (77, 21)])
