"""Amherst Weapon Store (1010001) - "Sid's forge workshop".

Classic (GMS v8) structure, from docs/research/maps/1010001_AmherstWeaponStore_1010001.md:
  one 800 x 600 room: plank floor, timber post-and-beam frame with grey stone caps, roof planks
  lashed with dark-blue cord. Sid sells from a boarded wooden booth on the west side (standing on
  a raised stand). Back wall: a window full of big gears and an alcove holding a chained dark
  armor. East: the forge machine (domed furnace with a glowing mouth, green glass tank, pipes)
  with a zig-zag metal stair up to a scaffold deck; a rope from the deck to the ceiling beam.
  Sacks and a barrel stuffed with weapons by the east wall. Exit out00 on the floor, centre-left.

3D translation: a cutaway room on the interior stage (open toward the camera, knee-high near
wall). The booth stands against the west wall facing into the room, the gear window and the
armor alcove sit on the back wall under the high banded beam, and the forge fills the back-right
with a metal stair along the east wall up to the scaffold deck (pipe hump and tank-lid perches),
then a rope up to the beam that runs along the back wall. Walkable surfaces never overlap in
plan (the ground is found by a top-down raycast).

The shared interior helpers (``cut_room``, stone-capped ``shop_frame``, banded beams, plank floors,
walkable blocks, sign text, interior lights) live in ``misostory.kit.interior``.
"""

import math

from mathutils import Vector

from misostory import collision_tags as CT
from misostory.geo import MeshBuilder
from misostory.kit import asset
from misostory.kit.architecture import shop_sign
from misostory.kit.interior import (BAND, ROOM, RUG_Z, SHOP_H, WALL_T, banded_beam, cut_room, lbox, lcyl, plank_floor,
                                    point_light, room_light, shop_frame, solid)

MAP_ID = 1010001
GAMEPLAY_FOCUS = (8.0, 7.6)
GAMEPLAY_SCALE = 20.0


# ===========================================================================
# WEAPON STORE ASSETS
# ===========================================================================

@asset("X1010001_SidBooth", "Architecture", footprint=4.6, tags=("interior", "shop"))
def _sid_booth(coll):
    """Boarded wooden weapon stall. Front (counter) faces -Y; back panel at +Y against the wall.

    Width 4.4 along X, depth 2.8. The shopkeeper stands on a 0.45 m stand (built walkable in the map).
    """
    mb = MeshBuilder()
    W, Dp = 4.4, 2.8
    # back panel with weapon pegs
    mb.box((W, 0.2, 3.0), loc=(0, Dp / 2 - 0.1, 1.5), mat="M_Plank", bevel=0.03, segs=1)
    for k in range(6):
        mb.box((W + 0.05, 0.22, 0.07), loc=(0, Dp / 2 - 0.1, 0.4 + k * 0.5), mat="M_Wood_Dark")
    for k, x in enumerate((-1.5, -0.9, -0.3, 0.3, 0.9, 1.5)):
        mb.box((0.1, 0.06, 1.1), loc=(x, Dp / 2 - 0.26, 2.05), rot=(0, (k - 2.5) * 5, 0), mat="M_Metal")
        mb.box((0.34, 0.08, 0.07), loc=(x, Dp / 2 - 0.28, 1.5), mat="M_Gold")
        mb.box((0.08, 0.08, 0.26), loc=(x, Dp / 2 - 0.28, 1.33), mat="M_Wood_Dark")
    # side panels (boarded, slightly ragged tops)
    for s in (-1, 1):
        for k in range(5):
            hgt = 2.2 + (0.18 if k % 2 else 0.0) - k * 0.06
            mb.box((0.14, 0.52, hgt), loc=(s * (W / 2 - 0.07), -Dp / 2 + 0.3 + k * 0.53, hgt / 2), mat="M_Plank",
                   bevel=0.025, segs=1)
        mb.box((0.18, Dp, 0.12), loc=(s * (W / 2 - 0.07), 0, 1.0), mat="M_Wood_Dark")
    # counter: plank front + thick top
    mb.box((W - 0.3, 0.5, 1.1), loc=(0, -Dp / 2 + 0.25, 0.55), mat="M_Wood", bevel=0.03, segs=1)
    for k in range(7):
        mb.box((0.06, 0.04, 1.0), loc=(-1.8 + k * 0.6, -Dp / 2 - 0.01, 0.55), mat="M_Wood_Dark")
    mb.box((W, 0.75, 0.14), loc=(0, -Dp / 2 + 0.25, 1.15), mat="M_Plank", bevel=0.03, segs=1)
    # front posts (open above the counter so the keeper stays visible) + title board on the back panel
    for s in (-1, 1):
        mb.box((0.24, 0.24, 2.6), loc=(s * (W / 2 - 0.05), -Dp / 2, 1.3), mat="M_Wood_Dark", bevel=0.03, segs=1)
        mb.box((0.36, 0.36, 0.3), loc=(s * (W / 2 - 0.05), -Dp / 2, 0.15), mat="M_Flat_stone_wall", bevel=0.04)
        mb.sphere(0.17, loc=(s * (W / 2 - 0.05), -Dp / 2, 2.68), mat="M_Gold", subdiv=1)
    by = Dp / 2 - 0.26
    mb.box((W - 0.4, 0.16, 0.7), loc=(0, by, 3.4), mat="M_Plank", bevel=0.04, segs=1)
    mb.box((W - 0.3, 0.2, 0.1), loc=(0, by, 3.02), mat="M_Wood_Dark")
    mb.box((W - 0.3, 0.2, 0.1), loc=(0, by, 3.78), mat="M_Wood_Dark")
    for s in (-1, 1):
        mb.box((0.1, 0.06, 0.95), loc=(s * 0.2, by - 0.12, 3.4), rot=(0, s * 40, 0), mat="M_Metal")
        mb.box((0.28, 0.07, 0.06), loc=(s * 0.36, by - 0.13, 3.18), rot=(0, s * 40, 0), mat="M_Gold")
        mb.cyl(0.2, 0.06, loc=(s * 1.3, by - 0.08, 3.4), rot=(90, 0, 0), mat="M_Flat_roof_red", verts=12)
    for s in (-1, 1):  # side rails tie the front posts to the back panel
        mb.box((0.12, Dp, 0.12), loc=(s * (W / 2 - 0.05), 0.0, 2.3), mat="M_Wood_Dark")
    # little wares on the counter
    mb.box((0.7, 0.3, 0.08), loc=(-1.1, -Dp / 2 + 0.3, 1.26), mat="M_Metal")
    mb.box((0.25, 0.22, 0.18), loc=(1.2, -Dp / 2 + 0.25, 1.31), mat="M_Flat_gold")
    mb.build("X1010001_SidBooth", coll, smooth=False)


