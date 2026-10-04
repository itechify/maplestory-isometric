"""In a Small Forest (1000001) - "a glade wrapped around one giant white tree".

Classic (GMS v8) structure, from docs/research/maps/1000001_InASmallForest_1000001.md:
  a flat forest floor (G1, the danger ring: Orange Mushrooms + Shrooms); a tall zig-zag tower of
  tiny 168 px floaters climbing the left-centre in single 60 px jumps, with dead-end ledges
  branching west (P01 low, P06 mid, P19 high), the central ledge P11 and the crown P25 on top;
  the huge top ledge P24 with three ropes hanging like curtains; the mid-air arrival ledge P14 on
  the right (out00, red-berry bushes either side, the only exit); stepping stones P08/P10/P12 and
  a 4-step hill P02a-d with a ladder in the bottom-right corner. White-trunk trees with green,
  orange and mustard foliage everywhere. No NPCs in v8.

3D translation: one 60 px tier = 0.4 m, so every classic one-jump step is a walkable 0.4 m ledge.
The floater tower becomes a giant white-barked trunk ringed by a single spiral of grassy shelves
(about 300 degrees, so no shelf ever sits above another); the west ledges branch off it at rising
heights and depths, and its broken top is the crown. The top ledge P24 is the high back-east
ridge with three vines. The player arrives high on a grassy rock at the front-right corner (the trail from
the Field comes in over the front edge) and walks a plank boardwalk straight onto the arrival ledge P14,
looking down over the glade and the giant tree; stairs climb from P14 to the ridge, and stumps
P12/P10/P08 with grassy ramps lead down to the 4-step hill and the glade floor.
"""

import math

from misostory import geo
from misostory.geo import MeshBuilder
from misostory.kit import asset

MAP_ID = 1000001
GAMEPLAY_FOCUS = (19.0, 15.0)
GAMEPLAY_SCALE = 32.0

TREE_C = (12.0, 21.0)     # giant trunk centre
TRUNK_R = 2.4
CROWN_Z = 7.6             # P25
SHELF_R0, SHELF_RM = 2.2, 3.8   # shelf inner radius / walking radius
SPIRAL_A0 = 300.0         # first shelf angle (deg, math convention: 0 = +x east, 90 = +y back)
SPIRAL_STEP = -23.0       # clockwise seen from above: front -> west -> back -> east
Z_P01 = 1.6
Z_P14 = 4.4
Z_P24 = 7.2


# ---------------------------------------------------------------------------
# local assets
# ---------------------------------------------------------------------------

TRUNK_H = 7.15
TRUNK_R0, TRUNK_R1 = TRUNK_R * 1.08, TRUNK_R * 0.82    # base / top radius (a real taper, not a silo)
# broken limb stubs (angle deg, base z, length): set where the shelf below is low enough for >= 1.8 m headroom
LIMBS = ((165.0, 6.6, 1.4), (200.0, 6.2, 1.7), (335.0, 5.3, 1.6))
# the living crown: thick white limbs rising out of the broken top's BACK rim (bearings 55-140, the +y side,
# clear of the crown route's end (bearing ~1) and the exit toward the ridge (~25 deg)). Each limb leans out, then
# bends up (two segments), and stays > 1.5 m above the spiral shelves it crosses at the walking radius:
# (bearing deg, base z, tilt1 from vertical, len1, tilt2, len2, base radius)
CROWN_LIMBS = ((58.0, 6.9, 38.0, 2.4, 20.0, 2.2, 0.62), (100.0, 6.9, 24.0, 2.6, 10.0, 2.1, 0.66),
               (138.0, 6.9, 44.0, 2.5, 24.0, 2.0, 0.58))
# puffy canopy lobes (local x, y, z centre, radius, leaf material): autumn yellow / orange + one teal, all north
# of the trunk axis so the walkable crown and the ridge exit stay open to the sky; every underside >= 9.6 m
# (CROWN_Z + HEAD 1.4 + margin) - see _lobe_bottom
CANOPY = ((1.7, 3.3, 11.7, 2.6, "M_Leaf_Yellow"), (-0.7, 4.1, 12.1, 2.8, "M_Leaf_Autumn"),
          (-3.4, 3.2, 11.5, 2.4, "M_Leaf_Yellow"), (3.8, 5.0, 12.8, 2.0, "M_Leaf_B"),
          (-2.2, 5.6, 13.4, 2.0, "M_Leaf_Yellow"), (0.6, 2.6, 13.2, 2.1, "M_Leaf_Autumn"),
          (0.2, 4.6, 13.7, 1.8, "M_Leaf_Autumn"), (4.6, 4.6, 11.4, 1.7, "M_Leaf_Autumn"),
          (-5.3, 4.4, 11.8, 1.7, "M_Leaf_Autumn"))
