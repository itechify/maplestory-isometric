"""Characters and monsters: chibi player proxy, parametric NPCs, stylized mobs.

Scale reference: the player proxy is 1.5 m tall (chibi, ~2.5 heads). Monsters are
scaled from the classic sprites at ~0.021 m per sprite pixel (NPC sprites ~70 px).
Everything faces -Y at rotation 0.
"""

import math

from mathutils import Matrix

from ..geo import MeshBuilder
from . import REGISTRY, asset

# Monster proxy scale on top of the modelled size (classic sprite px vs. a ~65 px player sprite, plus a little
# MapleStory exaggeration so mobs read at the 30-40 m Gameplay ortho scales). Heights with the 1.5 m player:
# Snail ~0.70 m (37x26 px sprite), Blue/Red Snail ~0.77 m (35x34 px), Shroom ~0.78 m (36x36 px),
# Orange Mushroom ~1.21 m (63x58 px).
MOB_SCALE = {"Mob_Snail": 1.25, "Mob_BlueSnail": 1.35, "Mob_RedSnail": 1.35, "Mob_Shroom": 1.15,
             "Mob_OrangeMushroom": 1.1}


def _rescale(coll, name):
    """Scale an asset's meshes about the ground-contact origin (the ink outline is added afterwards by
    kit.ensure, so its thickness is unaffected)."""
    m = Matrix.Scale(MOB_SCALE.get(name, 1.0), 4)
    for ob in coll.objects:
        if ob.type == "MESH":
            ob.data.transform(m)


# ---------------------------------------------------------------------------
# Chibi humanoid
# ---------------------------------------------------------------------------

def _eyes(mb, cx, cy, cz, spacing, size=0.07, height=1.6):
    for s in (-1, 1):
        mb.sphere(size, loc=(cx + s * spacing, cy, cz), scale=(0.75, 0.45, height), mat="M_Eye_Black", subdiv=1)
        mb.sphere(size * 0.32, loc=(cx + s * spacing + 0.015, cy - size * 0.35, cz + size * 0.5),
                  mat="M_Eye_White", subdiv=1)


def chibi(mb, hair="hair_brown", top="player_blue", bottom="wood_dk", skin="M_Skin", hat=None, extra=None,
          hat_color="roof_red", long_hair=False, skirt=False, scale=1.0, extras=(), coat=None, pigtails=False,
          shoes="wood_dk"):
    s = scale
    H = f"M_Flat_{hair}"
    T = f"M_Flat_{top}"
    B = f"M_Flat_{bottom}"
    # legs / shoes
    for x in (-0.1, 0.1):
        mb.cyl(0.075 * s, 0.3 * s, loc=(x * s, 0, 0.04 * s), mat=B, verts=8)
        mb.sphere(0.09 * s, loc=(x * s, -0.03 * s, 0.05 * s), scale=(1, 1.4, 0.6), mat=f"M_Flat_{shoes}", subdiv=1)
    # body
    if coat:
        mb.cyl(0.27 * s, 0.66 * s, loc=(0, 0, 0.1 * s), mat=f"M_Flat_{coat}", verts=12, r2=0.2 * s)
    if skirt:
        mb.cyl(0.3 * s, 0.42 * s, loc=(0, 0, 0.28 * s), mat=T, verts=12, r2=0.17 * s)
    else:
        mb.cyl(0.22 * s, 0.45 * s, loc=(0, 0, 0.3 * s), mat=T, verts=12, r2=0.18 * s)
    mb.sphere(0.2 * s, loc=(0, 0, 0.72 * s), scale=(1.05, 0.85, 0.55), mat=T, subdiv=2)
    # arms
    for sx in (-1, 1):
        mb.cyl(0.06 * s, 0.38 * s, loc=(sx * 0.25 * s, 0, 0.36 * s), rot=(0, sx * -12, 0), mat=T, verts=7)
        mb.sphere(0.075 * s, loc=(sx * 0.29 * s, -0.02 * s, 0.34 * s), mat=skin, subdiv=1)
    # head
    hz = 1.1 * s
    mb.sphere(0.37 * s, loc=(0, 0, hz), scale=(1.0, 0.95, 0.95), mat=skin, subdiv=3)
    _eyes(mb, 0, -0.33 * s, hz - 0.02 * s, 0.13 * s, size=0.06 * s)
    # hair
    mb.sphere(0.4 * s, loc=(0, 0.04 * s, hz + 0.08 * s), scale=(1.03, 1.0, 0.85), mat=H, subdiv=3,
              flatten_bottom=0.1)
    mb.sphere(0.16 * s, loc=(-0.2 * s, -0.24 * s, hz + 0.22 * s), scale=(1.4, 0.6, 0.7), mat=H, subdiv=2)
    mb.sphere(0.14 * s, loc=(0.18 * s, -0.26 * s, hz + 0.2 * s), scale=(1.3, 0.6, 0.7), mat=H, subdiv=2)
    if long_hair:
        mb.sphere(0.3 * s, loc=(0, 0.2 * s, hz - 0.25 * s), scale=(1.1, 0.7, 1.3), mat=H, subdiv=2)
    if pigtails:
        for sx in (-1, 1):
            mb.sphere(0.13 * s, loc=(sx * 0.38 * s, 0.05 * s, hz + 0.22 * s), scale=(0.8, 0.8, 1.3), mat=H, subdiv=2)
            mb.sphere(0.05 * s, loc=(sx * 0.34 * s, 0.0, hz + 0.33 * s), mat="M_Flat_cloth_red", subdiv=1)
    _hat(mb, hat, s, hz, hat_color, H)
    for ex in ([extra] if extra else []) + list(extras):
        _accessory(mb, ex, s, hz)


