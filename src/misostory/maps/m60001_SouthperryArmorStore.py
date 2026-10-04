"""Southperry Armor Store (60001) - "Pan's whitewashed armory by the harbour".

Classic (GMS v8) structure, from docs/research/maps/60001_SouthperryArmorStore_60001.md:
  one 800 x 600 room (same footholds as the Amherst Weapon Store): Pan sells from a booth window
  cut into a kiosk on the west side (standing on a raised stand); a stepped heap of wares on the
  east side (crates, barrels, armor) climbs to a wide shelf and a top shelf; a rope hangs from a
  ceiling beam over the shelf. The partial render shows timber ceiling beams bound with blue
  iron bands and a wooden post with grey stone caps. Exit out00 on the floor, centre-left.

3D translation: the shared shop shell (kit.interior) re-dressed as a harbour armory so it does not
read as the Amherst Weapon Store: whitewashed walls with a blue wainscot, a sandstone flag floor framed
by blue-and-white tiles, an off-centre rope-bordered compass rug, a fishing-net and lobster-pot corner
by the door, a big arched sea-view window whose daylight falls in a soft shaft onto the floor, and a
cargo net slung under the blue-banded ceiling beam. Pan's kiosk stands against the west wall facing
into the room; the ware heap is a staircase of real crates, wares boxes and blue trunks (their plank
lids are the walkable steps) rising along the east wall to a wide shelf in the back-right corner; a
rope climbs from the shelf to the beam. One plumed suit of armor stands by the shield rack; the other
goods vary (a tabard mannequin, a chainmail stand, a boots-and-gloves rack).
"""

import math

import bpy

from misostory import collision_tags as CT
from misostory.geo import MeshBuilder
from misostory.kit import add_outline, asset
from misostory.kit.interior import (PLANK_TOP, ROOM, RUG_Z, SHOP_H, WALL_T, banded_beam, cut_room, lbox, plank_floor,
                                    point_light, room_light, shop_frame, solid)

MAP_ID = 60001
GAMEPLAY_FOCUS = (8.0, 7.6)
GAMEPLAY_SCALE = 20.0

SHELF_Z = 2.4
BEAM_Z = 5.0


# ---------------------------------------------------------------------------
# local assets
# ---------------------------------------------------------------------------

def _shield(mb, loc, kind, r=0.38, face_y=-1.0):
    """A shield lying flat against a wall (faces -Y). kind: kite | round | cross."""
    x, y, z = loc
    if kind == "round":
        mb.cyl(r, 0.08, loc=(x, y, z), rot=(90, 0, 0), mat="M_Flat_cloth_white", verts=16)
        mb.cyl(r * 0.78, 0.1, loc=(x, y - 0.01, z), rot=(90, 0, 0), mat="M_Flat_roof_blue", verts=16)
        mb.cyl(r * 0.3, 0.14, loc=(x, y - 0.02, z), rot=(90, 0, 0), mat="M_Gold", verts=10)
    elif kind == "cross":
        pts = [(-r, r * 0.9), (r, r * 0.9), (r, 0.0), (0.0, -r * 1.25), (-r, 0.0)]
        mb.prism(pts, 0.0, 0.09, loc=(x, y + 0.05, z), rot=(90, 0, 0), mat="M_Flat_roof_green", bevel=0.02, segs=1)
        mb.box((r * 0.32, 0.06, r * 1.5), loc=(x, y - 0.06, z), mat="M_Flat_cloth_white")
        mb.box((r * 1.2, 0.06, r * 0.32), loc=(x, y - 0.06, z + r * 0.15), mat="M_Flat_cloth_white")
    else:  # kite
        pts = [(-r * 0.85, r), (r * 0.85, r), (r * 0.7, -r * 0.2), (0.0, -r * 1.35), (-r * 0.7, -r * 0.2)]
        mb.prism(pts, 0.0, 0.09, loc=(x, y + 0.05, z), rot=(90, 0, 0), mat="M_Flat_roof_blue", bevel=0.02, segs=1)
        mb.box((r * 0.18, 0.06, r * 2.0), loc=(x, y - 0.06, z - r * 0.15), mat="M_Gold")
        mb.box((r * 1.5, 0.06, r * 0.18), loc=(x, y - 0.06, z + r * 0.35), mat="M_Gold")


def _helmet(mb, loc, mat="M_Metal", plume=None, s=1.0):
    x, y, z = loc
    mb.dome(0.24 * s, 0.26 * s, loc=(x, y, z), mat=mat, u=14, v=4, underside=True)
    mb.box((0.36 * s, 0.05 * s, 0.07 * s), loc=(x, y - 0.21 * s, z + 0.1 * s), mat="M_Flat_rock_dk")
    mb.cyl(0.26 * s, 0.05 * s, loc=(x, y, z), mat=mat, verts=14)
    if plume:
        mb.sphere(0.1 * s, loc=(x, y + 0.05 * s, z + 0.32 * s), scale=(0.6, 1.6, 1.0), mat=plume, subdiv=1)


@asset("X60001_PanKiosk", "Architecture", footprint=4.6, tags=("interior", "shop"))
def _pan_kiosk(coll):
    """Pan's whitewashed armor kiosk: counter window facing -Y, shelves of helmets and shields behind.

    Width 4.4 (X), depth 2.8 (Y); the back (+Y) goes against a wall. The keeper's stand is walkable in-map.
    """
    mb = MeshBuilder()
    W, Dp = 4.4, 2.8
    # back panel: whitewashed boards with shelves of helmets
    mb.box((W, 0.22, 3.1), loc=(0, Dp / 2 - 0.11, 1.55), mat="M_Cloth_White", bevel=0.03, segs=1)
    for z in (1.35, 2.25):
        mb.box((W - 0.3, 0.42, 0.08), loc=(0, Dp / 2 - 0.4, z), mat="M_Wood", bevel=0.02, segs=1)
    for k, x in enumerate((-1.5, -0.75, 0.0, 0.75, 1.5)):
        _helmet(mb, (x, Dp / 2 - 0.42, 1.39), mat="M_Metal" if k % 2 else "M_Gold",
                plume="M_Flat_roof_red" if k == 2 else None, s=0.95)
    for k, x in enumerate((-1.4, -0.45, 0.5, 1.45)):
        _shield(mb, (x, Dp / 2 - 0.3, 2.75), ("kite", "round", "cross", "round")[k], r=0.3)
    # side walls: whitewashed with blue trim, rounded tops
    arch = [(-Dp / 2, 0.0), (Dp / 2, 0.0)]
    arch += [(math.cos(math.radians(a)) * Dp / 2, 2.1 + math.sin(math.radians(a)) * Dp / 2 * 0.8) for a in range(0, 181, 15)]
    for s in (-1, 1):
        # arch-topped side wall: profile (y, z) extruded along x
        mb.prism(arch, -0.1, 0.1, loc=(s * (W / 2 - 0.1), 0, 0), rot=(90, 0, 90), mat="M_Flat_cloth_white", bevel=0.03,
                 segs=1)
        mb.box((0.24, Dp + 0.04, 0.14), loc=(s * (W / 2 - 0.1), 0, 0.07), mat="M_Flat_roof_blue")
        mb.box((0.24, 0.16, 2.2), loc=(s * (W / 2 - 0.1), -Dp / 2 + 0.08, 1.1), mat="M_Flat_roof_blue")
    # counter with blue-painted boards and a plank top
    mb.box((W - 0.4, 0.5, 1.05), loc=(0, -Dp / 2 + 0.3, 0.52), mat="M_Flat_roof_blue", bevel=0.03, segs=1)
    for k in range(6):
        mb.box((0.05, 0.04, 0.95), loc=(-1.6 + k * 0.64, -Dp / 2 + 0.04, 0.52), mat="M_Flat_cloth_white")
    mb.box((W - 0.2, 0.72, 0.14), loc=(0, -Dp / 2 + 0.3, 1.1), mat="M_Plank", bevel=0.03, segs=1)
    _helmet(mb, (-1.3, -Dp / 2 + 0.3, 1.17), mat="M_Metal", plume="M_Flat_roof_blue", s=0.9)
    mb.box((0.5, 0.3, 0.3), loc=(1.25, -Dp / 2 + 0.3, 1.32), mat="M_Flat_wood_dk", bevel=0.05)  # boots box
    # striped awning over the back shelves (behind the keeper, so he stays visible)
    for i in range(8):
        x = -W / 2 + 0.275 + i * 0.55
        mb.box((0.56, 1.2, 0.07), loc=(x, Dp / 2 - 0.5, 3.35), rot=(-22, 0, 0),
               mat="M_Flat_roof_blue" if i % 2 else "M_Flat_cloth_white")
    mb.box((W + 0.1, 0.1, 0.18), loc=(0, Dp / 2 - 1.05, 3.12), mat="M_Wood_Dark")
    # title board on top of the back panel: green shield-and-cross emblem (the town sign)
    mb.box((2.0, 0.16, 0.7), loc=(0, Dp / 2 - 0.05, 3.85), mat="M_Plank", bevel=0.04, segs=1)
    _shield(mb, (0, Dp / 2 - 0.16, 3.86), "cross", r=0.27)
    mb.build("X60001_PanKiosk", coll, smooth=False)