LOBE_SQUASH, LOBE_FLAT, LOBE_LUMPY = 0.86, 0.4, 0.12


def _lobe_bottom(z, r):
    """Lowest point of a canopy lobe: flatten_bottom clamps the sphere at -r*FLAT (plus 15 % of the rest),
    lumpy noise can push it out by up to LUMPY*r, then the z squash applies."""
    return z - (LOBE_FLAT + (1 - LOBE_FLAT) * 0.15 + LOBE_LUMPY) * r * LOBE_SQUASH


def trunk_r(z):
    return TRUNK_R0 + (TRUNK_R1 - TRUNK_R0) * max(0.0, min(1.0, z / TRUNK_H))


@asset("X1000001_GiantTrunk_White", "Trees", footprint=6.0, tags=("tree", "landmark"))
def _giant_trunk(coll):
    """Giant white-barked 'midForest' trunk: tapered, birch-marked, with broken limb stubs, a knot hole and
    earthy root buttresses. Its broken top (z ~7.1) carries the walkable crown terrace built by the map.
    """
    mb = MeshBuilder()
    h = TRUNK_H
    mb.cyl(TRUNK_R0, h, mat="M_Flat_cloth_white", verts=22, r2=TRUNK_R1)
    # birch marks: short dark dashes all round the trunk
    for i in range(40):
        a = (i * 137.5) % 360
        z = 0.9 + (i * 0.61) % (h - 1.3)
        rr = trunk_r(z) + 0.01
        x, y = math.cos(math.radians(a)) * rr, math.sin(math.radians(a)) * rr
        mb.box((0.55 + (i % 3) * 0.2, 0.06, 0.09), loc=(x, y, z), rot=(0, 0, a + 90), mat="M_Flat_hair_black")
    # broken limb stubs high on the back / west / front-east (side-on to the camera, never end-on),
    # tilted 55 deg outward, with birch dashes and a raw tan break at the tip
    for (ad, zb, ln) in LIMBS:
        a = math.radians(ad)
        r_in = trunk_r(zb) - 0.1
        base = (math.cos(a) * r_in, math.sin(a) * r_in, zb)
        axis = (math.sin(math.radians(55)) * math.cos(a), math.sin(math.radians(55)) * math.sin(a),
                math.cos(math.radians(55)))
        up = (-math.cos(math.radians(55)) * math.cos(a), -math.cos(math.radians(55)) * math.sin(a),
              math.sin(math.radians(55)))
        side = (-math.sin(a), math.cos(a), 0.0)
        mb.cyl(0.46, ln, loc=base, rot=(0, 55, ad), mat="M_Flat_cloth_white", verts=10, r2=0.3)
        tip = tuple(base[i] + axis[i] * ln for i in range(3))
        mb.cyl(0.27, 0.05, loc=tip, rot=(0, 55, ad), mat="M_Flat_mush_stem_dk", verts=10)
        for k, (u, v, hh) in enumerate(((0.16, 0.0, 0.26), (-0.12, 0.12, 0.18), (-0.06, -0.15, 0.22))):
            p = tuple(tip[i] + up[i] * u + side[i] * v for i in range(3))
            mb.cyl(0.09, hh, loc=p, rot=(0, 55, ad), mat="M_Flat_cloth_white", verts=5, r2=0.02)
        for t in (0.35, 0.7):
            rt = 0.46 + (0.3 - 0.46) * t
            p = tuple(base[i] + axis[i] * ln * t + up[i] * rt for i in range(3))
            mb.box((0.08, 0.34, 0.07), loc=p, rot=(0, 55, ad), mat="M_Flat_hair_black")
    # a dark knot hole facing the camera
    mb.sphere(0.42, loc=(0.3, -trunk_r(1.55) + 0.02, 1.55), scale=(0.8, 0.35, 1.15), mat="M_Eye_Black", subdiv=2)
    mb.torus(0.44, 0.09, loc=(0.3, -trunk_r(1.55), 1.55), rot=(90, 0, 0), scale=(0.85, 1.25, 1.0),
             mat="M_Flat_mush_stem_dk", u=16, v=5)
    # jagged broken rim at the top (just inside the top radius; the crown terrace caps it)
    for k in range(9):
        a = 2 * math.pi * k / 9
        mb.cyl(0.3, 0.35 + (k % 3) * 0.12, loc=(math.cos(a) * TRUNK_R1 * 0.9, math.sin(a) * TRUNK_R1 * 0.9, h - 0.3),
               mat="M_Flat_cloth_white", verts=5, r2=0.04)
    # living limbs out of the back rim (white bark, birch dashes on the camera side), carrying the canopy
    from mathutils import Matrix, Vector
    cam = Vector((-0.17, -0.985, 0.0))   # toward the camera (local -view_dir) - where the dashes must show

    def dash(mb_, p, axis, rad, length=0.36):
        n = cam - axis * cam.dot(axis)
        if n.length < 1e-3:
            return
        n.normalize()
        t = n.cross(axis).normalized()
        e = Matrix((t, n, axis)).transposed().to_euler("XYZ")
        mb_.box((length, 0.06, 0.08), loc=tuple(p + n * (rad + 0.005)), rot=tuple(math.degrees(v) for v in e),
                mat="M_Flat_hair_black")

    tips = []
    for li, (ad, zb, t1, l1, t2, l2, rb) in enumerate(CROWN_LIMBS):
        a = math.radians(ad)
        r_in = trunk_r(zb) - 0.2
        base = Vector((math.cos(a) * r_in, math.sin(a) * r_in, zb))
        knee_r = rb * 0.78
        p = base
        for (tilt, ln, ra, rz) in ((t1, l1, rb, knee_r), (t2, l2, knee_r, rb * 0.45)):
            st, ct = math.sin(math.radians(tilt)), math.cos(math.radians(tilt))
            axis = Vector((st * math.cos(a), st * math.sin(a), ct))
            mb.cyl(ra, ln + 0.05, loc=tuple(p), rot=(0, tilt, ad), mat="M_Flat_cloth_white", verts=12, r2=rz)
            for k, f in enumerate((0.3, 0.68)):
                rr = ra + (rz - ra) * f
                q = p + axis * (ln * f)
                dash(mb, q + Vector((0, 0, 0.08 * (k - 0.5))), axis, rr, length=0.3 + 0.08 * ((li + k) % 2))
            p = p + axis * ln
            if tilt == t1:
                mb.sphere(knee_r * 1.02, loc=tuple(p), mat="M_Flat_cloth_white", subdiv=2)   # smooth knee
        tips.append(tuple(p))
        # a short side twig toward the neighbouring lobe, out of the knee
        knee = base + Vector((math.sin(math.radians(t1)) * math.cos(a), math.sin(math.radians(t1)) * math.sin(a),
                              math.cos(math.radians(t1)))) * l1
        mb.cyl(rb * 0.36, 1.4, loc=tuple(knee), rot=(0, t1 + 14, ad + (38 if li != 1 else -40)),
               mat="M_Flat_cloth_white", verts=8, r2=rb * 0.16)
    mb.build("X1000001_GiantTrunk_White", coll, smooth=True, sharp_angle=50)
    # the canopy as its own object (leaf gradients span the lobes, not the 14 m tree)
    crown = MeshBuilder()
    for i, (x, y, z, r, mat) in enumerate(CANOPY):
        assert _lobe_bottom(z, r) >= 9.6, ("canopy lobe too low", i, _lobe_bottom(z, r))
        crown.sphere(r, loc=(x, y, z), scale=(1.0, 1.0, LOBE_SQUASH), mat=mat, subdiv=3, lumpy=LOBE_LUMPY,
                     seed=40 + i, flatten_bottom=LOBE_FLAT)
    # small leaf tufts where each limb meets the canopy
    for k, tip in enumerate(tips):
        crown.sphere(0.95, loc=(tip[0], tip[1], max(tip[2] + 0.5, 9.6 + 0.6)), scale=(1.0, 1.0, LOBE_SQUASH),
                     mat=("M_Leaf_Autumn", "M_Leaf_Yellow", "M_Leaf_Autumn")[k % 3], subdiv=2, lumpy=0.12,
                     seed=60 + k, flatten_bottom=LOBE_FLAT)
    crown.build("X1000001_GiantTrunk_White_Crown", coll, smooth=True, sharp_angle=80)
    # root flare + blunt buttresses as their own object so the earthy-to-white gradient spans their height
    roots = MeshBuilder()
    roots.cyl(TRUNK_R * 1.45, 0.9, loc=(0, 0, -0.1), mat="M_Grad_bark__mush_stem_dk", verts=22,
              r2=TRUNK_R * 1.05)
    for k in range(7):
        a = 2 * math.pi * k / 7 + 0.35
        d = TRUNK_R * 1.15
        roots.sphere(1.0, loc=(math.cos(a) * d, math.sin(a) * d, 0.25), scale=(1.5, 0.75, 0.7),
                     rot=(0, 0, math.degrees(a)), mat="M_Grad_bark__mush_stem_dk", subdiv=2, lumpy=0.08,
                     seed=k, flatten_bottom=0.2)
    roots.build("X1000001_GiantTrunk_White_Roots", coll, smooth=True, sharp_angle=50)


