"""Props: crates, barrels, lamps, shop furniture, farm and harbor details."""

import math

from mathutils import Vector

from .. import core
from ..geo import MeshBuilder
from . import asset
from .art_pack import kit_materials

# Built from the pinned art pack (kit/art_pack.py, docs/AUTHORING.md section 9); pack= are the per-asset exceptions.
# The pack's lamp glass goes back into the kit's glowing window material (the pack has no emission).
LAMP_GLOW = dict(parts={"Glow": ["Amber lamp glass"]}, post=kit_materials(Glow="M_Glow_window"))


@asset("Crate", "Props", footprint=1.0, tags=("prop",))
def crate(coll):
    mb = MeshBuilder()
    mb.box((0.9, 0.9, 0.9), loc=(0, 0, 0.45), mat="M_Plank", bevel=0.05, segs=1)
    for s in (-1, 1):
        mb.box((0.95, 0.96, 0.12), loc=(0, 0, 0.45 + s * 0.36), mat="M_Wood_Dark", bevel=0.02, segs=1)
    mb.box((0.12, 0.96, 0.95), loc=(0, 0, 0.45), rot=(0, 45, 0), mat="M_Wood_Dark")
    mb.build("Crate", coll, smooth=False)


# pack: the kit stack starts at its origin crate and runs along +X; the pack stack is centred
@asset("Crate_Stack", "Props", footprint=1.8, tags=("prop",), pack=dict(align_xy="kit"))
def crate_stack(coll):
    mb = MeshBuilder()
    for (x, y, z, r) in ((0, 0, 0, 0), (0.95, 0.1, 0, 8), (0.45, 0.05, 0.9, -12)):
        mb.box((0.9, 0.9, 0.9), loc=(x, y, z + 0.45), rot=(0, 0, r), mat="M_Plank", bevel=0.05, segs=1)
        mb.box((0.95, 0.95, 0.12), loc=(x, y, z + 0.82), rot=(0, 0, r), mat="M_Wood_Dark", bevel=0.02, segs=1)
    mb.build("Crate_Stack", coll, smooth=False)


@asset("Barrel", "Props", footprint=0.9, tags=("prop",))
def barrel(coll):
    mb = MeshBuilder()
    mb.cyl(0.36, 0.5, loc=(0, 0, 0), mat="M_Wood", verts=14, r2=0.44)
    mb.cyl(0.44, 0.5, loc=(0, 0, 0.5), mat="M_Wood", verts=14, r2=0.36)
    for z in (0.15, 0.5, 0.85):
        mb.cyl(0.45 - abs(z - 0.5) * 0.2, 0.07, loc=(0, 0, z - 0.035), mat="M_Metal", verts=14)
    mb.cyl(0.34, 0.04, loc=(0, 0, 0.99), mat="M_Wood_Dark", verts=14)
    mb.build("Barrel", coll, smooth=True, sharp_angle=40)


@asset("Sack", "Props", footprint=0.7, tags=("prop",))
def sack(coll):
    mb = MeshBuilder()
    mb.sphere(0.35, loc=(0, 0, 0.3), scale=(1, 0.9, 1.0), mat="M_Flat_wood_lt", subdiv=2, lumpy=0.1, seed=3,
              flatten_bottom=0.6)
    mb.cyl(0.12, 0.25, loc=(0, 0, 0.6), mat="M_Flat_wood_lt", verts=8, r2=0.18)
    mb.torus(0.12, 0.03, loc=(0, 0, 0.62), mat="M_Rope", u=10, v=4)
    mb.build("Sack", coll, smooth=True)


# pack: a slim centred post; fitting the kit lamp's arm width made it 4.4 m tall, so it fits the kit height
@asset("Lamp_Post", "Props", footprint=0.6, tags=("prop", "light"), pack=dict(LAMP_GLOW, fit="z"))
def lamp_post(coll):
    mb = MeshBuilder()
    mb.cyl(0.25, 0.3, mat="M_StoneWall", verts=8, r2=0.2)
    mb.cyl(0.09, 2.8, loc=(0, 0, 0.3), mat="M_Wood_Dark", verts=8)
    mb.box((0.7, 0.08, 0.08), loc=(0.25, 0, 3.0), mat="M_Wood_Dark")
    mb.box((0.36, 0.36, 0.48), loc=(0.55, 0, 2.66), mat="M_Glow_window", bevel=0.04, segs=1)
    mb.cyl(0.3, 0.22, loc=(0.55, 0, 2.9), mat="M_Wood_Dark", verts=4, r2=0.05, rot=(0, 0, 45))
    mb.build("Lamp_Post", coll, smooth=False)