FORGE_CHIMNEY = (0.76, 0.36)   # forge-local chimney position


@asset("X1010001_Forge", "Props", footprint=3.0, tags=("interior", "landmark"))
def _forge(coll):
    """Domed stone furnace with a glowing mouth (faces -Y), iron hoops, chimney pipe and a red gauge."""
    mb = MeshBuilder()
    R = 1.3
    mb.cyl(R + 0.15, 0.35, mat="M_Flat_rock_dk", verts=20)
    mb.cyl(R, 1.25, loc=(0, 0, 0.3), mat="M_StoneWall", verts=20)
    mb.dome(R, 1.05, loc=(0, 0, 1.55), mat="M_Rock", u=20, v=5, profile=0.8, underside=False)
    for z in (0.55, 1.5):
        mb.cyl(R + 0.06, 0.12, loc=(0, 0, z), mat=BAND, verts=20)
    # mouth: dark arch frame + glowing coals
    mb.box((1.0, 0.5, 0.8), loc=(0, -R + 0.12, 0.85), mat="M_Flat_rock_dk", bevel=0.06, segs=1)
    mb.cyl(0.5, 0.5, loc=(0, -R - 0.13, 1.25), rot=(-90, 0, 0), mat="M_Flat_rock_dk", verts=14)
    mb.box((0.74, 0.1, 0.6), loc=(0, -R - 0.15, 0.82), mat="M_Glow_roof_orange")
    mb.cyl(0.37, 0.1, loc=(0, -R - 0.2, 1.12), rot=(-90, 0, 0), mat="M_Glow_roof_orange", verts=12)
    mb.sphere(0.2, loc=(-0.15, -R - 0.15, 0.62), mat="M_Glow_flower_yellow", subdiv=1)
    mb.sphere(0.16, loc=(0.18, -R - 0.17, 0.66), mat="M_Glow_flower_yellow", subdiv=1)
    # chimney pipe (to the roof) + collars. It rises from the dome's back-right shoulder so that, at
    # the map's rot=35, it stands right of the armor alcove on screen (screen-x ~ x + y) instead of
    # in front of it; the base is buried in the dome (surface z ~2.1-2.5 at this radius).
    cx, cy = FORGE_CHIMNEY
    mb.cyl(0.3, 5.1, loc=(cx, cy, 1.6), mat="M_Metal", verts=12)
    for z in (2.8, 3.95, 5.1):
        mb.cyl(0.36, 0.12, loc=(cx, cy, z), mat=BAND, verts=12)
    # bellows on the side
    mb.box((0.7, 0.9, 0.3), loc=(R + 0.25, -0.2, 0.55), rot=(0, 0, 20), mat="M_Flat_wood_dk", bevel=0.08)
    mb.box((0.12, 0.6, 0.06), loc=(R + 0.55, -0.6, 0.62), rot=(0, 0, 20), mat="M_Wood")
    # pressure gauge on a pipe stub
    mb.cyl(0.08, 0.5, loc=(0.9, -0.85, 1.6), rot=(0, 0, 0), mat="M_Metal", verts=8)
    mb.cyl(0.24, 0.1, loc=(0.9, -0.82, 2.25), rot=(-90, 0, 0), mat="M_Flat_cloth_red", verts=16)
    mb.cyl(0.18, 0.11, loc=(0.9, -0.84, 2.25), rot=(-90, 0, 0), mat="M_Flat_cloth_white", verts=16)
    mb.box((0.03, 0.03, 0.14), loc=(0.93, -0.96, 2.28), rot=(0, 35, 0), mat="M_Eye_Black")
    mb.build("X1010001_Forge", coll, smooth=True, sharp_angle=40)