@asset("X1000001_BracketFungus", "Foliage", footprint=1.6, tags=("mushroom",))
def _bracket_fungus(coll):
    """Tan/orange shelf fungus that props each grassy shelf on the trunk (protrudes toward -Y)."""
    mb = MeshBuilder()
    pts = [(math.cos(math.radians(a)) * 1.0, -math.sin(math.radians(a)) * 0.85) for a in range(0, 181, 15)]
    mb.prism(pts, -0.18, 0.12, mat="M_Grad_lid_tan__mush_orange", bevel=0.08, segs=2)
    pts2 = [(math.cos(math.radians(a)) * 0.7, -math.sin(math.radians(a)) * 0.55) for a in range(0, 181, 15)]
    mb.prism(pts2, -0.42, -0.16, mat="M_Flat_lid_tan", bevel=0.06, segs=2)
    mb.build("X1000001_BracketFungus", coll, smooth=True, sharp_angle=60)


@asset("X1000001_Bush_RedBerry", "Foliage", footprint=1.6, tags=("bush",))
def _bush_redberry(coll):
    """Round dark-green bush dotted with red berries (flanks the exit portal on P14)."""
    mb = MeshBuilder()
    for (x, y, z, r) in ((0, 0, 0.45, 0.62), (0.5, 0.15, 0.35, 0.48), (-0.48, 0.1, 0.33, 0.46), (0.05, 0.3, 0.75, 0.42)):
        mb.sphere(r, loc=(x, y, z), scale=(1.1, 1.0, 0.85), mat="M_Bush", subdiv=2, lumpy=0.12, seed=int(r * 100))
    for k in range(14):
        a = k * 2.4
        rr = 0.55 + (k % 3) * 0.12
        mb.sphere(0.07, loc=(math.cos(a) * rr * 0.9, math.sin(a) * rr * 0.6 - 0.25, 0.35 + (k % 4) * 0.13),
                  mat="M_Flat_flower_red", subdiv=1)
    mb.build("X1000001_Bush_RedBerry", coll, smooth=True, sharp_angle=60)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _polar(a_deg, r):
    a = math.radians(a_deg)
    return TREE_C[0] + math.cos(a) * r, TREE_C[1] + math.sin(a) * r


