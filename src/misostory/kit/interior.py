"""Shared interior kit: cutaway room shells, timber framing, plank floors, walkable blocks, 3D sign text,
interior lights, and the stone-capped shop frame (posts, lashed eaves, plank door).

Used by the interior maps (Amherst Weapon Store 1010001, Department Store 1010003, Mushroom Town house
20001, Southperry Armor Store 60001). Every helper takes the map context ``m`` and works in map-local
coordinates: (x, y, z) in meters, yaw in degrees, front toward local -y. The interior stage is laid out
in ``ROOM``: the back (y1) and left (x0) walls are tall, the camera-side walls stay knee-high.
"""

import math

import bpy

from ..geo import MeshBuilder
from . import asset

ROOM = (0.3, 0.3, 15.7, 11.7)   # x0, y0, x1, y1 (wall centre lines) used by every interior
WALL_T = 0.5                    # tall-wall thickness (encloses m.room's 0.35 m knee wall)
SHOP_H = 6.6                    # shop wall height (posts / eaves are modelled for this)
BAND = "M_Flat_sea_dk"          # dark-blue iron band / cord colour


def lbox(mb, m, size, c, yaw=0.0, mat="M_Wood", bevel=0.0, tilt=(0.0, 0.0)):
    """Box centred at local c=(x, y, z) with a local yaw (deg)."""
    mb.box(size, loc=m.w(*c), rot=(tilt[0], tilt[1], m.wyaw(yaw)), mat=mat, bevel=bevel, segs=1)


def lcyl(mb, m, r, h, c, mat="M_Wood", verts=12, r2=None, rot=(0.0, 0.0, 0.0)):
    """Cylinder whose base centre is at local c, optional tilt + local yaw."""
    mb.cyl(r, h, loc=m.w(*c), rot=(rot[0], rot[1], m.wyaw(rot[2])), mat=mat, verts=verts, r2=r2)


def wall_rects(length, height, holes):
    """Split a wall (0..length x 0..height) around rectangular holes (s0, s1, z0, z1)."""
    xs = sorted({0.0, length} | {min(length, max(0.0, h[0])) for h in holes}
                | {min(length, max(0.0, h[1])) for h in holes})
    out = []
    for a, b in zip(xs, xs[1:]):
        if b - a < 1e-3:
            continue
        mid = (a + b) / 2
        z = 0.0
        for z0, z1 in sorted((h[2], h[3]) for h in holes if h[0] < mid < h[1]):
            if z0 > z + 1e-3:
                out.append((a, b, z, z0))
            z = max(z, z1)
        if z < height - 1e-3:
            out.append((a, b, z, height))
    return out


RUG_Z = 0.014                   # rugs sit just above the plank overlay (top at PLANK_TOP)
PLANK_TOP = 0.011
PLANK_TONES = ("M_Flat_plank", "M_Flat_wood_lt", "M_Flat_plank", "M_Flat_wood_lt", "M_Flat_wood")


def plank_floor(m, x0, y0, x1, y1, z=0.0, board=0.45, gap=0.035, seed=0, name="Floor_Planks", coll=None):
    """Visual-only floorboards (flat colours) laid along +x over a flat floor whose top is at local z.

    The floor slab underneath should be dark (M_Flat_wood_dk) so the gaps read as seams. The boards
    float a few mm above the slab (no z-fighting) and are not added to the ground set.
    """
    import random
    rng = random.Random(f"{m.slug}-{name}-{seed}")
    mb = MeshBuilder()
    zb, zt = z + 0.003, z + PLANK_TOP
    ny = max(1, int(math.ceil((y1 - y0) / board - 1e-6)))
    for i in range(ny):
        ya, yb = y0 + i * board, min(y1, y0 + (i + 1) * board)
        if yb - ya < gap * 2:
            continue
        x = x0 - rng.uniform(0.0, 2.2)          # staggered butt joints
        while x < x1 - 1e-3:
            ln = rng.uniform(1.7, 3.6)
            a, b = max(x0, x), min(x1, x + ln)
            if b - a > gap * 2:
                lbox(mb, m, (b - a - gap, yb - ya - gap, zt - zb), ((a + b) / 2, (ya + yb) / 2, (zb + zt) / 2), 0,
                     rng.choice(PLANK_TONES))
            x += ln
    obj = mb.build(f"{m.slug}_{name}", coll or m.col_arch, smooth=False)
    obj.visible_shadow = False
    return obj