@asset("X1010001_GlassTank", "Props", footprint=1.1, tags=("interior",))
def _glass_tank(coll):
    """Green glass tank with iron hoops and a domed lid (the forge's coolant tank)."""
    mb = MeshBuilder()
    mb.cyl(0.55, 0.12, mat="M_Metal", verts=16)
    mb.cyl(0.46, 0.62, loc=(0, 0, 0.1), mat="M_Glow_leaf_b_lt", verts=16)
    for z in (0.12, 0.42, 0.7):
        mb.cyl(0.5, 0.07, loc=(0, 0, z), mat="M_Metal", verts=16)
    mb.dome(0.52, 0.12, loc=(0, 0, 0.72), mat="M_Metal", u=16, v=3)
    for k in range(5):
        mb.sphere(0.05, loc=(0.2 * math.cos(k * 1.3), -0.3, 0.25 + k * 0.08), mat="M_Glow_cloth_white", subdiv=1)
    mb.build("X1010001_GlassTank", coll, smooth=True, sharp_angle=40)


@asset("X1010001_Anvil", "Props", footprint=1.0, tags=("interior",))
def _anvil(coll):
    mb = MeshBuilder()
    mb.cyl(0.38, 0.5, mat="M_Bark", verts=12, r2=0.34)
    mb.box((0.36, 0.28, 0.22), loc=(0, 0, 0.6), mat="M_Flat_rock_dk")
    mb.box((0.72, 0.36, 0.2), loc=(0.05, 0, 0.8), mat="M_Flat_rock_dk", bevel=0.03, segs=1)
    mb.cyl(0.15, 0.4, loc=(0.4, 0, 0.81), rot=(0, 90, 0), mat="M_Flat_rock_dk", verts=10, r2=0.02)
    mb.box((0.08, 0.5, 0.08), loc=(-0.1, -0.05, 0.94), rot=(0, 0, 25), mat="M_Wood")
    mb.box((0.14, 0.12, 0.24), loc=(-0.2, 0.17, 0.95), rot=(0, 0, 25), mat="M_Metal")
    mb.build("X1010001_Anvil", coll, smooth=True, sharp_angle=40)


@asset("X1010001_Grindstone", "Props", footprint=1.2, tags=("interior",))
def _grindstone(coll):
    mb = MeshBuilder()
    for s in (-1, 1):
        mb.box((0.1, 0.6, 1.0), loc=(s * 0.25, 0, 0.5), mat="M_Wood_Dark")
    mb.box((0.62, 0.7, 0.1), loc=(0, 0, 0.12), mat="M_Wood")
    mb.cyl(0.45, 0.2, loc=(-0.1, 0, 0.95), rot=(0, 90, 0), mat="M_Flat_rock", verts=18)
    mb.cyl(0.05, 0.75, loc=(-0.37, 0, 0.95), rot=(0, 90, 0), mat="M_Metal", verts=6)
    mb.box((0.06, 0.06, 0.3), loc=(0.38, 0, 0.82), mat="M_Metal")
    mb.cyl(0.03, 0.18, loc=(0.38, 0, 0.67), rot=(0, 90, 0), mat="M_Wood", verts=6)
    mb.cyl(0.32, 0.18, loc=(0, -0.05, 0.18), mat="M_Water", verts=12)
    mb.build("X1010001_Grindstone", coll, smooth=True, sharp_angle=40)