@asset("Mailbox_Red", "Props", footprint=0.6, tags=("prop",))
def mailbox(coll):
    """Red postbox (a recognizable Amherst detail)."""
    mb = MeshBuilder()
    mb.box((0.5, 0.45, 0.9), loc=(0, 0, 0.45), mat="M_Flat_roof_red", bevel=0.08)
    mb.cyl(0.25, 0.45, loc=(0, 0.225, 0.9), rot=(90, 0, 0), mat="M_Flat_roof_red", verts=14)
    mb.box((0.3, 0.06, 0.06), loc=(0, -0.24, 0.7), mat="M_Eye_Black")
    mb.box((0.56, 0.5, 0.1), loc=(0, 0, 0.05), mat="M_Wood_Dark")
    mb.build("Mailbox_Red", coll, smooth=True, sharp_angle=40)


@asset("Bench", "Props", footprint=1.8, tags=("prop",))
def bench(coll):
    mb = MeshBuilder()
    for x in (-0.7, 0.7):
        mb.box((0.12, 0.45, 0.45), loc=(x, 0, 0.22), mat="M_Wood_Dark")
    mb.box((1.8, 0.5, 0.1), loc=(0, 0, 0.48), mat="M_Plank", bevel=0.03, segs=1)
    mb.box((1.8, 0.08, 0.35), loc=(0, 0.24, 0.78), mat="M_Plank", bevel=0.03, segs=1)
    mb.build("Bench", coll, smooth=False)


@asset("Well", "Props", footprint=2.2, tags=("prop", "landmark"))
def well(coll):
    mb = MeshBuilder()
    mb.cyl(1.0, 0.9, mat="M_StoneWall", verts=16)
    mb.cyl(0.8, 0.05, loc=(0, 0, 0.75), mat="M_Water", verts=16)
    for x in (-0.85, 0.85):
        mb.box((0.15, 0.15, 1.6), loc=(x, 0, 1.6), mat="M_Wood_Dark")
    mb.box((2.3, 0.9, 0.12), loc=(0, -0.35, 2.55), rot=(30, 0, 0), mat="M_Flat_roof_red", bevel=0.04, segs=1)
    mb.box((2.3, 0.9, 0.12), loc=(0, 0.35, 2.55), rot=(-30, 0, 0), mat="M_Flat_roof_red", bevel=0.04, segs=1)
    mb.cyl(0.08, 1.7, loc=(-0.85, 0, 2.0), rot=(0, 90, 0), mat="M_Wood", verts=6)
    mb.cyl(0.18, 0.3, loc=(0.1, 0, 1.3), mat="M_Wood", verts=8)
    mb.build("Well", coll, smooth=False)


# pack: the cart runs along Y with its handles at -Y; the kit cart's shafts point to +X. Decimated to the kit's 216
# triangles its wheels went octagonal; 3 placed, so it keeps more
@asset("Cart", "Props", footprint=2.5, tags=("prop",), pack=dict(rot_z=90, max_tris=700))
def cart(coll):
    mb = MeshBuilder()
    mb.box((2.0, 1.2, 0.5), loc=(0, 0, 0.85), mat="M_Plank", bevel=0.04, segs=1)
    for s in (-1, 1):
        mb.cyl(0.5, 0.12, loc=(0, s * 0.7, 0.5), rot=(90, 0, 0), mat="M_Wood_Dark", verts=12)
    mb.box((1.6, 0.08, 0.08), loc=(1.6, 0.35, 0.8), rot=(0, 10, 0), mat="M_Wood")
    mb.box((1.6, 0.08, 0.08), loc=(1.6, -0.35, 0.8), rot=(0, 10, 0), mat="M_Wood")
    mb.sphere(0.3, loc=(-0.4, 0.2, 1.2), mat="M_Tomato", subdiv=1)
    mb.sphere(0.28, loc=(0.2, -0.2, 1.18), mat="M_Tomato", subdiv=1)
    mb.sphere(0.32, loc=(0.4, 0.25, 1.2), mat="M_Flat_wood_lt", subdiv=1)
    mb.build("Cart", coll, smooth=True, sharp_angle=40)