@asset("X60001_Door_Arch", "Architecture", footprint=1.8, tags=("interior", "door"))
def _door_arch(coll):
    """Closed arched double door (pinkish wood) in a white stone frame with blue trim (faces -Y)."""
    mb = MeshBuilder()
    w, h = 1.5, 2.1
    mb.box((w + 0.5, 0.18, h + 0.2), loc=(0, 0.05, (h + 0.2) / 2), mat="M_Flat_cloth_white", bevel=0.06, segs=1)
    mb.cyl((w + 0.5) / 2, 0.18, loc=(0, 0.14, h + 0.2), rot=(90, 0, 0), mat="M_Flat_cloth_white", verts=18)
    mb.torus((w + 0.3) / 2, 0.06, loc=(0, -0.06, h + 0.05), rot=(90, 0, 0), mat="M_Flat_roof_blue", u=18, v=4)
    mb.box((w, 0.16, h), loc=(0, -0.04, h / 2), mat="M_Grad_door__flower_pink", bevel=0.03, segs=1)
    mb.cyl(w / 2, 0.16, loc=(0, 0.04, h), rot=(90, 0, 0), mat="M_Grad_door__flower_pink", verts=16)
    mb.box((0.05, 0.2, h + 0.7), loc=(0, -0.05, (h + 0.7) / 2), mat="M_Wood_Dark")
    for s in (-1, 1):
        for z in (0.5, 1.5):
            mb.box((0.5, 0.2, 0.07), loc=(s * 0.4, -0.06, z), mat="M_Flat_rock_dk")
        mb.sphere(0.07, loc=(s * 0.14, -0.16, 1.05), mat="M_Gold", subdiv=1)
    # starfish on the keystone
    star = [(math.cos(math.pi / 2 + i * math.pi / 5) * (0.2 if i % 2 == 0 else 0.08),
             math.sin(math.pi / 2 + i * math.pi / 5) * (0.2 if i % 2 == 0 else 0.08)) for i in range(10)]
    mb.prism(star, 0.0, 0.06, loc=(0, -0.05, h + 0.75), rot=(90, 0, 0), mat="M_Flat_roof_orange", bevel=0.02, segs=1)
    mb.box((w + 0.9, 0.7, 0.14), loc=(0, -0.3, 0.07), mat="M_Flat_cloth_white", bevel=0.04, segs=1)
    mb.build("X60001_Door_Arch", coll, smooth=True, sharp_angle=40)


@asset("X60001_ShipWheel", "Architecture", footprint=1.2, tags=("interior",))
def _ship_wheel(coll):
    """Wooden ship's wheel hung on a wall (faces -Y)."""
    mb = MeshBuilder()
    z = 0.0
    mb.torus(0.5, 0.06, loc=(0, -0.08, z), rot=(90, 0, 0), mat="M_Wood", u=20, v=5)
    mb.cyl(0.13, 0.16, loc=(0, 0.0, z), rot=(90, 0, 0), mat="M_Gold", verts=10)
    for k in range(8):
        a = k * 45
        mb.box((0.05, 0.05, 1.4), loc=(0, -0.08, z), rot=(0, a, 0), mat="M_Wood_Dark")
        mb.cyl(0.05, 0.16, loc=(math.cos(math.radians(a)) * 0.7, -0.08, z + math.sin(math.radians(a)) * 0.7),
               rot=(0, 90 - a, 0), mat="M_Wood", verts=6)
    mb.build("X60001_ShipWheel", coll, smooth=True, sharp_angle=40)


@asset("X60001_ShieldWall", "Architecture", footprint=2.6, tags=("interior",))
def _shield_wall(coll):
    """Plank rack holding three shields and two crossed spears (flat on a wall, faces -Y)."""
    mb = MeshBuilder()
    mb.box((2.6, 0.1, 1.5), loc=(0, 0.05, 2.25), mat="M_Plank", bevel=0.03, segs=1)
    mb.box((2.7, 0.14, 0.1), loc=(0, 0.02, 1.5), mat="M_Wood_Dark")
    mb.box((2.7, 0.14, 0.1), loc=(0, 0.02, 3.0), mat="M_Wood_Dark")
    for s in (-1, 1):
        mb.box((0.06, 0.06, 2.0), loc=(s * 0.3, -0.06, 2.25), rot=(0, s * 35, 0), mat="M_Wood")
        mb.cyl(0.07, 0.25, loc=(s * 0.87, -0.06, 3.05), rot=(0, s * 35, 0), mat="M_Metal", verts=6, r2=0.0)
    _shield(mb, (-0.85, -0.05, 2.25), "kite", r=0.42)
    _shield(mb, (0.0, -0.08, 2.3), "cross", r=0.4)
    _shield(mb, (0.85, -0.05, 2.25), "round", r=0.42)
    mb.build("X60001_ShieldWall", coll, smooth=True, sharp_angle=40)


@asset("X60001_Mirror", "Props", footprint=1.0, tags=("interior",))
def _mirror(coll):
    """Tall oval fitting mirror on a stand (faces -Y)."""
    mb = MeshBuilder()
    for s in (-1, 1):
        mb.box((0.1, 0.5, 0.1), loc=(s * 0.35, 0, 0.05), mat="M_Wood_Dark")
        mb.box((0.09, 0.09, 1.9), loc=(s * 0.42, 0.0, 0.95), mat="M_Wood")
    mb.cyl(0.42, 0.08, loc=(0, 0.04, 1.2), rot=(90, 0, 0), mat="M_Gold", verts=20, scale=(1.0, 1.65, 1.0))
    mb.cyl(0.36, 0.1, loc=(0, 0.02, 1.2), rot=(90, 0, 0), mat="M_Glow_water_lt", verts=20, scale=(1.0, 1.65, 1.0))
    mb.box((0.12, 0.11, 0.6), loc=(-0.12, -0.04, 1.35), rot=(0, 25, 0), mat="M_Flat_cloth_white")
    mb.build("X60001_Mirror", coll, smooth=True, sharp_angle=40)


@asset("X60001_HelmetPile", "Props", footprint=1.2, tags=("interior",))
def _helmet_pile(coll):
    """A little heap of helmets and a leaning shield."""
    mb = MeshBuilder()
    for (x, y, z, m_, p) in ((-0.25, 0.0, 0.0, "M_Metal", None), (0.25, 0.1, 0.0, "M_Gold", None),
                             (0.0, -0.15, 0.0, "M_Metal", "M_Flat_roof_blue"), (0.02, 0.05, 0.27, "M_Metal", None)):
        _helmet(mb, (x, y, z), mat=m_, plume=p)
    pts = [(-0.3, 0.35), (0.3, 0.35), (0.25, -0.1), (0.0, -0.45), (-0.25, -0.1)]
    mb.prism(pts, 0.0, 0.07, loc=(0.42, 0.25, 0.42), rot=(70, 0, -20), mat="M_Flat_roof_blue", bevel=0.02, segs=1)
    mb.build("X60001_HelmetPile", coll, smooth=True, sharp_angle=40)


@asset("X60001_KnightArmor", "Props", footprint=1.0, tags=("interior",))
def _knight_armor(coll):
    """Full suit of plate armor on a wooden stand: plumed helmet, pauldrons, blue tabard with a gold emblem."""
    mb = MeshBuilder()
    mb.cyl(0.38, 0.1, mat="M_Wood_Dark", verts=12)
    mb.box((0.09, 0.09, 0.5), loc=(0, 0, 0.3), mat="M_Wood_Dark")
    for sx in (-1, 1):
        mb.cyl(0.11, 0.55, loc=(sx * 0.13, 0, 0.12), mat="M_Metal", verts=10, r2=0.13)
        mb.sphere(0.13, loc=(sx * 0.13, -0.04, 0.14), scale=(1, 1.4, 0.6), mat="M_Flat_rock_dk", subdiv=1)
    mb.cyl(0.27, 0.62, loc=(0, 0, 0.65), mat="M_Metal", verts=14, r2=0.32)
    mb.box((0.36, 0.05, 0.62), loc=(0, -0.29, 0.92), mat="M_Flat_roof_blue")
    mb.cyl(0.11, 0.06, loc=(0, -0.33, 1.02), rot=(90, 0, 0), mat="M_Gold", verts=10)
    mb.cyl(0.33, 0.1, loc=(0, 0, 0.66), mat="M_Flat_wood_dk", verts=14)
    for sx in (-1, 1):
        mb.sphere(0.17, loc=(sx * 0.36, 0, 1.2), scale=(1.1, 1, 0.8), mat="M_Metal", subdiv=2)
        mb.cyl(0.08, 0.45, loc=(sx * 0.4, 0, 0.75), mat="M_Metal", verts=8)
    mb.sphere(0.22, loc=(0, 0, 1.52), scale=(1, 1, 1.1), mat="M_Metal", subdiv=2)
    mb.box((0.3, 0.06, 0.05), loc=(0, -0.2, 1.52), mat="M_Eye_Black")
    mb.sphere(0.1, loc=(0, 0.04, 1.8), scale=(0.6, 1.8, 1.1), mat="M_Flat_roof_red", subdiv=1)
    mb.build("X60001_KnightArmor", coll, smooth=True, sharp_angle=40)