@asset("X1010001_WeaponBarrel", "Props", footprint=1.0, tags=("interior",))
def _weapon_barrel(coll):
    """Barrel stuffed with swords, an axe and a club."""
    mb = MeshBuilder()
    mb.cyl(0.4, 0.5, mat="M_Wood", verts=14, r2=0.47)
    mb.cyl(0.47, 0.5, loc=(0, 0, 0.5), mat="M_Wood", verts=14, r2=0.4)
    for z in (0.12, 0.5, 0.88):
        mb.cyl(0.48 - abs(z - 0.5) * 0.18, 0.07, loc=(0, 0, z - 0.035), mat="M_Metal", verts=14)
    for k, (x, y, tx, ty) in enumerate(((-0.15, -0.1, -14, 8), (0.12, 0.05, 10, -6), (0.0, 0.18, 4, 14),
                                        (0.2, -0.15, 18, 10))):
        mb.box((0.09, 0.05, 1.0), loc=(x, y, 1.35), rot=(tx, ty, 0), mat="M_Metal")
        mb.box((0.34, 0.08, 0.07), loc=(x, y, 0.95), rot=(tx, ty, 0), mat="M_Gold")
    mb.cyl(0.035, 0.9, loc=(-0.12, 0.1, 0.8), rot=(-10, -12, 0), mat="M_Wood", verts=6)
    mb.box((0.36, 0.06, 0.28), loc=(-0.24, 0.1, 1.66), rot=(-10, -12, 0), mat="M_Metal", bevel=0.03, segs=1)
    mb.cyl(0.09, 0.7, loc=(0.18, 0.2, 0.8), rot=(12, 10, 0), mat="M_Wood_Dark", verts=8, r2=0.14)
    mb.build("X1010001_WeaponBarrel", coll, smooth=True, sharp_angle=40)


def _gear_poly(n, r_out, r_in):
    pts = []
    for i in range(n):
        a0 = 2 * math.pi * i / n
        da = 2 * math.pi / n
        for f, r in ((0.0, r_in), (0.18, r_out), (0.5, r_out), (0.68, r_in)):
            a = a0 + da * f
            pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


@asset("X1010001_GearWindow", "Architecture", footprint=2.4, tags=("interior",))
def _gear_window(coll):
    """Round window in the back wall full of big meshing gears (faces -Y, flat on a wall)."""
    mb = MeshBuilder()
    zc = 2.15
    mb.cyl(1.25, 0.2, loc=(0, 0.05, zc), rot=(90, 0, 0), mat="M_Wood_Dark", verts=24)
    mb.torus(1.12, 0.14, loc=(0, -0.08, zc), rot=(90, 0, 0), mat="M_Flat_stone_wall", u=24, v=6)
    mb.cyl(1.05, 0.05, loc=(0, -0.02, zc), rot=(90, 0, 0), mat="M_Flat_water_dk", verts=24)
    for (gx, gz, r, n, mat) in ((-0.3, 0.2, 0.66, 12, "M_Gold"), (0.48, -0.36, 0.44, 9, "M_Metal"),
                                (0.42, 0.52, 0.3, 7, "M_Flat_roof_orange"), (-0.45, -0.62, 0.3, 7, "M_Metal")):
        mb.prism(_gear_poly(n, r, r * 0.78), 0.0, 0.1, loc=(gx, -0.06, zc + gz), rot=(90, 0, 0), mat=mat)
        mb.cyl(r * 0.28, 0.14, loc=(gx, -0.1, zc + gz), rot=(90, 0, 0), mat="M_Flat_rock_dk", verts=10)
        mb.cyl(r * 0.1, 0.18, loc=(gx, -0.12, zc + gz), rot=(90, 0, 0), mat="M_Gold", verts=8)
    mb.build("X1010001_GearWindow", coll, smooth=True, sharp_angle=40)