def _hat(mb, hat, s, hz, hat_color, H):
    C = f"M_Flat_{hat_color}"
    if hat == "cap":
        mb.dome(0.4 * s, 0.28 * s, loc=(0, 0.02 * s, hz + 0.2 * s), mat=C, u=16, v=4)
        mb.box((0.4 * s, 0.3 * s, 0.05 * s), loc=(0, -0.38 * s, hz + 0.2 * s), mat=C)
    elif hat == "cap_back":
        mb.dome(0.4 * s, 0.26 * s, loc=(0, 0.0, hz + 0.2 * s), mat=C, u=16, v=4)
        mb.box((0.36 * s, 0.28 * s, 0.05 * s), loc=(0, 0.4 * s, hz + 0.2 * s), mat="M_Flat_cloth_red")
    elif hat == "wizard":
        mb.cyl(0.5 * s, 0.06 * s, loc=(0, 0, hz + 0.28 * s), mat=C, verts=16)
        mb.cyl(0.33 * s, 0.75 * s, loc=(0, 0, hz + 0.3 * s), rot=(-10, 0, 0), mat=C, verts=12, r2=0.02 * s)
    elif hat == "captain":
        mb.cyl(0.42 * s, 0.22 * s, loc=(0, 0, hz + 0.26 * s), mat=C, verts=16, r2=0.36 * s)
        mb.cyl(0.55 * s, 0.05 * s, loc=(0, 0, hz + 0.26 * s), mat=C, verts=16)
        mb.sphere(0.07 * s, loc=(0, -0.38 * s, hz + 0.38 * s), mat="M_Gold", subdiv=1)
    elif hat == "feather":
        mb.cyl(0.62 * s, 0.05 * s, loc=(0, 0, hz + 0.27 * s), mat=C, verts=18)
        mb.dome(0.36 * s, 0.3 * s, loc=(0, 0, hz + 0.3 * s), mat=C, u=16, v=4)
        mb.sphere(0.12 * s, loc=(0.3 * s, 0.1 * s, hz + 0.55 * s), scale=(0.6, 1.0, 2.2), rot=(0, 30, 0),
                  mat="M_Flat_cloth_white", subdiv=2)
    elif hat == "sailor":
        mb.cyl(0.33 * s, 0.16 * s, loc=(0, 0, hz + 0.27 * s), mat="M_Flat_cloth_white", verts=16, r2=0.36 * s)
        mb.cyl(0.335 * s, 0.05 * s, loc=(0, 0, hz + 0.28 * s), mat=C, verts=16)
    elif hat == "newsboy":
        mb.sphere(0.43 * s, loc=(0, 0.0, hz + 0.24 * s), scale=(1.0, 1.0, 0.45), mat="M_Flat_cloth_white", subdiv=2)
        mb.box((0.36 * s, 0.22 * s, 0.04 * s), loc=(0, -0.38 * s, hz + 0.2 * s), mat="M_Flat_cloth_white")
        mb.box((0.12 * s, 0.02 * s, 0.1 * s), loc=(0, -0.42 * s, hz + 0.3 * s), mat="M_Flat_roof_blue")
    elif hat == "bandana":
        mb.sphere(0.41 * s, loc=(0, 0.04 * s, hz + 0.12 * s), scale=(1.02, 1.0, 0.7), mat=C, subdiv=2,
                  flatten_bottom=0.2)
    elif hat == "bun":
        mb.sphere(0.17 * s, loc=(0, 0.1 * s, hz + 0.45 * s), mat=H, subdiv=2)
    elif hat == "bunny":
        for sx in (-1, 1):
            mb.sphere(0.07 * s, loc=(sx * 0.13 * s, 0.05 * s, hz + 0.62 * s), scale=(0.8, 0.5, 2.6),
                      mat="M_Flat_flower_pink", subdiv=2, rot=(0, sx * 12, 0))
    elif hat == "headband":
        mb.torus(0.37 * s, 0.035 * s, loc=(0, 0.02 * s, hz + 0.16 * s), rot=(12, 0, 0), mat=C, u=20, v=4)
    elif hat == "tiara":
        mb.torus(0.2 * s, 0.025 * s, loc=(0, -0.06 * s, hz + 0.36 * s), rot=(25, 0, 0), mat="M_Metal", u=14, v=4)