@asset("X60001_ShieldBarrel", "Props", footprint=1.0, tags=("interior",))
def _shield_barrel(coll):
    """Barrel of shields (a kite and a round one poking out) with a spear."""
    mb = MeshBuilder()
    mb.cyl(0.4, 0.5, mat="M_Wood", verts=14, r2=0.47)
    mb.cyl(0.47, 0.5, loc=(0, 0, 0.5), mat="M_Wood", verts=14, r2=0.4)
    for z in (0.12, 0.5, 0.88):
        mb.cyl(0.48 - abs(z - 0.5) * 0.18, 0.07, loc=(0, 0, z - 0.035), mat="M_Metal", verts=14)
    _shield(mb, (0.08, 0.12, 1.08), "kite", r=0.3)
    _shield(mb, (-0.1, -0.12, 1.02), "round", r=0.3)
    mb.cyl(0.03, 1.5, loc=(0.22, 0.05, 0.3), rot=(0, 10, 0), mat="M_Wood", verts=6)
    mb.cyl(0.06, 0.22, loc=(0.48, 0.05, 1.77), rot=(0, 10, 0), mat="M_Metal", verts=6, r2=0.0)
    mb.build("X60001_ShieldBarrel", coll, smooth=True, sharp_angle=40)


@asset("X60001_BootsCrate", "Props", footprint=1.0, tags=("interior",))
def _boots_crate(coll):
    """Open crate of leather and blue boots, with one boot leaning against it."""
    mb = MeshBuilder()
    mb.box((0.9, 0.7, 0.08), loc=(0, 0, 0.04), mat="M_Wood_Dark")
    for s in (-1, 1):
        mb.box((0.9, 0.08, 0.45), loc=(0, s * 0.31, 0.225), mat="M_Plank", bevel=0.02, segs=1)
        mb.box((0.08, 0.7, 0.45), loc=(s * 0.41, 0, 0.225), mat="M_Plank", bevel=0.02, segs=1)
    mb.box((0.94, 0.04, 0.07), loc=(0, -0.35, 0.3), mat="M_Flat_roof_blue")
    for k, (x, y, mat) in enumerate(((-0.24, -0.08, "M_Flat_wood_dk"), (-0.08, 0.1, "M_Flat_wood_dk"),
                                     (0.12, -0.1, "M_Flat_roof_blue"), (0.27, 0.08, "M_Flat_roof_blue"))):
        tilt = (k - 1.5) * 6
        mb.cyl(0.08, 0.42, loc=(x, y, 0.3), rot=(0, tilt, 0), mat=mat, verts=10)
        mb.cyl(0.095, 0.07, loc=(x + math.sin(math.radians(tilt)) * 0.4, y, 0.7), rot=(0, tilt, 0),
               mat="M_Gold" if k % 2 else "M_Flat_cloth_white", verts=10)
    # a boot leaning on the crate's front
    mb.box((0.17, 0.3, 0.12), loc=(0.15, -0.6, 0.06), rot=(0, 0, 10), mat="M_Flat_wood_dk", bevel=0.04, segs=1)
    mb.cyl(0.08, 0.4, loc=(0.13, -0.52, 0.06), rot=(18, 0, 10), mat="M_Flat_wood_dk", verts=10)
    mb.build("X60001_BootsCrate", coll, smooth=True, sharp_angle=40)


@asset("X60001_ShieldPlaque", "Architecture", footprint=1.3, tags=("interior",))
def _shield_plaque(coll):
    """Round blue plaque with a rope rim, crossed swords and a kite shield (flat on a wall, faces -Y)."""
    mb = MeshBuilder()
    mb.cyl(0.64, 0.08, loc=(0, 0.04, 0), rot=(90, 0, 0), mat="M_Flat_cloth_white", verts=22)
    mb.cyl(0.54, 0.1, loc=(0, 0.04, 0), rot=(90, 0, 0), mat="M_Flat_roof_blue", verts=22)
    mb.torus(0.6, 0.035, loc=(0, -0.05, 0), rot=(90, 0, 0), mat="M_Rope", u=24, v=4)
    for s in (-1, 1):
        mb.box((0.07, 0.04, 1.15), loc=(0, -0.1, 0), rot=(0, s * 40, 0), mat="M_Metal")
        mb.box((0.26, 0.06, 0.06), loc=(s * 0.29, -0.11, -0.35), rot=(0, s * 40, 0), mat="M_Gold")
        mb.box((0.06, 0.06, 0.18), loc=(s * 0.36, -0.11, -0.44), rot=(0, s * 40, 0), mat="M_Wood_Dark")
    _shield(mb, (0, -0.16, 0.04), "kite", r=0.3)
    mb.build("X60001_ShieldPlaque", coll, smooth=True, sharp_angle=40)


@asset("X60001_LobsterPot", "Props", footprint=0.9, tags=("interior", "port"))
def _lobster_pot(coll):
    """Arched wooden lobster pot (0.8 x 0.55 x 0.5) with rope netting, a funnel mouth and a red lobster."""
    mb = MeshBuilder()
    L, W, H = 0.8, 0.55, 0.5
    mb.box((L, W, 0.06), loc=(0, 0, 0.03), mat="M_Wood_Dark", bevel=0.01, segs=1)
    for x in (-L / 2 + 0.04, 0.0, L / 2 - 0.04):   # three bent-wood hoops
        for k in range(8):
            a0, a1 = math.pi * k / 8, math.pi * (k + 1) / 8
            ya, za = math.cos(a0) * W / 2, 0.06 + math.sin(a0) * (H - 0.06)
            yb, zb = math.cos(a1) * W / 2, 0.06 + math.sin(a1) * (H - 0.06)
            ang = math.degrees(math.atan2(zb - za, yb - ya))
            mb.box((0.04, math.hypot(yb - ya, zb - za) + 0.02, 0.04), loc=(x, (ya + yb) / 2, (za + zb) / 2),
                   rot=(ang, 0, 0), mat="M_Wood")
    for k in range(7):                              # slats along the arch
        a = math.pi * (k + 0.5) / 7
        mb.box((L, 0.035, 0.03), loc=(0, math.cos(a) * W / 2, 0.06 + math.sin(a) * (H - 0.06)),
               rot=(math.degrees(a) - 90, 0, 0), mat="M_Plank")
    for k in range(5):                              # netting rings on the ends
        mb.torus(0.07 + k * 0.035, 0.008, loc=(L / 2 + 0.005, 0, 0.22), rot=(0, 90, 0), mat="M_Rope", u=12, v=3)
    mb.cyl(0.12, 0.2, loc=(-L / 2 + 0.02, 0, 0.22), rot=(0, 90, 0), mat="M_Rope", verts=10, r2=0.05)
    # the lobster inside
    mb.sphere(0.1, loc=(0.02, 0, 0.16), scale=(1.8, 0.8, 0.6), mat="M_Flat_roof_red", subdiv=1)
    for s in (-1, 1):
        mb.sphere(0.06, loc=(0.24, s * 0.1, 0.16), scale=(1.4, 0.8, 0.6), mat="M_Flat_roof_red", subdiv=1)
    mb.cyl(0.035, 0.6, loc=(L / 2, 0.18, 0.12), rot=(0, 90, -20), mat="M_Rope", verts=6)
    mb.sphere(0.11, loc=(L / 2 + 0.35, 0.33, 0.11), scale=(1, 1, 1.25), mat="M_Flat_roof_orange", subdiv=1)  # float
    mb.cyl(0.112, 0.06, loc=(L / 2 + 0.35, 0.33, 0.1), mat="M_Flat_cloth_white", verts=10)
    mb.build("X60001_LobsterPot", coll, smooth=True, sharp_angle=40)