@asset("X1010001_ArmorAlcove", "Architecture", footprint=1.8, tags=("interior",))
def _armor_alcove(coll):
    """Stone-framed arched wall alcove with a chained dark suit of armor (faces -Y)."""
    mb = MeshBuilder()
    w, h = 1.4, 2.3
    mb.box((w + 0.4, 0.3, 0.42), loc=(0, -0.05, 0.21), mat="M_Flat_stone_wall", bevel=0.05, segs=1)  # sill
    for s in (-1, 1):
        mb.box((0.26, 0.3, h), loc=(s * (w / 2 + 0.07), 0.0, h / 2 + 0.3), mat="M_Flat_stone_wall", bevel=0.04)
    mb.torus(w / 2 + 0.07, 0.14, loc=(0, 0.0, h + 0.3), rot=(90, 0, 0), mat="M_Flat_stone_wall", u=20, v=5)
    mb.box((w, 0.08, h), loc=(0, 0.1, h / 2 + 0.3), mat="M_Flat_rock_dk")
    mb.cyl(w / 2, 0.08, loc=(0, 0.14, h + 0.3), rot=(90, 0, 0), mat="M_Flat_rock_dk", verts=16)
    # the dark armor
    mb.box((0.5, 0.3, 0.6), loc=(0, -0.05, 1.2), mat="M_Flat_hair_black", bevel=0.1)
    mb.sphere(0.2, loc=(0, -0.05, 1.68), mat="M_Flat_hair_black", subdiv=2)
    mb.box((0.26, 0.04, 0.05), loc=(0, -0.24, 1.7), mat="M_Glow_roof_red")
    for s in (-1, 1):
        mb.sphere(0.16, loc=(s * 0.32, -0.05, 1.42), mat="M_Flat_rock_dk", subdiv=2)
        mb.box((0.14, 0.18, 0.5), loc=(s * 0.36, -0.05, 1.05), mat="M_Flat_hair_black")
        mb.box((0.16, 0.2, 0.6), loc=(s * 0.13, -0.05, 0.62), mat="M_Flat_hair_black")
    # chains from the frame to the shoulders
    for s in (-1, 1):
        for k in range(5):
            t = k / 4
            mb.torus(0.05, 0.015, loc=(s * (0.68 - t * 0.33), -0.12, 2.25 - t * 0.75),
                     rot=(90 if k % 2 else 0, 0, s * 30), mat="M_Metal", u=8, v=4)
    mb.build("X1010001_ArmorAlcove", coll, smooth=True, sharp_angle=40)


@asset("X1010001_CrossedSwords", "Architecture", footprint=1.0, tags=("interior",))
def _crossed_swords(coll):
    """Wall plaque: round shield with two crossed swords (faces -Y)."""
    mb = MeshBuilder()
    mb.cyl(0.42, 0.1, loc=(0, 0.0, 0), rot=(90, 0, 0), mat="M_Flat_roof_blue", verts=16)
    mb.cyl(0.14, 0.12, loc=(0, -0.05, 0), rot=(90, 0, 0), mat="M_Gold", verts=10)
    for s in (-1, 1):
        mb.box((0.08, 0.05, 1.3), loc=(0, -0.12, 0), rot=(0, s * 40, 0), mat="M_Metal")
        mb.box((0.3, 0.07, 0.06), loc=(s * 0.33, -0.13, -0.4), rot=(0, s * 40, 0), mat="M_Gold")
    mb.build("X1010001_CrossedSwords", coll, smooth=True, sharp_angle=40)


@asset("X1010001_WeaponSign", "Architecture", footprint=1.4, tags=("interior", "sign"))
def _weapon_sign(coll):
    mb = MeshBuilder()
    shop_sign(mb, "weapon", (0, 0, 0))
    mb.build("X1010001_WeaponSign", coll, smooth=False)


@asset("X1010001_PipeRun", "Architecture", footprint=4.0, tags=("interior",))
def _pipe_run(coll):
    """4 m horizontal pipe along +X with brass joints and wall brackets (wall at +Y)."""
    mb = MeshBuilder()
    mb.cyl(0.13, 4.0, loc=(0, 0, 0), rot=(0, 90, 0), mat="M_Metal", verts=10)
    for x in (0.0, 1.35, 2.7, 4.0):
        mb.cyl(0.17, 0.16, loc=(x - 0.08, 0, 0), rot=(0, 90, 0), mat="M_Gold", verts=10)
        mb.box((0.08, 0.3, 0.08), loc=(x, 0.15, 0), mat="M_Flat_rock_dk")
    mb.build("X1010001_PipeRun", coll, smooth=True, sharp_angle=40)