def _accessory(mb, ex, s, hz):
    """Extra props for NPC proxies (small, but they make NPCs identifiable)."""
    if ex == "apron":
        mb.box((0.34 * s, 0.05 * s, 0.42 * s), loc=(0, -0.2 * s, 0.42 * s), mat="M_Flat_roof_blue", bevel=0.02)
    elif ex == "beard":
        mb.sphere(0.22 * s, loc=(0, -0.26 * s, hz - 0.28 * s), scale=(1.1, 0.7, 1.0), mat="M_Flat_hair_blonde",
                  subdiv=2)
    elif ex == "staff":
        mb.cyl(0.04 * s, 1.5 * s, loc=(0.36 * s, -0.05 * s, 0.0), mat="M_Wood", verts=6)
        mb.sphere(0.1 * s, loc=(0.36 * s, -0.05 * s, 1.52 * s), mat="M_Glow_portal_core", subdiv=1)
    elif ex == "sword":
        mb.box((0.06 * s, 0.04 * s, 0.7 * s), loc=(0.33 * s, -0.1 * s, 0.6 * s), rot=(0, 15, 0), mat="M_Metal")
        mb.box((0.22 * s, 0.05 * s, 0.05 * s), loc=(0.28 * s, -0.1 * s, 0.26 * s), mat="M_Gold")
    elif ex == "glasses":
        for sx in (-1, 1):
            mb.torus(0.07 * s, 0.015 * s, loc=(sx * 0.13 * s, -0.36 * s, hz - 0.02 * s), rot=(90, 0, 0),
                     mat="M_Gold", u=10, v=3)
    elif ex == "toolbox":
        mb.box((0.3 * s, 0.14 * s, 0.2 * s), loc=(0.36 * s, -0.05 * s, 0.22 * s), mat="M_Flat_roof_orange", bevel=0.02)
        mb.box((0.06 * s, 0.04 * s, 0.38 * s), loc=(-0.34 * s, -0.08 * s, 0.4 * s), mat="M_Metal")
    elif ex == "sunglasses":
        mb.box((0.36 * s, 0.05 * s, 0.09 * s), loc=(0, -0.36 * s, hz - 0.02 * s), mat="M_Eye_Black", bevel=0.02)
    elif ex == "cane":
        mb.cyl(0.035 * s, 1.15 * s, loc=(0.34 * s, -0.08 * s, 0.0), mat="M_Wood", verts=6)
        mb.torus(0.07 * s, 0.03 * s, loc=(0.34 * s, -0.08 * s, 1.18 * s), rot=(90, 0, 0), mat="M_Wood", u=8, v=4)
    elif ex == "broadsword":
        mb.box((0.14 * s, 0.03 * s, 0.85 * s), loc=(0.36 * s, -0.12 * s, 0.55 * s), rot=(0, -8, 0), mat="M_Metal")
        mb.box((0.3 * s, 0.06 * s, 0.06 * s), loc=(0.36 * s, -0.12 * s, 0.98 * s), mat="M_Gold")
    elif ex == "rope_coil":
        mb.torus(0.2 * s, 0.05 * s, loc=(-0.22 * s, 0.0, 0.62 * s), rot=(70, 0, 20), mat="M_Rope", u=12, v=4)
    elif ex == "balloons":
        for k, (dx, c) in enumerate(((-0.2, "flower_yellow"), (0.05, "flower_pink"), (0.28, "portal_core"))):
            mb.cyl(0.006 * s, 1.3 * s, loc=(0.3 * s, -0.05 * s, 0.4 * s), rot=(0, (k - 1) * 10, 0),
                   mat="M_Flat_cloth_white", verts=3)
            mb.sphere(0.17 * s, loc=(0.3 * s + dx * s, -0.05 * s, 1.85 * s + k * 0.08 * s), scale=(1, 1, 1.15),
                      mat=f"M_Flat_{c}", subdiv=2)
    elif ex == "skateboard":
        mb.box((0.06 * s, 0.22 * s, 0.75 * s), loc=(0.36 * s, 0.0, 0.42 * s), mat="M_Flat_wood_lt", bevel=0.03)
    elif ex == "briefcase":
        mb.box((0.3 * s, 0.1 * s, 0.24 * s), loc=(0.34 * s, -0.04 * s, 0.22 * s), mat="M_Eye_Black", bevel=0.02)
    elif ex == "laundry":
        mb.box((0.34 * s, 0.04 * s, 0.26 * s), loc=(0.0, -0.3 * s, 0.6 * s), mat="M_Cloth_White", bevel=0.01)
    elif ex == "gold_trim":
        mb.torus(0.21 * s, 0.03 * s, loc=(0, 0, 0.62 * s), mat="M_Gold", u=14, v=4)
    elif ex == "stole":
        mb.box((0.12 * s, 0.05 * s, 0.5 * s), loc=(-0.12 * s, -0.19 * s, 0.55 * s), rot=(0, 10, 0),
               mat="M_Flat_roof_purple")