def _net_strands(mb, grid, mat="M_Rope", t=0.022):
    """Draw a net as thin rope strands along both diagonals of a point grid (grid[i][j] = (x, y, z))."""
    n, k = len(grid), len(grid[0])
    for i in range(n - 1):
        for j in range(k - 1):
            for (a, b) in ((grid[i][j], grid[i + 1][j + 1]), (grid[i + 1][j], grid[i][j + 1])):
                dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
                L = math.sqrt(dx * dx + dy * dy + dz * dz)
                yaw = math.degrees(math.atan2(dy, dx))
                pitch = math.degrees(math.atan2(dz, math.hypot(dx, dy)))
                mb.cyl(t, L, loc=a, rot=(0, 90 - pitch, yaw), mat=mat, verts=4)


@asset("X60001_NetPile", "Props", footprint=1.3, tags=("interior", "port"))
def _net_pile(coll):
    """A heap of brown fishing net with cork floats, a leaning oar and a coiled line."""
    mb = MeshBuilder()
    mb.sphere(0.5, loc=(0, 0, 0.12), scale=(1.25, 0.95, 0.55), mat="M_Flat_sand_mortar", subdiv=2, lumpy=0.3, seed=3,
              flatten_bottom=0.2)
    mb.sphere(0.3, loc=(0.35, -0.2, 0.32), scale=(1.1, 0.9, 0.7), mat="M_Flat_sand_mortar", subdiv=2, lumpy=0.3,
              seed=8)
    grid = [[(-0.62 + i * 0.155, -0.48 + j * 0.16,
              0.14 + 0.28 * max(0.0, 1 - ((-0.62 + i * 0.155) / 0.66) ** 2 - ((-0.48 + j * 0.16) / 0.52) ** 2) ** 0.5)
             for j in range(7)] for i in range(9)]
    _net_strands(mb, grid, t=0.018)
    for k, (x, y) in enumerate(((-0.45, -0.3), (-0.1, -0.42), (0.3, -0.4), (0.55, 0.05), (-0.2, 0.25))):
        z = 0.14 + 0.3 * max(0.0, 1 - (x / 0.7) ** 2 - (y / 0.55) ** 2) ** 0.5
        mb.cyl(0.08, 0.12, loc=(x, y, z - 0.02), rot=(70, 0, k * 40), mat="M_Flat_roof_orange" if k % 2 else "M_Cloth_White",
               verts=10)
    mb.cyl(0.035, 1.7, loc=(-0.55, 0.35, 0.0), rot=(0, 22, 15), mat="M_Wood", verts=6)   # oar
    mb.box((0.16, 0.04, 0.5), loc=(-0.55 + 0.6, 0.35 + 0.16, 1.5), rot=(0, 22, 15), mat="M_Wood", bevel=0.02, segs=1)
    for k in range(3):
        mb.torus(0.22 - k * 0.03, 0.04, loc=(0.62, 0.32, 0.04 + k * 0.07), mat="M_Rope", u=12, v=4)
    mb.build("X60001_NetPile", coll, smooth=True, sharp_angle=50)


@asset("X60001_NetWall", "Architecture", footprint=1.4, tags=("interior", "port"))
def _net_wall(coll):
    """Fishing net hung on a wall from two pegs: sagging diamond mesh, cork floats, a starfish and a fish
    caught in it (flat on the wall, faces -Y). Origin at the wall base, centred."""
    mb = MeshBuilder()
    W, z0, z1 = 1.5, 0.9, 2.7
    for s in (-1, 1):
        mb.cyl(0.05, 0.16, loc=(s * W / 2, 0.0, z1 + 0.05), rot=(90, 0, 0), mat="M_Wood_Dark", verts=8)
    grid = []
    for i in range(9):
        u = i / 8
        x = (u - 0.5) * W * (1 - 0.15 * (1 - abs(2 * u - 1)))
        col = []
        for j in range(8):
            v = j / 7
            top = z1 - 0.18 * math.sin(math.pi * u)                    # the head rope sags between the pegs
            col.append((x * (1 - 0.25 * (1 - v)), -0.06 - 0.05 * math.sin(math.pi * u) * v, z0 + (top - z0) * v
                        - 0.12 * math.sin(math.pi * u) * (1 - v)))
        grid.append(col)
    _net_strands(mb, grid, t=0.016)
    for i in range(0, 9, 2):                        # floats along the head rope
        x, y, z = grid[i][-1]
        mb.cyl(0.075, 0.13, loc=(x, y - 0.04, z - 0.06), rot=(0, 90, 0), mat="M_Flat_roof_orange" if i % 4 else
               "M_Cloth_White", verts=10)
    star = [(math.cos(math.pi / 2 + k * math.pi / 5) * (0.2 if k % 2 == 0 else 0.08),
             math.sin(math.pi / 2 + k * math.pi / 5) * (0.2 if k % 2 == 0 else 0.08)) for k in range(10)]
    mb.prism(star, 0.0, 0.05, loc=(-0.3, -0.13, 1.6), rot=(90, 0, 15), mat="M_Flat_roof_orange", bevel=0.015, segs=1)
    mb.sphere(0.13, loc=(0.32, -0.12, 1.3), scale=(1.6, 0.4, 0.75), mat="M_Flat_sea", subdiv=2)
    mb.prism([(0.0, 0.0), (0.16, 0.12), (0.16, -0.12)], -0.02, 0.02, loc=(0.52, -0.12, 1.3), rot=(90, 0, 0),
             mat="M_Flat_sea_dk")
    mb.build("X60001_NetWall", coll, smooth=True, sharp_angle=50)


@asset("X60001_CargoNet", "Props", footprint=0.8, tags=("interior", "port"))
def _cargo_net(coll):
    """A rope cargo net slung from two hooks (origin = between the hooks, at the beam's underside) and
    sagging 1 m with floats, a little crate and a barrel in its belly. Spans 2.2 m along X."""
    mb = MeshBuilder()
    hw, hd, sag = 1.1, 0.42, 1.0
    for s in (-1, 1):
        mb.torus(0.07, 0.018, loc=(s * hw, 0, -0.06), rot=(90, 0, 0), mat="M_Metal", u=10, v=4)
        mb.cyl(0.03, 0.3, loc=(s * hw, 0, -0.38), mat="M_Rope", verts=6)
    grid = []
    for i in range(10):
        u = -1 + 2 * i / 9
        col = []
        for j in range(5):
            v = -1 + 2 * j / 4
            z = -0.38 - sag * (1 - u * u) * (0.55 + 0.45 * (1 - v * v))
            col.append((u * hw * (1 - 0.1 * (1 - v * v)), v * hd * (0.35 + 0.65 * (1 - u * u) ** 0.5), z))
        grid.append(col)
    _net_strands(mb, grid, t=0.02)
    for i in range(10):                              # the two side ropes of the sling
        if i < 9:
            for j in (0, 4):
                a, b = grid[i][j], grid[i + 1][j]
                dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
                L = math.sqrt(dx * dx + dy * dy + dz * dz)
                mb.cyl(0.03, L, loc=a, rot=(0, 90 - math.degrees(math.atan2(dz, math.hypot(dx, dy))),
                                            math.degrees(math.atan2(dy, dx))), mat="M_Rope", verts=6)
    zb = -0.38 - sag
    mb.box((0.5, 0.45, 0.42), loc=(-0.28, 0.02, zb + 0.28), rot=(0, 8, 12), mat="M_Wood", bevel=0.03, segs=1)
    mb.box((0.52, 0.47, 0.06), loc=(-0.28, 0.02, zb + 0.45), rot=(0, 8, 12), mat="M_Wood_Dark")
    mb.cyl(0.19, 0.5, loc=(0.3, 0.0, zb + 0.12), rot=(0, 80, 0), mat="M_Wood", verts=12)
    mb.cyl(0.2, 0.05, loc=(0.37, 0.0, zb + 0.13), rot=(0, 80, 0), mat="M_Metal", verts=12)
    for (x, mat) in ((0.68, "M_Flat_roof_orange"), (-0.72, "M_Cloth_White"), (0.0, "M_Flat_roof_orange")):
        mb.sphere(0.13, loc=(x, -0.12, zb + 0.32 + abs(x) * 0.25), mat=mat, subdiv=2)
    mb.build("X60001_CargoNet", coll, smooth=True, sharp_angle=50)