def cut_room(m, height, wall_mat, floor_mat="M_Flat_wood_dk", trim_mat="M_Wood_Dark", knee=0.9, knee_mat=None,
             base_mat=None, base_h=0.0, back_holes=(), left_holes=(), top_trim=True, room=ROOM, planks=True):
    """Cutaway interior shell.

    ``m.room`` gives the walkable floor and a knee-high frame on the back, left and right sides
    (the right/x1 side is the camera-side wall for interiors, so it must stay low). Tall back (y1)
    and left (x0) walls are added here, thick enough to swallow the knee wall. Holes are
    (s0, s1, z0, z1) with s = local x for the back wall and local y for the left wall; keep them
    above the knee height (doors are closed door props on the wall face). ``planks`` lays the
    visual floorboard overlay (see plank_floor) over the dark floor slab; rugs go at z=RUG_Z.
    """
    x0, y0, x1, y1 = room
    T = WALL_T
    floor = m.room(x0, y0, x1, y1, wall_h=knee, floor_mat=floor_mat, wall_mat=knee_mat or wall_mat,
                   trim_mat=trim_mat, beams=False)
    if planks:
        plank_floor(m, x0 + 0.15, y0 + 0.07, x1 - 0.1, y1 - 0.15)
    mb = MeshBuilder()
    sb0 = x0 - T / 2
    for (a, b, z0, z1) in wall_rects(x1 + T / 2 - sb0, height, [(h[0] - sb0, h[1] - sb0, h[2], h[3])
                                                               for h in back_holes]):
        lbox(mb, m, (b - a, T, z1 - z0), (sb0 + (a + b) / 2, y1, (z0 + z1) / 2), 0, wall_mat)
    for (a, b, z0, z1) in wall_rects(y1 - T / 2 - y0, height, [(h[0] - y0, h[1] - y0, h[2], h[3])
                                                               for h in left_holes]):
        lbox(mb, m, (b - a, T, z1 - z0), (x0, y0 + (a + b) / 2, (z0 + z1) / 2), 90, wall_mat)
    if base_mat and base_h > 0:
        lbox(mb, m, (x1 - x0 - T / 2, 0.08, base_h), ((x0 + x1) / 2 + T / 4, y1 - T / 2 - 0.04, base_h / 2), 0,
             base_mat)
        lbox(mb, m, (y1 - y0 - T / 2, 0.08, base_h), (x0 + T / 2 + 0.04, (y0 + y1 - T / 2) / 2, base_h / 2), 90,
             base_mat)
    if top_trim:
        lbox(mb, m, (x1 - x0 + T + 0.2, T + 0.16, 0.26), ((x0 + x1) / 2, y1, height - 0.1), 0, trim_mat, bevel=0.03)
        lbox(mb, m, (y1 - y0 + 0.1, T + 0.16, 0.26), (x0, (y0 + y1) / 2, height - 0.1), 90, trim_mat, bevel=0.03)
    # chunky cut ends on the camera side so the section reads as a dollhouse cut
    lbox(mb, m, (T + 0.16, 0.2, height), (x0, y0 + 0.02, height / 2), 0, trim_mat, bevel=0.03)
    lbox(mb, m, (0.2, T + 0.16, height), (x1 + T / 2 - 0.02, y1, height / 2), 0, trim_mat, bevel=0.03)
    walls = mb.build(f"{m.slug}_Shell_Walls", m.col_arch, smooth=False)
    walls.visible_shadow = False
    return floor, walls