# pack: the kit haystack's width is the loose straw at its foot (2.8 m), its body 1.9 m; the solid pack stack fitted to
# the straw blocked route EastYard in Tomato Field, so 0.7 gives the kit body (2 m across, 1.5 m tall)
@asset("Haystack", "Props", footprint=1.6, tags=("prop", "farm"), pack=dict(scale_mul=0.7))
def haystack(coll):
    """Tapered straw stack with binding bands, a ragged top tuft and loose straw at the foot."""
    r = core.rng("hay", 1)
    mb = MeshBuilder()
    mb.cyl(0.95, 0.9, mat="M_Grad_mush_stem_dk__roof_yellow", verts=16, r2=0.82)
    mb.dome(0.83, 0.85, loc=(0, 0, 0.88), mat="M_Grad_mush_stem_dk__roof_yellow", u=16, v=5, profile=0.75,
            underside=False)
    for z, rr in ((0.35, 0.93), (0.8, 0.85)):
        mb.torus(rr, 0.035, loc=(0, 0, z), mat="M_Rope", u=18, v=4)
    for k in range(9):
        a = 2 * math.pi * k / 9 + r.uniform(-0.2, 0.2)
        mb.cyl(0.03, 0.42, loc=(math.cos(a) * 0.12, math.sin(a) * 0.12, 1.62), rot=(r.uniform(-30, 30), r.uniform(-30, 30), 0),
               mat="M_Flat_roof_yellow", verts=3, r2=0.0)
    for k in range(10):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(1.0, 1.4)
        mb.box((0.5, 0.025, 0.025), loc=(math.cos(a) * d, math.sin(a) * d, 0.02), rot=(0, 0, r.uniform(0, 180)),
               mat="M_Flat_roof_yellow")
    mb.build("Haystack", coll, smooth=True, sharp_angle=50)


@asset("Scarecrow", "Props", footprint=1.0, tags=("prop", "farm"))
def scarecrow(coll):
    mb = MeshBuilder()
    mb.box((0.12, 0.12, 2.2), loc=(0, 0, 1.1), mat="M_Wood")
    mb.box((1.6, 0.1, 0.1), loc=(0, 0, 1.65), mat="M_Wood")
    mb.box((0.7, 0.35, 0.8), loc=(0, 0, 1.45), mat="M_Flat_roof_blue", bevel=0.08)
    mb.sphere(0.32, loc=(0, 0, 2.15), mat="M_Flat_wood_lt", subdiv=2)
    mb.dome(0.48, 0.35, loc=(0, 0, 2.3), mat="M_Flat_roof_yellow", u=12, v=3)
    mb.build("Scarecrow", coll, smooth=True, sharp_angle=40)


@asset("Tomato_Plant", "Props", footprint=0.8, tags=("prop", "farm"))
def tomato_plant(coll):
    r = core.rng("tp", 1)
    mb = MeshBuilder()
    mb.box((0.06, 0.06, 1.4), loc=(0, 0, 0.7), mat="M_Wood")
    for k in range(5):
        a = r.uniform(0, 2 * math.pi)
        z = 0.3 + k * 0.22
        mb.sphere(0.22, loc=(math.cos(a) * 0.14, math.sin(a) * 0.14, z), scale=(1.2, 1.2, 0.8), mat="M_Bush", subdiv=1,
                  lumpy=0.2, seed=k)
    for k in range(4):
        a = r.uniform(0, 2 * math.pi)
        mb.sphere(0.13, loc=(math.cos(a) * 0.24, math.sin(a) * 0.24, 0.35 + k * 0.22), mat="M_Tomato", subdiv=2)
    mb.build("Tomato_Plant", coll, smooth=True, sharp_angle=50)