@asset("X60001_SeaWindow", "Architecture", footprint=2.4, tags=("interior", "port"))
def _sea_window(coll):
    """Big arched window onto the harbour (flat on a wall, faces -Y; everything sits in front of the wall
    plane y=0): whitewashed frame with blue trim, open blue shutters, mullions, a flower box, and the sea
    view (sky, clouds, a sail, the lighthouse). Origin at the wall base, centred; opening x +-0.85,
    z 1.0..2.5 plus the round head to 3.35."""
    mb = MeshBuilder()
    w, zb, zr = 1.7, 1.0, 2.5
    r = w / 2
    # view (emissive so it reads as daylight): sky, then the sea band, foam line, clouds, sail, lighthouse
    mb.box((w, 0.02, zr - zb), loc=(0, -0.02, (zb + zr) / 2), mat="M_Glow_sky_horizon")
    mb.cyl(r, 0.02, loc=(0, -0.01, zr), rot=(90, 0, 0), mat="M_Glow_sky_top", verts=24)
    mb.box((w, 0.02, 0.7), loc=(0, -0.035, zb + 0.35), mat="M_Glow_sea_dk")
    mb.box((w, 0.02, 0.06), loc=(0, -0.045, zb + 0.7), mat="M_Glow_foam")
    mb.sphere(0.2, loc=(-0.38, -0.05, zr - 0.15), scale=(1.8, 0.15, 0.6), mat="M_Glow_cloud", subdiv=1)
    mb.sphere(0.15, loc=(0.38, -0.05, zr + 0.4), scale=(1.8, 0.15, 0.6), mat="M_Glow_cloud", subdiv=1)
    mb.prism([(0.0, 0.0), (0.0, 0.5), (0.3, 0.05)], -0.01, 0.01, loc=(0.3, -0.055, zb + 0.74), rot=(90, 0, 0),
             mat="M_Flat_cloth_white")                     # a sail on the horizon
    mb.box((0.36, 0.02, 0.07), loc=(0.42, -0.055, zb + 0.71), mat="M_Flat_wood_dk")
    mb.cyl(0.05, 0.4, loc=(-0.5, -0.055, zb + 0.68), mat="M_Flat_cloth_white", verts=8, r2=0.035)   # lighthouse
    mb.cyl(0.055, 0.08, loc=(-0.5, -0.056, zb + 1.08), mat="M_Flat_roof_red", verts=8)
    # frame: white jambs + round head, blue inner trim
    for s in (-1, 1):
        mb.box((0.2, 0.22, zr - zb + 0.1), loc=(s * (r + 0.1), -0.11, (zb + zr) / 2), mat="M_Flat_cloth_white",
               bevel=0.03, segs=1)
    for k in range(12):
        a0, a1 = math.pi * k / 12, math.pi * (k + 1) / 12
        am = (a0 + a1) / 2
        mb.box((0.2, 0.22, (r + 0.1) * (a1 - a0) + 0.04), loc=(math.cos(am) * (r + 0.1), -0.11,
                                                            zr + math.sin(am) * (r + 0.1)),
               rot=(0, -math.degrees(am), 0), mat="M_Flat_cloth_white")
    mb.torus(r, 0.04, loc=(0, -0.2, zr), rot=(90, 0, 0), mat="M_Flat_roof_blue", u=20, v=4, scale=(1, 1, 1))
    for s in (-1, 1):
        mb.box((0.08, 0.08, zr - zb), loc=(s * r, -0.2, (zb + zr) / 2), mat="M_Flat_roof_blue")
    # mullions
    mb.box((0.06, 0.05, zr - zb + r), loc=(0, -0.08, (zb + zr + r) / 2), mat="M_Flat_wood_dk")
    mb.box((w, 0.05, 0.06), loc=(0, -0.08, zb + 0.95), mat="M_Flat_wood_dk")
    mb.box((w, 0.05, 0.06), loc=(0, -0.08, zr), mat="M_Flat_wood_dk")
    # slim sill on a blue corbel (kept shallow so it does not hide the sea band from the high camera)
    mb.box((w + 0.5, 0.2, 0.09), loc=(0, -0.1, zb - 0.045), mat="M_Flat_cloth_white", bevel=0.03, segs=1)
    mb.box((w - 0.3, 0.12, 0.16), loc=(0, -0.06, zb - 0.17), mat="M_Flat_roof_blue", bevel=0.03, segs=1)
    # open shutters (blue planks) folded back flat against the wall, white ledges
    for s in (-1, 1):
        for k in range(2):
            mb.box((0.27, 0.05, zr - zb + 0.35), loc=(s * (r + 0.36 + k * 0.28), -0.03, (zb + zr) / 2 + 0.05),
                   mat="M_Flat_roof_blue", bevel=0.02, segs=1)
        for zz in (zb + 0.3, zr - 0.2):
            mb.box((0.58, 0.04, 0.07), loc=(s * (r + 0.5), -0.07, zz), mat="M_Flat_cloth_white")
    mb.build("X60001_SeaWindow", coll, smooth=True, sharp_angle=40)


@asset("X60001_TabardMannequin", "Props", footprint=1.0, tags=("interior",))
def _tabard_mannequin(coll):
    """Bare-headed linen mannequin on a pole wearing a blue Southperry tabard with a gold anchor."""
    mb = MeshBuilder()
    mb.cyl(0.34, 0.08, mat="M_Wood_Dark", verts=12)
    for k in range(3):
        a = math.radians(30 + k * 120)
        mb.box((0.5, 0.07, 0.05), loc=(math.cos(a) * 0.2, math.sin(a) * 0.2, 0.05), rot=(0, 0, math.degrees(a)),
               mat="M_Wood_Dark")
    mb.cyl(0.04, 0.85, loc=(0, 0, 0.05), mat="M_Wood", verts=8)
    mb.cyl(0.24, 0.75, loc=(0, 0, 0.85), mat="M_Cloth_White", verts=14, r2=0.3)      # linen dress form
    mb.sphere(0.3, loc=(0, 0, 1.6), scale=(1.1, 0.75, 0.32), mat="M_Cloth_White", subdiv=2)
    mb.cyl(0.07, 0.14, loc=(0, 0, 1.68), mat="M_Wood", verts=8)
    mb.sphere(0.07, loc=(0, 0, 1.86), mat="M_Wood", subdiv=1)                         # little wooden knob
    # tabard: front + back panels and the shoulder piece
    for s in (-1, 1):
        mb.box((0.46, 0.04, 0.95), loc=(0, s * 0.25, 1.15), rot=(s * 4, 0, 0), mat="M_Flat_roof_blue", bevel=0.02,
               segs=1)
        mb.box((0.5, 0.05, 0.06), loc=(0, s * 0.26, 0.7), mat="M_Gold")
    mb.box((0.62, 0.55, 0.06), loc=(0, 0, 1.64), mat="M_Flat_roof_blue", bevel=0.02, segs=1)
    mb.box((0.06, 0.03, 0.4), loc=(0, -0.29, 1.2), mat="M_Gold")                      # gold anchor
    mb.box((0.26, 0.03, 0.05), loc=(0, -0.29, 1.32), mat="M_Gold")
    mb.torus(0.13, 0.025, loc=(0, -0.29, 1.08), rot=(90, 0, 0), mat="M_Gold", u=12, v=4, scale=(1, 1, 0.8))
    mb.box((0.5, 0.06, 0.07), loc=(0, -0.27, 0.95), mat="M_Flat_wood_dk")             # belt
    mb.box((0.1, 0.07, 0.09), loc=(0, -0.3, 0.95), mat="M_Gold")
    mb.build("X60001_TabardMannequin", coll, smooth=True, sharp_angle=40)


@asset("X60001_ChainmailStand", "Props", footprint=1.0, tags=("interior",))
def _chainmail_stand(coll):
    """T-shaped wooden stand carrying a grey chainmail hauberk with a coif hood hung on its peg."""
    mb = MeshBuilder()
    mb.box((0.7, 0.45, 0.08), loc=(0, 0, 0.04), mat="M_Wood_Dark", bevel=0.02, segs=1)
    mb.box((0.09, 0.09, 1.75), loc=(0, 0, 0.9), mat="M_Wood")
    mb.box((0.95, 0.08, 0.08), loc=(0, 0, 1.6), mat="M_Wood", bevel=0.01, segs=1)
    # hauberk: a slightly flared mail shirt with short sleeves, ring rows as darker bands
    mb.cyl(0.27, 0.8, loc=(0, 0, 0.72), mat="M_Metal", verts=14, r2=0.25)
    for s in (-1, 1):
        mb.cyl(0.11, 0.4, loc=(s * 0.38, 0, 1.52), rot=(0, s * 125, 0), mat="M_Metal", verts=10, r2=0.13)
    mb.sphere(0.27, loc=(0, 0, 1.5), scale=(1.25, 0.8, 0.45), mat="M_Metal", subdiv=2)
    for k in range(5):
        mb.cyl(0.272 - k * 0.004, 0.025, loc=(0, 0, 0.8 + k * 0.15), mat="M_Flat_rock_dk", verts=14)
    mb.cyl(0.3, 0.06, loc=(0, 0, 0.7), mat="M_Flat_rock_dk", verts=14)
    # coif hood on the peg, and a leather belt
    mb.sphere(0.16, loc=(0, 0, 1.82), scale=(1, 1, 1.15), mat="M_Metal", subdiv=2)
    mb.cyl(0.2, 0.12, loc=(0, 0, 1.64), mat="M_Metal", verts=12, r2=0.15)
    mb.box((0.18, 0.04, 0.1), loc=(0, -0.15, 1.83), mat="M_Flat_rock_dk")
    mb.cyl(0.262, 0.07, loc=(0, 0, 1.08), mat="M_Flat_wood_dk", verts=14)
    mb.box((0.1, 0.06, 0.1), loc=(0, -0.27, 1.11), mat="M_Gold")
    mb.build("X60001_ChainmailStand", coll, smooth=True, sharp_angle=40)