def solid(m, name, boxes, mat="M_Plank", walkable=True, coll=None, bevel=0.03, shadow=True):
    """Boxes given as (x0, y0, x1, y1, z0, z1) in local coords -> one mesh (walkable by default)."""
    mb = MeshBuilder()
    for b in boxes:
        bx0, by0, bx1, by1, bz0, bz1 = b[:6]
        mat_b = b[6] if len(b) > 6 else mat
        lbox(mb, m, (bx1 - bx0, by1 - by0, bz1 - bz0), ((bx0 + bx1) / 2, (by0 + by1) / 2, (bz0 + bz1) / 2), 0,
             mat_b, bevel=bevel)
    obj = mb.build(f"{m.slug}_{name}", coll or m.col_terrain, smooth=False)
    obj.visible_shadow = shadow
    if walkable:
        m.add_ground(obj)
    return obj


def crate_block(m, name, x0, y0, x1, y1, top, seed=0, z0=0.0):
    """A walkable stack of crates standing on the floor or on a surface at z0 (hidden collision box +
    kit Crate visuals)."""
    col = solid(m, name, [(x0, y0, x1, y1, z0 - 0.05, top)], bevel=0.0)
    col.hide_render = True
    w, d = x1 - x0, y1 - y0
    layers = []
    z = z0
    while top - z > 0.05:
        h = 0.8 if top - z >= 0.79 else top - z
        layers.append((z, h))
        z += h
    for k, (z, h) in enumerate(layers):
        jig = ((seed * 7 + k * 3) % 5 - 2) * 1.5
        m.place("Crate", (x0 + x1) / 2, (y0 + y1) / 2, rot=jig, z=z, scale=(w / 0.95, d / 0.95, h / 0.9))
    return col