@asset("Player_Proxy", "Characters", footprint=0.8, tags=("character",))
def player_proxy(coll):
    mb = MeshBuilder()
    chibi(mb, hair="hair_brown", top="player_blue", bottom="wood_dk", extra="sword")
    mb.build("Player_Proxy", coll, smooth=True, sharp_angle=50)


def register_npc(name, **spec):
    """Register an NPC proxy asset ``NPC_<name>`` with chibi parameters."""
    asset_name = f"NPC_{name}"
    if asset_name in REGISTRY:
        return asset_name

    def build(coll, _spec=spec, _n=asset_name):
        mb = MeshBuilder()
        chibi(mb, **_spec)
        mb.build(_n, coll, smooth=True, sharp_angle=50)

    REGISTRY[asset_name] = {"fn": build, "category": "Characters", "footprint": 0.8, "tags": ("npc",),
                            "outline": None}
    return asset_name


# ---------------------------------------------------------------------------
# Monsters (modeled from the classic sprites)
# ---------------------------------------------------------------------------

def _tube(mb, pts, radius, mat, sides=6):
    """Sweep a small tube along a polyline of Vectors."""
    from mathutils import Vector
    bm = mb.bm
    mi = mb.mat(mat)
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        n1 = t.cross(a).normalized()
        n2 = t.cross(n1).normalized()
        rad = radius * (0.35 + 0.65 * (1 - i / max(1, len(pts) - 1)))
        ring = []
        for k in range(sides):
            ang = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + (n1 * math.cos(ang) + n2 * math.sin(ang)) * rad))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
            f.material_index = mi