@asset("X60001_GloveRack", "Props", footprint=1.1, tags=("interior",))
def _glove_rack(coll):
    """Two-tier plank rack: pairs of leather and blue gloves on pegs above, boots on the lower shelf."""
    mb = MeshBuilder()
    W, H = 1.0, 1.45
    for s in (-1, 1):
        mb.box((0.08, 0.36, H), loc=(s * W / 2, 0, H / 2), mat="M_Wood_Dark", bevel=0.015, segs=1)
    mb.box((W + 0.08, 0.38, 0.06), loc=(0, 0, 0.12), mat="M_Plank", bevel=0.015, segs=1)
    mb.box((W + 0.08, 0.38, 0.06), loc=(0, 0, 0.62), mat="M_Plank", bevel=0.015, segs=1)
    mb.box((W + 0.12, 0.1, 0.12), loc=(0, 0.1, H - 0.05), mat="M_Wood", bevel=0.02, segs=1)
    mb.box((W, 0.04, 0.36), loc=(0, 0.16, 1.1), mat="M_Plank")
    for k, (x, mat) in enumerate(((-0.33, "M_Flat_wood_dk"), (0.0, "M_Flat_roof_blue"), (0.33, "M_Flat_wood_lt"))):
        mb.cyl(0.02, 0.12, loc=(x, 0.12, 1.2), rot=(90, 0, 0), mat="M_Wood_Dark", verts=6)
        for s in (-1, 1):                              # a pair of gloves hanging from the peg
            gx = x + s * 0.07
            mb.box((0.11, 0.06, 0.16), loc=(gx, 0.02, 1.07), rot=(0, s * 8, 0), mat=mat, bevel=0.03, segs=1)
            mb.box((0.04, 0.05, 0.08), loc=(gx + s * 0.07, 0.02, 1.08), rot=(0, s * 35, 0), mat=mat)
            mb.cyl(0.06, 0.08, loc=(gx, 0.02, 0.92), mat="M_Gold" if k == 1 else mat, verts=8)
        # boots on the lower shelves
        for s in (-1, 1):
            bx = x + s * 0.07
            for zz in (0.15, 0.65):
                mb.cyl(0.055, 0.26, loc=(bx, 0.03, zz), mat=mat if zz < 0.5 else ("M_Flat_wood_dk", "M_Flat_rock_dk",
                                                                                    "M_Flat_roof_blue")[k], verts=8)
                mb.box((0.11, 0.2, 0.08), loc=(bx, -0.05, zz + 0.04), mat=mat if zz < 0.5 else "M_Flat_wood_dk",
                       bevel=0.03, segs=1)
    mb.build("X60001_GloveRack", coll, smooth=True, sharp_angle=40)


@asset("X60001_RugRope", "Props", footprint=3.0, tags=("interior", "port"))
def _rug_rope(coll):
    """Rectangular navy rug (3.2 x 2.2) with a cream compass rose, bordered by a twisted rope."""
    mb = MeshBuilder()
    L, W = 3.2, 2.2
    mb.box((L, W, 0.025), loc=(0, 0, 0.0125), mat="M_Flat_sea_dk")
    mb.box((L - 0.3, W - 0.3, 0.03), loc=(0, 0, 0.015), mat="M_Flat_cloth_white")
    mb.box((L - 0.45, W - 0.45, 0.035), loc=(0, 0, 0.0175), mat="M_Flat_sea")
    star = []
    for k in range(16):
        a = math.pi / 2 + k * math.pi / 8
        rr = (0.75 if k % 4 == 0 else 0.42) if k % 2 == 0 else 0.16
        star.append((math.cos(a) * rr, math.sin(a) * rr))
    mb.prism(star, 0.0, 0.04, mat="M_Flat_cloth_white")
    mb.cyl(0.12, 0.045, mat="M_Flat_roof_orange", verts=12)
    mb.prism([(0.0, 0.75), (0.1, 0.5), (-0.1, 0.5)], 0.0, 0.045, mat="M_Flat_roof_red")   # north point
    # rope border: straight runs + twist marks, rounded corners
    hx, hy, rr = L / 2 - 0.05, W / 2 - 0.05, 0.055
    for (ax, ay, bx, by) in ((-hx, -hy, hx, -hy), (hx, -hy, hx, hy), (hx, hy, -hx, hy), (-hx, hy, -hx, -hy)):
        ln = math.hypot(bx - ax, by - ay)
        yaw = math.degrees(math.atan2(by - ay, bx - ax))
        mb.cyl(rr, ln, loc=(ax, ay, rr), rot=(0, 90, yaw), mat="M_Rope", verts=8)
        n = int(ln / 0.11)
        for k in range(n):
            t = (k + 0.5) / n
            mb.box((0.03, 0.12, 0.03), loc=(ax + (bx - ax) * t, ay + (by - ay) * t, rr * 1.9), rot=(0, 0, yaw + 55),
                   mat="M_Flat_sand_mortar")
        mb.sphere(rr * 1.05, loc=(ax, ay, rr), mat="M_Rope", subdiv=1)
    mb.build("X60001_RugRope", coll, smooth=False)


# ---------------------------------------------------------------------------
# in-map helpers
# ---------------------------------------------------------------------------