def banded_beam(m, name, p0, p1, width, height, z_top, walkable=False, mat="M_Wood", band=BAND, spacing=1.3,
                coll=None):
    """Heavy timber beam between local points p0 -> p1 (xy), bound with dark-blue iron bands."""
    (ax, ay), (bx, by) = p0, p1
    L = math.hypot(bx - ax, by - ay)
    yaw = math.degrees(math.atan2(by - ay, bx - ax))
    mb = MeshBuilder()
    zc = z_top - height / 2
    lbox(mb, m, (L, width, height), ((ax + bx) / 2, (ay + by) / 2, zc), yaw, mat, bevel=0.05)
    n = max(1, int(L // spacing))
    for k in range(n):
        t = (k + 0.5) / n
        px, py = ax + (bx - ax) * t, ay + (by - ay) * t
        lbox(mb, m, (0.16, width + 0.06, height + 0.05), (px, py, zc), yaw, band, bevel=0.015)
        for s in (-1, 1):  # rivets
            ox = -math.sin(math.radians(yaw)) * s * (width / 2 + 0.03)
            oy = math.cos(math.radians(yaw)) * s * (width / 2 + 0.03)
            lbox(mb, m, (0.07, 0.05, 0.07), (px + ox, py + oy, zc), yaw, "M_Metal")
    obj = mb.build(f"{m.slug}_{name}", coll or (m.col_terrain if walkable else m.col_arch), smooth=False)
    obj.visible_shadow = False   # high beams would only drop dark blobs across the shop floor
    if walkable:
        m.add_ground(obj)
    return obj


def sign_text(m, text, x, y, z, rot=0.0, size=0.4, mat="M_Flat_cloth_white", extrude=0.03, name="Sign",
              as_mesh=True, outline=0.006):
    """Upright 3D text facing local -y at rot=0 (rot = local yaw).

    With ``as_mesh`` the FONT curve is converted to a mesh object (export-safe) and given a thin
    ink outline like the kit assets; if the conversion fails the curve object is kept.
    """
    cu = bpy.data.curves.new(f"{m.slug}_{name}_Text", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = extrude
    from .. import materials as MAT
    cu.materials.append(MAT.get(mat))
    ob = bpy.data.objects.new(f"{m.slug}_{name}_Text", cu)
    ob.location = m.w(x, y, z)
    ob.rotation_euler = (math.radians(90), 0.0, math.radians(m.wyaw(rot)))
    m.col_props.objects.link(ob)
    if not as_mesh:
        return ob
    try:
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        if not me.polygons:
            raise RuntimeError("empty text mesh")
        mo = bpy.data.objects.new(f"{m.slug}_{name}_TextMesh", me)
        mo.location = ob.location.copy()
        mo.rotation_euler = ob.rotation_euler.copy()
        m.col_props.objects.link(mo)
        if outline > 0:
            from . import add_outline
            add_outline(mo, outline)
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        return mo
    except Exception as exc:  # keep the curve text if the conversion is unavailable
        print(f"[{m.slug}] sign_text mesh conversion failed: {exc}")
        stray = bpy.data.objects.get(f"{m.slug}_{name}_TextMesh")
        if stray is not None:
            bpy.data.objects.remove(stray)
        return ob


def room_light(m, energy=2600.0, at=(12.5, 1.0, 9.5), target=(5.0, 9.0, 0.0), size=11.0, color=(1.0, 0.88, 0.72),
               name="Fill"):
    """Soft area fill: interiors sit on a remote stage and their back walls face away from the sun."""
    ld = bpy.data.lights.new(f"{m.slug}_{name}", "AREA")
    ld.energy = energy
    ld.size = size
    ld.color = color
    lo = bpy.data.objects.new(f"{m.slug}_{name}", ld)
    m.col_props.objects.link(lo)
    lo.location = m.w(*at)
    d = (m.w(*target) - lo.location).normalized()
    lo.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return lo


def point_light(m, x, y, z, energy=60.0, color=(1.0, 0.7, 0.4), radius=0.3, name="Lamp"):
    ld = bpy.data.lights.new(f"{m.slug}_{name}", "POINT")
    ld.energy = energy
    ld.color = color
    ld.shadow_soft_size = radius
    lo = bpy.data.objects.new(f"{m.slug}_{name}", ld)
    m.col_props.objects.link(lo)
    lo.location = m.w(x, y, z)
    return lo




# ---------------------------------------------------------------------------
# shop frame assets (stone-capped posts, lashed-plank eaves, plank door)
# ---------------------------------------------------------------------------

@asset("Post_StoneCap", "Architecture", footprint=0.8, tags=("interior",))
def _post_stonecap(coll):
    """6.6 m timber post with grey stone caps (base, mid, top) and a curved corbel toward -Y."""
    mb = MeshBuilder()
    H = SHOP_H
    mb.box((0.42, 0.42, H), loc=(0, 0, H / 2), mat="M_Wood", bevel=0.04, segs=1)
    for z0, h, w in ((0.0, 0.55, 0.62), (2.55, 0.42, 0.58), (H - 0.95, 0.5, 0.66)):
        mb.box((w, w, h), loc=(0, 0, z0 + h / 2), mat="M_Flat_stone_wall", bevel=0.07, segs=2)
    # corbel bracket under the wall plate (chunky quarter-round made of stacked blocks)
    for k in range(4):
        d = 0.25 + k * 0.18
        mb.box((0.34, d, 0.2), loc=(0, -d / 2 - 0.12, H - 1.15 - (3 - k) * 0.2), mat="M_Wood", bevel=0.04, segs=1)
    mb.box((0.62, 1.15, 0.36), loc=(0, -0.45, H - 0.42), mat="M_Flat_stone_wall", bevel=0.07, segs=2)
    ob = mb.build("Post_StoneCap", coll, smooth=False)
    ob.visible_shadow = False   # wall posts: their corbel blobs otherwise stain the floor


@asset("Eave_Lashed_4m", "Architecture", footprint=4.0, tags=("interior",))
def _eave(coll):
    """4 m run of the roof edge seen from inside: lashed planks rising toward -Y, dark-blue cords.

    Origin at the left end of the wall top; runs along +X; the planks lean into the room (-Y).
    """
    mb = MeshBuilder()
    a = math.radians(26)
    mb.box((4.0, 0.55, 0.45), loc=(2.0, -0.05, 0.22), mat="M_Wood_Dark", bevel=0.05, segs=1)  # wall plate
    for i in range(9):
        x = 0.22 + i * 0.445
        ln = 1.75 + (0.25 if i % 3 == 1 else 0.0) - (0.15 if i % 3 == 2 else 0.0)
        cy, cz = -ln / 2 * math.cos(a), 0.42 + ln / 2 * math.sin(a)
        mb.box((0.41, ln, 0.17), loc=(x, cy, cz), rot=(-26, 0, 0),
               mat="M_Wood" if i % 2 else "M_Plank", bevel=0.04, segs=1)
    for t in (0.45, 1.25):
        cy, cz = -t * math.cos(a), 0.42 + t * math.sin(a) + 0.11
        mb.box((4.02, 0.12, 0.07), loc=(2.0, cy, cz), rot=(-26, 0, 0), mat=BAND)
    ob = mb.build("Eave_Lashed_4m", coll, smooth=False)
    ob.visible_shadow = False


def shop_frame(m, height=SHOP_H, posts_back=(), posts_left=(), eaves=True):
    """Stone-capped posts against the back/left walls + lashed-plank eaves along both wall tops."""
    x0, y0, x1, y1 = ROOM
    inner_back = y1 - WALL_T / 2 - 0.21
    inner_left = x0 + WALL_T / 2 + 0.21
    for x in posts_back:
        m.place("Post_StoneCap", x, inner_back, rot=0, z=0.0)
    for y in posts_left:
        m.place("Post_StoneCap", inner_left, y, rot=90, z=0.0)
    m.place("Post_StoneCap", inner_left, inner_back, rot=45, z=0.0)
    if eaves:
        x = x0
        while x < x1 - 0.5:
            sx = min(1.0, (x1 + 0.2 - x) / 4.0)
            m.place("Eave_Lashed_4m", x, y1 - WALL_T / 2, rot=0, z=height, scale=(sx, 1, 1))
            x += 4.0
        y = y0
        y_end = y1 - WALL_T / 2 - 1.55  # stop before the back eave's planks (clean corner)
        while y < y_end - 0.5:
            sy = min(1.0, (y_end - y) / 4.0)
            m.place("Eave_Lashed_4m", x0 + WALL_T / 2, y, rot=90, z=height, scale=(sy, 1, 1))
            y += 4.0


@asset("Door_Plank", "Architecture", footprint=1.6, tags=("interior", "door"))
def _door_plank(coll):
    """Closed round-topped plank double door in a stone frame, modelled flat against a wall (faces -Y)."""
    mb = MeshBuilder()
    w, h = 1.5, 2.15
    mb.box((w + 0.5, 0.18, h + 0.3), loc=(0, 0.05, (h + 0.3) / 2), mat="M_Flat_stone_wall", bevel=0.06, segs=1)
    mb.cyl((w + 0.5) / 2, 0.18, loc=(0, 0.14, h + 0.3), rot=(90, 0, 0), mat="M_Flat_stone_wall", verts=16)
    mb.box((w, 0.16, h), loc=(0, -0.04, h / 2), mat="M_Door", bevel=0.03, segs=1)
    mb.cyl(w / 2, 0.16, loc=(0, 0.04, h), rot=(90, 0, 0), mat="M_Door", verts=16)
    mb.box((0.05, 0.2, h + 0.6), loc=(0, -0.05, (h + 0.6) / 2), mat="M_Wood_Dark")
    for z in (0.45, 1.6):
        for s in (-1, 1):
            mb.box((0.55, 0.2, 0.09), loc=(s * 0.42, -0.06, z), mat="M_Flat_rock_dk")
    for s in (-1, 1):
        mb.torus(0.09, 0.025, loc=(s * 0.17, -0.16, 1.05), rot=(90, 0, 0), mat="M_Gold", u=10, v=4)
    mb.box((w + 0.9, 0.7, 0.14), loc=(0, -0.3, 0.07), mat="M_Flat_stone_wall", bevel=0.04, segs=1)
    mb.build("Door_Plank", coll, smooth=True, sharp_angle=40)