def _spiral_shell(mb, loc, r, base, dark, light=None):
    """Round shell with a two-turn spiral groove on each side (classic snail shells)."""
    from mathutils import Vector
    x, y, z = loc
    sx = 0.8
    mb.sphere(r, loc=loc, scale=(sx, 1.0, 1.0), mat=f"M_Flat_{base}", subdiv=3)
    for side in (-1, 1):
        pts = []
        n = 40
        for i in range(n):
            th = 4.2 * math.pi * i / n
            rho = r * 0.86 * (1 - i / (n * 1.08))
            yy = math.cos(th) * rho
            zz = math.sin(th) * rho
            q = max(0.0, 1 - (rho / r) ** 2)
            xx = side * (sx * r * math.sqrt(q) + r * 0.02)
            pts.append(Vector((x + xx, y + yy, z + zz)))
        _tube(mb, pts, r * 0.085, f"M_Flat_{dark}")
    if light:
        mb.sphere(r * 0.22, loc=(x - r * 0.35, y - r * 0.45, z + r * 0.55), scale=(1, 0.6, 0.6),
                  mat=f"M_Flat_{light}", subdiv=1)


@asset("Mob_Snail", "Monsters", footprint=1.0, tags=("mob",))
def mob_snail(coll):
    """Snail (100100): low pale-lavender slug, single sleepy eye on a raised head, teal shell."""
    mb = MeshBuilder()
    mb.sphere(0.2, loc=(0, -0.05, 0.1), scale=(0.85, 2.0, 0.55), mat="M_Grad_snail_slug_dk__snail_slug", subdiv=2,
              flatten_bottom=0.5)
    mb.cyl(0.08, 0.24, loc=(0, -0.36, 0.1), rot=(-18, 0, 0), mat="M_Flat_snail_slug", verts=10, r2=0.07)
    mb.sphere(0.12, loc=(0, -0.42, 0.36), mat="M_Flat_snail_slug", subdiv=2)
    mb.box((0.1, 0.03, 0.025), loc=(0, -0.53, 0.37), mat="M_Eye_Black")
    mb.build("Mob_Snail_Body", coll, smooth=True, sharp_angle=60)
    sh = MeshBuilder()
    _spiral_shell(sh, (0, 0.1, 0.33), 0.23, "snail_teal", "snail_teal_dk", "snail_teal_lt")
    sh.build("Mob_Snail_Shell", coll, smooth=True, sharp_angle=60)
    _rescale(coll, "Mob_Snail")


def _blob_snail(coll, name, shell, shell_dk):
    """Blue/Red Snail (100101/130101): cream dumpling body, two lidded eyes on top, colored shell."""
    mb = MeshBuilder()
    mb.cyl(0.25, 0.3, loc=(0, -0.08, 0.0), mat="M_Grad_blob_cream_dk__blob_cream", verts=16, r2=0.16)
    mb.sphere(0.25, loc=(0, -0.08, 0.06), scale=(1.0, 1.0, 0.45), mat="M_Flat_blob_cream", subdiv=2,
              flatten_bottom=0.2)
    mb.sphere(0.17, loc=(0, -0.1, 0.3), mat="M_Flat_blob_cream", subdiv=2)
    for sx in (-1, 1):
        mb.sphere(0.085, loc=(sx * 0.08, -0.2, 0.44), mat="M_Eye_White", subdiv=2)
        mb.sphere(0.035, loc=(sx * 0.08, -0.27, 0.43), mat="M_Eye_Black", subdiv=1)
        mb.sphere(0.09, loc=(sx * 0.08, -0.2, 0.47), scale=(1.05, 1.05, 0.6), mat="M_Flat_lid_tan", subdiv=2)
    mb.box((0.08, 0.02, 0.015), loc=(0, -0.3, 0.2), mat="M_Eye_Black")
    mb.build(name + "_Body", coll, smooth=True, sharp_angle=60)
    sh = MeshBuilder()
    _spiral_shell(sh, (0, 0.17, 0.32), 0.25, shell, shell_dk)
    sh.build(name + "_Shell", coll, smooth=True, sharp_angle=60)
    _rescale(coll, name)


@asset("Mob_BlueSnail", "Monsters", footprint=1.05, tags=("mob",))
def mob_blue_snail(coll):
    """Blue Snail (100101): cream dumpling body with two lidded eyes on top and a blue spiral shell."""
    _blob_snail(coll, "Mob_BlueSnail", "bsnail_shell", "bsnail_shell_dk")