@asset("X1010001_DisplayBench", "Props", footprint=2.0, tags=("interior",))
def _display_bench(coll):
    """Low plank bench with swords, an axe and a round shield laid out for sale."""
    mb = MeshBuilder()
    mb.box((2.0, 0.8, 0.12), loc=(0, 0, 0.6), mat="M_Plank", bevel=0.03, segs=1)
    for x in (-0.85, 0.85):
        for y in (-0.3, 0.3):
            mb.box((0.1, 0.1, 0.6), loc=(x, y, 0.3), mat="M_Wood_Dark")
    mb.box((1.9, 0.7, 0.04), loc=(0, 0, 0.68), mat="M_Flat_cloth_red")
    for k, x in enumerate((-0.6, -0.25)):
        mb.box((0.12, 0.95, 0.04), loc=(x, 0.0, 0.72), rot=(0, 0, 8 - k * 16), mat="M_Metal")
        mb.box((0.4, 0.08, 0.06), loc=(x, -0.3, 0.73), rot=(0, 0, 8 - k * 16), mat="M_Gold")
    mb.cyl(0.3, 0.06, loc=(0.5, 0.05, 0.7), mat="M_Flat_roof_blue", verts=14)
    mb.cyl(0.1, 0.08, loc=(0.5, 0.05, 0.71), mat="M_Gold", verts=8)
    mb.box((0.06, 0.6, 0.05), loc=(0.15, 0.1, 0.72), rot=(0, 0, -30), mat="M_Wood")
    mb.box((0.25, 0.04, 0.2), loc=(0.07, -0.18, 0.74), rot=(90, 0, -30), mat="M_Metal")
    mb.build("X1010001_DisplayBench", coll, smooth=False)


@asset("X1010001_QuenchTub", "Props", footprint=1.0, tags=("interior",))
def _quench_tub(coll):
    """Half-barrel of water for quenching hot blades, with tongs."""
    mb = MeshBuilder()
    mb.cyl(0.5, 0.5, mat="M_Wood", verts=14, r2=0.55)
    for z in (0.08, 0.38):
        mb.cyl(0.54, 0.06, loc=(0, 0, z), mat="M_Metal", verts=14)
    mb.cyl(0.47, 0.04, loc=(0, 0, 0.42), mat="M_Water", verts=14)
    mb.box((0.04, 0.04, 0.8), loc=(0.2, 0.0, 0.6), rot=(0, 25, 0), mat="M_Flat_rock_dk")
    mb.box((0.04, 0.04, 0.8), loc=(0.26, 0.04, 0.6), rot=(0, 30, 0), mat="M_Flat_rock_dk")
    mb.build("X1010001_QuenchTub", coll, smooth=True, sharp_angle=40)


# ===========================================================================
# MAP
# ===========================================================================

DECK_Z = 2.4
BEAM_Z = 5.0