def _sector(a_mid, half_w, r0, r1, n=6):
    pts = []
    for i in range(n + 1):
        pts.append(_polar(a_mid - half_w + 2 * half_w * i / n, r1))
    for i in range(n + 1):
        pts.append(_polar(a_mid + half_w - 2 * half_w * i / n, r0))
    return pts


def shelf_angle(k):
    return SPIRAL_A0 + SPIRAL_STEP * k


def shelf_z(k):
    return 2.0 + 0.4 * k


def build(m):
    L, D = m.size  # 38 x 34

    # =====================================================================
    # EAST HILL (P02a-d, front-right) and the glade floor (plinth, z = 0)
    # =====================================================================
    # (the hill starts 1 m in from the front edge so the classic floor-to-hilltop ladder stands on the map)
    m.terrace("P02a_HillStep", geo.rounded_rect(20.4, 1.0, 23.6, 8.0, 1.0), top=0.4, bottom=-0.5)
    m.terrace("P02b_HillStep", geo.rounded_rect(23.0, 1.0, 26.1, 8.6, 1.0), top=0.8, bottom=-0.5)
    m.terrace("P02c_HillStep", geo.rounded_rect(25.5, 1.0, 28.6, 9.2, 1.0), top=1.2, bottom=-0.5)
    m.terrace("P02d_HillTop", [(28.0, 1.0), (38.6, 1.0), (38.6, 10.2), (28.0, 9.8)], top=Z_P01, bottom=-0.5)
    # classic ladder 1142 (floor -> hilltop), kept west of the arrival trail corridor
    m.ladder("Ladder_Hill", 28.8, 0.7, 0.0, Z_P01, facing=90)

    # ARRIVAL: the trail from the Field arrives over the front edge onto a high grassy rock on the hilltop
    # (out00); a plank boardwalk on posts carries the player straight onto the classic arrival ledge P14,
    # so you arrive high and look down into the glade. A ladder drops from the rock to the hilltop.
    m.terrace("ArrivalRock", geo.rounded_rect(31.4, -0.8, 36.6, 3.8, 1.0), top=Z_P14, bottom=-0.5)
    m.deck("ArrivalBoardwalk", geo.rect(32.6, 3.0, 35.4, 11.4), top=Z_P14 + 0.03, post_bottom=Z_P01 - 0.05)
    for side, x in (("W", 32.66), ("E", 35.34)):
        m.rail(f"ArrivalBoardwalk_Rail{side}", [(x, 3.9), (x, 10.5)], Z_P14 + 0.03, closed=False)
    m.ladder("Ladder_Rock", 31.1, 2.0, Z_P01, Z_P14, facing=0)

    # =====================================================================
    # ARRIVAL LEDGE P14 (out00), stepping stumps, the high ridge P24
    # =====================================================================
    m.terrace("P14_Arrival", [(29.2, 10.8), (38.6, 10.6), (38.6, 23.4), (29.0, 23.4)], top=Z_P14, bottom=-0.5)
    m.terrace("P12_Stump", geo.ellipse(27.2, 17.2, 2.2, 1.8, 18), top=4.0, bottom=1.0)
    m.terrace("P10_Stump", geo.ellipse(24.6, 15.0, 1.9, 1.7, 18), top=3.6, bottom=0.6)
    m.terrace("P08_Stump", geo.ellipse(26.8, 12.7, 1.9, 1.7, 18), top=3.2, bottom=0.6)
    # grassy saddle from hill step P02c up to the P08 stump (no plank stairs in the forest)
    m.ramp("R_Hill_P08", (27.0, 4.2, 1.2), (27.0, 11.6, 3.2), 2.6, top_mat=None)
    # classic rope 853 survives as a shortcut from the glade floor to P08
    m.ladder("Rope_Hill_P08", 25.4, 10.9, m.ground_z(25.4, 10.4), 3.2, facing=90, kind="rope")

    m.terrace("P24_Ridge", [(16.8, 22.4), (34.4, 23.0), (34.8, 34.6), (16.4, 34.6), (16.4, 28.6), (16.8, 26.0)],
              top=Z_P24, bottom=-0.5)
    m.stairs("St_P14_P24", (33.0, 15.4, Z_P14), (33.0, 23.1, Z_P24), 2.6, step_h=0.2)
    # the three classic ropes hanging off the ridge like curtains (x 811 / 890 / 981)
    m.ladder("Vine_P24_A", 25.8, 22.1, 0.0, Z_P24, facing=90, kind="rope")
    m.ladder("Vine_P24_B", 27.6, 22.15, 0.0, Z_P24, facing=90, kind="rope")
    m.ladder("Vine_P24_C", 30.4, 22.3, Z_P14, Z_P24, facing=90, kind="rope")

    # =====================================================================
    # THE GIANT TREE: start ledge P01, spiral of shelves, crown P25
    # =====================================================================
    m.place("X1000001_GiantTrunk_White", TREE_C[0], TREE_C[1], rot=0)
    m.terrace("P25_Crown", geo.ellipse(TREE_C[0], TREE_C[1], 2.3, 2.3, 20), top=CROWN_Z, bottom=CROWN_Z - 0.7,
              resample_step=0.8, wobble_amt=0.12)
    m.terrace("P01_StartLedge", geo.rounded_rect(13.6, 10.4, 20.2, 16.4, 1.8), top=Z_P01, bottom=-0.5)
    m.ramp("R_Floor_P01", (17.2, 5.0, 0.0), (17.2, 11.0, Z_P01), 2.6, top_mat=None)
    m.ladder("Rope_P01", 14.8, 10.1, 0.0, Z_P01, facing=90, kind="rope")
    wide = {3: 6.2, 5: 6.0, 10: 6.6}   # junction shelves reach out to the west/back branch ledges
    for k in range(14):
        a = shelf_angle(k)
        z = shelf_z(k)
        r1 = wide.get(k, 5.2)
        # (inner edge follows the tapered trunk so no slot opens between bark and shelf)
        m.terrace(f"Shelf_{k:02d}", _sector(a, 16.5, min(SHELF_R0, trunk_r(z) - 0.15), r1), top=z,
                  bottom=z - 0.55, resample_step=0.6, wobble_amt=0.1, smooth_iters=1)
        # bracket fungus peeking out under the shelf's outer rim (a second, smaller one on alternate shelves);
        # the junction shelves merge into their branch ledges, so they get none (it would be buried)
        if k in wide:
            continue
        fx, fy = _polar(a, r1 - 0.3)
        m.place("X1000001_BracketFungus", fx, fy, rot=a + 90, z=z - 0.6, scale=0.8 + (k % 3) * 0.1)
        if k % 2 == 0:
            fx, fy = _polar(a - 8.0, r1 - 0.5)
            m.place("X1000001_BracketFungus", fx, fy, rot=a - 8.0 + 90, z=z - 0.85, scale=0.6)

    # west branch ledges (dead ends): mid (P06), upper-mid (P11) and high (P19), stepping back as they rise
    m.terrace("P06_WestLedge", geo.rounded_rect(-1.0, 10.4, 8.6, 17.0, 1.6), top=3.2, bottom=-0.5)
    m.terrace("P11_WestLedge", geo.rounded_rect(-1.0, 17.8, 7.0, 25.2, 1.6), top=4.0, bottom=-0.5)
    m.terrace("P19_HighLedge", [(-1.0, 26.2), (11.0, 26.2), (12.6, 25.6), (15.2, 26.8), (17.2, 28.4),
                                (17.2, 34.6), (-1.0, 34.6)], top=6.0, bottom=-0.5)

    # =====================================================================
    # DRESSING
    # =====================================================================
    m.place("Bush_A", TREE_C[0] - 0.6, TREE_C[1] + 1.5)
    m.place("Bush_C", TREE_C[0] - 0.4, TREE_C[1] - 1.4)
    # red-berry bushes flanking the arrival (where the boardwalk lands on P14)
    m.place("X1000001_Bush_RedBerry", 36.4, 11.9, rot=20)
    m.place("X1000001_Bush_RedBerry", 31.5, 11.8, rot=-30)
    trees = [
        # P24 ridge: twin yellow + twin orange, plus a green one
        ("Tree_Birch_Yellow", 19.6, 31.6, 0.7), ("Tree_Birch_Yellow", 22.0, 33.0, 0.7),
        ("Tree_Birch_Orange", 26.4, 31.8, 1.0), ("Tree_Birch_Orange", 28.8, 33.2, 0.9),
        ("Tree_Birch_Teal", 33.4, 30.6, 0.9),
        # P19 / P11 / P06 west ledges
        ("Tree_Birch_Teal", 1.4, 31.6, 0.7), ("Tree_Birch_Orange", 5.6, 33.0, 0.9),
        ("Tree_Birch_Lime", 0.6, 22.4, 0.85), ("Tree_Birch_Teal", 1.2, 12.4, 0.9),
        # P14 arrival ledge: the green tree by the ridge
        ("Tree_Birch_Teal", 30.6, 20.8, 0.85),
        # P02d hilltop: the twin birches (west of the arrival rock and boardwalk)
        ("Tree_Birch_Yellow", 29.2, 8.8, 0.75), ("Tree_Birch_Orange", 30.7, 7.3, 0.7),
        # glade floor ring: a stand of autumn white-trunk birches along the west edge and the back of the
        # floor (smaller toward the front edge so the front band stays low)
        ("Tree_Birch_Orange", 0.4, 6.0, 0.95), ("Tree_Birch_Yellow", 0.8, 1.4, 0.8),
        ("Tree_Birch_Lime", 20.6, 10.4, 0.85),
        ("Tree_Birch_Orange", 2.8, 8.6, 0.85), ("Tree_Birch_Yellow", 5.8, 8.9, 0.8),
        ("Tree_Birch_Orange", 9.2, 8.2, 0.8), ("Tree_Birch_Yellow", 12.6, 8.9, 0.75),
        ("Tree_Birch_Yellow", 3.4, 1.8, 0.6), ("Tree_Birch_Orange", 11.6, 1.6, 0.6),
        ("Tree_Birch_Yellow", 15.0, 1.2, 0.55),
        # P24 ridge back edge
        ("Tree_Birch_Orange", 17.6, 33.4, 0.85), ("Tree_Birch_Orange", 24.4, 33.8, 0.9),
        ("Tree_Birch_Yellow", 31.4, 33.6, 0.85),
    ]
    for i, (a, x, y, s) in enumerate(trees):
        m.place(a, x, y, rot=i * 47, scale=s)
    for i, (a, x, y) in enumerate([("Bush_B", 4.4, 4.4), ("Bush_A", 9.6, 2.6), ("Bush_B", 14.6, 6.8),
                                   ("Bush_C", 19.2, 2.0), ("Bush_A", 22.0, 12.6), ("Bush_B", 1.2, 10.6),
                                   ("Bush_A", 5.4, 17.0), ("Bush_C", 3.2, 23.6), ("Bush_B", 10.6, 32.8),
                                   ("Bush_C", 28.6, 3.0), ("Bush_A", 24.2, 29.0),
                                   ("Bush_Flowering_A", 31.2, 29.4), ("Bush_C", 8.0, 33.4),
                                   # low bushes at the foot of the ridge face (keep the three ropes visible)
                                   ("Bush_A", 20.4, 19.0), ("Bush_B", 23.0, 20.6)]):
        m.place(a, x, y, rot=i * 53)
    for (a, x, y, r) in [("Rock_A", 7.4, 7.0, 20), ("Rock_C", 15.6, 3.2, 0), ("Stump_A", 11.2, 9.0, 0),
                         ("Log_A", 6.4, 1.0, 12), ("Rock_B", 24.0, 10.0, 40), ("Mushroom_Cluster_A", 9.0, 12.8, 30),
                         ("Mushroom_Red_S", 18.4, 7.4, 0), ("Mushroom_Orange_S", 2.6, 19.4, 0),
                         ("Rock_C", 36.6, 21.6, 0),
                         # west ledges and the high ledge
                         ("Mushroom_Cluster_A", 4.6, 12.4, 10), ("Flower_Bed_Large", 1.6, 15.4, 0),
                         ("Bush_Flowering_A", 5.6, 23.4, 0), ("Stump_A", 1.4, 19.0, 0),
                         ("Log_A", 6.8, 28.0, 10), ("Mushroom_Cluster_A", 12.6, 31.6, -30),
                         ("Flower_Bed_Large", 3.4, 27.6, 0),
                         # ridge top and arrival ledge
                         ("Mushroom_Cluster_A", 18.2, 26.2, 0), ("Rock_A", 31.6, 32.0, 0),
                         ("Flower_Patch_A", 29.6, 24.8, 0), ("Stump_A", 21.2, 28.8, 0),
                         ("Mushroom_Orange_S", 30.2, 11.4, 0), ("Mushroom_Yellow_S", 29.8, 12.2, 0),
                         # hilltop
                         ("Mushroom_Cluster_A", 29.0, 7.0, 20)]:
        m.place(a, x, y, rot=r)
    for (x, y, z) in [(4.0, 10.1, 1.6), (6.6, 10.2, 2.4), (2.4, 17.5, 2.6), (5.2, 17.6, 1.4), (19.4, 22.1, 3.0),
                      (23.0, 22.3, 5.0), (37.2, 10.5, 2.8), (8.6, 25.9, 3.4), (3.6, 25.9, 4.6)]:
        m.place("Rock_Cliff_Stone", x, y, z=z, scale=1.2)
    for x in (18.6, 21.8, 24.2):
        m.place("Vine_Hanging_A", x, 22.1, z=Z_P24 - 0.1, scale=(1, 1, 1.5))
    m.place("Butterfly", 8.0, 5.0)
    m.place("Butterfly", 33.0, 14.0)
    m.scatter(["Grass_Tuft_A", "Flower_Patch_A", "Flower_Patch_B"], geo.rect(0, 0, 38, 34), 34, seed=7, min_dist=1.6,
              avoid=[geo.rect(0, 3.4, 21, 6.6), geo.rect(15.8, 4.2, 18.6, 11.6), geo.rect(30.8, -1.0, 37.0, 12.4),
                     geo.rect(25.6, 4.0, 28.4, 12.0)])

    # =====================================================================
    # GAMEPLAY
    # =====================================================================
    m.edge_portal("out00")
    m.player(17.0, 13.7, rot=-10)
    m.player_spawn(33.4, 4.6, rot=180, note="sp x 947: west of and above out00, on the arrival rock")
    m.mobs("Orange Mushroom", geo.rect(2, 1, 20, 9.5), 2, seed=1, z_band=(-0.1, 0.2))
    m.mobs("Shroom", geo.rect(2, 1, 20, 9.5), 2, seed=2, z_band=(-0.1, 0.2))
    m.mobs("Snail", geo.rect(1, 11, 8, 16), 1, seed=3, z_band=(3.0, 3.4))
    m.mobs("Shroom", geo.rect(0, 18.5, 6.5, 24.5), 1, seed=4, z_band=(3.8, 4.2))
    m.mobs("Red Snail", geo.rect(0, 27.5, 11, 33.5), 1, seed=5, z_band=(5.8, 6.2))
    m.mobs("Blue Snail", geo.rect(17, 24.5, 33, 30), 1, seed=6, z_band=(7.0, 7.4))
    m.mobs("Snail", geo.rect(17, 24.5, 33, 30), 1, seed=7, z_band=(7.0, 7.4))
    m.mobs("Red Snail", geo.rect(28.2, 3.6, 32.2, 9.6), 1, seed=8, z_band=(1.4, 1.8))
    # (classic keeps the arrival ledge P14 nearly empty; the ridge P24 carries most spawns)
    m.mobs("Shroom", geo.rect(22, 25, 32, 30), 1, seed=9, z_band=(7.0, 7.4))

    # --- routes (walkable only) ---
    spiral = [_polar(shelf_angle(k), SHELF_RM) for k in range(14)]
    # (passes in front of the ridge stairs' foot instead of stepping off their side)
    m.route("Arrival_to_Floor", [(34.0, 1.4), (34.0, 3.2), (34.0, 7.0), (34.0, 11.8), (31.0, 14.4), (29.6, 16.0),
                                 (27.4, 17.2), (24.8, 15.0), (26.6, 12.6), (27.0, 11.6), (27.0, 4.8), (24.6, 4.6),
                                 (22.0, 4.6), (18.0, 4.8), (6.0, 5.0)])
    m.route("Floor_to_Crown", [(17.2, 3.6), (17.2, 5.2), (17.2, 11.2), (16.4, 14.0)] + spiral[:14] +
            [_polar(shelf_angle(13), 1.4)])
    m.route("To_P06", [spiral[3], (6.4, 15.0), (3.0, 13.6)])
    m.route("To_P11", [spiral[5], (5.4, 20.8), (2.4, 21.6)])
    m.route("To_P19", [spiral[10], _polar(66.0, 6.0), (11.0, 29.0), (6.0, 30.0), (2.4, 29.6)])
    m.route("Crown_to_Ridge_to_Arrival", [spiral[13], (18.2, 23.8), (22.0, 26.4), (28.0, 27.0), (33.0, 26.0),
                                          (33.0, 23.6), (33.0, 15.0), (34.0, 11.8)])
    # (no route runs under the boardwalk: the hilltop is walked west of it, and the rock is climbed by ladder)
    m.route("HillTop", [(26.8, 4.6), (28.6, 5.0), (30.4, 5.2)])
    m.route("Hilltop_to_Rock", [(30.4, 5.2), (30.6, 2.8), (31.0, 2.0), (33.0, 1.6), (34.0, 1.4)])