@asset("Tomato_Giant", "Props", footprint=1.6, tags=("prop", "farm", "landmark"))
def tomato_giant(coll):
    mb = MeshBuilder()
    mb.sphere(0.85, loc=(0, 0, 0.75), scale=(1.1, 1.1, 0.88), mat="M_Tomato", subdiv=3, lumpy=0.05, seed=2)
    for k in range(6):
        a = 2 * math.pi * k / 6
        mb.box((0.5, 0.12, 0.04), loc=(math.cos(a) * 0.22, math.sin(a) * 0.22, 1.5), rot=(0, -12, math.degrees(a)),
               mat="M_Flat_tomato_leaf")
    mb.cyl(0.06, 0.3, loc=(0, 0, 1.45), mat="M_Flat_tomato_leaf", verts=6)
    mb.build("Tomato_Giant", coll, smooth=True, sharp_angle=60)


# pack: a narrow, tall stall; fitting the kit stall's 3.2 m width made it 3.9 m tall, so it fits the kit height
@asset("Market_Stall", "Props", footprint=3.0, tags=("prop", "town"), pack=dict(fit="z"))
def market_stall(coll):
    mb = MeshBuilder()
    mb.box((2.6, 1.2, 0.9), loc=(0, 0, 0.45), mat="M_Plank", bevel=0.05, segs=1)
    for x in (-1.25, 1.25):
        for y in (-0.55, 0.55):
            mb.box((0.12, 0.12, 2.4), loc=(x, y, 1.2), mat="M_Wood_Dark")
    for i in range(6):
        x = -1.35 + i * 0.54 + 0.27
        mat = "M_Flat_roof_red" if i % 2 else "M_Cloth_White"
        mb.box((0.54, 1.7, 0.08), loc=(x, -0.15, 2.45), rot=(-12, 0, 0), mat=mat)
    for k, m in enumerate(("M_Tomato", "M_Flat_flower_yellow", "M_Flat_roof_green", "M_Flat_roof_orange")):
        mb.sphere(0.18, loc=(-0.9 + k * 0.6, -0.2, 1.05), mat=m, subdiv=1)
    mb.build("Market_Stall", coll, smooth=True, sharp_angle=40)


# pack (noticeboard.glb, shared with Sign_Board): a wide gabled board, only 1.3 m tall at the kit width; x1.2
@asset("Signpost_Notice", "Props", footprint=1.0, tags=("prop",), pack=dict(scale_mul=1.2))
def notice(coll):
    mb = MeshBuilder()
    mb.box((0.15, 0.15, 1.6), loc=(0, 0, 0.8), mat="M_Wood")
    mb.box((1.1, 0.1, 0.8), loc=(0, -0.08, 1.4), mat="M_Plank", bevel=0.04, segs=1)
    for k in range(3):
        mb.box((0.3, 0.02, 0.36), loc=(-0.32 + k * 0.32, -0.14, 1.42), rot=(0, (k - 1) * 6, 0),
               mat="M_Cloth_White")
    mb.build("Signpost_Notice", coll, smooth=False)


@asset("Anchor", "Props", footprint=1.2, tags=("prop", "port"))
def anchor(coll):
    mb = MeshBuilder()
    mb.box((0.18, 0.18, 1.6), loc=(0, 0, 0.9), mat="M_Metal")
    mb.torus(0.18, 0.06, loc=(0, 0, 1.8), rot=(90, 0, 0), mat="M_Metal", u=10, v=4)
    mb.box((0.9, 0.16, 0.16), loc=(0, 0, 1.45), mat="M_Metal")
    for s in (-1, 1):
        mb.box((0.7, 0.16, 0.18), loc=(s * 0.3, 0, 0.25), rot=(0, s * 35, 0), mat="M_Metal")
    mb.build("Anchor", coll, smooth=False)


@asset("Rope_Coil", "Props", footprint=0.7, tags=("prop", "port"))
def rope_coil(coll):
    mb = MeshBuilder()
    for k in range(4):
        mb.torus(0.3 - k * 0.02, 0.06, loc=(0, 0, 0.06 + k * 0.1), mat="M_Rope", u=14, v=5)
    mb.build("Rope_Coil", coll, smooth=True)


@asset("Lifebuoy", "Props", footprint=0.6, tags=("prop", "port"))
def lifebuoy(coll):
    mb = MeshBuilder()
    mb.torus(0.4, 0.12, loc=(0, 0, 0.55), rot=(90, 0, 0), mat="M_Cloth_Red", u=16, v=6)
    mb.box((0.1, 0.1, 1.0), loc=(0, 0.15, 0.5), mat="M_Wood_Dark")
    mb.build("Lifebuoy", coll, smooth=True, sharp_angle=50)