def build(m):
    x0, y0, x1, y1 = ROOM
    # ---------------- shell ----------------
    cut_room(m, SHOP_H, wall_mat="M_Stone_Cliff", knee_mat="M_StoneWall", base_mat="M_StoneWall", base_h=0.9,
             trim_mat="M_Wood_Dark")
    shop_frame(m, posts_back=(3.1, 12.4), posts_left=(6.0, 0.75))
    room_light(m, energy=2400)

    # ---------------- Sid's booth (west wall, facing into the room) ----------------
    solid(m, "Booth_Stand", [(0.6, 6.9, 2.7, 10.3, -0.1, 0.45)], mat="M_Plank")
    m.npc("Sid", 1.75, 8.6, rot=55)
    m.place("X1010001_SidBooth", 1.95, 8.6, rot=90, z=0.0)
    # hung from the booth's front-left post: the arm's far end meets the post top (3.35, 6.45, ~2.7)
    m.place("X1010001_WeaponSign", 3.8, 6.0, rot=45, z=2.1, required=False)

    # ---------------- exit door (west wall, front) ----------------
    m.place("Door_Plank", x0 + WALL_T / 2 + 0.02, 2.7, rot=90, z=0.0)
    m.door_portal("out00", 1.35, 2.7, rot=90)
    m.place("X1010001_CrossedSwords", x0 + WALL_T / 2 + 0.05, 4.75, rot=90, z=2.75)
    m.place("Weapon_Rack", x0 + WALL_T / 2 + 0.2, 4.75, rot=90, z=0.0)

    # ---------------- back wall: gear window + chained armor alcove ----------------
    m.place("X1010001_GearWindow", 4.6, y1 - WALL_T / 2, rot=0, z=0.0)
    m.place("X1010001_ArmorAlcove", 6.8, y1 - WALL_T / 2 - 0.12, rot=0, z=0.0)
    m.place("X1010001_PipeRun", x0 + WALL_T / 2 + 0.17, 6.6, rot=90, z=3.7)

    # ---------------- forge (back-right) ----------------
    m.place("X1010001_Forge", 9.85, 9.0, rot=35, z=0.0)
    point_light(m, 10.85, 7.55, 1.0, energy=180, color=(1.0, 0.55, 0.2), radius=0.5, name="ForgeGlow")
    # scaffold deck over the back-right corner + metal stair up the east wall
    solid(m, "Scaffold_Deck", [(11.6, 9.2, 15.55, 11.45, DECK_Z - 0.22, DECK_Z)], mat="M_Flat_wood_dk")
    plank_floor(m, 11.65, 9.25, 15.5, 11.4, z=DECK_Z, name="Deck_Planks")
    deck_frame = MeshBuilder()
    for (px, py) in ((11.75, 9.35), (11.75, 11.3), (13.9, 9.35), (15.4, 11.3)):
        lbox(deck_frame, m, (0.2, 0.2, DECK_Z - 0.2), (px, py, (DECK_Z - 0.2) / 2), 0, "M_Wood_Dark")
    for k in range(4):  # grating slats + rail
        lbox(deck_frame, m, (0.05, 2.2, 0.03), (12.1 + k * 0.85, 10.3, DECK_Z + 0.01), 0, "M_Metal")
    lbox(deck_frame, m, (2.25, 0.08, 0.08), (12.78, 9.25, DECK_Z + 0.95), 0, "M_Flat_roof_yellow")
    for px in (11.7, 12.8, 13.9):
        lbox(deck_frame, m, (0.08, 0.08, 0.95), (px, 9.25, DECK_Z + 0.47), 0, "M_Flat_roof_yellow")
    CT.tag(deck_frame.build(f"{m.slug}_Scaffold_Frame", m.col_arch, smooth=False), CT.WALL)
    m.stairs("Forge_Stair", (14.75, 3.3, 0.0), (14.75, 9.0, DECK_Z), 1.35, mat="M_Metal", side_mat="M_Wood_Dark")
    # perches on the deck: pipe hump then the glass tank lid (classic T09 / T10)
    m.collider("Pipe_Hump", [(13.35, 10.45, DECK_Z, 14.15, 11.4, DECK_Z + 0.42)])  # walkable top of the hump
    hp = MeshBuilder()
    lcyl(hp, m, 0.44, 1.2, (13.75, 10.3, DECK_Z - 0.02), mat="M_Metal", verts=16, rot=(-90, 0, 0))
    for yy in (10.45, 11.3):
        lcyl(hp, m, 0.5, 0.12, (13.75, yy, DECK_Z - 0.02), mat="M_Gold", verts=16, rot=(-90, 0, 0))
    CT.tag(hp.build(f"{m.slug}_Pipe_Hump_Vis", m.col_arch, smooth=True), CT.WALL)
    m.collider("Tank_Lid", cylinders=[(14.85, 10.9, 0.5, DECK_Z, DECK_Z + 0.78)])  # walkable lid of the glass tank
    m.place("X1010001_GlassTank", 14.85, 10.9, z=DECK_Z)
    # round pipes with brass collars (dome shoulder -> along the back wall -> pipe hump; forge -> deck post)
    pipes = MeshBuilder()
    for run in ([(10.85, 9.35, 2.1), (11.6, 11.25, 3.1), (13.4, 11.25, 2.75)],
                [(10.9, 8.6, 1.0), (11.75, 9.2, 1.4)]):
        dirs = []
        for a, b in zip(run, run[1:]):
            d = Vector(b) - Vector(a)
            yaw = math.degrees(math.atan2(d.y, d.x))
            pitch = math.degrees(math.atan2(d.z, math.hypot(d.x, d.y)))
            lcyl(pipes, m, 0.13, d.length, a, mat="M_Metal", verts=10, rot=(0, 90 - pitch, yaw))
            dirs.append((d.normalized(), yaw, pitch))
        for k, p in enumerate(run):
            dn, yaw, pitch = dirs[min(k, len(dirs) - 1)]
            base = Vector(p) - dn * 0.07
            lcyl(pipes, m, 0.17, 0.14, tuple(base), mat="M_Gold", verts=10, rot=(0, 90 - pitch, yaw))
    CT.tag(pipes.build(f"{m.slug}_Forge_Pipes", m.col_arch, smooth=True), CT.WALL)

    # ---------------- high beam + rope (classic ceiling beam, walkable) ----------------
    m.ladder("Rope_Beam", 11.95, 10.95, DECK_Z, BEAM_Z, facing=180, kind="rope")
    banded_beam(m, "Ceiling_Beam", (3.35, 10.95), (11.62, 10.95), 1.1, 0.6, BEAM_Z, walkable=True)
    m.place("Hanging_Lantern", 3.6, 10.3, z=BEAM_Z - 0.6)
    m.place("Hanging_Lantern", 9.0, 10.3, z=BEAM_Z - 0.6)
    point_light(m, 7.0, 9.2, 3.2, energy=90, color=(1.0, 0.8, 0.5), radius=0.4, name="Lantern")

    # yellow handrail along the open (west) side of the metal stair, matching the deck rail
    rail = MeshBuilder()
    rx = 14.12

    def rail_z(yy):
        return 0.95 + DECK_Z * (yy - 3.3) / 5.7

    ys = (3.55, 4.9, 6.25, 7.6, 8.95)
    for yy in ys:
        gz = m.ground_z(rx + 0.1, yy) or 0.0
        lbox(rail, m, (0.08, 0.08, rail_z(yy) - gz), (rx, yy, (rail_z(yy) + gz) / 2), 0, "M_Flat_roof_yellow")
    za, zb = rail_z(ys[0]), rail_z(ys[-1])
    lbox(rail, m, (0.09, math.hypot(ys[-1] - ys[0], zb - za), 0.09), (rx, (ys[0] + ys[-1]) / 2, (za + zb) / 2), 0,
         "M_Flat_roof_yellow", tilt=(math.degrees(math.atan2(zb - za, ys[-1] - ys[0])), 0))
    CT.tag(rail.build(f"{m.slug}_Stair_Rail", m.col_arch, smooth=False), CT.WALL)

    # ---------------- workshop floor dressing ----------------
    m.place("Rug_Round", 6.9, 5.5, rot=10, scale=(1.0, 0.8, 1.0), z=RUG_Z)
    m.place("X1010001_Anvil", 10.6, 5.6, rot=-25)
    m.place("X1010001_Grindstone", 12.4, 6.6, rot=-60)
    m.place("Weapon_Rack", 5.5, 1.3, rot=15)
    m.place("Armor_Stand", 2.9, 5.3, rot=60)
    m.place("X1010001_WeaponBarrel", 13.4, 1.5, rot=20)
    m.place("X1010001_WeaponBarrel", 13.35, 4.5, rot=-40)
    m.place("Sack", 13.6, 11.0, z=0.0, rot=-10)
    m.place("Crate", 15.0, 1.0, rot=10)
    m.place("X1010001_DisplayBench", 7.6, 2.3, rot=15)
    m.place("Crate", 2.4, 1.2, rot=25)
    m.place("Crate", 3.2, 0.9, rot=-10, scale=0.8)
    m.place("X1010001_QuenchTub", 9.2, 5.9, rot=0)
    m.place("Sack", 1.2, 5.9, rot=40)

    # ---------------- gameplay ----------------
    m.player(5.2, 3.6, rot=-60)
    m.player_spawn(3.0, 2.7, rot=90, note="interior: just inside the door (out00)")
    m.route("Main", [(1.35, 2.7), (3.6, 3.4), (4.4, 6.4), (4.2, 8.6)])
    # (the validator's 1.2 m slope window flags any route that runs through a rope, so the climb is
    #  split: up the stair to the rope foot, then from the rope head along the beam)
    m.route("ForgeClimb", [(4.2, 8.6), (6.5, 6.8), (9.0, 4.0), (12.5, 2.8), (14.75, 2.6), (14.75, 6.0),
                           (14.75, 9.5), (13.4, 10.0), (12.3, 10.6)])
    m.route("Rafters", [(11.3, 10.95), (4.2, 10.95)])
    # two samples straddling the rope climb (deck -> beam); the deck end stands 0.15 m off the beam line, clear of
    # the back post's stone cap
    m.route("Rope", [(11.8, 10.8), (11.45, 10.95)])
    m.route("Perches", [(12.6, 9.8), (13.75, 10.9), (14.85, 10.9)])