@asset("Mob_RedSnail", "Monsters", footprint=1.05, tags=("mob",))
def mob_red_snail(coll):
    """Red Snail (130101): the Blue Snail sprite with a crimson shell."""
    _blob_snail(coll, "Mob_RedSnail", "rsnail_shell", "rsnail_shell_dk")


@asset("Mob_Shroom", "Monsters", footprint=0.8, tags=("mob",))
def mob_shroom(coll):
    """Shroom (120100): red-orange spotted cap over a tan face-stem with an angry, lopsided face."""
    mb = MeshBuilder()
    mb.sphere(0.2, loc=(0, 0, 0.04), scale=(1.1, 1.0, 0.3), mat="M_Flat_bark_dk", subdiv=1)
    mb.cyl(0.18, 0.36, loc=(0, 0, 0.04), mat="M_Flat_shroom_stem", verts=14, r2=0.16)
    mb.sphere(0.075, loc=(0.07, -0.17, 0.25), mat="M_Eye_White", subdiv=2)
    mb.sphere(0.035, loc=(0.06, -0.23, 0.25), mat="M_Eye_Black", subdiv=1)
    mb.box((0.09, 0.02, 0.02), loc=(-0.08, -0.18, 0.25), rot=(0, -10, 0), mat="M_Eye_Black")
    mb.box((0.1, 0.02, 0.02), loc=(-0.08, -0.18, 0.31), rot=(0, 25, 0), mat="M_Eye_Black")
    mb.sphere(0.03, loc=(0.0, -0.18, 0.15), scale=(1.3, 0.5, 1.0), mat="M_Flat_mouth_red", subdiv=1)
    mb.build("Mob_Shroom_Body", coll, smooth=True, sharp_angle=60)
    cap = MeshBuilder()
    cap.dome(0.37, 0.32, loc=(0, 0, 0.36), mat="M_Spot_shroom_cap__shroom_spot", u=18, v=5, lip=0.06, profile=0.7)
    cap.build("Mob_Shroom_Cap", coll, smooth=True, sharp_angle=70)
    _rescale(coll, "Mob_Shroom")


@asset("Mob_OrangeMushroom", "Monsters", footprint=1.4, tags=("mob",))
def mob_orange_mushroom(coll):
    """Orange Mushroom (1210102): white dumpling body with a cute face, tilted orange cap with yellow spots."""
    mb = MeshBuilder()
    mb.sphere(0.42, loc=(0, 0, 0.32), scale=(1.0, 0.95, 0.78), mat="M_Flat_om_body", subdiv=3, flatten_bottom=0.55)
    for sx in (-1, 1):
        mb.sphere(0.05, loc=(sx * 0.13, -0.38, 0.38), scale=(0.8, 0.5, 1.2), mat="M_Eye_Black", subdiv=1)
        mb.sphere(0.06, loc=(sx * 0.22, -0.35, 0.28), scale=(1.2, 0.4, 0.7), mat="M_Flat_cheek_pink", subdiv=1)
    mb.torus(0.04, 0.012, loc=(0, -0.39, 0.27), rot=(90, 0, 0), mat="M_Eye_Black", u=10, v=3)
    mb.build("Mob_OrangeMushroom_Body", coll, smooth=True, sharp_angle=60)
    cap = MeshBuilder()
    cap.cyl(0.5, 0.06, loc=(0, 0, 0.6), rot=(0, 8, 0), mat="M_Flat_om_gill", verts=20)
    cap.dome(0.62, 0.48, loc=(0.03, 0, 0.62), rot=(0, 8, 0), mat="M_Spot_om_cap__om_spot", u=22, v=6, lip=0.08,
             profile=0.68)
    cap.build("Mob_OrangeMushroom_Cap", coll, smooth=True, sharp_angle=70)
    _rescale(coll, "Mob_OrangeMushroom")


MOB_ASSETS = {
    # canonical classic Maple Island mobs (GMS v8): Snail, Blue Snail, Shroom, Red Snail, Orange Mushroom
    "Snail": "Mob_Snail",
    "Blue Snail": "Mob_BlueSnail",
    "Red Snail": "Mob_RedSnail",
    "Shroom": "Mob_Shroom",
    "Spore": "Mob_Shroom",
    "Orange Mushroom": "Mob_OrangeMushroom",
}