# pack (chest.glb): decimated to the kit's 124 triangles its lid collapsed into a lump; 3 placed, so it keeps them all
@asset("Treasure_Chest", "Props", footprint=1.0, tags=("prop",), pack=dict(max_tris=560))
def chest(coll):
    mb = MeshBuilder()
    mb.box((1.0, 0.65, 0.55), loc=(0, 0, 0.28), mat="M_Wood", bevel=0.05, segs=1)
    mb.cyl(0.33, 1.0, loc=(-0.5, 0, 0.55), rot=(0, 90, 0), mat="M_Wood", verts=12)
    for x in (-0.38, 0.38):
        mb.box((0.1, 0.7, 0.9), loc=(x, 0, 0.45), mat="M_Gold")
    mb.box((0.18, 0.1, 0.22), loc=(0, -0.34, 0.55), mat="M_Gold")
    mb.build("Treasure_Chest", coll, smooth=True, sharp_angle=40)


@asset("Fountain_Small", "Props", footprint=3.0, tags=("prop", "landmark", "town"))
def fountain(coll):
    mb = MeshBuilder()
    mb.cyl(1.6, 0.6, mat="M_StoneWall", verts=20)
    mb.cyl(1.35, 0.05, loc=(0, 0, 0.5), mat="M_Water", verts=20)
    mb.cyl(0.25, 1.4, loc=(0, 0, 0.5), mat="M_StoneWall", verts=10)
    mb.cyl(0.7, 0.25, loc=(0, 0, 1.6), mat="M_StoneWall", verts=14, r2=0.5)
    mb.sphere(0.35, loc=(0, 0, 2.05), scale=(1, 1, 1.4), mat="M_Water", subdiv=2)
    mb.build("Fountain_Small", coll, smooth=True, sharp_angle=40)


@asset("Maple_Leaf_Monument", "Props", footprint=2.0, tags=("prop", "landmark"))
def maple_monument(coll):
    """Stone plinth with a big maple leaf - island emblem / map-name marker."""
    mb = MeshBuilder()
    mb.box((1.6, 1.0, 0.9), loc=(0, 0, 0.45), mat="M_StoneWall", bevel=0.12)
    leaf = []
    for i in range(11):
        a = math.pi / 2 + 2 * math.pi * i / 11
        rr = 1.0 if i % 2 == 0 else 0.55
        if i in (5, 6):
            rr *= 0.8
        leaf.append((math.cos(a) * rr, math.sin(a) * rr))
    mb.prism(leaf, -0.1, 0.1, loc=(0, 0, 2.0), rot=(90, 0, 0), mat="M_Flat_roof_orange", bevel=0.05, segs=2)
    mb.box((0.12, 0.12, 1.1), loc=(0, 0, 1.2), mat="M_Wood_Dark")
    mb.build("Maple_Leaf_Monument", coll, smooth=True, sharp_angle=40)


# ---------------------------------------------------------------------------
# Interior furniture (shops)
# ---------------------------------------------------------------------------

@asset("Shop_Counter", "Props", footprint=3.0, tags=("interior",))
def shop_counter(coll):
    mb = MeshBuilder()
    mb.box((3.0, 0.9, 1.05), loc=(0, 0, 0.52), mat="M_Wood", bevel=0.05, segs=1)
    mb.box((3.2, 1.05, 0.12), loc=(0, 0, 1.1), mat="M_Plank", bevel=0.03, segs=1)
    mb.box((2.6, 0.06, 0.5), loc=(0, -0.46, 0.55), mat="M_Wood_Dark")
    mb.build("Shop_Counter", coll, smooth=False)


@asset("Shelf_Goods", "Props", footprint=2.0, tags=("interior",))
def shelf_goods(coll):
    r = core.rng("shelf", 1)
    mb = MeshBuilder()
    mb.box((2.0, 0.5, 2.4), loc=(0, 0.1, 1.2), mat="M_Wood_Dark", bevel=0.03, segs=1)
    for k in range(4):
        z = 0.35 + k * 0.6
        mb.box((1.9, 0.5, 0.06), loc=(0, -0.05, z), mat="M_Plank")
        for j in range(5):
            m = r.choice(["M_Glow_roof_red", "M_Glow_roof_blue", "M_Flat_roof_yellow", "M_Flat_wood_lt", "M_Tomato"])
            mb.cyl(0.1, 0.24, loc=(-0.75 + j * 0.37, -0.1, z + 0.03), mat=m, verts=8)
    mb.build("Shelf_Goods", coll, smooth=False)