def _shaft_material(name, alpha_lo, alpha_hi, color=(1.0, 0.93, 0.74, 1.0), strength=1.0):
    """Soft additive-looking daylight: emission mixed with transparency, fading by the mesh's height."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["To Min"].default_value = alpha_lo
    mr.inputs["To Max"].default_value = alpha_hi
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try:
            setattr(mat, attr, val)
            break
        except Exception:
            continue
    try:
        mat.use_backface_culling = False
    except Exception:
        pass
    return mat


def spot_light(m, at, target, energy, size_deg=55.0, color=(1.0, 0.92, 0.75), name="Spot", blend=0.6):
    ld = bpy.data.lights.new(f"{m.slug}_{name}", "SPOT")
    ld.energy = energy
    ld.color = color
    ld.spot_size = math.radians(size_deg)
    ld.spot_blend = blend
    ld.shadow_soft_size = 0.4
    lo = bpy.data.objects.new(f"{m.slug}_{name}", ld)
    m.col_props.objects.link(lo)
    lo.location = m.w(*at)
    d = (m.w(*target) - lo.location).normalized()
    lo.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return lo


def flag_floor(m, x0, y0, x1, y1, band=0.45, seed=0):
    """Visual-only floor: whitewashed sandstone flags in staggered rows inside a blue-and-white tile band
    that runs along the walls. Floats a few mm over the floor slab (whose colour shows as grout)."""
    import random
    rng = random.Random(f"{m.slug}-flags-{seed}")
    mb = MeshBuilder()
    zb, zt = 0.003, PLANK_TOP
    gap = 0.045
    nx = int(round((x1 - x0) / band))
    ny = int(round((y1 - y0) / band))
    bx, by = (x1 - x0) / nx, (y1 - y0) / ny
    for i in range(nx):
        for j in range(ny):
            if 0 < i < nx - 1 and 0 < j < ny - 1:
                continue
            mat = "M_Flat_roof_blue" if (i + j) % 2 else "M_Flat_cloth_white"
            lbox(mb, m, (bx - gap, by - gap, zt - zb), (x0 + (i + 0.5) * bx, y0 + (j + 0.5) * by, (zb + zt) / 2), 0, mat)
    tones = ("M_Flat_sand_a", "M_Flat_sand_b", "M_Flat_beach", "M_Flat_plaster", "M_Flat_sand_a", "M_Flat_cobble_a")
    ix0, iy0, ix1, iy1 = x0 + bx + 0.06, y0 + by + 0.06, x1 - bx - 0.06, y1 - by - 0.06
    y = iy0
    while y < iy1 - 0.05:
        h = min(rng.uniform(0.72, 1.02), iy1 - y)
        if iy1 - (y + h) < 0.35:
            h = iy1 - y
        x = ix0 - rng.uniform(0.0, 0.7)
        while x < ix1 - 1e-3:
            ln = rng.uniform(0.75, 1.35)
            a, b = max(ix0, x), min(ix1, x + ln)
            if b - a > 0.2:
                lbox(mb, m, (b - a - gap, h - gap, zt - zb), ((a + b) / 2, y + h / 2, (zb + zt) / 2), 0, rng.choice(tones))
            x += ln
        y += h
    # visual only: no collision (the walkable floor slab below is the floor; untagged, the Architecture default made
    # these flags a Walls slab 3-11 mm above Ground)
    obj = CT.tag(mb.build(f"{m.slug}_Floor_Flags", m.col_arch, smooth=False), CT.NONE)
    obj.visible_shadow = False
    return obj


def _crate_faces(mb, m, cx, cy, w, d, z0, h, kind, frame_faces=("-Y", "+X")):
    """Visual body of one ware: crate (framed planks), box (lidded wares box) or trunk (blue, gold bands)."""
    body = {"crate": "M_Wood", "box": "M_Plank", "trunk": "M_Flat_roof_blue"}[kind]
    trim = {"crate": "M_Wood_Dark", "box": "M_Metal", "trunk": "M_Gold"}[kind]
    lbox(mb, m, (w, d, h), (cx, cy, z0 + h / 2), 0, body, bevel=0.02)
    t = 0.02
    for face in frame_faces:
        if face == "-Y":
            fy, span, ax = cy - d / 2 - t / 2, w, "x"
        else:
            fy, span, ax = cx + w / 2 + t / 2, d, "y"

        def strip(sx, sy, sz, off, zc, tilt=(0.0, 0.0)):
            if ax == "x":
                lbox(mb, m, (sx, t + 0.005, sz), (cx + off, fy, zc), 0, trim, tilt=tilt)
            else:
                lbox(mb, m, (sx, t + 0.005, sz), (fy, cy + off, zc), 90, trim, tilt=tilt)

        if kind == "crate":
            strip(span, 0, 0.09, 0, z0 + 0.06)
            strip(span, 0, 0.09, 0, z0 + h - 0.06)
            for s in (-1, 1):
                strip(0.09, 0, h, s * (span / 2 - 0.045), z0 + h / 2)
            dl = math.hypot(span - 0.18, h - 0.18)
            strip(dl, 0, 0.07, 0, z0 + h / 2, tilt=(0, math.degrees(math.atan2(h - 0.18, span - 0.18))))
        elif kind == "box":
            strip(span + 0.01, 0, 0.07, 0, z0 + h * 0.5)
            lbox(mb, m, (0.06, 0.03, 0.06), (cx if ax == "x" else fy + 0.01, cy if ax == "y" else fy - 0.01,
                                             z0 + h * 0.62), 0, "M_Rope")
            for s in (-1, 1):
                strip(0.07, 0, h, s * (span / 2 - 0.035), z0 + h / 2)
        else:  # trunk
            for s in (-1, 1):
                strip(0.08, 0, h, s * (span / 2 - 0.04), z0 + h / 2)
            strip(span, 0, 0.06, 0, z0 + h - 0.08)
            if ax == "x":
                strip(0.16, 0, 0.2, 0, z0 + h - 0.2)


def ware_heap(m, steps, lid_name="Heap_Lids", body_name="Heap_Goods"):
    """The climbable ware heap as REAL geometry: every step is a stack of crates / boxes / trunks whose
    plank lids are the walkable tops (no hidden collision proxies).

    steps: (x0, y0, x1, y1, top, z0, cells, split). Each layer (<= 0.8 m) of a step is split into two
    cells along x at ``split`` (or one cell for "box1"); the top layer uses ``cells`` (crate | box | trunk),
    lower layers are crates. Bodies are inset 3 cm under their lids so the lid edge covers the ink outline.
    """
    lids = []
    mb = MeshBuilder()
    for (x0, y0, x1, y1, top, z0, cells, split) in steps:
        layers = []
        z = z0
        while top - z > 0.05:
            h = 0.8 if top - z >= 0.79 else top - z
            layers.append((z, h))
            z += h
        xm = x0 + (x1 - x0) * split
        for li, (z, h) in enumerate(layers):
            last = li == len(layers) - 1
            kinds = (cells or ("crate", "crate")) if last else ("crate", "crate")
            single = kinds[0] == "box1"
            spans = [(x0, x1)] if single else [(x0, xm), (xm, x1)]
            for ci, (a, b) in enumerate(spans):
                kind = "box" if single else (kinds[ci] if ci < len(kinds) else kinds[-1])
                if kind == "crate" and h < 0.6:
                    kind = "box"
                hb = h - (0.07 if last else 0.0)
                _crate_faces(mb, m, (a + b) / 2, (y0 + y1) / 2, b - a - 0.06, y1 - y0 - 0.06, z, hb, kind)
                if last:
                    # the second lid overlaps the first by 2 cm (3 mm lower) and every lid runs 3 cm in under
                    # the next step, so a ray down a seam never slips through to the floor
                    lid_mat = {"crate": "M_Plank", "box": "M_Wood", "trunk": "M_Flat_roof_blue"}[kind]
                    dz = 0.003 if ci else 0.0
                    lids.append((a - (0.02 if ci else 0.0), y0, b, y1 + 0.03, top - 0.07 - dz, top - dz, lid_mat))
    goods = mb.build(f"{m.slug}_{body_name}", m.col_props, smooth=False)
    add_outline(goods, 0.022)
    solid(m, lid_name, lids, bevel=0.015)
    return goods


# ---------------------------------------------------------------------------
# map
# ---------------------------------------------------------------------------

def build(m):
    x0, y0, x1, y1 = ROOM
    # ---------------- shell: whitewash + blue wainscot over a flagstone floor ----------------
    cut_room(m, SHOP_H, wall_mat="M_Flat_cloth_white", knee_mat="M_Flat_roof_blue", base_mat="M_Flat_roof_blue",
             base_h=0.9, trim_mat="M_Wood_Dark", floor_mat="M_Flat_sand_mortar", planks=False)
    flag_floor(m, x0 + 0.25, y0 + 0.12, x1 - 0.12, y1 - 0.25)
    shop_frame(m, posts_back=(3.1, 12.4), posts_left=(6.0, 0.75))
    room_light(m, energy=2200, color=(1.0, 0.94, 0.85))

    # ---------------- Pan's kiosk (west wall) ----------------
    solid(m, "Kiosk_Stand", [(0.6, 6.9, 2.7, 10.3, -0.1, 0.45)], mat="M_Plank")
    m.npc("Pan", 1.85, 8.6, rot=55)
    m.place("X60001_PanKiosk", 1.95, 8.6, rot=90, z=0.0)
    # dress the kiosk's camera-facing arched side wall (outer face at y = 6.4)
    m.place("X60001_ShieldPlaque", 1.95, 6.38, rot=0, z=1.75)

    # ---------------- exit door (west wall, front) + the fishing-net / lobster-pot corner ----------------
    m.place("X60001_Door_Arch", x0 + WALL_T / 2 + 0.02, 2.7, rot=90, z=0.0)
    m.door_portal("out00", 1.35, 2.7, rot=90)
    m.place("Lifebuoy", x0 + WALL_T / 2 + 0.3, 4.4, rot=90, scale=1.2)
    m.place("X60001_ShipWheel", x0 + WALL_T / 2 + 0.05, 4.6, rot=90, z=3.6)
    m.place("X60001_NetWall", x0 + WALL_T / 2 + 0.02, 1.05, rot=90, z=0.0)
    m.place("X60001_LobsterPot", 1.45, 1.0, rot=12)
    m.place("X60001_LobsterPot", 2.45, 0.95, rot=-8)
    m.place("X60001_LobsterPot", 1.95, 1.0, rot=86, z=0.47, scale=0.9)
    m.place("X60001_NetPile", 2.3, 5.5, rot=-30)
    m.place("Rope_Coil", 1.15, 5.6)
    # classic T12: the low whitewashed entry step just inside the door, where the player appears
    solid(m, "Entry_Step", [(1.75, 1.95, 3.15, 3.45, -0.05, 0.3, "M_Flat_plaster"),
                            (1.7, 1.9, 3.2, 3.5, 0.26, 0.35, "M_Flat_cloth_white"),
                            (1.69, 1.89, 3.21, 1.95, 0.08, 0.2, "M_Flat_roof_blue"),
                            (3.15, 1.89, 3.21, 3.51, 0.08, 0.2, "M_Flat_roof_blue")], bevel=0.02)

    # ---------------- back wall under the beam: sea window + light shaft, shield rack, armor ----------------
    WX, WZB, WZR, WR = 5.0, 1.0, 2.5, 0.85
    m.place("X60001_SeaWindow", WX, y1 - WALL_T / 2, rot=0, z=0.0)
    m.place("X60001_ShieldWall", 8.4, y1 - WALL_T / 2 - 0.02, rot=0, z=0.0)
    m.place("X60001_KnightArmor", 9.7, 10.6, rot=10, z=0.0)        # the one full suit on display
    m.place("Armor_Stand", 10.9, 10.7, rot=-15, z=0.0, scale=1.1)
    # daylight through the window: a soft shaft down onto the floor + a sun patch + a warm spot
    d = (0.3, -1.0, -0.9)
    yw = y1 - WALL_T / 2 - 0.06
    outline = [(WX - WR, WZB), (WX + WR, WZB), (WX + WR, WZR)]
    outline += [(WX + math.cos(math.pi * k / 6) * WR, WZR + math.sin(math.pi * k / 6) * WR) for k in range(1, 6)]
    outline += [(WX - WR, WZR)]
    top_pts = [(x, yw, z) for (x, z) in outline]
    floor_pts = [(x + d[0] * z / -d[2], yw + d[1] * z / -d[2], 0.03) for (x, _y, z) in top_pts]
    shaft_mat = _shaft_material("M60001_LightShaft", 0.02, 0.32, color=(1.0, 0.9, 0.65, 1.0), strength=1.4)
    patch_mat = _shaft_material("M60001_SunPatch", 0.5, 0.5, color=(1.0, 0.88, 0.55, 1.0), strength=1.5)
    sh = MeshBuilder()
    n = len(top_pts)
    for i in range(n):
        a, b = top_pts[i], top_pts[(i + 1) % n]
        fa, fb = floor_pts[i], floor_pts[(i + 1) % n]
        sh.quad(m.w(*a), m.w(*b), m.w(*fb), m.w(*fa), shaft_mat.name)
    shaft = sh.build(f"{m.slug}_Light_Shaft", m.col_props, smooth=False, recalc_normals=False)
    shaft.visible_shadow = False
    shaft["passable"] = True      # light, not an obstacle
    pa = MeshBuilder()
    fl = [m.w(x, y, 0.025) for (x, y, _z) in floor_pts]
    for i in range(1, n - 1):
        pa.tri(tuple(fl[0]), tuple(fl[i]), tuple(fl[i + 1]), patch_mat.name)
    patch = pa.build(f"{m.slug}_Sun_Patch", m.col_props, smooth=False)
    patch.visible_shadow = False
    cx = sum(p[0] for p in floor_pts) / n
    cy = sum(p[1] for p in floor_pts) / n
    spot_light(m, (WX + 0.3, y1 - 0.9, 3.4), (cx, cy, 0.0), energy=260, size_deg=50, name="WindowSun")

    # ---------------- ware heap: crate staircase up the east wall to the wide shelf ----------------
    # real crates / lidded boxes / blue trunks whose plank lids are the walkable steps (barrels stand beside)
    steps = [(13.85, 3.2, 15.45, 4.3, 0.4, 0.0, ("box", "box"), 0.5),
             (13.95, 4.3, 15.5, 5.4, 0.8, 0.0, ("crate", "trunk"), 0.56),
             (13.8, 5.4, 15.45, 6.5, 1.2, 0.0, ("box1",), 0.5),
             (13.9, 6.5, 15.5, 7.6, 1.6, 0.0, ("trunk", "crate"), 0.45),
             (13.85, 7.6, 15.45, 8.7, 2.0, 0.0, ("box", "box"), 0.55),
             # top shelf (classic T1): two boxes stacked ON the wide shelf in the corner, two more hops up
             (14.2, 10.2, 15.5, 11.42, SHELF_Z + 0.4, SHELF_Z, ("box", "box"), 0.5),
             (14.8, 10.8, 15.46, 11.38, SHELF_Z + 0.8, SHELF_Z + 0.4, ("box1",), 0.5)]
    ware_heap(m, steps)
    # wide shelf (classic T4) across the back-right corner, plank top on posts
    solid(m, "Wide_Shelf", [(11.6, 8.7, 15.55, 11.45, SHELF_Z - 0.25, SHELF_Z)], mat="M_Flat_wood_dk")
    plank_floor(m, 11.65, 8.75, 15.5, 11.4, z=SHELF_Z, name="Shelf_Planks")
    legs = MeshBuilder()
    for (px, py) in ((11.75, 8.85), (11.75, 11.3), (13.7, 8.85), (15.4, 11.3)):
        lbox(legs, m, (0.22, 0.22, SHELF_Z - 0.25), (px, py, (SHELF_Z - 0.25) / 2), 0, "M_Wood_Dark")
    lbox(legs, m, (2.0, 0.1, 0.14), (12.75, 8.75, SHELF_Z - 0.32), 0, "M_Flat_roof_blue")
    legs.build(f"{m.slug}_Shelf_Legs", m.col_arch, smooth=False)
    # wares dressing the heap (kept off the walking line x 14.2..15.2)
    m.place("X60001_ShieldBarrel", 13.3, 4.0, rot=-20)
    m.place("Barrel", 13.35, 5.2, rot=0)
    m.place("Barrel", 13.2, 6.1, rot=40, scale=0.9)
    m.place("X60001_ChainmailStand", 13.15, 7.5, rot=35)
    m.place("X60001_HelmetPile", 14.05, 4.0, z=0.4, rot=160, scale=0.6)
    m.place("Rope_Coil", 14.15, 6.15, z=1.2, scale=0.8)
    m.place("X60001_HelmetPile", 13.98, 7.8, z=2.0, rot=66, scale=0.5)      # top step, west lip, shield to the back
    # wide shelf: a crate in the front-left corner (>= 1.5 m from WareHeap / TopShelf / Rafters) with a small
    # helmet heap beside it on the shelf's front lip
    m.place("Crate", 12.0, 9.05, z=SHELF_Z, rot=10, scale=0.6)
    m.place("X60001_HelmetPile", 12.75, 9.0, z=SHELF_Z, rot=15, scale=0.6)
    m.place("X60001_HelmetPile", 13.6, 11.0, z=SHELF_Z, rot=-35, scale=0.9)
    m.place("Barrel", 12.4, 9.8, z=0.0)
    m.place("Sack", 13.1, 10.6, z=0.0)
    m.place("Rope_Coil", 12.6, 11.0, z=0.0)

    # ---------------- ceiling beam (walkable) + rope from the shelf + a cargo net slung under it ----------------
    m.ladder("Rope_Beam", 11.95, 10.95, SHELF_Z, BEAM_Z, facing=180, kind="rope")
    banded_beam(m, "Ceiling_Beam", (3.35, 10.95), (11.62, 10.95), 1.1, 0.6, BEAM_Z, walkable=True)
    m.place("X60001_CargoNet", 10.15, 10.95, rot=0, z=BEAM_Z - 0.6)
    m.place("Hanging_Lantern", 3.6, 10.3, z=BEAM_Z - 0.6)
    m.place("Hanging_Lantern", 7.3, 10.3, z=BEAM_Z - 0.6)
    point_light(m, 7.0, 9.2, 3.2, energy=90, color=(1.0, 0.85, 0.6), radius=0.4, name="Lantern")

    # ---------------- shop floor dressing ----------------
    m.place("X60001_RugRope", 6.3, 4.8, rot=8, z=RUG_Z)
    m.place("Bench", 7.6, 2.0, rot=0)
    m.place("X60001_BootsCrate", 9.5, 2.2, rot=25)
    m.place("X60001_TabardMannequin", 10.6, 6.6, rot=25)
    m.place("X60001_GloveRack", 11.9, 5.0, rot=-20)
    m.place("X60001_Mirror", 12.0, 8.0, rot=-30, z=0.0)

    # ---------------- gameplay ----------------
    m.player(2.6, 2.7, rot=-60)   # on the entry step (classic spawn point)
    m.player_spawn(3.0, 2.7, rot=90, note="interior: just inside the door (out00), on the entry step")
    m.route("Main", [(1.35, 2.7), (3.9, 3.4), (4.5, 6.4), (4.2, 8.6)])
    # up the crate staircase; the last riser onto the wide shelf is taken head-on (+y), then across the shelf
    m.route("WareHeap", [(4.2, 8.6), (6.4, 7.6), (9.0, 4.2), (12.5, 2.6), (14.65, 2.6), (14.65, 5.0),
                         (14.65, 8.3), (14.65, 9.3), (14.0, 9.7), (12.3, 10.6)])
    # ends >0.6 m past the last riser and 0.4 m off the back wall (a body standing at y 11.3 touched it)
    m.route("TopShelf", [(13.6, 9.6), (14.6, 10.5), (15.35, 11.05)])
    # from the end of WareHeap up the rope (climbed mid-route) and along the walkable ceiling beam
    m.route("Rafters", [(12.3, 10.6), (11.8, 10.95), (11.45, 10.95), (11.0, 10.95), (4.2, 10.95)])