@asset("Weapon_Rack", "Props", footprint=2.0, tags=("interior",))
def weapon_rack(coll):
    mb = MeshBuilder()
    mb.box((2.0, 0.3, 0.12), loc=(0, 0.1, 0.35), mat="M_Wood_Dark")
    mb.box((2.0, 0.3, 0.12), loc=(0, 0.1, 1.7), mat="M_Wood_Dark")
    for x in (-0.95, 0.95):
        mb.box((0.12, 0.3, 1.9), loc=(x, 0.1, 0.95), mat="M_Wood_Dark")
    for k, x in enumerate((-0.6, -0.2, 0.2, 0.6)):
        mb.box((0.08, 0.04, 1.2), loc=(x, 0, 1.05), rot=(0, (k - 1.5) * 4, 0), mat="M_Metal")
        mb.box((0.3, 0.06, 0.06), loc=(x, -0.02, 0.48), mat="M_Gold")
    mb.build("Weapon_Rack", coll, smooth=False)


# pack: a mannequin with wide shoulder plates, 1.2 m tall at the kit width; fitted to 0.85 of the kit height instead
@asset("Armor_Stand", "Props", footprint=1.0, tags=("interior",), pack=dict(fit="z", scale_mul=0.85))
def armor_stand(coll):
    mb = MeshBuilder()
    mb.cyl(0.35, 0.1, mat="M_Wood_Dark", verts=10)
    mb.box((0.08, 0.08, 1.3), loc=(0, 0, 0.7), mat="M_Wood_Dark")
    mb.box((0.7, 0.42, 0.75), loc=(0, 0, 1.25), mat="M_Metal", bevel=0.12)
    mb.sphere(0.25, loc=(0, 0, 1.85), mat="M_Metal", subdiv=2)
    mb.cyl(0.3, 0.06, loc=(0.0, -0.35, 1.2), rot=(90, 0, 0), mat="M_Flat_roof_blue", verts=6)
    mb.build("Armor_Stand", coll, smooth=True, sharp_angle=40)


@asset("Rug_Round", "Props", footprint=3.0, tags=("interior",))
def rug(coll):
    mb = MeshBuilder()
    mb.cyl(1.5, 0.03, mat="M_Flat_roof_red", verts=24)
    mb.cyl(1.15, 0.035, mat="M_Flat_roof_yellow", verts=24)
    mb.build("Rug_Round", coll, smooth=False)


@asset("Table_Round", "Props", footprint=1.4, tags=("interior",))
def table_round(coll):
    mb = MeshBuilder()
    mb.cyl(0.65, 0.08, loc=(0, 0, 0.8), mat="M_Plank", verts=16)
    mb.cyl(0.08, 0.8, mat="M_Wood_Dark", verts=8)
    mb.cyl(0.35, 0.06, mat="M_Wood_Dark", verts=10)
    mb.build("Table_Round", coll, smooth=False)


# pack: the lantern stands on z = 0; the kit lantern hangs from its origin (the hook)
@asset("Hanging_Lantern", "Props", footprint=0.4, tags=("interior", "light"), pack=dict(LAMP_GLOW, anchor_z="kit_top"))
def hanging_lantern(coll):
    mb = MeshBuilder()
    mb.cyl(0.05, 0.62, loc=(0, 0, -0.62), mat="M_Metal", verts=6)
    mb.torus(0.07, 0.025, loc=(0, 0, 0.0), rot=(90, 0, 0), mat="M_Metal", u=8, v=4)
    mb.box((0.3, 0.3, 0.38), loc=(0, 0, -0.8), mat="M_Glow_window", bevel=0.04, segs=1)
    mb.cyl(0.24, 0.14, loc=(0, 0, -0.62), mat="M_Wood_Dark", verts=4, r2=0.04, rot=(0, 0, 45))
    mb.build("Hanging_Lantern", coll, smooth=False)
